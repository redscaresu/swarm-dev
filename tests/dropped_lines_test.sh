#!/usr/bin/env bash
# dropped_lines_test.sh — bin/lib/dropped_lines.py on real repos with real conflicting merges (no gh,
# no network). Each case starts from f's BASE0 lines on main and a branch pr off it. Most have main
# replace line three with three-main and main-added, pr replace it with three-pr, and pr merge main,
# resolving f to the lines the case gives. A base line the resolution dropped prints as
# `<merge sha7> f: <text>` with exit 1; the PR's own lines, its own removals, conflict markers and
# whitespace-only lines never print; a merge it cannot check exits 2 with one line saying why.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

DL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/lib/dropped_lines.py"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${tmp}"' EXIT
export CLAUDE_CONFIG_DIR="${tmp}/claude-config"   # under its own root, so parallel runs share no ~/.claude
# No user or system git config: no signing, and git's default conflict style whatever the machine sets.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
# '=======' is a markdown underline, so a line with a conflict marker's text is in every parent's f;
# '}' stands for a line a PR-side conflict section shares with the rest of the base file.
BASE0=(one two three four five six seven eight '-- nine' ten '=======' '}' eleven)
fails=0

check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else printf 'FAIL %s:\n want: %s\n got:  %s\n' "$1" "$2" "$3"; fails=$((fails + 1)); fi
}

# scan <args...> — dropped_lines.py's output, then `exit <code>` on a line of its own
scan() {
  local out rc=0
  out="$(python3 "${DL}" "$@")" || rc=$?
  printf '%sexit %s' "${out:+${out}$'\n'}" "${rc}"
}

# lines [<line>...] — BASE0 with line three replaced by these lines (dropped when none are given)
lines() { printf '%s\n' one two "$@" "${BASE0[@]:3}"; }

# put <repo> <file> — the file holds stdin, committed on the checked-out branch
put() { cat > "$1/$2"; git -C "$1" add -A; git -C "$1" commit -qm "$2"; }

on() { git -C "$1" checkout -q "$2"; }

# new_repo <name> — a repo with BASE0 in f on main, branch pr off it, main checked out; prints its path
new_repo() {
  local d="${tmp}/$1"
  git init -q -b main "${d}"; printf '%s\n' "${BASE0[@]}" | put "${d}" f; git -C "${d}" branch pr
  echo "${d}"
}

