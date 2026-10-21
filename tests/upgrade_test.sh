#!/usr/bin/env bash
# upgrade_test.sh — swarm.sh upgrade <epic> moves a running epic's agents to this version: it asks
# the idle conductor for a handover first, then restarts each builder and last the conductor in its
# own pane, once Claude Code has it idle: ctrl+c, a clean environment whose PATH starts at this
# version's bin (an older version's root gone, a shared folder kept), and herdr agent start
# --resume <herdr's session> with the flags its claude ran with (--session-id or an older --resume
# dropped). It tells each the new swarm.sh path, and the conductor to carry on. A dirty worktree is
# left as it was. A builder still busy at the end of the wait is waited for, never sent a key, and
# named as left on its old version, and an idle one after it is still restarted; one that cannot be
# told the new path stays on its old version; a second run skips the agents already on this
# version. A busy conductor gets the request in its inbox, and one with no handover by the end of
# the wait is named, its builders held. docs/reference.md and commands/swarm.md describe it.
# claude agents --json (claude_stub.sh) reads ${H}/claude.json. herdr is a stub on PATH: agent list
# reads ${H}/agents ("<name> <pane> <session>" lines), agent wait says idle at once, process-info
# shows claude with ${H}/argv-<pane>'s arguments until a ctrl+c (then a shell), agent start brings
# claude back, pane run keeps the launch file it runs as ${H}/launch-<pane>, and an agent prompt
# naming a handover file writes it (any prompt fails while ${H}/promptfail exists). Every call is
# logged.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWARM="${REPO}/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
H="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${H}"' EXIT
export CLAUDE_CONFIG_DIR="${H}/claude-config"
P="${H}/proj"; LOG="${H}/herdr.log"
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
WT="${H}/proj-wt/b1"
"${GIT[@]}" -C "${P}" worktree add -q -b story/b1 "${WT}"
echo work > "${WT}/f"; "${GIT[@]}" -C "${WT}" add f && "${GIT[@]}" -C "${WT}" commit -qm b1
echo dirty >> "${WT}/f"; echo new > "${WT}/untracked"
tree_state() { git -C "${WT}" rev-parse HEAD; git -C "${WT}" status --porcelain; cat "${WT}/f" "${WT}/untracked"; }
BEFORE="$(tree_state)"

# A conductor and two builders of epic e, and x1's builder of another epic.
printf 'w:c conduct-e\nw:b1 b1\nw:b2 b2\nw:x1 x1\n' > "${P}/.swarm/state/e"
printf '%s\n' $'2026-10-20\tconduct\tconduct-e\tclaude\topus\thigh\tsc' $'2026-10-20\tcode\tb1\tclaude\tsonnet\thigh\ts1' \
  $'2026-10-20\tcode\tb2\tclaude\tsonnet\thigh\ts2' $'2026-10-20\tcode\tx1\tclaude\tsonnet\thigh\tsx' > "${P}/.swarm/agents.tsv"
printf 'conduct-e w:c sc\nb1 w:b1 s1\nb2 w:b2 s2\nx1 w:x1 sx\n' > "${H}/agents"
for n in conduct-e b1 b2 x1; do echo 0.21.0 > "${P}/.swarm/versions/${n}"; done
argv() { printf '%s\n' claude --model "$2" --effort high "${@:3}" --permission-mode auto --disallowedTools 'Bash(gh pr merge:*)' --settings "{\"env\":{\"SWARM_AGENT\":\"$1\"}}"; }
argv conduct-e opus --session-id sc > "${H}/argv-w:c"
argv b1 sonnet --session-id s1 > "${H}/argv-w:b1"
argv b2 sonnet --resume s2 > "${H}/argv-w:b2"   # brought back by herdr once already
argv x1 sonnet --session-id sx > "${H}/argv-w:x1"

