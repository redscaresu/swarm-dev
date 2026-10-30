#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034 # run evals its script in a subshell: the variables expand there
# retire_fixes_ancestry_test.sh — fix_main's retire_fixes judges which fix-main story a red main no
# longer needs by commit ancestry, read in the project's clone, not by the order events.tsv logged the
# reds in: CI on an older commit can finish after CI on a newer one. A red in another repo, or one
# whose commit the clone lacks, retires nothing; a green main (retire_fixes <key> -) retires them all.
# merge.sh's functions run alone, on a git fixture: A then B on origin's main, B descending from A, and
# X and Y, two commits neither of which descends from the other. C, B's child, reaches origin later
# from another clone, so only a fetch brings it to the project's clone.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P="${ROOT}/proj"

gd() { local d="$1"; shift; git -C "${d}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
g() { gd "${P}" "$@"; }
git init -q --bare "${ROOT}/origin.git"; git init -q "${P}"; g remote add origin "${ROOT}/origin.git"
g commit -q --allow-empty -m root; ROOTC="$(g rev-parse HEAD)"
g commit -q --allow-empty -m a; A="$(g rev-parse HEAD)"
g commit -q --allow-empty -m b; B="$(g rev-parse HEAD)"
g push -q origin HEAD:main
X="$(g commit-tree -p "${ROOTC}" -m x "$(g rev-parse 'HEAD^{tree}')")"
Y="$(g commit-tree -p "${ROOTC}" -m y "$(g rev-parse 'HEAD^{tree}')")"
F=ffffffffffffffffffffffffffffffffffffffff   # in no clone

# gh: repo view names the project's origin Me/Proj (the case GitHub gives), and logs every call. With
# ${ROOT}/gh-sleep there, it first sleeps that many seconds.
mkdir -p "${ROOT}/bin"
printf '#!/usr/bin/env bash\necho "$*" >> "%s"\n[ ! -f "%s" ] || sleep "$(cat "%s")"\ncase "$1 $2" in "repo view") echo %s ;; *) exit 1 ;; esac\n' \
  "${ROOT}/gh.log" "${ROOT}/gh-sleep" "${ROOT}/gh-sleep" "'{\"nameWithOwner\":\"Me/Proj\"}'" > "${ROOT}/bin/gh"
chmod +x "${ROOT}/bin/gh"
export PATH="${ROOT}/bin:${PATH}"

fails=0
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }

# run <script> — the script in a subshell with merge.sh sourced on a fresh board and events.tsv in
# ${P}, its board helpers stubbed: a story is started when a file started-<slug> is there. red <repo>
# <sha> is fix_main's red main on <repo>'s main, its output in ${ROOT}/out-<short sha>. on_board
# prints the fix-main stories left, retired the retired: lines logged. state_lock waits up to 2 s for
# the lock, then fails, as board.sh's does after STATE_LOCK_WAIT.
# shellcheck disable=SC2034,SC2317,SC2329 # merge.sh's functions read these and call these
run() {
  (
    PROJECT_DIR="${P}"
    # shellcheck source=/dev/null
    . "${REPO}/bin/lib/agents.sh"   # first, as swarm.sh loads it: EVENT_OUTCOME_AWK, which merge.sh's readers use
    BOARD="${P}/board"; EVENTS_LOG="${P}/.swarm/events.tsv"; BOARD_IN_REPO=0; SWARM_HOME="${REPO}"; MERGE_TARGET=s
    rm -rf "${BOARD}" "${P}/.swarm" "${ROOT}"/out-* "${ROOT}/gh.log"; mkdir -p "${BOARD}/stories" "${P}/.swarm"
    # shellcheck source=/dev/null
    . "${REPO}/bin/lib/merge.sh"
    fm() { sed -n "s/^$2: *//p" "$1" | head -1; }
    one_off_started() { [[ -e "${ROOT}/started-$1" ]]; }
    delete_item() { rm "$1"; }
    record_event() { printf 'T\t%s\t%s\t-\t%s\n' "$1" "$2" "${3:-ok}" >> "${EVENTS_LOG}"; }
    state_lock() { local i; for i in $(seq 20); do mkdir "$1" 2>/dev/null && return 0; sleep 0.1; done; echo "locked: $1"; exit 1; }
    json() { python3 -c "import json,os,sys; d=json.load(sys.stdin); e=os.environ; print($1)"; }
    red() { fix_main "$1" "$2" main "test (failure)" > "${ROOT}/out-${2:0:7}" 2>&1; }
    on_board() { find "${BOARD}/stories" -name 'fix-main-*' -exec basename {} .md \; | sort | paste -sd' ' -; }
    retired() { awk -F'\t' '$2 == "fix-main" { print $3 " " $5 }' "${EVENTS_LOG}" | paste -sd'|' -; }
    eval "$1"
  )
}
a="${A:0:7}"; b="${B:0:7}"; x="${X:0:7}"; y="${Y:0:7}"
# sorted <sep> <word>... — the words in sha order, as on_board and retire_fixes give them, joined by <sep>.
sorted() { local d="$1"; shift; printf '%s\n' "$@" | sort | paste -sd"${d}" -; }

