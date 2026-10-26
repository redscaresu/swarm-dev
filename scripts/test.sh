#!/usr/bin/env bash
# test.sh <file>... — make test's runner. The files not named in SERIAL run JOBS at a time under
# xargs -P; then each file in SERIAL (one whose timing does not hold up beside the others) runs on its
# own. Each file has a TMPDIR of its own, stdin from /dev/null and its output in a log: a "run" line as
# it starts, ok or FAIL with its seconds as it ends, and once a phase is over, the log of each file in
# it that failed. A file passes only on its job's ok result. Exits 1 when any file failed, or when
# xargs stopped before every file had run; an interrupt (INT, HUP, TERM) stops every job and its test
# first, as the cleanup below does. Under codex it refuses before anything else.
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
# lines. SWARM_SLEEP_SCALE defaults to 0.01 here as in the Makefile, so a direct run is as fast. The test does
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
# checkout's .swarm, and one that names this checkout (a cd into it, SWARM_PROJECT) stops too:
# SWARM_FORBID_PROJECT names it and swarm.sh refuses it (tests/live_logs_test.sh). MAKEFLAGS, MFLAGS and MAKELEVEL are unset too, so a
# make a test runs starts clean, whatever make test was given (SHARD, TESTS).
for v in $(compgen -e); do case ${v} in SWARM_SLEEP_SCALE) ;; SWARM_*) unset "${v}" ;; esac; done
export SWARM_SLEEP_SCALE="${SWARM_SLEEP_SCALE:-0.01}" SWARM_NO_CI_REFRESH=1
limit="${TEST_FILE_TIMEOUT:-600}"
if [[ "${1:-}" == --one ]]; then
  run="$2" f="$3" t0=${SECONDS} rc=0 pid="" wd=""
  case " ${SLOW:-} " in *" ${f} "*) limit=$((limit * 3)) ;; esac   # the files that take minutes alone
  unset TEST_FILE_TIMEOUT JOBS SERIAL SLOW TESTS SHARD HERDR_SOCKET_PATH MAKEFLAGS MFLAGS MAKELEVEL
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
marks="$(dirname "${runs_log:-.}")/test-runs.d"
if [[ "$(printf '%s\n' "${files[@]+"${files[@]}"}" | LC_ALL=C sort)" == "$(printf '%s\n' tests/*_test.sh | LC_ALL=C sort)" ]]; then
  filter=all
else
  filter="${TESTS:-${#files[@]} files}"
fi
filter="${filter//$'\t'/ }${SHARD:+ shard ${SHARD}}"
branch="$(git symbolic-ref --short -q HEAD 2>/dev/null || echo -)"
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
# there, and KILL it 2 s later, and the job. Only then do the logs go.
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
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 129' HUP
trap 'exit 143' TERM

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
