#!/usr/bin/env bash
# binary_version_test.sh — `swarm.sh version` in an installed copy of the plugin (no .git) with no binary
# and SWARMDEV_BIN unset: it prints its version line, then fetches the binary (binary_ensure in
# bin/lib/binary.sh), and a fetch that fails costs one line and no exit code (show_version in bin/swarm.sh).
# Each case runs a no-.git copy's swarm.sh from a folder that is no project, with the stubs of
# tests/binary_fetch_stubs.sh first on PATH, go a stub that logs and fails, and SWARM_LATEST_URL a
# missing file, so the newer-version check finds nothing unless a case publishes a version.
#   The gh stub serving the release: stdout and stderr together are the version line alone, the call
#     exits 0, and <copy>/swarm is executable and cmp-equal to the fake release.
#   The gh stub failing the download: the version line, then one stderr line starting `binary: ` that
#     names the download, and nothing else; exit 0, and no <copy>/swarm.
#   The same with a newer version published: the warning still follows the binary line.
#   An older version's gh-shim folder first on PATH, a stub that logs and fails: the fetch runs past it,
#     so its log stays empty while the gh stub's is not, and <copy>/swarm is installed.
# No case checks the exact gh call list, so each holds whether a failed download stops or falls back to
# a build from source (go is a fail stub either way).
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
# shellcheck source=tests/binary_fetch_stubs.sh
source "$(dirname "${BASH_SOURCE[0]}")/binary_fetch_stubs.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -z "${SWARMDEV_BIN:-}" || ! -x "${SWARMDEV_BIN}" ]]; then
  echo "FAIL SWARMDEV_BIN names no executable binary ('${SWARMDEV_BIN:-}'): run this test through make test, which builds it"
  exit 1
fi
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[[ -d "${tmp}" ]] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'stop_test_group; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, as every test file

SUMS=SHA256SUMS
VERSION="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "${REPO}/.claude-plugin/plugin.json")"

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

case "$(uname -s)" in Darwin) OS=darwin ;; Linux) OS=linux ;; *) OS="" ;; esac
case "$(uname -m)" in x86_64) ARCH=amd64 ;; arm64|aarch64) ARCH=arm64 ;; *) ARCH="" ;; esac
[[ -n "${OS}" && -n "${ARCH}" ]] || { echo "FAIL this test runs on darwin or linux, amd64 or arm64"; exit 1; }
ASSET="swarm-${OS}-${ARCH}"

F="${ROOT}/fetch"; fetch_stubs "${F}" "${VERSION}" || exit 1
fetch_release "${F}" "${ASSET}" "${SUMS}" || exit 1
RELEASE="${F}/release/${ASSET}"
TOOLS="${ROOT}/tools"; mkdir -p "${TOOLS}"
# go: logs and fails, as an installed copy never builds here.
printf '#!/bin/sh\necho "$*" >> "%s/go.log"\nexit 1\n' "${ROOT}" > "${TOOLS}/go"
chmod +x "${TOOLS}/go"
RUN_PATH="${F}/bin:${TOOLS}:${PATH}"
NOWHERE="file://${ROOT}/missing.json"   # SWARM_LATEST_URL that no lookup reaches
W="${ROOT}/work"; mkdir -p "${W}"       # where each call runs: no project

# copy <dir> — a copy of the plugin as an install leaves it: bin/, scripts/build.sh, .claude-plugin/,
# go.mod, cmd/ and internal/, with no .git.
copy() {
  mkdir -p "$1/scripts"
  cp -R "${REPO}/bin" "${REPO}/.claude-plugin" "${REPO}/go.mod" "${REPO}/cmd" "${REPO}/internal" "$1/"
  cp "${REPO}/scripts/build.sh" "$1/scripts/"
}
# ver <copy> [NAME=value...] — <copy>'s swarm.sh version, with PATH RUN_PATH (or a PATH= among the
# names), SWARM_LATEST_URL NOWHERE (or one among the names) and SWARMDEV_BIN unset. It runs twice: first
# with stdout and stderr apart, setting out, err and rc (the run that fetches), then with the two in one
# file, setting both, in the order they were written.
ver() {
  local c="$1"; shift
  rc=0
  (cd "${W}" || exit 1
   env -u HERDR_ENV -u SWARM_PROJECT -u SWARMDEV_BIN PATH="${RUN_PATH}" SWARM_LATEST_URL="${NOWHERE}" "$@" \
     bash "${c}/bin/swarm.sh" version) < /dev/null > "${ROOT}/out" 2> "${ROOT}/err" || rc=$?
  out="$(cat "${ROOT}/out")"; err="$(cat "${ROOT}/err")"
  (cd "${W}" || exit 1
   env -u HERDR_ENV -u SWARM_PROJECT -u SWARMDEV_BIN PATH="${RUN_PATH}" SWARM_LATEST_URL="${NOWHERE}" "$@" \
     bash "${c}/bin/swarm.sh" version) < /dev/null > "${ROOT}/both" 2>&1 || true
  both="$(cat "${ROOT}/both")"
}
# installed <copy> — "executable, same" when <copy>/swarm is an executable file cmp-equal to the release.
installed() {
  local b="$1/swarm" x=not-executable s=differs
  [[ -e "${b}" ]] || { echo none; return; }
  [[ -f "${b}" && -x "${b}" ]] && x=executable
  cmp -s "${b}" "${RELEASE}" && s=same
  echo "${x}, ${s}"
}
# binary_line <text> — "one binary line, names the download" when <text>'s one line starts `binary: ` and
# says download; else what it is.
binary_line() {
  local n
  n="$(printf '%s' "$1" | grep -c '' || true)"
  [[ "${n}" == 1 ]] || { echo "${n} lines: $1"; return; }
  [[ "$1" == "binary: "* ]] || { echo "not a binary: line: $1"; return; }
  [[ "$1" == *[Dd]ownload* ]] || { echo "names no download: $1"; return; }
  echo "one binary line, names the download"
}

