#!/usr/bin/env bash
# test_shard_test.sh — scripts/test.sh's SHARD=i/N split, as CI's test-shard jobs run it: ci.yml's shard
# list is 1 to N, each once, and for N = 1, 3, 4 and CI's N over the real tests/*_test.sh list, every
# file lands in exactly one shard. With make's SLOW and SERIAL and CI's N, each of those files has a
# shard of its own and comes first in it. The order does not hang on the order of the arguments. A
# shard says how many files it kept, one that keeps none fails, a SHARD that is not i/N with
# 1 <= i <= N is refused, and a test does not see SHARD.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
# shard <i/N> <file>... — the files test.sh --list keeps for that shard, with make's SLOW and SERIAL.
shard() { local s="$1"; shift; SHARD="${s}" SLOW="${slow}" SERIAL="${serial}" bash "${REPO}/scripts/test.sh" --list "$@" 2>/dev/null; }

# CI's N: the test-shard matrix list, which must be 1 to N.
list="$(sed -nE 's/^ +shard: \[(.*)\]$/\1/p' "${REPO}/.github/workflows/ci.yml")"
ci_n="$(tr ',' '\n' <<< "${list}" | grep -c .)"
check "ci.yml's shard list is 1 to N, each once" "${list// /}" "$(seq 1 "${ci_n}" | paste -sd, -)"
# make's SLOW and SERIAL, as make test passes them.
# shellcheck disable=SC2016 # make expands these
vars="$(printf 'show:\n\t@echo "$(SLOW)|$(SERIAL)"\n' | make -s -C "${REPO}" -f Makefile -f - show)"
slow="${vars%%|*}" serial="${vars#*|}"
check "make has SLOW and SERIAL files" "$([[ -n "${slow}" && -n "${serial}" ]] && echo yes)" yes

cd "${REPO}" || exit 1
files=(tests/*_test.sh)
all="$(printf '%s\n' "${files[@]}" | sort)"
for n in 1 3 4 "${ci_n}"; do
  got="$(for ((i = 1; i <= n; i++)); do shard "${i}/${n}" "${files[@]}"; done | sort)"
  check "SHARD=i/${n}: each of the ${#files[@]} tests/ files lands in exactly one shard" "${got}" "${all}"
done

# With CI's N, the SLOW then SERIAL files (each sorted) are each first in a shard of their own.
# shellcheck disable=SC2086 # split the lists into files
want="$(printf '%s\n' ${slow} | LC_ALL=C sort; printf '%s\n' ${serial} | LC_ALL=C sort)"$'\n' got=""
for ((i = 1; i <= ci_n; i++)); do
  first="$(shard "${i}/${ci_n}" "${files[@]}" | head -1)"
  case " ${slow} ${serial} " in *" ${first} "*) got+="${first}"$'\n' ;; esac
done
check "SHARD=i/${ci_n}: each SLOW and SERIAL file is first in a shard of its own, SLOW first" "${got}" "${want}"

reversed=()
for ((k = ${#files[@]} - 1; k >= 0; k--)); do reversed+=("${files[k]}"); done
check "a shard keeps the same files in the same order whatever the order of the arguments" \
  "$(shard "2/${ci_n}" "${reversed[@]}")" "$(shard "2/${ci_n}" "${files[@]}")"

check "a shard says how many files it kept" \
  "$(SHARD=2/4 bash "${REPO}/scripts/test.sh" --list a_test.sh b_test.sh c_test.sh d_test.sh e_test.sh 2>&1 >/dev/null)" \
  "shard 2/4: 1 of 5 files"
check "a shard that keeps no file fails, saying so" \
  "$(SHARD=3/3 bash "${REPO}/scripts/test.sh" --list a_test.sh b_test.sh 2>&1; echo "rc=$?")" \
  "shard 3/3: 0 of 2 files
test.sh: shard 3/3 keeps no file
rc=1"

for bad in 0/4 5/4 x 1/0 1/4/2; do
  check "SHARD=${bad} is refused" "$(SHARD="${bad}" bash "${REPO}/scripts/test.sh" --list "${files[@]}" 2>&1; echo "rc=$?")" \
    "test.sh: SHARD=${bad} is not i/N with 1 <= i <= N
rc=1"
done

# shellcheck disable=SC2016 # the stub's own shell expands it
printf '#!/usr/bin/env bash\necho "${SHARD-unset} ${SLOW-unset}" > "%s/shard.seen"\n' "${ROOT}" > "${ROOT}/env_test.sh"
SHARD=1/1 SLOW=x bash "${REPO}/scripts/test.sh" "${ROOT}/env_test.sh" > /dev/null 2>&1
check "a test does not see SHARD or SLOW" "$(cat "${ROOT}/shard.seen" 2>&1)" "unset unset"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
