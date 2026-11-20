#!/usr/bin/env bash
# speed_run.sh — the speed run: time each command on a list against <tree-a> and <tree-b>, count its
# process starts, and fail a command that tree b runs slower than tree a by the margin.
#
#   bash tests/speed_run.sh [--runs <n>] [--list <file>] [--require-count] <tree-a> <tree-b>
#
#   --runs <n>        timed runs per tree and command (default 5)
#   --list <file>     the commands to time (default tests/speed_list.txt beside this script)
#   --require-count   fail when process starts cannot be counted, instead of reporting `not measured`
#
# The list holds one fixture name a line; a # starts a comment, and blank lines are skipped. Each name
# is a fixture fx_<name> of tests/diff_run.sh's, from a tests/diff_fixtures_<area>.sh file in this
# script's own checkout, sourced by the same glob, so an older tree runs the same fixtures as this one.
# diff_run.sh's header says what a fixture sets. A name with no fixture is red (UNKNOWN), and nothing
# is timed.
#
# Each fixture is built once per tree, in a root of its own, and that root is copied aside. Every run
# starts from a fresh copy at the same path, so a cache or log one run writes never reaches the next.
# Each tree first runs once untimed, a warm-up, since a first run pays for cold caches. Then the
# timed runs alternate trees, a then b, then b then a, and so on, so a drift in the machine's speed
# falls on both. A command runs as diff_run.sh runs it: under env -i with the same variables passed
# on, TMPDIR and CLAUDE_CONFIG_DIR under its root, in a process group of its own, with gh and herdr
# shims first on PATH that answer from the fixture's FX_GH and FX_HERDR stubs and never run a real
# gh or herdr. SWARM_SLEEP_SCALE and SWARM_DASH_NOW are fixed (SPEED_SLEEP_SCALE and SPEED_DASH_NOW
# below), before the fixture's FX_ENV, which may set its own the same on both trees.
#
# Wall time: from the command's start to its exit, in milliseconds, measured by perl's Time::HiRes
# around the fork and exec. The median of each tree's runs is compared. A command fails (SLOWER) when
# tree b's median is over tree a's by more than MARGIN_PERCENT of tree a's median and by at least
# MARGIN_FLOOR_MS: the margin the user set on 2026-11-20, 20% with a 100 ms floor, as CI runners vary
# from run to run. The command's exit code is not compared; tests/diff_run.sh compares what it does.
#
# Process starts: counted with strace -f -e trace=execve, one more run per tree after the timed ones,
# untimed, since tracing slows a command. The count is the execve calls that succeeded, in the
# command and every process it starts, the command's own exec included. It is reported and never
# fails a command. strace is found on PATH, or named by SPEED_RUN_STRACE; it counts only when a probe,
# strace on /usr/bin/true, counts exactly one. Where it cannot count (no strace, as on macOS, or ptrace
# refused), each count reads `not measured`, never 0, and --require-count makes that red
# (NOT-COUNTED).
#
# A run past TIMEOUT seconds (TIMEOUT), with more than MAX_PROCS processes in its group (RUNAWAY), or
# leaving a process in its group BOUND seconds after the command exited (STUCK) is killed and red.
#
# Exit 0 when no command is red, 1 when one is (SLOWER, UNKNOWN, NOT-COUNTED, TIMEOUT, RUNAWAY,
# STUCK, RUNNER-FAIL when the runner itself fails), and 2 on a bad argument, an empty list, a list that
# names a command twice or a fixture that fails to build (BUILD-FAIL).
set -euo pipefail

MARGIN_PERCENT=20
MARGIN_FLOOR_MS=100
SPEED_SLEEP_SCALE=0.01
SPEED_DASH_NOW=1791633600
TIMEOUT=300
MAX_PROCS=200
BOUND=10
RUNS=5
REQUIRE_COUNT=""
PASS_ENV="HOME LANG LC_ALL TERM USER LOGNAME SWARM_FORBID_PROJECT"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LIST="${HERE}/speed_list.txt"

usage() { sed -n '5,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
bad() { echo "speed_run: $*" >&2; usage >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --runs) [[ "${2-}" =~ ^[1-9][0-9]*$ ]] || bad "--runs takes a whole number above 0, not '${2-}'"; RUNS="$2"; shift 2 ;;
    --list) [[ -f "${2-}" ]] || bad "--list takes a file, and '${2-}' is not one"; LIST="$2"; shift 2 ;;
    --require-count) REQUIRE_COUNT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) bad "unknown option $1" ;;
    *) break ;;
  esac
