#!/usr/bin/env bash
# test_refusal_test.sh — scripts/test.sh, and so make test, refuses under codex. With CODEX_SANDBOX
# or CODEX_THREAD_ID set (codex sets both in its own shell), each exits non-zero with its one-line
# refusal before a stub test runs: the stub's marker is absent, and there is no "run" line, no line
# in TEST_RUNS_LOG and no test-runs.d beside it. With neither set, the same stub runs and the log gets
# its start and end lines, so the looks above can fail. Neither variable is one an agent starts with
# (AGENT_ENV, AGENT_SET or an AGENT_PREFIXES prefix), so the refusal never stops a builder. The inner
# make runs without the outer make's MAKEFLAGS, so `make test SHARD=i/N` does not shard the stub away.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
export HOME="${ROOT}/home"   # under its own root, so parallel runs share no ~
mkdir -p "${HOME}"
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

STUB="${ROOT}/stub_test.sh" MARK="${ROOT}/stub-ran" LOGS="${ROOT}/logs"
printf ': > "%s"\n' "${MARK}" > "${STUB}"
refusal() { echo "test.sh: refused under codex ($1 is set): the suite does not run in a codex session; run make test outside codex"; }

# run_stub <script|make> [NAME=value] — the stub run through scripts/test.sh or make test, from a fresh
# start, with no CODEX_* but the one given, none of an outer make's flags (MAKEFLAGS would hand its
# SHARD or TESTS to the inner make) and TEST_RUNS_LOG an empty file: its exit (0 or non-zero),
# its refusal line or none, whether it printed the stub's "run" line, whether the stub ran, the log's
# lines (start or end) and whether test-runs.d exists. One field a line.
run_stub() {
  local how="$1" rc=0 out
  shift
  rm -rf "${LOGS}" "${MARK}"; mkdir "${LOGS}"; : > "${LOGS}/test-runs.tsv"
  local cmd=(bash "${REPO}/scripts/test.sh" "${STUB}")
  [[ "${how}" == script ]] || cmd=(make -s -C "${REPO}" test TESTS="${STUB}" SERIAL= JOBS=1)
  out="$(cd "${ROOT}" && env -u CODEX_SANDBOX -u CODEX_THREAD_ID -u MAKEFLAGS -u MAKELEVEL -u MFLAGS TEST_RUNS_LOG="${LOGS}/test-runs.tsv" "$@" "${cmd[@]}" 2>&1)" || rc=$?
  if [[ ${rc} -eq 0 ]]; then echo "exit 0"; else echo "exit non-zero"; fi
  grep '^test.sh: refused' <<< "${out}" || echo "no refusal"
  if grep -qx "run  ${STUB}" <<< "${out}"; then echo "run line"; else echo "no run line"; fi
  if [[ -e "${MARK}" ]]; then echo "stub ran"; else echo "stub not run"; fi
  echo "log: $(awk -F '\t' '{ printf "%s ", ($2 == "" ? "start" : "end") }' "${LOGS}/test-runs.tsv")"
  if [[ -d "${LOGS}/test-runs.d" ]]; then echo "test-runs.d"; else echo "no test-runs.d"; fi
}

for v in CODEX_SANDBOX CODEX_THREAD_ID; do
  check "with ${v} set, scripts/test.sh refuses in one line before the stub, its run line, the log line and the mark" \
    "$(run_stub script "${v}=x")" "$(printf 'exit non-zero\n%s\nno run line\nstub not run\nlog: \nno test-runs.d' "$(refusal "${v}")")"
done
check "with CODEX_SANDBOX set, make test refuses the same way" \
  "$(run_stub make CODEX_SANDBOX=seatbelt)" "$(printf 'exit non-zero\n%s\nno run line\nstub not run\nlog: \nno test-runs.d' "$(refusal CODEX_SANDBOX)")"
for how in script make; do
  check "with neither set, the stub runs through ${how} and the log gets its start and end lines, so the looks above can fail" \
    "$(run_stub "${how}")" "$(printf 'exit 0\nno refusal\nrun line\nstub ran\nlog: start end \ntest-runs.d')"
done

# reaches_agent <name> — yes when every agent starts with <name>: named in AGENT_ENV or AGENT_SET, or
# under an AGENT_PREFIXES prefix.
reaches_agent() {
  bash -c 'source "$1/bin/lib/agents.sh"
    [[ " ${AGENT_ENV} ${AGENT_SET} " != *" $2 "* ]] || { echo yes; exit; }
    for p in ${AGENT_PREFIXES}; do [[ "$2" != "${p}"* ]] || { echo yes; exit; }; done
    echo no' _ "${REPO}" "$1"
}
check "no agent starts with CODEX_SANDBOX or CODEX_THREAD_ID, while CODEX_HOME and LC_ALL reach every agent" \
  "$(reaches_agent CODEX_SANDBOX) $(reaches_agent CODEX_THREAD_ID) $(reaches_agent CODEX_HOME) $(reaches_agent LC_ALL)" "no no yes yes"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
