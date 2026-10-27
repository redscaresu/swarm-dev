#!/usr/bin/env bash
# tell_blocked_test.sh — `tell <slug> nudge <file>` to an agent listed as waiting or blocked reads its
# pane once (pane_clear) and sends the tell only when the pane shows an empty input box with nothing
# over it; otherwise it refuses as before, says what the pane shows or that it could not be read, and
# sends no keys. When herdr then refuses the tell as blocked (agent_blocked, before any key), tell
# reads the pane again (tell_unblock) and, with it clear, reports a Claude agent idle to herdr
# (herdr_idle: its session and resume command), says so, logs a stale-blocked incident and sends once
# more. Three ways an agent is listed so:
#   waiting: Claude Code lists its session waiting (on a dialog), and herdr reads it blocked, as the
#     plugin's hook reported. A clear pane is reported idle, then told, also when the box is drawn as
#     Claude Code draws it (the prompt, then a no-break space). A permission prompt, text typed in the
#     box, a command running, or manual mode is refused, as is a pane herdr gives no text for, with no
#     report and no keys;
#   herdr:blocked: an agent herdr answers for (a Claude agent with no session on record). Its blocked is
#     herdr's own read of the screen, so a clear pane gets no report: while herdr still reads it blocked
#     when it sends, herdr refuses the tell and no key goes, and the refusal says why no report was sent;
#     once herdr no longer reads it blocked, it is told. A permission prompt is refused. So is an agent
#     whose name a codex agent took after a Claude one: herdr_idle reads its newest agents.tsv line;
#   herdr only: Claude Code lists the session idle while herdr still reads it blocked (#540's builder,
#     2026-10-26). herdr refuses the tell; a clear pane is then reported idle and told. A permission
#     prompt gets no report, and the tell fails on herdr's refusal (agent_blocked), saying the pane is
#     not clear, with no key sent. A permission prompt raised just after the pane read (its hook's blocked
#     report stamped then) outranks the idle report, whose --seq is from before the read, so herdr
#     refuses the second try too.
# herdr and claude are stubs on PATH. herdr lists b1 with ${ROOT}/status and refuses a prompt while
# ${ROOT}/live reads blocked, as herdr does before sending any input. A report-agent is logged to
# ${ROOT}/reports.log and, as herdr does, taken only when its --seq is above the last one taken
# (${ROOT}/lastseq); an idle one taken sets both to idle. With ${ROOT}/raise, the pane read also
# takes a blocked report stamped as it ends. Every prompt or key herdr takes is logged to
# ${ROOT}/keys.log. Its pane text is ${ROOT}/screen, a screen from tests/fixtures/panes.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWARM="${HERE}/../bin/swarm.sh"
FX="${HERE}/fixtures/panes"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export HOME="${ROOT}/home" CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/claude-config/projects"
export CLAUDE_STUB_AGENTS="${ROOT}/claude.json"
mkdir -p "${HOME}" "${ROOT}/bin" "${CLAUDE_PROJECTS_DIR}/p"
cp "${HERE}/claude_stub.sh" "${ROOT}/bin/claude"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

printf '#!/bin/sh\nF="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
case "$1 $2" in
  "agent list") printf '{"result":{"agents":[{"name":"b1","agent_status":"%s","pane_id":"w:9"}]}}\n' "$(cat "$F/status")" ;;
  "agent get") printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "$(cat "$F/status")" ;;
  "agent read") cat "$F/screen"
    if [ -f "$F/raise" ]; then python3 -c 'import time; print(time.time_ns())' > "$F/lastseq"; echo blocked > "$F/live"; fi ;;
  "agent prompt")
    if [ "$(cat "$F/live")" = blocked ]; then echo '{"error":{"code":"agent_blocked","message":"agent is blocked"}}' >&2; exit 1; fi
    echo "$*" >> "$F/keys.log"; echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent send-keys"|"pane send-keys"|"pane send-text"|"pane run") echo "$*" >> "$F/keys.log" ;;
  "pane report-agent") echo "$*" >> "$F/reports.log"; seq="" prev=""
    for a in "$@"; do [ "${prev}" != --seq ] || seq="${a}"; prev="${a}"; done
    [ "${seq:-0}" -gt "$(cat "$F/lastseq")" ] || exit 0
    echo "${seq}" > "$F/lastseq"
    case "$*" in *"--state idle"*) echo idle > "$F/live"; echo idle > "$F/status" ;; esac ;;
