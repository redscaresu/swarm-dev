#!/usr/bin/env bash
# flow_sections_test.sh — flow runs every bin/lib/flow_*.py: a section file dropped into a copy of
# bin/lib prints its line in flow's output, under its own `## <name>` line and after the others in
# name order, with no other file changed. A section that raises prints its error under its heading,
# the sections after it still run, and flow exits 1. So does one that calls sys.exit(3); one that
# calls sys.exit(0) only ends itself.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
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
check "each section in name order" "$(grep '^## ' <<< "${out}" | tr '\n' ' ')" "## ci_health ## cost ## epic_totals ## features ## gh_calls ## holds ## idle_slots ## incidents ## lead_queue ## merge_ins ## merges ## model_fit ## predictions ## review_loops ## reviewers ## run_times ## start_failures ## test_runs ## throughput ## time_in_state ## zz_test "
check "the copy differs from bin/lib by that file alone" "$(diff -rq -x __pycache__ "${REPO}/bin" "${dir}/plugin/bin" || true)" \
  "Only in ${dir}/plugin/bin/lib: flow_zz_test.py"

printf 'raise RuntimeError("boom")\n' > "${dir}/plugin/bin/lib/flow_aa_boom.py"
printf 'import sys\nsys.exit(3)\n' > "${dir}/plugin/bin/lib/flow_ab_exit.py"
printf 'import sys\nprint("done early")\nsys.exit(0)\nprint("never")\n' > "${dir}/plugin/bin/lib/flow_ac_done.py"
out="$(cd "${dir}/repo" && env -u HERDR_ENV -u SWARM_PROJECT bash "${dir}/plugin/bin/swarm.sh" flow 2>/dev/null)" && code=0 || code=$?
check "a section that raises prints its error under its heading" "$(sed -n 1,2p <<< "${out}")" "$(printf '%s\n' "## aa_boom" "error: aa_boom: boom")"
check "the sections after it still run" "$(grep '^## ' <<< "${out}" | tr '\n' ' ')" "## aa_boom ## ab_exit ## ac_done ## ci_health ## cost ## epic_totals ## features ## gh_calls ## holds ## idle_slots ## incidents ## lead_queue ## merge_ins ## merges ## model_fit ## predictions ## review_loops ## reviewers ## run_times ## start_failures ## test_runs ## throughput ## time_in_state ## zz_test "
check "a section's sys.exit(3) is its error, under its heading" "$(sed -n '/^## ab_exit$/,/^## /p' <<< "${out}")" "$(printf '%s\n' "## ab_exit" "error: ab_exit: exit 3" "" "## ac_done")"
check "a section's sys.exit(0) ends it with no error" "$(sed -n '/^## ac_done$/,/^## /p' <<< "${out}")" "$(printf '%s\n' "## ac_done" "done early" "" "## ci_health")"
check "flow exits 1 when a section raised" "${code}" 1

[[ ${fails} -eq 0 ]] || { echo "${out}"; echo "${fails} failed"; exit 1; }
echo "all passed"
