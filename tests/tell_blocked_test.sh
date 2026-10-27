#!/usr/bin/env bash
# tell_blocked_test.sh — `tell <slug> nudge <file>` to an agent listed as waiting or blocked reads its
# pane once (pane_clear) and sends the tell only when the pane shows an empty input box with nothing
# over it; otherwise it refuses as before and sends no keys. Three ways an agent is listed so:
#   waiting: Claude Code lists its session waiting (on a dialog), and herdr reads it blocked, as the
#     plugin's hook reported. A clear pane is reported idle to herdr (herdr_idle: its session and
#     resume command), then told. A permission prompt, text typed in the box, a command running, or
#     manual mode is refused, with no report and no keys;
#   herdr:blocked: an agent herdr answers for (a Claude agent with no session on record). A clear
#     pane is told, with no report: herdr's own check when it sends has the last word. A permission
#     prompt is refused;
#   herdr only: Claude Code lists the session idle while herdr still reads it blocked (#540's builder,
#     2026-10-26). A clear pane is reported idle, then told. A permission prompt gets no report, and
#     herdr refuses the tell (agent_blocked) before any key. A permission prompt raised just after the
#     pane read (its hook's blocked report stamped then) outranks the idle report, whose --seq is from
#     before the read, so herdr still refuses the tell and no key goes.
# herdr and claude are stubs on PATH. herdr lists b1 with ${ROOT}/status and refuses a prompt while
# ${ROOT}/live reads blocked, as herdr does before sending any input. A report-agent is logged to
# ${ROOT}/reports.log and, as herdr does, taken only when its --seq is above the last one taken
# (${ROOT}/lastseq); an idle one taken sets both to idle. With ${ROOT}/raise, the pane read also
# takes a blocked report stamped as it ends. Every prompt or key herdr takes is logged to
# ${ROOT}/keys.log. Its pane text is a screen from tests/fixtures/panes.
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
# setup <session status> <herdr's list> <herdr's check at send> <fixture> — a fresh tell: no keys, no reports.
setup() {
  echo "[{\"sessionId\": \"sb\", \"status\": \"$1\", \"waitingFor\": \"dialog open\"}]" > "${ROOT}/claude.json"
  echo "$2" > "${ROOT}/status"; echo "$3" > "${ROOT}/live"
  cp "${FX}/$4" "${ROOT}/screen"
  : > "${ROOT}/keys.log"; : > "${ROOT}/reports.log"; echo 0 > "${ROOT}/lastseq"; rm -f "${ROOT}/raise"
}
tell() { (cd "${p}" && env -u SWARM_PROJECT -u HERDR_PANE_ID HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" tell b1 nudge "${ROOT}/msg" 2>&1) || true; }
prompts() { grep -c '^agent prompt w:9 ' "${ROOT}/keys.log" || true; }
keys() { wc -l < "${ROOT}/keys.log" | tr -d ' '; }
reports() { wc -l < "${ROOT}/reports.log" | tr -d ' '; }
said() { grep -qF -- "$1" <<< "$2" && echo yes || echo no; }

agent sb
setup waiting blocked blocked empty-box.txt
out="$(tell)"
check "waiting, an empty input box: told" yes "$(said "told b1" "${out}")"
check "waiting, an empty input box: one prompt" 1 "$(prompts)"
check "waiting, an empty input box: herdr is told it is idle, with its session and resume command" "yes|yes" \
  "$(said "report-agent w:9 --source swarm --agent claude --state idle --seq " "$(cat "${ROOT}/reports.log")")|$(said "--agent-session-id sb -- python3 -I ${RESUME}/sb.py claude --resume sb --model opus" "$(cat "${ROOT}/reports.log")")"
for fx in prompt.txt:"a permission prompt" typed-box.txt:"text typed in the input box" \
    mid-command-manual.txt:"a command running over an empty box" manual.txt:"manual mode under an empty box"; do
  setup waiting blocked blocked "${fx%%:*}"
  out="$(tell)"
  check "waiting, ${fx#*:}: refused" yes "$(said "b1 is waiting on dialog open; answer it (herdr agent read b1), then tell it" "${out}")"
  check "waiting, ${fx#*:}: no keys and no report" "0 0" "$(keys) $(reports)"
done

agent -
setup idle blocked idle empty-box.txt
out="$(tell)"
check "herdr:blocked, an empty input box: told" yes "$(said "told b1" "${out}")"
check "herdr:blocked, an empty input box: one prompt, no report" "1 0" "$(prompts) $(reports)"
setup idle blocked idle prompt.txt
out="$(tell)"
check "herdr:blocked, a permission prompt: refused" yes "$(said "b1 is waiting on a prompt; answer it (herdr agent read b1), then tell it" "${out}")"
check "herdr:blocked, a permission prompt: no keys" 0 "$(keys)"

agent sb
setup idle blocked blocked empty-box.txt
out="$(tell)"
check "session idle, herdr still blocked, an empty input box: reported idle, then told" "yes 1 1" \
  "$(said "told b1" "${out}") $(reports) $(prompts)"
setup idle blocked blocked prompt.txt
out="$(tell)"
check "session idle, herdr blocked, a permission prompt: herdr refuses it (agent_blocked)" yes \
  "$(said "b1: herdr did not send it the brief: it is blocked on a question (agent_blocked)" "${out}")"
check "session idle, herdr blocked, a permission prompt: no keys and no report" "0 0" "$(keys) $(reports)"
setup idle blocked blocked empty-box.txt; touch "${ROOT}/raise"
out="$(tell)"
check "a permission prompt raised just after the pane read: its blocked outranks the idle report, and herdr refuses the tell" yes \
  "$(said "b1: herdr did not send it the brief: it is blocked on a question (agent_blocked)" "${out}")"
check "a permission prompt raised just after the pane read: no keys" 0 "$(keys)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
