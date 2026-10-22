#!/usr/bin/env bash
# test_shard_test.sh — scripts/test.sh's SHARD=i/N split, as CI's test-shard jobs run it: for N = 1, 3
# and 4 over the real tests/*_test.sh list, every file lands in exactly one shard. A SHARD that is not
# i/N with 1 <= i <= N is refused, and a test does not see SHARD.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

files=("${REPO}"/tests/*_test.sh)
all="$(printf '%s\n' "${files[@]}" | sort)"
for n in 1 3 4; do
  got="$(for ((i = 1; i <= n; i++)); do SHARD="${i}/${n}" bash "${REPO}/scripts/test.sh" --list "${files[@]}"; done | sort)"
  check "SHARD=i/${n}: each of the ${#files[@]} tests/ files lands in exactly one shard" "${got}" "${all}"
done

for bad in 0/4 5/4 x 1/0 1/4/2; do
  check "SHARD=${bad} is refused" "$(SHARD="${bad}" bash "${REPO}/scripts/test.sh" --list "${files[@]}" 2>&1; echo "rc=$?")" \
    "test.sh: SHARD=${bad} is not i/N with 1 <= i <= N
rc=1"
done

# shellcheck disable=SC2016 # the stub's own shell expands it
printf '#!/usr/bin/env bash\necho "${SHARD-unset}" > "%s/shard.seen"\n' "${ROOT}" > "${ROOT}/env_test.sh"
SHARD=1/1 bash "${REPO}/scripts/test.sh" "${ROOT}/env_test.sh" > /dev/null
check "a test does not see SHARD" "$(cat "${ROOT}/shard.seen" 2>&1)" unset

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
