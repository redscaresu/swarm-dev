#!/usr/bin/env bash
# incidents_test.sh — the incident events: wait_agent's timeout (wait-timeout, but not a conductor's
# hour slice), an expired login (login) and an idle builder with no PR (idle-no-pr), and close_agent
# ending a build with no PR (idle-no-pr), each write one incident line of its kind, their helpers
# stubbed. Then flow's incidents section over a fixture events.tsv holding six kinds on two days
# prints the per-day count of each.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

# sites <case> — run one site in a subshell with agents.sh and lifecycle.sh sourced and their helpers
# stubbed, and print the incident lines' command, target and outcome.
sites() (
  PROJECT_DIR="${ROOT}/p$1"; SWARM_HOME="${REPO}"; BOARD="${PROJECT_DIR}/board"; CFG_goal=off
  mkdir -p "${PROJECT_DIR}"
  # shellcheck source=bin/lib/agents.sh
  source "${REPO}/bin/lib/agents.sh"
  # shellcheck source=bin/lib/lifecycle.sh
  source "${REPO}/bin/lib/lifecycle.sh"
  json() { python3 -c "import json,os,sys; d=json.load(sys.stdin); e=os.environ; print($1)"; }
  own_target() { echo w:1; }
  session_state() { echo idle; }
  login_expired() { return 1; }
  nudge_reason() { return 1; }
  herdr() { :; }
  archive_session() { :; }
  close_panes() { :; }
  case "$1" in
    timeout) settle() { echo busy; return 1; }; wait_agent a 1000 ;;
    slice) settle() { echo busy; return 1; }; WAIT_SLICE=1 wait_agent conduct-e 1000 ;;
    login) settle() { echo idle; }; login_expired() { return 0; }; wait_agent a 1000 ;;
    idle) settle() { echo idle; }; nudge_reason() { echo "you are idle and story/a has no PR"; }; wait_agent a 1000 ;;
    idle-pr) settle() { echo idle; }; wait_agent a 1000 ;;
    close) failed_build() { echo '[{"state":"CLOSED"}]'; }; clear_build() { :; }; held_story() { :; }; close_agent a paused ;;
    close-pr) failed_build() { echo '[{"state":"OPEN"}]'; }; clear_build() { :; }; held_story() { :; }; close_agent a paused ;;
  esac >/dev/null 2>&1 || true
  cut -f2,3,5 "${EVENTS_LOG}" 2>/dev/null | grep '^incident' || true
)

check "wait_agent's timeout writes one wait-timeout line" "$(sites timeout)" $'incident\ta\twait-timeout: busy'
check "a conductor's hour slice running out (WAIT_SLICE) writes none" "$(sites slice)" ""
check "an expired login writes one login line" "$(sites login)" $'incident\ta\tlogin: Login expired'
check "a builder that settles idle with no PR, after its nudges, writes one idle-no-pr line" "$(sites idle)" \
  $'incident\ta\tidle-no-pr: you are idle and story/a has no PR'
check "a builder idle with its PR writes none" "$(sites idle-pr)" ""
check "a close that ends a build with only a closed PR writes one idle-no-pr line" "$(sites close)" \
  $'incident\ta\tidle-no-pr: closed (paused) with no PR on story/a'
check "a close that ends a build with an open PR writes none" "$(sites close-pr)" ""

# flow's incidents section over two days (noon UTC, the same local day in any zone within 11 hours),
# with an ok line and a malformed one that count nothing, and a day outside --since.
P="${ROOT}/repo"; mkdir -p "${P}/.swarm"; git -C "${P}" init -q
ev() { printf '%s\tincident\ts\tw:1\t%s\n' "$1T12:00:00Z" "$2" >> "${P}/.swarm/events.tsv"; }
ev 2026-10-01 "wait-timeout: busy"
ev 2026-10-02 "wait-timeout: busy"
ev 2026-10-02 "wait-timeout: unknown"
ev 2026-10-02 "login: Login expired"
ev 2026-10-03 "login: Login expired"
ev 2026-10-02 "idle-no-pr: you are idle and story/s has no PR"
ev 2026-10-03 "idle-no-pr: closed (met) with no PR on story/s"
ev 2026-10-03 "pull-failed: docs/stories/s.md"
ev 2026-10-03 "merge-blocked: gh pr merge"
ev 2026-10-02 "codex-limit: usage limit"
ev 2026-10-03 "codex-limit: usage limit"
ev 2026-10-03 "codex-limit: usage limit"
printf '%s\n' $'2026-10-03T12:00:00Z\tmerge\ts\tw:1\tok' $'bad\tincident\ts\tw:1\tlogin: x' >> "${P}/.swarm/events.tsv"
mkdir -p "${ROOT}/bin"; printf '#!/bin/sh\nexit 1\n' > "${ROOT}/bin/gh"; chmod +x "${ROOT}/bin/gh"
out="$(cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${REPO}/bin/swarm.sh" flow --since 2026-10-02)"
check "flow counts every kind's incidents per day" "$(sed -n '/^## incidents$/,/^$/p' <<< "${out}" | sed '/^$/d')" "$(printf '%s\n' \
  "## incidents" $'day\tkind\tincidents' \
  $'2026-10-02\tcodex-limit\t1' $'2026-10-02\tidle-no-pr\t1' $'2026-10-02\tlogin\t1' $'2026-10-02\twait-timeout\t2' \
  $'2026-10-03\tcodex-limit\t2' $'2026-10-03\tidle-no-pr\t1' $'2026-10-03\tlogin\t1' $'2026-10-03\tmerge-blocked\t1' \
  $'2026-10-03\tpull-failed\t1')"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