# B's red logged before A's, neither built: A's fix goes, B's fix stays and covers A's red.
is "B's red logged before A's: fix-main-B stays, fix-main-A retired, superseded by fix-main-B" \
  "fix-main-${b}|fix-main-${a} retired: superseded by fix-main-${b}" \
  "$(run 'red Me/Proj "${B}"; red me/proj "${A}"; echo "$(on_board)|$(retired)"')"
is "B's red logged before A's: fix_main's output for A names fix-main-B as the story that covers the red" \
  "story: ${P}/board/stories/fix-main-${b}.md, whose red descends from ${a}, so it covers this red too" \
  "$(run 'red me/proj "${B}"; red me/proj "${A}"; grep "^story:" "${ROOT}/out-${a}"')"
is "B's red logged before A's: red_mains gives B's red as the base's, so next names fix-main-B" "${B} me/proj main" \
  "$(run 'red me/proj "${B}"; red me/proj "${A}"; red_mains | cut -d" " -f1-3')"
# In log order, as before.
is "A's red logged first: B's red retires fix-main-A" \
  "fix-main-${b}|fix-main-${a} retired: superseded by fix-main-${b}" \
  "$(run 'red me/proj "${A}"; red me/proj "${B}"; echo "$(on_board)|$(retired)"')"
is "A's red logged first: fix_main's output for B names its own story" \
  "story: ${P}/board/stories/fix-main-${b}.md" "$(run 'red me/proj "${A}"; red me/proj "${B}"; grep "^story:" "${ROOT}/out-${b}"')"
# A started fix is left to its builder, and its red still covers an older one.
is "B's red logged before A's, fix-main-B started: fix-main-A retired, fix-main-B kept" \
  "fix-main-${b}|fix-main-${a} retired: superseded by fix-main-${b}" \
  "$(touch "${ROOT}/started-fix-main-${b}"; run 'red me/proj "${B}"; red me/proj "${A}"; echo "$(on_board)|$(retired)"'; rm "${ROOT}/started-fix-main-${b}")"
is "A's red logged first, fix-main-A started: both stay" "$(sorted ' ' "fix-main-${a}" "fix-main-${b}")|" \
  "$(touch "${ROOT}/started-fix-main-${a}"; run 'red me/proj "${A}"; red me/proj "${B}"; echo "$(on_board)|$(retired)"'; rm "${ROOT}/started-fix-main-${a}")"
# A red whose story is gone (a green main cleared it) covers nothing: A's fix stays.
is "B's red logged and its story gone before A's red: fix-main-A stays" "fix-main-${a}|" \
  "$(run 'red me/proj "${B}"; rm "${BOARD}/stories/fix-main-${b}.md"; red me/proj "${A}"; echo "$(on_board)|$(retired)"')"
# Neither descends from the other, or the clone lacks one: both stay.
is "two reds where neither descends from the other: both stay" "$(sorted ' ' "fix-main-${x}" "fix-main-${y}")|" \
  "$(run 'red me/proj "${X}"; red me/proj "${Y}"; echo "$(on_board)|$(retired)"')"
is "a red whose commit the clone lacks, logged after A's: both stay" "$(sorted ' ' "fix-main-${a}" fix-main-fffffff)|" \
  "$(run 'red me/proj "${A}"; red me/proj "${F}"; echo "$(on_board)|$(retired)"')"
is "a red whose commit the clone lacks, logged before A's: both stay" "$(sorted ' ' "fix-main-${a}" fix-main-fffffff)|" \
  "$(run 'red me/proj "${F}"; red me/proj "${A}"; echo "$(on_board)|$(retired)"')"
# Another repo's commits are not in this clone: logged out of order, both stay; a green retires both.
is "another repo's reds, logged out of order: both stay" "$(sorted ' ' "fix-main-${a}" "fix-main-${b}")|" \
  "$(run 'red other/repo "${B}"; red other/repo "${A}"; echo "$(on_board)|$(retired)"')"
is "another repo's reds: a green on that key retires both" \
  "|$(sorted '|' "fix-main-${a} retired: CI on main is green" "fix-main-${b} retired: CI on main is green")" \
  "$(run 'red other/repo "${B}"; red other/repo "${A}"; retire_fixes "other/repo main" - "CI on main is green" > /dev/null; echo "$(on_board)|$(retired)"')"
