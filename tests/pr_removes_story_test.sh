#!/usr/bin/env bash
# pr_removes_story_test.sh — a builder's PR takes its story off an in-repo board, and the epic with its
# last story; finish and drop on an in-repo board delete through a board PR and leave the main checkout
# alone; on an external board finish deletes in place; the conductor's brief and /swarm send story
# edits through board-pr. gh is a stub on PATH that logs to gh.log and creates a PR, which pr list
# then lists as open on its head; origin is a local bare repo.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
REPO="$(dirname "${SWARM}")/.."
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
URL=https://github.com/o/r/pull/9

mkdir -p "${ROOT}/bin"
printf '#!/usr/bin/env bash\nR="%s"\n' "${ROOT}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "${R}/gh.log"
case "$1 $2" in
  "pr create") echo "https://github.com/o/r/pull/9"; touch "${R}/open.$(sed 's/.*--head \([^ ]*\).*/\1/; s#/#_#g' <<< "$*")" ;;
  "pr list") h="$(sed 's/.*--head \([^ ]*\).*/\1/; s#/#_#g' <<< "$*")"
             if [ -e "${R}/open.${h}" ]; then echo '[{"state":"OPEN","url":"https://github.com/o/r/pull/9","headRefOid":"x"}]'; else echo '[]'; fi ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
chmod +x "${ROOT}/bin/gh"

item() { # <file> <front-matter line>...
  local path="$1" title; shift
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

# An in-repo board, committed and pushed to origin.
P="${ROOT}/proj"; B="${P}/board"
mkdir -p "${P}/.claude/swarm"; printf 'board_dir = board\n' > "${P}/.claude/swarm/config"
echo .swarm/ > "${P}/.gitignore"
item "${B}/epics/e.md" "status: active"
item "${B}/epics/f.md" "status: active"
item "${B}/stories/one.md" "status: ready"
item "${B}/stories/e1.md" "status: ready" "epic: e"
item "${B}/stories/e2.md" "status: ready" "epic: e"
item "${B}/stories/f1.md" "status: ready" "epic: f"
item "${B}/stories/f2.md" "status: ready" "epic: f" "after: f"
item "${B}/stories/done-one.md" "status: review"
item "${B}/stories/esc.md" "status: ready" "kind: lead" "escalated_from: code"
git init -q --bare "${ROOT}/origin.git"; git -C "${ROOT}/origin.git" symbolic-ref HEAD refs/heads/main
git -C "${P}" init -q -b main
git -C "${P}" add -A && git -C "${P}" commit -qm init
git -C "${P}" remote add origin "${ROOT}/origin.git"
git -C "${P}" push -q -u origin main

# An external board: a project whose board_dir is outside it.
X="${ROOT}/xproj"; XB="${ROOT}/vault"
mkdir -p "${X}/.claude/swarm"; printf 'board_dir = %s\n' "${XB}" > "${X}/.claude/swarm/config"
item "${XB}/epics/g.md" "status: active"
item "${XB}/stories/g1.md" "status: ready" "epic: g"
git -C "${X}" init -q -b main && git -C "${X}" commit -q --allow-empty -m init

# sw <dir> <args> — swarm.sh from <dir>; sets rc, stdout and stderr in out.
sw() {
  local d="$1"; shift; rc=0
  out="$(cd "${d}" && env -u SWARM_PROJECT -u HERDR_PANE_ID PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1)" || rc=$?
}
fails=0
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }
cleanup() { sw "$1" _brief "$2"; grep -oE 'Delete .* under [^ ]*/\.|Do not touch [^.]*\.' <<< "${out}" | head -1; }

# --- The builder's brief.
is "a one-off's brief deletes only its story" \
  "Delete board/stories/one.md in your PR, and nothing else under board/stories/." "$(cleanup "${P}" one)"
is "an epic story's brief, with another open story, leaves the epic" \
  "Delete board/stories/e1.md in your PR, and nothing else under board/stories/." "$(cleanup "${P}" e1)"
is "an epic story's brief, with only an after: story left, deletes the epic too" \
  "Delete board/stories/f1.md and board/epics/f.md (its epic's last story) in your PR, and nothing else under board/." "$(cleanup "${P}" f1)"
rm "${B}/stories/e2.md"
is "an epic story's brief, with no other story, deletes the epic too" \
  "Delete board/stories/e1.md and board/epics/e.md (its epic's last story) in your PR, and nothing else under board/." "$(cleanup "${P}" e1)"
git -C "${P}" checkout -q -- board
is "an external-board story's brief deletes nothing" "Do not touch the story file; the lead takes it off the board after your PR merges." \
  "$(cleanup "${X}" g1)"

# --- finish and drop on the in-repo board: a board PR each, the main checkout untouched.
: > "${ROOT}/gh.log"
sw "${P}" finish done-one
is "finish: exits 0" 0 "${rc}"
is "finish: the main checkout is clean" "" "$(git -C "${P}" status --porcelain)"
is "finish: the story is still in the main checkout" yes "$([[ -f "${B}/stories/done-one.md" ]] && echo yes || echo no)"
is "finish: opens one board PR" 1 "$(grep -c '^pr create' "${ROOT}/gh.log")"
is "finish: the board PR deletes the story" "D	board/stories/done-one.md" \
  "$(git -C "${ROOT}/origin.git" diff --name-status main board/finish-done-one)"
is "finish: prints the merge --board line" yes "$(has "land it: swarm.sh merge --board ${URL}" "${out}")"

sw "${P}" finish done-one
is "a second finish: exits 0 and pushes to the same PR" "0 1" "${rc} $(grep -c '^pr create' "${ROOT}/gh.log")"

sw "${P}" drop esc "no longer needed"
is "drop: exits 0" 0 "${rc}"
is "drop: the main checkout is clean" "" "$(git -C "${P}" status --porcelain)"
is "drop: opens a second board PR" 2 "$(grep -c '^pr create' "${ROOT}/gh.log")"
is "drop: the board PR deletes the story" "D	board/stories/esc.md" "$(git -C "${ROOT}/origin.git" diff --name-status main board/finish-esc)"
is "drop: prints the merge --board line" yes "$(has "land it: swarm.sh merge --board ${URL}" "${out}")"

# --- finish on the external board deletes the file where it is.
sw "${X}" finish g1
is "finish on an external board: exits 0" 0 "${rc}"
is "finish on an external board: deletes the file" no "$([[ -f "${XB}/stories/g1.md" ]] && echo yes || echo no)"

# --- Story edits go through board-pr.
# shellcheck disable=SC2016 # the backticks are the brief's, escaped in its heredoc
is "conduct_brief names board-pr for a story edit" yes \
  "$(has '(\`swarm.sh board-pr\`), as the lead does, never in the main checkout.' "$(awk '/^conduct_brief\(\)/,/^}/' "${REPO}/bin/lib/build.sh")")"
is "commands/swarm.md names board-pr for a conductor's story edit" yes \
  "$(has "edit to a story goes through \`swarm.sh board-pr\` too (its brief says so)." "$(cat "${REPO}/commands/swarm.md")")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
