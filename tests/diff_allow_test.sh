#!/usr/bin/env bash
# diff_allow_test.sh — tests/diff_run.sh's allow lists (--stage, --only and --draft, through
# tests/diff_allow.py), on two copies of this tree with a seeded change. (1) Each of these is red: the
# change with no entry; a hunk whose removed line is one byte off; an entry with no hunks; a heading
# with no lines, an empty fence and a heading naming only a fixture; a hunk that does not apply on a
# fixture the run ran (and the same hunk is skipped when its fixture is outside the run); a hunk whose
# lines are in the stream twice; a file:<path> hunk for a file the files list does not write. The
# entry that covers the change exits 0. (2) A calls:fg hunk for one extra gh call applies. (3) An entry
# in stage-2/ applies at --stage 2 and is red at --stage 1. (4) --only a applies a's entry and leaves
# b's out. Entries apply in the order their files reached HEAD's first-parent history, and with no
# git by PR number, never by file name; a files hunk that drops a file a file:<path> hunk before it
# changed applies. (5) Every entry file under this checkout's
# scripts/allow/ parses, and a malformed one, or a stray file, added on a copy is red. (6) --draft's
# hunks, pasted into an entry, cover every difference they print: a changed, an inserted and a
# removed line, a line that gains or keeps no newline, an exit code, a new, an empty, a changed and a deleted file,
# a gh call, and next's own run with an extra gh call that swarm.sh's gh-shim logs.
# shellcheck disable=SC2016 # the mutations are swarm.sh code, expanded when that copy runs it
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
# A diff_run.sh still running gets a TERM and is waited on first: its own EXIT trap kills the fixture
# commands' groups, which stop_test_group, holding only this test's group, never reaches.
DR_PID=""
trap '[[ -z "${DR_PID}" ]] || { kill -TERM "${DR_PID}" 2>/dev/null; wait "${DR_PID}" 2>/dev/null; }; stop_test_group; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
export HOME="${ROOT}/home"; mkdir -p "${HOME}"
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1: $2"; sed 's/^/  | /' "${ROOT}/out"; fails=$((fails + 1)); }

# Two copies of what the fixtures run. a's checkout holds the harness that runs, so its
# scripts/allow/ is the list read; b's is never read.
A="${ROOT}/a" B="${ROOT}/b"
for t in "${A}" "${B}"; do
  mkdir -p "${t}/tests"
  (cd "${REPO}" && tar -cf - bin hooks templates .claude-plugin tests/diff_run.sh tests/diff_allow.py tests/diff_fixtures_*.sh) | tar -C "${t}" -xf -
done
cat > "${A}/tests/diff_fixtures_probe.sh" <<'FX'
# shellcheck shell=bash disable=SC2034
fx_probe() { FX_CMD=(bash "${TREE}/probe.sh"); }
fx_probe2() { FX_CMD=(bash "${TREE}/probe2.sh"); }
FX
for t in "${A}" "${B}"; do printf 'echo same\n' > "${t}/probe2.sh"; done
# probe <a's script> <b's script> — what fx_probe runs in each tree.
probe() { printf '%s\n' "$1" > "${A}/probe.sh"; printf '%s\n' "$2" > "${B}/probe.sh"; }

# run <rc> [diff_run args...] — run a's diff_run.sh on a and b, its output in ${ROOT}/out, and check
# its exit.
run() {
  local want="$1" rc=0; shift
  bash "${A}/tests/diff_run.sh" "$@" > "${ROOT}/out" 2>&1 &
  DR_PID=$!; wait "${DR_PID}" || rc=$?; DR_PID=""
  [[ ${rc} == "${want}" ]] || { echo "exit ${rc}, not ${want}"; return 1; }
}
# expect <name> <rc> <line> [diff_run args...] — the run exits <rc> and prints a line starting with
# <line>.
expect() {
  local name="$1" want="$2" line="$3"; shift 3
  if ! run "${want}" "$@" > "${ROOT}/why"; then bad "${name}" "$(cat "${ROOT}/why")"
  elif ! grep -qF -- "${line}" "${ROOT}/out"; then bad "${name}" "no line '${line}'"
  else ok "${name}"; fi
}

