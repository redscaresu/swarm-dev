#!/usr/bin/env bash
# idle_epic_test.sh — next's idle epic lines (touches_rows.py --idle, through idle_now): a draft or
# later epic in the current stage whose depends_on are gone, or with a ready story, gets
# `idle: epic <epic> can start, ...` unless next's stage step covers it; an active epic with no stories
# and no scope-<epic> tab record gets `idle: epic <epic> has no plan running, ...`; and
# commands/swarm.md quotes both lines as the check prints them.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
# The claude stub goes first on PATH, so the swarm.sh next run here never reaches the real claude.
mkdir -p "${ROOT}/bin" && cp "${REPO}/tests/claude_stub.sh" "${ROOT}/bin/claude"
export PATH="${ROOT}/bin:${PATH}"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# board — a fresh project in CASE with an empty board.
board() {
  CASE="$(mktemp -d "${ROOT}/case.XXXXXX")"
  mkdir -p "${CASE}/docs/stories" "${CASE}/docs/epics" "${CASE}/docs/hld" "${CASE}/.swarm/board-state/stories" "${CASE}/repos"
}

# item <path under docs/> <front-matter line>... — write a board file.
item() {
  local f="${CASE}/docs/$1"; shift
  { echo "---"; printf '%s\n' "$@"; printf -- '---\n\n# item\n'; } > "${f}"
}

idle() {
  SWARM_AGENT_KINDS="code docs chore" SWARM_QUEUE_MINUTES=30 python3 "${REPO}/bin/lib/touches_rows.py" \
    "${CASE}/docs/stories" --idle "${CASE}" "${CASE}/repos" "${CASE}/.swarm/board-state/stories"
}
START="idle: epic e can start, exit: plan it, or set it active in a board PR"
NOPLAN="idle: epic e has no plan running, exit: /swarm-dev:plan-epic e"

# An epic that can start.
board; item epics/e.md "status: draft" "depends_on: [d]"
check "a draft epic whose depends_on epic left the board can start" "${START}" "$(idle)"
board; item epics/e.md "status: later" "depends_on: [d]"
check "a later epic whose depends_on epic left the board can start" "${START}" "$(idle)"
item epics/d.md "status: active"; item stories/s.md "status: ready" "kind: code" "epic: d"
check "a dependency epic still on the board gives no line" "" "$(idle)"
item epics/d.md "status: done"
check "a dependency epic marked done counts as gone" "${START}" "$(idle)"
item epics/d.md "status: split"; item epics/k.md "status: active" "parent: d"; item stories/t.md "status: ready" "kind: code" "epic: k"
check "a split dependency epic with an open child epic gives no line" "" "$(idle)"
rm "${CASE}/docs/epics/k.md"
check "a split dependency epic whose children are gone counts as gone" "${START}" "$(idle)"
board; item epics/e.md "status: later" "depends_on: []"
check "a later epic with no depends_on waits on the user: no line" "" "$(idle)"
item stories/s.md "status: ready" "kind: lead" "epic: e"
check "a later epic whose only ready story is a lead one gives no line" "" "$(idle)"
item stories/s.md "status: ready" "kind: code" "epic: e"
check "a later epic with a ready story an agent builds can start" "${START}" "$(idle)"
board; item epics/e.md "status: draft" "depends_on: [d]"; item epics/d.md "status: active"
item stories/s.md "status: later" "kind: code" "epic: e"; item stories/t.md "status: ready" "kind: code" "epic: d"
check "a draft epic whose stories are not ready and whose dependency is open gives no line" "" "$(idle)"
board; item epics/e.md "status: later" "depends_on: [d]" "unasked_plan: declined 2026-10-01"
check "a later epic whose unasked plan the user declined gives no line" "" "$(idle)"

# The current stage: the lowest stage: an epic on the board carries, a parent's standing in for a
# child's.
board; item epics/e.md "status: draft" "stage: v1.3.0" "depends_on: [d]"; item epics/c.md "status: active" "stage: v1.2.0"
item stories/s.md "status: ready" "kind: code" "epic: c"
check "a draft epic of a later stage than the board's lowest gives no line" "" "$(idle)"
item epics/c.md "status: active" "stage: v1.3.0  # the release that ships it"
check "a draft epic of the lowest stage (a commented stage: read as its version) can start" "${START}" "$(idle)"
board; item epics/e.md "status: draft" "parent: p" "depends_on: [d]"; item epics/p.md "status: split" "stage: v1.3.0"
item epics/c.md "status: active" "stage: v1.2.0"; item stories/s.md "status: ready" "kind: code" "epic: c"
check "a child epic with no stage: of its own is in its parent's stage" "" "$(idle)"
item epics/c.md "status: active" "stage: v1.4.0"
check "a child epic whose parent's stage is the lowest can start" "${START}" "$(idle)"