# conflict <repo> [<pr's lines for three>...] — main replaces three with three-main and main-added,
# pr with three-pr (or the lines given); leaves pr checked out
conflict() {
  local d="$1"; shift
  lines three-main main-added | put "${d}" f; on "${d}" pr
  if [[ $# -eq 0 ]]; then lines three-pr | put "${d}" f; else lines "$@" | put "${d}" f; fi
}

# merge <repo> <branch> [-] — merge <branch> into the checked-out branch, with f resolved to stdin
# when - is given (else the auto-merge's result), and commit; prints the merge's SHA
merge() {
  git -C "$1" merge -q --no-ff --no-commit "$2" >/dev/null 2>&1 || true
  [[ "${3:-}" != - ]] || cat > "$1/f"
  git -C "$1" add -A; git -C "$1" commit -q --no-edit; git -C "$1" rev-parse HEAD
}

# Two builder merges: the older drops main-added (a line the base added), the newer is clean.
R="$(new_repo two)"; conflict "${R}"
M1="$(lines three-pr three-main | merge "${R}" main -)"
on "${R}" main; echo g1 | put "${R}" g; on "${R}" pr
M2="$(merge "${R}" main)"
check "the older of two merges dropped a base line: it prints with that merge's SHA and file" \
  "${M1:0:7} f: main-added"$'\n'"exit 1" "$(scan "${R}" main pr)"
check "with SHAs given, a merge not among them is not scanned" "exit 0" "$(scan "${R}" main pr "${M2}")"
check "with SHAs given, a merge among them is scanned" \
  "${M1:0:7} f: main-added"$'\n'"exit 1" "$(scan "${R}" main pr "${M1}" "${M2}")"

# A clean merge (each side changed a file of its own), then a conflict resolved by keeping both sides,
# which removes only the markers, '=======' among them.
R="$(new_repo clean)"; on "${R}" pr; echo g-pr | put "${R}" g; on "${R}" main; echo h1 | put "${R}" h
on "${R}" pr; merge "${R}" main >/dev/null
check "a clean merge: nothing, exit 0" "exit 0" "$(scan "${R}" main pr)"
on "${R}" main; conflict "${R}"
lines three-pr three-main main-added | merge "${R}" main - >/dev/null
check "a conflict resolved by keeping both sides drops only its markers: nothing, exit 0" "exit 0" "$(scan "${R}" main pr)"

# The same, with the base file's own '=======' dropped as well: that line prints once, and the
# conflict's '=======' marker, the same text, is not a second.
R="$(new_repo markers)"; conflict "${R}"
M="$(lines three-pr three-main main-added | grep -vx '=======' | merge "${R}" main -)"
check "a dropped '=======' line prints once; the conflict marker of that text does not" \
  "${M:0:7} f: ======="$'\n'"exit 1" "$(scan "${R}" main pr)"

# The PR-side drop: the resolution keeps the base's side and drops three-pr.
R="$(new_repo prside)"; conflict "${R}"
lines three-main main-added | merge "${R}" main - >/dev/null
check "the resolution dropped the PR's line, not the base's: nothing" "exit 0" "$(scan "${R}" main pr)"

# The PR's own removal inside the conflict hunk: pr removed four and main edited five, so four is in the
# base's conflict section; the resolution follows the PR. Then a PR commit after the merge removes seven.
R="$(new_repo own)"
printf '%s\n' one two three four five-main "${BASE0[@]:5}" | put "${R}" f; on "${R}" pr
printf '%s\n' one two three five "${BASE0[@]:5}" | put "${R}" f
printf '%s\n' one two three five-main "${BASE0[@]:5}" | merge "${R}" main - >/dev/null
check "a line the PR removed before the merge, inside the conflict hunk: nothing" "exit 0" "$(scan "${R}" main pr)"
grep -vx seven "${R}/f" > "${tmp}/f.own"; put "${R}" f < "${tmp}/f.own"
check "a line a PR commit removed after the merge: nothing" "exit 0" "$(scan "${R}" main pr)"

# Whitespace and a line both parents had: main's side of the conflict ends in a whitespace-only line,
# and the resolution drops it and '-- nine', which every side has (a removed line starting with '--').
R="$(new_repo both)"; lines three-main '   ' | put "${R}" f; on "${R}" pr; lines three-pr | put "${R}" f
M="$(lines three-pr three-main | grep -vx -- '-- nine' | merge "${R}" main -)"
check "a whitespace-only line is not printed; a line both parents had is" \
  "${M:0:7} f: -- nine"$'\n'"exit 1" "$(scan "${R}" main pr)"

# The first case's drop, made from the base side: main's tip is the merge's first parent.
R="$(new_repo swapped)"; conflict "${R}"
git -C "${R}" checkout -q -b sw main
M="$(lines three-main three-pr | merge "${R}" pr -)"
check "a merge whose parents are in swapped order: the same dropped line is found" \
  "${M:0:7} f: main-added"$'\n'"exit 1" "$(scan "${R}" main sw)"

# A PR-side line in a conflict section whose text is elsewhere in the base file ('}'): the line's side
# is its section's, so it is not a base line.
R="$(new_repo loose)"; conflict "${R}" three-pr '}'
lines three-main main-added | merge "${R}" main - >/dev/null
check "a PR-side conflict line whose text is elsewhere in the base file: nothing" "exit 0" "$(scan "${R}" main pr)"

# The same, with the PR's section long enough that the remerge diff splits it into two hunks: the
# second, which drops '}', does not hold the <<<<<<< marker, and the section still holds there.
R="$(new_repo split)"; conflict "${R}" three-pr p1 p2 p3 p4 p5 p6 p7 p8 '}'
lines three-pr p1 p2 p3 p4 p5 p6 p7 p8 three-main main-added | merge "${R}" main - >/dev/null
check "a PR-side '}' dropped in a conflict split over two hunks: nothing" "exit 0" "$(scan "${R}" main pr)"

# A duplicated line the PR removed: d's merge base has '}' twice, pr removed the second and main
# edited the line after it, so that '}' is in the base's conflict section while pr keeps the first.
# The resolution follows the PR.
R="$(new_repo dup)"; printf '%s\n' x '}' y '}' z | put "${R}" d; git -C "${R}" branch -f pr main
printf '%s\n' x '}' y '}' z-main | put "${R}" d; on "${R}" pr; printf '%s\n' x '}' y z | put "${R}" d
git -C "${R}" merge -q --no-commit main >/dev/null 2>&1 || true
printf '%s\n' x '}' y z-main | put "${R}" d
check "a copy of a duplicated line that the PR removed, which the resolution follows: nothing" \
  "exit 0" "$(scan "${R}" main pr)"

# A file the PR renamed: pr moves f to g and edits three, main edits three in f, and the resolution
# in g keeps only three-pr. main's lines are read from its f, not from a g it does not have.
R="$(new_repo rename)"; lines three-main main-added | put "${R}" f; on "${R}" pr
git -C "${R}" mv f g; lines three-pr | put "${R}" g
M="$(git -C "${R}" merge -q --no-commit main >/dev/null 2>&1 || true; lines three-pr | put "${R}" g; git -C "${R}" rev-parse HEAD)"
check "a file the PR renamed: the base lines the resolution dropped there print under its new name" \
  "${M:0:7} g: three-main"$'\n'"${M:0:7} g: main-added"$'\n'"exit 1" "$(scan "${R}" main pr)"

# The PR removed the merge base's one 'return nil'; main added a second copy in a hunk that conflicts,
# and the resolution drops main's copy. The base side's copy is still owed, though the PR's removal
# leaves no copy on the PR side.
R="$(new_repo prremoved)"; printf '%s\n' a 'return nil' b c d e | put "${R}" d; git -C "${R}" branch -f pr main
printf '%s\n' a 'return nil' b c-main 'return nil' d e | put "${R}" d; on "${R}" pr
printf '%s\n' a b c-pr d e | put "${R}" d
M="$(git -C "${R}" merge -q --no-commit main >/dev/null 2>&1 || true; printf '%s\n' a b c-pr d e | put "${R}" d; git -C "${R}" rev-parse HEAD)"
check "a base copy of a line the PR removed another copy of, which the resolution dropped, prints" \
  "${M:0:7} d: c-main"$'\n'"${M:0:7} d: return nil"$'\n'"exit 1" "$(scan "${R}" main pr)"

# The merge base has '}' twice; the PR removes the first and the resolution drops the second as well,
# which both parents had.
R="$(new_repo twobraces)"; printf '%s\n' x '}' y '}' z | put "${R}" d; git -C "${R}" branch -f pr main
printf '%s\n' x '}' y '}' z-main | put "${R}" d; on "${R}" pr; printf '%s\n' x y '}' z | put "${R}" d
M="$(git -C "${R}" merge -q --no-commit main >/dev/null 2>&1 || true; printf '%s\n' x y z-main | put "${R}" d; git -C "${R}" rev-parse HEAD)"
check "the other copy of a duplicated line the PR removed one of, dropped by the resolution, prints" \
  "${M:0:7} d: }"$'\n'"exit 1" "$(scan "${R}" main pr)"

# main's conflict section adds a second '}' and the resolution drops it, and moves the base file's own
# '}' to the top: two removed '}' lines and one added back, with the file short of one copy.
R="$(new_repo moved)"; lines three-main '}' | put "${R}" f; on "${R}" pr; lines three-pr | put "${R}" f
M="$({ echo '}'; lines three-pr three-main | grep -vx '}'; } | merge "${R}" main -)"
check "two copies of a line removed and one added back, the file short of one: it prints once" \
  "${M:0:7} f: }"$'\n'"exit 1" "$(scan "${R}" main pr)"

# Both sides add file n: the merge base has no n, so main's line, which the resolution drops, is new.
R="$(new_repo addadd)"; echo n-main | put "${R}" n; on "${R}" pr; echo n-pr | put "${R}" n
git -C "${R}" merge -q --no-commit main >/dev/null 2>&1 || true
echo n-pr | put "${R}" n; M="$(git -C "${R}" rev-parse HEAD)"
check "a base line of a file the merge base lacks, which the resolution dropped, prints" \
  "${M:0:7} n: n-main"$'\n'"exit 1" "$(scan "${R}" main pr)"

# An octopus merge on the PR branch.
R="$(new_repo octopus)"; git -C "${R}" branch b1; git -C "${R}" branch b2
on "${R}" b1; echo g1 | put "${R}" g; on "${R}" b2; echo h1 | put "${R}" h; on "${R}" pr; echo p1 | put "${R}" p
git -C "${R}" merge -q --no-edit b1 b2 >/dev/null 2>&1
M="$(git -C "${R}" rev-parse HEAD)"
check "an octopus merge exits 2 naming it" \
  "merge ${M:0:7} has 3 parents: an octopus merge is not remerged, so it is not checked"$'\n'"exit 2" \
  "$(scan "${R}" main pr)"

# A stacked build: b, built on a, merges a's newer commit after a squash-merged into main.
R="$(new_repo stacked)"
git -C "${R}" checkout -q -b a main; echo a1 | put "${R}" a.txt
git -C "${R}" checkout -q -b b a; echo b1 | put "${R}" b.txt
on "${R}" a; echo a2 | put "${R}" a.txt
on "${R}" main; echo a2 | put "${R}" a.txt
on "${R}" b; M="$(merge "${R}" a)"
check "a merge of a stacked parent branch is unchecked, with its reason, not dropped lines" \
  "merge ${M:0:7} is unchecked: neither parent is on main, so it is not a merge of main (a stacked build's merge of its parent branch?)"$'\n'"exit 2" \
  "$(scan "${R}" main b)"

check "a range git cannot read exits 2 saying so" \
  "cannot list the merges in main..nope: fatal: bad revision 'main..nope'"$'\n'"exit 2" "$(scan "${R}" main nope)"

# --- swarm.sh dropped-lines <owner/repo> <n> <head> <base>: the project P is a clone of the bare origin
# acme/widget.git, where W, a work repo, pushes main and refs/pull/7/head. gh is a stub that serves PR 7's
# commits (${tmp}/commits.json, honouring --jq) and logs each call.
SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
ROOT="$(cd "${tmp}" && pwd -P)"; O="${ROOT}/acme/widget.git"; P="${ROOT}/widget"; URL7=https://github.com/acme/widget/pull/7
mkdir -p "${ROOT}/acme" "${ROOT}/bin" "${ROOT}/oldgit"; git init -q --bare "${O}"
# shellcheck disable=SC2016 # the stub's own variables
printf '#!/bin/sh\necho "$*" >> "%s/gh.log"\nFX="%s"\n' "${ROOT}" "${ROOT}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
case "$*" in
  *"/pulls/7/commits"*) q="."; prev=""; for a in "$@"; do [ "${prev}" != --jq ] || q="${a}"; prev="${a}"; done
                        jq -r "${q}" "${FX}/commits.json" ;;
  *) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
