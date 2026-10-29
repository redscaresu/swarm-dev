#!/usr/bin/env bash
# wait_lead_test.sh — swarm.sh wait --lead: it returns once the lead's queue gains a held or escalated
# story, or with merge = human a review item whose PR head is green, printing one line per new item and
# logging one lead-woken line each; at its timeout it fails with nothing printed. What it last saw is kept
# across runs, and a new run takes over from an earlier one. gh is a stub on PATH answering the PR's
# head and its check runs from ${FX}; herdr is a stub listing a running conductor, read once per poll for
# its agent list (no-agent: lines, no_agent_test.sh). Both log each call.
# ln is a stub that fails while ${FX}/ln.fail exists and waits as many seconds as ${FX}/ln.slow holds.
# ps is the real one. A read of every process (-A) drops the real swarm.sh merge lines, which other tests on the
# machine make, and adds the lines of ${FX}/ps: a fixture process list.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
lpid=""
trap 'stop; fix_stop; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; FX="${ROOT}/fx"; B="${P}/docs/stories"
H=1111111111111111111111111111111111111111; H2=2222222222222222222222222222222222222222; URL=https://github.com/o/r/pull/7
mkdir -p "${P}/.claude/swarm" "${B}" "${P}/.swarm/state" "${ROOT}/bin" "${FX}"
git -C "${P}" init -q

# gh: pr view <n> prints ${FX}/head.<n> or else ${FX}/head, waits as many seconds as ${FX}/view.slow
# holds (a slow gh), and fails while ${FX}/view.fail exists; a head's check runs are ${FX}/<sha>.checks
# or else ${FX}/checks; its commit statuses are ${FX}/<sha>.status, else none. For the main-red cases, where the project has the origin
# o/r: repo view names it, pr list has no PR, the default branch is ${FX}/default, a branch exists and has
# the head ${FX}/base.<branch> while that file does, and ci_gate fixed reads any commit as one that changes
# bin/x, any compare as one behind by nothing, and no workflow run. run view reads any Actions run as
# completed, its failed log one FAIL line.
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
  "repo view") echo o/r ;;
  "pr list") echo '[]' ;;
  "run view") case "$*" in *--log-failed*) printf 'test\tstep\t2026-10-29T00:00:00.0000000Z FAIL TestRed\n' ;; *) echo completed ;; esac ;;
  api*) case "$*" in
          *check-runs*) sha="${path#*/commits/}"; sha="${sha%%/*}"
                        cat "${FX}/${sha}.checks" 2>/dev/null || cat "${FX}/checks" ;;
          */status*) sha="${path#*/commits/}"; sha="${sha%%/*}"
                     cat "${FX}/${sha}.status" 2>/dev/null || echo '{"total_count":0,"statuses":[]}' ;;
          */git/matching-refs/heads/*) b="${path#*/matching-refs/heads/}"; [ ! -e "${FX}/base.${b}" ] || echo "refs/heads/${b}" ;;
          *"--jq .default_branch"*) cat "${FX}/default" ;;
          # A fix-main run (it has SWARM_FIX_MAIN_LOG_SECONDS) reads ${FX}/base.<branch>.run when there is one.
          *"--jq .sha "*/commits/*) b="${path#*/commits/}"
                                    if [ -n "${SWARM_FIX_MAIN_LOG_SECONDS:-}" ] && [ -e "${FX}/base.${b}.run" ]; then cat "${FX}/base.${b}.run"
                                    else cat "${FX}/base.${b}"; fi ;;
          */commits/*) echo '{"files":[{"filename":"bin/x"}],"parents":[]}' ;;
          */compare/*) echo '{"behind_by":0}' ;;
          */actions/runs*) echo '{"total_count":0,"workflow_runs":[]}' ;;
          *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
        esac ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
