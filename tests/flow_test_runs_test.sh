#!/usr/bin/env bash
# flow_test_runs_test.sh — scripts/test.sh logs each run, and flow's test_runs section reads the log.
# Run from a worktree of a temporary repo on a one-file TESTS filter, test.sh appends a start line and
# an end line to the main checkout's .swarm/test-runs.tsv, the end line with every field. The filter
# is all for every tests/*_test.sh, else TESTS, else how many files, with a SHARD's shard after it. A
# run started while another runs counts it as going, at its start and at its end; a run a test starts
# itself logs nothing and is never counted, nor is a dead run's mark. With .swarm a file, so the log
# cannot be written, a run still exits as its test did. Then, on a fixture test-runs.tsv: the at_once
# buckets (the larger of a run's start and end) with their medians, p90s and median start loads, and
# the 5 slowest full runs, two runs that start in the same second paired by PID; a start line alone,
# a filtered run, a shard, an interrupted run and a run before --since count nowhere, and with no log
# the section prints nothing. TZ is UTC.
set -euo pipefail
export TZ=UTC

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'touch "${dir}/goA" "${dir}/goD" 2>/dev/null; wait; rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

R="${dir}/repo"
git init -q "${R}"
git -C "${R}" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "${R}" worktree add -q -b wt "${dir}/wt"
mkdir "${dir}/wt/tests"
printf '#!/usr/bin/env bash\nexit 0\n' > "${dir}/wt/tests/pass_test.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "${dir}/wt/tests/fail_test.sh"
# run <test file> — test.sh on that one file, as make test TESTS=<file> JOBS=2 runs it; its exit status.
run() { (cd "${dir}/wt" && env -u TEST_RUNS_LOG TESTS="$1" JOBS=2 bash "${ROOT}/scripts/test.sh" "$1" > /dev/null 2>&1) && echo 0 || echo $?; }

check "a passing run exits 0" "$(run tests/pass_test.sh)" 0
log="${R}/.swarm/test-runs.tsv"
check "it wrote a start line and an end line to the main checkout's log" "$(wc -l < "${log}" | tr -d ' ')" 2
check "the start line leaves end, seconds and status empty" "$(sed -n 1p "${log}" | cut -f2,3,10)" $'\t\t'
IFS=$'\t' read -r start end secs jobs filter branch load cpus others status pid <<< "$(sed -n 2p "${log}")"
check "the end line has every field" "$(awk -F'\t' '{ n = 0; for (i = 1; i <= NF; i++) n += $i != ""; print NF "/" n }' <<< "$(sed -n 2p "${log}")")" 11/11
iso='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
check "start and end are UTC times, seconds a number" \
  "$([[ ${start} =~ ${iso} && ${end} =~ ${iso} && ${secs} =~ ^[0-9]+$ ]] && echo yes)" yes
check "JOBS, the TESTS filter and the worktree's branch" "${jobs} ${filter} ${branch}" "2 tests/pass_test.sh wt"
check "the load, CPUs and other runs are numbers" \
  "$([[ ${load} =~ ^[0-9]+(\.[0-9]+)?$ && ${cpus} =~ ^[1-9][0-9]*$ && ${others} =~ ^[0-9]+$ ]] && echo yes)" yes
check "the exit status" "${status}" 0
check "both lines name the run's PID" "$([[ ${pid} =~ ^[0-9]+$ && "$(sed -n 1p "${log}" | cut -f11)" == "${pid}" ]] && echo yes)" yes
run tests/fail_test.sh > /dev/null
check "a failing run's end line has its status" "$(tail -1 "${log}" | cut -f10)" 1
# bare [env...] <file>... — test.sh on those files with TESTS unset, as bash scripts/test.sh runs it.
bare() { (cd "${dir}/wt" && env -u TEST_RUNS_LOG -u TESTS "$@" bash "${ROOT}/scripts/test.sh" tests/fail_test.sh tests/pass_test.sh > /dev/null 2>&1) || true; }
bare
check "a run of every tests/*_test.sh logs all" "$(tail -1 "${log}" | cut -f5)" all
(cd "${dir}/wt" && env -u TEST_RUNS_LOG -u TESTS bash "${ROOT}/scripts/test.sh" tests/pass_test.sh > /dev/null 2>&1)
check "a run of some files, TESTS unset, logs how many" "$(tail -1 "${log}" | cut -f5)" "1 files"
bare SHARD=1/1
check "a SHARD run's filter names the shard, so flow counts it as no full run" "$(tail -1 "${log}" | cut -f5)" "all shard 1/1"

