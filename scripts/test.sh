#!/usr/bin/env bash
# test.sh <file>... — make test's runner. The files not named in SERIAL run JOBS at a time under
# xargs -P; then each file in SERIAL (one whose timing does not hold up beside the others) runs on its
# own. Each file has a TMPDIR of its own, stdin from /dev/null and its output in a log: a "run" line as
# it starts, ok or FAIL with its seconds as it ends, and once a phase is over, the log of each file in
# it that failed. A file passes only on its job's ok result. Under a cap in ~/.swarm/test-cap (below)
# a run may first wait for a slot. Exits 1 when any file failed, or when xargs stopped before every
# file had run, or before any file runs when the cap file holds no whole number or a slot cannot be
# used; an interrupt (INT, HUP, TERM) stops every job and its test first, as the cleanup below does.
# Under codex it refuses before anything else.
set -uo pipefail

# This suite does not run in a codex session (a codex review reads the diff; nothing codex runs
# needs it), so under codex this exits 1 with one line, before any job, "run" line or test-runs.tsv
# line. codex 0.164 sets CODEX_SANDBOX and CODEX_THREAD_ID in its own shell; the lead's shell and an
# agent's pane have neither (CODEX_HOME, which an agent may have, is no sign of codex). Either one
# refuses, in case a codex run lacks the other.
for v in CODEX_SANDBOX CODEX_THREAD_ID; do
  [[ -z "${!v+x}" ]] || { echo "test.sh: refused under codex (${v} is set): the suite does not run in a codex session; run make test outside codex" >&2; exit 1; }
done

# stop_group <pgid> <seconds> — TERM a process group, give it <seconds>, then KILL what is left.
# shellcheck disable=SC2317,SC2329 # invoked by the traps
stop_group() {
  local i
  kill -TERM -- "-$1" 2>/dev/null || return 0
  for ((i = $2 * 10; i > 0; i--)); do kill -0 -- "-$1" 2>/dev/null || return 0; sleep 0.1; done
  kill -KILL -- "-$1" 2>/dev/null || true
}

