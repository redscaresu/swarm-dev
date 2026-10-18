#!/usr/bin/env bash
# plan_epic_children_test.sh — `swarm.sh next` on a board where /plan-epic split an epic into child
# epics: the children are planned, and the split parent counts as done once none of them is left.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
fails=0
dir="$(mktemp -d)"
STUB_BIN="$(mktemp -d)"; trap 'rm -rf "${dir}" "${STUB_BIN}"' EXIT
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}"

# epic <slug> <front-matter line>... — write docs/epics/<slug>.md.
epic() {
  local slug="$1"; shift
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${slug}"; echo; echo "**Done when:** ${slug} works."; } > "${dir}/docs/epics/${slug}.md"
}

# expect <name> <first line of `next`>
expect() {
  local got
  got="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next)"; got="${got%%$'\n'*}"
  if [[ "${got}" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '${got}'"; fails=$((fails + 1)); fi
}

(cd "${dir}" && git init -q && mkdir -p docs/stories docs/epics)
epic big 'status: split' 'depends_on: []'
epic big-a 'status: active' 'parent: big' 'depends_on: []'
epic big-b 'status: active' 'parent: big' 'depends_on: []'

expect "the split parent is not planned; its first child is" "plan-epic big-a"
rm "${dir}/docs/epics/big-a.md"
expect "the second child is planned once the first is gone" "plan-epic big-b"
rm "${dir}/docs/epics/big-b.md"
expect "a split parent with no children left is never planned" "done"

# after sorts first and depends on the parent: it is held until both children are gone.
epic after 'status: active' 'depends_on: [big]'
epic big-a 'status: active' 'parent: big' 'depends_on: []'
epic big-b 'status: active' 'parent: big' 'depends_on: []'
expect "an epic on a split parent waits while both children are left" "plan-epic big-a"
rm "${dir}/docs/epics/big-a.md"
expect "an epic on a split parent waits while one child is left" "plan-epic big-b"
rm "${dir}/docs/epics/big-b.md"
expect "the split parent counts as done once both children are gone" "plan-epic after"

# A child written from the template carries `parent: big   # ...`: the comment is not part of the slug.
epic big-a 'status: active' 'parent: big            # only on a child epic of a split one' 'depends_on: []'
expect "a parent: with a trailing comment still names the parent" "plan-epic big-a"
rm "${dir}/docs/epics/big-a.md"
# Only the front matter names a parent: a body line does not, and a done child is no child.
epic big-a 'status: active' 'depends_on: []'
echo "parent: big" >> "${dir}/docs/epics/big-a.md"
expect "a parent: line in the body is no parent" "plan-epic after"
epic big-a 'status: done' 'parent: big' 'depends_on: []'
expect "a done child does not keep the parent open" "plan-epic after"

[ "${fails}" -eq 0 ]
