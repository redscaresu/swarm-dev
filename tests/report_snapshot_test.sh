#!/usr/bin/env bash
# report_snapshot_test.sh — a report (status, next, each dash frame) reads the board's files once, at
# report_start (board_snapshot), and fm and get_fm answer from that read.
# - On a fixture board with state files (a key set in state, a @base the item no longer matches, a key
#   only in a story's body, an empty value, a value cleared in state, a key in state that swarm.sh does
#   not write, two names that differ only in - and _2d, a name the snapshot leaves out), fm, get_fm and
#   get_fm_or_gone give the same output for every key of every story, epic and HLD file with the
#   snapshot as without it, and the values are the ones the rules give.
# - Those reads, made again and again with the snapshot, start no sed, awk, head or other process the
#   PATH wrapper counts.
# - A state_set made in a $( ) subshell during the report is seen by the next fm in the parent shell; a
#   story file made after the snapshot is read from disk; one gone since reads as gone.
# - On a board of epics with an after: lead story, a story with no epic and a kind: set in state,
#   epic_stories gives the same stories in the same order for every epic with the snapshot as without
#   it, from its story-to-epic index (board_snap_index), starting no counted process. A state_set of
#   kind: in a $( ) subshell during the report drops the index, and the next epic_stories reads it.
# - During one `status` (outside herdr) on fixture boards of 20 stories in 5 epics and 60 in 15, the
#   basename, sed, awk and head runs grow per added story by at most GROWTH_BOUND.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWARM="${REPO}/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" TMPDIR="${ROOT}/tmp"
mkdir -p "${TMPDIR}" "${ROOT}/bin" "${ROOT}/count"
# GROWTH_BOUND: the basename, sed, awk and head runs one status may add per added story. Each grew by
# tens a story: before the snapshot, as fm and get_fm ran sed, head or awk on every read; then as board
# and the report loops ran basename on every item, in walks made once per epic or per story in review.
GROWTH_BOUND=2.5

# The counting wrappers: each logs its name to COUNT_LOG, then runs the real program.
COUNTED="sed awk head basename perl cat rm mkdir mv grep tr wc"
# shellcheck disable=SC2016 # the wrappers' lines are literal
for t in ${COUNTED}; do
  printf '#!/bin/sh\necho %s >> "${COUNT_LOG:-/dev/null}"\nexec %s "$@"\n' "${t}" "$(command -v "${t}")" > "${ROOT}/count/${t}"
  chmod +x "${ROOT}/count/${t}"
done
# shellcheck disable=SC2016 # the stub's lines are literal
printf '#!/bin/sh\ncase "$1 $2" in "pr list") echo "[]" ;; esac\nexit 0\n' > "${ROOT}/bin/gh"
cp "${REPO}/tests/claude_stub.sh" "${ROOT}/bin/claude"
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/claude"

fails=0
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
holds() {
  if awk -v a="$3" -v b="$4" "BEGIN { exit !($2) }"; then echo "ok   $1"
  else echo "FAIL $1: $2 with a=$3, b=$4"; fails=$((fails + 1)); fi
}

# --- The fixture board: E's docs/{stories,epics,hld} and .swarm/board-state.
E="${ROOT}/eq"; B="${E}/docs"; ST="${E}/.swarm/board-state"
mkdir -p "${B}/stories" "${B}/epics" "${B}/hld" "${ST}/stories" "${ST}/epics" "${ST}/hld"
put() { printf '%s\n' "${@:2}" > "${B}/$1"; }
# a: status and prs set in state over the file's values (prs's @base empty, as the file's value is);
# epic in state, a key swarm.sh never writes there, is ignored; owner only in the body; a status in the
# body comes after the front matter's.
put stories/a.md --- 'status: ready' 'kind: code' 'epic: e' 'prs:' 'depends_on: []' --- '' '# a' \
  'owner: body-only' 'status: in-body'
