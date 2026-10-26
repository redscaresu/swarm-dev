#!/usr/bin/env bash
# test_cap_test.sh — ~/.swarm/test-cap caps the top-level make test runs that go at once on a
# machine, HOME here being a temp dir. With no cap file a run passes and makes nothing under
# ~/.swarm; an empty file or 0 is no cap either, and anything else, a number too big for bash
# included, stops the run before any test. With a cap of 1, two runs started together from two
# projects never overlap; a run that finds the slot held by a live PID says it waits, naming that
# PID, and starts its test only once the PID has gone; a slot whose PID is dead, or an empty one, is
# taken back at once; one that is a file stops the run; an interrupted run frees its slot. And every
# tests/*_test.sh that starts a top-level run (TEST_RUNS_LOG unset, or set to a file) exports HOME
# under its own mktemp root, so a cap in the real HOME never gates it.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
pids=()
trap 'for p in "${pids[@]+"${pids[@]}"}"; do kill "${p}" 2>/dev/null || true; done; wait; rm -rf "${ROOT}"' EXIT
export HOME="${ROOT}/home"
mkdir -p "${HOME}"
fails=0 fin=""
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

# start <project> <out> <file>... — scripts/test.sh on the files from <project>, a top-level run that
# logs to that project's own .swarm/test-runs.tsv, in the background, its output in <out>; $! is its PID.
start() {
  local p="${ROOT}/$1" out="$2"
  shift 2
  mkdir -p "${p}"
  (cd "${p}" && exec env TEST_RUNS_LOG="${p}/.swarm/test-runs.tsv" JOBS=2 bash "${REPO}/scripts/test.sh" "$@" > "${out}" 2>&1) &
}
# finish <pid> — set fin to that run's exit status, or to "hung" (and stop it) when it runs past 30 s.
# Not in a $(...): only the shell that started the run can wait for it.
finish() {
  local i
  for ((i = 0; i < 300; i++)); do
    kill -0 "$1" 2>/dev/null || { wait "$1" && fin=0 || fin=$?; return 0; }
    sleep 0.1
  done
  kill "$1" 2>/dev/null; wait "$1" 2>/dev/null || true; fin=hung
}
# until_there <grep -E pattern> <file> — wait for a line that matches, 30 s at most.
until_there() { for _ in $(seq 300); do grep -qE "$1" "$2" 2>/dev/null && return 0; sleep 0.1; done; echo "FAIL no '$1' in $2"; exit 1; }
slots="${HOME}/.swarm/test-slots"
# plant [pid] — slot 1 held by that PID (a directory with a file named by it), or empty with none,
# over whatever an earlier case that failed left.
plant() { rm -rf "${slots}/1"; mkdir -p "${slots}/1"; [[ -z "${1:-}" ]] || : > "${slots}/1/$1"; }
# left — what is left in the slots dir, hidden entries too, or empty.
left() {
  local f out=""
  [[ -d "${slots}" ]] || { echo "no slots dir"; return 0; }
  for f in "${slots}"/* "${slots}"/.[!.]*; do [[ -e "${f}" ]] && out+="${f##*/} "; done
  echo "${out:-empty}"
}

printf '#!/usr/bin/env bash\nexit 0\n' > "${ROOT}/pass_test.sh"
start p0 "${ROOT}/p0.out" "${ROOT}/pass_test.sh"; finish $!
check "with no cap file a run passes and makes nothing under ~/.swarm" "${fin}|$(ls -A "${HOME}")" "0|"

# capped <value> — with the cap file holding <value> (none at all for ''): "no cap" when a run passes
# and makes no slots dir, "refused" when it exits 1 saying why before its test runs.
capped() {
  mkdir -p "${HOME}/.swarm"
  if [[ -z "$1" ]]; then : > "${HOME}/.swarm/test-cap"; else printf '%s\n' "$1" > "${HOME}/.swarm/test-cap"; fi
  start p0 "${ROOT}/p0.out" "${ROOT}/pass_test.sh"; finish $!
  if [[ "${fin}" == 0 && ! -e "${slots}" ]]; then echo "no cap"
  elif [[ "${fin}" == 1 ]] && grep -qF "test-cap holds '$1', not a whole number" "${ROOT}/p0.out" && ! grep -q '^run ' "${ROOT}/p0.out"; then echo refused
  else echo "${fin}: $(cat "${ROOT}/p0.out")"; fi
}
check "an empty cap file and 0 are no cap; x, -1, 01, 1.5, 1 2 and 2^63 are refused before any test runs" \
  "$(capped '')|$(capped 0)|$(capped x)|$(capped -1)|$(capped 01)|$(capped 1.5)|$(capped '1 2')|$(capped 9223372036854775808)" \
  "no cap|no cap|refused|refused|refused|refused|refused|refused"

echo 1 > "${HOME}/.swarm/test-cap"
# Two runs started together from two projects: whichever starts its test first writes start, holds
# until the other run says it waits (20 s at most), then writes end.
# shellcheck disable=SC2016 # the stub's own shell expands it
printf '#!/usr/bin/env bash\necho start >> "%s/order"\nfor _ in $(seq 200); do grep -qs waiting "%s/p1.out" "%s/p2.out" && break; sleep 0.1; done\necho end >> "%s/order"\n' \
  "${ROOT}" "${ROOT}" "${ROOT}" "${ROOT}" > "${ROOT}/turn_test.sh"
