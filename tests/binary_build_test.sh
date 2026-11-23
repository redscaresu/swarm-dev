#!/usr/bin/env bash
# binary_build_test.sh — in a git checkout of the plugin with SWARMDEV_BIN unset, a ported command runs a
# binary built from the checkout's tree (binary_path in bin/lib/binary.sh). Each case runs swarm.sh
# config from a copy of the tree with git init and one commit, holding the marker bin/ported/config and
# a cmd/swarm/main.go of the test's own that prints a word, with a go wrapper first on PATH that logs each
# call. The first call builds and prints the word; a .go file under cmd/ or internal/, or go.mod, newer
# than the binary rebuilds it; a call with nothing newer builds nothing and leaves the binary's inode and
# mtime as they were, and so does a newer file under .swarm/ or docs/ alone. SWARMDEV_BIN set runs the
# file it names and builds nothing. A main.go that does not compile exits non-zero with Go's error, prints
# no word and leaves the old binary as it was. With no go on PATH the call exits 1 in one line and bash's
# config does not run. A copy with no .git tries no build: it is an installed copy, whose swarm.sh fetches
# the binary first (binary_ensure), and its copy has no scripts/build.sh, so the call stops with
# binary_download's line. Installed from swarm-dev-pre, that line names swarm-dev@swarm-dev-pre, and so
# does binary_copy_lists's when gh is too old to download. Two calls started together on a missing binary both print the word, and git
# status is empty after.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_GO="$(command -v go)" || { echo "FAIL go is not on PATH, and make test needs it"; exit 1; }
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[[ -d "${tmp}" ]] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'stop_test_group; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, as every test file

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

STUBS="${ROOT}/stubs"; FAILSTUBS="${ROOT}/failstubs"; LOGS="${ROOT}/logs"
mkdir -p "${STUBS}" "${FAILSTUBS}" "${LOGS}"
# go: logs each call, then runs the real go. The fail stub logs each call and exits 1.
printf '#!/bin/sh\necho "$*" >> "%s/go"\nexec "%s" "$@"\n' "${LOGS}" "${REAL_GO}" > "${STUBS}/go"
printf '#!/bin/sh\necho "$*" >> "%s/failgo"\nexit 1\n' "${LOGS}" > "${FAILSTUBS}/go"
chmod +x "${STUBS}/go" "${FAILSTUBS}/go"
# builds [log] — how many go build calls the log holds; 0 when it has none yet.
builds() { local f="${LOGS}/${1:-go}"; if [[ -f "${f}" ]]; then grep -c 'build' "${f}" || true; else echo 0; fi; }
# stamp <file> — its inode and its mtime to the nanosecond, or "none" when there is no file.
stamp() { if [[ -e "$1" ]]; then perl -MTime::HiRes=stat -e '@s = stat($ARGV[0]); printf "%d %.9f\n", $s[1], $s[9]' "$1"; else echo none; fi; }
OLD=202001010000; NEW=203001010000   # touch -t stamps: before any build, and after every one

# main_go <dir> <body> — write <dir>/cmd/swarm/main.go printing <body>'s word, or <body> itself with raw:.
main_go() {
  local f="$1/cmd/swarm/main.go"
  case "$2" in
    raw:*) printf '%s\n' "${2#raw:}" > "${f}" ;;
    *) printf 'package main\n\nimport "fmt"\n\nfunc main() { fmt.Println("%s") }\n' "$2" > "${f}" ;;
  esac
}
# checkout <dir> <word> — a copy of the plugin with the config marker, a main.go printing <word>, a .go
# file under internal/, files under docs/ and .swarm/, git init and one commit, its sources dated OLD.
checkout() {
  local d="$1"
  mkdir -p "${d}/cmd/swarm" "${d}/internal/stub" "${d}/docs" "${d}/.swarm"
  cp -R "${REPO}/bin" "${REPO}/.claude-plugin" "${REPO}/.gitignore" "${REPO}/go.mod" "${d}/"
  mkdir -p "${d}/bin/ported"; : > "${d}/bin/ported/config"
  main_go "${d}" "$2"
  printf 'package stub\n' > "${d}/internal/stub/stub.go"
  echo note > "${d}/docs/note.md"; echo log > "${d}/.swarm/x.log"
  touch -t "${OLD}" "${d}/go.mod" "${d}/cmd/swarm/main.go" "${d}/internal/stub/stub.go"
  git init -q "${d}"
  git -C "${d}" add -A
  git -C "${d}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q -m init
}

# The project: not a git repo.
P="${ROOT}/proj"; mkdir -p "${P}/.claude/swarm"
printf 'board_dir = board\n' > "${P}/.claude/swarm/config"

