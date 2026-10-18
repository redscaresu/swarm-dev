#!/usr/bin/env bash
# removed_test.sh — the switches, modes and reports that were removed stay gone: none of their names
# is in bin/swarm.sh, bin/lib/*.sh, bin/lib/*.py or tests/*.sh (this file excepted), and they say
# verify only as git's --verify, or in the one LEGACY_BUILDER_ROLES line that keeps past verify
# builds counted. cost, features and review-yield, folded into flow, each print the flow section that
# holds their numbers and exit 0. lessons, its rule PRs and its rules check stay gone from bin/ and
# commands/, whose collect step files a checks: story instead.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="${REPO}/tests/$(basename "${BASH_SOURCE[0]}")"
GONE='pr_per|CFG_finished|sign_commits|sign_rule|review_bot|keep_panes|base_branches|bump_rule|epic_branch|conduct_epic_mode|decisions_report|export_report|features_report|review_yield_report|cost_report\.py'
fails=0

files=("${REPO}/bin/swarm.sh" "${REPO}"/bin/lib/*.sh "${REPO}"/bin/lib/*.py)
for f in "${REPO}"/tests/*.sh; do [[ "${f}" == "${SELF}" ]] || files+=("${f}"); done
if found="$(grep -nE "${GONE}" "${files[@]}")"; then
  echo "FAIL a removed name is back:"; echo "${found}"; fails=$((fails + 1))
else echo "ok   no removed name in bin/swarm.sh, bin/lib/*.sh, bin/lib/*.py or tests/*.sh"; fi

if found="$(grep -hn '' "${REPO}/bin/swarm.sh" "${REPO}"/bin/lib/*.sh "${REPO}"/bin/lib/*.py | sed -e '/^[0-9]*:LEGACY_BUILDER_ROLES=/d' -e 's/--verify//g' | grep -w verify)"; then
  echo "FAIL bin/swarm.sh or bin/lib says verify other than as git --verify:"; echo "${found}"; fails=$((fails + 1))
else echo "ok   bin/swarm.sh and bin/lib say verify only as git --verify and in LEGACY_BUILDER_ROLES"; fi

# review.md is narrowed to docs/review.md: commands/epic.md still writes the epic reviewer's D/review.md.
DOCS_GONE='pr_per|finished = mark|keep_panes|sign_commits|review_bot|base_branches|release story|swarm.sh decisions|swarm.sh export|docs/review\.md|kind: verify|verify story|swarm\.sh cost'
if found="$(grep -rnE "${DOCS_GONE}" "${REPO}/docs" "${REPO}/commands" "${REPO}/templates" "${REPO}/skills")"; then
  echo "FAIL docs, commands, templates or skills mention something removed:"; echo "${found}"; fails=$((fails + 1))
else echo "ok   docs, commands, templates and skills mention nothing removed"; fi

LESSONS_GONE='LESSON_|lessons_report|rules_check_step|rules_review_rule|Rules checked|lesson: <kind>|lesson: prune'
if found="$(grep -rnE "${LESSONS_GONE}" "${REPO}/bin" "${REPO}/commands")"; then
  echo "FAIL bin/ or commands/ still has lessons or its rule PRs:"; echo "${found}"; fails=$((fails + 1))
else echo "ok   no lessons, rule PR or rules check in bin/ or commands/"; fi
collect="$(sed -n '/collect <agent>/,/^   - /p' "${REPO}/commands/swarm.md")"
if grep -q 'checks: <kind>' <<< "${collect}"; then
  echo "ok   commands/swarm.md's collect step files a checks: story"
else echo "FAIL commands/swarm.md's collect step does not name checks:"; fails=$((fails + 1)); fi
# It reads a windowed outcomes, and skips a kind whose check-<kind> board PR, looked up in the
# project's repo, is open, merged or declined; a board outside the repo is written in place.
wants=('outcomes --since' 'gh pr list -R <owner/repo> --state all --head board/check-<kind>' 'MERGED' 'written where the board is')
missing=""; for w in "${wants[@]}"; do grep -qF -- "${w}" <<< "$(tr -s '[:space:]' ' ' <<< "${collect}")" || missing+="[${w}] "; done
if [[ -z "${missing}" ]]; then echo "ok   the collect step reads outcomes --since, looks up the kind's board PR in the project's repo, and writes in place outside it"
else echo "FAIL the collect step is missing: ${missing}"; fails=$((fails + 1)); fi

W="[--since YYYY-MM-DD] [--until YYYY-MM-DD]"
for moved in "cost:cost:${W}" "features:features:${W}" "review-yield:reviewers:${W} [--epic <slug>]"; do
  cmd="${moved%%:*}"; rest="${moved#*:}"; section="${rest%%:*}"
  out="$(env -u HERDR_ENV bash "${REPO}/bin/swarm.sh" "${cmd}" --since 2026-01-01 2>&1)" && code=0 || code=$?
  want="swarm.sh ${cmd} is now flow's ${section} section: swarm.sh flow ${rest#*:}"
  if [[ ${code} -eq 0 && "${out}" == "${want}" ]]; then echo "ok   ${cmd} names flow's ${section} section and the flags it reads, and exits 0"
  else echo "FAIL ${cmd} exited ${code}, printing: ${out}"; fails=$((fails + 1)); fi
done

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
