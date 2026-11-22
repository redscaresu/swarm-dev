#!/usr/bin/env bash
# diff_run.sh — the differential run: run each fixture once against <tree-a> and once against
# <tree-b>, and compare what the two runs did.
# With --times N each fixture runs N times on each tree, and every run is compared.
#
#   bash tests/diff_run.sh [--bound <s>] [--timeout <s>] [--max-procs <n>] [--keep <dir>] <tree-a> <tree-b> [fixture...]
#   bash tests/diff_run.sh [those options] [--stage <n>] [--only <slug>] [--draft] <tree-a> <tree-b> [fixture...]
#   bash tests/diff_run.sh [those options] [--times <n>] <tree-a> <tree-b> [fixture...]
#   bash tests/diff_run.sh [those options] --base [--branch <ref>]... [--draft] <tree-a> <tree-b> [fixture...]
#
#   --bound <s>        how long a run waits, once its command has exited, for the processes it left in
#                      its group (default 10); one still alive then is red, by its argv, and is killed
#                      the same bound covers each process that left the group but holds the run's
#                      marker or hold pipe
#   --timeout <s>      how long a command may run (default 300); past it, its group is killed, and red
#   --max-procs <n>    how many processes its group may hold at once (default 200); past it, the group
#                      is killed, and red, so a command that forks without end never fills the machine
#   --times <n>        run each fixture <n> times on each tree (default 1); red when a run differs from
#                      its tree's first run, as well as when the two trees' first runs differ
#   --keep <dir>       also write each run's streams, as compared, to <dir>/<fixture>/<a|b>/<stream>
#                      (<a|b>.<n> for run <n> past the first)
#   --stage <n>        apply the allow lists scripts/allow/stage-1/ through stage-<n>/ to a's streams
#                      first, so only a difference no entry's hunk covers is red
#   --only <slug>      apply that one story's entry alone (from any stage, or up to --stage's), to
#                      check it against the story's own merge commit
#   --base             tree-a is a PR's base and tree-b its head: apply only the entries of the stories
#                      --branch names (from any stage), so a PR passes with its own entry and no other's
#   --branch <ref>     with --base, a head branch; story/<slug> names story <slug>, whose entry applies
#                      when it has one, and any other ref names none (a merge group gives one per PR)
#   --draft            print each difference as the hunks that would cover it, to edit into an entry
#
# A fixture is a function fx_<name> in a tests/diff_fixtures_<area>.sh file. Every such file in this
# script's own checkout is sourced, so an older tree runs the same fixtures as this one. With no
# fixture named, every fixture runs. A fixture runs in a subshell under set -e, with its cwd and ROOT
# a fresh, empty directory (the fixture root) and TREE the tree under test. It builds its project
# under ROOT and sets:
#   FX_CMD    the command line (required), such as (bash "${TREE}/bin/swarm.sh" next)
#   FX_ENV    NAME=value words added to the command's environment
#   FX_STDIN  a file for the command's stdin (default /dev/null)
#   FX_CWD    the command's cwd (default ROOT)
#   FX_GH, FX_HERDR  an executable that answers the gh or herdr shim's calls, such as the gh stub
#             tests/merge_fixture.sh writes; with none, every call is unanswered
#   FX_CALLS  the calls the command must make, each a "<tool> <args>" prefix of a calls:fg line, or of a step's line, as
#             compared (such as "herdr agent list"); a tree's run that makes one of them in no line is
#             red (MISSING), so a command that exits early in both trees cannot pass by making no call
#             in either. A fixture that rightly makes no call names none.
#
# The command runs under env -i with only PATH, HOME, LANG, LC_ALL, TERM, USER, LOGNAME,
# SWARM_SLEEP_SCALE and SWARM_FORBID_PROJECT passed on (the ones set), SWARMDEV_BIN too when it is set
# and the tree has no .git (PASS_BIN), TMPDIR=ROOT/tmp and
# CLAUDE_CONFIG_DIR=ROOT/claude-config, then FX_ENV, then the ones FX_ENV cannot override: PATH with
# the shims first (before FX_ENV's PATH when it sets one), GH_CONFIG_DIR an empty directory,
# HERDR_BIN_PATH, DIFF_RUN_MARK (the run's marker), and BASH_ENV and DIFF_RUN_STARTS (the bash start
# probe below). So no GH_TOKEN or GITHUB_TOKEN of the caller's reaches it. It leads a process
# group of its own; once it exits, the run waits up to --bound seconds for every other process in the
# group. Its group is counted every 0.2 s from its start until it is gone, and killed past
# --max-procs or --timeout. The gh and herdr shims go first on PATH, and HERDR_BIN_PATH names the
# herdr one. Each logs its call, then runs FX_GH or FX_HERDR; with none, it says so on stderr and
# exits 1. Neither ever runs a gh or herdr found on PATH, and a shim called again from inside a stub
# (or from itself) refuses the call the same way, so no stub can loop back through it.
# Within the same --bound, the run then waits for every process that holds the marker in its
# environment, then for every process that holds the run's hold pipe, whose write end the command
# gets on fd 19 and every process it starts inherits: so a run that left the group by setsid is
# waited for too, on macOS as well, where ps shows no environment for the system's own binaries.
# SWARM_FORBID_PROJECT, the checkout make test runs from, never names a fixture's project, since each
# fixture root is a new directory, so a hook writes its events.tsv line there under make test too.
# CLAUDE_PLUGIN_ROOT=TREE, as Claude Code sets it for a hook hooks/hooks.json runs, goes in beside
# TMPDIR and CLAUDE_CONFIG_DIR, before FX_ENV, so a fixture can set its own.
#
# Each call is placed on the foreground path or in one background step, by where it starts, never by
# when: bash and sh start each `&` job with SIGINT and SIGQUIT ignored, and the shim reads that from
# its own process, so a call inside a `( ... ) &` subshell, a `nohup ... &` run or a setsid'd one is
# a background call whether its step ends before the command exits or after. A call with either as
# it was is a foreground call, so `trap '' INT` alone moves none. The shim also logs the call's chain
# of ancestor pids, up to the command's own (or to the top of the run's processes, once that has
# exited), and marks each process its parent in the run was waiting on (an orphan's new parent, pid 1
# or a reaper outside the run, waits on nothing of the run's): one whose parent sleeps in a wait with
# it as its youngest child (bash forks a foreground command, then waits, so its newest child is the
# one it waits on and an `&` job it forked earlier is older). No other process's signals can be read
# on macOS, so the run learns them two ways: BASH_ENV runs a probe as each bash starts (a script,
# bash -c, bin/gh-shim/gh; a subshell is a fork and runs none), which logs whether it started with
# both ignored; and every process in a foreground call's chain is on the foreground path. A
# background call's chain is walked down from the command, past each process on the foreground
# path: one known so, or one its parent waited on. The first process past them is the call's step,
# so a subshell the command waits on at once (as swarm.sh runs its dispatch) is a boundary, and a run
# it starts in the background is a step of its own. With none past them, the call is a foreground
# call. A leaf that is that first process, below a process on the foreground path that is not the
# command, is that process's own `&` job, a foreground call: bin/gh-shim/gh starts every real gh so,
# and waits on it. Its own pid must not have begun as a background bash that then ran exec gh. A
# step is labelled by its process's argv (the command's pid in it masked as <pid>) and its first
# call, and steps are matched by label, never by position; two steps with one label are told apart
# by their calls. A call the run cannot place is red (UNPLACED): one whose chain the shim could not
# read, and a foreground call made after the command exited by a process that did not start in the
# background.
# How some shapes are placed (bin/ and hooks/ have the first three, and none of the last three):
#   - A subshell waited on at once (`( ... ) & wait $!`, as bin/swarm.sh runs dispatch and
#     bin/lib/merge.sh runs reconcile and story_note) is on the foreground path, its calls on calls:fg
#     in place, and so is a command substitution (`x="$(gh ... | jq ...)"`), whose parent reads its
#     output from a pipe until it ends. Where /proc names what the parent sleeps in (Linux), a wait or
#     a pipe read counts and a FIFO open does not, and the parent's own list of children is read. A
#     parent that has not yet reached its wait by the subshell's first call (the subshell has forked
#     and started a gh by that time) would leave it a step of its own, and a parent blocked reading a
#     pipe while an `&` job is its youngest child would make that job look waited on. A job the parent joins later is a step: one whose parent made a
#     call through a newer child before its last call (`( ... ) & gh ...; wait`) was not waited on at
#     once. One joined with no such call in between (`( ... ) & sleep 1; wait`) is placed by when its
#     first call comes.
#   - A run that such a subshell starts in the background (bin/lib/lifecycle.sh's nohup'd and setsid'd
#     runs, which swarm.sh's dispatch starts, and note_wake_later's subshell) is a step of its own,
#     labelled by its argv, and keeps its calls made after the command exits.
#   - A `gh ... &` the command itself runs is a step (hooks/agent-state.sh runs herdr so, unwaited);
#     one that a bash below the command runs and never waits on would be a foreground call.
#   - A waited `gh ... &` that a shell other than bash runs is a step: only bash runs the probe.
#   - A command that ignores both SIGINT and SIGQUIT itself (trap '' INT QUIT) makes its own calls
#     look like background ones, each a step of its own.
#   - A subshell that exits before the worker it started has begun (`( bash worker.sh & exit 0 ) &`)
#     leaves no trace, as a subshell is a fork no probe sees, so that worker's step is its own or the
#     subshell's by timing.
#
# Streams compared, each after the replacements and masks below:
#   stdout, stderr, exit  the command's
#   files     each file under ROOT the run added or changed, by path and content, each symbolic
#             link by its target, and each it deleted, the list of paths first; files under a .git
#             directory are left out, since a git read can rewrite the index with stat data
#   calls:fg  the foreground gh and herdr calls, in order, one "<tool> <args>" line each: in each argument the
#             tree and root paths are replaced first, then it is quoted as printf %q quotes it, so two
#             argument lists never log the same line
#   calls:[<argv>] <first call>  one stream per background step, its calls in order, as calls:fg's;
#             a step on one side only is red, by its label
# Replacements: each tree's path (as given and as pwd -P prints it) becomes <tree>, the fixture root
# <root>, the run's own directory around it (where the shims and GH_CONFIG_DIR live) <run>, and
# version=<the tree's own .claude-plugin/plugin.json version> version=<version>. Masks,
# each of a fixed shape: an ISO time stamp (2026-11-20T09:30:00Z) becomes <time>; a pid after "pid ",
# "pid=" or "pid:", and the content of a file named pid, <pid>; a mktemp suffix after tmp. or
# swarm-<name>. (bin/lib/merge.sh's names) <tmp>; and, in .swarm/run-times.tsv, the seconds column
# (1.234) <seconds> and the load column (0.52, or -) <load>. A value of another shape is left as it is.
# In a calls stream, a herdr call's value after --seq of 19 digits (agent-state.sh's time.time_ns())
# becomes <seq>, and a value of another shape there is left as it is too.
# A step's label line ("@@ [<argv>] <first call>") gets the same mask, in its argv and its call.
#
# With --stage, --only or --draft, tests/diff_allow.py compares the streams once every fixture has
# run. The entries apply to a's streams in the order their PRs merged (tests/diff_allow.py's
# merge_order: by the first-parent commit that added each, then by stage and PR number); a
# hunk for a fixture outside the run is skipped, and one that does not apply on a fixture the run
# ran is red (ALLOW-FAIL <fixture> <stream> ...). There the files stream is split in two: files is its
# list of written and deleted paths, and file:<path> one written file's content. scripts/allow/README.md
# gives the entry format; a malformed entry stops the run before any fixture, with exit 2.
# --base has it compare them too, with the entries of the stories --branch names.
# It compares each tree's first run; with --times, each repeat is still compared with its tree's
# first run by diff_run.sh itself. Each background step goes to it as two streams, steps (the
# labels, sorted) and step.<k> (the calls of the k-th), which it reads as the stream calls:<label>,
# the step's name here, so an entry's ## heading can name one.
#
# Exit 0 when every fixture's streams are the same, 1 when any differ (DIFF <fixture> <stream> and a
# diff for each), a process outlived the bound (STUCK <fixture> ...), or a group passed --max-procs
# (RUNAWAY <fixture> ...) or --timeout (TIMEOUT <fixture> ...), and 2 on a bad argument or a
# fixture that fails to build on either tree (BUILD-FAIL <fixture> ... and its output).
# A call the run could not place (UNPLACED <fixture> ...) exits 1 too, and a shim of the run's own
# that does not parse is a BUILD-FAIL (exit 2). A repeat's DIFF line ends "(a run <n> against run 1)",
# and a line about one run names its side, (a) or (b), and past the first run its number, (a run 2).
# A run that did not make a named call (MISSING <fixture> ...) exits 1 too.
set -euo pipefail