esac
STUB
# A git that says it is 2.35.0 and is the real git for anything else.
# shellcheck disable=SC2016 # the stub's own arguments
printf '#!/bin/sh\ncase "$1" in version|--version) echo "git version 2.35.0" ;; *) exec "%s" "$@" ;; esac\n' "$(command -v git)" > "${ROOT}/oldgit/git"
chmod +x "${ROOT}/bin/gh" "${ROOT}/oldgit/git"

# W: main replaces three with three-main and main-added, pr with three-pr, and pr's merge of main drops
# main-added (DROP). PLAIN, on branch plain off main, has no merge.
W="$(new_repo work)"; conflict "${W}"
DROP="$(lines three-pr three-main | merge "${W}" main -)"
git -C "${W}" checkout -q -b plain main; echo p | put "${W}" p; PLAIN="$(git -C "${W}" rev-parse HEAD)"
git -C "${W}" push -q "${O}" main
git clone -q "${O}" "${P}"; mkdir -p "${P}/.claude/swarm" "${P}/docs/stories" "${P}/.swarm"; : > "${P}/.claude/swarm/config"

# pull <ref commit> [<listed commit>] — origin's refs/pull/7/head is <ref commit>, and gh lists main..<listed
# commit> (by default <ref commit>), each as GitHub's own commit: committer web-flow, signature verified.
pull() {
  local c ps sep="" json="["
  git -C "${W}" push -q -f "${O}" "$1:refs/pull/7/head"
  for c in $(git -C "${W}" rev-list --reverse "main..${2:-$1}"); do
    ps="$(git -C "${W}" rev-list --parents -n 1 "${c}" | cut -d' ' -f2- | sed -E 's/([0-9a-f]+)/{"sha":"\1"}/g; s/ /,/g')"
    json+="${sep}{\"sha\":\"${c}\",\"committer\":{\"login\":\"web-flow\"},\"commit\":{\"verification\":{\"verified\":true}},\"parents\":[${ps}]}"
    sep=","
  done
  echo "${json}]" > "${ROOT}/commits.json"
}

