#!/usr/bin/env bash
# wait_lead_test.sh — swarm.sh wait --lead: it returns once the lead's queue gains a held or escalated
# story, or with merge = human a review item whose PR head is green, printing one line per new item and
# logging one lead-woken line each; at its timeout it fails with nothing printed. What it last saw is kept
# across runs, and a new run takes over from an earlier one. gh is a stub on PATH answering the PR's
# head and its check runs from ${FX}; herdr is a stub listing a running conductor, read once per poll for
# its agent list (no-agent: lines, no_agent_test.sh). Both log each call. A review agent whose start was
# cut short is started again by the poll alone, within its three tries, through a real swarm.sh review-agent.
# ln is a stub that fails while ${FX}/ln.fail exists and waits as many seconds as ${FX}/ln.slow holds.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
lpid=""; tpid=""
trap 'stop; [[ -z "${tpid}" ]] || kill "${tpid}" 2>/dev/null; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; FX="${ROOT}/fx"; B="${P}/docs/stories"
H=1111111111111111111111111111111111111111; H2=2222222222222222222222222222222222222222; URL=https://github.com/o/r/pull/7
mkdir -p "${P}/.claude/swarm" "${B}" "${P}/.swarm/state" "${ROOT}/bin" "${FX}"
git -C "${P}" init -q

# gh: pr view <n> prints ${FX}/head.<n> or else ${FX}/head, waits as many seconds as ${FX}/view.slow
# holds (a slow gh), and fails while ${FX}/view.fail exists; a head's check runs are ${FX}/<sha>.checks
# or else ${FX}/checks; its commit statuses are ${FX}/<sha>.status, else none. For the main-red cases, where
# the project has the origin o/r: repo view names it (and fails while ${FX}/repo.fail exists), pr list lists
# ${FX}/prs.json's PRs, else none, the default branch is ${FX}/default, a branch exists and has the head ${FX}/base.<branch> while that file
# does, and ci_gate fixed reads any commit as one that changes bin/x, any compare as one behind by nothing,
# no workflow run, the base's rules as ${FX}/rules while that file does (else the read fails, so every check
# counts) and no classic protection.
printf '#!/bin/sh\nFX="%s"; LOG="%s"\n' "${FX}" "${ROOT}/gh.log" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "${LOG}"
for a in "$@"; do path="${a}"; done
case "$1 $2" in
  # It reads a line of stdin, as a real gh may, so a caller that leaves its stdin open loses a line.
  "pr view") read -r _ || true
             sleep "$(cat "${FX}/view.slow" 2>/dev/null || echo 0)"
             [ ! -e "${FX}/view.fail" ] || { echo "gh: HTTP 502" >&2; exit 1; }
             cat "${FX}/head.$3" 2>/dev/null || cat "${FX}/head" ;;
  # The heads pass's read of the open story PRs, once the project has an origin (the main-red and stuck: cases).
  "repo view") [ ! -e "${FX}/repo.fail" ] || exit 1; echo o/r ;;
  "pr list") cat "${FX}/prs.json" 2>/dev/null || echo '[]' ;;
  api*) case "$*" in
          *check-runs*) sha="${path#*/commits/}"; sha="${sha%%/*}"
                        cat "${FX}/${sha}.checks" 2>/dev/null || cat "${FX}/checks" ;;
          */status*) sha="${path#*/commits/}"; sha="${sha%%/*}"
                     cat "${FX}/${sha}.status" 2>/dev/null || echo '{"total_count":0,"statuses":[]}' ;;
          */git/matching-refs/heads/*) b="${path#*/matching-refs/heads/}"; [ ! -e "${FX}/base.${b}" ] || echo "refs/heads/${b}" ;;
          *"--jq .default_branch"*) cat "${FX}/default" ;;
          *"--jq .sha "*/commits/*) cat "${FX}/base.${path#*/commits/}" ;;
          */commits/*) echo '{"files":[{"filename":"bin/x"}],"parents":[]}' ;;
          */compare/*) echo '{"behind_by":0}' ;;
          */actions/runs*) echo '{"total_count":0,"workflow_runs":[]}' ;;
          */rules/branches/*) [ -e "${FX}/rules" ] || { echo "stub: no rules" >&2; exit 1; }; cat "${FX}/rules" ;;
          */protection) echo 'Branch not protected (HTTP 404)' >&2; exit 1 ;;
          *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
        esac ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
# herdr: conduct-e is running, busy, or the agents ${FX}/agents lists. An agent start (the review agent
# wait --lead starts again) gets a pane, and its brief reads as taken. A pane's process info is ${FX}/pi.
printf '#!/bin/sh\necho "$*" >> "%s"\nFX="%s"\n' "${ROOT}/herdr.log" "${FX}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'STUB'
case "$1 $2" in
  "agent list") cat "${FX}/agents" 2>/dev/null || echo '{"result":{"agents":[{"name":"conduct-e","agent_status":"working","pane_id":"w:c"}]}}' ;;
  "pane process-info") cat "${FX}/pi" 2>/dev/null || echo '{"result":{}}' ;;
  "--version ") echo "herdr 0.9.5" ;;
  "tab create") echo '{"result":{"root_pane":{"pane_id":"w:r1"}}}' ;;
  "pane split") echo '{"result":{"pane":{"pane_id":"w:r2"}}}' ;;
  "agent prompt") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "workspace list") echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  *) echo '{"result":{}}' ;;
esac
STUB
printf '#!/bin/sh\nFX="%s"\n' "${FX}" > "${ROOT}/bin/ln"
cat >> "${ROOT}/bin/ln" <<'STUB'
[ ! -e "${FX}/ln.fail" ] || exit 1
sleep "$(cat "${FX}/ln.slow" 2>/dev/null || echo 0)"
STUB
printf 'exec %s "$@"\n' "$(command -v ln)" >> "${ROOT}/bin/ln"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${ROOT}/bin/claude"
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr" "${ROOT}/bin/ln" "${ROOT}/bin/claude"
printf 'w:c conduct-e\n' > "${P}/.swarm/state/e"

# checks <conclusion> [sha] — the head's (or <sha>'s) one check run, completed with <conclusion>, or
# in progress for pending.
checks() {
  local st=completed c="\"$1\""; [[ "$1" != pending ]] || { st=in_progress; c=null; }
  printf '{"total_count":1,"check_runs":[{"name":"test","status":"%s","conclusion":%s,"html_url":"u"}]}\n' "${st}" "${c}" \
    > "${FX}/${2:+$2.}checks"
}
item() { { echo ---; printf '%s\n' "${@:2}"; echo ---; echo; echo "# $1"; } > "${B}/$1.md"; }
held() { item "$1" "kind: lead" "status: ready" "escalated_from: code" "held_for: $2"; }
escalated() { item "$1" "kind: lead" "status: ready" "escalated_from: code"; }