start p1 "${ROOT}/p1.out" "${ROOT}/turn_test.sh"; r1=$!; pids+=("${r1}")
start p2 "${ROOT}/p2.out" "${ROOT}/turn_test.sh"; r2=$!; pids+=("${r2}")
finish "${r1}"; f1="${fin}"; finish "${r2}"; f2="${fin}"
check "with a cap of 1, two runs started together from two projects never overlap, one waiting, and leave no slot" \
  "$(tr '\n' ' ' < "${ROOT}/order")|${f1} ${f2}|$(cat "${ROOT}/p1.out" "${ROOT}/p2.out" | grep -c '^test.sh: waiting on 1 run')|$(left)" \
  "start end start end |0 0|1|empty"

# A slot held by a live PID: the run says it waits on that PID, and its test starts only after it exits.
sleep 60 & holder=$!; pids+=("${holder}")
plant "${holder}"
: > "${ROOT}/order"
printf '#!/usr/bin/env bash\necho start >> "%s/order"\n' "${ROOT}" > "${ROOT}/mark_test.sh"
start p3 "${ROOT}/p3.out" "${ROOT}/mark_test.sh"; r3=$!; pids+=("${r3}")
until_there '^test.sh: waiting' "${ROOT}/p3.out"
sleep 2   # two polls, so a run that only said it waits would have started its test by now
before="$(wc -l < "${ROOT}/order" | tr -d ' ')"
kill "${holder}"; wait "${holder}" 2>/dev/null || true
finish "${r3}"
check "a slot held by a live PID: the run says it waits on that PID, and starts its test only after the PID exits" \
  "$(grep -c "^test.sh: waiting on 1 run(s) (PID ${holder}) for a slot: ${HOME}/.swarm/test-cap allows 1 at once$" "${ROOT}/p3.out")|${before}|${fin}|$(cat "${ROOT}/order")|$(left)" \
  "1|0|0|start|empty"

# A slot whose PID is dead is taken back at once: no wait, and nothing left behind, not even aside.
# So is an empty one, which a run killed while freeing its slot leaves.
sleep 0 & dead=$!; wait "${dead}"
plant "${dead}"
start p4 "${ROOT}/p4.out" "${ROOT}/pass_test.sh"; finish $!
check "a slot whose PID is dead is taken back: the run passes without waiting and leaves no slot" \
  "${fin}|$(grep -c waiting "${ROOT}/p4.out")|$(left)" "0|0|empty"
plant
start p4 "${ROOT}/p4.out" "${ROOT}/pass_test.sh"; finish $!
check "an empty slot is taken: the run passes without waiting and leaves no slot" \
  "${fin}|$(grep -c waiting "${ROOT}/p4.out")|$(left)" "0|0|empty"

# A slot that is no directory (here a file) cannot be taken: the run stops saying so, never waits on.
rm -rf "${slots}/1"; : > "${slots}/1"
start p6 "${ROOT}/p6.out" "${ROOT}/pass_test.sh"; finish $!
check "a slot that is a file stops the run with an error, and runs no test" "${fin}|$(grep -c "^test.sh: no slot in ${slots} can be taken, yet live runs hold only 0 of 1" "${ROOT}/p6.out")|$(grep -c '^run ' "${ROOT}/p6.out")" "1|1|0"
rm -f "${slots}/1"

# An interrupted run (TERM: a background run ignores INT) frees the slot it held.
printf '#!/usr/bin/env bash\necho start >> "%s/order"\nsleep 30\n' "${ROOT}" > "${ROOT}/long_test.sh"
: > "${ROOT}/order"
start p5 "${ROOT}/p5.out" "${ROOT}/long_test.sh"; r5=$!; pids+=("${r5}")
until_there '^start$' "${ROOT}/order"
held="$(cd "${slots}/1" && echo *)"
kill -TERM "${r5}"; finish "${r5}"
check "an interrupted run frees the slot it held" "${held}|${fin}|$(left)" "${r5}|143|empty"

# rooted <file> <var> — 0 when <file> sets <var> from mktemp, or from a variable it sets so (as
# sleep_scale_test.sh's).
rooted() {
  local from
  grep -qE "^$2=\"\\\$\(mktemp " "$1" && return 0
  from="$(sed -nE "s/^$2=\"\\\$\(cd \"\\\$\{([A-Za-z_]+)\}\".*/\1/p" "$1" | head -1)"
  [[ -n "${from}" ]] && grep -qE "^${from}=\"\\\$\(mktemp " "$1"
}
starters="" unhomed=""
for t in "${REPO}"/tests/*_test.sh; do
  grep -qE -- '-u TEST_RUNS_LOG|unset TEST_RUNS_LOG|TEST_RUNS_LOG="[^"]' "${t}" || continue
  starters+=" ${t##*/} "
  v="$(sed -nE 's/^export HOME="\$\{([A-Za-z_]+)\}.*/\1/p' "${t}" | head -1)"
  [[ -n "${v}" ]] && rooted "${t}" "${v}" || unhomed+="${t##*/} "
done
check "the tests that start a top-level run include flow_test_runs_test.sh, sleep_scale_test.sh and this one" \
  "$(for t in flow_test_runs_test.sh sleep_scale_test.sh test_cap_test.sh; do [[ "${starters}" == *" ${t} "* ]] && printf 'yes ' || printf '%s no ' "${t}"; done)" "yes yes yes "
check "every test that starts a top-level run exports HOME under its own mktemp root" "${unhomed}" ""

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
