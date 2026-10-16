#!/usr/bin/env bash
# wait_lead_test.sh — swarm.sh wait --lead: it returns once the lead's queue gains a held or escalated
# story, or with merge = human a review item whose PR head is green, printing one line per new item and
# logging one lead-woken line each; at its timeout it fails with nothing printed. What it last saw is kept
# across runs, and only one runs at a time. gh is a stub on PATH answering the PR's head and its check
# runs from ${FX}; herdr is a stub listing a running conductor. Both log each call.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
lpid=""
trap 'stop; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; FX="${ROOT}/fx"; B="${P}/docs/stories"
H=1111111111111111111111111111111111111111; H2=2222222222222222222222222222222222222222; URL=https://github.com/o/r/pull/7
mkdir -p "${P}/.claude/swarm" "${B}" "${P}/.swarm/state" "${ROOT}/bin" "${FX}"
git -C "${P}" init -q

# gh: pr view prints ${FX}/head, and fails while ${FX}/view.fail exists; the head's check runs are
# ${FX}/checks; it has no commit status.
printf '#!/bin/sh\nFX="%s"; LOG="%s"\n' "${FX}" "${ROOT}/gh.log" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "${LOG}"
case "$1 $2" in
  "pr view") [ ! -e "${FX}/view.fail" ] || { echo "gh: HTTP 502" >&2; exit 1; }; cat "${FX}/head" ;;
  api*) case "$*" in
          *check-runs*) cat "${FX}/checks" ;;
          */status*) echo '{"total_count":0,"statuses":[]}' ;;
          *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
        esac ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
# herdr: conduct-e is running, busy.
printf '#!/bin/sh\necho "$*" >> "%s"\n' "${ROOT}/herdr.log" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'STUB'
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"conduct-e","agent_status":"working","pane_id":"w:c"}]}}' ;;
  *) echo '{"result":{}}' ;;
esac
STUB
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr"
printf 'w:c conduct-e\n' > "${P}/.swarm/state/e"

# checks <conclusion> — the head's one check run, completed with <conclusion>.
checks() {
  printf '{"total_count":1,"check_runs":[{"name":"test","status":"completed","conclusion":"%s","html_url":"u"}]}\n' "$1" > "${FX}/checks"
}
item() { { echo ---; printf '%s\n' "${@:2}"; echo ---; echo; echo "# $1"; } > "${B}/$1.md"; }
held() { item "$1" "kind: lead" "status: ready" "escalated_from: code" "held_for: $2"; }
escalated() { item "$1" "kind: lead" "status: ready" "escalated_from: code"; }

