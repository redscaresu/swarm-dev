#!/usr/bin/env bash
# diff_run.sh — the differential run: run each fixture once against <tree-a> and once against
# <tree-b>, and compare what the two runs did.
#
#   bash tests/diff_run.sh [--bound <s>] [--timeout <s>] [--max-procs <n>] [--keep <dir>] <tree-a> <tree-b> [fixture...]
#
#   --bound <s>        how long a run waits, once its command has exited, for the processes it left in
#                      its group (default 10); one still alive then is red, by its argv, and is killed
#   --timeout <s>      how long a command may run (default 300); past it, its group is killed, and red
#   --max-procs <n>    how many processes its group may hold at once (default 200); past it, the group
#                      is killed, and red, so a command that forks without end never fills the machine
#   --keep <dir>       also write each run's streams, as compared, to <dir>/<fixture>/<a|b>/<stream>
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
#   FX_CALLS  the calls the command must make, each a "<tool> <args>" prefix of a calls:fg line as
#             compared (such as "herdr agent list"); a tree's run that makes one of them in no line is
#             red (MISSING), so a command that exits early in both trees cannot pass by making no call
#             in either. A fixture that rightly makes no call names none.
#
# The command runs under env -i with only PATH, HOME, LANG, LC_ALL, TERM, USER, LOGNAME,
# SWARM_SLEEP_SCALE and SWARM_FORBID_PROJECT passed on (the ones set), TMPDIR=ROOT/tmp and
# CLAUDE_CONFIG_DIR=ROOT/claude-config, then FX_ENV, then three FX_ENV cannot override: PATH with the
# shims first (before FX_ENV's PATH when it sets one), GH_CONFIG_DIR an empty directory, and
# HERDR_BIN_PATH. So no GH_TOKEN or GITHUB_TOKEN of the caller's reaches it. It leads a process
# group of its own; once it exits, the run waits up to --bound seconds for every other process in the
# group. Its group is counted every 0.2 s from its start until it is gone, and killed past
# --max-procs or --timeout. The gh and herdr shims go first on PATH, and HERDR_BIN_PATH names the
# herdr one. Each logs its call, then runs FX_GH or FX_HERDR; with none, it says so on stderr and
# exits 1. Neither ever runs a gh or herdr found on PATH, and a shim called again from inside a stub
# (or from itself) refuses the call the same way, so no stub can loop back through it.
# SWARM_FORBID_PROJECT, the checkout make test runs from, never names a fixture's project, since each
# fixture root is a new directory, so a hook writes its events.tsv line there under make test too.
# CLAUDE_PLUGIN_ROOT=TREE, as Claude Code sets it for a hook hooks/hooks.json runs, goes in beside
# TMPDIR and CLAUDE_CONFIG_DIR, before FX_ENV, so a fixture can set its own.
#
# Streams compared, each after the replacements and masks below:
#   stdout, stderr, exit  the command's
#   files     each file under ROOT the run added or changed, by path and content, each symbolic
#             link by its target, and each it deleted, the list of paths first; files under a .git
#             directory are left out, since a git read can rewrite the index with stat data
#   calls:fg  the gh and herdr calls, in order, one "<tool> <args>" line each: in each argument the
#             tree and root paths are replaced first, then it is quoted as printf %q quotes it, so two
#             argument lists never log the same line
# Replacements: each tree's path (as given and as pwd -P prints it) becomes <tree>, the fixture root
# <root>, the run's own directory around it (where the shims and GH_CONFIG_DIR live) <run>, and
# version=<the tree's own .claude-plugin/plugin.json version> version=<version>. Masks,
# each of a fixed shape: an ISO time stamp (2026-11-20T09:30:00Z) becomes <time>; a pid after "pid ",
# "pid=" or "pid:", and the content of a file named pid, <pid>; a mktemp suffix after tmp. or
# swarm-<name>. (bin/lib/merge.sh's names) <tmp>; and, in .swarm/run-times.tsv, the seconds column
# (1.234) <seconds> and the load column (0.52, or -) <load>. A value of another shape is left as it is.
# In a calls stream, a herdr call's value after --seq of 19 digits (agent-state.sh's time.time_ns())
# becomes <seq>, and a value of another shape there is left as it is too.
#
# Exit 0 when every fixture's streams are the same, 1 when any differ (DIFF <fixture> <stream> and a
# diff for each), a process outlived the bound (STUCK <fixture> ...), or a group passed --max-procs
# (RUNAWAY <fixture> ...) or --timeout (TIMEOUT <fixture> ...), and 2 on a bad argument or a
# fixture that fails to build on either tree (BUILD-FAIL <fixture> ... and its output).
# A run that did not make a named call (MISSING <fixture> ...) exits 1 too.
set -euo pipefail

