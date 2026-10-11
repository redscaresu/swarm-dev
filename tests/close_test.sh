#!/usr/bin/env bash
# close_test.sh — close shuts every tab that carries the agent's label, one id per herdr call, even
# when two tabs share it. herdr is a stub on PATH that records each tab close.
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

(cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" close scope-x >/dev/null 2>&1) || true

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
check "both tabs with the label are closed, one id per call" test "$(sort "${CLOSED}" | tr '\n' ' ')" = "<w:t1> <w:t2> "
check "another label's tab is left open" bash -c "! grep -qx '<w:t3>' '${CLOSED}'"
check "the tab record is removed" test ! -e "${P}/.swarm/state/scope-x"
if [[ ${fails} -ne 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
