#!/usr/bin/env bash
# test_file_timeout_test.sh — scripts/test.sh refuses a TEST_FILE_TIMEOUT that is not a whole number of
# seconds. It stops a test file that runs past the limit: the file fails as "TIMEOUT <file> after <n>s"
# with its last output, within seconds, and nothing it started is left running. A file that finishes
# inside the limit still passes.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

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
# timeout_secs <output> <file> — the seconds in the "TIMEOUT <file> after <n>s" line, or nothing.
timeout_secs() { local l; l="$(grep -F "TIMEOUT $2 after " <<< "$1" | head -1)"; l="${l##* after }"; l="${l%s}"; [[ "${l}" =~ ^[0-9]+$ ]] && echo "${l}"; return 0; }
n="$(timeout_secs "${out}" "${ROOT}/hang_test.sh")"
check "it is named TIMEOUT with the file and at least the limit's seconds" "$([[ -n "${n}" && ${n} -ge 2 ]] && echo yes)" yes
check "the phase summary says it timed out and that the log was cut" "$(grep -cF "TIMEOUT ${ROOT}/hang_test.sh after " <<< "${out}")/$(grep -c '(last 20 lines)$' <<< "${out}")" "2/1"
check "its output so far is printed" "$(grep -c '^before-hang$' <<< "${out}")" 1
check "it ends within 10 seconds" "$([[ ${secs} -lt 10 ]] && echo yes)" yes
pgrep -f "^${marker}\$" > /dev/null && left=found || left=$?   # 1: no match; 2 or more: pgrep itself failed
check "nothing it started is left running" "${left}" 1

out="$(TEST_FILE_TIMEOUT=2 bash "${REPO}/scripts/test.sh" "${ROOT}/term0_test.sh" 2>&1)" && rc=0 || rc=$?
n="$(timeout_secs "${out}" "${ROOT}/term0_test.sh")"
check "a file that exits 0 on TERM past the limit still fails as TIMEOUT" "${rc}/$([[ -n "${n}" && ${n} -ge 2 ]] && echo yes)" "1/yes"

# A file in SLOW gets three times the limit: 3 s of work passes at 2 s x 3, and times out at 2 s alone.
printf '#!/usr/bin/env bash\nsleep 3\n' > "${ROOT}/two_test.sh"
TEST_FILE_TIMEOUT=2 SLOW="${ROOT}/two_test.sh" bash "${REPO}/scripts/test.sh" "${ROOT}/two_test.sh" > /dev/null 2>&1 && rc=0 || rc=$?
check "a SLOW file gets three times the limit" "${rc}" 0
out="$(TEST_FILE_TIMEOUT=2 bash "${REPO}/scripts/test.sh" "${ROOT}/two_test.sh" 2>&1)" && rc=0 || rc=$?
check "the same file outside SLOW times out at the limit" "${rc}/$([[ -n "$(timeout_secs "${out}" "${ROOT}/two_test.sh")" ]] && echo yes)" "1/yes"

# test.sh run directly defaults SWARM_SLEEP_SCALE to 0.01, as the Makefile does, and keeps one that is set.
# shellcheck disable=SC2016 # the fixture's own shell expands it
printf '#!/usr/bin/env bash\necho "${SWARM_SLEEP_SCALE-unset}" > "%s/scale.seen"\n' "${ROOT}" > "${ROOT}/scale_test.sh"
env -u SWARM_SLEEP_SCALE bash "${REPO}/scripts/test.sh" "${ROOT}/scale_test.sh" > /dev/null 2>&1
check "SWARM_SLEEP_SCALE defaults to 0.01" "$(cat "${ROOT}/scale.seen")" 0.01
SWARM_SLEEP_SCALE=0.5 bash "${REPO}/scripts/test.sh" "${ROOT}/scale_test.sh" > /dev/null 2>&1
check "a SWARM_SLEEP_SCALE that is set is kept" "$(cat "${ROOT}/scale.seen")" 0.5

# A test sees no SWARM_* the caller set (a builder's pane names its real project in them) but
# SWARM_SLEEP_SCALE, and SWARM_NO_CI_REFRESH=1, so it starts no ci refresh; and SWARM_PROJECT names the
# job's own stand-in, <its TMPDIR>/pane, never the caller's.
printf '#!/usr/bin/env bash\nenv | grep "^SWARM_" | sort > "%s/env.seen"\n' "${ROOT}" > "${ROOT}/env_test.sh"
SWARM_PROJECT=/real SWARM_AGENT=builder SWARM_GH_LOG=/real/.swarm/gh-calls.tsv SWARM_NO_CI_REFRESH='' SWARM_ANY_NEW=x SWARM_SLEEP_SCALE=0.01 \
  bash "${REPO}/scripts/test.sh" "${ROOT}/env_test.sh" > /dev/null 2>&1
check "no SWARM_* the caller set reaches a test but SWARM_SLEEP_SCALE; SWARM_NO_CI_REFRESH is 1 and SWARM_PROJECT the job's pane stand-in" \
  "$(sed -E 's#^SWARM_PROJECT=/.*/tmp\.[A-Za-z0-9]+/pane$#SWARM_PROJECT=<TMPDIR>/pane#' "${ROOT}/env.seen")" \
  "SWARM_NO_CI_REFRESH=1
SWARM_PROJECT=<TMPDIR>/pane
SWARM_SLEEP_SCALE=0.01"

check "--list runs nothing, so a bad TEST_FILE_TIMEOUT does not stop it" "$(TEST_FILE_TIMEOUT=abc bash "${REPO}/scripts/test.sh" --list "${ROOT}/quick_test.sh" 2>&1; echo "rc=$?")" "${ROOT}/quick_test.sh
rc=0"
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
