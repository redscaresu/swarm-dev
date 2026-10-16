#!/usr/bin/env bash
# board_pr_test.sh — swarm.sh board-pr: start makes the board worktree off origin/main and refuses
# anything that could touch the main checkout; open commits board files only and opens one PR; done
# clears up only once the PR merged or closed; one events.tsv line per step. gh is a stub on PATH
# that logs every call to gh.log and lists the PRs in ${ROOT}/prs (none without it); origin is a local
# bare repo. A git wrapper on PATH fails `worktree add` while ${ROOT}/wt-add.fail exists,
# `ls-remote` while ${ROOT}/ls-remote.fail does, and `push --delete` while ${ROOT}/push-delete.fail does.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
REPO="$(dirname "${SWARM}")/.."
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; WT="${ROOT}/proj-wt/_board-x"; URL=https://github.com/o/r/pull/9
mkdir -p "${P}/.claude/swarm" "${P}/board/stories" "${P}/bin" "${ROOT}/bin"
printf 'board_dir = board\nbase_branches = main\n' > "${P}/.claude/swarm/config"
cat > "${P}/.claude/swarm/brief.md" <<'BRIEF'
End every commit with this trailer, on a line of its own:

Co-Authored-By: Lead Bot <lead@example.com>

End commit messages with "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" and PR bodies with the footer.
Fill in the templates Reviewed-by: <you@example.com> and Co-Authored-By: <who> <email>.
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
  "pr list") cat "${R}/prs" 2>/dev/null || echo '[]' ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
printf '#!/usr/bin/env bash\nR="%s"; GIT="%s"\n' "${ROOT}" "$(command -v git)" > "${ROOT}/bin/git"
cat >> "${ROOT}/bin/git" <<'STUB'
case " $* " in *" ls-remote "*) [ ! -e "${R}/ls-remote.fail" ] || { echo "fatal: could not read from remote" >&2; exit 128; } ;; esac
case " $* " in *" push "*" --delete "*) [ ! -e "${R}/push-delete.fail" ] || { echo "error: failed to push some refs" >&2; exit 1; } ;; esac
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
# pr <state> [sha] — the one PR the gh stub lists from now on: <state>, its head board/x's tip or <sha>.
pr() { printf '[{"state":"%s","url":"%s","headRefOid":"%s"}]\n' "$1" "${URL}" "${2:-$(git -C "${P}" rev-parse board/x)}" > "${ROOT}/prs"; }
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

# --- A full cycle: start, edit, open, done; the main checkout never changes. A story's worktree
# named board-x (a slug starting board-) sits beside it untouched.
mkdir -p "${ROOT}/proj-wt/board-x"; echo builder > "${ROOT}/proj-wt/board-x/edit"
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
is "open: the commit's trailers are the brief's, a quoted one too, and no placeholder" \
  $'Co-Authored-By: Lead Bot <lead@example.com>\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>' \
  "$(git -C "${WT}" log -1 --format=%B | grep -E -- '-[Bb]y:' || true)"
is "open: the commit has both board files" "board/stories/a.md board/stories/b.md" "$(git -C "${WT}" diff --name-only origin/main HEAD | paste -sd' ' -)"
is "open: logs board-pr:open x ok" "board-pr:open x ok" "$(events)"

# A second open pushes more edits to the PR the first one opened, and creates none.
pr OPEN; echo typo-fixed > "${WT}/board/stories/a.md"
reset_log; bpr open x "Board edit" "${ROOT}/body.md"
is "a second open: exits 0" 0 "${rc}"
is "a second open: prints the open PR's URL" "${URL}" "$(cat "${ROOT}/out")"
is "a second open: no gh pr create" 0 "$(grep -c '^pr create' "${ROOT}/gh.log" || true)"
is "a second open: origin has the new commit" "$(git -C "${WT}" rev-parse HEAD)" "$(git -C "${P}" rev-parse refs/remotes/origin/board/x)"
is "a second open: logs board-pr:open x ok" "board-pr:open x ok" "$(events)"

