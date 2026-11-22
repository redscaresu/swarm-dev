#!/usr/bin/env bash
# update_test.sh — `swarm.sh update` acts on the plugin ID the copy is installed as (plugin_id in
# bin/swarm.sh): it runs `claude plugin marketplace update <marketplace>`, then
# `claude plugin update <plugin>@<marketplace>`, both read from the copy's path, and exits 0.
# Each case runs swarm.sh update from a folder that is no project, with a claude stub first on PATH that
# logs its arguments, SWARMDEV_BIN set (make test builds it) so no copy fetches, and SWARM_PROJECT unset.
#   A no-.git copy at <config>/plugins/cache/swarm-dev-pre/swarm-dev/1.0.0: the marketplace
#     swarm-dev-pre, then swarm-dev@swarm-dev-pre, and nothing else.
#   A copy at <config>/plugins/cache/swarm-dev/swarm-dev/1.0.0: swarm-dev, then swarm-dev@swarm-dev.
#   Copies of the -pre layout whose two segments above the marketplace are not exactly plugins, then
#     cache (plugins/caches, xplugins/cache): swarm-dev, then swarm-dev@swarm-dev, so only whole
#     segments match.
#   The checkout these tests run from: swarm-dev, then swarm-dev@swarm-dev.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${SWARMDEV_BIN:-}" || ! -x "${SWARMDEV_BIN}" ]]; then
  echo "FAIL SWARMDEV_BIN names no executable binary ('${SWARMDEV_BIN:-}'): run this test through make test, which builds it"
  exit 1
fi
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[[ -d "${tmp}" ]] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, as every test file

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

TOOLS="${ROOT}/tools"; mkdir -p "${TOOLS}"
# claude: logs each call's arguments, one line a call, and succeeds. Never the real one.
printf '#!/bin/sh\necho "$*" >> "%s/claude.log"\n' "${ROOT}" > "${TOOLS}/claude"
chmod +x "${TOOLS}/claude"
W="${ROOT}/work"; mkdir -p "${W}"   # where each call runs: no project
CACHE="${CLAUDE_CONFIG_DIR}/plugins/cache"
STABLE="plugin marketplace update swarm-dev|plugin update swarm-dev@swarm-dev"

# copy <dir> — a copy of the plugin as an install leaves it: bin/, scripts/build.sh, .claude-plugin/,
# go.mod, cmd/ and internal/, with no .git.
copy() {
  mkdir -p "$1/scripts"
  cp -R "${REPO}/bin" "${REPO}/.claude-plugin" "${REPO}/go.mod" "${REPO}/cmd" "${REPO}/internal" "$1/"
  cp "${REPO}/scripts/build.sh" "$1/scripts/"
}
# update <plugin root> — <root>'s swarm.sh update; sets rc, and log: the claude stub's calls joined by |.
update() {
  rm -f "${ROOT}/claude.log"; rc=0
  (cd "${W}" || exit 1
   env -u HERDR_ENV -u SWARM_PROJECT PATH="${TOOLS}:${PATH}" bash "$1/bin/swarm.sh" update) \
    < /dev/null > "${ROOT}/out" 2>&1 || rc=$?
  log="$(paste -sd'|' - < "${ROOT}/claude.log" 2>/dev/null || true)"
}

# --- Installed as swarm-dev@swarm-dev-pre: that marketplace, then that ID.
C="${CACHE}/swarm-dev-pre/swarm-dev/1.0.0"; copy "${C}"; update "${C}"
check "swarm-dev-pre copy: exits 0" 0 "${rc}"
check "swarm-dev-pre copy: updates marketplace swarm-dev-pre, then swarm-dev@swarm-dev-pre" \
  "plugin marketplace update swarm-dev-pre|plugin update swarm-dev@swarm-dev-pre" "${log}"

# --- Installed as swarm-dev@swarm-dev: as before the ID was read from the path.
C="${CACHE}/swarm-dev/swarm-dev/1.0.0"; copy "${C}"; update "${C}"
check "swarm-dev copy: exits 0" 0 "${rc}"
check "swarm-dev copy: updates marketplace swarm-dev, then swarm-dev@swarm-dev" "${STABLE}" "${log}"

# --- Not Claude Code's layout above the marketplace: the fixed ID, never swarm-dev-pre.
C="${CLAUDE_CONFIG_DIR}/plugins/caches/swarm-dev-pre/swarm-dev/1.0.0"; copy "${C}"; update "${C}"
check "plugins/caches copy: exits 0" 0 "${rc}"
check "plugins/caches copy (not cache): updates swarm-dev, then swarm-dev@swarm-dev" "${STABLE}" "${log}"
C="${ROOT}/xplugins/cache/swarm-dev-pre/swarm-dev/1.0.0"; copy "${C}"; update "${C}"
check "xplugins/cache copy: exits 0" 0 "${rc}"
check "xplugins/cache copy (not plugins): updates swarm-dev, then swarm-dev@swarm-dev" "${STABLE}" "${log}"

# --- The checkout: the fixed ID.
update "${REPO}"
check "checkout: exits 0" 0 "${rc}"
check "checkout: updates swarm-dev, then swarm-dev@swarm-dev" "${STABLE}" "${log}"

echo
if [[ ${fails} -eq 0 ]]; then echo "all update tests passed"; else echo "${fails} update test(s) failed"; exit 1; fi
