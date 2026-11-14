#!/usr/bin/env bash
# retro_done_test.sh — retro_done <ref> <version> <tag> (bin/lib/board.sh) on a git fixture. A done
# retro file covering the version from at or before the tag passes and prints its covers line. Each
# other shape fails with its reason on one line: covers ending at another version or starting after the
# tag, no done:, a done: that is not a date, a covers: only in the body or with a trailing word, no
# file. It reads the file at the ref, never the checkout, and a board outside the repo always fails.
# The repo's own retro notes (v0.28.0.md, v0.30.0.md) fail as notes.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
export HOME="${ROOT}/home"   # no global git config (commit signing) reaches the fixture's commits
mkdir -p "${HOME}"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

P="${ROOT}/proj"
F="board/retros/v1.3.0.md"
git init -q "${P}"
mkdir -p "${P}/board/retros"
echo "# fixture" > "${P}/README.md"
git -C "${P}" add -A
git -C "${P}" -c user.name=t -c user.email=t@t commit -q -m base
BASE_REF="$(git -C "${P}" rev-parse HEAD)"

# commit_retro <line>... — commit the lines as ${F}, and print the new commit's sha.
commit_retro() {
  printf '%s\n' "$@" > "${P}/${F}"
  git -C "${P}" add -A
  git -C "${P}" -c user.name=t -c user.email=t@t commit -q -m "retro $*"
  git -C "${P}" rev-parse HEAD
}

# rd <ref> <version> <tag> [<board> <in repo>] — "<exit> <stdout>" of retro_done, board.sh sourced in a
# subshell over P with swarm.sh's own board_rel, on P/board in the repo unless told otherwise.
# shellcheck disable=SC2030,SC2031,SC2329 # each call sets the board in its own subshell; die is board.sh's
rd() {
  (PROJECT_DIR="${P}" BOARD="${4:-${P}/board}" BOARD_IN_REPO="${5:-1}"
   die() { echo "swarm: $*" >&2; exit 1; }
   eval "$(grep '^board_rel()' "${REPO}/bin/swarm.sh")"
   # shellcheck source=bin/lib/board.sh
   source "${REPO}/bin/lib/board.sh"
   out="$(retro_done "$1" "$2" "$3")" && code=0 || code=$?
   echo "${code} ${out}")
}

GOOD="$(commit_retro --- 'covers: v1.2.0..v1.3.0' 'done: 2026-11-20' --- '' '# Retro: v1.3.0')"
check "a done retro passes for 1.3.0 with tag 1.2.0, printing its covers line" \
  "0 covers v1.2.0..v1.3.0, done 2026-11-20" "$(rd "${GOOD}" 1.3.0 1.2.0)"
check "it passes with tag 1.2.5, the covers start before it" \
  "0 covers v1.2.0..v1.3.0, done 2026-11-20" "$(rd "${GOOD}" 1.3.0 1.2.5)"

ref="$(commit_retro --- 'covers: v1.2.0..v1.2.5' 'done: 2026-11-20' ---)"
check "covers ending at v1.2.5 fails for 1.3.0" \
  "1 ${F} at ${ref}: covers: v1.2.0..v1.2.5 ends at v1.2.5, not v1.3.0" "$(rd "${ref}" 1.3.0 1.2.0)"

ref="$(commit_retro --- 'covers: v1.2.6..v1.3.0' 'done: 2026-11-20' ---)"
check "covers starting at v1.2.6 fails with tag 1.2.5" \
  "1 ${F} at ${ref}: covers: v1.2.6..v1.3.0 starts at v1.2.6, after the last tag v1.2.5" "$(rd "${ref}" 1.3.0 1.2.5)"

ref="$(commit_retro --- 'covers: v1.2.0..v1.3.0' ---)"
check "no done: fails" "1 ${F} at ${ref} has no done: in its front matter" "$(rd "${ref}" 1.3.0 1.2.0)"

ref="$(commit_retro --- 'covers: v1.2.0..v1.3.0' 'done: soon' ---)"
check "done: soon fails" "1 ${F} at ${ref}: done: 'soon' is not YYYY-MM-DD" "$(rd "${ref}" 1.3.0 1.2.0)"

ref="$(commit_retro --- 'done: 2026-11-20' --- '' 'covers: v1.2.0..v1.3.0')"
check "a covers: only in the body fails" "1 ${F} at ${ref} has no covers: in its front matter" "$(rd "${ref}" 1.3.0 1.2.0)"

ref="$(commit_retro --- 'covers: v1.2.0..v1.3.0 later' 'done: 2026-11-20' ---)"
check "a covers: with a trailing word fails" \
  "1 ${F} at ${ref}: covers: 'v1.2.0..v1.3.0 later' is not v<a.b.c>..v<x.y.z>" "$(rd "${ref}" 1.3.0 1.2.0)"

check "no file at the ref fails" "1 no board/retros/v1.4.0.md at ${GOOD}" "$(rd "${GOOD}" 1.4.0 1.3.0)"

# The checkout holds the good file, committed after BASE_REF: retro_done reads BASE_REF, not the disk.
commit_retro --- 'covers: v1.2.0..v1.3.0' 'done: 2026-11-20' --- > /dev/null
check "the checkout's file is the good one" "0 covers v1.2.0..v1.3.0, done 2026-11-20" "$(rd HEAD 1.3.0 1.2.0)"
check "a file committed after the ref fails at the ref while the checkout has it" \
  "1 no ${F} at ${BASE_REF}" "$(rd "${BASE_REF}" 1.3.0 1.2.0)"

# A board outside the repo, with the good file on disk, still fails.
V="${ROOT}/vault"
mkdir -p "${V}/retros" && cp "${P}/${F}" "${V}/retros/v1.3.0.md"
check "a board outside the repo fails while the file is on disk" \
  "1 no retro file can be read at HEAD: the board (${V}) is outside the project's repo" "$(rd HEAD 1.3.0 1.2.0 "${V}" 0)"

# The repo's own retro notes have neither field, so they stay notes.
for n in v0.28.0 v0.30.0; do
  cp "${REPO}/board/retros/${n}.md" "${P}/board/retros/${n}.md"
done
git -C "${P}" add -A
git -C "${P}" -c user.name=t -c user.email=t@t commit -q -m notes
for v in 0.28.0 0.30.0; do
  check "board/retros/v${v}.md is a note, not a retro" \
    "1 board/retros/v${v}.md at HEAD has neither done: nor covers: in its front matter, so it is a note, not a retro" \
    "$(rd HEAD "${v}" 0.27.2)"
done

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
