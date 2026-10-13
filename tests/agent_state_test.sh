#!/usr/bin/env bash
# agent_state_test.sh — structural: herdr's agent_status is read only where the agent-state epic
# allows, so a Claude agent's state always comes from its session. An awk walk over swarm.sh tracks
# the enclosing bash function and, inside PANES_PY, the python def; every non-comment line naming
# agent_status must sit in an allowlisted place. Also: agent_state is called without a session only
# from tidy_panes, and no `herdr agent read ... |` pipeline scrapes a pane. Run on another file with
# `bash tests/agent_state_test.sh <swarm.sh>`.
set -euo pipefail

SWARM="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh}"
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
"
# Allowed anywhere, with no list entry:
#   `agent_field <name> agent_status any` — a name check: does any agent hold the name; it reads no state.
#   PANES_PY's agent_state after `if s is not None:` — herdr's word only when session_state gave None.
# The one function that may call agent_state with no session (its no-entry fallback):
#   tidy_panes — closes only empty panes and retired ones, and retired is retire_agent's rename in
#   herdr, which no session reports.
NO_SESSION_CALLER=tidy_panes

# walk — one line per violation: "<line>: <function or PANES_PY def>: <what>".
walk() {
  awk -v allowed="$(awk 'NF {print $1}' <<< "${ALLOWED}" | tr '\n' ' ')" -v nosess="${NO_SESSION_CALLER}" -v q="'" '
    BEGIN { n = split(allowed, a, " "); for (i = 1; i <= n; i++) ok[a[i]] = 1 }
    $0 == "PANES_PY=" q { py = 1; next }
    py && $0 == q { py = 0; def = ""; next }
    py && match($0, /^def [a-z_]+/) { def = substr($0, 5, RLENGTH - 4); fb = 0 }
    py && def == "agent_state" && /^    if s is not None:/ { fb = 1; next }
    py && fb == 1 && /^    [^ ]/ { fb = 2 }
    !py && match($0, /^[a-z_]+\(\) *\{/) { fn = substr($0, 1, index($0, "(") - 1); one = ($0 ~ /\}$/) }
    {
      where = py ? "PANES_PY " def : fn
      if ($0 !~ /^[ \t]*#/) {
        l = $0; gsub(/agent_field "[^"]*" agent_status any/, "", l)
        if (l ~ /agent_status/ && !(!py && ok[fn]) && !(py && def == "agent_state" && fb == 2))
          print NR ": " where ": reads agent_status"
        if ($0 !~ /^def / && $0 ~ /agent_state\([^,()]*,[^,()]*(, *(s *= *)?None *)?\)/ && fn != nosess)
          print NR ": " where ": calls agent_state with no session"
        cmd = cmd " " $0 # a command continued with \ is checked whole, on its last line
        if ($0 !~ /\\$/) {
          if (cmd ~ /herdr agent read[^|]*\|([^|]|$)/) print NR ": " where ": pipes herdr agent read"
          cmd = ""
        }
      }
    }
    one { fn = ""; one = 0 }
    !py && /^\}/ { fn = "" }
  ' "${SWARM}"
}

out="$(walk)"
[[ -z "${out}" ]] || printf '%s\n' "${out}"
none() { ! grep -q "$1" <<< "${out}"; }
check "agent_status is read only in allowlisted places" none ': reads agent_status$'
check "agent_state is called with no session only from ${NO_SESSION_CALLER}" none ': calls agent_state with no session$'
check "no herdr agent read output is piped" none ': pipes herdr agent read$'
# The walk is only as good as its anchors: each allowlisted place must exist, or a rename would pass.
for fn in $(awk 'NF {print $1}' <<< "${ALLOWED}") "${NO_SESSION_CALLER}"; do
  check "allowlisted ${fn} is defined" grep -Eq "^${fn}\(\) *\{" "${SWARM}"
done
check "PANES_PY's agent_state has its session branch" grep -q '^    if s is not None:$' "${SWARM}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
