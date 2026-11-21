#!/usr/bin/env bash
# diff_run_test.sh — tests/diff_run.sh, the differential run, on two copies of this tree at different
# paths. (1) Every fixture on disk builds, and the copies compare clean, next's and status's
# run-times.tsv rows included. (2) With copy b changed, the run exits 1 naming the fixture and stream
# for one byte of stdout, a stdout line moved to stderr, a changed exit code, an extra file, one byte of
# a file both write, a written file deleted, a built file deleted, a run-times.tsv row's command
# column, that row missing, an extra gh call and an extra herdr call. (3) A time stamp is masked, but a
# one-byte change on its line is red. (4) An unanswered gh call fails with the shim's own line while a
# real gh sits on PATH, the caller's or a fixture's own, and a stub's answer reaches the command.
# (5) A gh call a backgrounded child makes after the command exits is compared, in its step, and a process alive
# past --bound is red by its argv. (6) A copy's swarm.sh that forks past --max-procs is killed and
# named, and none of its processes is left; a stub's own gh call is refused, so none loops back
# through the shim; a command past --timeout is killed and named; and a tree with no plugin.json
# still compares.
# And two calls whose arguments split differently log different lines, a file the command writes
# after a build that wrote none is compared by its content, a line of a file that looks like a header
# masks nothing nor passes for another file, nor moves where one ends, a symbolic link is compared by
# its target, a run-times.tsv row keeps a missing newline, a tree path with a space is replaced in a
# logged call, the run's own paths in a written file compare clean, and masked names set no order.
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

# Two copies at paths of different lengths, of what the fixtures run: bin/, hooks/, templates/, the
# plugin manifest and the harness with its fixtures. A copy of the whole tree takes a minute on a Mac
# that scans each new file.
# Each copy also gets tests/merge_fixture.sh, whose project and stubs the merge fixtures build on.
A="${ROOT}/a" B="${ROOT}/copies/b"
for t in "${A}" "${B}"; do
  mkdir -p "${t}/tests"
  (cd "${REPO}" && tar -cf - bin hooks templates .claude-plugin tests/diff_run.sh tests/diff_fixtures_*.sh) | tar -C "${t}" -xf -
  cp "${REPO}/tests/merge_fixture.sh" "${t}/tests/"
done

# run <rc> [diff_run args...] — run a's diff_run.sh, its output in ${ROOT}/out, and check its exit.
run() {
  local want="$1" rc=0; shift
  bash "${A}/tests/diff_run.sh" "$@" > "${ROOT}/out" 2>&1 &
  DR_PID=$!; wait "${DR_PID}" || rc=$?; DR_PID=""
  [[ ${rc} == "${want}" ]] || { echo "exit ${rc}, not ${want}"; return 1; }
}
# diffs — the DIFF lines of the last run, one per line, sorted.
diffs() { sed -n 's/^DIFF //p' "${ROOT}/out" | LC_ALL=C sort | tr '\n' ';'; }

# mutate <tree> <file> <old> <new> — replace the text <old> in <tree>/<file> with <new>, after a copy
# to <file>.orig that restore puts back. An <old> the file lacks fails the test: the file is not what
# this test thinks.
mutated=()
mutate() {
  grep -qF -- "$3" "$1/$2" || { echo "FAIL mutate: no '$3' in $2"; exit 1; }
  [[ -e "$1/$2.orig" ]] || { cp "$1/$2" "$1/$2.orig"; mutated+=("$1/$2"); }
  DR_OLD="$3" DR_NEW="$4" perl -pi -e 's/\Q$ENV{DR_OLD}\E/$ENV{DR_NEW}/' "$1/$2"
}
restore() { local f; for f in ${mutated[@]+"${mutated[@]}"}; do mv "${f}.orig" "${f}"; done; mutated=(); }

# expect <name> <fixture> <DIFF streams, ;-separated and sorted> — b as mutated is red on exactly
# those streams of <fixture>; then b is restored.
expect() {
  local got
  if ! run 1 "${A}" "${B}" "$2" > "${ROOT}/why"; then bad "$1" "$(cat "${ROOT}/why")"
  elif got="$(diffs)" && [[ "${got}" != "$3" ]]; then bad "$1" "DIFF lines '${got}', not '$3'"
  else ok "$1"; fi
  restore
}