# test.sh --one <run dir> <file> — one file, as above, in a process group of its own, which is
# recorded in <run dir>/jobs while it runs; its result is <log>.ok or <log>.failed, and it exits 1
# when it failed, never xargs's 255. A TERM, INT or HUP stops the whole group: the test and whatever
# it started; so does the test's end, so nothing it left running reaches a later file. A watchdog
# stops the group the same way once the file has run TEST_FILE_TIMEOUT seconds (a whole number, default
# 600; three times that for a file in SLOW; bash 3.2 and macOS have no timeout): the job then prints
# "TIMEOUT <file> after <n>s", n being the seconds it ran, and its log is cut to the file's last 20
# lines; it also appends a "reap" line (append_event's five fields) to TEST_REAP_LOG, the events.tsv
# beside the run's test-runs.tsv, which the run sets for its jobs and --one unsets before the test runs.
# Its outcome ends in append_event's tail after EVENT_SEP: slug=<slug> role=builder when the run's branch
# (TEST_REAP_BRANCH, unset the same way) is story/<slug>, none on any other branch, then version=, the
# version in this checkout's .claude-plugin/plugin.json (TEST_REAP_VERSION, read once by the run and
# unset the same way), left out when that cannot be read.
# SWARM_SLEEP_SCALE defaults to 0.01 here as in the Makefile, so a direct run is as fast. The test does
# not see make's JOBS, SERIAL, SLOW or TESTS (make exports a command-line variable to every recipe),
# nor SHARD, nor HERDR_SOCKET_PATH: run from a herdr pane, a wait would ask the real herdr about a
# test's made-up panes. Nor any SWARM_* but SWARM_SLEEP_SCALE: a builder's pane carries every SWARM_*
# the lead exported, SWARM_PROJECT and SWARM_AGENT among them, which name its real project. And
# SWARM_NO_CI_REFRESH is set, so a dash test starts no detached ci refresh, which outlives the test
# and runs flow, and gh, on a project. The file runs from its TMPDIR, outside any git repo, with
# SWARM_PROJECT naming a stand-in project of the job's own, as a pane's names the lead's real one:
# tests/test_helpers.sh, which every test sources first, drops it, and a file whose swarm.sh still
# reaches the stand-in fails, naming what it left there; a call a test leaves unpinned (no cd into
# its project, no SWARM_PROJECT) stops at "not in a swarm project" instead of reaching this
# checkout's .swarm, and one that names this checkout, or a worktree of it, stops too: SWARM_FORBID_PROJECT
# names it and swarm.sh refuses it (tests/live_logs_test.sh); the hooks that write event lines skip it
# themselves. MAKEFLAGS, MFLAGS and MAKELEVEL are unset too, so a
# make a test runs starts clean, whatever make test was given (SHARD, TESTS).
for v in $(compgen -e); do case ${v} in SWARM_SLEEP_SCALE) ;; SWARM_*) unset "${v}" ;; esac; done
export SWARM_SLEEP_SCALE="${SWARM_SLEEP_SCALE:-0.01}" SWARM_NO_CI_REFRESH=1
limit="${TEST_FILE_TIMEOUT:-600}"
if [[ "${1:-}" == --one ]]; then
  run="$2" f="$3" t0=${SECONDS} rc=0 pid="" wd="" fields=() x="" reap_log="" reap_tail=""
  case " ${SLOW:-} " in *" ${f} "*) limit=$((limit * 3)) ;; esac   # the files that take minutes alone
  reap_log="${TEST_REAP_LOG:-}"   # the run's events.tsv, or empty; the test never sees it
  # A story branch's slug, in a value append_event would keep: not empty, no space or tab.
  x="${TEST_REAP_BRANCH:-}"
  if [[ "${x}" == story/?* && "${x#story/}" =~ ^[^[:space:]]+$ ]]; then reap_tail="slug=${x#story/} role=builder"; fi
  x="${TEST_REAP_VERSION:-}"   # the checkout's version, kept only as a value append_event would keep
  if [[ "${x}" =~ ^[^[:space:]]+$ ]]; then reap_tail+="${reap_tail:+ }version=${x}"; fi
  unset TEST_FILE_TIMEOUT TEST_REAP_LOG TEST_REAP_BRANCH TEST_REAP_VERSION JOBS SERIAL SLOW TESTS SHARD HERDR_SOCKET_PATH MAKEFLAGS MFLAGS MAKELEVEL
  # The checkout this runner belongs to (its main checkout, from a worktree), found from this script, not
  # the cwd (a test runs test.sh from its TMPDIR): swarm.sh refuses to act on it.
  if forbid="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then SWARM_FORBID_PROJECT="$(dirname "${forbid}")"; export SWARM_FORBID_PROJECT; fi
  log="${run}/logs/$(printf '%s' "${f}" | tr '/' '_')"
  trap '[[ -z "${wd}" ]] || kill "${wd}" 2>/dev/null; [[ -z "${pid}" ]] || stop_group "${pid}" 2; rm -rf "${tmp:-}" "${run}/jobs/$$"; exit 1' TERM INT HUP
  : > "${run}/jobs/$$"   # first, so the cleanup can find this job before its test starts
  echo "run  ${f}"
  # Inside the run dir, so it goes with it even if this job is KILLed.
  tmp="$(mktemp -d "${run}/tmp.XXXXXX")" || exit 1
  case "${f}" in /*) abs="${f}" ;; *) abs="${PWD}/${f}" ;; esac   # the file, from the TMPDIR it runs in
  pane="${tmp}/pane"; mkdir -p "${pane}/.claude/swarm" && : > "${pane}/.claude/swarm/config"   # the pane's SWARM_PROJECT
  set -m   # the job below leads a process group of its own
  (cd "${tmp}" && TMPDIR="${tmp}" SWARM_PROJECT="${pane}" exec bash "${abs}") < /dev/null > "${log}" 2>&1 &
  pid=$!
  set +m
  echo "${pid}" > "${run}/jobs/$$"
  # The watchdog sleeps the limit; it signals and writes the marker only if this job (a KILLed job
  # would leave a PGID that may be reused) and the group are still there then.
  (
    sp=""
    trap '[[ -z "${sp}" ]] || kill "${sp}" 2>/dev/null; exit 0' TERM
    sleep "${limit}" & sp=$!
    wait "${sp}"; sp=""
    kill -0 "$$" 2>/dev/null && kill -0 -- "-${pid}" 2>/dev/null || exit 0
    : > "${log}.timeout"
    stop_group "${pid}" 2
  ) > /dev/null 2>&1 &
  wd=$!
  wait "${pid}" || rc=$?
  elapsed=$((SECONDS - t0))
  kill "${wd}" 2>/dev/null; wait "${wd}" 2>/dev/null; wd=""   # reaped, so no later kill can hit a recycled PID
  stop_group "${pid}" 2
  # What the test left in the pane's project: anything but the config it started with.
  reached="$(cd "${pane}" && find . -mindepth 1 ! -path ./.claude ! -path ./.claude/swarm ! -path ./.claude/swarm/config 2>/dev/null | LC_ALL=C sort)"
  rm -rf "${tmp}" "${run}/jobs/$$"
  if [[ -e "${log}.timeout" ]]; then
    : > "${log}.failed"
    { echo "TIMEOUT ${f} after ${elapsed}s (last 20 lines)"; tail -n 20 "${log}"; } > "${log}.tail"; mv "${log}.tail" "${log}"
    echo "TIMEOUT ${f} after ${elapsed}s"
    # A reap line, in append_event's five fields, the tail after its EVENT_SEP (" ~~ "); a log that
    # cannot be written is skipped.
    if [[ -n "${reap_log}" ]]; then
      for x in "$(date -u +%Y-%m-%dT%H:%M:%SZ)" reap "${f}" "${HERDR_PANE_ID:--}" "TIMEOUT after ${elapsed}s${reap_tail:+ ~~ ${reap_tail}}"; do fields+=("${x//[$'\t\n\r']/ }"); done
      { mkdir -p "${reap_log%/*}" && printf '%s\t%s\t%s\t%s\t%s\n' "${fields[@]}" >> "${reap_log}"; } 2>/dev/null || true
    fi
    exit 1
  fi
  if [[ -n "${reached}" ]]; then
    printf "FAIL %s ran swarm.sh against the pane's SWARM_PROJECT (source tests/test_helpers.sh first); it left:\n%s\n" "${f}" "${reached}" >> "${log}"
    rc=1
  fi
  if [[ ${rc} -eq 0 ]]; then : > "${log}.ok"; echo "ok   ${f} ${elapsed}s"; exit 0; fi
  : > "${log}.failed"
  echo "FAIL ${f} ${elapsed}s"
  exit 1
fi

# Every run takes the files in one order: sorted (LC_ALL=C, whatever the shell's glob order), the
# SLOW ones first, then the SERIAL ones, then the rest, so the slowest start first. SHARD=i/N keeps
# the files whose place in that order, counted from 0, is i-1 mod N, so N runs over the same list, i
# from 1 to N, run each file once (CI's test-shard jobs), and while SLOW and SERIAL hold no more than
# N files, each of them lands on a shard of its own. It says how many files it kept, and fails when
# it keeps none. test.sh --list <file>... prints the files it would run, in order, and stops.
list=""
[[ "${1:-}" != --list ]] || { list=1; shift; }
# rank <file>... — each file after its rank: 0 for SLOW, 1 for SERIAL, 2 for the rest.
rank() {
  local f
  for f in "$@"; do
    case " ${SLOW:-} " in *" ${f} "*) printf '0\t%s\n' "${f}"; continue ;; esac
    case " ${SERIAL:-} " in *" ${f} "*) printf '1\t%s\n' "${f}"; continue ;; esac
    printf '2\t%s\n' "${f}"
  done
}
files=()
while IFS=$'\t' read -r _ f; do files+=("${f}"); done < <(rank "$@" | LC_ALL=C sort)
set -- "${files[@]+"${files[@]}"}"
if [[ -n "${SHARD:-}" ]]; then
  if ! [[ "${SHARD}" =~ ^([1-9][0-9]*)/([1-9][0-9]*)$ ]] || ((BASH_REMATCH[1] > BASH_REMATCH[2])); then
    echo "test.sh: SHARD=${SHARD} is not i/N with 1 <= i <= N" >&2
    exit 1
  fi
  i=$((BASH_REMATCH[1] - 1)) n=${BASH_REMATCH[2]} k=0 kept=()
  for f in "$@"; do
    ((k++ % n == i)) && kept+=("${f}")
  done
  echo "shard ${SHARD}: ${#kept[@]} of $# files" >&2
  [[ ${#kept[@]} -gt 0 ]] || { echo "test.sh: shard ${SHARD} keeps no file" >&2; exit 1; }
  set -- "${kept[@]}"
fi
if [[ -n "${list}" ]]; then
  [[ $# -eq 0 ]] || printf '%s\n' "$@"
  exit 0
fi
if ! [[ "${limit}" =~ ^[1-9][0-9]*$ ]]; then
  echo "test.sh: TEST_FILE_TIMEOUT=${limit} is not a whole number of seconds, 1 or more" >&2
  exit 1
fi

# Each run appends a line to the main checkout's .swarm/test-runs.tsv (found through git's common
# dir, never SWARM_PROJECT, which is unset above) as it starts and as it ends, for flow's test_runs:
# start and end (UTC), seconds, JOBS, the filter, branch, the 1-minute load and CPUs, the other runs
# going, each line as of its own moment, the exit status and the run's PID; the start line leaves
# end, seconds and status empty. The filter is all when the files are every tests/*_test.sh, else TESTS, else how many
# files; then ` shard i/N` for a SHARD. A run going is a file named by its PID in test-runs.d beside
# the log, there from its start to its end; one whose PID has gone is stale, and removed. TEST_RUNS_LOG,
# when set, is the file instead, and set empty for the jobs, so a run a test starts itself logs
# nothing and is no run going. A write that fails is skipped.
runs_log="${TEST_RUNS_LOG-}"
if [[ -z "${TEST_RUNS_LOG+x}" ]] && common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
  runs_log="$(dirname "${common}")/.swarm/test-runs.tsv"
fi
export TEST_RUNS_LOG=""
# The jobs' reap log: the events.tsv beside the runs log, or empty for a nested run.
export TEST_REAP_LOG=""
[[ -z "${runs_log}" ]] || TEST_REAP_LOG="$(dirname "${runs_log}")/events.tsv"
# The reap lines' version=: this checkout's plugin.json version, read once here; empty when it cannot be read.
export TEST_REAP_VERSION=""
[[ -z "${TEST_REAP_LOG}" ]] || TEST_REAP_VERSION="$(python3 -c 'import json, sys
v = json.load(open(sys.argv[1], encoding="utf-8")).get("version")
print(v if isinstance(v, str) else "")' "$(dirname "${BASH_SOURCE[0]}")/../.claude-plugin/plugin.json" 2>/dev/null)" || TEST_REAP_VERSION=""
# ps_words <pid> <field>... — ps's fields for that process, one space between words, the same
# whatever the caller's TZ; started <pid> — when it started.
ps_words() {
  local p="$1" f
  local -a w
  shift
  f="$(IFS=,; echo "$*")"
  read -r -a w <<< "$(TZ=UTC LC_ALL=C ps -ww -o "${f}" -p "${p}" 2>/dev/null)"
  echo "${w[*]+"${w[*]}"}"
}
started() { ps_words "$1" lstart=; }
# A nested run, one a test started: TEST_SH_RUN, which each run exports for its jobs as its PID and
# start time, names a run still going: alive, no zombie, and started then, so neither a gone run nor
# its PID taken since makes a run nested.
nested="" me="$(started $$)"
if [[ "${TEST_SH_RUN:-}" == [0-9]*" "* ]]; then
  outer="$(ps_words "${TEST_SH_RUN%% *}" stat= lstart=)"
  [[ -n "${outer}" && "${outer}" != Z* && "${outer#* }" == "${TEST_SH_RUN#* }" ]] && nested=1
fi
export TEST_SH_RUN="$$ ${me}"
marks="$(dirname "${runs_log:-.}")/test-runs.d"
if [[ "$(printf '%s\n' "${files[@]+"${files[@]}"}" | LC_ALL=C sort)" == "$(printf '%s\n' tests/*_test.sh | LC_ALL=C sort)" ]]; then
  filter=all
else
  filter="${TESTS:-${#files[@]} files}"
fi
filter="${filter//$'\t'/ }${SHARD:+ shard ${SHARD}}"
branch="$(git symbolic-ref --short -q HEAD 2>/dev/null || echo -)"
export TEST_REAP_BRANCH="${branch}"   # for the jobs' reap lines
trap 'exit 130' INT
trap 'exit 129' HUP
trap 'exit 143' TERM

# The cap: ~/.swarm/test-cap, a whole number N above 0, lets at most N runs go at once on this
# machine, whatever their project; absent, empty or 0, there is no cap and nothing is made under
# ~/.swarm, and anything else, or a cap file it cannot read, stops the run. A run takes one of the
# slots ~/.swarm/test-slots/1 to N: a directory holding one file, named by the run's PID and holding
# the run's start time, built aside as .new.<pid> and renamed into place. The rename fails while the
# slot holds anything, so no two runs hold one slot and no slot is ever seen without its PID. A slot
# is held while its PID is alive and started then; a PID that has gone (or is a zombie), or that
# another process has taken since, holds nothing, and what such a slot holds (hidden files too) is removed by name, so a
# run that looked late never removes a slot another run took since. Only then does a run start perl
# for the rename. While every slot is held the run waits, polling, and names the holders and their
# slots whenever they change. The wait has no time limit: a holder that is stopped (Ctrl-Z) or hung
# keeps its slot until it ends or someone removes the slot by hand (rm -r <slot>, the path the
# message names). A slot that is no directory this run can read and write, or that it cannot clear,
# stops the run; so does a take with no perl to run, or no ps to read start times with. A take that keeps failing with a slot free says
# once what fails, then keeps trying. A nested run takes no slot: a test that runs make test would
# wait on the run it is part of. cleanup frees the slot.
cap_file="${HOME:-}/.swarm/test-cap" slots="${HOME:-}/.swarm/test-slots" cap="" held=0 holders=""
CAP_POLL=1   # seconds between looks at the slots while every one is held
CAP_STUCK=5  # passes in a row that fail with a slot free before the run says what fails
# free_slot — remove this run's PID from whatever slot holds it, and the slot it built aside.
# shellcheck disable=SC2317,SC2329 # invoked by the traps
free_slot() {
  local f
  [[ "${cap:-0}" -gt 0 ]] || return 0
  for f in "${slots}"/*/"$$"; do
    [[ -e "${f}" ]] && rm -f "${f}" && rmdir "${f%/*}" 2>/dev/null
  done
  rm -rf "${slots}/.new.$$"
}
# holder <entry> — 0 when a slot entry names the run that holds the slot: a file named by a live PID
# (not this run's: it holds no slot yet) and holding that process's start time, as the run wrote it
# when it took the slot. A PID another process has taken since started later, and holds nothing; nor
# does a run that has died and not been reaped (a zombie, state Z). A live PID whose start time this
# run cannot read, from the file or from ps, still holds, so a failed read never frees a slot; once
# that PID is gone, kill -0 frees it.
holder() {
  local p="${1##*/}" want now
  [[ "${p}" =~ ^[0-9]+$ && "${p}" != "$$" && -f "$1" ]] && kill -0 "${p}" 2>/dev/null || return 1
  if ! want="$(cat "$1" 2>/dev/null)" || [[ -z "${want}" ]]; then return 0; fi
  now="$(ps_words "${p}" stat= lstart=)"
  [[ -n "${now}" ]] || return 0
  [[ "${now}" != Z* && "${now#* }" == "${want}" ]]
}
# take_slot — move this run's slot, built aside, into the first slot no live run holds, once what a
# gone run left there is removed; else fail, held and holders saying how many runs hold the slots,
# and which, and failed the last slot it could not take and why.
take_slot() {
  local i s e live new="${slots}/.new.$$"
  local -a gone
  held=0 holders="" failed=""
  for ((i = 1; i <= cap; i++)); do
    s="${slots}/${i}"
    if [[ -L "${s}" ]] || [[ -e "${s}" && ! ( -d "${s}" && -r "${s}" && -w "${s}" && -x "${s}" ) ]]; then
      echo "test.sh: ${s} is no slot this run can use (a directory it can read and write); remove it by hand: rm -r '${s}'" >&2
      exit 1
    fi
    live="" gone=()
    for e in "${s}"/* "${s}"/.[!.]* "${s}"/..?*; do
      [[ -e "${e}" || -L "${e}" ]] || continue
      if holder "${e}"; then live="${e##*/}"; break; fi
      gone+=("${e}")
    done
    if [[ -n "${live}" ]]; then held=$((held + 1)) holders+="${holders:+, }PID ${live} holds ${s}"; continue; fi
    [[ ${#gone[@]} -eq 0 ]] || rm -rf "${gone[@]}" 2>/dev/null || {
      echo "test.sh: cannot clear ${s} of what a gone run left there; remove it by hand: rm -r '${s}'" >&2
      exit 1
    }
    rename_dir "${new}" "${s}" && return 0
    (($? != 127)) || { echo "test.sh: the cap needs perl to take a slot: ${take_err}" >&2; exit 1; }
    failed="${s}: ${take_err:-the rename failed}"
  done
  return 1
}
# rename_dir <dir> <slot> — rename(2), which takes <slot>'s place only while it is gone or empty
# (mv would move <dir> into a <slot> that is there); take_err holds what failed, if it did.
rename_dir() { take_err="$(perl -e 'rename($ARGV[0], $ARGV[1]) or die "$!\n"' "$1" "$2" 2>&1)"; }
if [[ -z "${nested}" && -n "${HOME:-}" ]] && [[ -e "${cap_file}" || -L "${cap_file}" ]]; then
  if ! [[ -f "${cap_file}" && -r "${cap_file}" ]] || ! cap="$(cat "${cap_file}" 2>/dev/null)"; then
    echo "test.sh: cannot read ${cap_file}, which must be a file holding a whole number of runs; fix it or remove it" >&2
    exit 1
  fi
fi
# A number past bash's integers wraps, so it must come back from arithmetic as written.
if ! [[ "${cap}" =~ ^(0|[1-9][0-9]*)?$ ]] || [[ -n "${cap}" && "$((cap))" != "${cap}" ]]; then
  echo "test.sh: ${cap_file} holds '${cap}', not a whole number of runs (0 or empty for no cap); fix it or remove it" >&2
  exit 1
fi
if [[ "${cap:-0}" -gt 0 ]]; then
  trap free_slot EXIT
  # A run killed while it waited left its .new.<pid>.
  for e in "${slots}"/.new.*; do
    p="${e##*/.new.}"
    [[ -e "${e}" && "${p}" != "$$" ]] && ! kill -0 "${p}" 2>/dev/null && rm -rf "${e}"
  done
  [[ -n "${me}" ]] || { echo "test.sh: the cap needs ps to tell runs apart, and ps gave no start time for this run" >&2; exit 1; }
  mkdir -p "${slots}/.new.$$" && echo "${me}" > "${slots}/.new.$$/$$" || exit 1
  # A pass that fails with fewer than cap slots held most often lost a race to a run taking or
  # freeing one, and the next pass looks again. CAP_STUCK of them in a row are more likely a slot that
  # will not take: the run says once what fails, and keeps trying, as a race is still possible.
  said="" short=0
  until take_slot; do
    if ((held == cap)); then
      short=0
      [[ "${holders}" == "${said}" ]] || echo "test.sh: waiting for a slot, as ${cap_file} allows ${cap} run(s) at once: ${holders}. A slot frees when its run ends; the wait has no time limit, so to free one by hand, rm -r it." >&2
      said="${holders}"
    elif ((++short == CAP_STUCK)); then
      echo "test.sh: cannot take a slot though live runs hold only ${held} of ${cap}: ${failed}. Still trying; if it does not clear, remove that slot by hand: rm -r it." >&2
    fi
    sleep "${CAP_POLL}"
  done
fi

t_start=${SECONDS} t_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# others — how many other runs are going: live marks but this run's.
others() {
  local m n=0
  for m in "${marks}"/*; do
    [[ -e "${m}" && "${m##*/}" != "$$" ]] || continue
    if kill -0 "${m##*/}" 2>/dev/null; then n=$((n + 1)); else rm -f "${m}"; fi
  done
  echo "${n}"
}
# log_run <end> <seconds> <status> — append this run's line, as of now, or nothing when it cannot.
log_run() {
  [[ -n "${runs_log}" ]] || return 0
  { mkdir -p "${marks}" && printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${t_iso}" "$1" "$2" "${JOBS:-4}" "${filter}" "${branch}" \
    "$(LC_ALL=C uptime | sed -nE 's/.*load averages?: *([0-9.]+).*/\1/p')" "$(getconf _NPROCESSORS_ONLN)" "$(others)" "$3" "$$" >> "${runs_log}"; } 2>/dev/null || true
}
[[ -z "${runs_log}" ]] || { mkdir -p "${marks}" && : > "${marks}/$$"; } 2>/dev/null
log_run "" "" ""

run="$(mktemp -d)" || exit 1
mkdir -p "${run}/logs" "${run}/jobs"
# On any exit, stop the jobs left (only after xargs stopped early, or an interrupt, can there be
# any): TERM each, which stops its test's group, and give them 5 s; then TERM the group of any still
# there, and KILL it 2 s later, and the job. Only then do the logs go, and last the slot.
# shellcheck disable=SC2317,SC2329 # invoked by the EXIT trap
cleanup() {
  local rc=$? j i g left
  for j in "${run}"/jobs/*; do [[ -e "${j}" ]] && kill -TERM "${j##*/}" 2>/dev/null; done
  for ((i = 50; i > 0; i--)); do
    left=""
    for j in "${run}"/jobs/*; do [[ -e "${j}" ]] && kill -0 "${j##*/}" 2>/dev/null && left=1; done
    [[ -n "${left}" ]] || break
    sleep 0.1
  done
  for j in "${run}"/jobs/*; do
    [[ -e "${j}" ]] || continue
    g="$(cat "${j}" 2>/dev/null)"; [[ -z "${g}" ]] || stop_group "${g}" 2
    kill -KILL "${j##*/}" 2>/dev/null
  done
  rm -rf "${run}"
  log_run "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$((SECONDS - t_start))" "${rc}"
  [[ -z "${runs_log}" ]] || rm -f "${marks}/$$"
  free_slot
}
trap cleanup EXIT

