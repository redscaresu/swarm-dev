#!/usr/bin/env bash
# board_pr_test.sh — swarm.sh board-pr: start makes the board worktree off origin/main and refuses
# anything that could touch the main checkout; open commits board files only and opens one PR; done
# clears up only once the PR merged or closed; one events.tsv line per step. gh is a stub on PATH
# that logs every call to gh.log and lists a PR whose state is ${ROOT}/state; origin is a local
# bare repo. A git wrapper on PATH fails `worktree add` while ${ROOT}/wt-add.fail exists, and
# `ls-remote` while ${ROOT}/ls-remote.fail does.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
REPO="$(dirname "${SWARM}")/.."
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; WT="${ROOT}/proj-wt/board-x"; URL=https://github.com/o/r/pull/9
mkdir -p "${P}/.claude/swarm" "${P}/board/stories" "${P}/bin" "${ROOT}/bin"
printf 'board_dir = board\nbase_branches = main\n' > "${P}/.claude/swarm/config"
cat > "${P}/.claude/swarm/brief.md" <<'BRIEF'
Sign off every commit with `Co-Authored-By: Lead Bot <lead@example.com>`.
BRIEF
echo .swarm/ > "${P}/.gitignore"
echo story > "${P}/board/stories/a.md"; echo code > "${P}/bin/tool"
git init -q --bare "${ROOT}/origin.git"
git -C "${P}" init -q -b main
git -C "${P}" -c user.name=t -c user.email=t@t add -A
git -C "${P}" -c user.name=t -c user.email=t@t commit -qm init
git -C "${P}" remote add origin "${ROOT}/origin.git"
git -C "${P}" push -q -u origin main
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

printf '#!/usr/bin/env bash\nR="%s"\n' "${ROOT}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "${R}/gh.log"
case "$1 $2" in
  "pr create") echo "https://github.com/o/r/pull/9" ;;
  "pr list") printf '[{"state":"%s"}]\n' "$(cat "${R}/state")" ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
printf '#!/usr/bin/env bash\nR="%s"; GIT="%s"\n' "${ROOT}" "$(command -v git)" > "${ROOT}/bin/git"
cat >> "${ROOT}/bin/git" <<'STUB'
case " $* " in *" ls-remote "*) [ ! -e "${R}/ls-remote.fail" ] || { echo "fatal: could not read from remote" >&2; exit 128; } ;; esac
case " $* " in *" worktree add "*) [ ! -e "${R}/wt-add.fail" ] || { echo "fatal: invalid reference: origin/main" >&2; exit 128; } ;; esac
exec "${GIT}" "$@"
STUB
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/git"