# dl <head> [<owner/repo>] — swarm.sh dropped-lines <owner/repo> (acme/widget) 7 <head> main, its stdout
# and stderr, then `exit <code>`; GITPATH, when set, goes first on PATH.
dl() {
  local out rc=0
  out="$(cd "${P}" && env -u HERDR_ENV SWARM_PROJECT="${P}" PATH="${GITPATH:+${GITPATH}:}${ROOT}/bin:${PATH}" \
    bash "${SWARM}" dropped-lines "${2:-acme/widget}" 7 "$1" main 2>&1)" || rc=$?
  printf '%sexit %s' "${out:+${out}$'\n'}" "${rc}"
}

# events.tsv before any run: one line, written by hand below.
pull "${DROP}"
check "dropped-lines: a builder's merge (web-flow, verified) that dropped a base line prints it, exit 1" \
  "${DROP:0:7} f: main-added"$'\n'"exit 1" "$(dl "${DROP}")"
check "dropped-lines: git 2.35 on a PR with a builder merge: exit 2 naming 2.36" \
  "swarm: dropped-lines: git 2.35.0 is below 2.36, the first with git show --remerge-diff, which the scan of ${URL7}'s merges reads: update git"$'\n'"exit 2" \
  "$(GITPATH="${ROOT}/oldgit" dl "${DROP}")"
