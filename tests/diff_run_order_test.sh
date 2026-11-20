#!/usr/bin/env bash
# diff_run_order_test.sh — tests/diff_run.sh's order of stub calls, on two copies of the harness at
# different paths. (1) Three fixtures whose gh calls from the background land at a random point among
# the foreground's (an anonymous `( ... ) &` subshell, a detached `nohup bash swarm.sh ... &` run and
# a setsid'd run, launched as bin/lib/lifecycle.sh launches its own) compare clean ten runs in ten,
# each step in a stream of its own, and each is red under one global order (the harness changed to
# put every call on calls:fg). (2) Two foreground calls swapped in one copy are red on calls:fg, and
# two calls swapped within a background step are red on that step, by its label. (3) A stub whose
# answer alternates by run is red under --times 2, run 2 against run 1, and clean under --times 1.
# A setsid'd step whose calls come a second after the command exits is waited for, and a setsid'd
# process past --bound is red by its argv and killed. A worker whose launcher exits between its
# calls, or before its first, keeps the launcher's step; a background bash that runs exec gh, or the
# command's own background gh, is a step whether the command still runs or not; and a foreground call
# inside two nested process groups is on calls:fg. Foreground calls through a wrapper that runs gh as
# a waited background job (bin/gh-shim/gh's way), answered by a bash stub, stay on calls:fg, in
# order, and so do calls made after trap '' INT and the calls of subshells the command waits on at
# once, so two such subshells swapped are red; on Linux, a subshell whose parent is blocked opening a
# FIFO is a step all the same. And a step that ends before the command exits gives the same
# streams, ten runs in ten, as one that ends after.
# shellcheck disable=SC2016 # the copies' scripts and the harness's perl, expanded when a run runs them
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
# Each diff_run.sh still running gets a TERM and is waited on first: its own EXIT trap kills the
# fixture commands' groups and marked processes, which stop_test_group, holding only this test's
# group, never reaches.
DR_PIDS=""
# shellcheck disable=SC2329 # the EXIT trap calls it
# Each kill and wait is best-effort: a run already gone, or a wait that returns 143, must not stop the
# trap under set -e before the rest of it runs.
stop_runs() { local p; for p in ${DR_PIDS}; do kill -TERM "${p}" 2>/dev/null || true; wait "${p}" 2>/dev/null || true; done; DR_PIDS=""; }
trap 'stop_runs; stop_test_group; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
export HOME="${ROOT}/home"; mkdir -p "${HOME}"
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1: $2"; fails=$((fails + 1)); }

# Two copies of the harness. The fixtures' commands are scripts in each copy, so a change to one
# copy's script is a change to that tree.
A="${ROOT}/a" B="${ROOT}/copies/b"
for t in "${A}" "${B}"; do mkdir -p "${t}/tests" "${t}/bin"; cp "${REPO}/tests/diff_run.sh" "${t}/tests/"; done
cat > "${A}/tests/diff_fixtures_order.sh" <<'FX'
# shellcheck shell=bash disable=SC2034
fx_order_sub() { FX_CMD=(bash "${TREE}/sub.sh"); }
fx_order_det() { FX_CMD=(bash "${TREE}/det.sh"); }
fx_order_set() { FX_CMD=(bash "${TREE}/set.sh"); }
fx_order_setlate() { FX_CMD=(bash "${TREE}/setlate.sh"); }
fx_order_nest() { FX_CMD=(bash "${TREE}/nest.sh"); }
fx_order_gone() { FX_CMD=(bash "${TREE}/gone.sh"); }
fx_order_exec() { FX_CMD=(bash "${TREE}/exec.sh"); }
fx_order_solo() { FX_CMD=(bash "${TREE}/solo.sh"); }
fx_order_mask() { FX_CMD=(bash "${TREE}/mask.sh"); }
fx_order_stuck() { FX_CMD=(bash "${TREE}/stuck.sh"); }
fx_order_waited() { FX_CMD=(bash "${TREE}/waited.sh"); }
fx_order_read() { FX_CMD=(bash "${TREE}/read.sh"); }
# A bash stub, as tests/merge_fixture.sh writes, behind a wrapper that runs gh as bin/gh-shim/gh does.
fx_order_wrap() { FX_GH="${TREE}/bash-stub"; FX_CMD=(bash "${TREE}/wrap.sh"); }
fx_order_within() { FX_CMD=(bash "${TREE}/within.sh"); }
fx_order_step() { FX_CMD=(bash "${TREE}/step.sh"); }
fx_order_alt() { FX_GH="${TREE}/alt-stub"; FX_CMD=(gh api x); }
FX

