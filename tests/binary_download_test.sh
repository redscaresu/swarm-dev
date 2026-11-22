#!/usr/bin/env bash
# binary_download_test.sh — bin/lib/binary.sh's binary_download fetches release v<version>'s binary for
# this platform and its checksum file with gh, into the folder it is given, and checks the SHA-256. Each
# case sources the lib in a new bash, run from <copy> (a folder holding a copy of scripts/build.sh), with
# GH_HOST=ghe.example.com and a PATH of the stubs in tests/binary_fetch_stubs.sh and only the programs the
# download may start: dirname (for build.sh), uname, and sha256sum or shasum.
#   A good release returns 0 and says nothing. The gh stub logged one call: the tag, the github.com repo,
#     this platform's asset and SHA256SUMS as patterns, and the folder. The folder holds the fake release,
#     and nothing else. Each of uname's mapped values picks its asset, and a binary-mode line passes.
#   A copy whose build.sh --list names other values: gh is asked for those, and the sum is read from SUMS-X.
#   Return 1 with one stderr line: a wrong sum; a line naming the asset with a suffix, or a prefix, and its
#     true sum; the asset named twice; no scripts/build.sh; a --list this cannot read; no sum program; no
#     folder.
#   Return BINARY_CANNOT with one stderr line: uname reporting Linux riscv64; no gh on PATH; gh failing,
#     the line quoting its first non-empty stderr line and not its second.
# No case writes outside the folder: a listing of <copy> is the same before and after each, and no case
# leaves <copy>/swarm.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
# shellcheck source=tests/binary_fetch_stubs.sh
source "$(dirname "${BASH_SOURCE[0]}")/binary_fetch_stubs.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="${REPO}/bin/lib/binary.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[[ -d "${tmp}" ]] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, as every test file

CANNOT=3   # BINARY_CANNOT, copied here so a change to it is a change to this test too
VERSION=9.8.7; HOST=ghe.example.com
ZERO=0000000000000000000000000000000000000000000000000000000000000000
FIX="reinstall swarm-dev (claude plugin uninstall swarm-dev@swarm-dev, then claude plugin install swarm-dev@swarm-dev)"
REPORT="run it again, and if it fails the same way report it at https://github.com/${FETCH_REPO}/issues"
T=$'\t'

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
lines() { # <text>: its number of lines, 0 for none
  if [[ -z "$1" ]]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi
}

# This platform, mapped by the test itself.
case "$(uname -s)" in Darwin) OS=darwin ;; Linux) OS=linux ;; *) OS="" ;; esac
case "$(uname -m)" in x86_64) ARCH=amd64 ;; arm64|aarch64) ARCH=arm64 ;; *) ARCH="" ;; esac
[[ -n "${OS}" && -n "${ARCH}" ]] || { echo "FAIL this test runs on darwin or linux, amd64 or arm64"; exit 1; }
ASSET="swarm-${OS}-${ARCH}"

F="${ROOT}/fetch"; fetch_stubs "${F}" "${VERSION}" || exit 1
STUBS="${F}/bin"
# TOOLS: the programs a case's PATH holds besides the stubs. NOSUM: the same without the sum programs.
TOOLS="${ROOT}/tools"; NOSUM="${ROOT}/nosum"; mkdir -p "${TOOLS}" "${NOSUM}"
for t in dirname uname sha256sum shasum; do
  p="$(command -v "${t}")" || continue
  ln -s "${p}" "${TOOLS}/${t}"
  case "${t}" in dirname|uname) ln -s "${p}" "${NOSUM}/${t}" ;; esac
done
[[ -e "${TOOLS}/sha256sum" || -e "${TOOLS}/shasum" ]] || { echo "FAIL neither sha256sum nor shasum is on PATH"; exit 1; }

# listing <dir>: every path under <dir> and each file's cksum, sorted.
listing() { (cd "$1" && find . -print && find . -type f -exec cksum {} +) | LC_ALL=C sort; }
# gh_calls / uname_calls: the stub's log since the last read, then emptied.
gh_calls() { cat "${F}/log/gh" 2>/dev/null || true; rm -f "${F}/log/gh"; }
uname_calls() { cat "${F}/log/uname" 2>/dev/null || true; rm -f "${F}/log/uname"; }
# call <asset> <checksums> <dir>: the one gh call a good download makes.
call() {
  printf 'GH_HOST=%s release download v%s --repo github.com/%s --pattern %s --pattern %s --dir %s' \
    "${HOST}" "${VERSION}" "${FETCH_REPO}" "$1" "$2" "$3"
}

