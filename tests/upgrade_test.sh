#!/usr/bin/env bash
# upgrade_test.sh — swarm.sh upgrade <epic> moves a running epic's agents to this version: it asks
# the idle conductor for a handover first, then restarts each idle builder and last the conductor in
# its own pane: ctrl+c twice at once, a clean environment whose PATH starts at this version's bin (an
# older version's root gone, a shared folder kept), and herdr agent start --resume <herdr's session>
# with the flags its claude ran with (--session-id or an older --resume dropped; an npm install's
# node .../claude-code/cli.js too), in a project whose path holds a space. It tells each the new
# swarm.sh path, and the conductor to carry on. A dirty worktree is left as it was. A busy builder is never sent a key: idle ones after it go first, it is
# restarted once idle, and one still busy at the end of the wait is named as left on its old
# version, and one whose session is gone is named at once. An agent whose newest record is codex is
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
# hears which builders were restarted and which left. docs/reference.md and
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
# its file (not while ${H}/nohandover exists) and runs ${H}/onhandover if there is one; a prompt
# telling an agent it was restarted fails while ${H}/promptfail exists. Every call is logged.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWARM="${REPO}/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
H="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${H}"' EXIT
export CLAUDE_CONFIG_DIR="${H}/claude-config"
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
  "agent list") awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                     { printf "%s{\"name\":\"%s\",\"pane_id\":\"%s\",\"agent_status\":\"idle\"%s}", (NR > 1 ? "," : ""), $1, $2, ($3 == "-" ? "" : ",\"agent_session\":{\"value\":\"" $3 "\"}") }
                     END { print "]}}" }' "$H/agents" ;;
  "agent wait") echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "pane process-info") p="$4"; [ -e "$H/pifail" ] && exit 1
                if [ -e "$H/exited-$p" ]; then echo '{"result":{"process_info":{"foreground_processes":[{"argv":["zsh"]}]}}}'
                else python3 -c 'import json, sys; print(json.dumps({"result": {"process_info": {"foreground_processes": [{"argv": open(sys.argv[1]).read().splitlines(), "cwd": sys.argv[2]}]}}}))' "$H/argv-$p" "$H/wt $p"; fi ;;
  "pane send-keys") p="$3"; n=0; shift 3; for k in "$@"; do [ "$k" = ctrl+c ] && n=$((n + 1)); done
                    [ "$n" -lt 2 ] || [ -e "$H/noexit" ] || touch "$H/exited-$p" ;;   # claude exits on a second ctrl+c at once
  "pane wait-output") [ -e "$H/envfail" ] && exit 1 ;;
  "pane run") p="$3"; eval "set -- $4"; for f; do :; done; cp "$f" "$H/launch-$p" ;;   # the launch file, its last word
  "agent start") read -r -t 1 _ 2>/dev/null || true   # takes a line of its stdin, as a real command may
                 n="$3"; shift 2; while [ "$1" != --pane ]; do shift; done; rm -f "$H/exited-$2"
                 [ ! -x "$H/onstart-$n" ] || "$H/onstart-$n" ;;
  "agent prompt") case "$4" in *"restarted you on"*) [ -e "$H/promptfail" ] && exit 1 ;; esac
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
j="$(cat "$H/claude.json")"
[ ! -e "$H/flip" ] || [ "$n" -le "$(cut -d' ' -f1 "$H/flip")" ] || j="$(printf '%s' "$j" | sed "$(cut -d' ' -f2- "$H/flip")")"
[ ! -e "$H/flip2" ] || [ "$n" -le "$(cut -d' ' -f1 "$H/flip2")" ] || j="$(printf '%s' "$j" | sed "$(cut -d' ' -f2- "$H/flip2")")"
printf '%s\n' "$j"
STUB
chmod +x "${H}/bin/claude"
claude_list() { printf '[{"sessionId":"sc","status":"%s"},{"sessionId":"s1","status":"%s"},{"sessionId":"s2","status":"%s"},{"sessionId":"s0","status":"idle"}]\n' "$@" > "${H}/claude.json"; rm -f "${H}/flip" "${H}/flip2"; }
claude_list idle idle idle

