#!/usr/bin/env bash
# version_ref_test.sh — `swarm.sh version` looks for a newer version on the ref the copy's marketplace
# follows (LATEST_URL in bin/swarm.sh): prerelease for an install from swarm-dev-pre, stable for any
# other and for a checkout. main runs ahead of both refs, so a copy that read main's plugin.json was
# warned about a version it could not install.
# Each case runs swarm.sh version from a folder that is no project, with SWARM_LATEST_URL and
# SWARM_PROJECT unset, SWARMDEV_BIN set (make test builds it) so no copy fetches, and a curl stub first
# on PATH that logs its arguments, one line a call, and prints a plugin.json with the version in
# SERVED.
#   A no-.git copy at <config>/plugins/cache/swarm-dev-pre/swarm-dev/1.0.0: one curl call, with
#     --max-time 5 and the prerelease ref's plugin.json.
#   A copy at <config>/plugins/cache/swarm-dev/swarm-dev/1.0.0, and the checkout: the stable ref's.
#   A served 99.0.0 gives the WARNING and the `  swarm.sh update` line; the installed version, neither.
#   SWARM_LATEST_URL set: curl gets that URL, and no other.
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
# curl: logs each call's arguments, one line a call, and prints a plugin.json whose version is the
# contents of ${ROOT}/served. Never the real one.
cat > "${TOOLS}/curl" <<STUB
#!/bin/sh
echo "\$*" >> "${ROOT}/curl.log"
printf '{"name": "swarm-dev", "version": "%s"}\n' "\$(cat "${ROOT}/served")"
STUB
chmod +x "${TOOLS}/curl"
W="${ROOT}/work"; mkdir -p "${W}"   # where each call runs: no project
CACHE="${CLAUDE_CONFIG_DIR}/plugins/cache"
RAW="https://raw.githubusercontent.com/redscaresu/swarm-dev"
PRE_URL="${RAW}/prerelease/.claude-plugin/plugin.json"
STABLE_URL="${RAW}/stable/.claude-plugin/plugin.json"
have="$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "${REPO}/.claude-plugin/plugin.json")"
[[ -n "${have}" ]] || { echo "FAIL cannot read the version from ${REPO}/.claude-plugin/plugin.json"; exit 1; }

# copy <dir> — a copy of the plugin as an install leaves it: bin/, scripts/build.sh, .claude-plugin/,
# go.mod, cmd/ and internal/, with no .git.
copy() {
  mkdir -p "$1/scripts"
  cp -R "${REPO}/bin" "${REPO}/.claude-plugin" "${REPO}/go.mod" "${REPO}/cmd" "${REPO}/internal" "$1/"
  cp "${REPO}/scripts/build.sh" "$1/scripts/"
}
# version <plugin root> <served version> [VAR=value...] — <root>'s swarm.sh version, with the stub
# serving <served version>; sets rc, out (its output), and log: the curl stub's calls joined by |.
version() {
  local root="$1"; echo "$2" > "${ROOT}/served"; shift 2
  rm -f "${ROOT}/curl.log"; rc=0
  (cd "${W}" || exit 1
   env -u HERDR_ENV -u SWARM_PROJECT -u SWARM_LATEST_URL PATH="${TOOLS}:${PATH}" "$@" \
     bash "${root}/bin/swarm.sh" version) < /dev/null > "${ROOT}/out" 2>&1 || rc=$?
  out="$(cat "${ROOT}/out")"
  log="$(paste -sd'|' - < "${ROOT}/curl.log" 2>/dev/null || true)"
}
# warned — yes when out has the WARNING for 99.0.0 and the update command's line, else no.
warned() {
  if grep -q "^WARNING: swarm-dev 99.0.0 is out; this is ${have}\." <<< "${out}" \
    && grep -qx '  swarm.sh update' <<< "${out}"; then echo yes; else echo no; fi
}

# --- Installed from swarm-dev-pre: the prerelease ref.
PRE="${CACHE}/swarm-dev-pre/swarm-dev/1.0.0"; copy "${PRE}"
version "${PRE}" 99.0.0
check "swarm-dev-pre copy: exits 0" 0 "${rc}"
check "swarm-dev-pre copy: one curl call, with --max-time 5 and the prerelease ref's plugin.json" \
  "-fsSL --max-time 5 ${PRE_URL}" "${log}"
check "swarm-dev-pre copy, 99.0.0 served: the WARNING and the update command" yes "$(warned)"
version "${PRE}" "${have}"
check "swarm-dev-pre copy, its own version served: no WARNING" "swarm-dev ${have}" "${out}"

# --- Installed from swarm-dev: the stable ref.
STABLE="${CACHE}/swarm-dev/swarm-dev/1.0.0"; copy "${STABLE}"
version "${STABLE}" 99.0.0
check "swarm-dev copy: exits 0" 0 "${rc}"
check "swarm-dev copy: one curl call, with --max-time 5 and the stable ref's plugin.json" \
  "-fsSL --max-time 5 ${STABLE_URL}" "${log}"
check "swarm-dev copy, 99.0.0 served: the WARNING and the update command" yes "$(warned)"
version "${STABLE}" "${have}"
check "swarm-dev copy, its own version served: no WARNING" "swarm-dev ${have}" "${out}"

# --- The checkout: the stable ref.
version "${REPO}" 99.0.0
check "checkout: exits 0" 0 "${rc}"
check "checkout: one curl call, with --max-time 5 and the stable ref's plugin.json" \
  "-fsSL --max-time 5 ${STABLE_URL}" "${log}"
check "checkout, 99.0.0 served: the WARNING and the update command" yes "$(warned)"

# --- SWARM_LATEST_URL overrides the ref's URL, in a -pre copy too.
OVERRIDE="https://example.invalid/plugin.json"
version "${PRE}" 99.0.0 SWARM_LATEST_URL="${OVERRIDE}"
check "SWARM_LATEST_URL set: curl gets that URL and no other" "-fsSL --max-time 5 ${OVERRIDE}" "${log}"

echo
if [[ ${fails} -eq 0 ]]; then echo "all version ref tests passed"; else echo "${fails} version ref test(s) failed"; exit 1; fi
