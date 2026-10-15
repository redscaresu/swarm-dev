#!/usr/bin/env bash
# codex_test.sh — swarm.sh codex-review <base>: codex's review against origin/<base>, with no prompt
# and stdin from /dev/null, its output and exit passed through. One that runs past the limit
# (SWARM_CODEX_SECONDS here) is stopped, TERM then KILL, leaving nothing of it running, and the
# command dies with "codex skipped: timed out", which events.tsv records. codex is a stub on PATH.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
# BIN is in every stub process's command line and in no other's: the marker pgrep -f looks for.
BIN="${ROOT}/bin"; P="${ROOT}/proj"; LIMIT=2; GRACE=3
trap 'pkill -KILL -f "${BIN}/" 2>/dev/null || true; rm -rf "${ROOT}"' EXIT
mkdir -p "${BIN}" "${P}/.claude/swarm"; : > "${P}/.claude/swarm/config"
ln -s "$(command -v sleep)" "${BIN}/stubsleep"   # the stub's child, named so pgrep -f can tell it
export PATH="${BIN}:${PATH}"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }

# stub <body> — the codex on PATH: it records its args and its stdin, then runs <body>.
# shellcheck disable=SC2016 # the stub's own variables, expanded when it runs
stub() {
  printf '%s\n' '#!/usr/bin/env bash' 'd="$(dirname "$0")"' 'printf "[%s]" "$@" > "${d}/args"' 'cat > "${d}/stdin"' "$1" > "${BIN}/codex"
  chmod +x "${BIN}/codex"
}
# review — codex-review main from the project, with text on its stdin, timed: sets out, rc and took
# (seconds). Its output goes through a file, since a stub left running would hold a $(...) open for
# good, and after REVIEW_CAP seconds the stubs are KILLed, so a codex-review that hangs fails the
# timing checks instead of hanging the test.
REVIEW_CAP=20
review() {
  local t0=${SECONDS} spid i
  (cd "${P}" && exec env -u SWARM_PROJECT -u HERDR_ENV SWARM_CODEX_SECONDS=${LIMIT} bash "${SWARM}" codex-review main \
    <<< "typed at the prompt" > "${ROOT}/out" 2>&1) &
  spid=$!
  for ((i = 0; i < REVIEW_CAP * 5; i++)); do kill -0 "${spid}" 2>/dev/null || break; sleep 0.2; done
  kill -0 "${spid}" 2>/dev/null && { pkill -KILL -f "${BIN}/" || true; }
  rc=0; wait "${spid}" || rc=$?
  took=$((SECONDS - t0)); out="$(cat "${ROOT}/out")"
}
# gone [seconds] — "yes" once no stub process is left, polled for up to <seconds> (2).
gone() {
  local i
  for ((i = 0; i < ${1:-2} * 5; i++)); do pgrep -f "${BIN}/" >/dev/null || { echo yes; return; }; sleep 0.2; done
  echo "no: $(pgrep -fl "${BIN}/" | tr '\n' ' ')"
}
last_event() { awk -F'\t' '$2 == "codex-review" { o = $3 "|" $5 } END { print o }' "${P}/.swarm/events.tsv"; }

# --- A codex that sleeps past the limit is stopped, with its child, and named.
# shellcheck disable=SC2016 # the stub's variable
stub '"${d}/stubsleep" 60'
review
check "a codex past the limit fails within 10 s, saying it was skipped" "fails|yes|yes" \
  "$([[ ${rc} -ne 0 ]] && echo fails || echo "exit 0")|$([[ ${took} -le 10 ]] && echo yes || echo "no, ${took}s")|$(has "codex skipped: timed out" "${out}")"
check "neither the stub nor its child sleep is left" "yes" "$(gone)"

# --- One that traps TERM and sleeps on is KILLed after the grace, with whatever it started since.
stub "trap 'echo TERM ignored' TERM; while :; do \"\${d}/stubsleep\" 60; done"
review
check "a codex that ignores TERM is stopped within the limit plus the grace" "fails|yes|yes" \
  "$([[ ${rc} -ne 0 ]] && echo fails || echo "exit 0")|$([[ ${took} -le $((LIMIT + GRACE + 1)) ]] && echo yes || echo "no, ${took}s")|$(gone)"
check "events.tsv's codex-review line says it timed out" "main|codex skipped: timed out after 10 min" "$(last_event)"

# --- The grace is real: a codex that exits on its own a second after TERM is not KILLed.
stub "trap 'sleep 1; touch \"\${d}/graceful\"; exit 0' TERM; while :; do \"\${d}/stubsleep\" 60; done"
review
check "a codex that exits within the grace after TERM finishes its trap, unKILLed" "yes|yes" \
  "$(has "codex skipped: timed out" "${out}")|$([[ -e "${BIN}/graceful" ]] && echo yes || echo no)"

# --- An interrupted codex-review stops codex as its timeout does: TERM, the grace, then KILL.
stub "trap 'echo TERM ignored' TERM; touch \"\${d}/ready\"; while :; do \"\${d}/stubsleep\" 60; done"
rm -f "${BIN}/ready"
(cd "${P}" && exec env -u SWARM_PROJECT -u HERDR_ENV SWARM_CODEX_SECONDS=60 bash "${SWARM}" codex-review main < /dev/null > "${ROOT}/out" 2>&1) &
spid=$!
for ((i = 0; i < 50; i++)); do [[ -e "${BIN}/ready" ]] && break; sleep 0.2; done
sleep 1; { kill -TERM "${spid}"; wait "${spid}"; } 2>/dev/null || true   # stderr off: no "Terminated" notice
check "codex-review sent TERM leaves neither a TERM-trapping stub nor its child" "yes|yes" \
  "$([[ -e "${BIN}/ready" ]] && echo yes || echo "no stub started")|$(gone $((GRACE + 2)))"
check "events.tsv's codex-review line says it was interrupted" "main|interrupted" "$(last_event)"

# --- A codex that finishes: its findings and exit come through, run with exactly these args.
stub 'echo "P1: x.sh:3 drops the error"; exit 0'
review
check "a codex that finishes passes its exit and findings through" "0|yes" "${rc}|$(has "P1: x.sh:3 drops the error" "${out}")"
check "codex runs as exec review --base origin/main, with no prompt" "[exec][review][--base][origin/main]" "$(cat "${BIN}/args")"
check "codex reads /dev/null, never the caller's stdin" "" "$(cat "${BIN}/stdin")"

# --- A usage limit is codex's own exit, never taken for a timeout.
stub 'echo "You have hit your usage limit."; exit 1'
review
check "a usage limit exits as codex did, and the log says failed, not skipped" "1|yes|main|failed (exit 1)" \
  "${rc}|$(has "usage limit" "${out}")|$(last_event)"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
