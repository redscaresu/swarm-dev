#!/usr/bin/env bash
# reconcile_pull_test.sh — reconcile pulls the main checkout with no backup, stash or restore. A story
# in review whose merged PR deleted it pulls cleanly and loses its state files, and so does a story a
# board PR took off the board (its state and escalated block), while a story still on the board keeps
# its state, even with its file removed by hand. An untracked copy of a story the pull brings gives way
# to it. A story whose uncommitted edit is only to swarm.sh's own keys (an older swarm.sh's review) has
# them moved to its state and pulls, reading as before even where its state disagrees with the file.
# Only a file the pull changes has its keys moved; a key edit on any other stays in it, and one whose
# file the pull gives a new dependency, or changes the same keys in, stops the pull, except a status
# write, which gives way to the incoming status. With no upstream, a merged item is marked done. A hand edit
# to a tracked story the pull also changes stops the pull, before any key is moved, names the file,
# changes nothing, and logs one pull-failed incident; with nothing to pull it stops nothing. A merge
# git refuses puts back every change made for it. After a pull by hand, reconcile still drops the
# state of the stories the pulled commits deleted, and of an epic whose deletion took docs/epics.
# gh is a stub on PATH; origin is a local bare repo.
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
# base_edit <name> — <name>-up pushes a body line to e, so the pull changes e too.
base_edit() {
  echo "the base's line" >> "${ROOT}/$1-up/docs/stories/e.md"
  "${GIT[@]}" -C "${ROOT}/$1-up" commit -q -am "edit e" && "${GIT[@]}" -C "${ROOT}/$1-up" push -q origin main
}

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
# with no state, and the pull changes e. reconcile moves them to e's state, checks e out, and pulls.
setup ks; base_edit ks; rm "${ROOT}/ks/.swarm/board-state/stories/e"
perl -pi -e 's|^status: .*$|status: review\nprs: '"${U}/2"'|' "${ROOT}/ks/docs/stories/e.md"
rc=0; out="$(at ks reconcile)" || rc=$?
check "a story edited only in swarm.sh's keys pulls, with its file checked out" "0|$(git -C "${ROOT}/ks.git" rev-parse main)|" \
  "${rc}|$(git -C "${ROOT}/ks" rev-parse HEAD)|$(git -C "${ROOT}/ks" status --porcelain)"
check "and reads as it did: review, with its PR, from its state" "review|${U}/2|status@base: ready|no" \
  "$(val "${ROOT}/ks/docs/stories/e.md" status)|$(val "${ROOT}/ks/docs/stories/e.md" prs)|$(grep -x 'status@base: ready' "${ROOT}/ks/.swarm/board-state/stories/e")|$(if grep -q incident "${ROOT}/ks/.swarm/events.tsv"; then echo yes; else echo no; fi)"

# --- e as an older swarm.sh's review wrote it, but its state, written since, says blocked (its base
# the file's review): e reads blocked before the pull and after it, with the file's PR.
setup kb; base_edit kb
printf '%s\n' "status: blocked" "status@base: review" > "${ROOT}/kb/.swarm/board-state/stories/e"
perl -pi -e 's|^status: .*$|status: review\nprs: '"${U}/2"'|' "${ROOT}/kb/docs/stories/e.md"
was="$(val "${ROOT}/kb/docs/stories/e.md" status)"
rc=0; at kb reconcile >/dev/null || rc=$?
check "a key edit under newer state moves as it reads: blocked before and after, with its PR" "0|blocked|blocked|${U}/2|" \
  "${rc}|${was}|$(val "${ROOT}/kb/docs/stories/e.md" status)|$(val "${ROOT}/kb/docs/stories/e.md" prs)|$(git -C "${ROOT}/kb" status --porcelain)"

# --- The same, but e's state cannot be written: e's edit is put back, and the pull stops, naming e.
setup kf; base_edit kf; rm "${ROOT}/kf/.swarm/board-state/stories/e"
perl -pi -e 's|^status: .*$|status: review\nprs: '"${U}/2"'|' "${ROOT}/kf/docs/stories/e.md"; cp "${ROOT}/kf/docs/stories/e.md" "${ROOT}/kf-e"
chmod a-w "${ROOT}/kf/.swarm/board-state/stories"
rc=0; out="$(at kf reconcile)" || rc=$?
chmod u+w "${ROOT}/kf/.swarm/board-state/stories"
check "a state write that fails puts the key edit back, and the pull stops, naming the file" "1|same|yes" \
  "${rc}|$(cmp -s "${ROOT}/kf-e" "${ROOT}/kf/docs/stories/e.md" && echo same)|$(has "reconcile: cannot pull ${ROOT}/kf: cannot move swarm.sh's keys in docs/stories/e.md into its board state, so every edit stays" "${out}")"

