#!/usr/bin/env bash
# board_state_test.sh — the front-matter keys swarm.sh writes (SET_FM_KEYS) go to .swarm/board-state/,
# never to a tracked story or epic file, and every reader takes them from there first: review leaves
# git status clean while next and status show the story in review; a story lead_block hands on is
# refused as kind: lead though its file says kind: code; merge holds a costs: money story whose prs:
# is only in state; an epic and a story with one slug keep separate state; a later commit to a key
# wins over its state line; a failed state write fails the command; a tab record named board is no
# clash; review and unblock write an item's keys in one write; two writers to one item keep both keys,
# and a lock left behind stops a write; touches_rows.py compares a value with a trailing space as
# state_value does; a state directory that cannot be written and a state file that cannot be read
# each stop the command, naming the file. gh is a stub on PATH that logs every call to gh.log: pr
# view answers the state in ${ROOT}/pr-<n> (OPEN without one) and a head. mv is a wrapper that, on a
# board-state path, waits 0.5s while ${ROOT}/mv.slow exists, and fails while ${ROOT}/mv.fail exists,
# after the number of moves it holds (none when it is empty).
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; ST="${P}/.swarm/board-state"; U=https://github.com/o/r/pull
H=1111111111111111111111111111111111111111
mkdir -p "${P}/.claude/swarm" "${P}/board/stories" "${P}/board/epics" "${ROOT}/bin"
printf 'board_dir = board\nmerge = agent\n' > "${P}/.claude/swarm/config"
echo .swarm/ > "${P}/.gitignore"
item() { { echo ---; printf '%s\n' "${@:3}"; echo ---; echo; echo "# $2"; } > "${P}/board/$1/$2.md"; }
# commit — commit every board file, so git status starts clean.
commit() { git -C "${P}" -c user.name=t -c user.email=t@t add -A; git -C "${P}" -c user.name=t -c user.email=t@t commit -qm "$1"; }
git -C "${P}" init -q -b main
item stories s "status: ready" "kind: code"
item epics same "status: review" "prs: ${U}/30"
commit init

printf '#!/usr/bin/env bash\nR="%s"; H="%s"\n' "${ROOT}" "${H}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "${R}/gh.log"
case "$1 $2" in
  "pr view") n="${3##*/}"; printf '{"state":"%s","headRefOid":"%s","baseRefName":"main","changedFiles":1}\n' "$(cat "${R}/pr-${n}" 2>/dev/null || echo OPEN)" "${H}" ;;
  "pr list") echo '[]' ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
# herdr: no agents, panes or tabs, so close finds no builder open.
cat > "${ROOT}/bin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[]}}' ;;
  "pane list") echo '{"result":{"panes":[]}}' ;;
  "tab list") echo '{"result":{"tabs":[]}}' ;;
esac
STUB
printf '#!/bin/sh\nR="%s"; MV="%s"\n' "${ROOT}" "$(command -v mv)" > "${ROOT}/bin/mv"
cat >> "${ROOT}/bin/mv" <<'STUB'
case "$*" in *board-state*)
  [ ! -e "${R}/mv.slow" ] || sleep 0.5
  if [ -e "${R}/mv.fail" ]; then n="$(cat "${R}/mv.fail")"; [ "${n:-0}" -gt 0 ] || exit 1; echo $((n - 1)) > "${R}/mv.fail"; fi ;;
esac
exec "${MV}" "$@"
STUB
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr" "${ROOT}/bin/mv"
# A tab record named board, as a story or epic slug of that name makes one in .swarm/state.
mkdir -p "${P}/.swarm/state"; echo "w:9 board" > "${P}/.swarm/state/board"