# (1) Clean, on every fixture on disk, with the rows next and status log compared as masked.
KEEP="${ROOT}/keep"
if run 0 --keep "${KEEP}" "${A}" "${B}" > "${ROOT}/why"; then ok "two copies compare clean"; else bad "two copies compare clean" "$(cat "${ROOT}/why")"; fi
for fx in usage next status; do
  if grep -qxF "same ${fx}" "${ROOT}/out"; then ok "${fx} ran"; else bad "${fx} ran" "no 'same ${fx}' line"; fi
done
for fx in next status; do
  row="$(printf '<time>\t%s\t<seconds>\t<load>' "${fx}")"
  for side in a b; do
    if grep -qxF -- "${row}" "${KEEP}/${fx}/${side}/files"; then ok "${fx}'s run-times row compared (${side})"
    else bad "${fx}'s run-times row compared (${side})" "no row in: $(cat "${KEEP}/${fx}/${side}/files")"; fi
  done
done
rm -rf "${KEEP}"

# (2) One change to b at a time.
NEXT_ARM='    next)   timed next next_report ;;'
arm() { printf '    next)   timed next next_report; %s ;;' "$1"; }
mutate "${B}" bin/lib/board.sh 'echo "done"; echo "nothing is open' 'echo "dune"; echo "nothing is open'
expect "one byte of stdout" next "next stdout;"
mutate "${B}" bin/lib/board.sh 'echo "done"; echo "nothing is open' 'echo "done" >&2; echo "nothing is open'
expect "a stdout line moved to stderr" next "next stderr;next stdout;"
mutate "${B}" bin/swarm.sh "${NEXT_ARM}" "$(arm 'exit 3')"
expect "a changed exit code" next "next exit;"
mutate "${B}" bin/swarm.sh "${NEXT_ARM}" "$(arm ': > "${PROJECT_DIR}/.swarm/extra"')"
expect "one extra file" next "next files;"
mutate "${B}" bin/swarm.sh "'%s\t%s\t%d.%03d\t%s\n'" "'%s\t%s\t%d,%03d\t%s\n'"
expect "one byte of a file both write (run-times.tsv's seconds, past their mask's shape)" next "next files;"
mutate "${B}" bin/swarm.sh "${NEXT_ARM}" "$(arm 'rm -f "${RUN_TIMES_LOG}"')"
expect "a written file deleted" next "next files;"
mutate "${B}" bin/swarm.sh "${NEXT_ARM}" "$(arm 'rm -f "${CONFIG_FILE}"')"
expect "a built file deleted" next "next files;"
mutate "${B}" bin/swarm.sh "${NEXT_ARM}" '    next)   timed nexu next_report ;;'
expect "a run-times.tsv row's command column changed" next "next files;"
mutate "${B}" bin/swarm.sh "${NEXT_ARM}" '    next)   next_report ;;'
expect "a run-times.tsv row missing" next "next files;"
# swarm.sh's own gh-shim logs the call to .swarm/gh-calls.tsv, a file a's run does not write.
mutate "${B}" bin/swarm.sh "${NEXT_ARM}" "$(arm 'gh api extra > /dev/null 2>&1 || true')"
expect "one extra gh call" next "next calls:fg;next files;"
mutate "${B}" bin/swarm.sh "${NEXT_ARM}" "$(arm '"${HERDR_BIN_PATH}" agent list > /dev/null 2>&1 || true')"
expect "one extra herdr call" next "next calls:fg;"

# (3) Two different time stamps on one stderr line compare clean; one byte more on that line is red.
mutate "${A}" bin/swarm.sh "${NEXT_ARM}" "$(arm 'echo "at 2026-01-01T00:00:00Z: x" >&2')"
mutate "${B}" bin/swarm.sh "${NEXT_ARM}" "$(arm 'echo "at 2027-12-31T23:59:59Z: x" >&2')"
if run 0 "${A}" "${B}" next > "${ROOT}/why"; then ok "a time stamp is masked"; else bad "a time stamp is masked" "$(cat "${ROOT}/why")"; fi
restore
mutate "${A}" bin/swarm.sh "${NEXT_ARM}" "$(arm 'echo "at 2026-01-01T00:00:00Z: x" >&2')"
mutate "${B}" bin/swarm.sh "${NEXT_ARM}" "$(arm 'echo "at 2027-12-31T23:59:59Z: y" >&2')"
expect "a one-byte change on a masked time stamp's line" next "next stderr;"