upgrade() { # [epic] — run upgrade from the project, its output in ${H}/out and exit code in rc
  : > "${LOG}"; rc=0; rm -f "${H}/claude.count" "${P}/.swarm/inbox/conduct-e.md"
  mkdir -p "${H}/tmp"
  (cd "${P}" && TMPDIR="${H}/tmp" SWARM_UPGRADE_GRACE_MS="${GRACE_MS:-200}" SWARM_PROJECT="${P}" HERDR_ENV=1 HERDR_PANE_ID=w:lead SWARM_SLEEP_SCALE=0.01 SWARM_UPGRADE_WAIT_MS="${WAIT_MS:-60000}" \
    PATH="${H}/bin:${H}/old/0.21.0/bin:${H}/shared:${PATH}" bash "${SWARM}" upgrade "$@" > "${H}/out" 2>&1) || rc=$?
}

fails=0
check() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }
calls() { grep -E "^$1 " "${LOG}" || true; }
order() { awk '/^agent prompt/ { print "prompt " $3 } /^pane send-keys/ { print "keys " $3 } /^agent start/ { print "start " $3 }' "${LOG}" | paste -sd'|' -; }

upgrade e
check "upgrade e succeeds" "0" "${rc}"
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
check "each restarted agent is told its background commands were stopped" "3" "$(calls 'agent prompt' | grep -c 'stopped any background command')"
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
check "it is named as left on its old version" "yes" "$(has 'b1: still busy at the end of the wait, left on 0.21.0' "$(cat "${H}/out")")"
check "the conductor already on this version is paused for the restarts, then told to carry on, never restarted" "1|1|yes|" \
  "$(calls 'agent prompt w:c' | grep -c 'Write a handover')|$(calls 'agent prompt w:c' | grep -c "Builders restarted on swarm-dev ${NEW}: b2. Left on their old version: b1.")|$(has "conduct-e: already on ${NEW}, told to carry on" "$(cat "${H}/out")")|$(calls 'pane send-keys w:c')"
check "b1's version is still the old one" "0.21.0" "$(cat "${P}/.swarm/versions/b1")"

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

# --- A builder whose Claude session is gone is named at once, not waited for.
echo 0.21.0 > "${P}/.swarm/versions/b1"; echo '[{"sessionId":"sc","status":"idle"},{"sessionId":"s2","status":"idle"}]' > "${H}/claude.json"
SECONDS=0; upgrade e; took="${SECONDS}"
check "it is named as gone and not restarted, well inside the wait" "1|yes|0|yes" \
  "${rc}|$(has 'b1: its Claude session is gone, so it is not restarted; left on 0.21.0' "$(cat "${H}/out")")|$(calls 'agent start b1' | grep -c .)|$( ((took < 30)) && echo yes || echo "no, ${took}s")"

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

# --- A conductor whose restart fails before its claude exits (herdr gives no session) is told to carry on.
echo 0.21.0 > "${P}/.swarm/versions/conduct-e"; claude_list idle idle idle
sed -i.bak 's/^conduct-e w:c sc$/conduct-e w:c -/' "${H}/agents"
upgrade e
check "it is named, never sent a key, and told to carry on on the version it runs" "1|yes||1" \
  "${rc}|$(has 'conduct-e: herdr gives no session for it' "$(cat "${H}/out")")|$(calls 'pane send-keys w:c')|$(calls 'agent prompt w:c' | grep -c 'could not restart you, so you stay on the version you run')"
sed -i.bak 's/^conduct-e w:c -$/conduct-e w:c sc/' "${H}/agents"

