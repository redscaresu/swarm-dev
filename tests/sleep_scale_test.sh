#!/usr/bin/env bash
# sleep_scale_test.sh — make test runs the files side by side, so each one exports HOME or
# CLAUDE_CONFIG_DIR under a root of its own from mktemp (a grep over tests/*_test.sh). And
# SWARM_SLEEP_SCALE scales swarm.sh's fixed sleeps: at 0.01 a start_agent retry (3 s) and a
# deliver_prompt wait (5 s) each finish in under a second; a scale of 0, one that rounds a 1 s sleep
# to 0 or one that is not a number is refused at startup, before any command runs. board's reader
# stopping early prints no write error. Then make test itself: a failed file that reads stdin on its rerun does not eat the rest of the rerun list, and
# xargs stopping early fails the run.
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
  esac
  echo "$(wc -l < "${ROOT}/calls" | tr -d ' ')|$( (( $(now_ms) - t0 < 1000 )) && echo yes || echo "no, $(( $(now_ms) - t0 )) ms")"
)
check "at SWARM_SLEEP_SCALE=0.01 a start_agent retry finishes in under a second" "2|yes" "$(timed start)"
check "at SWARM_SLEEP_SCALE=0.01 a deliver_prompt wait finishes in under a second" "2|yes" "$(timed deliver)"
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

# mk <file>... — make test over these files, two at a time: its output, then its exit on the last line.
mk() { local rc=0 o; o="$(make -s -C "${REPO}" test TESTS="$*" JOBS=2 2>&1)" || rc=$?; printf '%s\n%s\n' "${o}" "${rc}"; }
# reader fails first, then on its rerun reads all of stdin and passes; failer fails after it, both times.
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/usr/bin/env bash\nm="%s/reader.ran"; [ -e "$m" ] && { cat > /dev/null; exit 0; }; touch "$m"; exit 1\n' "${ROOT}" > "${ROOT}/reader_test.sh"
printf '#!/usr/bin/env bash\nsleep 0.5; exit 1\n' > "${ROOT}/failer_test.sh"
o="$(mk "${ROOT}/reader_test.sh" "${ROOT}/failer_test.sh")"
check "make test reruns every failed file, though one reads stdin, and fails on the one that fails again" "yes|yes|2" \
  "$(grep -qxF "flaky ${ROOT}/reader_test.sh: failed beside the others, passed alone" <<< "${o}" && echo yes || echo no)|$(grep -qxF "FAIL ${ROOT}/failer_test.sh, alone too" <<< "${o}" && echo yes || echo no)|$(tail -1 <<< "${o}")"
# killer kills its xargs wrapper (or xargs, where bash runs it in place of its $(...) subshell) on
# its first run: the file is never recorded as failed, so no rerun can make it pass.
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/usr/bin/env bash\nm="%s/killer.ran"; [ -e "$m" ] && exit 0; touch "$m"; kill -KILL "$(ps -o ppid= -p "${PPID}" | tr -d " ")"\n' "${ROOT}" > "${ROOT}/killer_test.sh"
o="$(mk "${ROOT}/killer_test.sh")"
check "make test fails when xargs stops before every file has run" "yes|2" \
  "$(grep -q '^FAIL xargs stopped (exit [0-9]*): not every file ran$' <<< "${o}" && echo yes || echo "no: ${o}")|$(tail -1 <<< "${o}")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