# sw [VAR=value]... <args> — swarm.sh outside herdr, unless VARs say otherwise, from the main
# checkout; sets rc, stdout and stderr in ${ROOT}/out.
sw() {
  local envs=()
  while [[ "${1:-}" == [A-Z]*=* ]]; do envs+=("$1"); shift; done
  rc=0
  (cd "${P}" && env -u HERDR_ENV -u HERDR_PANE_ID -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" SWARM_MERGE_POLL=0 \
    SWARM_MERGE_READ_WAIT=0 ${envs[@]+"${envs[@]}"} bash "${SWARM}" "$@" > "${ROOT}/out" 2>&1) || rc=$?
}
lead() { sw HERDR_ENV=1 HERDR_PANE_ID=w:me "$@"; }
clean() { git -C "${P}" status --porcelain; }
# bs <function> <arg>... — a board.sh function on ${P}'s board, with the stubs on PATH, as swarm.sh runs it.
# shellcheck source=/dev/null disable=SC2317,SC2329   # die is board.sh's, called from there
bs() { (export PATH="${ROOT}/bin:${PATH}" BOARD="${P}/board" PROJECT_DIR="${P}"; die() { echo "swarm: $*" >&2; exit 1; }
  . "${SWARM%/*}/lib/board.sh"; "$@"); }
v() { bs get_fm "${P}/board/stories/$1.md" "$2"; }   # <slug> <key>: as swarm.sh reads it

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
said() { grep -qF -- "$1" "${ROOT}/out"; }

# --- review writes status and prs to the story's state file, each with the file's value as its
# base; the tracked file is as committed, and the tab record named board is left alone.
sw review s "${U}/10"
is "review s beside a tab record named board: exits 0, git status clean" "0|" "${rc}|$(clean)"
is "review s: its state file holds status and prs, with their bases" "status: review|status@base: ready|prs: ${U}/10|prs@base:" \
  "$(paste -sd'|' - < "${ST}/stories/s")"
sw next
check "next lists s as awaiting your merge" said "awaiting your merge: s ${U}/10"
sw status
check "status lists s as awaiting your merge" said "awaiting your merge: s ${U}/10"

# --- A board PR then commits s as blocked: the file's value now differs from the base, so it wins.
perl -pi -e 's/^status: ready$/status: blocked/' "${P}/board/stories/s.md"; commit "s blocked"
sw status --all
is "a committed status: blocked wins over s's review in state" "yes|no" \
  "$(said 'blocked: s (' && echo yes)|$(said "awaiting your merge: s ${U}/10" && echo yes || echo no)"

# --- A costs: money story whose prs: is only in state: merge holds its PR (merge = agent).
item stories m "status: ready" "kind: code" "costs: money"
item stories c "status: ready" "kind: code"
item stories same "status: ready" "kind: code"
item stories s3 "status: ready" "kind: code"
commit more

# --- A state write that fails (its mv) fails review, and s3 is not in review.
touch "${ROOT}/mv.fail"; sw review s3 "${U}/11"; rm "${ROOT}/mv.fail"
is "review s3 with its state write failing: exits non-zero, no state file" "1|none" "${rc}|$([[ -e "${ST}/stories/s3" ]] && echo some || echo none)"

sw review m "${U}/20"
is "review m: prs: in state only, git status clean" "|${U}/20|" "$(sed -n 's/^prs: *//p' "${P}/board/stories/m.md")|$(sed -n 's/^prs: *//p' "${ST}/stories/m")|$(clean)"
: > "${ROOT}/gh.log"; sw merge --head "${H}" "${U}/20"
is "merge of m's PR: refused" 1 "${rc}"
check "merge of m's PR: held, m costs money" said "held: m costs money"
check "merge of m's PR: held before its checks are read, no pr merge" bash -c "! grep -qE '^(api|pr merge)' '${ROOT}/gh.log'"

# --- An epic and a story named same: review writes the story's state, reconcile the epic's.
sw review same "${U}/31"
echo CLOSED > "${ROOT}/pr-30"; sw reconcile
is "reconcile: exits 0, sends the epic back to ready" "0|yes" "${rc}|$(said 'back to ready: same' && echo yes)"
is "the story's state is review, the epic's ready" "review|ready" "$(sed -n 's/^status: //p' "${ST}/stories/same")|$(sed -n 's/^status: //p' "${ST}/epics/same")"
sw status
is "status: the story awaits your merge, the epic no longer does" "yes|no" \
  "$(said "awaiting your merge: same ${U}/31" && echo yes)|$(said 'awaiting your merge: epic same' && echo yes || echo no)"
is "after review, merge and reconcile, git status is clean" "" "$(clean)"

# --- close impossible (lead_block) hands c to the lead in state; story refuses it as kind: lead.
lead close c impossible --drop
is "close c impossible --drop: exits 0, kind: lead in state" "0|lead" "${rc}|$(sed -n 's/^kind: //p' "${ST}/stories/c")"
lead story c
is "story c: refused as kind: lead" "1|yes" "${rc}|$(said 'c is kind: lead' && echo yes)"
is "c's tracked file still says kind: code" "code" "$(sed -n 's/^kind: //p' "${P}/board/stories/c.md")"

item stories par "status: ready" "kind: code"
item stories kid "status: ready" "kind: code" "depends_on: [par]"
item stories w "status: ready" "kind: code"
item stories t "status: ready " "kind: code" "touches: [lib.sh]"
item stories o "status: ready" "kind: code" "touches: [lib.sh]"
commit last

# --- review holds kid, whose parent is open, in one write: with the second state mv failing, its
# status, prs and held_by are all there.
echo 1 > "${ROOT}/mv.fail"; sw review kid "${U}/40"; rm -f "${ROOT}/mv.fail"
is "review of kid, held with only one state write left: status, prs and held_by written together" "1|yes|blocked|${U}/40|par" \
  "${rc}|$(said 'held: kid waits for par' && echo yes)|$(v kid status)|$(v kid prs)|$(v kid held_by)"
# --- par finishes; unblock readies kid, its worktree gone, in one write too.
perl -pi -e 's/^status: ready$/status: done/' "${P}/board/stories/par.md"; commit "par done"
echo 1 > "${ROOT}/mv.fail"; sw unblock; rm -f "${ROOT}/mv.fail"
is "unblock of kid with only one state write left: ready, without held_by or prs" "0|ready||" "${rc}|$(v kid status)|$(v kid held_by)|$(v kid prs)"

# --- Two writers to w at once, each move slowed so their reads and writes overlap: the lock keeps both keys.
touch "${ROOT}/mv.slow"; rc=0
bs set_fm "${P}/board/stories/w.md" attempts 2 & a=$!
bs set_fm "${P}/board/stories/w.md" held_for pause & b=$!
wait "${a}" || rc=1; wait "${b}" || rc=1; rm "${ROOT}/mv.slow"
is "two writers to w at once: both succeed, both keys survive, no temp file or lock left" "0|2|pause|" \
  "${rc}|$(v w attempts)|$(v w held_for)|$(cd "${ST}/stories" && ls -d w.* 2>/dev/null)"
# --- A lock left behind: review waits SWARM_LOCK_WAIT seconds, then dies naming it, and writes nothing.
mkdir "${ST}/stories/w.lock"; sw SWARM_LOCK_WAIT=1 review w "${U}/60"; rmdir "${ST}/stories/w.lock"
is "review of w with its lock left behind: dies naming the lock, w still ready" "1|yes|ready" \
  "${rc}|$(said "stories/w.lock is still there after 1s" && echo yes)|$(v w status)"

# --- t's status had a trailing space when review wrote its base; a board PR then drops the space.
# The file's value now differs from the base, so status and touches_rows.py both read it, as ready.
sw review t "${U}/50"
perl -pi -e 's/^status: ready $/status: ready/' "${P}/board/stories/t.md"; commit "t trimmed"
sw status
is "t's committed status, a trailing space dropped since review: status and touches_rows read it as ready" "no|ready" \
  "$(said "awaiting your merge: t ${U}/50" && echo yes || echo no)|$(python3 "${SWARM%/*}/lib/touches_rows.py" "${P}/board/stories" o "${P}" "${ROOT}/repos" "${ST}/stories" | cut -f3)"

# --- A state directory that cannot be written: review dies naming the state file.
chmod u-w "${ST}/stories"; sw review o "${U}/70"; chmod u+w "${ST}/stories"
is "review of o with its state directory unwritable: dies naming the state file" "1|yes|ready" \
  "${rc}|$(said "board state: cannot write ${ST}/stories/o" && echo yes)|$(v o status)"
# --- A state file that cannot be read: m, in review there, is not read as the ready its file says.
chmod 000 "${ST}/stories/m"; lead story m; chmod 644 "${ST}/stories/m"
is "story m with its state file unreadable: refused as not ready, naming the file" "1|yes|yes" \
  "${rc}|$(said "board state: cannot read ${ST}/stories/m" && echo yes)|$(said "m is not status: ready" && echo yes)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failure(s)"; exit 1; }
echo "all passed"
