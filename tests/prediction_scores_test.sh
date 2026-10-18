#!/usr/bin/env bash
# prediction_scores_test.sh — flow's predictions section over `swarm.sh dataset`'s own output on
# dataset_test.sh's fixture (tests/fixtures/dataset.sh): one row per planner model with the precision
# and recall of easy against was_easy and the median and mean estimate error, then the same with three
# more opus-planned lines added by hand, so precision, recall, median and mean all differ. --since and
# --epic narrow it; with no dataset.jsonl it prints the line saying to run swarm.sh dataset.
set -euo pipefail
export TZ=UTC

dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
dir="$(cd "${dir}" && pwd -P)"
# shellcheck source=fixtures/dataset.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
source "$(dirname "${BASH_SOURCE[0]}")/fixtures/dataset.sh" "${dir}"
F="${P}/.swarm/dataset.jsonl"

fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
predictions() { # [flow flag...] — flow's predictions section, its heading and the blank line after it left out
  (cd "${P}" && { env -u HERDR_ENV -u SWARM_PROJECT CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" \
    bash "${SWARM}" flow "$@" 2>/dev/null || true; }) | sed -n '/^## predictions$/,/^## /p' | sed '1d;/^## /d;/^$/d'
}
HEAD=$'planner\tstories\teasy_precision\teasy_recall\testimate_err_median\testimate_err_mean'

check "dataset writes the fixture's three stories" "$(dataset)" "$(printf 'wrote 3 finished stories to %s\nexit 0' "${F}")"
# easy-ok: no planner, easy and was, 10 lines for 40; easy-hard: opus, easy but was not, 20 for 30;
# escalated: sonnet, neither, 150 for 200.
check "one row per planner model, - for none, a ratio with nothing to count empty" "$(predictions)" "$(printf '%s\n' "${HEAD}" \
  $'-\t1\t1.00\t1.00\t-30\t-30.0' $'opus\t1\t0.00\t\t-10\t-10.0' $'sonnet\t1\t\t\t-50\t-50.0')"

line() { # <slug> <easy> <was_easy> <estimate> <diff>: a dataset line planned by opus in e1, merged 2026-10-07
  printf '{"slug":"%s","epic":"e1","merged_at":"2026-10-07T10:00:00Z","inputs":{"planner_model":"opus","easy":%s,"estimate_lines":%s},"results":{"diff_lines":%s},"was_easy":%s}\n' "$1" "$2" "$4" "$5" "$3"
}
{ line missed false true 10 70; line right true true 50 50; line missed2 false true 10 30; line unread true null null null; } >> "${F}"
# opus: easy (T,F) (F,T) (T,T) (F,T), the unread one left out: 1 of 2 planned easy were, 1 of 3 that
# were was planned so; errors -10, 60, 0 and 20.
check "precision, recall, median and mean over a planner's stories, a null left out" "$(predictions | grep '^opus')" \
  $'opus\t5\t0.50\t0.33\t10\t17.5'
check "--since keeps the stories merged that day or later" "$(predictions --since 2026-10-06)" "$(printf '%s\n' "${HEAD}" \
  $'opus\t4\t1.00\t0.33\t20\t26.7' $'sonnet\t1\t\t\t-50\t-50.0')"
check "--epic keeps that epic's stories" "$(predictions --epic e0)" "$(printf '%s\n' "${HEAD}" $'sonnet\t1\t\t\t-50\t-50.0')"

rm "${F}"
check "with no dataset.jsonl it says to run swarm.sh dataset" "$(predictions)" "no .swarm/dataset.jsonl: run swarm.sh dataset first"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
