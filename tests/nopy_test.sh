#!/usr/bin/env bash
# nopy_test.sh — the python3-fails harness: each fixture on tests/nopy_list.txt runs with the programs
# its line names replaced by a failing stub, and the test is red when its command starts one.
#
# A fixture is one of tests/diff_run.sh's (fx_<name> in a tests/diff_fixtures_*.sh file), and
# diff_run.sh builds and runs it, with this checkout as both trees. For each line, a wrapper fixture
# runs fx_<name>, then wraps its command in a launcher that puts a stub directory of that line's own
# first on PATH. So the stubs reach the command and what it starts, never the fixture's build (which
# keeps the real python3: merge_fixture.sh's helpers use it) nor diff_run.sh's own perl launcher, and a
# program one line names is stubbed for that fixture only. Each stub appends its argv to the fixture's
# log, prints a loud line on stderr and exits 1. The test is red when that log has a line, so a command
# that swallows the failure (python3 -c 1 || true) is still caught. It is red too when diff_run.sh
# cut the command short (TIMEOUT, RUNAWAY, STUCK), since the command may have stopped first. A call
# from inside a gh or herdr stub (FX_GH, FX_HERDR), which diff_run.sh's shim marks with
# DIFF_RUN_SHIM, runs the real program and is not logged: the stub stands in for gh, not for the
# command.
#
# It catches only a program found on PATH: one started by its absolute path (/usr/bin/python3) is out
# of its reach.
#
# The test's own fixtures, fx_nopy_self_*, run in the same diff_run.sh call and check the harness:
# a command that runs python3 -c 1 || true is red, naming the command and the program; one whose build
# runs python3 and whose command does not is green; python3 named on one fixture's line is the real one
# in another's command; a gh stub's own python3 is not counted; and a command diff_run.sh cut short
# (TIMEOUT, RUNAWAY, or STUCK past --bound) is named, since its empty log proves nothing. When the list is empty, they are
# all that runs, and the test says so.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
LIST="${REPO}/tests/nopy_list.txt"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
# A diff_run.sh still running gets a TERM and is waited on first: its own EXIT trap kills the fixture
# commands' groups, which stop_test_group, holding only this test's group, never reaches.
DR_PID=""
trap '[[ -z "${DR_PID}" ]] || { kill -TERM "${DR_PID}" 2>/dev/null; wait "${DR_PID}" 2>/dev/null; }; stop_test_group; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
export HOME="${ROOT}/home"; mkdir -p "${HOME}" "${ROOT}/stubs" "${ROOT}/log" "${ROOT}/cmd" "${ROOT}/roots"
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1: $2"; fails=$((fails + 1)); }

# NOPY_BASH: the bash the launcher and the stubs run, by its absolute path, so neither looks bash up
# on the PATH the stubs are on.
NOPY_BASH="$(command -v bash)"
export NOPY_BASH

# nopy_wrap <stub dir> <cmd file> <roots file> — in a wrapper fixture's build, after fx_<name>: write
# the command as the fixture set it to <cmd file> and the fixture root (diff_run.sh's ROOT) to <roots
# file>, then run the command through a launcher that puts <stub dir> first on PATH.
nopy_wrap() {
  local q=""
  printf -v q ' %q' "${FX_CMD[@]}"; printf '%s\n' "${q# }" > "$2"
  printf '%s\n' "${ROOT}" >> "$3"
  # shellcheck disable=SC2016 # the launcher's own $1, $PATH and $@
  FX_CMD=("${NOPY_BASH}" -c 'PATH="$1:${PATH}"; export PATH; shift; exec "$@"' nopy-launcher "$1" "${FX_CMD[@]}")
}
export -f nopy_wrap

