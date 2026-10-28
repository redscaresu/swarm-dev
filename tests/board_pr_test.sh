#!/usr/bin/env bash
# board_pr_test.sh — swarm.sh board-pr: start makes the board worktree off origin/main and refuses
# anything that could touch the main checkout; open commits board files only and opens one PR; done
# clears up only once the PR merged or closed; one events.tsv line per step. gh is a stub on PATH
# that logs every call to gh.log and lists the PRs in ${ROOT}/prs (none without it); origin is a local
# bare repo. A git wrapper on PATH fails `worktree add` while ${ROOT}/wt-add.fail exists, `fetch` while
# ${ROOT}/fetch.fail does,
# `ls-remote` while ${ROOT}/ls-remote.fail does, and `push --delete` while ${ROOT}/push-delete.fail does.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
REPO="$(dirname "${SWARM}")/.."
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; WT="${ROOT}/proj-wt/_board-x"; URL=https://github.com/o/r/pull/9
mkdir -p "${P}/.claude/swarm" "${P}/board/stories" "${P}/bin" "${ROOT}/bin"
printf 'board_dir = board\n' > "${P}/.claude/swarm/config"
cat > "${P}/.claude/swarm/brief.md" <<'BRIEF'
End every commit with this trailer, on a line of its own:

Co-Authored-By: Lead Bot <lead@example.com>

End commit messages with "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" and PR bodies with the footer.
Fill in the templates Reviewed-by: <you@example.com> and Co-Authored-By: <who> <email>.
Every commit needs a Co-Authored-By: line, for example Co-Authored-By: Helper Bot <helper@example.com>.
Signed-off-by: is not used; Co-Authored-By: Lead <l@x.com>
BRIEF
echo .swarm/ > "${P}/.gitignore"
echo story > "${P}/board/stories/a.md"; echo code > "${P}/bin/tool"
git init -q --bare "${ROOT}/origin.git"; git -C "${ROOT}/origin.git" symbolic-ref HEAD refs/heads/main
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
case " $* " in *" fetch "*) [ ! -e "${R}/fetch.fail" ] || { echo "fatal: could not read from remote" >&2; exit 128; } ;; esac
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
# day <n> — the local date <n> days before today (-1: tomorrow). An epic's agreed: is a ticket only
# from today back AGREED_MAX_AGE (board.sh's, 7) days.
day() { python3 -c 'import datetime, sys; print(datetime.date.today() - datetime.timedelta(days=int(sys.argv[1])))' "$1"; }

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
is "open: the commit's trailers are the brief's, quoted or in a sentence, with no prose and no placeholder" \
  $'Co-Authored-By: Lead Bot <lead@example.com>\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\nCo-Authored-By: Helper Bot <helper@example.com>\nCo-Authored-By: Lead <l@x.com>' \
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

# done refuses, removing nothing, while board/x is checked out in another worktree.
bpr start x; git -C "${P}" push -q origin board/x; pr MERGED
git -C "${P}" worktree remove "${WT}"; git -C "${P}" worktree add -q "${ROOT}/elsewhere" board/x
reset_log; bpr "done" x
refused "done while board/x is checked out elsewhere" "board/x is checked out at ${ROOT}/elsewhere" "${before}"
check "checked out elsewhere: board/x stays on origin" on_origin board/x
check "checked out elsewhere: board/x stays here" branch board/x
git -C "${P}" worktree remove "${ROOT}/elsewhere"; bpr "done" x
is "done once nothing has board/x checked out: exits 0" 0 "${rc}"

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