# An open after the PR merged refuses: the branch still holds the merged commits.
pr MERGED; echo more > "${WT}/board/stories/a.md"; pushed="$(git -C "${P}" rev-parse refs/remotes/origin/board/x)"
reset_log; bpr open x "Board edit" "${ROOT}/body.md"
refused "an open after the PR merged" "has merged or closed" "${before}"
is "an open after the merge: no gh pr create" 0 "$(grep -c '^pr create' "${ROOT}/gh.log" || true)"
is "an open after the merge: nothing pushed" "${pushed}" "$(git -C "${P}" ls-remote origin refs/heads/board/x | cut -f1)"
git -C "${WT}" checkout -q -- board/stories/a.md
# The same after a merge-commit merge, whose head is in origin/main now.
tip="$(git -C "${P}" rev-parse board/x)"
git -C "${P}" fetch -q origin
merge="$(git -C "${P}" commit-tree "${tip}^{tree}" -p refs/remotes/origin/main -p "${tip}" -m "Merge board/x")"
git -C "${P}" push -q origin "${merge}:refs/heads/main"; pr MERGED "${tip}"; echo more > "${WT}/board/stories/a.md"
reset_log; bpr open x "Board edit" "${ROOT}/body.md"
refused "an open after a merge-commit merge" "has merged or closed" "${before}"
git -C "${WT}" checkout -q -- board/stories/a.md

# done refuses, removing nothing, while a newer PR is open though a closed one is on the local tip,
# and when origin's board/x has moved past the local tip.
tip="$(git -C "${P}" rev-parse board/x)"
printf '[{"state":"CLOSED","url":"%s","headRefOid":"%s"},{"state":"OPEN","url":"%s","headRefOid":"%s"}]\n' \
  "${URL}" "${tip}" "${URL}" 2222222222222222222222222222222222222222 > "${ROOT}/prs"
reset_log; bpr "done" x
refused "done with a newer PR open on another head" "still open" "${before}"
check "a newer open PR: board/x stays on origin" on_origin board/x
other="$(git -C "${P}" commit-tree "${tip}^{tree}" -p "${tip}" -m other)"
git -C "${P}" push -q -f origin "${other}:refs/heads/board/x"; pr MERGED
reset_log; bpr "done" x
refused "done when origin's board/x moved on" "origin's board/x is at" "${before}"
is "origin moved on: origin keeps its commit" "${other}" "$(git -C "${P}" ls-remote origin refs/heads/board/x | cut -f1)"
check "origin moved on: board/x stays here" branch board/x
git -C "${P}" push -q -f origin "${tip}:refs/heads/board/x"

# done refuses while the PR is open, or while origin cannot be read, removing nothing; then clears up
# once it merged.
pr OPEN; reset_log; bpr "done" x
refused "done while the PR is open" "still open" "${before}"
check "done while open: the worktree stays" test -d "${WT}"
check "done while open: board/x stays" branch board/x
pr MERGED; touch "${ROOT}/ls-remote.fail"; reset_log; bpr "done" x
refused "done when origin cannot be read" "cannot tell whether origin has board/x" "${before}"
check "done when origin cannot be read: the worktree stays" test -d "${WT}"
check "done when origin cannot be read: board/x stays here" branch board/x
check "done when origin cannot be read: board/x stays on origin" on_origin board/x
rm "${ROOT}/ls-remote.fail"
# origin's delete goes first, so when it fails the local state is all still there.
touch "${ROOT}/push-delete.fail"; reset_log; bpr "done" x
refused "done when origin's delete fails" "cannot delete board/x on origin" "${before}"
check "a failed origin delete: the worktree stays" test -d "${WT}"
check "a failed origin delete: board/x stays here" branch board/x
rm "${ROOT}/push-delete.fail"; reset_log; bpr "done" x
is "done after MERGED: exits 0" 0 "${rc}"
check "done: the worktree is gone" test ! -e "${WT}"
check "done: board/x is gone here" bash -c "! git -C '${P}' show-ref -q --verify refs/heads/board/x"
check "done: board/x is gone on origin" bash -c "! git -C '${P}' ls-remote --exit-code origin refs/heads/board/x >/dev/null"
is "done: logs board-pr:done x ok" "board-pr:done x ok" "$(events)"
is "the full cycle leaves the main checkout byte-identical" "${before}" "$(snap)"
is "the full cycle leaves the story worktree board-x alone" builder "$(cat "${ROOT}/proj-wt/board-x/edit" 2>/dev/null)"

# A new start of the name after that merge-commit merge: the old PR's head is in the new branch's
# start, so open opens a new PR.
bpr start x; echo next > "${WT}/board/stories/c.md"
reset_log; bpr open x "Next edit" "${ROOT}/body.md"
is "a new start after a merge-commit merge: open exits 0" 0 "${rc}"
is "a new start after a merge-commit merge: one gh pr create" 1 "$(grep -c '^pr create' "${ROOT}/gh.log" || true)"
git -C "${P}" worktree remove --force "${WT}"; git -C "${P}" branch -q -D board/x; git -C "${P}" push -q origin --delete board/x

