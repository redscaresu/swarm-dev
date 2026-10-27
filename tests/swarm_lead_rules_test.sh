#!/usr/bin/env bash
# swarm_lead_rules_test.sh — commands/swarm.md keeps the lead's three rules from the v0.28.0 retro:
# plan independent epics at the same time, restart an agent at its first API-error stop, and judge
# an agent alive from events.tsv, its PR and the stall check, not a pane read. Each check fails when its rule is removed.
# shellcheck disable=SC2016  # the backticks in the patterns are literal text in the doc
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

iso="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${iso}"' EXIT
export CLAUDE_CONFIG_DIR="${iso}/claude-config"   # under its own root, so parallel runs share no ~/.claude

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="${REPO}/commands/swarm.md"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# has <doc> <regex> — yes when the doc, its lines joined, matches the regex.
has() {
  if tr '\n' ' ' < "$1" | tr -s ' ' | grep -Eq "$2"; then echo yes; else echo no; fi
}

check "plan independent epics at the same time, each in its own pane" yes \
  "$(has "${DOC}" 'Plan epics whose plans do not depend on each other at the same time, not one after another.*run `/plan-epic <epic>` for each independent epic at once, each in its own pane')"
check "cross-epic order goes in depends_on through board-pr" yes \
  "$(has "${DOC}" 'put that order in a story.s `depends_on` once the other epic.s plan exists.*`swarm.sh board-pr`')"
check "restart at the first API-error stop, naming the route" yes \
  "$(has "${DOC}" 'Restart an agent at its first .Request timed out. or API-error stop that its own retries did not clear.*`swarm.sh restart <slug>`.*tells the agent to write its output as it goes')"
check "the stuck: api error arm follows the restart rule" yes \
  "$(has "${DOC}" 'prints .stuck: api error. .exit 4.*restart the agent as the first rule at the end of this file says')"
check "alive from events.tsv, status and the stall wait, never a pane read alone" yes \
  "$(has "${DOC}" 'whether an agent is alive from .\.swarm/events\.tsv.*`swarm.sh status` or `swarm.sh wait --stall <slug>`, never from a pane read alone')"

if (( fails > 0 )); then echo "${fails} failed"; exit 1; fi
echo "all passed"