# --- /plan-epic's large-epic path: the board PR that splits big (scope-big, big at status: split) opens
# only once the split critic wrote .swarm/big/split-critic.json; a medium epic's board PR needs none.
# The worktree's start is backdated, so a critic answer written in the same second still counts as newer.
# big is on main before its split, as a /plan-epic split finds it, so its children's parent: counts.
git clone -q "${ROOT}/origin.git" "${ROOT}/big-base"; mkdir -p "${ROOT}/big-base/board/epics"
printf -- '---\nstatus: active\nagreed: 2026-01-01\n---\n\n# big\n' > "${ROOT}/big-base/board/epics/big.md"
git -C "${ROOT}/big-base" add -A && git -C "${ROOT}/big-base" commit -qm "add big" && git -C "${ROOT}/big-base" push -q origin HEAD:main
git -C "${P}" fetch -q origin
rm -f "${ROOT}/prs"; bpr start scope-big; SB="${ROOT}/proj-wt/_board-scope-big/board/epics"; mkdir -p "${SB}"
touch -t 202101010000 "${ROOT}/proj-wt/_board-scope-big/.git"
printf -- '---\nstatus: split\ndepends_on: []\n---\n\n# big\n' > "${SB}/big.md"
printf -- '---\nstatus: active\nparent: big\ndepends_on: []\n---\n\n# big-a\n' > "${SB}/big-a.md"
before="$(snap)"; reset_log; bpr open scope-big "Split big" "${ROOT}/body.md"
refused "a split's board PR with no split-critic.json" "start the split critic first" "${before}"
check "a split's board PR with no split-critic.json: no gh call" test ! -s "${ROOT}/gh.log"
mkdir -p "${P}/.swarm/big"; echo '{"verdict": "fine"}' > "${P}/.swarm/big/split-critic.json"
reset_log; bpr open scope-big "Split big" "${ROOT}/body.md"
refused "a split's board PR whose split-critic.json has no findings list" "start the split critic first" "${before}"
# One an abandoned draft left (older than this worktree) is refused too.
echo '{"findings": []}' > "${P}/.swarm/big/split-critic.json"; touch -t 202001010000 "${P}/.swarm/big/split-critic.json"
reset_log; bpr open scope-big "Split big" "${ROOT}/body.md"
refused "a split's board PR whose split-critic.json is older than its worktree" "older than this board PR's worktree" "${before}"
echo '{"findings": [{"kind": "split-gap", "why": "w", "fix": "f"}]}' > "${P}/.swarm/big/split-critic.json"
reset_log; bpr open scope-big "Split big" "${ROOT}/body.md"
is "a split's board PR opens once the split critic answered" "0 ${URL}" "${rc} $(cat "${ROOT}/out")"
is "the split's board PR is recorded for flow, with its day" "$(date +%F)	${URL}" "$(cat "${P}/.swarm/big/split-pr")"
echo "2026-01-01	${URL}" > "${P}/.swarm/big/split-pr"; bpr open scope-big "Split big" "${ROOT}/body.md"
is "a second open of the split's PR keeps its first day" "2026-01-01	${URL}" "$(cat "${P}/.swarm/big/split-pr")"
# A later board PR on an epic the base already has split (a missed child) is no new split: it opens
# with no critic file, and leaves the first split's record as it was.
git clone -q "${ROOT}/origin.git" "${ROOT}/old-split"; mkdir -p "${ROOT}/old-split/board/epics" "${P}/.swarm/old"
printf -- '---\nstatus: split\n---\n\n# old\n' > "${ROOT}/old-split/board/epics/old.md"
git -C "${ROOT}/old-split" add board/epics/old.md && git -C "${ROOT}/old-split" commit -qm "old is split" && git -C "${ROOT}/old-split" push -q origin HEAD:main
git -C "${P}" fetch -q origin
printf '2026-01-01\thttps://github.com/o/r/pull/1\n' > "${P}/.swarm/old/split-pr"
bpr start scope-old; printf -- '---\nstatus: active\nparent: old\n---\n\n# old-b\n' > "${ROOT}/proj-wt/_board-scope-old/board/epics/old-b.md"
reset_log; bpr open scope-old "Add old-b" "${ROOT}/body.md"
is "a later board PR on an already-split epic opens with no split-critic.json" "0 ${URL}" "${rc} $(cat "${ROOT}/out")"
is "it leaves the first split's record as it was" "2026-01-01	https://github.com/o/r/pull/1" "$(cat "${P}/.swarm/old/split-pr")"
bpr start scope-med; mkdir -p "${ROOT}/proj-wt/_board-scope-med/board/epics"
printf -- '---\nstatus: active\nagreed: %s\n---\n\n# med\n' "$(day 0)" > "${ROOT}/proj-wt/_board-scope-med/board/epics/med.md"
echo story > "${ROOT}/proj-wt/_board-scope-med/board/stories/med-a.md"
reset_log; bpr open scope-med "Plan med" "${ROOT}/body.md"
is "a medium epic's board PR opens with no split-critic.json" "0 ${URL}" "${rc} $(cat "${ROOT}/out")"