# entry <stage> <slug> <pr> <body> — write a's scripts/allow/stage-<stage>/<slug>.md, kind stage.
entry() {
  mkdir -p "${A}/scripts/allow/stage-$1"
  printf -- '---\nstory: %s\npr: %s\nkind: stage\n---\n\n# %s\n\n%s\n' "$2" "$3" "$2" "$4" > "${A}/scripts/allow/stage-$1/$2.md"
}
clear_allow() { rm -rf "${A}/scripts/allow"; }
FENCE='```'
# hunk <fixture> <stream> <line>... — a ## heading and one fenced hunk of those lines.
hunk() { local h="## $1 $2"; shift 2; printf '%s\n\n%s\n' "${h}" "${FENCE}diff"; printf '%s\n' "$@"; printf '%s\n' "${FENCE}"; }

# (1) The seeded change: b prints TWO where a prints two.
probe "printf 'one\\ntwo\\n'" "printf 'one\\nTWO\\n'"
expect "the change with no entry is red" 1 "DIFF probe stdout" --stage 1 "${A}" "${B}" probe
if grep -qF "allow: no entry file in scripts/allow, stage-1, so every difference is red" "${ROOT}/out"; then ok "no entry says so"
else bad "no entry says so" "no 'allow: no entry file' line"; fi
entry 1 e 1 "$(hunk probe stdout ' one' -two +TWO)"
expect "the entry that covers it exits 0" 0 "allow e (#1, stage, stage-1): 1 of 1 hunks applied" --stage 1 "${A}" "${B}" probe
entry 1 e 1 "$(hunk probe stdout ' one' -twO +TWO)"
expect "a removed line one byte off is red" 1 "ALLOW-FAIL probe stdout: scripts/allow/stage-1/e.md:11 (e) does not apply: its - and ' ' lines are not in the stream" --stage 1 "${A}" "${B}" probe
entry 1 e 1 "The lines are left out."
expect "an entry with its lines left out is red" 2 "the entry has no hunks" --stage 1 "${A}" "${B}" probe
entry 1 e 1 "## probe stdout"
expect "a hunk naming a stream with no lines is red" 2 "## probe stdout names a stream with no lines" --stage 1 "${A}" "${B}" probe
entry 1 e 1 "$(printf '## probe stdout\n\n%s\n%s\n' "${FENCE}" "${FENCE}")"
expect "an empty fence is red" 2 "the hunk for probe stdout has no lines" --stage 1 "${A}" "${B}" probe
entry 1 e 1 "$(printf '## probe\n\n%s\n-two\n%s\n' "${FENCE}" "${FENCE}")"
expect "a hunk naming a whole fixture is red" 2 "## probe names a whole fixture" --stage 1 "${A}" "${B}" probe
entry 1 e 1 "$(hunk probe stdout ' one' -two +TWO; hunk probe2 stdout -absent +other)"
expect "a hunk that does not apply on a fixture the run ran is red" 1 "ALLOW-FAIL probe2 stdout: scripts/allow/stage-1/e.md:18 (e) does not apply" --stage 1 "${A}" "${B}" probe probe2
expect "a hunk for a fixture outside the run is skipped" 0 "allow e (#1, stage, stage-1): 1 of 2 hunks applied, 1 skipped as their fixture did not run" --stage 1 "${A}" "${B}" probe
entry 1 e 1 "$(hunk probe stdout ' one' -two +TWO; hunk probe 'file:<root>/nosuch' ^ +x)"
expect "a file:<path> hunk for a file the list does not write is red" 1 "ALLOW-FAIL probe file:<root>/nosuch" --stage 1 "${A}" "${B}" probe
probe "printf 'x\\nx\\n'" "printf 'x\\ny\\n'"
entry 1 e 1 "$(hunk probe stdout -x +y)"
expect "a hunk whose lines are in the stream twice is red" 1 "its - and ' ' lines are in the stream 2 times" --stage 1 "${A}" "${B}" probe
entry 1 e 1 "$(hunk probe stdout ' x' -x +y)"
expect "a context line makes it apply once" 0 "same probe" --stage 1 "${A}" "${B}" probe
clear_allow

