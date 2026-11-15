#!/usr/bin/env bash
# sleep_scale_test.sh — make test runs the files side by side, so each one exports HOME or
# CLAUDE_CONFIG_DIR under a root of its own from mktemp (a grep over tests/*_test.sh). And
# SWARM_SLEEP_SCALE scales swarm.sh's fixed sleeps: at 0.01 a start_agent retry (3 s) and a
# deliver_prompt wait (5 s) each finish in under a second; a scale of 0, one that rounds a 1 s sleep
# to 0 or one that is not a number is refused at startup, before any command runs. board's reader
# stopping early prints no write error. Then make test itself: a failing file fails it and its output
# comes whole after its phase, a SERIAL file runs after the parallel ones, and xargs stopping early
# fails the run and leaves no job (nor anything a job started) running, BSD xargs's exit 1 still runs
# the SERIAL phase, a job with no result fails it, an interrupt stops each test with a TERM and leaves
# nothing behind, a test's end stops what it left running, a test sees none of make's variables, a
# make test inside a run that holds the one slot of a cap of 1 takes none and so never waits on it,
# and a path with a space runs.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
export HOME="${ROOT}/home"   # its own runs are top-level when it runs alone: a cap in the real ~/.swarm/test-cap would gate them
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
# Case nap prints 1 when nap 1 took at least 100 ms; case floor prints scaled 20 at a scale of 0.001.
timed() (
  PROJECT_DIR="${ROOT}/p"; BOARD="${PROJECT_DIR}/board"; export SWARM_SLEEP_SCALE=0.01
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
    floor) SWARM_SLEEP_SCALE=0.001 scaled 20; return ;;
  esac
  echo "$(wc -l < "${ROOT}/calls" | tr -d ' ')|$( (( $(now_ms) - t0 < 1000 )) && echo yes || echo "no, $(( $(now_ms) - t0 )) ms")"
)
check "at SWARM_SLEEP_SCALE=0.01 a start_agent retry finishes in under a second" "2|yes" "$(timed start)"
check "at SWARM_SLEEP_SCALE=0.01 a deliver_prompt wait finishes in under a second" "2|yes" "$(timed deliver)"
check "at SWARM_SLEEP_SCALE=0.01 nap 1 still sleeps a tenth of a second, so no poll loop is near busy" "1" "$(timed nap)"
check "scaled holds to a tenth of a second: merge's 20 s CI poll at a scale of 0.001 is 0.1 s" "0.100" "$(timed floor)"
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

# mk <file>... — make test over these files, $JOBS (2) at a time, SERIAL from $SERIAL: its output,
# then its exit on the last line. ms — the time in milliseconds.
mk() { local rc=0 o; o="$(make -s -C "${REPO}" test TESTS="$*" SERIAL="${SERIAL:-}" JOBS="${JOBS:-2}" 2>&1)" || rc=$?; printf '%s\n%s\n' "${o}" "${rc}"; }
ms() { python3 -c 'import time; print(int(time.time() * 1000))'; }
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
# killer kills xargs (its job's parent): make fails, and the jobs beside it are stopped with
# everything their tests started, within a bound, before make returns. late's child would write its
# mark after 2 s; stubborn's child ignores TERM and would write its mark after 6 s.
# shellcheck disable=SC2016 # the stubs' own shell expands these
printf '#!/usr/bin/env bash\nsleep 0.3; kill -KILL "$(ps -o ppid= -p "${PPID}" | tr -d " ")"\n' > "${ROOT}/killer_test.sh"
printf '#!/usr/bin/env bash\n(sleep 2; : > "%s/late.mark") &\nwait\n' "${ROOT}" > "${ROOT}/late_test.sh"
printf '#!/usr/bin/env bash\n(trap "" TERM; sleep 6; : > "%s/stubborn.mark") &\nwait\n' "${ROOT}" > "${ROOT}/stubborn_test.sh"
t0="$(ms)"
o="$(JOBS=3 mk "${ROOT}/killer_test.sh" "${ROOT}/late_test.sh" "${ROOT}/stubborn_test.sh")"; took=$(( $(ms) - t0 ))
sleep 7
check "make test fails when xargs stops early, stops what the jobs left started (TERM, then KILL), and returns within 5 s" "yes|2|no marks|yes" \
  "$(grep -q '^FAIL xargs stopped (exit [0-9]*): not every file ran$' <<< "${o}" && echo yes || echo "no: ${o}")|$(tail -1 <<< "${o}")|$(compgen -G "${ROOT}/*.mark" | sed 's#.*/##' | tr '\n' ' ' | grep . || echo "no marks")|$( ((took < 5000)) && echo yes || echo "no, ${took} ms")"
