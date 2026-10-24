#!/usr/bin/env bash
# plan_hld_test.sh — pins /plan-hld's rules (commands/plan-hld.md) with a grep each, the way
# hld_command_test.sh pins /hld's: the swarm (three surveys, one hld-lead, skeptics capped at five,
# codex, critic) in tab plan-$1 writing to .swarm/$1/, the epics grant read before the ask, epics
# carrying hld: $1, the HLD's planned: and ## Epics in one board PR, and the cleanup after its merge.
# It also pins commands/swarm.md's plan-hld and hld steps, and that the HLD skeleton holds no planned:.
# Run on other copies with `bash tests/plan_hld_test.sh <plan-hld.md> <swarm.md> <hld README.md>`.
# shellcheck disable=SC2016 # the patterns hold literal backticks
set -euo pipefail

iso="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${iso}"' EXIT
export CLAUDE_CONFIG_DIR="${iso}/claude-config"   # under its own root, so parallel runs share no ~/.claude

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
F="${1:-$ROOT/commands/plan-hld.md}"
S="${2:-$ROOT/commands/swarm.md}"
T="${3:-$ROOT/templates/docs/hld/README.md}"
fails=0
# Each file with line breaks folded to spaces, so a wrapped phrase still matches.
flat=$(tr '\n' ' ' < "$F" | tr -s ' ')
swarm=$(tr '\n' ' ' < "$S" | tr -s ' ')
# The template's first fenced block: the skeleton /hld step 1 copies into every new HLD.
skeleton=$(awk '/^```/ { n++; next } n == 1' "$T")

has() { # <name> <pattern> [text]
  if grep -qE -- "$2" <<< "${3-$flat}"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}
hasnt() { # <name> <pattern> [text]
  if grep -qE -- "$2" <<< "${3-$flat}"; then echo "FAIL $1"; fails=$((fails + 1)); else echo "ok   $1"; fi
}

has description '^--- description: Use when asked to plan an agreed HLD into epics\.'
has agreed-only 'It must be `status: agreed`; if not, say so and stop'
has planned-refused 'If its front matter has a `planned:` line, it has been planned already: say so and stop'
has three-surveys 'role `survey`, three in parallel'
has one-hld-lead 'one `hld-lead`, role `hld-lead`'
has skeptic-cap 'role `skeptic` \(capped at five'
has codex 'one `codex`, role `codex`'
has critic 'one `critic`, role `critic`'
has agent-tab 'swarm\.sh agent plan-\$1 <name> "\$PWD" <role>'
has output-dir '`\.swarm/\$1/<name>\.json`'
# The grants are read before the ask: the grants line comes before the "ask before" line.
has grants-before-ask 'Before the ask, run `swarm\.sh grants \$1`.*ask before `board-pr open`'
has active-under-epics 'lists `epics`, the HLD lets you write the epics `status: active`'
has draft-otherwise 'Without it, write each epic `status: draft`'
has hld-on-epic 'front matter `status:` as above, `hld: \$1`'
has planned 'give the HLD `planned: <today>` in its front matter'
has epics-link 'a link to each epic under its `## Epics`'
has board-pr-start 'swarm\.sh board-pr start plan-\$1'
has board-pr-open 'swarm\.sh board-pr open plan-\$1'
has codex-review 'one `swarm\.sh codex-review` pass'
has log-finding 'swarm\.sh log-finding --reviewer skeptic\|codex\|critic'
has board-pr-done 'swarm\.sh board-pr done plan-\$1'
has done-on-close 'Once it has merged, or been closed unmerged, run `swarm\.sh board-pr done plan-\$1`'
has close 'swarm\.sh close plan-\$1'
has stop-when-open 'If the board PR `plan-\$1` is already open .* report its URL and stop'
has resume-worktree 'exists with no open PR, an earlier run stopped there: write in that worktree below instead of running `board-pr start`'

has swarm-plan-hld-step '- `plan-hld <hld>`: follow `/plan-hld <hld>`' "$swarm"
has swarm-hld-step '- `hld <hld>`: .{0,120}`swarm\.sh finish <hld>`' "$swarm"
has swarm-finish-done 'swarm\.sh board-pr done finish-<hld>' "$swarm"

hasnt skeleton-no-planned '^planned:' "$skeleton"
has skeleton-found '^status: draft \| agreed \| superseded$' "$skeleton"

[ "$fails" -eq 0 ]
