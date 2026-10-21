#!/usr/bin/env bash
# resume_report_test.sh — herdr resumes a Claude pane after a restart with `claude --resume <id>`
# alone, in the pane's whole environment, so start_agent reports the agent's own resume command: once
# a Claude agent's brief is taken up, `herdr pane report-agent <pane> --source swarm --agent claude
# --state working --seq <time the brief was sent> --agent-session-id <session> -- bash <wrapper>
# claude --resume <session>` carries every flag of its launch line, --session-id as --resume, with
# --settings JSON a real encoder wrote. The wrapper (python3 -I <wrapper>) and the command it reads
# are the session's own, outside the project, so a project path with ", \ or ' starts as any other
# and a start refused for a busy name changes no agent's files. Run as herdr would after a restart,
# that command starts claude with those flags in the allowlisted environment (the story's names kept,
# anything else dropped, an exported function and a BASH_ENV in that environment never run), and no
# value is on it or in the files it reads. A codex agent reports nothing. Before a pane opens, a herdr
# older than 0.9.2 stops the start, and so does a resume command herdr would refuse (an apostrophe or
# a control character in a flag, more than 8 KiB joined or 64 arguments), naming why; a report herdr
# refuses keeps the agent, which is at work by then, and says so. Then the plugin's hooks
# (hooks/hooks.json, run as Claude Code would for each event) report working on UserPromptSubmit and
# PostToolUse, idle on Stop, StopFailure and a cleared or resumed SessionStart, blocked on a
# permission Notification, and release on a quit, each with a --seq taken before it forks, the
# session's id and its resume command, from the pane's own session only (its input's top-level
# session_id, the one after --resume, which a clear moves), never a nested session's, printing
# nothing, with herdr in the background so one that hangs holds no prompt. start_agent runs sourced
# with its helpers stubbed; herdr is a stub that logs each call's argv, %q-quoted.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
LOG="${ROOT}/herdr.log"; echo brief > "${ROOT}/brief.md"
RDIR="${CLAUDE_CONFIG_DIR}/swarm-dev/resume"
fails=0
check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }
now_ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }

