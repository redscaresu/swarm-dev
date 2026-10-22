#!/usr/bin/env bash
# tell_note_test.sh — `tell conduct-<epic> note <file>` writes the note to the conductor's inbox and,
# when the conductor's turn has ended (idle, or busy only with background jobs: its session log ends
# on an assistant entry that ended its turn), sends it one prompt to process the inbox as its brief
# says (via <inbox>.reading.md). One mid-turn gets the note in its inbox and no prompt. Each inbox
# wakes it once: a second note, or two at once (each prompt takes a second with ${ROOT}/slow), send
# one prompt, even when the one that starts the inbox is slow to clear the last claim (${ROOT}/slowrm);
# a note after the conductor moved the inbox away to read it sends another. A lock a killed tell left
# is cleared. A prompt that fails (${ROOT}/promptfail) warns and lets the next note prompt again. No
# prompt goes to a conductor that wrote its report, or one paused for upgrade's handover
# (<inbox>.upgrade), though the note lands. herdr and claude are stubs on PATH: herdr lists the conductor from ${ROOT}/agents ("<name>
# <pane> <session>") and logs each agent prompt to ${ROOT}/prompts.log; claude agents --json prints
# ${ROOT}/claude.json.
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
  "agent prompt") [ ! -f "$F/promptfail" ] || exit 1; [ ! -f "$F/slow" ] || sleep 1; echo "$*" >> "$F/prompts.log" ;;
esac
EOF
# rm takes 4 s over <inbox>.woke while ${ROOT}/slowrm exists: the note that starts an inbox pauses
# before it clears the claim, so a note beside it can claim and prompt in between.
printf '#!/bin/sh\ncase "$*" in *.woke) [ ! -f "%s/slowrm" ] || sleep 4 ;; esac\nexec /bin/rm "$@"\n' "${ROOT}" > "${ROOT}/bin/rm"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/claude" "${ROOT}/bin/rm"

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
check "the prompt points it at its brief's .reading.md steps" 1 "$(grep -c "mv the inbox to ${p}/.swarm/inbox/conduct-e.reading.md" "${ROOT}/prompts.log" || true)"
note >/dev/null
check "a second note within a minute: both are in the inbox" 2 "$(notes)"
check "a second note within a minute: no second prompt" 1 "$(prompts)"
mv "${INBOX}" "${INBOX%.md}.reading.md"   # the conductor takes the inbox to read it
note >/dev/null
check "a note after the conductor read its inbox: another prompt" 2 "$(prompts)"

state idle; touch "${ROOT}/slow"
note >/dev/null & note >/dev/null & wait
rm -f "${ROOT}/slow"
check "two notes at once: both are in the inbox" 2 "$(notes)"
check "two notes at once: one prompt" 1 "$(prompts)"

state idle; touch "${ROOT}/slowrm"
note >/dev/null & sleep 0.5; note >/dev/null & wait   # the second appends once the first has checked the inbox
rm -f "${ROOT}/slowrm"
check "two notes at once, one slow to clear the claim: one prompt" 1 "$(prompts)"

state idle; mkdir -p "${INBOX}.lock"; touch -t 202001010000 "${INBOX}.lock"   # left by a killed tell
note >/dev/null
check "a lock a killed tell left: cleared, and the note prompts" "1 no" "$(prompts) $([[ -e "${INBOX}.lock" ]] && echo yes || echo no)"

state idle; touch "${ROOT}/promptfail"
said="$(note)"
rm -f "${ROOT}/promptfail"
check "a prompt that fails: tell warns" 1 "$(grep -c "warning: conduct-e was not prompted to read its inbox" <<< "${said}" || true)"
check "a prompt that fails: its claim is given back" no "$([[ -e "${INBOX}.woke" ]] && echo yes || echo no)"
note >/dev/null
check "a prompt that fails: the next note prompts again" 1 "$(prompts)"

state busy
check "a conductor mid-turn: tell says it noted it" "noted conduct-e" "$(note)"
check "a conductor mid-turn: the note is in its inbox" 1 "$(notes)"
check "a conductor mid-turn: no prompt" 0 "$(prompts)"

state busy
echo '{"type":"assistant","message":{"model":"claude-opus-5-5","stop_reason":"end_turn"}}' > "${CLAUDE_PROJECTS_DIR}/p/sc.jsonl"
note >/dev/null
check "busy only with background jobs (its turn ended): the note is in its inbox" 1 "$(notes)"
check "busy only with background jobs (its turn ended): one prompt" 1 "$(prompts)"

state idle; touch "${p}/.swarm/conduct-e.report.md"
note >/dev/null
rm -f "${p}/.swarm/conduct-e.report.md"
check "a conductor that wrote its report: the note is in its inbox" 1 "$(notes)"
check "a conductor that wrote its report: no prompt" 0 "$(prompts)"

state idle; mkdir -p "${p}/.swarm/inbox"; touch "${INBOX}.upgrade"
note >/dev/null
check "a conductor paused for upgrade's handover: the note is in its inbox" 1 "$(notes)"
check "a conductor paused for upgrade's handover: no prompt" 0 "$(prompts)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