# Fixtures of this test's own, in a's checkout: diff_run.sh loads them by its glob.
cat > "${A}/tests/diff_fixtures_probe.sh" <<'FX'
# shellcheck shell=bash disable=SC2034
fx_probe_gh() { FX_CMD=(gh api user); }
fx_probe_stub() { printf '#!/bin/sh\necho "answered: $*"\n' > "${ROOT}/gh-stub"; chmod +x "${ROOT}/gh-stub"; FX_GH="${ROOT}/gh-stub"; FX_CMD=(gh api user); }
fx_probe_late() { FX_CMD=(bash "${TREE}/late.sh"); }
fx_probe_args() { FX_CMD=(bash "${TREE}/args.sh"); }
fx_probe_write() { FX_CMD=(bash "${TREE}/write.sh"); }
fx_probe_path() { FX_CMD=(bash "${TREE}/path.sh"); }
fx_probe_env() { FX_CMD=(sh -c 'echo "${PATH} ${GH_CONFIG_DIR} ${HERDR_BIN_PATH}" > env.txt'); }
fx_probe_reenter() { printf '#!/bin/sh\ngh api again\n' > "${ROOT}/gh-stub"; chmod +x "${ROOT}/gh-stub"; FX_GH="${ROOT}/gh-stub"; FX_CMD=(gh api user); }
fx_probe_slow() { FX_CMD=(sleep 20); }
FX
# A fixture whose own PATH puts the real gh first.
printf 'fx_probe_envpath() { FX_ENV=("PATH=%s:/usr/bin:/bin"); FX_CMD=(gh api user); }\n' "${ROOT}/real" >> "${A}/tests/diff_fixtures_probe.sh"

# (4) A real gh first on the caller's PATH, which the shim never runs.
mkdir -p "${ROOT}/real"
printf '#!/bin/sh\necho "the real gh ran"\n: > "%s/real/ran"\n' "${ROOT}" > "${ROOT}/real/gh"; chmod +x "${ROOT}/real/gh"
K="${ROOT}/keep"
if PATH="${ROOT}/real:${PATH}" run 0 --keep "${K}" "${A}" "${B}" probe_gh probe_stub probe_envpath > "${ROOT}/why"; then
  if [[ "$(cat "${K}/probe_gh/a/exit")" != 0 ]] && grep -qF 'diff_run: no stub answers this gh call, so it fails; a real gh is never run: gh api user' "${K}/probe_gh/a/stderr" \
    && [[ ! -s "${K}/probe_gh/a/stdout" && ! -e "${ROOT}/real/ran" ]]; then ok "an unanswered gh call fails with the shim's line"
  else bad "an unanswered gh call fails with the shim's line" "exit $(cat "${K}/probe_gh/a/exit"), stderr: $(cat "${K}/probe_gh/a/stderr"), stdout: $(cat "${K}/probe_gh/a/stdout")"; fi
  if [[ "$(cat "${K}/probe_gh/a/calls:fg")" == "gh api user" ]]; then ok "the unanswered call is logged"; else bad "the unanswered call is logged" "calls: $(cat "${K}/probe_gh/a/calls:fg")"; fi
  if grep -qF 'diff_run: no stub answers this gh call' "${K}/probe_envpath/a/stderr" && [[ ! -s "${K}/probe_envpath/a/stdout" && ! -e "${ROOT}/real/ran" ]]; then
    ok "a fixture's own PATH goes behind the shims"
  else bad "a fixture's own PATH goes behind the shims" "stderr: $(cat "${K}/probe_envpath/a/stderr"), stdout: $(cat "${K}/probe_envpath/a/stdout")"; fi
  if [[ "$(cat "${K}/probe_stub/a/stdout")" == "answered: api user" ]]; then ok "a stub answers the shim's call"; else bad "a stub answers the shim's call" "stdout: $(cat "${K}/probe_stub/a/stdout")"; fi
else bad "an unanswered gh call fails with the shim's line" "$(cat "${ROOT}/why")"; fi
rm -rf "${K}"

# (5) A child the command leaves running calls gh a second after the command exits.
late() { printf '(sleep 1; gh api %s > /dev/null 2>&1) &\n%s\nexit 0\n' "$2" "${3-}" > "$1/late.sh"; }
late "${A}" late-a; late "${B}" late-b
# Its step is labelled by its argv and first call, so each side's step is one the other lacks.
if run 1 "${A}" "${B}" probe_late > "${ROOT}/why" \
  && [[ "$(diffs)" == "probe_late calls:[bash <tree>/late.sh] gh api late-a;probe_late calls:[bash <tree>/late.sh] gh api late-b;" ]] \
  && grep -qxF '+gh api late-b' "${ROOT}/out"; then ok "a backgrounded child's late gh call is compared, in its step"
