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

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
