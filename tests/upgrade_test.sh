#!/usr/bin/env bash
# upgrade_test.sh — swarm.sh upgrade <epic> moves a running epic's agents to this version: it asks
# the idle conductor for a handover first, then restarts each idle builder and last the conductor in
# its own pane: ctrl+c twice at once, a clean environment whose PATH starts at this version's bin (an
# older version's root gone, a shared folder kept), and herdr agent start --resume <herdr's session>
# with the flags its claude ran with (--session-id or an older --resume dropped; an npm install's
# node .../claude-code/cli.js too), in a project whose path holds a space. It tells each the new
# swarm.sh path, and the conductor to carry on. A dirty worktree is left as it was. A busy builder is never sent a key: idle ones after it go first, it is
# restarted once idle, and one still busy at the end of the wait is named as left on its old
# version. One whose session is gone, or whose pane herdr no longer lists, is skipped as closed:
# named once on a skipped (closed) line, never touched, and counted neither moved nor left. An agent whose newest record is codex is
# left alone. One that cannot be told the new path stays on its old version; a restart that fails once
# claude has exited says how to resume it; a second run skips the agents already on this version. A
# busy conductor gets the request in its inbox. A conductor already on this version is paused while
# its builders restart, then told to carry on; builders it starts before the handover are restarted
# too. A conductor whose env: names are refused is asked
# for nothing; one with no handover by the end of the wait, or still busy after writing it, gets a
# note (a prompt when idle) to carry on as before, and is named; either way its builders are held.
# upgrade backlog moves the backlog conductor and the stories with no epic. Round 3: idle is read
# from the pane's current session; each restarted agent's resume command goes to herdr and it hears
# its background commands were stopped; unreadable process-info leaves an agent alone; a claude
# that ignores ctrl+c gets the resume hint; a conductor whose restart fails before its claude exits
# is told to carry on; one whose session goes after the request is named at once; the conductor
# hears which builders were restarted, which left and which were skipped as closed. Rounds: a busy conductor asked in its inbox is
# asked again by prompt once idle, and its late handover still moves it and its builders. Without
# --foreground upgrade runs detached, outlives the shell that started it, is named by a second
# upgrade (which starts nothing) and by status, and moves a builder busy at first once it is idle;
# every run ends on one line per agent. A conductor skipped as closed after its handover stays skipped
# on a TERM, told nothing. A builder whose Claude review agent is busy waits for it; one
# still busy at the end is named, and so is its builder, for it; one skipped as closed holds nothing,
# whatever Claude Code's list reads at the hold. docs/reference*.md and
# commands/swarm.md describe it. An empty version record reads as unknown, and no message file is
# left behind. claude agents --json is a stub printing ${H}/claude.json; with
# ${H}/flip ("<n> <sed expression>"), its calls after the n-th print it through the expression, and
# then through ${H}/flip2's, the same way.
# herdr is a stub on PATH: agent list reads ${H}/agents ("<name> <pane> <session>" lines), agent wait
# says idle at once, process-info shows ${H}/argv-<pane> (in folder "${H}/wt <pane>") until one
# send-keys sends ctrl+c twice (then a shell), agent start reads a line of its stdin, brings claude back, runs
# ${H}/onstart-<name> if there is one (an agent whose session is - has none; process-info fails
# while ${H}/pifail exists, and claude ignores ctrl+c while ${H}/noexit does), pane run keeps the launch file it runs as ${H}/launch-<pane>,
# pane wait-output fails while ${H}/envfail exists, and an agent prompt asking for a handover writes
# its file (not while ${H}/nohandover exists) and runs ${H}/onhandover if there is one; agent start
# hangs while ${H}/slowstart exists; agent list fails three times once ${H}/listfail exists, and
# always while ${H}/listdown does, and once while ${H}/listfail1 does; agent list runs ${H}/onlist once, after printing, once the claude
# stub's call numbered in ${H}/arm has made ${H}/armed (each claude call logs "claude <n>"); a prompt
# telling an agent it was restarted fails while ${H}/promptfail exists, and one telling it upgrade could not
# restart it while ${H}/sayfail does. Every call is logged.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWARM="${REPO}/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
H="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${H}"' EXIT
export CLAUDE_CONFIG_DIR="${H}/claude-config" CLAUDE_PROJECTS_DIR="${H}/claude-config/projects"
P="${H}/my proj"; LOG="${H}/herdr.log"
NEW="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "${REPO}/.claude-plugin/plugin.json")"
mkdir -p "${P}/docs/epics" "${P}/docs/stories" "${P}/.swarm/state" "${P}/.swarm/versions" "${H}/bin" "${H}/old/0.21.0/bin"
# An older version's root, and a shared folder that holds a swarm.sh link among other tools.
mkdir -p "${H}/old/0.21.0/.claude-plugin" "${H}/shared"; echo '{"version":"0.21.0"}' > "${H}/old/0.21.0/.claude-plugin/plugin.json"
for d in "${H}/old/0.21.0/bin" "${H}/shared"; do printf '#!/bin/sh\n' > "${d}/swarm.sh"; chmod +x "${d}/swarm.sh"; done
GIT=(git -c user.name=t -c user.email=t@t)
git -C "${P}" init -q
printf -- '---\nstatus: active\n---\n\n# e\n' > "${P}/docs/epics/e.md"
for s in b1 b2; do printf -- '---\nkind: code\nstatus: ready\nepic: e\n---\n\n# %s\n' "${s}" > "${P}/docs/stories/${s}.md"; done
printf -- '---\nkind: code\nstatus: ready\nepic: other\n---\n\n# x1\n' > "${P}/docs/stories/x1.md"
"${GIT[@]}" -C "${P}" add -A && "${GIT[@]}" -C "${P}" commit -qm init
# Untracked, as a project's config is: every restarted agent gets PROVIDER_KEY (agent_env).
mkdir -p "${P}/.claude/swarm"; echo "agent_env = PROVIDER_KEY" > "${P}/.claude/swarm/config"

# b1's worktree, with a commit, an uncommitted change and an untracked file.
WT="${P}-wt/b1"
"${GIT[@]}" -C "${P}" worktree add -q -b story/b1 "${WT}"
echo work > "${WT}/f"; "${GIT[@]}" -C "${WT}" add f && "${GIT[@]}" -C "${WT}" commit -qm b1
echo dirty >> "${WT}/f"; echo new > "${WT}/untracked"
tree_state() { git -C "${WT}" rev-parse HEAD; git -C "${WT}" status --porcelain; cat "${WT}/f" "${WT}/untracked"; }
BEFORE="$(tree_state)"

# A project whose path holds a space. A conductor and two builders of epic e (b1 recorded under s0,
# its session before a /clear; herdr has s1 in its pane now), and x1's builder of another epic.
printf 'w:c conduct-e\nw:b1 b1\nw:b2 b2\nw:x1 x1\nw:r review-b1\n' > "${P}/.swarm/state/e"
printf '%s\n' $'2026-10-20\tconduct\tconduct-e\tclaude\topus\thigh\tsc' $'2026-10-20\tcode\tb1\tclaude\tsonnet\thigh\ts0' \
  $'2026-10-20\tcode\tb2\tclaude\tsonnet\thigh\ts2' $'2026-10-20\tcode\tx1\tclaude\tsonnet\thigh\tsx' \
  $'2026-10-20\treview\treview-b1\tclaude\tsonnet\thigh\tsr' $'2026-10-21\treview\treview-b1\tcodex\tdefault\thigh\t-' > "${P}/.swarm/agents.tsv"   # review-b1 is codex now
printf 'conduct-e w:c sc\nb1 w:b1 s1\nb2 w:b2 s2\nx1 w:x1 sx\nreview-b1 w:r -\n' > "${H}/agents"
for n in conduct-e b1 b2 x1; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
argv() { printf '%s\n' "${CMD[@]}" --model "$2" --effort high "${@:3}" --permission-mode auto --disallowedTools 'Bash(gh pr merge:*)' --settings "{\"env\":{\"SWARM_AGENT\":\"$1\"}}"; }
CMD=(claude)
argv conduct-e opus --session-id sc > "${H}/argv-w:c"
argv b1 sonnet --session-id s1 > "${H}/argv-w:b1"
CMD=(node /usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js)   # an npm install's claude
argv b2 sonnet --resume s2 > "${H}/argv-w:b2"   # brought back by herdr once already
CMD=(claude)
argv x1 sonnet --session-id sx > "${H}/argv-w:x1"

