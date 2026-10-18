#!/usr/bin/env bash
# plan_epic_children_test.sh — `swarm.sh next` on a board where /plan-epic split an epic into child
# epics: the children are planned, and the split parent counts as done once none of them is left.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
fails=0
dir="$(mktemp -d)"
STUB_BIN="$(mktemp -d)"; trap 'rm -rf "${dir}" "${STUB_BIN}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
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
  # A next that never returns (a parent: cycle) is killed with its whole process group after 20 s,
  # so the case fails instead of hanging.
  # shellcheck disable=SC2016 # the $ are perl's
  got="$(cd "${dir}" || exit; env -u HERDR_ENV perl -e '$p = fork // die; if (!$p) { setpgrp; exec @ARGV }
    $SIG{ALRM} = sub { kill "KILL", -$p }; alarm 20; waitpid $p, 0; exit $? >> 8' bash "${SWARM}" next || true)"
  got="${got%%$'\n'*}"
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
rm "${dir}/docs/epics/big-a.md"

epic big-a 'status: active' 'parent: "big"' 'depends_on: []'
expect "a quoted parent: still names the parent" "plan-epic big-a"
# A child that depends on its own parent is not held by it.
epic big-a 'status: active' 'parent: big' 'depends_on: [big]'
expect "a child's depends_on on its own parent does not hold it" "plan-epic big-a"
# A split child keeps the parent open while it has children, and lets it go once they are gone.
epic big-a 'status: split' 'parent: big' 'depends_on: []'
epic big-a-x 'status: done' 'parent: big-a' 'depends_on: []'
expect "a split child with no open children of its own leaves the parent done" "plan-epic after"
epic big-a-x 'status: active' 'parent: big-a' 'depends_on: []'
expect "a split child with an open child keeps the parent open" "plan-epic big-a-x"
rm "${dir}/docs/epics/big-a.md" "${dir}/docs/epics/big-a-x.md"

# parent: cycles end: an epic is never its own child, and two that name each other have none.
epic big 'status: split' 'parent: big' 'depends_on: []'
expect "a split epic that names itself as parent: counts as done" "plan-epic after"
epic big 'status: split' 'parent: big-z' 'depends_on: []'
epic big-z 'status: split' 'parent: big' 'depends_on: []'
expect "two split epics that name each other as parent: count as done" "plan-epic after"

[ "${fails}" -eq 0 ]
