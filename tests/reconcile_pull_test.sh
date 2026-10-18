#!/usr/bin/env bash
# reconcile_pull_test.sh — reconcile pulls the main checkout with no backup, stash or restore. A story
# in review whose merged PR deleted it pulls cleanly and loses its state files, and so does a story a
# board PR took off the board (its state and escalated block), while a story still on the board keeps
# its state, even with its file removed by hand. An untracked copy of a story the pull brings gives way
# to it. A story whose uncommitted edit is only to swarm.sh's own keys (an older swarm.sh's review) has
# them moved to its state and pulls. A hand edit to a tracked story stops the pull, names the file,
# changes nothing, and logs one pull-failed incident, but with nothing to pull a hand edit stops
# nothing. gh is a stub on PATH; origin is a local bare repo.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
GIT=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main)
U="https://github.com/o/r/pull"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }
gone() { if [[ -e "$1" ]]; then echo there; else echo gone; fi; }

# gh answers pr view with the state ROOT/prs gives the URL; anything else fails.
mkdir -p "${ROOT}/bin"
printf '#!/bin/sh\nF="%s/prs"\n' "${ROOT}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'EOF'
case "$1 $2" in
  "pr view") st=$(awk -v u="$3" '$1 == u { print $2 }' "$F"); [ -n "$st" ] || exit 1; echo "{\"state\":\"$st\"}" ;;
  *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
chmod +x "${ROOT}/bin/gh"
printf '%s\n' "${U}/1 MERGED" "${U}/2 OPEN" "${U}/3 MERGED" > "${ROOT}/prs"