# fg_calls [<first> <second>...] — the foreground's four gh calls, a short sleep after each, in the
# order given (default fg-1 to fg-4).
fg_calls() {
  local c calls=("$@")
  [[ $# -gt 0 ]] || calls=(fg-1 fg-2 fg-3 fg-4)
  for c in "${calls[@]}"; do printf 'gh api %s > /dev/null 2>&1; sleep 0.05\n' "${c}"; done
}
# step_calls <name> [<n>...] — a step's three gh calls (<name>-1 to <name>-3, or in the order of the
# <n> given), after a random sleep of up to 0.3 s, so they land anywhere among the foreground's.
step_calls() {
  local name="$1" n ns; shift
  ns=("$@"); [[ $# -gt 0 ]] || ns=(1 2 3)
  printf 'sleep "0.$((RANDOM %% 4))"\n'
  for n in "${ns[@]}"; do printf 'gh api %s-%s > /dev/null 2>&1\n' "${name}" "${n}"; done
}
# trees — each copy's scripts, as both start: sub.sh forks an anonymous subshell; det.sh starts
# bin/swarm.sh detached under nohup; set.sh starts it setsid'd through python3, as
# bin/lib/lifecycle.sh's detached runs do. bin/swarm.sh is a stand-in that makes the step's calls.
# step.sh is the step that ends before the command exits on a's side and after it on b's.
trees() {
  local t
  for t in "${A}" "${B}"; do
    { echo '('; step_calls sub; echo ') > /dev/null 2>&1 &'; fg_calls; } > "${t}/sub.sh"
    { echo 'case "$1" in'; echo 'det) :'; step_calls det; echo ';;'; echo 'set) :'; step_calls set; echo ';;'
      echo 'late) sleep 1; gh api late-1 > /dev/null 2>&1; gh api late-2 > /dev/null 2>&1 ;;'; echo 'esac'; } > "${t}/bin/swarm.sh"
    { echo 'nohup bash "$(dirname "$0")/bin/swarm.sh" det < /dev/null > /dev/null 2>&1 &'; fg_calls; } > "${t}/det.sh"
    { echo "nohup python3 -I -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \\"
      echo '  bash "$(dirname "$0")/bin/swarm.sh" set < /dev/null > /dev/null 2>&1 &'; fg_calls; } > "${t}/set.sh"
    # A setsid'd step whose calls all come a second after the command has exited.
    { echo "nohup python3 -I -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \\"
      echo '  bash "$(dirname "$0")/bin/swarm.sh" late < /dev/null > /dev/null 2>&1 &'; echo 'exit 0'; } > "${t}/setlate.sh"
    # A launcher that starts a worker and exits between the worker's first call and its second. The gaps
# are seconds wide, so a slow process start on a loaded machine still lands each call where meant.
    printf '( bash "$(dirname "$0")/worker.sh" & sleep 2 ) > /dev/null 2>&1 &\nexit 0\n' > "${t}/nest.sh"
    printf 'gh api w-1 > /dev/null 2>&1\nsleep 3\ngh api w-2 > /dev/null 2>&1\ngh api w-3 > /dev/null 2>&1\n' > "${t}/worker.sh"
    # A launcher that exits before its worker's first call.
    printf '( bash "$(dirname "$0")/late-worker.sh" & sleep 4 ) > /dev/null 2>&1 &\nexit 0\n' > "${t}/gone.sh"
    printf 'sleep 6\ngh api v-1 > /dev/null 2>&1\ngh api v-2 > /dev/null 2>&1\n' > "${t}/late-worker.sh"
    # Two wrappers, each running its command in a group of its own (as bin/lib/merge.sh's within does),
    # one inside the other, on the foreground path.
    printf '%s\n' "perl -e 'if (!fork) { setpgrp; exec @ARGV } wait; exit(\$? >> 8)' bash \"\$(dirname \"\$0\")/mid.sh\"" > "${t}/within.sh"
    printf '%s\n' "perl -e 'if (!fork) { setpgrp; exec @ARGV } wait; exit(\$? >> 8)' sh -c 'gh api in-1 > /dev/null 2>&1; exit 0'" > "${t}/mid.sh"
    printf '#!/bin/sh\nn=$(($(cat "%s/count" 2>/dev/null || echo 0) + 1)); echo "${n}" > "%s/count"\necho "answer $((n %% 2))"\n' "${t}" "${t}" > "${t}/alt-stub"
    chmod +x "${t}/alt-stub"; rm -f "${t}/count"
    printf '#!/usr/bin/env bash\necho "stub: $*"\n' > "${t}/bash-stub"; chmod +x "${t}/bash-stub"
    printf '#!/usr/bin/env bash\ngh "$@" <&0 &\nwait "$!"\n' > "${t}/bin/gh-wrap"
    wrap "${t}" w-1 w-2 w-3
  done
  # A background bash that runs exec gh: on a's side while the command still runs, on b's once it has
  # exited.
  printf '%s\n' "bash -c 'sleep 0.3; exec gh api ex-1 > /dev/null 2>&1' &" 'sleep 2' 'exit 0' > "${A}/exec.sh"
  printf '%s\n' "bash -c 'sleep 0.5; exec gh api ex-1 > /dev/null 2>&1' &" 'exit 0' > "${B}/exec.sh"
  # The command's own background gh, run in the subshell's pid: on a's side while the command still
  # runs, on b's once it has exited.
  printf '%s\n' '(exec gh api solo > /dev/null 2>&1) &' 'sleep 2' 'exit 0' > "${A}/solo.sh"
  printf '%s\n' '(sleep 0.5; exec gh api solo > /dev/null 2>&1) &' 'exit 0' > "${B}/solo.sh"
  # a: the step ends (it leaves done) before the command makes its last call and exits.
  printf '( gh api st-1; gh api st-2; : > done ) > /dev/null 2>&1 &\nwhile [ ! -e done ]; do sleep 0.05; done\ngh api fg-1 > /dev/null 2>&1\nexit 0\n' > "${A}/step.sh"
  # b: the command makes that call and exits first; the step's calls come once it has gone.
  printf 'gh api fg-1 > /dev/null 2>&1\n( sleep 0.3; gh api st-1; gh api st-2; : > done ) > /dev/null 2>&1 &\nexit 0\n' > "${B}/step.sh"
}

# wrap <tree> <call>... — wrap.sh: each call through the gh-shim-like wrapper, in the order given.
wrap() {
  local t="$1" c; shift
  for c in "$@"; do printf 'bash "$(dirname "$0")/bin/gh-wrap" api %s > /dev/null 2>&1\n' "${c}"; done > "${t}/wrap.sh"
}

# start <out> <harness> [args...] — run <harness> (a copy of diff_run.sh) in the background, its
# output in <out> and its exit code in <out>.rc once it ends.
# The harness itself is the background job, so the EXIT trap's TERM reaches its own trap.
STARTED=()
start() {
  local out="$1" h="$2"; shift 2
  bash "${h}" "$@" > "${out}" 2>&1 &
  DR_PIDS+=" $!"; STARTED+=("$!:${out}")
}
# finish — wait for every run start began, and write each one's exit code.
finish() {
  local e rc
  for e in ${STARTED[@]+"${STARTED[@]}"}; do rc=0; wait "${e%%:*}" || rc=$?; echo "${rc}" > "${e#*:}.rc"; done
  STARTED=(); DR_PIDS=""
}
# rc_of <out> — the exit code start wrote, or "none".
rc_of() { cat "$1.rc" 2>/dev/null || echo none; }
# diffs <out> — the DIFF lines of a run, one per line, sorted.
diffs() { sed -n 's/^DIFF //p' "$1" | LC_ALL=C sort | tr '\n' ';'; }
# field <file> — a kept stream's lines joined with ;.
field() { tr '\n' ';' < "$1" 2>/dev/null; }

# One global order: the harness changed to put every call on calls:fg, in the order the calls came.
GLOBAL="${A}/tests/diff_run_global.sh"
cp "${A}/tests/diff_run.sh" "${GLOBAL}"
for old in 'if ($path eq "fg") {' 'if ($end eq "top") {'; do
  grep -qF -- "${old}" "${GLOBAL}" || { echo "FAIL the global-order copy: no '${old}' in tests/diff_run.sh"; exit 1; }
  DR_OLD="${old}" perl -pi -e 's/\Q$ENV{DR_OLD}\E/if (1) {/' "${GLOBAL}"
done

# (1), and the step that ends early or late: three runs at once, each mostly asleep.
trees
K="${ROOT}/keep" KS="${ROOT}/keep-step" KL="${ROOT}/keep-late" KN="${ROOT}/keep-nest"
start "${ROOT}/clean" "${A}/tests/diff_run.sh" --times 10 --keep "${K}" "${A}" "${B}" order_sub order_det order_set
start "${ROOT}/global" "${GLOBAL}" --times 10 "${A}" "${B}" order_sub order_det order_set
start "${ROOT}/step" "${A}/tests/diff_run.sh" --times 10 --keep "${KS}" "${A}" "${B}" order_step
start "${ROOT}/late" "${A}/tests/diff_run.sh" --times 2 --keep "${KL}" "${A}" "${B}" order_setlate
start "${ROOT}/nest" "${A}/tests/diff_run.sh" --times 3 --keep "${KN}" "${A}" "${B}" order_nest order_gone order_within order_exec order_solo
finish
if [[ "$(rc_of "${ROOT}/clean")" == 0 ]]; then ok "three fixtures with background steps compare clean ten runs in ten"
else bad "three fixtures with background steps compare clean ten runs in ten" "exit $(rc_of "${ROOT}/clean"): $(cat "${ROOT}/clean")"; fi
for fx in sub det set; do
  if grep -qxF "same order_${fx}" "${ROOT}/clean"; then ok "order_${fx} ran clean"; else bad "order_${fx} ran clean" "no 'same order_${fx}' line"; fi
done
# Each step's calls in a stream of their own, the foreground's on calls:fg, on both sides.
want_fg="gh api fg-1;gh api fg-2;gh api fg-3;gh api fg-4;"
for side in a b; do
  for row in "sub|[bash <tree>/sub.sh] gh api sub-1" "det|[bash <tree>/bin/swarm.sh det] gh api det-1" "set|[bash <tree>/bin/swarm.sh set] gh api set-1"; do
    fx="${row%%|*}" label="${row#*|}"
    if [[ "$(cat "${K}/order_${fx}/${side}/steps" 2>/dev/null)" == "${label}" \
      && "$(field "${K}/order_${fx}/${side}/step.1")" == "gh api ${fx}-1;gh api ${fx}-2;gh api ${fx}-3;" \
      && "$(field "${K}/order_${fx}/${side}/calls:fg")" == "${want_fg}" ]]; then ok "order_${fx}'s step has a stream of its own (${side})"
    else bad "order_${fx}'s step has a stream of its own (${side})" "steps: $(cat "${K}/order_${fx}/${side}/steps" 2>/dev/null), calls:fg: $(field "${K}/order_${fx}/${side}/calls:fg" 2>/dev/null)"; fi
  done
done
if [[ "$(rc_of "${ROOT}/global")" == 1 ]]; then ok "under one global order the run is red"
else bad "under one global order the run is red" "exit $(rc_of "${ROOT}/global"): $(cat "${ROOT}/global")"; fi
for fx in sub det set; do
  if grep -q "^DIFF order_${fx} calls:fg" "${ROOT}/global"; then ok "order_${fx} is red under one global order"
  else bad "order_${fx} is red under one global order" "no DIFF order_${fx} calls:fg line in: $(cat "${ROOT}/global")"; fi
done
if [[ "$(rc_of "${ROOT}/step")" == 0 && "$(cat "${KS}/order_step/a/steps" 2>/dev/null)" == "[bash <tree>/step.sh] gh api st-1" \
  && "$(field "${KS}/order_step/b/step.1")" == "gh api st-1;gh api st-2;" && "$(field "${KS}/order_step/b/calls:fg")" == "gh api fg-1;" ]]; then
  ok "a step that ends before the command exits gives the same streams as one that ends after, ten runs in ten"
else bad "a step that ends before the command exits gives the same streams as one that ends after, ten runs in ten" \
  "exit $(rc_of "${ROOT}/step"): $(cat "${ROOT}/step"); a steps: $(cat "${KS}/order_step/a/steps" 2>/dev/null)"; fi
# A setsid'd run leaves the command's group, so only its marker keeps the run waiting for its calls.
if [[ "$(rc_of "${ROOT}/late")" == 0 && "$(cat "${KL}/order_setlate/a/steps" 2>/dev/null)" == "[bash <tree>/bin/swarm.sh late] gh api late-1" \
  && "$(field "${KL}/order_setlate/b/step.1")" == "gh api late-1;gh api late-2;" && ! -s "${KL}/order_setlate/a/calls:fg" ]]; then
  ok "a setsid'd step whose calls come after the command exits is waited for"
else bad "a setsid'd step whose calls come after the command exits is waited for" \
  "exit $(rc_of "${ROOT}/late"): $(cat "${ROOT}/late"); a steps: $(cat "${KL}/order_setlate/a/steps" 2>/dev/null)"; fi
# A worker's calls stay in one step, its launcher's, whether the launcher still runs or has exited.
if [[ "$(rc_of "${ROOT}/nest")" == 0 && "$(cat "${KN}/order_nest/a/steps" 2>/dev/null)" == "[bash <tree>/nest.sh] gh api w-1" \
  && "$(field "${KN}/order_nest/a/step.1")" == "gh api w-1;gh api w-2;gh api w-3;" ]]; then
  ok "a worker whose launcher exits between its calls keeps one step"
else bad "a worker whose launcher exits between its calls keeps one step" \
  "exit $(rc_of "${ROOT}/nest"): $(cat "${ROOT}/nest"); a steps: $(cat "${KN}/order_nest/a/steps" 2>/dev/null)"; fi
# A worker whose launcher has exited before its first call: still the launcher's step, by its argv.
if grep -qxF "same order_gone" "${ROOT}/nest" && [[ "$(cat "${KN}/order_gone/a/steps" 2>/dev/null)" == "[bash <tree>/gone.sh] gh api v-1" ]]; then
  ok "a worker whose launcher exits before its first call keeps the launcher's step"
else bad "a worker whose launcher exits before its first call keeps the launcher's step" \
  "a steps: $(cat "${KN}/order_gone/a/steps" 2>/dev/null); $(cat "${ROOT}/nest")"; fi
# A background bash that ran exec gh is a step of its own, whether the command still ran or not.
if grep -qxF "same order_exec" "${ROOT}/nest" && [[ "$(field "${KN}/order_exec/a/steps")" == "[bash <run>/meta/shims/gh api ex-1] gh api ex-1;" \
  && ! -s "${KN}/order_exec/a/calls:fg" ]]; then ok "a background bash that runs exec gh is a step, before the command exits or after"
else bad "a background bash that runs exec gh is a step, before the command exits or after" \
  "a steps: $(cat "${KN}/order_exec/a/steps" 2>/dev/null), a calls:fg: $(field "${KN}/order_exec/a/calls:fg"); $(cat "${ROOT}/nest")"; fi
# The command's own background gh is a step, whether the command still ran or not.
if grep -qxF "same order_solo" "${ROOT}/nest" && [[ "$(field "${KN}/order_solo/b/steps")" == "[bash <run>/meta/shims/gh api solo] gh api solo;" \
  && ! -s "${KN}/order_solo/a/calls:fg" ]]; then ok "the command's own background gh is a step, before the command exits or after"
else bad "the command's own background gh is a step, before the command exits or after" \
  "b steps: $(cat "${KN}/order_solo/b/steps" 2>/dev/null), a calls:fg: $(field "${KN}/order_solo/a/calls:fg"); $(cat "${ROOT}/nest")"; fi
# A foreground call inside two nested groups is placed on calls:fg.
if grep -qxF "same order_within" "${ROOT}/nest" && [[ "$(field "${KN}/order_within/a/calls:fg")" == "gh api in-1;" ]]; then
  ok "a foreground call inside two nested groups is on calls:fg"
else bad "a foreground call inside two nested groups is on calls:fg" "$(cat "${ROOT}/nest")"; fi
rm -rf "${K}" "${KS}" "${KL}" "${KN}"

# (2) Two calls swapped on the foreground path, then two within a step, in b's copy only.
{ echo '('; step_calls sub; echo ') > /dev/null 2>&1 &'; fg_calls fg-1 fg-3 fg-2 fg-4; } > "${B}/sub.sh"
start "${ROOT}/swap-fg" "${A}/tests/diff_run.sh" "${A}" "${B}" order_sub; finish
if [[ "$(rc_of "${ROOT}/swap-fg")" == 1 && "$(diffs "${ROOT}/swap-fg")" == "order_sub calls:fg;" ]]; then ok "two foreground calls swapped are red on calls:fg"
else bad "two foreground calls swapped are red on calls:fg" "exit $(rc_of "${ROOT}/swap-fg"): $(cat "${ROOT}/swap-fg")"; fi
{ echo '('; step_calls sub 1 3 2; echo ') > /dev/null 2>&1 &'; fg_calls; } > "${B}/sub.sh"
start "${ROOT}/swap-step" "${A}/tests/diff_run.sh" "${A}" "${B}" order_sub; finish
if [[ "$(rc_of "${ROOT}/swap-step")" == 1 && "$(diffs "${ROOT}/swap-step")" == "order_sub calls:[bash <tree>/sub.sh] gh api sub-1;" ]]; then
  ok "two calls swapped within a step are red on that step, by its label"
else bad "two calls swapped within a step are red on that step, by its label" "exit $(rc_of "${ROOT}/swap-step"): $(cat "${ROOT}/swap-step")"; fi

# Foreground calls through a wrapper that runs gh as a waited background job, answered by a bash stub,
# stay on calls:fg in order: clean as they are, red on calls:fg once two are swapped.
trees
start "${ROOT}/wrap-same" "${A}/tests/diff_run.sh" --keep "${ROOT}/keep-wrap" "${A}" "${B}" order_wrap; finish
if [[ "$(rc_of "${ROOT}/wrap-same")" == 0 && "$(field "${ROOT}/keep-wrap/order_wrap/a/calls:fg")" == "gh api w-1;gh api w-2;gh api w-3;" \
  && ! -s "${ROOT}/keep-wrap/order_wrap/a/steps" ]]; then ok "calls through a waited wrapper to a bash stub stay on calls:fg"
else bad "calls through a waited wrapper to a bash stub stay on calls:fg" \
  "exit $(rc_of "${ROOT}/wrap-same"): $(cat "${ROOT}/wrap-same"); calls:fg: $(field "${ROOT}/keep-wrap/order_wrap/a/calls:fg")"; fi
rm -rf "${ROOT}/keep-wrap"
wrap "${B}" w-1 w-3 w-2
start "${ROOT}/wrap-swap" "${A}/tests/diff_run.sh" "${A}" "${B}" order_wrap; finish
if [[ "$(rc_of "${ROOT}/wrap-swap")" == 1 && "$(diffs "${ROOT}/wrap-swap")" == "order_wrap calls:fg;" ]]; then
  ok "two calls swapped through the waited wrapper are red on calls:fg"
else bad "two calls swapped through the waited wrapper are red on calls:fg" "exit $(rc_of "${ROOT}/wrap-swap"): $(cat "${ROOT}/wrap-swap")"; fi

# A command that ignores SIGINT itself (trap '' INT, as bin/lib/ci_gate.py does in its cleanup) makes
# foreground calls all the same: two swapped are red on calls:fg.
printf '%s\n' "trap '' INT" 'gh api m-1 2> /dev/null' 'gh api m-2 2> /dev/null' 'gh api m-3 2> /dev/null' 'exit 0' > "${A}/mask.sh"
printf '%s\n' "trap '' INT" 'gh api m-1 2> /dev/null' 'gh api m-3 2> /dev/null' 'gh api m-2 2> /dev/null' 'exit 0' > "${B}/mask.sh"
start "${ROOT}/mask" "${A}/tests/diff_run.sh" "${A}" "${B}" order_mask; finish
if [[ "$(rc_of "${ROOT}/mask")" == 1 && "$(diffs "${ROOT}/mask")" == "order_mask calls:fg;" ]]; then
  ok "two calls swapped after trap '' INT are red on calls:fg"
else bad "two calls swapped after trap '' INT are red on calls:fg" "exit $(rc_of "${ROOT}/mask"): $(cat "${ROOT}/mask")"; fi

# A setsid'd process still running past --bound is red by its argv and is killed: it left the group,
# and on macOS ps shows no environment for /bin/sleep, so only the hold pipe finds it. It sleeps far
# longer than the run's kill loop lasts, so only a kill ends it before the check.
for t in "${A}" "${B}"; do
  { echo "nohup python3 -I -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' sleep 300.75 < /dev/null > /dev/null 2>&1 &"
    echo "echo \$! > '${t}/stuck.pid'"; echo 'exit 0'; } > "${t}/stuck.sh"
done
start "${ROOT}/stuck" "${A}/tests/diff_run.sh" --bound 2 "${A}" "${B}" order_stuck; finish
if [[ "$(rc_of "${ROOT}/stuck")" == 1 ]] && grep -qE '^STUCK order_stuck \(a\): still running 2s after the command exited: sleep 300.75$' "${ROOT}/stuck"; then
  ok "a setsid'd process past --bound is red by its argv"
else bad "a setsid'd process past --bound is red by its argv" "exit $(rc_of "${ROOT}/stuck"): $(cat "${ROOT}/stuck")"; fi
for t in "${A}" "${B}"; do
  if [[ -s "${t}/stuck.pid" ]] && ! ps -p "$(cat "${t}/stuck.pid")" > /dev/null; then ok "the setsid'd process was killed (${t##*/})"
  else bad "the setsid'd process was killed (${t##*/})" "pid $(cat "${t}/stuck.pid" 2>/dev/null) still runs, or none was written"
    [[ ! -s "${t}/stuck.pid" ]] || kill -KILL "$(cat "${t}/stuck.pid")" 2>/dev/null || true; fi
done

# Two subshells the command waits on at once (bin/lib/merge.sh runs reconcile and story_note so),
# one of them a single command that bash runs in the subshell's own pid: their calls are on calls:fg
# in place, clean three runs in three, and red on calls:fg once the two are swapped.
# waited <tree> <first> <second> — waited.sh, the a and b subshells in the order given.
waited() {
  local -a sub=([1]='( gh api a-1 2> /dev/null; gh api a-2 2> /dev/null ) & wait $!' [2]='( gh api b-1 2> /dev/null ) & wait $!')
  printf '%s\n' 'gh api fg-0 2> /dev/null' "${sub[$2]}" 'gh api fg-1 2> /dev/null' "${sub[$3]}" 'exit 0' > "$1/waited.sh"
}
waited "${A}" 1 2; waited "${B}" 1 2
start "${ROOT}/waited" "${A}/tests/diff_run.sh" --times 3 --keep "${ROOT}/keep-waited" "${A}" "${B}" order_waited; finish
if [[ "$(rc_of "${ROOT}/waited")" == 0 && "$(field "${ROOT}/keep-waited/order_waited/a/calls:fg")" == "gh api fg-0;gh api a-1;gh api a-2;gh api fg-1;gh api b-1;" \
  && ! -s "${ROOT}/keep-waited/order_waited/a/steps" ]]; then ok "subshells waited on at once are on calls:fg, in place"
else bad "subshells waited on at once are on calls:fg, in place" \
  "exit $(rc_of "${ROOT}/waited"): $(cat "${ROOT}/waited"); calls:fg: $(field "${ROOT}/keep-waited/order_waited/a/calls:fg")"; fi
rm -rf "${ROOT}/keep-waited"
waited "${B}" 2 1
start "${ROOT}/waited-swap" "${A}/tests/diff_run.sh" "${A}" "${B}" order_waited; finish
if [[ "$(rc_of "${ROOT}/waited-swap")" == 1 && "$(diffs "${ROOT}/waited-swap")" == "order_waited calls:fg;" ]]; then
  ok "two subshells waited on at once, swapped, are red on calls:fg"
else bad "two subshells waited on at once, swapped, are red on calls:fg" "exit $(rc_of "${ROOT}/waited-swap"): $(cat "${ROOT}/waited-swap")"; fi

# The command blocked opening a FIFO, with an unwaited subshell its only child: on Linux, whose
# /proc names what a process sleeps in, that subshell is a step, not on calls:fg. The FIFO's writer
# is no child of the command: the subshell that starts it exits at once.
sleep 5 & nap=$!; sleep 0.3
nap_in="$(cat "/proc/${nap}/wchan" 2>/dev/null || true)"; kill "${nap}" 2>/dev/null || true; wait "${nap}" 2>/dev/null || true
if [[ "${nap_in}" =~ [a-z] ]]; then
  for t in "${A}" "${B}"; do
    printf '%s\n' 'mkfifo f' '( ( sleep 1.5; echo go > f ) & )' '( sleep 0.3; gh api r-1 2> /dev/null; gh api r-2 2> /dev/null ) &' 'read -r x < f' 'exit 0' > "${t}/read.sh"
  done
  start "${ROOT}/read" "${A}/tests/diff_run.sh" --keep "${ROOT}/keep-read" "${A}" "${B}" order_read; finish
  if [[ "$(rc_of "${ROOT}/read")" == 0 && "$(cat "${ROOT}/keep-read/order_read/a/steps" 2>/dev/null)" == "[bash <tree>/read.sh] gh api r-1" \
    && ! -s "${ROOT}/keep-read/order_read/a/calls:fg" ]]; then ok "a subshell whose parent is blocked in a FIFO open is a step"
  else bad "a subshell whose parent is blocked in a FIFO open is a step" \
    "exit $(rc_of "${ROOT}/read"): $(cat "${ROOT}/read"); steps: $(cat "${ROOT}/keep-read/order_read/a/steps" 2>/dev/null)"; fi
  rm -rf "${ROOT}/keep-read"
else echo "skip a subshell whose parent is blocked in a FIFO open is a step: /proc names no wait channel here"; fi

# (3) The stub answers "answer 1" on a tree's odd runs and "answer 0" on its even ones.
trees
start "${ROOT}/alt-1" "${A}/tests/diff_run.sh" "${A}" "${B}" order_alt; finish
if [[ "$(rc_of "${ROOT}/alt-1")" == 0 ]]; then ok "the alternating stub is clean under --times 1"
else bad "the alternating stub is clean under --times 1" "exit $(rc_of "${ROOT}/alt-1"): $(cat "${ROOT}/alt-1")"; fi
rm -f "${A}/count" "${B}/count"
start "${ROOT}/alt-2" "${A}/tests/diff_run.sh" --times 2 "${A}" "${B}" order_alt; finish
if [[ "$(rc_of "${ROOT}/alt-2")" == 1 && "$(diffs "${ROOT}/alt-2")" == "order_alt stdout (a run 2 against run 1);order_alt stdout (b run 2 against run 1);" ]]; then
  ok "a stub that alternates its answer by run is red under --times 2"
else bad "a stub that alternates its answer by run is red under --times 2" "exit $(rc_of "${ROOT}/alt-2"): $(cat "${ROOT}/alt-2")"; fi

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
