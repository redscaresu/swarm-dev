#!/usr/bin/env bash
# removed_test.sh — the switches, modes and reports that were removed stay gone: none of their names
# is in bin/swarm.sh, bin/lib/*.sh, bin/lib/*.py or tests/*.sh (this file excepted), and they say
# verify only as git's --verify, or in the one LEGACY_BUILDER_ROLES line that keeps past verify
# builds counted. cost, features and review-yield, folded into flow, each print the flow section that
# holds their numbers and exit 0.
# A config that sets a removed key (pr_per, finished, review_bot, keep_panes) loads with a warning;
# a made-up key still stops the script.
# lessons, its rule PRs and its rules check stay gone from bin/ and commands/. commands/swarm.md's
# collect step reads the conductor's report, relays it and closes the conductor; it files no checks:
# story, and neither it nor AGENTS.md names that filing, which swarm.sh retro's recurring list replaced.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

iso="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${iso}"' EXIT
export CLAUDE_CONFIG_DIR="${iso}/claude-config"   # under its own root, so parallel runs share no ~/.claude

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="${REPO}/tests/$(basename "${BASH_SOURCE[0]}")"
GONE='pr_per|CFG_finished|review_bot|keep_panes|bump_rule|epic_branch|conduct_epic_mode|decisions_report|export_report|features_report|review_yield_report|cost_report\.py'
fails=0

