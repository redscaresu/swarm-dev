#!/usr/bin/env bash
# stuck_work_watch_test.sh — wait --lead's prompt: lines (prompt_lines). An agent herdr lists as blocked in a
# pane this project opened, its pane one of tests/fixtures/panes' stuck screens (a permission prompt, a
# dialog, an expired login, an API error, manual mode), gives its `prompt: <agent> (<kind>), exit: <exit>`
# line on one `swarm.sh wait --lead 0`, and the next poll is quiet. Quiet too: an agent mid-command, a
# working agent (whose pane is never read), a co-writer (/hld), any agent while an upgrade runs, and an API
# error while a `swarm.sh wait` naming the agent runs, which resumes it. A pane read, a herdr list or a
# list parse that fails keeps the line from the last poll, so it neither goes nor wakes the lead again. A
# run with no .swarm/lead/seen yet still prints it, as an alert. A pane found clear is read again only when
# its agent's status or session log changed, or STUCK_RECHECK passed; a stuck one every poll; none while a
# swarm.sh command delivers the agent a prompt; and agents not read in a poll whose budget ran out go first
# in the next. A turn that ends on the same stop, or the same stop in a new pane, wakes the lead again; a
# prompt over the manual-mode footer is manual, which never does. Manual mode on a ready story's builder
# closes its pane, then restarts or holds the story, found by its full slug (cut_record).
# herdr is a stub listing ${ROOT}/agents (failing while ${ROOT}/list-fails exists, cut short while
# ${ROOT}/list-garbled does), whose agent read logs itself to ${ROOT}/reads, hangs while ${ROOT}/hang-<pane>
# exists, and prints ${ROOT}/pane.txt, failing without it.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWARM="${HOME_DIR}/bin/swarm.sh"
FX="${HOME_DIR}/tests/fixtures/panes"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
WAITER=""
trap '[[ -z "${WAITER}" ]] || kill "${WAITER}" 2>/dev/null || true; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TMPDIR="${ROOT}/tmp"
# The agent: a name of this run's own, since ps is the whole machine's and the fake wait below names it.
P="${ROOT}/proj"; B="${P}/docs/stories"; AGENT="sww$$"; A="${AGENT}"
mkdir -p "${P}/.claude/swarm" "${B}" "${P}/.swarm/state" "${ROOT}/bin" "${ROOT}/fake" "${ROOT}/projects" "${TMPDIR}"
git -C "${P}" init -q
echo "merge = human" > "${P}/.claude/swarm/config"
echo "w:p1 ${A}" > "${P}/.swarm/state/tab"   # the pane this project opened for the agent

printf '#!/bin/sh\nR="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'STUB'
case "$1 $2" in
  "agent list") [ ! -e "${R}/list-fails" ] || exit 1; [ ! -e "${R}/list-garbled" ] || { echo '{"result":'; exit 0; }; printf '{"result":{"agents":[%s]}}\n' "$(cat "${R}/agents" 2>/dev/null)" ;;
  "agent read") echo "$*" >> "${R}/reads"; [ ! -e "${R}/hang-$3" ] || sleep 15; cat "${R}/pane.txt" ;;
  *) echo '{"result":{}}' ;;
