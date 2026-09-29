#!/usr/bin/env bash
# next_test.sh — `swarm.sh next` against small throwaway boards, one per case.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
fails=0

# item <path> <front-matter line>... — write a board file under docs/.
item() {
  local path="docs/$1" title; shift
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

# expect <name> <first line of `next`> <setup...> — build a board with the setup, check next.
expect() {
  local name="$1" want="$2" dir got; shift 2
  dir="$(mktemp -d)"
  (
    cd "${dir}" && git init -q && mkdir -p docs/stories docs/epics docs/hld
    echo "# Stories" > docs/stories/README.md   # READMEs are never items
    for step in "$@"; do eval "${step}"; done
  )
  got="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next | head -1)"
  if [[ "${got}" == "${want}" ]]; then
    echo "ok   ${name}"
  else
    echo "FAIL ${name}: want '${want}', got '${got}'"; fails=$((fails + 1))
  fi
  rm -rf "${dir}"
}

expect "empty board" "done"
expect "draft HLD" "hld 2026-01-01-x" \
  "item hld/2026-01-01-x.md 'status: draft'"
expect "agreed HLD, no epics" "plan-hld 2026-01-01-x" \
  "item hld/2026-01-01-x.md 'status: agreed'"
expect "agreed HLD, epics listed and done" "done" \
  "item hld/2026-01-01-x.md 'status: agreed'" \
  "printf '\n## Epics\n\n- e1 — done (#1)\n' >> docs/hld/2026-01-01-x.md"
expect "superseded HLD" "done" \
  "item hld/2026-01-01-x.md 'status: superseded'"
expect "active epic, no stories" "plan-epic e1" \
  "item epics/e1.md 'status: active'"
expect "active epic before a one-off" "conduct e1" \
  "item epics/e1.md 'status: active'" \
  "item stories/a-one-off.md 'status: ready' 'kind: code'" \
  "item stories/b.md 'status: ready' 'kind: code' 'epic: e1'"
expect "one-off story" "story a" \
  "item stories/a.md 'status: ready'"
expect "blocked story is not built" "gate" \
  "item epics/e1.md 'status: active'" \
  "item stories/a.md 'status: blocked' 'kind: lead' 'epic: e1'"
expect "operator story is a gate" "gate" \
  "item stories/a.md 'status: ready' 'kind: operator'"
expect "lead story is a gate" "gate" \
  "item stories/a.md 'status: ready' 'kind: lead'"
expect "ready story in a later epic waits" "gate" \
  "item epics/e1.md 'status: later'" \
  "item stories/a.md 'status: ready' 'kind: code' 'epic: e1'"
expect "only later epics left is a gate" "gate" \
  "item epics/e1.md 'status: later'"
expect "stories before planning" "conduct e2" \
  "item hld/2026-01-01-x.md 'status: draft'" \
  "item epics/e1.md 'status: active'" \
  "item epics/e2.md 'status: active'" \
  "item stories/a.md 'status: ready' 'epic: e2'"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
