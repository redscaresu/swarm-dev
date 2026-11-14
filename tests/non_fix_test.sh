#!/usr/bin/env bash
# non_fix_test.sh — non_fix_change (bin/lib/board.sh), the one definition of a fix, on a git fixture
# tagged v1.2.0 with a stub gh that lists its merged PRs. A change is a fix only when its PR's head is
# story/fix-main-<sha7> or story/<slug> whose story file has fix: true in its front matter at the
# commit's first parent; every other change prints one line. Board-only commits are no change. It
# reads git at the commits only, never the checkout or the board's state, exits 1 when it cannot answer,
# and caches an answer only once git and gh both answered and every commit had a PR, under the rule,
# the board's path and both SHAs.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWARM="${REPO}/bin/swarm.sh"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
ROOT="$(cd "${ROOT}" && pwd -P)"
# Under its own root, so parallel runs share no ~ and no ~/.claude.
export HOME="${ROOT}/home" CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
mkdir -p "${HOME}"
fails=0

# git reads no config but the fixture's own: no signing, no hooks, a fixed name and date, so a commit
# needs nothing from the machine.
printf '[user]\n\tname = t\n\temail = t@t\n[commit]\n\tgpgsign = false\n[tag]\n\tgpgsign = false\n[init]\n\tdefaultBranch = main\n' > "${ROOT}/gitconfig"
export GIT_CONFIG_GLOBAL="${ROOT}/gitconfig" GIT_CONFIG_NOSYSTEM=1
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
NL=$'\n'
# tick — the next commit's date, a second after the last (from 2026-01-15T10:00:00Z, UTC), so every
# commit has its own.
T=0
tick() { T=$((T + 1)); export GIT_AUTHOR_DATE GIT_COMMITTER_DATE; GIT_COMMITTER_DATE="2026-01-15T10:00:$(printf %02d "${T}")Z"; GIT_AUTHOR_DATE="${GIT_COMMITTER_DATE}"; }

# The stub gh logs each call to gh.log, fails while gh.fail is there, and prints prs.json. The git
# wrapper logs each call to git.log and runs the real git.
mkdir -p "${ROOT}/bin"
printf '#!/bin/sh\necho "$*" >> "%s/gh.log"\n[ ! -f "%s/gh.fail" ] || exit 1\ncat "%s/prs.json"\n' "${ROOT}" "${ROOT}" "${ROOT}" > "${ROOT}/bin/gh"
printf '#!/bin/sh\necho "$*" >> "%s/git.log"\nexec "%s" "$@"\n' "${ROOT}" "$(command -v git)" > "${ROOT}/bin/git"
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/git"

# nf.sh <board> <owner/repo> <from> <ref> — non_fix_change in the project in the cwd, board.sh loaded
# under set -euo pipefail as swarm.sh loads it, with swarm.sh's own lines for PROJECT_IS_GIT,
# BOARD_IN_REPO and board_rel, and BOARD as swarm.sh config board_dir resolves it.
cat > "${ROOT}/nf.sh" <<'NF'
set -euo pipefail
PROJECT_DIR="$(pwd -P)"; SWARM_HOME="${NF_HOME}"; BOARD="$1"; shift
die() { echo "swarm: $*" >&2; exit 1; }
# The BOARD_IN_REPO line ends on a test that fails for a board outside the repo, so eval's status is no error.
eval "$(sed -n -e '/^board_rel() /p' -e '/^PROJECT_IS_GIT=0;/p' -e '/^BOARD_IN_REPO=0;/p' "${SWARM_HOME}/bin/swarm.sh")" || true
declare -F board_rel > /dev/null && [[ -n "${PROJECT_IS_GIT:-}" && -n "${BOARD_IN_REPO:-}" ]] \
  || { echo "nf.sh: swarm.sh's board_rel, PROJECT_IS_GIT or BOARD_IN_REPO line did not load" >&2; exit 3; }
