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

check "plan independent epics at the same time, the next once a plan waits for approval" yes \
  "$(has "${DOC}" 'Plan epics whose plans do not depend on each other at the same time, not one after another.*once a plan.s agents have finished and it waits for the user.s approval, start the next independent epic.s `/plan-epic <epic>`')"
check "never two plans' agents at once, since they share names and briefs" yes \
  "$(has "${DOC}" 'Never run two plans. agents at once: they share agent names and brief files')"
check "the plan-epic arm starts the next independent plan before it stops" yes \
  "$(has "${DOC}" 'approve the stories, that is the user.s decision: wait for it. Before you stop, start the next independent epic.s plan, as the planning rule under "Three more rules for the lead" says')"
check "a conductor is restarted by its agent name, the backlog's included" yes \
  "$(has "${DOC}" '`swarm.sh close <conductor>`, then the same `swarm.sh conduct <epic>` or `swarm.sh conduct --backlog` that started it.*`<conductor>` is its agent name as `next` or `status` prints it: `conduct-<epic>`, or `conduct-backlog-<dir>-<hash>`')"
check "a stuck planner is closed before its command runs again" yes \
  "$(has "${DOC}" 'A planner or co-author: `swarm.sh close <agent>`, since its name stays taken.*then run its command again')"
check "a restarted conductor gets its unread notes back" yes \
  "$(has "${DOC}" 'copy whichever of `\.swarm/inbox/<conductor>\.reading\.md` and `\.swarm/inbox/<conductor>\.md` exist into one file aside, since a new conductor deletes both.*If you saved any notes, send the copy again with `swarm.sh tell <conductor> note <copy>`')"
check "with goal on, a builder is held, not restarted" yes \
  "$(has "${DOC}" 'With `goal` on, a builder is never restarted: its conductor closes it `cleared-on-error`, which holds the story for you')"
check "only epics next would offer are planned early" yes \
  "$(has "${DOC}" 'for an `active` epic whose `depends_on` are done .a `later` one only after `swarm.sh plan-unasked <epic>`, as the `plan-epic` arm says., never a `draft` one')"
check "a restarted planner gets the line in its brief" yes \
  "$(has "${DOC}" 'A planner or co-author gets the line in the brief you write for its rerun, before it starts')"
check "each agent's stall signs are named" yes \
  "$(has "${DOC}" 'a story.s builder shows life through worktree commits, edits and PR updates, an agent with no story .a planner or conductor. through its own `events.tsv` lines, and any agent through its session log and a test suite running in its pane')"
check "cross-epic order goes in depends_on through board-pr" yes \
  "$(has "${DOC}" 'put that order in a story.s `depends_on` once the other epic.s plan exists.*`swarm.sh board-pr`')"
check "restart at the first API-error stop, naming each route" yes \
  "$(has "${DOC}" 'Restart an agent at its first .Request timed out. or API-error stop that its own retries did not clear.*`swarm.sh restart <slug>`.*`swarm.sh review-agent <slug> <PR URL>`.*`swarm.sh conduct --backlog`')"
check "the restart is followed by a tell, since restart and conduct take no brief" yes \
  "$(has "${DOC}" 'take no brief.*to write its output as it goes.*A builder comes back working, so run `swarm.sh wait --stall <slug> && swarm.sh tell <slug> nudge <file>` in the background: the tell goes once its turn ends.*`swarm.sh tell <conductor> note <file>` goes in busy or not')"
check "the stuck: api error arm follows the restart rule by name" yes \
  "$(has "${DOC}" 'prints .stuck: api error. .exit 4.*restart the agent as the restart rule under "Three more rules for the lead" says')"
check "a conductor is closed only when the restart rule says so" yes \
  "$(has "${DOC}" 'Never close a conductor that has not reported, unless the restart rule under "Three more rules for the lead" says to')"
check "alive from events.tsv, its PR, status and dash, never a pane read alone" yes \
  "$(has "${DOC}" 'whether an agent is alive from .\.swarm/events\.tsv., its PR where it has one, and `swarm.sh status` or `swarm.sh dash`, never from a pane read alone')"
check "only dash shows the age; status shows the state" yes \
  "$(has "${DOC}" '`dash` shows `working <N>m` or `stalled <N>m`, `status` shows the agent.s state, and neither acts on anything')"
check "wait --stall is not a liveness check" yes \
  "$(has "${DOC}" 'Do not use `swarm.sh wait --stall` as a check')"

if (( fails > 0 )); then echo "${fails} failed"; exit 1; fi
echo "all passed"
