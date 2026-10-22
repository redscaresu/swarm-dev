#!/usr/bin/env bash
# lead-stop.sh — the plugin's Stop hook for the lead (hooks/hooks.json). A Claude Code session acts
# only when a message or a notification wakes it, so a lead that ends its turn promising the step
# `next` names leaves that step waiting until the user asks. In the lead's session (a .claude/swarm/
# in $SWARM_PROJECT or the hook input's cwd, and SWARM_AGENT unset) it runs `swarm.sh next`, each
# call within LEAD_STOP_SECONDS (times SWARM_SLEEP_SCALE, as make test sets it; 1 at least). When
# the first line is plan-epic, story, resume, collect or conduct and the step has not started, it
# prints a block decision naming the line; any other step allows the stop. A step has started when
# `swarm.sh status --all` lists an agent for it, named as agent_name names it (the subject, or
# conduct-<epic> for conduct; for story and resume, the backlog conductor too), or in tab
# scope-<epic> or scope-<epic>-<n> for plan-epic. An EMPTY pane, a gone session or an unknown one is
# no agent; for collect an idle or done conductor is not either, since its report waits on the lead.
# A status with no agent list allows. The stops the lead makes to wait on the user count as started
# too: plan-epic once its plan is drafted (a .swarm/<epic>/*.json newer than the epic, or the
# board/scope-<epic> branch); story once the backlog conductor's report is newer than every board
# item (commands/swarm.md); and resume once that holds or the report lists the slug under `not
# started:`. stop_hook_active (the turn was blocked once already) allows the stop, so a lead with a
# reason not to act says so and stops. Every verdict after next ran is one events.tsv line,
# `lead-stop <step> blocked|allowed`. Any error (no swarm.sh or python3, a timeout, a non-zero exit)
# allows the stop, with nothing on stdout.
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
  SWARM_PROJECT="${project}" perl -MTime::HiRes=alarm -e 'my $t = shift; $t = 1 if $t < 1;
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

# name <slug> — swarm.sh's agent_name: the agent name swarm.sh gives <slug>.
name() {
  local n
  n="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-')"
  [[ "${n}" =~ ^[a-z] ]] || n="s${n}"
  printf '%s' "${n:0:32}"
}

# live <name> <tab> <busy> <backlog> — status --all's Agents section lists the agent <name>, one in
# tab <tab> or <tab>-<n> (next_pane's later panes), or with <backlog> 1 the backlog conductor (not a
# retired one, renamed <name>-done, -done2 ...). With <busy> 1 an idle or done agent does not count. A status that fails or has no agent list counts.
live() {
  local agents
  agents="$(swarm status --all)" || return 0
  # The section ends at its first blank line; the Next section below it names the subject too.
  awk -v n="$1" -v tab="$2" -v busy="$3" -v backlog="$4" '
    NR == 1 && /not available/ || /^  \(herdr gave no agent list\)/ { f = 1; exit }
    NR > 1 && /^$/ { exit }
    NR > 1 && /^  [^ (]/ {
      if ($2 ~ /^(EMPTY|gone|unknown)/ || busy && $2 ~ /^(idle|done)/) next
      t = $0; sub(/.*\[/, "", t); sub(/ .*/, "", t); r = substr(t, length(tab) + 1)
      if ($1 == n || backlog && $1 ~ /^conduct-backlog-/ && $1 !~ /-done[0-9]*$/) f = 1
      if (tab != "" && substr(t, 1, length(tab)) == tab && (r == "" || r ~ /^-[0-9]+$/)) f = 1
    } END { exit !f }' <<< "${agents}"
}

REPORT="${project}/.swarm/conduct-backlog.report.md"

# not_started <slug> — the backlog conductor's report lists <slug> as `not started: <slug> (...)`.
not_started() {
  awk -v k="not started: $1" '{ i = index($0, k); c = substr($0, i + length(k), 1)
    if (i && (c == "" || c == " " || c == "(")) f = 1 } END { exit !f }' "${REPORT}" 2>/dev/null
}

# backlog_stopped — the backlog conductor's report is newer than every story and epic: a new one
# would stop the same way, so the lead tells the user why and stops (commands/swarm.md, story).
backlog_stopped() {
  local board
  [[ -f "${REPORT}" ]] && board="$(swarm config board_dir)" && [[ -d "${board}" ]] || return 1
  [[ -z "$(find "${board}/stories" "${board}/epics" \( -name '*.md' -o -type d \) -newer "${REPORT}" 2>/dev/null)" ]]
}

# plan_drafted <epic> — the plan waits on the user: the board-PR branch the lead plans a small epic
# in, or a planner's answer in .swarm/<epic>/ that parses as JSON and is newer than the epic (an
# older one belongs to a previous plan, as /plan-epic reads it).
plan_drafted() {
  local board
  git -C "${project}" show-ref -q --verify "refs/heads/board/scope-$1" 2>/dev/null && return 0
  board="$(swarm config board_dir)" || return 1
  python3 -I -c '
import glob, json, os, sys
try:
    t = os.path.getmtime(sys.argv[2])
except OSError:
    t = 0
for f in glob.glob(os.path.join(sys.argv[1], "*.json")):
    try:
        if os.path.getmtime(f) > t:
            with open(f) as h:
                json.load(h)
            sys.exit(0)
    except (OSError, ValueError):
        pass
sys.exit(1)' "${project}/.swarm/$1" "${board}/epics/$1.md" 2>/dev/null
}

# started — the step next names is under way, or is a stop that waits on the user.
started() {
  case "${step}" in
    plan-epic) plan_drafted "${subject}" || live "" "scope-${subject}" 0 0 ;;
    story)     backlog_stopped || live "$(name "${subject}")" "" 0 1 ;;
    resume)    not_started "${subject}" || backlog_stopped || live "$(name "${subject}")" "" 0 1 ;;
    conduct)   live "$(name "conduct-${subject}")" "" 0 0 ;;
    collect)   live "$(name "${subject}")" "" 1 0 ;;
    *)         return 0 ;;
  esac
}

line="$(swarm next | sed -n 1p)" && [[ -n "${line}" ]] || { log - allowed; exit 0; }
read -r step subject _ <<< "${line}"
subject="${subject:-}"
if started; then log "${step}" allowed; exit 0; fi
log "${step}" blocked
LINE="${line}" python3 -I -c 'import json, os
print(json.dumps({"decision": "block", "reason": "next says: " + os.environ["LINE"] + ". Start it now, or tell the user why it cannot start."}))'
exit 0
