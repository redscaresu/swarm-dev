#!/usr/bin/env bash
# tell_note_test.sh — `tell conduct-<epic> note <file>` writes the note to the conductor's inbox and,
# when the conductor's turn has ended (idle, or busy only with background jobs: its session log ends
# on an assistant entry that ended its turn, system entries aside; its session is agents.tsv's when
# herdr lists none, as herdr 0.9.5 does; with none recorded either, herdr's working stands), sends it
# one prompt to process the inbox as its brief says (via <inbox>.reading.md) and end its turn,
# leaving its waits alone. One mid-turn gets the note and no prompt. One prompt a minute at most (SWARM_NOTE_WAKE_SECS, 4 here), per conductor: a second
# note within it, after the conductor took the inbox to read it too, or two at once (each prompt
# takes a second with ${ROOT}/slow), send one prompt now; a deferred check sends one more once the
# minute is up while the inbox is still there, which also retries a prompt that was dropped (one
# sent inside a pending check's minute too, at the end of its own), and sends none once the inbox
# was read. A lock a killed tell left is cleared; one held is warned of. A
# prompt that fails (${ROOT}/promptfail) warns, with no die line, and lets the next note prompt. No
# prompt goes to a conductor that wrote its report, or one paused for upgrade's handover
# (<inbox>.upgrade), though the note lands. A deferred check wakes the conductor that holds the name
# when it fires, never one a new conduct replaced. herdr and claude are stubs on PATH: herdr lists the
# conductor from ${ROOT}/agents ("<name> <pane> <session>") and logs each agent prompt to
# ${ROOT}/prompts.log; claude agents --json prints ${ROOT}/claude.json.
# Last, a builder told findings while herdr's screen reads it idle for every settle read of the first
# try and done only after them (plan-hld-command's tells, 2026-10-24), its log already holding the same
# findings from an earlier tell. It gets one prompt, logged ok, when its session shows it took them by
# the second settle read ($F/takes): it turns busy, or its log gets them as a pasted prompt (a short
# turn between two reads). Its session shows no sign of them with only another tell's prompt
# (othertell), a Task subagent's entry holding the findings' line (sidechain), a tool result holding it
# (toolresult) or an automated prompt holding it (notice): sent once more, and the done read after
# takes it. herdr idle on every read (never): sent twice, and the tell fails, not taken up.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
p="${ROOT}/o'proj"   # an apostrophe in the path, which the deferred check's trap must survive
# settle — wait (20 s at most) for the deferred check a note left to finish.
settle() { local i; for ((i = 0; i < 100; i++)); do compgen -G "${p}/.swarm/inbox/*.later" >/dev/null || return 0; sleep 0.2; done; }
trap 'settle; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/claude-config/projects"
export CLAUDE_STUB_AGENTS="${ROOT}/claude.json" SWARM_NOTE_WAKE_SECS=4
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
    { s = $3 == "-" ? "" : sprintf(",\"agent_session\":{\"value\":\"%s\"}", $3)
      printf "%s{\"name\":\"%s\",\"agent_status\":\"working\",\"pane_id\":\"%s\"%s}", (NR > 1 ? "," : ""), $1, $2, s }
    END { print "]}}" }' "$F/agents" ;;
  "agent prompt") [ ! -f "$F/promptfail" ] || exit 1; [ ! -f "$F/slow" ] || sleep 1; echo "$*" >> "$F/prompts.log" ;;
  "agent get") n=$(($(cat "$F/gets" 2>/dev/null || echo 0) + 1)); echo "${n}" > "$F/gets"
    if [ "${n}" -eq 3 ]; then case "$(cat "$F/takes" 2>/dev/null)" in
      busy) echo '[{"sessionId": "sb", "status": "busy"}]' > "$F/claude.json" ;;
      prompt) l='{"type":"user","message":{"content":"<pasted_content id=\"x\">\nFrom the conductor:\n\nstart s2 first\n</pasted_content>"}}' ;;
      othertell) l='{"type":"user","message":{"content":"From the conductor:\n\nreview round 9"}}' ;;
      sidechain) l='{"type":"user","isSidechain":true,"message":{"content":"From the conductor:\n\nstart s2 first"}}' ;;
      toolresult) l='{"type":"user","message":{"content":[{"type":"tool_result","content":"start s2 first"}]}}' ;;
      notice) l='{"type":"user","message":{"content":"<task-notification>start s2 first</task-notification>"}}' ;;
    esac; [ -z "${l:-}" ] || printf '%s\n' "${l}" >> "$F/claude-config/projects/p/sb.jsonl"; fi
    if [ "${n}" -le 4 ] || [ "$(cat "$F/takes" 2>/dev/null)" = never ]; then echo '{"result":{"agent":{"agent_status":"idle"}}}'
    else echo '{"result":{"agent":{"agent_status":"done","completion_seq":9}}}'; fi ;;