# --- An epic that goes active (new, or not active at the base) needs a ticket: agreed:, parent:, an hld:
# naming an HLD agreed with grants: [epics] at both ends, or lead_epics = on. A refused PR creates no
# PR and pushes nothing. Fixtures on origin/main go in through the old-split clone.
NT="goes active with no ticket (agreed: within the last 7 days, parent:, hld: of an agreed HLD granting epics, or lead_epics = on); commit it as status: draft first, then run /swarm-dev:epic"
# on_main <path> <content> — commit <path> with <content> on origin/main, fetched here.
on_main() {
  mkdir -p "$(dirname "${ROOT}/old-split/$1")"; printf '%b' "$2" > "${ROOT}/old-split/$1"
  git -C "${ROOT}/old-split" add "$1" && git -C "${ROOT}/old-split" commit -qm "add $1" && git -C "${ROOT}/old-split" push -q origin HEAD:main
}
# ep <board-pr name> <path under board/> <content> — write a file in that board PR's worktree.
ep() { mkdir -p "$(dirname "${ROOT}/proj-wt/_board-$1/board/$2")"; printf '%b' "$3" > "${ROOT}/proj-wt/_board-$1/board/$2"; }
# guard_refused <name> <case> <text> — open board PR <name>: refused saying <text>, with no gh pr
# create and no board/<name> on origin.
guard_refused() {
  local before; before="$(snap)"; reset_log; bpr open "$1" "Epic" "${ROOT}/body.md"
  refused "$2" "$3" "${before}"
  is "$2: no gh pr create" 0 "$(grep -c '^pr create' "${ROOT}/gh.log" || true)"
  check "$2: no board/$1 on origin" bash -c "! git -C '${P}' ls-remote --exit-code origin refs/heads/board/$1 >/dev/null"
}
guard_opens() { reset_log; bpr open "$1" "Epic" "${ROOT}/body.md"; is "$2 opens" "0 ${URL}" "${rc} $(cat "${ROOT}/out")"; }
on_main board/epics/flip.md '---\nstatus: draft\n---\n\n# flip\n'
# TODAY: a date inside AGREED_MAX_AGE all through the run (a day old by then at most), so only the
# rule a case is about refuses it.
TODAY="$(day 0)"
on_main board/epics/stale.md "---\nstatus: draft\nagreed: ${TODAY}\n---\n\n# stale\n"
on_main board/epics/fresh.md '---\nstatus: draft\nagreed: 2026-01-01\n---\n\n# fresh\n'
on_main board/epics/selfp.md '---\nstatus: draft\n---\n\n# selfp\n'
on_main board/epics/pdraft.md '---\nstatus: draft\n---\n\n# pdraft\n'
on_main board/epics/pact.md '---\nstatus: active\n---\n\n# pact\n'
on_main board/epics/pstale.md '---\nstatus: draft\n---\n\n# pstale\n'
on_main board/epics/nostat.md '---\ndepends_on: []\n---\n\n# nostat\n'
# was-<status>.md: an epic at each status but active (and draft, above) on origin/main.
for st in later split review "done"; do on_main "board/epics/was-${st}.md" "---\nstatus: ${st}\n---\n\n# was-${st}\n"; done
on_main board/epics/act.md '---\nstatus: active\n---\n\n# act\n'
on_main board/epics/gone.md '---\nstatus: active\n---\n\n# gone\n'
on_main board/hld/h-draft.md '---\nstatus: draft\ngrants: [epics]\n---\n'
on_main board/hld/h-ok.md '---\nstatus: agreed\ngrants: [epics]\n---\n'
on_main board/hld/h-merge.md '---\nstatus: agreed\ngrants: [merge]\n---\n'
on_main board/hld/h-move.md '---\nstatus: agreed\ngrants: [epics]\n---\n'
on_main board/hld/H.dot.md '---\nstatus: agreed\ngrants: [epics]\n---\n'
on_main board/hld/h-bad.md '---\nstatus: agreed\ngrants: [bogus]\n---\n'
# ren-*: files a case moves to epics/<name>2.md, with a body long enough that git pairs the move.
BODY='The epic body, which the move keeps as it was, so that git sees one file under two names.'
on_main board/epics/ren-act.md "---\nstatus: active\n---\n\n# ren-act\n\n${BODY}\n"
on_main board/epics/ren-stale.md "---\nstatus: draft\nagreed: ${TODAY}\n---\n\n# ren-stale\n\n${BODY}\n"
on_main board/stories/ren-story.md "---\nstatus: active\n---\n\n# ren-story\n\n${BODY}\n"
on_main board/epics/ren-del.md "---\nstatus: active\n---\n\n# ren-del\n\n${BODY}\n"
on_main board/epics/ren-ttl.md "---\nstatus: draft\nagreed: ${TODAY}\n---\n\n# ren-ttl\n\n${BODY}\n"
git -C "${P}" fetch -q origin

