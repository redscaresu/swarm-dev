#!/usr/bin/env bash
# next_time_limit_test.sh — `swarm.sh next` keeps to the report deadline (SWARM_REPORT_SECONDS). With
# herdr's agent list, ci_gate's gh read (a head's check runs), herdr's agent read or gh's read of the
# repo's origin sleeping past it, next prints its step first, names the cut read in a `skipped (over
# <n> s):` line, and exits soon after the deadline, before the read could have finished: it was cut or
# skipped, not waited for. The reads that decide a conductor start are cut too, and fail closed: after
# one is cut, next starts no conductor and names the one it would have started, telling the lead to run
# next again, on a wait step and on a no-agent step while a conductor works. A start that begins is
# never cut: one slower than the deadline runs to its end and logs its conduct line ok. With every read
# fast, next reads herdr's agent list once, prints its queued: line and no skipped: line; a
# SWARM_REPORT_SECONDS that is not a whole number above 0 falls back to 30, so the first read still runs.
# gh, herdr and claude are stubs on PATH. A slow read logs `<read> start` to slow.log and when it began
# to <read>.at, sleeps SLEEP, then logs `<read> done`; one the deadline passed before next reached never
# starts. herdr notes when its first agent list began in first.at: next's first read, made just after
# the deadline is set. Timing holds on a loaded machine: the fast runs get a deadline far past what
# their reads take; each slow run's deadline covers the work before its slow read (the herdr list is
# the first read, the later ones get more); the time check counts from first.at, so from the deadline
# less its seconds, not from before next starts, and allows SLACK for next's work after the cut.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export HOME="${ROOT}/home" TMPDIR="${ROOT}/tmp" CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root
mkdir -p "${HOME}" "${TMPDIR}" "${ROOT}/bin"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${ROOT}/bin/claude"
fails=0
FAR=600          # the fast runs' deadline: far past what their reads take on any machine
LIST_LIMIT=5     # the slow herdr list's deadline: it is next's first read
CHECKS_LIMIT=40  # the slow check-runs read's: it comes after next_step's work and three gh calls
READ_LIMIT=20    # the slow agent read's: it comes after next_step's no-agent check
ORIGIN_LIMIT=20  # the slow origin read's: it comes after a no-agent step's work
START_LIMIT=20   # the slow start's at least: every read before it must finish first, so it is raised to
                 # twice what the fast run took after its first read, on a machine where that is more
SLACK=60         # what next may take after the deadline, on a loaded machine
SLEEP=120        # a slow read: past each deadline plus SLACK, so a read next waits for fails the time check