# bpr <args> — swarm.sh board-pr from the main checkout; sets rc, stdout in out, stderr in err.
bpr() {
  rc=0
  (cd "${P}" && env -u SWARM_PROJECT -u HERDR_PANE_ID PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" board-pr "$@" \
    > "${ROOT}/out" 2> "${ROOT}/err") || rc=$?
}
# snap — a hash of every file in the main checkout but .git and .swarm (events.tsv lives there).
snap() { (cd "${P}" && find . -path ./.git -prune -o -path ./.swarm -prune -o -type f -print | LC_ALL=C sort | xargs shasum); }
events() { awk -F'\t' '{ print $2 " " $3 " " $5 }' "${P}/.swarm/events.tsv" 2>/dev/null || true; }
lines() { events | grep -c . || true; }
logged() { grep -qF -- "board-pr:" <<< "$(events)" && grep -qF -- "$1" <<< "$(events)"; }
reset_log() { rm -f "${P}/.swarm/events.tsv" "${ROOT}/gh.log"; : > "${ROOT}/gh.log"; }
branch() { git -C "${P}" show-ref -q --verify "refs/heads/$1"; }
on_origin() { git -C "${P}" ls-remote --exit-code origin "refs/heads/$1" >/dev/null 2>&1; }

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
# refused <name> <text> <snapshot> — the last call failed naming <text>, printed nothing on stdout,
# left the main checkout as <snapshot> and logged exactly one line, its refusal.
refused() {
  is "$1: exits non-zero" 1 "${rc}"
  check "$1: says ${2}" grep -qF -- "$2" "${ROOT}/err"
  is "$1: prints no path" "" "$(cat "${ROOT}/out")"
  is "$1: the main checkout is unchanged" "$3" "$(snap)"
  is "$1: one events line" 1 "$(lines)"
  check "$1: the line is the refusal" logged "$2"
}

# --- A full cycle: start, edit, open, done; the main checkout never changes.
before="$(snap)"; reset_log
bpr start x
is "start: exits 0" 0 "${rc}"
is "start: prints the worktree's path" "${WT}" "$(cat "${ROOT}/out")"
is "start: the worktree is on board/x" board/x "$(git -C "${WT}" symbolic-ref --short HEAD)"
is "start: board/x starts at origin/main" "$(git -C "${P}" rev-parse origin/main)" "$(git -C "${WT}" rev-parse HEAD)"
is "start: logs board-pr:start x ok" "board-pr:start x ok" "$(events)"

reset_log; after_start="$(snap)"
bpr start x
refused "a second start x" "exists" "${after_start}"
is "a second start x leaves board/x where it was" "$(git -C "${P}" rev-parse origin/main)" "$(git -C "${P}" rev-parse board/x)"

# open refuses a change outside the board, and opens nothing.
echo changed > "${WT}/board/stories/a.md"; echo new > "${WT}/board/stories/b.md"
echo hacked > "${WT}/bin/tool"
reset_log; bpr open x "Board edit" "${P}/.gitignore"
refused "open with bin/tool changed" "bin/tool is outside board/" "${before}"
check "open with bin/tool changed: no gh call" test ! -s "${ROOT}/gh.log"
check "open with bin/tool changed: nothing pushed" bash -c "! git -C '${P}' ls-remote --exit-code origin refs/heads/board/x >/dev/null"
git -C "${WT}" checkout -q -- bin/tool

echo "The board edit." > "${ROOT}/body.md"
reset_log; bpr open x "Board edit" "${ROOT}/body.md"
is "open: exits 0" 0 "${rc}"
is "open: prints the PR URL" "${URL}" "$(cat "${ROOT}/out")"
is "open: one gh pr create" 1 "$(grep -c '^pr create' "${ROOT}/gh.log")"
check "open: the PR is board/x into main" grep -qF -- "--base main --head board/x --title Board edit --body-file ${ROOT}/body.md" "${ROOT}/gh.log"
check "open: board/x is on origin" on_origin board/x
is "open: origin has the commit" "$(git -C "${WT}" rev-parse HEAD)" "$(git -C "${P}" rev-parse refs/remotes/origin/board/x)"
check "open: the commit carries the brief's trailer" bash -c "git -C '${WT}' log -1 --format=%B | grep -qxF 'Co-Authored-By: Lead Bot <lead@example.com>'"
is "open: the commit has both board files" "board/stories/a.md board/stories/b.md" "$(git -C "${WT}" diff --name-only origin/main HEAD | paste -sd' ' -)"
is "open: logs board-pr:open x ok" "board-pr:open x ok" "$(events)"

# done refuses while the PR is open, and clears up once it merged.
echo OPEN > "${ROOT}/state"; reset_log; bpr "done" x
refused "done while the PR is open" "still open" "${before}"
check "done while open: the worktree stays" test -d "${WT}"
check "done while open: board/x stays" branch board/x
echo MERGED > "${ROOT}/state"; touch "${ROOT}/ls-remote.fail"; reset_log; bpr "done" x
refused "done when origin cannot be read" "cannot tell whether origin still has board/x" "${before}"
check "done when origin cannot be read: board/x stays on origin" on_origin board/x
rm "${ROOT}/ls-remote.fail"; reset_log; bpr "done" x
is "done after MERGED: exits 0" 0 "${rc}"
check "done: the worktree is gone" test ! -e "${WT}"
check "done: board/x is gone here" bash -c "! git -C '${P}' show-ref -q --verify refs/heads/board/x"
check "done: board/x is gone on origin" bash -c "! git -C '${P}' ls-remote --exit-code origin refs/heads/board/x >/dev/null"
is "done: logs board-pr:done x ok" "board-pr:done x ok" "$(events)"
is "the full cycle leaves the main checkout byte-identical" "${before}" "$(snap)"

# --- start's refusals, each with no branch made.
mkdir -p "${WT}"; reset_log; bpr start x
refused "start onto an existing directory" "exists" "${before}"
check "existing directory: no board/x" bash -c "! git -C '${P}' show-ref -q --verify refs/heads/board/x"
rm -rf "${ROOT}/proj-wt"

# <repo>-wt through a symlink and .. to the main checkout: board-x would land inside it.
ln -s "${P}/board/.." "${ROOT}/proj-wt"; reset_log; bpr start x
refused "start into the main checkout through a symlink and .." "in the main checkout" "${before}"
check "symlinked target: no board/x" bash -c "! git -C '${P}' show-ref -q --verify refs/heads/board/x"
rm "${ROOT}/proj-wt"

touch "${ROOT}/wt-add.fail"; reset_log; bpr start x
refused "start when git worktree add fails (a bad base ref)" "git worktree add failed" "${before}"
rm "${ROOT}/wt-add.fail"

reset_log; bpr start ../proj
refused "a name with .." "not a name" "${before}"

# --- board_dir = .: the whole repo is the board, so open takes any file.
printf 'board_dir = .\nbase_branches = main\n' > "${P}/.claude/swarm/config"
bpr start y; echo changed > "${ROOT}/proj-wt/board-y/bin/tool"
reset_log; bpr open y "Root board edit" "${ROOT}/body.md"
is "board_dir = .: open exits 0" 0 "${rc}"
is "board_dir = .: open prints the PR URL" "${URL}" "$(cat "${ROOT}/out")"

# --- The docs send the lead's board edits through it.
check "method.md § Who does what names swarm.sh board-pr" \
  bash -c "sed -n '/^## Who does what/,/^## /p' '${REPO}/docs/method.md' | grep -q 'swarm.sh board-pr'"
check "commands/swarm.md names swarm.sh board-pr" grep -q 'swarm.sh board-pr' "${REPO}/commands/swarm.md"

echo
if [[ ${fails} -eq 0 ]]; then echo "all board-pr tests passed"; else echo "${fails} board-pr test(s) failed"; exit 1; fi
