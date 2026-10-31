#!/usr/bin/env bash
# user-caught-reminder.sh — the plugin's UserPromptSubmit hook for the lead (hooks/hooks.json). The
# lead is told to log `swarm.sh intervene user-caught` the moment the user finds a problem the swarm
# missed (commands/swarm.md), but a rule it must remember gets skipped: on 2026-10-25 the user caught
# three and none was logged until they asked. So each prompt in the lead's session gets one line of
# context saying so. The lead is found as lead-stop.sh finds it (lead-session.sh's lead_project);
# anywhere else it prints nothing. It never blocks the prompt: it always exits 0, and a hook input
# it cannot read falls back to the hook's own cwd.
set -uo pipefail

input="$(cat)"
# shellcheck source=hooks/lead-session.sh
. "$(dirname "$0")/lead-session.sh" || exit 0
cwd="$(printf '%s' "${input}" | python3 -I -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    d = None
c = d.get("cwd") if isinstance(d, dict) else None
print(c if isinstance(c, str) and "\n" not in c else "")' 2>/dev/null)" || cwd=""
lead_project "${cwd:-${PWD}}" > /dev/null || exit 0
echo 'If this message points out a problem the swarm or the lead missed, log it first: swarm.sh intervene user-caught <cause> "<what they found>". The cause is one word from the list in /swarm-dev:swarm; an unknown one fails and lists them.'
exit 0
