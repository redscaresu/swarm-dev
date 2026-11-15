#!/usr/bin/env bash
# api_model_error_test.sh — wait on an agent whose turn stopped on an API error. A model error (a 400
# or 404 that names the model: the provider refused the model ID the session sends) gets no resume:
# wait prints `stuck: model error (<line>)` at once, exits 4 and logs a model-error incident; an
# expired login behind it is auth. Any other API error (a 529, a 503, a 400 that names no model) keeps
# its three resumes and ends on `stuck: api error`, exit 4.
# herdr is a stub on PATH whose `agent prompt` calls (the resumes) land in herdr.log; claude is the
# claude stub, which gives the session's state.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects"
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}" CLAUDE_STUB_AGENTS="${ROOT}/claude.json"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# herdr: logs every call. Agent a is in pane w:950 and herdr says it is done. `agent read` prints the
# file screen. Each `agent prompt` (a resume) adds the prompt to screen, then the file reerr's line,
# so the resumed turn stops on that API error again.
mkdir -p "${ROOT}/bin"
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
case "$1 $2" in
  "agent list")   echo '{"result":{"agents":[{"name":"a","agent_status":"done","pane_id":"w:950"}]}}' ;;
  "pane list")    echo '{"result":{"panes":[]}}' ;;
  "agent wait")   echo '{"result":{"agent":{"agent_status":"done"}}}' ;;
  "agent read")   cat "$H/screen" ;;
  "agent prompt") [ -e "$H/reerr" ] && printf '> %s\n%s\n\n> \n' "$4" "$(cat "$H/reerr")" >> "$H/screen"
                  echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
esac
EOF
chmod +x "${ROOT}/bin/herdr"
printf '#!/bin/sh\necho "[]"\n' > "${ROOT}/bin/gh"; chmod +x "${ROOT}/bin/gh"

p="${ROOT}/proj"
mkdir -p "${p}/.claude/swarm" "${p}/.swarm/state"; : > "${p}/.claude/swarm/config"
echo "w:950 a" > "${p}/.swarm/state/wait-a"   # this project's agent a, in a pane it recorded
printf '2026-11-14\tconduct\ta\tclaude\topus\thigh\tsess-a\n' > "${p}/.swarm/agents.tsv"
session() { echo "[{\"sessionId\":\"sess-a\",\"status\":\"$1\"}]" > "${ROOT}/claude.json"; }
# waitrc — wait on a, a 20 s timeout in 1 s slices: "<stdout>|exit <rc>|<resumes sent>".
waitrc() {
  local out rc=0
  : > "${ROOT}/herdr.log"; : > "${p}/.swarm/events.tsv"; rm -rf "${p}/.swarm/panes"
  out="$(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 SWARM_STALL_POLL_MS=1000 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" wait a 20000 2>/dev/null)" || rc=$?
  echo "${out}|exit ${rc}|$(grep -c '^agent prompt w:950 ' "${ROOT}/herdr.log" || true)"
}
screen() { printf '%s\n' '⏺ Running the tests.' "⏺ $1" '' '> ' > "${ROOT}/screen"; }
# incidents <kind> <line start> — events.tsv's incident lines for a whose outcome is `<kind>: <line start>...`.
incidents() { awk -F'\t' -v o="$1: $2" '$2 == "incident" && $3 == "a" && index($5, o) == 1 { n++ } END { print n + 0 }' "${p}/.swarm/events.tsv"; }

# The #899 line, longer than the 200 characters wait keeps of it. The session reads busy (background
# shells keep it so), so settle's read finds the stop.
L899='API Error (anthropic.claude-fable-5-2): 400 Invocation of model ID anthropic.claude-fable-5-2 with on-demand throughput isn'"'"'t supported. Retry your request with the ID or ARN of an inference profile that contains this model.'
session busy; screen "${L899}"; rm -f "${ROOT}/reerr"
check "the #899 model-ID line, session busy: stuck: model error with the line cut to 200, exit 4, no resume" \
  "stuck: model error (${L899:0:200})|exit 4|0" "$(waitrc)"
check "that stop is one model-error incident in events.tsv" "1" "$(incidents model-error 'API Error (anthropic.claude-fable-5-2): 400 Invocation of model ID')"

# An invalid model identifier, the session idle: wait's own read of the pane finds it.
L400='API Error (eu.anthropic.claude-x-9): 400 The provided model identifier is invalid.'
session idle; screen "${L400}"
check "a 400 invalid model identifier, session idle: stuck: model error, exit 4, no resume" \
  "stuck: model error (${L400})|exit 4|0" "$(waitrc)"
check "that stop is one model-error incident in events.tsv" "1" "$(incidents model-error "${L400}")"

# A 404 whose text is model_not_found, the session busy: a model error too.
L404='API Error: 404 {"type":"error","error":{"code":"model_not_found","message":"The model does not exist"}}'
session busy; screen "${L404}"
check "a 404 model_not_found, session busy: stuck: model error, exit 4, no resume" \
  "stuck: model error (${L404})|exit 4|0" "$(waitrc)"
check "that stop is one model-error incident in events.tsv" "1" "$(incidents model-error "${L404}")"

# An expired login behind a busy session's model-error stop (its transcript's last entry): auth, the
# user's /login, before any restart, and nothing sent.
mkdir -p "${CLAUDE_PROJECTS_DIR}/p"; tr="${CLAUDE_PROJECTS_DIR}/p/sess-a.jsonl"
printf '%s\n' '{"type":"assistant","error":"authentication_failed","message":{"content":[{"type":"text","text":"Login expired · Please run /login"}]}}' > "${tr}"
session busy; screen "${L899}"
check "a busy model-error stop on an expired login returns auth and sends nothing" "auth|exit 0|0" "$(waitrc)"
rm -f "${tr}"

# A passing error keeps today's resumes: each resumed turn stops on it again, so three resumes, then stuck.
# A 400 that names no model is a passing error too.
for l in 'API Error: 529 Overloaded' 'API Error (eu.anthropic.claude-x-9): 503 Service Unavailable' \
  'API Error: 400 {"type":"error","error":{"type":"invalid_request_error","message":"messages: text content blocks must be non-empty"}}'; do
  session busy; screen "${l}"; echo "⏺ ${l}" > "${ROOT}/reerr"
  check "${l}: three resumes, then stuck: api error, exit 4" "stuck: api error|exit 4|3" "$(waitrc)"
  check "${l}: logged as api-error, never model-error" "yes|0" \
    "$([[ $(incidents api-error "${l}") -ge 1 ]] && echo yes || echo no)|$(incidents model-error "")"
done

if [[ ${fails} -ne 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
