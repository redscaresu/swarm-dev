#!/usr/bin/env bash
# llms_test.sh — llms.txt names real paths and the first steps; plugin.json's description drops HLD
# and its version equals the one on origin/main (or the merge base): a story PR never bumps it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0

check() { # <name> <cond...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}

paths="$(grep -o '](\([^)]*\))' "${ROOT}/llms.txt" | sed 's/^](//; s/)$//; s/#.*//' | grep -v '^https\?://' || true)"
check "llms.txt names at least one path" [ -n "${paths}" ]
while IFS= read -r p; do
  [ -z "${p}" ] || check "llms.txt path exists: ${p}" test -e "${ROOT}/${p}"
done <<<"${paths}"

check "names swarm.sh init" grep -q 'swarm.sh init' "${ROOT}/llms.txt"
check "names /swarm-dev:swarm" grep -q '/swarm-dev:swarm' "${ROOT}/llms.txt"

desc="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["description"])' "${ROOT}/.claude-plugin/plugin.json")"
check "plugin.json description has no HLD" [ "${desc}" = "${desc//HLD/}" ]
ver="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "${ROOT}/.claude-plugin/plugin.json")"
base="$(git -C "${ROOT}" rev-parse --verify -q origin/main || git -C "${ROOT}" merge-base HEAD main)"
base_ver="$(git -C "${ROOT}" show "${base}:.claude-plugin/plugin.json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')"
check "plugin.json version is unchanged (${base_ver})" [ "${ver}" = "${base_ver}" ]

exit $((fails > 0))
