#!/usr/bin/env bash
# wait_pr_cache_test.sh — concurrent swarm.sh wait-pr runs on one head share each poll's reads of the
# check runs, commit statuses and workflow runs (bin/lib/poll_cache.py, through ci_gate's pages): one
# read per poll between two waiters, two with the cache off; two that miss together make one read; a
# fetcher killed before it writes, or one whose read fails, leaves the other to read for itself; a new
# head is read from GitHub; a flip to green is seen within one poll, by a waiter out of step with the
# other too; a read the wait does not accept is not kept; a wait with the cache off (WAIT_PR_FRESH, as
# merge's own wait sets it) or a max age of 0 reads GitHub while a fresh entry is on disk; a read slower
# than the max age is not taken as fresh; and a lock older than the max age holds no one. Every case
# drives swarm.sh wait-pr from outside.
# gh is a stub on PATH: it logs "<epoch> <waiter> <args>" for every call to gh.log; pr view answers the
# head in ${FX}/head with the mergeable state UNKNOWN, so wait-pr reads the PR again before every pass,
# and each waiter's pr view count is its passes; check runs are one check, pending until ${FX}/green
# exists. With ${FX}/hold, a check-runs read writes "<the reading process's pid> <waiter> <its pid>" to
# ${FX}/arrived.<pid> and waits for ${FX}/release (30 s at most); with ${FX}/fail, the first check-runs
# read fails with HTTP 502; with ${FX}/short, check-runs answers one of a total_count of 2, a read the
# wait does not accept; with ${FX}/slow, a check-runs read takes that many seconds. One workflow, ci.yml
# (on: pull_request), always has a green pull_request run.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
PIDS=()
# The waiters left running when the file ends early are killed, then the temp dir goes.
cleanup() { [[ ${#PIDS[@]} -eq 0 ]] || kill "${PIDS[@]}" 2>/dev/null || true; stop_test_group; rm -rf "${ROOT}"; }
trap cleanup EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; FX="${ROOT}/fx"; URL=https://github.com/o/r/pull/7; CACHE="${P}/.swarm/poll-cache"
H=1111111111111111111111111111111111111111; H2=2222222222222222222222222222222222222222
mkdir -p "${P}/.claude/swarm" "${P}/docs/stories" "${ROOT}/bin"; : > "${P}/.claude/swarm/config"
git -C "${P}" init -q

printf '#!/usr/bin/env bash\nFX="%s"; LOG="%s"\n' "${FX}" "${ROOT}/gh.log" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$(date +%s) ${WAITER:--} $*" >> "${LOG}"
a="$*"
case "${a}" in
  "pr view"*) echo "$(cat "${FX}/head") UNKNOWN main OPEN 1" ;;
  *check-runs*)
    if [ -e "${FX}/hold" ]; then
      # The process that made this read: the first ancestor that is not a gh run with these arguments,
      # past swarm.sh's gh shim.
      g=${PPID}
      for _ in 1 2 3 4 5; do
        case "$(ps -o command= -p "${g}")" in *"${a}"*) g=$(ps -o ppid= -p "${g}" | tr -d ' ') ;; *) break ;; esac
      done
      echo "${g} ${WAITER:--} $$" > "${FX}/arrived.$$"
      for _ in $(seq 600); do [ ! -e "${FX}/release" ] || break; sleep 0.05; done
    fi
    if [ -e "${FX}/fail" ] && mkdir "${FX}/failed" 2>/dev/null; then echo "HTTP 502: Bad Gateway" >&2; exit 1; fi
    [ ! -e "${FX}/slow" ] || sleep "$(cat "${FX}/slow")"
    if [ -e "${FX}/short" ]; then echo '{"total_count":2,"check_runs":[{"name":"test","status":"completed","conclusion":"success"}]}'; exit 0; fi
    if [ -e "${FX}/green" ]; then s=completed c='"success"'; else s=in_progress c=null; fi
    printf '{"total_count":1,"check_runs":[{"name":"test","status":"%s","conclusion":%s}]}\n' "${s}" "${c}" ;;
  */status*) echo '{"total_count":0,"statuses":[]}' ;;
  *actions/runs*) sha="${a#*head_sha=}"; sha="${sha%%&*}"
    printf '{"total_count":1,"workflow_runs":[{"id":1,"path":".github/workflows/ci.yml","event":"pull_request","head_sha":"%s","status":"completed","conclusion":"success"}]}\n' "${sha}" ;;
  *actions/workflows*) echo '{"total_count":0,"workflows":[]}' ;;
  *commits/refs/pull/7/merge) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  *"contents/.github/workflows?ref="*) echo '[{"type":"file","name":"ci.yml","path":".github/workflows/ci.yml"}]' ;;
  *contents/.github/workflows/ci.yml*) printf 'name: ci\non: pull_request\njobs: {}\n' ;;
  *compare/main...*) echo '{"files":[{"filename":"bin/swarm.sh","status":"modified"}]}' ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