# BSD xargs exits 1 when a command failed, every file run: a stub xargs that does so still leads
# to the SERIAL phase, with no "stopped".
mkdir -p "${ROOT}/bsd"; printf '#!/bin/sh\n"%s" "$@"\nexit 1\n' "$(command -v xargs)" > "${ROOT}/bsd/xargs"; chmod +x "${ROOT}/bsd/xargs"
printf '#!/usr/bin/env bash\nexit 0\n' > "${ROOT}/one_test.sh"; cp "${ROOT}/one_test.sh" "${ROOT}/two_test.sh"
o="$(PATH="${ROOT}/bsd:${PATH}" SERIAL="${ROOT}/two_test.sh" mk "${ROOT}/one_test.sh" "${ROOT}/two_test.sh")"
check "an xargs exit of 1 (BSD's for a failed command) counts as every file run, and the SERIAL phase runs" "0|yes|no" \
  "$(tail -1 <<< "${o}")|$(grep -q "^ok   ${ROOT}/two_test.sh " <<< "${o}" && echo yes || echo no)|$(grep -q 'xargs stopped' <<< "${o}" && echo yes || echo no)"
# A job that ends with no result (here its TERM trap, which the test pulls) fails make test.
# shellcheck disable=SC2016 # the stub's own shell expands it
printf '#!/usr/bin/env bash\nkill -TERM "${PPID}"; sleep 5\n' > "${ROOT}/noresult_test.sh"
o="$(SERIAL="${ROOT}/noresult_test.sh" mk "${ROOT}/noresult_test.sh")"
check "a SERIAL job that ends with no result fails make test" "2|yes" \
  "$(tail -1 <<< "${o}")|$(grep -qxF "FAIL ${ROOT}/noresult_test.sh: its job ended without a result" <<< "${o}" && echo yes || echo "no: ${o}")"
# An interrupt (INT to the runner's process group, as Ctrl-C sends it) TERMs each test, so its EXIT
# trap runs, and leaves no test process and no temp dir behind.
mkdir -p "${ROOT}/rt"
printf '#!/usr/bin/env bash\ntrap ": > %s/exit.mark" EXIT\nsleep 20\n' "${ROOT}" > "${ROOT}/slowint_test.sh"
# The runner gets INT back to its default first: started in the background here, it would come in
# ignored, and a signal ignored on entry cannot be trapped. A terminal's Ctrl-C has no such catch.
(TMPDIR="${ROOT}/rt" JOBS=2 exec python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
  bash "${REPO}/scripts/test.sh" "${ROOT}/slowint_test.sh" > "${ROOT}/int.out" 2>&1) &
# shellcheck disable=SC2031 # $! is the background subshell's pid, set here; shellcheck 0.11 reads it as set inside it
ipid=$!
for ((i = 0; i < 50; i++)); do grep -q '^run ' "${ROOT}/int.out" 2>/dev/null && pgrep -f "${ROOT}/slowint_test.sh" > /dev/null && break; sleep 0.1; done
kill -INT -- "-${ipid}"
for ((i = 0; i < 100; i++)); do kill -0 "${ipid}" 2>/dev/null || break; sleep 0.1; done
check "an interrupt TERMs each test (its EXIT trap runs), leaving no test process and no temp dir" "yes|none|empty" \
  "$([[ -e "${ROOT}/exit.mark" ]] && echo yes || echo no)|$(pgrep -f "${ROOT}/slowint_test.sh" > /dev/null && echo "left running" || echo none)|$([[ -z "$(ls -A "${ROOT}/rt")" ]] && echo empty || echo "left: $(ls -A "${ROOT}/rt")")"
