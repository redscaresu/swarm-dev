#!/usr/bin/env bash
# unsent_brief_test.sh — wait --lead's resend pass: an idle agent whose input box still holds the brief
# a start or tell typed there (a collapsed `[Pasted text #N` paste) gets one Enter, and one `resend
# <agent>` events.tsv line, per delivery; nothing else is ever submitted. Each poll is one `swarm.sh wait
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
  rm -rf "${B:?}"/*.md "${P}/.swarm/events.tsv" "${P}/.swarm/agents.tsv" "${P}/.swarm/lead" "${FX:?}"/* \
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

echo
[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