# start <role> [names] — start_agent for agent a1 with role <role>, policy $POLICY (claude opus high)
# and the story names <names>, in project $PROJ (${ROOT}/p), in a subshell with agents.sh sourced and
# its helpers stubbed, where FAKE_SECRET is lead-secret: free_agent_name refuses while namefail
# exists, a pane opens as w:1 (logged as "pane opened"), clean_env writes the SWARM_RESUME it would
# pass on to launch-resume, herdr --version says herdr $HERDR_VERSION (0.9.5), herdr logs every other
# call's argv to herdr.log and fails a report-agent while reportfail exists, and deliver_prompt logs
# "brief" and writes the time it ran to brief-at. Sets start_out (stdout and stderr) and start_rc.
# started refusal <n> prints resume_refusal's word on <n> arguments, or "passes"; started refusal-args
# <arg>... its word on those.
start() { : > "${LOG}"; start_rc=0; start_out="$(started "$1" "${2:-}" 2>&1)" || start_rc=$?; }
started() (
    local PROJECT_DIR="${PROJ:-${ROOT}/p}" SWARM_HOME="${REPO}" STATE_DIR="${ROOT}/p/.swarm/state"
    local CFG_builder_subagent_model="${SUBAGENT:-}" BUILDER_ROLES="code code-risky"
    export FAKE_SECRET=lead-secret
    # shellcheck source=bin/lib/agents.sh
    source "${REPO}/bin/lib/agents.sh"
    die() { echo "swarm: $*" >&2; exit 1; }
    policy() { echo "${POLICY:-claude opus high}"; }
    agent_name() { printf '%s' "$1"; }
    require_trusted() { :; }; require_claude() { :; }; record_agent() { :; }; nap() { :; }
    free_agent_name() { [[ ! -e "${ROOT}/namefail" ]] || die "$1 is working, so its name is not free"; }
    clean_env() { printenv SWARM_RESUME > "${ROOT}/launch-resume" || echo "(not exported)" > "${ROOT}/launch-resume"; }
    next_pane() { echo "pane opened" >> "${LOG}"; echo w:1; }
    deliver_prompt() { echo brief >> "${LOG}"; python3 -c 'import time; print(time.time_ns())' > "${ROOT}/brief-at"; }
    herdr() {
      [[ "$1" != --version ]] || { echo "herdr ${HERDR_VERSION:-0.9.5}"; return; }
      { printf '%q ' "$@"; echo; } >> "${LOG}"
      [[ "$1 $2" != "pane report-agent" || ! -e "${ROOT}/reportfail" ]] || { echo '{"error":{"code":"invalid_resume_argv"}}'; return 1; }
    }
    # shellcheck disable=SC2046 # one argument per number
    if [[ "$1" == refusal ]]; then resume_refusal $(seq "$2") || echo passes; return; fi
    if [[ "$1" == refusal-args ]]; then shift; resume_refusal "$@" || echo passes; return; fi
    start_agent t a1 "${ROOT}" "$1" "${ROOT}/brief.md" a1 "$2"
)
# line <first words> — herdr's logged call, its --seq shown as N; seq_of — the report's --seq.
line() { grep "^$1 " "${LOG}" | sed -E 's/ $//; s/--seq [0-9]+/--seq N/' || true; }
seq_of() { sed -nE 's/^pane report-agent .*--seq ([0-9]+) .*/\1/p' "${LOG}"; }
order() { cut -d' ' -f1,2 "${LOG}" | paste -sd'|' -; }
sid() { line 'agent start' | sed -E 's/.* -- --session-id ([^ ]+).*/\1/'; }   # the session the start minted
# want_report — the report the agent start line calls for: working, its session id, and the wrapper,
# then claude with its launch flags, --session-id as --resume.
want_report() {
  local l id; l="$(line 'agent start')"; l="${l#* -- --session-id }"; id="${l%% *}"
  echo "pane report-agent w:1 --source swarm --agent claude --state working --seq N --agent-session-id ${id} -- python3 -I $(printf %q "${RDIR}/${id}.py") claude --resume ${l}"
}
# settings_env <argv file> — the env --settings sets, as sorted NAME=value words, from its JSON.
settings_env() {
  python3 -c '
import json, sys
a = open(sys.argv[1]).read().split("\n")
print(" ".join("%s=%s" % kv for kv in sorted(json.loads(a[a.index("--settings") + 1])["env"].items())))' "$1"
}
# restore — run the reported resume command as herdr does after a restart: from the agent's folder, in
# the user's whole environment (FAKE_SECRET, the story's name, as restored-value; LEAK_TOKEN and
# AWS_SECRET_ACCESS_KEY too), with herdr's variables for pane w:5 (HERDR_TAB_ID left empty), and a
# claude stub on PATH that writes its argv to claude.argv and its environment to claude.env. Any
# NAME=value arguments join that environment.
mkdir -p "${ROOT}/restore-bin" "${ROOT}/home"
cat > "${ROOT}/restore-bin/claude" <<EOF
#!/bin/sh
printf '%s\n' "\$@" > "${ROOT}/claude.argv"; env > "${ROOT}/claude.env"
EOF
chmod +x "${ROOT}/restore-bin/claude"
restore() {
  local cmd; cmd="$(grep '^pane report-agent ' "${LOG}")"; cmd="${cmd#* -- }"
  local args; eval "args=(${cmd})"   # the stub's own %q quoting
  rm -f "${ROOT}/claude.argv" "${ROOT}/claude.env"
  (cd "${ROOT}" && env -i PATH="${ROOT}/restore-bin:/usr/bin:/bin" HOME="${ROOT}/home" TERM=dumb FAKE_SECRET=restored-value \
    LEAK_TOKEN=leak AWS_SECRET_ACCESS_KEY=aws-leak SWARM_X=1 HERDR_ENV=1 HERDR_PANE_ID=w:5 HERDR_TAB_ID= "$@" "${args[@]}")
}
var() { sed -n "s/^$1=//p" "${ROOT}/claude.env"; }   # <name> — its value in the restored claude's environment