esac
STUB
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/bin/gh"
# A stand-in for a `swarm.sh wait` that is still resuming the agent: ps shows its command line. The sleep
# runs in the background, so no sh replaces itself with it, and goes with the shell.
printf '#!/bin/sh\nsleep 60 &\ntrap '"'"'kill $!; exit 0'"'"' TERM\nwait\n' > "${ROOT}/fake/swarm.sh"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh" "${ROOT}/fake/swarm.sh"

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
run() { (cd "${P}" || exit 1; env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" HERDR_ENV=1 bash "${SWARM}" wait --lead 0 2>&1) || true; }
# agent <status> <fixture> — herdr lists the agent with <status>, its pane the fixture's screen.
agent() {
  echo "{\"name\":\"${A}\",\"agent_status\":\"$1\",\"pane_id\":\"w:p1\"}" > "${ROOT}/agents"
  cp "${FX}/$2" "${ROOT}/pane.txt"
}
# fresh — a lead that has read its queue before, with nothing in it.
fresh() { rm -rf "${P}/.swarm/lead" "${P}/.swarm/events.tsv"; mkdir -p "${P}/.swarm/lead"; : > "${P}/.swarm/lead/seen"; }
# fake <args>... — the fake swarm.sh running <args> in the background, returning once ps shows it: a
# poll that read ps before its exec would see no such command.
fake() {
  "${ROOT}/fake/swarm.sh" "$@" & WAITER=$!
  local i
  for ((i = 0; i < 100; i++)); do ! ps -p "${WAITER}" -o command= 2>/dev/null | grep -q "fake/swarm.sh $1" || return 0; sleep 0.1; done
  echo "FAIL the fake swarm.sh $* never showed in ps"; fails=$((fails + 1))
}
# reads — how many pane reads herdr took since the last call.
reads() { local n; n="$(grep -c '^agent read' "${ROOT}/reads" 2>/dev/null)" || true; : > "${ROOT}/reads"; echo "${n:-0}"; }
# count <text> <out> — how many lines of <out> start with <text>.
count() { awk -v t="$1" 'index($0, t) == 1 { n++ } END { print n + 0 }' <<< "$2"; }

# <fixture> <kind> <exit>, for each stuck screen.
while read -r fx kind exit; do
  fresh; agent blocked "${fx}"
  line="prompt: ${A} (${kind}), exit: ${exit}"
  out="$(run)"
  check "a blocked agent on ${fx} gives its ${kind} line once" test "$(count "${line}" "${out}")" = 1
  check "the line on ${fx} is the whole line" grep -qxF "${line}" <<< "${out}"
  out="$(run)"
  check "the next poll on ${fx} is quiet" test "$(count "prompt: " "${out}")" = 0
done <<EOF
prompt.txt prompt the user answers it in pane w:p1
dialog.txt prompt the user answers it in pane w:p1
login.txt login the user runs /login, then swarm.sh tell ${A} resume <file>
api-error.txt api-error herdr agent read ${A}, then tell the user what it shows
manual.txt manual the user turns manual mode off in pane w:p1
EOF

fresh; agent blocked mid-command.txt
check "an agent mid-command gives no prompt: line" test "$(count "prompt: " "$(run)")" = 0
fresh; agent working prompt.txt
check "a working agent gives no prompt: line" test "$(count "prompt: " "$(run)")" = 0
fresh; agent idle prompt.txt; rm -f "${P}/.swarm/state/tab"
check "an agent in a pane this project did not open gives no prompt: line" test "$(count "prompt: " "$(run)")" = 0
echo "w:p1 ${A}" > "${P}/.swarm/state/tab"

# A run with no lead/seen yet prints only the alerts on its first read: a prompt: line is one.
fresh; agent blocked prompt.txt; rm -f "${P}/.swarm/lead/seen"
check "a first read with no lead/seen yet prints the prompt: line" test "$(count "prompt: ${A} (prompt)" "$(run)")" = 1

# A pane found clear is read again only when the agent's herdr status or its session log changed since the
# last poll (or STUCK_RECHECK passed, below). A stuck one is read every poll, so a stop cleared with no
# turn goes.
fresh; agent blocked mid-command.txt; : > "${ROOT}/reads"
mkdir -p "${ROOT}/projects/proj"; log="${ROOT}/projects/proj/session-0.jsonl"; : > "${log}"
printf '2026-10-27\tconduct\t%s\tclaude\topus\t-\tsession-0\n' "${A}" > "${P}/.swarm/agents.tsv"
check "the first poll on a clear pane reads it and gives no line" test "$(count "prompt: " "$(run)")|$(reads)" = "0|1"
cp "${FX}/prompt.txt" "${ROOT}/pane.txt"
check "the next poll, nothing changed, reads no pane" test "$(count "prompt: " "$(run)")|$(reads)" = "0|0"
touch -t 203001010000 "${log}"
check "a poll after the session log changed reads the pane again and finds the prompt" \
  test "$(count "prompt: ${A} (prompt)" "$(run)")|$(reads)" = "1|1"
touch -t 203006010000 "${log}"
check "a turn that ends on the same prompt again wakes the lead again" test "$(count "prompt: ${A} (prompt)" "$(run)")" = 1
check "the poll after it, with no turn, is quiet" test "$(count "prompt: " "$(run)")" = 0
cp "${FX}/manual.txt" "${ROOT}/pane.txt"; run > /dev/null; reads > /dev/null
cp "${FX}/empty-box.txt" "${ROOT}/pane.txt"; run > /dev/null
check "a stuck pane is read every poll, so manual mode turned off with no turn clears its line" \
  test "$(reads)|$(grep -c "prompt: ${A}" "${P}/.swarm/lead/seen" || true)" = "1|0"
# An agent a swarm.sh command is delivering a prompt to is not read, and keeps its line.
cp "${FX}/prompt.txt" "${ROOT}/pane.txt"; touch -t 203101010000 "${log}"; run > /dev/null
check "a new turn that ends on a prompt brings the line back" grep -qF "prompt: ${A} (prompt)" "${P}/.swarm/lead/seen"
agent idle prompt.txt; reads > /dev/null
fake tell "${A}" nudge /tmp/f.md
check "an agent a tell is delivering to is quiet" test "$(count "prompt: " "$(run)")" = 0
check "and its pane is not read" test "$(reads)" = 0
check "and its line stays in the lead's queue" grep -qF "prompt: ${A} (prompt)" "${P}/.swarm/lead/seen"
kill "${WAITER}" 2>/dev/null || true; wait "${WAITER}" 2>/dev/null || true; WAITER=""
rm -f "${P}/.swarm/agents.tsv"

# A clear pane is read again after STUCK_RECHECK seconds with nothing changed, so manual mode turned on at an
# idle box shows; with no session log, too, and at once when its status changes.
fresh; agent idle empty-box.txt; : > "${ROOT}/reads"
check "an idle agent at an empty box gives no line" test "$(count "prompt: " "$(run)")|$(reads)" = "0|1"
cp "${FX}/manual.txt" "${ROOT}/pane.txt"
check "with no session log and nothing changed, the next poll reads no pane" test "$(count "prompt: " "$(run)")|$(reads)" = "0|0"
awk 'BEGIN { FS = OFS = "\t" } { $5 = 0 } 1' "${P}/.swarm/lead/stuck" > "${ROOT}/stuck" && mv "${ROOT}/stuck" "${P}/.swarm/lead/stuck"
check "once STUCK_RECHECK has passed, the pane is read again and shows manual mode turned on" \
  test "$(count "prompt: ${A} (manual)" "$(run)")|$(reads)" = "1|1"
fresh; agent idle empty-box.txt; run > /dev/null; cp "${FX}/manual.txt" "${ROOT}/pane.txt"; agent blocked manual.txt
check "a status change reads a clear pane again at once" test "$(count "prompt: ${A} (manual)" "$(run)")" = 1

# A permission prompt over the manual-mode footer is manual mode, and a builder in it answering prompts
# wakes no one again.
fresh; agent blocked ruled-dialog.txt
printf '2026-10-27\tconduct\t%s\tclaude\topus\t-\tsession-0\n' "${A}" > "${P}/.swarm/agents.tsv"
check "a permission prompt over the manual-mode footer gives a manual line" test "$(count "prompt: ${A} (manual)" "$(run)")" = 1
touch -t 203201010000 "${log}"
check "the next answered prompt, in manual mode still, wakes no one" test "$(count "prompt: " "$(run)")" = 0
# A co-writer (/hld, /epic) asks the user in its own pane: no line.
fresh; agent blocked prompt.txt
printf '2026-10-27\thld\t%s\tclaude\topus\t-\tsession-0\n' "${A}" > "${P}/.swarm/agents.tsv"
check "an hld co-writer on a prompt gives no line" test "$(count "prompt: " "$(run)")" = 0
rm -f "${P}/.swarm/agents.tsv"

# An agent back in a new pane that stops on the same login is a new stop.
fresh; agent blocked login.txt
check "a login stop gives its line" test "$(count "prompt: ${A} (login)" "$(run)")" = 1
echo "w:p2 ${A}" > "${P}/.swarm/state/tab"; echo "{\"name\":\"${A}\",\"agent_status\":\"blocked\",\"pane_id\":\"w:p2\"}" > "${ROOT}/agents"
check "the same login in a new pane wakes the lead again" test "$(count "prompt: ${A} (login)" "$(run)")" = 1
echo "w:p1 ${A}" > "${P}/.swarm/state/tab"

# While an upgrade runs, which restarts agents through their own prompts, no pane is read and no line comes.
fresh; agent blocked prompt.txt; : > "${ROOT}/reads"
fake upgrade --all; echo "${WAITER} - ${ROOT}/upgrade.log" > "${P}/.swarm/upgrade.pid"
check "while an upgrade runs, no pane is read and no line comes" test "$(count "prompt: " "$(run)")|$(reads)" = "0|0"
kill "${WAITER}" 2>/dev/null || true; wait "${WAITER}" 2>/dev/null || true; WAITER=""; rm -f "${P}/.swarm/upgrade.pid"
check "a poll leaves no pane text behind, in .swarm/lead or TMPDIR" \
  test "$(find "${P}/.swarm/lead/reads" -type f 2>/dev/null | wc -l | tr -d ' ')|$(find "${TMPDIR}" -name 'swarm-reads.*' | wc -l | tr -d ' ')" = "0|0"

# Slow reads that use up the poll's budget leave the agents not read first in line for the next poll.
fresh; printf '%s\n' "w:p1 ${A}" "w:p2 sww-slow-a" "w:p3 sww-slow-b" "w:p4 sww-slow-c" > "${P}/.swarm/state/tab"
printf '{"name":"sww-slow-%s","agent_status":"blocked","pane_id":"w:p%s"},' a 2 b 3 c 4 > "${ROOT}/agents"  # vacuous-test: ok, objects the stub joins into its list
printf '{"name":"%s","agent_status":"blocked","pane_id":"w:p1"}' "${A}" >> "${ROOT}/agents"
touch "${ROOT}/hang-w:p2" "${ROOT}/hang-w:p3" "${ROOT}/hang-w:p4"; cp "${FX}/prompt.txt" "${ROOT}/pane.txt"
check "three hung reads first in herdr's list use up the budget, so the fourth agent is not read" \
  test "$(count "prompt: ${A} " "$(run)")" = 0
check "the next poll reads it first and gives its line" test "$(count "prompt: ${A} (prompt)" "$(run)")" = 1
rm -f "${ROOT}"/hang-*; echo "w:p1 ${A}" > "${P}/.swarm/state/tab"

# A pane read that fails keeps the line: the poll after it, with the pane back, is quiet too. The status
# changes between the polls, so each one reads the pane.
fresh; agent idle prompt.txt
out="$(run)"
check "an idle agent on a prompt gives its line" test "$(count "prompt: ${A} (prompt)" "${out}")" = 1
agent blocked prompt.txt; rm -f "${ROOT}/pane.txt"
check "a poll whose pane read fails is quiet" test "$(count "prompt: " "$(run)")" = 0
check "it keeps the line in the lead's queue" grep -qF "prompt: ${A} (prompt)" "${P}/.swarm/lead/seen"
cp "${FX}/prompt.txt" "${ROOT}/pane.txt"; : > "${ROOT}/reads"
check "the poll after it, with the pane back, is quiet" test "$(count "prompt: " "$(run)")" = 0
check "and reads the pane it could not read" test "$(reads)" = 1

# So does a poll whose herdr agent list fails.
touch "${ROOT}/list-fails"
check "a poll whose herdr agent list fails is quiet" test "$(count "prompt: " "$(run)")" = 0
check "it keeps the line in the lead's queue too" grep -qF "prompt: ${A} (prompt)" "${P}/.swarm/lead/seen"
rm -f "${ROOT}/list-fails"
check "the poll after it, with the list back, is quiet" test "$(count "prompt: " "$(run)")" = 0
# And a poll whose list herdr gives but no parser can read.
touch "${ROOT}/list-garbled"
check "a poll whose herdr agent list does not parse is quiet" test "$(count "prompt: " "$(run)")" = 0
check "it keeps the line in the lead's queue as well" grep -qF "prompt: ${A} (prompt)" "${P}/.swarm/lead/seen"
rm -f "${ROOT}/list-garbled"

# An API error while a wait naming the agent runs: that wait resumes it.
fresh; agent idle api-error.txt
fake wait --stall "${A}"
check "an API error while a swarm.sh wait names the agent gives no line" test "$(count "prompt: " "$(run)")" = 0
kill "${WAITER}" 2>/dev/null || true; wait "${WAITER}" 2>/dev/null || true; WAITER=""
check "once that wait ends, the API error gives its line" test "$(count "prompt: ${A} (api-error)" "$(run)")" = 1
# An API error that already woke the lead stays seen while a wait runs, so it does not wake the lead again.
fake wait --stall "${A}"
check "a wait started on an API error already seen is quiet" test "$(count "prompt: " "$(run)")" = 0
check "and the line stays in the lead's queue" grep -qF "prompt: ${A} (api-error)" "${P}/.swarm/lead/seen"
kill "${WAITER}" 2>/dev/null || true; wait "${WAITER}" 2>/dev/null || true; WAITER=""
check "once that wait ends, the same API error does not wake the lead again" test "$(count "prompt: " "$(run)")" = 0
# A wait's flag is no agent name: agent_name makes --lead s--lead.
A=s--lead; fresh; agent idle api-error.txt; echo "w:p1 ${A}" > "${P}/.swarm/state/tab"
fake wait --lead 600000
check "a swarm.sh wait --lead hides no API error of an agent named s--lead" test "$(count "prompt: ${A} (api-error)" "$(run)")" = 1
kill "${WAITER}" 2>/dev/null || true; wait "${WAITER}" 2>/dev/null || true; WAITER=""
A="${AGENT}"; echo "w:p1 ${A}" > "${P}/.swarm/state/tab"

# Manual mode on a ready story's builder: close its pane, then no_agent_exit's restart or hold.
fresh; agent blocked manual.txt
{ echo ---; echo "kind: code"; echo "status: ready"; echo ---; echo; echo "# ${A}"; } > "${B}/${A}.md"
printf '2026-10-27\tcode\t%s\tclaude\topus\t-\tsession-1\n' "${A}" > "${P}/.swarm/agents.tsv"
out="$(run)"
check "manual mode on a ready story's builder closes its pane, then holds it (no worktree to restart)" \
  grep -qxF "prompt: ${A} (manual), exit: herdr pane close w:p1 then swarm.sh hold ${A} <reason>" <<< "${out}"

# The same for a story whose slug is past AGENT_NAME_MAX (32): its builder's name is the slug cut short.
LONG=sww-a-story-whose-slug-runs-past-the-name-cap; A="${LONG:0:32}"
fresh; agent blocked manual.txt; echo "w:p1 ${LONG}" > "${P}/.swarm/state/tab"
{ echo ---; echo "kind: code"; echo "status: ready"; echo ---; echo; echo "# ${LONG}"; } > "${B}/${LONG}.md"
printf '2026-10-27\tcode\t%s\tclaude\topus\t-\tsession-2\n' "${A}" >> "${P}/.swarm/agents.tsv"
out="$(run)"
check "manual mode on a long-slug story's builder holds the story by its full slug" \
  grep -qxF "prompt: ${A} (manual), exit: herdr pane close w:p1 then swarm.sh hold ${LONG} <reason>" <<< "${out}"
# Two stories whose slugs share the cut: herdr's name says neither, so no story is named.
{ echo ---; echo "kind: code"; echo "status: ready"; echo ---; echo; echo "# ${LONG}-2"; } > "${B}/${LONG}-2.md"
fresh; agent blocked manual.txt
check "manual mode on a cut name two stories share names no story" \
  grep -qxF "prompt: ${A} (manual), exit: the user turns manual mode off in pane w:p1" <<< "$(run)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