# --- The gh stub serving the release: version fetches, installs and says nothing more.
C1="${ROOT}/c1"; copy "${C1}"
ver "${C1}"
check "fetched: version prints only its line and exits 0" "swarm-dev ${VERSION}|0" "${out}${err}|${rc}"
check "fetched: <copy>/swarm is the release, executable" "executable, same" "$(installed "${C1}")"

# --- The gh stub failing the download, go a fail stub, no newer version: one more line, and exit 0.
printf 'stub: could not reach github.com\n' > "${F}/stub/download.stderr"
C2="${ROOT}/c2"; copy "${C2}"
ver "${C2}"
check "download fails: version still exits 0" "0" "${rc}"
check "download fails: stdout is the version line alone" "swarm-dev ${VERSION}" "${out}"
check "download fails: stderr is one line saying the download failed" "one binary line, names the download" \
  "$(binary_line "${err}")"
check "download fails: the version line, then that line, and nothing else" "swarm-dev ${VERSION}|${err}|2" \
  "$(sed -n 1p <<< "${both}")|$(sed -n 2p <<< "${both}")|$(printf '%s\n' "${both}" | grep -c '')"
check "download fails: no <copy>/swarm" "none" "$(installed "${C2}")"

# --- The same, with a newer version published: the newer-version check still runs.
echo '{"version": "99.0.0"}' > "${ROOT}/latest.json"
ver "${C2}" SWARM_LATEST_URL="file://${ROOT}/latest.json"
check "download fails, newer out: exit 0, the binary line, then the warning" \
  "0|swarm-dev ${VERSION}|binary: |WARNING: swarm-dev 99.0.0 is out; this is ${VERSION}. To update, run:" \
  "${rc}|$(sed -n 1p <<< "${both}")|$(sed -n 2p <<< "${both}" | cut -c1-8)|$(sed -n 3p <<< "${both}")"
rm -f "${F}/stub/download.stderr"

# --- An older version's gh-shim folder first on PATH: the fetch never runs it.
OLD="${ROOT}/old/swarm-dev/0.30.0/bin/gh-shim"; mkdir -p "${OLD}"
printf '#!/bin/sh\necho "$*" >> "%s/shim.log"\nexit 1\n' "${ROOT}" > "${OLD}/gh"; chmod +x "${OLD}/gh"
rm -f "${F}/log/gh"
C3="${ROOT}/c3"; copy "${C3}"
ver "${C3}" PATH="${OLD}:${RUN_PATH}"
check "old gh-shim first: version exits 0 and installs the release" "0|executable, same" "${rc}|$(installed "${C3}")"
check "old gh-shim first: the shim logs no call" "" "$(cat "${ROOT}/shim.log" 2>/dev/null || true)"
check "old gh-shim first: the gh stub was called" "yes" "$([[ -s "${F}/log/gh" ]] && echo yes || echo no)"
# The control: the shim logs a call made through that PATH.
(PATH="${OLD}:${RUN_PATH}" gh control > /dev/null 2>&1) || true
check "old gh-shim first: the shim logs a direct call (control)" "control" "$(cat "${ROOT}/shim.log" 2>/dev/null || true)"

if [[ "${fails}" -eq 0 ]]; then echo "binary_version_test: all passed"; else echo "binary_version_test: ${fails} failed"; exit 1; fi