BOUND=10
TIMEOUT=300
MAX_PROCS=200
TIMES=1
KEEP=""
STAGE="" ONLY="" DRAFT=""
BASE="" BRANCHES=()
STREAMS="stdout stderr exit files calls:fg"
PASS_ENV="HOME LANG LC_ALL TERM USER LOGNAME SWARM_SLEEP_SCALE SWARM_FORBID_PROJECT"
# PASS_BIN: passed on too, for a tree with no .git: make test's binary, where that tree's swarm.sh would
# otherwise fetch one (binary_ensure in bin/lib/binary.sh). A git checkout's tree, as the diff-run job
# runs, builds its own from its tree, so it gets none.
PASS_BIN=SWARMDEV_BIN
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

usage() { sed -n '6,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
bad() { echo "diff_run: $*" >&2; usage >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bound) [[ "${2-}" =~ ^[0-9]+$ ]] || bad "--bound takes a whole number of seconds, not '${2-}'"; BOUND="$2"; shift 2 ;;
    --timeout) [[ "${2-}" =~ ^[1-9][0-9]*$ ]] || bad "--timeout takes a whole number of seconds above 0, not '${2-}'"; TIMEOUT="$2"; shift 2 ;;
    --max-procs) [[ "${2-}" =~ ^[1-9][0-9]*$ ]] || bad "--max-procs takes a whole number above 0, not '${2-}'"; MAX_PROCS="$2"; shift 2 ;;
    --times) [[ "${2-}" =~ ^[1-9][0-9]*$ ]] || bad "--times takes a whole number above 0, not '${2-}'"; TIMES="$2"; shift 2 ;;
    --keep) [[ -n "${2-}" ]] || bad "--keep takes a directory"; KEEP="$2"; shift 2 ;;
    --stage) [[ "${2-}" =~ ^[1-9][0-9]*$ ]] || bad "--stage takes a stage number above 0, not '${2-}'"; STAGE="$2"; shift 2 ;;
    --only) [[ "${2-}" =~ ^[a-z0-9][a-z0-9-]*$ ]] || bad "--only takes a story slug, not '${2-}'"; ONLY="$2"; shift 2 ;;
    --base) BASE=1; shift ;;
    --branch) [[ -n "${2-}" ]] || bad "--branch takes a branch name"; BRANCHES+=("$2"); shift 2 ;;
    --draft) DRAFT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) bad "unknown option $1" ;;
    *) break ;;
  esac