# An active epic with no plan running.
board; item epics/e.md "status: active"
check "an active epic with no stories and no plan recorded gives the line" "${NOPLAN}" "$(idle)"
mkdir -p "${CASE}/.swarm/state" && echo "w1:p1 lead-e" > "${CASE}/.swarm/state/scope-e"
check "a scope-<epic> tab record (its plan running) gives no line" "" "$(idle)"
mv "${CASE}/.swarm/state/scope-e" "${CASE}/.swarm/state/scope-e-2"
check "a numbered overflow scope-<epic>-2 record gives no line" "" "$(idle)"
mv "${CASE}/.swarm/state/scope-e-2" "${CASE}/.swarm/state/scope-ex"
check "another epic's scope- record leaves the line" "${NOPLAN}" "$(idle)"
item stories/s.md "status: ready" "kind: lead" "epic: e" "after: e"
check "a lead story with after: its epic does not count in it (epic_stories)" "${NOPLAN}" "$(idle)"
item stories/s.md "status: blocked" "kind: code" "epic: e"
check "an active epic with a story gives no line" "" "$(idle)"
board; item epics/e.md "status: draft"
check "a draft epic with no stories is not an unplanned active one" "" "$(idle)"
board; item epics/e.md "status: active" "depends_on: [d]"; item epics/d.md "status: active"
item stories/t.md "status: ready" "kind: code" "epic: d"
check "an active epic whose dependency epic has a story not yet in review gives no line" "" "$(idle)"
item stories/t.md "status: review" "kind: code" "epic: d"
check "an active epic whose dependency epic's stories are in review gives the line" "${NOPLAN}" "$(idle)"
board; item epics/e.md "status: active" "depends_on: [d]"; item epics/d.md "status: split"
check "a split dependency epic with no open child does not hold the plan" "${NOPLAN}" "$(idle)"
board; item epics/e.md "status: active" "parent: p" "depends_on: [p]"; item epics/p.md "status: split"
check "an active child epic's own parent never holds its plan" "${NOPLAN}" "$(idle)"

# next's stage step covers a staged draft (an agreed HLD granting epics, the minor before its stage
# tagged on origin/main): idle_now drops its line. A draft of the same stage with no hld: is no
# staged draft, so its line stays.
board
(
  cd "${CASE}" && git init -q && git init -q --bare origin.git && git remote add origin "${CASE}/origin.git"
  printf 'origin.git\nrepos\n' > .git/info/exclude
  item hld/h.md "status: agreed" "grants: [epics]"
  item epics/a.md "status: draft" "stage: v1.3.0" "hld: h" "depends_on: [d]"
  item epics/b.md "status: draft" "stage: v1.3.0" "depends_on: [d]"
  git add -A && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m init \
    && git -c tag.gpgsign=false tag v1.2.0
  git push -q origin HEAD:main && git fetch -q origin && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
)
out="$(cd "${CASE}" && env -u HERDR_ENV bash "${REPO}/bin/swarm.sh" next)"
check "next's step is the stage step for the staged draft" "stage v1.3.0" "${out%%$'\n'*}"
check "touches_rows.py itself names both drafts" \
  "idle: epic a can start, exit: plan it, or set it active in a board PR"$'\n'"idle: epic b can start, exit: plan it, or set it active in a board PR" "$(idle)"
check "next prints the line for the draft with no hld: and none for the one its stage step covers" \
  "idle: epic b can start, exit: plan it, or set it active in a board PR" "$(grep '^idle: epic ' <<< "${out}" || true)"

# On a board outside the repo, an interrupted /plan-hld's marker (.swarm/<hld>/writing-epics) means its
# rerun will overwrite the epic: idle_now drops the no-plan line, as plannable_epic leaves the epic.
board; mkdir -p "${CASE}/proj/.claude/swarm" "${CASE}/proj/.swarm/h" && git -C "${CASE}/proj" init -q
echo "board_dir = ${CASE}/docs" > "${CASE}/proj/.claude/swarm/config"
item hld/h.md "status: agreed"; item epics/e1.md "status: active" "hld: h"
out="$(cd "${CASE}/proj" && env -u HERDR_ENV bash "${REPO}/bin/swarm.sh" next)"
check "outside the repo with no /plan-hld marker, next prints the no-plan line" \
  "idle: epic e1 has no plan running, exit: /swarm-dev:plan-epic e1" "$(grep '^idle: epic ' <<< "${out}" || true)"
echo e1 > "${CASE}/proj/.swarm/h/writing-epics"
out="$(cd "${CASE}/proj" && env -u HERDR_ENV bash "${REPO}/bin/swarm.sh" next)"
check "next's step is the interrupted /plan-hld's rerun" "plan-hld h" "${out%%$'\n'*}"
check "an epic a resuming /plan-hld will overwrite gets no no-plan line" "" "$(grep '^idle: epic ' <<< "${out}" || true)"

# swarm.md's next idle list quotes the lines --idle prints, with <epic> for the slug.
# quoted <prefix> — the first `idle: epic <epic> <prefix>...` quote in commands/swarm.md, backticks off.
# `|| true`: with no such quote, grep's exit 1 under pipefail would end the script with no FAIL line.
quoted() { grep -o "\`idle: epic <epic> $1[^\`]*\`" "${REPO}/commands/swarm.md" | head -1 | tr -d '`' || true; }
board; item epics/e.md "status: draft" "depends_on: [d]"; q="$(quoted "can start")"
check "commands/swarm.md quotes the can-start line touches_rows.py prints" "$(idle)" "${q//<epic>/e}"
board; item epics/e.md "status: active"; q="$(quoted "has no plan running")"
check "commands/swarm.md quotes the no-plan line touches_rows.py prints" "$(idle)" "${q//<epic>/e}"

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