done
[[ $# -eq 2 ]] || bad "two trees are needed"
for t in "$1" "$2"; do [[ -d "${t}" ]] || bad "${t} is not a directory"; done
TREE_A="$(cd "$1" && pwd -P)"
TREE_B="$(cd "$2" && pwd -P)"

for f in "${HERE}"/diff_fixtures_*.sh; do
  [[ -e "${f}" ]] || continue
  # shellcheck source=/dev/null # the fixtures are found by glob
  source "${f}"
done

# The list, each name checked before anything runs.
entries=() unknown=0 seen=" "
while IFS= read -r line || [[ -n "${line}" ]]; do
  line="${line%%#*}"; line="${line#"${line%%[![:space:]]*}"}"; line="${line%"${line##*[![:space:]]}"}"
  [[ -n "${line}" ]] || continue
  [[ "${seen}" != *" ${line} "* ]] || bad "${LIST} names ${line} twice"
  seen="${seen}${line} "
  if [[ "${line}" =~ ^[A-Za-z0-9_]+$ ]] && declare -F "fx_${line}" > /dev/null; then entries+=("${line}")
  else echo "UNKNOWN ${line}: no fixture fx_${line} in ${HERE}/diff_fixtures_*.sh"; unknown=1; fi
done < "${LIST}"
[[ ${unknown} -eq 0 ]] || exit 1
[[ ${#entries[@]} -gt 0 ]] || bad "${LIST} names no command"

WORK="$(mktemp -d)"; WORK="$(cd "${WORK}" && pwd -P)"
# While they run, the build worker's pid is in ${WORK}/builder.pid and its build's in build.pid, the
# runner's in runner.pid, and the command's group id in group: the command writes it itself, before it
# execs, so none runs unrecorded. So the trap signals only what still runs. It stops the worker, the
# build and the runner first, so none starts a command after it, gives a command the runner had forked
# time to record itself, then sends the recorded command's group a TERM, and half a second later a
# KILL. The TERM comes first because a command may hold a group of its own under a supervisor that
# kills it on TERM (dash's report_read, bin/lib/merge.sh's within), which a KILL would stop first.
# shellcheck disable=SC2329 # the EXIT trap calls it
cleanup() {
  local f g stopped=""
  for f in builder.pid build.pid runner.pid; do
    [[ -e "${WORK}/${f}" ]] || continue
    g="$(cat "${WORK}/${f}")"; [[ "${g}" =~ ^[0-9]+$ ]] || continue
    kill -KILL "${g}" 2>/dev/null && stopped=1
  done
  [[ -z "${stopped}" ]] || sleep 0.5
  if [[ -e "${WORK}/group" ]]; then
    g="$(cat "${WORK}/group")"
    if [[ "${g}" =~ ^[0-9]+$ ]]; then
      kill -TERM -- "-${g}" 2>/dev/null && sleep 0.5
      kill -KILL "${g}" 2>/dev/null || true; kill -KILL -- "-${g}" 2>/dev/null || true
    fi
  fi
  rm -rf "${WORK}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# run.pl <timeout> <max procs> <bound> <group file> <result file> <command...> — run <command> as the
# leader of a new process group, its id in <group file> while it runs, and write "<ms> <state>" to
# <result file>: <ms> its wall time, <state> ok, or TIMEOUT, RUNAWAY or STUCK and why. A watcher
# process counts the group every quarter second and kills it past <max procs> or <timeout> seconds,
# and exits once the runner is gone; once the command exits, the group has <bound> seconds to empty
# before it is killed.
cat > "${WORK}/run.pl" <<'PERL'
use strict; use warnings; use Time::HiRes qw(time sleep);
my ($timeout, $max, $bound, $gfile, $res) = splice(@ARGV, 0, 5);
$SIG{INT} = $SIG{QUIT} = 'DEFAULT';
sub members { my $g = shift; my @m = grep { /^\d+$/ } map { s/\s+//gr } `pgrep -g $g 2>/dev/null`; return @m }
# A TERM first, half a second before the KILLs, as the trap sends: a supervisor in the group (within)
# kills the group it made for its child on TERM, which a KILL would stop it doing.
sub kill_group { my $g = shift; kill 'TERM', -$g and sleep 0.5; for (1 .. 50) { kill 'KILL', -$g; kill 'KILL', $g; last unless members($g); sleep 0.1 } }
my $t0 = time;
my $pid = fork() // die "speed_run: fork: $!\n";
# The command records its group before it runs: the trap reads the file.
if (!$pid) {
  setpgrp(0, 0) or exit 126;
  my $g; open($g, '>', $gfile) && print($g "$$\n") && close($g) or exit 126;
  exec { $ARGV[0] } @ARGV or exit 127;
}
my $why = "$res.killed";
my $runner = $$;
my $watch = fork() // die "speed_run: fork: $!\n";
if (!$watch) {
  while (1) {
    sleep 0.25;
    exit 0 if getppid() != $runner;
    my @m = members($pid); my $w = '';
    if (@m > $max) { $w = "RUNAWAY more than $max processes in its group" }
    elsif (time - $t0 >= $timeout) { $w = "TIMEOUT still running after ${timeout}s" }
    next unless $w;
    if (open(my $k, '>', $why)) { print $k "$w\n"; close $k }
    kill_group($pid); exit 0;
  }
}
waitpid($pid, 0);
my $ms = int((time - $t0) * 1000 + 0.5);
my $state = 'ok';
for (my $i = 0; $i < $bound * 10 && members($pid); $i++) { sleep 0.1 }
if (my @left = members($pid)) {
  my $args = join('; ', map { s/\s+$//r } `ps -o args= -p @{[join(',', @left)]} 2>/dev/null`);
  $state = "STUCK still running ${bound}s after the command exited: $args"; kill_group($pid);
}
kill 'KILL', $watch; waitpid($watch, 0);
if (-s $why && open(my $k, '<', $why)) { $state = <$k>; chomp $state }
unlink $gfile;
open(my $r, '>', $res) or die "speed_run: $res: $!\n"; print $r "$ms $state\n"; close $r;
PERL

# shim <tool> <dir> <stub> — write <dir>/<tool>: exec <stub>; with no <stub>, fail loudly. It never
# looks on PATH, and a call from inside a stub (or from the shim itself) is refused, as diff_run.sh's
# shim refuses it, so no stub loops back through it.
shim() {
  { printf '#!/usr/bin/env bash\nTOOL=%q STUB=%q\n' "$1" "$3"
    cat <<'SHIM'
if [[ -n "${SPEED_RUN_SHIM:-}" ]]; then
  echo "speed_run: the ${TOOL} shim was called again from inside ${SPEED_RUN_SHIM}'s stub, so it fails: ${TOOL} $*" >&2
  exit 1
fi
export SPEED_RUN_SHIM="${TOOL}"
[[ -z "${STUB}" ]] || exec "${STUB}" "$@"
echo "speed_run: no stub answers this ${TOOL} call, so it fails; a real ${TOOL} is never run: ${TOOL} $*" >&2
exit 1
SHIM
  } > "$2/$1"
  chmod +x "$2/$1"
}

# The counter: strace, when its probe counts /usr/bin/true's one exec.
STRACE="${SPEED_RUN_STRACE:-strace}" COUNTER="" NO_COUNT=""
# count_execs <strace output> — the execve calls in it that succeeded, an unfinished call counted
# once, on its resumed line.
count_execs() { grep -c 'execve.*= 0$' "$1" || true; }
# Made absolute, since each command runs from its own cwd.
if ! s="$(command -v "${STRACE}")"; then NO_COUNT="no ${STRACE} on PATH"
elif [[ "${s}" != /* ]] && ! s="$(cd "$(dirname "${s}")" && pwd -P)/$(basename "${s}")"; then NO_COUNT="no directory for ${STRACE}"
elif ! "${s}" -f -qq -e trace=execve -e signal=none -o "${WORK}/probe" -- /usr/bin/true > /dev/null 2>&1; then NO_COUNT="${s} could not trace /usr/bin/true"
elif [[ "$(count_execs "${WORK}/probe")" != 1 ]]; then NO_COUNT="${s} counted $(count_execs "${WORK}/probe") execs for /usr/bin/true, not 1"
else COUNTER="${s}"; fi

# build <fixture> <root> <tree> <vars> — run fx_<fixture> in <root> and write the FX_ settings it made
# to <vars>, as diff_run.sh's build does. Run it in a subshell of its own, not under || or &&, so set -e
# holds inside.
build() {
  # shellcheck disable=SC2034 # the fixture reads ROOT and TREE
  ROOT="$2" TREE="$3"
  FX_CMD=(); FX_ENV=(); FX_STDIN=/dev/null; FX_CWD="$2"; FX_GH=""; FX_HERDR=""
  cd "$2"
  "fx_$1"
  [[ ${#FX_CMD[@]} -gt 0 ]] || { echo "fx_$1 set no FX_CMD" >&2; return 1; }
  declare -p FX_CMD FX_ENV FX_STDIN FX_CWD FX_GH FX_HERDR > "$4"
}

# build_one <entry> <a|b> — build fx_<entry> against the tree into ${WORK}/<entry>.<side>/root, write
# its shims and its command's environment, and copy the root aside to pristine. Returns 2 when the
# build failed. Run it in the background and wait on it, never under || or &&: there bash ignores set -e
# in every subshell it starts, the build's too, so a fixture step that fails would pass.
build_one() {
  local fx="$1" side="$2" tree dir root meta rc=0 v base_path envs=() FX_CMD FX_ENV FX_STDIN FX_CWD FX_GH FX_HERDR
  if [[ "${side}" == a ]]; then tree="${TREE_A}"; else tree="${TREE_B}"; fi
  dir="${WORK}/${fx}.${side}"; root="${dir}/root"; meta="${dir}/meta"
  mkdir -p "${root}" "${meta}/shims" "${meta}/gh-config"
  ( set -e; build "${fx}" "${root}" "${tree}" "${meta}/vars" ) > "${meta}/build.log" 2>&1 &
  echo "$!" > "${WORK}/build.pid"
  wait "$!" || rc=$?
  rm -f "${WORK}/build.pid"
  if [[ ${rc} -ne 0 ]]; then
    echo "BUILD-FAIL ${fx} (${side}: ${tree}): fx_${fx} exited ${rc}"; sed 's/^/  /' "${meta}/build.log"; return 2
  fi
  # shellcheck source=/dev/null # build's declare -p
  source "${meta}/vars"
  mkdir -p "${root}/tmp"
  shim gh "${meta}/shims" "${FX_GH}"
  shim herdr "${meta}/shims" "${FX_HERDR}"
  base_path="${PATH}"
  for v in ${FX_ENV[@]+"${FX_ENV[@]}"}; do [[ "${v}" != PATH=* ]] || base_path="${v#PATH=}"; done
  for v in ${PASS_ENV}; do [[ -z "${!v+x}" ]] || envs+=("${v}=${!v}"); done
  envs+=("TMPDIR=${root}/tmp" "CLAUDE_CONFIG_DIR=${root}/claude-config" "SWARM_SLEEP_SCALE=${SPEED_SLEEP_SCALE}"
    "SWARM_DASH_NOW=${SPEED_DASH_NOW}" ${FX_ENV[@]+"${FX_ENV[@]}"}
    "PATH=${meta}/shims:${base_path}" "GH_CONFIG_DIR=${meta}/gh-config" "HERDR_BIN_PATH=${meta}/shims/herdr")
  declare -p envs FX_CMD FX_STDIN FX_CWD > "${meta}/run"
  cp -Rp "${root}" "${dir}/pristine"
}

# run_one <entry> <a|b> [warm|count] — run the built command once from a fresh copy of its root and
# append its wall time in ms to ${WORK}/<entry>.<side>/ms; with warm, keep no time; with count, run it
# under strace instead and write the process starts to .../starts. Returns 3 when the run was killed
# or left a process.
run_one() {
  local fx="$1" side="$2" dir meta ms state envs FX_CMD FX_STDIN FX_CWD trace=()
  dir="${WORK}/${fx}.${side}"; meta="${dir}/meta"
  rm -rf "${dir}/root"; cp -Rp "${dir}/pristine" "${dir}/root"
  # shellcheck source=/dev/null # build_one's declare -p
  source "${meta}/run"
  [[ "${3:-}" != count ]] || trace=("${COUNTER}" -f -qq -e trace=execve -e signal=none -o "${meta}/trace" --)
  rm -f "${meta}/result" "${meta}/result.killed"
  ( cd "${FX_CWD}" && exec perl "${WORK}/run.pl" "${TIMEOUT}" "${MAX_PROCS}" "${BOUND}" "${WORK}/group" "${meta}/result" \
      env -i "${envs[@]}" ${trace[@]+"${trace[@]}"} "${FX_CMD[@]}" ) < "${FX_STDIN}" > "${meta}/stdout" 2> "${meta}/stderr" &
  # In the background and waited on, so a TERM to this script runs its trap at once.
  echo "$!" > "${WORK}/runner.pid"
  wait "$!" || true
  rm -f "${WORK}/runner.pid"
  [[ -s "${meta}/result" ]] || { echo "RUNNER-FAIL ${fx} (${side}): its runner wrote no result"; sed "s/^/  /" "${meta}/stderr"; return 3; }
  read -r ms state < "${meta}/result"
  if [[ "${state}" != ok ]]; then echo "${state%% *} ${fx} (${side}): ${state#* }"; return 3; fi
  case "${3:-}" in
    # A count run that left no trace counts nothing: not measured, which --require-count fails.
    count) if [[ -s "${meta}/trace" ]]; then count_execs "${meta}/trace" > "${dir}/starts"
           else echo "COUNT-FAIL ${fx} (${side}): ${COUNTER} wrote no trace"; NO_COUNT="${COUNTER} wrote no trace for ${fx}"; fi ;;
    warm) ;;
    *) echo "${ms}" >> "${dir}/ms" ;;
  esac
}

# median <file> — the median of the whole numbers in <file>, one a line; of an even count, the mean
# of the middle two, rounded.
median() { LC_ALL=C sort -n "$1" | awk '{ v[NR] = $1 } END { if (NR % 2) print v[(NR + 1) / 2]; else printf "%d\n", (v[NR / 2] + v[NR / 2 + 1]) / 2 + 0.5 }'; }

echo "a: ${TREE_A}"
echo "b: ${TREE_B}"
echo "runs: ${RUNS} a tree after one untimed, alternating; red past ${MARGIN_PERCENT}% of a's median and at least ${MARGIN_FLOOR_MS} ms"
if [[ -n "${COUNTER}" ]]; then echo "process starts: ${COUNTER} -f -e trace=execve, the execve calls that succeeded"
else echo "process starts: not measured (${NO_COUNT})"; fi
status=0 rows=()
for fx in "${entries[@]}"; do
  broken="" red=""
  for side in a b; do
    build_one "${fx}" "${side}" & echo "$!" > "${WORK}/builder.pid"
    wait "$!" || broken=1
    rm -f "${WORK}/builder.pid"
  done
  if [[ -n "${broken}" ]]; then
    status=2; rows+=("$(printf '%-14s %10s %10s %14s %14s  %s' "${fx}" - - - - BUILD-FAIL)"); continue
  fi
  # One untimed run a tree first: a tree's first run pays for cold caches the later ones do not.
  for side in a b; do run_one "${fx}" "${side}" warm || red=1; done
  for ((i = 1; i <= RUNS && ${#red} == 0; i++)); do
    order="a b"; [[ $((i % 2)) -eq 1 ]] || order="b a"
    for side in ${order}; do run_one "${fx}" "${side}" || red=1; done
  done
  starts_a="not measured" starts_b="not measured"
  if [[ -n "${COUNTER}" && -z "${red}" ]]; then
    for side in a b; do run_one "${fx}" "${side}" count || red=1; done
    [[ -n "${red}" || ! -s "${WORK}/${fx}.a/starts" || ! -s "${WORK}/${fx}.b/starts" ]] \
      || { starts_a="$(cat "${WORK}/${fx}.a/starts")"; starts_b="$(cat "${WORK}/${fx}.b/starts")"; }
  fi
  if [[ -n "${red}" ]]; then
    [[ ${status} -eq 2 ]] || status=1
    rows+=("$(printf '%-14s %10s %10s %14s %14s  %s' "${fx}" - - - - red)"); continue
  fi
  ma="$(median "${WORK}/${fx}.a/ms")" mb="$(median "${WORK}/${fx}.b/ms")" gap=$((mb - ma)) result=ok
  if [[ ${gap} -ge ${MARGIN_FLOOR_MS} && $((gap * 100)) -gt $((ma * MARGIN_PERCENT)) ]]; then
    echo "SLOWER ${fx}: b's median ${mb} ms is ${gap} ms over a's ${ma} ms, past the margin (${MARGIN_PERCENT}% of a's, at least ${MARGIN_FLOOR_MS} ms)"
    result=SLOWER; [[ ${status} -eq 2 ]] || status=1
  fi
  rows+=("$(printf '%-14s %10s %10s %14s %14s  %s' "${fx}" "${ma} ms" "${mb} ms" "${starts_a}" "${starts_b}" "${result}")")
done
printf '%-14s %10s %10s %14s %14s  %s\n' command "a median" "b median" "a starts" "b starts" result
printf '%s\n' ${rows[@]+"${rows[@]}"}
if [[ -n "${REQUIRE_COUNT}" && ( -z "${COUNTER}" || -n "${NO_COUNT}" ) ]]; then
  echo "NOT-COUNTED: --require-count, and process starts were not measured: ${NO_COUNT}"
  [[ ${status} -eq 2 ]] || status=1
fi
exit "${status}"