# fresh [config line]... — a board with one held story, h, and nothing else; no events, no earlier run.
fresh() {
  stop
  rm -f "${B}"/*.md "${P}/.swarm/events.tsv" "${P}/.swarm/state/lead-"* "${FX}/view.fail" "${ROOT}"/*.log
  again
  printf '%s\n' "$@" > "${P}/.claude/swarm/config"
  echo "${H}" > "${FX}/head"; checks success
  held h paused
}
# again — forget the last run's output and exit code, keeping what it saw.
again() { rm -f "${ROOT}/out" "${ROOT}/rc"; }
# lead [VAR=value]... <timeout-ms> — swarm.sh wait --lead in the foreground, polling every second, inside
# herdr; output in ${ROOT}/out, exit code in ${ROOT}/rc.
lead() {
  local envs=()
  while [[ "$1" == [A-Z]*=* ]]; do envs+=("$1"); shift; done
  (cd "${P}" && env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" HERDR_ENV=1 HERDR_PANE_ID=w:me SWARM_LEAD_POLL=1 \
    ${envs[@]+"${envs[@]}"} bash "${SWARM}" wait --lead "$1" > "${ROOT}/out" 2>&1) 2>/dev/null && echo 0 > "${ROOT}/rc" || echo $? > "${ROOT}/rc"
}
# start [VAR=value]... <timeout-ms> — lead in the background; then give it time to read the board once.
start() {
  lead "$@" &
  lpid=$!
  sleep 2
}
# returned <tenths> — true once wait --lead has exited, within <tenths> of a second.
returned() {
  local i
  for ((i = 0; i < $1; i++)); do [[ ! -e "${ROOT}/rc" ]] || { lpid=""; return 0; }; sleep 0.1; done
  return 1
}
# stop — end a background run: swarm.sh itself, by its pid file, then the subshell around it.
stop() {
  [[ -z "${lpid}" ]] && return 0
  kill "$(cat "${P}/.swarm/state/lead-wait.pid" 2>/dev/null)" "${lpid}" 2>/dev/null || true
  wait "${lpid}" 2>/dev/null || true; lpid=""
}
out() { cat "${ROOT}/out"; }
rc() { cat "${ROOT}/rc" 2>/dev/null; }
events() { awk -F'\t' '{ print $2 " " $3 }' "${P}/.swarm/events.tsv" 2>/dev/null || true; }

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
nothing_yet() { [[ ! -e "${ROOT}/rc" && -z "$(out)" && -z "$(events)" ]]; }

# --- held and escalated stories.
fresh; escalated x
start 20000
check "a story held before it started does not wake it" nothing_yet
held x paused
check "an escalated story held since returns within two polls" returned 25
check "it prints held: <slug> (<cause>) and exits 0" test "$(out)|$(rc)" == "held: x (paused)|0"
check "it logs one lead-woken line for it" test "$(events)" == "lead-woken x"

# --- what lands between two runs wakes the second at once.
again; held y paused
start 20000
check "an item that appears between two runs wakes the second at once" returned 5
check "the second run prints only that item" test "$(out)|$(rc)" == "held: y (paused)|0"

# --- one run at a time.
fresh
start 20000
lead 20000 > /dev/null
check "a second wait --lead refuses while one runs" test "$(rc)" == 1
check "it says the first still watches" grep -q 'running already.*still watches' "${ROOT}/out"
stop

# --- SWARM_LEAD_POLL and the timeout.
fresh; lead SWARM_LEAD_POLL=0 1000
check "SWARM_LEAD_POLL=0 is refused" grep -q 'SWARM_LEAD_POLL is whole seconds, at least 1' "${ROOT}/out"
fresh; t0=${SECONDS}; lead SWARM_LEAD_POLL=30 2000
check "the last sleep stops at the timeout, not a full poll later" test $((SECONDS - t0)) -le 4 -a "$(rc)" == 1

fresh; item c "kind: code" "status: ready"
start 20000
item c "kind: lead" "status: ready" "escalated_from: code"
check "a story turned lead with escalated_from: and no held_for: wakes it" returned 25
check "it prints escalated: <slug>" test "$(out)|$(rc)" == "escalated: c|0"

# --- review items, by merge mode.
fresh "merge = human"; checks failure; item r "kind: code" "status: review" "prs: ${URL}"
start 20000
sleep 1
check "with merge = human, a review story whose head is red does not wake it" nothing_yet
checks success
check "once its head is green, it wakes" returned 25
check "it prints merge: <slug> <PR URL>" test "$(out)|$(rc)" == "merge: r ${URL}|0"
check "it logs lead-woken for the review story" test "$(events)" == "lead-woken r"

fresh "merge = human"; item r "kind: code" "status: review" "prs: ${URL}"
start 20000
sleep 1
check "ci_gate reads a green head once, however many polls" test "$(grep -c "${H}/check-runs" "${ROOT}/gh.log")" == 1
echo "${H2}" > "${FX}/head"; sleep 1.5
check "a new head is read again" test "$(grep -c "${H2}/check-runs" "${ROOT}/gh.log")" == 1
touch "${FX}/view.fail"; sleep 1.5; rm -f "${FX}/view.fail"; sleep 2
check "a green review item whose head cannot be read for a poll does not wake it after" nothing_yet
stop

fresh "merge = agent"
start 4000
item r "kind: code" "status: review" "prs: ${URL}"
check "with merge = agent, a green review story does not wake it, and it times out" returned 40
check "with merge = agent it times out non-zero with nothing printed" test "$(out)|$(rc)" == "|1"
check "with merge = agent nothing is logged" test -z "$(events)"

# --- no change: a short timeout.
fresh
start 3000
check "with no change it returns at its timeout" returned 30
check "at its timeout it exits non-zero and prints nothing" test "$(out)|$(rc)" == "|1"
check "events.tsv gains no line while it waits" test -z "$(events)"

# --- a running conductor does not hide a new held story.
fresh
start 20000
held n cleared-on-error
check "with a conductor running, a new held story still wakes it" returned 25
check "it prints the new held story" test "$(out)" == "held: n (cleared-on-error)"
check "it never asks herdr, so a running conductor cannot hide the lead's queue" test ! -s "${ROOT}/herdr.log"

# --- /swarm's wait arm starts wait --lead and handles a held: or escalated: line at once.
arm="$(awk '/^   - `wait <agent>`/ { s = 1; print; next } s && /^   - `/ { exit } s' "$(dirname "${SWARM}")/../commands/swarm.md")"
check "the wait arm names wait --lead" grep -q 'swarm.sh wait --lead' <<< "${arm}"
# shellcheck disable=SC2016 # the backticks are the Markdown's own
check "the wait arm does the escalated <slug> step for held: or escalated: without waiting for next" \
  grep -q 'do the `escalated <slug>` step for that slug at once, without waiting for `next`' <<< "${arm}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
