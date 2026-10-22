#!/usr/bin/env bash
# tell_note_test.sh — `tell conduct-<epic> note <file>` writes the note to the conductor's inbox and,
# when the conductor's turn has ended (idle, or busy only with background jobs: its session log ends
# on an assistant entry that ended its turn), sends it one prompt to read the inbox now. One mid-turn
# gets the note in its inbox and no prompt. Two notes within a minute send one prompt, two at once
# too (each prompt takes a second with ${ROOT}/slow); one a minute after the last prompt sends another. herdr and claude are stubs on PATH: herdr lists the conductor
# from ${ROOT}/agents ("<name> <pane> <session>") and logs each agent prompt to ${ROOT}/prompts.log;
# claude agents --json prints ${ROOT}/claude.json.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/claude-config/projects"
export CLAUDE_STUB_AGENTS="${ROOT}/claude.json"
mkdir -p "${ROOT}/bin" "${CLAUDE_PROJECTS_DIR}/p"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${ROOT}/bin/claude"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

printf '#!/bin/sh\nF="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
case "$1 $2" in
  "agent list") awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
    { printf "%s{\"name\":\"%s\",\"agent_status\":\"working\",\"pane_id\":\"%s\",\"agent_session\":{\"value\":\"%s\"}}", (NR > 1 ? "," : ""), $1, $2, $3 }
    END { print "]}}" }' "$F/agents" ;;
  "agent prompt") [ ! -f "$F/slow" ] || sleep 1; echo "$*" >> "$F/prompts.log" ;;
esac
EOF
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/claude"

p="${ROOT}/proj"
mkdir -p "${p}/.claude/swarm" "${p}/docs/epics" "${p}/docs/stories" "${p}/.swarm/state"
: > "${p}/.claude/swarm/config"
git -C "${p}" init -q
printf -- '---\nstatus: active\n---\n' > "${p}/docs/epics/e.md"
echo "w:7 conduct-e" > "${p}/.swarm/state/tab"   # its pane, as start_agent records one
echo "conduct-e w:7 sc" > "${ROOT}/agents"
INBOX="${p}/.swarm/inbox/conduct-e.md"
echo "start s2 first" > "${ROOT}/note"

# state <status> — Claude Code's status for the conductor's session; fresh: no inbox, prompt or stamp.
state() {
  echo "[{\"sessionId\": \"sc\", \"status\": \"$1\"}]" > "${ROOT}/claude.json"
  rm -rf "${p}/.swarm/inbox" "${CLAUDE_PROJECTS_DIR}/p/sc.jsonl"; : > "${ROOT}/prompts.log"
}
note() { (cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" tell conduct-e note "${ROOT}/note" 2>&1); }
prompts() { grep -c 'agent prompt w:7' "${ROOT}/prompts.log" || true; }
notes() { grep -c '^start s2 first$' "${INBOX}" 2>/dev/null || true; }

state idle
check "an idle conductor: tell says it noted it" "noted conduct-e" "$(note)"
check "an idle conductor: the note is in its inbox" 1 "$(notes)"
check "an idle conductor: it is sent one prompt" 1 "$(prompts)"
check "the prompt tells it to read its inbox" 1 "$(grep -c "Read your inbox now" "${ROOT}/prompts.log" || true)"
note >/dev/null
check "a second note within a minute: both are in the inbox" 2 "$(notes)"
check "a second note within a minute: no second prompt" 1 "$(prompts)"
echo $(( $(date +%s) - 61 )) > "${INBOX}.woke"
note >/dev/null
check "a note a minute after the last prompt: another prompt" 2 "$(prompts)"

state idle; touch "${ROOT}/slow"
note >/dev/null & note >/dev/null & wait
rm -f "${ROOT}/slow"
check "two notes at once: both are in the inbox" 2 "$(notes)"
check "two notes at once: one prompt" 1 "$(prompts)"

state busy
check "a conductor mid-turn: tell says it noted it" "noted conduct-e" "$(note)"
check "a conductor mid-turn: the note is in its inbox" 1 "$(notes)"
check "a conductor mid-turn: no prompt" 0 "$(prompts)"

state busy
echo '{"type":"assistant","message":{"model":"claude-opus-5-5","stop_reason":"end_turn"}}' > "${CLAUDE_PROJECTS_DIR}/p/sc.jsonl"
note >/dev/null
check "busy only with background jobs (its turn ended): the note is in its inbox" 1 "$(notes)"
check "busy only with background jobs (its turn ended): one prompt" 1 "$(prompts)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
