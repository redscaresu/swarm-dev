#!/usr/bin/env bash
# llms_test.sh — llms.txt names real paths and the first steps; plugin.json's description drops HLD
# and its version is still a plain x.y.z (no comparison with main: CI checks out shallow, and the
# release PR bumps it on purpose).
set -euo pipefail

iso="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${iso}"' EXIT
export CLAUDE_CONFIG_DIR="${iso}/claude-config"   # under its own root, so parallel runs share no ~/.claude

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

check "names swarm.sh init" grep -qF 'swarm.sh init' "${ROOT}/llms.txt"
check "names /swarm-dev:swarm" grep -qwF '/swarm-dev:swarm' "${ROOT}/llms.txt"

desc="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["description"])' "${ROOT}/.claude-plugin/plugin.json")"
check "plugin.json description has no HLD" [ "${desc}" = "${desc//HLD/}" ]
ver="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "${ROOT}/.claude-plugin/plugin.json")"
check "plugin.json version is x.y.z" grep -Eq "^[0-9]+\.[0-9]+\.[0-9]+\$" <<<"${ver}"

exit $((fails > 0))