# gh: the project's repo, one open PR on story/s1 (head SHA), and that head's check runs, all passed
# 40 and a half minutes before gh is asked, so ci_gate, reading its clock just after, counts 40. A file
# slow-<read> in ROOT makes that read slow: slow-origin the repo view, slow-runs the check runs ci_gate
# reads.
SHA=1111111111111111111111111111111111111111
printf '#!/bin/sh\nF="%s"\nSLEEP=%s\nSHA=%s\n' "${ROOT}" "${SLEEP}" "${SHA}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'EOF'
# slow <read> — when ROOT has slow-<read>: log its start and when, sleep, log its end.
slow() { [ -f "$F/slow-$1" ] || return 0; echo "$1 start" >> "$F/slow.log"; date +%s > "$F/$1.at"; sleep "$SLEEP"; echo "$1 done" >> "$F/slow.log"; }
path=""; for a in "$@"; do case "$a" in repos/*) path="${a%%\?*}" ;; esac; done
case "$1 $2" in
  "repo view") slow origin; echo o/svc; exit 0 ;;
  "pr list") echo "3 $SHA story/s1"; exit 0 ;;
esac
case "${path}" in
  repos/o/svc/commits/*/check-runs) slow runs
    DONE="$(perl -MPOSIX=strftime -e 'print strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time - 40 * 60 - 30))')"
    echo '{"total_count":1,"check_runs":[{"status":"completed","conclusion":"success","completed_at":"'"$DONE"'"}]}' ;;
  repos/o/svc/commits/*/status) echo '{"statuses":[],"total_count":0}' ;;
  *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
# herdr: the agents in ROOT/agents ("<name> <pane>" lines), and a conductor start as next_test's stub
# makes one. slow-list makes the agent list slow, slow-read its agent read (a pane's text); slow-start
# makes `agent start` take the seconds in start-seconds (START_LIMIT + 3).
printf '#!/bin/sh\nF="%s"\nSLEEP=%s\n' "${ROOT}" "${SLEEP}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
slow() { [ -f "$F/slow-$1" ] || return 0; echo "$1 start" >> "$F/slow.log"; date +%s > "$F/$1.at"; sleep "$2"; echo "$1 done" >> "$F/slow.log"; }
echo "$*" >> "$F/herdr.log"
[ "$*" != "agent list" ] || [ -f "$F/first.at" ] || date +%s > "$F/first.at"
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;
  "workspace list") echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  "tab create") echo '{"result":{"root_pane":{"pane_id":"w:8"}}}' ;;
  "agent start") slow start "$(cat "$F/start-seconds")"; echo "$3 w:8" >> "$F/agents" ;;
  "agent prompt") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent wait") echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent read") slow read "$SLEEP" ;;
  "agent list") slow list "$SLEEP"
    awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
      { printf "%s{\"name\":\"%s\",\"agent_status\":\"working\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
      END { print "]}}" }' "$F/agents" ;;
esac
EOF
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr" "${ROOT}/bin/claude"

# The epic e1 has the code story s1 in review, whose PR #3 is green, and a working conductor,
# conduct-e1, in a pane this project recorded. No story is ready, so next starts no conductor.
p="${ROOT}/proj"
mkdir -p "${p}/.claude/swarm" "${p}/docs/epics" "${p}/docs/stories" "${p}/.swarm/briefs" "${p}/.swarm/state"
: > "${p}/.claude/swarm/config"
git -C "${p}" init -q && git -C "${p}" remote add origin https://github.com/o/svc
printf -- '---\nstatus: active\n---\n' > "${p}/docs/epics/e1.md"
printf -- '---\nstatus: review\nkind: code\nepic: e1\nprs: https://github.com/o/svc/pull/3\n---\n' > "${p}/docs/stories/s1.md"
touch "${p}/.swarm/briefs/conduct-e1.md"; echo "w:7 conduct-e1" > "${p}/.swarm/state/tab"
echo "conduct-e1 w:7" > "${ROOT}/agents"

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
# nextrun <deadline> [slow-file] — run next with the stubs under SWARM_REPORT_SECONDS=<deadline>, with
# ROOT/<slow-file> there if named; OUT holds its stdout, ERR its stderr, ENDED when it exited (epoch
# seconds), and LISTS how many agent lists herdr answered.
nextrun() {
  : > "${ROOT}/slow.log"; : > "${ROOT}/herdr.log"; rm -f "${ROOT}"/*.at; [[ -z "${2:-}" ]] || touch "${ROOT}/$2"
  OUT="$(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 SWARM_REPORT_SECONDS="$1" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" next 2> "${ROOT}/next.err")" || true
  ENDED="$(date +%s)"; ERR="$(cat "${ROOT}/next.err")"
  [[ -z "${2:-}" ]] || rm "${ROOT}/$2"
  LISTS="$(grep -cx 'agent list' "${ROOT}/herdr.log" || true)"
}
first() { printf '%s\n' "${OUT%%$'\n'*}"; }
# skipped — next's skipped: line, or (none).
skipped() { grep '^skipped ' <<< "${OUT}" || echo "(none)"; }
# named <read> — <read> when next's skipped: line names it among others, else (not named).
named() { skipped | sed 's/^skipped (over [0-9]* s): //' | tr ',' '\n' | sed 's/^ //' | grep -x -- "$1" || echo "(not named)"; }
# soon <name> <deadline> — next exited within <deadline> + SLACK seconds of its first read (first.at):
# the report's deadline is no later than that read's start plus <deadline>.
soon() {
  local at
  if ! at="$(cat "${ROOT}/first.at" 2>/dev/null)"; then
    echo "FAIL $1: herdr's agent list, next's first read, never ran"; fails=$((fails + 1))
  elif (( ENDED - at < $2 + SLACK )); then echo "ok   $1 ($((ENDED - at)) s after its first read)"
  else echo "FAIL $1: next exited $((ENDED - at)) s after its first read, not within $2 + ${SLACK} s"; fails=$((fails + 1)); fi
}
# waited <read> — `waited for` when next exited SLEEP seconds or more after the slow <read> began (it
# waited the read out), else `not waited for`, as when the read never began.
waited() {
  local at
  at="$(cat "${ROOT}/$1.at" 2>/dev/null)" && (( ENDED - at >= SLEEP )) && echo "waited for" || echo "not waited for"
}
# fail_closed — `said` when next printed conduct_ready's line for the backlog's conductor it did not
# start after a cut read, telling the lead to run next again.
fail_closed() {
  grep -qE "^no conductor started: conduct-backlog-[a-z0-9-]+: a read it needs was cut at the report's deadline; run swarm\.sh next again$" <<< "${OUT}" \
    && echo said || echo "not said: ${OUT}"
}
# starts — how many conductor starts herdr was asked for.
starts() { grep -c '^agent start' "${ROOT}/herdr.log" || true; }

# --- Every read fast: one agent list, the queued: line, and no skipped: line.
nextrun "${FAR}"
check "fast reads: next's step comes first" "wait conduct-e1" "$(first)"
check "fast reads: next reads herdr's agent list once" "1" "${LISTS}"
check "fast reads: next prints its queued: line" \
  "queued: o/svc #3 story/s1 green 40m with no review on 1111111 (conduct-e1)" "$(grep '^queued: ' <<< "${OUT}" || echo "(none)")"
check "fast reads: next names no skipped read" "(none)" "$(skipped)"
FAST=$(( ENDED - $(cat "${ROOT}/first.at" 2>/dev/null || echo "${ENDED}") ))
(( 2 * FAST <= START_LIMIT )) || START_LIMIT=$(( 2 * FAST ))
echo "$(( START_LIMIT + 3 ))" > "${ROOT}/start-seconds"

# --- A SWARM_REPORT_SECONDS that is not a whole number above 0 is 30: herdr's list, the first read, runs.
for v in 0 abc; do
  nextrun "${v}"
  check "SWARM_REPORT_SECONDS=${v} falls back to 30 s: next reads herdr's agent list" "1" "${LISTS}"
done

# --- herdr's agent list is slow: next's step is worked out without it (no conductor seen, so it
# conducts the ready story r1's epic), and the list is named.
printf -- '---\nstatus: ready\nkind: code\nepic: e1\n---\n' > "${p}/docs/stories/r1.md"
nextrun "${LIST_LIMIT}" slow-list
rm "${p}/docs/stories/r1.md"
soon "a slow herdr list: next exits soon after the deadline" "${LIST_LIMIT}"
check "a slow herdr list is cut, not waited for" "not waited for" "$(waited list)"
check "a slow herdr list: next's step comes first" "conduct e1" "$(first)"
check "a slow herdr list: next names it skipped" "skipped (over ${LIST_LIMIT} s): herdr agent list" "$(skipped)"

# --- ci_gate's read of the head's check runs is slow: gh run by python, named as ci_gate's.
nextrun "${CHECKS_LIMIT}" slow-runs
soon "a slow ci_gate read: next exits soon after the deadline" "${CHECKS_LIMIT}"
check "a slow ci_gate read is cut, not waited for" "not waited for" "$(waited runs)"
check "a slow ci_gate read: next's step comes first" "wait conduct-e1" "$(first)"
check "a slow ci_gate read: next names it skipped" "skipped (over ${CHECKS_LIMIT} s): ci_gate age" "$(skipped)"

# --- herdr's agent read (conductor_stop's, which next_step and conduct_ready both run on conduct-e1)
# is slow, with ready work: r1 in e1, whose conductor works, and the one-off b1, which none holds.
# next ends soon after the deadline and names the read; conduct_ready, whose reads are cut by then
# too, starts no conductor and names the backlog's, telling the lead to run next again.
printf -- '---\nstatus: ready\nkind: code\nepic: e1\n---\n' > "${p}/docs/stories/r1.md"
printf -- '---\nstatus: ready\nkind: code\n---\n' > "${p}/docs/stories/b1.md"
nextrun "${READ_LIMIT}" slow-read
rm "${p}/docs/stories/r1.md"
soon "a slow herdr agent read: next exits soon after the deadline" "${READ_LIMIT}"
check "a slow herdr agent read is cut, not waited for" "not waited for" "$(waited read)"
check "a slow herdr agent read: next's step comes first" "wait conduct-e1" "$(first)"
check "a slow herdr agent read: next names it skipped" "herdr agent read" "$(named "herdr agent read")"
check "a slow herdr agent read: next starts no conductor, names it and says to run next again" "said" "$(fail_closed)"
check "a slow herdr agent read: next asks herdr for no conductor start" "0" "$(starts)"

# --- A no-agent step while a conductor works decides its starts as a wait does. n1, in e1, started
# and its builder closed with no agent since. The repo's origin read (conductors_queued's) is slow and
# uses the deadline up: the cut origin read is said to be cut, not missing, and b1's conductor is not
# started, but named, never skipped silently.
printf -- '---\nstatus: ready\nkind: code\nepic: e1\n---\n' > "${p}/docs/stories/n1.md"
mkdir -p "${p}-wt/n1"; echo "w:9 n1" >> "${p}/.swarm/state/tab"
printf '2026-10-26T10:00:00Z\tstory\tn1\t-\tok\n2026-10-26T10:30:00Z\tclose\tn1\t-\tok\n' >> "${p}/.swarm/events.tsv"
printf '2026-10-26\tcode\tn1\tclaude\tsonnet\thigh\ts-n1\n' >> "${p}/.swarm/agents.tsv"
nextrun "${ORIGIN_LIMIT}" slow-origin
rm "${p}/docs/stories/n1.md"
soon "a slow origin read: next exits soon after the deadline" "${ORIGIN_LIMIT}"
check "a no-agent step after a slow origin read: next's step comes first" "no-agent n1" "$(first)"
check "a slow origin read is cut, not waited for" "not waited for" "$(waited origin)"
check "a slow origin read: next names it skipped" "gh repo view" "$(named "gh repo view")"
check "a slow origin read: next says the read was cut, not that the origin is missing" \
  "the read of ${p}'s GitHub origin was cut at the report's deadline, so its PRs waiting for a review are unknown" \
  "$(grep -o "the read of .*GitHub origin.*" <<< "${ERR}" || grep 'GitHub origin' <<< "${ERR}" || echo "(none)")"
check "a no-agent step after a slow origin read: next starts no conductor, names it and says to run next again" "said" "$(fail_closed)"

# --- A conductor start slower than the deadline. Every read is fast and the deadline is twice what the
# fast run took, so b1, which no conductor holds, gets the backlog's before the deadline, and its agent
# start takes START_LIMIT + 3 s: it runs to its end past the deadline, is printed and is logged ok.
nextrun "${START_LIMIT}" slow-start
check "a slow conductor start: next's step comes first" "wait conduct-e1" "$(first)"
check "a slow conductor start runs to its end, past the deadline" "start done,start start" "$(sort -u "${ROOT}/slow.log" | paste -sd, -)"
check "a slow conductor start is printed" "started" \
  "$(grep -q '^started: conduct-backlog-.* (swarm.sh conduct --backlog)$' <<< "${OUT}" && echo started || echo "not started: ${OUT}")"
check "a slow conductor start logs its conduct line ok" "--backlog ok" \
  "$(awk -F'\t' '$2 == "conduct" { print $3 " " $5 }' "${p}/.swarm/events.tsv" 2>/dev/null)"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failure(s)"; exit 1; fi
echo "all passed"
