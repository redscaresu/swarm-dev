#!/usr/bin/env bash
# binary_source_test.sh — bin/lib/binary.sh's binary_build builds the swarm binary from the source beside
# it, on a copy with no .git, into a file of its own that it renames over <root>/swarm. Each case runs
# binary_build in a new bash that sources the lib, with a PATH the case sets. Real go behind a logging
# stub builds a main.go that prints a word, and leaves no swarm.build-* file. A copy with no go.mod or no
# cmd/swarm stops in one line and the go stub logs no build. No go on PATH stops in one line naming
# go.mod's version. A failed build with an older installed Go names both versions and what to do, then
# Go's error; the version probe runs with GOTOOLCHAIN=local, as the stub fails it otherwise (as a Go that
# tries to fetch a newer one offline does). A newer, equal or unreadable Go gets the plain failed-build
# line. A failed build, and a build KILLed with its process group mid-write, leave a good <root>/swarm
# as it was.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="${REPO}/bin/lib/binary.sh"
REAL_GO="$(command -v go)" || { echo "FAIL go is not on PATH, and make test needs it"; exit 1; }
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[[ -d "${tmp}" ]] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'stop_groups "${ROOT}/groups"; stop_test_group; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, as every test file
WANT=1.27.1   # the go line of the go.mod each stub copy gets

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

LOGS="${ROOT}/logs"; REALSTUB="${ROOT}/real"; VSTUB="${ROOT}/vstub"; HALF="${ROOT}/half"; EMPTY="${ROOT}/empty"
mkdir -p "${LOGS}" "${REALSTUB}" "${VSTUB}" "${HALF}" "${EMPTY}"
SYS=/usr/bin:/bin   # what binary_build runs beside go: rm and mv
# real/go: logs each call, then runs the real go.
printf '#!/bin/sh\necho "$*" >> "%s/real"\nexec "%s" "$@"\n' "${LOGS}" "${REAL_GO}" > "${REALSTUB}/go"
# vstub/go: logs each call with GOTOOLCHAIN. `env GOVERSION` prints $STUB_VERSION only with
# GOTOOLCHAIN=local, and otherwise fails as a Go that tries to fetch a newer one offline does. build
# prints an error and exits 1.
cat > "${VSTUB}/go" <<EOF
#!/bin/sh
echo "GOTOOLCHAIN=\${GOTOOLCHAIN-unset} \$*" >> "${LOGS}/vstub"
case "\$1" in
  env) [ "\${GOTOOLCHAIN-}" = local ] || { echo "go: download go${WANT}: dial tcp: lookup proxy.golang.org: no such host" >&2; exit 1; }
       echo "\${STUB_VERSION}" ;;
  build) echo "stub: build failed" >&2; exit 1 ;;
  *) exit 1 ;;
esac
EOF
# half/go: on build, writes half a file to its -o path, marks it has, and blocks on a fifo no one writes.
mkfifo "${ROOT}/block"
cat > "${HALF}/go" <<EOF
#!/bin/sh
echo "\$*" >> "${LOGS}/half"
out=""; prev=""
for a in "\$@"; do [ "\${prev}" = -o ] && out="\${a}"; prev="\${a}"; done
[ "\$1" = build ] && [ -n "\${out}" ] || exit 1
printf '#!/bin/sh\\necho ha' > "\${out}"
: > "${ROOT}/half-wrote"
read -r x < "${ROOT}/block"
EOF
chmod +x "${REALSTUB}/go" "${VSTUB}/go" "${HALF}/go"
# builds <log> — how many go build calls <log> holds; 0 when it has none yet.
builds() { local f="${LOGS}/$1"; if [[ -f "${f}" ]]; then grep -cw build "${f}" || true; else echo 0; fi; }
# leftovers <dir> — the swarm.build-* files in <dir>, one a line.
leftovers() { (cd "$1" && find . -maxdepth 1 -name 'swarm.build-*'); }

# copy <dir> [go.mod] — a copy with no .git holding a cmd/swarm/main.go that prints "word", and the
# repo's go.mod, or one whose go line is WANT with stub.
copy() {
  mkdir -p "$1/cmd/swarm"
  printf 'package main\n\nimport "fmt"\n\nfunc main() { fmt.Println("word") }\n' > "$1/cmd/swarm/main.go"
  if [[ "${2:-}" == stub ]]; then printf 'module example.com/stub\n\ngo %s\n' "${WANT}" > "$1/go.mod"
  else cp "${REPO}/go.mod" "$1/go.mod"; fi
}

# build <root> <path> [NAME=value...] — run binary_build <root> in a new bash with PATH <path> and no
# GOTOOLCHAIN (setup-go exports GOTOOLCHAIN=local, which would hide a probe that drops it). Sets rc, out
# and err.
build() {
  local root="$1" path="$2"; shift 2
  rc=0
  # shellcheck disable=SC2016  # $1 and $2 are the new bash's
  env -u GOTOOLCHAIN PATH="${path}" "$@" "${BASH}" -c 'source "$1"; binary_build "$2"' _ "${LIB}" "${root}" \
    < /dev/null > "${ROOT}/out" 2> "${ROOT}/err" || rc=$?
  out="$(cat "${ROOT}/out")"; err="$(cat "${ROOT}/err")"
}

