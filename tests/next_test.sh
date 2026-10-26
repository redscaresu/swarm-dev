#!/usr/bin/env bash
# next_test.sh — `swarm.sh next` against small throwaway boards, one per case.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
fails=0
# The claude stub goes first on PATH, so no run here reaches the real claude.
STUB_BIN="$(mktemp -d)"; trap 'rm -rf "${STUB_BIN}"' EXIT
export CLAUDE_CONFIG_DIR="${STUB_BIN}/claude-config"   # under its own root, so parallel runs share no ~/.claude
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}"

# item <path> <front-matter line>... — write a board file under docs/.
item() {
  local path="docs/$1" title; shift
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

# expect <name> <first line of `next`> <setup...> — build a board with the setup, check next. The
# whole output is left in out.
expect() {
  local name="$1" want="$2" dir got; shift 2
  dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
  [ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
  (
    cd "${dir}" && git init -q && mkdir -p docs/stories docs/epics docs/hld
    echo "# Stories" > docs/stories/README.md   # READMEs are never items
    for step in "$@"; do eval "${step}"; done
  )
  # The whole output, then its first line: `| head -1` can close the pipe while next is still
  # printing a gate's list, and the broken pipe fails the run under pipefail.
  # Its stderr is kept in ${err} too, for the checks that read it.
  out="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next 2> "${dir}.err")"; got="${out%%$'\n'*}"
  err="$(cat "${dir}.err")"; rm -f "${dir}.err"; [[ -z "${err}" ]] || echo "${err}" >&2
  if [[ "${got}" == "${want}" ]]; then
    echo "ok   ${name}"
  else
    echo "FAIL ${name}: want '${want}', got '${got}'"; fails=$((fails + 1))
  fi
  rm -rf "${dir}" "${dir}-wt"
}

expect "empty board" "done"
if [[ "${out}" == *"/epic <title>"* ]]; then echo "ok   an empty board names the /epic step"
else echo "FAIL an empty board does not name /epic <title>: ${out}"; fails=$((fails + 1)); fi
expect "draft epic waits on the user, not planned" "gate" \
  "item epics/e1.md 'status: draft'"
if [[ "${out}" == *"draft epic: e1, run /epic e1"* ]]; then echo "ok   a draft epic is named as waiting on the user"
else echo "FAIL a draft epic is not named as waiting on the user: ${out}"; fails=$((fails + 1)); fi
expect "draft epic once active is planned" "plan-epic e1" \
  "item epics/e1.md 'status: active'"
expect "an escalated story comes before a draft epic" "escalated esc" \
  "item epics/e1.md 'status: draft'" \
  "item stories/esc.md 'status: ready' 'kind: lead' 'escalated_from: code'"
expect "a draft epic is in the gate beside a lead story" "gate" \
  "item epics/e1.md 'status: draft'" \
  "item stories/l.md 'status: ready' 'kind: lead'"
if [[ "${out}" == *"lead: l"* && "${out}" == *"draft epic: e1, run /epic e1"* ]]; then echo "ok   the gate lists the lead story and the draft epic"
else echo "FAIL the gate does not list both the lead story and the draft epic: ${out}"; fails=$((fails + 1)); fi
# A draft HLD waits on the user, listed under waiting on you; a superseded one, and the README, are not.
expect "a draft HLD waits on the user" "gate" \
  "item hld/2026-01-01-a.md 'status: draft'"
if [[ "${out}" == *"draft hld: 2026-01-01-a, run /hld 2026-01-01-a"* ]]; then echo "ok   a draft HLD is named as waiting on the user"
else echo "FAIL a draft HLD is not named as waiting on the user: ${out}"; fails=$((fails + 1)); fi
# An agreed HLD is planned until its front matter says planned:, then finished once no epic names it.
expect "an agreed HLD with no planned: is planned, a superseded one is not" "plan-hld 2026-01-01-b" \
  "item hld/2026-01-01-b.md 'status: agreed'" \
  "item hld/2026-01-01-c.md 'status: superseded'"
expect "an agreed HLD whose ## Epics holds a hand-written link is still planned" "plan-hld h" \
  "item hld/h.md 'status: agreed'" \
  "printf '%s\n' '## Epics' '- [e1](../epics/e1.md)' >> docs/hld/h.md"
expect "an open plan PR (its worktree) lets the HLD fall through to the next arm" "escalated esc" \
  "item hld/h.md 'status: agreed'" \
  "item stories/esc.md 'status: ready' 'kind: lead' 'escalated_from: code'" \
  "mkdir -p \"\${PWD}-wt/_board-plan-h\""
expect "an open plan PR with nothing else open is a gate row, not done" "gate" \
  "item hld/h.md 'status: agreed'" \
  "mkdir -p \"\${PWD}-wt/_board-plan-h\""
if [[ "${out}" == *"plan PR awaiting merge: h"* ]]; then echo "ok   the gate lists the plan PR awaiting merge"
else echo "FAIL the gate does not list the plan PR: ${out}"; fails=$((fails + 1)); fi
expect "a planned HLD with an epic carrying its hld: plans the epic" "plan-epic e1" \
  "item hld/h.md 'status: agreed' 'planned: 2026-10-24'" \
  "item epics/e1.md 'status: active' 'hld: h'"
# An HLD decomposed through /epic before planned: existed has epics carrying its hld:: never planned again.
expect "an agreed HLD with no planned: and an epic carrying its hld: is not planned again" "gate" \
  "item hld/h.md 'status: agreed'" \
  "item epics/e1.md 'status: later' 'hld: h'"
if [[ "${out}" != *"plan-hld"* ]]; then echo "ok   an HLD with an epic carrying its hld: gets no plan-hld"
else echo "FAIL an HLD with an epic carrying its hld: gets plan-hld: ${out}"; fails=$((fails + 1)); fi
# planned: with no value once quotes, brackets and a comment are gone is not planned.
expect "planned: \"\" is not planned" "plan-hld h" \
  "item hld/h.md 'status: agreed' 'planned: \"\"'"
expect "planned: with only a comment is not planned" "plan-hld h" \
  "item hld/h.md 'status: agreed' 'planned: # by /plan-hld'"
expect "an epic whose hld: only shares a prefix does not count" "hld h" \
  "item hld/h.md 'status: agreed' 'planned: 2026-10-24'" \
  "item epics/e1.md 'status: later' 'hld: h-2'"
expect "a planned HLD with no epics left is finished" "hld h" \
  "item hld/h.md 'status: agreed' 'planned: 2026-10-24'"
if [[ "${out}" == *"swarm.sh finish h"* ]]; then echo "ok   the hld step names swarm.sh finish"
else echo "FAIL the hld step does not name swarm.sh finish h: ${out}"; fails=$((fails + 1)); fi
expect "an open finish PR (its worktree) is a gate row" "gate" \
  "item hld/h.md 'status: agreed' 'planned: 2026-10-24'" \
  "mkdir -p \"\${PWD}-wt/_board-finish-h\""
if [[ "${out}" == *"finish PR awaiting merge: h"* ]]; then echo "ok   the gate lists the finish PR awaiting merge"
else echo "FAIL the gate does not list the finish PR: ${out}"; fails=$((fails + 1)); fi
expect "a superseded HLD with no planned: is not planned" "done" \
  "item hld/h.md 'status: superseded'"
expect "a superseded HLD with planned: is neither planned nor finished" "done" \
  "item hld/h.md 'status: superseded' 'planned: 2026-10-24'"
expect "a draft HLD with planned: is the gate's draft line" "gate" \
  "item hld/h.md 'status: draft' 'planned: 2026-10-24'"
if [[ "${out}" == *"draft hld: h, run /hld h"* && "${out}" != *"plan-hld"* ]]; then echo "ok   a draft HLD is only the gate's draft line"
else echo "FAIL a draft HLD is not only the gate's draft line: ${out}"; fails=$((fails + 1)); fi
expect "the HLD README is never listed" "done" \
  "item hld/README.md 'status: draft'"
expect "an agreed HLD README is never planned" "done" \
  "item hld/README.md 'status: agreed'"
expect "an epic with an hld: key and its HLD present is planned" "plan-epic e1" \
  "item hld/2026-01-01-x.md 'status: agreed'" \
  "item epics/e1.md 'status: active' 'hld: 2026-01-01-x'"
expect "active epic, no stories" "plan-epic e1" \
  "item epics/e1.md 'status: active'"
expect "epic waits on an open dependency" "plan-epic b" \
  "item epics/a.md 'status: active' 'depends_on: [b]'" \
  "item epics/b.md 'status: active'"
expect "epic planned once its dependency is deleted" "plan-epic a" \
  "item epics/a.md 'status: active' 'depends_on: [b]'"
expect "epic planned once its dependency is done" "plan-epic a" \
  "item epics/a.md 'status: active' 'depends_on: [b]'" \
  "item epics/b.md 'status: done'"
# A dependency whose stories are all in review has built its code: the next epic is planned against
# it. One ready or blocked story left holds it up.
expect "epic planned once its dependency's stories are all in review" "plan-epic a" \
  "item epics/a.md 'status: active' 'depends_on: [b]'" \
  "item epics/b.md 'status: active'" \
  "item stories/s1.md 'status: review' 'kind: code' 'epic: b'" \
  "item stories/s2.md 'status: review' 'kind: code' 'epic: b'"
# A later epic whose one dependency is done is planned before the gate: planning is read-only, and
# its stories still wait for the user's approval. One not done yet leaves the gate.
expect "a later epic whose dependency is done is planned before the gate" "plan-epic a" \
  "item epics/a.md 'status: later' 'depends_on: [b]'" \
  "item epics/b.md 'status: done'" \
  "item stories/l.md 'status: ready' 'kind: lead'"
expect "a later epic whose dependency is not done waits in the gate" "gate" \
  "item epics/a.md 'status: later' 'depends_on: [b]'" \
  "item epics/b.md 'status: active'" \
  "item stories/s1.md 'status: review' 'kind: code' 'epic: b'"
# shellcheck disable=SC2016 # backticks are the Markdown's, never expanded
if grep -qF 'its why says a `later` epic'"'"'s dependencies are done' "$(dirname "${SWARM}")/../commands/swarm.md" \
  && grep -qF 'unasked: planning is read-only. First run `swarm.sh plan-unasked <epic>`' "$(dirname "${SWARM}")/../commands/swarm.md" \
  && grep -qF 'run `swarm.sh plan-unasked --declined <epic>`' "$(dirname "${SWARM}")/../commands/swarm.md"; then echo "ok   swarm.md runs an unblocked epic's plan-epic unasked"
else echo "FAIL swarm.md does not say the lead plans an unblocked epic unasked"; fails=$((fails + 1)); fi
# shellcheck disable=SC2016 # backticks are the Markdown's, never expanded
if grep -qF '`status: later` when $1 is `later`' "$(dirname "${SWARM}")/../commands/plan-epic.md"; then echo "ok   plan-epic.md keeps a later epic's child epics later"
else echo "FAIL plan-epic.md's split arm makes a later epic's children active"; fails=$((fails + 1)); fi
# A later epic that has stories, or is a split epic's later child, waits for the user to start it.
expect "a later epic with done dependencies and a story is a gate" "gate" \
  "item epics/a.md 'status: later' 'depends_on: [b]'" \
  "item stories/s.md 'status: ready' 'kind: code' 'epic: a'"
expect "a split later epic's later child is not planned unasked" "gate" \
  "item epics/p.md 'status: split' 'depends_on: [b]'" \
  "item epics/c.md 'status: later' 'parent: p' 'depends_on: [b]'"
# Once planned unasked (plan-unasked), a later epic is never offered again: the gate says what to do
# with it. With no stories yet, plan it again if that plan stopped; with stories (they reach the board
# only once approved), set it active. Declined (--declined), the gate says that instead.
expect "a later epic planned unasked with no stories is a gate" "gate" \
  "item epics/a.md 'status: later' 'depends_on: [b]'" \
  "bash \"\${SWARM}\" plan-unasked a >/dev/null"
if [[ "${out}" == *"later epic: a (planned unasked on $(date +%F), no stories yet; run /plan-epic a again if that plan stopped)"* ]]; then echo "ok   the gate says a later epic planned unasked with no stories can be planned again"
else echo "FAIL the gate's line for a later epic planned unasked with no stories: ${out}"; fails=$((fails + 1)); fi
expect "a later epic planned unasked with stories is a gate" "gate" \
  "item epics/a.md 'status: later' 'depends_on: [b]'" \
  "item stories/s.md 'status: ready' 'kind: code' 'epic: a'" \
  "bash \"\${SWARM}\" plan-unasked a >/dev/null"
if [[ "${out}" == *"later epic: a (planned unasked on $(date +%F); set it active to start it)"* ]]; then echo "ok   the gate says to set a later epic planned unasked with stories active"
else echo "FAIL the gate's line for a later epic planned unasked with stories: ${out}"; fails=$((fails + 1)); fi
expect "a later epic whose unasked plan was declined is offered no more" "gate" \
  "item epics/a.md 'status: later' 'depends_on: [b]'" \
  "bash \"\${SWARM}\" plan-unasked --declined a >/dev/null"
if [[ "${out}" == *"later epic: a (its unasked plan was declined $(date +%F))"* ]]; then echo "ok   the gate says the later epic's unasked plan was declined"
else echo "FAIL the gate does not say a's unasked plan was declined: ${out}"; fails=$((fails + 1)); fi
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p docs/stories && item epics/e.md 'status: active')
got="$(cd "${dir}" && bash "${SWARM}" plan-unasked e 2>&1; echo "exit $?")"
if [[ "${got}" == *"plan-unasked: e is not a later epic"*"exit 1" ]]; then echo "ok   plan-unasked refuses an epic that is not later"
else echo "FAIL plan-unasked on an active epic: ${got}"; fails=$((fails + 1)); fi
# --declined after the slug counts too; a second slug is refused.
(cd "${dir}" && item epics/l.md 'status: later')
got="$(cd "${dir}" && bash "${SWARM}" plan-unasked l --declined 2>&1; bash "${SWARM}" plan-unasked l e 2>&1; echo "exit $?")"
if [[ "${got}" == "plan-unasked: l, declined on $(date +%F)"*"plan-unasked: one epic only"*"exit 1" ]]; then echo "ok   plan-unasked takes --declined after the slug and refuses a second slug"
else echo "FAIL plan-unasked with the flag last or two slugs: ${got}"; fails=$((fails + 1)); fi
rm -rf "${dir}"
# A ready lead story: no agent builds it, so next reaches the plan-epic arm instead of conduct b.
expect "a ready story of its dependency holds an epic's planning" "gate" \
  "item epics/a.md 'status: active' 'depends_on: [b]'" \
  "item epics/b.md 'status: active'" \
  "item stories/s1.md 'status: review' 'kind: code' 'epic: b'" \
  "item stories/s2.md 'status: ready' 'kind: lead' 'epic: b'"
expect "a blocked story of its dependency holds an epic's planning" "gate" \
  "item epics/a.md 'status: active' 'depends_on: [b]'" \
  "item epics/b.md 'status: active'" \
  "item stories/s1.md 'status: review' 'kind: code' 'epic: b'" \
  "item stories/s2.md 'status: blocked' 'kind: code' 'epic: b'"
expect "an open depends_on story holds an epic's planning" "gate" \
  "item epics/a.md 'status: active' 'depends_on: [s]'" \
  "item stories/s.md 'status: review' 'kind: code'"
expect "active epic before a one-off" "conduct e1" \
  "item epics/e1.md 'status: active'" \
  "item stories/a-one-off.md 'status: ready' 'kind: code'" \
  "item stories/b.md 'status: ready' 'kind: code' 'epic: e1'"
expect "one-off story" "story a" \
  "item stories/a.md 'status: ready'"
expect "blocked code story is a gate, not done" "gate" \
  "item epics/e1.md 'status: active'" \
  "item stories/a.md 'status: blocked' 'kind: code' 'epic: e1' 'depends_on: [b]'"
# shellcheck disable=SC2016 # the setup is eval'd inside the fixture, so $PWD is the fixture's
expect "started one-off resumes" "resume a" \
  "item stories/a.md 'status: ready'" \
  'mkdir -p "../$(basename "$PWD")-wt/a"'
# The same one-off with a real worktree, its builder open in a pane this project recorded: a counted
# close clears the worktree, so the next step builds it afresh. herdr and gh are stubs.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
origin="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
(
  cd "${dir}" && git init -q && git init -q --bare "${origin}" && git remote add origin "${origin}"
  git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init && git push -q origin HEAD
  mkdir -p docs/stories bin .swarm/state && item stories/a.md 'status: ready' 'kind: code'
  git worktree add -q -b story/a "../$(basename "${dir}")-wt/a" && echo "w:1 a" > .swarm/state/a
  # shellcheck disable=SC2016 # the stubs' own shell expands these
  printf '%s\n' '#!/bin/sh' 'case "$1 $2" in' \
    "  \"agent list\") echo '{\"result\":{\"agents\":[{\"name\":\"a\",\"agent_status\":\"idle\",\"pane_id\":\"w:1\"}]}}' ;;" \
    "  \"tab list\") echo '{\"result\":{\"tabs\":[]}}' ;;" 'esac' > bin/herdr
  printf '%s\n' '#!/bin/sh' "[ \"\$1 \$2\" = 'pr list' ] && echo '[]'" 'exit 0' > bin/gh
  chmod +x bin/herdr bin/gh
)
nxt() { local got; got="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next)"; echo "${got%%$'\n'*}"; }
before="$(nxt)"
(cd "${dir}" && HERDR_ENV=1 PATH="${dir}/bin:${PATH}" bash "${SWARM}" close a >/dev/null 2>&1) || true
for pair in "before:resume a:${before}" "after:story a:$(nxt)"; do
  IFS=: read -r when want got <<< "${pair}"
  if [[ "${got}" == "${want}" ]]; then echo "ok   a started one-off is '${want}' ${when} the counted close"; else
    echo "FAIL a started one-off is '${want}' ${when} the counted close: got '${got}'"; fails=$((fails + 1)); fi
done
rm -rf "${dir}" "${dir}-wt" "${origin}"
expect "blocked story is not built" "gate" \
  "item epics/e1.md 'status: active'" \
  "item stories/a.md 'status: blocked' 'kind: lead' 'epic: e1'"
expect "unknown kind is a gate, not built" "gate" \
  "item stories/a.md 'status: ready' 'kind: Lead'"
expect "old operator kind is a gate, not built" "gate" \
  "item stories/a.md 'status: ready' 'kind: operator'"
expect "lead story is a gate" "gate" \
  "item stories/a.md 'status: ready' 'kind: lead'"
# verify is no longer a kind an agent builds: a ready verify story gets no conduct or story step, and
# status --all lists it under Waiting on you, as for a typo.
expect "a verify one-off is a gate, not a story step" "gate" \
  "item stories/v.md 'status: ready' 'kind: verify'"
expect "an epic's verify story is a gate, not a conduct step" "gate" \
  "item epics/e1.md 'status: active'" \
  "item stories/v.md 'status: ready' 'kind: verify' 'epic: e1'"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p docs/stories && item stories/v.md 'status: ready' 'kind: verify')