item() { # <file> <front-matter line>...
  local path="$1" title; shift
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}
at() { local d="${ROOT}/$1"; shift; (cd "${d}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
# val <item file> <key> — <key> as swarm.sh reads it: board.sh's own get_fm, in the project that holds it.
# shellcheck source=/dev/null
val() { local d="${1%/*}"; (export BOARD="${d%/*}"; export PROJECT_DIR="${BOARD%/*}"; . "${SWARM%/*}/lib/board.sh"; get_fm "$1" "$2"); }

# setup <name> — a bare origin whose board has stories a, d and e, with .swarm/ ignored; its main checkout <name>, with a in
# review (its PR merged), e in review (its PR open), and d escalated to the lead (its state and block
# as close writes them); and a clone <name>-up, which pushes a's PR (it deletes a) and d's drop board
# PR (it deletes d) to the base.
setup() {
  local d="${ROOT}/$1"
  "${GIT[@]}" init -q --bare "${d}.git"
  "${GIT[@]}" clone -q "${d}.git" "${d}" 2>/dev/null
  item "${d}/docs/stories/a.md" "status: ready" "kind: code"
  item "${d}/docs/stories/d.md" "status: ready" "kind: code"
  item "${d}/docs/stories/e.md" "status: ready" "kind: code"
  echo ".swarm/" > "${d}/.gitignore"   # as init writes it
  "${GIT[@]}" -C "${d}" add .gitignore docs && "${GIT[@]}" -C "${d}" commit -q -m board && "${GIT[@]}" -C "${d}" push -q origin main
  at "$1" review a "${U}/1" >/dev/null
  at "$1" review e "${U}/2" >/dev/null
  mkdir -p "${d}/.swarm/board-state/stories" "${d}/.swarm/escalated"
  printf '%s\n' "kind: lead" "kind@base: code" "escalated_from: code" "escalated_from@base:" > "${d}/.swarm/board-state/stories/d"
  echo "**Escalated.** d failed twice." > "${d}/.swarm/escalated/d"
  "${GIT[@]}" clone -q "${d}.git" "${d}-up"
  "${GIT[@]}" -C "${d}-up" rm -q docs/stories/a.md && "${GIT[@]}" -C "${d}-up" commit -q -m "a's PR"
  "${GIT[@]}" -C "${d}-up" rm -q docs/stories/d.md && "${GIT[@]}" -C "${d}-up" commit -q -m "drop d"
  "${GIT[@]}" -C "${d}-up" push -q origin main
}
state() { gone "${ROOT}/$1/.swarm/board-state/stories/$2"; }

# --- a's PR merged and deleted a: reconcile pulls with no backup, stash or error, and a's and d's
# state files go; e, still on the board, keeps its state, and so does f, an untracked story in review
# removed by hand. A board PR added g, and an untracked copy of it, byte for byte, is still here.
setup ok
item "${ROOT}/ok/docs/stories/f.md" "status: ready" "kind: code"; at ok review f "${U}/2" >/dev/null; rm "${ROOT}/ok/docs/stories/f.md"
item "${ROOT}/ok-up/docs/stories/g.md" "status: ready" "kind: code"
"${GIT[@]}" -C "${ROOT}/ok-up" add docs && "${GIT[@]}" -C "${ROOT}/ok-up" commit -q -m "add g" && "${GIT[@]}" -C "${ROOT}/ok-up" push -q origin main
cp "${ROOT}/ok-up/docs/stories/g.md" "${ROOT}/ok/docs/stories/g.md"
rc=0; out="$(at ok reconcile)" || rc=$?
check "a story deleted by its merged PR: reconcile exits 0 and fast-forwards to the base" "0|$(git -C "${ROOT}/ok.git" rev-parse main)" \
  "${rc}|$(git -C "${ROOT}/ok" rev-parse HEAD)"
check "the pull leaves no edit, no stash and no backup" "|||gone" \
  "$(git -C "${ROOT}/ok" status --porcelain)|$(git -C "${ROOT}/ok" stash list)|$(grep -i 'backup' <<< "${out}" || true)|$(gone "${ROOT}/ok/.swarm/state/reconcile-backup")"
check "a is gone from the board, and so is its state file" "gone|gone|yes" \
  "$(gone "${ROOT}/ok/docs/stories/a.md")|$(state ok a)|$(has "merged: a" "${out}")"
check "d, taken off by a board PR, loses its state file and its escalated block" "gone|gone|gone" \
  "$(gone "${ROOT}/ok/docs/stories/d.md")|$(state ok d)|$(gone "${ROOT}/ok/.swarm/escalated/d")"
check "e, still on the board and in review, keeps its state" "there|review ${U}/2" \
  "$(state ok e)|$(sed -n 's/^status: //p' "${ROOT}/ok/.swarm/board-state/stories/e") $(sed -n 's/^prs: //p' "${ROOT}/ok/.swarm/board-state/stories/e")"
check "f, an untracked story removed by hand, keeps its state after the pull" "there" "$(state ok f)"
check "the untracked copy of g, the same as the pull's, gives way to it" "there|" \
  "$(gone "${ROOT}/ok/docs/stories/g.md")|$(git -C "${ROOT}/ok" status --porcelain -- docs/stories/g.md)"

# --- Then e's file removed by hand, with no pull due: e keeps its state, since only a deletion a
# pull brings drops it.
rm "${ROOT}/ok/docs/stories/e.md"
rc=0; at ok reconcile >/dev/null || rc=$?
check "a story file removed by hand, no pull due: reconcile exits 0, and e keeps its state" "0|there" "${rc}|$(state ok e)"

# --- e in review as an older swarm.sh wrote it, in the file: its status: and prs: lines uncommitted,
# with no state. reconcile moves them to e's state, checks e out, and pulls.
setup ks; rm "${ROOT}/ks/.swarm/board-state/stories/e"
perl -pi -e 's|^status: .*$|status: review\nprs: '"${U}/2"'|' "${ROOT}/ks/docs/stories/e.md"
rc=0; out="$(at ks reconcile)" || rc=$?
check "a story edited only in swarm.sh's keys pulls, with its file checked out" "0|$(git -C "${ROOT}/ks.git" rev-parse main)|" \
  "${rc}|$(git -C "${ROOT}/ks" rev-parse HEAD)|$(git -C "${ROOT}/ks" status --porcelain)"
check "and reads as it did: review, with its PR, from its state" "review|${U}/2|status@base: ready|no" \
  "$(val "${ROOT}/ks/docs/stories/e.md" status)|$(val "${ROOT}/ks/docs/stories/e.md" prs)|$(grep -x 'status@base: ready' "${ROOT}/ks/.swarm/board-state/stories/e")|$(if grep -q incident "${ROOT}/ks/.swarm/events.tsv"; then echo yes; else echo no; fi)"

# --- The same, but e's state cannot be written: e's edit is put back, and the pull stops, naming e.
setup kf; rm "${ROOT}/kf/.swarm/board-state/stories/e"
perl -pi -e 's|^status: .*$|status: review\nprs: '"${U}/2"'|' "${ROOT}/kf/docs/stories/e.md"; cp "${ROOT}/kf/docs/stories/e.md" "${ROOT}/kf-e"
chmod a-w "${ROOT}/kf/.swarm/board-state/stories"
rc=0; out="$(at kf reconcile)" || rc=$?
chmod u+w "${ROOT}/kf/.swarm/board-state/stories"
check "a state write that fails puts the key edit back, and the pull stops, naming the file" "1|same|yes" \
  "${rc}|$(cmp -s "${ROOT}/kf-e" "${ROOT}/kf/docs/stories/e.md" && echo same)|$(has "board files are changed here: docs/stories/e.md" "${out}")"

# --- A hand edit to e, a tracked story: the pull stops, names e, changes nothing, and logs one
# pull-failed incident.
setup he
echo "a local note" >> "${ROOT}/he/docs/stories/e.md"; cp "${ROOT}/he/docs/stories/e.md" "${ROOT}/he-e"
before="$(git -C "${ROOT}/he" rev-parse HEAD)"
rc=0; out="$(at he reconcile)" || rc=$?
check "a hand edit to a tracked story stops the pull, named" "1|yes" \
  "${rc}|$(has "reconcile: cannot pull ${ROOT}/he: board files are changed here: docs/stories/e.md; land each edit through swarm.sh board-pr, or check the file out to drop it, then run reconcile again" "${out}")"
check "and changes nothing: HEAD, e's edit, a in review, and no stash" "${before}| M docs/stories/e.md|same|there|" \
  "$(git -C "${ROOT}/he" rev-parse HEAD)|$(git -C "${ROOT}/he" status --porcelain)|$(cmp -s "${ROOT}/he-e" "${ROOT}/he/docs/stories/e.md" && echo same)|$(state he a)|$(git -C "${ROOT}/he" stash list)"
check "one incident line: pull-failed, naming e" "1|pull-failed: docs/stories/e.md" \
  "$(awk -F'\t' '$2 == "incident"' "${ROOT}/he/.swarm/events.tsv" | wc -l | tr -d ' ')|$(awk -F'\t' '$2 == "incident" { print $5 }' "${ROOT}/he/.swarm/events.tsv")"

# --- Nothing to pull (the base pulled by hand), e in review with its PR merged, and a hand edit to a
# tracked file: reconcile marks e done, leaves the edit, and logs no incident.
setup np; git -C "${ROOT}/np" pull -q --ff-only
at np review e "${U}/3" >/dev/null; echo "# mine" >> "${ROOT}/np/.gitignore"
rc=0; out="$(at np reconcile)" || rc=$?
check "nothing to pull: a hand edit stops nothing, and the merged story is marked done" "0|done|yes" \
  "${rc}|$(val "${ROOT}/np/docs/stories/e.md" status)|$(has "merged: e, marked done" "${out}")"
check "and the edit stays, with no incident" " M .gitignore|no" \
  "$(git -C "${ROOT}/np" status --porcelain)|$(if grep -qs incident "${ROOT}/np/.swarm/events.tsv"; then echo yes; else echo no; fi)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
