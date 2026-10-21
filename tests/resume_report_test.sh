#!/usr/bin/env bash
# resume_report_test.sh — herdr resumes a Claude pane after a restart with `claude --resume <id>`
# alone, so start_agent reports the agent's whole resume command: once a Claude agent starts, and
# before its brief, `herdr pane report-agent <pane> --source swarm --agent claude --state idle --
# claude --resume <session>` carries every flag of its launch line, --session-id as --resume. A codex
# agent reports nothing. A flag with an apostrophe (herdr refuses one) stops the start before a pane
# opens, naming the flag, and a report herdr refuses closes the pane and fails the start. Then the
# plugin's hooks (hooks/hooks.json, run as Claude Code would for each event) report working on
# UserPromptSubmit, idle on Stop, blocked on a permission Notification and release on a quit, in a
# swarm agent's session only, printing nothing. start_agent runs sourced with its helpers stubbed;
# herdr is a stub that logs each call's argv, %q-quoted.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
LOG="${ROOT}/herdr.log"; echo brief > "${ROOT}/brief.md"
fails=0
check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }

# start <role> — start_agent for agent a1 with role <role> and policy $POLICY (claude opus high), in a
# subshell with agents.sh sourced and its helpers stubbed: a pane opens as w:1 (logged as "pane
# opened"), herdr logs its argv to herdr.log and fails a report-agent while reportfail exists, and
# deliver_prompt logs "brief". Sets out (stdout and stderr) and rc.
start() {
  : > "${LOG}"; rc=0
  out="$(
    PROJECT_DIR="${ROOT}/p"; SWARM_HOME="${REPO}"; STATE_DIR="${ROOT}/p/.swarm/state"
    CFG_builder_subagent_model="${SUBAGENT:-}"; BUILDER_ROLES="code code-risky"
    # shellcheck source=bin/lib/agents.sh
    source "${REPO}/bin/lib/agents.sh"
    die() { echo "swarm: $*" >&2; exit 1; }
    policy() { echo "${POLICY:-claude opus high}"; }
    agent_name() { printf '%s' "$1"; }
    require_trusted() { :; }; require_claude() { :; }; free_agent_name() { :; }; clean_env() { :; }
    record_agent() { :; }; nap() { :; }
    next_pane() { echo "pane opened" >> "${LOG}"; echo w:1; }
    deliver_prompt() { echo brief >> "${LOG}"; }
    herdr() {
      { printf '%q ' "$@"; echo; } >> "${LOG}"
      [[ "$1 $2" != "pane report-agent" || ! -e "${ROOT}/reportfail" ]] || { echo '{"error":{"code":"invalid_resume_argv"}}'; return 1; }
    }
    start_agent t a1 "${ROOT}" "$1" "${ROOT}/brief.md" 2>&1
  )" || rc=$?
}
line() { grep "^$1 " "${LOG}" | sed 's/ $//' || true; }   # <first words> — herdr's logged call
order() { cut -d' ' -f1,2 "${LOG}" | paste -sd'|' -; }
# want_report — the report the agent start line calls for: its launch flags, --session-id as --resume.
want_report() { local l; l="$(line 'agent start')"; l="${l#* -- }"; echo "pane report-agent w:1 --source swarm --agent claude --state idle -- claude ${l/--session-id/--resume}"; }

# --- A builder with builder_subagent_model: the report carries every launch flag, before the brief.
SUBAGENT=haiku start code
check "a builder starts" "0" "${rc}"
check "its report-agent call is its launch line in resume form" "$(want_report)" "$(line 'pane report-agent')"
check "the report carries the model, effort, permission mode, merge guard and SWARM_AGENT, and the subagent model" "yes|yes" \
  "$(has '--model opus --effort high --permission-mode auto --disallowedTools Bash\(gh\ pr\ merge:\*\) --settings' "$(line 'pane report-agent')")|$(
  has 'SWARM_AGENT\":\"a1\"\,\"CLAUDE_CODE_SUBAGENT_MODEL\":\"haiku\"' "$(line 'pane report-agent')")"
check "the report comes after the start and before the brief" "pane opened|agent start|pane report-agent|brief" "$(order)"

# --- The fallback reviewer: its extra denied tools are in the report too.
POLICY="claude sonnet high" start review-fallback
check "the fallback reviewer's report-agent call is its launch line in resume form" "$(want_report)" "$(line 'pane report-agent')"
check "its report denies the file tools, commit and push" "yes" \
  "$(has '--disallowedTools Bash\(gh\ pr\ merge:\*\) Edit Write NotebookEdit Bash\(git\ commit:\*\) Bash\(git\ push:\*\) --settings' "$(line 'pane report-agent')")"

# --- A codex agent: herdr resumes nothing of it, so nothing is reported.
POLICY="codex default high" start codex
check "a codex agent starts, with no report-agent call" "0|pane opened|agent start|brief" "${rc}|$(order)"

