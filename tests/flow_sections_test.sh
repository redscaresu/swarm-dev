#!/usr/bin/env bash
# flow_sections_test.sh — flow runs every bin/lib/flow_*.py: a section file dropped into a copy of
# bin/lib prints its line in flow's output, under its own `## <name>` line and after the others in
# name order, with no other file changed.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
mkdir -p "${dir}/plugin" "${dir}/repo/.swarm"
cp -R "${REPO}/bin" "${REPO}/docs" "${dir}/plugin/"
git -C "${dir}/repo" init -q
printf 'print(f"zz_test saw since {since}, until {until}, epic {epic!r}, {len(rows)} rows")\n' > "${dir}/plugin/bin/lib/flow_zz_test.py"

out="$(cd "${dir}/repo" && env -u HERDR_ENV -u SWARM_PROJECT bash "${dir}/plugin/bin/swarm.sh" flow --since 2026-10-01 --epic e1)"
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
check "the dropped-in section prints its line, with the window, under its name, last" "$(tail -2 <<< "${out}")" \
  "$(printf '%s\n' "## zz_test" "zz_test saw since 2026-10-01, until 9999-12-30, epic 'e1', 0 rows")"
check "each section in name order" "$(grep '^## ' <<< "${out}" | tr '\n' ' ')" "## cost ## features ## reviewers ## throughput ## zz_test "
check "the copy differs from bin/lib by that file alone" "$(diff -rq -x __pycache__ "${REPO}/bin" "${dir}/plugin/bin" || true)" \
  "Only in ${dir}/plugin/bin/lib: flow_zz_test.py"

[[ ${fails} -eq 0 ]] || { echo "${out}"; echo "${fails} failed"; exit 1; }
echo "all passed"
