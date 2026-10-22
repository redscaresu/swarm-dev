#!/usr/bin/env bash
# board-only.sh — CI's gate in the shellcheck, test-shard and plugin-validate jobs. It prints why, and
# writes board_only=true to $GITHUB_OUTPUT when the job's later steps may skip, else board_only=false.
# ci.yml runs the base's copy when the base has one, so a PR is never judged by a gate it changed.
# A pull request is board-only when every path it changes (git diff --no-renames, so a renamed file's
# old path too) is under board/, as merge --board has it, except a board README, which
# tests/board_readme_test.sh checks against templates/. It is fast-path too when the only other path
# is .claude-plugin/plugin.json, changed in nothing but its version (compared as parsed JSON), that
# version is MAJOR.MINOR.PATCH and greater than the base's, the base is main's latest commit and main's
# CI on that commit is green (ci_gate head): the code being released has to be the code main tested.
# A push, an empty diff, a failed diff, a failed read or a change to the gate's own files runs everything.
# Env: GITHUB_EVENT_NAME, BASE_SHA (the event's base SHA), GITHUB_REPOSITORY, GITHUB_OUTPUT; gh reads GH_TOKEN.
set -euo pipefail

BOARD=board/
PLUGIN=.claude-plugin/plugin.json
MAIN=main
GATE_FILES=" scripts/board-only.sh .github/workflows/ci.yml tests/board_only_test.sh "

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
  [[ "${GATE_FILES}" != *" ${p} "* ]] || verdict false "${p} is the gate's own"
  case "${p}" in
    "${BOARD}"README.md|"${BOARD}"*/README.md) verdict false "${p} is a board README, which a test checks" ;;
    "${BOARD}"*) ;;
    "${PLUGIN}") release=1 ;;
    *) verdict false "${p} is outside ${BOARD}" ;;
  esac
done <<< "${paths}"
[[ -n "${release}" ]] || verdict true "every path is under ${BOARD}"

old="$(git show "${BASE_SHA}:${PLUGIN}")" || verdict false "cannot read ${PLUGIN} on the base"
new="$(git show "HEAD:${PLUGIN}")" || verdict false "cannot read ${PLUGIN} on the PR"
why="$(OLD="${old}" NEW="${new}" python3 -c 'import json, os, re
o, n = (json.loads(os.environ[k]) for k in ("OLD", "NEW"))
v, w = n.pop("version", None), o.pop("version", None)
semver = lambda x: tuple(map(int, x.split("."))) if isinstance(x, str) and re.fullmatch(r"\d+\.\d+\.\d+", x) else None
if semver(v) is None:
    print("its version %r is not MAJOR.MINOR.PATCH" % (v,))
elif semver(w) is None or semver(v) <= semver(w):
    print("its version %s is not greater than the base'"'"'s %r" % (v, w))
elif json.dumps(o, sort_keys=True) != json.dumps(n, sort_keys=True):
    print("it changes more than its version")' 2>/dev/null)" || why="it is not a JSON object"
[[ -z "${why}" ]] || verdict false "${PLUGIN}: ${why}"
tip="$(gh api "repos/${GITHUB_REPOSITORY:-}/commits/${MAIN}" --jq .sha)" || verdict false "gh cannot read ${MAIN}'s latest commit"
[[ "${tip}" == "${BASE_SHA}" ]] || verdict false "the base ${BASE_SHA:0:7} is not ${MAIN}'s latest commit ${tip:0:7}"
gate="$(git rev-parse --show-toplevel)/bin/lib/ci_gate.py"
why="$(python3 "${gate}" head "${GITHUB_REPOSITORY}" "${BASE_SHA}")" \
  || verdict false "${MAIN}'s CI on ${BASE_SHA:0:7} is not green: ${why}"
verdict true "a version-only release on ${MAIN}'s latest, green commit"