BOUND=10
TIMEOUT=300
MAX_PROCS=200
KEEP=""
STREAMS="stdout stderr exit files calls:fg"
PASS_ENV="HOME LANG LC_ALL TERM USER LOGNAME SWARM_SLEEP_SCALE SWARM_FORBID_PROJECT"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

usage() { sed -n '5,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
bad() { echo "diff_run: $*" >&2; usage >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bound) [[ "${2-}" =~ ^[0-9]+$ ]] || bad "--bound takes a whole number of seconds, not '${2-}'"; BOUND="$2"; shift 2 ;;
    --timeout) [[ "${2-}" =~ ^[1-9][0-9]*$ ]] || bad "--timeout takes a whole number of seconds above 0, not '${2-}'"; TIMEOUT="$2"; shift 2 ;;
    --max-procs) [[ "${2-}" =~ ^[1-9][0-9]*$ ]] || bad "--max-procs takes a whole number above 0, not '${2-}'"; MAX_PROCS="$2"; shift 2 ;;
    --keep) [[ -n "${2-}" ]] || bad "--keep takes a directory"; KEEP="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) bad "unknown option $1" ;;
    *) break ;;
  esac
done
[[ $# -ge 2 ]] || bad "two trees are needed"
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

WORK="$(mktemp -d)"; WORK="$(cd "${WORK}" && pwd -P)"
# Each side's worker (run_one) has its pid in ${WORK}/<fixture>.<side>.pid, and its build its pid in
# meta/build.pid, while they run. Each command's group id is in its meta/group from just before perl's
# setpgrp until the group is gone; perl writes it, so no command runs unrecorded. So the trap signals
# only what still runs, never an id a finished one gave back. It stops the workers first, so none
# starts a command after it, gives a command one of them had forked time to record itself, then kills
# each recorded command by its pid (one stopped before setpgrp) and its group (no pid is reused while
# its group lives).
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
    if ($f =~ m{/\.swarm/run-times\.tsv$}) {
      $nl = chomp; @c = split /\t/, $_, -1;
      $c[2] = "<seconds>" if @c > 2 && $c[2] =~ /^\d+\.\d{3}$/;
      $c[3] = "<load>" if @c > 3 && $c[3] =~ /^(\d+(\.\d+)?|-)$/;
      $_ = join("\t", @c) . ($nl ? "\n" : "");   # a row with no newline keeps none
    }'
}

# shim <tool> <meta> <stub> — write <meta>/shims/<tool>: log the call to <meta>/calls:fg, then exec
# <stub>; with no <stub>, fail loudly. It never looks on PATH. Each argument is logged with the paths
# in <meta>/paths ("<label>\t<path>" lines, longest path first) replaced by their labels, then quoted
# as printf %q quotes it (the labels left as they are), so a path with a space is replaced before %q
# escapes it.
shim() {
  { printf '#!/usr/bin/env bash\nTOOL=%q LOG=%q STUB=%q PATHS=%q\n' "$1" "$2/calls:fg" "$3" "$2/paths"
    cat <<'SHIM'
# A call from inside a stub, or from this shim through anything on PATH, is refused: a loop back
# through the shim would fork without end.
if [[ -n "${DIFF_RUN_SHIM:-}" ]]; then
  printf '%s re-entered from %s\n' "${TOOL}" "${DIFF_RUN_SHIM}" >> "${LOG}"
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
printf '%s%s\n' "${TOOL}" "${q}" >> "${LOG}"
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

# run_one <fixture> <a|b> — build and run <fixture> against tree <a|b>, leaving its streams in
# ${WORK}/<fixture>.<a|b>/out/. Returns 2 when the build failed, 3 when a process outlived the bound
# or watch_group killed the group.
# A named call it did not make returns 3 too.
run_one() {
  local fx="$1" side="$2" tree tree_l dir root meta pid kind why rc=0 left="" i s v base_path missing="" envs=() FX_CMD FX_ENV FX_STDIN FX_CWD FX_GH FX_HERDR FX_CALLS
  if [[ "${side}" == a ]]; then tree="${TREE_A}" tree_l="${TREE_A_L}"; else tree="${TREE_B}" tree_l="${TREE_B_L}"; fi
  dir="${WORK}/${fx}.${side}"; root="${dir}/root"; meta="${dir}/meta"
  mkdir -p "${root}" "${meta}/shims" "${meta}/gh-config" "${dir}/out"
  ( set -e; build "${fx}" "${root}" "${tree}" "${meta}/vars" ) > "${meta}/build.log" 2>&1 &
  echo "$!" > "${meta}/build.pid"
  wait "$!" || rc=$?
  rm -f "${meta}/build.pid"
  if [[ ${rc} -ne 0 ]]; then
    echo "BUILD-FAIL ${fx} (${side}: ${tree}): fx_${fx} exited ${rc}"; sed 's/^/  /' "${meta}/build.log"; return 2
  fi
  # shellcheck source=/dev/null # build's declare -p
  source "${meta}/vars"
  mkdir -p "${root}/tmp"
  : > "${meta}/calls:fg"
  for v in "<tree>"$'\t'"${tree}" "<tree>"$'\t'"${tree_l}" "<root>"$'\t'"${root}" "<run>"$'\t'"${dir}"; do printf '%d\t%s\n' "${#v}" "${v}"; done |
    LC_ALL=C sort -rn | cut -f2- > "${meta}/paths"
  shim gh "${meta}" "${FX_GH}"
  shim herdr "${meta}" "${FX_HERDR}"
  # FX_ENV goes before the settings that keep the shims in front, as env's last word for a name wins:
  # a PATH of the fixture's own goes behind the shims, and HERDR_BIN_PATH and GH_CONFIG_DIR stay ours.
  base_path="${PATH}"
  for v in ${FX_ENV[@]+"${FX_ENV[@]}"}; do [[ "${v}" != PATH=* ]] || base_path="${v#PATH=}"; done
  for v in ${PASS_ENV}; do [[ -z "${!v+x}" ]] || envs+=("${v}=${!v}"); done
  envs+=("TMPDIR=${root}/tmp" "CLAUDE_CONFIG_DIR=${root}/claude-config" "CLAUDE_PLUGIN_ROOT=${tree}" ${FX_ENV[@]+"${FX_ENV[@]}"}
    "PATH=${meta}/shims:${base_path}" "GH_CONFIG_DIR=${meta}/gh-config" "HERDR_BIN_PATH=${meta}/shims/herdr")
  snapshot "${root}" > "${meta}/before"
  # A background job starts with INT and QUIT ignored; perl puts them back, writes its pid (the group's
  # id once setpgrp runs) to meta/group, then makes the group and execs the command.
  # shellcheck disable=SC2016 # perl's own variables
  ( cd "${FX_CWD}" && exec env -i "${envs[@]}" perl -e \
      '$SIG{INT} = $SIG{QUIT} = "DEFAULT"; $g = shift; open(G, ">", $g) && print(G "$$\n") && close(G) or exit 126;
       setpgrp(0, 0) or exit 126; exec { $ARGV[0] } @ARGV or exit 127' -- "${meta}/group" "${FX_CMD[@]}" ) \
    < "${FX_STDIN}" > "${meta}/stdout" 2> "${meta}/stderr" &
  pid=$!
  watch_group "${pid}" "${meta}" & echo "$!" > "${meta}/watch.pid"
  rc=0; wait "${pid}" || rc=$?
  for ((i = 0; i < BOUND * 10; i++)); do
    left="$(pgrep -g "${pid}" || true)"; [[ -n "${left}" ]] || break; sleep 0.1
  done
  [[ ${BOUND} -gt 0 ]] || left="$(pgrep -g "${pid}" || true)"
  if [[ -n "${left}" ]]; then
    ps -o args= -p "${left//$'\n'/,}" > "${meta}/stuck" 2>/dev/null || true
    kill -KILL -- "-${pid}" 2>/dev/null || true
    for ((i = 0; i < 50; i++)); do [[ -n "$(pgrep -g "${pid}" || true)" ]] || break; sleep 0.1; done
  fi
  [[ -n "$(pgrep -g "${pid}" || true)" ]] || rm -f "${meta}/group"
  kill -TERM "$(cat "${meta}/watch.pid")" 2>/dev/null || true; wait "$(cat "${meta}/watch.pid")" 2>/dev/null || true; rm -f "${meta}/watch.pid"
  echo "${rc}" > "${meta}/exit"
  snapshot "${root}" > "${meta}/after"
  v="$(version_of "${tree}")"
  written "${meta}/before" "${meta}/after" "${tree}" "${tree_l}" "${dir}" "${v}" > "${dir}/out/files"
  for s in ${STREAMS}; do
    [[ "${s}" == files ]] || normalize "${tree}" "${tree_l}" "${dir}" "${v}" "${s}" < "${meta}/${s}" > "${dir}/out/${s}"
  done
  # Each named call is the whole of a compared line, or that line's start up to a space.
  for v in ${FX_CALLS[@]+"${FX_CALLS[@]}"}; do
    awk -v c="${v}" '$0 == c || index($0, c " ") == 1 { f = 1 } END { exit !f }' "${dir}/out/calls:fg" && continue
    echo "MISSING ${fx} (${side}): no call '${v}' in calls:fg"; missing=1
  done
  if [[ -n "${KEEP}" ]]; then mkdir -p "${KEEP}/${fx}/${side}" && cp "${dir}/out/"* "${KEEP}/${fx}/${side}/"; fi
  if [[ -s "${meta}/killed" ]]; then
    IFS=$'\t' read -r kind why < "${meta}/killed"; echo "${kind} ${fx} (${side}): ${why}"; return 3
  fi
  [[ ! -s "${meta}/stuck" ]] || {
    while IFS= read -r v; do echo "STUCK ${fx} (${side}): still running ${BOUND}s after the command exited: ${v}"; done < "${meta}/stuck"
    return 3; }
  [[ -z "${missing}" ]] || return 3
}

echo "a: ${TREE_A}"
echo "b: ${TREE_B}"
status=0
for fx in "${names[@]}"; do
  red="" broken=""
  # The two runs go side by side, each with its own root; their lines come out a's first.
  for side in a b; do run_one "${fx}" "${side}" > "${WORK}/${fx}.${side}.log" 2>&1 & echo "$!" > "${WORK}/${fx}.${side}.pid"; done
  for side in a b; do
    rc=0; wait "$(cat "${WORK}/${fx}.${side}.pid")" || rc=$?
    rm -f "${WORK}/${fx}.${side}.pid"
    cat "${WORK}/${fx}.${side}.log"
    case "${rc}" in 0) ;; 2) broken=1 ;; *) red=1 ;; esac
  done
  if [[ -n "${broken}" ]]; then status=2; continue; fi
  for s in ${STREAMS}; do
    a="${WORK}/${fx}.a/out/${s}" b="${WORK}/${fx}.b/out/${s}"
    cmp -s "${a}" "${b}" && continue
    red=1; echo "DIFF ${fx} ${s}"
    diff -u -L "a/${fx}/${s}" -L "b/${fx}/${s}" "${a}" "${b}" || true
  done
  if [[ -n "${red}" ]]; then [[ ${status} -eq 2 ]] || status=1; else echo "same ${fx}"; fi
done
exit "${status}"