failed=0
# show <file>... — after a phase: each failed file's log, whole, and any file whose job ended with no
# result (it stopped before its test could pass).
show() {
  local f log
  for f in "$@"; do
    log="${run}/logs/$(printf '%s' "${f}" | tr '/' '_')"
    [[ ! -e "${log}.ok" ]] || continue
    failed=1
    if [[ -e "${log}.failed" ]]; then echo "---- ${f}"; cat "${log}"; else echo "FAIL ${f}: its job ended without a result"; fi
  done
}

par=() ser=()
for f in "$@"; do
  case " ${SERIAL:-} " in *" ${f} "*) ser+=("${f}") ;; *) par+=("${f}") ;; esac
done
if [[ ${#par[@]} -gt 0 ]]; then
  printf '%s\0' "${par[@]}" | xargs -0 -P "${JOBS:-4}" -n 1 bash "$0" --one "${run}"
  xrc=$?
  show "${par[@]}"
  # Every file ran on 0, on 123 (GNU xargs: a command failed) and on 1 (BSD xargs: the same); 124
  # to 127, or a signal, stopped it early.
  case ${xrc} in
    0|1|123) ;;
    *) echo "FAIL xargs stopped (exit ${xrc}): not every file ran"; exit 1 ;;
  esac
fi
for f in "${ser[@]+"${ser[@]}"}"; do
  bash "$0" --one "${run}" "${f}"
  show "${f}"
done
exit "${failed}"
