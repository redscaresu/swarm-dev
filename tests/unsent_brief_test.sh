#!/usr/bin/env bash
# unsent_brief_test.sh — wait --lead's resend pass: an idle agent whose input box still holds the brief
# a start or tell typed there (a collapsed `[Pasted text #N` paste) gets one Enter, and one `resend
# <agent>` events.tsv line, per delivery; nothing else is ever submitted. A paste still there on the read
# after that Enter writes a .swarm/briefs/<stem>.unsent marker, which wakes the lead with an `unsent brief:`
# line until its agent works, goes, or shows a clear box. Each poll is one `swarm.sh wait
# --lead 0`. herdr is a stub: its agent list is ${FX}/agents, `agent read <pane>` prints ${FX}/<pane>.txt
# (failing once while ${FX}/read.fail exists, hanging while ${FX}/read.hang does), `pane send-keys` fails
# once while ${FX}/keys.fail exists, and it logs every call to ${ROOT}/herdr.log. python3 is the real one,
# but the resend check exits 1 once while ${FX}/py.crash exists, as an uncaught exception would.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/lib"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
busy_pid=""
trap 'unbusy; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; FX="${ROOT}/fx"; B="${P}/docs/stories"
SID=11111111-2222-3333-4444-555555555555
mkdir -p "${P}/.claude/swarm" "${B}" "${P}/.swarm/state" "${ROOT}/bin" "${FX}" "${CLAUDE_CONFIG_DIR}/projects/proj"
git -C "${P}" init -q

printf '#!/bin/sh\nFX="%s"; LOG="%s"\n' "${FX}" "${ROOT}/herdr.log" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'STUB'
echo "$*" >> "${LOG}"
case "$1 $2" in
  "agent list") printf '{"result":{"agents":[%s]}}\n' "$(cat "${FX}/agents" 2>/dev/null)" ;;
  "agent read") if [ -e "${FX}/read.fail" ]; then rm -f "${FX}/read.fail"; exit 1; fi
                # A tell that starts between the pass's ps read and its Enter: the fake swarm.sh, left running.
                # A tell that starts and ends while the pane is read: its line, written then.
                if [ -e "${FX}/read.ev" ]; then cat "${FX}/read.ev" >> "$(cat "${FX}/events.path")"; rm -f "${FX}/read.ev"; fi
                if [ -e "${FX}/read.spawn" ]; then bash "$(cat "${FX}/read.spawn")" tell ubr-s1 findings /tmp/f.md >/dev/null 2>&1 & echo $! > "${FX}/spawn.pid"; fi
                if [ -e "${FX}/read.hang" ]; then sleep 60; fi
                cat "${FX}/$3.txt" 2>/dev/null ;;
  "pane send-keys") if [ -e "${FX}/keys.fail" ]; then rm -f "${FX}/keys.fail"; exit 1; fi ;;
  *) echo '{"result":{}}' ;;
esac
STUB
chmod +x "${ROOT}/bin/herdr"
printf '#!/bin/sh\nFX="%s"\n' "${FX}" > "${ROOT}/bin/python3"
cat >> "${ROOT}/bin/python3" <<'STUB'
case "$*" in *unsent_brief*) if [ -e "${FX}/py.crash" ]; then rm -f "${FX}/py.crash"; exit 1; fi ;; esac
STUB
printf 'exec %s "$@"\n' "$(command -v python3)" >> "${ROOT}/bin/python3"
chmod +x "${ROOT}/bin/python3"
# The fake swarm.sh a delivery under way runs: ps shows `bash .../swarm.sh <args>` while it sleeps.
mkdir -p "${ROOT}/fake"; printf 'while :; do sleep 0.2; done\n' > "${ROOT}/fake/swarm.sh"
# busy <args>... — a process running `swarm.sh <args>` until unbusy.
busy() { bash "${ROOT}/fake/swarm.sh" "$@" & busy_pid=$!; }
unbusy() { [[ -z "${busy_pid}" ]] || { kill "${busy_pid}" 2>/dev/null || true; wait "${busy_pid}" 2>/dev/null || true; busy_pid=""; }; }

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }

# ago <seconds> — that long before now, as events.tsv and a session log stamp it.
ago() { python3 -c 'import sys, time; print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - int(sys.argv[1]))))' "$1"; }
# ev <command> <target> [time] [outcome] — one events.tsv line, as swarm.sh writes it.
ev() { printf '%s\t%s\t%s\t-\t%s\n' "${3:-$(ago 120)}" "$1" "$2" "${4:-ok}" >> "${P}/.swarm/events.tsv"; }
# listed <name:status>... — herdr lists each, in pane w:p<n> this project opened.
listed() {
  local a list="" i=0
  : > "${P}/.swarm/state/tab"
  for a in "$@"; do
    i=$((i + 1))
    list+="${list:+,}{\"name\":\"${a%%:*}\",\"agent_status\":\"${a#*:}\",\"pane_id\":\"w:p${i}\"}"
    echo "w:p${i} ${a%%:*}" >> "${P}/.swarm/state/tab"
  done
  printf '%s' "${list}" > "${FX}/agents"
}
# pane <id> <fixture> — what herdr agent read shows for pane <id>.
pane() { "$2" > "${FX}/$1.txt"; }
# A fresh agent's screen: the banner box, then the input box holding the brief herdr typed.
unsent() { printf '╭───────────────╮\n│ Claude Code   │\n╰───────────────╯\n\n────────────────\n❯ [Pasted text #1 +40 lines]\n────────────────\n  ⏵⏵ auto mode on\n'; }
# The brief submitted above an empty box.
submitted() { printf '> [Pasted text #1 +40 lines]\n\n────────────────\n❯ \n────────────────\n'; }
# A finished brief, its reply, and an unrelated paste in the box after it.
finished() { printf '> [Pasted text #1 +40 lines]\n\n⏺ Done: opened the PR.\n\n────────────────\n❯ [Pasted text #2 +3 lines]\n────────────────\n'; }
# session <name> <time>... — <name>'s Claude session on record, its log holding a prompt typed in at each
# time. tool <time> adds a turn's tool result and reply at <time>.
session() {
  local t
  printf '2026-10-26\tcode\t%s\tclaude\topus\thigh\t%s\n' "$1" "${SID}" >> "${P}/.swarm/agents.tsv"
  for t in "${@:2}"; do printf '{"type":"user","timestamp":"%s.500Z","message":{"content":"a brief"}}\n' "${t}"; done \
    > "${CLAUDE_CONFIG_DIR}/projects/proj/${SID}.jsonl"
}
tool() {
  printf '{"type":"user","timestamp":"%s.500Z","message":{"content":[{"type":"tool_result","content":"ok"}]}}\n' "$1"
  printf '{"type":"assistant","timestamp":"%s.600Z","message":{"content":[{"type":"text","text":"PR opened"}]}}\n' "$1"
} >> "${CLAUDE_CONFIG_DIR}/projects/proj/${SID}.jsonl"