# stub <fixture> <program> — write ${ROOT}/stubs/<fixture>/<program>. Called by the command (no
# DIFF_RUN_SHIM), it logs "<program> <args, each as printf %q quotes it>" to ${ROOT}/log/<fixture>, says
# so on stderr and exits 1. Called from inside a gh or herdr stub, it runs the real program, found on
# this test's PATH now, or exits 127 when there is none.
stub() {
  local real
  real="$(command -v "$2" 2>/dev/null || true)"; [[ "${real}" == /* ]] || real=""
  { printf '#!%s\nFX=%q PROG=%q REAL=%q LOG=%q\n' "${NOPY_BASH}" "$1" "$2" "${real}" "${ROOT}/log/$1"
    cat <<'STUB'
if [[ -n "${DIFF_RUN_SHIM:-}" ]]; then
  [[ -z "${REAL}" ]] || exec "${REAL}" "$@"
  echo "nopy: no real ${PROG} for ${DIFF_RUN_SHIM}'s stub" >&2; exit 127
fi
q=""
for a in "$@"; do printf -v q '%s %q' "${q}" "${a}"; done
printf '%s%s\n' "${PROG}" "${q}" >> "${LOG}"
echo "nopy: fixture ${FX}'s command started ${PROG}, which tests/nopy_list.txt bars, so it fails: ${PROG}${q}" >&2
exit 1
STUB
  } > "${ROOT}/stubs/$1/$2"
  chmod +x "${ROOT}/stubs/$1/$2"
}

# add <where> <fixture> <program>... — a wrapper fixture, fx_nopy__<fixture>, with a stub for each
# program, and its name on WRAPPERS. <where> names the line in a failure.
WRAPPERS=()
add() {
  local where="$1" fx="$2" p; shift 2
  [[ "${fx}" =~ ^[A-Za-z0-9_]+$ ]] || { bad "${where}" "'${fx}' is not a fixture name"; return 0; }
  [[ $# -gt 0 ]] || { bad "${where}" "${fx} names no program"; return 0; }
  [[ ! -d "${ROOT}/stubs/${fx}" ]] || { bad "${where}" "${fx} is listed twice"; return 0; }
  mkdir -p "${ROOT}/stubs/${fx}"
  for p in "$@"; do
    [[ "${p}" =~ ^[A-Za-z0-9._+-]+$ ]] || { bad "${where}" "'${p}' is not a program name"; return 0; }
    stub "${fx}" "${p}"
  done
  eval "fx_nopy__${fx}() {
    declare -F fx_${fx} > /dev/null || { echo 'nopy: no fixture fx_${fx} in tests/diff_fixtures_*.sh' >&2; return 1; }
    fx_${fx}
    nopy_wrap '${ROOT}/stubs/${fx}' '${ROOT}/cmd/${fx}' '${ROOT}/roots/${fx}'
  }"
  export -f "fx_nopy__${fx}"
  WRAPPERS+=("nopy__${fx}")
}

# The test's own fixtures. Each command is a bash -c, so it starts what it names through PATH.
# shellcheck disable=SC2034 # diff_run.sh reads the FX_ settings
fx_nopy_self_starts() { FX_CMD=(bash -c 'python3 -c 1 || true; echo swallowed'); }
# shellcheck disable=SC2034
fx_nopy_self_quiet() { python3 -c 'open("built", "w").close()'; FX_CMD=(bash -c '[ -e built ] && echo quiet'); }
# shellcheck disable=SC2034
fx_nopy_self_other() { FX_CMD=(bash -c 'python3 -c "print(6 * 7)"'); }
# shellcheck disable=SC2034
fx_nopy_self_gh() {
  printf '#!%s\nexec python3 -c "print(\\"gh-ok\\")"\n' "${NOPY_BASH}" > "${ROOT}/gh-stub"; chmod +x "${ROOT}/gh-stub"
  FX_GH="${ROOT}/gh-stub"; FX_CMD=(bash -c 'gh api x')
}
# A sleep well past --bound, which diff_run.sh counts in polls (pgrep and a 0.1 s sleep each), so on a
# slow machine the bound takes far longer than its seconds; diff_run.sh kills the sleep at the bound.
# shellcheck disable=SC2034
fx_nopy_self_stuck() { FX_CMD=(bash -c 'sleep 300 & echo left'); }
export -f fx_nopy_self_starts fx_nopy_self_quiet fx_nopy_self_other fx_nopy_self_gh fx_nopy_self_stuck
add self nopy_self_starts python3
add self nopy_self_quiet python3
add self nopy_self_other awk
add self nopy_self_gh python3
add self nopy_self_stuck python3

listed=()
n=0
while IFS= read -r line || [[ -n "${line}" ]]; do
  n=$((n + 1))
  [[ -n "${line//[[:space:]]/}" && "${line}" != \#* ]] || continue
  read -r -a words <<< "${line}"
  [[ "${words[0]}" != nopy_self_* ]] || { bad "nopy_list.txt:${n}" "${words[0]} is a name of this test's own"; continue; }
  add "nopy_list.txt:${n}" "${words[@]}"
  listed+=("${words[0]}")
done < "${LIST}"
[[ ${#listed[@]} -gt 0 ]] || echo "note tests/nopy_list.txt lists no fixture yet: only this test's own fixtures run"

rc=0
bash "${REPO}/tests/diff_run.sh" --keep "${ROOT}/keep" "${REPO}" "${REPO}" "${WRAPPERS[@]}" > "${ROOT}/out" 2>&1 &
DR_PID=$!; wait "${DR_PID}" || rc=$?; DR_PID=""
# Exit 1 is a difference between the two runs of this one tree, which is diff_run_test.sh's to catch,
# or a command diff_run.sh killed (cut below, by its fixture); exit 2 is a fixture that did not build,
# so its command never ran.
[[ ${rc} -ne 2 ]] || { bad diff_run "a fixture did not build"; sed 's/^/  | /' "${ROOT}/out"; }

# unroot <fixture> — stdin with each of its two fixture roots (one a side) as <root>.
unroot() {
  local c r
  while IFS= read -r c; do
    while IFS= read -r r; do [[ -z "${r}" ]] || c="${c//"${r}"/<root>}"; done < "${ROOT}/roots/$1"
    printf '%s\n' "${c}"
  done
}
# calls <fixture> — the distinct calls its stubs logged, one line each, so a call both sides made shows
# once.
calls() { [[ ! -s "${ROOT}/log/$1" ]] || unroot "$1" < "${ROOT}/log/$1" | LC_ALL=C sort -u; }
# reds <fixture> — one line a call: the command, the program it started and the call.
reds() {
  local c cmd
  cmd="$(unroot "$1" < "${ROOT}/cmd/$1")"
  calls "$1" | while IFS= read -r c; do echo "its command (${cmd}) started ${c%% *}, which its line bars: ${c}"; done
}
# stdout <fixture> — what its command printed, on side a.
stdout() { cat "${ROOT}/keep/nopy__$1/a/stdout" 2>/dev/null || true; }
# ran <fixture> — its build reached nopy_wrap, so its command ran under the stubs.
ran() { [[ -s "${ROOT}/cmd/$1" ]]; }
# cut <fixture> — diff_run.sh's TIMEOUT, RUNAWAY and STUCK lines for it: a command it killed, or one that
# left a process past --bound, may have stopped before the call its line bars, so its empty log proves
# nothing.
cut() { grep -E "^(TIMEOUT|RUNAWAY|STUCK) nopy__$1 " "${ROOT}/out" || true; }

# (1) A swallowed python3 call is red, naming the command and the call, as a listed fixture's FAIL
# line below does.
printf -v want ' %q' bash -c 'python3 -c 1 || true; echo swallowed'
want="its command (${want# }) started python3, which its line bars: python3 -c 1"
got="$(ran nopy_self_starts && reds nopy_self_starts)" || true
if [[ "${got}" == "${want}" ]]; then ok "a command that swallows python3 -c 1 is red, by its command and the call"
else bad "self starts" "got '${got}', not '${want}'"; fi
if [[ "$(stdout nopy_self_starts)" == swallowed ]]; then ok "the command went on past the failed python3"
else bad "self starts" "stdout '$(stdout nopy_self_starts)', not swallowed"; fi
# (2, 4) A build that runs python3 and a command that does not: green, and the build's file is there.
if ran nopy_self_quiet && [[ -z "$(calls nopy_self_quiet)" ]] && [[ "$(stdout nopy_self_quiet)" == quiet ]]; then
  ok "a build's own python3 is not stubbed, and a command that starts none passes"
else bad "self quiet" "logged '$(calls nopy_self_quiet)', stdout '$(stdout nopy_self_quiet)'"; fi
# (3) python3 on another fixture's line is the real one here.
if ran nopy_self_other && [[ -z "$(calls nopy_self_other)" ]] && [[ "$(stdout nopy_self_other)" == 42 ]]; then
  ok "a program named for one fixture is stubbed for that fixture only"
else bad "self other" "logged '$(calls nopy_self_other)', stdout '$(stdout nopy_self_other)', not 42"; fi
# A gh stub's python3 is the real one, and not the command's.
if ran nopy_self_gh && [[ -z "$(calls nopy_self_gh)" ]] && [[ "$(stdout nopy_self_gh)" == gh-ok ]]; then
  ok "a gh stub's own python3 runs and is not counted"
else bad "self gh" "logged '$(calls nopy_self_gh)', stdout '$(stdout nopy_self_gh)', not gh-ok"; fi

# A command that leaves a process past --bound is cut, by its fixture.
if [[ "$(cut nopy_self_stuck)" == "STUCK nopy__nopy_self_stuck "* ]] && [[ -z "$(cut nopy_self_quiet)" ]]; then
  ok "a command diff_run.sh cuts short is named, and only that one"
else bad "self stuck" "cut '$(cut nopy_self_stuck)', quiet's '$(cut nopy_self_quiet)'"; fi

# Each listed fixture: green when it ran to its end and its stubs logged nothing.
for fx in ${listed[@]+"${listed[@]}"}; do
  if ! ran "${fx}"; then bad "${fx}" "its command never ran under the stubs"; continue; fi
  got="$(cut "${fx}")"
  if [[ -n "${got}" ]]; then
    while IFS= read -r c; do bad "${fx}" "diff_run.sh cut its run short, so its log proves nothing: ${c}"; done <<< "${got}"
    continue
  fi
  got="$(reds "${fx}")"
  if [[ -z "${got}" ]]; then ok "${fx} starts no program its line bars"; continue; fi
  while IFS= read -r c; do bad "${fx}" "${c}"; done <<< "${got}"
done

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