bpr start new; ep new epics/e-new.md '---\nstatus: active\n---\n\n# e-new\n'
guard_refused new "a new active epic with no ticket" "e-new ${NT} e-new"
ep new epics/e-new.md '---\nstatus: draft\n---\n\n# e-new\n'
git -C "${ROOT}/proj-wt/_board-new" add -A && git -C "${ROOT}/proj-wt/_board-new" commit -qm "e-new as a draft"
guard_opens new "after the refusal, the same epic committed as status: draft"
bpr start flip; ep flip epics/flip.md '---\nstatus: active\n---\n\n# flip\n'
guard_refused flip "a draft-to-active flip with no ticket" "flip ${NT} flip"
bpr start stale; ep stale epics/stale.md "---\nstatus: active\nagreed: ${TODAY}\n---\n\n# stale\n"
guard_refused stale "a draft's stale agreed: left as it was on the flip to active" "stale ${NT} stale"
bpr start body; ep body epics/e-body.md '---\ndepends_on: []\n---\n\n# e-body\nstatus: active\n'
guard_refused body "an epic active by a body status: line, as fm reads it" "e-body ${NT} e-body"
bpr start pbog; ep pbog epics/e-pbog.md '---\nstatus: active\nparent: bogus\n---\n'
guard_refused pbog "parent: an epic the base does not have" "e-pbog ${NT} e-pbog"
bpr start padd; ep padd epics/p-added.md '---\nstatus: draft\n---\n'; ep padd epics/e-padd.md '---\nstatus: active\nparent: p-added\n---\n'
guard_refused padd "parent: an epic the same PR adds" "e-padd ${NT} e-padd"
bpr start pdr; ep pdr epics/e-pdr.md '---\nstatus: active\nparent: pdraft\n---\n'
guard_refused pdr "parent: a draft epic on main" "e-pdr ${NT} e-pdr"
# parent: counts at the head too when the PR changes it: one PR cannot take the parent out of active
# (to a draft, or deleted) and add an active child.
bpr start pdem; ep pdem epics/pact.md '---\nstatus: draft\n---\n\n# pact\n'; ep pdem epics/e-pdem.md '---\nstatus: active\nparent: pact\n---\n'
guard_refused pdem "parent: an active epic the same PR sets back to a draft" "e-pdem ${NT} e-pdem"
bpr start pdel; rm "${ROOT}/proj-wt/_board-pdel/board/epics/pact.md"; ep pdel epics/e-pdel.md '---\nstatus: active\nparent: pact\n---\n'
guard_refused pdel "parent: an active epic the same PR deletes" "e-pdel ${NT} e-pdel"
bpr start nst; ep nst epics/nostat.md '---\nstatus: active\ndepends_on: []\n---\n\n# nostat\n'
guard_refused nst "an epic with no status: at the base, flipped to active" "nostat ${NT} nostat"
# selfp is on the base, so only the own-slug rule refuses it.
bpr start pself; ep pself epics/selfp.md '---\nstatus: active\nparent: selfp\n---\n\n# selfp\n'
guard_refused pself "parent: the epic's own slug" "selfp ${NT} selfp"
# open judges against origin/main as it is now: an HLD superseded there since the start does not count.
bpr start hmv; ep hmv epics/e-hmv.md '---\nstatus: active\nhld: h-move\n---\n'
on_main board/hld/h-move.md '---\nstatus: superseded\ngrants: [epics]\n---\n'
guard_refused hmv "hld: an HLD superseded on origin/main since the start" "e-hmv ${NT} e-hmv"
bpr start fch; ep fch epics/e-fch.md "---\nstatus: active\nagreed: ${TODAY}\n---\n"; touch "${ROOT}/fetch.fail"
guard_refused fch "a failed fetch of origin/main" "board-pr: cannot fetch origin's base branch"
rm "${ROOT}/fetch.fail"
bpr start hd; ep hd hld/h-draft.md '---\nstatus: agreed\ngrants: [epics]\n---\n'; ep hd epics/e-hd.md '---\nstatus: active\nhld: h-draft\n---\n'
guard_refused hd "hld: an HLD draft at the base, agreed in the worktree" "e-hd ${NT}"
bpr start hn; ep hn hld/h-new.md '---\nstatus: agreed\ngrants: [epics]\n---\n'; ep hn epics/e-hn.md '---\nstatus: active\nhld: h-new\n---\n'
guard_refused hn "hld: an HLD missing at the base, agreed in the worktree" "e-hn ${NT}"
bpr start hdel; rm "${ROOT}/proj-wt/_board-hdel/board/hld/h-ok.md"; ep hdel epics/e-hdel.md '---\nstatus: active\nhld: h-ok\n---\n'
guard_refused hdel "hld: an agreed HLD the worktree deletes" "e-hdel ${NT}"
bpr start hsup; ep hsup hld/h-ok.md '---\nstatus: superseded\ngrants: [epics]\n---\n'; ep hsup epics/e-hsup.md '---\nstatus: active\nhld: h-ok\n---\n'
guard_refused hsup "hld: an agreed HLD the worktree supersedes" "e-hsup ${NT}"
bpr start hnoe; ep hnoe hld/h-ok.md '---\nstatus: agreed\ngrants: [merge]\n---\n'; ep hnoe epics/e-hnoe.md '---\nstatus: active\nhld: h-ok\n---\n'
guard_refused hnoe "hld: an agreed HLD whose epics grant the worktree removes" "e-hnoe ${NT}"
bpr start hdr; ep hdr epics/e-hdr.md '---\nstatus: active\nhld: h-draft\n---\n'
guard_refused hdr "hld: a draft HLD" "e-hdr ${NT}"
bpr start hm; ep hm epics/e-hm.md '---\nstatus: active\nhld: h-merge\n---\n'
guard_refused hm "hld: an HLD whose grants lack epics" "e-hm ${NT}"
bpr start hb; ep hb epics/e-hb.md '---\nstatus: active\nhld: h-bad\n---\n'
guard_refused hb "hld: an HLD with a bad grant value" "board/hld/h-bad.md at the base, line 3: grants must be"
is "a bad grant value: the refusal names the HLD, not a temp path" \
  "swarm: board-pr: board/hld/h-bad.md at the base, line 3: grants must be epics, stories, merge or release" "$(cat "${ROOT}/err")"
