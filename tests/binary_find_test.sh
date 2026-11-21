#!/usr/bin/env bash
# binary_find_test.sh — bin/lib/binary.sh's binary_find finds the swarm binary and never builds or
# downloads it. With SWARMDEV_BIN naming an executable file it prints that path. Naming a missing file, a
# non-executable file, a directory or nothing, it prints one line naming SWARMDEV_BIN and the path,
# returns 1 and looks nowhere else, though the root's build path holds a binary. Unset, in a git checkout
# (a .git directory, or a worktree's .git file) with an executable at the build path, it prints that path.
# With no file or a non-executable one there, and in a copy with no .git, it prints one line saying there
# is no binary and returns 1. Each case runs in a new bash whose PATH holds only gh and go stubs that log
# any call and exit 1, so a call to any program fails it; both logs stay empty. Sourcing the file prints
# nothing and changes no shell option.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="${REPO}/bin/lib/binary.sh"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[[ -d "${ROOT}" ]] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, as every test file
BUILT=swarm   # BINARY_BUILD_PATH, copied here so a change to it is a change to this test too
STUBS="${ROOT}/stubs"; LOGS="${ROOT}/logs"
mkdir -p "${STUBS}" "${LOGS}" "${ROOT}/bins"

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

for s in gh go; do
  printf '#!/bin/sh\necho "$*" >> "%s/%s"\nexit 1\n' "${LOGS}" "${s}" > "${STUBS}/${s}"
  chmod +x "${STUBS}/${s}"
done
# A positive control: each stub logs a call made through the PATH every case runs with, so an empty log
# below means no call.
for s in gh go; do
  PATH="${STUBS}" "${BASH}" -c "${s} control" || true
  check "the ${s} stub logs a call" control "$(cat "${LOGS}/${s}" 2>/dev/null)"
  rm -f "${LOGS:?}/${s}"
done

printf '#!/bin/sh\necho named\n' > "${ROOT}/bins/exec"; chmod +x "${ROOT}/bins/exec"
printf '#!/bin/sh\necho named\n' > "${ROOT}/bins/plain"; chmod -x "${ROOT}/bins/plain"
build() { # <root> [plain]: a binary at <root>'s build path, executable unless plain
  printf '#!/bin/sh\necho built\n' > "$1/${BUILT}"
  if [[ "${2:-}" == plain ]]; then chmod -x "$1/${BUILT}"; else chmod +x "$1/${BUILT}"; fi
}
# A checkout with a .git directory, a worktree of it with a .git file, and a copy with no .git.
CO="${ROOT}/checkout"; WT="${ROOT}/worktree"; COPY="${ROOT}/copy"
EMPTY="${ROOT}/empty"; PLAIN="${ROOT}/plain"
for d in "${CO}" "${EMPTY}" "${PLAIN}"; do git init -q "${d}"; done
git -C "${CO}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q --allow-empty -m init
git -C "${CO}" worktree add -q "${WT}" 2>/dev/null
check "the worktree's .git is a file" file "$([[ -f "${WT}/.git" ]] && echo file || echo not-a-file)"
mkdir -p "${COPY}"
build "${CO}"; build "${WT}"; build "${COPY}"; build "${PLAIN}" plain