printf '#!/bin/sh\nH="%s"\n' "${H}" > "${H}/bin/herdr"
cat >> "${H}/bin/herdr" <<'STUB'
[ "$1" = --version ] && { echo "herdr 0.9.5"; exit 0; }
{ for a in "$@"; do printf '%s ' "$a"; done; echo; } >> "$H/herdr.log"
case "$1 $2" in
  "agent list") [ ! -e "$H/listdown" ] || exit 1
                [ ! -e "$H/listfail1" ] || { rm -f "$H/listfail1"; exit 1; }
                if [ -e "$H/listfail" ]; then   # fails three times, then is gone
                  n=$(($(cat "$H/listfail.count" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/listfail.count"
                  [ "$n" -lt 3 ] || rm -f "$H/listfail" "$H/listfail.count"; exit 1; fi
                awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                     { printf "%s{\"name\":\"%s\",\"pane_id\":\"%s\",\"agent_status\":\"idle\"%s}", (NR > 1 ? "," : ""), $1, $2, ($3 == "-" ? "" : ",\"agent_session\":{\"value\":\"" $3 "\"}") }
                     END { print "]}}" }' "$H/agents"
                [ ! -e "$H/armed" ] || [ ! -x "$H/onlist" ] || { rm -f "$H/armed"; "$H/onlist"; } ;;   # after the list it printed
  "agent wait") echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "pane process-info") p="$4"; [ -e "$H/pifail" ] && exit 1
                if [ -e "$H/exited-$p" ]; then echo '{"result":{"process_info":{"foreground_processes":[{"argv":["zsh"]}]}}}'
                else python3 -c 'import json, sys; print(json.dumps({"result": {"process_info": {"foreground_processes": [{"argv": open(sys.argv[1]).read().splitlines(), "cwd": sys.argv[2]}]}}}))' "$H/argv-$p" "$H/wt $p"; fi ;;
  "pane send-keys") p="$3"; n=0; shift 3; for k in "$@"; do [ "$k" = ctrl+c ] && n=$((n + 1)); done
                    [ "$n" -lt 2 ] || [ -e "$H/noexit" ] || touch "$H/exited-$p" ;;   # claude exits on a second ctrl+c at once
  "pane wait-output") [ -e "$H/envfail" ] && exit 1 ;;
  "pane run") p="$3"; eval "set -- $4"; for f; do :; done; cp "$f" "$H/launch-$p" ;;   # the launch file, its last word
  "agent start") read -r -t 1 _ 2>/dev/null || true   # takes a line of its stdin, as a real command may
                 i=0; while [ -e "$H/slowstart" ] && [ "$i" -lt 600 ]; do sleep 0.1; i=$((i + 1)); done
                 n="$3"; shift 2; while [ "$1" != --pane ]; do shift; done; rm -f "$H/exited-$2"
                 [ ! -x "$H/onstart-$n" ] || "$H/onstart-$n" ;;
  "agent prompt") case "$4" in *"restarted you on"*) [ -e "$H/promptfail" ] && exit 1 ;; *"could not restart you"*) [ -e "$H/sayfail" ] && exit 1 ;; esac
                  f="$(printf '%s' "$4" | grep -o '/[^:]*/\.swarm/handover-[^ :]*\.md' | head -1)"
                  case "$4" in *"Write a handover"*) [ -e "$H/nohandover" ] || [ -z "$f" ] || echo "PRs and rounds" > "$f"
                                                     [ ! -x "$H/onhandover" ] || "$H/onhandover" ;; esac
                  echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
