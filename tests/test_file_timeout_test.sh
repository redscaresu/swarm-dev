#!/usr/bin/env bash
# test_file_timeout_test.sh — scripts/test.sh refuses a TEST_FILE_TIMEOUT that is not a whole number of
# seconds. It stops a test file that runs past the limit: the file fails as "TIMEOUT <file> after <n>s"
# with its last output, within seconds, and nothing it started is left running. A file that finishes
# inside the limit still passes.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

secs_marker="7${RANDOM}"; marker="sleep ${secs_marker}"
# The fixture starts a background process and a foreground one, both past the limit.
printf '#!/usr/bin/env bash\necho before-hang\nsleep %s &\nsleep %s\n' "${secs_marker}" "${secs_marker}" > "${ROOT}/hang_test.sh"
# A file that exits 0 on TERM still fails: it ran past the limit.
printf '#!/usr/bin/env bash\ntrap "exit 0" TERM\nwhile :; do sleep 0.1; done\n' > "${ROOT}/term0_test.sh"
printf '#!/usr/bin/env bash\necho fine\n' > "${ROOT}/quick_test.sh"

t0=${SECONDS}
out="$(TEST_FILE_TIMEOUT=2 bash "${REPO}/scripts/test.sh" "${ROOT}/hang_test.sh" 2>&1)" && rc=0 || rc=$?
secs=$((SECONDS - t0))
check "a file past the limit fails" "${rc}" 1
check "it is named TIMEOUT with the file and the limit" "$(grep -Ec "^TIMEOUT ${ROOT}/hang_test.sh after [0-9]+s$" <<< "${out}")" 1
check "its output so far is printed" "$(grep -c '^before-hang$' <<< "${out}")" 1
check "it ends within 10 seconds" "$([[ ${secs} -lt 10 ]] && echo yes)" yes
pgrep -f "^${marker}\$" > /dev/null && left=found || left=$?   # 1: no match; 2 or more: pgrep itself failed
check "nothing it started is left running" "${left}" 1

out="$(TEST_FILE_TIMEOUT=2 bash "${REPO}/scripts/test.sh" "${ROOT}/term0_test.sh" 2>&1)" && rc=0 || rc=$?
check "a file that exits 0 on TERM past the limit still fails as TIMEOUT" "${rc}/$(grep -Ec "^TIMEOUT ${ROOT}/term0_test.sh after [0-9]+s$" <<< "${out}")" "1/1"

for bad in 0 1.5 abc 10m; do
  check "TEST_FILE_TIMEOUT=${bad} is refused" "$(TEST_FILE_TIMEOUT="${bad}" bash "${REPO}/scripts/test.sh" "${ROOT}/quick_test.sh" 2>&1; echo "rc=$?")" \
    "test.sh: TEST_FILE_TIMEOUT=${bad} is not a whole number of seconds, 1 or more
rc=1"
done

out="$(TEST_FILE_TIMEOUT=2 bash "${REPO}/scripts/test.sh" "${ROOT}/quick_test.sh" 2>&1)" && rc=0 || rc=$?
check "a file inside the limit passes" "${rc}" 0
check "it says ok, not TIMEOUT" "$(grep -c '^ok ' <<< "${out}")/$(grep -c TIMEOUT <<< "${out}" || true)" "1/0"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
