#!/usr/bin/env bash
# test.sh <file>... — make test's runner. The files not named in SERIAL run JOBS at a time under
# xargs -P; then each file in SERIAL (one whose timing does not hold up beside the others) runs on its
# own. Each file has a TMPDIR of its own, stdin from /dev/null and its output in a log: a "run" line as
# it starts, ok or FAIL with its seconds as it ends, and once a phase is over, the log of each file in
# it that failed. Exits 1 when any file failed, or when xargs stopped before every file had run (the
# jobs still running are then stopped, and waited for, before the logs go).
set -uo pipefail

# test.sh --one <run dir> <file> — one file, as above; exit 1 when it failed, never xargs's 255. The
# run dir in its command line is how the cleanup below finds it. A TERM stops its test too.
if [[ "${1:-}" == --one ]]; then
  run="$2" f="$3" t0=${SECONDS} rc=0
  log="${run}/logs/$(printf '%s' "${f}" | tr '/' '_')"
  echo "run  ${f}"
  tmp="$(mktemp -d)" || exit 1
  TMPDIR="${tmp}" bash "${f}" < /dev/null > "${log}" 2>&1 &
  pid=$!
  trap 'kill -TERM "${pid}" 2>/dev/null; wait "${pid}"; rm -rf "${tmp}"; exit 1' TERM
  wait "${pid}" || rc=$?
  rm -rf "${tmp}"
  if [[ ${rc} -eq 0 ]]; then echo "ok   ${f} $((SECONDS - t0))s"; exit 0; fi
  : > "${log}.failed"
  echo "FAIL ${f} $((SECONDS - t0))s"
  exit 1
fi

run="$(mktemp -d)" || exit 1
mkdir -p "${run}/logs"
# On any exit, stop the jobs left (only after xargs stopped early can there be any), wait for them,
# and only then remove their logs.
# shellcheck disable=SC2317,SC2329 # invoked by the EXIT trap
cleanup() {
  pkill -TERM -f -- "--one ${run} " 2>/dev/null
  while pgrep -f -- "--one ${run} " > /dev/null; do sleep 0.1; done
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
  printf '%s\n' "${par[@]}" | xargs -P "${JOBS:-4}" -n 1 bash "$0" --one "${run}"
  xrc=$?
  show "${par[@]}"
  [[ ${xrc} -eq 0 || ${xrc} -eq 123 ]] || { echo "FAIL xargs stopped (exit ${xrc}): not every file ran"; exit 1; }
fi
for f in "${ser[@]+"${ser[@]}"}"; do
  bash "$0" --one "${run}" "${f}"
  show "${f}"
done
exit "${failed}"