# A clone with no origin cannot tell which repo it is: nothing retires.
is "a project clone with no origin: both stay" "$(sorted ' ' "fix-main-${a}" "fix-main-${b}")|" \
  "$(run 'git -C "${P}" remote remove origin; red me/proj "${B}"; red me/proj "${A}"; git -C "${P}" remote add origin "${ROOT}/origin.git"; echo "$(on_board)|$(retired)"')"
# A red that a main-green cleared covers nothing, even with its fix started and still on the board:
# A's late red keeps its own fix, and red_mains gives A.
is "B's red cleared by a green while its fix was building, then A's red: fix-main-A stays, red_mains gives A" \
  "$(sorted ' ' "fix-main-${a}" "fix-main-${b}")||${A}" \
  "$(touch "${ROOT}/started-fix-main-${b}"; run 'red me/proj "${B}"; record_event main-green "${B}" "me/proj main ${B}"; red me/proj "${A}"
    echo "$(on_board)|$(retired)|$(red_mains | cut -d" " -f1)"'; rm "${ROOT}/started-fix-main-${b}")"
is "B's red cleared by an older green naming no red, then A's red: fix-main-A stays, red_mains gives A" \
  "$(sorted ' ' "fix-main-${a}" "fix-main-${b}")||${A}" \
  "$(touch "${ROOT}/started-fix-main-${b}"; run 'red me/proj "${B}"; record_event main-green g "me/proj main"; red me/proj "${A}"
    echo "$(on_board)|$(retired)|$(red_mains | cut -d" " -f1)"'; rm "${ROOT}/started-fix-main-${b}")"
# A red logged again on B after that green (CI re-run) is live again: it covers A's late red.
is "B red, cleared by a green, then red again, then A's red: fix-main-A retired by fix-main-B, red_mains gives B" \
  "fix-main-${b}|fix-main-${a} retired: superseded by fix-main-${b}|${B}" \
  "$(touch "${ROOT}/started-fix-main-${b}"; run 'red me/proj "${B}"; record_event main-green "${B}" "me/proj main ${B}"; red me/proj "${B}"; red me/proj "${A}"
    echo "$(on_board)|$(retired)|$(red_mains | cut -d" " -f1)"'; rm "${ROOT}/started-fix-main-${b}")"
is "red_mains: a red superseded by one a main-green already cleared stays the base's red" "${A}" \
  "$(run 'printf "T\tmain-red\t%s\t-\tme/proj main test (failure)\n" "${B}" >> "${EVENTS_LOG}"
    printf "T\tmain-green\tg\t-\tme/proj main %s\n" "${B}" >> "${EVENTS_LOG}"
    printf "T\tmain-red\t%s\t-\tme/proj main test (failure)\n" "${A}" >> "${EVENTS_LOG}"
    printf "T\tfix-main\tfix-main-%s\t-\tretired: superseded by fix-main-%s\n" "${a}" "${b}" >> "${EVENTS_LOG}"
    red_mains | cut -d" " -f1')"
# fix_main asks gh before it takes the key's lock, even with no other red on the board: two red merges
# at once on an empty board, gh taking 4 s and the lock waited on 2 s, both write their stories, and
# B's covers A's.
is "two reds at once on an empty board while gh is slow: both print fix-main:, and fix-main-B covers fix-main-A" \
  "2|fix-main-${b}" \
  "$(run 'echo 4 > "${ROOT}/gh-sleep"; red me/proj "${A}" & red me/proj "${B}" & wait; rm "${ROOT}/gh-sleep"
    echo "$(grep -l "^fix-main:" "${ROOT}"/out-* | wc -l | tr -d " ")|$(on_board)"')"
# The fetch: C reaches origin from another clone, so the project's clone has it only once fix_main
# fetches the base.
git clone -q --branch main "${ROOT}/origin.git" "${ROOT}/other"; gd "${ROOT}/other" commit -q --allow-empty -m c
C="$(gd "${ROOT}/other" rev-parse HEAD)"; c="${C:0:7}"; gd "${ROOT}/other" push -q origin HEAD:main
is "C, pushed from another clone, is not in the project's clone yet" no "$(g cat-file -e "${C}^{commit}" 2>/dev/null && echo yes || echo no)"
is "a red at a commit only a fetch brings (C): it retires fix-main-B" "fix-main-${c}|fix-main-${b} retired: superseded by fix-main-${c}" \
  "$(run 'red me/proj "${B}"; red me/proj "${C}"; echo "$(on_board)|$(retired)"')"

echo
if [[ ${fails} -eq 0 ]]; then echo "all retire_fixes_ancestry tests passed"; else echo "${fails} retire_fixes_ancestry test(s) failed"; exit 1; fi