printf 'status: review\nstatus@base: ready\nprs: https://github.com/o/r/pull/1\nprs@base:\nepic: other\n' > "${ST}/stories/a"
# b: a status@base the file no longer has (the file's value wins); held_by cleared in state, over a
# held_by line in the body.
put stories/b.md --- 'status: ready' 'kind:    code' 'title: spaced   ' --- '' 'held_by: body-val'
printf 'status: review\nstatus@base: blocked\nheld_by:\nheld_by@base:\n' > "${ST}/stories/b"
# c: no front matter; d: a third --- and a key after the front matter's end.
put stories/c.md 'status: loose' 'kind: code'
put stories/d.md --- 'status: done' --- 'kind: late' --- 'epic: later'
# Two names the snapshot's encoding must keep apart, and one it leaves out (a space).
# shellcheck disable=SC2016 # a value that must never run
put stories/x-y.md --- 'status: ready' 'note: it'"'"'s $(touch '"${ROOT}"'/pwned) a=b' ---
put stories/x_2dy.md --- 'status: blocked' ---
put 'stories/odd name.md' --- 'status: ready' ---
# An epic with the slug a, with a state of its own; an HLD, with a state file swarm.sh never reads.
put epics/a.md --- 'status: active' 'hld: h' ---
printf 'status: done\nstatus@base: active\n' > "${ST}/epics/a"
put hld/h.md --- 'status: agreed' 'grants: [epics]' ---
printf 'status: draft\n' > "${ST}/hld/h"

# bs <command>... — <command> in a shell with board.sh loaded on E's board, the counting wrappers first
# on PATH.
# shellcheck source=/dev/null disable=SC2030,SC2317,SC2329 # die is board.sh's, called from there
bs() { (export PATH="${ROOT}/count:${ROOT}/bin:${PATH}" BOARD="${B}" PROJECT_DIR="${E}"
  die() { echo "swarm: $*" >&2; exit 1; }
  . "${REPO}/bin/lib/board.sh"; "$@"); }

