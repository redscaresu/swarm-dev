#!/usr/bin/env bash
# roles_test.sh — every role in ROLE_GROUPS is started by something: a `swarm.sh agent` line in
# commands/*.md that passes it literally, a role `x` in a command file whose agent line takes
# <role>, a start_agent call in bin/swarm.sh or bin/lib/*.sh that passes it literally, or
# `swarm.sh _role` for a fixture story. A role policy() knows that nothing starts is dead weight, or a missing caller.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWARM="${REPO}/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${tmp}"' EXIT

roles="$(sed -n 's/^ROLE_GROUPS="\(.*\)"$/\1/p' "${SWARM}")"
[[ -n "${roles}" ]] || { echo "FAIL no ROLE_GROUPS line in ${SWARM}"; exit 1; }
roles="$(tr ' ' '\n' <<< "${roles}" | sed 's/^[^:]*://' | tr ',' '\n')"

reached=""   # one role per line
# shellcheck disable=SC2016 # the backticks are Markdown's, matched literally
# The fourth word after `swarm.sh agent` (or start_agent) is the role; a literal one counts.
# A command file is read without its <!-- --> comments.
for f in "${REPO}"/commands/*.md; do
  md="$(perl -0pe 's/<!--.*?-->//gs' "${f}")"
  reached+=$'\n'"$(sed -n 's/.*swarm\.sh agent \([^ `]*\) \([^ `]*\) \([^ `]*\) \([a-z-]*\)\([ `].*\)\{0,1\}$/\4/p' <<< "${md}")"
  if grep -q 'swarm\.sh agent .*<role>' <<< "${md}"; then
    reached+=$'\n'"$(grep -o 'role `[a-z-]*`' <<< "${md}" | sed 's/role `\(.*\)`/\1/' || true)"
  fi
done
reached+=$'\n'"$(cat "${SWARM}" "${REPO}"/bin/lib/*.sh | grep -v '^[[:space:]]*#' \
  | sed -n 's/.*start_agent \([^ ]*\) \([^ ]*\) \([^ ]*\) \([a-z-]*\)\( .*\)\{0,1\}$/\4/p')"

# _role for one fixture story per arm of story_role. With sonnet_share = 4, slug e4-f marked easy: true
# lands in the code-sonnet sample and slug e4-a does not. escalate_after is set too, so its default can change.
mkdir -p "${tmp}/docs/stories" "${tmp}/.claude/swarm"
printf '%s\n' "sonnet_share = 4" "escalate_after = 2" > "${tmp}/.claude/swarm/config"
story() { # <slug> <front-matter line>... — write the story, add its _role to reached
  local s="$1" out; shift
  { echo ---; echo "status: ready"; printf '%s\n' "$@"; echo ---; } > "${tmp}/docs/stories/${s}.md"
  if ! out="$(cd "${tmp}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${SWARM}" _role "${s}" 2>&1)"; then
    echo "FAIL _role ${s} ($*) failed: ${out}"; exit 1
  fi
  reached+=$'\n'"${out}"
}
story e4-a "kind: code"
story e4-a "kind: code" "risk: high"
story e4-f "kind: code" "easy: true"
story a "kind: docs"
story a "kind: chore"
story a "kind: code" "attempts: 2"

fails=0
# /epic replaced /hld: its reviewer is epic-review, and the hld roles are gone from ROLE_GROUPS and policy.
pol="$(sed -n '/^policy() {$/,/^}$/p' "${SWARM}")"
if grep -qx epic-review <<< "${roles}" && grep -q '^ *epic-review)' <<< "${pol}"; then
  echo "ok   epic-review is in ROLE_GROUPS and policy"
else echo "FAIL epic-review is missing from ROLE_GROUPS or policy"; fails=$((fails + 1)); fi
for r in hld hld-review hld-lead; do
  if grep -qx -- "${r}" <<< "${roles}" || grep -q "^ *${r})" <<< "${pol}"; then
    echo "FAIL ${r} is still in ROLE_GROUPS or policy"; fails=$((fails + 1))
  else echo "ok   ${r} is in neither ROLE_GROUPS nor policy"; fi
done
for r in ${roles}; do
  if grep -qx -- "${r}" <<< "${reached}"; then
    echo "ok   ${r} is reached"
  else
    echo "FAIL ${r}: no command, start_agent call or _role starts it"; fails=$((fails + 1))
  fi
done
if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