# fresh — an empty board, no events, sessions or panes, an empty seen file (a run before this one).
fresh() {
  rm -rf "${B:?}"/*.md "${P}/.swarm/events.tsv" "${P}/.swarm/agents.tsv" "${P}/.swarm/lead" "${P}/.swarm/briefs" "${FX:?}"/* \
    "${CLAUDE_CONFIG_DIR}/projects/proj/"* "${ROOT}"/*.log
  : > "${P}/.claude/swarm/config"
  listed
  mkdir -p "${P}/.swarm/lead"; : > "${P}/.swarm/lead/seen"
}
# poll — one read of the lead's queue, inside herdr; output in ${ROOT}/out, exit code in ${ROOT}/rc.
poll() {
  (cd "${P}" && env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" HERDR_ENV=1 HERDR_PANE_ID=w:lead \
    bash "${SWARM}" wait --lead 0 > "${ROOT}/out" 2>&1) && echo 0 > "${ROOT}/rc" || echo $? > "${ROOT}/rc"
}
silent() { [[ "$(cat "${ROOT}/out")|$(cat "${ROOT}/rc")" == "|1" ]]; }
# count <pattern> <file> — lines of <file> matching <pattern>, 0 when it is missing.
count() { grep -c -- "$1" "$2" 2>/dev/null || true; }
enters() { count '^pane send-keys w:p1 Enter$' "${ROOT}/herdr.log"; }
reads() { count '^agent read ' "${ROOT}/herdr.log"; }
resends() { count $'\tresend\tubr-s1\t' "${P}/.swarm/events.tsv"; }

# Agent names no other test's processes name: a swarm.sh story, tell or review-agent naming one anywhere
# on the machine counts as a delivery under way and skips it.
# --- the resend.
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1; session ubr-s1
poll
check "an idle agent with its brief in the input box gets one Enter in its pane" test "$(enters)" == 1
check "and one resend ubr-s1 line" test "$(resends)" == 1
check "and the poll prints nothing and does not return" silent
: > "${ROOT}/herdr.log"; poll
check "the next poll, with no new start or tell line, sends nothing" test "$(enters)|$(resends)" == "0|1"

# --- what is never submitted.
fresh; listed ubr-s1:idle; pane w:p1 submitted; ev story ubr-s1; session ubr-s1
poll
check "an empty box under a submitted brief gets no Enter and no resend line" test "$(enters)|$(resends)" == "0|0"

fresh; listed ubr-s1:working; pane w:p1 unsent; ev story ubr-s1
poll
check "a working agent with the paste in its box gets no pane read" test "$(reads)|$(enters)" == "0|0"

fresh; listed ubr-s1:idle; pane w:p1 finished; ev story ubr-s1 "$(ago 120)"; session ubr-s1 "$(ago 60)"
poll
check "a finished brief, with an unrelated paste in the box after it, is not submitted" test "$(enters)|$(resends)" == "0|0"
# No log is no sign of no turn: Claude Code writes one before the first prompt.
fresh; listed ubr-s1:idle; pane w:p1 finished; ev story ubr-s1; printf '2026-10-26\tcode\tubr-s1\tclaude\topus\thigh\t%s\n' "${SID}" > "${P}/.swarm/agents.tsv"
poll
check "an agent whose session log is missing is not submitted" test "$(reads)|$(enters)|$(resends)" == "1|0|0"
pane w:p1 unsent; session ubr-s1
poll
check "once its log shows no turn, the next poll reads it again and resends" test "$(reads)|$(enters)|$(resends)" == "2|1|1"
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1
poll
check "an agent with no session on record is not submitted" test "$(reads)|$(enters)|$(resends)" == "1|0|0"

# A turn the brief started can be stamped before its line: swarm.sh logs the line once the command returns.
# A start opens its own session, so any turn in it took the brief, however long the start ran.
fresh; listed ubr-s1:idle; pane w:p1 finished; ev story ubr-s1 "$(ago 120)"; session ubr-s1 "$(ago 900)"
poll
check "a started brief taken up before its command logged the line, then an unrelated paste, is not submitted" test "$(enters)|$(resends)" == "0|0"
fresh; listed ubr-s1:idle; pane w:p1 finished; ev story ubr-s1 "$(ago 3600)"; ev tell:findings ubr-s1 "$(ago 120)"; session ubr-s1 "$(ago 3600)" "$(ago 520)"
poll
check "a told brief taken up before its tell logged the line, then an unrelated paste, is not submitted" test "$(enters)|$(resends)" == "0|0"

# What the command's outcome says about the prompt.
# A newer start that failed before sending decides, though an older one went: its new session has no turn.
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1 "$(ago 3600)"; session ubr-s1
ev story ubr-s1 "$(ago 120)" "ubr-s1: herdr did not send it the brief (agent_not_found); see herdr agent read ubr-s1"
poll
check "a newer start that failed before sending gets no Enter from an older ok one" test "$(enters)|$(resends)" == "0|0"
fresh; listed ubr-s1:idle; pane w:p1 finished; ev story ubr-s1 "$(ago 3600)"; session ubr-s1 "$(ago 3600)"
ev tell:findings ubr-s1 "$(ago 120)" "ubr-s1: no file /tmp/findings.md"
poll
check "a tell that failed before sending anything makes no unrelated paste a brief" test "$(enters)|$(resends)" == "0|0"
# A note goes to the conductor's inbox; a busy conductor gets no prompt at all.
fresh; listed conduct-ubr-e:idle; pane w:p1 finished; ev conduct ubr-e "$(ago 3600)"; session conduct-ubr-e "$(ago 3600)"
ev tell:note conduct-ubr-e "$(ago 120)"
poll
check "a note makes no unrelated paste in a conductor's box a brief" test "$(enters)|$(count $'\tresend\t' "${P}/.swarm/events.tsv")" == "0|0"
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1 "$(ago 3600)"; session ubr-s1 "$(ago 3600)"
ev tell:findings ubr-s1 "$(ago 120)" "ubr-s1: the brief was not taken up: herdr sent it the brief twice, and herdr reads it idle with no turn finished since; see herdr agent read ubr-s1"
poll
check "a tell that failed because the brief was not taken up is resent" test "$(enters)|$(resends)" == "1|1"

fresh; listed ubr-hld:idle; pane w:p1 unsent; ev agent ubr-hld; session ubr-hld
poll
check "an agent started by name with its brief in the box is resent" test "$(enters)|$(count $'\tresend\tubr-hld\t' "${P}/.swarm/events.tsv")" == "1|1"

# A restart under way: its pane and session are up before its story line is written.
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1 "$(ago 3600)"; session ubr-s1; busy story ubr-s1
poll
check "an agent a story start is still delivering to gets no pane read" test "$(reads)|$(enters)|$(resends)" == "0|0|0"
unbusy; poll
check "once the start has returned, the next poll resends" test "$(enters)|$(resends)" == "1|1"
fresh; listed review-ubr-s1:idle; pane w:p1 unsent; ev review-agent ubr-s1 "$(ago 3600)"; session review-ubr-s1; busy review-agent ubr-s1 https://github.com/o/r/pull/1
poll
check "a review agent that review-agent <slug> is still delivering to gets no pane read" test "$(reads)|$(enters)" == "0|0"
unbusy
# herdr's names are cut to 32 characters; the command names the whole slug.
long=ubr-a-story-slug-longer-than-the-name-cut
fresh; listed "${long:0:32}:idle"; pane w:p1 unsent; ev story "${long}" "$(ago 3600)"; session "${long:0:32}"; busy tell "${long}" findings /tmp/f.md
poll
check "a builder whose long slug a tell is still delivering to gets no pane read" test "$(reads)|$(enters)" == "0|0"
unbusy
fresh; listed ubrhld:idle; pane w:p1 unsent; ev agent ubrhld "$(ago 3600)"; session ubrhld; busy agent _hld UbrHld /tmp hld /tmp/b.md
poll
check "an agent that swarm.sh agent is starting under a name agent_name lowers gets no pane read" test "$(reads)|$(enters)" == "0|0"
unbusy

# swarm.sh next and merge start conductors in their own process (conduct_ready).
fresh; listed conduct-ubr-e:idle; pane w:p1 unsent; ev conduct ubr-e "$(ago 3600)"; session conduct-ubr-e; busy merge https://github.com/o/r/pull/9
poll
check "a conductor gets no pane read while a swarm.sh merge, which may be starting it, runs" test "$(reads)|$(enters)" == "0|0"
unbusy   # no check that it is resent next: any swarm.sh next or merge on the machine (another test's) holds it

# --- which lines are deliveries.
# agent_name puts an s before a slug that does not start with a letter.
fresh; listed s2ubr-fa:idle; pane w:p1 unsent; ev story 2ubr-fa; session s2ubr-fa
poll
check "a digit-led slug's builder, named s<slug>, is resent" test "$(enters)|$(count $'\tresend\ts2ubr-fa\t' "${P}/.swarm/events.tsv")" == "1|1"
# A ladder step-up logs only its escalate line; the new rung's handover brief can sit in its box.
# A poll first checks the story line against a clear box, so only the escalate line can send.
fresh; listed ubr-s1:idle; pane w:p1 submitted; ev story ubr-s1 "$(ago 3600)"; session ubr-s1
poll
pane w:p1 unsent; ev escalate ubr-s1 "$(ago 120)" "ok (findings-3: opus -> fable)"
poll
check "a stepped-up rung's handover brief left in its box is resent" test "$(enters)|$(resends)" == "1|1"
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1 "$(ago 3600)"; session ubr-s1 "$(ago 3600)"
ev tell:findings ubr-s1 "$(ago 120)" "ubr-s1: herdr's reply to the brief could not be read once, then could not send it again (timeout); see herdr agent read ubr-s1"
poll
check "a tell whose herdr reply could not be read, the paste maybe in the box, is resent" test "$(enters)|$(resends)" == "1|1"

fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1; session ubr-s1; echo "${ROOT}/fake/swarm.sh" > "${FX}/read.spawn"
poll
spawned="$(cat "${FX}/spawn.pid" 2>/dev/null || true)"; [[ -z "${spawned}" ]] || { kill "${spawned}" 2>/dev/null || true; wait "${spawned}" 2>/dev/null || true; }
check "a tell that starts while the pane is read gets no Enter from the pass" test "${spawned:+x}|$(reads)|$(enters)" == "x|1|0"

fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1 "$(ago 3600)"; session ubr-s1
echo "${P}/.swarm/events.tsv" > "${FX}/events.path"; printf '%s\ttell:findings\tubr-s1\t-\tok\n' "$(ago 30)" > "${FX}/read.ev"
poll
check "a tell logged while the pane is read stops that Enter" test "$(enters)|$(resends)" == "0|0"
poll
check "the next poll resends for the tell, once" test "$(enters)|$(resends)" == "1|1"
# Its own resend line grows events.tsv too: that must not hold back a second agent's Enter.
fresh; listed ubr-s1:idle ubr-s2:idle; pane w:p1 unsent; pane w:p2 unsent; ev story ubr-s1; ev story ubr-s2; session ubr-s1
printf '2026-10-26\tcode\tubr-s2\tclaude\topus\thigh\t%s\n' "${SID}" >> "${P}/.swarm/agents.tsv"
poll
check "two unsent briefs are both resent in one poll" test "$(count '^pane send-keys ' "${ROOT}/herdr.log")" == 2

# --- a pane that cannot be read.
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1; session ubr-s1; touch "${FX}/read.fail"
poll
check "a pane read that fails sends nothing" test "$(reads)|$(enters)|$(resends)" == "1|0|0"
poll
check "the next poll reads it again and resends the unsent brief" test "$(reads)|$(enters)|$(resends)" == "2|1|1"

fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1; session ubr-s1; touch "${FX}/keys.fail"
poll
check "an Enter herdr fails to send logs the failure as the resend's outcome" \
  test "$(enters)|$(count $'\tresend\tubr-s1\tw:lead\therdr could not send Enter' "${P}/.swarm/events.tsv")" == "1|1"
poll
check "the next poll sends it again" test "$(enters)|$(count $'\tresend\tubr-s1\tw:lead\tok$' "${P}/.swarm/events.tsv")" == "2|1"

fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1; session ubr-s1; touch "${FX}/py.crash"
poll
check "a resend check that crashes sends nothing" test "$(enters)|$(resends)" == "0|0"
poll
check "the next poll checks it again and resends" test "$(enters)|$(resends)" == "1|1"

# A hung herdr read must not hold the poll: the lead still gets the held story it found.
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1; session ubr-s1; touch "${FX}/read.hang"
printf -- '---\nkind: code\nstatus: ready\nheld_for: needs a key\n---\n\n# ubr-h1\n' > "${B}/ubr-h1.md"
t0=${SECONDS}; poll
check "a hung pane read is cut off, and the poll still returns on the held story" \
  test "$(cat "${ROOT}/out")|$(cat "${ROOT}/rc")|$(enters)|$(( SECONDS - t0 < 40 ))" == "held: ubr-h1 (needs a key)|0|0|1"

# Hung reads in many panes: no read starts 20 s into the pass, so at most three of these five start.
fresh; listed ubr-s1:idle ubr-s2:idle ubr-s3:idle ubr-s4:idle ubr-s5:idle; touch "${FX}/read.hang"
for i in 1 2 3 4 5; do pane "w:p${i}" unsent; ev story "ubr-s${i}"; done
printf -- '---\nkind: code\nstatus: ready\nheld_for: needs a key\n---\n\n# ubr-h1\n' > "${B}/ubr-h1.md"
poll
check "hung reads in five panes start at most three, and the poll still returns on the held story" \
  test "$(cat "${ROOT}/out")|$(cat "${ROOT}/rc")|$(( $(reads) <= 3 ))" == "held: ubr-h1 (needs a key)|0|1"

# The record goes in before the Enter: a delivery it cannot record gets none.
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1; session ubr-s1; mkdir "${P}/.swarm/lead/resend"
poll
check "a delivery whose record cannot be written gets no Enter" test "$(enters)|$(resends)" == "0|0"
rmdir "${P}/.swarm/lead/resend"; poll
check "once it can be, the next poll resends" test "$(enters)|$(resends)" == "1|1"
# A run stopped between its pending line and its Enter (a new wait --lead took over).
fresh; listed ubr-s1:idle; pane w:p1 unsent; t="$(ago 120)"; ev story ubr-s1 "${t}"; session ubr-s1
printf 'ubr-s1\t%s\tstory\t1\tpending\n' "${t}" > "${P}/.swarm/lead/resend"
poll
check "a delivery left pending by a stopped run is resent by the next" test "$(enters)|$(resends)" == "1|1"

# --- a tell's brief, and what the resend line is not.
# The builder's last turn, a short one, started ten minutes before the findings tell and ended (a tool
# result and its reply) 80 seconds before it.
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1 "$(ago 3600)"; ev tell:findings ubr-s1; session ubr-s1 "$(ago 3600)" "$(ago 720)"; tool "$(ago 200)"
poll
check "a findings tell left in the box is resent, though the last turn ended just before it" test "$(enters)|$(resends)" == "1|1"
check "events.tsv still has one tell:findings line for ubr-s1" test "$(count $'\ttell:findings\tubr-s1\t' "${P}/.swarm/events.tsv")" == 1
line="$(grep $'\tresend\tubr-s1\t' "${P}/.swarm/events.tsv")"
check "the stall rule's sign_time skips the resend line" test "$(SWARM_LIB="${LIB}" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["SWARM_LIB"]); from stall import sign_time
print(sign_time(sys.argv[1].split("\t")))' "${line}")" == None

# Two tells to one agent in the same second are two deliveries.
fresh; listed ubr-s1:idle; pane w:p1 submitted; t="$(ago 120)"; ev tell:findings ubr-s1 "${t}"; session ubr-s1 "$(ago 3600)"
poll
pane w:p1 unsent; ev tell:findings ubr-s1 "${t}"
poll
check "a second tell logged in the same second as one already checked is still resent" test "$(enters)|$(resends)" == "1|1"

# --- it wakes no one, and the queue still does.
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1; session ubr-s1
printf -- '---\nkind: code\nstatus: ready\nheld_for: needs a key\n---\n\n# ubr-h1\n' > "${B}/ubr-h1.md"
poll
check "a poll that resends and finds a held story returns on the held story alone" \
  test "$(cat "${ROOT}/out")|$(cat "${ROOT}/rc")|$(enters)|$(resends)" == "held: ubr-h1 (needs a key)|0|1|1"

# --- still unsent after the resend: the .unsent marker and its lead line.
M="${P}/.swarm/briefs/ubr-s1.unsent"
in_seen() { count '^unsent brief: ' "${P}/.swarm/lead/seen"; }
# A ready story with its worktree and builder on record, which no_agent_exit offers a restart.
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1; session ubr-s1; mkdir -p "${ROOT}/proj-wt/ubr-s1"
printf -- '---\nkind: code\nstatus: ready\n---\n\n# ubr-s1\n' > "${B}/ubr-s1.md"
poll
check "the poll that resends writes no .unsent marker" test "$(enters)|$([[ -e "${M}" ]] && echo marker)" == "1|"
poll
check "the poll after the resend, still reading the paste in the box, writes .swarm/briefs/ubr-s1.unsent" test -f "${M}"
check "and wait --lead returns, naming the builder's close and restart" \
  test "$(cat "${ROOT}/out")|$(cat "${ROOT}/rc")" == "unsent brief: ubr-s1, exit: herdr pane close w:p1 then swarm.sh restart ubr-s1, or swarm.sh hold ubr-s1 <reason>|0"
: > "${ROOT}/herdr.log"; poll
check "a later poll reads the marked pane once, sends nothing, keeps the marker and does not return" \
  test "$(reads)|$(enters)|$([[ -e "${M}" ]] && echo marker)|$(cat "${ROOT}/out")|$(cat "${ROOT}/rc")" == "1|0|marker||1"
listed ubr-s1:working; poll
check "the marker goes on the poll that finds its agent working" test ! -e "${M}"
check "and its line is gone from .swarm/lead/seen" test "$(in_seen)" == 0
rm -rf "${ROOT}/proj-wt"

fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1; session ubr-s1; poll; poll
check "with the marker written, its line is in .swarm/lead/seen" test "$(in_seen)" == 1
pane w:p1 submitted; poll
check "the marker goes on the poll that finds its box clear" test "$(in_seen)|$([[ -e "${M}" ]] && echo marker)" == "0|"
# The brief taken up between polls, and a new paste left in the box after it.
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1 "$(ago 3600)"; session ubr-s1; poll; poll
pane w:p1 finished; session ubr-s1 "$(ago 10)"; poll
check "the marker goes on the poll whose session shows a turn since the brief, a new paste in the box" \
  test "$(in_seen)|$([[ -e "${M}" ]] && echo marker)" == "0|"
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1; session ubr-s1; poll; poll; listed; poll
check "the marker goes once herdr no longer lists its agent" test "$(in_seen)|$([[ -e "${M}" ]] && echo marker)" == "0|"

# The false case: the resend went through.
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1; session ubr-s1; poll
pane w:p1 submitted; poll
check "a box clear on the poll after the resend gets no marker" test ! -e "${M}"
check "and wait --lead does not return" silent
: > "${ROOT}/herdr.log"; poll
check "that read after the resend is done once: the next poll reads nothing" test "$(reads)" == 0
# A tell logged while that read runs: the paste may be the tell's own, which has had no resend yet.
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1 "$(ago 3600)"; session ubr-s1; poll
echo "${P}/.swarm/events.tsv" > "${FX}/events.path"; printf '%s\ttell:findings\tubr-s1\t-\tok\n' "$(ago 30)" > "${FX}/read.ev"
poll
check "a tell logged during the read after the resend writes no marker" test "$([[ -e "${M}" ]] && echo marker)|$(cat "${ROOT}/rc")" == "|1"
poll
check "and the next poll resends for that tell instead" test "$(enters)|$(resends)" == "2|2"

fresh; listed review-ubr-s1:idle; pane w:p1 unsent; ev review-agent ubr-s1; session review-ubr-s1
printf -- '---\nkind: code\nstatus: ready\nprs: https://github.com/o/r/pull/7\n---\n\n# ubr-s1\n' > "${B}/ubr-s1.md"
poll; poll
check "a review agent's line names swarm.sh close review-<slug>, then review-agent <slug> <PR URL>" \
  test "$(cat "${ROOT}/out")|$(cat "${P}/.swarm/briefs/review-ubr-s1.unsent" 2>/dev/null | head -1)" \
  == "unsent brief: review-ubr-s1, exit: swarm.sh close review-ubr-s1 then swarm.sh review-agent ubr-s1 https://github.com/o/r/pull/7|review-ubr-s1 w:p1 review"

# A tell takes its agent's role: from its start line (a review agent), or with none, from the name it
# was told by (a conductor). Any swarm.sh next or merge on the machine holds a conductor's read
# (resend_busy), so its polls go on until the marker is written, at most twelve.
fresh; listed review-ubr-s1:idle; pane w:p1 unsent; ev review-agent ubr-s1 "$(ago 3600)"; ev tell:nudge review-ubr-s1
session review-ubr-s1 "$(ago 3600)"
printf -- '---\nkind: code\nstatus: ready\nprs: https://github.com/o/r/pull/7\n---\n\n# ubr-s1\n' > "${B}/ubr-s1.md"
poll; poll
check "a tell left unsent in a review agent's box gets a review marker and the review-agent exit" \
  test "$(cat "${ROOT}/out")|$(head -1 "${P}/.swarm/briefs/review-ubr-s1.unsent" 2>/dev/null)" \
  == "unsent brief: review-ubr-s1, exit: swarm.sh close review-ubr-s1 then swarm.sh review-agent ubr-s1 https://github.com/o/r/pull/7|review-ubr-s1 w:p1 review"
# nexts — the swarm.sh next and merge processes running now, which hold every conductor's read.
nexts() { ps -A -ww -o command= | awk '{ for (i = 1; i < NF; i++) if ($i ~ /swarm\.sh$/ && ($(i + 1) == "next" || $(i + 1) == "merge")) { n++; break } } END { print n + 0 }'; }
# held: a next or merge seen around any poll. One that held every poll and ended before a single check
# after them was a FAIL where it should skip, on a CI shard whose other files run next and merge.
fresh; listed conduct-ubr-e:idle; pane w:p1 unsent; ev tell:nudge conduct-ubr-e; session conduct-ubr-e
held=0
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  [[ "$(nexts)" -eq 0 ]] || held=1
  poll
  [[ "$(nexts)" -eq 0 ]] || held=1
  [[ ! -e "${P}/.swarm/briefs/conduct-ubr-e.unsent" ]] || break
done
if [[ ! -e "${P}/.swarm/briefs/conduct-ubr-e.unsent" && ${held} -eq 1 ]]; then
  echo "skip a tell left unsent in a conductor's box: a swarm.sh next or merge on this machine held its reads"
else
  check "a tell left unsent in a conductor's box gets a conductor marker and the conduct exit" \
    test "$(cat "${ROOT}/out")|$(head -1 "${P}/.swarm/briefs/conduct-ubr-e.unsent" 2>/dev/null)" \
    == "unsent brief: conduct-ubr-e, exit: swarm.sh close conduct-ubr-e then swarm.sh conduct ubr-e|conduct-ubr-e w:p1 conductor"
fi

# A story in review: restart refuses it, so its builder, findings in the box, is kept.
fresh; echo "merge = agent" > "${P}/.claude/swarm/config"; listed ubr-s1:idle; pane w:p1 unsent
ev story ubr-s1 "$(ago 3600)"; ev tell:findings ubr-s1; session ubr-s1 "$(ago 3600)"
printf -- '---\nkind: code\nstatus: review\nprs: https://github.com/o/r/pull/7\n---\n\n# ubr-s1\n' > "${B}/ubr-s1.md"
poll; poll
check "a story in review's builder, its findings unsent, is kept: the exit tells it a nudge" \
  test "$(cat "${ROOT}/out")" == "unsent brief: ubr-s1, exit: swarm.sh wait --idle ubr-s1 && swarm.sh tell ubr-s1 nudge <a file asking it to act on the brief in its input box>"

# A restart is a delivery: its brief is watched, and an older resend is not read against it.
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1 "$(ago 3600)"; session ubr-s1; poll
ev restart ubr-s1 "$(ago 60)" "ok (fresh on opus: no session to resume)"; poll
check "a builder restarted after the resend gets its new brief resent, and no marker from the old one" \
  test "$(enters)|$(resends)|$([[ -e "${M}" ]] && echo marker)" == "2|2|"
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1 "$(ago 3600)"; session ubr-s1; poll; poll
listed; poll; listed ubr-s1:idle; ev restart ubr-s1 "$(ago 60)" "ok (fresh on opus: no session to resume)"; poll
check "after the exit's pane close and restart, the restarted builder's brief is resent" \
  test "$(enters)|$([[ -e "${M}" ]] && echo marker)" == "2|"
poll
check "and, still in its box on the next poll, gets the marker again" test -f "${M}"

# An Enter herdr fails to send logs a line: another agent's marker in the same pass is not put off.
fresh; listed ubr-s1:working ubr-s2:idle; pane w:p1 unsent; pane w:p2 unsent; ev story ubr-s2 "$(ago 3600)"; session ubr-s2
printf '2026-10-26\tcode\tubr-s1\tclaude\topus\thigh\t%s\n' "${SID}" >> "${P}/.swarm/agents.tsv"; poll
listed ubr-s1:idle ubr-s2:idle; ev story ubr-s1 "$(ago 60)"; touch "${FX}/keys.fail"; poll
check "a failed Enter to one agent does not stop the marker of another in the same poll" \
  test "$(count $'\tresend\tubr-s1\tw:lead\therdr could not send Enter' "${P}/.swarm/events.tsv")|$([[ -e "${P}/.swarm/briefs/ubr-s2.unsent" ]] && echo marker)" == "1|marker"

# herdr can list an agent with no status: it is still listed, so its marker stays.
fresh; listed ubr-s1:idle; pane w:p1 unsent; ev story ubr-s1; session ubr-s1; poll; poll
printf '{"name":"ubr-s1","pane_id":"w:p1"}' > "${FX}/agents"; poll
check "an agent herdr lists with no status keeps its marker" test -f "${M}"

echo
[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