bpr start unr; ep unr epics/e-unr.md '---\nstatus: active\n---\n'; chmod 000 "${ROOT}/proj-wt/_board-unr/board/epics/e-unr.md"
guard_refused unr "an unreadable epic in the worktree" "cannot read board/epics/e-unr.md at the head"
chmod 644 "${ROOT}/proj-wt/_board-unr/board/epics/e-unr.md"
# Only active at the base goes on with no ticket: later, split, review and done need one, as a draft does.
for st in later split review "done"; do
  bpr start "w${st}"; ep "w${st}" "epics/was-${st}.md" "---\nstatus: active\n---\n\n# was-${st}\n"
  guard_refused "w${st}" "${st} to active with no ticket" "was-${st} ${NT} was-${st}"
done
bpr start two1; ep two1 epics/a-ok.md "---\nstatus: active\nagreed: ${TODAY}\n---\n"; ep two1 epics/b-no.md '---\nstatus: active\n---\n'
guard_refused two1 "two active epics, the ticketed one first" "b-no ${NT} b-no"
check "the ticketed one first: the refusal does not name it" bash -c "! grep -qF a-ok '${ROOT}/err'"
bpr start two2; ep two2 epics/a-no.md '---\nstatus: active\n---\n'; ep two2 epics/b-ok.md '---\nstatus: active\nparent: old\n---\n'
guard_refused two2 "two active epics, the unticketed one first" "a-no ${NT} a-no"
check "the unticketed one first: the refusal does not name the ticketed one" bash -c "! grep -qF b-ok '${ROOT}/err'"