# --- A builder with builder_subagent_model and a story's env: name: the report carries every launch
# flag, once the brief is taken up.
SUBAGENT=haiku start code FAKE_SECRET
S1="$(sid)"
check "a builder starts" "0" "${start_rc}"
check "its report-agent call is working, its session id, the wrapper and its launch line in resume form" "$(want_report)" "$(line 'pane report-agent')"
check "the report carries the model, effort, permission mode, merge guard and SWARM_AGENT, and the subagent model" \
  "yes|CLAUDE_CODE_SUBAGENT_MODEL=haiku CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 SWARM_AGENT=a1" \
  "$(has '--model opus --effort high --permission-mode auto --disallowedTools Bash\(gh\ pr\ merge:\*\) --settings' "$(line 'pane report-agent')")|$(
  settings_env "${RDIR}/${S1}.argv")"
check "no state is reported before the brief is taken up: the report comes after it" "pane opened|agent start|brief|pane report-agent" "$(order)"
check "the report's --seq is the time before the brief was sent, so the hooks' later reports win" "yes" \
  "$( (($(seq_of) > 0 && $(seq_of) <= $(cat "${ROOT}/brief-at"))) && echo yes || echo "no: $(seq_of) vs $(cat "${ROOT}/brief-at")")"
check "SWARM_RESUME reaches the agent through clean_env, exported, never on a command line" "${RDIR}/${S1}.argv|0" \
  "$(cat "${ROOT}/launch-resume")|$(grep -c SWARM_RESUME "${LOG}" || true)"
cp "${RDIR}/${S1}.argv" "${ROOT}/a1.argv"   # the builder's resume command, for the hooks below

# --- The builder restored: claude with its flags, in the allowlist alone, and no value written down.
restore
check "restored, the wrapper starts claude with --resume and every launch flag" "$(tail -n +5 "${ROOT}/a1.argv")" "$(cat "${ROOT}/claude.argv")"
check "restored, the agent keeps the allowlist and its story's name, with the restored pane's values" \
  "${ROOT}/home|restored-value|1|w:5|${ROOT}/p|${RDIR}/${S1}.argv|/bin/zsh|${ROOT}/p/.swarm/zdotdir/a1" \
  "$(var HOME)|$(var FAKE_SECRET)|$(var SWARM_X)|$(var HERDR_PANE_ID)|$(var SWARM_PROJECT)|$(var SWARM_RESUME)|$(var SHELL)|$(var ZDOTDIR)"
check "restored, the agent gets no other variable, and herdr's empty ones are unset" "" \
  "$(grep -E '^(LEAK_TOKEN|AWS_SECRET_ACCESS_KEY|HERDR_TAB_ID)=' "${ROOT}/claude.env" || true)"
check "no value is on the resume command or in the files it reads" "no|no" \
  "$(if grep -q lead-secret "${LOG}"; then echo yes; else echo no; fi)|$(if grep -rq lead-secret "${RDIR}"; then echo yes; else echo no; fi)"
check "the wrapper and the command it reads are the session's own, and the owner's alone (0600)" "${S1}.argv ${S1}.py" \
  "$(find "${RDIR}" -name "${S1}.*" -perm 600 -exec basename {} \; | sort | paste -sd' ' -)"

# --- The restoring pane's shell exports a function named unset and sets a BASH_ENV that would mark
# that it ran and define one: neither runs, neither reaches the agent, and the scrub still holds.
printf '%s\n' "touch '${ROOT}/bash-env-ran'" 'unset() { :; }' > "${ROOT}/bash-env"
restore 'BASH_FUNC_unset%%=() { :; }' BASH_ENV="${ROOT}/bash-env"
check "restored, an exported function and a BASH_ENV in the pane never run and never reach the agent" "ran||no" \
  "$([[ -s "${ROOT}/claude.argv" ]] && echo ran)|$(grep -E '^(BASH_FUNC_|BASH_ENV=|LEAK_TOKEN=)' "${ROOT}/claude.env" || true)|$(
  [[ -e "${ROOT}/bash-env-ran" ]] && echo yes || echo no)"

# --- A start refused because the name's holder still works: no resume file written or changed.
before="$(cd "${RDIR}" && find . -type f | sort | xargs cat)"; n="$(find "${RDIR}" -type f | wc -l)"
touch "${ROOT}/namefail"; POLICY="claude sonnet high" start code; rm -f "${ROOT}/namefail"
check "a start refused for a busy name writes no resume file and leaves the live agent's as they were" "1|${n}|same" \
  "${start_rc}|$(find "${RDIR}" -type f | wc -l)|$([[ "$(cd "${RDIR}" && find . -type f | sort | xargs cat)" == "${before}" ]] && echo same || echo changed)"

