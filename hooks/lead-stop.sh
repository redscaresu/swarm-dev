#!/usr/bin/env bash
# lead-stop.sh — the plugin's Stop hook for the lead (hooks/hooks.json). A Claude Code session acts
# only when a message or a notification wakes it, so a lead that ends its turn promising the step
# `next` names leaves that step waiting until the user asks. In the lead's session (SWARM_AGENT
# unset, in a swarm project: $SWARM_PROJECT, else the hook input's cwd mapped to its main checkout as
# swarm.sh's find_project does, holding a .claude/swarm/) it runs `swarm.sh next`. When the first
# line is plan-epic, story, resume, collect or conduct and the step has not started, it prints a
# block decision naming the line; any other step allows the stop. collect is the lead's own step, so
# it always blocks. Another step has started when herdr runs an agent in one of the project's panes
# (.swarm/state) named as agent_name names it (the subject, or conduct-<epic> for conduct; for story
# and resume, the backlog conductor too, not a retired one), or for plan-epic any agent in tab
# scope-<epic> or scope-<epic>-<n>. A pane with no agent, or one herdr calls unknown, is no agent.
# The stops the lead makes to wait on the user count as started too: plan-epic once its plan is
# drafted (a .swarm/<epic>/*.json newer than the epic that parses, or the board/scope-<epic>
# branch); story once the backlog conductor's report is newer than every story and epic
# (commands/swarm.md); and resume once that holds or the report lists the slug under `not
# started:`. stop_hook_active (the turn was blocked once already) allows the stop, so a lead with a
# reason not to act says so and stops. The whole hook runs within LEAD_STOP_SECONDS (times
# SWARM_SLEEP_SCALE, as make test sets it; 1 at least), under hooks.json's 60: `next` alone takes
# up to half a minute on a busy board, so nothing else here runs next_step again. Every verdict
# after next ran is one events.tsv line, `lead-stop <step> blocked|allowed`. Any error (no swarm.sh
# or python3, no herdr, a lookup that fails, the deadline) allows the stop, with nothing on stdout.
set -uo pipefail
LEAD_STOP_SECONDS=45

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
deadline="$(perl -MTime::HiRes=time -e 'my $s = shift() * shift(); printf "%.3f", time + ($s < 1 ? 1 : $s)' \
  "${LEAD_STOP_SECONDS}" "${SWARM_SLEEP_SCALE:-1}")" || exit 0

# main_checkout <dir> — swarm.sh's main_checkout: <dir> as it sits in its repo's main checkout.
main_checkout() {
  local common top d
  common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    && top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || return 1
  d="$(cd "$1" && pwd -P)" || return 1
  echo "$(dirname "${common}")${d#"${top}"}"
}

if [[ -n "${SWARM_PROJECT:-}" ]]; then project="${SWARM_PROJECT}"
else d="${cwd:-${PWD}}"; project="$(main_checkout "${d}")" || project="${d}"
fi
[[ -d "${project}/.claude/swarm" ]] || exit 0
sw="$(cd "$(dirname "$0")/.." && pwd)/bin/swarm.sh"
[[ -x "${sw}" ]] || exit 0

# within <command>... — the command in its own process group, KILLed at the deadline (exit 142), as
# merge.sh's within does: a call that hangs never holds the stop past it.
within() {
  perl -MTime::HiRes=alarm,time -e 'my $t = shift() - time; exit 142 if $t <= 0;
    defined(my $p = fork) or exit 127;
    if (!$p) { setpgrp; exec @ARGV or exit 127 }
    $SIG{ALRM} = sub { kill "KILL", -$p; exit 142 };
    alarm $t; waitpid $p, 0;
    exit($? & 127 ? 128 + ($? & 127) : $? >> 8)' "${deadline}" "$@" < /dev/null 2>/dev/null
}

swarm() { SWARM_PROJECT="${project}" within "${sw}" "$@"; }