# KEYS — every key named in a line of the fixture's files, those swarm.sh writes, and one no file has.
KEYS="missing $(cat "${B}"/*/*.md "${ST}"/*/* | sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)\(@base\)*:.*/\1/p' | sort -u | tr '\n' ' ')"
# reads [held] — every key (KEYS and SET_FM_KEYS) of every story, epic and HLD file through fm, get_fm
# and get_fm_or_gone: "<file> <key> F=<fm> G=<get_fm> O=<get_fm_or_gone>:<status>" lines. With held,
# only the files the snapshot holds: not odd name.md, which it leaves out, so its reads run sed and awk.
reads() {
  local f k o rc
  for f in "${B}"/stories/*.md "${B}"/epics/*.md "${B}"/hld/*.md; do
    [[ -z "${1:-}" || "${f}" != *" "* ]] || continue
    for k in ${KEYS} ${SET_FM_KEYS}; do
      rc=0; o="$(get_fm_or_gone "${f}" "${k}")" || rc=$?
      printf '%s %s F=%s G=%s O=%s:%s\n' "${f#"${B}/"}" "${k}" "$(fm "${f}" "${k}")" "$(get_fm "${f}" "${k}")" "${o}" "${rc}"
    done
  done
}
# equal — reads without the snapshot, then with it, into plain and snap; the held files' reads twice
# more with it, the counted runs logged to $1; then the values the rules give, with the snapshot.
equal() {
  reads > "${ROOT}/plain"
  board_snapshot "${ROOT}/mark" || { echo "board_snapshot failed" >&2; return 1; }
  reads > "${ROOT}/snap"
  COUNT_LOG="$1" reads held > "${ROOT}/held"
  COUNT_LOG="$1" reads held > "${ROOT}/held2"
  [[ -n "${BOARD_SNAP}" ]] || echo "the snapshot was dropped" >&2
  local s="${B}/stories"
  printf '%s|' "$(fm "${s}/a.md" status)" "$(get_fm "${s}/a.md" prs)" "$(fm "${s}/a.md" epic)" "$(fm "${s}/a.md" owner)" \
    "$(get_fm "${s}/a.md" owner)" "$(fm "${s}/b.md" status)" "$(fm "${s}/b.md" held_by)" "$(get_fm "${s}/b.md" kind)" \
    "$(fm "${s}/b.md" title)" "$(fm "${s}/c.md" status)" "$(get_fm "${s}/c.md" status)" "$(get_fm "${s}/d.md" kind)" \
    "$(fm "${s}/d.md" epic)" "$(fm "${s}/x-y.md" note)" "$(fm "${s}/x_2dy.md" status)" "$(fm "${B}/epics/a.md" status)" \
    "$(get_fm "${B}/hld/h.md" status)"
}
: > "${ROOT}/snap-count"
vals="$(bs equal "${ROOT}/snap-count")"
is "with the snapshot, fm, get_fm and get_fm_or_gone give every key of every file as without it" \
  "$(cat "${ROOT}/plain")" "$(cat "${ROOT}/snap")"
is "read twice more with the snapshot, the held files give the same as without it" \
  "$(grep -v '^stories/odd name.md ' "${ROOT}/plain")|$(grep -v '^stories/odd name.md ' "${ROOT}/plain")" \
  "$(cat "${ROOT}/held")|$(cat "${ROOT}/held2")"
is "the reads give the values the rules give: state over the file, a stale @base and the file wins, a key only in a body, a cleared key" \
  "review|https://github.com/o/r/pull/1|e|body-only||ready||code|spaced   |loose|||later|it's \$(touch ${ROOT}/pwned) a=b|blocked|done|agreed|" \
  "${vals}"
is "a value is never run as a command" "" "$(ls "${ROOT}/pwned" 2>/dev/null || true)"
is "the reads of the files the snapshot holds, $(( $(wc -l < "${ROOT}/held") * 6 )) of them, start no counted process (${COUNTED}) with the snapshot" \
  "" "$(sort "${ROOT}/snap-count" | uniq -c | tr -s ' \n' '  ')"

# --- A write during the report, and files made or gone after the snapshot.
# shellcheck disable=SC2329 # run through bs
after() {
  local s="${B}/stories" out
  board_snapshot "${ROOT}/mark2" || return 1
  out="$(state_set "${s}/a.md" status 'done')"
  printf '%s|' "${out}" "$(fm "${s}/a.md" status)" "$(get_fm "${s}/a.md" status)"
  board_snapshot "${ROOT}/mark3" || return 1
  put stories/new.md --- 'status: ready' ---
  rm -f "${s}/c.md"
  local rc=0; get_fm_or_gone "${s}/c.md" status > /dev/null || rc=$?
  printf '%s|' "$(fm "${s}/new.md" status)" "$(fm "${s}/c.md" status)" "${rc}"
}
# odd — a board with only a name the snapshot leaves out: the snapshot reads none of stdin, and holds
# no variable.
# shellcheck disable=SC2329 # run through bs
odd() {
  local l=""
  mkdir -p "${ROOT}/odd/stories"; printf -- '---\nstatus: ready\n---\n' > "${ROOT}/odd/stories/a b.md"
  BOARD="${ROOT}/odd"
  { board_snapshot "${ROOT}/mark4"; IFS= read -r l || true; } <<< "left for the caller"
  printf '%s|%s|' "${l}" "$(compgen -v _BS_ | wc -l | tr -d ' ')"
}
is "a board of names the snapshot leaves out: the caller's stdin is left to it, and no value is held" \
  "left for the caller|0|" "$(bs odd)"
is "a state_set in a \$( ) subshell is seen by the parent's next fm and get_fm; a story made after the snapshot is read; one gone reads as gone" \
  "|done|done|ready||3|" "$(bs after)"

# --- epic_stories from the snapshot's story-to-epic index (board_snap_index).
# W: epics w1 and w2; in board order a code story of each, an after: lead story of w1 (waits on it, so
# counts in none), a lead story whose after: names another epic (counts in w1), a story with no epic, a
# story whose kind: lead is in state (after: w2, so it counts in none), and one whose epic: is only in
# its body (fm's rule: it counts in w2).
W="${ROOT}/w"
mkdir -p "${W}/docs/stories" "${W}/docs/epics" "${W}/.swarm/board-state/stories"
wput() { printf '%s\n' "${@:2}" > "${W}/docs/$1"; }
wput epics/w1.md --- 'status: active' ---
wput epics/w2.md --- 'status: active' ---
wput stories/a1.md --- 'kind: code' 'epic: w1' 'status: ready' ---
wput stories/a2.md --- 'kind: code' 'epic: w2' 'status: ready' ---
wput stories/b-after.md --- 'kind: lead' 'epic: w1' 'after: w1' 'status: ready' ---
wput stories/c_other.md --- 'kind: lead' 'epic: w1' 'after: [w2]' 'status: ready' ---
wput stories/d.md --- 'kind: code' 'status: ready' ---
wput stories/e.md --- 'kind: code' 'epic: w2' 'after: w2' 'status: ready' ---
printf 'kind: lead\nkind@base: code\n' > "${W}/.swarm/board-state/stories/e"
wput stories/f.md --- 'kind: code' 'status: ready' --- '' 'epic: w2'
wput stories/README.md '# stories'
# ws <command>... — bs on board W.
# shellcheck source=/dev/null disable=SC2030,SC2031,SC2317,SC2329 # die is board.sh's, called from there
ws() { (export PATH="${ROOT}/count:${ROOT}/bin:${PATH}" BOARD="${W}/docs" PROJECT_DIR="${W}"
  die() { echo "swarm: $*" >&2; exit 1; }
  . "${REPO}/bin/lib/board.sh"; "$@"); }
# walks — epic_stories for every epic of W, one with none and "": "<epic>: <names>" lines.
walks() {
  local e
  for e in w1 w2 none ""; do printf '%s: %s\n' "${e}" "$(epic_stories "${e}" | sed 's|.*/||' | tr '\n' ' ')"; done
}
# shellcheck disable=SC2329 # run through ws
index_walks() {
  walks > "${ROOT}/walk-plain"
  board_snapshot "${ROOT}/wmark" || return 1
  local e
  # The lookups alone counted, and fm's calls in them: the index answers with no fm read (sed in walks
  # names the files, after the count). The walk it replaced runs no counted process either, as
  # board names its files with no basename, but it calls fm on every story.
  eval "fm_real() $(declare -f fm | sed 1d)"
  fm() { [[ -z "${FM_LOG:-}" ]] || echo "fm $1" >> "${FM_LOG}"; fm_real "$@"; }
  for e in w1 w2 none; do COUNT_LOG="${ROOT}/walk-count" FM_LOG="${ROOT}/walk-fm" epic_stories "${e}" > /dev/null; done
  walks > "${ROOT}/walk-snap"
}
: > "${ROOT}/walk-count"; : > "${ROOT}/walk-fm"
ws index_walks
is "epic_stories gives every epic's stories in board order: an after: lead story of its own epic counts in none, one naming another epic counts, kind: lead in state holds one back" \
  "w1: a1.md c_other.md |w2: a2.md f.md |none: |: d.md |" "$(tr '\n' '|' < "${ROOT}/walk-plain")"
