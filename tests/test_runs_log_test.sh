#!/usr/bin/env bash
# test_runs_log_test.sh — every scripts/test.sh run that writes a start line to test-runs.tsv gets one
# end line. A run that is sent TERM, INT, HUP or PIPE after its start line, before its first job,
# writes its end line with that signal's status (143, 130, 129, 141): the EXIT trap is set before the
# start line. A run that is KILLed there writes none and leaves its mark; the next run ends it: one end
# line with the killed run's start and PID, status 137 and `-` for what no run measured, and the mark
# gone, so a third run adds no second one. The run is held between its start line and its first job
# by a mktemp on PATH that waits, when HOLD is set, on the run's `mktemp -d` (its run dir). A gone
# run's mark beside its end line gets no second one, and a claim on a mark whose claiming run died
# before it wrote the line is ended by the next run. A run held as it builds its start line (an uptime
# on PATH that waits, when HOLD_UPTIME is set) already has its mark, so a run that starts then counts
# it. Two runs released together from there against 30 stale marks end each one once between them.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'touch "${ROOT}/go" "${ROOT}/u1/go" "${ROOT}/u2/go" 2>/dev/null; wait; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
export HOME="${ROOT}/home"   # its runs are top-level: a cap in the real ~/.swarm/test-cap would gate them
mkdir -p "${ROOT}/log" "${ROOT}/bin" "${ROOT}/cwd"
LOG="${ROOT}/log/test-runs.tsv"
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

# The mktemp stub: `mktemp -d` alone, with HOLD set, touches HOLD/held and waits for HOLD/go (10 s at
# most); every call then runs the real mktemp.
real_mktemp="$(command -v mktemp)"
# shellcheck disable=SC2016 # the stub's own shell expands it
printf '#!/usr/bin/env bash\nif [ "$#" = 1 ] && [ "$1" = -d ] && [ -n "${HOLD:-}" ]; then\n  : > "${HOLD}/held"\n  for _ in $(seq 200); do [ -e "${HOLD}/go" ] && break; sleep 0.05; done\nfi\nexec "%s" "$@"\n' \
  "${real_mktemp}" > "${ROOT}/bin/mktemp"
chmod +x "${ROOT}/bin/mktemp"
# The uptime stub: with HOLD_UPTIME set and no HOLD_UPTIME/go, it touches HOLD_UPTIME/held.<its PID> and
# waits for go (10 s at most); then it runs the real uptime. test.sh calls it as it builds a line.
real_uptime="$(command -v uptime)"
# shellcheck disable=SC2016 # the stub's own shell expands it
printf '#!/usr/bin/env bash
if [ -n "${HOLD_UPTIME:-}" ] && [ ! -e "${HOLD_UPTIME}/go" ]; then
  : > "${HOLD_UPTIME}/held.$$"
  for _ in $(seq 200); do [ -e "${HOLD_UPTIME}/go" ] && break; sleep 0.05; done
fi
exec "%s" "$@"
' \
  "${real_uptime}" > "${ROOT}/bin/uptime"
chmod +x "${ROOT}/bin/uptime"
printf '#!/usr/bin/env bash\nexit 0\n' > "${ROOT}/pass_test.sh"

