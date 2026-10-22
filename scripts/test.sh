#!/usr/bin/env bash
# test.sh <file>... — make test's runner. The files not named in SERIAL run JOBS at a time under
# xargs -P; then each file in SERIAL (one whose timing does not hold up beside the others) runs on its
# own. Each file has a TMPDIR of its own, stdin from /dev/null and its output in a log: a "run" line as
# it starts, ok or FAIL with its seconds as it ends, and once a phase is over, the log of each file in
# it that failed. A file passes only on its job's ok result. Exits 1 when any file failed, or when
# xargs stopped before every file had run; an interrupt (INT, HUP, TERM) stops every job and its test
# first, as the cleanup below does.
set -uo pipefail

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
# it started; so does the test's end, so nothing it left running reaches a later file. The test does
# not see make's JOBS, SERIAL or TESTS (make exports a command-line variable to every recipe), nor
# HERDR_SOCKET_PATH: run from a herdr pane, a wait would ask the real herdr about a test's made-up panes.
if [[ "${1:-}" == --one ]]; then
  unset JOBS SERIAL TESTS SHARD HERDR_SOCKET_PATH
  run="$2" f="$3" t0=${SECONDS} rc=0 pid=""
  log="${run}/logs/$(printf '%s' "${f}" | tr '/' '_')"
  trap '[[ -z "${pid}" ]] || stop_group "${pid}" 2; rm -rf "${tmp:-}" "${run}/jobs/$$"; exit 1' TERM INT HUP
  : > "${run}/jobs/$$"   # first, so the cleanup can find this job before its test starts
  echo "run  ${f}"
  # Inside the run dir, so it goes with it even if this job is KILLed.
  tmp="$(mktemp -d "${run}/tmp.XXXXXX")" || exit 1
  set -m   # the job below leads a process group of its own
  TMPDIR="${tmp}" bash "${f}" < /dev/null > "${log}" 2>&1 &
  pid=$!
  set +m
  echo "${pid}" > "${run}/jobs/$$"
  wait "${pid}" || rc=$?
  stop_group "${pid}" 2
  rm -rf "${tmp}" "${run}/jobs/$$"
  if [[ ${rc} -eq 0 ]]; then : > "${log}.ok"; echo "ok   ${f} $((SECONDS - t0))s"; exit 0; fi
  : > "${log}.failed"
  echo "FAIL ${f} $((SECONDS - t0))s"
  exit 1
fi

# SHARD=i/N keeps only the files whose place in the list, counted from 0, is i-1 mod N, so N runs
# over the same list, i from 1 to N, run each file once (CI's test-shard jobs). test.sh --list
# <file>... prints the files it would run and stops.
list=""
[[ "${1:-}" != --list ]] || { list=1; shift; }
if [[ -n "${SHARD:-}" ]]; then
  if ! [[ "${SHARD}" =~ ^([1-9][0-9]*)/([1-9][0-9]*)$ ]] || ((BASH_REMATCH[1] > BASH_REMATCH[2])); then
    echo "test.sh: SHARD=${SHARD} is not i/N with 1 <= i <= N" >&2
    exit 1
  fi
  i=$((BASH_REMATCH[1] - 1)) n=${BASH_REMATCH[2]} k=0 kept=()
  for f in "$@"; do
    ((k++ % n == i)) && kept+=("${f}")
  done
  set -- "${kept[@]+"${kept[@]}"}"
fi
if [[ -n "${list}" ]]; then
  [[ $# -eq 0 ]] || printf '%s\n' "$@"
  exit 0
fi

run="$(mktemp -d)" || exit 1
mkdir -p "${run}/logs" "${run}/jobs"
# On any exit, stop the jobs left (only after xargs stopped early, or an interrupt, can there be
# any): TERM each, which stops its test's group, and give them 5 s; then TERM the group of any still
# there, and KILL it 2 s later, and the job. Only then do the logs go.
# shellcheck disable=SC2317,SC2329 # invoked by the EXIT trap
cleanup() {
  local j i g left
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
