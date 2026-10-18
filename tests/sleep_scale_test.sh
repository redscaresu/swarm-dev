#!/usr/bin/env bash
# sleep_scale_test.sh — make test runs the files side by side, so each one exports HOME or
# CLAUDE_CONFIG_DIR under a root of its own from mktemp (a grep over tests/*_test.sh). And
# SWARM_SLEEP_SCALE scales swarm.sh's fixed sleeps: at 0.01 a start_agent retry (3 s) and a
# deliver_prompt wait (5 s) each finish in under a second; a scale of 0 is refused.
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
# Case zero prints whether scaled takes a scale of 0 instead.
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
    zero) (SWARM_SLEEP_SCALE=0 scaled 1) >/dev/null 2>&1 && echo taken || echo refused; return ;;
  esac
  echo "$(wc -l < "${ROOT}/calls" | tr -d ' ')|$( (( $(now_ms) - t0 < 1000 )) && echo yes || echo "no, $(( $(now_ms) - t0 )) ms")"
)
check "at SWARM_SLEEP_SCALE=0.01 a start_agent retry finishes in under a second" "2|yes" "$(timed start)"
check "at SWARM_SLEEP_SCALE=0.01 a deliver_prompt wait finishes in under a second" "2|yes" "$(timed deliver)"
check "a SWARM_SLEEP_SCALE of 0 is refused" "refused" "$(timed zero)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
