#!/usr/bin/env bash
# board_rel_test.sh — board_rel (swarm.sh _board-rel), the board's path from the project root with a
# trailing /: empty for a board at the root, docs/ and a/b/ for boards under it, and the real path for
# a board_dir with .. in it. init resolves a board it has just made, so its listing names that path.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
# rel <name> <board_dir line or -> [<dir to make>] — [board_rel] in a project of its own, its board
# made first; - leaves board_dir out of the config, so the default (docs) holds.
rel() {
  local p="${ROOT}/$1"
  mkdir -p "${p}/.claude/swarm" "${p}/${3:-}"
  if [[ "$2" == - ]]; then : > "${p}/.claude/swarm/config"; else echo "board_dir = $2" > "${p}/.claude/swarm/config"; fi
  echo "[$(cd "${p}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${SWARM}" _board-rel)]"
}

check "a board at the root is empty" "[]" "$(rel root . .)"
check "the default board is docs/" "[docs/]" "$(rel default - docs)"
check "a board two folders down is a/b/" "[a/b/]" "$(rel nested a/b a/b)"
check "a board_dir through .. is the real path" "[docs/]" "$(rel dotdot x/../docs x/../docs)"
check "a board_dir of .. back to the root is empty" "[]" "$(rel dotroot docs/.. docs)"

# init makes a board_dir with .. that is not there yet, then lists the files by the path it resolved.
p="${ROOT}/init"
git init -q "${p}"
mkdir -p "${p}/.claude/swarm" && echo "board_dir = sub/../board" > "${p}/.claude/swarm/config"
out="$(cd "${p}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${SWARM}" init 2>&1 || true)"
check "init names a new board_dir with .. by its resolved path" "yes" \
  "$(grep -qxF "copied board/stories/README.md" <<< "${out}" && echo yes || echo "no, got: ${out}")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