waiting="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" status --all | sed -n '/^Waiting on you$/,/^$/p')"
if grep -qx '  verify: v' <<< "${waiting}"; then echo "ok   status --all lists a ready verify story under Waiting on you"
else echo "FAIL status --all lists a ready verify story under Waiting on you: got '${waiting}'"; fails=$((fails + 1)); fi
rm -rf "${dir}"
# A story whose Fable build failed is the lead's to decide, so next names it instead of the gate.
expect "an escalated story is the lead's to decide, ahead of gate" "escalated b" \
  "item stories/a.md 'status: ready' 'kind: lead'" \
  "item stories/b.md 'status: ready' 'kind: lead' 'attempts: 3' 'escalated_from: code'"
# `close <slug> impossible` hands a story on with an **Impossible.** block: the lead's, like a failed
# Fable build, so escalated, never a gate; next's reason says its builder called it impossible.
IMPOSSIBLE_BLOCK="mkdir -p .swarm/escalated && echo '**Impossible.** The builder replied' > .swarm/escalated/b"
expect "an impossible story is the lead's to decide, escalated, not a gate" "escalated b" \
  "item stories/b.md 'status: ready' 'kind: lead' 'attempts: 1' 'escalated_from: code'" "${IMPOSSIBLE_BLOCK}"
# drop deletes the story in a board PR (pr_removes_story_test.sh); here that PR has landed.
expect "once the lead drops it, next no longer names it" "gate" \
  "item stories/a.md 'status: ready' 'kind: lead'" \
  "item stories/b.md 'status: ready' 'kind: lead' 'attempts: 3' 'escalated_from: code'" \
  'rm docs/stories/b.md'
# The escalated story is the lead's, so status's Waiting on you lists the plain lead story, not it.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p docs/stories && item stories/a.md 'status: ready' 'kind: lead' \
  && item stories/b.md 'status: ready' 'kind: lead' 'attempts: 3' 'escalated_from: code')
waiting="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" status | sed -n '/^Waiting on you$/,/^$/p')"
if grep -qx '  lead: a' <<< "${waiting}" && ! grep -q 'b$' <<< "${waiting}"; then echo "ok   status lists a plain lead story under Waiting on you, never an escalated one"
else echo "FAIL status lists a plain lead story under Waiting on you, never an escalated one: got '${waiting}'"; fails=$((fails + 1)); fi
rm -rf "${dir}"
# An impossible story is never under Waiting on you, and next says why it is the lead's.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p docs/stories && item stories/b.md 'status: ready' 'kind: lead' 'attempts: 1' 'escalated_from: code' \
  && eval "${IMPOSSIBLE_BLOCK}")
waiting="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" status | sed -n '/^Waiting on you$/,/^$/p')"
why="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next | sed -n 2p)"
if ! grep -q 'b$' <<< "${waiting}" && [[ "${why}" == "b's builder called its Done when impossible: re-scope it and run swarm.sh reset b <reason>, or swarm.sh drop b <reason>, then tell the user why" ]]; then
  echo "ok   an impossible story is not under Waiting on you, and next says its builder called it impossible"
else echo "FAIL an impossible story is not under Waiting on you, and next says its builder called it impossible: got '${waiting}' and '${why}'"; fails=$((fails + 1)); fi
rm -rf "${dir}"
# Before its one reset, next offers reset or drop; after it (an ok reset line in events.tsv), only drop.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p docs/stories .swarm && item stories/b.md 'status: ready' 'kind: lead' 'attempts: 3' 'escalated_from: code')
why1="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next | sed -n 2p)"
printf '2026-10-15T01:00:00Z\treset\tb\tw:me\tok (re-scoped)\n' > "${dir}/.swarm/events.tsv"
why2="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next | sed -n 2p)"
# An impossible story after its one reset is offered only drop too.
(cd "${dir}" && eval "${IMPOSSIBLE_BLOCK}")
why3="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next | sed -n 2p)"
if [[ "${why1}" == *"swarm.sh reset b <reason>"* && "${why2}" == *"after its one reset (2026-10-15T01:00:00Z)"* \
      && "${why2}" == *"swarm.sh drop b <reason>"* && "${why2}" != *"swarm.sh reset"* \
      && "${why3}" == *"impossible after its one reset (2026-10-15T01:00:00Z)"* && "${why3}" == *"swarm.sh drop b <reason>"* && "${why3}" != *"swarm.sh reset"* ]]; then
  echo "ok   next offers reset before a story's one reset, and only drop after it, impossible or not"
else echo "FAIL next offers reset before a story's one reset, and only drop after it, impossible or not: got '${why1}', '${why2}', '${why3}'"; fails=$((fails + 1)); fi
rm -rf "${dir}"
# close s1 paused or cleared-on-error, with its builder open (herdr and gh stubs), holds the story on
# the board: next names it escalated, with the cause and never Fable, until reset lifts the hold.
HOLD_BIN="$(mktemp -d)"
cat > "${HOLD_BIN}/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;   # start_agent's require_herdr_version
  "agent list") echo '{"result":{"agents":[{"name":"s1","agent_status":"idle","pane_id":"w:p1"}]}}' ;;
  "tab list") echo '{"result":{"tabs":[]}}' ;;