is "epic_stories gives the same stories in the same order for every epic with the snapshot as without it" \
  "$(cat "${ROOT}/walk-plain")" "$(cat "${ROOT}/walk-snap")"
is "with the snapshot, epic_stories for each epic starts no counted process (${COUNTED})" \
  "" "$(sort "${ROOT}/walk-count" | uniq -c | tr -s ' \n' '  ')"
is "with the snapshot, epic_stories answers from the index: no fm read of a story" \
  0 "$(grep -c '/stories/' "${ROOT}/walk-fm" || true)"

# A state_set of kind: during the report, in a $( ) subshell as a report makes it: a1 becomes an
# after: lead story of w1 (its after: is in the file), so it no longer counts in w1. Then a story made
# after the snapshot is read from its file, while the snapshot holds.
# shellcheck disable=SC2329 # run through ws
index_write() {
  local out
  wput stories/a1.md --- 'kind: code' 'epic: w1' 'after: w1' 'status: ready' ---
  board_snapshot "${ROOT}/wmark2" || return 1
  printf '%s|' "$(epic_stories w1 | sed 's|.*/||' | tr '\n' ' ')"
  out="$(state_set "${W}/docs/stories/a1.md" kind lead)"
  printf '%s|%s|' "${out}" "$(epic_stories w1 | sed 's|.*/||' | tr '\n' ' ')"
  board_snapshot "${ROOT}/wmark3" || return 1
  wput stories/g.md --- 'kind: code' 'epic: w1' ---
  printf '%s|%s|' "$(epic_stories w1 | sed 's|.*/||' | tr '\n' ' ')" "${BOARD_SNAP:+held}"
}
is "a state_set of kind: during the report drops the index, and the next epic_stories reads the new kind; a story made after the snapshot is read from its file" \
  "a1.md c_other.md ||c_other.md |c_other.md g.md |held|" "$(ws index_write)"