# --- e's key edit, and a hand edit to d, which the pull deletes: the pull stops on d before e's keys
# move, so e's file and state are as they were.
setup k4; base_edit k4; rm "${ROOT}/k4/.swarm/board-state/stories/e"
perl -pi -e 's|^status: .*$|status: review\nprs: '"${U}/2"'|' "${ROOT}/k4/docs/stories/e.md"; cp "${ROOT}/k4/docs/stories/e.md" "${ROOT}/k4-e"
echo "a local note" >> "${ROOT}/k4/docs/stories/d.md"
rc=0; out="$(at k4 reconcile)" || rc=$?
check "a stop on another file moves no key first: e's edit stays, with no state" "1|yes|same|gone" \
  "${rc}|$(has "board files are changed here: docs/stories/d.md;" "${out}")|$(cmp -s "${ROOT}/k4-e" "${ROOT}/k4/docs/stories/e.md" && echo same)|$(state k4 e)"

# --- codex's case: h committed blocked on old, an older swarm.sh's uncommitted unblock flip to ready,
# and incoming commits that add a dependency (depends_on: [old, new]) without touching status. The
# pull stops, naming h; h's edit stays, with no state, so h is not read as ready over the dependency.
setup kd; git -C "${ROOT}/kd" pull -q --ff-only
item "${ROOT}/kd-up/docs/stories/h.md" "status: blocked" "kind: code" "depends_on: [old]"
"${GIT[@]}" -C "${ROOT}/kd-up" add docs && "${GIT[@]}" -C "${ROOT}/kd-up" commit -q -m "add h" && "${GIT[@]}" -C "${ROOT}/kd-up" push -q origin main
git -C "${ROOT}/kd" pull -q --ff-only
perl -pi -e 's|^status: blocked$|status: ready|' "${ROOT}/kd/docs/stories/h.md"; cp "${ROOT}/kd/docs/stories/h.md" "${ROOT}/kd-h"
perl -pi -e 's|^depends_on: \[old\]$|depends_on: [old, new]|' "${ROOT}/kd-up/docs/stories/h.md"
"${GIT[@]}" -C "${ROOT}/kd-up" commit -q -am "h waits on new too" && "${GIT[@]}" -C "${ROOT}/kd-up" push -q origin main
rc=0; out="$(at kd reconcile)" || rc=$?
check "an old ready flip under a new dependency stops the pull, naming h, and moves nothing" "1|yes|same|gone|pull-failed: docs/stories/h.md" \
  "${rc}|$(has "swarm.sh's keys are changed here in docs/stories/h.md, and the incoming commits change its depends_on or the same keys" "${out}")|$(cmp -s "${ROOT}/kd-h" "${ROOT}/kd/docs/stories/h.md" && echo same)|$(state kd h)|$(awk -F'\t' '$2 == "incident" { print $5 }' "${ROOT}/kd/.swarm/events.tsv")"

# --- e in review as an older swarm.sh wrote it (status: review and prs: uncommitted, no state), and
# its merged PR sets status: done: the old status write gives way, and the pull goes, e done.
setup kc; rm "${ROOT}/kc/.swarm/board-state/stories/e"
perl -pi -e 's|^status: ready$|status: done|' "${ROOT}/kc-up/docs/stories/e.md"
"${GIT[@]}" -C "${ROOT}/kc-up" commit -q -am "e's PR" && "${GIT[@]}" -C "${ROOT}/kc-up" push -q origin main
perl -pi -e 's|^status: .*$|status: review\nprs: '"${U}/3"'|' "${ROOT}/kc/docs/stories/e.md"
rc=0; out="$(at kc reconcile)" || rc=$?
check "a leftover status: review gives way to the PR's status: done, and the pull goes" "0|$(git -C "${ROOT}/kc.git" rev-parse main)||done||yes|no" \
  "${rc}|$(git -C "${ROOT}/kc" rev-parse HEAD)|$(git -C "${ROOT}/kc" status --porcelain)|$(val "${ROOT}/kc/docs/stories/e.md" status)|$(val "${ROOT}/kc/docs/stories/e.md" prs)|$(has "merged: e" "${out}")|$(if grep -qs pull-failed "${ROOT}/kc/.swarm/events.tsv"; then echo yes; else echo no; fi)"