# fresh [config line]... — a board with one held story, h, and nothing else; no events, no earlier run.
fresh() {
  stop
  rm -f "${B}"/*.md "${P}/.swarm/events.tsv" "${FX}/view.fail" "${FX}/view.slow" "${FX}/ln.slow" "${FX}/ln.fail" "${FX}"/head.* "${FX}"/*.checks; rm -rf "${P}/.swarm/lead" "${ROOT}"/*.log
  again
  printf '%s\n' "$@" > "${P}/.claude/swarm/config"
  echo "${H}" > "${FX}/head"; checks success
  held h paused
}
# again — forget the last run's output and exit code, keeping what it saw.
again() { rm -f "${ROOT}/out" "${ROOT}/rc"; }
# lead [VAR=value]... <timeout-ms> — swarm.sh wait --lead in the foreground, polling every second, inside
# herdr; output in ${ROOT}/out, exit code in ${ROOT}/rc. Every poll is a heads pass (SWARM_LEAD_HEADS_EVERY=1),
# so the gh counts below are a pass's, unless a case sets it longer.
lead() {
  local envs=()
  while [[ "$1" == [A-Z]*=* ]]; do envs+=("$1"); shift; done
  (cd "${P}" && env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" HERDR_ENV=1 HERDR_PANE_ID=w:me SWARM_LEAD_POLL=1 SWARM_LEAD_HEADS_EVERY=1 \
    ${envs[@]+"${envs[@]}"} bash "${SWARM}" wait --lead "$1" > "${ROOT}/out" 2>&1) 2>/dev/null && echo 0 > "${ROOT}/rc" || echo $? > "${ROOT}/rc"
}
# must <what> <command>... — count a FAIL when the command is false, and say nothing when it is true.
must() { local what="$1"; shift; "$@" || { echo "FAIL ${what}"; fails=$((fails + 1)); }; }
# seen_id — the inode of the run's seen file, which every read replaces (mv), or nothing before the first.
# shellcheck disable=SC2012 # one fixed path; stat -c and stat -f differ between Linux and macOS
seen_id() { { ls -i "${P}/.swarm/lead/seen" 2>/dev/null || true; } | awk '{ print $1 }'; }
# first_read [seen id] — wait until the run has read the board once more than the id says: its seen file
# is a new one, written when a read ends. A fixed sleep is not that: a slow gh or a loaded runner reads
# later, and a read that lands after the case changed the board, the head or the checks sees the changed
# ones, not the ones the case starts from. False when the run exits (its rc file) or 60 s pass without
# one: a run that dies before it reads is not one that read.
first_read() {
  local i
  for ((i = 0; i < 600; i++)); do
    [[ "$(seen_id)" == "$1" ]] || return 0
    [[ ! -e "${ROOT}/rc" ]] || return 1
    sleep 0.1
  done
  return 1
}
# start [VAR=value]... <timeout-ms> — lead in the background, once it has read the board.
start() {
  local before
  before="$(seen_id)"
  lead "$@" &
  lpid=$!
  must "the run read the board once" first_read "${before}"
}
# reads — how many times the run has read PR 7's head.
reads() { grep -c '^pr view 7 ' "${ROOT}/gh.log" 2>/dev/null || true; }
# polls <n> — wait until the run has begun <n> more reads of PR 7's head; after a change, polls 2 waits
# for a read that began after it to end, and polls n for n - 1 of them. False when 60 s pass first; true
# at once when the run has exited.
polls() {
  local want i
  want=$(( $(reads) + $1 ))
  for ((i = 0; i < 600; i++)); do [[ $(reads) -ge ${want} || -e "${ROOT}/rc" ]] && return 0; sleep 0.1; done
  return 1
}
# logged <text> <n> — true once gh's log holds <n> lines with <text>; false if the run exits first or 30 s
# pass.
logged() {
  local i
  for ((i = 0; i < 300; i++)); do
    [[ "$(grep -c "$1" "${ROOT}/gh.log" 2>/dev/null || true)" -lt $2 ]] || return 0
    [[ ! -e "${ROOT}/rc" ]] || return 1
    sleep 0.1
  done
  return 1
}
# returned <tenths> — true once wait --lead has exited, within <tenths> of a second.
returned() {
  local i
  for ((i = 0; i < $1; i++)); do [[ ! -e "${ROOT}/rc" ]] || { lpid=""; return 0; }; sleep 0.1; done
  return 1
}
# freeze <pid> — stop a process, then everything under it, top down, printing each pid: a stopped
# process forks nothing, so no child is born after its parent's children were listed.
freeze() { local c; kill -STOP "$1" 2>/dev/null || return 0; echo "$1"; for c in $(pgrep -P "$1"); do freeze "${c}"; done; }
# stop — end a background run, swarm.sh and the subshells around it, even one that never took the lock,
# and see each of its processes gone within 5 s. One left would share the next case's .swarm/lead.
stop() {
  local pids i
  [[ -z "${lpid}" ]] && return 0
  pids="$(freeze "${lpid}" | paste -sd, -)"
  # shellcheck disable=SC2086 # one pid per word
  kill -KILL ${pids//,/ } 2>/dev/null || true
  wait "${lpid}" 2>/dev/null || true; lpid=""
  for ((i = 0; i < 50; i++)); do ps -p "${pids}" > /dev/null 2>&1 || return 0; sleep 0.1; done
  echo "FAIL stop left the run's processes alive: ${pids}"; fails=$((fails + 1))
}
out() { cat "${ROOT}/out"; }
rc() { cat "${ROOT}/rc" 2>/dev/null; }
events() { awk -F'\t' '{ print $2 " " $3 }' "${P}/.swarm/events.tsv" 2>/dev/null || true; }

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
nothing_yet() { [[ ! -e "${ROOT}/rc" && -z "$(out)" && -z "$(events)" ]]; }

# --- held and escalated stories.
# The run takes its lock 2.5 s late, so its first read is later than a fixed wait after start would be.
fresh; escalated x; echo 2.5 > "${FX}/ln.slow"
start 20000
check "a story held before it started does not wake it" nothing_yet
held x paused
check "an escalated story held since returns within two polls" returned 25
check "it prints held: <slug> (<cause>) and exits 0" test "$(out)|$(rc)" == "held: x (paused)|0"
check "it logs one lead-woken line for it" test "$(events)" == "lead-woken x"
rm -f "${FX}/ln.slow"

# --- what lands between two runs wakes the second at once.
again; held y paused
start 20000
check "an item that appears between two runs wakes the second at once" returned 5
check "the second run prints only that item" test "$(out)|$(rc)" == "held: y (paused)|0"

# --- one run at a time: a new one takes over.
fresh
(cd "${P}" && env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" SWARM_LEAD_POLL=1 bash "${SWARM}" wait --lead 20000 \
  > "${ROOT}/out.a" 2>&1 && echo 0 > "${ROOT}/rc.a" || echo $? > "${ROOT}/rc.a") 2>/dev/null &
apid=$!; must "the earlier run read the board once" first_read ""
# The new run is waited on itself: the earlier one rewrites seen every poll, so start would return on that.
lead 20000 &
lpid=$!
saw() { local i; for ((i = 0; i < 600; i++)); do grep -q "$1" "${ROOT}/out" 2>/dev/null && return 0; sleep 0.1; done; return 1; }
must "the new run took over" saw 'stopping the earlier run'
for ((i = 0; i < 30; i++)); do [[ ! -e "${ROOT}/rc.a" ]] || break; sleep 0.1; done
check "a new wait --lead stops the earlier one" test -e "${ROOT}/rc.a"
check "the earlier one ends with nothing printed" test ! -s "${ROOT}/out.a"
wait "${apid}" 2>/dev/null || true
must "the new run read the board once" first_read "$(seen_id)"
check "the new one says it took over" grep -q 'stopping the earlier run' "${ROOT}/out"
alive() { ps -p "$(cat "$1" 2>/dev/null || echo 0)" > /dev/null 2>&1; }
check "the new one holds the pid file" alive "${P}/.swarm/lead/pid"
held z paused
check "the new one watches" returned 25
check "the new one prints what landed" test "$(grep -v '^swarm:' "${ROOT}/out")" == "held: z (paused)"
check "its pid file is gone once it returns" test ! -e "${P}/.swarm/lead/pid"

fresh; touch "${FX}/ln.fail"
lead 20000 &
lpid=$!
check "when the pid file cannot be made, it stops instead of spinning" returned 30
check "it says it cannot write the pid file" grep -q 'cannot write .*/lead/pid' "${ROOT}/out"
stop; rm -f "${FX}/ln.fail"

# --- a run's first read with no .swarm/lead/seen: a LEAD_QUIET kind is saved unprinted, any other line prints.
# fresh holds h; s waits on d, which it shares no file with, so next has an idle: line for s.
fresh "merge = human"
item s "kind: code" "status: blocked" "depends_on: [d]" "touches: [a.sh]"
item d "kind: code" "status: ready" "touches: [b.sh]"
IDLE="idle: s waits on d but shares no touches part with it and needs nothing from it"
lead 0
check "a held: line prints nothing on a run's first read" test -z "$(grep '^held: ' "${ROOT}/out")"
check "an idle: line prints nothing on a run's first read" test -z "$(grep '^idle: ' "${ROOT}/out")"
check "with nothing else, that first read wakes no one" test "$(out)|$(rc)" == "|1"
check "it saves both lines as seen" test "$(grep -cxF -e "held: h (paused)" -e "${IDLE}" "${P}/.swarm/lead/seen")" == 2
# A started story with a worktree and a builder record, whose builder closed and is not listed: a
# no-agent: line, which is no LEAD_QUIET kind.
rm -rf "${P}/.swarm/lead"; again
item wl-quiet "kind: code" "status: ready" "touches: [c.sh]"
mkdir -p "${ROOT}/proj-wt/wl-quiet"; printf '2026-10-01\tcode\twl-quiet\tclaude\tsonnet\thigh\ts-wl-quiet\n' > "${P}/.swarm/agents.tsv"
printf '%s\t%s\twl-quiet\t-\tok\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" story "$(date -u +%Y-%m-%dT%H:%M:%SZ)" close >> "${P}/.swarm/events.tsv"
lead 0
check "a no-agent: line prints on a run's first read, alone" test "$(out)|$(rc)" == \
  "no-agent: wl-quiet, exit: swarm.sh restart wl-quiet, or swarm.sh hold wl-quiet <reason>|0"
rm -rf "${P}/.swarm/events.tsv" "${P}/.swarm/agents.tsv" "${ROOT}/proj-wt"

fresh; lead 0900
check "a timeout with a leading zero is decimal, not octal" test "$(out)|$(rc)" == "|1"

# --- SWARM_LEAD_POLL and the timeout.
fresh; lead SWARM_LEAD_POLL=0 1000
check "SWARM_LEAD_POLL=0 is refused" grep -q 'SWARM_LEAD_POLL is whole seconds, at least 1' "${ROOT}/out"
fresh; lead SWARM_LEAD_HEADS_EVERY=0 1000
check "SWARM_LEAD_HEADS_EVERY=0 is refused" grep -q 'SWARM_LEAD_HEADS_EVERY is whole seconds, at least 1' "${ROOT}/out"
fresh; t0=${SECONDS}; lead SWARM_LEAD_POLL=30 2000
check "the last sleep stops at the timeout, not a full poll later" test $((SECONDS - t0)) -le 4 -a "$(rc)" == 1

fresh; item c "kind: code" "status: ready"
start 20000
item c "kind: lead" "status: ready" "escalated_from: code"
check "a story turned lead with escalated_from: and no held_for: wakes it" returned 25
check "it prints escalated: <slug>" test "$(out)|$(rc)" == "escalated: c|0"

# --- review items, by merge mode.
fresh "merge = human"; checks failure; item r "kind: code" "status: review" "prs: ${URL}"
start 20000
sleep 1
check "with merge = human, a review story whose head is red does not wake it" nothing_yet
checks success
check "once its head is green, it wakes" returned 25
check "it prints merge: <slug> <PR URL>" test "$(out)|$(rc)" == "merge: r ${URL}|0"
check "it logs lead-woken for the review story" test "$(events)" == "lead-woken r"

# Each gh pr view takes 1.3 s, longer than the 1 s between polls: the cases below wait for reads (start,
# polls), not for time.
fresh "merge = human"; echo 1.3 > "${FX}/view.slow"; item r "kind: code" "status: review" "prs: ${URL}"
start 120000
must "it polled" polls 3
check "ci_gate reads a green head once, however many polls" test "$(grep -c "${H}/check-runs" "${ROOT}/gh.log")" == 1
echo "${H2}" > "${FX}/head"; must "it polled" polls 2
check "a new head is read again" test "$(grep -c "${H2}/check-runs" "${ROOT}/gh.log")" == 1
touch "${FX}/view.fail"; must "it polled" polls 2; rm -f "${FX}/view.fail"; must "it polled" polls 2
check "a green review item whose head cannot be read for a poll does not wake it after" nothing_yet
check "a cached green head outlives a poll that could not read it" test "$(grep -c "${H2}/check-runs" "${ROOT}/gh.log")" == 1
stop

# The heads pass: PR heads are read on a run's first read and then once every SWARM_LEAD_HEADS_EVERY
# seconds (30 here: room for two polls on a loaded runner), and the polls between read only .swarm/lead/heads.
fresh "merge = human"; checks failure; item r "kind: code" "status: review" "prs: ${URL}"
start SWARM_LEAD_HEADS_EVERY=30 90000
n=$(grep -c '' "${ROOT}/gh.log")
checks success
must "a poll ended" first_read "$(seen_id)"; must "a poll ended" first_read "$(seen_id)"
check "the polls between two heads passes make no gh call" test "$(grep -c '' "${ROOT}/gh.log")" == "${n}"
check "a head that turned green after a heads pass does not wake it before the next pass" nothing_yet
check "it wakes on the next heads pass" returned 600
check "the wake came from that pass, the head's second read, and printed merge:" test "$(reads)|$(out)|$(rc)" == "2|merge: r ${URL}|0"
stop

# A green verdict is dropped once its item leaves review: back in review with a red head before the next
# pass, it waits for that pass instead of waking on the old verdict.
fresh "merge = human"; item r "kind: code" "status: review" "prs: ${URL}"
lead 1000   # a first run only records what it saw: merge: r is in LEAD_SEEN
again; start SWARM_LEAD_HEADS_EVERY=30 90000
check "the run's first heads pass found r green" grep -qxF "green merge: r ${URL}" "${P}/.swarm/lead/heads"
item r "kind: code" "status: ready" "prs: ${URL}"
must "a poll ended" first_read "$(seen_id)"; must "a poll ended" first_read "$(seen_id)"
echo "${H2}" > "${FX}/head"; checks failure "${H2}"; item r "kind: code" "status: review" "prs: ${URL}"
must "a poll ended" first_read "$(seen_id)"; must "a poll ended" first_read "$(seen_id)"
check "an item back in review with a red head before the next pass does not wake it" nothing_yet
stop

# A story a close kept (kept:, its PR not reviewed) is listed as kept, never offered to merge, though
# its head is green; once review clears kept:, it is.
fresh "merge = human"; lead 1000   # a first run only records what it saw
again; item k "kind: code" "status: review" "prs: ${URL}" "kept: 2026-10-22 close stalled (not reviewed)"
lead 5000
check "a kept green PR wakes it as kept: <slug> <url> (not reviewed), never as merge:" \
  test "$(grep -c "^kept: k ${URL} (not reviewed)$" "${ROOT}/out")|$(grep -c '^merge: k' "${ROOT}/out")" == "1|0"
(cd "${P}" && env -u SWARM_PROJECT bash "${SWARM}" review k "${URL}" >/dev/null 2>&1) || true
again; lead 5000
check "once review k clears kept:, it is offered to merge" test "$(out)|$(rc)" == "merge: k ${URL}|0"

fresh "merge = human"; echo 1.3 > "${FX}/view.slow"; echo "${H2}" > "${FX}/head.8"; checks pending "${H2}"
item r "kind: code" "status: review" "prs: ${URL} ${URL%/*}/8"
start 120000
# start returned after the first read: it cached the first PR's green head, and the other is pending
checks failure "${H}"; checks success "${H2}"
check "it read the cached head again before it would wake" logged "${H}/check-runs" 2
must "it polled" polls 1   # the read that did it has decided
check "a cached green head that a re-run turned red does not wake it when the item's other PR goes green" nothing_yet
check "a head the fresh re-read finds red is gone from LEAD_GREEN after that poll" \
  test "$(grep -c "^${URL} ${H}$" "${P}/.swarm/lead/green")" == 0
# No longer cached, PR 7's head is read red in each poll's first pass, which then stops before PR 8: a
# fresh re-read comes only after a first pass that read PR 8 green. So PR 8 is read no more, however
# late the counts are taken.
v8=$(grep -c '^pr view 8 ' "${ROOT}/gh.log" || true)
must "a poll ended" first_read "$(seen_id)"; must "a poll ended" first_read "$(seen_id)"
check "the next poll makes no fresh re-read for it" test "$(grep -c '^pr view 8 ' "${ROOT}/gh.log" || true)" == "${v8}"
stop

fresh "merge = human"
start 20000
item r "kind: code" "status: review" "prs: ${URL}"; item r2 "kind: code" "status: review" "prs: ${URL}"
check "two review items turning green at once wake it" returned 25
check "it prints both, so gh never reads the board's lines" test "$(out)" == "merge: r ${URL}"$'\n'"merge: r2 ${URL}"
stop

fresh "merge = human"
start 20000
item r "kind: code" "status: review" "prs: ${URL}" "costs: money"
check "with merge = human, a green costs: money review story wakes it too" returned 25
check "it prints merge: <slug> <PR URL> for it" test "$(out)|$(rc)" == "merge: r ${URL}|0"
stop

fresh "merge = agent"
start 4000
item r "kind: code" "status: review" "prs: ${URL}"
check "with merge = agent, a green review story does not wake it, and it times out" returned 60
check "with merge = agent it times out non-zero with nothing printed" test "$(out)|$(rc)" == "|1"
check "with merge = agent nothing is logged" test -z "$(events)"

fresh "merge = agent"
start 20000
item r "kind: code" "status: review" "prs: ${URL}" "costs: money"
check "with merge = agent, a green costs: money review story wakes it: the user merges it" returned 25
check "it prints merge: <slug> <PR URL> for it under merge = agent" test "$(out)|$(rc)" == "merge: r ${URL}|0"
stop

fresh "merge = agent"; mkdir -p "${P}/docs/epics"
start 20000
item r "kind: code" "status: review" "prs: ${URL}" "costs: money"
printf -- '---\nstatus: review\nprs: %s\n---\n\n# e\n' "${URL}" > "${P}/docs/epics/e.md"
check "a held PR that a story and its epic both list wakes it" returned 25
check "it prints the held PR once, under the story" test "$(out)|$(rc)" == "merge: r ${URL}|0"
stop; rm -rf "${P}/docs/epics"

# The first item listing a held PR is not green (its other PR is red): a later one listing only it still wakes it.
fresh "merge = agent"; mkdir -p "${P}/docs/epics"; echo "${H2}" > "${FX}/head.8"; checks failure "${H2}"
start 20000
item r "kind: code" "status: review" "prs: ${URL} ${URL%/*}/8" "costs: money"
printf -- '---\nstatus: review\nprs: %s\n---\n\n# e\n' "${URL}" > "${P}/docs/epics/e.md"
check "a held PR whose first item is not green still wakes it through a later green one" returned 25
check "it prints the later item" test "$(out)|$(rc)" == "merge: e ${URL}|0"
stop; rm -rf "${P}/docs/epics"

# --- under merge = human, the lead merges a reviewed PR whose HLD grants merge:
# with review-wl-granted gone (herdr lists conduct-e only) after an ok start and its PR open, it needs the
# lead. A slug and URL no other test's processes name: a swarm.sh merge or tell on them anywhere on the
# machine would make the story look busy (no_agent_busy reads the real ps).
GURL=https://github.com/wl-owner/wl-granted/pull/7
# granted <grants> — story wl-granted in review, under epic ge, under the agreed HLD g with grants:
# <grants>; its build, its review agent's ok start and the handover (review, then the builder's close)
# on record, its worktree kept, the review's head pending, no findings yet.
granted() {
  mkdir -p "${P}/docs/epics" "${P}/docs/hld" "${P}/.swarm/reviews" "${P}/.swarm/briefs"
  printf -- '---\nstatus: agreed\ngrants: %s\n---\n\n# g\n' "$1" > "${P}/docs/hld/g.md"
  printf -- '---\nstatus: active\nhld: g\n---\n\n# ge\n' > "${P}/docs/epics/ge.md"
  item wl-granted "kind: code" "status: review" "prs: ${GURL}" "epic: ge"
  printf 'Review %s, the PR of story wl-granted, at its head %s, in this worktree.\n' "${GURL}" "${H}" > "${P}/.swarm/briefs/review-wl-granted.md"
  echo "${H}" > "${P}/.swarm/reviews/wl-granted.head"
  printf '2026-10-27T00:00:00Z\tstory\twl-granted\t-\tok\n2026-10-27T00:01:00Z\treview-agent\twl-granted\t-\tok\n' >> "${P}/.swarm/events.tsv"
  printf '2026-10-27T00:02:00Z\treview\twl-granted\t-\tok (%s)\n2026-10-27T00:03:00Z\tclose\twl-granted\t-\tok\n' "${GURL}" >> "${P}/.swarm/events.tsv"
  mkdir -p "${ROOT}/proj-wt/wl-granted"
  checks pending
}
fresh "merge = human"; granted "[merge]"
lead 0
check "a granted review story whose review agent went reaches wait --lead" test "$(out)|$(rc)" == \
  "no-review: wl-granted ${GURL}, exit: swarm.sh review-agent wl-granted ${GURL}, or the fallback reviewer|0"
fresh "merge = human"; granted "[epics, stories]"
lead 0
check "the same story with no merge grant (an ordinary handoff to the user) gives none" test "$(out)|$(rc)" == "|1"
rm -rf "${P}/docs/epics" "${P}/docs/hld" "${P}/.swarm/reviews" "${P}/.swarm/briefs" "${ROOT}/proj-wt"

# --- a review agent whose start was cut short: the poll starts its next try, within 3 tries in all.
# One board, a story per case, each ready with no prs: under epic e, whose conductor runs (so next only
# waits on it), built (its story start), its builder listed in a pane of its own, and its review starts
# on record as the case writes them. Their repo svc, beside the
# project, has a worktree for each at the PR's head, so a swarm.sh review-agent the poll runs reaches
# herdr's agent start. One poll reads every case, and a second checks that nothing more starts. Slugs
# and URLs no other test's processes name: no_agent_busy reads the real ps.
RBIN="${ROOT}/rbin"; GIT=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main)
mkdir -p "${RBIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${RBIN}/claude"   # review-agent reads its version
"${GIT[@]}" init -q --bare "${ROOT}/svc.git"
"${GIT[@]}" clone -q "${ROOT}/svc.git" "${ROOT}/svc" 2>/dev/null
"${GIT[@]}" -C "${ROOT}/svc" commit -q --allow-empty -m init && "${GIT[@]}" -C "${ROOT}/svc" push -q origin main
rurl() { echo "https://github.com/wl-owner/$1/pull/7"; }
began() { echo "(try $1 of 3) started"; }
ran() { echo "review-agent: review-$1 did not start; it ran nothing: pane not found (try $2 of 3)"; }
# cutshort <slug> [nobrief] [prs=<url>] <command> <outcome>... — story <slug> as above (with prs: <url>),
# then these review-agent events, a pair of words each; its review brief names its PR (rurl) unless nobrief.
# dash draws only an initialised board (init's README marker).
fresh; mkdir -p "${P}/.swarm/briefs" "${P}/docs/epics"; git -C "${ROOT}/svc" rev-parse HEAD > "${FX}/head"; : > "${B}/README.md"
printf -- '---\nstatus: active\n---\n\n# e\n' > "${P}/docs/epics/e.md"
agents='{"name":"conduct-e","agent_status":"working","pane_id":"w:c"}'; n=0
cutshort() {
  local slug="$1" brief=yes prs=(); shift
  [[ "$1" != nobrief ]] || { brief=""; shift; }
  [[ "$1" != prs=* ]] || { prs=("prs: ${1#prs=}"); shift; }
  n=$((n + 1))
  item "${slug}" "kind: code" "status: ready" "epic: e" "repo: svc" "touches: [x.sh]" ${prs[@]+"${prs[@]}"}
  printf '\n**Done when:**\n- it holds\n' >> "${B}/${slug}.md"
  "${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b "story/${slug}" "${ROOT}/svc-wt/${slug}"
  agents+=",{\"name\":\"${slug}\",\"agent_status\":\"working\",\"pane_id\":\"w:b${n}\"}"
  printf 'w:b%s %s\n' "${n}" "${slug}" > "${P}/.swarm/state/${slug}"
  [[ -z "${brief}" ]] || printf 'Review %s, the PR of story %s, at its head x, in this worktree.\n' "$(rurl "${slug}")" "${slug}" > "${P}/.swarm/briefs/review-${slug}.md"
  printf '2026-10-29T00:00:00Z\tstory\t%s\t-\tok\n' "${slug}" >> "${P}/.swarm/events.tsv"
  while [[ $# -gt 1 ]]; do printf '2026-10-29T00:01:00Z\t%s\t%s\t-\t%s\n' "$1" "${slug}" "$2" >> "${P}/.swarm/events.tsv"; shift 2; done
}
# Started again: a start that ran nothing on try 1; a command cut off in its nap after that try
# (main_signal's interrupted line), whose PR comes from the brief though prs: still names an older one;
# a restart killed before its command logged a line, which still spends try 2.
cutshort wlr-one review-agent:try "$(began 1)" review-agent "$(ran wlr-one 1)"
cutshort wlr-cut prs=https://github.com/wl-owner/wlr-cut/pull/6 review-agent:try "$(began 1)" review-agent "$(ran wlr-cut 1)" review-agent interrupted
cutshort wlr-killed review-agent:try "$(began 1)" review-agent "$(ran wlr-killed 1)" review-agent:restart "started (try 2 of 3)"
# Never started again: three tries spent; a failure outside the retry class (no (try suffix); no PR
# known (no prs:, no brief); two restarts killed so; and try 2 begun (its brief may have gone), then
# its command interrupted.
cutshort wlr-spent review-agent:try "$(began 1)" review-agent "$(ran wlr-spent 1)" review-agent:try "$(began 2)" \
  review-agent "$(ran wlr-spent 2)" review-agent:try "$(began 3)" review-agent "$(ran wlr-spent 3)"
cutshort wlr-out review-agent:try "$(began 1)" review-agent "review-agent: review-wlr-out did not start; herdr could not start the agent: agent_name_taken"
cutshort wlr-nourl nobrief review-agent:try "$(began 1)" review-agent "$(ran wlr-nourl 1)"
cutshort wlr-twice review-agent:try "$(began 1)" review-agent "$(ran wlr-twice 1)" review-agent:restart "started (try 2 of 3)" \
  review-agent:restart "started (try 3 of 3)"
cutshort wlr-mid review-agent:try "$(began 1)" review-agent "$(ran wlr-mid 1)" review-agent:try "$(began 2)" review-agent interrupted
# Nor while another poll holds the story's restart lock (polls overlap while a new wait --lead takes
# over), or the last restart's command still runs (its pid file names a live process: this test's own).
cutshort wlr-locked review-agent:try "$(began 1)" review-agent "$(ran wlr-locked 1)"
mkdir -p "${P}/.swarm/lead/review-wlr-locked.restart.lock"
cutshort wlr-running review-agent:try "$(began 1)" review-agent "$(ran wlr-running 1)" review-agent:restart "started (try 2 of 3)"
echo "$$" > "${P}/.swarm/lead/review-wlr-running.restart.pid"
printf '{"result":{"agents":[%s]}}\n' "${agents}" > "${FX}/agents"

# poll — one wait --lead read; a review agent it starts inherits its PATH, with the claude stub first.
poll() { again; lead PATH="${RBIN}:${ROOT}/bin:${PATH}" 0; }
# run <command>... — swarm.sh in the project, as the lead runs it, with the same stubs. A report deadline
# of 10 minutes: at 30 s, a loaded machine cuts dash's herdr read, and dash then draws no case at all.
run() { (cd "${P}" && env -u SWARM_PROJECT PATH="${RBIN}:${ROOT}/bin:${PATH}" HERDR_ENV=1 HERDR_PANE_ID=w:me COLUMNS=400 SWARM_REPORT_SECONDS=600 bash "${SWARM}" "$@" 2>&1); }
# starts [slug] — herdr's agent starts, of review-<slug> or of any agent.
starts() { grep -c "^agent start ${1:+review-$1 }" "${ROOT}/herdr.log" 2>/dev/null || true; }
restarts() { awk -F'\t' '$2 == "review-agent:restart"' "${P}/.swarm/events.tsv" | wc -l | tr -d ' '; }
said() { grep "^no-review: $1[ ,]" "${ROOT}/out" || true; }
today() { echo "no-review: $1 $(rurl "$1"), exit: swarm.sh review-agent $1 $(rurl "$1"), or the fallback reviewer"; }
again_at() { echo "no-review: $1 $(rurl "$1") (started $2 of 3), exit: swarm.sh review-agent $1 $(rurl "$1"), or the fallback reviewer"; }
revents() { awk -F'\t' -v s="$1" '$3 == s && $2 ~ /^review-agent/ { print $2 " " $5 }' "${P}/.swarm/events.tsv"; }
# restarted <slug> — the output file of the review-agent the poll started detached for <slug>, once that
# command has logged its outcome (main logs it as it exits) after the poll's restart line; at most 60 s.
# A command still running then is killed, by its pid, and it fails.
restarted() {
  local i pid
  for ((i = 0; i < 600; i++)); do
    if awk -F'\t' -v s="$1" '$3 == s && $2 == "review-agent:restart" { r = 1; d = 0; next }
                             r && $3 == s && $2 == "review-agent" { d = 1 } END { exit !d }' "${P}/.swarm/events.tsv"; then
      cat "${P}/.swarm/lead/review-$1.restart"; return 0
    fi
    sleep 0.1
  done
  for pid in $(pgrep -f "swarm.sh review-agent $1 " || true); do kill "${pid}" 2>/dev/null || true; done
  return 1
}

for c in next status dash; do run "${c}" > "${ROOT}/${c}.out" || true; done
check "next, status and dash read every case and start no agent, logging no restart" test "$(starts)|$(restarts)" == "0|4"
check "status prints a start cut short as today" grep -qxF "  $(today wlr-one)" "${ROOT}/status.out"
check "dash shows it too" grep -qF "$(today wlr-one)" "${ROOT}/dash.out"

poll
check "after a start that ran nothing on try 1, the poll starts try 2 and says so" test "$(said wlr-one)" == "$(again_at wlr-one 2)"
check "it ran swarm.sh review-agent detached, with its output in a file that has the agent's start" \
  grep -q '^review-wlr-one w:r[12] ' <<< "$(restarted wlr-one)"
check "herdr's log has one agent start, and the command's first try is 2 (SWARM_START_TRY), after the restart line" \
  test "$(starts wlr-one)|$(revents wlr-one | tail -3)" == "1|review-agent:restart started (try 2 of 3)
review-agent:try $(began 2)
review-agent ok"
check "a command cut off after try 1: the poll starts try 2, on its brief's PR" test "$(said wlr-cut)" == "$(again_at wlr-cut 2)"
check "and writes its restart line before the start's own lines; herdr's log has one agent start" \
  test "$(restarted wlr-cut > /dev/null; revents wlr-cut)|$(starts wlr-cut)" == "review-agent:try $(began 1)
review-agent $(ran wlr-cut 1)
review-agent interrupted
review-agent:restart started (try 2 of 3)
review-agent:try $(began 2)
review-agent ok|1"
check "a restart that left no line of its own still spent try 2: the poll starts try 3, once" \
  test "$(said wlr-killed)|$(restarted wlr-killed > /dev/null && starts wlr-killed)" == "$(again_at wlr-killed 3)|1"
check "after try 3 of 3 the poll starts nothing, and the line is as today" test "$(said wlr-spent)|$(starts wlr-spent)" == "$(today wlr-spent)|0"
check "a failure outside the retry class starts nothing, and the line is as today" test "$(said wlr-out)|$(starts wlr-out)" == "$(today wlr-out)|0"
check "with no PR URL known, nothing is started and the exit finds the PR first, as today" test "$(said wlr-nourl)|$(starts wlr-nourl)" == \
  "no-review: wlr-nourl, exit: gh pr list -R ${ROOT}/svc.git --head story/wlr-nourl, then swarm.sh review-agent wlr-nourl <PR URL>, or the fallback reviewer|0"
check "two restarts killed before a line of their own: the poll stops at 3 in all, and the line is as today" \
  test "$(said wlr-twice)|$(starts wlr-twice)" == "$(today wlr-twice)|0"
check "a restart lock another poll holds: nothing is started, and the line is as today" \
  test "$(said wlr-locked)|$(starts wlr-locked)" == "$(today wlr-locked)|0"
check "a last restart whose command still runs: no next try, and the line is as today" \
  test "$(said wlr-running)|$(starts wlr-running)" == "$(today wlr-running)|0"
check "a try cut off mid-start starts no agent and names the lead's check" test "$(said wlr-mid)|$(starts wlr-mid)" == \
  "no-review: wlr-mid $(rurl wlr-mid) (try 2 of 3 was cut off mid-start and may have sent the brief), exit: check that no pane holds review-wlr-mid (swarm.sh status, then swarm.sh tidy for an empty one), then swarm.sh review-agent wlr-mid $(rurl wlr-mid), or the fallback reviewer|0"
poll
check "a second poll starts nothing more, for any case" test "$(starts)|$(restarts)" == "3|7"
rm -rf "${P}/.swarm/briefs" "${P}/.swarm/reviews" "${P}/.swarm/agents.tsv" "${P}/.swarm/state"/wlr-* "${FX}/agents" "${B}/README.md" "${P}/docs/epics"

# --- no change: a short timeout.
fresh
start 3000
check "with no change it returns at its timeout" returned 50
check "at its timeout it exits non-zero and prints nothing" test "$(out)|$(rc)" == "|1"
check "events.tsv gains no line while it waits" test -z "$(events)"

# --- a running conductor does not hide a new held story, and a poll asks herdr only for its agent list.
fresh
start 20000
held n cleared-on-error
check "with a conductor running, a new held story still wakes it" returned 25
check "it prints the new held story" test "$(out)" == "held: n (cleared-on-error)"
# wait --lead 0 reads the queue exactly once.
rm -f "${ROOT}/herdr.log"; again; lead 0; again; lead 0
check "one herdr agent list per poll, no per-pane read" test "$(cat "${ROOT}/herdr.log")" == "agent list"$'\n'"agent list"

# --- close still finds a story's pane by its tab record, with that slug in wait --lead's seen file.
printf 'w:c conduct-e\nw:n n\n' > "${P}/.swarm/state/tab-n"
(cd "${P}" && env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" HERDR_ENV=1 HERDR_PANE_ID=w:me bash "${SWARM}" close n > /dev/null 2>&1) || true
check "close on a slug wait --lead saw still closes its pane" grep -qx 'pane close w:n' "${ROOT}/herdr.log"
check "and leaves wait --lead's seen file as it was" grep -qx 'held: n (cleared-on-error)' "${P}/.swarm/lead/seen"
rm -f "${P}/.swarm/state/tab-n"

# --- stuck: a builder idle on findings told to it on an unchanged PR head.
# Story wl-stuck is building PR 9 (head H), its builder live in pane w:b; Claude Code lists its session
# idle. stuck <head> <first seen, minutes ago> <tell, minutes ago or -> sets the PR's head, the head wait
# --lead first saw and when, and the findings tell; poll [VAR=value]... reads the queue once, as a run
# with no seen file, and prints its stuck: lines.
SURL=https://github.com/o/r/pull/9
SLINE="stuck: wl-stuck ${SURL} (findings pending 60 min), exit: swarm.sh tell wl-stuck resume <file>"
mins() { perl -MPOSIX -e 'print strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time - 60 * shift))' "$1"; }
stuck() {
  printf '[{"url":"%s","headRefName":"story/wl-stuck","headRefOid":"%s","mergeable":"MERGEABLE","createdAt":"%s","statusCheckRollup":[]}]\n' \
    "${SURL}" "$1" "$(mins 600)" > "${FX}/prs.json"
  mkdir -p "${P}/.swarm/lead"; echo "wl-stuck ${H} $(( $(date +%s) - 60 * $2 )) -" > "${P}/.swarm/lead/pr-heads"
  rm -f "${P}/.swarm/events.tsv"
  [[ "$3" == - ]] || printf '%s\ttell:findings\twl-stuck\tw:r\tok\n' "$(mins "$3")" > "${P}/.swarm/events.tsv"
}
poll() { rm -f "${P}/.swarm/lead/seen"; again; lead "$@" CLAUDE_STUB_AGENTS="${FX}/claude.json" 0; grep '^stuck: ' "${ROOT}/out" || true; }
fresh "merge = human"
git -C "${P}" remote add origin https://github.com/o/r.git
item wl-stuck "kind: code" "status: ready" "touches: [s.sh]"
printf 'w:b wl-stuck\n' > "${P}/.swarm/state/wl-stuck"
printf '2026-10-01\tcode\twl-stuck\tclaude\tsonnet\thigh\ts-wl-stuck\n' > "${P}/.swarm/agents.tsv"
echo '{"result":{"agents":[{"name":"conduct-e","agent_status":"working","pane_id":"w:c"},{"name":"wl-stuck","agent_status":"idle","pane_id":"w:b"}]}}' > "${FX}/agents"
echo '[{"sessionId":"s-wl-stuck","status":"idle"}]' > "${FX}/claude.json"
stuck "${H}" 90 61
check "an idle builder whose findings tell is past SWARM_STUCK_MINUTES on an unchanged head is stuck:" test "$(poll)" == "${SLINE}"
check "the line names N, the threshold, never the minutes elapsed" test "$(poll SWARM_STUCK_MINUTES=30)" == "${SLINE/pending 60 /pending 30 }"
first="$(poll)"; second="$(poll)"
check "two polls in a row print the same stuck: line text" test "${first}|${second}" == "${SLINE}|${SLINE}"
check "and the head's first sighting is kept, not reset" grep -q "^wl-stuck ${H} " "${P}/.swarm/lead/pr-heads"
stuck "${H}" 90 5
check "findings told 5 minutes ago on a head seen 90 minutes ago: no stuck: line" test -z "$(poll)"
stuck "${H}" 90 61
check "the same findings told 61 minutes ago: a stuck: line" test "$(poll)" == "${SLINE}"
stuck "${H2}" 90 61
check "a head that changed since the tell: no stuck: line" test -z "$(poll)"
check "and the new head is kept as first seen now" grep -q "^wl-stuck ${H2} " "${P}/.swarm/lead/pr-heads"
stuck "${H}" 90 -
check "no findings tell and no conflict: no stuck: line" test -z "$(poll)"
stuck "${H}" 90 61; printf '%s\tstory\twl-stuck\t-\tok\n' "$(mins 30)" >> "${P}/.swarm/events.tsv"
check "findings told to a build that has since been started again: no stuck: line" test -z "$(poll)"
# The builder declined every finding and the review passed on the same head: the PR waits on its merge.
stuck "${H}" 90 61; mkdir -p "${P}/.swarm/reviews"
printf 'head: %s\n\n## Findings\n\nnone\n' "${H}" > "${P}/.swarm/reviews/wl-stuck.md"
check "findings told on a head whose review has since passed: no stuck: line" test -z "$(poll)"
rm -f "${P}/.swarm/reviews/wl-stuck.md"
# GitHub reads mergeable UNKNOWN for a while: the same head keeps the line the lead saw, a new one drops it.
stuck "${H}" 90 61; poll > /dev/null
sed -i.bak 's/"MERGEABLE"/"UNKNOWN"/' "${FX}/prs.json"; again; lead CLAUDE_STUB_AGENTS="${FX}/claude.json" 0
check "an UNKNOWN mergeable on the same head keeps the stuck: line" grep -qxF "${SLINE}" "${P}/.swarm/lead/seen"
sed -i.bak "s/${H}/${H2}/" "${FX}/prs.json"; again; lead CLAUDE_STUB_AGENTS="${FX}/claude.json" 0
check "an UNKNOWN mergeable on a new head drops it" test -z "$(grep '^stuck: ' "${P}/.swarm/lead/seen")"
rm -f "${FX}/prs.json.bak"
stuck "${H}" 90 61
echo '[{"sessionId":"s-wl-stuck","status":"busy"}]' > "${FX}/claude.json"
check "a busy builder: no stuck: line" test -z "$(poll)"
echo '[{"sessionId":"s-wl-stuck","status":"idle"}]' > "${FX}/claude.json"
# A selected test run (make test, as select-tests.sh --run execs it) under the builder's pane shell, which is this shell.
bash -c 'exec -a make perl -e "sleep 600" test' & tpid=$!
printf '{"result":{"process_info":{"pane_id":"w:b","shell_pid":%s}}}\n' "$$" > "${FX}/pi"
check "a builder whose pane runs a test suite: no stuck: line" test -z "$(poll)"
kill "${tpid}" 2>/dev/null || true; wait "${tpid}" 2>/dev/null || true; tpid=""; rm -f "${FX}/pi"
mkdir -p "${CLAUDE_CONFIG_DIR}/projects/p"
printf '{"type":"user","message":{"content":[{"type":"tool_result","content":"started"}]},"toolUseResult":{"backgroundTaskId":"bx-1"}}\n' \
  > "${CLAUDE_CONFIG_DIR}/projects/p/s-wl-stuck.jsonl"
check "a builder whose transcript has a live background task: no stuck: line" test -z "$(poll)"
rm -rf "${CLAUDE_CONFIG_DIR}/projects/p"
check "with the task gone, the line is back" test "$(poll)" == "${SLINE}"
rm -f "${FX}/agents" "${FX}/prs.json" "${FX}/claude.json" "${P}/.swarm/state/wl-stuck" "${P}/.swarm/agents.tsv"
git -C "${P}" remote remove origin

# --- Gone story case (#691): a story file a merge deletes during a poll, between the board's list and its
# read, prints no sed: or awk: line, and the poll's other lines are as before. The race happens every
# time: first on PATH, ${ROOT}/gone/<tool> is the real awk or sed, except that the first call naming
# ${B}/v.md deletes it. Each tool in turn, so the poll's first awk read of v (stories_fm) and its first
# sed read (fm) each meet a file that is gone.
mkdir -p "${ROOT}/gone"
for t in awk sed; do
  rm -f "${ROOT}/gone"/*
  printf '#!/bin/sh\nREAL="%s"; V="%s"\n' "$(command -v "${t}")" "${B}/v.md" > "${ROOT}/gone/${t}"
  cat >> "${ROOT}/gone/${t}" <<'STUB'
for a in "$@"; do [ "${a}" != "${V}" ] || rm -f "${V}"; done
exec "${REAL}" "$@"
STUB
  chmod +x "${ROOT}/gone/${t}"
  fresh; lead 0   # a first run only records what it saw
  again; held y paused; item v "kind: code" "status: ready"
  lead PATH="${ROOT}/gone:${ROOT}/bin:${PATH}" 0
  check "a story gone at the poll's first ${t} read of it: it went" test ! -e "${B}/v.md"
  check "a story gone at the poll's first ${t} read of it: no sed: or awk: line" test -z "$(grep -E '(sed|awk):' "${ROOT}/out")"
  check "a story gone at the poll's first ${t} read of it: its other lines as before" test "$(out)|$(rc)" == "held: y (paused)|0"
done
# A story made unreadable at that first awk read (stories_fm) is not gone: that poll names it, as
# stories_fm's check of the board names a file there but unreadable.
rm -f "${ROOT}/gone"/*
printf '#!/bin/sh\nREAL="%s"; V="%s"\n' "$(command -v awk)" "${B}/v.md" > "${ROOT}/gone/awk"
cat >> "${ROOT}/gone/awk" <<'STUB'
for a in "$@"; do [ "${a}" != "${V}" ] || chmod 000 "${V}"; done
exec "${REAL}" "$@"
STUB
chmod +x "${ROOT}/gone/awk"
fresh; lead 0; again; held y paused; item v "kind: code" "status: ready"
lead PATH="${ROOT}/gone:${ROOT}/bin:${PATH}" 0
check "a story made unreadable during a poll: that poll names it" grep -qxF "swarm: cannot read ${B}/v.md" "${ROOT}/out"
chmod 644 "${B}/v.md"
rm -rf "${ROOT}/gone"

# --- main-red cases: each heads pass reads every base's head and its CI (lead_bases), and each poll prints one
# main-red: line per red base, from events.tsv or else from what the pass wrote (main_red_lines). The project's
# origin is o/r here, whose default branch is main.
B1=3333333333333333333333333333333333333333; B2=4444444444444444444444444444444444444444; B3=5555555555555555555555555555555555555555
git -C "${P}" remote add origin https://github.com/o/r.git
# based [config line]... — fresh, main the default branch, no branch on GitHub yet, and no build of a fix.
based() { fresh "$@"; rm -f "${FX}"/base.* "${FX}"/*.status "${FX}/repo.fail" "${FX}/rules"; rm -rf "${ROOT}/proj-wt"; echo main > "${FX}/default"; }
# red_line <sha> <base> [exit] — the main-red: line for <sha> on <base> of o/r with test failed.
red_line() { echo "main-red: ${1:0:7} o/r $2 (test (failure)), exit: ${3:-fix $2 by hand, as no fix-main story covers it yet}"; }
# red_out — the main-red: lines the run printed; red_seen — those in the queue the last poll saved.
red_out() { grep '^main-red: ' "${ROOT}/out" || true; }
red_seen() { grep '^main-red: ' "${P}/.swarm/lead/seen" || true; }
# no_red_line — no main-red: line in the queue the last poll saved.
no_red_line() { ! grep -q '^main-red: ' "${P}/.swarm/lead/seen"; }
# status_only <state> <sha> — <sha>'s CI is one commit status, ci, in <state>, and no check run.
status_only() {
  echo '{"total_count":0,"check_runs":[]}' > "${FX}/$2.checks"
  printf '{"total_count":1,"statuses":[{"context":"ci","state":"%s","target_url":"u"}]}\n' "$1" > "${FX}/$2.status"
}
# test_and_build <sha> <status> [conclusion] — <sha>'s two check runs: test failed, and build in <status>.
test_and_build() {
  local c=null; [[ -z "${3:-}" ]] || c="\"$3\""
  printf '{"total_count":2,"check_runs":[{"name":"test","status":"completed","conclusion":"failure","html_url":"u"},{"name":"build","status":"%s","conclusion":%s,"html_url":"u"}]}\n' \
    "$2" "${c}" > "${FX}/$1.checks"
}
# test_and_opt <sha> — <sha>'s two check runs, both finished: test passed, and opt failed.
test_and_opt() {
  printf '{"total_count":2,"check_runs":[{"name":"test","status":"completed","conclusion":"success","html_url":"u"},{"name":"opt","status":"completed","conclusion":"failure","html_url":"u"}]}\n' > "${FX}/$1.checks"
}
# woken <sha> — the lead-woken lines events.tsv holds for <sha>'s main-red: line.
woken() { grep -c "^lead-woken ${1:0:7}$" <<< "$(events)" || true; }
# logged_red <sha> [base] — the main-red line fix_main writes for a red at <sha> on o/r <base> (main) with test failed.
logged_red() { printf '%s\tmain-red\t%s\t-\to/r %s test (failure)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${2:-main}" >> "${P}/.swarm/events.tsv"; }

based; echo "${B1}" > "${FX}/base.main"; checks pending "${B1}"
lead 0
check "a base head whose CI is pending prints no main-red: line" test "$(out)|$(rc)" == "|1"
check "the heads pass read the default branch's head" grep -qxF "api --jq .sha repos/o/r/commits/main" "${ROOT}/gh.log"
again; test_and_build "${B1}" in_progress; lead 0
check "once its CI concludes red, the next poll prints one main-red: line naming the red check alone" \
  test "$(out)|$(rc)" == "$(red_line "${B1}" main)|0"
check "it logs lead-woken for that line" test "$(woken "${B1}")" == 1
again; test_and_build "${B1}" completed failure; lead 0
check "a red head whose other check fails later wakes no one a second time" test "$(out)|$(rc)|$(woken "${B1}")" == "|1|1"
# A run whose gh repo view fails cannot name the project's repo: the red the last pass found stands.
again; touch "${FX}/repo.fail"; lead 0; rm -f "${FX}/repo.fail"
check "a run that cannot name the repo keeps the red the last pass found, and wakes no one" \
  test "$(out)|$(rc)|$(grep -c '^main-red: ' "${P}/.swarm/lead/seen")" == "|1|1"
again; checks success "${B1}"; lead 0
check "a red the read found goes once a rerun turns the same head green" no_red_line

# The base moves to a head whose CI cannot be read (an answer that is not JSON): the red stands until it is.
based; echo "${B1}" > "${FX}/base.main"; checks failure "${B1}"; lead 0
again; echo "${B2}" > "${FX}/base.main"; echo nope > "${FX}/${B2}.checks"; lead 0
check "a red the read found stays while the base's new head's CI cannot be read" \
  test "$(out)|$(rc)|$(red_seen)" == "|1|$(red_line "${B1}" main)"
again; checks success "${B2}"; lead 0
check "and goes once that head's CI is read green" no_red_line

based; echo "${B2}" > "${FX}/base.main"; checks success "${B2}"
lead 0
check "a green base head prints no main-red: line" test "$(out)|$(rc)" == "|1"
again; checks failure "${B2}"; lead 0
check "a head read green that a rerun turns red prints main-red: on the next poll" test "$(out)|$(rc)" == "$(red_line "${B2}" main)|0"

# A green head whose rerun is still running when the 2-hour recheck window ends: the rerun is read until it
# concludes. The window's end is the line's epoch set back, in the file the pass wrote.
based; echo "${B1}" > "${FX}/base.main"; checks success "${B1}"; lead 0
again; checks pending "${B1}"; lead 0
sed -i.bak -E 's/ [0-9]+$/ 1/' "${P}/.swarm/lead/bases" && rm -f "${P}/.swarm/lead/bases.bak"
again; checks failure "${B1}"; lead 0
check "a rerun under way on a green head is read past the recheck window: its red prints main-red:" \
  test "$(out)|$(rc)" == "$(red_line "${B1}" main)|0"

# A red main a merge logged (fix_main's main-red line and story): the exit follows the story, a later red
# head on the base adds no line, and once the base's head goes green, with no main-green written by anyone
# else, the read clears it.
based; echo "${B1}" > "${FX}/base.main"; checks failure "${B1}"
item "fix-main-${B1:0:7}" "kind: code" "status: ready" "touches: [.]"; logged_red "${B1}"
lead 0
check "a red main merge logged prints one main-red: line naming its fix-main story" \
  test "$(out)|$(rc)" == "$(red_line "${B1}" main "build fix-main-${B1:0:7}, which next names first")|0"
again; mkdir -p "${ROOT}/proj-wt/fix-main-${B1:0:7}"; lead 0
check "once the fix-main story's build has begun, its exit is to wait for that build's merge" \
  test "$(red_out)" == "$(red_line "${B1}" main "wait for fix-main-${B1:0:7}, whose build has started, to merge")"
again; rm -rf "${ROOT}/proj-wt"; item "fix-main-${B1:0:7}" "kind: code" "status: review" "touches: [.]"; lead 0
check "a fix-main story in review keeps the exit to wait for its merge" \
  test "$(red_seen)" == "$(red_line "${B1}" main "wait for fix-main-${B1:0:7}, whose build has started, to merge")"
again; held "fix-main-${B1:0:7}" "runner down"; lead 0
check "a held fix-main story's exit sends the lead to its held: line" \
  test "$(red_out)" == "$(red_line "${B1}" main "fix-main-${B1:0:7} waits on the lead: handle its held: or escalated: line")"
again; echo "${B2}" > "${FX}/base.main"; checks failure "${B2}"; lead 0
check "a second red head on a base with a logged red adds no line of its own" \
  test "$(out)|$(rc)|$(grep -c '^main-red: ' "${P}/.swarm/lead/seen")" == "|1|1"
again; echo "${B3}" > "${FX}/base.main"; checks success "${B3}"; lead 0
check "once the base's head reads green, the read logs main-green for that red" \
  grep -qx "main-green ${B3} o/r main ${B1}" <<< "$(awk -F'\t' '{ print $2, $3, $5 }' "${P}/.swarm/events.tsv")"
check "and the line is gone from the queue" no_red_line
check "the red's unstarted fix-main story is retired" test ! -e "${B}/fix-main-${B1:0:7}.md"

# Two logged reds, on main and dev, each with a buildable fix-main story: next names the newest (main_red), and
# the older red's exit says so.
based; echo "${B1}" > "${FX}/base.main"; checks failure "${B1}"; echo "${B2}" > "${FX}/base.dev"; checks failure "${B2}"
item "fix-main-${B1:0:7}" "kind: code" "status: ready" "touches: [.]"; logged_red "${B1}"
item "fix-main-${B2:0:7}" "kind: code" "status: ready" "touches: [.]"; logged_red "${B2}" dev
lead 0
check "with two buildable fix-main stories, the newest red's exit is the one next names first" \
  grep -qxF "$(red_line "${B2}" dev "build fix-main-${B2:0:7}, which next names first")" "${ROOT}/out"
check "and the older red's exit names the story next names before it" \
  grep -qxF "$(red_line "${B1}" main "build fix-main-${B1:0:7}, which next names after fix-main-${B2:0:7}")" "${ROOT}/out"

# A base that requires its test check, with a logged red: a later head whose test passes while an optional check
# fails shows the red fixed, as ci_gate fixed judges it for reconcile, so the pass clears it; that poll prints the
# head's own line for the optional check, which no story covers.
based; echo "${B1}" > "${FX}/base.main"; checks failure "${B1}"
item "fix-main-${B1:0:7}" "kind: code" "status: ready" "touches: [.]"; logged_red "${B1}"
echo '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"test"}]}}]' > "${FX}/rules"
lead 0
again; echo "${B2}" > "${FX}/base.main"; test_and_opt "${B2}"; lead 0
check "a head red only on a check the base does not require clears the logged red, as reconcile does" \
  grep -qx "main-green ${B2} o/r main ${B1}" <<< "$(awk -F'\t' '{ print $2, $3, $5 }' "${P}/.swarm/events.tsv")"
check "and that poll prints the head's own main-red: line for the optional check, with the by-hand exit" \
  test "$(red_out)" == "main-red: ${B2:0:7} o/r main (opt (failure)), exit: fix main by hand, as no fix-main story covers it yet"
check "and the red's unstarted fix-main story is retired by that pass" test ! -e "${B}/fix-main-${B1:0:7}.md"

# A base whose CI posts only commit statuses: no check run is needed for its head to read green.
based; echo "${B1}" > "${FX}/base.main"; status_only failure "${B1}"
lead 0
check "a base whose only CI is a failed commit status prints main-red:" test "$(out)|$(rc)" == \
  "main-red: ${B1:0:7} o/r main (ci (failure)), exit: fix main by hand, as no fix-main story covers it yet|0"
again; status_only success "${B1}"; lead 0
check "once a rerun passes that status, with no check run, the line goes" no_red_line

based "base_branches = dev main"; echo "${B1}" > "${FX}/base.main"; echo "${B2}" > "${FX}/base.dev"
checks success "${B1}"; checks failure "${B2}"
lead 0
check "with base_branches = dev main, it reads dev, red here" test "$(out)|$(rc)" == "$(red_line "${B2}" dev)|0"
check "and reads neither the default branch nor main" bash -c "! grep -qE 'default_branch|commits/main' '${ROOT}/gh.log'"
# The default branch is trunk here, so a read of main can only come from base_branches.
based "base_branches = dev main"; echo trunk > "${FX}/default"; echo "${B1}" > "${FX}/base.main"; checks failure "${B1}"
lead 0
check "with no dev on GitHub, it reads main, the next base_branches entry" test "$(out)|$(rc)" == "$(red_line "${B1}" main)|0"

# The configured base changes to one GitHub lacks: the repo's lines stand, and the branch it had is not read,
# so a red there now is no alert.
based "base_branches = dev"; echo "${B1}" > "${FX}/base.dev"; checks success "${B1}"; lead 0
again; echo 'base_branches = main' > "${P}/.claude/swarm/config"; checks failure "${B1}"; lead 0
check "a base it cannot tell is not read on the branch it had: a red there now prints nothing" test "$(out)|$(rc)" == "|1"
check "and that branch's head was read once, in the run that had it as the base" test "$(grep -c 'commits/dev' "${ROOT}/gh.log")" == 1

# Reads that keep failing warn once on stderr, at SWARM_LEAD_PRS_WARN_AFTER heads passes in a row.
based; lead 0   # main has no head on GitHub: the head read fails
check "one failed base read under SWARM_LEAD_PRS_WARN_AFTER's default of 3 warns nothing" bash -c "! grep -q '^warning: ' '${ROOT}/out'"
again; lead SWARM_LEAD_PRS_WARN_AFTER=1 0
check "a base head it cannot read warns at SWARM_LEAD_PRS_WARN_AFTER failed passes" \
  grep -qF "warning: wait --lead could not read CI on main of o/r on 1 heads passes in a row" "${ROOT}/out"
again; rm -f "${FX}/default"; lead SWARM_LEAD_PRS_WARN_AFTER=1 0
check "a base it cannot tell warns the same way" grep -qF "warning: wait --lead could not tell the base of o/r on 1 heads passes in a row" "${ROOT}/out"

based; echo "${B1}" > "${FX}/base.main"; checks pending "${B1}"
lead SWARM_LEAD_HEADS_EVERY=30 4000
check "the polls between heads passes read no base head" test "$(grep -c 'commits/main' "${ROOT}/gh.log")" == 1
git -C "${P}" remote remove origin; rm -f "${FX}"/base.* "${FX}/default" "${FX}"/*.status

# --- /swarm's wait arm starts wait --lead and handles a held: or escalated: line at once.
arm="$(awk '/^   - `wait <agent>`/ { s = 1; print; next } s && /^   - `/ { exit } s' "$(dirname "${SWARM}")/../commands/swarm.md")"
check "the wait arm names wait --lead" grep -q 'swarm.sh wait --lead' <<< "${arm}"
# shellcheck disable=SC2016 # the backticks are the Markdown's own
check "the wait arm does the escalated <slug> step for held: or escalated: without waiting for next" \
  grep -q 'do the `escalated <slug>` step for that slug at once, without waiting for `next`' <<< "${arm}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
