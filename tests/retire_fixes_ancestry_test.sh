#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034 # run evals its script in a subshell: the variables expand there
# retire_fixes_ancestry_test.sh — fix_main's retire_fixes judges which fix-main story a red main no
# longer needs by commit ancestry, read in the project's clone, not by the order events.tsv logged the
# reds in: CI on an older commit can finish after CI on a newer one. A red in another repo, or one
# whose commit the clone lacks, retires nothing; a green main (retire_fixes <key> -) retires them all.
# merge.sh's functions run alone, on a git fixture: A then B on origin's main, B descending from A, and
# X and Y, two commits neither of which descends from the other.
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

g() { git -C "${P}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }
git init -q --bare "${ROOT}/origin.git"; git init -q "${P}"; g remote add origin "${ROOT}/origin.git"
g commit -q --allow-empty -m root; ROOTC="$(g rev-parse HEAD)"
g commit -q --allow-empty -m a; A="$(g rev-parse HEAD)"
g commit -q --allow-empty -m b; B="$(g rev-parse HEAD)"
g push -q origin HEAD:main
X="$(g commit-tree -p "${ROOTC}" -m x "$(g rev-parse 'HEAD^{tree}')")"
Y="$(g commit-tree -p "${ROOTC}" -m y "$(g rev-parse 'HEAD^{tree}')")"
F=ffffffffffffffffffffffffffffffffffffffff   # in no clone

# gh: repo view names the project's origin Me/Proj (the case GitHub gives), and logs every call.
mkdir -p "${ROOT}/bin"
printf '#!/usr/bin/env bash\necho "$*" >> "%s"\ncase "$1 $2" in "repo view") echo %s ;; *) exit 1 ;; esac\n' \
  "${ROOT}/gh.log" "'{\"nameWithOwner\":\"Me/Proj\"}'" > "${ROOT}/bin/gh"
chmod +x "${ROOT}/bin/gh"
export PATH="${ROOT}/bin:${PATH}"

fails=0
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }

# run <script> — the script in a subshell with merge.sh sourced on a fresh board and events.tsv in
# ${P}, its board helpers stubbed: a story is started when a file started-<slug> is there. red <repo>
# <sha> is fix_main's red main on <repo>'s main, its output in ${ROOT}/out-<short sha>. on_board
# prints the fix-main stories left, retired the retired: lines logged.
# shellcheck disable=SC2034,SC2317,SC2329 # merge.sh's functions read these and call these
run() {
  (
    PROJECT_DIR="${P}"; BOARD="${P}/board"; EVENTS_LOG="${P}/.swarm/events.tsv"; BOARD_IN_REPO=0; SWARM_HOME="${REPO}"; MERGE_TARGET=s
    rm -rf "${BOARD}" "${P}/.swarm" "${ROOT}"/out-* "${ROOT}/gh.log"; mkdir -p "${BOARD}/stories" "${P}/.swarm"
    # shellcheck source=/dev/null
    . "${REPO}/bin/lib/merge.sh"
    fm() { sed -n "s/^$2: *//p" "$1" | head -1; }
    one_off_started() { [[ -e "${ROOT}/started-$1" ]]; }
    delete_item() { rm "$1"; }
    record_event() { printf 'T\t%s\t%s\t-\t%s\n' "$1" "$2" "${3:-ok}" >> "${EVENTS_LOG}"; }
    state_lock() { mkdir "$1"; }
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
# With no unstarted fix to judge, gh is never asked which repo the clone is.
is "a red with its own fix started and no other: no gh call" "" \
  "$(touch "${ROOT}/started-fix-main-${a}"; run 'red me/proj "${A}"; cat "${ROOT}/gh.log" 2>/dev/null || true'; rm "${ROOT}/started-fix-main-${a}")"

echo
if [[ ${fails} -eq 0 ]]; then echo "all retire_fixes_ancestry tests passed"; else echo "${fails} retire_fixes_ancestry test(s) failed"; exit 1; fi
