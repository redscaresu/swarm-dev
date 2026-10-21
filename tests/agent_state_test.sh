#!/usr/bin/env bash
# agent_state_test.sh — structural: herdr's agent_status is read only where the agent-state epic
# allows, so a Claude agent's state always comes from its session. An awk walk over swarm.sh,
# bin/lib/*.sh and bin/lib/*.py tracks the enclosing bash function (a .py file is named for the one it runs for) and,
# inside panes.py, the python def; every non-comment line naming
# agent_status must sit in an allowlisted place. Also: agent_state is called without a session only
# from tidy_panes, and no `herdr agent read ... |` pipeline scrapes a pane. Run on another file with
# `bash tests/agent_state_test.sh <swarm.sh>`.
set -euo pipefail

iso="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${iso}"' EXIT
export CLAUDE_CONFIG_DIR="${iso}/claude-config"   # under its own root, so parallel runs share no ~/.claude

SWARM="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh}"
LIB="$(dirname "${SWARM}")/lib"
fails=0

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}

# The bash functions that may read agent_status, each with its reason.
ALLOWED="
deliver_prompt  the taken-up gate: herdr's working or blocked after a prompt, for any agent (out of the epic's scope)
agent_field     the definition: the one reader of herdr's agent list
agent_status    the definition: herdr's status for an agent, used only by the fallbacks here
read_state      the reader's herdr fallback for tell and free_agent_name: codex, or no session recorded
herdr_wait      wait's herdr fallback: codex, or no session recorded
herdr_step      herdr_wait's step, its stream or herdr agent wait: codex, or no session recorded
herdr_events    herdr_wait's event stream (herdr_events.py): codex, or no session recorded
close_lists     close's guard, read once per close: herdr's word for an agent no session answers for
turn_ended      an API-error or auto-denied stop: herdr's done or idle, while open background shells keep the session busy
"
# Allowed anywhere, with no list entry:
#   `-z "$(agent_field <name> agent_status any)"` — a name check: does any agent hold the name. Any
#   other use of the `any` form reads herdr's status.
#   panes.py's agent_state after `if s is not None:` — herdr's word only when session_state gave None.
# The one function that may call agent_state with no session (its no-entry fallback):
#   tidy_panes — closes only empty panes and retired ones, and retired is retire_agent's rename in
#   herdr, which no session reports.
NO_SESSION_CALLER=tidy_panes
# The one function that may call herdr_wait, which has no session guard of its own:
#   settle — calls it only when session_state answered `herdr` (codex, or no session recorded).
HERDR_WAIT_CALLER=settle

# walk — one line per violation: "<file>:<line>: <function or panes.py def>: <what>".
walk() {
  awk -v allowed="$(awk 'NF {print $1}' <<< "${ALLOWED}" | tr '\n' ' ')" -v nosess="${NO_SESSION_CALLER}" -v hwait="${HERDR_WAIT_CALLER}" '
    BEGIN { n = split(allowed, a, " "); for (i = 1; i <= n; i++) ok[a[i]] = 1 }
    # no_session(line) — the line calls agent_state with fewer than three arguments, or a None third.
    function no_session(line,   args, f) {
      if (!match(line, /agent_state\(/)) return 0
      args = substr(line, RSTART + RLENGTH)
      while (gsub(/\([^()]*\)/, "", args)) {}
      args = substr(args, 1, index(args ")", ")") - 1)
      return split(args, f, ",") < 3 || f[3] ~ /^ *(s *= *)?None *$/
    }
    FNR == 1 { sh = FILENAME !~ /\.py$/; fn = sh ? "" : FILENAME; sub(/.*\//, "", fn); sub(/\.py$/, "", fn); py = fn == "panes"; def = "" }
    py && /^[^ \t#]/ { def = ""; fb = 0 } # column 0 ends a def
    py && match($0, /^def [A-Za-z0-9_]+/) { def = substr($0, 5, RLENGTH - 4) }
    py && fb == 1 && /^    [^ ]/ { fb = 2 } # first line after the session branch: the fallback
    py && def == "agent_state" && /^    if s is not None:/ { fb = 1 }
    sh && match($0, /^[A-Za-z0-9_]+\(\) *\{/) { fn = substr($0, 1, index($0, "(") - 1); one = ($0 ~ /\}[ \t]*(#.*)?$/) }
    {
      where = py ? "panes.py " def : fn
      if ($0 !~ /^[ \t]*#/) {
        l = $0; gsub(/-z "\$\(agent_field "[^"]*" agent_status any\)"/, "", l)
        if (l ~ /agent_status/ && !(!py && ok[fn]) && !(py && def == "agent_state" && fb == 2))
          print FILENAME ":" FNR ": " where ": reads agent_status"
        if ($0 !~ /^def / && no_session($0) && fn != nosess)
          print FILENAME ":" FNR ": " where ": calls agent_state with no session"
        if ($0 ~ /(^|[^A-Za-z0-9_])herdr_wait([ \t]|$)/ && fn != hwait)
          print FILENAME ":" FNR ": " where ": calls herdr_wait"
        cmd = cmd " " $0 # a command continued with \ is checked whole, on its last line
        if ($0 !~ /\\$/) {
          if (cmd ~ /herdr agent read[^|]*\|([^|]|$)/) print FILENAME ":" FNR ": " where ": pipes herdr agent read"
          cmd = ""
        }
      }
    }
    one { fn = ""; one = 0 }
    sh && /^\}/ { fn = "" }
  ' "${SWARM}" "${LIB}"/*.sh "${LIB}"/*.py
}

out="$(walk)"
[[ -z "${out}" ]] || printf '%s\n' "${out}"
none() { ! grep -q "$1" <<< "${out}"; }
check "agent_status is read only in allowlisted places" none ': reads agent_status$'
check "agent_state is called with no session only from ${NO_SESSION_CALLER}" none ': calls agent_state with no session$'
check "herdr_wait is called only from ${HERDR_WAIT_CALLER}" none ': calls herdr_wait$'
check "no herdr agent read output is piped" none ': pipes herdr agent read$'
# The walk is only as good as its anchors: each allowlisted place must exist, or a rename would pass.
for fn in $(awk 'NF {print $1}' <<< "${ALLOWED}") "${NO_SESSION_CALLER}" "${HERDR_WAIT_CALLER}"; do
  check "allowlisted ${fn} is defined" grep -Eq "^${fn}\(\) *\{" "${SWARM}" "${LIB}"/*.sh
done
check "panes.py's agent_state has its session branch" grep -q '^    if s is not None:$' "${LIB}/panes.py"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