# log <step> <verdict> — append record_event's five fields; a log that cannot be written changes nothing.
log() {
  { mkdir -p "${project}/.swarm" \
    && printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" lead-stop "$1" "${HERDR_PANE_ID:--}" "$2" \
      >> "${project}/.swarm/events.tsv"; } 2>/dev/null || true
}

# allow — a lookup failed: allow the stop, which proves nothing either way.
allow() { log "${step}" allowed; exit 0; }

# name <slug> — swarm.sh's agent_name: the agent name swarm.sh gives <slug>.
name() {
  local n
  n="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-')"
  [[ "${n}" =~ ^[a-z] ]] || n="s${n}"
  printf '%s' "${n:0:32}"
}

# live <name> <tab> <backlog> — herdr runs, in a pane of this project's (.swarm/state/<tab>, a
# `<pane> [<name>]` line each, as own_panes reads it), the agent <name>, an agent in tab <tab> or
# <tab>-<n> (next_pane's later panes), or with <backlog> 1 the backlog conductor (not a retired one,
# renamed <name>-done, -done2 ...). Outside herdr, or with no agent list, the lookup allows.
live() {
  local agents
  [[ "${HERDR_ENV:-}" == 1 ]] || allow
  agents="$(within "${HERDR_BIN_PATH:-herdr}" agent list)" || allow
  printf '%s' "${agents}" | python3 -I -c '
import glob, json, os, re, sys
state, name, tab, backlog = sys.argv[1:5]
try:
    agents = {a.get("pane_id"): a for a in json.load(sys.stdin)["result"]["agents"]}
except (ValueError, KeyError, TypeError, AttributeError):
    sys.exit(2)
for path in glob.glob(os.path.join(state, "*")):
    t = os.path.basename(path)
    if not os.path.isfile(path) or t.endswith(".tmp"):
        continue
    for line in open(path, errors="replace"):
        f = line.split()
        if not f or len(f) > 2 or not re.fullmatch(r"[A-Za-z0-9]+:[A-Za-z0-9]+", f[0]):
            continue
        a = agents.get(f[0])
        if a is None or a.get("agent_status") in (None, "unknown"):
            continue
        n = a.get("name") or (f[1] if len(f) > 1 else "")
        if n == name or backlog == "1" and n.startswith("conduct-backlog-") and not re.search(r"-done[0-9]*$", n):
            sys.exit(0)
        if tab and (t == tab or re.fullmatch(re.escape(tab) + r"-[0-9]+", t)):
            sys.exit(0)
sys.exit(1)' "${project}/.swarm/state" "$1" "$2" "$3" 2>/dev/null
  case $? in 0) return 0 ;; 1) return 1 ;; *) allow ;; esac
}

REPORT="${project}/.swarm/conduct-backlog.report.md"

# board — the board's directory (config board_dir); fails when the lookup does.
board() {
  local b
  b="$(swarm config board_dir)" && [[ -d "${b}" ]] && echo "${b}"
}

# not_started <slug> — the backlog conductor's report lists <slug> as `not started: <slug> (...)`.
not_started() {
  awk -v k="not started: $1" '{ i = index($0, k); c = substr($0, i + length(k), 1)
    if (i && (c == "" || c == " " || c == "(")) f = 1 } END { exit !f }' "${REPORT}" 2>/dev/null
}

# backlog_stopped — the backlog conductor's report is newer than every story and epic: a new one
# would stop the same way, so the lead tells the user why and stops (commands/swarm.md, story).
backlog_stopped() {
  local b
  [[ -f "${REPORT}" ]] || return 1
  b="$(board)" || allow
  [[ -z "$(find "${b}/stories" "${b}/epics" \( -name '*.md' -o -type d \) -newer "${REPORT}" 2>/dev/null)" ]]
}

# plan_drafted <epic> — the plan waits on the user: the board-PR branch the lead plans a small epic
# in, or a planner's answer in .swarm/<epic>/ that parses as JSON and is newer than the epic (an
# older one belongs to a previous plan, as /plan-epic reads it).
plan_drafted() {
  local b
  git -C "${project}" show-ref -q --verify "refs/heads/board/scope-$1" 2>/dev/null && return 0
  b="$(board)" || allow
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
sys.exit(1)' "${project}/.swarm/$1" "${b}/epics/$1.md" 2>/dev/null
}

# started — the step next names is under way, or is a stop that waits on the user.
started() {
  case "${step}" in
    plan-epic) plan_drafted "${subject}" || live "" "scope-${subject}" 0 ;;
    story)     backlog_stopped || live "$(name "${subject}")" "" 1 ;;
    resume)    not_started "${subject}" || backlog_stopped || live "$(name "${subject}")" "" 1 ;;
    conduct)   live "$(name "conduct-${subject}")" "" 0 ;;
    collect)   return 1 ;;
    *)         return 0 ;;
  esac
}

step=-
line="$(swarm next | sed -n 1p)" && [[ -n "${line}" ]] || allow
read -r step subject _ <<< "${line}"
subject="${subject:-}"
if started; then log "${step}" allowed; exit 0; fi
log "${step}" blocked
LINE="${line}" python3 -I -c 'import json, os
print(json.dumps({"decision": "block", "reason": "next says: " + os.environ["LINE"] + ". Start it now, or tell the user why it cannot start."}))'
exit 0