bpr start hok; ep hok epics/e-hok.md '---\nstatus: active\nhld: h-ok\n---\n'
guard_opens hok "hld: an HLD agreed with grants: [epics] at both ends"
bpr start fresh; ep fresh epics/fresh.md "---\nstatus: active\nagreed: ${TODAY}\n---\n\n# fresh\n"
guard_opens fresh "a draft flipped to active with a new agreed: date, today's"
# agreed: counts from today back AGREED_MAX_AGE (7) days: 6 days ago opens; 8 days ago, or tomorrow, is
# refused.
bpr start a6; ep a6 epics/e-a6.md "---\nstatus: active\nagreed: $(day 6)\n---\n"
guard_opens a6 "agreed: 6 days ago, a day inside AGREED_MAX_AGE"
bpr start a8; ep a8 epics/e-a8.md "---\nstatus: active\nagreed: $(day 8)\n---\n"
guard_refused a8 "agreed: 8 days ago, a day past AGREED_MAX_AGE" "e-a8 ${NT} e-a8"
bpr start anext; ep anext epics/e-anext.md "---\nstatus: active\nagreed: $(day -1)\n---\n"
guard_refused anext "agreed: tomorrow" "e-anext ${NT} e-anext"
bpr start hdot; ep hdot epics/e-hdot.md '---\nstatus: active\nhld: H.dot\n---\n'
guard_opens hdot "hld: an HLD name item_hld takes (capitals and a dot)"
bpr start pok; ep pok epics/pact.md '---\nstatus: active\n---\n\n# pact, edited\n'; ep pok epics/e-pok.md '---\nstatus: active\nparent: pact\n---\n'
guard_opens pok "parent: an epic active on main that the same PR edits and leaves active"
# A parent the PR leaves alone is read on origin/main only: this branch was cut while pstale was a
# draft, and main has set it active since.
bpr start pst; ep pst epics/e-pst.md '---\nstatus: active\nparent: pstale\n---\n'
on_main board/epics/pstale.md '---\nstatus: active\n---\n\n# pstale\n'
guard_opens pst "parent: a draft at the branch's start that origin/main has set active since"
# A later epic with no agreed:, parent: or hld: starts on the user's go: the lead writes agreed: <today>
# in the edit that sets it active, as /epic does.
bpr start later; ep later epics/was-later.md "---\nstatus: active\nagreed: $(date +%F)\n---\n\n# was-later\n"
guard_opens later "later to active with agreed: <today>"
bpr start act; ep act epics/act.md '---\nstatus: active\n---\n\n# act, edited\n'
guard_opens act "a body-only edit to an active epic"
bpr start gone; rm "${ROOT}/proj-wt/_board-gone/board/epics/gone.md"
guard_opens gone "a deleted epic"
# A renamed epic is judged by its base copy at the old path, moved with mv and left uncommitted or
# committed; an old path outside epics/ reads as new.
bpr start rna; mv "${ROOT}/proj-wt/_board-rna/board/epics/ren-act.md" "${ROOT}/proj-wt/_board-rna/board/epics/ren-act2.md"
guard_opens rna "an active epic renamed with mv, nothing else changed"
bpr start rns; git -C "${ROOT}/proj-wt/_board-rns" mv board/epics/ren-stale.md board/epics/ren-stale2.md
ep rns epics/ren-stale2.md "---\nstatus: active\nagreed: ${TODAY}\n---\n\n# ren-stale\n\n${BODY}\n"
git -C "${ROOT}/proj-wt/_board-rns" commit -qam "ren-stale renamed and active"
guard_refused rns "a draft renamed and set active, the agreed: its base copy had kept" "ren-stale2 ${NT} ren-stale2"
bpr start rnx; mv "${ROOT}/proj-wt/_board-rnx/board/stories/ren-story.md" "${ROOT}/proj-wt/_board-rnx/board/epics/ren-story.md"
guard_refused rnx "an active file moved into epics/ from outside it" "ren-story ${NT} ren-story"
# git pairs a deleted epic with a new one sharing its body as a rename too (by content, at half alike);
# with another heading the new one reads as new, so it needs a ticket.
bpr start rnu; rm "${ROOT}/proj-wt/_board-rnu/board/epics/ren-del.md"; ep rnu epics/ren-new.md "---\nstatus: active\n---\n\n# ren-new\n\n${BODY}\n"
guard_refused rnu "an active epic deleted and an unrelated active one added, alike enough to pair" "ren-new ${NT} ren-new"
# A rename that changes the heading too still compares the old copy's agreed:: a stale date under a
# new heading is no ticket (the second Done when, by another route).
bpr start rnt; git -C "${ROOT}/proj-wt/_board-rnt" mv board/epics/ren-ttl.md board/epics/ren-ttl2.md
ep rnt epics/ren-ttl2.md "---\nstatus: active\nagreed: ${TODAY}\n---\n\n# ren-ttl, retitled\n\n${BODY}\n"
git -C "${ROOT}/proj-wt/_board-rnt" commit -qam "ren-ttl renamed, retitled and active"
guard_refused rnt "a draft renamed with another heading and set active, the agreed: its base copy had kept" "ren-ttl2 ${NT} ren-ttl2"
# A file staged past .gitignore (git add -f) is one open's git add -A commits, so the change list
# holds it: outside the board, it is refused as such.
bpr start fadd; echo fadd > "${ROOT}/proj-wt/_board-fadd/board/stories/a.md"
mkdir -p "${ROOT}/proj-wt/_board-fadd/.swarm"; echo x > "${ROOT}/proj-wt/_board-fadd/.swarm/x"; git -C "${ROOT}/proj-wt/_board-fadd" add -f .swarm/x
guard_refused fadd "a file staged past .gitignore outside the board, beside a board edit" "board-pr: .swarm/x is outside board/"
printf 'board_dir = board\nlead_epics = on\n' > "${P}/.claude/swarm/config"
bpr start lead; ep lead epics/e-lead.md '---\nstatus: active\n---\n'
guard_opens lead "lead_epics = on, with no ticket"
printf 'board_dir = board\n' > "${P}/.claude/swarm/config"