# --- status's basename, sed, awk and head runs on 20 and 60 stories.
# board <n> — a project of <n> stories, in <n>/4 epics under an agreed HLD: ready, blocked on the one
# before, in review through state, done, in turn.
board() {
  local P="${ROOT}/p$1" i e ne=$(( $1 / 4 ))
  mkdir -p "${P}/docs/stories" "${P}/docs/epics" "${P}/docs/hld" "${P}/.swarm/board-state/stories"
  git -C "${P}" init -q -b main
  it() { { echo ---; printf '%s\n' "${@:3}"; echo ---; echo; echo "# $2"; } > "${P}/docs/$1/$2.md"; }
  it hld h 'status: agreed' 'grants: [epics]'
  for ((e = 1; e <= ne; e++)); do it epics "e${e}" 'status: active' 'hld: h'; done
  for ((i = 1; i <= $1; i++)); do
    e=$(( i % ne + 1 ))
    case $(( i % 4 )) in
      0) it stories "s${i}" 'kind: code' "epic: e${e}" 'status: ready' 'depends_on: []' ;;
      1) it stories "s${i}" 'kind: code' "epic: e${e}" 'status: blocked' "depends_on: [s$(( i > 1 ? i - 1 : 1 ))]" ;;
      2) it stories "s${i}" 'kind: code' "epic: e${e}" 'status: ready' 'depends_on: []'
         printf 'status: review\nstatus@base: ready\nprs: https://github.com/o/r/pull/%s\nprs@base:\n' "${i}" > "${P}/.swarm/board-state/stories/s${i}" ;;
      3) it stories "s${i}" 'kind: code' "epic: e${e}" 'status: done' 'depends_on: []' ;;
    esac
  done
  git -C "${P}" -c user.name=t -c user.email=t@t add -A
  git -C "${P}" -c user.name=t -c user.email=t@t commit -qm init
}
# runs <n> — the basename, sed, awk and head runs of one status on board <n>; its output goes to ${ROOT}/out<n>.
runs() {
  : > "${ROOT}/count$1"
  # shellcheck disable=SC2031 # PATH is the test's own here
  (cd "${ROOT}/p$1" && env -u HERDR_ENV -u HERDR_PANE_ID COUNT_LOG="${ROOT}/count$1" \
    PATH="${ROOT}/count:${ROOT}/bin:${PATH}" bash "${SWARM}" status > "${ROOT}/out$1" 2>&1) || echo "status on $1 stories failed: $(cat "${ROOT}/out$1")" >&2
  grep -cxE 'basename|sed|awk|head' "${ROOT}/count$1" || true
}
board 20; board 60
c20="$(runs 20)"; c60="$(runs 60)"
echo "status's basename, sed, awk and head runs: ${c20} on 20 stories, ${c60} on 60"
is "status on 60 stories lists the 15 in review" 15 "$(grep -c '^  awaiting your merge: ' "${ROOT}/out60" || true)"
holds "status's basename, sed, awk and head runs grow per added story by at most ${GROWTH_BOUND} (tens before the snapshot, and before board named its files with no basename)" \
  "(b - a) / 40 <= ${GROWTH_BOUND}" "${c20}" "${c60}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