# --- A hand-set status: later in e (uncommitted; e's state says review), and a board PR that blocks
# e: the pull's status wins, and reconcile names both values, on stdout and in an incident.
setup kh
perl -pi -e 's|^status: ready$|status: blocked|' "${ROOT}/kh-up/docs/stories/e.md"
"${GIT[@]}" -C "${ROOT}/kh-up" commit -q -am "block e" && "${GIT[@]}" -C "${ROOT}/kh-up" push -q origin main
perl -pi -e 's|^status: ready$|status: later|' "${ROOT}/kh/docs/stories/e.md"
rc=0; out="$(at kh reconcile)" || rc=$?
check "a hand edit the pull's status replaces is named, with both values, on stdout and in an incident" "0|blocked|yes|key-dropped: docs/stories/e.md status: later -> blocked" \
  "${rc}|$(val "${ROOT}/kh/docs/stories/e.md" status)|$(has "reconcile: docs/stories/e.md: the pull's status: blocked replaced your uncommitted status: later; set it again if you meant it" "${out}")|$(awk -F'\t' '$2 == "incident" { print $5 }' "${ROOT}/kh/.swarm/events.tsv")"

# --- A leftover kind: lead in e (uncommitted, no state), and a board PR that commits the same kind:
# lead: the same value on both sides goes through, and e reads lead.
setup ki; rm "${ROOT}/ki/.swarm/board-state/stories/e"
perl -pi -e 's|^kind: code$|kind: lead|' "${ROOT}/ki-up/docs/stories/e.md"
"${GIT[@]}" -C "${ROOT}/ki-up" commit -q -am "e is lead" && "${GIT[@]}" -C "${ROOT}/ki-up" push -q origin main
perl -pi -e 's|^kind: code$|kind: lead\nescalated_from: code|' "${ROOT}/ki/docs/stories/e.md"
rc=0; at ki reconcile >/dev/null || rc=$?
check "the same key value on both sides goes through: the pull goes, and e reads lead, from code" "0|$(git -C "${ROOT}/ki.git" rev-parse main)||lead|code|no" \
  "${rc}|$(git -C "${ROOT}/ki" rev-parse HEAD)|$(git -C "${ROOT}/ki" status --porcelain)|$(val "${ROOT}/ki/docs/stories/e.md" kind)|$(val "${ROOT}/ki/docs/stories/e.md" escalated_from)|$(if grep -qs incident "${ROOT}/ki/.swarm/events.tsv"; then echo yes; else echo no; fi)"

# --- e escalated by an older swarm.sh (kind: lead, uncommitted), and incoming commits that set e's
# kind too: the pull stops, naming e, and e's edit stays, with no state.
setup kk; rm "${ROOT}/kk/.swarm/board-state/stories/e"
perl -pi -e 's|^kind: code$|kind: docs|' "${ROOT}/kk-up/docs/stories/e.md"
"${GIT[@]}" -C "${ROOT}/kk-up" commit -q -am "e is docs" && "${GIT[@]}" -C "${ROOT}/kk-up" push -q origin main
perl -pi -e 's|^kind: code$|kind: lead\nescalated_from: code|' "${ROOT}/kk/docs/stories/e.md"; cp "${ROOT}/kk/docs/stories/e.md" "${ROOT}/kk-e"
rc=0; out="$(at kk reconcile)" || rc=$?
check "an old key edit the incoming commits change too stops the pull, naming e, and moves nothing" "1|yes|same|gone" \
  "${rc}|$(has "swarm.sh's keys are changed here in docs/stories/e.md, and the incoming commits change its depends_on or the same keys" "${out}")|$(cmp -s "${ROOT}/kk-e" "${ROOT}/kk/docs/stories/e.md" && echo same)|$(state kk e)"