# --- A project path with ", \ and ': the start goes ahead, --settings is still JSON, and the path is
# in no resume argument, only in the wrapper.
mkdir -p "${ROOT}/home"
PROJ="${ROOT}/p\"q\\r's" start code
S2="$(sid)"
check "a project path with \", \\ and ' starts as any other" "0" "${start_rc}"
check "its --settings is JSON a real encoder wrote" "SWARM_AGENT=a1" "$(settings_env "${RDIR}/${S2}.argv")"
check "its resume command holds no project path" "0" "$(grep -cF "${ROOT}/p\"q" "${RDIR}/${S2}.argv" || true)"
restore
check "restored, it is in its project, with that path" "${ROOT}/p\"q\\r's|${ROOT}/p\"q\\r's/.swarm/zdotdir/a1" "$(var SWARM_PROJECT)|$(var ZDOTDIR)"

# --- The fallback reviewer: its extra denied tools are in the report too.
POLICY="claude sonnet high" start review-fallback
check "the fallback reviewer's report-agent call is its launch line in resume form" "$(want_report)" "$(line 'pane report-agent')"
check "its report denies the file tools, commit and push" "yes" \
  "$(has '--disallowedTools Bash\(gh\ pr\ merge:\*\) Edit Write NotebookEdit Bash\(git\ commit:\*\) Bash\(git\ push:\*\) --settings' "$(line 'pane report-agent')")"

# --- A codex agent: herdr resumes nothing of it, so nothing is reported, and it has no SWARM_RESUME.
POLICY="codex default high" start codex
check "a codex agent starts, with no report-agent call and no SWARM_RESUME" "0|pane opened|agent start|brief|" \
  "${start_rc}|$(order)|$(cat "${ROOT}/launch-resume")"

# --- herdr too old to keep a resume command, or naming no version: refused before any pane opens.
HERDR_VERSION=0.9.1 start code
check "a herdr older than 0.9.2 fails the start, saying so, before a pane opens" "1|yes|" \
  "${start_rc}|$(has "swarm: swarm.sh needs herdr 0.9.2 or later, or a restart brings agents back without their guards, and herdr --version says 'herdr 0.9.1'." "${start_out}")|$(order)"
HERDR_VERSION=unknown start code
check "a herdr that names no version fails the start too" "1|yes|" "${start_rc}|$(has "herdr --version says 'herdr unknown'" "${start_out}")|$(order)"

# --- A resume command herdr would refuse: refused before any pane opens, naming why.
REFUSE="swarm: a1: herdr would refuse the command that resumes the agent after a restart:"
POLICY="claude o'pus high" start code
check "a flag with an apostrophe fails the start, naming it, before a pane opens" "1|yes|" \
  "${start_rc}|$(has "${REFUSE} --model o'pus has an apostrophe" "${start_out}")|$(order)"
POLICY=$'claude op\rus high' start code
check "a flag with a control character fails the start, naming it, before a pane opens" "1|yes|" \
  "${start_rc}|$(has "${REFUSE} --model has a control character" "${start_out}")|$(order)"
POLICY="claude $(printf 'm%.0s' $(seq 9000)) high" start code
check "a resume command over 8 KiB fails the start before a pane opens" "1|yes|" "${start_rc}|$(has "bytes, more than 8 KiB" "${start_out}")|$(order)"
check "more than 64 arguments are refused, and 64 pass" "65 arguments, more than 64|passes" "$(started refusal 65)|$(started refusal 64)"
A4K="$(printf 'a%.0s' $(seq 4096))"
check "8 KiB counts the command joined: 4096 + 4096 bytes and a separator is refused, 4096 + 4095 passes" \
  "8193 bytes, more than 8 KiB|passes" "$(started refusal-args "${A4K}" "${A4K}")|$(started refusal-args "${A4K}" "${A4K%a}")"

