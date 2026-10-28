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
# state of the stories the pulled commits deleted, and of an epic whose deletion took docs/epics, and
# finishes a story in review whose PR merged: its builder closed, its build cleared (in its own repo
# too) and `reconcile <slug> ok (finished)` logged; a builder whose pane cannot be closed keeps it, and
# the story its state, until a later reconcile can close it. One whose PR is open, or whose file a later
# commit took out of review, only loses its state; one whose PR gh cannot read keeps it, and one whose
# state cannot be read stops reconcile. Inside herdr, a merged story's idle review agent,
# review-<slug>, closes with its builder, through reconcile's merged arm and drop_gone_state's; run
# from its own pane (swarm.sh merge there, or reconcile), it is retired instead, and a later tidy
# --yes closes it, leaving no tab of the story.
# gh, herdr and claude are stubs on PATH; origin is a local bare repo.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

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
printf '%s\n' "${U}/1 MERGED" "${U}/2 OPEN" "${U}/3 MERGED" "${U}/4 OPEN" "${U}/5 MERGED" > "${ROOT}/prs"
# herdr logs each call to herdr.log; agent list gives the agents in ROOT/agents ("<name> <pane>"
# lines), and pane close drops the pane's agent, or fails while ROOT/stuck is there. Only the cases
# that set HERDR_ENV=1 reach it.
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
case "$1 $2" in
  "agent list") printf '{"result":{"agents":['   # vacuous-test: ok, the list's head; awk and echo print the rest
                awk '{ printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }' "$H/agents" 2>/dev/null
                echo ']}}' ;;
  "pane close") [ -e "$H/stuck" ] && exit 1
                awk -v p="$3" '$2 != p' "$H/agents" > "$H/agents.tmp" && mv "$H/agents.tmp" "$H/agents" ;;
  *) echo "stub herdr: unexpected $*" >&2; exit 1 ;;
esac
EOF
chmod +x "${ROOT}/bin/herdr"

