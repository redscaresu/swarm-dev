#!/usr/bin/env bash
# idle_epic_test.sh — next's idle epic lines (idle_epic_lines, through idle_now): a draft or later epic
# with nothing left to wait on gets `idle: epic <epic> can start, ...`, unless next's stage or plan-epic
# step names it; an active epic next's plan-epic step could name but does not, with no plan running,
# gets `idle: epic <epic> has no plan running, ...`; and commands/swarm.md quotes both lines as next
# prints them. Every check reads swarm.sh next on a board of its own, outside herdr, where next starts
# nothing, and one reads swarm.sh status, which passes next's step on; epics that do not interact share
# a board, so the file runs next about 17 times.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
# The claude stub goes first on PATH, so no swarm.sh next run here reaches the real claude.
mkdir -p "${ROOT}/bin" && cp "${REPO}/tests/claude_stub.sh" "${ROOT}/bin/claude"
export PATH="${ROOT}/bin:${PATH}"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
# has <name> <line> — the line is among LINES, the last run's idle: epic lines; no_line <name> <slug> — no
# idle: epic line names <slug>, whatever its exit.
has() { if grep -qxF "$2" <<< "${LINES}"; then echo "ok   $1"; else echo "FAIL $1: want '$2' among '${LINES}'"; fails=$((fails + 1)); fi; }
no_line() { if grep -q "^idle: epic $2 " <<< "${LINES}"; then echo "FAIL $1: want no line for $2, got '${LINES}'"; fails=$((fails + 1)); else echo "ok   $1"; fi; }

# board — a fresh project in CASE: an empty board under docs/ in a repo with no commit, so the board is
# in the repo (staged_draft can apply) and an epic's history reads as planned (epic_planned).
board() {
  CASE="$(mktemp -d "${ROOT}/case.XXXXXX")"
  mkdir -p "${CASE}/docs/stories" "${CASE}/docs/epics" "${CASE}/docs/hld" "${CASE}/.swarm/state"
  git -C "${CASE}" init -q
}

# item <path under docs/> <front-matter line>... — write a board file.
item() {
  local f="${CASE}/docs/$1"; shift
  { echo "---"; printf '%s\n' "$@"; printf -- '---\n\n# item\n'; } > "${f}"
}

# run [<project>] — swarm.sh next in CASE (or <project>): STEP is its first line, LINES its idle: epic
# lines. A next that fails or warns (idle_warned's warning: line) is a FAIL of its own.
run() {
  local out
  if ! out="$(cd "${1:-${CASE}}" && env -u HERDR_ENV bash "${REPO}/bin/swarm.sh" next 2>&1)"; then
    echo "FAIL swarm.sh next failed in ${1:-${CASE}}: ${out}"; fails=$((fails + 1))
  fi
  STEP="${out%%$'\n'*}"
  LINES="$(grep '^idle: epic ' <<< "${out}" || true)"
  if grep -q '^warning: ' <<< "${out}"; then echo "FAIL next warned: $(grep '^warning: ' <<< "${out}")"; fails=$((fails + 1)); fi
}
# The can-start line's exit is the epic's case: a draft (start_draft), a later epic with no stories
# (start_plan) and a later epic with stories (start_go).
start_draft() { echo "idle: epic $1 can start, exit: tell the user it can start (/swarm-dev:epic $1)"; }
start_plan() { echo "idle: epic $1 can start, exit: swarm.sh plan-unasked $1, then /swarm-dev:plan-epic $1"; }
start_go() { echo "idle: epic $1 can start, exit: the user's go, then set it active with agreed: <today> in a board PR"; }
noplan() { echo "idle: epic $1 has no plan running, exit: /swarm-dev:plan-epic $1"; }

# What a draft epic's depends_on may still wait on: e<n> depends on d<n>, each in its own state.
board
item epics/e1.md "status: draft" "depends_on: [d1]"
item epics/e2.md "status: draft" "depends_on: [d2]"; item epics/d2.md "status: active"; item stories/s2.md "status: ready" "kind: code" "epic: d2"
item epics/e3.md "status: draft" "depends_on: [d3]"; item epics/d3.md "status: done"
item epics/e4.md "status: draft" "depends_on: [d4]"; item epics/d4.md "status: split"; item epics/k4.md "status: active" "parent: d4"; item stories/s4.md "status: ready" "kind: code" "epic: k4"
item epics/e5.md "status: draft" "depends_on: [d5]"; item epics/d5.md "status: active"; item stories/s5.md "status: ready" "kind: lead" "epic: d5" "after: d5"
item epics/e6.md "status: draft" "depends_on: [d6]"; item stories/d6.md "kind: code"
item epics/e7.md "status: draft" "depends_on: [d7]"; item stories/d7.md "status: done" "kind: code"
run
has "a draft epic whose dependency epic left the board can start" "$(start_draft e1)"
no_line "a dependency epic still on the board gives no line" e2
has "a dependency epic marked done counts as gone" "$(start_draft e3)"
no_line "a split dependency epic with an open child epic gives no line" e4
has "a dependency epic whose only open story is a lead after: one counts as done (epic_after_only)" "$(start_draft e5)"
no_line "a dependency story with no status: is open (open_item), not done" e6
has "a dependency story marked done counts as gone" "$(start_draft e7)"
no_line "an active epic that counts as done is not one with no plan running" d5
rm "${CASE}/docs/epics/k4.md"; run
has "a split dependency epic whose children are gone counts as gone" "$(start_draft e4)"

