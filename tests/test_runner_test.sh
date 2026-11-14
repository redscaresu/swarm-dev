#!/usr/bin/env bash
# test_runner_test.sh — a dash test leaves no ci refresh behind. Its stub runs dash in a fixture
# project with a github.com origin, a build from today and no ci cache, where dash would start a
# detached dash_slow.py refresh, and a gh that hangs, so a refresh that started is still running
# when the test looks. Run through scripts/test.sh with SWARM_PROJECT naming another such project
# (a builder's real one), or alone with SWARM_SLEEP_SCALE set (test mode), it leaves no dash_slow.py
# or swarm.sh naming either; with SWARM_NO_CI_REFRESH set empty, which turns the refresh back on, it
# leaves a dash_slow.py and its swarm.sh flow, so the look can fail. The stub runs swarm.sh through a
# link under the test's marker directory, so both name the marker however the project resolved.
# Then a stopped run leaves nothing: a TERM to the make that runs scripts/test.sh (the PID a builder
# kills, as select-tests.sh --run execs make) ends make, the runner, xargs, each job, its watchdog and
# its test within 10 s, in the xargs phase and in the SERIAL one, and xargs starts no further file.
# The slow fixture holds a perl naming the marker for 60 s.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
M="${ROOT}/marker${RANDOM}"   # in every path the stub's dash and a refresh it starts name
# left — the PID of each dash_slow.py or swarm.sh naming M: a refresh and its flow.
left() { pgrep -f "${M}/repo/.*(dash_slow\.py|swarm\.sh)" || true; }
# reap — stop each such refresh, its flow and their gh: each process's children first, by PID.
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
  for p in $(left) $(pgrep -f "${M}/stop" || true) $(snap_live | cut -d' ' -f1); do tree "${p}"; done
}
trap 'reap; rm -rf "${ROOT}"' EXIT
# A pgrep that cannot list processes (a sandbox) would see no refresh, and leave the one the last
# check starts: stop before starting any.
pgrep -f . > /dev/null || { echo "FAIL pgrep cannot list processes here"; exit 1; }
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

mkdir -p "${M}/bin" "${M}/projects"
printf '#!/bin/sh\nexit 1\n' > "${M}/bin/herdr"
printf '#!/bin/sh\nexec sleep 30\n' > "${M}/bin/gh"
chmod +x "${M}/bin/herdr" "${M}/bin/gh"
cp "${REPO}/tests/claude_stub.sh" "${M}/bin/claude"
ln -s "${REPO}" "${M}/repo"
for p in fixture real; do
  mkdir -p "${M}/${p}/docs/stories"; touch "${M}/${p}/docs/stories/README.md"
  git -C "${M}/${p}" init -q && git -C "${M}/${p}" remote add origin "https://github.com/o/${p}.git"
  # A build from today, so a refresh's flow asks gh about its PR, and waits on it.
  mkdir "${M}/${p}/.swarm"; printf '%s\tcode\ts1\tclaude\topus\thigh\t-\n' "$(date +%F)" > "${M}/${p}/.swarm/agents.tsv"
done
cat > "${M}/dash_stub_test.sh" <<EOF
#!/usr/bin/env bash
cd "${M}/fixture" && env -u HERDR_ENV PATH="${M}/bin:\${PATH}" CLAUDE_PROJECTS_DIR="${M}/projects" \\
  bash "${M}/repo/bin/swarm.sh" dash > /dev/null 2>&1 || true
EOF

mkdir "${M}/tmp1"
SWARM_PROJECT="${M}/real" TMPDIR="${M}/tmp1" bash "${REPO}/scripts/test.sh" "${M}/dash_stub_test.sh" > /dev/null 2>&1 || true
check "a dash test run through scripts/test.sh, SWARM_PROJECT set, leaves no dash_slow.py or swarm.sh" "$(left)" ""
reap
# Run alone, as from a builder's pane, the stub must not inherit the real SWARM_PROJECT.
mkdir "${M}/tmp2"
env -u SWARM_PROJECT -u SWARM_NO_CI_REFRESH SWARM_SLEEP_SCALE=0.01 TMPDIR="${M}/tmp2" bash "${M}/dash_stub_test.sh"
check "dash in test mode (SWARM_SLEEP_SCALE set) starts no dash_slow.py or swarm.sh" "$(left)" ""
reap
mkdir "${M}/tmp3"
env -u SWARM_PROJECT SWARM_NO_CI_REFRESH='' SWARM_SLEEP_SCALE=0.01 TMPDIR="${M}/tmp3" bash "${M}/dash_stub_test.sh"
# The refresh starts its flow just after dash returns: up to 10 s for it.
for _ in $(seq 100); do pgrep -f "${M}/repo/.*swarm\.sh flow" > /dev/null && break; sleep 0.1; done
check "with SWARM_NO_CI_REFRESH set empty it leaves a dash_slow.py and its swarm.sh flow, so the looks above can fail" \
  "$(pgrep -f "${M}/repo/.*dash_slow\.py" > /dev/null && echo refresh)|$(pgrep -f "${M}/repo/.*swarm\.sh flow" > /dev/null && echo flow)" "refresh|flow"

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