# shellcheck source=/dev/null
. "${SWARM_HOME}/bin/lib/reports.sh"
# shellcheck source=/dev/null
. "${SWARM_HOME}/bin/lib/board.sh"
# shellcheck source=/dev/null
. "${SWARM_HOME}/bin/lib/merge.sh"
non_fix_change "$@"
NF

P="${ROOT}/proj"
mkdir -p "${P}/.claude/swarm" "${P}/docs/stories" "${P}/board/stories" "${P}/bin"
git -C "${P}" init -q
printf '.claude/\n.swarm/\n' > "${P}/.git/info/exclude"
: > "${P}/.claude/swarm/config"

# board_dir <value> — set the fixture's board_dir; BOARD is then what swarm.sh config board_dir prints.
board_dir() {
  printf 'board_dir = %s\n' "$1" > "${P}/.claude/swarm/config"
  BOARD="$(cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${SWARM}" config board_dir)"
}
# nf <from> <ref> [VAR=value...] — non_fix_change o/r <from> <ref> on the fixture: its stdout in OUT,
# stderr in ERR, exit code in CODE; gh and git calls logged to gh.log and git.log.
nf() {
  local from="$1" ref="$2"; shift 2
  rm -f "${ROOT}/gh.log" "${ROOT}/git.log"; CODE=0
  OUT="$(cd "${P}" && env "$@" NF_HOME="${REPO}" PATH="${ROOT}/bin:${PATH}" bash "${ROOT}/nf.sh" "${BOARD}" o/r "${from}" "${ref}" 2> "${ROOT}/err")" || CODE=$?
  ERR="$(cat "${ROOT}/err")"
}
check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"
  else printf 'FAIL %s\n  want: %s\n  got:  %s\n' "$1" "${2//${NL}/${NL}        }" "${3//${NL}/${NL}        }"; fails=$((fails + 1)); fi
}
has() { grep -qxF -- "$2" <<< "$1"; }   # <text> <line> — <text> holds <line>, whole
cached_files() { find "${P}/.swarm/gh-cache" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }

# story <slug> <front matter line>... [-- <body line>...] — write docs/stories/<slug>.md.
story() {
  local f="${P}/docs/stories/$1.md"; shift
  { echo ---; while [[ $# -gt 0 && "$1" != -- ]]; do echo "$1"; shift; done; echo ---; echo; echo "# A story"
    [[ $# -eq 0 ]] || { shift; printf '%s\n' "$@"; }; } > "${f}"
}
# commit <message> — commit the fixture's tree; the commit's SHA in SHA.
commit() { tick && git -C "${P}" add -A && git -C "${P}" commit -q -m "$1" && SHA="$(git -C "${P}" rev-parse HEAD)"; }
# pr <number> <head> <sha> — gh lists PR <number> from <head>, merged as <sha>.
PRS=""
pr() { PRS+="$1 $2 $3${NL}"; }
write_prs() {
  python3 -I -c '
import json, sys
prs = [{"number": int(n), "headRefName": h, "mergeCommit": {"oid": s}} for n, h, s in (l.split() for l in sys.stdin if l.strip())]
prs.append({"number": 99, "headRefName": "story/s2", "mergeCommit": None})   # a merged PR gh gives no commit for
json.dump(prs, sys.stdout)' <<< "${PRS}" > "${ROOT}/prs.json"
}

# Before the tag: the story old, no fix: line, built and kept on the board at done.
echo "# Stories" > "${P}/docs/stories/README.md"; echo "# Stories" > "${P}/board/stories/README.md"; echo a > "${P}/bin/a"
story old 'status: ready' 'kind: code'
commit init
echo old > "${P}/bin/old"; story old 'status: done' 'kind: code'
commit "story old"; OLD="${SHA}"; pr 1 story/old "${OLD}"
git -C "${P}" tag v1.2.0
# The planner's board PR: a board-only commit, with a PR from no story branch, so it would print if read.
story s1 'status: ready' 'kind: code' 'fix: true  # a fix'
story s2 'status: ready' 'kind: code'
story s3 'status: ready' 'kind: code' 'fix: yes'
story s4 'status: ready' 'kind: code' 'fix: true'
story s5 'status: ready' 'kind: code'
story s6 'status: ready' 'kind: code' -- 'fix: true'
story s7 'status: ready' 'kind: code'
commit "plan"; PLAN="${SHA}"; pr 2 board/plan "${PLAN}"
echo 1 > "${P}/bin/s1"; commit "s1"; C1="${SHA}"; pr 3 story/s1 "${C1}"
echo 2 > "${P}/bin/s2"; commit "s2"; C2="${SHA}"; pr 4 story/s2 "${C2}"
echo 3 > "${P}/bin/s3"; commit "s3"; C3="${SHA}"; pr 5 story/s3 "${C3}"
echo x > "${P}/bin/x"; commit "hand fix"; C4="${SHA}"; pr 6 fix/x "${C4}"
echo np > "${P}/bin/np"; commit "direct push"; NOPR="${SHA}"
echo fm > "${P}/bin/fm"; commit "fix main"; FM="${SHA}"; pr 7 story/fix-main-abc1234 "${FM}"
rm "${P}/docs/stories/s4.md"; echo 4 > "${P}/bin/s4"; commit "s4"; C7="${SHA}"; pr 8 story/s4 "${C7}"
echo d > "${P}/bin/fmd"; commit "decoy"; DECOY="${SHA}"; pr 9 story/fix-main-docs "${DECOY}"
story s5 'status: ready' 'kind: code' 'fix: true'; echo 5 > "${P}/bin/s5"; commit "s5"; OWN="${SHA}"; pr 10 story/s5 "${OWN}"
echo 6 > "${P}/bin/s6"; commit "s6"; BODY="${SHA}"; pr 11 story/s6 "${BODY}"
git -C "${P}" checkout -q -b story/s7; echo 7 > "${P}/bin/s7"; commit "s7"; SIDE="${SHA}"
git -C "${P}" checkout -q main; tick; git -C "${P}" merge -q --no-ff story/s7 -m "Merge story/s7"
NOFF="$(git -C "${P}" rev-parse HEAD)"; pr 12 story/s7 "${NOFF}"
write_prs

L_S2="${C2:0:7} #4 story/s2: docs/stories/s2.md had no fix: true before the merge"
L_S3="${C3:0:7} #5 story/s3: docs/stories/s3.md had fix: yes before the merge, not true"
L_X="${C4:0:7} #6 fix/x: not a story or fix-main branch"
L_NOPR="${NOPR:0:7}: no merged PR has this commit"
L_DECOY="${DECOY:0:7} #9 story/fix-main-docs: no docs/stories/fix-main-docs.md before the merge"
L_OWN="${OWN:0:7} #10 story/s5: docs/stories/s5.md had no fix: true before the merge"
L_BODY="${BODY:0:7} #11 story/s6: docs/stories/s6.md had no fix: true before the merge"
L_NOFF="${NOFF:0:7} #12 story/s7: docs/stories/s7.md had no fix: true before the merge"
AFTER_S2="${L_S3}${NL}${L_X}${NL}${L_NOPR}${NL}${L_DECOY}${NL}${L_OWN}${NL}${L_BODY}${NL}${L_NOFF}"
ALL="${L_S2}${NL}${AFTER_S2}"

# --- v1.2.0..HEAD, the board in docs/.
board_dir docs
nf v1.2.0 HEAD
check "every non-fix change since the tag prints one line, oldest first, and it exits 0" "0|${ALL}" "${CODE}|${OUT}"
for c in "s2 (no fix: line)|${L_S2}" "s3 (fix: yes)|${L_S3}" "fix/x (no story branch)|${L_X}" "the commit no PR lists|${L_NOPR}"; do
  check "a commit from ${c%%|*} prints with its sha7" yes "$(has "${OUT}" "${c#*|}" && echo yes || echo no)"
done
check "a commit from story/s1, whose s1 has fix: true, is not printed" no "$(grep -qF "${C1:0:7}" <<< "${OUT}" && echo yes || echo no)"
check "a commit from story/fix-main-abc1234, which has no story file, is not printed" no "$(grep -qF "${FM:0:7}" <<< "${OUT}" && echo yes || echo no)"
check "the board-only commit, whose PR is from board/plan, is not read" no "$(grep -qF "${PLAN:0:7}" <<< "${OUT}" && echo yes || echo no)"
check "a story PR that deleted its own fix: true file is read at the commit's parent: not printed" no "$(grep -qF "${C7:0:7}" <<< "${OUT}" && echo yes || echo no)"
check "a story/fix-main-docs decoy branch is printed as a non-fix" yes "$(has "${OUT}" "${L_DECOY}" && echo yes || echo no)"
check "a PR that adds fix: true to its own story file is printed as a non-fix" yes "$(has "${OUT}" "${L_OWN}" && echo yes || echo no)"
check "fix: true only in a story's body is printed as a non-fix" yes "$(has "${OUT}" "${L_BODY}" && echo yes || echo no)"
check "a --no-ff merge commit from a non-fix story is printed" yes "$(has "${OUT}" "${L_NOFF}" && echo yes || echo no)"
check "the --no-ff merge's own side commit is not a change of its own" no "$(grep -qF "${SIDE:0:7}" <<< "${OUT}" && echo yes || echo no)"
check "one gh pr list of the PRs merged from the day before the tag's commit date" \
  "pr list --repo o/r --state merged --search merged:>=2026-01-14 --json number,headRefName,mergeCommit --limit 1000" "$(cat "${ROOT}/gh.log")"
check "no git log call" 0 "$(grep -cE '(^| )log( |$)' "${ROOT}/git.log" || true)"
# The walk itself: today's git gives a first-parent walk's merges the same answer with or without
# --full-history, so only the call shows the flag that keeps a merge TREESAME to its second parent on
# a git that compares later parents too.
check "the commits are one rev-list: first-parent, full history, the board's folder excluded" \
  "-C ${P} rev-list --reverse --first-parent --full-history ${OLD}..${NOFF} -- . :(exclude)docs/" "$(grep -F ' rev-list ' "${ROOT}/git.log")"
check "an answer with a no-PR line is not cached" 0 "$(cached_files)"

# A non-fix story merged before the tag, still on the board at done, plus a fix: true story after it.
nf v1.2.0 "${C1}"
check "old (before the tag, at done on the board) and s1 (fix: true): prints nothing" "0|" "${CODE}|${OUT}"
check "an answer whose every change is a fix is cached" 1 "$(cached_files)"

# The checkout and the board's state are never read: fix: true on s2 in the checkout, and s2 done in
# the board's state, change nothing. SWARM_GH_FRESH, so no cached answer could hide a read.
cp "${P}/docs/stories/s2.md" "${ROOT}/s2.md"
story s2 'status: done' 'kind: code' 'fix: true'
mkdir -p "${P}/.swarm/board-state/stories"; printf 'status: done\n' > "${P}/.swarm/board-state/stories/s2"
nf v1.2.0 HEAD SWARM_GH_FRESH=1
check "fix: true on s2 in the checkout, and s2 done in the board's state, change nothing" "0|${ALL}" "${CODE}|${OUT}"
cp "${ROOT}/s2.md" "${P}/docs/stories/s2.md"; rm -r "${P}/.swarm/board-state"

# <from> after s2's commit: s2 is out of the window, though the local tag still points before it.
nf "${C2}" HEAD SWARM_GH_FRESH=1
check "with <from> after s2's commit (the tag still at ${OLD:0:7}), s2 is not printed" \
  "0|${AFTER_S2}|${OLD}" "${CODE}|${OUT}|$(git -C "${P}" rev-parse 'v1.2.0^{commit}')"

# --- What it cannot answer exits 1, saying why.
nf v1.2.0 no-such-ref
check "an invalid <ref> exits 1, naming it" "1||non_fix_change: git cannot read the commit 'no-such-ref'" "${CODE}|${OUT}|${ERR}"
nf no-such-tag HEAD
check "an invalid <from> exits 1, naming it" "1||non_fix_change: git cannot read the commit 'no-such-tag'" "${CODE}|${OUT}|${ERR}"
: > "${ROOT}/gh.fail"
nf v1.2.0 HEAD
check "a failing gh exits 1" "1||non_fix_change: gh pr list --repo o/r --state merged failed" "${CODE}|${OUT}|${ERR}"
rm "${ROOT}/gh.fail"
mkdir -p "${ROOT}/outside/stories"; board_dir "${ROOT}/outside"
nf v1.2.0 HEAD
check "a board outside the repo exits 1, with no gh call" "1||non_fix_change: the board is outside the repo, so git holds no story history to read|no gh" \
  "${CODE}|${OUT}|${ERR}|$([[ -e "${ROOT}/gh.log" ]] && echo "gh ran" || echo "no gh")"

# --- The cache: v1.2.0..C4 has a PR for every commit. The cache starts empty (v1.2.0..C1's answer,
# above, was cached).
board_dir docs
rm -r "${P}/.swarm/gh-cache"
WIN="${L_S2}${NL}${L_S3}${NL}${L_X}"
: > "${ROOT}/gh.fail"
nf v1.2.0 "${C4}"
check "a run whose gh call fails first exits 1 and leaves no cache file" "1|0" "${CODE}|$(cached_files)"
rm "${ROOT}/gh.fail"
nf v1.2.0 "${C4}"
check "the next run gives the real answer, and caches it" "0|${WIN}|1" "${CODE}|${OUT}|$(cached_files)"
check "the cache file is named for the rule, the board's path and both SHAs" \
  "${P}/.swarm/gh-cache/o--r/non-fix/rule1-docs%2F-${OLD}-${C4}.json" "$(find "${P}/.swarm/gh-cache" -name '*.json')"
: > "${ROOT}/gh.fail"
nf v1.2.0 "${C4}"
check "a second run on the same SHAs with gh failing prints the first run's answer from the cache" "0|${WIN}|no gh" \
  "${CODE}|${OUT}|$([[ -e "${ROOT}/gh.log" ]] && echo "gh ran" || echo "no gh")"
nf "$(git -C "${P}" rev-parse v1.2.0)" "${C4}"
check "the cache is keyed by the SHAs: the tag's SHA reads the tag's answer" "0|${WIN}" "${CODE}|${OUT}"
nf v1.2.0 "${C4}" SWARM_GH_FRESH=1
check "with SWARM_GH_FRESH=1 the cache is not read, and gh failing exits 1" 1 "${CODE}"
board_dir ./docs/../docs
nf v1.2.0 "${C4}"
check "board_dir ./docs/../docs is docs/, normalized: the cached answer is read" "0|${WIN}" "${CODE}|${OUT}"
rm "${ROOT}/gh.fail"
nf v1.2.0 HEAD
: > "${ROOT}/gh.fail"
nf v1.2.0 HEAD
check "an answer with a no-PR line (gh's search can lag) is never read from the cache" 1 "${CODE}"
rm "${ROOT}/gh.fail"

# Changing board_dir with both commits fixed reads afresh: under board/, the plan commit is a change
# (docs/ is no board now), and s1's story is read at board/stories/s1.md, which is not there.
board_dir board
nf v1.2.0 "${C4}"
check "changing board_dir with both commits fixed does not reuse the earlier cached answer" \
  "0|${PLAN:0:7} #2 board/plan: not a story or fix-main branch
${C1:0:7} #3 story/s1: no board/stories/s1.md before the merge
${C2:0:7} #4 story/s2: no board/stories/s2.md before the merge
${C3:0:7} #5 story/s3: no board/stories/s3.md before the merge
${L_X}|2" "${CODE}|${OUT}|$(cached_files)"

if [[ ${fails} -eq 0 ]]; then echo "all non_fix_change checks passed"; else echo "${fails} non_fix_change check(s) failed"; exit 1; fi
