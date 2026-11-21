#!/usr/bin/env bash
# status_states_test.sh — status's agent states from Claude Code's sessions and herdr, in a project
# whose panes are w2's: a working agent whose pane is on the usage-limit dialog is usage-limit, and
# one idle under the usage-limit waiting line is idle. An agent list that is not JSON is no agent list.
# herdr, gh and claude are stubs on PATH.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWARM="${HERE}/../bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0
check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}

# The claude stub goes first on PATH, so no run here reaches the real claude. herdr lists the
# project's agents; its agent read of s-limit's pane (w2:p10) shows the usage-limit dialog, or with
# LIMIT_WAITING the waiting line after it; with GARBLED its agent list is not JSON. gh fails.
mkdir -p "${ROOT}/bin" "${ROOT}/projects/p" "${ROOT}/tmp"
cp "${HERE}/claude_stub.sh" "${ROOT}/bin/claude"
cat > "${ROOT}/bin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") if [ -n "${GARBLED:-}" ]; then echo 'not json'; else echo '{"result":{"agents":[{"name":"s-limit","agent_status":"working","pane_id":"w2:p10"}]}}'; fi ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w2:p10"}]}}' ;;
  "agent read") [ "$3" = w2:p10 ] || exit 0
    if [ -n "${LIMIT_WAITING:-}" ]; then printf '%s\n' '⏺ Working on it.' '⚠ Usage limit reached · limit resets 3pm' '  Continuing shortly'
    else printf '%s\n' '⏺ Working on it.' '❯ 1. Stop and wait for limit to reset' '  2. Wait here, then continue automatically'; fi ;;
  *) exit 1 ;;
esac
STUB
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/bin/gh"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh"
export PATH="${ROOT}/bin:${PATH}" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TMPDIR="${ROOT}/tmp"

S="${ROOT}/s"; mkdir -p "${S}/.swarm/state" "${S}/docs/stories"; git -C "${S}" init -q; touch "${S}/docs/stories/README.md"
printf 'w2:p10 s-limit\n' > "${S}/.swarm/state/t"
printf '2026-10-13\tcode\ts-limit\tclaude\topus\thigh\tlimit\n' > "${S}/.swarm/agents.tsv"
status() { # <session status> [status args] — swarm.sh status in S, with s-limit's session in that state
  printf '[{"sessionId":"limit","status":"%s"}]' "$1" > "${ROOT}/s.json"; shift
  (cd "${S}" || exit 1; HERDR_ENV=1 CLAUDE_STUB_AGENTS="${ROOT}/s.json" bash "${SWARM}" status "$@" 2>&1 || true)
}

st="$(status busy)"
check "status shows usage-limit for a working agent whose pane is on the usage-limit dialog" grep -qE '^  s-limit +usage-limit  \[' <<< "${st}"
st="$(LIMIT_WAITING=1 status idle --all)"
check "an idle agent under the usage-limit waiting line is idle in status" grep -qE '^  s-limit +idle: ' <<< "${st}"
st="$(GARBLED=1 status busy)"
check "with an agent list that is not JSON, status says herdr gave none" grep -qF "(herdr gave no agent list)" <<< "${st}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