pkill -KILL -f "${ROOT}/slowint_test.sh" 2>/dev/null || true
# A test's end stops what it left running (lingering's child would write its mark after 1 s), and a
# test sees none of make's JOBS, SERIAL or TESTS.
printf '#!/usr/bin/env bash\n(sleep 1; : > "%s/linger.mark") &\nexit 0\n' "${ROOT}" > "${ROOT}/lingering_test.sh"
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/usr/bin/env bash\necho "${JOBS-unset} ${SERIAL-unset} ${TESTS-unset}" > "%s/env.seen"\n' "${ROOT}" > "${ROOT}/env_test.sh"
o="$(SERIAL="${ROOT}/env_test.sh" mk "${ROOT}/lingering_test.sh" "${ROOT}/env_test.sh")"; sleep 2
check "a test's end stops what it left running, and a test sees no JOBS, SERIAL or TESTS" "0|no mark|unset unset unset" \
  "$(tail -1 <<< "${o}")|$([[ -e "${ROOT}/linger.mark" ]] && echo "its child ran on" || echo "no mark")|$(cat "${ROOT}/env.seen" 2>&1)"
# With a cap of 1 in HOME, a top-level run (TEST_SH_RUN unset, TEST_RUNS_LOG at a file) holds the
# one slot, and a test in it that runs make test again starts a nested run (TEST_SH_RUN naming the
# outer run), which takes no slot, so it never waits on the run it is part of. A nested run that
# waited would be stopped at TEST_FILE_TIMEOUT, past the bound.
mkdir -p "${ROOT}/caphome/.swarm"; echo 1 > "${ROOT}/caphome/.swarm/test-cap"
printf '#!/usr/bin/env bash\ncd "%s/caphome/.swarm/test-slots/1" && echo * > "%s/cap.holder"\n' "${ROOT}" "${ROOT}" > "${ROOT}/inner_test.sh"
printf '#!/usr/bin/env bash\nmake -s -C "%s" test TESTS="%s/inner_test.sh" SERIAL= JOBS=1\n' "${REPO}" "${ROOT}" > "${ROOT}/nest_test.sh"
t0="$(ms)"
o="$(unset TEST_SH_RUN; HOME="${ROOT}/caphome" TEST_RUNS_LOG="${ROOT}/cap-runs.tsv" TEST_FILE_TIMEOUT=5 mk "${ROOT}/nest_test.sh")"; took=$(( $(ms) - t0 ))
check "with a cap of 1, make test over a file that runs make test again holds the slot, finishes within 5 s and frees it" \
  "0|yes|yes|empty" \
  "$(tail -1 <<< "${o}")|$([[ -s "${ROOT}/cap.holder" && "$(cat "${ROOT}/cap.holder")" == "$(tail -1 "${ROOT}/cap-runs.tsv" | cut -f11)" ]] && echo yes || echo "no: holder $(cat "${ROOT}/cap.holder" 2>&1), runs $(cat "${ROOT}/cap-runs.tsv" 2>&1)")|$( ((took < 5000)) && echo yes || echo "no, ${took} ms")|$(compgen -G "${ROOT}/caphome/.swarm/test-slots/*" || echo empty)"
# A file whose path holds a space runs.
printf '#!/usr/bin/env bash\nexit 0\n' > "${ROOT}/sp ace_test.sh"
check "a test file whose path holds a space runs" "yes" \
  "$(JOBS=2 bash "${REPO}/scripts/test.sh" "${ROOT}/sp ace_test.sh" | sed 's/ [0-9]*s$//' | grep -qxF "ok   ${ROOT}/sp ace_test.sh" && echo yes || echo no)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