# --- A flag with an apostrophe: refused before any pane opens, naming it.
POLICY="claude o'pus high" start code
check "a flag with an apostrophe fails the start, naming it, before a pane opens" "1|yes|" \
  "${rc}|$(has "swarm: a1: --model o'pus has an apostrophe, which herdr refuses in the command that resumes the agent after a restart" "${out}")|$(order)"

# --- herdr refuses the report: the pane is closed and the start fails, with no brief sent.
touch "${ROOT}/reportfail"; start code; rm -f "${ROOT}/reportfail"
check "a refused report closes the pane and fails the start, saying why" "1|yes|pane opened|agent start|pane report-agent|pane close" \
  "${rc}|$(has 'swarm: a1: herdr did not take the command that resumes the agent, so a restart would drop its guards: {"error":{"code":"invalid_resume_argv"}}' "${out}")|$(order)"

# --- The hooks. hook <event> <subject> <input> [unset] — run each command hooks.json gives <event>
# whose matcher finds <subject> (or that has none), as Claude Code would: through sh, with <input> on
# stdin, CLAUDE_PLUGIN_ROOT this repo, in agent a1's session (SWARM_AGENT) in herdr pane w:9
# (HERDR_PANE_ID), less the variable <unset> names. The herdr stub logs its argv to hook.log, prints a result and fails while hookfail
# exists. Sets got: what was logged, then what the hooks printed.
HOOK_LOG="${ROOT}/hook.log"
cat > "${ROOT}/herdr-bin" <<EOF
#!/bin/sh
echo "\$*" >> "${HOOK_LOG}"; echo '{"result":{}}'
[ ! -e "${ROOT}/hookfail" ] || exit 2
EOF
chmod +x "${ROOT}/herdr-bin"
hook() {
  local cmd printed="" rc=0 v vars=()
  for v in CLAUDE_PLUGIN_ROOT="${REPO}" HERDR_BIN_PATH="${ROOT}/herdr-bin" HERDR_PANE_ID=w:9 SWARM_AGENT=a1; do
    [[ "${v%%=*}" == "${4:-}" ]] || vars+=("${v}")
  done
  : > "${HOOK_LOG}"
  while IFS= read -r cmd; do
    printed+="$(printf '%s' "$3" | env -u SWARM_AGENT -u HERDR_PANE_ID "${vars[@]}" sh -c "${cmd}")" || rc=$?
  done < <(python3 -c '
import json, re, sys
for entry in json.load(open(sys.argv[1]))["hooks"].get(sys.argv[2], []):
    if re.search(entry.get("matcher") or "", sys.argv[3]):
        for h in entry["hooks"]:
            print(h["command"])' "${REPO}/hooks/hooks.json" "$1" "$2")
  got="$(cat "${HOOK_LOG}")|${printed}|${rc}"
}
hook UserPromptSubmit "" '{"hook_event_name":"UserPromptSubmit","prompt":"go"}'
check "UserPromptSubmit reports working, printing nothing" "pane report-agent --source swarm --agent claude --state working w:9||0" "${got}"
hook Stop "" '{"hook_event_name":"Stop"}'
check "Stop reports idle" "pane report-agent --source swarm --agent claude --state idle w:9||0" "${got}"
hook Notification permission_prompt '{"hook_event_name":"Notification","notification_type":"permission_prompt"}'
check "a permission Notification reports blocked" "pane report-agent --source swarm --agent claude --state blocked w:9||0" "${got}"
hook Notification idle_prompt '{"hook_event_name":"Notification","notification_type":"idle_prompt"}'
check "an idle Notification reports nothing: the agent is idle, not blocked" "||0" "${got}"
hook SessionEnd prompt_input_exit '{"hook_event_name":"SessionEnd","reason":"prompt_input_exit"}'
check "SessionEnd on a quit releases the pane" "pane release-agent --source swarm --agent claude w:9||0" "${got}"
hook SessionEnd other '{"hook_event_name":"SessionEnd","reason":"other"}'
check "SessionEnd as the pane dies (a herdr restart) releases nothing, keeping the resume command" "||0" "${got}"
hook UserPromptSubmit "" '{"hook_event_name":"UserPromptSubmit","prompt":"go"}' SWARM_AGENT
check "outside a swarm agent's session (no SWARM_AGENT), the hooks report nothing" "||0" "${got}"
hook Stop "" '{"hook_event_name":"Stop"}' HERDR_PANE_ID
check "outside a herdr pane, the hooks report nothing" "||0" "${got}"
touch "${ROOT}/hookfail"; hook UserPromptSubmit "" '{"hook_event_name":"UserPromptSubmit","prompt":"go"}'; rm -f "${ROOT}/hookfail"
check "a herdr that fails never fails the hook, which would block the prompt" "pane report-agent --source swarm --agent claude --state working w:9||0" "${got}"

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
