#!/usr/bin/env bash
# build.sh — build the release binaries of cmd/swarm, one per platform in PLATFORMS, and their checksum
# file. This script is the release contract: binary-fetch and release-ci read it, through --list, and keep
# no copy of it.
#
#   scripts/build.sh [--out <dir>]   build into <dir> (default dist/ under the repo root; a relative <dir>
#                                    is taken from the current directory)
#   scripts/build.sh --list          print the contract, one tab-separated line each, without running go:
#                                      asset<TAB><os>/<arch><TAB>swarm-<os>-<arch>   for each platform
#                                      checksums<TAB>SHA256SUMS<TAB>sha256
#                                      signer<TAB>.github/workflows/release.yml
#
# A build makes <dir> if it is missing and first removes only the files it writes there (each
# swarm-<os>-<arch> and SHA256SUMS), leaving anything else in <dir>. Each platform is built with
# CGO_ENABLED=0 go build -trimpath. SHA256SUMS is written last, in sha256sum's format, and only when every
# build passed: a failed build exits non-zero and leaves no SHA256SUMS.
set -euo pipefail

PLATFORMS="darwin/arm64 darwin/amd64 linux/arm64 linux/amd64"
CHECKSUMS=SHA256SUMS
SIGNER=.github/workflows/release.yml

usage() { echo "usage: scripts/build.sh [--out <dir>] | --list" >&2; exit 2; }

asset() { # <os>/<arch> -> the binary's file name
  echo "swarm-${1%/*}-${1#*/}"
}

list() {
  local p
  for p in ${PLATFORMS}; do printf 'asset\t%s\t%s\n' "${p}" "$(asset "${p}")"; done
  printf 'checksums\t%s\tsha256\n' "${CHECKSUMS}"
  printf 'signer\t%s\n' "${SIGNER}"
}

# The sha256 of a file: sha256sum where there is one (Linux), else shasum -a 256 (macOS).
sum() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi
}

build() { # <dir>
  local out="$1" p name names=""
  mkdir -p "${out}"
  rm -f "${out}/${CHECKSUMS}"
  for p in ${PLATFORMS}; do rm -f "${out}/$(asset "${p}")"; done
  for p in ${PLATFORMS}; do
    name="$(asset "${p}")"
    echo "build: ${p} -> ${out}/${name}" >&2
    if ! CGO_ENABLED=0 GOOS="${p%/*}" GOARCH="${p#*/}" go build -trimpath -o "${out}/${name}" ./cmd/swarm; then
      echo "build: ${p} failed; no ${CHECKSUMS} written" >&2
      return 1
    fi
    names="${names} ${name}"
  done
  # Summed from inside <dir>, so each line names the bare asset and shasum -c runs there. The sums are
  # gathered first and written in one step, so a failed sum leaves no SHA256SUMS and no other file is
  # touched. set -e does not hold in a command substitution left of ||, so each sum exits on its own failure.
  local sums
  sums="$(cd "${out}" || exit 1; for name in ${names}; do sum "${name}" || exit 1; done)" ||
    { echo "build: summing failed; no ${CHECKSUMS} written" >&2; return 1; }
  printf '%s\n' "${sums}" > "${out}/${CHECKSUMS}"
  echo "build: wrote ${out}/${CHECKSUMS}" >&2
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
out="${root}/dist"
case "${1:-}" in
  --list) [ "$#" -eq 1 ] || usage; list; exit 0 ;;
  # A relative <dir> is taken from where build.sh was run, before it moves to the repo root.
  --out) [ "$#" -eq 2 ] && [ -n "$2" ] || usage; case "$2" in /*) out="$2" ;; *) out="${PWD}/$2" ;; esac ;;
  "") [ "$#" -eq 0 ] || usage ;;
  *) usage ;;
esac
cd "${root}" || exit 1
build "${out}"
