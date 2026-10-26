#!/usr/bin/env bash
# hld_command_test.sh — pins /hld's rules (commands/hld.md) with a grep each, the way plan_epic_test.sh
# pins /epic's: the dated file, the _hld tab, grants asked of the user and attacked by the reviewer,
# status: agreed only once D/agreed exists, and both agents closed by name. Run on another copy with
# `bash tests/hld_command_test.sh <hld.md>`.
# shellcheck disable=SC2016 # the patterns hold literal backticks
set -euo pipefail
unset SWARM_PROJECT   # from a pane it names the real project, whose .swarm logs a direct run of this test would write (live_logs_test.sh)

iso="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${iso}"' EXIT
export CLAUDE_CONFIG_DIR="${iso}/claude-config"   # under its own root, so parallel runs share no ~/.claude

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
F="${1:-$ROOT/commands/hld.md}"
fails=0
# The file with line breaks and the brief's "> " quote marks folded to spaces, so a wrapped phrase still matches.
flat=$(sed 's/^ *> *//' "$F" | tr '\n' ' ' | tr -s ' ')

has() { # <name> <pattern>
  if grep -qE -- "$2" <<< "$flat"; then echo "ok   $1"; else echo "FAIL $1"; fails=$((fails + 1)); fi
}
hasnt() { # <name> <pattern> [text]
  if grep -qE -- "$2" <<< "${3-$flat}"; then echo "FAIL $1"; fails=$((fails + 1)); else echo "ok   $1"; fi
}

has description '^--- description: Use when asked to write, start or resume an HLD or a design\.'
has argument-hint 'argument-hint: "'
has dated-file '`<file>` is `YYYY-MM-DD-<slug>`, dated today: create `docs/hld/<file>\.md` from the skeleton'
has fills-title-date 'fill in `title:` and `date:`'
has exact-slug 'without its leading `YYYY-MM-DD-`, is exactly that slug'
has resume-by-file-name 'with its file name without `\.md` as the argument, never its `title:`'
has argument-not-readme 'exists and is not the README'
has bare-headings 'write the ten section headings bare \(`## Problem`'
has no-slash 'If the argument contains `/`, stop'
has slug-from-file 'by name or by title, `<file>` is its name without `\.md` and `<slug>` is `<file>` without its leading `YYYY-MM-DD-`'
has reviewer-path 'attack the draft in `docs/hld/<file>\.md`'
has d-dir '`D` below is `\.swarm/hld-<slug>`'
has resume-draft-grep "grep -l '\^status: draft\\$' docs/hld/\\*\\.md\`, never the README"
has several-ask 'Several: list them with their titles and ask which'
has hld-tab 'swarm\.sh agent _hld hld-<slug> "\$PWD" hld \.swarm/briefs/hld-<slug>\.md` \(the tab `_hld`'
has review-tab 'swarm\.sh agent _hld hld-review-<slug> "\$PWD" hld-review <brief>'
has grants-asked 'Ask the user which `grants:` the HLD carries .* never fill `grants:` in by yourself'
has grants-attacked 'its `grants:` as a risk'
has agreed-only-on-file 'Once `D/agreed` exists, and only then, on the user.s agreement, set `status: agreed`'
has resume-clears 'remove any old `D/ready` and `D/agreed`, on a resume too'
has agreed-watched-from-step-3 'watch for `D/agreed` from step 3 on'
has close-by-name '`swarm\.sh close hld-<slug>`, then `swarm\.sh close hld-review-<slug>`'
has codex-pass 'board PR for the HLD with one `swarm\.sh codex-review` pass'
hasnt no-tab-close 'swarm\.sh close hld`' "${flat//'never `swarm.sh close hld`'/}"
hasnt no-active 'status: active'

[ "$fails" -eq 0 ]