# --- board_dir = .: the board is its own paths at the root (board_paths), as merge --board has it, so
# open takes a story and refuses any other file.
printf 'board_dir = .\n' > "${P}/.claude/swarm/config"
bpr start y; mkdir -p "${ROOT}/proj-wt/_board-y/stories"; echo changed > "${ROOT}/proj-wt/_board-y/stories/root-y.md"
reset_log; bpr open y "Root board edit" "${ROOT}/body.md"
is "board_dir = .: open exits 0" 0 "${rc}"
is "board_dir = .: open prints the PR URL" "${URL}" "$(cat "${ROOT}/out")"
bpr start yb; echo changed > "${ROOT}/proj-wt/_board-yb/bin/tool"
guard_refused yb "board_dir = .: a file off the board's paths" "board-pr: bin/tool is outside the board's paths (stories/, epics/, hld/, Board.base, .obsidian/)"
# git C-quotes a path with a " in it ("epics/a\"b.md"), which would miss the epics/ prefix: refused.
bpr start q; mkdir -p "${ROOT}/proj-wt/_board-q/epics"; printf -- '---\nstatus: active\n---\n' > "${ROOT}/proj-wt/_board-q/epics/a\"b.md"
guard_refused q "board_dir = .: an active epic whose name holds a quote" 'board-pr: "epics/a\"b.md" has a quote, backslash, tab or newline in its name; rename it'