esac
STUB
printf '#!/bin/sh\necho "[]"\n' > "${HOLD_BIN}/gh"
chmod +x "${HOLD_BIN}/herdr" "${HOLD_BIN}/gh"
for c in paused cleared-on-error; do
  dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
  (cd "${dir}" && git init -q && git remote add origin "${dir}/none.git" && mkdir -p docs/stories .swarm/state \
    && item stories/s1.md 'status: ready' 'kind: code' 'attempts: 1' && echo "w:p1 s1" > .swarm/state/s1)
  (cd "${dir}" && CLAUDE_CONFIG_DIR="${dir}/cc" HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${HOLD_BIN}:${PATH}" bash "${SWARM}" close s1 "${c}" >/dev/null 2>&1) || true
  held="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next)"
  (cd "${dir}" && bash "${SWARM}" reset s1 lifted >/dev/null 2>&1) || true
  lifted="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next | sed -n 1p)"
  if [[ "${held%%$'\n'*}" == "escalated s1" && "$(sed -n 2p <<< "${held}")" =~ paused|cleared && "${held}" != *Fable* && "${lifted}" == "story s1" ]]; then
    echo "ok   after close s1 ${c}, next prints escalated s1 naming the cause, not Fable; after reset, it offers story s1"
  else echo "FAIL after close s1 ${c}, next prints escalated s1 naming the cause, not Fable; after reset, it offers story s1: got '${held}' then '${lifted}'"; fails=$((fails + 1)); fi
  rm -rf "${dir}"
done
rm -rf "${HOLD_BIN}"
# /swarm's story and resume arms hand a one-off to the backlog conductor, whose brief carries the
# review, goal and give-up rules (backlog_test.sh), and stop on a story it reported not started.
# shellcheck disable=SC2016 # the backticks are literal Markdown
arm="$(sed -n '/^   - `resume <slug>`:/,/^   - `plan-epic <epic>`:/p' "$(dirname "${SWARM}")/../commands/swarm.md")"
got=""
# Each arm on its own: the resume arm stops on a dead build, naming its worktree and the commands
# that remove it; the story arm stops on any unchanged report, reading only stories/ and epics/.
# armwords <arm heading> <phrase>... — "<arm> missing '<phrase>'" for each phrase that arm lacks.
armwords() {
  local a="$1" part w; shift
  part="$(awk -v a="${a}" 'index($0, a) == 1 { on = 1; print; next } on && /^   - `/ { exit } on' <<< "${arm}" | tr -s '[:space:]' ' ')"
  for w in "$@"; do grep -qF -- "${w}" <<< "${part}" || printf " %s missing '%s'" "${a# *- }" "${w}"; done
}
# shellcheck disable=SC2016 # the backticks are literal Markdown
got+="$(armwords '   - `resume <slug>`:' 'swarm.sh conduct --backlog' 'not started:' 'name its worktree' \
  'has commits worth keeping (`git log origin/<base>..story/<slug>`' \
  '`git worktree remove --force ../<repo>-wt/<slug>`' '`git worktree prune`' '`git branch -D story/<slug>`' \
  '`git push origin --delete story/<slug>` if it was pushed' 'then delete `.swarm/conduct-backlog.report.md`')"
# shellcheck disable=SC2016 # the backticks are literal Markdown
got+="$(armwords '   - `story <slug>`:' 'swarm.sh conduct --backlog' 'not started:' 'whatever the report says: start no' \
  "\`find <board>/stories <board>/epics \\( -name '*.md' -o -type d \\) -newer .swarm/conduct-backlog.report.md\`" \
  'deleting `.swarm/conduct-backlog.report.md` once the cause is fixed')"
if [[ -z "${got}" ]]; then echo "ok   commands/swarm.md's story and resume arms run conduct --backlog, stop on not started: or an unchanged report, and say what clears each stop"
else echo "FAIL commands/swarm.md's story and resume arms:${got}"; fails=$((fails + 1)); fi
# /swarm acts on `escalated <slug>` itself: its arm resets or drops the story and tells the user why.
# shellcheck disable=SC2016 # the backticks are literal Markdown
arm="$(sed -n '/^   - `escalated <slug>`:/,/^   - `gate`:/p' "$(dirname "${SWARM}")/../commands/swarm.md")"
got=""; for w in 'swarm.sh reset <slug> <reason>' 'swarm.sh drop <slug> <reason>' 'not a stop' 'tell the user' \
         'swarm.sh reset <slug> <reason> && git pull --ff-only' 'Waiting on you' '(its block starts **Impossible.**)' \
         'its block starts **Held (<cause>).**' 'Lifting a hold is not the story'"'"'s one reset'; do grep -qF -- "${w}" <<< "${arm}" || got+=" missing '${w}'"; done
if [[ -z "${got}" ]]; then echo "ok   commands/swarm.md's escalated arm resets then pulls, or drops, is not a stop, tells the user, and shows Waiting on you while it waits"
else echo "FAIL commands/swarm.md's escalated arm:${got}"; fails=$((fails + 1)); fi
expect "ready story in a later epic waits" "gate" \
  "item epics/e1.md 'status: later'" \
  "item stories/a.md 'status: ready' 'kind: code' 'epic: e1'"
expect "only later stories left is a gate, not done" "gate" \
  "item stories/a.md 'status: later' 'kind: code'"
# A later epic with no depends_on waits on nothing but the user: it is never planned unasked.
expect "only later epics left is a gate" "gate" \
  "item epics/e1.md 'status: later'"
expect "a later epic with an empty depends_on is a gate" "gate" \
  "item epics/e1.md 'status: later' 'depends_on: []'"
# A blocked story whose dependency shares no file in touches waits for nothing it uses: next names it.
# A shared file (another function in it counts), a needs: line, or a hold by review keeps it quiet.
# idle_case <name> <b's touches> <named: yes|no> [b's extra front-matter line]
idle_case() {
  local got=no
  expect "idle dependency, $1" "story a" \
    "item stories/a.md 'status: ready' 'kind: code' 'touches: [x.sh:f, y.sh]'" \
    "item stories/b.md 'status: blocked' 'kind: code' 'depends_on: [a]' 'touches: [$2]' ${4:+"'$4'"}"
  grep -qxF "idle: b waits on a but shares no touches with it" <<< "${out}" && got=yes
  if [[ "${got}" == "$3" ]]; then echo "ok   idle dependency, $1: named $3"
  else echo "FAIL idle dependency, $1: want named $3: ${out}"; fails=$((fails + 1)); fi
}
idle_case disjoint c.sh yes
idle_case "shared file" x.sh:g no
idle_case "needs line" c.sh no "needs: a.sh"
idle_case "held by review" c.sh no "held_by: review"
# A multi-word kind is no kind an agent builds: it stays with the lead.
expect "a multi-word kind stays with the lead" "gate" \
  "item stories/a.md 'status: ready' 'kind: code docs'"
# A blocked lead story's dependency must stay, whatever its touches.
expect "a blocked lead story is never named over-broad" "story a" \
  "item stories/a.md 'status: ready' 'kind: code' 'touches: [x.sh]'" \
  "item stories/b.md 'status: blocked' 'kind: lead' 'depends_on: [a]' 'touches: [c.sh]'"
if ! grep -q '^idle: b ' <<< "${out}"; then echo "ok   a blocked lead story is not named over-broad"
else echo "FAIL a blocked lead story is named over-broad: ${out}"; fails=$((fails + 1)); fi
# A dependency in review: unblock stacks the story on its PR, so it is not idle.
expect "a dependency in review is never named over-broad" "gate" \
  "item stories/a.md 'status: review' 'kind: code' 'touches: [x.sh]'" \
  "item stories/b.md 'status: blocked' 'kind: code' 'depends_on: [a]' 'touches: [c.sh]'"
if ! grep -q '^idle: b ' <<< "${out}"; then echo "ok   a dependency in review is not named over-broad"
else echo "FAIL a dependency in review is named over-broad: ${out}"; fails=$((fails + 1)); fi
# A lead story's step (credentials, a person) is no code to share: depending on it is never over-broad.
expect "idle dependency on a lead story" "gate" \
  "item stories/a.md 'status: ready' 'kind: lead' 'touches: [x.sh]'" \
  "item stories/b.md 'status: blocked' 'kind: code' 'depends_on: [a]' 'touches: [c.sh]'"
if ! grep -q '^idle: b ' <<< "${out}"; then echo "ok   a dependency on a lead story is not named over-broad"
else echo "FAIL a dependency on a lead story is named over-broad: ${out}"; fails=$((fails + 1)); fi

# findings_fixture — a findings.tsv (run inside a fixture): "cache the parse" declined out-of-scope
# twice (listed once, by its newest row), one declined as a nit, an old one, one fixed after its
# decline, one a story carries (filed), one a story carried that merged and left the board, one an
# open board PR's branch files, and one the lead logged with log-finding --filed (a paraphrased story).
findings_fixture() {
  local t; t="$(date +%F)"; mkdir -p .swarm
  {
    printf '%s\tk\to/r#1\tcache the parse\tdeclined\tcodex\tout-of-scope\n' "${t}"
    printf '%s\tk\to/r#2\ttoo small\tdeclined\tcodex\tnit\n2020-01-01\tk\to/r#3\tancient\tdeclined\tcodex\tout-of-scope\n' "${t}"
    printf '%s\tk\to/r#4\tcache the parse\tdeclined\tcodex\tout-of-scope\n' "${t}"
    printf '%s\tk\to/r#5\tsplit the lexer\tdeclined\tcodex\tout-of-scope\n%s\tk\to/r#6\tsplit the lexer\tfixed\tcodex\n' "${t}" "${t}"
    printf '%s\tk\to/r#7\tfiled already\tdeclined\tcodex\tout-of-scope\n' "${t}"
    printf '%s\tk\to/r#8\tfiled and merged\tdeclined\tcodex\tout-of-scope\n' "${t}"
    printf '%s\tk\to/r#9\tfiled in a board PR\tdeclined\tcodex\tout-of-scope\n' "${t}"
    printf '%s\tk\to/r#10\tlogged as filed\tdeclined\tcodex\tout-of-scope\n' "${t}"
  } > .swarm/findings.tsv
  bash "${SWARM}" log-finding --filed --reviewer lead k o/r#10 'logged as filed' >/dev/null
  echo "filed already" >> docs/stories/bl.md
  item stories/gone.md 'status: ready' 'kind: code'; echo "filed and merged" >> docs/stories/gone.md
  git add docs/stories/gone.md && git -c user.name=t -c user.email=t@t commit -qm file
  git rm -q docs/stories/gone.md && git -c user.name=t -c user.email=t@t commit -qm merged
  git checkout -q -b board/file-it && item stories/pr.md 'status: ready' 'kind: code' && echo "filed in a board PR" >> docs/stories/pr.md
  git add docs/stories/pr.md && git -c user.name=t -c user.email=t@t commit -qm "board PR" && git checkout -q -
}
# idle_project <name> <want lines> — check that next named the project idle with exactly these lines.
idle_project() {
  local got; got="$(sed -n '/^idle: ".*"$/,$p' <<< "${out}")"
  if [[ "${got}" == "$2" ]]; then echo "ok   $1"
  else echo "FAIL $1: want '$2', got '${got}': ${out}"; fails=$((fails + 1)); fi
}
# A project with nothing an agent can build: next names it idle with the out-of-scope finding still
# to file, never its later story (the user's to start, which the gate lists).
expect "an idle project is a gate" "gate" \
  "item stories/l1.md 'status: later' 'kind: code'" \
  "item stories/bl.md 'status: blocked' 'kind: code' 'depends_on: [l1]'" \
  "item stories/ld.md 'status: ready' 'kind: lead'" \
  findings_fixture
p="$(grep '^idle: ".*"$' <<< "${out}" || true)"
idle_project "an idle project lists one out-of-scope finding, deduped, unfixed and unfiled, and no later story" \
  "${p:-idle: ?}"$'\n'"  out-of-scope finding: $(date +%F) k o/r#4: cache the parse"
# A ready story in a later epic: next does not build it, so nothing is buildable and the project is idle.
expect "a ready story in a later epic leaves the project idle" "gate" \
  "item epics/e1.md 'status: later'" \
  "item stories/s.md 'status: ready' 'kind: code' 'epic: e1'" \
  "item stories/bl.md 'status: blocked' 'kind: code'" \
  findings_fixture
if grep -q '^idle: ".*"$' <<< "${out}"; then echo "ok   a ready story in a later epic is no buildable story: the project is named idle"
else echo "FAIL a ready story in a later epic keeps the project from being named idle: ${out}"; fails=$((fails + 1)); fi
# With no finding to offer there is nothing for the lead to do: no idle project line.
expect "an idle project with nothing to offer" "gate" \
  "item stories/l1.md 'status: later' 'kind: code'"
if ! grep -q '^idle: ".*"$' <<< "${out}"; then echo "ok   with no finding to offer the project is not named idle"
else echo "FAIL with no finding to offer the project is named idle: ${out}"; fails=$((fails + 1)); fi
# A board in no git repo: log-finding --filed writes a filed row, and that row alone drops the finding.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && mkdir -p .claude/swarm .swarm docs/stories && : > .claude/swarm/config && item stories/l1.md 'status: later' 'kind: code' \
  && printf '%s\tk\to/r#1\tstill open\tdeclined\tcodex\tout-of-scope\n%s\tk\to/r#2\tlogged as filed\tdeclined\tcodex\tout-of-scope\n' "$(date +%F)" "$(date +%F)" > .swarm/findings.tsv \
  && bash "${SWARM}" log-finding --filed --reviewer lead k o/r#2 "logged as filed" >/dev/null)
out="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next)"
if tail -1 "${dir}/.swarm/findings.tsv" | grep -q $'\tlogged as filed\tfiled\tlead$'; then echo "ok   log-finding --filed writes a filed row"
else echo "FAIL log-finding --filed wrote: $(tail -1 "${dir}/.swarm/findings.tsv")"; fails=$((fails + 1)); fi
idle_project "with no git, a finding logged as filed is not offered" "idle: \"$(basename "${dir}")\""$'\n'"  out-of-scope finding: $(date +%F) k o/r#1: still open"
rm -rf "${dir}"
# A reader that has stopped reading (a closed stdout, as after head -1 or grep -q) leaves next
# exiting 0 with no warning: it writes its step and idle lines in one go and ignores the broken pipe.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p docs/stories && item stories/a.md 'status: ready' 'kind: code' 'touches: [x.sh]' \
  && item stories/b.md 'status: blocked' 'kind: code' 'depends_on: [a]' 'touches: [c.sh]')
got="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next 2>"${dir}/err" | true; echo "exit ${PIPESTATUS[0]}")"
if [[ "${got}" == "exit 0" && ! -s "${dir}/err" ]]; then echo "ok   next into a closed pipe exits 0 with no warning"
else echo "FAIL next into a closed pipe: ${got} $(cat "${dir}/err")"; fails=$((fails + 1)); fi
rm -rf "${dir}"
# A failure in next_step stops next: it runs in the main shell, where errexit is on. A basename that
# fails on a ready story's path fails next_step's buildable+="... $(basename ...)" assignment.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
# shellcheck disable=SC2016 # the stub's $1 and $@ are its own
(cd "${dir}" && git init -q && mkdir -p bin && mkdir -p docs/stories && item stories/x.md 'status: ready' 'kind: code' 'touches: [x.sh]' \
  && printf '#!/bin/sh\ncase "$1" in */stories/x.md) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v basename)" > bin/basename && chmod +x bin/basename)
got="$(cd "${dir}" && PATH="${dir}/bin:${PATH}" env -u HERDR_ENV bash "${SWARM}" next 2>/dev/null; echo "exit $?")"
if [[ "${got}" != "exit 0" && "${got}" != *$'\n'"exit 0" ]]; then echo "ok   a failure in next_step makes next fail"
else echo "FAIL a failure in next_step does not stop next: ${got}"; fails=$((fails + 1)); fi
rm -rf "${dir}"
# A planning step is about to give the builders stories: no idle project beside it.
expect "a planning step is no idle project" "plan-epic e1" \
  "item epics/e1.md 'status: active'" \
  "item stories/bl.md 'status: blocked' 'kind: code'" \
  findings_fixture
if ! grep -q '^idle: ".*"$' <<< "${out}"; then echo "ok   beside plan-epic the project is not named idle"
else echo "FAIL beside plan-epic the project is named idle: ${out}"; fails=$((fails + 1)); fi
# The idle check is advisory: when touches_rows.py fails (a state file that is a directory), next
# still prints its step, warns, and exits 0. A project name with a space stays one quoted name.
dir="$(mktemp -d)/my proj" || { echo "mktemp -d failed" >&2; exit 1; }
mkdir -p "${dir}" && (cd "${dir}" && git init -q && mkdir -p docs/stories .swarm/board-state/stories/a && item stories/a.md 'status: ready' 'kind: code')
got="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next 2>"${dir}.err"; echo "exit $?")"
if [[ "${got}" == "story a"*"exit 0" ]] && grep -q '^warning: the idle-dependency check failed' "${dir}.err"; then echo "ok   a failed idle check warns and next still exits 0"
else echo "FAIL a failed idle check: ${got} $(cat "${dir}.err")"; fails=$((fails + 1)); fi
(cd "${dir}" && rm -rf .swarm && item stories/a.md 'status: later' 'kind: code' && mkdir .swarm \
  && printf '%s\tk\to/r#1\tone to file\tdeclined\tcodex\tout-of-scope\n' "$(date +%F)" > .swarm/findings.tsv)
got="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next)"
if grep -qx 'idle: "my proj"' <<< "${got}"; then echo "ok   a project name with a space is one quoted name on its idle line"
else echo "FAIL a project name with a space: ${got}"; fails=$((fails + 1)); fi
rm -rf "$(dirname "${dir}")"
expect "a project with a buildable story is not idle" "story r" \
  "item stories/l1.md 'status: later' 'kind: code'" \
  "item stories/r.md 'status: ready' 'kind: code'"
if ! grep -q '^idle: ' <<< "${out}"; then echo "ok   a project with a buildable story is not named idle"
else echo "FAIL a project with a buildable story is named idle: ${out}"; fails=$((fails + 1)); fi
# The lead's half: swarm.md says what to do with each idle: line, plan-epic's critic checks for it.
cmds="$(dirname "${SWARM}")/../commands"
got=""
# shellcheck disable=SC2016 # backticks are the Markdown's, never expanded
{
grep -qF '`idle: <story> waits on <dep> but shares no touches with it`' "${cmds}/swarm.md" || got+=" swarm.md has no idle-dependency line"
grep -qF '`idle: "<project>"`' "${cmds}/swarm.md" || got+=" swarm.md has no idle-project line"
grep -qF 'swarm.sh log-finding --filed --reviewer lead <kind> <PR>' "${cmds}/swarm.md" || got+=" swarm.md does not log a filed finding"
grep -qF 'set the story'"'"'s `status: ready` in the same edit' "${cmds}/swarm.md" || got+=" swarm.md does not ready a story whose dependency it drops"
grep -qF 'a `depends_on` story that shares no file in `touches` with it' "${cmds}/plan-epic.md" || got+=" plan-epic.md's critic has no disjoint-touches check"
}
if [[ -z "${got}" ]]; then echo "ok   swarm.md handles both idle: lines and plan-epic's critic checks disjoint touches"
else echo "FAIL${got}"; fails=$((fails + 1)); fi
expect "stories before planning" "conduct e2" \
  "item epics/e0.md 'status: draft'" \
  "item epics/e1.md 'status: active'" \
  "item epics/e2.md 'status: active'" \
  "item stories/a.md 'status: ready' 'epic: e2'"

# With a conductor in herdr: `wait` until it has written its report, then `collect`. A stub herdr
# lists the agent; being idle must not count as finished. A long epic's agent name is cut at 32
# characters, and its report is still found under the full epic name. The whole output is left in out.
expect_conductor() { # <name> <want> <write the report?> [epic] [glob next's why matches] [setup...]
  local name="$1" want="$2" epic="${4:-e1}" why="${5:-*}" dir got agent step
  dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
  [ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
  # An older brief whose epic shares the cut name, as a finished long epic leaves behind.
  (cd "${dir}" && git init -q && mkdir -p docs/stories bin .swarm/briefs && touch -t 202001010000 ".swarm/briefs/conduct-${epic}-old.md" && touch ".swarm/briefs/conduct-${epic}.md")
  agent="$(cd "${dir}" && bash "${SWARM}" _name "conduct-${epic}")"; want="${want//AGENT/${agent}}"
  mkdir -p "${dir}/.swarm/state"; echo "w:7 ${agent}" > "${dir}/.swarm/state/tab"   # its pane, as next_pane records it
  # Started in this project: in a pane it recorded (herdr lists every project's agents).
  # Its pane's text is the file screen, when a setup writes one.
  # shellcheck disable=SC2016 # the stub's own shell expands these
  printf '#!/bin/sh\n[ "$1 $2" = "agent read" ] && [ -f %s/screen ] && exec cat %s/screen\necho %s\n' "${dir}" "${dir}" \
    "'{\"result\":{\"agents\":[{\"name\":\"${agent}\",\"agent_status\":\"idle\",\"pane_id\":\"w:7\"}]}}'" > "${dir}/bin/herdr"
  chmod +x "${dir}/bin/herdr"
  [[ "$3" == yes ]] && echo report > "${dir}/.swarm/conduct-${epic}.report.md"
  for step in "${@:6}"; do (cd "${dir}" && eval "${step}"); done
  got="$(cd "${dir}" && HERDR_ENV=1 PATH="${dir}/bin:${PATH}" bash "${SWARM}" next)"; out="${got}"
  # next only reads: it never writes a pane record or logs a stop (pane_check is status's and wait's).
  if [[ -e "${dir}/.swarm/panes" ]] || grep -q $'\tincident\t' "${dir}/.swarm/events.tsv" 2>/dev/null; then got="next wrote a pane record or an incident: ${got}"; fi
  # shellcheck disable=SC2053 # the why is a glob
  [[ "$(sed -n 2p <<< "${got}")" == ${why} ]] || got="${got%%$'\n'*} (why: $(sed -n 2p <<< "${got}"))"
  got="${got%%$'\n'*}"
  if [[ "${got}" == "${want}" ]]; then echo "ok   ${name}"; else
    echo "FAIL ${name}: want '${want}', got '${got}'"; fails=$((fails + 1)); fi
  rm -rf "${dir}"
}
expect_conductor "idle conductor without a report is still waited on" "wait conduct-e1" no
expect_conductor "conductor with a report is collected" "collect conduct-e1" yes
# A conductor whose turn stopped on an API error (herdr idle, its pane ending on the error) is named a stall.
expect_conductor "a conductor stopped on an API error: next names the stop" "wait conduct-e1" no e1 "stuck: *API error*" \
  "printf '%s\n' '⏺ Waiting on the builders.' '⏺ API Error: Connection dropped (ECONNRESET)' > screen"
expect_conductor "a conductor whose pane has a later reply after an API error is still working" "wait conduct-e1" no e1 "*still working*" \
  "printf '%s\n' '⏺ API Error: Connection dropped (ECONNRESET)' '⏺ Carrying on.' > screen"
expect_conductor "a long epic's conductor is collected by its report" "collect AGENT" yes aws-layer3-claim-sweep-reap
# While a conductor works, an epic whose dependency is all in review is planned first; the why names
# the conductor to wait on in the background. With no such epic, next waits on the conductor.
expect_conductor "a plannable epic comes before a working conductor's wait" "plan-epic a" no e1 \
  "*conduct-e1*wait --until-report conduct-e1*" \
  "item epics/a.md 'status: active' 'depends_on: [e1]'" "item epics/e1.md 'status: active'" \
  "item stories/s1.md 'status: review' 'kind: code' 'epic: e1'"
expect_conductor "an unblocked later epic comes before a working conductor's wait" "plan-epic a" no e1 \
  "*later epic a*conduct-e1*wait --until-report conduct-e1*" \
  "item epics/a.md 'status: later' 'depends_on: [b]'" "item epics/e1.md 'status: active'" \
  "item stories/s1.md 'status: ready' 'kind: code' 'epic: e1'"
expect_conductor "a later epic planned unasked does not replace a working conductor's wait" "wait conduct-e1" no e1 "*" \
  "item epics/a.md 'status: later' 'depends_on: [b]'" "item epics/e1.md 'status: active'" \
  "item stories/s1.md 'status: ready' 'kind: code' 'epic: e1'" "bash \"\${SWARM}\" plan-unasked a >/dev/null"
expect_conductor "a working conductor's dependent epic with a blocked story left: wait" "wait conduct-e1" no e1 "*" \
  "item epics/a.md 'status: active' 'depends_on: [e1]'" "item epics/e1.md 'status: active'" \
  "item stories/s1.md 'status: review' 'kind: code' 'epic: e1'" \
  "item stories/s2.md 'status: blocked' 'kind: code' 'epic: e1'"
# A ready lead story that a blocked story depends on is named under the wait: the lead runs it
# meanwhile. One nothing blocked depends on is not, nor an escalated one (wait --lead hands it on),
# nor one with after: (it waits for its epic to finish), nor one that only a blocked lead story
# depends on, nor one in a later or draft epic or blocking only a story in one. A legacy kind no agent
# builds (operator) is lead work too.
expect_conductor "a working conductor's wait names a lead story that blocks one" "wait conduct-e1" no e1 "*" \
  "item stories/l.md 'status: ready' 'kind: lead'" "item stories/l2.md 'status: ready' 'kind: lead'" \
  "item stories/s.md 'status: blocked' 'kind: code' 'depends_on: [l]'" \
  "item stories/t.md 'status: blocked' 'kind: code' 'depends_on: [x, l]'" \
  "item stories/esc.md 'status: ready' 'kind: lead' 'escalated_from: code'" \
  "item stories/u.md 'status: blocked' 'kind: code' 'depends_on: [esc]'" \
  "item stories/aft.md 'status: ready' 'kind: lead' 'epic: e1' 'after: e1'" \
  "item stories/v.md 'status: blocked' 'kind: code' 'depends_on: [aft]'" \
  "item stories/ll.md 'status: ready' 'kind: lead'" "item stories/bl.md 'status: blocked' 'kind: lead' 'depends_on: [ll]'" \
  "item epics/el.md 'status: later'" "item epics/ed.md 'status: draft'" \
  "item stories/lat.md 'status: ready' 'kind: lead' 'epic: el'" "item stories/w.md 'status: blocked' 'kind: code' 'depends_on: [lat]'" \
  "item stories/l3.md 'status: ready' 'kind: lead'" "item stories/x2.md 'status: blocked' 'kind: code' 'epic: ed' 'depends_on: [l3]'" \
  "item stories/op.md 'status: ready' 'kind: operator'" "item stories/y.md 'status: blocked' 'kind: code' 'depends_on: [op]'"
if [[ "$(sed -n '3,$p' <<< "${out}")" == "also: lead l blocks s t"$'\n'"also: lead op blocks y" ]]; then echo "ok   the wait is followed by also: lead l blocks s t and also: lead op blocks y (kind: operator), and nothing for l2, the escalated esc, aft with after:, ll (only a lead story waits), lat or l3 (later and draft epics)"
else echo "FAIL the wait's also: lines: ${out}"; fails=$((fails + 1)); fi
expect_conductor "a working conductor's wait with no blocked dependant" "wait conduct-e1" no e1 "*" \
  "item stories/l.md 'status: ready' 'kind: lead'" \
  "item stories/s.md 'status: ready' 'kind: code' 'epic: e1' 'depends_on: [l]'"
if [[ "${out}" != *"also:"* ]]; then echo "ok   no also: line when no blocked story depends on the lead story"
else echo "FAIL an also: line with no blocked story depending on the lead story: ${out}"; fails=$((fails + 1)); fi

# release: a fixture repo whose origin/HEAD is main, plugin.json says 1.2.0 and the local tag v1.2.0
# is on origin/main; each setup runs after the tag, then the repo is pushed and fetched. herdr=1 runs
# next with a stub herdr listing a working conductor.
expect_release() { # <name> <want> <herdr: 0|1> <setup>...
  local name="$1" want="$2" herdr="$3" dir got step; shift 3
  dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
  (
    cd "${dir}" && git init -q && git init -q --bare origin.git && git remote add origin "${dir}/origin.git"
    printf 'origin.git\n' > .git/info/exclude
    mkdir -p docs/stories .claude-plugin bin && echo "# Stories" > docs/stories/README.md
    echo '{"name":"x","version":"1.2.0"}' > .claude-plugin/plugin.json
    git add -A && git -c user.name=t -c user.email=t@t commit -q -m init && git tag v1.2.0
    for step in "$@"; do eval "${step}"; done
    git push -q origin HEAD:main && git fetch -q origin && git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
    mkdir -p .swarm/briefs .swarm/state && touch .swarm/briefs/conduct-e1.md && echo "w:7 conduct-e1" > .swarm/state/tab
    printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"agents\":[{\"name\":\"conduct-e1\",\"agent_status\":\"working\",\"pane_id\":\"w:7\"}]}}'" > bin/herdr
    chmod +x bin/herdr
  )
  if [[ ${herdr} == 1 ]]; then got="$(cd "${dir}" && HERDR_ENV=1 PATH="${dir}/bin:${PATH}" bash "${SWARM}" next)"
  else got="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next)"; fi
  got="${got%%$'\n'*}"
  if [[ "${got}" == "${want}" ]]; then echo "ok   ${name}"; else
    echo "FAIL ${name}: want '${want}', got '${got}'"; fails=$((fails + 1)); fi
  rm -rf "${dir}"
}
COMMIT="git add -A && git -c user.name=t -c user.email=t@t commit -q -m change"
expect_release "a commit outside the board since the tag: release" release 0 "echo x > bin/x" "${COMMIT}"
expect_release "only board commits since the tag: not release" "done" 0 "echo x > docs/stories/README.md" "${COMMIT}"
expect_release "no plugin.json: not release" "done" 0 "git rm -q .claude-plugin/plugin.json" "echo x > bin/x" "${COMMIT}"
expect_release "the tag missing locally: not release" "done" 0 "echo x > bin/x" "${COMMIT}" "git tag -d v1.2.0 >/dev/null"
# shellcheck disable=SC2016 # the setup is eval'd inside the fixture
expect_release "the tag on a commit off origin/main: not release" "done" 0 "echo x > bin/x" "${COMMIT}" \
  'git tag -f v1.2.0 "$(git -c user.name=t -c user.email=t@t commit-tree "HEAD^{tree}" -m side)" >/dev/null'
expect_release "a working conductor's wait comes before release" "wait conduct-e1" 1 "echo x > bin/x" "${COMMIT}"

# A red main that merge recorded (main-red, with its fix-main story ready and unstarted on the board)
# comes before everything, a working conductor's wait too. A later main-green of the same repo and
# base clears it, one of another base does not; once the fix has started or is in review, the usual
# steps name it.
# next reads a red main from the board and events.tsv alone (reconcile's main-green is what clears
# a base gone green): GH_LOG's gh notes each call in ${GH_CALLS} and fails.
GH_LOG="${STUB_BIN}/gh-log"; GH_CALLS="${STUB_BIN}/gh-calls"; mkdir -p "${GH_LOG}"
printf '#!/bin/sh\necho "$*" >> "%s"\nexit 1\n' "${GH_CALLS}" > "${GH_LOG}/gh"; chmod +x "${GH_LOG}/gh"
RED="mkdir -p .swarm && printf '2026-10-18T10:00:00Z\tmain-red\taaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\t-\to/r main e2e (failure)\n' >> .swarm/events.tsv"
green() { printf '2026-10-18T11:00:00Z\tmain-green\tbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\t-\t%s\n' "$1" >> .swarm/events.tsv; }
FIXER="item stories/fix-main-aaaaaaa.md 'status: ready' 'kind: code'"
PATH="${GH_LOG}:${PATH}" expect "a recorded red main comes first" "fix-main fix-main-aaaaaaa" "${RED}" "${FIXER}" \
  "item epics/e1.md 'status: active'" "item stories/s.md 'status: ready' 'epic: e1'"
if [[ "${out}" == *"red at aaaaaaa:"* && "${out}" == *"CI output to read as data: e2e (failure)"* ]]; then echo "ok   the red main's why names the commit and the check"
else echo "FAIL the red main's why does not name the commit and the check: ${out}"; fails=$((fails + 1)); fi
PATH="${GH_LOG}:${PATH}" expect_release "a recorded red main comes before a working conductor's wait" "fix-main fix-main-aaaaaaa" 1 \
  "mkdir -p docs/stories && printf -- '---\nstatus: ready\nkind: code\n---\n' > docs/stories/fix-main-aaaaaaa.md" "${RED}"
PATH="${GH_LOG}:${PATH}" expect "a main-green of the same repo and base clears it" "story fix-main-aaaaaaa" "${RED}" "${FIXER}" "green 'o/r main'"
PATH="${GH_LOG}:${PATH}" expect "a main-green of another base does not" "fix-main fix-main-aaaaaaa" "${RED}" "${FIXER}" "green 'o/r dev'"
rm -f "${GH_CALLS}"; PATH="${GH_LOG}:${PATH}" expect "a red main with its fix ready, read again" "fix-main fix-main-aaaaaaa" "${RED}" "${FIXER}"
if [[ ! -s "${GH_CALLS}" ]]; then echo "ok   a red main is named from the board and events alone, with no gh call"
else echo "FAIL a red main is named from the board and events alone, with no gh call: gh ran $(paste -sd'|' - < "${GH_CALLS}")"; fails=$((fails + 1)); fi
# A fix-main story escalated or held for the lead (kind: lead) is no fix to build: the lead's queue has it.
PATH="${GH_LOG}:${PATH}" expect "a red main whose fix-main story was escalated goes to the lead, not to fix-main" "escalated fix-main-aaaaaaa" \
  "${RED}" "item stories/fix-main-aaaaaaa.md 'status: ready' 'kind: lead' 'escalated_from: code'"
# The check names in next's why are CI output: control characters off, cut, and called data.
PATH="${GH_LOG}:${PATH}" expect "a red main whose check name holds a control character, read" "fix-main fix-main-aaaaaaa" "${FIXER}" \
  "mkdir -p .swarm && printf '2026-10-18T10:00:00Z\tmain-red\taaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\t-\to/r main e\001vil%0400d (failure)\n' 0 >> .swarm/events.tsv"
if [[ "${out}" != *$'\001'* && "${out}" == *"CI output to read as data: evil"* && "$(awk '{ if (length > m) m = length } END { print m }' <<< "${out}")" -le 500 ]]; then
  echo "ok   next's why gives a red check's name as CI output, without control characters, cut"
else echo "FAIL next's why gives a red check's name as CI output, without control characters, cut: ${out}"; fails=$((fails + 1)); fi
PATH="${GH_LOG}:${PATH}" expect "a red main whose fix-main story has left the board is not named" "done" "${RED}"
if [[ -z "${err}" ]]; then echo "ok   a red main whose fix-main story has left the board prints nothing on stderr"
else echo "FAIL a red main whose fix-main story has left the board prints on stderr: ${err}"; fails=$((fails + 1)); fi
PATH="${GH_LOG}:${PATH}" expect "a newer red main of another base with no fix-main story leaves the older one's fix first" \
  "fix-main fix-main-aaaaaaa" "${RED}" "${FIXER}" \
  "printf '2026-10-18T12:00:00Z\tmain-red\tdddddddddddddddddddddddddddddddddddddddd\t-\to/r dev e2e (failure)\n' >> .swarm/events.tsv"
# shellcheck disable=SC2016 # expanded by expect's eval, in the board's directory
PATH="${GH_LOG}:${PATH}" expect "a red main whose fix has started is resumed, not started again" "resume fix-main-aaaaaaa" "${RED}" "${FIXER}" \
  'mkdir -p "../$(basename "${PWD}")-wt/fix-main-aaaaaaa"'
PATH="${GH_LOG}:${PATH}" expect "a red main whose fix is in review is not named" "gate" "${RED}" \
  "item stories/fix-main-aaaaaaa.md 'status: review' 'kind: code' 'prs: https://github.com/o/r/pull/9'"

# The stub lists this project's conductor (and its retired name) in panes the state records, as
# next_pane does: wait addresses an agent by this project's pane, never by a bare name. herdr says
# `done` for both and is never asked for a Claude conductor's state: that is its session's, recorded
# in agents.tsv (sess-c1) and read from the claude stub's fixture.
# shellcheck disable=SC2016 # the stub's $1/$2/$3 are its own arguments, written literally
stub() { # [api-error | api-stop] — the pane: an API error with a reply after it, or one it stopped on
  {
    echo '#!/bin/sh'
    echo 'case "$1 $2" in'
    echo "  \"agent prompt\") echo \"\$*\" >> '${dir}/prompts' ;;"
    echo 'esac'
    echo 'case "$1 $2" in'
    echo "  \"agent list\") echo '{\"result\":{\"agents\":[{\"name\":\"conduct-e1\",\"agent_status\":\"done\",\"pane_id\":\"w:1\"},{\"name\":\"conduct-e1-done\",\"agent_status\":\"done\",\"pane_id\":\"w:2\"}]}}' ;;"
    case "${1:-}" in
      api-error) printf '%s\n' "  \"agent read\") printf '%s\\n' '⏺ API Error: overloaded' '⏺ Carrying on.' ;;" ;;
      api-stop) printf '%s\n' "  \"agent read\") printf '%s\\n' '⏺ API Error: overloaded' ;;" ;;
    esac
    echo '  "agent wait"|"agent prompt") case "$3" in w:1|w:2) ;; *) echo "{\"error\":\"not this project'"'"'s pane: $3\"}"; exit 1 ;; esac ;;'
    echo 'esac'
    echo 'case "$1 $2" in "agent list"|"agent read") ;; *)'
    echo "  echo '{\"result\":{\"agent\":{\"agent_status\":\"done\"}}}' ;;"
    echo 'esac'
  } > "${dir}/bin/herdr"
  chmod +x "${dir}/bin/herdr"
}
session() { # <status> [waitingFor] — the conductor's session, as `claude agents --json` lists it
  echo "[{\"sessionId\":\"sess-c1\",\"status\":\"$1\"${2:+,\"waitingFor\":\"$2\"}}]" > "${dir}/claude.json"
}
waitc() { (cd "${dir}" && HERDR_ENV=1 CLAUDE_STUB_AGENTS="${dir}/claude.json" CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" bash "${SWARM}" wait "$@"); }
# `wait` on a conductor: idle without a report is not settled. It returns once the report lands.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p docs/stories bin .swarm/briefs .swarm/state && touch .swarm/briefs/conduct-e1.md && printf 'w:1 conduct-e1\nw:2 conduct-e1-done\n' > .swarm/state/e1)
printf '2026-10-13\tconduct\tconduct-e1\tclaude\topus\thigh\tsess-c1\n' > "${dir}/.swarm/agents.tsv"
stub; session idle
(sleep 2; echo report > "${dir}/.swarm/conduct-e1.report.md") &
got="$(SWARM_CONDUCTOR_POLL=1 waitc conduct-e1 20000)"
reported=no; [[ -f "${dir}/.swarm/conduct-e1.report.md" ]] && reported=yes
wait
if [[ "${got}" == idle && "${reported}" == yes ]]; then
  echo "ok   wait on a conductor whose session is idle holds until its report"; else
  echo "FAIL wait on a conductor whose session is idle holds until its report: got '${got}', report there on return: ${reported}"; fails=$((fails + 1)); fi
rm -f "${dir}/.swarm/conduct-e1.report.md"

# A conductor waiting on a prompt has settled: wait returns at once and says what it waits on.
session waiting "permission prompt"; start=${SECONDS}
got="$(SWARM_CONDUCTOR_POLL=5 waitc conduct-e1 20000)"
if [[ "${got}" == "waiting: permission prompt" && $((SECONDS - start)) -lt 5 ]]; then
  echo "ok   wait on a conductor waiting on a prompt returns at once, naming it"; else
  echo "FAIL wait on a conductor waiting on a prompt returns at once, naming it: got '${got}' after $((SECONDS - start))s"; fails=$((fails + 1)); fi

# A conductor whose session has no entry has exited: wait returns gone at once.
echo '[]' > "${dir}/claude.json"; start=${SECONDS}
got="$(SWARM_CONDUCTOR_POLL=5 waitc conduct-e1 20000)"
if [[ "${got}" == gone && $((SECONDS - start)) -lt 5 ]]; then
  echo "ok   wait on a conductor whose session is gone returns at once"; else
  echo "FAIL wait on a conductor whose session is gone returns at once: got '${got}' after $((SECONDS - start))s"; fails=$((fails + 1)); fi
session idle

# A conductor whose transcript ends on an expired login will not report until the user's /login:
# wait returns auth at once, naming it. The fixture is a real transcript's shape, ids replaced.
fixture="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/login-expired.jsonl"
mkdir -p "${dir}/projects/p"; cp "${fixture}" "${dir}/projects/p/sess-c1.jsonl"; start=${SECONDS}
got="$(SWARM_CONDUCTOR_POLL=5 waitc conduct-e1 20000 2>"${dir}/wait.err")"
if [[ "${got}" == auth && $((SECONDS - start)) -lt 5 ]] && grep -q "conduct-e1: its login expired" "${dir}/wait.err"; then
  echo "ok   wait on a conductor whose login expired returns auth at once, naming it"; else
  echo "FAIL wait on a conductor whose login expired returns auth at once, naming it: got '${got}' after $((SECONDS - start))s, stderr: $(cat "${dir}/wait.err")"; fails=$((fails + 1)); fi
# next says so too: its step stays `wait` (which returns auth at once), its why names auth and /login.
nextc() { (cd "${dir}" && HERDR_ENV=1 CLAUDE_STUB_AGENTS="${dir}/claude.json" CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" bash "${SWARM}" next); }
got="$(nextc)"
if [[ "${got}" == "wait conduct-e1"$'\n'"auth: the conductor conduct-e1 stopped on an expired login; run /login"* ]]; then
  echo "ok   next names auth and /login for a conductor whose login expired"; else
  echo "FAIL next names auth and /login for a conductor whose login expired: got '${got}'"; fails=$((fails + 1)); fi
# A busy session (background shells open) whose turn stopped on an API error, behind an expired login:
# auth too, as wait returns it, never "wait resumes it".
stub api-stop; session busy
got="$(nextc)"
if [[ "${got}" == "wait conduct-e1"$'\n'"auth: the conductor conduct-e1 stopped on an expired login; run /login"* ]]; then
  echo "ok   next names auth for a busy conductor stopped on an API error behind an expired login"; else
  echo "FAIL next names auth for a busy conductor stopped on an API error behind an expired login: got '${got}'"; fails=$((fails + 1)); fi
stub; session idle
# Only an idle session (or one stopped on an API error) is auth, as in wait: with the session gone there is nothing to resume.
echo '[]' > "${dir}/claude.json"
got="$(nextc)"
if [[ "${got}" == "wait conduct-e1"$'\n'"the conductor conduct-e1 is still working"* ]]; then
  echo "ok   next does not say auth for a conductor whose session is gone"; else
  echo "FAIL next does not say auth for a conductor whose session is gone: got '${got}'"; fails=$((fails + 1)); fi
session idle
# After an ordinary turn (the same transcript without the auth entry) it is waited on, as below.
grep -v authentication_failed "${fixture}" > "${dir}/projects/p/sess-c1.jsonl"
got="$(nextc)"
if [[ "${got}" == "wait conduct-e1"$'\n'"the conductor conduct-e1 is still working"* ]]; then
  echo "ok   next does not say auth once the conductor's last turn is an ordinary one"; else
  echo "FAIL next does not say auth once the conductor's last turn is an ordinary one: got '${got}'"; fails=$((fails + 1)); fi

# A conductor that never reports does not hang `wait`: the timeout bounds the whole wait.
start=${SECONDS}
got="$(waitc conduct-e1 2000)"
if [[ "${got}" == idle && $((SECONDS - start)) -le 10 ]]; then
  echo "ok   wait on a conductor that never reports ends at its timeout"; else
  echo "FAIL wait on a conductor that never reports ends at its timeout: got '${got}' after $((SECONDS - start))s"; fails=$((fails + 1)); fi

# A conductor has no story, so it is never nudged, even with an API error on its pane that a later
# reply followed (its last turn did not stop on it): idle with no report, wait polls on until the timeout.
stub api-error; rm -f "${dir}/prompts"
start=${SECONDS}
got="$(SWARM_CONDUCTOR_POLL=1 waitc conduct-e1 4000 2>/dev/null)"
if [[ "${got}" == idle && $((SECONDS - start)) -ge 4 && ! -e "${dir}/prompts" ]]; then
  echo "ok   an idle conductor with no report is not nudged, and wait returns at the timeout"; else
  echo "FAIL an idle conductor with no report is not nudged, and wait returns at the timeout: got '${got}' after $((SECONDS - start))s, prompts: $(cat "${dir}/prompts" 2>/dev/null)"; fails=$((fails + 1)); fi

# `wait --until-report` has no deadline: it holds past any timeout until the report lands, and
# returns at once on waiting or auth. The no-nudge checks are regression guards: wait never prompts a
# conductor for an earlier API error on its pane (the api-error stub above); only a last turn that
# stopped on one is resumed.
quiet() { [[ ! -e "${dir}/prompts" ]] && ! grep -qE 'nudge|resume' "${dir}/.swarm/events.tsv" 2>/dev/null; }
rm -f "${dir}/prompts" "${dir}/.swarm/events.tsv"; start=${SECONDS}
(sleep 4; echo report > "${dir}/.swarm/conduct-e1.report.md") &
got="$(SWARM_CONDUCTOR_POLL=1 waitc --until-report conduct-e1 2>/dev/null; echo "exit $?")"
reported=no; [[ -f "${dir}/.swarm/conduct-e1.report.md" ]] && reported=yes
wait
if [[ "${got}" == "idle"$'\n'"exit 0" && "${reported}" == yes && $((SECONDS - start)) -ge 4 ]] && quiet; then
  echo "ok   wait --until-report on an idle conductor holds until its report, and never nudges"; else
  echo "FAIL wait --until-report on an idle conductor holds until its report, and never nudges: got '${got}' after $((SECONDS - start))s, report: ${reported}, prompts: $(cat "${dir}/prompts" 2>/dev/null)"; fails=$((fails + 1)); fi
rm -f "${dir}/.swarm/conduct-e1.report.md"
# Busy across several 1 s slices: a slice that ends busy waits again, not returns.
session busy; start=${SECONDS}
(sleep 3; echo report > "${dir}/.swarm/conduct-e1.report.md"; session idle) &
got="$(SWARM_CONDUCTOR_SLICE_MS=1000 SWARM_CONDUCTOR_POLL=1 waitc --until-report conduct-e1 2>/dev/null; echo "exit $?")"
reported=no; [[ -f "${dir}/.swarm/conduct-e1.report.md" ]] && reported=yes
wait
if [[ "${got}" == "idle"$'\n'"exit 0" && "${reported}" == yes && $((SECONDS - start)) -ge 3 ]]; then
  echo "ok   wait --until-report on a busy conductor waits across slices until it reports"; else
  echo "FAIL wait --until-report on a busy conductor waits across slices until it reports: got '${got}' after $((SECONDS - start))s, report: ${reported}"; fails=$((fails + 1)); fi
rm -f "${dir}/.swarm/conduct-e1.report.md"
# A slice that runs out with the session unknown (claude agents --json failing) waits again too.
rm -f "${dir}/claude.json"; start=${SECONDS}
(sleep 3; echo report > "${dir}/.swarm/conduct-e1.report.md"; session idle) &
got="$(SWARM_CONDUCTOR_SLICE_MS=1000 SWARM_CONDUCTOR_POLL=1 waitc --until-report conduct-e1 2>/dev/null; echo "exit $?")"
reported=no; [[ -f "${dir}/.swarm/conduct-e1.report.md" ]] && reported=yes
wait
if [[ "${got}" == "idle"$'\n'"exit 0" && "${reported}" == yes && $((SECONDS - start)) -ge 3 ]]; then
  echo "ok   wait --until-report on a conductor of unknown state waits across slices until it reports"; else
  echo "FAIL wait --until-report on a conductor of unknown state waits across slices until it reports: got '${got}' after $((SECONDS - start))s, report: ${reported}"; fails=$((fails + 1)); fi
rm -f "${dir}/.swarm/conduct-e1.report.md"
# A herdr wait that fails other than by timing out is not a slice running out: it ends the wait.
mv "${dir}/bin/herdr" "${dir}/bin/herdr.real"
# shellcheck disable=SC2016 # the stub's $1/$2/$@ are its own arguments, written literally
printf '#!/bin/sh\n[ "$1 $2" = "agent wait" ] && { echo "{\\"error\\":\\"socket closed\\"}" >&2; exit 1; }\nexec "%s" "$@"\n' "${dir}/bin/herdr.real" > "${dir}/bin/herdr"
chmod +x "${dir}/bin/herdr"; session busy; start=${SECONDS}
got="$(cd "${dir}" && SWARM_CONDUCTOR_SLICE_MS=10000 HERDR_ENV=1 CLAUDE_STUB_AGENTS="${dir}/claude.json" CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" \
  perl -e 'alarm 30; exec @ARGV' bash "${SWARM}" wait --until-report conduct-e1 2>/dev/null; echo "exit $?")"   # a slice well above startup; alarm: a retry loop fails, not hangs
mv "${dir}/bin/herdr.real" "${dir}/bin/herdr"
if [[ "${got}" == "busy"$'\n'"exit 1" && $((SECONDS - start)) -lt 10 ]]; then
  echo "ok   wait --until-report on a busy conductor ends when herdr's wait fails"; else
  echo "FAIL wait --until-report on a busy conductor ends when herdr's wait fails: got '${got}' after $((SECONDS - start))s"; fails=$((fails + 1)); fi
session waiting "permission prompt"
got="$(SWARM_CONDUCTOR_POLL=1 waitc --until-report conduct-e1 2>/dev/null || true)"
if [[ "${got}" == "waiting: permission prompt" ]] && quiet; then
  echo "ok   wait --until-report on a conductor waiting on a prompt returns it, and never nudges"; else
  echo "FAIL wait --until-report on a conductor waiting on a prompt returns it, and never nudges: got '${got}'"; fails=$((fails + 1)); fi
session idle; cp "${fixture}" "${dir}/projects/p/sess-c1.jsonl"
got="$(SWARM_CONDUCTOR_POLL=1 waitc --until-report conduct-e1 2>/dev/null || true)"
if [[ "${got}" == auth ]] && quiet; then
  echo "ok   wait --until-report on a conductor whose login expired returns auth, and never nudges"; else
  echo "FAIL wait --until-report on a conductor whose login expired returns auth, and never nudges: got '${got}'"; fails=$((fails + 1)); fi
grep -v authentication_failed "${fixture}" > "${dir}/projects/p/sess-c1.jsonl"
got="$(waitc --until-report s1 2>&1; echo "exit $?")"
if [[ "${got}" == *"only on a conductor (conduct-<epic>)"* && "${got}" == *"exit 1" ]]; then
  echo "ok   wait --until-report on a builder fails naming conductors"; else
  echo "FAIL wait --until-report on a builder fails naming conductors: got '${got}'"; fails=$((fails + 1)); fi
# /swarm's wait step runs the deadline-free wait, so an epic over an hour is not cut short.
# shellcheck disable=SC2016 # the backticks are literal Markdown
step="$(sed -n '/^   - `wait <agent>`:/,/^     If any `wait` here/p' "$(dirname "${SWARM}")/../commands/swarm.md")"
if [[ "${step}" == *"swarm.sh wait --until-report <agent>"* && "${step}" != *"an hour"* ]]; then
  echo "ok   commands/swarm.md's wait step runs wait --until-report, with no hour"; else
  echo "FAIL commands/swarm.md's wait step runs wait --until-report, with no hour: got '${step}'"; fails=$((fails + 1)); fi
flat="$(tr -s ' \n' '  ' <<< "${step}")"   # wrapping-proof
if [[ "${flat}" == *"also: lead"* && "${flat}" == *"while the wait runs"* ]]; then
  echo "ok   commands/swarm.md's wait step runs each also: lead story while the wait runs"; else
  echo "FAIL commands/swarm.md's wait step does not run the also: lead stories"; fails=$((fails + 1)); fi

# A conductor of the same name started by another project is refused, never waited on.
printf 'w:9 other\n' > "${dir}/.swarm/state/e1"; stub
got="$(waitc conduct-e1 3000 2>&1; echo "exit $?")"
if [[ "${got}" == *"no agent this project started"* && "${got}" == *"exit 1" ]]; then
  echo "ok   wait refuses another project's conductor of the same name"; else
  echo "FAIL wait refuses another project's conductor of the same name: got '${got}'"; fails=$((fails + 1)); fi
printf 'w:1 conduct-e1\nw:2 conduct-e1-done\n' > "${dir}/.swarm/state/e1"

# A retired conductor (renamed <name>-done) is not waited on for a report. agents.tsv has no line
# for that name, so herdr answers for it.
start=${SECONDS}
got="$(SWARM_CONDUCTOR_POLL=5 waitc conduct-e1-done 20000)"
if [[ "${got}" == "done" && $((SECONDS - start)) -lt 5 ]]; then
  echo "ok   wait on a retired conductor returns at once"; else
  echo "FAIL wait on a retired conductor returns at once: got '${got}' after $((SECONDS - start))s"; fails=$((fails + 1)); fi
rm -rf "${dir}"

# A retired conductor (renamed <name>-done) is finished: next must not wait on it.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p docs/stories bin)
printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"agents\":[{\"name\":\"conduct-e1-done\",\"agent_status\":\"idle\"}]}}'" > "${dir}/bin/herdr"
chmod +x "${dir}/bin/herdr"
got="$(cd "${dir}" && HERDR_ENV=1 PATH="${dir}/bin:${PATH}" bash "${SWARM}" next)"; got="${got%%$'\n'*}"
if [[ "${got}" == "done" ]]; then echo "ok   a retired conductor is not waited on"; else
  echo "FAIL a retired conductor is not waited on: want 'done', got '${got}'"; fails=$((fails + 1)); fi
rm -rf "${dir}"

# Another project's conductor runs in a pane this project never opened: next must not wait on it,
# even when this project once had a conductor of the same name in a pane of its own.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p docs/stories bin .swarm/state && echo "w:1 conduct-x" > .swarm/state/tab)
printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"agents\":[{\"name\":\"conduct-x\",\"agent_status\":\"working\",\"pane_id\":\"w:9\"}]}}'" > "${dir}/bin/herdr"
chmod +x "${dir}/bin/herdr"
got="$(cd "${dir}" && HERDR_ENV=1 PATH="${dir}/bin:${PATH}" bash "${SWARM}" next)"; got="${got%%$'\n'*}"
if [[ "${got}" == "done" ]]; then echo "ok   another project's conductor is not waited on"; else
  echo "FAIL another project's conductor is not waited on: want 'done', got '${got}'"; fails=$((fails + 1)); fi
rm -rf "${dir}"

# `tell <slug> <kind> <file>` sends an idle builder the file and exits 0, leaving no temp file behind.
# A Claude builder's state is its session's (agents.tsv's newest line for s1, then the claude stub's
# fixture), never herdr's: it refuses one busy, waiting (naming on what), gone or unknown instead of
# typing into it. The stub's `agent list` reports s1 as $TELL_STATUS in pane $TELL_PANE; `agent
# prompt` appends what it was sent to ${dir}/sent as one record ending in a `--` line, and reports
# the agent working. With $TELL_GOAL set (a goal test), a prompt that is not a /goal makes sess-s1
# busy, as its turn starts, or $TELL_AFTER: idle (herdr said working, the session has not started)
# or waiting (on a permission prompt); a /goal's record also holds `state: <sess-s1's status>`
# as the stub saw it, and the stub appends to sess-s1's log a goal_status set entry for it, written
# now (new), an hour ago (old), or none, showing the goal on the pane instead (pane).
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p docs/stories bin .swarm/state projects/p && printf 'w:1 s1\nw:2 conduct-e\n' > .swarm/state/t)
cat > "${dir}/bin/herdr" <<EOF
#!/bin/sh
case "\$1 \$2" in
  "agent list") echo "{\"result\":{\"agents\":[{\"name\":\"s1\",\"agent_status\":\"\${TELL_STATUS}\",\"pane_id\":\"\${TELL_PANE:-w:1}\"},{\"name\":\"conduct-e\",\"agent_status\":\"working\",\"pane_id\":\"w:2\"}]}}" ;;
  "agent prompt") st=\$(sed -n 's/.*"sess-s1","status":"\([a-z]*\)".*/\1/p' "${dir}/claude.json")
    case "\$4" in
      "/goal "*) printf '%s\nstate: %s\n--\n' "\$4" "\$st" >> "${dir}/sent"
        [ "\${TELL_GOAL}" = pane ] && printf 'Goal set: %s\n' "\${4#/goal }" > "${dir}/screen"
        if [ "\${TELL_GOAL}" = new ] || [ "\${TELL_GOAL}" = old ]; then
          python3 -c 'import datetime, json, sys
t = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=sys.argv[1] == "old")
print(json.dumps({"type": "attachment", "timestamp": t.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
                  "attachment": {"type": "goal_status", "met": False, "sentinel": True, "condition": sys.argv[2]}}))' \
            "\${TELL_GOAL}" "\${4#/goal }" >> "${dir}/projects/p/sess-s1.jsonl"
        fi ;;
      *) printf '%s\n--\n' "\$4" >> "${dir}/sent"
        after="\${TELL_AFTER:-busy}\""; [ "\${TELL_AFTER}" = waiting ] && after='waiting","waitingFor":"permission prompt"'
        [ -z "\${TELL_GOAL}" ] || sed -i.bak "s/\"sess-s1\",\"status\":\"[a-z]*\"/\"sess-s1\",\"status\":\"\$after/" "${dir}/claude.json" ;;
    esac
    echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent read") cat "${dir}/screen" 2>/dev/null ;;
esac
EOF
chmod +x "${dir}/bin/herdr"
printf -- '- a finding\n' > "${dir}/findings.md"
mkdir -p "${dir}/tmp"
tsv() { printf '2026-10-13\tcode\ts1\t%s\topus\thigh\t%s\n' "$1" "$2" >> "${dir}/.swarm/agents.tsv"; }
tsession() { # <status> [waitingFor] — sess-s1's entry; `none` lists no entry for it
  if [[ "$1" == none ]]; then echo '[]'; else echo "[{\"sessionId\":\"sess-s1\",\"status\":\"$1\"${2:+,\"waitingFor\":\"$2\"}},{\"sessionId\":\"sess-old\",\"status\":\"${OLD:-idle}\"}]"; fi > "${dir}/claude.json"
}
# tellout <herdr status> <tell args...> — run tell; print its output, then "exit N".
tellout() {
  local st="$1"; shift; rm -f "${dir}/sent"
  (cd "${dir}" && HERDR_ENV=1 TMPDIR="${dir}/tmp" TELL_STATUS="${st}" TELL_GOAL="${TELL_GOAL:-}" TELL_AFTER="${TELL_AFTER:-}" CLAUDE_STUB_AGENTS="${CLAUDE_STUB_AGENTS:-${dir}/claude.json}" \
    CLAUDE_PROJECTS_DIR="${dir}/projects" SWARM_PROMPT_TIMEOUT_MS="${PTO:-2000}" PATH="${dir}/bin:${PATH}" bash "${SWARM}" tell s1 "$@" 2>&1; echo "exit $?")
}
refused() { # <name> <want in the message> <herdr status> <tell args...>
  local name="$1" want="$2" out; shift 2
  out="$(tellout "$@")"
  if [[ "${out}" == *"${want}"* && "${out}" == *"exit 1" && ! -f "${dir}/sent" ]]; then echo "ok   ${name}"; else
    echo "FAIL ${name}: got '${out}', sent: $(cat "${dir}/sent" 2>/dev/null)"; fails=$((fails + 1)); fi
}
told() { # <name> <herdr status> <tell args...>
  local name="$1" out sent left; shift
  out="$(tellout "$@")"; sent="$(cat "${dir}/sent" 2>/dev/null || true)"; left="$(ls "${dir}/tmp")"
  if [[ "${out}" == *"exit 0" && "${sent}" == "From the conductor:"* && "${sent}" == *"- a finding"* && -z "${left}" ]]; then echo "ok   ${name}"; else
    echo "FAIL ${name}: got '${out}', sent '${sent}', left '${left}'"; fails=$((fails + 1)); fi
}
tsv claude sess-s1
tsession idle; told "tell sends an idle session the findings while herdr says working, and leaves no temp file" working findings findings.md
tsession busy; refused "tell refuses a busy session while herdr says done: still working" "still working" "done" findings findings.md
tsession waiting "permission prompt"; refused "tell refuses a waiting session, naming what it waits for" "waiting on permission prompt" idle findings findings.md
tsession none; refused "tell refuses a session that is gone" "gone" idle findings findings.md
tsession compacting; refused "tell refuses a session in a state it does not know (unknown)" "(unknown)" idle findings findings.md
tsession idle
CLAUDE_STUB_AGENTS="${dir}/no-such-file" refused "tell refuses when Claude Code cannot list its sessions (unknown)" "(unknown)" idle findings findings.md
for k in nudge resume; do told "tell takes the kind ${k}" idle "${k}" findings.md; done
# goal = N: once the findings are taken up, a findings tell sends a fresh /goal mid-turn (sess-s1 busy)
# and finds it set in sess-s1's log after the tell began; a nudge or resume tell, or goal off, sends one record.
# The events log holds one ok tell:findings line, and when the goal step fails, its failure after it.
records() { grep -c '^--$' "${dir}/sent" 2>/dev/null || true; }
# reply — reply_sentence's text, or a line no goal holds when it is not found (an empty want matches any goal).
reply() {
  local f; f="$(awk '/^reply_sentence\(\)/,/^}$/' "${SWARM}" "$(dirname "${SWARM}")"/lib/*.sh)"
  [[ -n "${f}" ]] || { echo "no reply_sentence() in bin/swarm.sh or bin/lib/*.sh"; return; }
  (eval "${f}"; reply_sentence)
}
goalcase() { # <name> <0: told with a goal, 1: refused naming s1> <want in the /goal or the refusal> <tell args...>
  # A refusal leaves $NREC records (2: the /goal was sent) and says the findings must not be sent again.
  local name="$1" rc="$2" want="$3" out goal ev; shift 3
  : > "${dir}/projects/p/sess-s1.jsonl"; rm -f "${dir}/screen" "${dir}/.swarm/events.tsv"; tsession idle
  # WORKED: an assistant entry dated after the tell. A findings /goal goes only mid-turn, so an idle
  # session with work since is no sign it may go.
  [[ -z "${WORKED:-}" ]] || python3 -c 'import datetime, json
t = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=5)
print(json.dumps({"type": "assistant", "timestamp": t.isoformat(timespec="milliseconds").replace("+00:00", "Z"), "message": {"model": "m", "content": []}}))' > "${dir}/projects/p/sess-s1.jsonl"
  out="$(tellout idle "$@")"; ev="$(cut -f2,3,5 "${dir}/.swarm/events.tsv" | tr '\t\n' ' |')"; goal="$(sed -n '/^\/goal /,/^--$/p' "${dir}/sent" 2>/dev/null)"
  if [[ ${rc} == 0 && "${out}" == *"exit 0" && "$(records)" == 2 && "$(head -1 "${dir}/sent")" == "From the conductor:" \
        && "${goal}" == *"the conductor's review findings, sent to you just before this goal, are addressed (each fixed, or declined with a reason in your reply) and you have replied"*"${want}"*"or stop after 4 more turns"* && "${goal}" == *"state: busy"* \
        && -z "$(ls "${dir}/tmp")" && "${ev}" == "tell:findings s1 ok|" ]] \
     || [[ ${rc} == 1 && "${out}" == *"s1: ${want}"*"do not send them again"*"exit 1" && "$(records)" == "${NREC:-2}" \
           && "${ev}" == "tell:findings s1 ok|tell:findings s1 s1: ${want}"* ]]; then echo "ok   ${name}"; else
    echo "FAIL ${name}: got '${out}', events '${ev}', sent '$(cat "${dir}/sent" 2>/dev/null)'"; fails=$((fails + 1)); fi
}
onerecord() { # <name> <tell args...> — the tell sends one record, no goal
  local name="$1"; shift
  tsession idle; : "$(TELL_GOAL=new tellout idle "$@")"   # in $(), so a failing tell does not trip set -e
  if [[ "$(records)" == 1 ]]; then echo "ok   ${name}"; else
    echo "FAIL ${name}: sent '$(cat "${dir}/sent" 2>/dev/null)'"; fails=$((fails + 1)); fi
}
mkdir -p "${dir}/.claude/swarm"; echo "goal = 4" > "${dir}/.claude/swarm/config"
TELL_GOAL=new goalcase "goal on: a findings tell sends the findings, then mid-turn a /goal with the story reply, and finds it set" 0 "$(reply)" findings findings.md
TELL_GOAL=old goalcase "goal on: only a set entry older than the tell fails the tell, naming s1" 1 "the findings were delivered, but its session log shows no goal set" findings findings.md
TELL_GOAL=pane goalcase "goal on: a goal on the pane with no new entry fails the tell, naming s1" 1 "the findings were delivered, but its session log shows no goal set" findings findings.md
# The /goal goes only into a turn that has started, never into a dialog: nothing is typed otherwise.
t0=${SECONDS}
TELL_GOAL=new TELL_AFTER=waiting NREC=1 PTO=10000 goalcase "goal on: a session waiting on a prompt once the findings are taken up gets no /goal; the tell fails naming s1 and the prompt" \
  1 "the findings were delivered, but its builder is waiting on permission prompt, so no /goal was sent" findings findings.md