# (2) One extra gh call, on the foreground's calls.
probe 'gh api first > /dev/null 2>&1 || true' 'gh api first > /dev/null 2>&1 || true; gh api extra > /dev/null 2>&1 || true'
expect "an extra gh call with no entry is red" 1 "DIFF probe calls:fg" --stage 1 "${A}" "${B}" probe
entry 1 e 1 "$(hunk probe calls:fg ' gh api first' '+gh api extra')"
expect "a calls:fg hunk for one extra gh call applies" 0 "same probe" --stage 1 "${A}" "${B}" probe
clear_allow

# (3) An entry in stage-2/.
probe "printf 'one\\ntwo\\n'" "printf 'one\\nTWO\\n'"
entry 2 e 1 "$(hunk probe stdout -two +TWO)"
expect "an entry in stage-2/ applies at --stage 2" 0 "allow e (#1, stage, stage-2): 1 of 1 hunks applied" --stage 2 "${A}" "${B}" probe
expect "an entry in stage-2/ is red at --stage 1" 1 "DIFF probe stdout" --stage 1 "${A}" "${B}" probe
clear_allow

# (4) Two stories: b holds a's change only, as a's own merge commit does.
probe "printf 'one\\ntwo\\n'" "printf 'ONE\\ntwo\\n'"
entry 1 a 1 "$(hunk probe stdout -one +ONE)"
entry 1 b 2 "$(hunk probe stdout -two +TWO)"
expect "--only a applies a's entry" 0 "allow a (#1, stage, stage-1): 1 of 1 hunks applied" --only a "${A}" "${B}" probe
if grep -qF "allow b " "${ROOT}/out"; then bad "--only a leaves b's out" "b's entry was read"; else ok "--only a leaves b's out"; fi
expect "without --only, b's entry applies too and is red there" 1 "allow b (#2, stage, stage-1): 1 of 1 hunks applied" --stage 1 "${A}" "${B}" probe
expect "--only names an entry that exists" 2 "--only c: no c.md" --only c "${A}" "${B}" probe
clear_allow
# PR 10's entry turns two into mid, then PR 20's mid into three; by file name they would go the other way.
probe "printf 'one\\ntwo\\n'" "printf 'one\\nthree\\n'"
entry 1 aa 20 "$(hunk probe stdout -mid +three)"
entry 1 zz 10 "$(hunk probe stdout -two +mid)"
expect "with no git, entries apply by PR number" 0 "same probe" --stage 1 "${A}" "${B}" probe
# In a git checkout, by the commit that added each: PR 20's entry first, then PR 10's.
clear_allow
entry 1 aa 20 "$(hunk probe stdout -two +mid)"
G=(git -C "${A}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false)
"${G[@]}" init -q && "${G[@]}" add scripts/allow && "${G[@]}" commit -qm 'PR 20 merged'
entry 1 zz 10 "$(hunk probe stdout -mid +three)"
"${G[@]}" add scripts/allow && "${G[@]}" commit -qm 'PR 10 merged'
expect "in a git checkout, entries apply in the order they merged" 0 "same probe" --stage 1 "${A}" "${B}" probe
rm -rf "${A}/.git"
clear_allow
# PR 1 changes a file a's run writes; PR 2's story stops writing it.
probe 'echo a > kept' ':'
entry 1 e1 1 "$(hunk probe 'file:<root>/kept' -a +b)"
entry 1 e2 2 "$(hunk probe files '-written <root>/kept')"
expect "a files hunk drops a file an earlier hunk changed" 0 "same probe" --stage 1 "${A}" "${B}" probe
clear_allow

# (5) Every entry file on disk parses; on a copy, a malformed one and a stray file are red.
if python3 "${REPO}/tests/diff_allow.py" check "${REPO}/scripts/allow" > "${ROOT}/out" 2>&1; then ok "every entry file on disk parses"
else bad "every entry file on disk parses" "exit non-zero"; fi
C="${ROOT}/copy/scripts/allow"; mkdir -p "${C%/allow}"; cp -R "${REPO}/scripts/allow" "${C}"
mkdir -p "${C}/stage-1"; printf -- '---\nstory: good\npr: 99999\nkind: fix\n---\n\n## probe stdout\n\n```\n-a\n+b\n```\n' > "${C}/stage-1/good.md"
if python3 "${REPO}/tests/diff_allow.py" check "${C}" > "${ROOT}/out" 2>&1 && grep -qF "parsed scripts/allow/stage-1/good.md (good, #99999, fix): 1 hunks" "${ROOT}/out"; then
  ok "a well-formed entry added on a copy parses"; else bad "a well-formed entry added on a copy parses" "exit non-zero, or no parsed line"; fi
printf -- '---\nstory: broken\npr: 99998\nkind: fix\n---\n\n## probe stdout\n\n```\n*a\n```\n' > "${C}/stage-1/broken.md"
rc=0; python3 "${REPO}/tests/diff_allow.py" check "${C}" > "${ROOT}/out" 2>&1 || rc=$?
if [[ ${rc} == 2 ]] && grep -qF "stage-1/broken.md:10: a hunk line starts with" "${ROOT}/out"; then ok "a malformed entry added on a copy is red"
else bad "a malformed entry added on a copy is red" "exit ${rc}"; fi
rm "${C}/stage-1/broken.md"; : > "${C}/stage-1/notes.txt"
rc=0; python3 "${REPO}/tests/diff_allow.py" check "${C}" > "${ROOT}/out" 2>&1 || rc=$?
if [[ ${rc} == 2 ]] && grep -qF "stage-1/notes.txt: a stage directory holds <slug>.md entry files only" "${ROOT}/out"; then ok "a stray file added on a copy is red"
else bad "a stray file added on a copy is red" "exit ${rc}"; fi

# (6) --draft, then its hunks as an entry. b changes stdout (a line changed, one inserted at the
# start, one removed, the last line's newline dropped), stderr (the second of two x lines removed, which
# the hunk must name by the line before it), the exit code, the files (one new, one
# empty, one deleted, and one whose last line, with no newline on either side, changed) and the gh
# calls; and next calls gh once more.
probe 'printf "head\nkeep\nold\nx\nx\nend\n"; printf "a\nx\nb\nx\n" >&2; printf "k1\nk2" > kept; echo gone > gone; exit 0' \
  'printf "first\nhead\nkeep\nnew\nx\nend"; printf "a\nx\nb\n" >&2; printf "k1\nK2" > kept; echo n > made; : > empty; gh api extra > /dev/null 2>&1; exit 3'
NEXT_ARM='    next)   timed next next_report ;;'
cp "${B}/bin/swarm.sh" "${ROOT}/swarm.sh.orig"
perl -pi -e 's/\Q'"${NEXT_ARM}"'\E/    next)   timed next next_report; gh api extra > \/dev\/null 2>&1 || true ;;/' "${B}/bin/swarm.sh"
grep -qF 'gh api extra' "${B}/bin/swarm.sh" || { echo "FAIL the next arm is not in bin/swarm.sh"; exit 1; }
if run 1 --draft "${A}" "${B}" probe next > "${ROOT}/why"; then
  awk '/^DIFF /{p=0} /^## /{p=1} p' "${ROOT}/out" > "${ROOT}/draft"
  got="$(sed -n 's/^DIFF //p' "${ROOT}/out" | LC_ALL=C sort | tr '\n' ';')"
  want="next calls:fg;next file:<root>/proj/.swarm/gh-calls.tsv;next files;probe calls:fg;probe exit;probe file:<root>/empty;probe file:<root>/gone;probe file:<root>/kept;probe file:<root>/made;probe files;probe stderr;probe stdout;"
  if [[ "${got}" == "${want}" ]]; then ok "--draft names each difference"; else bad "--draft names each difference" "DIFF lines '${got}', not '${want}'"; fi
  entry 1 drafted 7 "$(cat "${ROOT}/draft")"
  expect "--draft's hunks, as an entry, cover every difference" 0 "same next" --stage 1 "${A}" "${B}" probe next
  if grep -qxF "same probe" "${ROOT}/out"; then ok "probe compares the same once its drafted hunks apply"
  else bad "probe compares the same once its drafted hunks apply" "no 'same probe'"; fi
else bad "--draft names each difference" "$(cat "${ROOT}/why")"; fi
mv "${ROOT}/swarm.sh.orig" "${B}/bin/swarm.sh"
clear_allow

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