# held_run — start a run of pass_test.sh in the background, INT and PIPE at their default (a background
# job ignores INT, and bash cannot trap a signal ignored when it starts), held at its run dir; wait for
# the hold. Sets pid.
held_run() {
  rm -f "${ROOT}/held" "${ROOT}/go"
  # shellcheck disable=SC2016 # perl's own variables
  (cd "${ROOT}/cwd" && exec env HOLD="${ROOT}" PATH="${ROOT}/bin:${PATH}" TEST_RUNS_LOG="${LOG}" \
    perl -e '$SIG{INT} = $SIG{PIPE} = "DEFAULT"; exec @ARGV or die "exec: $!\n"' bash "${REPO}/scripts/test.sh" "${ROOT}/pass_test.sh" > /dev/null 2>&1) &
  pid=$!
  for _ in $(seq 200); do [[ -e "${ROOT}/held" ]] && return 0; sleep 0.05; done
  echo "FAIL the run never reached its run dir"; exit 1
}
# lines <pid> — that run's lines: start, end (empty on a start line) and status, one a line.
lines() { awk -F'\t' -v OFS=' ' -v p="$1" '$11 == p { print $1, ($2 == "" ? "(start)" : $2), ($10 == "" ? "(none)" : $10) }' "${LOG}"; }
# ended <pid> — the statuses of that run's end lines, and how many start lines it has.
ended() { awk -F'\t' -v p="$1" '$11 == p { if ($10 == "") s++; else e = e (e == "" ? "" : " ") $10 } END { printf "starts=%d ends=%s\n", s, (e == "" ? "none" : e) }' "${LOG}"; }

# Each trappable signal, sent after the start line and before the first job.
for sig_status in TERM:143 INT:130 HUP:129 PIPE:141; do
  sig="${sig_status%%:*}" want="${sig_status#*:}"
  held_run
  kill -s "${sig}" "${pid}"
  touch "${ROOT}/go"
  wait "${pid}" && rc=0 || rc=$?
  check "a run sent ${sig} after its start line exits ${want} and writes one end line with that status" \
    "rc=${rc} $(ended "${pid}")" "rc=${want} starts=1 ends=${want}"
done

# KILL there: nothing in the run runs, so it leaves its start line and its mark, and no end line.
held_run
kill -KILL "${pid}"
wait "${pid}" || true
touch "${ROOT}/go"
killed="${pid}"
start="$(awk -F'\t' -v p="${killed}" '$11 == p { print $1 }' "${LOG}")"
check "a KILLed run leaves its start line, no end line, and its mark" \
  "$(ended "${killed}") $(ls "${ROOT}/log/test-runs.d")" "starts=1 ends=none ${killed}"
# The next run ends it, and a third adds nothing.
(cd "${ROOT}/cwd" && TEST_RUNS_LOG="${LOG}" bash "${REPO}/scripts/test.sh" "${ROOT}/pass_test.sh" > /dev/null 2>&1)
check "the next run writes one end line for the KILLed run: its start and PID, status 137, the rest -" \
  "$(awk -F'\t' -v OFS='|' -v p="${killed}" '$11 == p && $10 != "" { $1 = $1; print }' "${LOG}")" "${start}|-|-|4|1 files|-|-|-|-|137|${killed}"
(cd "${ROOT}/cwd" && TEST_RUNS_LOG="${LOG}" bash "${REPO}/scripts/test.sh" "${ROOT}/pass_test.sh" > /dev/null 2>&1)
check "its mark is gone, and a third run adds no second end line" \
  "$(ended "${killed}") $(find "${ROOT}/log/test-runs.d" -mindepth 1 | wc -l | tr -d ' ')" "starts=1 ends=137 0"
# A gone run's mark beside its end line (KILLed after it wrote the line, before it removed the mark)
# gets no second one; a claim whose claiming run died before it wrote the line is ended by the next run.
# dead_pid — a PID that has gone.
dead_pid() { sleep 0 & local d=$!; wait "${d}"; echo "${d}"; }
# start_line <pid> — a start line for that PID.
start_line() { printf '2026-01-01T00:00:00Z\t\t\t4\t1 files\t-\t1.00\t8\t0\t\t%s\n' "$1"; }
ended_pid="$(dead_pid)" claimed="$(dead_pid)" claimer="$(dead_pid)"
start_line "${ended_pid}" > "${ROOT}/log/test-runs.d/${ended_pid}"
start_line "${claimed}" > "${ROOT}/log/test-runs.d/.dead.${claimed}.${claimer}"
{
  start_line "${ended_pid}"
  printf '2026-01-01T00:00:00Z\t2026-01-01T00:01:00Z\t60\t4\t1 files\t-\t1.00\t8\t0\t0\t%s\n' "${ended_pid}"
  start_line "${claimed}"
} >> "${LOG}"
(cd "${ROOT}/cwd" && TEST_RUNS_LOG="${LOG}" bash "${REPO}/scripts/test.sh" "${ROOT}/pass_test.sh" > /dev/null 2>&1)
check "a gone run's mark beside its end line adds no second end line, and the mark goes" \
  "$(ended "${ended_pid}") $(find "${ROOT}/log/test-runs.d" -mindepth 1 -name "*${ended_pid}*" | wc -l | tr -d ' ')" "starts=1 ends=0 0"