pull "${PLAIN}"
check "dropped-lines: no merge commit, refs/pull/7/head fetched and equal to the head: exit 0 (owner/repo compared lower case)" \
  "exit 0" "$(dl "${PLAIN}" ACME/widget)"
pull "${DROP}" "${PLAIN}"
check "dropped-lines: no merge commit, refs/pull/7/head another commit (a stale fetch): exit 2 naming both" \
  "swarm: dropped-lines: ${URL7}'s head on ${O} (refs/pull/7/head) is ${DROP}, not ${PLAIN}: the PR moved, or GitHub has not updated the ref yet; run it on the head the PR has"$'\n'"exit 2" \
  "$(dl "${PLAIN}")"
pull "${DROP}" "${PLAIN}"
check "dropped-lines: the head absent from gh's list of the PR's commits: exit 2" \
  "swarm: dropped-lines: ${DROP} is not among ${URL7}'s commits as gh lists them: the PR's head moved"$'\n'"exit 2" "$(dl "${DROP}")"

# DROP recorded as GitHub's merge of the base (merge_base_update's line): skipped, though it drops a line.
printf '2026-10-29T00:00:00Z\tmerge\ts\t-\tbase-merged %s from %s\n' "${DROP}" "${PLAIN}" > "${P}/.swarm/events.tsv"
cp "${P}/.swarm/events.tsv" "${ROOT}/events.before"
pull "${DROP}"
check "dropped-lines: the only merge is a recorded base-merged update: exit 0" "exit 0" "$(dl "${DROP}")"
pull "${PLAIN}" "${DROP}"
check "dropped-lines: a recorded base-merged update, refs/pull/7/head another commit: exit 2" \
  "swarm: dropped-lines: ${URL7}'s head on ${O} (refs/pull/7/head) is ${PLAIN}, not ${DROP}: the PR moved, or GitHub has not updated the ref yet; run it on the head the PR has"$'\n'"exit 2" \
  "$(dl "${DROP}")"
check "dropped-lines: a repo whose origin is not <owner/repo>: exit 2 naming both" \
  "swarm: dropped-lines: ${P}'s origin is ${O} (acme/widget), not elsewhere/widget"$'\n'"exit 2" "$(dl "${DROP}" elsewhere/widget)"
check "dropped-lines: a die (a head that is no SHA) exits 2, not 1" \
  "swarm: dropped-lines: usage: swarm.sh dropped-lines <owner/repo> <n> <40-character head SHA> <base>"$'\n'"exit 2" "$(dl nothex)"
check "dropped-lines: no run added a line to events.tsv" "" "$(diff "${ROOT}/events.before" "${P}/.swarm/events.tsv" 2>&1)"
check "dropped-lines: no run left its fetch's ref, or a FETCH_HEAD" "none" \
  "$(git -C "${P}" for-each-ref refs/swarm; [[ ! -e "${P}/.git/FETCH_HEAD" ]] && echo none)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
