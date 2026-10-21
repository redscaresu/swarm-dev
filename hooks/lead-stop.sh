#!/usr/bin/env bash
# lead-stop.sh — the plugin's Stop hook for the lead (hooks/hooks.json). A Claude Code session acts
# only when a message or a notification wakes it, so a lead that ends its turn promising the step
# `next` names leaves that step waiting until the user asks. In the lead's session (a .claude/swarm/
# in $SWARM_PROJECT or the hook input's cwd, and SWARM_AGENT unset) it runs `swarm.sh next`, each
# call within LEAD_STOP_SECONDS (times SWARM_SLEEP_SCALE, as make test sets it). When the first line
# is plan-epic, story, resume, collect or conduct and `swarm.sh status` lists no working agent for
# its subject (named after it, its conductor conduct-<subject>, or in tab scope-<subject>; an EMPTY
# pane, a gone session or an unknown one is no agent at work; a status with no agent list allows),
# it prints a block decision naming the line; any other step allows the stop. stop_hook_active (the
# turn was blocked once already) allows it, so a lead with a reason not to act says so and stops.
# Every verdict after next ran is one events.tsv line, `lead-stop <step> blocked|allowed`. Any error
# (no swarm.sh or python3, a timeout, a non-zero exit) allows the stop, with nothing on stdout.
set -uo pipefail
LEAD_STOP_SECONDS=10

input="$(cat)"
[[ -z "${SWARM_AGENT:-}" ]] || exit 0
command -v python3 >/dev/null || exit 0
out="$(printf '%s' "${input}" | python3 -I -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    d = None
d = d if isinstance(d, dict) else {}
print("1" if d.get("stop_hook_active") is True else "")
c = d.get("cwd")
print(c if isinstance(c, str) and "\n" not in c else "")' 2>/dev/null)" || exit 0
{ read -r active; read -r cwd; } <<EOF
${out}
EOF
[[ -z "${active}" ]] || exit 0
project=""
for d in "${SWARM_PROJECT:-}" "${cwd:-${PWD}}"; do
  [[ -n "${d}" && -d "${d}/.claude/swarm" ]] && { project="${d}"; break; }
done
[[ -n "${project}" ]] || exit 0
sw="$(cd "$(dirname "$0")/.." && pwd)/bin/swarm.sh"
[[ -x "${sw}" ]] || exit 0
secs="$(awk -v s="${LEAD_STOP_SECONDS}" -v k="${SWARM_SLEEP_SCALE:-1}" 'BEGIN { print s * k }')"

# swarm <args>... — swarm.sh in the project, in its own process group, KILLed after secs (exit 142),
# as merge.sh's within does: a stub or a herdr call that hangs never holds the stop.
swarm() {
  SWARM_PROJECT="${project}" perl -MTime::HiRes=alarm -e 'my $t = shift;
    defined(my $p = fork) or exit 127;
    if (!$p) { setpgrp; exec @ARGV or exit 127 }
    $SIG{ALRM} = sub { kill "KILL", -$p; exit 142 };
    alarm $t; waitpid $p, 0;
    exit($? & 127 ? 128 + ($? & 127) : $? >> 8)' "${secs}" "${sw}" "$@" < /dev/null 2>/dev/null
}

# log <step> <verdict> — append record_event's five fields; a log that cannot be written changes nothing.
log() {
  { mkdir -p "${project}/.swarm" \
    && printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" lead-stop "$1" "${HERDR_PANE_ID:--}" "$2" \
      >> "${project}/.swarm/events.tsv"; } 2>/dev/null || true
}

line="$(swarm next | sed -n 1p)" && [[ -n "${line}" ]] || { log - allowed; exit 0; }
read -r step subject _ <<< "${line}"
case "${step}" in
  plan-epic|story|resume|collect|conduct) ;;
  *) log "${step}" allowed; exit 0 ;;
esac
agents="$(swarm status)" || { log "${step}" allowed; exit 0; }
# The Agents section ends at its first blank line; the Next section below it names the subject too.
# A status with no agent list (outside herdr, or herdr failed) proves nothing, so it allows.
if awk -v s="${subject:-}" 'NR == 1 && /not available/ || /^  \(herdr gave no agent list\)/ { f = 1; exit }
    NR > 1 && /^$/ { exit } NR > 1 && /^  [^ (]/ {
    t = $0; sub(/.*\[/, "", t); sub(/ .*/, "", t)
    if (($1 == s || $1 == "conduct-" s || t == "scope-" s) && $2 !~ /^(EMPTY|gone|unknown)/) f = 1 } END { exit !f }' <<< "${agents}"; then
  log "${step}" allowed; exit 0
fi
log "${step}" blocked
LINE="${line}" python3 -I -c 'import json, os
print(json.dumps({"decision": "block", "reason": "next says: " + os.environ["LINE"] + ". Start it now, or tell the user why it cannot start."}))'
exit 0
