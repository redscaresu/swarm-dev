#!/usr/bin/env bash
# plan_epic_test.sh — pins the plan-epic rules with a grep each. Run on another copy with
# `bash tests/plan_epic_test.sh <plan-epic.md> <reference.md>`.
# shellcheck disable=SC2016 # the patterns hold literal backticks
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
F="${1:-$ROOT/commands/plan-epic.md}"
M="${2:-$ROOT/docs/reference.md}"
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

[ "$fails" -eq 0 ]