# A runs a test that starts test.sh itself (B, nested) and holds until goA; D starts while both run
# and holds until goD. A dead run's mark is there from the start.
mkdir "${dir}/wt/hold"
# hold <name> — a test that touches in<name>, then waits for go<name>, 60 s at most.
# shellcheck disable=SC2016 # the hold test's own shell expands it
hold() { printf '#!/usr/bin/env bash\n: > "%s/in%s"\nfor _ in $(seq 600); do [ -e "%s/go%s" ] && exit 0; sleep 0.1; done\nexit 1\n' "${dir}" "$1" "${dir}" "$1"; }
hold A > "${dir}/wt/hold/hold_a_test.sh"
hold D > "${dir}/wt/hold/hold_d_test.sh"
printf '#!/usr/bin/env bash\nbash "%s/scripts/test.sh" hold/hold_a_test.sh\n' "${ROOT}" > "${dir}/wt/hold/nest_test.sh"
# until_there <file> — wait for it, 60 s at most.
until_there() { for _ in $(seq 600); do [[ -e "$1" ]] && return 0; sleep 0.1; done; echo "FAIL $1 never appeared"; exit 1; }
sleep 0 & dead=$!; wait "${dead}"
: > "${R}/.swarm/test-runs.d/${dead}"
before="$(wc -l < "${log}")"
(cd "${dir}/wt" && exec env -u TEST_RUNS_LOG TESTS=hold/nest_test.sh bash "${ROOT}/scripts/test.sh" hold/nest_test.sh > /dev/null 2>&1) &
pa=$!
until_there "${dir}/inA"
(cd "${dir}/wt" && exec env -u TEST_RUNS_LOG TESTS=hold/hold_d_test.sh bash "${ROOT}/scripts/test.sh" hold/hold_d_test.sh > /dev/null 2>&1) &
pd=$!
until_there "${dir}/inD"
touch "${dir}/goA"; wait "${pa}"
touch "${dir}/goD"; wait "${pd}"
# going <filter> — the other runs on that filter's start line, then its end line.
going() { awk -F'\t' -v f="$1" '$5 == f { printf "%s%s", sep, $9; sep = " " }' "${log}"; }
check "A, starting beside a dead run's mark only, counts none at its start; D, still going, at its end" "$(going hold/nest_test.sh)" "0 1"
check "D counts A at its start, but not the run A's test started" "$(going hold/hold_d_test.sh)" "1 0"
check "the run a test started logs nothing: four lines, A's and D's" "$(($(wc -l < "${log}") - before))" 4
check "the dead run's mark is gone, and so are A's and D's" "$(ls "${R}/.swarm/test-runs.d")" ""

rm -rf "${R}/.swarm"
: > "${R}/.swarm"   # a file: no log can be written under it
check "with the log unwritable, a passing run still exits 0" "$(run tests/pass_test.sh)" 0
check "and a failing run still exits 1" "$(run tests/fail_test.sh)" 1

