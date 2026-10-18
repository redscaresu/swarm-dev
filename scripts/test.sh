#!/usr/bin/env bash
# test.sh <file>... — make test's runner. The files not named in SERIAL run JOBS at a time under
# xargs -P; then each file in SERIAL (one whose timing does not hold up beside the others) runs on its
# own. Each file has a TMPDIR of its own, stdin from /dev/null and its output in a log: a "run" line as
# it starts, ok or FAIL with its seconds as it ends, and once a phase is over, the log of each file in
# it that failed. Exits 1 when any file failed, or when xargs stopped before every file had run (the
# jobs still running are then stopped, and waited for, before the logs go).
set -uo pipefail

# stop_group <pgid> <seconds> — TERM a process group, give it <seconds>, then KILL what is left.
# shellcheck disable=SC2317,SC2329 # invoked by --one's TERM trap
stop_group() {
  local i
  kill -TERM -- "-$1" 2>/dev/null || return 0
  for ((i = $2 * 10; i > 0; i--)); do kill -0 -- "-$1" 2>/dev/null || return 0; sleep 0.1; done
  kill -KILL -- "-$1" 2>/dev/null || true
}

# test.sh --one <run dir> <file> — one file, as above, in a process group of its own, which is
# recorded in <run dir>/jobs while it runs; exit 1 when it failed, never xargs's 255. A TERM stops
# the whole group: the test and whatever it started.
if [[ "${1:-}" == --one ]]; then
  run="$2" f="$3" t0=${SECONDS} rc=0 pid=""
  log="${run}/logs/$(printf '%s' "${f}" | tr '/' '_')"
  tmp="$(mktemp -d)" || exit 1
  trap '[[ -z "${pid}" ]] || stop_group "${pid}" 2; rm -rf "${tmp}" "${run}/jobs/$$"; exit 1' TERM
  echo "run  ${f}"
  : > "${run}/jobs/$$"   # first, so the cleanup can find this job before its test starts
  set -m   # the job below leads a process group of its own
  TMPDIR="${tmp}" bash "${f}" < /dev/null > "${log}" 2>&1 &
  pid=$!
  set +m
  echo "${pid}" > "${run}/jobs/$$"
  wait "${pid}" || rc=$?
  rm -rf "${tmp}" "${run}/jobs/$$"
  if [[ ${rc} -eq 0 ]]; then echo "ok   ${f} $((SECONDS - t0))s"; exit 0; fi
  : > "${log}.failed"
  echo "FAIL ${f} $((SECONDS - t0))s"
  exit 1
fi

run="$(mktemp -d)" || exit 1
mkdir -p "${run}/logs" "${run}/jobs"
# On any exit, stop the jobs left (only after xargs stopped early can there be any): TERM each, which
# stops its test's group, give them 5 s, then KILL each and its group. Only then do the logs go.
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
    kill -KILL "${j##*/}" 2>/dev/null
    g="$(cat "${j}" 2>/dev/null)"; [[ -z "${g}" ]] || kill -KILL -- "-${g}" 2>/dev/null
  done
  rm -rf "${run}"
}
trap cleanup EXIT

failed=0
# show <file>... — each failed file's log, whole, after its phase.
show() {
  local f log
  for f in "$@"; do
    log="${run}/logs/$(printf '%s' "${f}" | tr '/' '_')"
    [[ -e "${log}.failed" ]] || continue
    echo "---- ${f}"; cat "${log}"; failed=1
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
  [[ ${xrc} -eq 0 || ${xrc} -eq 123 ]] || { echo "FAIL xargs stopped (exit ${xrc}): not every file ran"; exit 1; }
fi
for f in "${ser[@]+"${ser[@]}"}"; do
  bash "$0" --one "${run}" "${f}"
  show "${f}"
done
exit "${failed}"
