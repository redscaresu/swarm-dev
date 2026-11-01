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
# - During one `status` (outside herdr) on fixture boards of 20 and 60 stories, the sed, awk and head runs
#   grow per added story by at most GROWTH_BOUND, below main's growth on the same fixture.
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
# GROWTH_BOUND: the sed, awk and head runs one status may add per added story. Before the snapshot,
# status added about 45 a story on this fixture, as fm and get_fm ran sed, head or awk on every read.
GROWTH_BOUND=5

# The counting wrappers: each logs its name to COUNT_LOG, then runs the real program.
COUNTED="sed awk head perl cat rm mkdir mv grep tr wc"
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

# --- status's sed, awk and head runs on 20 and 60 stories.
# board <n> — a project of <n> stories, in three epics under an agreed HLD: ready, blocked on the one
# before, in review through state, done, in turn.
board() {
  local P="${ROOT}/p$1" i e
  mkdir -p "${P}/docs/stories" "${P}/docs/epics" "${P}/docs/hld" "${P}/.swarm/board-state/stories"
  git -C "${P}" init -q -b main
  it() { { echo ---; printf '%s\n' "${@:3}"; echo ---; echo; echo "# $2"; } > "${P}/docs/$1/$2.md"; }
  it hld h 'status: agreed' 'grants: [epics]'
  for e in 1 2 3; do it epics "e${e}" 'status: active' 'hld: h'; done
  for ((i = 1; i <= $1; i++)); do
    e=$(( i % 3 + 1 ))
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
# runs <n> — the sed, awk and head runs of one status on board <n>; its output goes to ${ROOT}/out<n>.
runs() {
  : > "${ROOT}/count$1"
  # shellcheck disable=SC2031 # PATH is the test's own here
  (cd "${ROOT}/p$1" && env -u HERDR_ENV -u HERDR_PANE_ID COUNT_LOG="${ROOT}/count$1" \
    PATH="${ROOT}/count:${ROOT}/bin:${PATH}" bash "${SWARM}" status > "${ROOT}/out$1" 2>&1) || echo "status on $1 stories failed: $(cat "${ROOT}/out$1")" >&2
  grep -cxE 'sed|awk|head' "${ROOT}/count$1" || true
}
board 20; board 60
c20="$(runs 20)"; c60="$(runs 60)"
echo "status's sed, awk and head runs: ${c20} on 20 stories, ${c60} on 60"
is "status on 60 stories lists the 15 in review" 15 "$(grep -c '^  awaiting your merge: ' "${ROOT}/out60" || true)"
holds "status's sed, awk and head runs grow per added story by at most ${GROWTH_BOUND} (about 45 before the snapshot)" \
  "(b - a) / 40 <= ${GROWTH_BOUND}" "${c20}" "${c60}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
