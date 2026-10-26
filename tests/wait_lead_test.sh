#!/usr/bin/env bash
# wait_lead_test.sh — swarm.sh wait --lead: it returns once the lead's queue gains a held or escalated
# story, or with merge = human a review item whose PR head is green, printing one line per new item and
# logging one lead-woken line each; at its timeout it fails with nothing printed. What it last saw is kept
# across runs, and a new run takes over from an earlier one. gh is a stub on PATH answering the PR's
# head and its check runs from ${FX}; herdr is a stub listing a running conductor, read once per poll for
# its agent list (no-agent: lines, no_agent_test.sh). Both log each call.
# ln is a stub that fails while ${FX}/ln.fail exists and waits as many seconds as ${FX}/ln.slow holds.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

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

# gh: pr view <n> prints ${FX}/head.<n> or else ${FX}/head, waits as many seconds as ${FX}/view.slow
# holds (a slow gh), and fails while ${FX}/view.fail exists; a head's check runs are ${FX}/<sha>.checks
# or else ${FX}/checks; it has no commit status.
printf '#!/bin/sh\nFX="%s"; LOG="%s"\n' "${FX}" "${ROOT}/gh.log" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "${LOG}"
case "$1 $2" in
  # It reads a line of stdin, as a real gh may, so a caller that leaves its stdin open loses a line.
  "pr view") read -r _ || true
             sleep "$(cat "${FX}/view.slow" 2>/dev/null || echo 0)"
             [ ! -e "${FX}/view.fail" ] || { echo "gh: HTTP 502" >&2; exit 1; }
             cat "${FX}/head.$3" 2>/dev/null || cat "${FX}/head" ;;
  api*) case "$*" in
          *check-runs*) for a in "$@"; do path="${a}"; done; sha="${path#*/commits/}"; sha="${sha%%/*}"
                        cat "${FX}/${sha}.checks" 2>/dev/null || cat "${FX}/checks" ;;
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
printf '#!/bin/sh\nFX="%s"\n' "${FX}" > "${ROOT}/bin/ln"
cat >> "${ROOT}/bin/ln" <<'STUB'
[ ! -e "${FX}/ln.fail" ] || exit 1
sleep "$(cat "${FX}/ln.slow" 2>/dev/null || echo 0)"
STUB
printf 'exec %s "$@"\n' "$(command -v ln)" >> "${ROOT}/bin/ln"
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr" "${ROOT}/bin/ln"
printf 'w:c conduct-e\n' > "${P}/.swarm/state/e"

# checks <conclusion> [sha] — the head's (or <sha>'s) one check run, completed with <conclusion>, or
# in progress for pending.
checks() {
  local st=completed c="\"$1\""; [[ "$1" != pending ]] || { st=in_progress; c=null; }
  printf '{"total_count":1,"check_runs":[{"name":"test","status":"%s","conclusion":%s,"html_url":"u"}]}\n' "${st}" "${c}" \
    > "${FX}/${2:+$2.}checks"
}
item() { { echo ---; printf '%s\n' "${@:2}"; echo ---; echo; echo "# $1"; } > "${B}/$1.md"; }
held() { item "$1" "kind: lead" "status: ready" "escalated_from: code" "held_for: $2"; }
escalated() { item "$1" "kind: lead" "status: ready" "escalated_from: code"; }

