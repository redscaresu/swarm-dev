#!/usr/bin/env bash
# pr_removes_story_test.sh — a builder's PR takes its story off an in-repo board, and the epic with its
# last story; finish and drop on an in-repo board delete through a board PR and leave the main checkout
# alone, and finish <hld> only once the HLD is planned and no epic names it; on an external board
# finish deletes in place; the conductor's brief and /swarm send story
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
item "${B}/stories/f2.md" "status: ready" "epic: f" "kind: lead" "after: f"
item "${B}/epics/h.md" "status: active"
item "${B}/stories/h1.md" "status: ready" "epic: h"
item "${B}/stories/h2.md" "status: ready" "epic: h" "after: h"
echo "kind: lead" >> "${B}/stories/h2.md" # in the body, not the front matter: h2 is still a code story
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
cleanup() { sw "$1" _brief "$2"; grep -oE 'Delete .* under [^ ]*/( or [^ ]*/)?\.|Do not touch [^.]*\.' <<< "${out}" | head -1; }

# A board at the default board_dir = docs, beside the project's own docs.
D="${ROOT}/dproj"
mkdir -p "${D}/.claude/swarm"; printf 'board_dir = docs\n' > "${D}/.claude/swarm/config"
item "${D}/docs/epics/k.md" "status: active"
item "${D}/docs/stories/k1.md" "status: ready" "epic: k" "kind: docs"
git -C "${D}" init -q -b main && git -C "${D}" add -A && git -C "${D}" commit -qm init

# --- The builder's brief.
is "a one-off's brief deletes only its story" \
  "Delete board/stories/one.md in your PR, and nothing else under board/stories/." "$(cleanup "${P}" one)"
is "an epic story's brief, with another open story, leaves the epic" \
  "Delete board/stories/e1.md in your PR, and nothing else under board/stories/." "$(cleanup "${P}" e1)"
is "an epic story's brief, with only an after: lead story left, deletes the epic too" \
  "Delete board/stories/f1.md and board/epics/f.md (its epic's last story) in your PR, and nothing else under board/stories/ or board/epics/." "$(cleanup "${P}" f1)"
is "an epic story's brief, with an after: code story left, leaves the epic" \
  "Delete board/stories/h1.md in your PR, and nothing else under board/stories/." "$(cleanup "${P}" h1)"
rm "${B}/stories/e2.md"
is "an epic story's brief, with no other story, deletes the epic too" \
  "Delete board/stories/e1.md and board/epics/e.md (its epic's last story) in your PR, and nothing else under board/stories/ or board/epics/." "$(cleanup "${P}" e1)"
git -C "${P}" checkout -q -- board
is "with board_dir = docs, an epic's last story may still change the rest of docs/" \
  "Delete docs/stories/k1.md and docs/epics/k.md (its epic's last story) in your PR, and nothing else under docs/stories/ or docs/epics/." "$(cleanup "${D}" k1)"
is "an external-board story's brief deletes nothing" "Do not touch the story file; the lead takes it off the board after your PR merges." \
  "$(cleanup "${X}" g1)"
# fix_main writes its story into the main checkout, untracked, so the builder's worktree has no copy.
item "${B}/stories/fix-main-aaaaaaa.md" "status: ready" "kind: code"
is "an untracked story's brief deletes nothing" "Do not touch the story file; the lead takes it off the board after your PR merges." \
  "$(cleanup "${P}" fix-main-aaaaaaa)"
