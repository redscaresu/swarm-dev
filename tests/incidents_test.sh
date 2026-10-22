#!/usr/bin/env bash
# incidents_test.sh — the incident events, their helpers stubbed: wait_agent's timeout writes one
# wait-timeout line (not for a conductor's hour slice, nor for herdr's wait failing early); an expired
# login one login line however often it is waited on, and one more after a resume (matched through
# agent_name, so a long slug's counts) or a new start, but not after a note or a failed tell; a close
# that ends a stuck builder's build with no open or merged PR one idle-no-pr line (its waits none), and
# none for a stalled, paused, cleared-on-error or impossible close or a build with an open PR. Then flow's incidents section over a
# fixture events.tsv holding six kinds on two days prints the per-day count of each.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${ROOT}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

# sites <case> — run one case in a fresh project, in a subshell with agents.sh and lifecycle.sh
# sourced and their helpers stubbed, and print the incident lines' command, target and outcome.
sites() (
  PROJECT_DIR="${ROOT}/p-$1"; SWARM_HOME="${REPO}"; BOARD="${PROJECT_DIR}/board"; CFG_goal=off
  mkdir -p "${PROJECT_DIR}"
  # shellcheck source=bin/lib/agents.sh
  source "${REPO}/bin/lib/agents.sh"
  # shellcheck source=bin/lib/lifecycle.sh
  source "${REPO}/bin/lib/lifecycle.sh"
  agent_name() { local n; n=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-'); [[ "${n}" =~ ^[a-z] ]] || n="s${n}"; printf '%s' "${n:0:32}"; }
  impossible_refused() { return 1; }
  impossible_story() { :; }
  json() { python3 -c "import json,os,sys; d=json.load(sys.stdin); e=os.environ; print($1)"; }
  own_target() { echo w:1; }
  session_state() { echo idle; }
  login_expired() { return 1; }
  nudge_reason() { echo "you are idle and story/a has no PR"; }
  herdr() { :; }
  archive_session() { :; }
  close_panes() { :; }
  clear_build() { :; }
  held_story() { :; }
  escalate_story() { :; }
  get_fm() { :; }
  set_fm() { :; }
  stub_prs='[{"state":"CLOSED"}]'
  failed_build() { echo "${stub_prs}"; }
  slow_timeout() { sleep 1; echo busy; return 1; }
  case "$1" in
    timeout) settle() { slow_timeout; }; wait_agent a 1000 ;;
    slice) settle() { slow_timeout; }; SWARM_WAIT_SLICE=1 wait_agent conduct-e 1000 ;;
    herdr-fails) settle() { echo busy; return 1; }; wait_agent a 60000 ;;
    login) settle() { echo idle; }; login_expired() { return 0; }
      wait_agent a 1000; wait_agent a 1000; record_event tell:resume a; wait_agent a 1000 ;;
    stuck) settle() { echo idle; }; wait_agent a 1000; wait_agent a 1000; close_agent a met ;;
    login-long) settle() { echo idle; }; login_expired() { return 0; }; slug=Story-With-A-Name-Longer-Than-32-Chars
      wait_agent "$(agent_name "${slug}")" 1000; record_event tell:resume "${slug}"; wait_agent "$(agent_name "${slug}")" 1000 ;;
    login-no-prompt) settle() { echo idle; }; login_expired() { return 0; }
      wait_agent a 1000; record_event tell:note a; record_event tell:resume a "tell: a is busy"; wait_agent a 1000 ;;
    login-restart) settle() { echo idle; }; login_expired() { return 0; }
      wait_agent a 1000; record_event story a; wait_agent a 1000 ;;
    login-stalled) settle() { echo idle; }; login_expired() { return 0; }
      wait_agent a 1000; record_event incident a "stalled: working 40 min; longest-running: pid 1, 40 min: sleep 9"; wait_agent a 1000 ;;
    stalled|paused|cleared-on-error|impossible) close_agent a "$1" ;;
    open-pr) stub_prs='[{"state":"OPEN"}]'; close_agent a ;;
  esac >/dev/null 2>&1 || true
  cut -f2,3,5 "${EVENTS_LOG}" 2>/dev/null | grep '^incident' || true
)