check "a claim whose claiming run died is ended by the next run, and goes" \
  "$(ended "${claimed}") $(find "${ROOT}/log/test-runs.d" -mindepth 1 | wc -l | tr -d ' ')" "starts=1 ends=137 0"
# uptime_run <dir> — start a run of pass_test.sh in the background, held at its start line's load by
# the uptime stub until <dir>/go; prints nothing, adds its PID to held_pids.
held_pids=()
uptime_run() {
  (cd "${ROOT}/cwd" && exec env HOLD_UPTIME="$1" PATH="${ROOT}/bin:${PATH}" TEST_RUNS_LOG="${LOG}" \
    bash "${REPO}/scripts/test.sh" "${ROOT}/pass_test.sh" > /dev/null 2>&1) &
  held_pids+=($!)
}
# until_held <dir> <n> — wait for n runs held there, 10 s at most.
until_held() {
  local n
  for _ in $(seq 200); do
    n="$(find "$1" -name 'held.*' | wc -l | tr -d ' ')"
    [[ "${n}" -lt "$2" ]] || return 0
    sleep 0.05
  done
  echo "FAIL only ${n} of $2 runs reached their start line's load"; exit 1
}
# B is held as it builds its start line; A starts and ends meanwhile.
mkdir "${ROOT}/u1"
uptime_run "${ROOT}/u1"
until_held "${ROOT}/u1" 1
(cd "${ROOT}/cwd" && exec env TEST_RUNS_LOG="${LOG}" bash "${REPO}/scripts/test.sh" "${ROOT}/pass_test.sh" > /dev/null 2>&1) &
a=$!
wait "${a}"
touch "${ROOT}/u1/go"
wait "${held_pids[0]}"
check "a run that starts while another builds its start line counts it as going, at its start and its end" \
  "$(awk -F'\t' -v p="${a}" '$11 == p { printf "%s%s", sep, $9; sep = " " }' "${LOG}")" "1 1"

# Two runs released together against 30 stale marks, each holding a gone run's start line.
stale=()
for _ in $(seq 30); do
  p="$(dead_pid)"
  stale+=("${p}")
  start_line "${p}" > "${ROOT}/log/test-runs.d/${p}"
  start_line "${p}" >> "${LOG}"
done
mkdir "${ROOT}/u2"
held_pids=()
uptime_run "${ROOT}/u2"
uptime_run "${ROOT}/u2"
until_held "${ROOT}/u2" 2
touch "${ROOT}/u2/go"
wait "${held_pids[@]}"
check "two runs started together write one end line, status 137, for each of 30 stale marks between them" \
  "$(for p in "${stale[@]}"; do ended "${p}"; done | sort | uniq -c | awk '{ $1 = $1; print }')" "30 starts=1 ends=137"
check "each other run has one start and one end line" \
  "$(awk -F'\t' -v k="${killed}" '$11 != k { n[$11 ($10 == "" ? " start" : " end")]++ } END { for (x in n) if (n[x] != 1) print x, n[x] }' "${LOG}")" ""
[[ ${fails} -eq 0 ]] || { echo "lines in the log:"; awk -F'\t' '{ print $11 }' "${LOG}" | sort -u | while read -r p; do lines "${p}"; done; }

if [[ ${fails} -gt 0 ]]; then echo "FAILED: ${fails}"; exit 1; fi
echo "all ok"
