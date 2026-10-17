#!/usr/bin/env bash
# removed_test.sh — the switches, modes and reports that were removed stay gone: none of their names
# is in bin/swarm.sh, bin/lib/*.sh, bin/lib/*.py or tests/*.sh (this file excepted), and they say
# verify only as git's --verify, or in the one LEGACY_BUILDER_ROLES line that keeps past verify
# builds counted. cost, features and review-yield, folded into flow, each print the flow section that
# holds their numbers and exit 0.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="${REPO}/tests/$(basename "${BASH_SOURCE[0]}")"
GONE='pr_per|CFG_finished|sign_commits|sign_rule|review_bot|keep_panes|merge_admin|base_branches|bump_rule|epic_branch|conduct_epic_mode|decisions_report|export_report|features_report|review_yield_report|cost_report\.py'
fails=0

files=("${REPO}/bin/swarm.sh" "${REPO}"/bin/lib/*.sh "${REPO}"/bin/lib/*.py)
for f in "${REPO}"/tests/*.sh; do [[ "${f}" == "${SELF}" ]] || files+=("${f}"); done
if found="$(grep -nE "${GONE}" "${files[@]}")"; then
  echo "FAIL a removed name is back:"; echo "${found}"; fails=$((fails + 1))
else echo "ok   no removed name in bin/swarm.sh, bin/lib/*.sh, bin/lib/*.py or tests/*.sh"; fi

if found="$(grep -hn '' "${REPO}/bin/swarm.sh" "${REPO}"/bin/lib/*.sh "${REPO}"/bin/lib/*.py | sed -e '/^[0-9]*:LEGACY_BUILDER_ROLES=/d' -e 's/--verify//g' | grep -w verify)"; then
  echo "FAIL bin/swarm.sh or bin/lib says verify other than as git --verify:"; echo "${found}"; fails=$((fails + 1))
else echo "ok   bin/swarm.sh and bin/lib say verify only as git --verify and in LEGACY_BUILDER_ROLES"; fi

# review.md is narrowed to docs/review.md: commands/hld.md still writes the HLD reviewer's D/review.md.
DOCS_GONE='pr_per|finished = mark|keep_panes|merge_admin|sign_commits|review_bot|base_branches|release story|swarm.sh decisions|swarm.sh export|docs/review\.md|kind: verify|verify story'
if found="$(grep -rnE "${DOCS_GONE}" "${REPO}/docs" "${REPO}/commands" "${REPO}/templates" "${REPO}/skills")"; then
  echo "FAIL docs, commands, templates or skills mention something removed:"; echo "${found}"; fails=$((fails + 1))
else echo "ok   docs, commands, templates and skills mention nothing removed"; fi

for moved in cost:cost features:features review-yield:reviewers; do
  out="$(env -u HERDR_ENV bash "${REPO}/bin/swarm.sh" "${moved%%:*}" --since 2026-01-01 2>&1)" && code=0 || code=$?
  want="swarm.sh ${moved%%:*} is now flow's ${moved#*:} section: swarm.sh flow [--since YYYY-MM-DD] [--epic <slug>]"
  if [[ ${code} -eq 0 && "${out}" == "${want}" ]]; then echo "ok   ${moved%%:*} names flow's ${moved#*:} section and exits 0"
  else echo "FAIL ${moved%%:*} exited ${code}, printing: ${out}"; fails=$((fails + 1)); fi
done

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
