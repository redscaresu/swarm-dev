#!/usr/bin/env bash
# test_runner_test.sh — a stopped run leaves nothing: a TERM to the make that runs scripts/test.sh
# (the PID a builder kills, as select-tests.sh --run execs make) ends make, the runner, xargs, each
# job, its watchdog and its test within 10 s, in the xargs phase and in the SERIAL one, and xargs
# starts no further file. The slow fixture holds a perl naming the marker for 60 s.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
M="${ROOT}/marker${RANDOM}"   # in every path the slow fixtures name
# reap — stop each process a stopped run left: each process's children first, by PID.
tree() { local c; for c in $(pgrep -P "$1" || true); do tree "${c}"; done; kill -KILL "$1" 2>/dev/null || true; }
# A stopped run's processes, in stop_case below: each one's "pid lstart". snap_live prints those
# still running with that start time, so a PID taken since is neither left nor killed.
snap="${ROOT}/snapshot"
# live <pid>... — "pid lstart" of each still running and no zombie.
live() { [[ $# -gt 0 ]] || return 0; TZ=UTC LC_ALL=C ps -ww -o pid=,stat=,lstart= -p "$(IFS=,; echo "$*")" 2>/dev/null | awk '$2 !~ /^Z/ { $2 = ""; $1 = $1; print }' || true; }
# shellcheck disable=SC2046 # one PID a word
snap_live() { [[ -s "${snap}" ]] || return 0; live $(cut -d' ' -f1 "${snap}") | grep -Fxf "${snap}" || true; }
reap() {
  local p
  for p in $(pgrep -f "${M}/stop" || true) $(snap_live | cut -d' ' -f1); do tree "${p}"; done
}
trap 'reap; stop_test_group; rm -rf "${ROOT}"' EXIT
# A pgrep that cannot list processes (a sandbox) would see nothing left: stop before starting any.
pgrep -f . > /dev/null || { echo "FAIL pgrep cannot list processes here"; exit 1; }
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

# stop_case <name> <make arg>... — run make test on the slow fixtures with those arguments, TERM
# make once a fixture's perl runs, and check that within 10 s nothing from the run is left: no process
# of its tree as it stood at the TERM (matched by PID and start time, so a PID taken since is no
# match; a zombie make, which only this test can reap, is none), nor any naming the marker.
# desc <pid> — every descendant of <pid>.
desc() { local c; for c in $(pgrep -P "$1" || true); do echo "${c}"; desc "${c}"; done; }
stop_case() {
  local name="$1" d="${M}/stop/$1" x pid end left_now=""
  shift
  # The case's own fixtures and marker, so no process left from an earlier case matches.
  mkdir -p "${d}/tmp"
  for x in a b; do
    printf '#!/usr/bin/env bash\nexec perl -e "sleep 60" %s\n' "${d}/hold-${x}" > "${d}/slow_${x}_test.sh"
  done
  (cd "${d}/tmp" && exec env TMPDIR="${d}/tmp" TEST_RUNS_LOG='' TEST_FILE_TIMEOUT=120 \
    make -C "${REPO}" test TESTS="${d}/slow_a_test.sh ${d}/slow_b_test.sh" "$@") > "${d}/out" 2>&1 &
  pid=$!
  end=$((SECONDS + 30))
  until pgrep -f "${d}/hold-" > /dev/null || [[ ${SECONDS} -ge ${end} ]]; do sleep 0.05; done
  # shellcheck disable=SC2046 # one PID a word
  live "${pid}" $(desc "${pid}") > "${snap}"
  kill -TERM "${pid}"
  # By the clock, not a count of polls: on a busy machine each poll's ps and pgrep take most of a second.
  end=$((SECONDS + 10))
  while :; do
    left_now="$(snap_live; pgrep -f "${d}/" || true)"
    [[ -n "${left_now}" && ${SECONDS} -lt ${end} ]] || break
    sleep 0.1
  done
  [[ -n "${left_now}" ]] || { wait "${pid}"; } 2>/dev/null || true
  # What is left, by PID, parent, group, state and command, with the signals each ignores and blocks
  # where /proc has them (Linux), and the run's own output, so a red run says which process the TERM
  # did not reach.
  [[ -z "${left_now}" ]] || left_now="$(left_pids="$( (snap_live | cut -d' ' -f1; pgrep -f "${d}/" || true) | sort -u)"
    ps -ww -o pid=,ppid=,pgid=,stat=,args= -p "$(paste -sd, - <<< "${left_pids}")" 2>&1 || true
    for x in ${left_pids}; do
      [[ ! -r "/proc/${x}/status" ]] || echo "${x} $(grep -E '^Sig(Ign|Blk):' "/proc/${x}/status" | tr '\t\n' '  ')"
    done
    echo "the run's output:"; cat "${d}/out")"
  check "${name}: a TERM to make leaves no process of the run within 10 s (it had $(wc -l < "${snap}" | tr -d ' '))" "${left_now:-none}" "none"
  check "${name}: the run printed only the first file's run line besides make's own lines: no second file started" \
    "$(grep -v '^make' "${d}/out" || true)" "run  ${d}/slow_a_test.sh"
  reap; : > "${snap}"
}
stop_case xargs-phase JOBS=1 SERIAL=
stop_case serial-phase SERIAL="${M}/stop/serial-phase/slow_a_test.sh ${M}/stop/serial-phase/slow_b_test.sh"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