# Later epics: the one next's plan-epic step names (unblocked_epic) gets no line; the others can start.
board; item epics/e.md "status: later" "depends_on: [d]"
run
check "a later epic with its dependencies done and no stories is next's plan-epic step" "plan-epic e" "${STEP}"
check "the later epic next's plan-epic step names gets no line" "" "${LINES}"
board
item epics/a.md "status: later" "depends_on: [d]"
item epics/e.md "status: later" "depends_on: [d]"
item epics/f.md "status: later" "depends_on: []"
item epics/g.md "status: later" "depends_on: []"; item stories/sg.md "status: ready" "kind: lead" "epic: g"
item epics/h.md "status: later" "depends_on: []"; item stories/sh.md "status: ready" "kind: code" "epic: h"
item epics/i.md "status: later" "parent: p" "depends_on: [d]"; item stories/si.md "status: ready" "kind: code" "epic: i"; item epics/p.md "status: split"
item epics/j.md "status: later" "depends_on: [d]" "unasked_plan: declined 2026-10-01"
item epics/m.md "status: later" "depends_on: [d]"; item stories/sm.md "status: later" "kind: code" "epic: m"
run
check "next's plan-epic step names the first unblocked later epic in board order" "plan-epic a" "${STEP}"
no_line "the later epic the step names gets no line" a
has "a second later epic with its dependencies done and no stories can start: plan it unasked, as the step would" "$(start_plan e)"
no_line "a later epic with no depends_on and no ready story waits on the user: no line" f
no_line "a later epic whose only ready story is a lead one gives no line" g
has "a later epic with a ready story an agent builds can start, on the user's go" "$(start_go h)"
no_line "a later child epic (parent: set) is the user's: no line, ready story or not" i
no_line "a later epic whose unasked plan the user declined gives no line" j
has "a later epic already planned, with its dependencies done, can start on the user's go" "$(start_go m)"

# The current stage: the lowest stage: an epic on the board carries; an epic with none is in it.
board; item epics/c.md "status: active" "stage: v1.2.0"; item stories/sc.md "status: ready" "kind: code" "epic: c"
item epics/e1.md "status: draft" "stage: v1.3.0" "depends_on: [d]"
item epics/e2.md "status: draft" "depends_on: [d]"
item epics/e3.md "status: draft" "stage: soon" "depends_on: [d]"
item epics/e4.md "status: draft" "parent: p" "depends_on: [d]"; item epics/p.md "status: split"
run
no_line "a draft epic of a later stage than the board's lowest gives no line" e1
has "a draft epic with no stage: is in the current stage" "$(start_draft e2)"
no_line "a draft epic whose stage: is not v<x.y.z> gives no line" e3
no_line "a draft child epic (parent: set) gives no line" e4
item epics/c.md "status: active" "stage: v1.3.0  # the release that ships it"
run
has "a draft epic of the lowest stage (a commented stage: read as its version) can start" "$(start_draft e1)"
item epics/z.md "status: done" "stage: v1.2.0"
run
no_line "a done epic still on the board with a lower stage: pins the current stage below the draft" e1

# next's stage step covers a staged draft (an agreed HLD granting epics, the minor before its stage
# tagged on origin/main): no line for it. A draft of the same stage with no hld: is no staged draft, so
# its line stays. The fixture repo's own commit and tag are unsigned: it is thrown away with ROOT.
board
(
  cd "${CASE}" && git init -q --bare origin.git && git remote add origin "${CASE}/origin.git"
  printf 'origin.git\n' > .git/info/exclude
  item hld/h.md "status: agreed" "grants: [epics]"
  item epics/a.md "status: draft" "stage: v1.3.0" "hld: h" "depends_on: [d]"
  item epics/b.md "status: draft" "stage: v1.3.0" "depends_on: [d]"
  git add -A && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m init \
    && git -c tag.gpgsign=false tag v1.2.0
  git push -q origin HEAD:main && git fetch -q origin && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
)
run
check "next's step is the stage step for the staged draft" "stage v1.3.0" "${STEP}"
check "next prints the line for the draft with no hld: and none for the one its stage step covers" "$(start_draft b)" "${LINES}"