# done leaves alone a worktree at the board path that is not on board/x.
git -C "${P}" branch -q board/x origin/main; git -C "${P}" worktree add -q -b story/q "${WT}" origin/main
pr MERGED; reset_log; bpr "done" x
refused "done on a worktree not on board/x" "is not a worktree on board/x" "${before}"
check "a worktree not on board/x: it stays" test -d "${WT}"
git -C "${P}" worktree remove --force "${WT}"; git -C "${P}" branch -q -D story/q board/x

# An abandoned start (no PR, nothing past the base): done refuses while the worktree has edits, then
# removes it.
rm -f "${ROOT}/prs"; bpr start x; echo dirt > "${WT}/board/stories/a.md"
reset_log; bpr "done" x
refused "done on an abandoned start with edits" "has uncommitted changes" "${before}"
git -C "${WT}" checkout -q -- board/stories/a.md
reset_log; bpr "done" x
is "done on a clean abandoned start: exits 0" 0 "${rc}"
check "a clean abandoned start: the worktree is gone" test ! -e "${WT}"
check "a clean abandoned start: board/x is gone" bash -c "! git -C '${P}' show-ref -q --verify refs/heads/board/x"

# board/x on origin only (a retry after a failed remote delete, or a reused name): done drops it only
# when a PR's head is origin's tip.
git -C "${P}" push -q origin "${other}:refs/heads/board/x"; pr MERGED "${tip}"
reset_log; bpr "done" x
refused "done with board/x only on origin and an old PR" "no PR on board/x has its tip" "${before}"
check "only on origin, old PR: board/x stays on origin" on_origin board/x
pr MERGED "${other}"; reset_log; bpr "done" x
is "done with board/x only on origin and its PR merged: exits 0" 0 "${rc}"
check "only on origin, its PR merged: board/x is gone on origin" bash -c "! git -C '${P}' ls-remote --exit-code origin refs/heads/board/x >/dev/null"
reset_log; bpr "done" x
refused "done with no board/x anywhere" "no board/x here or on origin" "${before}"

# A second use of the name: the first one's merged PR does not let done drop an unpushed commit.
old="$(git -C "${P}" rev-parse refs/remotes/origin/main)"; pr MERGED 1111111111111111111111111111111111111111
bpr start x; echo again > "${WT}/board/stories/a.md"; git -C "${WT}" commit -qam again
reset_log; bpr "done" x
refused "done with only an earlier use's merged PR" "no PR on board/x has its tip" "${before}"
check "an earlier use's PR: the worktree stays" test -d "${WT}"
check "an earlier use's PR: board/x keeps its commit" bash -c "git -C '${P}' log -1 --format=%s board/x | grep -qx again"
git -C "${P}" worktree remove --force "${WT}"; git -C "${P}" branch -q -D board/x

# A locked worktree: done refuses before it removes anything, origin's branch included.
bpr start x; pr MERGED; git -C "${P}" push -q origin board/x; git -C "${P}" worktree lock "${WT}"
reset_log; bpr "done" x
refused "done on a locked worktree" "locked" "${before}"
check "a locked worktree: board/x stays" branch board/x
check "a locked worktree: board/x stays on origin" on_origin board/x
git -C "${P}" worktree unlock "${WT}"; bpr "done" x
is "done once unlocked: exits 0" 0 "${rc}"

# start refuses when origin has board/x already, or cannot be read.
git -C "${P}" push -q origin "${old}:refs/heads/board/x"
reset_log; bpr start x
refused "start when origin has board/x" "origin has board/x" "${before}"
check "origin has board/x: no board/x here" bash -c "! git -C '${P}' show-ref -q --verify refs/heads/board/x"
git -C "${P}" push -q origin --delete board/x
touch "${ROOT}/ls-remote.fail"; reset_log; bpr start x
refused "start when origin cannot be read" "cannot tell whether origin has board/x" "${before}"
rm "${ROOT}/ls-remote.fail"

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
bpr start y; echo changed > "${ROOT}/proj-wt/_board-y/bin/tool"
reset_log; bpr open y "Root board edit" "${ROOT}/body.md"
is "board_dir = .: open exits 0" 0 "${rc}"
is "board_dir = .: open prints the PR URL" "${URL}" "$(cat "${ROOT}/out")"

# --- The docs send the lead's board edits through it.
check "method.md § Who does what names swarm.sh board-pr" \
  bash -c "sed -n '/^## Who does what/,/^## /p' '${REPO}/docs/method.md' | grep -q 'swarm.sh board-pr'"
check "commands/swarm.md names swarm.sh board-pr" grep -q 'swarm.sh board-pr' "${REPO}/commands/swarm.md"

echo
if [[ ${fails} -eq 0 ]]; then echo "all board-pr tests passed"; else echo "${fails} board-pr test(s) failed"; exit 1; fi