esac
EOF
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/claude"

mkdir -p "${p}/.claude/swarm" "${p}/docs/epics" "${p}/docs/stories" "${p}/.swarm/state"
: > "${p}/.claude/swarm/config"
git -C "${p}" init -q
printf -- '---\nstatus: active\n---\n' > "${p}/docs/epics/e.md"
echo "w:7 conduct-e" > "${p}/.swarm/state/tab"   # its pane, as start_agent records one
echo "conduct-e w:7 sc" > "${ROOT}/agents"
BASE="${p}/.swarm/inbox/conduct-e"; INBOX="${BASE}.md"
echo "start s2 first" > "${ROOT}/note"

# state <status> — Claude Code's status for the conductor's session, once the last deferred check is
# done; fresh: no inbox, stamp or prompt.
state() {
  settle
  echo "[{\"sessionId\": \"sc\", \"status\": \"$1\"}]" > "${ROOT}/claude.json"
  rm -rf "${p}/.swarm/inbox" "${CLAUDE_PROJECTS_DIR}/p/sc.jsonl"; : > "${ROOT}/prompts.log"
}
note() { (cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" tell conduct-e note "${ROOT}/note" 2>&1); }
prompts() { grep -c 'agent prompt w:7' "${ROOT}/prompts.log" || true; }
notes() { grep -c '^start s2 first$' "${INBOX}" 2>/dev/null || true; }
said() { grep -c "$1" "${ROOT}/prompts.log" || true; }

state idle
check "an idle conductor: tell says it noted it" "noted conduct-e" "$(note)"
check "an idle conductor: the note is in its inbox" 1 "$(notes)"
check "an idle conductor: it is sent one prompt" 1 "$(prompts)"
check "the prompt points it at its brief's .reading.md steps" 1 "$(said "mv the inbox to ${BASE}.reading.md")"
check "the prompt has it start what unblock --startable prints" 1 "$(said "Then run swarm.sh unblock --startable e and start each story it prints as startable:")"
check "the prompt has it end its turn and leave its waits alone" 1 "$(said "Then end your turn, leaving any wait or watch you have running alone; start one only if none runs")"
note >/dev/null
check "a second note within a minute: both are in the inbox" 2 "$(notes)"
check "a second note within a minute: no second prompt" 1 "$(prompts)"
settle
check "a second note within a minute: one deferred prompt once the minute is up" 2 "$(prompts)"
check "the deferred check removes its .later" no "$([[ -e "${BASE}.later" ]] && echo yes || echo no)"

state idle
note >/dev/null
mv "${INBOX}" "${BASE}.reading.md"   # the conductor takes the inbox to read it
note >/dev/null
check "a second note within a minute, after the conductor took the inbox: no second prompt" 1 "$(prompts)"
settle
check "a second note within a minute, after the conductor took the inbox: one deferred prompt" 2 "$(prompts)"

state idle
note >/dev/null; settle
check "a dropped prompt (inbox still there): retried once the minute is up" 2 "$(prompts)"

state busy
note >/dev/null   # mid-turn: no wake, and a check due a minute from now
sleep 2; echo "[{\"sessionId\": \"sc\", \"status\": \"idle\"}]" > "${ROOT}/claude.json"
note >/dev/null   # its turn has ended: woken, inside the check's minute
check "a wake inside a pending check's minute: sent" 1 "$(prompts)"
settle
check "a wake inside a pending check's minute: retried at the end of its own minute" 2 "$(prompts)"

state idle
note >/dev/null; rm -f "${INBOX}"; settle   # the conductor read it
check "a conductor that read its inbox: no retry" 1 "$(prompts)"

state idle; touch "${ROOT}/slow"
note >/dev/null & note >/dev/null & wait
rm -f "${ROOT}/slow"
check "two notes at once: both are in the inbox" 2 "$(notes)"
check "two notes at once: one prompt" 1 "$(prompts)"

state idle; mkdir -p "${BASE}.lock"; touch -t 202001010000 "${BASE}.lock"   # left by a killed tell
note >/dev/null
check "a lock a killed tell left: cleared, and the note prompts" "1 no" "$(prompts) $([[ -e "${BASE}.lock" ]] && echo yes || echo no)"

state idle; mkdir -p "${BASE}.lock"   # another tell holds it
out="$(note)"
rmdir "${BASE}.lock"
check "a held lock: tell warns" 1 "$(grep -c "warning: conduct-e was not prompted to read its inbox (${BASE}.lock is held)" <<< "${out}" || true)"
check "a held lock: the note is in its inbox, and no prompt" "1 0" "$(notes) $(prompts)"

state idle; touch "${ROOT}/promptfail"
out="$(note)"
rm -f "${ROOT}/promptfail"
check "a prompt that fails: tell warns" 1 "$(grep -c "warning: conduct-e was not prompted to read its inbox; it reads it after its wait" <<< "${out}" || true)"
check "a prompt that fails: no die line" 0 "$(grep -c '^swarm: ' <<< "${out}" || true)"
check "a prompt that fails: its stamp is taken back" no "$([[ -e "${BASE}.woke" ]] && echo yes || echo no)"
note >/dev/null
check "a prompt that fails: the next note prompts" 1 "$(prompts)"

state busy
check "a conductor mid-turn: tell says it noted it" "noted conduct-e" "$(note)"
check "a conductor mid-turn: the note is in its inbox" 1 "$(notes)"
check "a conductor mid-turn: no prompt" 0 "$(prompts)"
settle
check "a conductor mid-turn: no deferred prompt" 0 "$(prompts)"

state busy
echo '{"type":"assistant","message":{"model":"claude-opus-5-5","stop_reason":"end_turn"}}' > "${CLAUDE_PROJECTS_DIR}/p/sc.jsonl"
note >/dev/null
check "busy only with background jobs (its turn ended): the note is in its inbox" 1 "$(notes)"
check "busy only with background jobs (its turn ended): one prompt" 1 "$(prompts)"

# A live conductor idle between turns with background shells (Claude Code 2.1.311): the end_turn
# entry, then a stop_hook_summary and a turn_duration system entry, and nothing more while they run.
# herdr (0.9.5) lists no agent_session ("-" in ${ROOT}/agents), so its session is agents.tsv's.
state busy
echo "conduct-e w:7 -" > "${ROOT}/agents"
printf '2026-10-26\tconduct\tconduct-e\tclaude\topus\thigh\tsc\n' > "${p}/.swarm/agents.tsv"
cat > "${CLAUDE_PROJECTS_DIR}/p/sc.jsonl" <<'EOF'
{"type":"assistant","isSidechain":false,"message":{"role":"assistant","content":[{"type":"text","text":"x"}],"stop_reason":"end_turn"}}
{"type":"system","subtype":"stop_hook_summary","isSidechain":false,"hookCount":0,"hookInfos":[],"hookErrors":[],"preventedContinuation":false,"stopReason":"","hasOutput":false,"level":"info","toolUseID":"t1"}
{"type":"system","subtype":"turn_duration","isMeta":false,"isSidechain":false,"durationMs":0,"messageCount":0}
EOF
note >/dev/null
check "background shells after end_turn, no session from herdr: one prompt" 1 "$(prompts)"

state busy   # the same conductor mid-turn: a tool call waits on its result
printf '%s\n' '{"type":"assistant","isSidechain":false,"message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Bash","input":{}}],"stop_reason":"tool_use"}}' > "${CLAUDE_PROJECTS_DIR}/p/sc.jsonl"
note >/dev/null; settle
check "a tool call waiting on its result, no session from herdr: no prompt" 0 "$(prompts)"

state busy   # no session recorded either (a codex agent, or '-'): herdr's working stands, though a log ends its turn
printf '2026-10-26\tconduct\tconduct-e\tcodex\tdefault\thigh\t-\n' > "${p}/.swarm/agents.tsv"
printf '%s\n' '{"type":"assistant","isSidechain":false,"message":{"role":"assistant","content":[{"type":"text","text":"x"}],"stop_reason":"end_turn"}}' > "${CLAUDE_PROJECTS_DIR}/p/sc.jsonl"
note >/dev/null; settle
check "no session from herdr or agents.tsv, herdr working: no prompt" 0 "$(prompts)"
echo "conduct-e w:7 sc" > "${ROOT}/agents"; rm -f "${p}/.swarm/agents.tsv"

state idle; touch "${p}/.swarm/conduct-e.report.md"
note >/dev/null; settle
rm -f "${p}/.swarm/conduct-e.report.md"
check "a conductor that wrote its report: the note is in its inbox" 1 "$(notes)"
check "a conductor that wrote its report: no prompt" 0 "$(prompts)"

state idle; mkdir -p "${p}/.swarm/inbox"; touch "${BASE}.upgrade"
note >/dev/null; settle
check "a conductor paused for upgrade's handover: the note is in its inbox" 1 "$(notes)"
check "a conductor paused for upgrade's handover: no prompt" 0 "$(prompts)"

state idle
note >/dev/null
echo "w:8 conduct-e" > "${p}/.swarm/state/tab"; echo "conduct-e w:8 sc" > "${ROOT}/agents"   # a new conduct took the name
settle
check "a conductor replaced before the deferred check: the old pane is not prompted again" 1 "$(prompts)"
check "a conductor replaced before the deferred check: the new one is" 1 "$(grep -c "agent prompt w:8" "${ROOT}/prompts.log" || true)"

settle
echo "w:9 b1" > "${p}/.swarm/state/b1"; echo "b1 w:9 sb" >> "${ROOT}/agents"
printf '2026-10-24\tcode\tb1\tclaude\topus\thigh\tsb\n' >> "${p}/.swarm/agents.tsv"
for how in busy:1:ok prompt:1:ok othertell:2:ok sidechain:2:ok toolresult:2:ok notice:2:ok never:2:taken; do
  want="${how#*:}" how="${how%%:*}" end="${want#*:}" want="${want%%:*}"
  echo "${how}" > "${ROOT}/takes"; rm -f "${ROOT}/gets"; : > "${ROOT}/prompts.log"
  printf '%s\n' '{"type":"user","message":{"content":"From the conductor:\n\nstart s2 first"}}' > "${CLAUDE_PROJECTS_DIR}/p/sb.jsonl"   # an earlier tell's
  echo '[{"sessionId": "sb", "status": "idle"}]' > "${ROOT}/claude.json"
  out="$(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 SWARM_SLEEP_SCALE=0.01 SWARM_PROMPT_TIMEOUT_MS=15000 PATH="${ROOT}/bin:${PATH}" \
    bash "${SWARM}" tell b1 findings "${ROOT}/note" 2>&1)" || true
  check "findings to a builder whose session shows ${how} while herdr read it idle: sent ${want} time(s)" "${want}" "$(grep -c 'agent prompt w:9' "${ROOT}/prompts.log" || true)"
  check "findings to a builder whose session shows ${how} while herdr read it idle: no warning" no \
    "$(grep -q "did not show the turn start" <<< "${out}" && echo yes || echo no)"
  if [[ "${end}" == ok ]]; then
    check "findings to a builder whose session shows ${how} while herdr read it idle: told, and logged ok" "yes|ok" \
      "$(grep -qx "told b1" <<< "${out}" && echo yes || echo no)|$(awk -F'\t' '$2 == "tell:findings" && $3 == "b1" { o = $5 } END { print o }' "${p}/.swarm/events.tsv")"
  else
    check "findings to a builder whose session never shows them, herdr idle throughout: the tell fails, not taken up" yes \
      "$(awk -F'\t' '$2 == "tell:findings" && $3 == "b1" { o = $5 } END { print o }' "${p}/.swarm/events.tsv" | grep -q '^b1: the brief was not taken up: herdr sent it the brief twice' && echo yes || echo no)"
  fi
done

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