sw "${P}" _brief fix-main-aaaaaaa
is "an untracked story's brief names it by its full path" yes "$(has "Implement ${B}/stories/fix-main-aaaaaaa.md (this worktree is" "${out}")"
rm "${B}/stories/fix-main-aaaaaaa.md"

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
is "drop: the board PR deletes the story, on board/drop-esc" "D	board/stories/esc.md" "$(git -C "${ROOT}/origin.git" diff --name-status main board/drop-esc)"
is "drop: the PR is titled with the verb and the reason" yes "$(has "--head board/drop-esc --title Drop esc: no longer needed --body-file" "$(cat "${ROOT}/gh.log")")"
is "drop: prints the merge --board line" yes "$(has "land it: swarm.sh merge --board ${URL}" "${out}")"

# --- A story that is not on origin/main (an unmerged board PR adds it): refused with the reason, and
# the worktree and branch the run started are gone, so a second run fails the same way.
item "${B}/stories/fresh.md" "status: review"
for run in first second; do
  sw "${P}" finish fresh
  is "finish of a story not on origin/main, ${run} run: refused with the reason" "1 yes" \
    "${rc} $(has "board/stories/fresh.md is not on origin/main (is it in a board PR that has not merged?)" "${out}")"
  is "finish of a story not on origin/main, ${run} run: no worktree or branch left" "no no no" \
    "$([[ -e "${ROOT}/proj-wt/_board-finish-fresh" ]] && echo yes || echo no) $(git -C "${P}" show-ref -q --verify refs/heads/board/finish-fresh && echo yes || echo no) $(git -C "${ROOT}/origin.git" show-ref -q --verify refs/heads/board/finish-fresh && echo yes || echo no)"
done
rm "${B}/stories/fresh.md"

# --- finish <hld>: a planned HLD with no epic left goes in a board PR; anything else is refused
# before any branch or worktree is left.
left() { echo "$([[ -e "${ROOT}/proj-wt/_board-finish-$1" ]] && echo yes || echo no) $(git -C "${P}" show-ref -q --verify "refs/heads/board/finish-$1" && echo yes || echo no) $(git -C "${ROOT}/origin.git" show-ref -q --verify "refs/heads/board/finish-$1" && echo yes || echo no)"; }
item "${B}/hld/hd.md" "status: agreed" "planned: 2026-10-24"
item "${B}/epics/hde.md" "status: active" "hld: hd"
item "${B}/hld/hu.md" "status: agreed"
item "${B}/hld/hdr.md" "status: draft"
item "${B}/hld/ho.md" "status: agreed" "planned: 2026-10-24"
item "${B}/hld/hf.md" "status: agreed" "planned: 2026-10-24"
item "${B}/hld/hp.md" "status: agreed" "planned: 2026-10-24"
git -C "${P}" add -A && git -C "${P}" commit -qm hlds && git -C "${P}" push -q origin main
sw "${P}" finish hd
is "finish of an HLD an epic names: refused naming the epic" "1 yes" "${rc} $(has "still has epics on the board: hde" "${out}")"
is "finish of an HLD an epic names: no worktree or branch left" "no no no" "$(left hd)"
sw "${P}" finish hu
is "finish of an agreed HLD with no planned:: refused" "1 yes" "${rc} $(has "the HLD hu has no planned:" "${out}")"
is "finish of an agreed HLD with no planned:: no worktree or branch left" "no no no" "$(left hu)"
sw "${P}" finish hdr
is "finish of a draft HLD: refused" "1 yes" "${rc} $(has "the HLD hdr is a draft" "${out}")"
is "finish of a draft HLD: no worktree or branch left" "no no no" "$(left hdr)"
# On origin, not pulled into the main checkout: an epic under ho, and hp without its planned:. A
# finish-ho worktree started by hand before they merged is stale, so the check reads origin itself.
sw "${P}" board-pr start finish-ho
git clone -q "${ROOT}/origin.git" "${ROOT}/other"
item "${ROOT}/other/board/epics/hoe.md" "status: active" "hld: ho"
item "${ROOT}/other/board/hld/hp.md" "status: agreed"
git -C "${ROOT}/other" add -A && git -C "${ROOT}/other" commit -qm hoe && git -C "${ROOT}/other" push -q origin main
git -C "${P}" fetch -q origin
sw "${P}" finish ho
is "finish of an HLD an epic on origin names, in a stale board worktree started by hand: refused, the worktree kept" "1 yes yes" \
  "${rc} $(has "on origin/main, the HLD ho still has epics on the board: hoe" "${out}") $([[ -e "${ROOT}/proj-wt/_board-finish-ho" ]] && echo yes || echo no)"
sw "${P}" board-pr "done" finish-ho
sw "${P}" finish ho
is "finish of an HLD an epic on origin names: refused naming the epic" "1 yes" "${rc} $(has "on origin/main, the HLD ho still has epics on the board: hoe" "${out}")"
is "finish of an HLD an epic on origin names: no worktree or branch left" "no no no" "$(left ho)"
sw "${P}" finish hp
is "finish of an HLD with no planned: on origin: refused" "1 yes" "${rc} $(has "on origin/main, the HLD hp has no planned:" "${out}")"
is "finish of an HLD with no planned: on origin: no worktree or branch left" "no no no" "$(left hp)"
: > "${ROOT}/gh.log"
sw "${P}" finish hf
is "finish of a planned HLD with no epic: exits 0" 0 "${rc}"
is "finish of a planned HLD with no epic: opens one board PR titled Finish hf" "1 yes" \
  "$(grep -c '^pr create' "${ROOT}/gh.log") $(has "--head board/finish-hf --title Finish hf --body-file" "$(cat "${ROOT}/gh.log")")"
is "finish of a planned HLD with no epic: the board PR deletes the HLD" "D	board/hld/hf.md" \
  "$(git -C "${ROOT}/origin.git" diff --name-status main board/finish-hf)"
is "finish of a planned HLD with no epic: the main checkout is clean" "" "$(git -C "${P}" status --porcelain)"
# A board with no epics/ in git at all (its last epic went, and no README kept the directory).
Q="${ROOT}/qproj"
mkdir -p "${Q}/.claude/swarm"; printf 'board_dir = board\n' > "${Q}/.claude/swarm/config"
item "${Q}/board/hld/q.md" "status: agreed" "planned: 2026-10-24"
git init -q --bare "${ROOT}/qorigin.git"; git -C "${ROOT}/qorigin.git" symbolic-ref HEAD refs/heads/main
git -C "${Q}" init -q -b main && git -C "${Q}" add -A && git -C "${Q}" commit -qm init
git -C "${Q}" remote add origin "${ROOT}/qorigin.git" && git -C "${Q}" push -q -u origin main
sw "${Q}" finish q
is "finish of a planned HLD on a board with no epics/: deletes it in a board PR" "0 D	board/hld/q.md" \
  "${rc} $(git -C "${ROOT}/qorigin.git" diff --name-status main board/finish-q)"

# --- finish on the external board deletes the file where it is.
sw "${X}" finish g1
is "finish on an external board: exits 0" 0 "${rc}"
is "finish on an external board: deletes the file" no "$([[ -f "${XB}/stories/g1.md" ]] && echo yes || echo no)"
item "${XB}/hld/gh.md" "status: agreed" "planned: 2026-10-24"
sw "${X}" finish gh
is "finish of an HLD on an external board: deletes it in place" "0 no" "${rc} $([[ -f "${XB}/hld/gh.md" ]] && echo yes || echo no)"

# --- Story edits go through board-pr.
# shellcheck disable=SC2016 # the backticks are the brief's, escaped in its heredoc
is "conduct_brief names board-pr for a story edit" yes \
  "$(has '(\`swarm.sh board-pr\`), as the lead does, never in the main checkout.' "$(awk '/^conduct_brief\(\)/,/^}/' "${REPO}/bin/lib/build.sh")")"
# shellcheck disable=SC2016 # the backticks are the brief's, escaped in its heredoc
is "the conductor's epic end: the epic leaves with its last story's PR on an in-repo board" "yes|yes" \
  "$(has "the epic leaves the board with its last story's PR, whose brief deletes the epic file. Run" "$(cat "${REPO}/bin/lib/build.sh")")|$(has '\`swarm.sh finish <epic>\` only on a board outside the repo, or when the epic file is still there after' "$(cat "${REPO}/bin/lib/build.sh")")"
is "the conductor's board PR: the user lands it with merge = human, and its story waits for the merge" "yes|yes" \
  "$(has "With merge = human you cannot land that PR: list it in your report for the user." "$(cat "${REPO}/bin/lib/build.sh")")|$(has "start again, a story whose edit is still in a board PR." "$(cat "${REPO}/bin/lib/build.sh")")"
# shellcheck disable=SC2016 # literal backticks
is "commands/swarm.md's drop arm stops until the board PR merges, and hands it to the user with merge = human" "yes|yes" \
  "$(has '`swarm.sh merge --board` line it prints. With `merge = human` you never merge: hand the PR' "$(cat "${REPO}/commands/swarm.md")")|$(has "user's merge, so name the board PR, show what \`swarm.sh status\` lists under Waiting on" "$(cat "${REPO}/commands/swarm.md")")"
is "commands/swarm.md names board-pr for a conductor's story edit" yes \
  "$(has "edit to a story goes through \`swarm.sh board-pr\` too (its brief says so)." "$(cat "${REPO}/commands/swarm.md")")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