# --- herdr refuses the report: the agent, at work on its brief by then, is kept, and the start says so.
touch "${ROOT}/reportfail"; start code; rm -f "${ROOT}/reportfail"
check "a refused report keeps the agent at work, its pane open, and says the command was not recorded" \
  "0|yes|yes|pane opened|agent start|brief|pane report-agent" \
  "${start_rc}|$(has 'swarm: a1: herdr did not take the command that resumes the agent ({"error":{"code":"invalid_resume_argv"}}); the agent works on' "${start_out}")|$(
  has "a1 w:1 claude:opus:high" "${start_out}")|$(order)"

# --- The hooks. hook <event> <subject> <input> [unset] — run each command hooks.json gives <event>
# whose matcher finds <subject> (or that has none), as Claude Code would: through sh, with <input> on
# stdin (@S1@ in it the builder's session), CLAUDE_PLUGIN_ROOT this repo, in agent a1's session
# (SWARM_AGENT, and SWARM_RESUME a copy of the builder's resume command, fresh unless KEEP is set) in
# herdr pane w:9 (HERDR_PANE_ID), less the variable <unset> names; with SLOWPY set, the hook's first
# python3 takes a second. run_hooks does the same without clearing hook.log or waiting. The herdr stub
# logs its argv to hook.log, prints a result, fails while hookfail exists and sleeps 5 s while
# hookslow does. A hook's herdr runs in the background, so its line is waited for, up to a second.
# Sets got: what was logged (--seq shown as N), then what the hooks printed and their exit code; raw,
# what was logged; and took, their milliseconds.
HOOK_LOG="${ROOT}/hook.log"; REAL_PY="$(command -v python3)"
cat > "${ROOT}/herdr-bin" <<EOF
#!/bin/sh
echo "\$*" >> "${HOOK_LOG}"; echo '{"result":{}}'
[ ! -e "${ROOT}/hookslow" ] || sleep 5
[ ! -e "${ROOT}/hookfail" ] || exit 2
EOF
mkdir -p "${ROOT}/slowpy"
cat > "${ROOT}/slowpy/python3" <<EOF
#!/bin/sh
if [ -e "${ROOT}/slowpy-once" ]; then rm -f "${ROOT}/slowpy-once"; sleep 1; fi
exec "${REAL_PY}" "\$@"
EOF
chmod +x "${ROOT}/herdr-bin" "${ROOT}/slowpy/python3"
cp "${ROOT}/a1.argv" "${ROOT}/a1.argv.orig"
run_hooks() {
  local cmd v vars=() path="${PATH}"
  [[ -z "${SLOWPY:-}" ]] || { path="${ROOT}/slowpy:${PATH}"; touch "${ROOT}/slowpy-once"; }
  for v in CLAUDE_PLUGIN_ROOT="${REPO}" HERDR_BIN_PATH="${ROOT}/herdr-bin" HERDR_PANE_ID=w:9 SWARM_AGENT=a1 SWARM_RESUME="${ROOT}/a1.argv" PATH="${path}"; do
    [[ "${v%%=*}" == "${4:-}" ]] || vars+=("${v}")
  done
  while IFS= read -r cmd; do
    printed+="$(printf '%s' "${3//@S1@/${S1}}" | env -u SWARM_AGENT -u HERDR_PANE_ID -u SWARM_RESUME "${vars[@]}" sh -c "${cmd}")" || rc=$?
  done < <(python3 -c '
import json, re, sys
for entry in json.load(open(sys.argv[1]))["hooks"].get(sys.argv[2], []):
    if re.search(entry.get("matcher") or "", sys.argv[3]):
        for h in entry["hooks"]:
            print(h["command"])' "${REPO}/hooks/hooks.json" "$1" "$2")
}
hook() {
  local t0 i
  printed="" rc=0
  [[ -n "${KEEP:-}" ]] || cp "${ROOT}/a1.argv.orig" "${ROOT}/a1.argv"
  : > "${HOOK_LOG}"; t0="$(now_ms)"
  run_hooks "$@"
  took=$(($(now_ms) - t0))
  for ((i = 0; i < 10; i++)); do [[ ! -s "${HOOK_LOG}" ]] || break; sleep 0.1; done
  raw="$(cat "${HOOK_LOG}")"
  got="$(sed -E 's/--seq [0-9]+/--seq N/' <<< "${raw}")|${printed}|${rc}"
}
# as <state> <session> — what a hook reports for <state> in session <session>, with the resume command as it now stands.
as() { echo "pane report-agent --source swarm --agent claude --state $1 --seq N --agent-session-id $2 w:9 -- $(paste -sd' ' "${ROOT}/a1.argv")"; }
resumes() { sed -n '/^--resume$/{n;p;q;}' "${ROOT}/a1.argv"; }   # the session the resume command resumes
hook UserPromptSubmit "" '{"hook_event_name":"UserPromptSubmit","session_id":"@S1@","prompt":"go"}'
check "UserPromptSubmit reports working, with the resume command, printing nothing" "$(as working "${S1}")||0" "${got}"
seq1="$(sed -nE 's/.*--seq ([0-9]+).*/\1/p' <<< "${raw}")"
hook PostToolUse Bash '{"hook_event_name":"PostToolUse","session_id":"@S1@","tool_name":"Bash"}'
check "PostToolUse reports working, so an answered permission prompt no longer reads as blocked" "$(as working "${S1}")||0" "${got}"
seq2="$(sed -nE 's/.*--seq ([0-9]+).*/\1/p' <<< "${raw}")"
check "each report's --seq is later than start_agent's and than the one before" "yes" \
  "$( ((seq1 > $(cat "${ROOT}/brief-at") && seq2 > seq1)) && echo yes || echo "no: $(cat "${ROOT}/brief-at") ${seq1} ${seq2}")"
hook PostToolUse mcp__x__run '{"hook_event_name":"PostToolUse","session_id":"@S1@","tool_name":"mcp__x__run","tool_input":{"session_id":"t-in"},"tool_response":{"session_id":"t-out"}}'
check "the session is the input's own, never a session_id in a tool's input or response" "$(as working "${S1}")||0" "${got}"
hook Stop "" '{"hook_event_name":"Stop","session_id":"@S1@"}'
check "Stop reports idle" "$(as idle "${S1}")||0" "${got}"
hook StopFailure "" '{"hook_event_name":"StopFailure","session_id":"@S1@"}'
check "StopFailure (a turn that ended on an API error) reports idle" "$(as idle "${S1}")||0" "${got}"
hook Notification permission_prompt '{"hook_event_name":"Notification","session_id":"@S1@","notification_type":"permission_prompt"}'
check "a permission Notification reports blocked" "$(as blocked "${S1}")||0" "${got}"
hook Notification idle_prompt '{"hook_event_name":"Notification","session_id":"@S1@","notification_type":"idle_prompt"}'
check "an idle Notification reports nothing: the agent is idle, not blocked" "||0" "${got}"
# A working report whose seq is slow to come, then a blocked one: the blocked one still has the higher seq.
: > "${HOOK_LOG}"; printed="" rc=0; cp "${ROOT}/a1.argv.orig" "${ROOT}/a1.argv"
SLOWPY=1 run_hooks PostToolUse Bash '{"hook_event_name":"PostToolUse","session_id":"@S1@","tool_name":"Bash"}'
run_hooks Notification permission_prompt '{"hook_event_name":"Notification","session_id":"@S1@","notification_type":"permission_prompt"}'
for ((i = 0; i < 30; i++)); do [[ $(grep -c . "${HOOK_LOG}") -lt 2 ]] || break; sleep 0.1; done
sw="$(sed -nE 's/.*--state working --seq ([0-9]+).*/\1/p' "${HOOK_LOG}")"; sb="$(sed -nE 's/.*--state blocked --seq ([0-9]+).*/\1/p' "${HOOK_LOG}")"
check "a working report then a blocked one keep that order: the seq is taken before the call forks" "yes" \
  "$([[ -n "${sw}" && -n "${sb}" ]] && ((sb > sw)) && echo yes || echo "no: working ${sw:-none}, blocked ${sb:-none}")"
hook SessionStart clear '{"hook_event_name":"SessionStart","source":"clear","session_id":"s-new"}'
check "SessionStart on a cleared session moves the resume command to the new id and reports idle" "s-new|$(as idle s-new)||0" "$(resumes)|${got}"
KEEP=1 hook Stop "" '{"hook_event_name":"Stop","session_id":"@S1@"}'
check "after a clear, the old session reports nothing: it is no longer the pane's" "||0" "${got}"
KEEP=1 hook Stop "" '{"hook_event_name":"Stop","session_id":"s-new"}'
check "and the new one reports, under its own id" "$(as idle s-new)||0" "${got}"
hook SessionStart resume '{"hook_event_name":"SessionStart","source":"resume","session_id":"@S1@"}'
check "SessionStart on the pane's session resumed (after a restart) reports idle" "$(as idle "${S1}")||0" "${got}"
hook SessionStart startup '{"hook_event_name":"SessionStart","source":"startup","session_id":"@S1@"}'
check "SessionStart on startup reports nothing: start_agent reports once the brief is taken up" "||0" "${got}"
# A nested `claude -p` the agent runs from Bash: the same SWARM_AGENT, HERDR_PANE_ID and SWARM_RESUME,
# its own session.
for ev in 'UserPromptSubmit||{"hook_event_name":"UserPromptSubmit","session_id":"child-1","prompt":"x"}' \
  'Stop||{"hook_event_name":"Stop","session_id":"child-1"}' \
  'SessionStart|startup|{"hook_event_name":"SessionStart","source":"startup","session_id":"child-1"}' \
  'SessionStart|resume|{"hook_event_name":"SessionStart","source":"resume","session_id":"child-1"}' \
  'SessionEnd|prompt_input_exit|{"hook_event_name":"SessionEnd","session_id":"child-1","reason":"prompt_input_exit"}'; do
  IFS='|' read -r e sub in <<< "${ev}"
  hook "${e}" "${sub}" "${in}"
  check "a nested session's ${e}${sub:+ (${sub})} reports nothing and leaves the resume command at the agent's session" "||0|${S1}" "${got}|$(resumes)"
done
hook SessionEnd prompt_input_exit '{"hook_event_name":"SessionEnd","session_id":"@S1@","reason":"prompt_input_exit"}'
check "SessionEnd on a quit releases the pane" "pane release-agent --source swarm --agent claude --seq N w:9||0" "${got}"
hook SessionEnd other '{"hook_event_name":"SessionEnd","session_id":"@S1@","reason":"other"}'
check "SessionEnd as the pane dies (a herdr restart) releases nothing, keeping the resume command" "||0" "${got}"
hook Stop "" '{"hook_event_name":"Stop"}'
check "a report with no session id reports nothing: it cannot be told from a nested session's" "||0" "${got}"
hook Stop "" '{"hook_event_name":"Stop","session_id":"@S1@"}' SWARM_RESUME
check "with no resume command recorded, nothing reports: the pane's session is not known" "||0" "${got}"
hook UserPromptSubmit "" '{"hook_event_name":"UserPromptSubmit","session_id":"@S1@","prompt":"go"}' SWARM_AGENT
check "outside a swarm agent's session (no SWARM_AGENT), the hooks report nothing" "||0" "${got}"
hook Stop "" '{"hook_event_name":"Stop","session_id":"@S1@"}' HERDR_PANE_ID
check "outside a herdr pane, the hooks report nothing" "||0" "${got}"
touch "${ROOT}/hookfail"; hook UserPromptSubmit "" '{"hook_event_name":"UserPromptSubmit","session_id":"@S1@","prompt":"go"}'; rm -f "${ROOT}/hookfail"
check "a herdr that fails never fails the hook, which would block the prompt" "$(as working "${S1}")||0" "${got}"
touch "${ROOT}/hookslow"; hook UserPromptSubmit "" '{"hook_event_name":"UserPromptSubmit","session_id":"@S1@","prompt":"go"}'; rm -f "${ROOT}/hookslow"
check "a herdr that hangs holds no prompt: the hook returns at once, its call made" \
  "$(as working "${S1}")||0|fast" "${got}|$( ((took < 2000)) && echo fast || echo "${took} ms")"
check "every state hook has a timeout of at most 10 seconds" "" "$(python3 -c '
import json, sys
for event, entries in json.load(open(sys.argv[1]))["hooks"].items():
    for e in entries:
        for h in e["hooks"]:
            if "agent-state.sh" in h["command"] and not 0 < h.get("timeout", 0) <= 10:
                print(event)' "${REPO}/hooks/hooks.json")"

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