item() { # <file> <front-matter line>...
  local path="$1" title; shift
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}
at() { local d="${ROOT}/$1"; shift; (cd "${d}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
# in_herdr <name> <args> — at, inside herdr: the herdr stub answers.
in_herdr() { local d="${ROOT}/$1"; shift; (cd "${d}" && env -u SWARM_PROJECT -u HERDR_PANE_ID HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
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
check "a leftover status: review gives way to the PR's status: done, and the pull goes, with no incident" "0|$(git -C "${ROOT}/kc.git" rev-parse main)||done||yes|no|no" \
  "${rc}|$(git -C "${ROOT}/kc" rev-parse HEAD)|$(git -C "${ROOT}/kc" status --porcelain)|$(val "${ROOT}/kc/docs/stories/e.md" status)|$(val "${ROOT}/kc/docs/stories/e.md" prs)|$(has "merged: e" "${out}")|$(if grep -qs incident "${ROOT}/kc/.swarm/events.tsv"; then echo yes; else echo no; fi)|$(if grep -q "set it again" <<< "${out}"; then echo yes; else echo no; fi)"

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

# built <name> <slug> — <slug> built in <name> as story builds it: its worktree <name>-wt/<slug> on
# story/<slug>, pushed to origin.
built() {
  local d="${ROOT}/$1"
  "${GIT[@]}" -C "${d}" worktree add -q -b "story/$2" "${d}-wt/$2"
  "${GIT[@]}" -C "${d}-wt/$2" commit -q --allow-empty -m "$2" && "${GIT[@]}" -C "${d}-wt/$2" push -q origin "story/$2"
}
# pulled <name> — setup <name>, with a built and its builder open in herdr on pane w:1, recorded in a
# tab beside w:0.
pulled() {
  local d="${ROOT}/$1"
  setup "$1"; built "$1" a
  mkdir -p "${d}/.swarm/state"; printf '%s\n' "w:0" "w:1 a" > "${d}/.swarm/state/a"
  echo "a w:1" > "${ROOT}/agents"; : > "${ROOT}/herdr.log"; rm -f "${ROOT}/stuck"
}
# left <repo> <slug> — what is left of a build: its worktree, story/<slug> in <repo> and on its origin.
left() {
  echo "$([[ -e "${ROOT}/$1-wt/$2" ]] && echo worktree) $(git -C "${ROOT}/$1" show-ref -q --verify "refs/heads/story/$2" && echo branch) $(git -C "${ROOT}/$1.git" show-ref -q --verify "refs/heads/story/$2" && echo origin)"
}
finished() { awk -F'\t' '$2 == "reconcile" && $5 == "ok (finished)" { printf "%s ", $3 }' "${ROOT}/$1/.swarm/events.tsv" 2>/dev/null; }

# --- The base pulled by hand after the PRs of a and b merged and deleted them, before reconcile saw
# either: reconcile finishes both after the fact. a's builder is closed and its build cleared here and
# on origin; b's build is cleared in svc, the repo its deleted file named. d, dropped by a board PR,
# only loses its state, and e, still on the board, keeps its. Three more, each built or in review, go
# in the same pull: c, its PR open, dropped by a board PR; f, its PR merged, but set later by a commit
# before another removed it; and g, whose PR gh cannot read.
pulled pf
"${GIT[@]}" init -q --bare "${ROOT}/svc.git"; "${GIT[@]}" clone -q "${ROOT}/svc.git" "${ROOT}/svc" 2>/dev/null
"${GIT[@]}" -C "${ROOT}/svc" commit -q --allow-empty -m init && "${GIT[@]}" -C "${ROOT}/svc" push -q origin main
"${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b story/b "${ROOT}/svc-wt/b"
"${GIT[@]}" -C "${ROOT}/svc-wt/b" commit -q --allow-empty -m b && "${GIT[@]}" -C "${ROOT}/svc-wt/b" push -q origin story/b
item "${ROOT}/pf-up/docs/stories/b.md" "status: ready" "kind: code" "repo: svc"
for x in c f g; do item "${ROOT}/pf-up/docs/stories/${x}.md" "status: ready" "kind: code"; done
"${GIT[@]}" -C "${ROOT}/pf-up" add docs && "${GIT[@]}" -C "${ROOT}/pf-up" commit -q -m "add b c f g" && "${GIT[@]}" -C "${ROOT}/pf-up" push -q origin main
git -C "${ROOT}/pf" pull -q --ff-only
at pf review b "${U}/3" >/dev/null; at pf review c "${U}/4" >/dev/null; at pf review f "${U}/5" >/dev/null; at pf review g "${U}/6" >/dev/null
built pf c; built pf f
perl -pi -e 's|^status: ready$|status: later|' "${ROOT}/pf-up/docs/stories/f.md"
"${GIT[@]}" -C "${ROOT}/pf-up" commit -q -am "f later"
for x in b c f g; do "${GIT[@]}" -C "${ROOT}/pf-up" rm -q "docs/stories/${x}.md" && "${GIT[@]}" -C "${ROOT}/pf-up" commit -q -m "take ${x} off"; done
"${GIT[@]}" -C "${ROOT}/pf-up" push -q origin main
git -C "${ROOT}/pf" pull -q --ff-only
rc=0; out="$(in_herdr pf reconcile)" || rc=$?
check "a merged story whose file a pull already removed: its builder is closed and its build cleared" "0|yes|yes|  " \
  "${rc}|$(has "pane close w:1" "$(cat "${ROOT}/herdr.log")")|$(has "closed pane a" "${out}")|$(left pf a)"
check "one in another repo has its build cleared there, and both are logged finished" "  |a b |yes" \
  "$(left svc b)|$(finished pf)|$(has "merged: b, its file already pulled off the board" "${out}")"
check "and the state goes: a's and b's, and d's, dropped with no finish; e keeps its" "gone|gone|gone|there" \
  "$(state pf a)|$(state pf b)|$(state pf d)|$(state pf e)"
check "c, its PR open and dropped by a board PR, only loses its state: its build stays, and it is not finished" "gone|worktree branch origin|a b " \
  "$(state pf c)|$(left pf c)|$(finished pf)"
check "f, which a later commit set later before another removed it, reads later, so it only loses its state" "gone|worktree branch origin" \
  "$(state pf f)|$(left pf f)"
check "g, whose PR gh cannot read, keeps its state, and reconcile names what to remove if gh never can" "there|yes" \
  "$(state pf g)|$(has "remove ${ROOT}/pf/.swarm/board-state/stories/g, and ${ROOT}/pf/.swarm/escalated/g if it is there, by hand" "${out}")"

# --- The same, but a's builder pane cannot be closed: it may still be working there, so its worktree
# and story/a stay, here and on origin, and reconcile says so. a keeps its state and its escalated
# block, and is not logged finished; once the pane closes, the next reconcile finishes it.
pulled pk; git -C "${ROOT}/pk" pull -q --ff-only; touch "${ROOT}/stuck"
mkdir -p "${ROOT}/pk/.swarm/escalated"; echo "**Escalated.** a failed twice." > "${ROOT}/pk/.swarm/escalated/a"
rc=0; out="$(in_herdr pk reconcile)" || rc=$?
rm -f "${ROOT}/stuck"
check "a builder whose pane cannot be closed keeps its worktree and branch, and reconcile says once that the next one clears them" "0|worktree branch origin|1|yes|a w:1" \
  "${rc}|$(left pk a)|$(grep -c '^build kept:' <<< "${out}")|$(has "build kept: a's builder pane is still open, so its worktree and story/a stay, and so does its state; the next reconcile clears them once that pane closes" "${out}")|$(cat "${ROOT}/agents")"
check "and a keeps its state and escalated block for the next reconcile, not yet finished, its pane tried once" "there|there||1" \
  "$(state pk a)|$([[ -e "${ROOT}/pk/.swarm/escalated/a" ]] && echo there || echo gone)|$(finished pk)|$(grep -c '^pane close w:1$' "${ROOT}/herdr.log")"
rc=0; in_herdr pk reconcile >/dev/null || rc=$?
check "once the pane closes, the next reconcile closes it, clears the build and finishes a" "0|  |a |gone|gone" \
  "${rc}|$(left pk a)|$(finished pk)|$(state pk a)|$([[ -e "${ROOT}/pk/.swarm/escalated/a" ]] && echo there || echo gone)"

# --- The same pull by hand, but a's board state cannot be read: reconcile stops, naming the file and
# logging why, and leaves a as it was (its state and build, not finished). Read as its deleted copy, a
# would be ready, and dropped.
setup pu; built pu a; git -C "${ROOT}/pu" pull -q --ff-only
chmod a-r "${ROOT}/pu/.swarm/board-state/stories/a"
rc=0; out="$(at pu reconcile)" || rc=$?
[[ ! -e "${ROOT}/pu/.swarm/board-state/stories/a" ]] || chmod u+r "${ROOT}/pu/.swarm/board-state/stories/a"   # gone if reconcile dropped it
check "a's board state cannot be read: reconcile stops naming it and logs why; a keeps its state and build, not finished" \
  "1|yes|yes|there|worktree branch origin|" \
  "${rc}|$(has "board state: cannot read ${ROOT}/pu/.swarm/board-state/stories/a; make it readable" "${out}")|$(has "reconcile: a, pulled off the board, has a board state that cannot be read" "$(awk -F'\t' '$2 == "reconcile" { o = $5 } END { print o }' "${ROOT}/pu/.swarm/events.tsv")")|$(state pu a)|$(left pu a)|$(finished pu)"

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

# setup_root <name> — a bare origin whose board is the project root (board_dir = .), with stories e,
# x and y, .swarm/ ignored; its main checkout <name>; and a clone <name>-up.
setup_root() {
  local d="${ROOT}/$1"
  "${GIT[@]}" init -q --bare "${d}.git"
  "${GIT[@]}" clone -q "${d}.git" "${d}" 2>/dev/null
  mkdir -p "${d}/.claude/swarm"; echo "board_dir = ." > "${d}/.claude/swarm/config"
  item "${d}/stories/e.md" "status: ready" "kind: code"
  item "${d}/stories/x.md" "status: ready" "kind: code"
  item "${d}/stories/y.md" "status: ready" "kind: code"
  echo ".swarm/" > "${d}/.gitignore"
  "${GIT[@]}" -C "${d}" add .gitignore .claude stories && "${GIT[@]}" -C "${d}" commit -q -m board && "${GIT[@]}" -C "${d}" push -q origin main
  "${GIT[@]}" clone -q "${d}.git" "${d}-up"
}
# --- A board at the root: e's key edit (the pull changes e) moves to its state and the pull goes,
# and y, removed by hand but still in HEAD, keeps its state.
setup_root ra
echo "the base's line" >> "${ROOT}/ra-up/stories/e.md"
"${GIT[@]}" -C "${ROOT}/ra-up" commit -q -am "edit e" && "${GIT[@]}" -C "${ROOT}/ra-up" push -q origin main
perl -pi -e 's|^status: .*$|status: review\nprs: '"${U}/2"'|' "${ROOT}/ra/stories/e.md"
mkdir -p "${ROOT}/ra/.swarm/board-state/stories"; printf '%s\n' "status: blocked" "status@base: ready" > "${ROOT}/ra/.swarm/board-state/stories/y"
rm "${ROOT}/ra/stories/y.md"
rc=0; at ra reconcile >/dev/null || rc=$?
check "a root board: e's key edit moves to its state, the pull goes, and y keeps its state" "0|$(git -C "${ROOT}/ra.git" rev-parse main)| D stories/y.md|status: review|there" \
  "${rc}|$(git -C "${ROOT}/ra" rev-parse HEAD)|$(git -C "${ROOT}/ra" status --porcelain)|$(grep -x 'status: review' "${ROOT}/ra/.swarm/board-state/stories/e")|$(state ra y)"
# --- A root board: a hand edit to x, which the pull changes too, is named as a board file.
setup_root rx
echo "the base's line" >> "${ROOT}/rx-up/stories/x.md"
"${GIT[@]}" -C "${ROOT}/rx-up" commit -q -am "edit x" && "${GIT[@]}" -C "${ROOT}/rx-up" push -q origin main
echo "a local note" >> "${ROOT}/rx/stories/x.md"
rc=0; out="$(at rx reconcile)" || rc=$?
check "a root board: a hand edit the pull changes too is named as a board file" "1|yes" \
  "${rc}|$(has "board files are changed here: stories/x.md; land each edit through swarm.sh board-pr" "${out}")"
# --- One reconcile at a time: a die inside frees the lock and is still the logged outcome, and a held
# lock makes the next one wait, then stop naming it.
check "a reconcile that dies frees its lock, and logs why" "gone|yes" \
  "$(gone "${ROOT}/rx/.swarm/reconcile.lock")|$(has "reconcile: cannot pull" "$(tail -1 "${ROOT}/rx/.swarm/events.tsv")")"
mkdir "${ROOT}/ra/.swarm/reconcile.lock"
rc=0; out="$(SWARM_RECONCILE_WAIT=1 at ra reconcile)" || rc=$?
check "a reconcile while another holds the lock waits, then stops naming it" "1|yes|there" \
  "${rc}|$(has "${ROOT}/ra/.swarm/reconcile.lock is still there after 1s" "${out}")|$([[ -d "${ROOT}/ra/.swarm/reconcile.lock" ]] && echo there || echo gone)"
# --- A root board: a hand edit off its own paths (board_paths), which the pull changes too, is named as
# a file outside the board, not as a board file.
setup_root ro
echo "notes/" >> "${ROOT}/ro-up/.gitignore"
"${GIT[@]}" -C "${ROOT}/ro-up" commit -q -am "ignore notes" && "${GIT[@]}" -C "${ROOT}/ro-up" push -q origin main
echo "local/" >> "${ROOT}/ro/.gitignore"
rc=0; out="$(at ro reconcile)" || rc=$?
check "a root board: a hand edit off its own paths is named as outside the board" "1|yes|no" \
  "${rc}|$(has "files outside the board are changed here: .gitignore; commit or move each change" "${out}")|$(grep -qF "board files are changed here" <<< "${out}" && echo yes || echo no)"

# herdr_stub <dir> — a herdr and a claude in <dir>/bin, herdr's state in <dir>/h: tabs ("<tab>
# <label>"), panes ("<pane> <tab>") and agents ("<name> <pane> <status>"). A pane close takes its
# agent, and its tab once no pane is left there, as herdr does; a tab close takes its panes and their
# agents. agent list fails while h/listfail is there, and a close of the pane h/closefail names, or
# of its tab, fails. claude lists no session (claude_stub.sh), so herdr's status answers for each agent.
herdr_stub() {
  mkdir -p "$1/bin" "$1/h"
  printf '#!/bin/sh\nH="%s"\n' "$1/h" > "$1/bin/herdr"
  cat >> "$1/bin/herdr" <<'STUB'
drop() { awk -v k="$2" -v c="$3" '$c != k' "$H/$1" > "$H/$1.tmp" && mv "$H/$1.tmp" "$H/$1"; }
# list <file> <key>... — the file's lines as herdr's JSON list of that name, a key per field.
list() { f="$1"; shift; awk -v w="${f}" -v k="$*" 'BEGIN { n = split(k, key, " "); printf "{\"result\":{\"%s\":[", w }
  { printf "%s{", (NR > 1 ? "," : ""); for (i = 1; i <= n; i++) printf "%s\"%s\":\"%s\"", (i > 1 ? "," : ""), key[i], $i; printf "}" }
  END { print "]}}" }' "$H/${f}"; }
case "$1 $2" in
  "tab list") list tabs tab_id label ;;
  "pane list") list panes pane_id tab_id ;;
  "agent list") [ ! -e "$H/listfail" ] || exit 1; list agents name pane_id agent_status ;;
  "agent rename") awk -v p="$3" -v n="$4" '$2 == p { $1 = n } { print }' "$H/agents" > "$H/agents.tmp" && mv "$H/agents.tmp" "$H/agents" ;;
  "pane close") [ "$(cat "$H/closefail" 2>/dev/null)" != "$3" ] || exit 1
                t="$(awk -v p="$3" '$1 == p { print $2 }' "$H/panes")"; [ -n "$t" ] || exit 1
                drop panes "$3" 1; drop agents "$3" 2
                if ! awk -v t="$t" '$2 == t { f = 1 } END { exit !f }' "$H/panes"; then drop tabs "$t" 1; fi ;;
  "tab close") ! grep -qx "$(cat "$H/closefail" 2>/dev/null) $3" "$H/panes" || exit 1
               for p in $(awk -v t="$3" '$2 == t { print $1 }' "$H/panes"); do drop agents "$p" 2; done
               drop panes "$3" 2; drop tabs "$3" 1 ;;