done
[[ $# -ge 2 ]] || bad "two trees are needed"
# The hold pipe's holders are found in /proc, or by lsof (macOS ships it): with neither, a stuck one
# could be neither named nor killed.
[[ -d /proc/self ]] || command -v lsof > /dev/null || bad "with no /proc, lsof is needed to find the processes that hold a run's hold pipe"
for t in "$1" "$2"; do [[ -d "${t}" ]] || bad "${t} is not a directory"; done
TREE_A="$(cd "$1" && pwd -P)"; TREE_A_L="$(cd "$1" && pwd)"
TREE_B="$(cd "$2" && pwd -P)"; TREE_B_L="$(cd "$2" && pwd)"
shift 2

for f in "${HERE}"/diff_fixtures_*.sh; do
  [[ -e "${f}" ]] || continue
  # shellcheck source=/dev/null # the fixtures are found by glob
  source "${f}"
done
names=("$@")
if [[ ${#names[@]} -eq 0 ]]; then
  while read -r _ _ fn; do [[ "${fn}" != fx_* ]] || names+=("${fn#fx_}"); done < <(declare -F | LC_ALL=C sort -k3)
fi
[[ ${#names[@]} -gt 0 ]] || bad "no fixture: no fx_<name> in ${HERE}/diff_fixtures_*.sh"
for n in "${names[@]}"; do declare -F "fx_${n}" > /dev/null || bad "no fixture fx_${n} in ${HERE}/diff_fixtures_*.sh"; done

# The allow lists are this checkout's, as the fixtures are. A malformed entry stops the run here,
# before any fixture runs.
ALLOW_DIR="$(cd "${HERE}/.." && pwd -P)/scripts/allow"
allow=()
[[ -z "${STAGE}" ]] || allow+=(--stage "${STAGE}")
[[ -z "${ONLY}" ]] || allow+=(--only "${ONLY}")
if [[ -n "${BASE}" ]]; then
  [[ -z "${STAGE}${ONLY}" ]] || bad "--base takes neither --stage nor --only: it applies the head's own stories' entries alone"
  allow+=(--base)
  for b in ${BRANCHES[@]+"${BRANCHES[@]}"}; do
    if [[ "${b}" =~ ^story/([a-z0-9][a-z0-9-]*)$ ]]; then allow+=(--story "${BASH_REMATCH[1]}")
    else echo "--base: ${b} is no story/<slug> branch, so it names no entry"; fi
  done
elif [[ ${#BRANCHES[@]} -gt 0 ]]; then bad "--branch goes with --base"; fi
[[ ${#allow[@]} -eq 0 ]] || python3 "${HERE}/diff_allow.py" check "${ALLOW_DIR}" "${allow[@]}" > /dev/null || exit 2
[[ -z "${DRAFT}" ]] || allow+=(--draft)

WORK="$(mktemp -d)"; WORK="$(cd "${WORK}" && pwd -P)"
# marked <mark> — the pid of each process whose environment holds DIFF_RUN_MARK=<mark>, a run's
# marker ("<run dir>:") or the start of every run's ("${WORK}/"). Read from /proc where there is one,
# else from ps -E (macOS), whose line holds the argv too: the match is put together inside awk, so
# awk's own line never holds it.
marked() {
  if [[ -d /proc/self ]]; then
    DR_M="DIFF_RUN_MARK=$1" perl -e 'local $/ = "\0"; for my $f (glob "/proc/[0-9]*/environ") {
        open(my $e, "<", $f) or next; while (<$e>) { if (index($_, $ENV{DR_M}) == 0) { print "$1\n" if $f =~ m{^/proc/(\d+)/}; last } } }'
  else
    ps -A -wwE -o pid=,command= 2>/dev/null | DR_M="$1" awk 'index($0, "DIFF_RUN_MARK=" ENVIRON["DR_M"]) { print $1 }'
  fi
}

# Each side's worker (run_one) has its pid in ${WORK}/<fixture>.<side>.<n>.pid, and its build its pid in
# meta/build.pid, while they run. Each command's group id is in its meta/group from just before perl's
# setpgrp until the group is gone; perl writes it, so no command runs unrecorded. So the trap signals
# only what still runs, never an id a finished one gave back. It stops the workers first, so none
# starts a command after it, gives a command one of them had forked time to record itself, then kills
# each recorded command by its pid (one stopped before setpgrp) and its group (no pid is reused while
# its group lives).
# Last it kills each process that holds a run's marker or hold pipe, as a setsid'd one left the
# group, and each pipe's reader.
# shellcheck disable=SC2329 # the EXIT trap calls it
cleanup() {
  local f g stopped=""
  for f in "${WORK}"/*.pid "${WORK}"/*/meta/build.pid "${WORK}"/*/meta/watch.pid; do
    [[ -e "${f}" ]] || continue
    g="$(cat "${f}")"; [[ "${g}" =~ ^[0-9]+$ ]] || continue
    kill -KILL "${g}" 2>/dev/null && stopped=1
  done
  [[ -z "${stopped}" ]] || sleep 0.5
  for f in "${WORK}"/*/meta/group; do
    [[ -e "${f}" ]] || continue
    g="$(cat "${f}")"; [[ "${g}" =~ ^[0-9]+$ ]] || continue
    kill -KILL "${g}" 2>/dev/null || true; kill -KILL -- "-${g}" 2>/dev/null || true
  done
  for g in $(marked "${WORK}/"); do kill -KILL "${g}" 2>/dev/null || true; done
  for f in "${WORK}"/*/meta/hold.pid; do
    [[ -e "${f}" ]] || continue
    for g in $(holders "${f%/meta/hold.pid}"); do kill -KILL "${g}" 2>/dev/null || true; done
    g="$(cat "${f}")"; [[ "${g}" =~ ^[0-9]+$ ]] && kill -KILL "${g}" 2>/dev/null || true
  done
  rm -rf "${WORK}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# version_of <tree> — the version in <tree>'s .claude-plugin/plugin.json, or nothing.
# A tree with no plugin.json has none, and that is no error.
version_of() { { sed -nE 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "$1/.claude-plugin/plugin.json" 2>/dev/null || true; } | head -1; }

# snapshot <root> — one "<path>\t<cksum> <size>" line per file under <root>, and one
# "<path>\tlink <target>" line per symbolic link (never followed), past any .git, by path.
snapshot() {
  local c s p
  { find "$1" -name .git -prune -o -type f -exec cksum {} + | while read -r c s p; do printf '%s\t%s %s\n' "${p}" "${c}" "${s}"; done
    find "$1" -name .git -prune -o -type l -print | while IFS= read -r p; do printf '%s\tlink %s\n' "${p}" "$(readlink "${p}")"; done
  } | LC_ALL=C sort
}

# written <before> <after> <normalize args...> — the files stream. First the inventory: "written
# <path>" for each file or link <after> adds or changes and "deleted <path>" for each it lost, then
# "==> <path> (<n> bytes) <==" and the content of each written file, <n> the length of that content
# as normalized ("==> <path> -> <target> <==" for a link). The inventory comes first, so no file's
# content can add or hide an entry; the length fixes where each content ends, so none can pass for
# another file's; and each file is normalized on its own, with its path for its own masks. Each part
# is sorted only once normalized, so a mask's random part (a mktemp suffix) sets no order.
# shellcheck disable=SC2094 # normalize takes a file's path as a name for its masks; it writes stdout only
written() {
  local p kind n=0 rec before="$1" after="$2"; shift 2
  awk -F'\t' 'FILENAME == ARGV[1] { was[$1] = $2; next } { now[$1] = 1; if (!($1 in was) || was[$1] != $2) print "written\t" $1 }
    END { for (p in was) if (!(p in now)) print "deleted\t" p }' "${before}" "${after}" > "${after}.changes"
  # Sorted only once normalized, so the random part of a masked name sets no order.
  tr '\t' ' ' < "${after}.changes" | normalize "$@" | LC_ALL=C sort
  mkdir -p "${after}.records"
  while IFS=$'\t' read -r kind p; do
    [[ "${kind}" == written ]] || continue
    n=$((n + 1)); rec="${after}.records/${n}"
    if [[ -L "${p}" ]]; then printf '==> %s -> %s <==\n' "${p}" "$(readlink "${p}")" | normalize "$@" > "${rec}"; continue; fi
    normalize "$@" "${p}" < "${p}" > "${after}.body"
    { printf '==> %s (%s bytes) <==\n' "${p}" "$(wc -c < "${after}.body" | tr -d ' ')" | normalize "$@"; cat "${after}.body"; echo; } > "${rec}"
  done < "${after}.changes"
  # The records by their normalized header, then by a checksum of the whole record for two headers
  # a mask made the same.
  for rec in "${after}.records"/*; do
    [[ -e "${rec}" ]] || continue
    printf '%s\t%s\t%s\n' "$(head -1 "${rec}")" "$(cksum < "${rec}")" "${rec}"
  done | LC_ALL=C sort | while IFS=$'\t' read -r _ _ rec; do cat "${rec}"; done
}

# normalize <tree> <tree as given> <run dir> <version> [file] — stdin with the replacements and masks
# above; with [file], stdin is that file's content, and its own masks apply.
# A calls:<name> stream in place of [file] gets a call's masks.
normalize() {
  DR_T="$1" DR_TL="$2" DR_R="$3/root" DR_D="$3" DR_V="$4" DR_F="${5-}" perl -pe '
    BEGIN { @r = sort { length($b->[0]) <=> length($a->[0]) } grep { length $_->[0] }
              ([$ENV{DR_T}, "<tree>"], [$ENV{DR_TL}, "<tree>"], [$ENV{DR_R}, "<root>"], [$ENV{DR_D}, "<run>"]); $f = $ENV{DR_F} }
    for $p (@r) { s/\Q$p->[0]\E/$p->[1]/g }
    s/\bversion=\Q$ENV{DR_V}\E(?=\s|$)/version=<version>/g if length $ENV{DR_V};
    s/\b\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ\b/<time>/g;
    s/\bpid([ =:])\d+\b/pid$1<pid>/g;
    s/\b(tmp|swarm-[a-z]+(?:-[a-z]+)*)\.[A-Za-z0-9]{6,}\b/$1.<tmp>/g;
    if ($f =~ m{/pid$}) { s/^\d+$/<pid>/ }
    if ($f =~ /^calls:/ && /^herdr /) { s/(?<= --seq )\d{19}(?=\s|$)/<seq>/g }
    if ($f =~ /^calls:/ && /^@@ \[/) { s/(?<= --seq )\d{19}(?=[\s\]]|$)/<seq>/g }
    if ($f =~ m{/\.swarm/run-times\.tsv$}) {
      $nl = chomp; @c = split /\t/, $_, -1;
      $c[2] = "<seconds>" if @c > 2 && $c[2] =~ /^\d+\.\d{3}$/;
      $c[3] = "<load>" if @c > 3 && $c[3] =~ /^(\d+(\.\d+)?|-)$/;
      $_ = join("\t", @c) . ($nl ? "\n" : "");   # a row with no newline keeps none
    }'
}

# shim <tool> <meta> <stub> — write <meta>/shims/<tool>: log the call to <meta>/calls, then exec
# <stub>; with no <stub>, fail loudly. It never looks on PATH. Each argument is logged with the paths
# in <meta>/paths ("<label>\t<path>" lines, longest path first) replaced by their labels, then quoted
# as printf %q quotes it (the labels left as they are), so a path with a space is replaced before %q
# escapes it.
# Each line starts with the call's place: bg or fg (its own SIGINT and SIGQUIT both ignored or
# not), a tab, its chain of pids from its own up (each "<pid>=w" when its parent sleeps
# in a wait with it as its youngest child), ending in "top" when the chain reached the command's pid (in
# <meta>/group) or "-" when it stopped at a process outside the run first, and a tab; or "?", a tab
# and "?" when the chain could not be read. Each pid in the chain goes to
# <meta>/procs too, with its parent then and its argv: "<pid>\t<ppid>\t<argv>" lines.
shim() {
  { printf '#!/usr/bin/env bash\nTOOL=%q LOG=%q STUB=%q PATHS=%q GROUP=%q PROCS=%q PERL=%q PS=%q WAITED=%q\n' \
      "$1" "$2/calls" "$3" "$2/paths" "$2/group" "$2/procs" "$(command -v perl)" "$(command -v ps)" "$2/waited.pl"
    cat <<'SHIM'
# This pid's start probe has just run for this shim: place_calls drops that record by this line.
[[ -z "${DIFF_RUN_STARTS:-}" ]] || printf '%s\tshim\n' "$$" >> "${DIFF_RUN_STARTS}" 2>/dev/null || true
# The call's place. The chain climbs from this shim's pid through each parent up to the command,
# whatever groups it crosses (bin/lib/merge.sh's within runs a command in a group of its own, and one
# can run inside another). A chain that reaches pid 1 first is an orphan's: it keeps each parent in the
# command's group, or in the group of the process below it (the rest of a group a setsid'd run made),
# or that holds the run's marker (DIFF_RUN_MARK), and stops below the first that does not, a process
# outside the run.
# shellcheck disable=SC2016 # perl's own variables
place="$("${PERL}" -e '
  my ($me, $gf, $pf, $ps, $wl) = @ARGV;
  my $mark = "DIFF_RUN_MARK=" . ($ENV{DIFF_RUN_MARK} // "");
  # marked <pid> — whether <pid> holds the marker: from /proc where there is one, else from ps -E.
  sub marked {
    my ($p) = @_;
    return 0 if $mark eq "DIFF_RUN_MARK=";
    if (-d "/proc/self") {
      open(my $e, "<", "/proc/$p/environ") or return 0;
      local $/ = "\0"; while (<$e>) { chomp; return 1 if $_ eq $mark }
      return 0;
    }
    # macOS ps prints the environment only for -A, never for -p <pid>.
    open(my $e, "-|", $ps, "-A", "-wwE", "-o", "pid=,command=") or return 0;
    my $hit = 0;
    while (my $line = <$e>) {
      chomp $line; $line =~ s/^\s+//;
      my ($q, $rest) = split /\s+/, $line, 2;
      next unless defined $q && $q eq $p;
      $hit = 1 if index("$rest ", " $mark ") >= 0;
    }
    close $e;
    return $hit;
  }
  # Both, as bash and sh start each `&` job; trap "" INT, or Python ignoring SIGINT in a cleanup
  # (bin/lib/ci_gate.py), leaves SIGQUIT as it was.
  my $flag = ($SIG{INT} // "") eq "IGNORE" && ($SIG{QUIT} // "") eq "IGNORE" ? "bg" : "fg";
  my $g = "";
  if (open(my $f, "<", $gf)) { $g = <$f> // ""; chomp $g; close $f }
  open(my $l, "-|", $ps, "-ww", "-A", "-o", "pid=,ppid=,pgid=,stat=,args=") or exit 1;
  my (%up, %grp, %stat, %argv, %kids);
  while (<$l>) { chomp; s/^\s+//; my ($p, $u, $pg, $st, $a) = split /\s+/, $_, 5; ($up{$p}, $grp{$p}, $stat{$p}, $argv{$p}) = ($u, $pg, $st, $a // ""); push @{$kids{$u}}, $p }
  close $l or exit 1;
  # Up to the command, whatever groups the chain crosses; past pid 1 or a missing parent it is the
  # chain of an orphan, cut where the group rule first fails.
  my ($p, $end, @all, %seen) = ($me, "-");
  while (exists $up{$p} && !$seen{$p}++) {
    if ($p eq $g) { $end = "top"; last }
    push @all, $p;
    my $u = $up{$p};
    last if $u <= 1 || !exists $up{$u};
    $p = $u;
  }
  my @chain = @all;
  if ($end ne "top") {
    @chain = ();
    for my $i (0 .. $#all) {
      push @chain, $all[$i];
      my $u = $all[$i + 1] // last;
      last if $grp{$u} ne $g && $grp{$u} ne $grp{$all[$i]} && !marked($u);
    }
  }
  # The chain is empty only when this shim is the command itself, as in FX_CMD=(gh api user).
  exit 1 unless @chain || $end eq "top";
  open(my $o, ">>", $pf) or exit 1;
  print $o join("", map { "$_\t$up{$_}\t$argv{$_}\n" } @chain);
  close $o or exit 1;
  # A process its parent waits on is marked "<pid>=w" (meta/waited.pl, which the start probe uses too).
  require $wl;
  my $snap = sub { (\%stat, \%kids) };
  # Only a parent in the run can wait on it: the next process up the chain, or the command itself. An
  # orphan gets a new parent (pid 1, or a reaper outside the run) that often sleeps in a wait with it
  # newest.
  my @marks;
  for my $i (0 .. $#chain) {
    my $in = $i < $#chain || $end eq "top";
    push @marks, $in && dr_waited($up{$chain[$i]} // "", $chain[$i], $snap) ? "$chain[$i]=w" : $chain[$i];
  }
  print "$flag\t", join(" ", @marks, $end);' "$$" "${GROUP}" "${PROCS}" "${PS}" "${WAITED}" 2>/dev/null)" || place=""
[[ "${place}" == [bf]g$'\t'* ]] || place=$'?\t?'
# A call from inside a stub, or from this shim through anything on PATH, is refused: a loop back
# through the shim would fork without end.
if [[ -n "${DIFF_RUN_SHIM:-}" ]]; then
  printf '%s\t%s re-entered from %s\n' "${place}" "${TOOL}" "${DIFF_RUN_SHIM}" >> "${LOG}"
  echo "diff_run: the ${TOOL} shim was called again from inside ${DIFF_RUN_SHIM}'s stub, so it fails: ${TOOL} $*" >&2
  exit 1
fi
export DIFF_RUN_SHIM="${TOOL}"
# One write a call, so calls made at once never mix within a line.
q=""
for a in "$@"; do
  while IFS=$'\t' read -r label p; do a="${a//"${p}"/${label}}"; done < "${PATHS}"
  printf -v q '%s %q' "${q}" "${a}"
done
q="${q//\\<tree\\>/<tree>}"; q="${q//\\<root\\>/<root>}"; q="${q//\\<run\\>/<run>}"   # %q escapes the labels' < and >
printf '%s\t%s%s\n' "${place}" "${TOOL}" "${q}" >> "${LOG}"
# The stub runs in this shim's pid: a bash stub's own start probe would log that pid as a background
# start, and the call would lose its place.
unset BASH_ENV DIFF_RUN_STARTS
[[ -z "${STUB}" ]] || exec "${STUB}" "$@"
echo "diff_run: no stub answers this ${TOOL} call, so it fails; a real ${TOOL} is never run: ${TOOL} $*" >&2
exit 1
SHIM
  } > "$2/shims/$1"
  chmod +x "$2/shims/$1"
}

# build <fixture> <root> <tree> <vars> — run fx_<fixture> in <root> and write the FX_ settings it made
# to <vars>. Run it in a subshell of its own, not under || or &&, so set -e holds inside.
build() {
  # shellcheck disable=SC2034 # the fixture reads ROOT and TREE
  ROOT="$2" TREE="$3"
  FX_CMD=(); FX_ENV=(); FX_STDIN=/dev/null; FX_CWD="$2"; FX_GH=""; FX_HERDR=""
  FX_CALLS=()
  cd "$2"
  "fx_$1"
  [[ ${#FX_CMD[@]} -gt 0 ]] || { echo "fx_$1 set no FX_CMD" >&2; return 1; }
  declare -p FX_CMD FX_ENV FX_STDIN FX_CWD FX_GH FX_HERDR FX_CALLS > "$4"
}

# watch_group <pid> <meta> — count <pid>'s group every 0.2 s while it has a member: past MAX_PROCS,
# or once <pid> has run TIMEOUT seconds, kill the group and write <meta>/killed: RUNAWAY or TIMEOUT,
# a tab, then why, with the group's three most common argvs and their counts.
watch_group() {
  local n left why="" i start="${SECONDS}"
  while left="$(pgrep -g "$1" 2>/dev/null)" || kill -0 "$1" 2>/dev/null; do
    n="$(printf '%s\n' "${left}" | grep -c .)" || n=0
    if [[ ${n} -gt ${MAX_PROCS} ]]; then why="RUNAWAY"$'\t'"more than ${MAX_PROCS} processes in its group"
    elif [[ $((SECONDS - start)) -ge ${TIMEOUT} ]]; then why="TIMEOUT"$'\t'"still running after ${TIMEOUT}s"; fi
    if [[ -n "${why}" ]]; then
      printf '%s; killed; it ran: %s\n' "${why}" "$(ps -o args= -p "${left//$'\n'/,}" 2>/dev/null | sort | uniq -c | sort -rn | head -3 | tr -s ' ' | tr '\n' ';')" > "$2/killed"
      # Again until the group is empty: a KILL can miss a child forked while it walks the group.
      for ((i = 0; i < 50; i++)); do
        kill -KILL -- "-$1" 2>/dev/null || true; kill -KILL "$1" 2>/dev/null || true
        [[ -n "$(pgrep -g "$1" 2>/dev/null)" ]] || break; sleep 0.1
      done
      return 0
    fi
    sleep 0.2
  done
}

# place_calls <meta> <command pid> — split the calls in <meta>/calls by their place: <meta>/fg the
# foreground calls, in order; <meta>/steps one block per background step, in the order the steps
# made their first calls, each an "@@ [<argv>] <first call>" line and then the step's calls in order;
# and <meta>/unplaced a "<call>\t<why>" line for each call the run cannot place. A process is on the
# foreground path when it is the command, a bash that <meta>/starts says started with SIGINT or
# SIGQUIT as it was, a process in a foreground call's chain, or one marked waited on (=w) by the first
# call that saw it. A background call's step is the first process of its chain, walked down from the
# command, that is none of these; with none, or with only its leaf below a process on the foreground
# path that is not the command, it is a foreground call. A chain the shim cut short, as a process
# above it had exited, goes on through each top's parent as first seen (in <meta>/procs or
# <meta>/starts), so a worker whose launcher exits keeps the launcher's step.
place_calls() {
  # shellcheck disable=SC2016 # perl's own variables
  DR_TOP="$2" perl -e '
    my $m = shift; my $g = $ENV{DR_TOP};
    require "$m/waited.pl";
    my (%argv, %first_up, @calls, %fg_proc, %bg_start, %step, %waited_first, %probe_waited, @order);
    if (open(my $f, "<", "$m/procs")) { while (<$f>) { chomp; my ($p, $u, $a) = split /\t/, $_, 3; $argv{$p} //= $a // ""; $first_up{$p} //= $u if ($u // 0) > 1 } }
    if (open(my $f, "<", "$m/starts")) {
      my %starts;
      while (<$f>) {
        chomp; my ($p, $s, $rest) = split /\t/, $_, 3; $s //= ""; $rest //= "";
        if ($s eq "up") { $rest =~ s/^\s+//; my ($u, $a) = split /\s+/, $rest, 2; $argv{$p} //= $a // ""; $first_up{$p} //= $u if ($u // 0) > 1; next }
        if ($s eq "shim") { pop @{$starts{$p}}; next }
        if ($s eq "w" || $s eq "nw") { $probe_waited{$p} //= $s eq "w" ? 1 : 0; next }
        push @{$starts{$p}}, [$s, $rest];
      }
      for my $p (keys %starts) {
        for my $r (@{$starts{$p}}) {
          $fg_proc{$p} = 1 if $r->[0] eq "fg";
          $bg_start{$p} = 1 if $r->[0] eq "ign";
          $first_up{$p} //= $r->[1] if $r->[1] =~ /^\d+$/ && $r->[1] > 1;
        }
      }
    }
    $fg_proc{$g} = 1;
    open(my $f, "<", "$m/calls") or die "diff_run: no $m/calls\n";
    while (<$f>) {
      chomp; my ($flag, $chain, $call) = split /\t/, $_, 3; my @c = split / /, $chain; my $end = pop @c; my %w;
      for (@c) { $w{$_} = 1 if s/=w$// }
      push @calls, { flag => $flag, chain => \@c, waited => \%w, end => $end // "", call => $call // "" };
    }
    for my $c (@calls) { next unless $c->{flag} eq "fg"; $fg_proc{$_} = 1 for @{$c->{chain}} }
    # Whether each process was waited on, as the first call that saw it found it. A parent waiting on
    # a process at once forks nothing until it ends, so one whose parent made a call through a newer
    # child (a newer pid, as dr_newer reads them) before its own last call was joined later (`( ... ) & gh ...; wait`), not
    # waited on at once: it stays off the foreground path, whenever its first call came.
    my (%parent, %last, @kid_calls);
    for my $n (0 .. $#calls) {
      my @ch = @{$calls[$n]{chain}};
      for my $i (0 .. $#ch) {
        $waited_first{$ch[$i]} //= $calls[$n]{waited}{$ch[$i]} ? 1 : 0;
        $last{$ch[$i]} = $n;
        my $u = $i < $#ch ? $ch[$i + 1] : ($calls[$n]{end} eq "top" ? $g : undef);
        next unless defined $u;
        $parent{$ch[$i]} //= $u;
        push @kid_calls, [$u, $ch[$i], $n];
      }
    }
    # A start probe saw the parent of a background bash while it ran, before that bash made any call,
    # and a launcher that exits before its worker calls is known only so: its view comes first.
    $waited_first{$_} = $probe_waited{$_} for keys %probe_waited;
    for my $k (@kid_calls) {
      my ($u, $e, $n) = @$k;
      for my $x (keys %waited_first) {
        next unless $waited_first{$x} && ($parent{$x} // "") eq $u && dr_newer($e, $x) && $n < $last{$x};
        $waited_first{$x} = 0;
      }
    }
    open(my $fg, ">", "$m/fg") or die "diff_run: cannot write $m/fg\n";
    open(my $un, ">", "$m/unplaced") or die "diff_run: cannot write $m/unplaced\n";
    for my $c (@calls) {
      my ($chain, $end, $call) = ($c->{chain}, $c->{end}, $c->{call});
      my $path = $c->{flag} eq "fg" || $c->{flag} eq "bg" ? $c->{flag} : "?";
      my $root;
      if ($path eq "bg") {
        if ($end ne "top") {
          my %in = map { $_ => 1 } @$chain;
          my $u;
          while (@$chain && defined($u = $first_up{$chain->[-1]}) && $u ne $g && !$in{$u}++) { push @$chain, $u }
        }
        # Down from the command, past each process on the foreground path: one known so, or one its
        # parent waited on (a waited subshell, the dispatch of swarm.sh among them, is a boundary, so a
        # run it starts in the background is a step of its own). The first process past them is the
        # step. A leaf that is that first one, below a process on the foreground path that is not the
        # command, is the own `&` job of that process (bin/gh-shim/gh starts the real gh so, and waits on
        # it): a foreground call. A `gh ... &` of the command itself (hooks/agent-state.sh runs herdr so) is
        # a step, whether the command has exited by the call or not, and so is a leaf that began as a
        # background bash and then ran exec gh (as bash -c "...; exec gh ..." & does).
        my $k = $#$chain;
        $k-- while $k >= 0 && ($fg_proc{$chain->[$k]} || $waited_first{$chain->[$k]});
        if ($k < 0 || ($k == 0 && @$chain > 1 && !$bg_start{$chain->[0]})) { $path = "fg" } else { $root = $chain->[$k] }
      }
      if ($path eq "fg") {
        if ($end eq "top") { print $fg "$call\n" }
        else { print $un "$call\tits process outlived the command but did not start in the background\n" }
        next;
      }
      if ($path ne "bg") { print $un "$call\tthe shim could not read its chain of pids\n"; next }
      push @order, $root unless $step{$root};
      push @{$step{$root}}, $call;
    }
    open(my $st, ">", "$m/steps") or die "diff_run: cannot write $m/steps\n";
    for my $r (@order) {
      (my $a = $argv{$r} // "?") =~ s/\b\Q$g\E\b/<pid>/g;
      print $st "@@ [$a] $step{$r}[0]\n", map { "$_\n" } @{$step{$r}};
    }' "$1"
}

# bash_env <meta> — write <meta>/bash-env, the command's BASH_ENV: each bash that starts under the
# command (a script, bash -c, bin/gh-shim/gh; not a subshell, which is a fork) first appends
# "<pid>\tfg\t<ppid>" to <meta>/starts when it started with SIGINT or SIGQUIT as it was, or
# "<pid>\tign\t<ppid>" when both were ignored. An ignored one then appends, while its parent still
# runs, "<ppid>\tup\t<its parent>\t<its argv>", so a launcher that exits before its worker's first
# call is still known by its argv and its parent. One perl reads the two signals, as the shim does
# (it inherits them from the bash, and bash's own trap -p reports a signal ignored at start
# differently by version: 3.2 prints nothing, 5.x a trap of ''), and looks the parent up in the same
# process, so the launcher has the least time to exit first. Nothing is printed or left set. Each shim then
# appends "<pid>\tshim", and place_calls drops the record just before it for that pid, the shim's own
# (bash 3.2 sets no $0 a probe could tell a shim by): a record left for a shim's pid is a bash that
# ran there before it, as `exec gh` leaves.
bash_env() {
  { printf 'DIFF_RUN_PS=%q DIFF_RUN_PERL=%q DIFF_RUN_WAITED=%q\n' "$(command -v ps)" "$(command -v perl)" "$1/waited.pl"
    cat <<'PROBE'
if [ -n "${DIFF_RUN_STARTS-}" ]; then
  DIFF_RUN_REC="$("${DIFF_RUN_PERL}" -e 'my ($pid, $pp, $ps, $wl) = @ARGV;
    unless (($SIG{INT} // "") eq "IGNORE" && ($SIG{QUIT} // "") eq "IGNORE") { print "$pid\tfg\t$pp\n"; exit 0 }
    print "$pid\tign\t$pp\n";
    my $u = "";
    if (open(my $l, "-|", $ps, "-ww", "-o", "ppid=,args=", "-p", $pp)) { $u = join("", <$l>); chomp $u; print "$pp\tup\t$u\n" if length $u }
    my ($gp) = $u =~ /^\s*(\d+)/;
    exit 0 unless $gp && $gp > 1 && require $wl;
    # Only a parent in the run, one that holds its marker, can wait on it (Linux reads that from /proc).
    if (-d "/proc/self") {
      my $m = "DIFF_RUN_MARK=" . ($ENV{DIFF_RUN_MARK} // "");
      open(my $e, "<", "/proc/$gp/environ") or exit 0;
      local $/ = "\0"; my $in = 0; while (<$e>) { chomp; $in = 1 if $_ eq $m } close $e;
      exit 0 unless $in;
    }
    my $snap = sub {
      my (%stat, %kids);
      if (open(my $a, "-|", $ps, "-A", "-o", "pid=,ppid=,stat=")) { while (<$a>) { s/^\s+//; my ($p, $q, $st) = split; $stat{$p} = $st; push @{$kids{$q}}, $p } }
      return (\%stat, \%kids);
    };
    print "$pp\t", (dr_waited($gp, $pp, $snap) ? "w" : "nw"), "\n";' \
    "$$" "${PPID}" "${DIFF_RUN_PS}" "${DIFF_RUN_WAITED}" 2>/dev/null)" || DIFF_RUN_REC=""
  [ -z "${DIFF_RUN_REC}" ] || printf '%s\n' "${DIFF_RUN_REC}" >> "${DIFF_RUN_STARTS}" 2>/dev/null || :
  unset DIFF_RUN_REC
fi
unset DIFF_RUN_PS DIFF_RUN_PERL DIFF_RUN_WAITED
PROBE
  } > "$1/bash-env"
}

# waited_lib <meta> — write <meta>/waited.pl, which the shim and the start probe both load:
# dr_waited <parent> <child> <snapshot> is 1 when <parent> sleeps in a wait with <child> as its
# youngest child (the newest pid, in circular order, as pids wrap). Bash forks a foreground command
# and then waits, so its newest child is the one it waits on, and an `&` job it forked earlier is
# older; `( ... ) & wait $!` leaves its subshell so too, and a command substitution leaves its parent
# reading the child's output from a pipe. Where /proc names what <parent> sleeps in (Linux),
# <parent> itself is read, not ps: ps reads /proc one process at a time, so a child forked meanwhile
# can be missing. <parent> must be in a wait or a pipe read before and between two reads of its own
# list of children (which holds a child not yet reaped too), and <child> must be the youngest in
# both; one blocked opening a FIFO is not waiting. Where /proc names nothing (macOS, whose ps reads the whole table at once, or a kernel that
# hides it), <snapshot> (a sub that returns ps -A's stat and children by pid) is read the same way, a
# sleeping parent taken as waiting.
waited_lib() {
  cat > "$1/waited.pl" <<'WAITED'
sub dr_slurp { my ($f) = @_; open(my $h, "<", $f) or return ""; my $c = join("", <$h>); close $h; return $c }
# Pids wrap (at pid_max on Linux, past 99999 on macOS), so their order is circular: the youngest of a
# set forked close together is the last before the widest gap between them, and a pid is newer than
# another when it lies less than half the range after it.
sub dr_range { my $m = dr_slurp("/proc/sys/kernel/pid_max"); return $m =~ /^(\d+)/ ? $1 + 1 : 100000 }
sub dr_newer { my ($e, $x) = @_; my $r = dr_range(); my $d = ($e - $x) % $r; return $d > 0 && $d < $r / 2 }
sub dr_youngest {
  my @p = sort { $a <=> $b } grep { /^\d+$/ } @_;
  return -1 unless @p;
  my $r = dr_range(); my ($best, $gap) = ($p[-1], $p[0] + $r - $p[-1]);
  for my $i (0 .. $#p - 1) { ($best, $gap) = ($p[$i], $p[$i + 1] - $p[$i]) if $p[$i + 1] - $p[$i] > $gap }
  return $best;
}
sub dr_waited {
  my ($u, $child, $snap) = @_;
  return 0 unless length $u;
  my $w1 = dr_slurp("/proc/$u/wchan");
  if ($w1 =~ /[a-z]/) {
    return 0 unless $w1 =~ /^(?:do_wait|kernel_wait4|pipe_read|anon_pipe_read|pipe_wait)/;
    my $cf = "/proc/$u/task/$u/children";
    if (-e $cf) {
      my $one = sub { dr_youngest(split " ", dr_slurp($cf)) eq $child };
      return $one->() && dr_slurp("/proc/$u/wchan") =~ /^(?:do_wait|kernel_wait4|pipe_read|anon_pipe_read|pipe_wait)/ && $one->() ? 1 : 0;
    }
  }
  my ($stat, $kids) = $snap->();
  return ($stat->{$u} // "") =~ /^S/ && dr_youngest(@{$kids->{$u} // []}) eq $child ? 1 : 0;
}
1;
WAITED
}

# split_steps <steps> <out> — write each step of <steps> (place_calls' blocks, normalized) to
# <out>/step.<k> and its label ("[<argv>] <first call>") as line <k> of <out>/steps, sorted by label
# and then by calls, so no step's place depends on when it ran. A label two steps share gets " #2"
# on its second, " #3" on its third, and so on.
split_steps() {
  # shellcheck disable=SC2016 # perl's own variables
  perl -e '
    my ($in, $out) = @ARGV; my (@s, $cur, %n, $k);
    open(my $f, "<", $in) or die "diff_run: no $in\n";
    while (<$f>) { chomp; if (s/^@@ //) { push @s, $cur = [$_, ""] } elsif ($cur) { $cur->[1] .= "$_\n" } }
    open(my $ix, ">", "$out/steps") or die "diff_run: cannot write $out/steps\n";
    for my $s (sort { $a->[0] cmp $b->[0] or $a->[1] cmp $b->[1] } @s) {
      my $c = ++$n{$s->[0]}; $k++;
      print $ix ($c > 1 ? "$s->[0] #$c" : $s->[0]), "\n";
      open(my $o, ">", "$out/step.$k") or die "diff_run: cannot write $out/step.$k\n"; print $o $s->[1]; close $o;
    }' "$1" "$2"
}

# alive <pid> <dir> — the pids still alive in <pid>'s group; with none, of the processes that hold the
# marker of the run in <dir>; with none, "hold" while a process still holds the run's hold pipe (macOS
# shows no environment for its own binaries, so a setsid'd /bin/bash has no marker ps can see).
alive() {
  local l
  l="$(pgrep -g "$1" || true)"
  [[ -n "${l}" ]] || l="$(marked "$2:")"
  [[ -n "${l}" ]] || ! kill -0 "$(cat "$2/meta/hold.pid" 2>/dev/null)" 2>/dev/null || l=hold
  printf '%s' "${l}"
}

# holders <dir> — the pids that hold the run's hold pipe open, from /proc/<pid>/fd where there is a
# /proc, else as lsof names each one's fd 19 (the run refuses to start with neither); the pipe's
# reader is left out.
holders() {
  local r
  r="$(cat "$1/meta/hold.pid" 2>/dev/null)" || r=""
  if [[ -d /proc/self ]]; then
    # shellcheck disable=SC2016 # perl's own variables
    DR_F="$1/meta/hold" perl -e 'for my $d (glob "/proc/[0-9]*/fd") { opendir(my $h, $d) or next;
        for my $e (readdir $h) { my $l = readlink("$d/$e"); next unless defined $l && $l eq $ENV{DR_F};
          print "$1\n" if $d =~ m{^/proc/(\d+)/}; last } }'
  else
    # By fd 19 and the pipe's name: macOS lsof finds no FIFO holder by its path alone.
    lsof -nP -w -a -d 19 -F pn 2>/dev/null | DR_F="$1/meta/hold" awk '/^p/ { p = substr($0, 2) } /^n/ && substr($0, 2) == ENVIRON["DR_F"] { print p }'
  fi | grep -vxF -- "${r:-none}" || true
}

# run_one <fixture> <a|b> <n> — build and run <fixture> against tree <a|b>, its run <n>, leaving its
# streams in ${WORK}/<fixture>.<a|b>.<n>/out/. Returns 2 when the build failed, 3 when a process
# outlived the bound, watch_group killed the group or a call could not be placed.
# A named call it did not make returns 3 too.
run_one() {
  local fx="$1" side="$2" n="$3" tag="$2" tree tree_l dir root meta pid kind why rc=0 red="" left="" i s v g base_path missing="" envs=() FX_CMD FX_ENV FX_STDIN FX_CWD FX_GH FX_HERDR FX_CALLS
  if [[ "${side}" == a ]]; then tree="${TREE_A}" tree_l="${TREE_A_L}"; else tree="${TREE_B}" tree_l="${TREE_B_L}"; fi
  [[ "${n}" -eq 1 ]] || tag="${side} run ${n}"
  dir="${WORK}/${fx}.${side}.${n}"; root="${dir}/root"; meta="${dir}/meta"
  mkdir -p "${root}" "${meta}/shims" "${meta}/gh-config" "${dir}/out"
  ( set -e; build "${fx}" "${root}" "${tree}" "${meta}/vars" ) > "${meta}/build.log" 2>&1 &
  echo "$!" > "${meta}/build.pid"
  wait "$!" || rc=$?
  rm -f "${meta}/build.pid"
  if [[ ${rc} -ne 0 ]]; then
    echo "BUILD-FAIL ${fx} (${tag}: ${tree}): fx_${fx} exited ${rc}"; sed 's/^/  /' "${meta}/build.log"; return 2
  fi
  # shellcheck source=/dev/null # build's declare -p
  source "${meta}/vars"
  mkdir -p "${root}/tmp"
  : > "${meta}/calls"; : > "${meta}/procs"; : > "${meta}/starts"
  bash_env "${meta}"
  waited_lib "${meta}"
  for v in "<tree>"$'\t'"${tree}" "<tree>"$'\t'"${tree_l}" "<root>"$'\t'"${root}" "<run>"$'\t'"${dir}"; do printf '%d\t%s\n' "${#v}" "${v}"; done |
    LC_ALL=C sort -rn | cut -f2- > "${meta}/paths"
  shim gh "${meta}" "${FX_GH}"
  shim herdr "${meta}" "${FX_HERDR}"
  # A shim or probe that does not parse breaks both trees alike, and so would compare clean: it fails.
  for v in "${meta}/shims/gh" "${meta}/shims/herdr" "${meta}/bash-env"; do
    bash -n "${v}" 2> "${meta}/parse.log" || { echo "BUILD-FAIL ${fx} (${tag}): diff_run's own ${v##*/} does not parse"; sed 's/^/  /' "${meta}/parse.log"; return 2; }
  done
  perl -c "${meta}/waited.pl" > /dev/null 2> "${meta}/parse.log" || { echo "BUILD-FAIL ${fx} (${tag}): diff_run's own waited.pl does not parse"; sed 's/^/  /' "${meta}/parse.log"; return 2; }
  # FX_ENV goes before the settings that keep the shims in front, as env's last word for a name wins:
  # a PATH of the fixture's own goes behind the shims, and HERDR_BIN_PATH and GH_CONFIG_DIR stay ours.
  # The marker and the bash start probe stay ours too.
  base_path="${PATH}"
  for v in ${FX_ENV[@]+"${FX_ENV[@]}"}; do [[ "${v}" != PATH=* ]] || base_path="${v#PATH=}"; done
  for v in ${PASS_ENV}; do [[ -z "${!v+x}" ]] || envs+=("${v}=${!v}"); done
  [[ -e "${tree}/.git" || -z "${!PASS_BIN+x}" ]] || envs+=("${PASS_BIN}=${!PASS_BIN}")
  envs+=("TMPDIR=${root}/tmp" "CLAUDE_CONFIG_DIR=${root}/claude-config" "CLAUDE_PLUGIN_ROOT=${tree}" ${FX_ENV[@]+"${FX_ENV[@]}"}
    "PATH=${meta}/shims:${base_path}" "GH_CONFIG_DIR=${meta}/gh-config" "HERDR_BIN_PATH=${meta}/shims/herdr"
    "DIFF_RUN_MARK=${dir}:" "BASH_ENV=${meta}/bash-env" "DIFF_RUN_STARTS=${meta}/starts")
  snapshot "${root}" > "${meta}/before"
  # The hold pipe: a reader runs while any process holds its write end, which the command gets on fd 19
  # and every process it starts inherits, a setsid'd one too. run_one lets go of its own copy at once,
  # and the watcher never takes one.
  mkfifo "${meta}/hold"
  cat "${meta}/hold" > /dev/null 2>&1 & echo "$!" > "${meta}/hold.pid"
  exec 19> "${meta}/hold"
  # A background job starts with INT and QUIT ignored; perl puts them back, writes its pid (the group's
  # id once setpgrp runs) to meta/group, then makes the group and execs the command.
  # shellcheck disable=SC2016 # perl's own variables
  ( cd "${FX_CWD}" && exec env -i "${envs[@]}" perl -e \
      '$SIG{INT} = $SIG{QUIT} = "DEFAULT"; $g = shift; open(G, ">", $g) && print(G "$$\n") && close(G) or exit 126;
       setpgrp(0, 0) or exit 126; exec { $ARGV[0] } @ARGV or exit 127' -- "${meta}/group" "${FX_CMD[@]}" ) \
    < "${FX_STDIN}" > "${meta}/stdout" 2> "${meta}/stderr" &
  pid=$!
  exec 19>&-
  watch_group "${pid}" "${meta}" & echo "$!" > "${meta}/watch.pid"
  rc=0; wait "${pid}" || rc=$?
  # The group first, then each process that left it but holds the marker or the hold pipe, within one
  # bound.
  for ((i = 0; i < BOUND * 10; i++)); do
    left="$(alive "${pid}" "${dir}")"; [[ -n "${left}" ]] || break; sleep 0.1
  done
  [[ ${BOUND} -gt 0 ]] || left="$(alive "${pid}" "${dir}")"
  if [[ -n "${left}" ]]; then
    [[ "${left}" != hold ]] || left="$(holders "${dir}")"
    if [[ -n "${left}" ]]; then ps -o args= -p "${left//$'\n'/,}" > "${meta}/stuck" 2>/dev/null || true
    else echo "a process that held the run's hold pipe and was gone by the time it was looked up" > "${meta}/stuck"; fi
    for ((i = 0; i < 50; i++)); do
      kill -KILL -- "-${pid}" 2>/dev/null || true
      for g in $(marked "${dir}:") $(holders "${dir}"); do kill -KILL "${g}" 2>/dev/null || true; done
      [[ -n "$(alive "${pid}" "${dir}")" ]] || break; sleep 0.1
    done
  fi
  # The reader goes once every holder is killed (or, in a race, had already gone).
  kill -KILL "$(cat "${meta}/hold.pid")" 2>/dev/null || true; wait "$(cat "${meta}/hold.pid")" 2>/dev/null || true; rm -f "${meta}/hold.pid"
  [[ -n "$(pgrep -g "${pid}" || true)" ]] || rm -f "${meta}/group"
  kill -TERM "$(cat "${meta}/watch.pid")" 2>/dev/null || true; wait "$(cat "${meta}/watch.pid")" 2>/dev/null || true; rm -f "${meta}/watch.pid"
  echo "${rc}" > "${meta}/exit"
  snapshot "${root}" > "${meta}/after"
  v="$(version_of "${tree}")"
  written "${meta}/before" "${meta}/after" "${tree}" "${tree_l}" "${dir}" "${v}" > "${dir}/out/files"
  place_calls "${meta}" "${pid}"
  for s in stdout stderr exit; do normalize "${tree}" "${tree_l}" "${dir}" "${v}" "${s}" < "${meta}/${s}" > "${dir}/out/${s}"; done
  normalize "${tree}" "${tree_l}" "${dir}" "${v}" calls:fg < "${meta}/fg" > "${dir}/out/calls:fg"
  normalize "${tree}" "${tree_l}" "${dir}" "${v}" calls:steps < "${meta}/steps" > "${meta}/steps.normal"
  split_steps "${meta}/steps.normal" "${dir}/out"
  # Each named call is the whole of a compared line, or that line's start up to a space.
  # It may be in calls:fg or in any step's stream.
  g=("${dir}/out/calls:fg"); for s in "${dir}/out"/step.*; do [[ ! -e "${s}" ]] || g+=("${s}"); done
  for v in ${FX_CALLS[@]+"${FX_CALLS[@]}"}; do
    awk -v c="${v}" '$0 == c || index($0, c " ") == 1 { f = 1 } END { exit !f }' "${g[@]}" && continue
    echo "MISSING ${fx} (${tag}): no call '${v}' in calls:fg or a step"; missing=1
  done
  if [[ -n "${KEEP}" ]]; then
    s="${KEEP}/${fx}/${side}"; [[ "${n}" -eq 1 ]] || s+=".${n}"
    # A kept directory used before may hold more steps than this run has: those go first.
    mkdir -p "${s}" && find "${s}" -maxdepth 1 -name 'step.*' -type f -delete && cp "${dir}/out/"* "${s}/"
  fi
  if [[ -s "${meta}/killed" ]]; then
    IFS=$'\t' read -r kind why < "${meta}/killed"; echo "${kind} ${fx} (${tag}): ${why}"; return 3
  fi
  if [[ -s "${meta}/stuck" ]]; then
    while IFS= read -r v; do echo "STUCK ${fx} (${tag}): still running ${BOUND}s after the command exited: ${v}"; done < "${meta}/stuck"
    red=1
  fi
  while IFS=$'\t' read -r s why; do
    echo "UNPLACED ${fx} (${tag}): ${why}: ${s}"; red=1
  done < <(normalize "${tree}" "${tree_l}" "${dir}" "${v}" calls:unplaced < "${meta}/unplaced")
  [[ -z "${red}" ]] || return 3
  [[ -z "${missing}" ]] || return 3
}

# step_file <out> <label> — the file that holds the step <label> in <out>, or /dev/null with none.
step_file() {
  local k
  k="$(DR_L="$2" awk '$0 == ENVIRON["DR_L"] { print NR; exit }' "$1/steps")"
  if [[ -n "${k}" ]]; then echo "$1/step.${k}"; else echo /dev/null; fi
}

# compare <fixture> <out-x> <out-y> <x> <y> <suffix> — print a DIFF line and a diff for each stream
# that differs between two runs' out/ directories, <x> and <y> naming them in the diff and <suffix>
# ending each DIFF line; each background step is matched by its label. Returns 1 when any differs.
compare() {
  local fx="$1" x="$2" y="$3" s fx_ fy lx ly red=0
  for s in ${STREAMS}; do
    cmp -s "${x}/${s}" "${y}/${s}" && continue
    red=1; echo "DIFF ${fx} ${s}$6"
    diff -u -L "$4/${fx}/${s}" -L "$5/${fx}/${s}" "${x}/${s}" "${y}/${s}" || true
  done
  while IFS= read -r s; do
    fx_="$(step_file "${x}" "${s}")"; fy="$(step_file "${y}" "${s}")"
    [[ "${fx_}" == /dev/null || "${fy}" == /dev/null ]] || ! cmp -s "${fx_}" "${fy}" || continue
    lx="$4/${fx}/calls:${s}"; [[ "${fx_}" != /dev/null ]] || lx+=" (no such step)"
    ly="$5/${fx}/calls:${s}"; [[ "${fy}" != /dev/null ]] || ly+=" (no such step)"
    red=1; echo "DIFF ${fx} calls:${s}$6"
    diff -u -L "${lx}" -L "${ly}" "${fx_}" "${fy}" || true
  done < <(LC_ALL=C sort -u "${x}/steps" "${y}/steps")
  return "${red}"
}

echo "a: ${TREE_A}"
echo "b: ${TREE_B}"
status=0
ran=() reds=()
for fx in "${names[@]}"; do
  red="" broken=""
  # The two runs go side by side, each with its own root; their lines come out a's first.
  # With --times, each repeat's two runs go after the last repeat's.
  for ((n = 1; n <= TIMES; n++)); do
    for side in a b; do run_one "${fx}" "${side}" "${n}" > "${WORK}/${fx}.${side}.${n}.log" 2>&1 & echo "$!" > "${WORK}/${fx}.${side}.${n}.pid"; done
    for side in a b; do
      rc=0; wait "$(cat "${WORK}/${fx}.${side}.${n}.pid")" || rc=$?
      rm -f "${WORK}/${fx}.${side}.${n}.pid"
      cat "${WORK}/${fx}.${side}.${n}.log"
      case "${rc}" in 0) ;; 2) broken=1 ;; *) red=1 ;; esac
    done
  done
  if [[ -n "${broken}" ]]; then status=2; continue; fi
  if [[ ${#allow[@]} -gt 0 ]]; then
    # diff_allow.py compares <fixture>.a/out/ with <fixture>.b/out/: each tree's first run.
    ln -s "${fx}.a.1" "${WORK}/${fx}.a"; ln -s "${fx}.b.1" "${WORK}/${fx}.b"
    ran+=("${fx}")
  else
    compare "${fx}" "${WORK}/${fx}.a.1/out" "${WORK}/${fx}.b.1/out" a b "" || red=1
  fi
  # Each repeat against its own tree's first run.
  for ((n = 2; n <= TIMES; n++)); do
    for side in a b; do
      compare "${fx}" "${WORK}/${fx}.${side}.1/out" "${WORK}/${fx}.${side}.${n}/out" "${side}" "${side}.${n}" " (${side} run ${n} against run 1)" || red=1
    done
  done
  if [[ ${#allow[@]} -gt 0 ]]; then
    [[ -z "${red}" ]] || { reds+=(--red "${fx}"); [[ ${status} -eq 2 ]] || status=1; }
    continue
  fi
  if [[ -n "${red}" ]]; then [[ ${status} -eq 2 ]] || status=1; else echo "same ${fx}"; fi
done
if [[ ${#ran[@]} -gt 0 ]]; then
  rc=0
  python3 "${HERE}/diff_allow.py" compare "${ALLOW_DIR}" "${WORK}" "${allow[@]}" ${reds[@]+"${reds[@]}"} -- "${ran[@]}" || rc=$?
  case "${rc}" in 0) ;; 1) [[ ${status} -eq 2 ]] || status=1 ;; *) status=2 ;; esac
fi
exit "${status}"