# find_in <root> [<SWARMDEV_BIN>]: source the lib and run binary_find <root> in a new bash with only the
# stubs on PATH, SWARMDEV_BIN unset unless given. Sets out, err (its lines) and rc.
find_in() {
  local root="$1" setbin=()
  [[ $# -lt 2 ]] || setbin=("SWARMDEV_BIN=$2")
  rc=0
  # shellcheck disable=SC2016 # the inner bash expands its own arguments
  env -u SWARMDEV_BIN PATH="${STUBS}" ${setbin[@]+"${setbin[@]}"} "${BASH}" -c 'source "$1" && binary_find "$2"' _ \
    "${LIB}" "${root}" > "${ROOT}/out" 2> "${ROOT}/err" || rc=$?
  out="$(cat "${ROOT}/out")"; err="$(cat "${ROOT}/err")"
}
lines() { # <text>: its number of lines, 0 for none
  if [[ -z "$1" ]]; then echo 0; else printf '%s\n' "$1" | wc -l | tr -d ' '; fi
}
# refused <name> <path>: the last find_in printed nothing, returned 1 and said one line naming
# SWARMDEV_BIN and <path>.
refused() {
  check "$1: returns 1" 1 "${rc}"
  check "$1: prints no path" "" "${out}"
  check "$1: says one line" 1 "$(lines "${err}")"
  check "$1: the line names SWARMDEV_BIN and '$2'" yes \
    "$([[ "${err}" == *SWARMDEV_BIN* && "${err}" == *"'$2'"* ]] && echo yes || echo "no: ${err}")"
}
# none <name>: the last find_in printed nothing, returned 1 and said one line that there is no binary.
none() {
  check "$1: returns 1" 1 "${rc}"
  check "$1: prints no path" "" "${out}"
  check "$1: says one line" 1 "$(lines "${err}")"
  check "$1: the line says there is no binary" yes \
    "$([[ "${err}" == *"no swarm binary"* ]] && echo yes || echo "no: ${err}")"
}

# SWARMDEV_BIN set: that file, and nothing else, whatever the root holds.
find_in "${CO}" "${ROOT}/bins/exec"
check "SWARMDEV_BIN executable: returns 0" 0 "${rc}"
check "SWARMDEV_BIN executable: prints its path" "${ROOT}/bins/exec" "${out}"
check "SWARMDEV_BIN executable: says nothing else" "" "${err}"
find_in "${COPY}" "${ROOT}/bins/exec"
check "SWARMDEV_BIN executable, root with no .git: prints its path" "${ROOT}/bins/exec" "${out}"
find_in "${CO}" "${ROOT}/bins/missing"; refused "SWARMDEV_BIN missing" "${ROOT}/bins/missing"
find_in "${CO}" "${ROOT}/bins/plain"; refused "SWARMDEV_BIN not executable" "${ROOT}/bins/plain"
find_in "${CO}" "${ROOT}/bins"; refused "SWARMDEV_BIN a directory" "${ROOT}/bins"
find_in "${CO}" ""; refused "SWARMDEV_BIN empty" ""

# SWARMDEV_BIN unset: the checkout's build path, or no binary.
find_in "${CO}"
check "unset, checkout with a build: returns 0" 0 "${rc}"
check "unset, checkout with a build: prints the build path" "${CO}/${BUILT}" "${out}"
check "unset, checkout with a build: says nothing else" "" "${err}"
find_in "${CO}/"
check "unset, root with a trailing slash: prints the build path" "${CO}/${BUILT}" "${out}"
find_in "${WT}"
check "unset, worktree with a build: prints the build path" "${WT}/${BUILT}" "${out}"
find_in "${EMPTY}"; none "unset, checkout with no build"
find_in "${PLAIN}"; none "unset, checkout whose build is not executable"
find_in "${COPY}"; none "unset, a copy with no .git and a build"
find_in ""; none "unset, no root given"

# Every case above ran with only the stubs on PATH.
for s in gh go; do
  check "no case called ${s}" "" "$(cat "${LOGS}/${s}" 2>/dev/null)"
done

# Sourcing prints nothing and leaves every shell option as it was.
# shellcheck disable=SC2016 # the inner bash expands its own variables
opts="$(env PATH="${STUBS}" "${BASH}" -c 'a="$(set -o; shopt -p)"; source "$1"; b="$(set -o; shopt -p)"
  [[ "${a}" == "${b}" ]] && echo same || echo changed' _ "${LIB}" 2>&1)"
check "sourcing prints nothing and changes no option" same "${opts}"

[[ "${fails}" -eq 0 ]] || { echo "${fails} check(s) failed"; exit 1; }
echo "all binary_find checks passed"