# Why: an org that requires every commit and merge GPG-signed sets sign_commits = true.
# Boards outside swarm-dev and infrafactory set this key, so checking those two configs is not
# enough to remove it.
# --- sign_commits = true: open's commit passes -S. git signs with a throwaway SSH key here, and
# commit.gpgsign is off, so only -S can sign it; with sign_commits off the same commit is unsigned.
ssh-keygen -q -t ed25519 -N '' -C board-pr-test -f "${ROOT}/signkey"
signed() { git -C "$1" cat-file commit HEAD | grep -q '^gpgsig '; }
# sign_open <name> — start <name>, change a board file and open it, with signing set up for git.
sign_open() {
  rm -f "${ROOT}/prs"; bpr start "$1"; echo "$1" > "${ROOT}/proj-wt/_board-$1/board/stories/a.md"
  reset_log
  GIT_CONFIG_COUNT=3 GIT_CONFIG_KEY_0=gpg.format GIT_CONFIG_VALUE_0=ssh GIT_CONFIG_KEY_1=user.signingkey \
    GIT_CONFIG_VALUE_1="${ROOT}/signkey" GIT_CONFIG_KEY_2=commit.gpgsign GIT_CONFIG_VALUE_2=false bpr open "$1" "Signed edit" "${ROOT}/body.md"
}
printf 'board_dir = board\nsign_commits = true\n' > "${P}/.claude/swarm/config"
sign_open sig
is "sign_commits = true: open exits 0" 0 "${rc}"
check "sign_commits = true: open's commit is signed" signed "${ROOT}/proj-wt/_board-sig"
printf 'board_dir = board\n' > "${P}/.claude/swarm/config"
sign_open unsig
is "sign_commits off: open exits 0" 0 "${rc}"
check "sign_commits off: open's commit is not signed" bash -c "! git -C '${ROOT}/proj-wt/_board-unsig' cat-file commit HEAD | grep -q '^gpgsig '"

# --- The docs send the lead's board edits through it.
check "method.md § Who does what names swarm.sh board-pr" \
  bash -c "sed -n '/^## Who does what/,/^## /p' '${REPO}/docs/method.md' | grep -q 'swarm.sh board-pr'"
check "commands/swarm.md names swarm.sh board-pr" grep -q 'swarm.sh board-pr' "${REPO}/commands/swarm.md"

echo
if [[ ${fails} -eq 0 ]]; then echo "all board-pr tests passed"; else echo "${fails} board-pr test(s) failed"; exit 1; fi