else bad "a backgrounded child's late gh call is compared, in its step" "$(cat "${ROOT}/why")"; fi
late "${A}" late-a "sleep 37.25 & echo \$! > ${A}/stuck.pid"; late "${B}" late-a "sleep 37.25 & echo \$! > ${B}/stuck.pid"
if run 1 --bound 2 "${A}" "${B}" probe_late > "${ROOT}/why" && grep -qE '^STUCK probe_late \(a\): still running 2s after the command exited: sleep 37.25$' "${ROOT}/out" \
  && grep -qE '^STUCK probe_late \(b\): ' "${ROOT}/out"; then ok "a process past the bound is red by its argv"
else bad "a process past the bound is red by its argv" "$(cat "${ROOT}/why")"; fi
# This run's own sleeps, by the pids late.sh wrote, so another run's never counts.
for t in "${A}" "${B}"; do
  if [[ -s "${t}/stuck.pid" ]] && ! ps -p "$(cat "${t}/stuck.pid")" > /dev/null; then ok "the stuck process was killed (${t##*/})"
  else echo "FAIL the stuck process was killed (${t##*/}): pid $(cat "${t}/stuck.pid" 2>/dev/null) still runs, or none was written"; fails=$((fails + 1)); fi
done

# Two calls whose arguments differ only in where one splits log two different lines.
printf 'gh api x -f "title=a b"\n' > "${A}/args.sh"; printf 'gh api x -f title=a b\n' > "${B}/args.sh"
expect "argument boundaries in a logged call" probe_args "probe_args calls:fg;"
# A build that leaves no file, then a command that writes one: its content is compared.
printf 'printf abc > result\n' > "${A}/write.sh"; printf 'printf abd > result\n' > "${B}/write.sh"
expect "a file written after a build that wrote none" probe_write "probe_write files;"
# A line of a file that looks like a run-times.tsv header does not mask the lines after it.
printf 'printf "==> /r/.swarm/run-times.tsv <==\\nt\\tnext\\t1.234\\t0.1\\n" > result\n' > "${A}/write.sh"
printf 'printf "==> /r/.swarm/run-times.tsv <==\\nt\\tnext\\t9.234\\t0.1\\n" > result\n' > "${B}/write.sh"
expect "a file's content cannot pass for a header" probe_write "probe_write files;"
# One file whose content holds a second file's header, against those two files.
printf 'printf "a\\n\\n==> %%s/y <==\\nb\\n" "$(pwd -P)" > x\n' > "${A}/write.sh"; printf 'printf "a\\n" > x; printf "b\\n" > y\n' > "${B}/write.sh"
expect "a file's content cannot pass for another file" probe_write "probe_write files;"
# The same two files on both sides, with a line of y's header moved from x's content into y's.
printf 'printf "a\\n==> %%s/y <==\\nb" "$(pwd -P)" > x; printf c > y\n' > "${A}/write.sh"
printf 'printf a > x; printf "b\\n==> %%s/y <==\\nc" "$(pwd -P)" > y\n' > "${B}/write.sh"
expect "where one file's content ends" probe_write "probe_write files;"
printf 'ln -s t1 link\n' > "${A}/write.sh"; printf 'ln -s t2 link\n' > "${B}/write.sh"
expect "a symbolic link's target" probe_write "probe_write files;"
printf 'mkdir .swarm; printf "2026-01-01T00:00:00Z\\tnext\\t1.234\\t0.5\\n" > .swarm/run-times.tsv\n' > "${A}/write.sh"
printf 'mkdir .swarm; printf "2026-01-01T00:00:00Z\\tnext\\t1.234\\t0.5" > .swarm/run-times.tsv\n' > "${B}/write.sh"
expect "a run-times.tsv row's missing newline" probe_write "probe_write files;"
# Two temp files whose names a mask makes the same, their suffixes in the other order on b's side.
printf 'printf x > tmp/tmp.AAAAAA; printf y > tmp/tmp.ZZZZZZ\n' > "${A}/write.sh"; printf 'printf y > tmp/tmp.AAAAAA; printf x > tmp/tmp.ZZZZZZ\n' > "${B}/write.sh"
if run 0 "${A}" "${B}" probe_write > "${ROOT}/why"; then ok "masked names set no order"; else bad "masked names set no order" "$(cat "${ROOT}/why")"; fi