# Positive controls: each stub logs a call, and the version stub fails env GOVERSION without
# GOTOOLCHAIN=local, so a probe that drops it is seen.
PATH="${REALSTUB}:${SYS}" go version > /dev/null
check "the real go stub logs a call" 1 "$(grep -c '^version$' "${LOGS}/real")"
rc=0; env -u GOTOOLCHAIN PATH="${VSTUB}:${SYS}" STUB_VERSION=go1.0.0 go env GOVERSION > /dev/null 2>&1 || rc=$?
check "the version stub fails env GOVERSION without GOTOOLCHAIN=local" 1 "${rc}"
check "the version stub prints its version with GOTOOLCHAIN=local" go1.0.0 \
  "$(PATH="${VSTUB}:${SYS}" STUB_VERSION=go1.0.0 GOTOOLCHAIN=local go env GOVERSION)"
rm -f "${LOGS}/real" "${LOGS}/vstub"

# A no-.git copy and real go: it builds, the binary prints the word, and no build file is left.
G="${ROOT}/good"; copy "${G}"
build "${G}" "${REALSTUB}:${PATH}"
check "real go: returns 0" 0 "${rc}"
check "real go: prints nothing" "|" "${out}|${err}"
check "real go: built once" 1 "$(builds real)"
check "real go: the binary prints the word" word "$("${G}/swarm" 2>&1 || true)"
check "real go: no swarm.build-* file is left" "" "$(leftovers "${G}")"
cp "${G}/swarm" "${ROOT}/good-swarm"   # a good binary, for the cases that must leave one as it was

# No go.mod, and no cmd/swarm: one line each, and no build.
M="${ROOT}/nomod"; copy "${M}" stub; rm "${M}/go.mod"
build "${M}" "${VSTUB}:${SYS}"
check "no go.mod: returns 1" 1 "${rc}"
check "no go.mod: one line" "binary: ${M} has no go.mod, so it holds no source to build the swarm binary from" "${err}"
D="${ROOT}/nocmd"; copy "${D}" stub; rm -r "${D}/cmd"
build "${D}" "${VSTUB}:${SYS}"
check "no cmd/swarm: returns 1" 1 "${rc}"
check "no cmd/swarm: one line" "binary: ${D} has no cmd/swarm, so it holds no source to build the swarm binary from" "${err}"
check "no go.mod or cmd/swarm: the go stub logged no build" 0 "$(builds vstub)"

# No go on PATH: one line naming go.mod's version, and no binary.
S="${ROOT}/stub"; copy "${S}" stub
build "${S}" "${EMPTY}"
check "no go: returns 1" 1 "${rc}"
check "no go: one line naming go.mod's ${WANT}" \
  "binary: go is not on PATH, and the swarm binary builds from the source in ${S}: install Go ${WANT} or later, the version ${S}/go.mod names" "${err}"
check "no go: no binary" no "$([[ -e "${S}/swarm" ]] && echo yes || echo no)"

# A failed build, by the installed Go's version. Older: the line names both and what to do, then Go's
# error. Equal, newer or unreadable: the plain line, then Go's error. A good binary stays as it was.
OLDER="binary: go build ./cmd/swarm failed in ${S}, and the installed Go is %s, older than the ${WANT} go.mod names: install Go ${WANT} or later, or reconnect so Go can fetch it:"
PLAIN="binary: go build ./cmd/swarm failed in ${S}, so the ported command did not run:"
cp "${ROOT}/good-swarm" "${S}/swarm"
for v in "go1.0.0|older" "go1.9.0|older" "go1.27|older" "go1.27.0 X:nocoverageredesign|older" \
         "go1.27.1|plain" "go1.99.0|plain" "go1.28|plain" "devel go1.28-abc123 Tue Nov 1 2026|plain"; do
  ver="${v%|*}"
  # shellcheck disable=SC2059  # OLDER is the format
  if [[ "${v#*|}" == older ]]; then line="$(printf "${OLDER}" "${ver}")"; else line="${PLAIN}"; fi
  rm -f "${LOGS}/vstub"
  build "${S}" "${VSTUB}:${SYS}" "STUB_VERSION=${ver}"
  check "${ver}, a failed build: returns 1" 1 "${rc}"
  check "${ver}, a failed build: the ${v#*|} line, then Go's error" "${line}|stub: build failed" "$(head -1 <<< "${err}")|$(sed -n 2,\$p <<< "${err}")"
  check "${ver}, a failed build: the good binary is unchanged" same "$(cmp -s "${ROOT}/good-swarm" "${S}/swarm" && echo same || echo changed)"
  check "${ver}, a failed build: no swarm.build-* file is left" "" "$(leftovers "${S}")"
done
check "the version probe ran with GOTOOLCHAIN=local" "GOTOOLCHAIN=local env GOVERSION" "$(grep env "${LOGS}/vstub")"

# A build KILLed with its process group while go has written half a file: the good binary is as it was.
K="${ROOT}/kill"; copy "${K}" stub; cp "${ROOT}/good-swarm" "${K}/swarm"
# shellcheck disable=SC2016  # $1 and $2 are the new bash's
(in_new_group env -u GOTOOLCHAIN PATH="${HALF}:${SYS}" "${BASH}" -c 'source "$1"; binary_build "$2"' _ "${LIB}" "${K}" \
   < /dev/null > /dev/null 2>&1) &
pid=$!; group_record "${pid}" "${ROOT}/groups"
for ((i = 0; i < 100; i++)); do [[ -e "${ROOT}/half-wrote" ]] && break; sleep 0.1; done
check "KILL: go wrote half a file" yes "$([[ -e "${ROOT}/half-wrote" ]] && echo yes || echo no)"
stop_group "${pid}" "${ROOT}/groups"
check "KILL: the good binary is unchanged" same "$(cmp -s "${ROOT}/good-swarm" "${K}/swarm" && echo same || echo changed)"
check "KILL: the half file is left beside it" 1 "$(leftovers "${K}" | grep -c 'swarm.build-' || true)"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