# sw <tree> <path> [NAME=value...] — run <tree>'s swarm.sh config from the project with PATH <path> and
# SWARMDEV_BIN unset unless named. Sets out, err and rc.
sw() {
  local tree="$1" path="$2"; shift 2
  rc=0
  (cd "${P}" || exit 1
   env -u HERDR_ENV -u SWARM_PROJECT -u SWARMDEV_BIN PATH="${path}" "$@" bash "${tree}/bin/swarm.sh" config) \
    < /dev/null > "${ROOT}/out" 2> "${ROOT}/err" || rc=$?
  out="$(cat "${ROOT}/out")"; err="$(cat "${ROOT}/err")"
}
GOPATH_RUN="${STUBS}:${PATH}"

C="${ROOT}/co"; checkout "${C}" one
B="${C}/swarm"
check "the checkout has no binary yet" none "$(stamp "${B}")"

# First call: it builds, and the build prints one.
sw "${C}" "${GOPATH_RUN}"
check "first call: exits 0" 0 "${rc}"
check "first call: prints one" one "${out}"
check "first call: says nothing on stderr" "" "${err}"
check "first call: go built once" 1 "$(builds)"

# main.go rewritten to print two, newer than the binary: the next call rebuilds.
touch -t "${OLD}" "${B}"; main_go "${C}" two
sw "${C}" "${GOPATH_RUN}"
check "main.go newer: prints two" "0|two" "${rc}|${out}"
check "main.go newer: go built again" 2 "$(builds)"

# Nothing newer: no build, and the binary keeps its inode and mtime.
touch -t "${OLD}" "${C}/cmd/swarm/main.go"
was="$(stamp "${B}")"
sw "${C}" "${GOPATH_RUN}"
check "nothing newer: prints two" "0|two" "${rc}|${out}"
check "nothing newer: no build" 2 "$(builds)"
check "nothing newer: the binary's inode and mtime are unchanged" "${was}" "$(stamp "${B}")"

# A newer file under .swarm/ or docs/ alone builds nothing.
touch -t "${NEW}" "${C}/.swarm/x.log" "${C}/docs/note.md"
sw "${C}" "${GOPATH_RUN}"
check "newer .swarm/ and docs/ files: prints two" "0|two" "${rc}|${out}"
check "newer .swarm/ and docs/ files: no build" 2 "$(builds)"
check "newer .swarm/ and docs/ files: the binary is unchanged" "${was}" "$(stamp "${B}")"

# A newer .go file under internal/, or a newer go.mod, rebuilds.
n=2
for f in internal/stub/stub.go go.mod; do
  touch -t "${NEW}" "${C}/${f}"
  sw "${C}" "${GOPATH_RUN}"
  n=$((n + 1))
  check "a newer ${f}: prints two" "0|two" "${rc}|${out}"
  check "a newer ${f}: go built again" "${n}" "$(builds)"
  touch -t "${OLD}" "${C}/${f}"
done

# SWARMDEV_BIN set in the checkout, with a newer .go file: the named binary runs, and nothing builds.
printf '#!/bin/sh\necho named\n' > "${ROOT}/named"; chmod +x "${ROOT}/named"
touch -t "${NEW}" "${C}/cmd/swarm/main.go"
sw "${C}" "${GOPATH_RUN}" "SWARMDEV_BIN=${ROOT}/named"
check "SWARMDEV_BIN set: the named binary runs" "0|named" "${rc}|${out}"
check "SWARMDEV_BIN set: no build" "${n}" "$(builds)"
touch -t "${OLD}" "${C}/cmd/swarm/main.go"

# main.go that does not compile, newer than the binary: Go's error, no word, and the old binary as it was.
touch -t "${OLD}" "${B}"; was="$(stamp "${B}")"
main_go "${C}" 'raw:package main