printf '#!/bin/sh\nH="%s"\n' "${H}" > "${H}/bin/herdr"
cat >> "${H}/bin/herdr" <<'STUB'
[ "$1" = --version ] && { echo "herdr 0.9.5"; exit 0; }
{ for a in "$@"; do printf '%s ' "$a"; done; echo; } >> "$H/herdr.log"
case "$1 $2" in
  "agent list") awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                     { printf "%s{\"name\":\"%s\",\"pane_id\":\"%s\",\"agent_status\":\"idle\",\"agent_session\":{\"value\":\"%s\"}}", (NR > 1 ? "," : ""), $1, $2, $3 }
                     END { print "]}}" }' "$H/agents" ;;
  "agent wait") echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "pane process-info") p="$4"
                if [ -e "$H/exited-$p" ]; then echo '{"result":{"process_info":{"foreground_processes":[{"argv":["zsh"]}]}}}'
                else python3 -c 'import json, sys; print(json.dumps({"result": {"process_info": {"foreground_processes": [{"argv": open(sys.argv[1]).read().splitlines()}]}}}))' "$H/argv-$p"; fi ;;
  "pane send-keys") touch "$H/exited-$3" ;;
  "pane run") f="${4##* }"; cp "$f" "$H/launch-$3" ;;
  "agent start") shift 2; while [ "$1" != --pane ]; do shift; done; rm -f "$H/exited-$2" ;;
  "agent prompt") [ -e "$H/promptfail" ] && exit 1
                  f="$(printf '%s' "$4" | grep -o '/[^ :]*/\.swarm/handover-[^ :]*\.md' | head -1)"
                  case "$4" in *"Write a handover"*) [ -z "$f" ] || echo "PRs and rounds" > "$f" ;; esac
                  echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
esac
exit 0
STUB
chmod +x "${H}/bin/herdr"
cp "${REPO}/tests/claude_stub.sh" "${H}/bin/claude"; chmod +x "${H}/bin/claude"
export CLAUDE_STUB_AGENTS="${H}/claude.json"   # Claude Code's own list, which says whether the conductor is idle
claude_list() { printf '[{"sessionId":"sc","status":"%s"},{"sessionId":"s1","status":"%s"},{"sessionId":"s2","status":"%s"}]\n' "$@" > "${CLAUDE_STUB_AGENTS}"; }
claude_list idle idle idle