# --- A conductor whose session goes right after the request is named at once; its builders are held.
echo 0.21.0 > "${P}/.swarm/versions/conduct-e"; claude_list idle idle idle; touch "${H}/nohandover"
echo '1 s/{"sessionId":"sc","status":"idle"},//' > "${H}/flip"
SECONDS=0; upgrade e; took="${SECONDS}"
check "it is named as gone well inside the wait, and nothing is restarted" "1|yes||yes" \
  "${rc}|$(has 'conduct-e: its Claude session is gone, so it wrote no handover' "$(cat "${H}/out")")|$(calls 'pane send-keys')|$( ((took < 30)) && echo yes || echo "no, ${took}s")"
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
  "$(has 'conduct-e: no handover by the end of the wait, told to carry on as before, left on 0.21.0' "$(cat "${H}/out")")|$(cat "${P}/.swarm/versions/conduct-e")"
check "and its inbox withdraws the request" "yes" "$(grep -q 'gave up waiting for your handover' "${P}/.swarm/inbox/conduct-e.md" 2>/dev/null && echo yes || echo no)"
check "and its idle builder is held: named, never sent a key or restarted" "yes|" \
  "$(has 'b2: its conductor wrote no handover, left on 0.21.0' "$(cat "${H}/out")")|$(calls 'pane send-keys'; calls 'agent start')"

# --- A conductor that writes its handover but stays busy is told to carry on as before; its builders are held.
claude_list idle idle idle; echo '1 s/"sc","status":"idle"/"sc","status":"busy"/' > "${H}/flip"
WAIT_MS=300 upgrade e
check "it was asked by prompt and wrote a handover, but is not restarted while busy" "1|1|yes|" \
  "${rc}|$(calls 'agent prompt' | grep -c 'Write a handover')|$(grep -q 'gave up waiting for your handover' "${P}/.swarm/inbox/conduct-e.md" 2>/dev/null && echo yes || echo no)|$(calls 'pane send-keys')"

# --- One busy past the wait but idle within the grace gets the withdrawal by prompt, not in its inbox.
claude_list idle idle idle; touch "${H}/nohandover"
echo '1 s/"sc","status":"idle"/"sc","status":"busy"/' > "${H}/flip"; echo '40 s/"sc","status":"busy"/"sc","status":"idle"/' > "${H}/flip2"
GRACE_MS=120000 WAIT_MS=300 upgrade e; echo "${rc}" > "${H}/rc"
check "the withdrawal waits for it to go idle, then goes as a prompt" "1|1|no" \
  "$(cat "${H}/rc")|$(calls 'agent prompt w:c' | grep -c 'gave up waiting for your handover')|$(grep -q 'gave up waiting' "${P}/.swarm/inbox/conduct-e.md" 2>/dev/null && echo yes || echo no)"
rm -f "${H}/nohandover"

# --- A conductor whose epic has an env: name not set here is asked for no handover, and holds its builders.
claude_list idle idle idle; : > "${P}/.swarm/versions/conduct-e"   # an empty record reads as unknown
printf -- '---\nkind: code\nstatus: ready\nepic: e\nenv: [UPGRADE_TEST_UNSET]\n---\n\n# b3\n' > "${P}/docs/stories/b3.md"
(unset UPGRADE_TEST_UNSET; WAIT_MS=300 upgrade e; echo "${rc}" > "${H}/rc")
check "the conductor gets no request, is named, and no builder is touched" "1||yes|yes|" \
  "$(cat "${H}/rc")|$(calls 'agent prompt')|$(has 'env: UPGRADE_TEST_UNSET is not set here' "$(cat "${H}/out")")|$(has 'asked for no handover, left on unknown' "$(cat "${H}/out")")|$(calls 'pane send-keys')"
rm -f "${P}/docs/stories/b3.md"

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

# --- The docs describe it.
for f in docs/reference.md commands/swarm.md; do
  check "${f} describes swarm.sh upgrade" "yes" "$(grep -q 'swarm.sh upgrade' "${REPO}/${f}" && echo yes || echo no)"
done

[[ ${fails} -eq 0 ]] || { cat "${H}/out"; exit 1; }
echo "all upgrade tests passed"