esac
EOF
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/claude"

p="${ROOT}/proj"
mkdir -p "${p}/.claude/swarm" "${p}/docs/epics" "${p}/docs/stories" "${p}/.swarm/state"
: > "${p}/.claude/swarm/config"
git -C "${p}" init -q
echo "w:9 b1" > "${p}/.swarm/state/b1"   # its pane, as start_agent records one
echo "carry on with the brief" > "${ROOT}/msg"
RESUME="${CLAUDE_CONFIG_DIR}/swarm-dev/resume"
mkdir -p "${RESUME}"
printf '%s\n' python3 -I "${RESUME}/sb.py" claude --resume sb --model opus > "${RESUME}/sb.argv"   # as resume_file writes it

# agent <session> — b1's agents.tsv line, a Claude agent with session <session>; - is none on record,
# so herdr answers for it.
agent() { printf '2026-10-27\tcode\tb1\tclaude\topus\thigh\t%s\n' "$1" > "${p}/.swarm/agents.tsv"; }
# setup <session status> <herdr's list> <herdr's check at send> <screen> — a fresh tell: no keys,
# reports or events. <screen> is a fixture, or nbsp (empty-box.txt with Claude Code's no-break space
# after the box's prompt) or none (herdr gives no text).
setup() {
  echo "[{\"sessionId\": \"sb\", \"status\": \"$1\", \"waitingFor\": \"dialog open\"}]" > "${ROOT}/claude.json"
  echo "$2" > "${ROOT}/status"; echo "$3" > "${ROOT}/live"
  case "$4" in
    nbsp) perl -CSD -Mutf8 -pe 's/^❯ $/❯\x{a0}/' "${FX}/empty-box.txt" > "${ROOT}/screen"
      grep -q $'^\xe2\x9d\xaf\xc2\xa0$' "${ROOT}/screen" || { echo "setup: no no-break space in the box" >&2; exit 1; } ;;
    none) : > "${ROOT}/screen" ;;
    *) cp "${FX}/$4" "${ROOT}/screen" ;;
  esac
  : > "${ROOT}/keys.log"; : > "${ROOT}/reports.log"; echo 0 > "${ROOT}/lastseq"; rm -f "${ROOT}/raise" "${p}/.swarm/events.tsv"
}
tell() { (cd "${p}" && env -u SWARM_PROJECT -u HERDR_PANE_ID HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" tell b1 nudge "${ROOT}/msg" 2>&1) || true; }
prompts() { grep -c '^agent prompt w:9 ' "${ROOT}/keys.log" || true; }
keys() { wc -l < "${ROOT}/keys.log" | tr -d ' '; }
reports() { wc -l < "${ROOT}/reports.log" | tr -d ' '; }
said() { grep -qF -- "$1" <<< "$2" && echo yes || echo no; }
stale() { grep -c $'\tincident\tb1\t.*\tstale-blocked: herdr listed it blocked with its pane clear; reported idle$' "${p}/.swarm/events.tsv" 2>/dev/null || true; }
REFUSED="b1: herdr did not send it the brief: it is blocked on a question (agent_blocked); answer it, see herdr agent read b1"

agent sb
setup waiting blocked blocked empty-box.txt
out="$(tell)"
check "waiting, an empty input box: told" yes "$(said "told b1" "${out}")"
check "waiting, an empty input box: one prompt" 1 "$(prompts)"
check "waiting, an empty input box: herdr is told it is idle, with its session and resume command" "yes|yes" \
  "$(said "report-agent w:9 --source swarm --agent claude --state idle --seq " "$(cat "${ROOT}/reports.log")")|$(said "--agent-session-id sb -- python3 -I ${RESUME}/sb.py claude --resume sb --model opus" "$(cat "${ROOT}/reports.log")")"
check "waiting, an empty input box: tell says it reported it idle, and logs a stale-blocked incident" "yes 1" \
  "$(said "b1: herdr listed it blocked, but its pane reads clear, so it was reported idle to herdr; sending again" "${out}") $(stale)"
setup waiting blocked blocked nbsp
out="$(tell)"
check "waiting, an empty input box with a no-break space after its prompt: told" "yes 1" "$(said "told b1" "${out}") $(prompts)"
# <fixture>:<case>:<what tell says the pane shows>
for fx in "prompt.txt:a permission prompt:a prompt or dialog" "typed-box.txt:text typed in the input box:text in the input box" \
    "mid-command-manual.txt:a command running over an empty box:a running command" "manual.txt:manual mode under an empty box:manual mode"; do
  shows="${fx##*:}" fx="${fx%:*}"
  setup waiting blocked blocked "${fx%%:*}"
  out="$(tell)"
  check "waiting, ${fx#*:}: refused, naming what the pane shows" yes "$(said "b1 is waiting on dialog open, and its pane shows ${shows}; answer it (herdr agent read b1), then tell it" "${out}")"
  check "waiting, ${fx#*:}: no keys and no report" "0 0" "$(keys) $(reports)"
done
setup waiting blocked blocked none
out="$(tell)"
check "waiting, a pane herdr gives no text for: refused, saying so" yes "$(said "b1 is waiting on dialog open, and its pane could not be read; answer it (herdr agent read b1), then tell it" "${out}")"
check "waiting, a pane herdr gives no text for: no keys and no report" "0 0" "$(keys) $(reports)"

agent -
setup idle blocked blocked empty-box.txt
out="$(tell)"
check "herdr:blocked, an empty input box, herdr still blocked when it sends: herdr refuses it, saying no report was sent" yes \
  "$(said "${REFUSED}; its pane reads clear, but herdr answers for it (no Claude session with a resume command on record), so no idle report was sent" "${out}")"
check "herdr:blocked, an empty input box, herdr still blocked when it sends: no keys and no report" "0 0" "$(keys) $(reports)"
setup idle blocked idle empty-box.txt
out="$(tell)"
check "herdr:blocked, an empty input box, herdr no longer blocked when it sends: told" yes "$(said "told b1" "${out}")"
check "herdr:blocked, an empty input box, herdr no longer blocked when it sends: one prompt, no report" "1 0" "$(prompts) $(reports)"
setup idle blocked idle prompt.txt
out="$(tell)"
check "herdr:blocked, a permission prompt: refused" yes "$(said "b1 is waiting on a prompt, and its pane shows a prompt or dialog; answer it (herdr agent read b1), then tell it" "${out}")"
check "herdr:blocked, a permission prompt: no keys" 0 "$(keys)"
agent sb; printf '2026-10-27\tcode\tb1\tcodex\tgpt\thigh\t-\n' >> "${p}/.swarm/agents.tsv"   # a codex agent took the name
setup idle blocked blocked empty-box.txt
out="$(tell)"
check "a name a codex agent took after a Claude one: no report of the old session, no keys" "0 0" "$(reports) $(keys)"

agent sb
setup idle blocked blocked empty-box.txt
out="$(tell)"
check "session idle, herdr still blocked, an empty input box: reported idle, then told" "yes 1 1" \
  "$(said "told b1" "${out}") $(reports) $(prompts)"
setup idle blocked blocked prompt.txt
out="$(tell)"
check "session idle, herdr blocked, a permission prompt: herdr refuses it (agent_blocked), saying the pane is not clear" yes \
  "$(said "${REFUSED}; its pane shows a prompt or dialog" "${out}")"
check "session idle, herdr blocked, a permission prompt: no keys and no report" "0 0" "$(keys) $(reports)"
setup idle blocked blocked empty-box.txt; touch "${ROOT}/raise"
out="$(tell)"
check "a permission prompt raised just after the pane read: its blocked outranks the idle report, and herdr refuses the tell" yes \
  "$(said "${REFUSED}; it was sent again after its pane read clear and it was reported idle to herdr" "${out}")"
check "a permission prompt raised just after the pane read: no keys" 0 "$(keys)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
