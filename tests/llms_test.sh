#!/usr/bin/env bash
# llms_test.sh — llms.txt names real paths and the first steps; plugin.json's description drops HLD
# and its version is still a plain x.y.z (the release PR owns the number, so no pin here).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0

check() { # <name> <cond...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}

while IFS= read -r p; do
  check "llms.txt path exists: ${p}" test -e "${ROOT}/${p}"
done < <(grep -o '](\([^)]*\))' "${ROOT}/llms.txt" | sed 's/^](//; s/)$//')

check "names swarm.sh init" grep -q 'swarm.sh init' "${ROOT}/llms.txt"
check "names /swarm-dev:swarm" grep -q '/swarm-dev:swarm' "${ROOT}/llms.txt"

desc="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["description"])' "${ROOT}/.claude-plugin/plugin.json")"
check "plugin.json description has no HLD" [ "${desc}" = "${desc//HLD/}" ]
ver="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "${ROOT}/.claude-plugin/plugin.json")"
check "plugin.json version is x.y.z" [[ "${ver}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]

exit $((fails > 0))
