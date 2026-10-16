#!/usr/bin/env bash
# removed_test.sh — the switches, modes and reports that were removed stay gone: none of their names
# is in bin/swarm.sh or tests/*.sh (this file excepted), and bin/swarm.sh says verify only as git's
# --verify, or in the one LEGACY_BUILDER_ROLES line that keeps past verify builds counted.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="${REPO}/tests/$(basename "${BASH_SOURCE[0]}")"
GONE='pr_per|CFG_finished|sign_commits|sign_rule|review_bot|keep_panes|merge_admin|base_branches|bump_rule|epic_branch|conduct_epic_mode|decisions_report|export_report'
fails=0

files=("${REPO}/bin/swarm.sh")
for f in "${REPO}"/tests/*.sh; do [[ "${f}" == "${SELF}" ]] || files+=("${f}"); done
if found="$(grep -nE "${GONE}" "${files[@]}")"; then
  echo "FAIL a removed name is back:"; echo "${found}"; fails=$((fails + 1))
else echo "ok   no removed name in bin/swarm.sh or tests/*.sh"; fi

if found="$(grep -n '' "${REPO}/bin/swarm.sh" | sed -e '/^[0-9]*:LEGACY_BUILDER_ROLES=/d' -e 's/--verify//g' | grep -w verify)"; then
  echo "FAIL bin/swarm.sh says verify other than as git --verify:"; echo "${found}"; fails=$((fails + 1))
else echo "ok   bin/swarm.sh says verify only as git --verify and in LEGACY_BUILDER_ROLES"; fi

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
