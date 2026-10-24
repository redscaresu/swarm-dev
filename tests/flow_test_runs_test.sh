#!/usr/bin/env bash
# flow_test_runs_test.sh — scripts/test.sh logs each run, and flow's test_runs section reads the log.
# Run from a worktree of a temporary repo on a one-file TESTS filter, test.sh appends a start line and
# an end line to the main checkout's .swarm/test-runs.tsv, the end line with every field (a SHARD run's
# filter names its shard); with .swarm a file, so the log cannot be written, a run still exits as its
# test did. Then, on a fixture test-runs.tsv: the at_once buckets with their medians, p90s and median
# loads, and the 5 slowest full runs; a start line, a filtered run, a shard and a run before --since
# count nowhere. TZ is UTC.
set -euo pipefail
export TZ=UTC

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
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
IFS=$'\t' read -r start end secs jobs filter branch load cpus others status <<< "$(sed -n 2p "${log}")"
check "the end line has every field" "$(awk -F'\t' '{ n = 0; for (i = 1; i <= NF; i++) n += $i != ""; print NF "/" n }' <<< "$(sed -n 2p "${log}")")" 10/10
iso='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
check "start and end are UTC times, seconds a number" \
  "$([[ ${start} =~ ${iso} && ${end} =~ ${iso} && ${secs} =~ ^[0-9]+$ ]] && echo yes)" yes
check "JOBS, the TESTS filter and the worktree's branch" "${jobs} ${filter} ${branch}" "2 tests/pass_test.sh wt"
check "the load, CPUs and other runs are numbers" \
  "$([[ ${load} =~ ^[0-9]+(\.[0-9]+)?$ && ${cpus} =~ ^[1-9][0-9]*$ && ${others} =~ ^[0-9]+$ ]] && echo yes)" yes
check "the exit status" "${status}" 0
run tests/fail_test.sh > /dev/null
check "a failing run's end line has its status" "$(tail -1 "${log}" | cut -f10)" 1
(cd "${dir}/wt" && env -u TEST_RUNS_LOG -u TESTS SHARD=1/1 bash "${ROOT}/scripts/test.sh" tests/pass_test.sh > /dev/null 2>&1)
check "a SHARD run's filter names the shard, so flow counts it as no full run" "$(tail -1 "${log}" | cut -f5)" "all shard 1/1"

rm -rf "${R}/.swarm"
: > "${R}/.swarm"   # a file: no log can be written under it
check "with the log unwritable, a passing run still exits 0" "$(run tests/pass_test.sh)" 0
check "and a failing run still exits 1" "$(run tests/fail_test.sh)" 1

mkdir -p "${dir}/project/.swarm"
P="$(cd "${dir}/project" && pwd -P)"
git init -q "${P}"
# line <start> <end> <seconds> <filter> <load> <others> <status>
line() { printf '%s\t%s\t%s\t4\t%s\tb-%s\t%s\t10\t%s\t%s\n' "$1" "$2" "$3" "$4" "$3" "$5" "$6" "$7" >> "${P}/.swarm/test-runs.tsv"; }
line 2026-10-01T09:00:00Z "" "" all 1.00 0 ""
line 2026-10-01T10:00:00Z 2026-10-01T10:01:40Z 100 all 1.00 0 0
line 2026-10-01T11:00:00Z 2026-10-01T11:03:20Z 200 all 2.00 0 0
line 2026-10-01T12:00:00Z 2026-10-01T12:05:00Z 300 all 3.00 0 1
line 2026-10-02T10:00:00Z 2026-10-02T10:08:20Z 500 all 8.00 1 0
line 2026-10-02T11:00:00Z 2026-10-02T11:15:00Z 900 all 20.00 2 0
line 2026-10-02T12:00:00Z 2026-10-02T12:16:40Z 1000 all 30.00 3 130
line 2026-10-02T13:00:00Z 2026-10-02T14:00:00Z 3600 tests/x_test.sh 9.00 0 0
line 2026-10-02T15:00:00Z 2026-10-02T16:00:00Z 3700 'all shard 1/8' 9.00 0 0
line 2026-09-01T10:00:00Z 2026-09-01T11:23:20Z 5000 all 9.00 0 0
section() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FLOW_SECTIONS=test_runs bash "${ROOT}/bin/swarm.sh" flow "$@" | grep -v '^## test_runs$'); }
check "the buckets, medians and slowest five" "$(section --since 2026-10-01)" "$(printf '%s\n' \
  $'at_once\truns\tmedian_s\tp90_s\tmedian_load' $'1\t3\t200\t300\t2.00' $'2\t1\t500\t500\t8.00' $'3-4\t2\t950\t1000\t25.00' $'5+\t0\t-\t-\t-' '' \
  $'start\tseconds\tbranch\tat_once\tstatus' $'2026-10-02T12:00:00Z\t1000\tb-1000\t4\t130' $'2026-10-02T11:00:00Z\t900\tb-900\t3\t0' \
  $'2026-10-02T10:00:00Z\t500\tb-500\t2\t0' $'2026-10-01T12:00:00Z\t300\tb-300\t1\t1' $'2026-10-01T11:00:00Z\t200\tb-200\t1\t0')"
check "a window with no full run says so" "$(section --since 2026-11-01)" "no full test runs logged in the window (2026-11-01 to 9999-12-30)"
rm "${P}/.swarm/test-runs.tsv"
check "no log says so" "$(section)" \
  "no test runs logged: no ${P}/.swarm/test-runs.tsv yet (scripts/test.sh writes it on each run)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
