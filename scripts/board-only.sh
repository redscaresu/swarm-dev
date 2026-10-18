#!/usr/bin/env bash
# board-only.sh — CI's gate in the shellcheck, test and plugin-validate jobs. It prints why, and
# writes board_only=true to $GITHUB_OUTPUT when the job's later steps may skip, else board_only=false.
# A pull request is board-only when every path it changes (git diff --no-renames, so a renamed file's
# old path too) is under board/, as merge --board has it. It is fast-path too when the only other path
# is .claude-plugin/plugin.json, changed in nothing but its version (compared as parsed JSON), its
# base is main's latest commit and main's CI on that commit is green (ci_gate head): the code being
# released has to be the code main tested. A push, an empty diff, a failed diff or a failed read runs
# everything.
# Env: GITHUB_EVENT_NAME, BASE_SHA (the event's base SHA), GITHUB_REPOSITORY, GITHUB_OUTPUT; gh reads GH_TOKEN.
set -euo pipefail

BOARD=board/
PLUGIN=.claude-plugin/plugin.json
MAIN=main
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# verdict <true|false> <why> — the answer, then stop.
verdict() {
  echo "board-only: $1 ($2)"
  echo "board_only=$1" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
}

[[ "${GITHUB_EVENT_NAME:-}" == pull_request ]] || verdict false "a ${GITHUB_EVENT_NAME:-local} run tests everything"
[[ "${BASE_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || verdict false "no base SHA"
paths="$(git diff --name-only --no-renames "${BASE_SHA}...HEAD")" || verdict false "git diff against ${BASE_SHA:0:7} failed"
[[ -n "${paths}" ]] || verdict false "the diff is empty"
release=""
while IFS= read -r p; do
  case "${p}" in
    "${BOARD}"*) ;;
    "${PLUGIN}") release=1 ;;
    *) verdict false "${p} is outside ${BOARD}" ;;
  esac
done <<< "${paths}"
[[ -n "${release}" ]] || verdict true "every path is under ${BOARD}"

old="$(git show "${BASE_SHA}:${PLUGIN}")" || verdict false "cannot read ${PLUGIN} on the base"
new="$(git show "HEAD:${PLUGIN}")" || verdict false "cannot read ${PLUGIN} on the PR"
OLD="${old}" NEW="${new}" python3 -c 'import json, os
o, n = (json.loads(os.environ[k]) for k in ("OLD", "NEW"))
o.pop("version", None); n.pop("version", None)
raise SystemExit(json.dumps(o, sort_keys=True) != json.dumps(n, sort_keys=True))' 2>/dev/null \
  || verdict false "${PLUGIN} changes more than its version"
tip="$(gh api "repos/${GITHUB_REPOSITORY:-}/commits/${MAIN}" --jq .sha)" || verdict false "gh cannot read ${MAIN}'s latest commit"
[[ "${tip}" == "${BASE_SHA}" ]] || verdict false "the base ${BASE_SHA:0:7} is not ${MAIN}'s latest commit ${tip:0:7}"
why="$(python3 "${HERE}/bin/lib/ci_gate.py" head "${GITHUB_REPOSITORY}" "${BASE_SHA}")" \
  || verdict false "${MAIN}'s CI on ${BASE_SHA:0:7} is not green: ${why}"
verdict true "a version-only release on ${MAIN}'s latest, green commit"
