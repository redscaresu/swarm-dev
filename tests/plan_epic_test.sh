#!/usr/bin/env bash
# plan_epic_test.sh — pins the plan-epic rules with a grep each. Run on another copy with
# `bash tests/plan_epic_test.sh <plan-epic.md> <reference.md> <epic.md>`.
# shellcheck disable=SC2016 # the patterns hold literal backticks
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
F="${1:-$ROOT/commands/plan-epic.md}"
M="${2:-$ROOT/docs/reference.md}"
EPIC="${3:-$ROOT/commands/epic.md}"
fails=0

has() { # <name> <pattern> [text]
  local text="${3-$(cat "$F")}"
  if grep -qE -- "$2" <<< "$text"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}
hasnt() { # <name> <pattern> [text]
  local text="${3-$(cat "$F")}"
  if grep -qE -- "$2" <<< "$text"; then echo "FAIL $1"; fails=$((fails + 1)); else echo "ok   $1"; fi
}

step3=$(awk '/^\*\*3\. /{on=1} /^\*\*4\. |^\*\*Then report/{on=0} on' "$F")
step2=$(awk '/^\*\*2\. /{on=1} /^\*\*3\. /{on=0} on' "$F" | tr '\n' ' ' | tr -s ' ')
approval=$(printf '%s' "$(tr '\n' ' ' < "$F" | tr -s ' ')" | grep -oE 'On approval write one.*open a PR with' || true)
# The file with line breaks folded to spaces, so a phrase wrapped over two lines still matches.
flat=$(tr '\n' ' ' < "$F" | tr -s ' ')
risk=$(printf '%s' "$flat" | grep -oE 'risk: high` only[^;]*;' || true)

has small-epic 'at most 3 stories with no `risk: high` is planned by the lead alone' "$flat"
has small-epic-codex 'one `swarm.sh codex-review` pass over them' "$flat"
has chain-depth 'at most 3 stories deep' "$flat"
has depends-on-names 'what it needs from each `depends_on`: the file or the function' "$flat"
has report-chain 'longest chain'
step0=$(awk '/^\*\*0\. /{on=1} /^\*\*1\. /{on=0} on' "$F" | tr '\n' ' ' | tr -s ' ')
has large-epic-arm 'A large epic, one that is not small and either has more than 8 stories.* becomes child epics instead of stories' "$step0"
has child-epic-shape '`docs/epics/<child>\.md` per goal, with front matter `status: active`, `parent: \$1`.* its own \*\*Done when\*\*' "$step0"
has child-not-on-parent 'plus any sibling it builds on, never the parent itself' "$step0"
has parent-split 'Set the parent.s `status: split`: nothing plans a split epic, and it counts as done once none of its children is left' "$step0"
has critic-in-step-3 'role `critic`' "$step3"
has risk-clause 'real-cloud, teardown, credentials and safety' "$risk"
if [ -n "$risk" ]; then hasnt risk-hygiene 'hygiene' "$risk"; else echo "FAIL risk-hygiene"; fails=$((fails + 1)); fi
has one-survey 'one agent \(lands, constraints and overlaps together\) unless the epic.s text names another repo' "$flat"
has survey-name 'named `survey`' "$flat"
has small-worktree 'board-pr start scope-.*commit them there' "$flat"
has small-open 'board-pr open scope-.*board-pr done scope-' "$flat"
has skeptic-chain 'depends_on` chain through it more than 3 stories deep' "$flat"
has declined-reasons '`out-of-scope`, `nit` or `wrong`' "$flat"
has folded 'folded into'
has log-skeptic 'log-finding --reviewer skeptic[|]codex[|]critic <kind> <board PR URL>' "$flat"
has log-declined 'log-finding --declined <reason>'
has cap-step-2 'capped at one new command or one changed behaviour and about 300 lines' "$step2"
has cap-step-3 'over the cap of one new command or one changed behaviour and about 300 lines' "$(printf '%s' "$step3" | tr '\n' ' ' | tr -s ' ')"
has output-shape 'depends_on, estimate_lines, easy\}\]' "$flat"
has front-matter 'front matter .*`estimate_lines`, `easy`' "$approval"
has report-estimate 'with `kind`, `estimate_lines`, `touches`' "$flat"
has readme-keys 'estimate_lines.*easy: true' "$(tr '\n' ' ' < "$ROOT/templates/docs/stories/README.md")"
hasnt no-blocked-by 'blocked_by'
hasnt no-verify 'verify'
hasnt no-version-bump 'needs no version bump'

m=$(awk '/^## Scoping an epic/{on=1;next} /^## /{on=0} on' "$M")
if [ -z "$m" ]; then echo "FAIL method-section"; fails=$((fails + 1)); fi
hasnt method-three-surveys 'three surveys' "$m"
hasnt method-then-critic 'then a critic' "$m"

# /epic writes a draft epic on the board with its four sections, and only the user's agreement makes it active.
e=$(cat "$EPIC")
eflat=$(tr '\n' ' ' <<< "$e" | tr -s ' ')
has epic-path 'docs/epics/<slug>\.md' "$e"
has epic-draft '^ *status: draft$' "$e"
for h in Problem Goals Non-goals Constraints; do has "epic-section-$h" "^ *## $h$" "$e"; done
has epic-active-on-agreement '[Oo]nly then, on the user.s agreement, set `status: active`; nothing plans a draft epic' "$eflat"
has epic-resume-draft-only 'is `status: draft`, resume it\. If it exists with any other status, it is live .* stop' "$eflat"
has epic-slug-chars 'every run of characters other than `a-z` and `0-9` into one `-`' "$eflat"
has epic-slug-backlog 'If the slug is empty or `backlog`.* stop' "$eflat"
has epic-file-name-first 'If `docs/epics/<argument>.md` exists, that file is the epic and its name is the slug' "$eflat"
has epic-resume-clears 'remove any old `D/ready` and `D/agreed`, on a resume too' "$eflat"
has epic-resume-stale-review 'on a resume, move it to `D/review-stale.md`' "$eflat"
has epic-agreed-watched-from-step-3 'watch for `D/agreed` from step 3 on, whatever has or has not happened in this step' "$eflat"
has epic-close-by-name '`swarm.sh close epic-<slug>`, then `swarm.sh close epic-review-<slug>`' "$eflat"
hasnt epic-no-tab-close 'swarm\.sh close epic`' "${eflat//'never `swarm.sh close epic`'/}"

[ "$fails" -eq 0 ]
