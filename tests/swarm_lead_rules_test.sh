#!/usr/bin/env bash
# swarm_lead_rules_test.sh — commands/swarm.md keeps the lead's three rules from the v0.28.0 retro:
# plan independent epics at the same time, restart an agent at its first API-error stop, and judge
# an agent alive from events.tsv and its PR, not a pane read. Each check fails when its rule is removed.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

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

# shellcheck disable=SC2016  # the backticks are literal text in the doc
check "plan independent epics at the same time" yes \
  "$(has "${DOC}" 'Plan epics whose plans do not depend on each other at the same time, not one after another.*`depends_on` once the other epic.s plan exists')"
check "restart at the first API-error stop" yes \
  "$(has "${DOC}" 'Restart an agent at its first .Request timed out. or API-error stop that its own retries did not clear.*writes? its output as it goes')"
check "alive from events.tsv and its PR" yes \
  "$(has "${DOC}" 'whether an agent is alive from .\.swarm/events\.tsv. and its PR, never from a pane read alone')"

if (( fails > 0 )); then echo "${fails} failed"; exit 1; fi
echo "all passed"