# herdr: conduct-e is running, busy.
printf '#!/bin/sh\necho "$*" >> "%s"\n' "${ROOT}/herdr.log" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'STUB'
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"conduct-e","agent_status":"working","pane_id":"w:c"}]}}' ;;
  *) echo '{"result":{}}' ;;
esac
STUB
printf '#!/bin/sh\nFX="%s"\n' "${FX}" > "${ROOT}/bin/ln"
cat >> "${ROOT}/bin/ln" <<'STUB'
[ ! -e "${FX}/ln.fail" ] || exit 1
sleep "$(cat "${FX}/ln.slow" 2>/dev/null || echo 0)"
STUB
printf 'exec %s "$@"\n' "$(command -v ln)" >> "${ROOT}/bin/ln"
printf '#!/bin/sh\nFX="%s"; PS="%s"\n' "${FX}" "$(command -v ps)" > "${ROOT}/bin/ps"
cat >> "${ROOT}/bin/ps" <<'STUB'
case " $* " in
  # Less the real swarm.sh merges: other tests on the machine run them on o/r.
  *" -A "*) out="$("${PS}" "$@")" || exit $?
            printf '%s\n' "${out}" | grep -vF 'swarm.sh merge' || true
            cat "${FX}/ps" 2>/dev/null || true ;;
  *) exec "${PS}" "$@" ;;
esac
STUB
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr" "${ROOT}/bin/ln" "${ROOT}/bin/ps"
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