if (( SECONDS - t0 < 5 )); then echo "ok   goal on: a waiting session fails the tell at once, not at the timeout"; else
  echo "FAIL goal on: a waiting session fails the tell at once, not at the timeout: took $((SECONDS - t0))s"; fails=$((fails + 1)); fi
TELL_GOAL=new TELL_AFTER=idle NREC=1 goalcase "goal on: a session still idle while herdr says working gets no /goal; the tell fails naming s1" \
  1 "the findings were delivered, but its session did not read busy" findings findings.md
TELL_GOAL=new TELL_AFTER=idle NREC=1 WORKED=1 goalcase "goal on: a session idle after the findings, with work since the tell, gets no /goal; the tell fails naming s1" \
  1 "the findings were delivered, but its session did not read busy" findings findings.md
for k in nudge resume; do onerecord "goal on: a ${k} tell sends no goal" "${k}" findings.md; done
# A second findings tell right after one that set its goal: the same condition's entry from the
# first tell is older than the second tell, so with no new entry the second fails.
tsession idle; first="$(TELL_GOAL=new tellout idle findings findings.md)"; tsession idle
out="$(TELL_GOAL=pane tellout idle findings findings.md)"
if [[ "${first}" == *"exit 0" && "${out}" == *"s1: the findings were delivered, but its session log shows no goal set"*"exit 1" ]]; then echo "ok   goal on: a repeated findings tell does not count the previous tell's goal"; else
  echo "FAIL goal on: a repeated findings tell does not count the previous tell's goal: got '${out}'"; fails=$((fails + 1)); fi