chmod +x "${ROOT}/bin/gh"

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }

# fresh <head> — a cold start: no cache, no logs, the PR's head <head>, its check pending.
fresh() {
  rm -rf "${FX}" "${CACHE}"; mkdir -p "${FX}"; : > "${ROOT}/gh.log"
  echo "$1" > "${FX}/head"
}
# reads [waiter] — the check-runs, status and workflow-runs reads in gh.log (of <waiter> alone, if named).
reads() {
  local w="${1:-[^ ]*}" e out=""
  for e in /check-runs /status 'actions/runs[?]'; do
    out="${out:+${out} }$(grep -cE "^[0-9]+ ${w} .*${e}" "${ROOT}/gh.log" || true)"
  done
  echo "${out}"
}
# passes <waiter> — the passes <waiter> made: its pr view reads, one before each pass (the PR is UNKNOWN).
passes() { grep -cE "^[0-9]+ $1 pr view" "${ROOT}/gh.log" || true; }
# await <seconds> <command>... — runs <command> every 0.1 s until it succeeds; fails after <seconds>.
await() {
  local end=$((SECONDS + $1)); shift
  until "$@"; do (( SECONDS < end )) || return 1; sleep 0.1; done
}
both_passed() { [[ $(passes a) -ge $1 && $(passes b) -ge $1 ]]; }
a_passed() { [[ $(passes a) -ge $1 ]]; }
runs_read() { [[ $(reads | cut -d' ' -f3) -ge $1 ]]; }
# ended <waiter> — the seconds from the flip (flipped, epoch) to <waiter>'s green line: its output's last write.
ended() { echo $(( $(perl -e 'print((stat shift)[9])' "${ROOT}/out.$1") - flipped )); }
arrived() { compgen -G "${FX}/arrived.*" > /dev/null; }
# start <waiter> [VAR=value]... [arg]... — swarm.sh wait-pr [arg]... ${URL} in the background as <waiter>,
# polling every 10 s and retrying after 10 s (the cache keeps 9 s) unless VARs say otherwise; its output in
# ${ROOT}/out.<waiter>, its pid in LAST.
start() {
  local w="$1" envs=(); shift
  while [[ "${1:-}" == [A-Z]*=* ]]; do envs+=("$1"); shift; done
  (cd "${P}" && exec env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" WAITER="${w}" SWARM_MERGE_POLL=10 \
    SWARM_WAIT_PR_RETRY=10 SWARM_MERGE_CI_SECONDS=240 ${envs[@]+"${envs[@]}"} bash "${SWARM}" wait-pr "$@" "${URL}" \
    > "${ROOT}/out.${w}" 2>&1) &
  LAST=$!; PIDS+=("${LAST}")
}
# finish <pid> — waits for a waiter; sets rc to its exit.
finish() { rc=0; wait "$1" || rc=$?; }
# kept <path part> — the cache entries whose read names <path part>.
kept() { grep -l -- "$1" "${CACHE}"/*.json 2>/dev/null | wc -l | tr -d ' '; }

# --- Two waiters started together on one head, pending for two polls, then green: with the cache on
# they make one read of each kind per poll between them, and both print green within a poll of the flip:
# a pass that starts after it may take an entry from just before it, and the next reads green.
fresh "${H}"
start a; pa=${LAST}; start b; pb=${LAST}
await 120 both_passed 2 || echo "warning: the waiters made under 2 passes each in 120 s"
touch "${FX}/green"; na=$(passes a); nb=$(passes b); flipped=$(date +%s)
finish "${pa}"; rc_a=${rc}; finish "${pb}"; rc_b=${rc}
is "cache on: both waiters end green" "0 0" "${rc_a} ${rc_b}"
m=$(passes a); (( $(passes b) <= m )) || m=$(passes b)
is "cache on: one check-runs, one status and one workflow-runs read per poll between them" "${m} ${m} ${m}" "$(reads)"
check "cache on: each waiter polled more than once" test "$(passes a)" -ge 2 -a "$(passes b)" -ge 2
check "flip: a prints green" grep -q '^green:' "${ROOT}/out.a"
check "flip: b prints green" grep -q '^green:' "${ROOT}/out.b"
check "flip: both print green within one poll of the flip, 2 passes after it at most (a $(( $(passes a) - na )), b $(( $(passes b) - nb )))" \
  test $(( $(passes a) - na )) -le 2 -a $(( $(passes b) - nb )) -le 2
check "flip: both print green within a poll of it, allowing 10 s for reads on a loaded machine ($(ended a) and $(ended b) s after it)" \
  test "$(ended a)" -le 20 -a "$(ended b)" -le 20

# --- Out of step: b starts about 12 s after a, both polling every 20 s (the cache keeps 19 s), so b's
# first read takes a's entries about 12 s old. It pauses that much less and polls in step with a: both
# print green within one poll of a flip made just after the second poll's last read (its workflow runs),
# b within a few seconds of a.
# (Out of step, b would print it about 12 s after a, 32 s after the flip.)
fresh "${H}"
start a SWARM_MERGE_POLL=20 SWARM_WAIT_PR_RETRY=20; pa=${LAST}
await 30 a_passed 1 || echo "warning: a made no pass in 30 s"
sleep 11; start b SWARM_MERGE_POLL=20 SWARM_WAIT_PR_RETRY=20; pb=${LAST}
await 60 runs_read 2 || echo "warning: the second poll made no workflow-runs read in 60 s"
touch "${FX}/green"; na=$(passes a); nb=$(passes b); flipped=$(date +%s)
finish "${pa}"; rc_a=${rc}; finish "${pb}"; rc_b=${rc}
end_a=$(ended a); end_b=$(ended b)
is "out of step: both waiters end green" "0 0" "${rc_a} ${rc_b}"
check "out of step: b took a's entries, making fewer reads than its passes" test "$(reads b | cut -d' ' -f1)" -lt "$(passes b)"
check "out of step: b prints green within 5 s of a (${end_a} and ${end_b} s after the flip)" test $((end_b - end_a)) -le 5 -a $((end_a - end_b)) -le 5
check "out of step: both print green within a poll of the flip, allowing 10 s for reads on a loaded machine" \
  test "${end_a}" -le 30 -a "${end_b}" -le 30
check "out of step: both print green within one poll of the flip, 2 passes after it at most (a $(( $(passes a) - na )), b $(( $(passes b) - nb )))" \
  test $(( $(passes a) - na )) -le 2 -a $(( $(passes b) - nb )) -le 2

# The same with the cache off (a retry pause of 1 s keeps nothing): two reads of each per poll.
fresh "${H}"
start a SWARM_WAIT_PR_RETRY=1; pa=${LAST}; start b SWARM_WAIT_PR_RETRY=1; pb=${LAST}
await 120 both_passed 2 || echo "warning: the waiters made under 2 passes each in 120 s"
touch "${FX}/green"
finish "${pa}"; rc_a=${rc}; finish "${pb}"; rc_b=${rc}
is "cache off: both waiters end green" "0 0" "${rc_a} ${rc_b}"
m=$(( $(passes a) + $(passes b) ))
is "cache off: each waiter makes its own reads, two of each per poll" "${m} ${m} ${m}" "$(reads)"
check "cache off: nothing is kept" test ! -e "${CACHE}"

# --- Two waiters that start cold together, the first check-runs read held at a barrier in the stub
# while the other is already polling: one read per endpoint between them. Polling every 20 s, the
# other waits up to 19 s for the held read, which is let go 1.5 s after both started.
fresh "${H}"; touch "${FX}/hold" "${FX}/green"
start a SWARM_MERGE_POLL=20 SWARM_WAIT_PR_RETRY=20; pa=${LAST}; start b SWARM_MERGE_POLL=20 SWARM_WAIT_PR_RETRY=20; pb=${LAST}
await 30 arrived && await 30 both_passed 1 || echo "warning: the waiters did not reach the barrier in 30 s"
sleep 1.5; touch "${FX}/release"
finish "${pa}"; rc_a=${rc}; finish "${pb}"; rc_b=${rc}
is "barrier: both waiters end green" "0 0" "${rc_a} ${rc_b}"
is "barrier: one read per endpoint between them" "1 1 1" "$(reads)"
is "barrier: one waiter reached the stub's check-runs read" 1 "$(compgen -G "${FX}/arrived.*" | wc -l | tr -d ' ')"

# A fetcher killed at the barrier, before it writes: the other waiter reads for itself within one poll.
fresh "${H}"; touch "${FX}/hold" "${FX}/green"
start a SWARM_MERGE_POLL=20 SWARM_WAIT_PR_RETRY=20; pa=${LAST}; start b SWARM_MERGE_POLL=20 SWARM_WAIT_PR_RETRY=20; pb=${LAST}
await 30 arrived && await 30 both_passed 1 || echo "warning: the waiters did not reach the barrier in 30 s"
sleep 1.5
read -r gate_pid held stub_pid < "$(compgen -G "${FX}/arrived.*" | head -1)"
other=a; [[ "${held}" != a ]] || other=b
rm "${FX}/hold"; kill -9 "${gate_pid}" "${stub_pid}"; killed=$(date +%s); touch "${FX}/release"
finish "${pa}"; rc_a=${rc}; finish "${pb}"; rc_b=${rc}
rc_other=${rc_a}; rc_held=${rc_b}; [[ "${other}" == a ]] || { rc_other=${rc_b}; rc_held=${rc_a}; }
is "killed fetcher: the other waiter ends green" 0 "${rc_other}"
check "killed fetcher: its own waiter ends, not green (${rc_held})" test "${rc_held}" -ne 0
check "killed fetcher: its read was the one killed" grep -q 'failed (exit 137)' "${ROOT}/out.${held}"
is "killed fetcher: the other waiter read check runs for itself" 1 "$(reads "${other}" | cut -d' ' -f1)"
at=$(grep -E "^[0-9]+ ${other} .*/check-runs" "${ROOT}/gh.log" | head -1 | cut -d' ' -f1)
check "killed fetcher: within one poll of the kill (read at ${at:-none}, killed at ${killed}, a poll is 20 s)" \
  test -n "${at}" -a "${at:-0}" -le $((killed + 20))

# The stub fails the held check-runs read: no entry is written, and the other waiter reads for itself.
fresh "${H}"; touch "${FX}/hold" "${FX}/green" "${FX}/fail"
start a SWARM_MERGE_POLL=20 SWARM_WAIT_PR_RETRY=20; pa=${LAST}; start b SWARM_MERGE_POLL=20 SWARM_WAIT_PR_RETRY=20; pb=${LAST}
await 30 arrived && await 30 both_passed 1 || echo "warning: the waiters did not reach the barrier in 30 s"
sleep 1.5
read -r _ held _ < "$(compgen -G "${FX}/arrived.*" | head -1)"
other=a; [[ "${held}" != a ]] || other=b
rm "${FX}/hold"; touch "${FX}/release"
finish "${pa}"; rc_a=${rc}; finish "${pb}"; rc_b=${rc}
is "failed read: both waiters end green, the failed one after a retry" "0 0" "${rc_a} ${rc_b}"
check "failed read: the failed waiter retried" grep -q '^retrying after .*HTTP 502' "${ROOT}/out.${held}"
is "failed read: the other waiter read check runs for itself" 1 "$(reads "${other}" | cut -d' ' -f1)"
# The write itself, at once: a check-runs read gh answered but the wait did not accept keeps no entry,
# though the cache was on for it (its folder made).
fresh "${H}"; touch "${FX}/short"
start a; finish "${LAST}"
is "unaccepted read: the wait ends with an error (exit 2)" 2 "${rc}"
check "unaccepted read: it says why" grep -q 'read 1 of 2' "${ROOT}/out.a"
check "unaccepted read: the cache was on" test -d "${CACHE}"
is "unaccepted read: no check-runs entry is kept" 0 "$(kept check-runs)"

# --- A wait on a new head of the same PR, while the old head's entries are fresh (kept 19 s), reads GitHub
# for it in its first pass.
fresh "${H}"; touch "${FX}/green"
start a SWARM_MERGE_POLL=20 SWARM_WAIT_PR_RETRY=20; finish "${LAST}"
is "new head: the wait on the old head ends green" 0 "${rc}"
echo "${H2}" > "${FX}/head"; : > "${ROOT}/gh.log"
start b SWARM_MERGE_POLL=20 SWARM_WAIT_PR_RETRY=20 --head "${H2}"; finish "${LAST}"
is "new head: the wait on the new head ends green" 0 "${rc}"
is "new head: in one pass, nothing of the old head's taken for it" 1 "$(passes b)"
is "new head: reads its check runs, status and workflow runs from GitHub" "1 1 1" \
  "$(grep -c "commits/${H2}/check-runs" "${ROOT}/gh.log") $(grep -c "commits/${H2}/status" "${ROOT}/gh.log") $(grep -c "head_sha=${H2}" "${ROOT}/gh.log")"

# --- A wait with the cache off reads all three while a fresh entry for the head is on disk: one with
# WAIT_PR_FRESH (merge's own wait on a head it made), and one whose 1 s poll makes the max age 0. A wait
# with the cache on, run between them, reads none of them, so the entries were fresh. Polls of 60 s keep
# each entry 59 s, longer than three waits take on a slow, loaded machine.
fresh "${H}"; touch "${FX}/green"
start a SWARM_MERGE_POLL=60 SWARM_WAIT_PR_RETRY=60; finish "${LAST}"
is "fresh entries: the first wait ends green" 0 "${rc}"
is "fresh entries: the first wait reads all three" "1 1 1" "$(reads)"
: > "${ROOT}/gh.log"; start b SWARM_MERGE_POLL=60 SWARM_WAIT_PR_RETRY=60 WAIT_PR_FRESH=1; finish "${LAST}"
is "cache off: a wait with WAIT_PR_FRESH ends green" 0 "${rc}"
is "cache off: a wait with WAIT_PR_FRESH reads all three, the entries fresh" "1 1 1" "$(reads)"
: > "${ROOT}/gh.log"; start a SWARM_MERGE_POLL=60 SWARM_WAIT_PR_RETRY=60; finish "${LAST}"
is "fresh entries: a wait with the cache on again reads none of them" "0 0 0" "$(reads)"
: > "${ROOT}/gh.log"; start b SWARM_MERGE_POLL=1 SWARM_WAIT_PR_RETRY=60; finish "${LAST}"
is "max age 0: a wait polling every 1 s ends green" 0 "${rc}"
is "max age 0: a wait polling every 1 s reads all three" "1 1 1" "$(reads)"

# --- A read slower than the max age is kept as old as it is, stamped with when it started: the next wait
# reads check runs again rather than take a snapshot from before it as fresh. Polls of 16 s keep each
# entry 15 s, and the first check-runs read takes 16.
fresh "${H}"; touch "${FX}/green"; echo 16 > "${FX}/slow"
start a SWARM_MERGE_POLL=16 SWARM_WAIT_PR_RETRY=16; finish "${LAST}"
rm "${FX}/slow"; : > "${ROOT}/gh.log"
start b SWARM_MERGE_POLL=16 SWARM_WAIT_PR_RETRY=16; finish "${LAST}"
is "slow read: the next wait ends green" 0 "${rc}"
is "slow read: the next wait reads check runs again" 1 "$(reads | cut -d' ' -f1)"

# --- A lock older than the max age holds no one, though its pid lives (a wait stopped with Ctrl-Z, a read
# that hangs) or it holds no pid (its reader killed before it wrote one): the next read goes ahead at
# once. The locks name a sleep this test starts, the first is empty, all are aged 300 s, and no entry is
# left. Polls of 181 s keep each entry 180 s, so a lock that held would hold each of the three reads that
# long, well past what one wait takes on a slow, loaded machine.
fresh "${H}"; touch "${FX}/green"
start a SWARM_MERGE_POLL=181 SWARM_WAIT_PR_RETRY=181; finish "${LAST}"
sleep 600 & live=$!; PIDS+=("${live}"); first=1
for e in "${CACHE}"/*.json; do
  if [[ -n "${first}" ]]; then : > "${e%.json}.lock"; first=""; else echo "${live}" > "${e%.json}.lock"; fi
  rm "${e}"
done
perl -e '$t = time - 300; utime $t, $t, @ARGV' "${CACHE}"/*.lock
: > "${ROOT}/gh.log"; t0=${SECONDS}
start b SWARM_MERGE_POLL=181 SWARM_WAIT_PR_RETRY=181; finish "${LAST}"; took=$((SECONDS - t0))
kill "${live}" 2>/dev/null || true
is "stale lock: the wait ends green" 0 "${rc}"
is "stale lock: reads all three from GitHub" "1 1 1" "$(reads)"
check "stale lock: waits on no lock (${took}s; a lock that held would hold each read 180 s)" test "${took}" -le 120

if [[ ${fails} -eq 0 ]]; then echo "all wait-pr poll-cache tests passed"; else echo "${fails} wait-pr poll-cache test(s) failed"; exit 1; fi