# fix_stop — KILL every fix-main run wait --lead started (main_red_fix), with its session: one left would
# write into the next case's board, or into ${ROOT} once the test has removed it.
fix_stop() {
  local p
  while read -r p; do kill -KILL -- "-${p}" "${p}" 2>/dev/null || true; done < <(awk '$6 ~ /^[0-9]+$/ { print $6 }' "${P}/.swarm/lead/fixes" 2>/dev/null)
}
# fresh [config line]... — a board with one held story, h, and nothing else; no events, no earlier run.
fresh() {
  stop; fix_stop; rm -f "${FX:?}/ps"
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

# --- main-red cases: each heads pass reads every base's head and its CI (lead_bases), and each poll prints one
# main-red: line per red base, from what the pass wrote and from events.tsv (main_red_lines). The project's
# origin is o/r here, whose default branch is main. A swarm.sh merge of a PR in o/r runs throughout these read
# cases (the ps fixture), so no fix-main run starts (main_red_fix); the fix cases below take it away.
B1=3333333333333333333333333333333333333333; B2=4444444444444444444444444444444444444444
git -C "${P}" remote add origin https://github.com/o/r.git
# merging <owner/repo> — ps lists a swarm.sh merge of PR 9 in <owner/repo>.
merging() { printf '99999 bash /x/bin/swarm.sh merge --head %s https://github.com/%s/pull/9\n' "${H}" "$1" > "${FX}/ps"; }
# based [config line]... — fresh, main the default branch, no branch on GitHub yet, and a merge into o/r running.
based() { fresh "$@"; rm -f "${FX}"/base.* "${FX}"/*.status; echo main > "${FX}/default"; merging o/r; }
# red_line <sha> <base> [exit] — the main-red: line for <sha> on <base> of o/r with test failed.
red_line() { echo "main-red: ${1:0:7} o/r $2 (test (failure)), exit: ${3:-wait for fix-main-${1:0:7}, which a fix-main run is writing and next then names first}"; }
# no_red_line — no main-red: line in the queue the last poll saved.
no_red_line() { ! grep -q '^main-red: ' "${P}/.swarm/lead/seen"; }
# status_only <state> <sha> — <sha>'s CI is one commit status, ci, in <state>, and no check run.
status_only() {
  echo '{"total_count":0,"check_runs":[]}' > "${FX}/$2.checks"
  printf '{"total_count":1,"statuses":[{"context":"ci","state":"%s","target_url":"u"}]}\n' "$1" > "${FX}/$2.status"
}

based; echo "${B1}" > "${FX}/base.main"; checks pending "${B1}"
lead 0
check "a base head whose CI is pending prints no main-red: line" test "$(out)|$(rc)" == "|1"
check "the heads pass read the default branch's head" grep -qxF "api --jq .sha repos/o/r/commits/main" "${ROOT}/gh.log"
again; checks failure "${B1}"; lead 0
check "once its CI concludes red, the next poll prints one main-red: line" test "$(out)|$(rc)" == "$(red_line "${B1}" main)|0"
check "it logs lead-woken for that line" grep -qx "lead-woken ${B1:0:7}" <<< "$(events)"
again; lead 0
check "the same red wakes no one again" test "$(out)|$(rc)" == "|1"
again; checks success "${B1}"; lead 0
check "a red the read found goes once a rerun turns the same head green" no_red_line

based; echo "${B2}" > "${FX}/base.main"; checks success "${B2}"
lead 0
check "a green base head prints no main-red: line" test "$(out)|$(rc)" == "|1"
again; checks failure "${B2}"; lead 0
check "a head read green that a rerun turns red prints main-red: on the next poll" test "$(out)|$(rc)" == "$(red_line "${B2}" main)|0"

# A red main a merge logged (fix_main's main-red line and story), then the base's head goes green with no
# main-green written by anyone else: the read clears it.
based; echo "${B1}" > "${FX}/base.main"; checks failure "${B1}"
item "fix-main-${B1:0:7}" "kind: code" "status: ready" "touches: [.]"
printf '%s\tmain-red\t%s\t-\to/r main test (failure)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${B1}" >> "${P}/.swarm/events.tsv"
lead 0
check "a red main merge logged prints one main-red: line naming its fix-main story" \
  test "$(out)|$(rc)" == "$(red_line "${B1}" main "build fix-main-${B1:0:7}, which next names first")|0"
again; echo "${B2}" > "${FX}/base.main"; checks success "${B2}"; lead 0
check "once the base's head reads green, the read logs main-green for that red" \
  grep -qx "main-green ${B2} o/r main ${B1}" <<< "$(awk -F'\t' '{ print $2, $3, $5 }' "${P}/.swarm/events.tsv")"
check "that poll prints nothing new" test "$(out)|$(rc)" == "|1"
check "and gone from the queue" no_red_line
check "the red's unstarted fix-main story is retired" test ! -e "${B}/fix-main-${B1:0:7}.md"

# A base whose CI posts only commit statuses: no check run is needed for its head to read green.
based; echo "${B1}" > "${FX}/base.main"; status_only failure "${B1}"
lead 0
check "a base whose only CI is a failed commit status prints main-red:" test "$(out)|$(rc)" == \
  "main-red: ${B1:0:7} o/r main (ci (failure)), exit: wait for fix-main-${B1:0:7}, which a fix-main run is writing and next then names first|0"
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

based; echo "${B1}" > "${FX}/base.main"; checks pending "${B1}"
lead SWARM_LEAD_HEADS_EVERY=30 2500
check "the polls between heads passes read no base head" test "$(grep -c 'commits/main' "${ROOT}/gh.log")" == 1

# --- main-red fix cases: each poll starts swarm.sh _fix-main, detached, for a red base head that no main-red
# covers (main_red_fix), and the run writes the fix-main story (main_red_run, fix_main).
# red_run <sha> — <sha>'s one check run, test, failed in Actions run 99.
red_run() {
  printf '{"total_count":1,"check_runs":[{"name":"test","status":"completed","conclusion":"failure","html_url":"%s"}]}\n' \
    https://github.com/o/r/actions/runs/99/job/1 > "${FX}/$1.checks"
}
# fix_runs <sha> — how many runs wait --lead started for <sha>, from their log.
fix_runs() { local n; n="$(grep -c '^run ' "${P}/.swarm/lead/fix-main-${1:0:7}.log" 2>/dev/null)" || true; echo "${n:-0}"; }
# fix_pid <sha> — the pid of <sha>'s last run, as wait --lead wrote it.
fix_pid() { awk -v s="$1" '$3 == s { print $6 }' "${P}/.swarm/lead/fixes" 2>/dev/null; }
# fix_done <sha> — true once <sha>'s last run has exited; false when it has not within 60 s, or there is none.
fix_done() {
  local i p
  p="$(fix_pid "$1")"; [[ "${p}" =~ ^[0-9]+$ ]] || return 1
  for ((i = 0; i < 600; i++)); do kill -0 "${p}" 2>/dev/null || return 0; sleep 0.1; done
  return 1
}
# fix_kill <sha> — KILL <sha>'s last run with its session, and see it gone.
fix_kill() {
  local p
  p="$(fix_pid "$1")"; [[ ! "${p}" =~ ^[0-9]+$ ]] || kill -KILL -- "-${p}" "${p}" 2>/dev/null || true
  must "the run was killed" fix_done "$1"
}
# one_of <value> <a> <b> — <value> is <a> or <b>.
one_of() { [[ "$1" == "$2" || "$1" == "$3" ]]; }
# main_reds <sha> — how many main-red lines events.tsv holds for <sha>.
main_reds() { awk -F'\t' -v s="$1" '$2 == "main-red" && $3 == s' "${P}/.swarm/events.tsv" 2>/dev/null | wc -l | tr -d ' '; }
F="${B}/fix-main-${B1:0:7}.md"

based; rm -f "${FX:?}/ps"; echo "${B1}" > "${FX}/base.main"; red_run "${B1}"
built="$(red_line "${B1}" main "build fix-main-${B1:0:7}, which next names first")"
lead 0
# A run that writes the story before the poll reads the board gives the build exit at once.
check "a red head no main-red covers prints main-red:, waiting on its story or naming it" \
  one_of "$(out)|$(rc)" "$(red_line "${B1}" main)|0" "${built}|0"
check "the poll started one _fix-main run" test "$(fix_runs "${B1}")" == 1
check "the run ends" fix_done "${B1}"
check "the run wrote fix-main-<sha>" test -f "${F}"
check "and logged one main-red for that head" test "$(main_reds "${B1}")" == 1
check "the story names the failed check" grep -qx 'red: test (failure)' "${F}"
check "and its Actions run" grep -qF 'The failed runs: https://github.com/o/r/actions/runs/99.' "${F}"
# shellcheck disable=SC2016 # the backticks are the story's own
check "and says no swarm.sh merge wrote a fix for the red" grep -qF 'no `swarm.sh merge` wrote a fix-main story for' "${F}"
check "it is the project's own repo's story, with no repo: line" bash -c "! grep -q '^repo:' '${F}'"
again; lead 0
check "the next poll's one main-red: line names the story as the exit" \
  test "$(grep '^main-red: ' "${P}/.swarm/lead/seen")" == "${built}"
check "and starts no second run" test "$(fix_runs "${B1}")" == 1
check "and logs no second main-red" test "$(main_reds "${B1}")" == 1

based; echo "${B1}" > "${FX}/base.main"; red_run "${B1}"
lead 0
check "with a swarm.sh merge into o/r running, the line waits on the story" test "$(out)|$(rc)" == "$(red_line "${B1}" main)|0"
check "and no run starts" test "$(fix_runs "${B1}")" == 0
merging o/rx; again; lead 0
check "a merge into another repo, o/rx, holds no run back" test "$(fix_runs "${B1}")" == 1
check "and that run ends" fix_done "${B1}"
check "having written the story" test -f "${F}"

# fix_main's lock is held, so a run waits on it and writes nothing before it is killed.
based; rm -f "${FX:?}/ps"; echo "${B1}" > "${FX}/base.main"; red_run "${B1}"
mkdir -p "${P}/.swarm/fix-main.o-r-main.lock"
lead SWARM_LOCK_WAIT=60 0
check "a run starts" test "$(fix_runs "${B1}")" == 1
again; lead SWARM_LOCK_WAIT=60 0
check "a poll while it runs starts no second run" test "$(fix_runs "${B1}")" == 1
fix_kill "${B1}"
check "killed before it writes, it leaves no story" test ! -e "${F}"
again; lead SWARM_LOCK_WAIT=60 0
check "the next poll starts the run again" test "$(fix_runs "${B1}")" == 2
check "and the line, unchanged, wakes no one" test "$(out)|$(rc)" == "|1"
fix_kill "${B1}"
again; lead 0
check "after two failed runs the line names the lead's check" test "$(out)|$(rc)" == \
  "$(red_line "${B1}" main "read .swarm/lead/fix-main-${B1:0:7}.log, as no run wrote fix-main-${B1:0:7}, then fix main by hand")|0"
check "and no third run starts" test "$(fix_runs "${B1}")" == 2
rmdir "${P}/.swarm/fix-main.o-r-main.lock"

# A merge's fix_main logs the red while a run waits on the lock: once it has the lock, the run writes nothing.
based; rm -f "${FX:?}/ps"; echo "${B1}" > "${FX}/base.main"; red_run "${B1}"
mkdir -p "${P}/.swarm/fix-main.o-r-main.lock"
lead SWARM_LOCK_WAIT=60 0
printf '%s\tmain-red\t%s\t-\to/r main test (failure)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${B1}" >> "${P}/.swarm/events.tsv"
rmdir "${P}/.swarm/fix-main.o-r-main.lock"
check "a run whose red a merge logged while it waited ends" fix_done "${B1}"
check "having written no story" test ! -e "${F}"
check "and no second main-red" test "$(main_reds "${B1}")" == 1

# The base moved after the pass read it: the run writes nothing, and the polls before the next heads pass
# start no other run and count no failure.
based; rm -f "${FX:?}/ps"; echo "${B1}" > "${FX}/base.main"; red_run "${B1}"; echo "${B2}" > "${FX}/base.main.run"
# Seen already, so the run's polls go on: its first read wakes no one.
mkdir -p "${P}/.swarm/lead"; printf '%s\n' "held: h (paused)" "$(red_line "${B1}" main)" > "${P}/.swarm/lead/seen"
start SWARM_LEAD_HEADS_EVERY=3600 120000
check "a run that finds the base moved since the pass ends" fix_done "${B1}"
check "having written no story" test ! -e "${F}"
check "its log says why" grep -qx "stale: main is at ${B2:0:7} now, not ${B1:0:7}; no fix-main story written" \
  "${P}/.swarm/lead/fix-main-${B1:0:7}.log"
s="$(seen_id)"; must "a poll read after the run" first_read "${s}"; s="$(seen_id)"; must "and another" first_read "${s}"
check "the polls before the next heads pass start no second run" test "$(fix_runs "${B1}")" == 1
check "nor name the lead's check" bash -c "! grep -q '^main-red: .*, exit: read ' '${P}/.swarm/lead/seen'"
stop
git -C "${P}" remote remove origin; rm -f "${FX}"/base.* "${FX}/default" "${FX}"/*.status

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

# --- /swarm's wait arm starts wait --lead and handles a held: or escalated: line at once.
arm="$(awk '/^   - `wait <agent>`/ { s = 1; print; next } s && /^   - `/ { exit } s' "$(dirname "${SWARM}")/../commands/swarm.md")"
check "the wait arm names wait --lead" grep -q 'swarm.sh wait --lead' <<< "${arm}"
# shellcheck disable=SC2016 # the backticks are the Markdown's own
check "the wait arm does the escalated <slug> step for held: or escalated: without waiting for next" \
  grep -q 'do the `escalated <slug>` step for that slug at once, without waiting for `next`' <<< "${arm}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