rm -rf "${dir}/.claude" "${dir}/docs/stories/s1.md"
onerecord "goal off: a findings tell sends no goal" findings findings.md
refused "tell with no kind fails, listing the three" "findings, nudge or resume, not ''" idle
refused "the old form, tell <slug> <file>, fails on its kind" "findings, nudge or resume, not 'findings.md'" idle findings.md
refused "tell with an unknown kind fails, listing the three" "findings, nudge or resume, not 'review'" idle review findings.md
refused "tell with a kind and no file fails" "no such file ''" idle findings
TELL_PANE=w:77 refused "tell refuses another project's agent of the same name" "not one this project started" idle findings findings.md
# A reused name: the older line's session (sess-old) is retired; the newer line's (sess-s1) decides.
: > "${dir}/.swarm/agents.tsv"; tsv claude sess-old; tsv claude sess-s1
OLD=busy tsession idle; told "a reused name reads the newer line (older busy, newer idle): told" working findings findings.md
OLD=idle tsession busy; refused "a reused name reads the newer line (older idle, newer busy): refused" "still working" idle findings findings.md
# No session recorded ('-', as a codex agent has): herdr answers for it.
tsv codex -; tsession busy
told "tell sends an agent with no session that herdr reports as idle" idle findings findings.md
told "tell also sends one herdr reports as done" "done" findings findings.md
refused "tell refuses one herdr reports as working" "still working" working findings findings.md
refused "tell refuses one herdr reports as blocked on a prompt" "waiting on a prompt" blocked findings findings.md
# herdr giving no status (agent_field reads it as unknown): refused as unknown, never as another project's.
refused "tell refuses its own agent with no session and no herdr status as unknown" "herdr gives no state for it (unknown)" "" findings findings.md
# `tell conduct-e note <file>` appends the file to the conductor's inbox while its session is busy,
# sends no prompt, and logs tell:note; a second note appends after the first. A note to a builder,
# or to a conductor this project never started, is refused and writes no inbox.
inbox="${dir}/.swarm/inbox/conduct-e.md"
printf '2026-10-13\tconduct\tconduct-e\tclaude\topus\thigh\tsess-c\n' >> "${dir}/.swarm/agents.tsv"
echo '[{"sessionId":"sess-c","status":"busy"}]' > "${dir}/claude.json"
noteout() { rm -f "${dir}/sent"; (cd "${dir}" && HERDR_ENV=1 TMPDIR="${dir}/tmp" CLAUDE_STUB_AGENTS="${dir}/claude.json" PATH="${dir}/bin:${PATH}" bash "${SWARM}" tell "$@" 2>&1; echo "exit $?"); }
printf 'first note\n' > "${dir}/n1.md"; printf 'second note\n' > "${dir}/n2.md"
out="$(noteout conduct-e note n1.md)"
if [[ "${out}" == *"noted conduct-e"*"exit 0" && "$(cat "${inbox}" 2>/dev/null)" == *"first note"* && ! -f "${dir}/sent" \
      && "$(tail -1 "${dir}/.swarm/events.tsv" | cut -f2,3,5)" == $'tell:note\tconduct-e\tok' ]]; then echo "ok   tell note leaves a busy conductor the file in its inbox, prompts nothing, and logs tell:note ok"; else
  echo "FAIL tell note leaves a busy conductor the file in its inbox: got '${out}', inbox '$(cat "${inbox}" 2>/dev/null)', sent '$(cat "${dir}/sent" 2>/dev/null)', events '$(tail -1 "${dir}/.swarm/events.tsv")'"; fails=$((fails + 1)); fi