files=("${REPO}/bin/swarm.sh" "${REPO}"/bin/lib/*.sh "${REPO}"/bin/lib/*.py)
for f in "${REPO}"/tests/*.sh; do [[ "${f}" == "${SELF}" ]] || files+=("${f}"); done
# bin/swarm.sh's REMOVED_KEYS line names the removed keys a config may still set, to warn on them.
found="$(grep -nE "${GONE}" "${files[@]}" | grep -vE '^[^:]*/bin/swarm\.sh:[0-9]+:REMOVED_KEYS="' || true)"
if [[ -n "${found}" ]]; then
  echo "FAIL a removed name is back:"; echo "${found}"; fails=$((fails + 1))
else echo "ok   no removed name in bin/swarm.sh, bin/lib/*.sh, bin/lib/*.py or tests/*.sh but REMOVED_KEYS"; fi

# Why: an older board's config still sets these keys, and swarm.sh must keep running there. Boards
# outside swarm-dev and infrafactory set them, so checking those two configs is not enough to make
# them die again.
# A config that sets a removed key still loads: the key is ignored, with a warning on stderr naming it
# and its line. Any other unknown key still stops the script.
proj="$(cd "${iso}" && pwd -P)/proj"; mkdir -p "${proj}/.claude/swarm"
for key in pr_per finished review_bot keep_panes; do
  printf 'merge = agent\n%s = anything\n' "${key}" > "${proj}/.claude/swarm/config"
  out="$(cd "${proj}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${REPO}/bin/swarm.sh" config merge 2>"${iso}/err")" && code=0 || code=$?
  err="$(cat "${iso}/err")"
  if [[ ${code} -eq 0 && "${out}" == agent && "${err}" == "swarm: warning: ${proj}/.claude/swarm/config:2: ${key} was removed and is ignored; delete the line" ]]; then
    echo "ok   ${key} warns on stderr that it was removed, and the config loads"
  else echo "FAIL ${key}: exit ${code}, stdout '${out}', stderr '${err}'"; fails=$((fails + 1)); fi
done
printf 'made_up = 1\n' > "${proj}/.claude/swarm/config"
out="$(cd "${proj}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${REPO}/bin/swarm.sh" config merge 2>&1)" && code=0 || code=$?
if [[ ${code} -ne 0 && "${out}" == *"config:1: unknown key 'made_up'"* ]]; then
  echo "ok   a made-up key still stops the script"
else echo "FAIL a made-up key: exit ${code}, output '${out}'"; fails=$((fails + 1)); fi

if found="$(grep -hn '' "${REPO}/bin/swarm.sh" "${REPO}"/bin/lib/*.sh "${REPO}"/bin/lib/*.py | sed -e '/^[0-9]*:LEGACY_BUILDER_ROLES=/d' -e 's/--verify//g' | grep -w verify)"; then
  echo "FAIL bin/swarm.sh or bin/lib says verify other than as git --verify:"; echo "${found}"; fails=$((fails + 1))
else echo "ok   bin/swarm.sh and bin/lib say verify only as git --verify and in LEGACY_BUILDER_ROLES"; fi

# review.md is narrowed to docs/review.md: commands/epic.md still writes the epic reviewer's D/review.md.
DOCS_GONE='pr_per|finished = mark|keep_panes|review_bot|release story|swarm.sh decisions|swarm.sh export|docs/review\.md|kind: verify|verify story|swarm\.sh cost'
if found="$(grep -rnE "${DOCS_GONE}" "${REPO}/docs" "${REPO}/commands" "${REPO}/templates" "${REPO}/skills")"; then
  echo "FAIL docs, commands, templates or skills mention something removed:"; echo "${found}"; fails=$((fails + 1))
else echo "ok   docs, commands, templates and skills mention nothing removed"; fi

LESSONS_GONE='LESSON_|lessons_report|rules_check_step|rules_review_rule|Rules checked|lesson: <kind>|lesson: prune'
if found="$(grep -rnE "${LESSONS_GONE}" "${REPO}/bin" "${REPO}/commands" "${REPO}/rules.md")"; then
  echo "FAIL bin/, commands/ or rules.md still has lessons or its rule PRs:"; echo "${found}"; fails=$((fails + 1))
else echo "ok   no lessons, rule PR or rules check in bin/, commands/ or rules.md"; fi
collect="$(sed -n '/collect <agent>/,/^   - /p' "${REPO}/commands/swarm.md" | tr -s '[:space:]' ' ')"
# The collect step reads the report, relays it to the user and closes the conductor.
# shellcheck disable=SC2016 # the backticks are the command's
wants=('.swarm/conduct-<epic>.report.md' 'relay what merged, what is left and what waits on the user' 'then `swarm.sh close <agent>`' "\`swarm.sh retro\`'s recurring list")
missing=""; for w in "${wants[@]}"; do grep -qF -- "${w}" <<< "${collect}" || missing+="[${w}] "; done
if [[ -z "${missing}" ]]; then echo "ok   the collect step reads the report, relays it, closes the conductor and leaves recurring kinds to retro"
else echo "FAIL the collect step is missing: ${missing}"; fails=$((fails + 1)); fi
# Neither commands/swarm.md nor AGENTS.md files a checks: story per recurring kind any more.
# shellcheck disable=SC2016 # the backticks are the docs'
if found="$(grep -nE 'checks: <kind>|board/check-<kind>|\.swarm/checks-filed\.tsv|files a `checks:` story' "${REPO}/commands/swarm.md" "${REPO}/AGENTS.md")"; then
  echo "FAIL commands/swarm.md or AGENTS.md still files a checks: story:"; echo "${found}"; fails=$((fails + 1))
else echo "ok   commands/swarm.md and AGENTS.md file no checks: story"; fi
log_finding="$(grep -F -- '- `swarm.sh log-finding ' "${REPO}/AGENTS.md" || true)"
if grep -qF -- "\`swarm.sh retro\`'s recurring list" <<< "${log_finding}"; then
  echo "ok   AGENTS.md's log-finding item names swarm.sh retro's recurring list"
else echo "FAIL AGENTS.md's log-finding item does not name swarm.sh retro's recurring list"; fails=$((fails + 1)); fi

W="[--since YYYY-MM-DD] [--until YYYY-MM-DD]"
# In a bare project of its own: a test runs from its TMPDIR, outside any project, and never against the checkout.
bare="${iso}/bare"; mkdir -p "${bare}/.claude/swarm"; : > "${bare}/.claude/swarm/config"
for moved in "cost:cost:${W}" "features:features:${W}" "review-yield:reviewers:${W} [--epic <slug>]"; do
  cmd="${moved%%:*}"; rest="${moved#*:}"; section="${rest%%:*}"
  out="$(cd "${bare}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${REPO}/bin/swarm.sh" "${cmd}" --since 2026-01-01 2>&1)" && code=0 || code=$?
  want="swarm.sh ${cmd} is now flow's ${section} section: swarm.sh flow ${rest#*:}"
  if [[ ${code} -eq 0 && "${out}" == "${want}" ]]; then echo "ok   ${cmd} names flow's ${section} section and the flags it reads, and exits 0"
  else echo "FAIL ${cmd} exited ${code}, printing: ${out}"; fails=$((fails + 1)); fi
done

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