upgrade() { # [epic] — run upgrade from the project, its output in ${H}/out and exit code in rc
  : > "${LOG}"; rc=0
  (cd "${P}" && SWARM_PROJECT="${P}" HERDR_ENV=1 HERDR_PANE_ID=w:lead SWARM_SLEEP_SCALE=0.01 SWARM_UPGRADE_WAIT_MS="${WAIT_MS:-60000}" \
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
  "$(calls 'agent prompt' | grep -c "Its swarm.sh is ${REPO}/bin/swarm.sh: use that path")|$(has "Your handover is ${HANDOVER}. Carry on" "$(calls 'agent prompt w:c')")"
check "b1 restarts with --resume of herdr's session and its launch flags, no --session-id" \
  "agent start b1 --kind claude --pane w:b1 --timeout 60000 -- --resume s1 --model sonnet --effort high --permission-mode auto --disallowedTools Bash(gh pr merge:*) --settings {\"env\":{\"SWARM_AGENT\":\"b1\"}} " \
  "$(calls 'agent start b1')"
check "b2, brought back once already, restarts with one --resume" \
  "yes|1" "$(has -- '-- --resume s2 --model sonnet --effort high --permission-mode' "$(calls 'agent start b2')")|$(calls 'agent start b2' | grep -o -- '--resume' | grep -c .)"
check "the conductor restarts with --resume too" "yes" "$(has -- '-- --resume sc --model opus' "$(calls 'agent start conduct-e')")"
check "another epic's builder is left alone" "" "$(grep -E 'w:x1|x1 ' "${LOG}" | grep -v '^agent list' || true)"
check "each restart's PATH starts at this version's bin, an older version's root gone, a shared folder kept" "yes|0|1" \
  "$(has "export PATH=$(printf %q "${REPO}/bin"):" "$(cat "${H}/launch-w:b1")")|$(grep -c 'old/0.21.0' "${H}/launch-w:b1" || true)|$(grep -c "${H}/shared" "${H}/launch-w:b1" || true)"
check "the resume command is this version's, with --resume" "yes" \
  "$(has $'claude\n--resume\ns1\n--model' "$(cat "${CLAUDE_CONFIG_DIR}/swarm-dev/resume/s1.argv")")"
check "SWARM_RESUME reaches the restarted agent" "yes" "$(has "export SWARM_RESUME=$(printf %q "${CLAUDE_CONFIG_DIR}/swarm-dev/resume/s1.argv")" "$(cat "${H}/launch-w:b1")")"
check "it prints each agent's old and new version" "b1: 0.21.0 -> ${NEW}|b2: 0.21.0 -> ${NEW}|conduct-e: 0.21.0 -> ${NEW}" \
  "$(grep -- ' -> ' "${H}/out" | paste -sd'|' -)"
check "the dirty worktree is as it was" "${BEFORE}" "$(tree_state)"

# --- Both builders back on their old version, b1 busy past the wait, as Claude Code says though herdr
# has it idle: b1 is named, left on it and never sent a key; idle b2 after it is still restarted.
echo 0.21.0 > "${P}/.swarm/versions/b1"; echo 0.21.0 > "${P}/.swarm/versions/b2"; claude_list idle busy idle
WAIT_MS=200 upgrade e
check "a run with an agent left fails" "1" "${rc}"
check "the busy builder was waited for" "yes" "$(has 'agent wait w:b1 --until idle --until done --timeout' "$(calls 'agent wait')")"
check "and never interrupted or restarted; the idle builder after it is" "pane send-keys w:b2 ctrl+c |b2" \
  "$(calls 'pane send-keys' | paste -sd'|' -)|$(calls 'agent start' | cut -d' ' -f3)"
check "it is named as left on its old version" "yes" "$(has 'b1: still busy at the end of the wait, left on 0.21.0' "$(cat "${H}/out")")"
check "the conductor already on this version is skipped and asked for no handover" "yes|1" \
  "$(has "conduct-e: already on ${NEW}" "$(cat "${H}/out")")|$(calls 'agent prompt' | grep -c .)"
check "b1's version is still the old one" "0.21.0" "$(cat "${P}/.swarm/versions/b1")"

# --- A restarted builder that cannot be told the new path stays on its old version, for a second run.
echo 0.21.0 > "${P}/.swarm/versions/b2"; claude_list idle idle idle; touch "${H}/promptfail"
echo "${NEW}" > "${P}/.swarm/versions/b1"
WAIT_MS=200 upgrade e
check "the run fails, and b2 is still on its old version" "1|0.21.0" "${rc}|$(cat "${P}/.swarm/versions/b2")"
rm -f "${H}/promptfail"

# --- A busy conductor gets the request as a note in its inbox; one that writes no handover by the
# end of the wait is named and left as it is.
echo 0.21.0 > "${P}/.swarm/versions/conduct-e"; claude_list busy idle idle
WAIT_MS=200 upgrade e
check "the busy conductor is sent no prompt, and finds the request in its inbox" "|yes" \
  "$(calls 'agent prompt')|$(grep -q "Write a handover to ${P}/.swarm/handover-e-" "${P}/.swarm/inbox/conduct-e.md" 2>/dev/null && echo yes || echo no)"
check "with no handover it is named and left on its old version" "yes|0.21.0" \
  "$(has 'conduct-e: no handover by the end of the wait, left on 0.21.0' "$(cat "${H}/out")")|$(cat "${P}/.swarm/versions/conduct-e")"
check "and its idle builder is held: named, never sent a key or restarted" "yes|" \
  "$(has 'b2: its conductor wrote no handover, left on 0.21.0' "$(cat "${H}/out")")|$(calls 'pane send-keys'; calls 'agent start')"

# --- The docs describe it.
for f in docs/reference.md commands/swarm.md; do
  check "${f} describes swarm.sh upgrade" "yes" "$(grep -q 'swarm.sh upgrade' "${REPO}/${f}" && echo yes || echo no)"
done

[[ ${fails} -eq 0 ]] || { cat "${H}/out"; exit 1; }
echo "all upgrade tests passed"