# An active epic with no plan running: the epic next's plan-epic step names gets no line; under any
# other step, every plannable epic with no plan running gets it, the first in board order (a) too.
board; item epics/e.md "status: active"
run
check "a lone active epic with no stories is next's plan-epic step" "plan-epic e" "${STEP}"
check "the active epic next's plan-epic step names gets no line" "" "${LINES}"
# status prints what next would do and passes that step on, so the epic it names gets no idle: line
# there either (dash does the same; its goldens hold it).
out="$(cd "${CASE}" && env -u HERDR_ENV bash "${REPO}/bin/swarm.sh" status 2>&1)" || { echo "FAIL swarm.sh status failed: ${out}"; fails=$((fails + 1)); }
check "status's Next names the plan-epic step" "plan-epic e" "$(grep -E '^  plan-epic ' <<< "${out}" | sed 's/^  //' || true)"
check "status passes the step on, so the epic it names gets no idle: line there either" "" "$(grep -E '^ *idle: epic ' <<< "${out}" || true)"
board
item epics/a.md "status: active"
item epics/e.md "status: active"
item epics/e3.md "status: active"; item stories/s3.md "status: ready" "kind: lead" "epic: e3" "after: e3"
item epics/e4.md "status: active"; item stories/s4.md "status: blocked" "kind: code" "epic: e4"
item epics/e5.md "status: draft"
item epics/e6.md "status: active" "depends_on: [d]"; item epics/d.md "status: active"; item stories/sd.md "status: ready" "kind: code" "epic: d"
item epics/e7.md "status: active" "depends_on: [ds]"; item epics/ds.md "status: split"
item epics/e8.md "status: active" "parent: p" "depends_on: [p]"; item epics/p.md "status: split"; item epics/k.md "status: active" "parent: p"; item stories/sk.md "status: ready" "kind: code" "epic: k"
run
check "the step is a conduct, which next takes before plan-epic" "conduct d" "${STEP}"
has "under a conduct step no step names the first plannable epic, so it gets the line too" "$(noplan a)"
has "a second active epic with no stories and no plan running gets the line" "$(noplan e)"
no_line "an active epic whose only story is a lead after: one counts as done (epic_after_only): no line" e3
no_line "an active epic with a story gives no line" e4
no_line "a draft epic with no stories is not an unplanned active one" e5
no_line "an active epic whose dependency epic has a story not yet in review is held: no line" e6
has "a split dependency epic with no open child does not hold the plan" "$(noplan e7)"
has "an active child epic's own parent never holds its plan" "$(noplan e8)"
item stories/sd.md "status: review" "kind: code" "epic: d"; run
has "an active epic whose dependency epic's stories are in review gets the line" "$(noplan e6)"
echo "w1:p1 lead-e" > "${CASE}/.swarm/state/scope-e"; run
no_line "a scope-<epic> tab record (its plan running) gives no line" e
mv "${CASE}/.swarm/state/scope-e" "${CASE}/.swarm/state/scope-e-2"; run
no_line "a numbered overflow scope-<epic>-2 record gives no line" e
mv "${CASE}/.swarm/state/scope-e-2" "${CASE}/.swarm/state/scope-ex"; run
has "another epic's scope- record leaves the line" "$(noplan e)"
mkdir -p "${CASE}-wt/_board-scope-e"; run
no_line "an open plan board PR (its _board-scope-<epic> worktree) is a plan running: no line" e

# On a board outside the repo, an interrupted /plan-hld's marker (.swarm/<hld>/writing-epics) means its
# rerun will overwrite the epic: no no-plan line for it, as plannable_epics leaves the epic.
board; mkdir -p "${CASE}/proj/.claude/swarm" "${CASE}/proj/.swarm/h" && git -C "${CASE}/proj" init -q
echo "board_dir = ${CASE}/docs" > "${CASE}/proj/.claude/swarm/config"
item hld/h.md "status: agreed"; item epics/a.md "status: active"; item epics/e1.md "status: active" "hld: h"
run "${CASE}/proj"
has "outside the repo with no /plan-hld marker, next prints the no-plan line" "$(noplan e1)"
echo e1 > "${CASE}/proj/.swarm/h/writing-epics"; run "${CASE}/proj"
no_line "an epic a resuming /plan-hld will overwrite gets no no-plan line" e1

# swarm.md's next idle list quotes the lines next prints (above), with <epic> for the slug.
# quoted <prefix> — the first `idle: epic <epic> <prefix>...` quote in commands/swarm.md, backticks off.
# `|| true`: with no such quote, grep's exit 1 under pipefail would end the script with no FAIL line.
quoted() { grep -o "\`idle: epic <epic> $1[^\`]*\`" "${REPO}/commands/swarm.md" | head -1 | tr -d '`' || true; }
q="$(quoted "can start, exit: tell")"; check "commands/swarm.md quotes the draft's can-start line next prints" "$(start_draft e)" "${q//<epic>/e}"
q="$(quoted "can start, exit: swarm.sh plan-unasked")"; check "commands/swarm.md quotes the unplanned later epic's can-start line next prints" "$(start_plan e)" "${q//<epic>/e}"
q="$(quoted "can start, exit: the user")"; check "commands/swarm.md quotes the planned later epic's can-start line next prints" "$(start_go e)" "${q//<epic>/e}"
q="$(quoted "has no plan running")"; check "commands/swarm.md quotes the no-plan line next prints" "$(noplan e)" "${q//<epic>/e}"

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
