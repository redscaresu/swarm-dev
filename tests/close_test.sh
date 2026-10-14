#!/usr/bin/env bash
# close_test.sh — close shuts every tab that carries the agent's label, one id per herdr call, even
# when two tabs share it, and archives the agent's session log once. herdr is a stub on PATH that
# records each tab close.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; CLOSED="${ROOT}/closed"
mkdir -p "${P}/.swarm/state" "${P}/docs/stories" "${ROOT}/bin"
git -C "${P}" init -q
: > "${CLOSED}"
cat > "${ROOT}/bin/herdr" <<STUB
#!/bin/sh
case "\$1 \$2" in
  "tab list") echo '{"result":{"tabs":[{"tab_id":"w:t1","label":"scope-x"},{"tab_id":"w:t2","label":"scope-x"},{"tab_id":"w:t3","label":"other"}]}}' ;;
  "tab close") printf '<%s>\\n' "\$3" >> "${CLOSED}" ;;
  "agent list") echo '{"result":{"agents":[]}}' ;;
  "pane list") echo '{"result":{"panes":[]}}' ;;
esac
STUB
chmod +x "${ROOT}/bin/herdr"
echo "w:p1 lead-x" > "${P}/.swarm/state/scope-x"
# scope-x has a Claude session (an older line for the same name came first), and so does lead-x, the
# agent in its tab; codex-y has none.
mkdir -p "${CLAUDE_CONFIG_DIR}/projects/p"
printf '{"type":"user","cwd":"/x"}\n' > "${CLAUDE_CONFIG_DIR}/projects/p/sx.jsonl"
printf '{"type":"user","cwd":"/l"}\n' > "${CLAUDE_CONFIG_DIR}/projects/p/lx.jsonl"
printf '%s\n' $'2026-10-01\tplan\tscope-x\tclaude\topus\thigh\told' $'2026-10-02\tplan\tscope-x\tclaude\topus\thigh\tsx' \
  $'2026-10-02\tlead\tlead-x\tclaude\topus\thigh\tlx' $'2026-10-02\tcodex\tcodex-y\tcodex\tdefault\thigh\t-' > "${P}/.swarm/agents.tsv"
close() { (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" close "$1" >/dev/null 2>&1) || true; }

close scope-x

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
check "both tabs with the label are closed, one id per call" test "$(sort "${CLOSED}" | tr '\n' ' ')" = "<w:t1> <w:t2> "
check "another label's tab is left open" bash -c "! grep -qx '<w:t3>' '${CLOSED}'"
check "the tab record is removed" test ! -e "${P}/.swarm/state/scope-x"
archives() { find "${P}/.swarm/sessions" -type f 2>/dev/null | wc -l | tr -d ' '; }
check "close archives the agent's newest session, gzip'd" \
  test "$(gunzip -c "${P}/.swarm/sessions/"*-scope-x-sx.jsonl.gz 2>/dev/null)" = '{"type":"user","cwd":"/x"}'
check "closing its tab archives the agent left in it too" \
  test "$(gunzip -c "${P}/.swarm/sessions/"*-lead-x-lx.jsonl.gz 2>/dev/null)" = '{"type":"user","cwd":"/l"}'
check "the two archives are the only files there" test "$(archives)" = 2
check "the archives are readable by their owner only" test "$(find "${P}/.swarm/sessions" -name "*.jsonl.gz" -perm 600 | wc -l | tr -d ' ')" = 2
# Dated earlier, so a second copy would get a new name rather than overwrite this one.
mv "${P}/.swarm/sessions/"*-scope-x-sx.jsonl.gz "${P}/.swarm/sessions/2026-01-01-scope-x-sx.jsonl.gz"
close scope-x
check "closing it again, another day, archives nothing more" test "$(archives)" = 2
close codex-y
check "an agent with no session archives nothing" test "$(archives)" = 2
if [[ ${fails} -ne 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