out="$(noteout conduct-e note n2.md)"
if [[ "${out}" == *"exit 0" && "$(grep -v '^From the lead' "${inbox}" | grep .)" == $'first note\nsecond note' ]]; then echo "ok   a second note appends after the first"; else
  echo "FAIL a second note appends after the first: got '${out}', inbox '$(cat "${inbox}")'"; fails=$((fails + 1)); fi
rm -f "${inbox}"
for who in s1 conduct-zz; do
  out="$(noteout "${who}" note n1.md)"
  want="a note goes only to a conductor"; [[ ${who} == s1 ]] || want="could not reach conduct-zz"
  if [[ "${out}" == *"${want}"*"exit 1" && ! -e "${inbox%/*}/${who}.md" \
        && "$(tail -1 "${dir}/.swarm/events.tsv" | cut -f2,3,5)" != *ok ]]; then echo "ok   tell note refuses ${who}, writes no inbox and logs no ok"; else
    echo "FAIL tell note refuses ${who}: got '${out}', inbox '$(ls "${inbox%/*}" 2>/dev/null)'"; fails=$((fails + 1)); fi
done
out="$(noteout conduct-e bogus n1.md)"
if [[ "${out}" == *"findings, nudge or resume, not 'bogus' (or note, to a conductor)"*"exit 1" ]]; then echo "ok   an unknown kind's refusal lists note with findings, nudge and resume"; else
  echo "FAIL an unknown kind's refusal lists note with findings, nudge and resume: got '${out}'"; fails=$((fails + 1)); fi
rm -rf "${dir}"

# conduct on a later epic sets it active in its state file, never the epic file, says so, and status
# stops listing it as waiting on you; an active epic is left as it is, silently. An epic whose state
# cannot be written stays later, conduct says so and still succeeds. herdr is a stub whose one answer
# has every field conduct reads.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p bin && item stories/s.md 'status: ready' 'kind: code' 'epic: e')
# shellcheck disable=SC2016 # the stub's own $1
printf '#!/bin/sh\n[ "$1" != --version ] || { echo "herdr 0.9.5"; exit 0; }\necho %s\n' "'{\"result\":{\"workspaces\":[{\"workspace_id\":\"w\",\"label\":\"e\"}],\"root_pane\":{\"pane_id\":\"w:1\"},\"agent\":{\"agent_status\":\"working\"},\"agents\":[],\"panes\":[]}}'" > "${dir}/bin/herdr"
chmod +x "${dir}/bin/herdr"
conduct() { (cd "${dir}" && HERDR_ENV=1 CLAUDE_CONFIG_DIR="${dir}/cc" PATH="${dir}/bin:${PATH}" bash "${SWARM}" conduct e 2>&1); }
es="${dir}/.swarm/board-state/epics"
for st in later active; do
  (cd "${dir}" && item epics/e.md "status: ${st}"); rm -rf "${es}"
  # Its tab records go, so the next conduct starts afresh; its state stays.
  out="$(conduct)"; find "${dir}/.swarm/state" -maxdepth 1 -type f -exec rm -f {} +
  said=no; grep -q '^epic e: status later -> active (in .swarm/board-state)$' <<< "${out}" && said=yes
  # The whole output, then grep: grep -q can close the pipe on status, which fails under pipefail.
  waits=no; grep -q 'later epic: e' <<< "$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" status)" && waits=yes
  got="$(sed -n 's/^status: //p' "${es}/e" 2>/dev/null)|$(sed -n 's/^status: //p' "${dir}/docs/epics/e.md")|${said}|${waits}"
  want="|active|no|no"; [[ ${st} == later ]] && want="active|later|yes|no"
  if [[ "${got}" == "${want}" ]]; then echo "ok   conduct on a ${st} epic leaves it active (active|said|waits on you: ${got})"; else
    echo "FAIL conduct on a ${st} epic: want '${want}', got '${got}': ${out}"; fails=$((fails + 1)); fi
done
(cd "${dir}" && item epics/e.md "status: later"); rm -rf "${es}"; mkdir -p "${es}"; chmod a-w "${es}"
out="$(conduct; echo "exit $?")"; chmod u+w "${es}"
got="$(sed -n 's/^status: //p' "${dir}/docs/epics/e.md")|$(ls "${es}")"; rm -rf "${dir}/.swarm/state"
if [[ "${got}" == "later|" && "${out}" == *"epic e: could not write its state in "*"/.swarm/board-state/epics, so it is still later"*"exit 0" ]]; then
  echo "ok   conduct on a later epic it cannot write leaves it later, says so, and exits 0"; else
  echo "FAIL conduct on a later epic it cannot write: got '${got}': ${out}"; fails=$((fails + 1)); fi
# The same when only the state file's mv fails (a wrapper on PATH): conduct tests set_fm in an if,
# where set -e is off, so set_fm must fail by itself.
printf '#!/bin/sh\ncase "$*" in *board-state*) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v mv)" > "${dir}/bin/mv"; chmod +x "${dir}/bin/mv"
(cd "${dir}" && item epics/e.md "status: later"); rm -rf "${es}"
out="$(conduct; echo "exit $?")"; rm -f "${dir}/bin/mv"
waits=no; grep -q 'later epic: e' <<< "$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" status)" && waits=yes
got="${waits}|$(ls "${es}" 2>/dev/null)"
if [[ "${got}" == "yes|" && "${out}" == *"epic e: could not write its state in "*", so it is still later"*"exit 0" ]]; then
  echo "ok   conduct whose state mv fails leaves the epic later, says so, and exits 0"; else
  echo "FAIL conduct whose state mv fails: got '${got}': ${out}"; fails=$((fails + 1)); fi
# The same when the epic's lock is held: set_fm dies after SWARM_LOCK_WAIT, and conduct says why.
rm -rf "${dir}/.swarm/state"; (cd "${dir}" && item epics/e.md "status: later"); rm -rf "${es}"; mkdir -p "${es}/e.lock"
out="$(SWARM_LOCK_WAIT=1 conduct; echo "exit $?")"
waits=no; grep -q 'later epic: e' <<< "$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" status)" && waits=yes
if [[ "${waits}" == yes && "${out}" == *"epic e: could not write its state in "*", so it is still later; set status: active by hand (board state: "*"/e.lock is still there after 1s"*"exit 0" ]]; then
  echo "ok   conduct whose epic lock is held leaves the epic later, says why, and exits 0"; else
  echo "FAIL conduct whose epic lock is held: waits on you '${waits}': ${out}"; fails=$((fails + 1)); fi
rm -rf "${dir}"

# next with an epic's conductor working and a ready story with no epic starts the backlog's conductor
# (conduct, against a herdr stub that logs each call and lists the agents it started), and still waits
# on the epic's. While the backlog report is newer than every story and epic, it starts none and says why.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p bin .swarm/state && item epics/e1.md 'status: active' \
  && item stories/s1.md 'status: review' 'kind: code' 'epic: e1' && item stories/b1.md 'status: ready' 'kind: code')
echo "w:7 conduct-e1" > "${dir}/.swarm/state/tab"; echo "conduct-e1 w:7" > "${dir}/agents"
printf '#!/bin/sh\nA="%s"\n' "${dir}/agents" > "${dir}/bin/herdr"
cat >> "${dir}/bin/herdr" <<'STUB'
echo "$*" >> "$A.log"
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;
  "workspace list") echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  "tab create") echo '{"result":{"root_pane":{"pane_id":"w:8"}}}' ;;
  "agent start") echo "$3 w:8" >> "$A" ;;
  "agent prompt") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent wait") echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent list") awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                     { printf "%s{\"name\":\"%s\",\"agent_status\":\"%s\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, ($3 == "" ? "working" : $3), $2 }
                     END { print "]}}" }' "$A" ;;
  "agent read") cat "$A.screen.$3" 2>/dev/null ;;
esac
STUB
chmod +x "${dir}/bin/herdr"
nextb() { : > "${dir}/agents.log"; (cd "${dir}" && HERDR_ENV=1 CLAUDE_CONFIG_DIR="${dir}/cc" PATH="${dir}/bin:${PATH}" bash "${SWARM}" next 2>/dev/null); }
# collected <conductor>: the lead collected its report (collect ends with swarm.sh close, logged ok).
collected() { printf '%s\tclose\t%s\t-\tok\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "${dir}/.swarm/events.tsv"; }
echo report > "${dir}/.swarm/conduct-backlog.report.md"; touch -t 202001010000 "${dir}"/docs/stories/* "${dir}"/docs/epics/* "${dir}/docs/stories" "${dir}/docs/epics"
collected "$(cd "${dir}" && bash "${SWARM}" _conductor backlog)"
out="$(nextb)"
if [[ "${out%%$'\n'*}" == "wait conduct-e1" && "${out}" == *"no backlog conductor started: no story or epic changed after"* ]] \
    && ! grep -q '^agent start' "${dir}/agents.log"; then
  echo "ok   next with the backlog report newer than the board starts no backlog conductor, says why, and waits"; else
  echo "FAIL next with the backlog report newer than the board: '${out}', herdr: $(grep '^agent start' "${dir}/agents.log")"; fails=$((fails + 1)); fi
# A state write for s1, epic e1's story, as state_set makes it (its file, a lock made and removed
# beside it): no change to the backlog's stories, so the stop holds.
mkdir -p "${dir}/.swarm/board-state/stories"; echo "status: review" > "${dir}/.swarm/board-state/stories/s1"
mkdir "${dir}/.swarm/board-state/stories/s1.lock"; rmdir "${dir}/.swarm/board-state/stories/s1.lock"
out="$(nextb)"
if [[ "${out}" == *"no backlog conductor started: no story or epic changed after"* ]] && ! grep -q '^agent start' "${dir}/agents.log"; then
  echo "ok   next after another epic's state write keeps the backlog's stop"; else
  echo "FAIL next after another epic's state write: '${out}', herdr: $(grep '^agent start' "${dir}/agents.log")"; fails=$((fails + 1)); fi
rm "${dir}/.swarm/conduct-backlog.report.md"
out="$(nextb)"
if [[ "${out%%$'\n'*}" == "wait conduct-e1" && "${out}" == *"started: conduct-backlog-"*"(swarm.sh conduct --backlog)"* ]] \
    && grep -q '^agent start conduct-backlog-' "${dir}/agents.log"; then
  echo "ok   next with an epic conductor working and a ready story with no epic starts the backlog conductor and still waits"; else
  echo "FAIL next with a ready story with no epic and no backlog conductor: '${out}', herdr: $(grep '^agent start' "${dir}/agents.log")"; fails=$((fails + 1)); fi
out="$(nextb)"
if [[ "${out%%$'\n'*}" == "wait conduct-e1" && "${out}" != *"conduct --backlog"* ]] && ! grep -q '^agent start' "${dir}/agents.log"; then
  echo "ok   next with the backlog conductor running starts no second one"; else
  echo "FAIL next with the backlog conductor running: '${out}', herdr: $(grep '^agent start' "${dir}/agents.log")"; fails=$((fails + 1)); fi
# A report that lists b1 under not started: while b1's worktree is still there (its build died) stops
# a new backlog conductor even once the board has changed.
echo "conduct-e1 w:7" > "${dir}/agents"; mkdir -p "${dir}-wt/b1"
echo "not started: b1 (build died)" > "${dir}/.swarm/conduct-backlog.report.md"; touch -t 202001010000 "${dir}/.swarm/conduct-backlog.report.md"; touch "${dir}/docs/stories/b1.md"
out="$(nextb)"
if [[ "${out%%$'\n'*}" == "wait conduct-e1" && "${out}" == *"no backlog conductor started: "*" lists b1 under not started: and its worktree is still there"* ]] \
    && ! grep -q '^agent start' "${dir}/agents.log"; then
  echo "ok   next with a died build of b1 in the backlog report starts no backlog conductor and says why"; else
  echo "FAIL next with a died build of b1 in the backlog report: '${out}', herdr: $(grep '^agent start' "${dir}/agents.log")"; fails=$((fails + 1)); fi
# conduct-e1 works, but conduct-e3, also this project's, stopped on an API error: a backlog conductor
# started now would stop on it too.
rm -rf "${dir}-wt" "${dir}/.swarm/conduct-backlog.report.md"; echo "w:9 conduct-e3" >> "${dir}/.swarm/state/tab"
printf 'conduct-e1 w:7\nconduct-e3 w:9 idle\n' > "${dir}/agents"
printf '%s\n' '⏺ API Error: Connection dropped (ECONNRESET)' > "${dir}/agents.screen.w:9"
out="$(nextb)"
if [[ "${out%%$'\n'*}" == "wait conduct-e1" && "${out}" == *"no conductor started: conduct-e3 stopped on an API error"* ]] \
    && ! grep -q '^agent start' "${dir}/agents.log"; then
  echo "ok   next while another conductor is stopped on an API error starts no conductor"; else
  echo "FAIL next while another conductor is stopped on an API error: '${out}', herdr: $(grep '^agent start' "${dir}/agents.log")"; fails=$((fails + 1)); fi
# Epic e2's conductor has reported and gone, and no story or epic changed since: a new one would stop
# as it did. The backlog's starts (its earlier tab forgotten: the stub opens only new tabs).
rm "${dir}/agents.screen.w:9" "${dir}"/.swarm/state/conduct-backlog-*; echo "conduct-e1 w:7" > "${dir}/agents"
(cd "${dir}" && item epics/e2.md 'status: active' && item stories/s2.md 'status: ready' 'kind: code' 'epic: e2' \
  && item stories/s6.md 'status: blocked' 'kind: code' 'epic: e2' 'depends_on: [gone]')
touch -t 202001010000 "${dir}"/docs/stories/* "${dir}"/docs/epics/* "${dir}/docs/stories" "${dir}/docs/epics"; echo report > "${dir}/.swarm/conduct-e2.report.md"
# Nobody collected it, and its pane is gone: no conductor starts over it; the lead reads it first.
out="$(nextb)"
if [[ "${out}" == *"no conductor started: conduct-e2 is gone, and nobody collected "*"/.swarm/conduct-e2.report.md; read it, then delete it"* ]] \
    && ! grep -q '^agent start conduct-e2 ' "${dir}/agents.log"; then
  echo "ok   next with an uncollected report and no pane starts no conductor over it, and names the report"; else
  echo "FAIL next with an uncollected report and no pane: '${out}', herdr: $(grep '^agent start' "${dir}/agents.log")"; fails=$((fails + 1)); fi
rm "${dir}"/.swarm/state/conduct-backlog-*; echo "conduct-e1 w:7" > "${dir}/agents"; collected conduct-e2
out="$(nextb)"
if [[ "${out}" == *"no conductor for epic e2 started: no story or epic changed after"* && "${out}" == *"started: conduct-backlog-"* ]] \
    && ! grep -q '^agent start conduct-e2 ' "${dir}/agents.log"; then
  echo "ok   next with an epic's report newer than the board starts no conductor for it, and says why"; else
  echo "FAIL next with an epic's report newer than the board: '${out}', herdr: $(grep '^agent start' "${dir}/agents.log")"; fails=$((fails + 1)); fi
# unblock readies s6 (its dependency is gone) in .swarm/board-state, not in its file: a board change
# after the report all the same, so next starts e2's conductor. The report is put back for below.
(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" unblock >/dev/null 2>&1)
out="$(nextb)"
if [[ "${out}" != *"no conductor for epic e2 started"* ]] && grep -q '^agent start conduct-e2 ' "${dir}/agents.log"; then
  echo "ok   next after unblock readies a story of an epic whose report is older starts its conductor"; else
  echo "FAIL next after unblock readies a story of an epic whose report is older: '${out}', herdr: $(grep '^agent start' "${dir}/agents.log")"; fails=$((fails + 1)); fi
echo report > "${dir}/.swarm/conduct-e2.report.md"
# conduct-e2 is still in its pane and has written its report, which the lead has not collected: no
# conductor starts over it, though s2 changed since. conduct-e5's name is held by another project's
# agent (a pane this project never opened). e4's start fails (its parent: is not a slug); the
# backlog's, in the same run, still prints its started: line above the warnings.
(cd "${dir}" && item epics/e4.md 'status: active' 'parent: Not_A_Slug' && item stories/s4.md 'status: ready' 'kind: code' 'epic: e4' \
  && item epics/e5.md 'status: active' && item stories/s5.md 'status: ready' 'kind: code' 'epic: e5')
rm "${dir}"/.swarm/state/conduct-backlog-*; printf 'conduct-e1 w:7\nconduct-e2 w:10 working\nconduct-e5 w:99\n' > "${dir}/agents"
echo "w:10 conduct-e2" >> "${dir}/.swarm/state/tab"; touch "${dir}/docs/stories/s2.md"; rm -f "${dir}/.swarm/events.tsv"
out="$(nextb)"
if [[ "${out}" == *"no conductor started: conduct-e2 has reported; collect it first"* ]] && ! grep -q '^agent start conduct-e2 ' "${dir}/agents.log" \
    && [[ -f "${dir}/.swarm/conduct-e2.report.md" ]]; then
  echo "ok   next with a reported conductor in its pane starts none over its report, and says to collect it"; else
  echo "FAIL next with a reported conductor in its pane: '${out}', herdr: $(grep '^agent start' "${dir}/agents.log")"; fails=$((fails + 1)); fi
if [[ "${out}" == *"no conductor started: another project's agent holds the name conduct-e5"* ]] && ! grep -q '^agent start conduct-e5 ' "${dir}/agents.log"; then
  echo "ok   next with a conductor's name held by another project's agent starts none, and says so"; else
  echo "FAIL next with a conductor's name held by another project's agent: '${out}', herdr: $(grep '^agent start' "${dir}/agents.log")"; fails=$((fails + 1)); fi
if [[ "${out}" == *"started: conduct-backlog-"*"warning: swarm.sh conduct e4 failed"*"warning: starting conductors for ready work failed"* ]]; then
  echo "ok   next with one start failing keeps the started: lines of the others"; else
  echo "FAIL next with one start failing: '${out}'"; fails=$((fails + 1)); fi
# Each start is logged as a dispatched swarm.sh conduct logs it: ok, or its die line.
ev="$(awk -F'\t' '$2 == "conduct" { print $3 " " $5 }' "${dir}/.swarm/events.tsv" 2>/dev/null)"
if grep -qx -- "--backlog ok" <<< "${ev}" && grep -qx "e4 e4: bad parent 'Not_A_Slug'" <<< "${ev}"; then
  echo "ok   next logs each conductor start, ok or its die line, in events.tsv"; else
  echo "FAIL next's conductor starts in events.tsv: '${ev}'"; fails=$((fails + 1)); fi
# Run as an agent (a conductor, with its allowlisted env), a failed start is the lead's to retry.
out="$(cd "${dir}" && SWARM_AGENT=conduct-e1 HERDR_ENV=1 CLAUDE_CONFIG_DIR="${dir}/cc" PATH="${dir}/bin:${PATH}" bash "${SWARM}" next 2>/dev/null)"
if [[ "${out}" == *"warning: swarm.sh conduct e4 failed ("*"); the lead's swarm.sh next starts it"* && "${out}" != *"run it yourself"* ]]; then
  echo "ok   next run by an agent leaves a failed start to the lead's next"; else
  echo "FAIL next run by an agent, one start failing: '${out}'"; fails=$((fails + 1)); fi
rm -rf "${dir}" "${dir}-wt"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
