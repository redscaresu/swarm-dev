#!/usr/bin/env bash
# sleep_scale_test.sh — make test runs the files side by side, so each one exports HOME or
# CLAUDE_CONFIG_DIR under a root of its own from mktemp (a grep over tests/*_test.sh). And
# SWARM_SLEEP_SCALE scales swarm.sh's fixed sleeps: at 0.01 a start_agent retry (3 s) and a
# deliver_prompt wait (5 s) each finish in under a second; a scale of 0, one that rounds a 1 s sleep
# to 0 or one that is not a number is refused at startup, before any command runs. board's reader
# stopping early prints no write error. Then make test itself: a failing file fails it and its output
# comes whole after its phase, a SERIAL file runs after the parallel ones, and xargs stopping early
# fails the run and leaves no job running.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

# rooted <file> <var> — 0 when <file> sets <var> from mktemp, or from a variable it sets so.
rooted() {
  local from
  grep -qE "^$2=\"\\\$\(mktemp " "$1" && return 0
  from="$(sed -nE "s/^$2=\"\\\$\(cd \"\\\$\{([A-Za-z_]+)\}\".*/\1/p" "$1" | head -1)"
  [[ -n "${from}" ]] && grep -qE "^${from}=\"\\\$\(mktemp " "$1"
}
unrooted=""
for t in "${REPO}"/tests/*_test.sh; do
  v="$(sed -nE 's/^export (HOME|CLAUDE_CONFIG_DIR)="\$\{([A-Za-z_]+)\}.*/\2/p' "${t}" | head -1)"
  [[ -n "${v}" ]] && rooted "${t}" "${v}" || unrooted+="${t##*/} "
done
check "every tests/*_test.sh exports HOME or CLAUDE_CONFIG_DIR under its own mktemp root" "" "${unrooted}"

# timed <case> — run one case with agents.sh sourced and its helpers stubbed, at SWARM_SLEEP_SCALE
# 0.01; print "<herdr calls>|<under a second?>". herdr fails its first call and takes the second.
# Case nap prints 1 when nap 1 took at least 100 ms.
timed() (
  PROJECT_DIR="${ROOT}/p"; SWARM_HOME="${REPO}"; BOARD="${PROJECT_DIR}/board"; export SWARM_SLEEP_SCALE=0.01
  mkdir -p "${PROJECT_DIR}"; : > "${ROOT}/calls"
  # shellcheck source=bin/lib/agents.sh
  source "${REPO}/bin/lib/agents.sh"
  die() { echo "die: $*"; exit 1; }
  json() { python3 -c "import json,os,sys; d=json.load(sys.stdin); e=os.environ; print($1)"; }
  policy() { echo "codex gpt-5 high"; }
  agent_name() { echo "$1"; }
  free_agent_name() { :; }
  next_pane() { echo w:1; }
  clean_env() { :; }
  record_agent() { :; }
  herdr() {
    echo "$*" >> "${ROOT}/calls"
    [[ $(wc -l < "${ROOT}/calls") -ge 2 ]] || return 1
    echo '{"result":{"agent":{"agent_status":"working"}}}'
  }
  echo brief > "${ROOT}/brief"
  local t0
  t0="$(now_ms)"
  case "$1" in
    start) deliver_prompt() { :; }; start_agent tab a "${ROOT}" builder "${ROOT}/brief" >/dev/null ;;
    deliver) deliver_prompt a "${ROOT}/brief" w:1 ;;
    nap) nap 1; echo "$(( $(now_ms) - t0 >= 100 ))"; return ;;
  esac
  echo "$(wc -l < "${ROOT}/calls" | tr -d ' ')|$( (( $(now_ms) - t0 < 1000 )) && echo yes || echo "no, $(( $(now_ms) - t0 )) ms")"
)
check "at SWARM_SLEEP_SCALE=0.01 a start_agent retry finishes in under a second" "2|yes" "$(timed start)"
check "at SWARM_SLEEP_SCALE=0.01 a deliver_prompt wait finishes in under a second" "2|yes" "$(timed deliver)"
check "at SWARM_SLEEP_SCALE=0.01 nap 1 still sleeps a tenth of a second, so no poll loop is near busy" "1" "$(timed nap)"
# scale <value> — taken or refused: swarm.sh run outside any project, so a scale it takes stops it next,
# at the project lookup.
scale() {
  local o; o="$(cd "${ROOT}" && env -u SWARM_PROJECT SWARM_SLEEP_SCALE="$1" bash "${REPO}/bin/swarm.sh" status 2>&1)" || true
  [[ "${o}" == *"is not a number of at least 0.001"* ]] && echo refused || echo taken
}
check "SWARM_SLEEP_SCALE 0, 0.0001 and x are refused; 0.001 and 1 are taken" "refused refused refused taken taken" \
  "$(scale 0) $(scale 0.0001) $(scale x) $(scale 0.001) $(scale 1)"