# fresh [config line]... — a board with one held story, h, and nothing else; no events, no earlier run.
fresh() {
  stop
  rm -f "${B}"/*.md "${P}/.swarm/events.tsv" "${FX}/view.fail" "${FX}/view.slow" "${FX}/ln.slow" "${FX}/ln.fail" "${FX}"/head.* "${FX}"/*.checks; rm -rf "${P}/.swarm/lead" "${ROOT}"/*.log
  again
  printf '%s\n' "$@" > "${P}/.claude/swarm/config"
  echo "${H}" > "${FX}/head"; checks success
  held h paused
}
# again — forget the last run's output and exit code, keeping what it saw.
again() { rm -f "${ROOT}/out" "${ROOT}/rc"; }
# lead [VAR=value]... <timeout-ms> — swarm.sh wait --lead in the foreground, polling every second, inside
# herdr; output in ${ROOT}/out, exit code in ${ROOT}/rc. Every poll is a heads pass (SWARM_LEAD_HEADS_EVERY=1),
# so the gh counts below are a pass's, unless a case sets it longer.
lead() {
  local envs=()
  while [[ "$1" == [A-Z]*=* ]]; do envs+=("$1"); shift; done
  (cd "${P}" && env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" HERDR_ENV=1 HERDR_PANE_ID=w:me SWARM_LEAD_POLL=1 SWARM_LEAD_HEADS_EVERY=1 \
    ${envs[@]+"${envs[@]}"} bash "${SWARM}" wait --lead "$1" > "${ROOT}/out" 2>&1) 2>/dev/null && echo 0 > "${ROOT}/rc" || echo $? > "${ROOT}/rc"
}
# must <what> <command>... — count a FAIL when the command is false, and say nothing when it is true.
must() { local what="$1"; shift; "$@" || { echo "FAIL ${what}"; fails=$((fails + 1)); }; }
# seen_id — the inode of the run's seen file, which every read replaces (mv), or nothing before the first.
# shellcheck disable=SC2012 # one fixed path; stat -c and stat -f differ between Linux and macOS
seen_id() { { ls -i "${P}/.swarm/lead/seen" 2>/dev/null || true; } | awk '{ print $1 }'; }
# first_read [seen id] — wait until the run has read the board once more than the id says: its seen file
# is a new one, written when a read ends. A fixed sleep is not that: a slow gh or a loaded runner reads
# later, and a read that lands after the case changed the board, the head or the checks sees the changed
# ones, not the ones the case starts from. False when the run exits (its rc file) or 60 s pass without
# one: a run that dies before it reads is not one that read.
first_read() {
  local i
  for ((i = 0; i < 600; i++)); do
    [[ "$(seen_id)" == "$1" ]] || return 0
    [[ ! -e "${ROOT}/rc" ]] || return 1
    sleep 0.1
  done
  return 1
}
# start [VAR=value]... <timeout-ms> — lead in the background, once it has read the board.
start() {
  local before
  before="$(seen_id)"
  lead "$@" &
  lpid=$!
  must "the run read the board once" first_read "${before}"
}
# reads — how many times the run has read PR 7's head.
reads() { grep -c '^pr view 7 ' "${ROOT}/gh.log" 2>/dev/null || true; }
# polls <n> — wait until the run has begun <n> more reads of PR 7's head; after a change, polls 2 waits
# for a read that began after it to end, and polls n for n - 1 of them. False when 60 s pass first; true
# at once when the run has exited.
polls() {
  local want i
  want=$(( $(reads) + $1 ))
  for ((i = 0; i < 600; i++)); do [[ $(reads) -ge ${want} || -e "${ROOT}/rc" ]] && return 0; sleep 0.1; done
  return 1
}
# logged <text> <n> — true once gh's log holds <n> lines with <text>; false if the run exits first or 30 s
# pass.
logged() {
  local i
  for ((i = 0; i < 300; i++)); do
    [[ "$(grep -c "$1" "${ROOT}/gh.log" 2>/dev/null || true)" -lt $2 ]] || return 0
    [[ ! -e "${ROOT}/rc" ]] || return 1
    sleep 0.1
  done
  return 1
}
# returned <tenths> — true once wait --lead has exited, within <tenths> of a second.
returned() {
  local i
  for ((i = 0; i < $1; i++)); do [[ ! -e "${ROOT}/rc" ]] || { lpid=""; return 0; }; sleep 0.1; done
  return 1
}
# freeze <pid> — stop a process, then everything under it, top down, printing each pid: a stopped
# process forks nothing, so no child is born after its parent's children were listed.
freeze() { local c; kill -STOP "$1" 2>/dev/null || return 0; echo "$1"; for c in $(pgrep -P "$1"); do freeze "${c}"; done; }
# stop — end a background run, swarm.sh and the subshells around it, even one that never took the lock,
# and see each of its processes gone within 5 s. One left would share the next case's .swarm/lead.
stop() {
  local pids i
  [[ -z "${lpid}" ]] && return 0
  pids="$(freeze "${lpid}" | paste -sd, -)"
  # shellcheck disable=SC2086 # one pid per word
  kill -KILL ${pids//,/ } 2>/dev/null || true
  wait "${lpid}" 2>/dev/null || true; lpid=""
  for ((i = 0; i < 50; i++)); do ps -p "${pids}" > /dev/null 2>&1 || return 0; sleep 0.1; done
  echo "FAIL stop left the run's processes alive: ${pids}"; fails=$((fails + 1))
}
out() { cat "${ROOT}/out"; }
rc() { cat "${ROOT}/rc" 2>/dev/null; }
events() { awk -F'\t' '{ print $2 " " $3 }' "${P}/.swarm/events.tsv" 2>/dev/null || true; }

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
nothing_yet() { [[ ! -e "${ROOT}/rc" && -z "$(out)" && -z "$(events)" ]]; }

# --- held and escalated stories.
# The run takes its lock 2.5 s late, so its first read is later than a fixed wait after start would be.
fresh; escalated x; echo 2.5 > "${FX}/ln.slow"
start 20000
check "a story held before it started does not wake it" nothing_yet
held x paused
check "an escalated story held since returns within two polls" returned 25
check "it prints held: <slug> (<cause>) and exits 0" test "$(out)|$(rc)" == "held: x (paused)|0"
check "it logs one lead-woken line for it" test "$(events)" == "lead-woken x"
rm -f "${FX}/ln.slow"

# --- what lands between two runs wakes the second at once.
again; held y paused
start 20000
check "an item that appears between two runs wakes the second at once" returned 5
check "the second run prints only that item" test "$(out)|$(rc)" == "held: y (paused)|0"

# --- one run at a time: a new one takes over.
fresh
(cd "${P}" && env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" SWARM_LEAD_POLL=1 bash "${SWARM}" wait --lead 20000 \
  > "${ROOT}/out.a" 2>&1 && echo 0 > "${ROOT}/rc.a" || echo $? > "${ROOT}/rc.a") 2>/dev/null &
apid=$!; must "the earlier run read the board once" first_read ""
# The new run is waited on itself: the earlier one rewrites seen every poll, so start would return on that.
lead 20000 &
lpid=$!
saw() { local i; for ((i = 0; i < 600; i++)); do grep -q "$1" "${ROOT}/out" 2>/dev/null && return 0; sleep 0.1; done; return 1; }
must "the new run took over" saw 'stopping the earlier run'
for ((i = 0; i < 30; i++)); do [[ ! -e "${ROOT}/rc.a" ]] || break; sleep 0.1; done
check "a new wait --lead stops the earlier one" test -e "${ROOT}/rc.a"
check "the earlier one ends with nothing printed" test ! -s "${ROOT}/out.a"
wait "${apid}" 2>/dev/null || true
must "the new run read the board once" first_read "$(seen_id)"
check "the new one says it took over" grep -q 'stopping the earlier run' "${ROOT}/out"
alive() { ps -p "$(cat "$1" 2>/dev/null || echo 0)" > /dev/null 2>&1; }
check "the new one holds the pid file" alive "${P}/.swarm/lead/pid"
held z paused
check "the new one watches" returned 25
check "the new one prints what landed" test "$(grep -v '^swarm:' "${ROOT}/out")" == "held: z (paused)"
check "its pid file is gone once it returns" test ! -e "${P}/.swarm/lead/pid"

fresh; touch "${FX}/ln.fail"
lead 20000 &
lpid=$!
check "when the pid file cannot be made, it stops instead of spinning" returned 30
check "it says it cannot write the pid file" grep -q 'cannot write .*/lead/pid' "${ROOT}/out"
stop; rm -f "${FX}/ln.fail"

fresh; lead 0900
check "a timeout with a leading zero is decimal, not octal" test "$(out)|$(rc)" == "|1"

# --- SWARM_LEAD_POLL and the timeout.
fresh; lead SWARM_LEAD_POLL=0 1000
check "SWARM_LEAD_POLL=0 is refused" grep -q 'SWARM_LEAD_POLL is whole seconds, at least 1' "${ROOT}/out"
fresh; lead SWARM_LEAD_HEADS_EVERY=0 1000
check "SWARM_LEAD_HEADS_EVERY=0 is refused" grep -q 'SWARM_LEAD_HEADS_EVERY is whole seconds, at least 1' "${ROOT}/out"
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

# Each gh pr view takes 1.3 s, longer than the 1 s between polls: the cases below wait for reads (start,
# polls), not for time.
fresh "merge = human"; echo 1.3 > "${FX}/view.slow"; item r "kind: code" "status: review" "prs: ${URL}"
start 120000
must "it polled" polls 3
check "ci_gate reads a green head once, however many polls" test "$(grep -c "${H}/check-runs" "${ROOT}/gh.log")" == 1
echo "${H2}" > "${FX}/head"; must "it polled" polls 2
check "a new head is read again" test "$(grep -c "${H2}/check-runs" "${ROOT}/gh.log")" == 1
touch "${FX}/view.fail"; must "it polled" polls 2; rm -f "${FX}/view.fail"; must "it polled" polls 2
check "a green review item whose head cannot be read for a poll does not wake it after" nothing_yet
check "a cached green head outlives a poll that could not read it" test "$(grep -c "${H2}/check-runs" "${ROOT}/gh.log")" == 1
stop

# The heads pass: PR heads are read on a run's first read and then once every SWARM_LEAD_HEADS_EVERY
# seconds (30 here: room for two polls on a loaded runner), and the polls between read only .swarm/lead/heads.
fresh "merge = human"; checks failure; item r "kind: code" "status: review" "prs: ${URL}"
start SWARM_LEAD_HEADS_EVERY=30 90000
n=$(grep -c '' "${ROOT}/gh.log")
checks success
must "a poll ended" first_read "$(seen_id)"; must "a poll ended" first_read "$(seen_id)"
check "the polls between two heads passes make no gh call" test "$(grep -c '' "${ROOT}/gh.log")" == "${n}"
check "a head that turned green after a heads pass does not wake it before the next pass" nothing_yet
check "it wakes on the next heads pass" returned 600
check "the wake came from that pass, the head's second read, and printed merge:" test "$(reads)|$(out)|$(rc)" == "2|merge: r ${URL}|0"
stop

# A story a close kept (kept:, its PR not reviewed) is listed as kept, never offered to merge, though
# its head is green; once review clears kept:, it is.
fresh "merge = human"; lead 1000   # a first run only records what it saw
again; item k "kind: code" "status: review" "prs: ${URL}" "kept: 2026-10-22 close stalled (not reviewed)"
lead 5000
check "a kept green PR wakes it as kept: <slug> <url> (not reviewed), never as merge:" \
  test "$(grep -c "^kept: k ${URL} (not reviewed)$" "${ROOT}/out")|$(grep -c '^merge: k' "${ROOT}/out")" == "1|0"
(cd "${P}" && env -u SWARM_PROJECT bash "${SWARM}" review k "${URL}" >/dev/null 2>&1) || true
again; lead 5000
check "once review k clears kept:, it is offered to merge" test "$(out)|$(rc)" == "merge: k ${URL}|0"

fresh "merge = human"; echo 1.3 > "${FX}/view.slow"; echo "${H2}" > "${FX}/head.8"; checks pending "${H2}"
item r "kind: code" "status: review" "prs: ${URL} ${URL%/*}/8"
start 120000
# start returned after the first read: it cached the first PR's green head, and the other is pending
checks failure "${H}"; checks success "${H2}"
check "it read the cached head again before it would wake" logged "${H}/check-runs" 2
must "it polled" polls 1   # the read that did it has decided
check "a cached green head that a re-run turned red does not wake it when the item's other PR goes green" nothing_yet
check "a head the fresh re-read finds red is gone from LEAD_GREEN after that poll" \
  test "$(grep -c "^${URL} ${H}$" "${P}/.swarm/lead/green")" == 0
# No longer cached, PR 7's head is read red in each poll's first pass, which then stops before PR 8: a
# fresh re-read comes only after a first pass that read PR 8 green. So PR 8 is read no more, however
# late the counts are taken.
v8=$(grep -c '^pr view 8 ' "${ROOT}/gh.log" || true)
must "a poll ended" first_read "$(seen_id)"; must "a poll ended" first_read "$(seen_id)"
check "the next poll makes no fresh re-read for it" test "$(grep -c '^pr view 8 ' "${ROOT}/gh.log" || true)" == "${v8}"
stop

fresh "merge = human"
start 20000
item r "kind: code" "status: review" "prs: ${URL}"; item r2 "kind: code" "status: review" "prs: ${URL}"
check "two review items turning green at once wake it" returned 25
check "it prints both, so gh never reads the board's lines" test "$(out)" == "merge: r ${URL}"$'\n'"merge: r2 ${URL}"
stop

fresh "merge = human"
start 20000
item r "kind: code" "status: review" "prs: ${URL}" "costs: money"
check "with merge = human, a green costs: money review story wakes it too" returned 25
check "it prints merge: <slug> <PR URL> for it" test "$(out)|$(rc)" == "merge: r ${URL}|0"
stop

fresh "merge = agent"
start 4000
item r "kind: code" "status: review" "prs: ${URL}"
check "with merge = agent, a green review story does not wake it, and it times out" returned 60
check "with merge = agent it times out non-zero with nothing printed" test "$(out)|$(rc)" == "|1"
check "with merge = agent nothing is logged" test -z "$(events)"

fresh "merge = agent"
start 20000
item r "kind: code" "status: review" "prs: ${URL}" "costs: money"
check "with merge = agent, a green costs: money review story wakes it: the user merges it" returned 25
check "it prints merge: <slug> <PR URL> for it under merge = agent" test "$(out)|$(rc)" == "merge: r ${URL}|0"
stop

fresh "merge = agent"; mkdir -p "${P}/docs/epics"
start 20000
item r "kind: code" "status: review" "prs: ${URL}" "costs: money"
printf -- '---\nstatus: review\nprs: %s\n---\n\n# e\n' "${URL}" > "${P}/docs/epics/e.md"
check "a held PR that a story and its epic both list wakes it" returned 25
check "it prints the held PR once, under the story" test "$(out)|$(rc)" == "merge: r ${URL}|0"
stop; rm -rf "${P}/docs/epics"

# The first item listing a held PR is not green (its other PR is red): a later one listing only it still wakes it.
fresh "merge = agent"; mkdir -p "${P}/docs/epics"; echo "${H2}" > "${FX}/head.8"; checks failure "${H2}"
start 20000
item r "kind: code" "status: review" "prs: ${URL} ${URL%/*}/8" "costs: money"
printf -- '---\nstatus: review\nprs: %s\n---\n\n# e\n' "${URL}" > "${P}/docs/epics/e.md"
check "a held PR whose first item is not green still wakes it through a later green one" returned 25
check "it prints the later item" test "$(out)|$(rc)" == "merge: e ${URL}|0"
stop; rm -rf "${P}/docs/epics"

# --- no change: a short timeout.
fresh
start 3000
check "with no change it returns at its timeout" returned 50
check "at its timeout it exits non-zero and prints nothing" test "$(out)|$(rc)" == "|1"
check "events.tsv gains no line while it waits" test -z "$(events)"

# --- a running conductor does not hide a new held story, and a poll asks herdr only for its agent list.
fresh
start 20000
held n cleared-on-error
check "with a conductor running, a new held story still wakes it" returned 25
check "it prints the new held story" test "$(out)" == "held: n (cleared-on-error)"
# wait --lead 0 reads the queue exactly once.
rm -f "${ROOT}/herdr.log"; again; lead 0; again; lead 0
check "one herdr agent list per poll, no per-pane read" test "$(cat "${ROOT}/herdr.log")" == "agent list"$'\n'"agent list"

# --- close still finds a story's pane by its tab record, with that slug in wait --lead's seen file.
printf 'w:c conduct-e\nw:n n\n' > "${P}/.swarm/state/tab-n"
(cd "${P}" && env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" HERDR_ENV=1 HERDR_PANE_ID=w:me bash "${SWARM}" close n > /dev/null 2>&1) || true
check "close on a slug wait --lead saw still closes its pane" grep -qx 'pane close w:n' "${ROOT}/herdr.log"
check "and leaves wait --lead's seen file as it was" grep -qx 'held: n (cleared-on-error)' "${P}/.swarm/lead/seen"
rm -f "${P}/.swarm/state/tab-n"

# --- /swarm's wait arm starts wait --lead and handles a held: or escalated: line at once.
arm="$(awk '/^   - `wait <agent>`/ { s = 1; print; next } s && /^   - `/ { exit } s' "$(dirname "${SWARM}")/../commands/swarm.md")"
check "the wait arm names wait --lead" grep -q 'swarm.sh wait --lead' <<< "${arm}"
# shellcheck disable=SC2016 # the backticks are the Markdown's own
check "the wait arm does the escalated <slug> step for held: or escalated: without waiting for next" \
  grep -q 'do the `escalated <slug>` step for that slug at once, without waiting for `next`' <<< "${arm}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