# --- A hand edit to e's swarm.sh keys (kind: lead, the lead's own) on a file the pull leaves alone:
# it stays in the file, and e's state is as it was.
setup kl
perl -pi -e 's|^kind: code$|kind: lead|' "${ROOT}/kl/docs/stories/e.md"; cp "${ROOT}/kl/.swarm/board-state/stories/e" "${ROOT}/kl-se"
rc=0; at kl reconcile >/dev/null || rc=$?
check "a key edit on a file the pull leaves alone stays in the file, and e's state as it was" "0|$(git -C "${ROOT}/kl.git" rev-parse main)| M docs/stories/e.md|kind: lead|same" \
  "${rc}|$(git -C "${ROOT}/kl" rev-parse HEAD)|$(git -C "${ROOT}/kl" status --porcelain)|$(grep -x 'kind: lead' "${ROOT}/kl/docs/stories/e.md")|$(cmp -s "${ROOT}/kl-se" "${ROOT}/kl/.swarm/board-state/stories/e" && echo same)"

# --- A merge git refuses (an untracked notes.txt the base adds, with other bytes): every change made
# for the pull is put back. e's key edit (the pull changes e), e's state and g's identical untracked
# copy are as they were.
setup rf; base_edit rf
item "${ROOT}/rf-up/docs/stories/g.md" "status: ready" "kind: code"; echo theirs > "${ROOT}/rf-up/notes.txt"
"${GIT[@]}" -C "${ROOT}/rf-up" add docs notes.txt && "${GIT[@]}" -C "${ROOT}/rf-up" commit -q -m "add g and notes" && "${GIT[@]}" -C "${ROOT}/rf-up" push -q origin main
cp "${ROOT}/rf-up/docs/stories/g.md" "${ROOT}/rf/docs/stories/g.md"; cp "${ROOT}/rf/docs/stories/g.md" "${ROOT}/rf-g"; echo mine > "${ROOT}/rf/notes.txt"
perl -pi -e 's|^kind: code$|kind: lead|' "${ROOT}/rf/docs/stories/e.md"; cp "${ROOT}/rf/docs/stories/e.md" "${ROOT}/rf-e"; cp "${ROOT}/rf/.swarm/board-state/stories/e" "${ROOT}/rf-se"
before="$(git -C "${ROOT}/rf" rev-parse HEAD)"
rc=0; out="$(at rf reconcile)" || rc=$?
check "a merge git refuses, after e's keys moved, is reported" "1|yes|yes" \
  "${rc}|$(has "changed only swarm.sh's own keys" "${out}")|$(has "git refused the pull (" "$(grep 'cannot pull' <<< "${out}")")"
check "and every change made for it is put back: HEAD, e's edit, e's state, g's copy, notes.txt" "${before}|same|same|same|mine" \
  "$(git -C "${ROOT}/rf" rev-parse HEAD)|$(cmp -s "${ROOT}/rf-e" "${ROOT}/rf/docs/stories/e.md" && echo same)|$(cmp -s "${ROOT}/rf-se" "${ROOT}/rf/.swarm/board-state/stories/e" && echo same)|$(cmp -s "${ROOT}/rf-g" "${ROOT}/rf/docs/stories/g.md" && echo same)|$(cat "${ROOT}/rf/notes.txt")"

# --- A hand edit to e, a tracked story the base changes too: the pull stops, names e, changes
# nothing, and logs one pull-failed incident.
setup he; base_edit he
echo "a local note" >> "${ROOT}/he/docs/stories/e.md"; cp "${ROOT}/he/docs/stories/e.md" "${ROOT}/he-e"
before="$(git -C "${ROOT}/he" rev-parse HEAD)"
rc=0; out="$(at he reconcile)" || rc=$?
check "a hand edit to a tracked story stops the pull, named" "1|yes" \
  "${rc}|$(has "reconcile: cannot pull ${ROOT}/he: board files are changed here: docs/stories/e.md; land each edit through swarm.sh board-pr, or check the file out to drop it, then run reconcile again" "${out}")"
check "and changes nothing: HEAD, e's edit, a in review, and no stash" "${before}| M docs/stories/e.md|same|there|" \
  "$(git -C "${ROOT}/he" rev-parse HEAD)|$(git -C "${ROOT}/he" status --porcelain)|$(cmp -s "${ROOT}/he-e" "${ROOT}/he/docs/stories/e.md" && echo same)|$(state he a)|$(git -C "${ROOT}/he" stash list)"