# NOMARK: an xattr stub that lists no attribute. With uname reporting Darwin, binary_download checks the
# asset for macOS's quarantine mark with BINARY_XATTR, which Linux does not have; tests/binary_quarantine_test.sh
# tests that check.
NOMARK="${ROOT}/xattr-nomark"; printf '#!/bin/sh\nexit 0\n' > "${NOMARK}"; chmod +x "${NOMARK}"

# run_lib <path> <copy> <dir>: binary_download <copy> VERSION <dir> in a new bash with PATH <path>,
# GH_HOST and BINARY_XATTR=NOMARK, from <copy>. Sets rc, out and err.
run_lib() {
  rc=0
  # shellcheck disable=SC2016 # the inner bash expands its own arguments
  (cd "$2" || exit 1
   env GH_HOST="${HOST}" PATH="$1" "${BASH}" -c 'source "$1" && BINARY_XATTR="$5" && binary_download "$2" "$3" "$4"' _ \
     "${LIB}" "$2" "${VERSION}" "$3" "${NOMARK}") > "${ROOT}/out" 2> "${ROOT}/err" || rc=$?
  out="$(cat "${ROOT}/out")"; err="$(cat "${ROOT}/err")"
}
# dl <name> <path> <copy>: run_lib into D, a new empty folder, and check it changed nothing in <copy>.
n=0
dl() {
  local before
  n=$((n + 1)); D="${ROOT}/dl-${n}"; mkdir -p "${D}"
  before="$(listing "$3")"
  run_lib "$2" "$3" "${D}"
  check "$1: writes nothing in the copy" "${before}" "$(listing "$3")"
  check "$1: leaves no <copy>/swarm" none "$([[ -e "$3/swarm" ]] && echo there || echo none)"
}
# refused <name> <rc> <line>: the last case returned <rc>, printed nothing on stdout and said <line>, one
# line, on stderr.
refused() {
  check "$1: returns $2" "$2" "${rc}"
  check "$1: prints nothing on stdout" "" "${out}"
  check "$1: says one line" 1 "$(lines "${err}")"
  check "$1: the line" "$3" "${err}"
}
same_file() { cmp -s "$1" "$2" && echo same || echo differs; }

# A positive control: the stubs answer through the PATH the cases run with.
fetch_uname "${F}" Linux riscv64
check "the uname stub reports what it is given" "Linux riscv64" "$(PATH="${STUBS}" uname -s) $(PATH="${STUBS}" uname -m)"
fetch_uname "${F}"
check "the uname stub runs the real uname by default" "$(uname -s)" "$(PATH="${STUBS}" uname -s)"
uname_calls > /dev/null

C="${ROOT}/copy"; mkdir -p "${C}/scripts"; cp "${REPO}/scripts/build.sh" "${C}/scripts/"

# A good release. The checksum file has a line for other assets before and after the asset's, as
# build.sh writes one line a platform, so the line is picked by its name, not its place.
fetch_release "${F}" "${ASSET}" SHA256SUMS || exit 1
SUM="$(fetch_sum "${F}/release/${ASSET}")"
printf '%s  %s\n' "${ZERO}" swarm-plan9-amd64 "${SUM}" "${ASSET}" "${ZERO}" swarm-plan9-arm64 > "${F}/release/SHA256SUMS"
dl "a good release" "${STUBS}:${TOOLS}" "${C}"
check "a good release: returns 0" 0 "${rc}"
check "a good release: says nothing" "" "${out}${err}"
check "a good release: gh logged one call, naming github.com and the folder" "$(call "${ASSET}" SHA256SUMS "${D}")" "$(gh_calls)"
check "a good release: uname was asked -s, then -m" "-s
-m" "$(uname_calls)"
check "a good release: the asset is the fake release" same "$(same_file "${D}/${ASSET}" "${SWARMDEV_BIN}")"
check "a good release: the folder holds the two files and nothing else" "SHA256SUMS ${ASSET}" \
  "$(cd "${D}" && find . ! -name . -print | sed 's|^\./||' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"

# A line in sha256sum's binary mode (<hex> *<name>) passes too.
printf '%s *%s\n' "${SUM}" "${ASSET}" > "${F}/release/SHA256SUMS"
dl "a binary-mode line" "${STUBS}:${TOOLS}" "${C}"
check "a binary-mode line: returns 0 and says nothing" "0|" "${rc}|${err}"
gh_calls > /dev/null

