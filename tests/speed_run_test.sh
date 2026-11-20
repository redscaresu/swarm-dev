#!/usr/bin/env bash
# speed_run_test.sh — tests/speed_run.sh, the speed run, on two copies of its harness at different
# paths, with at most 3 timed runs a tree. It times two commands of a probe script this test writes into
# each copy, a /bin/sh with a case arm each and nothing else, through fixtures of its own in copy a: a
# swarm.sh command starts dozens of processes, and on a busy machine the time those take swings by
# seconds, past any margin, while the probe's noise stays under the 100 ms floor.
# (1) Two copies of one tree pass. (2) With a /bin/sleep longer than the margin seeded into b's probe
# command one, the run fails that command and not command two. (3) With one extra external exec
# (/usr/bin/true) in b's command one, where strace can count, b's row shows exactly one more process
# start; where it cannot (no strace, or SPEED_RUN_STRACE naming none, checked on every machine), both
# counts say `not measured`, and --require-count fails the run; a counter named by a relative path is
# found from each command's cwd, and a count run that leaves no trace reads `not measured`. (4) An unknown list entry is red and
# nothing is timed; every entry of tests/speed_list.txt names a fixture. And a fixture with a step that
# fails before it sets FX_CMD is BUILD-FAIL, never timed; and a TERM to the run while a command runs
# leaves nothing behind, not even a child its command put in a group of its own.
# shellcheck disable=SC2016 # the probe is sh code, expanded when it runs
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${ROOT}" && pwd -P)"
# A speed_run.sh still running gets a TERM and is waited on first: its own EXIT trap kills the running
# command's group, which stop_test_group, holding only this test's group, never reaches.
SR_PID=""
trap '[[ -z "${SR_PID}" ]] || { kill -TERM "${SR_PID}" 2>/dev/null; wait "${SR_PID}" 2>/dev/null; }; stop_test_group; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
export HOME="${ROOT}/home"; mkdir -p "${HOME}"
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1: $2"; sed 's/^/  | /' "${ROOT}/out"; fails=$((fails + 1)); }

# Two copies at paths of different lengths: the harness, its fixtures and list, and the probe.
A="${ROOT}/a" B="${ROOT}/copies/b"
for t in "${A}" "${B}"; do
  mkdir -p "${t}/tests"
  (cd "${REPO}" && tar -cf - tests/speed_run.sh tests/speed_list.txt tests/diff_fixtures_*.sh) | tar -C "${t}" -xf -
  printf '%s\n' 'case "$1" in' '  one) ;;' '  two) ;;' 'esac' > "${t}/tests/speed_probe.sh"