check "wait_agent's timeout writes one wait-timeout line" "$(sites timeout)" $'incident\ta\twait-timeout: busy'
check "a conductor's hour slice running out (SWARM_WAIT_SLICE) writes none" "$(sites slice)" ""
check "herdr's wait failing before the timeout writes none" "$(sites herdr-fails)" ""
check "an expired login waited on twice writes one login line, and a resume then another" "$(sites login)" \
  "$(printf '%s\n' $'incident\ta\tlogin: Login expired' $'incident\ta\tlogin: Login expired')"
check "a stuck builder, waited on twice (nudged) and closed, writes one idle-no-pr line, the close's" "$(sites stuck)" \
  $'incident\ta\tidle-no-pr: closed (met) with no open or merged PR on story/a'
login2="$(printf '%s\n' $'incident\ta\tlogin: Login expired' $'incident\ta\tlogin: Login expired')"
check "a resume for a slug over 32 characters ends its agent's login episode" "$(sites login-long)" \
  "$(printf '%s\n' $'incident\tstory-with-a-name-longer-than-32\tlogin: Login expired' $'incident\tstory-with-a-name-longer-than-32\tlogin: Login expired')"
check "a note or a failed tell does not end a login episode" "$(sites login-no-prompt)" $'incident\ta\tlogin: Login expired'
check "the agent's start line ends a login episode" "$(sites login-restart)" "${login2}"
check "a stalled incident between two waits does not end a login episode" "$(sites login-stalled)" \
  "$(printf '%s\n' $'incident\ta\tlogin: Login expired' $'incident\ta\tstalled: working 40 min; longest-running: pid 1, 40 min: sleep 9')"
# With escalate_ladder set, a stall stepped up prints step-up's line, then the longest-running one.
ladder() (
  PROJECT_DIR="${ROOT}/p-ladder"; SWARM_HOME="${REPO}"; BOARD="${PROJECT_DIR}/board"; CFG_goal=off
  mkdir -p "${PROJECT_DIR}"
  # shellcheck source=bin/lib/agents.sh
  source "${REPO}/bin/lib/agents.sh"
  # shellcheck source=bin/lib/lifecycle.sh
  source "${REPO}/bin/lib/lifecycle.sh"
  own_target() { echo w:1; }
  stall_py() { echo a; }
  settle() { echo "stalled: working 40 min with no commit"; }
  longest_child() { echo "longest-running: pid 400, 45 min: sleep"; }
  ladder_step() { echo "stepped up: a: sonnet -> opus"; return "${LADDER_RC}"; }
  LADDER_RC="$1" wait_agent a 1000 --stall 2>/dev/null; echo "exit $?"
)
check "another step-up still running prints the longest-running line as read" "$(ladder 5)" \
  "$(printf '%s\n' 'stepping up: a: another step-up of it is running; wait on its builder again' 'longest-running: pid 400, 45 min: sleep' 'exit 0')"
check "a stall stepped up prints the longest-running line after stepped up" "$(ladder 0)" \
  "$(printf '%s\n' 'stepped up: a: sonnet -> opus' 'longest-running: pid 400, 45 min: sleep; read before the step-up closed its pane, so the PID may be gone: check it with ps first' 'exit 0')"
for cause in stalled paused cleared-on-error impossible; do
  check "a close with cause ${cause} and no PR writes none" "$(sites "${cause}")" ""
done
check "a close that ends a build with an open PR writes none" "$(sites open-pr)" ""

# flow's incidents section over two days (noon UTC, flow run with TZ=UTC so the local day is UTC's),
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
out="$(cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT TZ=UTC PATH="${ROOT}/bin:${PATH}" bash "${REPO}/bin/swarm.sh" flow --since 2026-10-02)"
check "flow counts every kind's incidents per day" "$(sed -n '/^## incidents$/,/^$/p' <<< "${out}" | sed '/^$/d')" "$(printf '%s\n' \
  "## incidents" $'day\tkind\tincidents' \
  $'2026-10-02\tcodex-limit\t1' $'2026-10-02\tidle-no-pr\t1' $'2026-10-02\tlogin\t1' $'2026-10-02\twait-timeout\t2' \
  $'2026-10-03\tcodex-limit\t2' $'2026-10-03\tidle-no-pr\t1' $'2026-10-03\tlogin\t1' $'2026-10-03\tmerge-blocked\t1' \
  $'2026-10-03\tpull-failed\t1')"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