esac
exit 0
STUB
chmod +x "${H}/bin/herdr"
printf '#!/bin/sh\nH="%s"\n' "${H}" > "${H}/bin/claude"
cat >> "${H}/bin/claude" <<'STUB'
[ "$*" = "agents --json" ] || { echo "claude stub: unexpected call: $*" >&2; exit 1; }
n=$(($(cat "$H/claude.count" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/claude.count"
echo "claude $n" >> "$H/herdr.log"
[ "$n" != "$(cat "$H/arm" 2>/dev/null)" ] || touch "$H/armed"
j="$(cat "$H/claude.json")"
[ ! -e "$H/flip" ] || [ "$n" -le "$(cut -d' ' -f1 "$H/flip")" ] || j="$(printf '%s' "$j" | sed "$(cut -d' ' -f2- "$H/flip")")"
[ ! -e "$H/flip2" ] || [ "$n" -le "$(cut -d' ' -f1 "$H/flip2")" ] || j="$(printf '%s' "$j" | sed "$(cut -d' ' -f2- "$H/flip2")")"
printf '%s\n' "$j"
STUB
chmod +x "${H}/bin/claude"
claude_list() { printf '[{"sessionId":"sc","status":"%s"},{"sessionId":"s1","status":"%s"},{"sessionId":"s2","status":"%s"},{"sessionId":"s0","status":"idle"}]\n' "$@" > "${H}/claude.json"; rm -f "${H}/flip" "${H}/flip2"; }
claude_list idle idle idle

mkdir -p "${H}/tmp"
ENVV=(TMPDIR="${H}/tmp" SWARM_PROJECT="${P}" PROVIDER_KEY=provider-key HERDR_ENV=1 HERDR_PANE_ID=w:lead SWARM_SLEEP_SCALE=0.01 PATH="${H}/bin:${H}/old/0.21.0/bin:${H}/shared:${PATH}")
upgrade() { # [epic] — run upgrade --foreground from the project, its output in ${H}/out and exit code in rc
  : > "${LOG}"; rc=0; rm -f "${H}/claude.count" "${P}/.swarm/inbox/conduct-e.md"
  (cd "${P}" && env "${ENVV[@]}" SWARM_UPGRADE_GRACE_MS="${GRACE_MS:-200}" SWARM_UPGRADE_WAIT_MS="${WAIT_MS:-60000}" \
    bash "${SWARM}" upgrade "$@" --foreground > "${H}/out" 2>&1) || rc=$?
}

fails=0
check() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }
calls() { grep -E "^$1 " "${LOG}" || true; }
order() { awk '/^agent prompt/ { print "prompt " $3 } /^pane send-keys/ { print "keys " $3 } /^agent start/ { print "start " $3 }' "${LOG}" | paste -sd'|' -; }

upgrade e
check "upgrade e succeeds" "0" "${rc}"
n="$(grep -c '^agent list' "${LOG}")"   # 19 when each agent's pane was its own herdr read
check "herdr's agent list is read once a round, not once an agent" "yes" "$( ((n <= 8)) && echo yes || echo "no, ${n} reads")"
HANDOVER="$(ls "${P}"/.swarm/handover-e-*.md 2>/dev/null || true)"
check "the conductor wrote its handover, as asked, to .swarm/handover-e-<date>.md" "${P}/.swarm/handover-e-$(date +%F).md|PRs and rounds" \
  "${HANDOVER}|$(cat "${HANDOVER}" 2>/dev/null)"
check "handover first, then each builder and last the conductor, each told the new path once restarted" \
  "prompt w:c|keys w:b1|start b1|prompt w:b1|keys w:b2|start b2|prompt w:b2|keys w:c|start conduct-e|prompt w:c" "$(order)"
check "each restarted agent is told this version's swarm.sh path, the conductor its handover too" "3|yes" \
  "$(calls 'agent prompt' | grep -c "Its swarm.sh is ${REPO}/bin/swarm.sh: use that path")|$(has "Your handover is ${HANDOVER}. Builders restarted on swarm-dev ${NEW}: b1 b2. Left on their old version: none. Carry on" "$(calls 'agent prompt w:c')")"
check "b1 restarts with --resume of herdr's session and its launch flags, no --session-id" \
  "agent start b1 --kind claude --pane w:b1 --timeout 60000 -- --resume s1 --model sonnet --effort high --permission-mode auto --disallowedTools Bash(gh pr merge:*) --settings {\"env\":{\"SWARM_AGENT\":\"b1\"}} " \
  "$(calls 'agent start b1')"
check "b2, an npm install brought back once already, restarts with one --resume and its flags" \
  "yes|1" "$(has '-- --resume s2 --model sonnet --effort high --permission-mode' "$(calls 'agent start b2')")|$(calls 'agent start b2' | grep -o -- '--resume' | grep -c .)"
check "the conductor restarts with --resume too" "yes" "$(has '-- --resume sc --model opus' "$(calls 'agent start conduct-e')")"
check "another epic's builder, and an agent whose newest record is codex, are left alone" "" "$(grep -E 'w:x1|x1 |w:r|review-b1' "${LOG}" | grep -v '^agent list' || true)"
check "each restart's PATH starts at this version's bin, an older version's root gone, a shared folder kept" "yes|0|1" \
  "$(has "export PATH=$(printf %q "${REPO}/bin"):" "$(cat "${H}/launch-w:b1")")|$(grep -c 'old/0.21.0' "${H}/launch-w:b1" || true)|$(grep -c "${H}/shared" "${H}/launch-w:b1" || true)"
check "the resume command is this version's, with --resume" "yes" \
  "$(has $'claude\n--resume\ns1\n--model' "$(cat "${CLAUDE_CONFIG_DIR}/swarm-dev/resume/s1.argv")")"
check "herdr gets each restarted agent's resume command, as at its start" "yes" \
  "$(has "pane report-agent w:b1 --source swarm --agent claude --state idle --seq" "$(calls 'pane report-agent w:b1')")"
check "and that command resumes its session with its flags" "yes" \
  "$(has "--agent-session-id s1 -- python3 -I ${CLAUDE_CONFIG_DIR}/swarm-dev/resume/s1.py claude --resume s1 --model sonnet" "$(calls 'pane report-agent w:b1')")"
check "each restarted agent is told its background commands, subagents and monitors were stopped" "3" "$(calls 'agent prompt' | grep -c 'stopped any background command, subagent or monitor')"
# Why agent_env exists: agents on Azure Foundry (or another provider) need its endpoint, key and
# model names (ANTHROPIC_FOUNDRY_RESOURCE, ANTHROPIC_FOUNDRY_API_KEY, ANTHROPIC_DEFAULT_*_MODEL) in
# every pane, not only builders'; without them every agent stops at its start. Boards outside
# swarm-dev and infrafactory set it, so finding it unset in those two configs is no reason to remove it.
# An upgrade restart must keep them, or a Foundry agent stops when swarm.sh upgrade restarts it.
check "agent_env's names reach the restarted agent, and its restart wrapper keeps them" "yes|yes" \
  "$(has "export PROVIDER_KEY=provider-key" "$(cat "${H}/launch-w:b1")")|$(has "'PROVIDER_KEY'" "$(cat "${CLAUDE_CONFIG_DIR}/swarm-dev/resume/s1.py")")"
check "SWARM_RESUME reaches the restarted agent" "yes" "$(has "export SWARM_RESUME=$(printf %q "${CLAUDE_CONFIG_DIR}/swarm-dev/resume/s1.argv")" "$(cat "${H}/launch-w:b1")")"
check "it prints each agent's old and new version" "b1: 0.21.0 -> ${NEW}|b2: 0.21.0 -> ${NEW}|conduct-e: 0.21.0 -> ${NEW}" \
  "$(grep -- ' -> ' "${H}/out" | paste -sd'|' -)"
check "the dirty worktree is as it was" "${BEFORE}" "$(tree_state)"

# --- Both builders back on their old version, b1 busy past the wait, as Claude Code says though herdr
# has it idle: b1 is named, left on it and never sent a key; idle b2 after it is still restarted.
echo 0.21.0 > "${P}/.swarm/versions/b1"; echo 0.21.0 > "${P}/.swarm/versions/b2"; claude_list idle busy idle
WAIT_MS=200 upgrade e
check "a run with an agent left fails" "1" "${rc}"
check "the busy builder is never interrupted or restarted; the idle builder after it is" "pane send-keys w:b2 ctrl+c ctrl+c |b2" \
  "$(calls 'pane send-keys' | paste -sd'|' -)|$(calls 'agent start' | cut -d' ' -f3)"
check "it is named as left on its old version" "yes" "$(has 'b1: left on 0.21.0: still busy at the end of the wait' "$(cat "${H}/out")")"
check "the conductor already on this version is paused for the restarts, then told to carry on, never restarted" "1|1|yes|" \
  "$(calls 'agent prompt w:c' | grep -c 'Write a handover')|$(calls 'agent prompt w:c' | grep -c "Builders restarted on swarm-dev ${NEW}: b2. Left on their old version: b1.")|$(has "conduct-e: already on ${NEW}, told to carry on" "$(cat "${H}/out")")|$(calls 'pane send-keys w:c')"
check "b1's version is still the old one" "0.21.0" "$(cat "${P}/.swarm/versions/b1")"
check "the tally counts b2 as moved, not the conductor only told to carry on" "upgrade done: 1 moved, 1 left (exit 1)" "$(tail -1 "${H}/out")"

# --- b1 reads busy (background shells), but its log says its turn is over: restarted, and told to
# start its background commands again. A log ending in a tool call with no result, and a session
# waiting on a prompt, stay busy and are left alone.
LOGDIR="${CLAUDE_PROJECTS_DIR}/p"; mkdir -p "${LOGDIR}"
entry() { printf '{"type":"assistant","message":{"model":"m","stop_reason":"%s","content":[{"type":"%s"}]}}\n' "$1" "$2"; }
entry end_turn text > "${LOGDIR}/s1.jsonl"; printf '{"type":"system","subtype":"turn_duration"}\n' >> "${LOGDIR}/s1.jsonl"
echo 0.21.0 > "${P}/.swarm/versions/b1"; echo 0.21.0 > "${P}/.swarm/versions/b2"; claude_list idle busy idle
upgrade e
check "a busy session whose turn ended is restarted and told its background commands stopped" "0|keys w:b1|start b1|prompt w:b1" \
  "${rc}|$(order | tr '|' '\n' | grep -E '(keys|start|prompt) w?:?b1|w:b1' | paste -sd'|' -)"
check "it is told its background commands were stopped" "1" "$(calls 'agent prompt w:b1' | grep -c 'stopped any background command, subagent or monitor')"
entry tool_use tool_use > "${LOGDIR}/s1.jsonl"
echo 0.21.0 > "${P}/.swarm/versions/b1"; echo 0.21.0 > "${P}/.swarm/versions/b2"
WAIT_MS=200 upgrade e
check "a log ending in a tool call with no result is busy, and b1 is left alone" "pane send-keys w:b2 ctrl+c ctrl+c " "$(calls 'pane send-keys')"
entry end_turn text > "${LOGDIR}/s1.jsonl"; claude_list idle waiting idle
echo 0.21.0 > "${P}/.swarm/versions/b1"; echo 0.21.0 > "${P}/.swarm/versions/b2"
WAIT_MS=200 upgrade e
check "a session waiting on a prompt is left alone, its log aside" "pane send-keys w:b2 ctrl+c ctrl+c " "$(calls 'pane send-keys')"
entry end_turn text > "${LOGDIR}/s1.jsonl"; printf '{"type":"user","isMeta":true,"message":{"role":"user","content":"A scheduled prompt."}}\n' >> "${LOGDIR}/s1.jsonl"; claude_list idle busy idle
echo 0.21.0 > "${P}/.swarm/versions/b1"; echo 0.21.0 > "${P}/.swarm/versions/b2"
WAIT_MS=200 upgrade e
check "a scheduled prompt after the ended turn starts a new one: b1 is busy and left alone" "pane send-keys w:b2 ctrl+c ctrl+c " "$(calls 'pane send-keys')"
entry tool_use tool_use > "${LOGDIR}/s1.jsonl"; entry end_turn text | sed 's/^{/{"isSidechain":true,/' >> "${LOGDIR}/s1.jsonl"; claude_list idle busy idle
echo 0.21.0 > "${P}/.swarm/versions/b1"; echo 0.21.0 > "${P}/.swarm/versions/b2"
WAIT_MS=200 upgrade e
check "a subagent's ended turn after the parent's tool call is not the session's: b1 is busy and left alone" "pane send-keys w:b2 ctrl+c ctrl+c " "$(calls 'pane send-keys')"
rm -rf "${LOGDIR}"

# --- Both back on their old version, b1 busy for Claude Code's first reads: idle b2 goes first, and
# b1 is waited for and restarted once idle.
echo 0.21.0 > "${P}/.swarm/versions/b1"; echo 0.21.0 > "${P}/.swarm/versions/b2"; claude_list idle busy idle
printf '#!/bin/sh\nsed -i.bak "s/busy/idle/" "%s"\n' "${H}/claude.json" > "${H}/onstart-b2"; chmod +x "${H}/onstart-b2"   # b1 goes idle once b2 is back
upgrade e
check "the busy builder is waited for, the idle one restarted first, and both are restarted" "0|prompt w:c|keys w:b2|start b2|prompt w:b2|keys w:b1|start b1|prompt w:b1|prompt w:c" \
  "${rc}|$(order)"
rm -f "${H}/onstart-b2"

# --- A restarted builder that cannot be told the new path stays on its old version, for a second run.
echo 0.21.0 > "${P}/.swarm/versions/b2"; claude_list idle idle idle; touch "${H}/promptfail"
echo "${NEW}" > "${P}/.swarm/versions/b1"
WAIT_MS=200 upgrade e
check "the run fails, and b2 is still on its old version" "1|0.21.0" "${rc}|$(cat "${P}/.swarm/versions/b2")"
check "the message file of the failed tell is gone" "" "$(find "${H}/tmp" -name 'swarm-upgrade.*')"
rm -f "${H}/promptfail"

# --- A restart that fails once claude has exited (the clean shell never comes) says how to resume it.
touch "${H}/envfail"
upgrade e
check "the failed restart keeps the pane and names the session and folder to resume it in" "1|yes|" \
  "${rc}|$(has "b2: not started again; if pane w:b2 shows a shell, claude --resume s2, run in ${H}/wt w:b2, brings the session back" "$(cat "${H}/out")")|$(calls 'pane close')"
check "and its summary line carries that resume hint" "1" \
  "$(grep -c "^b2: left on 0.21.0: .*; not started again; if pane w:b2 shows a shell, claude --resume s2, run in ${H}/wt w:b2, brings the session back$" "${H}/out")"
rm -f "${H}/envfail" "${H}/exited-w:b2"   # b2 resumed by hand, as the hint says

# --- process-info that cannot be read leaves the agent alone; a claude that ignores ctrl+c gets the resume hint.
echo 0.21.0 > "${P}/.swarm/versions/b2"; claude_list idle idle idle; touch "${H}/pifail"
upgrade e
check "with process-info unreadable b2 is named and sent no key" "1|yes|" \
  "${rc}|$(has 'b2: herdr pane process-info could not be read, so it is left as it is' "$(cat "${H}/out")")|$(calls 'pane send-keys w:b2')"
rm -f "${H}/pifail"; touch "${H}/noexit"
upgrade e
check "a claude that does not exit is named, with the resume hint" "1|yes|yes" \
  "${rc}|$(has 'b2: claude did not exit on ctrl+c, left on 0.21.0' "$(cat "${H}/out")")|$(has 'b2: not started again; if pane w:b2 shows a shell, claude --resume s2' "$(cat "${H}/out")")"
rm -f "${H}/noexit"

# --- Of three agents, b1's Claude session is gone: it is skipped as closed before the first round,
# named once, never waited on, sent a key or restarted, and counted neither moved nor left; the
# other two are restarted and the run succeeds.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
echo '[{"sessionId":"sc","status":"idle"},{"sessionId":"s2","status":"idle"}]' > "${H}/claude.json"
upgrade e
check "a gone session is skipped as closed, named once, and the other two restart" "0|1|1|start b2|start conduct-e" \
  "${rc}|$(grep -cx 'skipped (closed): b1' "${H}/out")|$(grep -c 'skipped (closed)' "${H}/out")|$(order | tr '|' '\n' | grep '^start' | paste -sd'|' -)"
check "b1 is sent no key and no wait, has no line of its own, and counts neither moved nor left" "|0|upgrade done: 2 moved, 0 left (exit 0)" \
  "$(calls 'pane send-keys w:b1'; calls 'agent wait w:b1')|$(grep -c '^b1: ' "${H}/out")|$(tail -1 "${H}/out")"
check "its conductor is told b1 was skipped as closed" "1" "$(calls 'agent prompt w:c' | grep -c 'Skipped as closed: b1\. Carry on')"
# One whose session goes after the check, before its round reaches it, is skipped too, not left.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
claude_list idle idle idle; echo '1 s/{"sessionId":"s1","status":"idle"},//' > "${H}/flip"
upgrade e
check "a session gone by its round is skipped as closed, not left" "0|1|0|upgrade done: 2 moved, 0 left (exit 0)" \
  "${rc}|$(grep -cx 'skipped (closed): b1' "${H}/out")|$(calls 'agent start b1' | grep -c .)|$(tail -1 "${H}/out")"

# A conductor whose session is gone at the check is skipped before it is asked: no prompt, no note,
# and its builders, with no conductor to pause, are restarted.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
echo '[{"sessionId":"s1","status":"idle"},{"sessionId":"s2","status":"idle"}]' > "${H}/claude.json"; rm -f "${H}/flip" "${H}/flip2"
upgrade e
check "a gone conductor is skipped as closed, never asked, and its builders move" "0|1||no|start b1|start b2|upgrade done: 2 moved, 0 left (exit 0)" \
  "${rc}|$(grep -cx 'skipped (closed): conduct-e' "${H}/out")|$(calls 'agent prompt w:c')|$(grep -qs 'Write a handover' "${P}/.swarm/inbox/conduct-e.md" && echo yes || echo no)|$(order | tr '|' '\n' | grep '^start' | paste -sd'|' -)|$(tail -1 "${H}/out")"

# One idle at its round's read whose session is gone by the restart's own idle check (Claude Code's
# 6th read, after the check's, two for the conductor's request, its handover's and b1's round read)
# is skipped too, not left.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
claude_list idle idle idle; echo '5 s/{"sessionId":"s1","status":"idle"},//' > "${H}/flip"
upgrade e
check "a session gone by its restart is skipped as closed, not left" "0|1|0|upgrade done: 2 moved, 0 left (exit 0)" \
  "${rc}|$(grep -cx 'skipped (closed): b1' "${H}/out")|$(calls 'pane send-keys w:b1' | grep -c .)|$(tail -1 "${H}/out")"

# --- b2's pane is closed (herdr lists no agent b2, though its tab record and agents.tsv name it): it
# is named in skipped (closed), never waited on, sent a key or restarted, and not counted as left.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
claude_list idle idle idle; cp "${H}/agents" "${H}/agents.keep"; sed -i.bak '/^b2 /d' "${H}/agents"
upgrade e
check "a closed pane is named, never touched, and the run succeeds" "0|1|||upgrade done: 2 moved, 0 left (exit 0)" \
  "${rc}|$(grep -cx 'skipped (closed): b2' "${H}/out")|$(calls 'pane send-keys w:b2'; calls 'agent wait w:b2'; calls 'agent start b2')|$(grep '^b2: ' "${H}/out" || true)|$(tail -1 "${H}/out")"
check "its conductor is told b2 was skipped as closed" "1" "$(calls 'agent prompt w:c' | grep -c 'Skipped as closed: b2\. Carry on')"
# A herdr list that cannot be read before the first round names nobody as closed, and says so.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
touch "${H}/listfail1"
upgrade e
rm -f "${H}/listfail1"; cp "${H}/agents.keep" "${H}/agents"
check "an unread list skips nobody and says it was not read" "0|0|1|yes" \
  "${rc}|$(grep -c 'skipped (closed)' "${H}/out")|$(grep -cx "herdr's agent list could not be read before the first round, so the closed check did not run" "${H}/out")|$(has "b1: 0.21.0 -> ${NEW}" "$(cat "${H}/out")")"

# --- A builder the conductor starts before it writes its handover is restarted too.
printf -- '---\nkind: code\nstatus: ready\nepic: e\n---\n\n# b4\n' > "${P}/docs/stories/b4.md"
echo 0.21.0 > "${P}/.swarm/versions/conduct-e"; claude_list idle idle idle; echo "${NEW}" > "${P}/.swarm/versions/b1"
CMD=(claude); argv b4 sonnet --session-id s4 > "${H}/argv-w:b4"
cat > "${H}/onhandover" <<EOF
#!/bin/sh
echo "b4 w:b4 s4" >> "${H}/agents"; echo "w:b4 b4" >> "${P}/.swarm/state/e"; echo 0.21.0 > "${P}/.swarm/versions/b4"
printf '2026-10-22\tcode\tb4\tclaude\tsonnet\thigh\ts4\n' >> "${P}/.swarm/agents.tsv"
sed -i.bak 's/]\$/,{"sessionId":"s4","status":"idle"}]/' "${H}/claude.json"
EOF
chmod +x "${H}/onhandover"
upgrade e
check "the new builder is restarted with the rest" "0|yes|yes" \
  "${rc}|$(has 'agent start b4 --kind claude --pane w:b4' "$(calls 'agent start b4')")|$(has "b4: 0.21.0 -> ${NEW}" "$(cat "${H}/out")")"
rm -f "${H}/onhandover"

# --- herdr lists no session for b1 (herdr 0.9.5 lists none). agents.tsv recorded s0, the session before
# b1's /clear; hooks/agent-state.sh moved s0.argv's --resume to s7, the session it is in now. Claude Code
# lists s0 as idle but s7 as busy: b1 is waited for, never sent a key. Once s7 is idle b1 resumes s7 with
# its launch flags, the output says where the id came from, and the files keep agents.tsv's name, s0.
RD="${CLAUDE_CONFIG_DIR}/swarm-dev/resume"; mkdir -p "${RD}"
with_session() { sed -i.bak "s/]\$/,{\"sessionId\":\"$1\",\"status\":\"$2\"}]/" "${H}/claude.json"; }   # <id> <status>
printf '%s\n' python3 -I "${RD}/s0.py" claude --resume s7 --model sonnet > "${RD}/s0.argv"
for n in conduct-e b2 b4; do echo "${NEW}" > "${P}/.swarm/versions/${n}"; done
echo 0.21.0 > "${P}/.swarm/versions/b1"; claude_list idle idle idle; with_session s7 busy
sed -i.bak 's/^b1 w:b1 s1$/b1 w:b1 -/' "${H}/agents"
WAIT_MS=200 upgrade e
check "agents.tsv's s0 reads idle but s7, where b1 is now, is busy: b1 is sent no key and is named as busy" "1|yes|" \
  "${rc}|$(has 'b1: left on 0.21.0: still busy at the end of the wait' "$(cat "${H}/out")")|$(calls 'pane send-keys w:b1')"
claude_list idle idle idle; with_session s7 idle
upgrade e
check "with no session from herdr, b1 restarts with --resume of the session a /clear moved agents.tsv's id to, and its launch flags" "0|yes" \
  "${rc}|$(has 'agent start b1 --kind claude --pane w:b1 --timeout 60000 -- --resume s7 --model sonnet --effort high --permission-mode auto' "$(calls 'agent start b1')")"
check "it says where the session came from, and b1 moved" "yes|yes" \
  "$(has 'b1: herdr lists no session for it; resuming s7, which a /clear moved agents.tsv'"'"'s s0 to' "$(cat "${H}/out")")|$(has "b1: 0.21.0 -> ${NEW}" "$(cat "${H}/out")")"
check "the report to herdr carries s7 under s0's wrapper, s0.argv (the file the hooks move) says s7, and no s7.argv is made" "yes|yes|no" \
  "$(has "--agent-session-id s7 -- python3 -I ${RD}/s0.py claude --resume s7 --model sonnet" "$(calls 'pane report-agent w:b1')")|$(has $'claude\n--resume\ns7\n--model' "$(cat "${RD}/s0.argv")")|$([[ -e "${RD}/s7.argv" ]] && echo yes || echo no)"
check "SWARM_RESUME names s0.argv, the file a later /clear moves" "yes" \
  "$(has "export SWARM_RESUME=$(printf %q "${RD}/s0.argv")" "$(cat "${H}/launch-w:b1")")"

# --- A second /clear moves s0.argv on to s8 (the hook's rewrite); the next upgrade resumes s8.
sed -i.bak 's/^s7$/s8/' "${RD}/s0.argv"; claude_list idle idle idle; with_session s8 idle; echo 0.21.0 > "${P}/.swarm/versions/b1"
upgrade e
check "after a second /clear, b1 resumes s8, the session s0.argv names now" "0|yes" \
  "${rc}|$(has 'agent start b1 --kind claude --pane w:b1 --timeout 60000 -- --resume s8 --model sonnet' "$(calls 'agent start b1')")"

# --- With no resume command for agents.tsv's id, b1 resumes that id as it stands.
rm -f "${RD}/s0.argv" "${RD}/s7.argv"; claude_list idle idle idle; echo 0.21.0 > "${P}/.swarm/versions/b1"
upgrade e
check "with no resume command for it, b1 restarts with --resume of agents.tsv's id itself, and says so" "0|yes|yes" \
  "${rc}|$(has 'agent start b1 --kind claude --pane w:b1 --timeout 60000 -- --resume s0 --model sonnet' "$(calls 'agent start b1')")|$(has 'b1: herdr lists no session for it; resuming s0, the one agents.tsv recorded' "$(cat "${H}/out")")"
rm -f "${RD}/s0.argv"
sed -i.bak 's/^b1 w:b1 -$/b1 w:b1 s1/' "${H}/agents"

# --- A conductor whose restart fails before its claude exits (neither herdr nor agents.tsv gives a
# session) is told to carry on.
echo 0.21.0 > "${P}/.swarm/versions/conduct-e"; claude_list idle idle idle
sed -i.bak 's/^conduct-e w:c sc$/conduct-e w:c -/' "${H}/agents"
cp "${P}/.swarm/agents.tsv" "${H}/agents.tsv.keep"
printf '2026-10-22\tconduct\tconduct-e\tclaude\topus\thigh\t-\n' >> "${P}/.swarm/agents.tsv"   # its newest record has no session
upgrade e
check "it is named with both sources, never sent a key or restarted, and told to carry on on the version it runs" "1|yes||0|1" \
  "${rc}|$(has 'conduct-e: neither herdr nor agents.tsv gives a session for it' "$(cat "${H}/out")")|$(calls 'pane send-keys w:c')|$(calls 'agent start conduct-e' | grep -c .)|$(calls 'agent prompt w:c' | grep -c 'could not restart you, so you stay on the version you run')"
echo 0.21.0 > "${P}/.swarm/versions/conduct-e"; touch "${H}/sayfail"
upgrade e
check "one that cannot even be told that is named in the summary, to be told by hand" "1|1" \
  "${rc}|$(sed -n '/: left on /,$p' "${H}/out" | grep -cx 'conduct-e: could not be told to carry on; tell it by hand')"
rm -f "${H}/sayfail"
sed -i.bak 's/^conduct-e w:c -$/conduct-e w:c sc/' "${H}/agents"; cp "${H}/agents.tsv.keep" "${P}/.swarm/agents.tsv"

# --- A conductor whose session goes right after the request is named at once; its builders are held.
echo 0.21.0 > "${P}/.swarm/versions/conduct-e"; claude_list idle idle idle; touch "${H}/nohandover"
echo '2 s/{"sessionId":"sc","status":"idle"},//' > "${H}/flip"
SECONDS=0; upgrade e; took="${SECONDS}"
check "it is named as gone well inside the wait, and nothing is restarted" "1|yes||yes" \
  "${rc}|$(has 'conduct-e: left on 0.21.0: its Claude session is gone, so it wrote no handover' "$(cat "${H}/out")")|$(calls 'pane send-keys')|$( ((took < 30)) && echo yes || echo "no, ${took}s")"
rm -f "${H}/nohandover"

# --- An idle conductor that writes no handover by the end of the wait is told to carry on by prompt.
echo 0.21.0 > "${P}/.swarm/versions/conduct-e"; echo 0.21.0 > "${P}/.swarm/versions/b2"; claude_list idle idle idle; touch "${H}/nohandover"
WAIT_MS=300 upgrade e
check "the withdrawal goes as a prompt, and nothing is restarted" "1|1|" \
  "${rc}|$(calls 'agent prompt w:c' | grep -c 'gave up waiting for your handover')|$(calls 'pane send-keys')"
rm -f "${H}/nohandover"

# --- A busy conductor gets the request as a note in its inbox; one that writes no handover by the
# end of the wait is told to carry on as before, named and left as it is.
echo 0.21.0 > "${P}/.swarm/versions/conduct-e"; claude_list busy idle idle
WAIT_MS=200 upgrade e
check "the busy conductor is sent no prompt, and finds the request in its inbox" "|yes" \
  "$(calls 'agent prompt')|$(grep -q "Write a handover to ${P}/.swarm/handover-e-" "${P}/.swarm/inbox/conduct-e.md" 2>/dev/null && echo yes || echo no)"
check "with no handover it is named and left on its old version" "yes|0.21.0" \
  "$(has 'conduct-e: left on 0.21.0: no handover by the end of the wait, told to carry on as before' "$(cat "${H}/out")")|$(cat "${P}/.swarm/versions/conduct-e")"
check "and its inbox withdraws the request" "yes" "$(grep -q 'gave up waiting for your handover' "${P}/.swarm/inbox/conduct-e.md" 2>/dev/null && echo yes || echo no)"
check "and its idle builder is held: named, never sent a key or restarted" "yes|" \
  "$(has 'b2: left on 0.21.0: its conductor wrote no handover' "$(cat "${H}/out")")|$(calls 'pane send-keys'; calls 'agent start')"

# --- A conductor that writes its handover but stays busy is told to carry on as before; its builders are held.
claude_list idle idle idle; echo '2 s/"sc","status":"idle"/"sc","status":"busy"/' > "${H}/flip"
WAIT_MS=300 upgrade e
check "it was asked by prompt and wrote a handover, but is not restarted while busy" "1|1|yes|" \
  "${rc}|$(calls 'agent prompt' | grep -c 'Write a handover')|$(grep -q 'gave up waiting for your handover' "${P}/.swarm/inbox/conduct-e.md" 2>/dev/null && echo yes || echo no)|$(calls 'pane send-keys')"

# --- One busy past the wait but idle within the grace gets the withdrawal by prompt, not in its inbox.
claude_list idle idle idle; touch "${H}/nohandover"
echo '2 s/"sc","status":"idle"/"sc","status":"busy"/' > "${H}/flip"; echo '41 s/"sc","status":"busy"/"sc","status":"idle"/' > "${H}/flip2"
GRACE_MS=120000 WAIT_MS=300 upgrade e; echo "${rc}" > "${H}/rc"
check "the withdrawal waits for it to go idle, then goes as a prompt" "1|1|no" \
  "$(cat "${H}/rc")|$(calls 'agent prompt w:c' | grep -c 'gave up waiting for your handover')|$(grep -q 'gave up waiting' "${P}/.swarm/inbox/conduct-e.md" 2>/dev/null && echo yes || echo no)"
rm -f "${H}/nohandover"

# --- A conductor whose epic has an env: name not set here is asked for no handover, and holds its builders.
claude_list idle idle idle; : > "${P}/.swarm/versions/conduct-e"   # an empty record reads as unknown
printf -- '---\nkind: code\nstatus: ready\nepic: e\nenv: [UPGRADE_TEST_UNSET]\n---\n\n# b3\n' > "${P}/docs/stories/b3.md"
(unset UPGRADE_TEST_UNSET; WAIT_MS=300 upgrade e; echo "${rc}" > "${H}/rc")
check "the conductor gets no request, is named, and no builder is touched" "1||yes|yes|" \
  "$(cat "${H}/rc")|$(calls 'agent prompt')|$(has 'env: UPGRADE_TEST_UNSET is not set here' "$(cat "${H}/out")")|$(has 'conduct-e: left on unknown: asked for no handover' "$(cat "${H}/out")")|$(calls 'pane send-keys')"
rm -f "${P}/docs/stories/b3.md"

# --- A busy conductor finds the request in its inbox and writes nothing there; once idle with no
# handover it is asked again by prompt, and that handover, in after the first round, still moves it
# and its builders.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
claude_list busy idle idle; echo '3 s/"sc","status":"busy"/"sc","status":"idle"/' > "${H}/flip"
sleep 120 & other=$!; echo "${other} - /gone.log" > "${P}/.swarm/upgrade.pid"   # a dead run's lock, its pid now another process's
upgrade e
kill "${other}" 2>/dev/null || true
check "a dead run's lock is taken over, though its pid runs something else now, and let go at the end" "0|no" \
  "$(grep -c 'already runs here' "${H}/out")|$([[ -e "${P}/.swarm/upgrade.pid" ]] && echo yes || echo no)"
check "the conductor is asked in its inbox, then by prompt, and moved after its builders" \
  "0|yes|1|prompt w:c|keys w:b1|start b1|prompt w:b1|keys w:b2|start b2|prompt w:b2|keys w:c|start conduct-e|prompt w:c" \
  "${rc}|$(grep -q 'Write a handover' "${P}/.swarm/inbox/conduct-e.md" 2>/dev/null && echo yes || echo no)|$(calls 'agent prompt w:c' | grep -c 'Write a handover')|$(order)"
check "it prints one line per agent" "b1: 0.21.0 -> ${NEW}|b2: 0.21.0 -> ${NEW}|conduct-e: 0.21.0 -> ${NEW}" "$(grep -- ' -> ' "${H}/out" | paste -sd'|' -)"

# --- Without --foreground upgrade runs detached, its log at .swarm/upgrade-<version>.log. Killing the
# shell that started it does not stop it; a second upgrade while it runs starts nothing and names it,
# and status names it with the agents still on an old version. b1, busy at first, is moved once idle.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
claude_list idle busy idle; : > "${LOG}"; rm -f "${H}/claude.count"
ULOG="${P}/.swarm/upgrade-${NEW}.log"; rm -f "${ULOG}"
EV="${P}/.swarm/events.tsv"; ev0="$(awk -F'\t' '$2 == "upgrade"' "${EV}" 2>/dev/null | wc -l | tr -d ' ')"
# The starting shell is a session of its own, so the test can kill its whole process group.
# shellcheck disable=SC2016 # $@ and $0 are the inner shell's
(cd "${P}" && exec python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
  bash -c '"$@" > "$0" 2>&1; sleep 60' "${H}/starter.out" env "${ENVV[@]}" SWARM_UPGRADE_WAIT_MS=120000 bash "${SWARM}" upgrade e) &
spid=$!
for _ in $(seq 150); do [[ -s "${P}/.swarm/upgrade.pid" ]] && grep -q 'runs detached' "${H}/starter.out" 2>/dev/null && break; sleep 0.2; done
UPID="$(sed -n 's/.*: pid \([0-9]*\), log .*/\1/p' "${H}/starter.out")"
check "it prints the detached run's pid and log" "yes" "$(has "swarm.sh upgrade runs detached until every agent is moved: pid ${UPID}, log ${ULOG}" "$(cat "${H}/starter.out")")"
kill -HUP -- "-${spid}" 2>/dev/null || true; kill -TERM -- "-${spid}" 2>/dev/null || true; wait "${spid}" 2>/dev/null || true
sleep 1   # time for a run that shared the starter's process group to die of it
check "the starting shell is gone, the upgrade runs on" "gone|runs" \
  "$(kill -0 "${spid}" 2>/dev/null && echo alive || echo gone)|$(kill -0 "${UPID:-0}" 2>/dev/null && echo runs || echo stopped)"
rc=0; (cd "${P}" && env "${ENVV[@]}" bash "${SWARM}" upgrade e) > "${H}/out" 2>&1 || rc=$?
check "a second upgrade starts nothing and names the running one" "0|yes|${UPID}" \
  "${rc}|$(has "swarm.sh upgrade already runs here (pid ${UPID}, log ${ULOG}); this one started nothing" "$(cat "${H}/out")")|$(cut -d' ' -f1 "${P}/.swarm/upgrade.pid")"
rc=0; (cd "${P}" && env "${ENVV[@]}" bash "${SWARM}" upgrade backlog) > "${H}/out" 2>&1 || rc=$?
check "one for another scope fails, saying its agents were not moved" "1|yes" \
  "${rc}|$(has "swarm.sh upgrade already runs here for e (pid ${UPID}, log ${ULOG}): backlog was not moved; run it again once the running one ends" "$(cat "${H}/out")")"
for _ in $(seq 150); do [[ "$(cat "${P}/.swarm/versions/b2")" == "${NEW}" ]] && break; sleep 0.2; done
(cd "${P}" && env "${ENVV[@]}" bash "${SWARM}" status) > "${H}/out" 2>&1 || true
check "status names the upgrade and its scope's agents still on an old version, not another epic's" "yes|1" \
  "$(has "Upgrade of e running (pid ${UPID}, log ${ULOG})" "$(cat "${H}/out")")|$(grep -cx '  still on an old version: conduct-e b1' "${H}/out")"
check "the paused conductor holds back tell's wake prompt while b1 is busy" "yes" "$([[ -e "${P}/.swarm/inbox/conduct-e.upgrade" ]] && echo yes || echo no)"
claude_list idle idle idle
for _ in $(seq 300); do kill -0 "${UPID:-0}" 2>/dev/null || break; sleep 0.2; done
kill -0 "${UPID:-0}" 2>/dev/null && { echo "the detached upgrade never ended" >&2; kill -- "-${UPID}" 2>/dev/null || true; }
check "the detached run moved every agent, b1 in a later round, and let the project and the conductor go" \
  "b2: 0.21.0 -> ${NEW}|b1: 0.21.0 -> ${NEW}|conduct-e: 0.21.0 -> ${NEW}|no|no" \
  "$(grep -- ' -> ' "${ULOG}" | paste -sd'|' -)|$([[ -e "${P}/.swarm/upgrade.pid" ]] && echo yes || echo no)|$([[ -e "${P}/.swarm/inbox/conduct-e.upgrade" ]] && echo yes || echo no)"
check "the log ends on its tally" "upgrade done: 3 moved, 0 left (exit 0)" "$(tail -1 "${ULOG}")"
check "the run is one event, the worker's, its target the epic" "$((ev0 + 1))|e	ok" \
  "$(awk -F'\t' '$2 == "upgrade"' "${EV}" | wc -l | tr -d ' ')|$(awk -F'\t' '$2 == "upgrade" { l = $3 "\t" $5 } END { print l }' "${EV}" | no_version)"

# --- Two upgrades started together run one, and both print its pid. A TERM mid-run names b1, still
# waiting, as left, tells the conductor it paused which builders moved and to carry on, lets it go,
# and logs its stop.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
claude_list idle busy idle; : > "${LOG}"; rm -f "${ULOG}"
for i in 1 2; do (cd "${P}" && env "${ENVV[@]}" SWARM_UPGRADE_WAIT_MS=120000 bash "${SWARM}" upgrade e > "${H}/start${i}.out" 2>&1) & done; wait
UPID="$(cat "${H}/start1.out" "${H}/start2.out" | sed -n 's/^swarm.sh upgrade runs detached until every agent is moved: pid \([0-9]*\), log .*/\1/p')"
check "two upgrades started together: one runs, the other names it, both with the pid that holds the upgrade" "1|1|${UPID}" \
  "$(cat "${H}/start1.out" "${H}/start2.out" | grep -c '^swarm.sh upgrade runs detached')|$(cat "${H}/start1.out" "${H}/start2.out" | grep -c "already runs here (pid ${UPID:-none}, ")|$(cut -d' ' -f1 "${P}/.swarm/upgrade.pid" 2>/dev/null)"
for _ in $(seq 150); do [[ "$(cat "${P}/.swarm/versions/b2")" == "${NEW}" && -e "${P}/.swarm/inbox/conduct-e.upgrade" ]] && break; sleep 0.2; done
kill -TERM "${UPID:-0}" 2>/dev/null || true
for _ in $(seq 150); do kill -0 "${UPID:-0}" 2>/dev/null || break; sleep 0.2; done
kill -0 "${UPID:-0}" 2>/dev/null && { echo "the stopped upgrade never ended" >&2; kill -9 "${UPID}" 2>/dev/null || true; }
check "the stopped run named b1, told the conductor which builders moved, let it go, and logged its stop" \
  "yes|1|no|upgrade stopped: 1 moved, 2 left (exit 143)|no" \
  "$(has 'b1: left on 0.21.0: the upgrade was stopped' "$(cat "${ULOG}")")|$(calls 'agent prompt w:c' | grep -c "was stopped before it moved you. Builders restarted on swarm-dev ${NEW}: b2. Left on their old version: b1.")|$([[ -e "${P}/.swarm/inbox/conduct-e.upgrade" ]] && echo yes || echo no)|$(tail -1 "${ULOG}")|$([[ -e "${P}/.swarm/upgrade.pid" ]] && echo yes || echo no)"

# --- A conductor whose handover is in and whose session goes by its restart's own idle check (b2's
# start takes it) is skipped as closed, and stays skipped on a TERM: told nothing, named only on the
# skipped (closed) line, not counted as left. Every agent is in scope, so x1, busy, keeps the run
# going until the TERM.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
echo '[{"sessionId":"sc","status":"idle"},{"sessionId":"s1","status":"idle"},{"sessionId":"s2","status":"idle"},{"sessionId":"s4","status":"idle"},{"sessionId":"sx","status":"busy"}]' > "${H}/claude.json"
ULOG="${P}/.swarm/upgrade-${NEW}.log"; rm -f "${H}/flip" "${H}/flip2" "${P}/.swarm/inbox/conduct-e.md" "${ULOG}"; : > "${LOG}"
cat > "${H}/onstart-b2" <<EOF
#!/bin/sh
sed -i.bak 's/{"sessionId":"sc","status":"idle"},//' "${H}/claude.json"
EOF
chmod +x "${H}/onstart-b2"
(cd "${P}" && env "${ENVV[@]}" SWARM_UPGRADE_WAIT_MS=120000 bash "${SWARM}" upgrade) > "${H}/out" 2>&1
UPID="$(sed -n 's/.*: pid \([0-9]*\), log .*/\1/p' "${H}/out")"
for _ in $(seq 600); do ls "${H}"/tmp/swarm-upgrade-run.*/closed-conduct-e >/dev/null 2>&1 && break; sleep 0.2; done
closed_seen="$(ls "${H}"/tmp/swarm-upgrade-run.*/closed-conduct-e >/dev/null 2>&1 && echo yes || echo no)"
kill -TERM "${UPID:-0}" 2>/dev/null || true
for _ in $(seq 300); do kill -0 "${UPID:-0}" 2>/dev/null || break; sleep 0.2; done
kill -0 "${UPID:-0}" 2>/dev/null && { echo "the stopped upgrade never ended" >&2; kill -9 "${UPID}" 2>/dev/null || true; }
rm -f "${H}/onstart-b2"
check "a conductor skipped as closed after its handover stays skipped on a TERM: told nothing, named once, not left" "yes|1|0|no|upgrade stopped: 2 moved, 1 left (exit 143)" \
  "${closed_seen}|$(grep -cx 'skipped (closed): conduct-e' "${ULOG}")|$(grep -c '^conduct-e: ' "${ULOG}")|$(grep -qs 'was stopped before it moved you' "${P}/.swarm/inbox/conduct-e.md" && echo yes || echo no)|$(tail -1 "${ULOG}")"

# --- A TERM while a restart is under way names that builder as left, with how to resume it.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
claude_list idle idle idle; : > "${LOG}"; rm -f "${ULOG}"; touch "${H}/slowstart"
(cd "${P}" && env "${ENVV[@]}" SWARM_UPGRADE_WAIT_MS=120000 bash "${SWARM}" upgrade e) > "${H}/out" 2>&1
UPID="$(sed -n 's/.*: pid \([0-9]*\), log .*/\1/p' "${H}/out")"
for _ in $(seq 150); do grep -q '^agent start b1 ' "${LOG}" && break; sleep 0.2; done
sed -i.bak '/^b1 /d' "${H}/agents"   # herdr no longer lists b1: its hint file still names it
kill -TERM "${UPID:-0}" 2>/dev/null || true
for _ in $(seq 150); do kill -0 "${UPID:-0}" 2>/dev/null || break; sleep 0.2; done
kill -0 "${UPID:-0}" 2>/dev/null && { echo "the stopped upgrade never ended" >&2; kill -9 "${UPID}" 2>/dev/null || true; }
rm -f "${H}/slowstart" "${H}/exited-w:b1"; echo "b1 w:b1 s1" >> "${H}/agents"
check "the builder cut off mid-restart is left with its resume hint, the tally counts it" "1|upgrade stopped: 0 moved, 3 left (exit 143)" \
  "$(grep -cx "b1: left on 0.21.0: the upgrade was stopped; not started again; if pane w:b1 shows a shell, claude --resume s1, run in ${H}/wt w:b1, brings the session back" "${ULOG}")|$(tail -1 "${ULOG}")"

# --- A conductor idle with its handover in that turns busy again (a watch woke it) holds its
# builders: b1, idle only once the conductor is busy, is not restarted, and is named for it.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
claude_list idle busy idle
cat > "${H}/onstart-b2" <<EOF
#!/bin/sh
sed -i.bak -e 's/"sc","status":"idle"/"sc","status":"busy"/' -e 's/"s1","status":"busy"/"s1","status":"idle"/' "${H}/claude.json"
EOF
chmod +x "${H}/onstart-b2"
WAIT_MS=4000 upgrade e
check "b1 waits on its busy conductor and is named for it" "1||yes" \
  "${rc}|$(calls 'agent start b1')|$(has 'b1: left on 0.21.0: its conductor wrote its handover but stayed busy' "$(cat "${H}/out")")"
rm -f "${H}/onstart-b2"

# --- herdr's list failing mid-run is a round that waits, not one with nothing left: b1, held then,
# and its conductor are still moved once the list comes back.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
claude_list idle busy idle
cat > "${H}/onstart-b2" <<EOF
#!/bin/sh
touch "${H}/listfail"; sed -i.bak 's/"s1","status":"busy"/"s1","status":"idle"/' "${H}/claude.json"
EOF
chmod +x "${H}/onstart-b2"
upgrade e
rm -f "${H}/onstart-b2" "${H}/listfail" "${H}/listfail.count"
check "a failed list read does not end the run: b1 and the conductor are moved" "0|yes|yes" \
  "${rc}|$(has "b1: 0.21.0 -> ${NEW}" "$(cat "${H}/out")")|$(has "conduct-e: 0.21.0 -> ${NEW}" "$(cat "${H}/out")")"

# --- herdr's list still failing at the end of the wait: the last round's list names b1 and the paused
# conductor as left, the conductor is told to carry on and let go, and the run fails.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
claude_list idle busy idle
printf '#!/bin/sh\ntouch "%s/listdown"\n' "${H}" > "${H}/onstart-b2"; chmod +x "${H}/onstart-b2"
WAIT_MS=2000 upgrade e
rm -f "${H}/onstart-b2" "${H}/listdown"
check "a list still down at the end fails the run, names b1 and the conductor, and lets the conductor go" "1|yes|yes|no" \
  "${rc}|$(has 'b1: left on 0.21.0' "$(cat "${H}/out")")|$(has 'conduct-e: left on 0.21.0' "$(cat "${H}/out")")|$([[ -e "${P}/.swarm/inbox/conduct-e.upgrade" ]] && echo yes || echo no)"

# --- A builder that leaves herdr's list between rounds is named as left, never forgotten.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
claude_list idle busy idle
printf '#!/bin/sh\nsed -i.bak "/^b1 /d" "%s/agents"\n' "${H}" > "${H}/onstart-b2"; chmod +x "${H}/onstart-b2"
WAIT_MS=3000 upgrade e
rm -f "${H}/onstart-b2"; echo "b1 w:b1 s1" >> "${H}/agents"
check "b1, gone from herdr's list, is left and counted" "1|1|upgrade done: 2 moved, 1 left (exit 1)" \
  "${rc}|$(grep -cx "b1: left on 0.21.0: it left herdr's agent list before it was moved" "${H}/out")|$(tail -1 "${H}/out")"

# --- A paused conductor that leaves herdr's list before it writes its handover holds no builder:
# b1 and b2 are restarted.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
claude_list idle idle idle; touch "${H}/nohandover"
printf '#!/bin/sh\nsed -i.bak "/^conduct-e /d" "%s/agents"\n' "${H}" > "${H}/onhandover"; chmod +x "${H}/onhandover"
upgrade e
rm -f "${H}/onhandover" "${H}/nohandover"; echo "conduct-e w:c sc" >> "${H}/agents"
check "the conductor is left for it, its marker gone, and its builders are moved" "1|yes|no|yes|yes" \
  "${rc}|$(has "conduct-e: left on 0.21.0: it left herdr's agent list while paused for its handover" "$(cat "${H}/out")")|$([[ -e "${P}/.swarm/inbox/conduct-e.upgrade" ]] && echo yes || echo no)|$(has "b1: 0.21.0 -> ${NEW}" "$(cat "${H}/out")")|$(has "b2: 0.21.0 -> ${NEW}" "$(cat "${H}/out")")"

# --- An unknown read of Claude Code's list (a bad read) waits for the next round; nothing is left for it.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
claude_list idle idle idle; echo '2 s/^\[/X[/' > "${H}/flip"; echo '6 s/^X\[/[/' > "${H}/flip2"
upgrade e
check "the run, through four bad reads, moves every agent" "0|b1: 0.21.0 -> ${NEW}|b2: 0.21.0 -> ${NEW}|conduct-e: 0.21.0 -> ${NEW}" \
  "${rc}|$(grep -- ' -> ' "${H}/out" | paste -sd'|' -)"
# A bad read at the closed check skips no agent as closed, says so, and the run moves them all.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
claude_list idle idle idle; echo '0 s/^\[/X[/' > "${H}/flip"; echo '1 s/^X\[/[/' > "${H}/flip2"
upgrade e
check "an unreadable Claude Code list at the check skips nobody, says so, and every agent moves" "0|0|1|3" \
  "${rc}|$(grep -c '^skipped (closed)' "${H}/out")|$(grep -cx "Claude Code's list of its sessions could not be read before the first round, so the closed check skipped no agent for a gone session" "${H}/out")|$(grep -c -- ' -> ' "${H}/out")"

# --- A run whose herdr list never reads fails, saying no agent was moved.
for n in conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
claude_list idle idle idle; touch "${H}/listdown"
WAIT_MS=500 upgrade e
rm -f "${H}/listdown"
check "it exits 1 and says so" "1|1|upgrade done: 0 moved, 0 left (exit 1)" \
  "${rc}|$(grep -cx "herdr's agent list could not be read during the run, so no agent was moved" "${H}/out")|$(tail -1 "${H}/out")"

# --- A conductor on its old version first seen at the end of the wait (the one round's read failed)
# is named as left, and the run fails.
echo 0.21.0 > "${P}/.swarm/versions/conduct-e"; for n in b1 b2; do echo "${NEW}" > "${P}/.swarm/versions/${n}"; done
claude_list idle idle idle; touch "${H}/listfail1"
WAIT_MS=1 upgrade e
rm -f "${H}/listfail1"
check "it is left, never asked, and the run exits 1" "1|1|0" \
  "${rc}|$(grep -cx "conduct-e: left on 0.21.0: not reached before the end of the wait, never asked for a handover" "${H}/out")|$(calls 'agent prompt' | grep -c .)"

# --- A conductor already on this version that writes no handover is told to carry on, and kept, never
# left: only its held builder fails the run.
echo "${NEW}" > "${P}/.swarm/versions/conduct-e"; echo "${NEW}" > "${P}/.swarm/versions/b1"; echo 0.21.0 > "${P}/.swarm/versions/b2"
claude_list idle idle idle; touch "${H}/nohandover"
WAIT_MS=300 upgrade e
check "it is kept on its version, its builder left, and nothing counts it as moved" "1|1|0|upgrade done: 0 moved, 1 left (exit 1)" \
  "${rc}|$(grep -cx "conduct-e: already on ${NEW}: no handover by the end of the wait, told to carry on as before" "${H}/out")|$(grep -c '^conduct-e: left on' "${H}/out")|$(tail -1 "${H}/out")"
rm -f "${H}/nohandover"

# --- status judges "old" by the running upgrade's version (its log's name), not its own.
echo 0.21.0 > "${P}/.swarm/versions/conduct-e"; for n in b1 b2 b4; do echo "${NEW}" > "${P}/.swarm/versions/${n}"; done
bash -c 'exec -a "swarm.sh upgrade" sleep 60' & fake=$!
echo "${fake} e ${P}/.swarm/upgrade-0.21.0.log" > "${P}/.swarm/upgrade.pid"
(cd "${P}" && env "${ENVV[@]}" bash "${SWARM}" status) > "${H}/out" 2>&1 || true
kill "${fake}" 2>/dev/null || true; rm -f "${P}/.swarm/upgrade.pid"
check "status lists the agents not on the running upgrade's version" "1" "$(grep -cx '  still on an old version: b1 b2 b4' "${H}/out")"

# --- A builder idle at the round's read but busy by its restart waits one round, not the whole run:
# z2, after it in the list, is restarted first.
for z in z1 z2; do
  printf -- '---\nkind: code\nstatus: ready\n---\n\n# %s\n' "${z}" > "${P}/docs/stories/${z}.md"
  echo "${z} w:${z} s${z}" >> "${H}/agents"; echo "w:${z} ${z}" >> "${P}/.swarm/state/zz"; echo 0.21.0 > "${P}/.swarm/versions/${z}"
  printf '2026-10-22\tcode\t%s\tclaude\tsonnet\thigh\ts%s\n' "${z}" "${z}" >> "${P}/.swarm/agents.tsv"
  CMD=(claude); argv "${z}" sonnet --session-id "s${z}" > "${H}/argv-w:${z}"
done
echo '[{"sessionId":"sz1","status":"idle"},{"sessionId":"sz2","status":"idle"}]' > "${H}/claude.json"
echo "${Z1_BUSY_AT:-2} s/\"sz1\",\"status\":\"idle\"/\"sz1\",\"status\":\"busy\"/" > "${H}/flip"
echo "${Z1_IDLE_AT:-13} s/\"sz1\",\"status\":\"busy\"/\"sz1\",\"status\":\"idle\"/" > "${H}/flip2"
upgrade backlog
check "z1 waits for the next round, and z2 is restarted before it" "0|start z2|start z1" "${rc}|$(order | tr '|' '\n' | grep '^start' | paste -sd'|' -)"

# --- A conductor already ready, woken by a watch, starts b5 and ends its turn again before a round
# reads it: the agents are read again that round, so b5 is restarted before the conductor, which hears of it.
echo 0.21.0 > "${P}/.swarm/versions/conduct-e"; echo 0.21.0 > "${P}/.swarm/versions/b1"; echo "${NEW}" > "${P}/.swarm/versions/b2"
printf -- '---\nkind: code\nstatus: ready\nepic: e\n---\n\n# b5\n' > "${P}/docs/stories/b5.md"
CMD=(claude); argv b5 sonnet --session-id s5 > "${H}/argv-w:b5"
cat > "${H}/onlist" <<EOF
#!/bin/sh
echo "b5 w:b5 s5" >> "${H}/agents"; echo "w:b5 b5" >> "${P}/.swarm/state/e"; echo 0.21.0 > "${P}/.swarm/versions/b5"
printf '2026-10-22\tcode\tb5\tclaude\tsonnet\thigh\ts5\n' >> "${P}/.swarm/agents.tsv"
sed -i.bak 's/]\$/,{"sessionId":"s5","status":"idle"}]/' "${H}/claude.json"
EOF
chmod +x "${H}/onlist"
claude_list idle busy idle; echo "${B1_IDLE_AT:-5} s/\"s1\",\"status\":\"busy\"/\"s1\",\"status\":\"idle\"/" > "${H}/flip"; echo "${ARM_AT:-4}" > "${H}/arm"
upgrade e
rm -f "${H}/onlist" "${H}/arm" "${H}/armed"
check "b5 is restarted before its conductor, which is told of it" "0|start b5|start conduct-e|1" \
  "${rc}|$(order | tr '|' '\n' | grep -E '^start (b5|conduct-e)$' | paste -sd'|' -)|$(calls 'agent prompt w:c' | grep -c "Builders restarted on swarm-dev ${NEW}: b1 b5.")"

# --- upgrade backlog moves the backlog conductor and the stories with no epic, and no epic's agents.
CB="$(cd "${P}" && SWARM_PROJECT="${P}" bash "${SWARM}" _conductor backlog)"
printf -- '---\nkind: code\nstatus: ready\n---\n\n# y1\n' > "${P}/docs/stories/y1.md"
printf 'w:k %s\nw:y1 y1\n' "${CB}" > "${P}/.swarm/state/backlog"
printf '%s w:k sk\ny1 w:y1 sy\n' "${CB}" >> "${H}/agents"
printf '2026-10-22\tconduct\t%s\tclaude\topus\thigh\tsk\n2026-10-22\tcode\ty1\tclaude\tsonnet\thigh\tsy\n' "${CB}" >> "${P}/.swarm/agents.tsv"
for n in "${CB}" y1 conduct-e b1 b2; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
CMD=(claude); argv "${CB}" opus --session-id sk > "${H}/argv-w:k"; argv y1 sonnet --session-id sy > "${H}/argv-w:y1"
echo '[{"sessionId":"sk","status":"idle"},{"sessionId":"sy","status":"idle"},{"sessionId":"sc","status":"idle"},{"sessionId":"s1","status":"idle"},{"sessionId":"s2","status":"idle"}]' > "${H}/claude.json"
upgrade backlog
check "it restarts y1 then the backlog conductor, after its handover, and leaves epic e alone" "0|prompt w:k|keys w:y1|start y1|prompt w:y1|keys w:k|start ${CB}|prompt w:k|yes" \
  "${rc}|$(order)|$(ls "${P}"/.swarm/handover-backlog-*.md >/dev/null 2>&1 && echo yes || echo no)"

# --- review-b1 is a Claude agent now (it owns b1's PR): idle b1 waits while review-b1 is busy, and
# both are restarted once it reads idle, from Claude Code's 8th read on (its 1st is the closed check's).
printf '2026-10-22\treview\treview-b1\tclaude\tsonnet\thigh\tsr\n' >> "${P}/.swarm/agents.tsv"
sed -i.bak 's/^review-b1 w:r -$/review-b1 w:r sr/' "${H}/agents"
CMD=(claude); argv review-b1 sonnet --session-id sr > "${H}/argv-w:r"
review_b1() {   # <status> — review-b1 and b1 on the old version, the rest of epic e on this one
  for n in b1 review-b1; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
  for n in conduct-e b2 b5; do echo "${NEW}" > "${P}/.swarm/versions/${n}"; done
  printf '[{"sessionId":"sc","status":"idle"},{"sessionId":"s1","status":"idle"},{"sessionId":"s2","status":"idle"},{"sessionId":"s5","status":"idle"},{"sessionId":"sr","status":"%s"}]\n' "$1" > "${H}/claude.json"
  rm -f "${H}/flip" "${H}/flip2"
}
review_b1 busy; echo '7 s/"sr","status":"busy"/"sr","status":"idle"/' > "${H}/flip"
upgrade e
check "b1 is restarted only once its busy review agent reads idle, and both are moved" "0|yes|yes|yes" \
  "${rc}|$(awk '/^claude 8$/ { seen = 1 } /^agent start b1 / { print (seen ? "yes" : "no, before claude 8"); exit }' "${LOG}")|$(has "b1: 0.21.0 -> ${NEW}" "$(cat "${H}/out")")|$(has "review-b1: 0.21.0 -> ${NEW}" "$(cat "${H}/out")")"
review_b1 busy
WAIT_MS=300 upgrade e
check "a review agent busy past the wait is left and named, and holds its idle builder, named for it" "1|1|1|" \
  "${rc}|$(grep -cx 'review-b1: left on 0.21.0: still busy at the end of the wait' "${H}/out")|$(grep -cx 'b1: left on 0.21.0: its review agent review-b1 stayed busy' "${H}/out")|$(calls 'agent start')"
# A builder whose Claude session is gone is skipped as closed at once, though its review agent is busy.
review_b1 busy; sed -i.bak 's/{"sessionId":"s1","status":"idle"},//' "${H}/claude.json"
WAIT_MS=300 upgrade e
check "a gone builder is skipped as closed, not held by its busy review agent" "1|1|0|" \
  "${rc}|$(grep -cE '^skipped \(closed\):( [a-z0-9-]+)* b1( |$)' "${H}/out")|$(grep -c '^b1: ' "${H}/out")|$(calls 'agent start')"
# A review agent skipped as closed (its session gone at the check) holds its builder no more, and its
# state is not read at the hold: a bad read there (the 6th, right after b1's own 5th) cannot hold b1.
review_b1 idle; sed -i.bak 's/,{"sessionId":"sr","status":"idle"}//' "${H}/claude.json"
echo '5 s/^\[/X[/' > "${H}/flip"; echo '6 s/^X\[/[/' > "${H}/flip2"
WAIT_MS=300 upgrade e
check "a review agent skipped as closed holds its builder no more, whatever Claude Code's list reads at the hold" "0|1|1|0|upgrade done: 1 moved, 0 left (exit 0)" \
  "${rc}|$(grep -cx 'skipped (closed): review-b1' "${H}/out")|$(calls 'agent start b1' | grep -c .)|$(grep -c '^b1: left on' "${H}/out")|$(tail -1 "${H}/out")"
# A review agent busy through the one round that reads idle at the end, from Claude Code's 8th read
# on (the closed check reads its list once, then the round 6 times: 3 for the conductor, then b1,
# b1's hold and review-b1),
# still names idle b1, which it held.
review_b1 busy; echo '7 s/"sr","status":"busy"/"sr","status":"idle"/' > "${H}/flip"
WAIT_MS=1 upgrade e
check "a builder its review agent held in the last round is named for it, though that agent reads idle at the end" "1|1|" \
  "${rc}|$(grep -cx 'b1: left on 0.21.0: its review agent review-b1 stayed busy' "${H}/out")|$(calls 'agent start')"
# A review agent left on its old version (it could not be told the new path) that then goes busy
# still holds b1, busy at first and idle from then on.
review_b1 idle; sed -i.bak 's/"s1","status":"idle"/"s1","status":"busy"/' "${H}/claude.json"; touch "${H}/promptfail"
cat > "${H}/onstart-review-b1" <<EOF
#!/bin/sh
sed -i.bak -e 's/"sr","status":"idle"/"sr","status":"busy"/' -e 's/"s1","status":"busy"/"s1","status":"idle"/' "${H}/claude.json"
EOF
chmod +x "${H}/onstart-review-b1"
WAIT_MS=3000 upgrade e
rm -f "${H}/promptfail" "${H}/onstart-review-b1"
check "a left review agent gone busy still holds its idle builder" "1|1||1" \
  "${rc}|$(grep -c '^review-b1: left on 0.21.0: ' "${H}/out")|$(calls 'agent start b1')|$(grep -cx 'b1: left on 0.21.0: its review agent review-b1 stayed busy' "${H}/out")"

# --- The docs describe it.
for f in 'docs/reference*.md' commands/swarm.md; do
  # shellcheck disable=SC2086 # ${f} is unquoted so the reference glob expands to the set
  check "${f} describes swarm.sh upgrade" "yes" "$(grep -q 'swarm.sh upgrade' "${REPO}"/${f} && echo yes || echo no)"
done

[[ ${fails} -eq 0 ]] || { cat "${H}/out"; exit 1; }
echo "all upgrade tests passed"