mkdir -p "${dir}/project/.swarm"
P="$(cd "${dir}/project" && pwd -P)"
git init -q "${P}"
# line <start> <end> <seconds> <filter> <load> <others at start> <others at end> <status> — a run's start
# line, then its end line, whose load (99) flow never reads; its PID is its seconds.
line() {
  printf '%s\t\t\t4\t%s\tb-%s\t%s\t10\t%s\t\t%s\n' "$1" "$4" "$3" "$5" "$6" "$3" >> "${P}/.swarm/test-runs.tsv"
  printf '%s\t%s\t%s\t4\t%s\tb-%s\t99.00\t10\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$3" "$7" "$8" "$3" >> "${P}/.swarm/test-runs.tsv"
}
printf '2026-10-01T09:00:00Z\t\t\t4\tall\tb-killed\t1.00\t10\t0\t\t1\n' >> "${P}/.swarm/test-runs.tsv"
line 2026-10-01T10:00:00Z 2026-10-01T10:01:40Z 100 all 1.00 0 0 0
line 2026-10-01T11:00:00Z 2026-10-01T11:03:20Z 200 all 2.00 0 0 0
line 2026-10-01T12:00:00Z 2026-10-01T12:05:00Z 300 all 3.00 0 0 1
line 2026-10-02T10:00:00Z 2026-10-02T10:08:20Z 500 all 8.00 1 0 0
line 2026-10-02T11:00:00Z 2026-10-02T11:15:00Z 900 all 20.00 0 2 0
line 2026-10-02T12:00:00Z 2026-10-02T12:16:40Z 1000 all 30.00 3 3 0
line 2026-10-02T12:30:00Z 2026-10-02T12:48:20Z 1100 all 40.00 0 0 130
line 2026-10-02T12:40:00Z 2026-10-02T13:00:00Z 1200 all 40.00 0 0 143
line 2026-10-02T13:00:00Z 2026-10-02T14:00:00Z 3600 tests/x_test.sh 9.00 0 0 0
line 2026-10-02T15:00:00Z 2026-10-02T16:00:00Z 3700 'all shard 1/8' 9.00 0 0 0
line 2026-09-01T10:00:00Z 2026-09-01T11:23:20Z 5000 all 9.00 0 0 0
# Two runs on one branch that start in the same second, told apart by their PIDs.
printf '%s\n' $'2026-10-02T08:00:00Z\t\t\t4\tall\tb-same\t7.00\t10\t4\t\t600' $'2026-10-02T08:00:00Z\t\t\t4\tall\tb-same\t6.00\t10\t0\t\t700' \
  $'2026-10-02T08:00:00Z\t2026-10-02T08:10:00Z\t600\t4\tall\tb-same\t99.00\t10\t0\t0\t600' \
  $'2026-10-02T08:00:00Z\t2026-10-02T08:11:40Z\t700\t4\tall\tb-same\t99.00\t10\t0\t0\t700' >> "${P}/.swarm/test-runs.tsv"
# An end line whose start line is missing: its own load and other runs.
printf '2026-10-02T09:00:00Z\t2026-10-02T09:06:40Z\t400\t4\tall\tb-400\t5.00\t10\t4\t0\t400\n' >> "${P}/.swarm/test-runs.tsv"
section() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FLOW_SECTIONS=test_runs bash "${ROOT}/bin/swarm.sh" flow "$@" | grep -v '^## test_runs$'); }
check "the buckets, medians and slowest five" "$(section --since 2026-10-01)" "$(printf '%s\n' \
  $'at_once\truns\tmedian_s\tp90_s\tmedian_load' $'1\t4\t250\t700\t2.50' $'2\t1\t500\t500\t8.00' $'3-4\t2\t950\t1000\t25.00' $'5+\t2\t500\t600\t6.00' '' \
  $'start\tseconds\tbranch\tat_once\tstatus' $'2026-10-02T12:00:00Z\t1000\tb-1000\t4\t0' $'2026-10-02T11:00:00Z\t900\tb-900\t3\t0' \
  $'2026-10-02T08:00:00Z\t700\tb-same\t1\t0' $'2026-10-02T08:00:00Z\t600\tb-same\t5\t0' $'2026-10-02T10:00:00Z\t500\tb-500\t2\t0')"
check "a window with no full run says so" "$(section --since 2026-11-01)" "no full test runs logged in the window (2026-11-01 to 9999-12-30)"
rm "${P}/.swarm/test-runs.tsv"
check "with no log (a project with no scripts/test.sh) it prints nothing" "$(section)" ""

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
