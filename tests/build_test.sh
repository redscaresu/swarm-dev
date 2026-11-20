#!/usr/bin/env bash
# build_test.sh — scripts/build.sh, the release contract, with a stub go first on PATH. The test shards
# have no Go, so the stub stands in for it: it logs GOOS, GOARCH, CGO_ENABLED and its arguments, one line
# a call, and writes a file at its -o path. The real four-platform build is go-checks-ci's to run.
# --list names exactly the four HLD platforms (each written out here), the checksum file and the signer,
# which exists, and runs no go. A build into --out writes exactly --list's assets and SHA256SUMS, each
# platform with CGO_ENABLED=0 and -trimpath, leaves the files it did not write, and its SHA256SUMS passes
# shasum -a 256 -c. A build that fails on one platform exits non-zero and leaves no SHA256SUMS, a stale
# one from an earlier run included.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="${REPO}/scripts/build.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${tmp}"' EXIT
export CLAUDE_CONFIG_DIR="${tmp}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0
TAB="$(printf '\t')"

check() { # <name> <cond...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}
has_line() { grep -qxF -- "$1" <<< "$2"; }   # <line> <text>: <text> has <line> as a whole line

# The stub go. GO_LOG is its log; GO_FAIL names an <os>/<arch> it fails on.
mkdir -p "${tmp}/bin"
cat > "${tmp}/bin/go" <<'STUB'
#!/usr/bin/env bash
printf 'GOOS=%s GOARCH=%s CGO_ENABLED=%s %s\n' "${GOOS-}" "${GOARCH-}" "${CGO_ENABLED-}" "$*" >> "${GO_LOG}"
[ "${GOOS-}/${GOARCH-}" != "${GO_FAIL-}" ] || { echo "stub go: ${GO_FAIL} fails" >&2; exit 1; }
out=""
while [ "$#" -gt 0 ]; do [ "$1" != -o ] || out="$2"; shift; done
[ -n "${out}" ] || { echo "stub go: no -o" >&2; exit 1; }
printf 'binary for %s/%s\n' "${GOOS-}" "${GOARCH-}" > "${out}"
STUB
chmod +x "${tmp}/bin/go"
export GO_LOG="${tmp}/go.log" PATH="${tmp}/bin:${PATH}"
unset GO_FAIL

# --list, with the stub on PATH: it must not call it.
: > "${GO_LOG}"
list="$(bash "${BUILD}" --list)"
check "--list runs no go" [ ! -s "${GO_LOG}" ]
check "--list names darwin/arm64" has_line "asset${TAB}darwin/arm64${TAB}swarm-darwin-arm64" "${list}"
check "--list names darwin/amd64" has_line "asset${TAB}darwin/amd64${TAB}swarm-darwin-amd64" "${list}"
check "--list names linux/arm64" has_line "asset${TAB}linux/arm64${TAB}swarm-linux-arm64" "${list}"
check "--list names linux/amd64" has_line "asset${TAB}linux/amd64${TAB}swarm-linux-amd64" "${list}"
assets="$(awk -F '\t' '$1 == "asset" { print $3 }' <<< "${list}")"
check "--list names four assets and no other" [ "$(grep -c . <<< "${assets}")" = 4 ]
check "--list names SHA256SUMS as the sha256 checksum file" has_line "checksums${TAB}SHA256SUMS${TAB}sha256" "${list}"
check "--list's signer is .github/workflows/release.yml" has_line "signer${TAB}.github/workflows/release.yml" "${list}"
check "the signer workflow exists" [ -f "${REPO}/.github/workflows/release.yml" ]
check "--list prints only asset, checksums and signer lines" \
  [ "$(grep -cvE "^(asset${TAB}[a-z0-9]+/[a-z0-9]+${TAB}swarm-[a-z0-9]+-[a-z0-9]+|checksums${TAB}.*|signer${TAB}.*)\$" <<< "${list}")" = 0 ]

# --list with no go anywhere on PATH: only dirname, which build.sh runs to find its root.
mkdir -p "${tmp}/nogo"
ln -s "$(command -v dirname)" "${tmp}/nogo/dirname"
rc=0; nogo="$(PATH="${tmp}/nogo" "${BASH}" "${BUILD}" --list 2> "${tmp}/nogo.err")" || rc=$?
check "--list exits 0 with no go on PATH" [ "${rc}" = 0 ]
check "--list prints the same contract with no go on PATH" [ "${nogo}" = "${list}" ]

# A build into an --out that is missing, then into one that holds a file build.sh did not write.
out="${tmp}/out"
: > "${GO_LOG}"
rc=0; bash "${BUILD}" --out "${out}" 2> "${tmp}/build.err" || rc=$?
check "a build into a missing --out exits 0" [ "${rc}" = 0 ]
echo keep > "${out}/sentinel"
echo keep > "${out}/SHA256SUMS.tmp"   # a name build.sh might pick for a temporary file
: > "${GO_LOG}"
rc=0; bash "${BUILD}" --out "${out}" 2>> "${tmp}/build.err" || rc=$?
check "a build into an existing --out exits 0" [ "${rc}" = 0 ]
check "a file in --out that build.sh did not write is still there" [ "$(cat "${out}/sentinel" 2>/dev/null)" = keep ]
check "a SHA256SUMS.tmp in --out that build.sh did not write is still there" [ "$(cat "${out}/SHA256SUMS.tmp" 2>/dev/null)" = keep ]
want="$( (echo "${assets}"; echo SHA256SUMS; echo SHA256SUMS.tmp; echo sentinel) | sort)"
check "the build wrote exactly --list's assets and SHA256SUMS" [ "$(cd "${out}" && find . -mindepth 1 | sed 's|^\./||' | sort)" = "${want}" ]
log="$(cat "${GO_LOG}")"
for p in darwin/arm64 darwin/amd64 linux/arm64 linux/amd64; do
  name="swarm-${p%/*}-${p#*/}"
  check "go built ${p} with CGO_ENABLED=0 and -trimpath into --out" \
    has_line "GOOS=${p%/*} GOARCH=${p#*/} CGO_ENABLED=0 build -trimpath -o ${out}/${name} ./cmd/swarm" "${log}"
done
check "go ran once per platform" [ "$(grep -c . <<< "${log}")" = 4 ]
sums="$(cat "${out}/SHA256SUMS" 2>/dev/null || true)"
check "SHA256SUMS has one <64 hex>  <asset> line per asset, in --list's order" \
  [ "$(sed -nE 's/^[0-9a-f]{64}  (swarm-[a-z0-9-]+)$/\1/p' <<< "${sums}")" = "${assets}" ]
# shellcheck disable=SC2016 # $1 is the inner shell's
check "shasum -a 256 -c SHA256SUMS passes in --out" \
  bash -c 'cd "$1" || exit 1; shasum -a 256 -c SHA256SUMS > /dev/null' _ "${out}"

# A build that fails on linux/arm64, over an --out that still holds an earlier run's SHA256SUMS.
rc=0; GO_FAIL=linux/arm64 bash "${BUILD}" --out "${out}" 2> "${tmp}/fail.err" || rc=$?
check "a failed linux/arm64 build exits non-zero" [ "${rc}" != 0 ]
check "a failed build leaves no SHA256SUMS, though an earlier run left one" [ ! -e "${out}/SHA256SUMS" ]
check "a failed build still leaves the sentinel it did not write" [ -f "${out}/sentinel" ]
check "a failed build still leaves the SHA256SUMS.tmp it did not write" [ -f "${out}/SHA256SUMS.tmp" ]

# A relative --out is taken from the directory build.sh runs in, not the repo root.
mkdir -p "${tmp}/cwd"
rc=0; (cd "${tmp}/cwd" || exit 1; bash "${BUILD}" --out rel 2> /dev/null) || rc=$?
check "a build with a relative --out exits 0" [ "${rc}" = 0 ]
check "a relative --out is under the current directory" [ -f "${tmp}/cwd/rel/SHA256SUMS" ]

# shellcheck disable=SC2016 # $1 is the inner shell's
check "an unknown argument exits 2" bash -c '"$1" --bogus 2> /dev/null; [ "$?" = 2 ]' _ "${BUILD}"

if [ "${fails}" -gt 0 ]; then
  echo "--- build.err"; cat "${tmp}/build.err" 2>/dev/null || true
  echo "--- nogo.err"; cat "${tmp}/nogo.err" 2>/dev/null || true
  echo "${fails} failed"; exit 1
fi
echo "all passed"