# Each value uname gives picks its --list asset.
for p in "Darwin arm64 darwin-arm64" "Darwin x86_64 darwin-amd64" "Linux aarch64 linux-arm64" "Linux x86_64 linux-amd64"; do
  read -r s m a <<< "${p}"
  fetch_uname "${F}" "${s}" "${m}"; fetch_release "${F}" "swarm-${a}" SHA256SUMS || exit 1
  dl "uname ${s} ${m}" "${STUBS}:${TOOLS}" "${C}"
  check "uname ${s} ${m}: returns 0 and fetches swarm-${a}" "0|$(call "swarm-${a}" SHA256SUMS "${D}")" "${rc}|$(gh_calls)"
done
fetch_uname "${F}"

# A copy whose build.sh --list names swarm-<os>-<arch>-x and SUMS-X.
CX="${ROOT}/copy-x"; mkdir -p "${CX}/scripts"
sed -e 's/^CHECKSUMS=SHA256SUMS$/CHECKSUMS=SUMS-X/' -e 's/^\(  echo "swarm-.*\)"$/\1-x"/' \
  "${REPO}/scripts/build.sh" > "${CX}/scripts/build.sh"
xlist="$(bash "${CX}/scripts/build.sh" --list)"
check "the SUMS-X copy's --list names ${ASSET}-x and SUMS-X" "asset${T}${OS}/${ARCH}${T}${ASSET}-x|checksums${T}SUMS-X${T}sha256" \
  "$(grep -Fx "asset${T}${OS}/${ARCH}${T}${ASSET}-x" <<< "${xlist}" || true)|$(grep -Fx "checksums${T}SUMS-X${T}sha256" <<< "${xlist}" || true)"
fetch_release "${F}" "${ASSET}-x" SUMS-X || exit 1
dl "SUMS-X" "${STUBS}:${TOOLS}" "${CX}"
check "SUMS-X: returns 0 and says nothing" "0|" "${rc}|${err}"
check "SUMS-X: gh is asked for ${ASSET}-x and SUMS-X" "$(call "${ASSET}-x" SUMS-X "${D}")" "$(gh_calls)"
printf '%s  %s\n' "${ZERO}" "${ASSET}-x" > "${F}/release/SUMS-X"
dl "SUMS-X with a wrong sum" "${STUBS}:${TOOLS}" "${CX}"
refused "SUMS-X with a wrong sum" 1 "binary: the SHA-256 of v${VERSION}'s ${ASSET}-x does not match its line in SUMS-X: ${REPORT}"
gh_calls > /dev/null

# Checksum files that fail the check.
fetch_release "${F}" "${ASSET}" SHA256SUMS || exit 1
sums_case() { # <name> <SHA256SUMS text> <line>: the case returns 1 saying <line>, after one gh call
  printf '%s\n' "$2" > "${F}/release/SHA256SUMS"
  dl "$1" "${STUBS}:${TOOLS}" "${C}"
  refused "$1" 1 "$3"
  check "$1: gh logged one call" "$(call "${ASSET}" SHA256SUMS "${D}")" "$(gh_calls)"
}
sums_case "a wrong sum" "${ZERO}  ${ASSET}" \
  "binary: the SHA-256 of v${VERSION}'s ${ASSET} does not match its line in SHA256SUMS: ${REPORT}"
sums_case "the asset's name with a suffix, and its true sum" "${SUM}  ${ASSET}-old" \
  "binary: v${VERSION}'s SHA256SUMS has no line naming ${ASSET}, so the download cannot be checked: ${REPORT}"
sums_case "the asset's name with a prefix, and its true sum" "${SUM}  old-${ASSET}" \
  "binary: v${VERSION}'s SHA256SUMS has no line naming ${ASSET}, so the download cannot be checked: ${REPORT}"
sums_case "the asset named twice" "${SUM}  ${ASSET}"$'\n'"${SUM} *${ASSET}" \
  "binary: v${VERSION}'s SHA256SUMS names ${ASSET} on 2 lines, so the download cannot be checked: ${REPORT}"
fetch_release "${F}" "${ASSET}" SHA256SUMS || exit 1

# No sum program on PATH.
dl "no sha256sum or shasum" "${STUBS}:${NOSUM}" "${C}"
refused "no sha256sum or shasum" 1 "binary: could not take the SHA-256 of ${D}/${ASSET} (no sha256sum or shasum on PATH, or it failed), so the download cannot be checked: install coreutils, or set SWARMDEV_BIN to a swarm binary"
gh_calls > /dev/null