done
cat > "${A}/tests/diff_fixtures_speedtest.sh" <<'FX'
# shellcheck shell=bash
fx_speedtest_one() { FX_CMD=(/bin/sh "${TREE}/tests/speed_probe.sh" one); }
fx_speedtest_two() { FX_CMD=(/bin/sh "${TREE}/tests/speed_probe.sh" two); }
# A supervisor, as bin/lib/merge.sh's within is: its child in a group of its own, killed on TERM.
fx_speedtest_hang() {
  FX_CMD=(perl -e '$p = fork; if (!$p) { setpgrp; exec "/bin/sh", "-c", "sleep 30; :", $ARGV[0] }
    $SIG{TERM} = sub { kill "KILL", -$p, $p; exit 143 }; waitpid $p, 0' "speed-run-hang-${SPEED_TEST_TAG}")
}
fx_speedtest_broken() { false; FX_CMD=(/bin/sh "${TREE}/tests/speed_probe.sh" two); }
FX
printf '%s\n' speedtest_one speedtest_two > "${ROOT}/two.txt"
printf '%s\n' speedtest_one > "${ROOT}/one.txt"

# run <rc> [speed_run args...] — run a's speed_run.sh, its output in ${ROOT}/out, and check its exit.
run() {
  local want="$1" rc=0; shift
  bash "${A}/tests/speed_run.sh" "$@" > "${ROOT}/out" 2>&1 &
  SR_PID=$!; wait "${SR_PID}" || rc=$?; SR_PID=""
  [[ ${rc} == "${want}" ]] || { echo "exit ${rc}, not ${want}"; return 1; }
}
# row <command> — the last run's report row for <command>, its fields one space apart.
row() { awk -v c="$1" '$1 == c { $1 = $1; print }' "${ROOT}/out"; }
# seed <text> — b's command one runs <text>; unseed puts it back.
seed() { printf '%s\n' 'case "$1" in' "  one) $1 ;;" '  two) ;;' 'esac' > "${B}/tests/speed_probe.sh"; }
unseed() { printf '%s\n' 'case "$1" in' '  one) ;;' '  two) ;;' 'esac' > "${B}/tests/speed_probe.sh"; }

# (1) Two copies of one tree pass.
if run 0 --runs 3 --list "${ROOT}/two.txt" "${A}" "${B}" > "${ROOT}/why" \
  && [[ "$(row speedtest_one)" =~ ' ok'$ && "$(row speedtest_two)" =~ ' ok'$ ]]; then ok "two copies of one tree pass"
else bad "two copies of one tree pass" "$(cat "${ROOT}/why")"; fi

# (2) A 2-second /bin/sleep: past 20% of a command this cheap and past the 100 ms floor, and an
# external sleep, which SWARM_SLEEP_SCALE does not shrink.
seed "/bin/sleep 2"
if run 1 --runs 3 --list "${ROOT}/two.txt" "${A}" "${B}" > "${ROOT}/why" \
  && grep -qE '^SLOWER speedtest_one: b.s median [0-9]+ ms is [0-9]+ ms over a.s [0-9]+ ms' "${ROOT}/out" \
  && [[ "$(row speedtest_one)" =~ ' SLOWER'$ ]]; then ok "a sleep seeded into one command fails that command"
else bad "a sleep seeded into one command fails that command" "$(cat "${ROOT}/why")"; fi
if ! grep -q '^SLOWER speedtest_two' "${ROOT}/out" && [[ "$(row speedtest_two)" =~ ' ok'$ ]]; then ok "the seeded sleep fails no other command"
else bad "the seeded sleep fails no other command" "command two's row: $(row speedtest_two)"; fi
unseed

# (3) One extra external exec. A shell's true is a builtin; /usr/bin/true is a process.
seed /usr/bin/true
run 0 --runs 1 --list "${ROOT}/one.txt" "${A}" "${B}" > "${ROOT}/why" || true
r="$(row speedtest_one)"
if grep -q '^process starts: not measured' "${ROOT}/out"; then
  echo "     (no counter here: $(sed -n 's/^process starts: //p' "${ROOT}/out"); the not-measured checks below still run)"
elif [[ "${r}" =~ ^speedtest_one\ [0-9]+\ ms\ [0-9]+\ ms\ ([0-9]+)\ ([0-9]+)\  ]] && [[ $((BASH_REMATCH[2] - BASH_REMATCH[1])) -eq 1 ]]; then
  ok "one extra exec shows as exactly one more process start (${BASH_REMATCH[1]} and ${BASH_REMATCH[2]})"
else bad "one extra exec shows as exactly one more process start" "row '${r}'"; fi
# No counter: SPEED_RUN_STRACE names none, so this runs on a machine that has strace too. Its exit is
# not checked: on a busy machine the extra process start alone can pass the 100 ms floor.
export SPEED_RUN_STRACE="${ROOT}/no-strace"
run 0 --runs 1 --list "${ROOT}/one.txt" "${A}" "${B}" > "${ROOT}/why" || true
if grep -qF "process starts: not measured (no ${ROOT}/no-strace on PATH)" "${ROOT}/out" \
  && [[ "$(row speedtest_one)" =~ ' ms not measured not measured '(ok|SLOWER)$ ]] && ! grep -q NOT-COUNTED "${ROOT}/out"; then
  ok "with no counter, each count says not measured, never 0"
else bad "with no counter, each count says not measured, never 0" "$(cat "${ROOT}/why")"; fi
if run 1 --runs 1 --require-count --list "${ROOT}/one.txt" "${A}" "${B}" > "${ROOT}/why" \
  && grep -qF "NOT-COUNTED: --require-count, and process starts were not measured: no ${ROOT}/no-strace on PATH" "${ROOT}/out"; then
  ok "with no counter, --require-count fails the run"
else bad "with no counter, --require-count fails the run" "$(cat "${ROOT}/why")"; fi
# Two stand-in counters, which check speed_run.sh's use of a counter, not strace: each writes a trace of
# one exec to its -o file, for every run or for the probe only, then runs the command after --.
for m in all probe; do
  cat > "${ROOT}/fake-${m}" <<FAKE
#!/bin/bash
out=""; while [[ \$# -gt 0 && "\$1" != -- ]]; do [[ "\$1" != -o ]] || { out="\$2"; shift; }; shift; done; shift
[[ ${m} == all || "\$1" == /usr/bin/true ]] && echo '1 execve("/x", [], []) = 0' > "\${out}"
exec "\$@"
FAKE
  chmod +x "${ROOT}/fake-${m}"
done
# A relative counter is made absolute: each command runs from a cwd of its own.
export SPEED_RUN_STRACE=./fake-all
(cd "${ROOT}" && run 0 --runs 1 --require-count --list "${ROOT}/one.txt" "${A}" "${B}") > "${ROOT}/why" || true
if [[ "$(row speedtest_one)" =~ ' ms 1 1 '(ok|SLOWER)$ ]] && ! grep -q NOT-COUNTED "${ROOT}/out"; then ok "a relative counter is found from the command's cwd"
else bad "a relative counter is found from the command's cwd" "$(cat "${ROOT}/why")"; fi
# A counter that writes no trace on a run counts nothing: not measured, and --require-count fails.
export SPEED_RUN_STRACE="${ROOT}/fake-probe"
if run 1 --runs 1 --require-count --list "${ROOT}/one.txt" "${A}" "${B}" > "${ROOT}/why" \
  && grep -q "^COUNT-FAIL speedtest_one (a): ${ROOT}/fake-probe wrote no trace" "${ROOT}/out" \
  && [[ "$(row speedtest_one)" =~ ' ms not measured not measured '(ok|SLOWER)$ ]] && grep -q '^NOT-COUNTED: ' "${ROOT}/out"; then
  ok "a counter that writes no trace leaves the counts not measured, and --require-count fails"
else bad "a counter that writes no trace leaves the counts not measured, and --require-count fails" "$(cat "${ROOT}/why")"; fi
unset SPEED_RUN_STRACE
unseed

# (4) An unknown entry is red before anything is timed, and the shipped list's entries all name one.
{ sed 's/#.*//' "${A}/tests/speed_list.txt"; echo nosuch; } > "${ROOT}/unknown.txt"
if run 1 --list "${ROOT}/unknown.txt" "${A}" "${B}" > "${ROOT}/why" \
  && [[ "$(grep '^UNKNOWN' "${ROOT}/out")" == "UNKNOWN nosuch: no fixture fx_nosuch in ${A}/tests/diff_fixtures_*.sh" ]] \
  && ! grep -q 'median' "${ROOT}/out"; then ok "an unknown list entry is red, and every entry of speed_list.txt names a fixture"
else bad "an unknown list entry is red, and every entry of speed_list.txt names a fixture" "$(cat "${ROOT}/why")"; fi

# A fixture step that fails fails the build, though the fixture sets FX_CMD after it.
echo speedtest_broken > "${ROOT}/broken.txt"
if run 2 --runs 1 --list "${ROOT}/broken.txt" "${A}" "${B}" > "${ROOT}/why" \
  && grep -q '^BUILD-FAIL speedtest_broken (a: ' "${ROOT}/out" && [[ "$(row speedtest_broken)" =~ ' BUILD-FAIL'$ ]]; then
  ok "a fixture step that fails is BUILD-FAIL"
else bad "a fixture step that fails is BUILD-FAIL" "$(cat "${ROOT}/why")"; fi

# A TERM while a command runs: the run's trap TERMs the command's group before it KILLs it, so the
# supervisor there kills its child's group too.
export SPEED_TEST_TAG="$$"
echo speedtest_hang > "${ROOT}/hang.txt"
bash "${A}/tests/speed_run.sh" --runs 1 --list "${ROOT}/hang.txt" "${A}" "${B}" > "${ROOT}/out" 2>&1 &
SR_PID=$!
hang="" g=""
# The child, by its own argv: the runner's and the supervisor's hold the same words after perl's.
for ((i = 0; i < 300; i++)); do
  hang="$(pgrep -f "^/bin/sh -c sleep 30; : [s]peed-run-hang-${SPEED_TEST_TAG}\$" | head -1)" || true
  [[ -z "${hang}" ]] || break; sleep 0.1
done
[[ -z "${hang}" ]] || g="$(ps -o pgid= -p "${hang}" | tr -d ' ')"
kill -TERM "${SR_PID}" 2>/dev/null || true; rc=0; wait "${SR_PID}" || rc=$?; SR_PID=""
left=""; for ((i = 0; i < 20; i++)); do left="$(pgrep -g "${g:-0}" 2>/dev/null || true)"; [[ -n "${left}" ]] || break; sleep 0.1; done
if [[ -n "${g}" && "${g}" != "$(ps -o pgid= -p $$ | tr -d ' ')" && ${rc} -eq 143 && -z "${left}" ]]; then
  ok "a TERM while a command runs leaves no child group behind"
else
  bad "a TERM while a command runs leaves no child group behind" "command pid '${hang}', group '${g}', exit ${rc}, left '${left}'"
  [[ -z "${left}" ]] || kill -KILL -- "-${g}" 2>/dev/null || true
fi
unset SPEED_TEST_TAG

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