esac
STUB
  cp "${SWARM%/bin/*}/tests/claude_stub.sh" "$1/bin/claude"
  chmod +x "$1/bin/herdr" "$1/bin/claude"
}
# lay <stub dir> <project> <slug> [epic] — the lead idle in w:lead (tab t0, in no tab record), and
# story <slug>'s builder (w:b) and idle review agent (w:r) in tab t1: its epic's, beside conduct-<epic>
# (w:c), or with no epic a tab of its own. The project's tab record for t1's label names them, and
# its agents.tsv starts review-<slug> with role review.
lay() {
  local h="$1/h" label="${4:-$3}"
  printf 't0 lead\nt1 %s\n' "${label}" > "${h}/tabs"
  printf 'lead w:lead idle\n%s w:b idle\nreview-%s w:r idle\n' "$3" "$3" > "${h}/agents"
  printf 'w:lead t0\nw:b t1\nw:r t1\n' > "${h}/panes"
  mkdir -p "$2/.swarm/state"; printf 'w:b %s\nw:r review-%s\n' "$3" "$3" > "$2/.swarm/state/${label}"
  printf '2026-10-26\treview\treview-%s\tclaude\tsonnet\thigh\t-\n' "$3" > "$2/.swarm/agents.tsv"
  if [[ -n "${4:-}" ]]; then
    echo "conduct-$4 w:c idle" >> "${h}/agents"; echo "w:c t1" >> "${h}/panes"; echo "w:c conduct-$4" >> "$2/.swarm/state/${label}"
  fi
}
# panes_in <stub dir> — herdr's panes now, as "<agent, else pane>@<tab label>", sorted, space-separated.
panes_in() {
  awk 'FILENAME ~ /tabs$/ { l[$1] = $2; next } FILENAME ~ /agents$/ { n[$2] = $1; next }
       { print (($1 in n) ? n[$1] : $1) "@" l[$2] }' "$1/h/tabs" "$1/h/agents" "$1/h/panes" | sort | paste -sd' ' -
}
HV="${ROOT}/hv"; herdr_stub "${HV}"
# hat <name> <pane> <args> — at, inside herdr, run from <pane>, with HV's herdr and claude.
hat() { local d="${ROOT}/$1" pane="$2"; shift 2; (cd "${d}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_PANE_ID="${pane}" PATH="${HV}/bin:${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }

# --- reconcile's merged arm, run from the lead's pane: a's PR merged, so its builder and its idle
# review agent close at once, and a's own tab and its record with them.
setup va; lay "${HV}" "${ROOT}/va" a
rc=0; out="$(hat va w:lead reconcile)" || rc=$?
check "the merged arm, from the lead's pane: a's builder and review agent close, and a's tab with them" "0|lead@lead|gone|yes" \
  "${rc}|$(panes_in "${HV}")|$(gone "${ROOT}/va/.swarm/state/a")|$(has "merged: a" "${out}")"

# --- A ready story slugged review-a, its builder open under that name (agents.tsv role code): a's
# merge leaves it alone, with no attempt counted, though its name is a's review agent's.
setup vb; lay "${HV}" "${ROOT}/vb" a; item "${ROOT}/vb/docs/stories/review-a.md" "status: ready" "kind: code"
printf '2026-10-26\tcode\treview-a\tclaude\tsonnet\thigh\t-\n' > "${ROOT}/vb/.swarm/agents.tsv"
rc=0; out="$(hat vb w:lead reconcile)" || rc=$?
check "a story slugged review-a keeps its open builder through a's merge, with no attempt counted" "0|lead@lead review-a@a|w:r review-a|" \
  "${rc}|$(panes_in "${HV}")|$(cat "${ROOT}/vb/.swarm/state/a" 2>/dev/null)|$(val "${ROOT}/vb/docs/stories/review-a.md" attempts)"

# --- review-a working when a's PR merged (its own merge waiting on CI, or a round still running): the
# lead's reconcile finishes a and closes its builder, but leaves review-a open, and says so.
setup vw; lay "${HV}" "${ROOT}/vw" a; perl -pi -e 's/^review-a w:r idle$/review-a w:r working/' "${HV}/h/agents"
rc=0; out="$(hat vw w:lead reconcile)" || rc=$?
check "a working review-a is left open, and said, while a is finished and its builder closed" "0|yes|lead@lead review-a@a|yes" \
  "${rc}|$(has "merged: a" "${out}")|$(panes_in "${HV}")|$(has "review-a is working, so it was left open; close it once it is done with swarm.sh close review-a" "${out}")"

# --- review-a's recorded session is one Claude Code no longer lists (gone), and herdr has it working:
# herdr's status answers, so it is left open, and said.
setup vg; lay "${HV}" "${ROOT}/vg" a; perl -pi -e 's/^review-a w:r idle$/review-a w:r working/' "${HV}/h/agents"
perl -pi -e 's/\t-$/\tsess-gone/' "${ROOT}/vg/.swarm/agents.tsv"
rc=0; out="$(hat vg w:lead reconcile)" || rc=$?
check "a review-a whose session is gone but herdr has working is left open, and said" "0|yes|lead@lead review-a@a|yes" \
  "${rc}|$(has "merged: a" "${out}")|$(panes_in "${HV}")|$(has "review-a is working, so it was left open" "${out}")"

# --- Two slugs that share their first 25 characters give their review agents one herdr name, cut at
# 32. A reconcile in the second's review pane that finishes the first leaves the second as it is:
# its tab record names it, not the first.
L="abcdefghijklmnopqrstuvwxy"; CUT="review-${L}"
setup vx; item "${ROOT}/vx/docs/stories/${L}-one.md" "status: ready" "kind: code"; at vx review "${L}-one" "${U}/3" >/dev/null
printf 't0 lead\nt1 %s-two\n' "${L}" > "${HV}/h/tabs"; printf 'w:lead t0\nw:r t1\n' > "${HV}/h/panes"
printf 'lead w:lead idle\n%s w:r idle\n' "${CUT}" > "${HV}/h/agents"
mkdir -p "${ROOT}/vx/.swarm/state"; echo "w:r review-${L}-two" > "${ROOT}/vx/.swarm/state/${L}-two"
printf '2026-10-26\treview\t%s\tclaude\tsonnet\thigh\t-\n' "${CUT}" > "${ROOT}/vx/.swarm/agents.tsv"
rc=0; out="$(hat vx w:r reconcile)" || rc=$?
check "a reconcile in review-<L>-two's pane, finishing <L>-one, leaves review-<L>-two as it is" "0|yes|lead@lead ${CUT}@${L}-two|w:r review-${L}-two" \
  "${rc}|$(has "deleted: ${ROOT}/vx/docs/stories/${L}-one.md" "${out}")|$(panes_in "${HV}")|$(cat "${ROOT}/vx/.swarm/state/${L}-two")"

# --- review-a's pane cannot be closed, or herdr cannot list its agents: reconcile still finishes a,
# and says review-a may be open, naming the close.
setup vc; lay "${HV}" "${ROOT}/vc" a; echo w:r > "${HV}/h/closefail"
rc=0; out="$(hat vc w:lead reconcile)" || rc=$?; rm -f "${HV}/h/closefail"
check "a review pane that cannot be closed is said, with the close to run" "0|yes|lead@lead review-a@a|yes" \
  "${rc}|$(has "merged: a" "${out}")|$(panes_in "${HV}")|$(has "review-a was left open (exit 1); close it with swarm.sh close review-a" "${out}")"
setup vl; lay "${HV}" "${ROOT}/vl" a; touch "${HV}/h/listfail"
rc=0; out="$(hat vl w:lead reconcile)" || rc=$?; rm -f "${HV}/h/listfail"
check "herdr with no agent list: reconcile says review-a may still be open" "0|yes|yes" \
  "${rc}|$(has "merged: a" "${out}")|$(has "review-a may still be open (herdr cannot list its agents); close its pane with swarm.sh close review-a" "${out}")"

# --- drop_gone_state's arm: a's file already pulled off the board by hand, its PR merged.
setup vd; git -C "${ROOT}/vd" pull -q --ff-only; lay "${HV}" "${ROOT}/vd" a
rc=0; out="$(hat vd w:lead reconcile)" || rc=$?
check "drop_gone_state's arm, from the lead's pane: a is finished, and its builder, review agent and tab close" "0|yes|lead@lead|gone|gone" \
  "${rc}|$(has "merged: a, its file already pulled off the board" "${out}")|$(panes_in "${HV}")|$(gone "${ROOT}/vd/.swarm/state/a")|$(state vd a)"

# --- The same arm, run from review-a's own pane: it stays open, retired as review-a-done, and a later
# tidy --yes from the lead's pane closes it, and a's tab with it.
setup vr; git -C "${ROOT}/vr" pull -q --ff-only; lay "${HV}" "${ROOT}/vr" a
rc=0; out="$(hat vr w:r reconcile)" || rc=$?
check "drop_gone_state's arm, from review-a's pane: the builder closes, and review-a stays open, retired" "0|lead@lead review-a-done@a|w:r review-a-done|gone" \
  "${rc}|$(panes_in "${HV}")|$(cat "${ROOT}/vr/.swarm/state/a" 2>/dev/null)|$(state vr a)"
rc=0; out="$(hat vr w:lead tidy --yes)" || rc=$?
check "and tidy --yes from the lead's pane closes it, leaving no tab of a" "0|lead@lead|gone" \
  "${rc}|$(panes_in "${HV}")|$(gone "${ROOT}/vr/.swarm/state/a")"

# --- swarm.sh merge run from review-s's pane, on merge_fixture.sh's project, in a subshell, since its
# helpers share these names: the merge's reconcile closes s's builder and leaves review-s open,
# retired, and tidy --yes from the lead's pane closes it. An epic story's tab keeps its conductor; a
# backlog story's own tab goes. In the background, so set -e holds inside it and a failed setup step
# fails the file; it exits with its count of failed checks.
merged_review_fails=0
( set -e
  ROOT="${ROOT}/m"; mkdir -p "${ROOT}"
  # shellcheck source=merge_fixture.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
  . "$(dirname "${BASH_SOURCE[0]}")/merge_fixture.sh"
  herdr_stub "${ROOT}"
  tidy() { rc=0; (cd "${P}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_PANE_ID=w:lead PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" tidy --yes > "${ROOT}/out" 2>&1) || rc=$?; }
  for epic in e ""; do
    what="${epic:+an epic story}"; what="${what:-a backlog story}"; label="${epic:-s}"
    fresh; rm -f "${P}"/.swarm/state/*; item s "status: review" "prs: ${URL}" ${epic:+"epic: ${epic}"}; lay "${ROOT}" "${P}" s "${epic}"
    merge HERDR_ENV=1 HERDR_PANE_ID=w:r "${URL}"
    is "${what}, merged from review-s's pane: s's builder closes, and review-s stays open, retired" \
      "0|${epic:+conduct-e@e }lead@lead review-s-done@${label}|yes" \
      "${rc}|$(panes_in "${ROOT}")|$(grep -qx 'w:r review-s-done' "${P}/.swarm/state/${label}" && echo yes)"
    tidy
    is "${what}: tidy --yes from the lead's pane closes review-s-done, leaving no tab of s" \
      "0|${epic:+conduct-e@e }lead@lead|${epic:+w:c conduct-e}" "${rc}|$(panes_in "${ROOT}")|$(cat "${P}/.swarm/state/${label}" 2>/dev/null)"
  done
  exit "${fails}"
) &
wait $! || merged_review_fails=$?
fails=$((fails + merged_review_fails))

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