# No scripts/build.sh, and a --list this cannot read. None calls gh.
CN="${ROOT}/copy-none"; mkdir -p "${CN}"
dl "no scripts/build.sh" "${STUBS}:${TOOLS}" "${CN}"
refused "no scripts/build.sh" 1 "binary: cannot tell which release files are this copy's binary: ${CN}/scripts/build.sh is missing: ${FIX}"
check "no scripts/build.sh: no gh call" "" "$(gh_calls)"
fetch_uname "${F}" Linux x86_64
A="asset${T}linux/amd64${T}swarm-linux-amd64"; S="checksums${T}SHA256SUMS${T}sha256"
k=0
list_case() { # <name> <build.sh body> <why>: the case returns 1 saying why, and calls no gh
  local c
  k=$((k + 1)); c="${ROOT}/copy-list-${k}"; mkdir -p "${c}/scripts"
  printf '%s\n' "$2" > "${c}/scripts/build.sh"
  dl "$1" "${STUBS}:${TOOLS}" "${c}"
  refused "$1" 1 "binary: cannot tell which release files are this copy's binary: ${c}/scripts/build.sh $3: ${FIX}"
  check "$1: no gh call" "" "$(gh_calls)"
}
list_case "--list fails" "printf '%s\n' '${A}' '${S}'; exit 1" "--list failed"
list_case "--list with no checksums line" "printf '%s\n' '${A}'" "--list has no one sha256 checksums line"
list_case "--list with a sha512 checksums line" "printf '%s\n' '${A}' 'checksums${T}SHA512SUMS${T}sha512'" \
  "--list has no one sha256 checksums line"
list_case "--list with no asset line" "printf '%s\n' '${S}'" "--list has no asset line"
list_case "--list with two asset lines for linux/amd64" "printf '%s\n' '${A}' '${A}' '${S}'" \
  "--list has 2 asset lines for linux/amd64"
list_case "--list naming a glob as the asset" "printf '%s\n' 'asset${T}linux/amd64${T}swarm-*' '${S}'" \
  "--list names 'swarm-*', which is not a plain file name"
list_case "--list naming a glob as the checksum file" "printf '%s\n' '${A}' 'checksums${T}SHA*${T}sha256'" \
  "--list names 'SHA*', which is not a plain file name"

# Cases where the download cannot work here.
fetch_uname "${F}" Linux riscv64
dl "uname Linux riscv64" "${STUBS}:${TOOLS}" "${C}"
refused "uname Linux riscv64" "${CANNOT}" "binary: swarm-dev publishes no binary for linux/riscv64 (uname: Linux riscv64): set SWARMDEV_BIN to a swarm binary built for it (go build ./cmd/swarm)"
check "uname Linux riscv64: no gh call" "" "$(gh_calls)"
fetch_uname "${F}"

dl "no gh on PATH" "${TOOLS}" "${C}"
refused "no gh on PATH" "${CANNOT}" "binary: gh is not on PATH, so swarm-dev cannot download its binary: install the GitHub CLI (https://cli.github.com) and run gh auth login, or set SWARMDEV_BIN to a swarm binary"

printf '\nfirst line\nsecond line\n' > "${F}/stub/download.stderr"
dl "gh failing" "${STUBS}:${TOOLS}" "${C}"
refused "gh failing" "${CANNOT}" "binary: gh release download v${VERSION} --repo github.com/${FETCH_REPO} failed: 'first line': fix what gh says and run again, or set SWARMDEV_BIN to a swarm binary"
check "gh failing: gh logged one call" "$(call "${ASSET}" SHA256SUMS "${D}")" "$(gh_calls)"
check "gh failing: the folder is empty" "" "$(ls -A "${D}")"
rm -f "${F}/stub/download.stderr"

# No folder to download into.
before="$(listing "${C}")"
run_lib "${STUBS}:${TOOLS}" "${C}" "${ROOT}/no-such-folder"
refused "no folder" 1 "binary: binary_download needs a plugin root, a version and an existing folder; it got '${C}' '${VERSION}' '${ROOT}/no-such-folder'"
check "no folder: writes nothing in the copy, and makes no folder" "${before}|none" \
  "$(listing "${C}")|$([[ -e "${ROOT}/no-such-folder" ]] && echo there || echo none)"
check "no folder: no gh call" "" "$(gh_calls)"

[[ "${fails}" -eq 0 ]] || { echo "${fails} check(s) failed"; exit 1; }
echo "all binary_download checks passed"