check "one incident line: pull-failed, naming e" "1|pull-failed: docs/stories/e.md" \
  "$(awk -F'\t' '$2 == "incident"' "${ROOT}/he/.swarm/events.tsv" | wc -l | tr -d ' ')|$(awk -F'\t' '$2 == "incident" { print $5 }' "${ROOT}/he/.swarm/events.tsv")"
rc=0; at he reconcile >/dev/null || rc=$?
check "the same stop on the next reconcile logs no second incident" "1|1" \
  "${rc}|$(awk -F'\t' '$2 == "incident"' "${ROOT}/he/.swarm/events.tsv" | wc -l | tr -d ' ')"

# --- Nothing to pull (the base pulled by hand), e in review with its PR merged, and a hand edit to a
# tracked file: reconcile marks e done, leaves the edit, and logs no incident.
setup np; git -C "${ROOT}/np" pull -q --ff-only
at np review e "${U}/3" >/dev/null; echo "# mine" >> "${ROOT}/np/.gitignore"
rc=0; out="$(at np reconcile)" || rc=$?
check "nothing to pull: a hand edit stops nothing, and the merged story is marked done" "0|done|yes" \
  "${rc}|$(val "${ROOT}/np/docs/stories/e.md" status)|$(has "merged: e, marked done" "${out}")"
check "and the edit stays, with no incident" " M .gitignore|no" \
  "$(git -C "${ROOT}/np" status --porcelain)|$(if grep -qs incident "${ROOT}/np/.swarm/events.tsv"; then echo yes; else echo no; fi)"

# --- The base pulled by hand: a's PR and d's board PR deleted them, and no pull is due. reconcile
# still drops their state and d's escalated block, so a new d reads as written; e keeps its state.
setup hp; git -C "${ROOT}/hp" pull -q --ff-only
rc=0; at hp reconcile >/dev/null || rc=$?
check "after a pull by hand, the deleted stories lose their state, and e keeps its" "0|gone|gone|gone|there" \
  "${rc}|$(state hp a)|$(state hp d)|$(gone "${ROOT}/hp/.swarm/escalated/d")|$(state hp e)"
item "${ROOT}/hp/docs/stories/d.md" "status: ready" "kind: code"
check "and a new story d reads as written: ready, kind code" "ready|code" \
  "$(val "${ROOT}/hp/docs/stories/d.md" status)|$(val "${ROOT}/hp/docs/stories/d.md" kind)"

# --- A board PR deletes x, the only epic, so git removes docs/epics with it: x's state goes too.
setup ep; git -C "${ROOT}/ep" pull -q --ff-only
item "${ROOT}/ep-up/docs/epics/x.md" "status: planned"
"${GIT[@]}" -C "${ROOT}/ep-up" add docs && "${GIT[@]}" -C "${ROOT}/ep-up" commit -q -m "add x" && "${GIT[@]}" -C "${ROOT}/ep-up" push -q origin main
git -C "${ROOT}/ep" pull -q --ff-only
mkdir -p "${ROOT}/ep/.swarm/board-state/epics"; printf '%s\n' "status: ready" "status@base: planned" > "${ROOT}/ep/.swarm/board-state/epics/x"
"${GIT[@]}" -C "${ROOT}/ep-up" rm -q docs/epics/x.md && "${GIT[@]}" -C "${ROOT}/ep-up" commit -q -m "drop x" && "${GIT[@]}" -C "${ROOT}/ep-up" push -q origin main
rc=0; at ep reconcile >/dev/null || rc=$?
check "a pull that deletes the last epic takes docs/epics, and x's state goes" "0|gone|gone" \
  "${rc}|$(gone "${ROOT}/ep/docs/epics")|$(gone "${ROOT}/ep/.swarm/board-state/epics/x")"

# --- No upstream for the main checkout: nothing can be pulled, so a, merged with its file still
# here, is marked done at once, and the main checkout keeps no edit.
setup nu; git -C "${ROOT}/nu" branch -q --unset-upstream
rc=0; out="$(at nu reconcile)" || rc=$?
check "no upstream: a merged item is marked done, not left in review" "0|done||yes" \
  "${rc}|$(val "${ROOT}/nu/docs/stories/a.md" status)|$(git -C "${ROOT}/nu" status --porcelain)|$(has "merged: a, marked done" "${out}")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