# b at a path with a space: a gh call naming a path under it logs the same line as a's.
mv "${B}" "${ROOT}/copies/b c"; B="${ROOT}/copies/b c"
for t in "${A}" "${B}"; do printf 'gh api "$(cd "$(dirname "$0")" && pwd -P)/result" "$(pwd -P)/x"\n' > "${t}/path.sh"; done
if run 0 "${A}" "${B}" probe_path > "${ROOT}/why"; then ok "a tree path with a space is replaced in a logged call"
else bad "a tree path with a space is replaced in a logged call" "$(cat "${ROOT}/why")"; fi

# The run's own paths that reach the command (the shims, GH_CONFIG_DIR) differ by side; a file that
# records them compares clean.
if run 0 "${A}" "${B}" probe_env > "${ROOT}/why"; then ok "the run's own paths in a written file compare clean"
else bad "the run's own paths in a written file compare clean" "$(cat "${ROOT}/why")"; fi

# A copy whose swarm.sh next starts 300 sleeps: the run kills its group once it passes --max-procs,
# and names it. The sleeps' pids are in ${B}/pids, so this checks each is gone, and kills any left
# (they are in the command's own group, which the EXIT trap's stop_test_group does not reach).
mutate "${B}" bin/swarm.sh "${NEXT_ARM}" "$(arm "for i in \$(seq 300); do sleep 31.5 & echo \$! >> '${B}/pids'; done; wait")"
if run 1 --max-procs 100 "${A}" "${B}" next > "${ROOT}/why" \
  && grep -qE '^RUNAWAY next \(b\): more than 100 processes in its group; killed; it ran: .*sleep 31.5' "${ROOT}/out"; then
  ok "a copy's swarm.sh that forks past --max-procs is killed and named"
else bad "a copy's swarm.sh that forks past --max-procs is killed and named" "$(cat "${ROOT}/why")"; fi
restore
left=""; while read -r p; do ps -p "${p}" > /dev/null && left+=" ${p}"; done < "${B}/pids"
if [[ -s "${B}/pids" && -z "${left}" ]]; then ok "every process of the killed group is gone"
else echo "FAIL every process of the killed group is gone: still running:${left:- none were recorded}"; fails=$((fails + 1))
  for p in ${left}; do kill -KILL "${p}" 2>/dev/null || true; done; fi
rm -f "${B}/pids"

# A stub that calls gh again is refused by the shim, so no stub loops back through it.
K="${ROOT}/keep"
if run 0 --max-procs 50 --keep "${K}" "${A}" "${B}" probe_reenter > "${ROOT}/why" \
  && grep -qF "diff_run: the gh shim was called again from inside gh's stub, so it fails: gh api again" "${K}/probe_reenter/a/stderr" \
  && [[ "$(cat "${K}/probe_reenter/a/calls:fg")" == "gh api user"$'\n'"gh re-entered from gh" && "$(cat "${K}/probe_reenter/a/exit")" != 0 ]]; then
  ok "a stub's own gh call is refused"
else bad "a stub's own gh call is refused" "$(cat "${ROOT}/why"; cat "${K}/probe_reenter/a/stderr" "${K}/probe_reenter/a/calls:fg" 2>/dev/null)"; fi
rm -rf "${K}"
# A tree with no plugin.json: no version to replace, and the run still compares.
mv "${B}/.claude-plugin/plugin.json" "${B}/plugin.json.aside"
if run 0 "${A}" "${B}" probe_gh > "${ROOT}/why"; then ok "a tree with no plugin.json still compares"; else bad "a tree with no plugin.json still compares" "$(cat "${ROOT}/why")"; fi
mv "${B}/plugin.json.aside" "${B}/.claude-plugin/plugin.json"
# A command that outlives --timeout is killed and named.
if run 1 --timeout 1 "${A}" "${B}" probe_slow > "${ROOT}/why" && grep -qE '^TIMEOUT probe_slow \(a\): still running after 1s; killed; it ran: .*sleep 20' "${ROOT}/out"; then
  ok "a command past --timeout is killed and named"
else bad "a command past --timeout is killed and named" "$(cat "${ROOT}/why")"; fi

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