# A bad scale stops swarm.sh before its command runs: merge never reaches gh.
git -C "${ROOT}" init -q; mkdir -p "${ROOT}/.claude/swarm"; : > "${ROOT}/.claude/swarm/config"
mkdir -p "${ROOT}/bin"; printf '#!/bin/sh\necho "$*" >> "%s/gh.log"\nexit 1\n' "${ROOT}" > "${ROOT}/bin/gh"; chmod +x "${ROOT}/bin/gh"
o="$(cd "${ROOT}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_SLEEP_SCALE=0 PATH="${ROOT}/bin:${PATH}" bash "${REPO}/bin/swarm.sh" merge https://github.com/o/r/pull/1 2>&1)" && rc=0 || rc=$?
check "SWARM_SLEEP_SCALE=0 stops swarm.sh at startup, saying why, before merge calls gh" "1|yes|no gh" \
  "${rc}|$([[ "${o}" == *"SWARM_SLEEP_SCALE: '0' is not a number of at least 0.001"* ]] && echo yes || echo "no: ${o}")|$([[ -e "${ROOT}/gh.log" ]] && echo "gh ran" || echo "no gh")"

# board's reader stopping early, with SIGPIPE ignored (as under ptywatch.py's python), prints nothing:
# a write error in a dash frame made it repaint (a flake the parallel runs showed).
mkdir -p "${ROOT}/b/stories"; for i in $(seq 1 200); do : > "${ROOT}/b/stories/s${i}.md"; done
o="$( (trap '' PIPE; PROJECT_DIR="${ROOT}/b"; BOARD="${ROOT}/b"
  # shellcheck source=bin/lib/board.sh
  source "${REPO}/bin/lib/board.sh"; board stories | { read -r _; }) 2>&1)"
check "board's reader stopping early, SIGPIPE ignored, prints no write error" "" "${o}"

# mk <file>... — make test over these files, two at a time (SERIAL from $SERIAL): its output, then its
# exit on the last line.
mk() { local rc=0 o; o="$(make -s -C "${REPO}" test TESTS="$*" SERIAL="${SERIAL:-}" JOBS=2 2>&1)" || rc=$?; printf '%s\n%s\n' "${o}" "${rc}"; }
# A failing file fails make, and its output comes whole once its phase is over: failer prints 3000
# lines (past PIPE_BUF) at once and fails; slow passes a second later.
printf '#!/usr/bin/env bash\nseq 1 3000; exit 1\n' > "${ROOT}/failer_test.sh"
printf '#!/usr/bin/env bash\nsleep 1\n' > "${ROOT}/slow_test.sh"
o="$(mk "${ROOT}/failer_test.sh" "${ROOT}/slow_test.sh")"
check "a failing file fails make test, and its output comes whole after every file of its phase ended" "2|yes|yes" \
  "$(tail -1 <<< "${o}")|$(sed -n "/^---- ${ROOT//\//\\/}\/failer_test.sh$/,\$p" <<< "${o}" | sed -n '2,3001p' | cmp -s - <(seq 1 3000) && echo yes || echo no)|$(awk -v s="ok   ${ROOT}/slow_test.sh" -v f="---- ${ROOT}/failer_test.sh" 'index($0, s) == 1 { ok = NR } $0 == f { at = NR } END { print (ok && at > ok) ? "yes" : "no" }' <<< "${o}")"
# A SERIAL file starts only once the parallel ones have ended.
# shellcheck disable=SC2016 # the stubs' own shell expands these
printf '#!/usr/bin/env bash\nsleep 1; python3 -c "import time; print(time.time())" > "%s/par.end"\n' "${ROOT}" > "${ROOT}/par_test.sh"
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\npython3 -c "import time; print(time.time())" > "%s/ser.start"\n' "${ROOT}" > "${ROOT}/ser_test.sh"
o="$(SERIAL="${ROOT}/ser_test.sh" mk "${ROOT}/ser_test.sh" "${ROOT}/par_test.sh")"
check "a SERIAL file runs after the parallel ones have ended" "0|yes" \
  "$(tail -1 <<< "${o}")|$(python3 -c 'import sys; print("yes" if float(open(sys.argv[1]).read()) >= float(open(sys.argv[2]).read()) else "no")' "${ROOT}/ser.start" "${ROOT}/par.end")"
# killer kills xargs (its wrapper's parent): make fails, and the job beside it (late, which would
# write its mark after 2 s) is stopped before make returns, not left running.
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/usr/bin/env bash\nsleep 0.3; kill -KILL "$(ps -o ppid= -p "${PPID}" | tr -d " ")"\n' > "${ROOT}/killer_test.sh"
printf '#!/usr/bin/env bash\nsleep 2; : > "%s/late.mark"\n' "${ROOT}" > "${ROOT}/late_test.sh"
o="$(mk "${ROOT}/killer_test.sh" "${ROOT}/late_test.sh")"; sleep 3
check "make test fails when xargs stops early, and leaves no job running" "yes|2|no mark" \
  "$(grep -q '^FAIL xargs stopped (exit [0-9]*): not every file ran$' <<< "${o}" && echo yes || echo "no: ${o}")|$(tail -1 <<< "${o}")|$([[ -e "${ROOT}/late.mark" ]] && echo "late ran on" || echo "no mark")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