func main() { fmt.Println("three" }'
sw "${C}" "${GOPATH_RUN}"
check "syntax error: exits 1" 1 "${rc}"
check "syntax error: go tried a build" $((n + 1)) "$(builds)"
check "syntax error: the first line says the build failed" \
  "swarm: binary: go build ./cmd/swarm failed in ${C}, so the ported command did not run:" "$(head -1 <<< "${err}")"
check "syntax error: Go's error follows" yes "$(grep -q 'cmd/swarm/main.go:3:.*syntax error' <<< "${err}" && echo yes || echo "no: ${err}")"
check "syntax error: no word printed" "" "${out}"
check "syntax error: the old binary keeps its inode and mtime" "${was}" "$(stamp "${B}")"
check "syntax error: no build file is left" "" "$(cd "${C}" && find . -maxdepth 1 -name 'swarm.build-*')"
main_go "${C}" two

# No go on PATH: one line, and bash's config does not run. Each PATH directory holding go is replaced by
# one with links to everything in it but go.
NOGO=""; i=0
IFS=: read -r -a dirs <<< "${PATH}"
for d in "${dirs[@]}"; do
  if [[ -n "${d}" && -e "${d}/go" ]]; then
    i=$((i + 1)); s="${ROOT}/nogo${i}"; mkdir -p "${s}"
    ln -s "${d}"/* "${s}/" 2>/dev/null || true
    rm -f "${s}/go"
    d="${s}"
  fi
  NOGO="${NOGO:+${NOGO}:}${d}"
done
check "the no-go PATH has no go" "" "$(PATH="${NOGO}" command -v go || true)"
check "the no-go PATH has bash" yes "$(PATH="${NOGO}" command -v bash > /dev/null && echo yes)"
rm -f "${B}"
sw "${C}" "${NOGO}"
check "no go: exits 1" 1 "${rc}"
check "no go: says it in one line" \
  "swarm: binary: ${C} is a git checkout, which builds the ported command's binary from its tree, and go is not on PATH: install Go, or set SWARMDEV_BIN to a swarm binary" "${err}"
check "no go: bash's config did not run" "" "${out}"
check "no go: no binary built" none "$(stamp "${B}")"

# A copy with no .git: no build is tried. The fetch goes first, and stops with binary_download's line, as
# the copy has no scripts/build.sh to name the release's files.
N="${ROOT}/plain"; cp -R "${C}" "${N}"; rm -rf "${N}/.git"
sw "${N}" "${FAILSTUBS}:${PATH}"
check "no .git: exits 1" 1 "${rc}"
check "no .git: binary_download's line" \
  "binary: cannot tell which release files are this copy's binary: ${N}/scripts/build.sh is missing: reinstall swarm-dev (claude plugin uninstall swarm-dev@swarm-dev, then claude plugin install swarm-dev@swarm-dev)" "${err}"
check "no .git: the go stub logged no call" 0 "$(builds failgo)"

# The same copy installed from swarm-dev-pre: its reinstall hint names swarm-dev@swarm-dev-pre, both
# from binary_download (a gh new enough to download) and from binary_copy_lists (a gh older than
# BINARY_GH_MIN, so the download is never tried).
PRE="${ROOT}/plugins/cache/swarm-dev-pre/swarm-dev/9.9.9"; mkdir -p "${PRE%/*}"; cp -R "${N}" "${PRE}"
PRE_FIX="reinstall swarm-dev (claude plugin uninstall swarm-dev@swarm-dev-pre, then claude plugin install swarm-dev@swarm-dev-pre)"
for v in fit:2.99.0 old:2.0.0; do
  d="${ROOT}/gh-${v%%:*}"; mkdir -p "${d}"
  printf '#!/bin/sh\necho "gh version %s (2026-01-01)"\n' "${v#*:}" > "${d}/gh"; chmod +x "${d}/gh"
  sw "${PRE}" "${d}:${FAILSTUBS}:${PATH}"
  check "-pre copy, ${v%%:*} gh: exits 1" 1 "${rc}"
  check "-pre copy, ${v%%:*} gh: the line names swarm-dev@swarm-dev-pre" \
    "binary: cannot tell which release files are this copy's binary: ${PRE}/scripts/build.sh is missing: ${PRE_FIX}" "${err}"
done

# Two calls started together on a missing binary: both print the word, and git status stays empty.
C2="${ROOT}/co2"; checkout "${C2}" together
for k in 1 2; do
  (cd "${P}" || exit 1
   r=0
   env -u HERDR_ENV -u SWARM_PROJECT -u SWARMDEV_BIN PATH="${GOPATH_RUN}" bash "${C2}/bin/swarm.sh" config \
     < /dev/null > "${ROOT}/out${k}" 2> "${ROOT}/err${k}" || r=$?
   echo "${r}" > "${ROOT}/rc${k}") &
done
wait
for k in 1 2; do
  check "together, call ${k}: exits 0 and prints the word" "0|together|" \
    "$(cat "${ROOT}/rc${k}")|$(cat "${ROOT}/out${k}")|$(cat "${ROOT}/err${k}")"
done
check "together: git status is empty" "" "$(git -C "${C2}" status --porcelain)"
check "together: no build file is left" "" "$(cd "${C2}" && find . -maxdepth 1 -name 'swarm.build-*')"

# A positive control: the fail stub logs a call made through the PATH the no-.git run had.
PATH="${FAILSTUBS}:${PATH}" go control > /dev/null 2>&1 || true
check "the fail stub logs a call" 1 "$(grep -c control "${LOGS}/failgo" || true)"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
