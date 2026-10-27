#!/usr/bin/env bash
# next_time_limit_test.sh — `swarm.sh next` keeps to the report deadline (SWARM_REPORT_SECONDS). With
# herdr's agent list, gh's PR list or ci_gate's gh read (a head's check runs) sleeping past it, next
# exits within the deadline plus SLACK, prints its step first and names the cut read in a `skipped
# (over <n> s):` line; the read started and never finished, so it was cut, not waited for. A
# conductor start slower than the deadline is never cut: it runs to its end, prints its started: line
# and logs its conduct line ok. With every read fast, next prints its queued: line and no skipped: line.
# gh, herdr and claude are stubs on PATH. A slow read logs `<read> start` to slow.log, sleeps, then
# logs `<read> done`, so whether it was cut does not hang on how busy the machine is. The deadline is
# long enough for the fast reads before a slow one on a loaded machine (CI's shards run four files at
# a time); the time check counts swarm.sh's start and its work after the reads in SLACK.
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
LIMIT=10   # the deadline next runs under here, in seconds
SLACK=8    # what next may take past it: its start before the deadline begins, and its work after
SLEEP=60   # a slow read: far past LIMIT + SLACK

# gh: the project's repo, one open PR on story/s1 (head SHA), and that head's check runs, all passed
# 40 minutes ago. A file slow-<read> in ROOT makes that read slow: slow-pr the PR list, slow-runs the
# check runs ci_gate reads.
SHA=1111111111111111111111111111111111111111
DONE="$(python3 -c 'import time; print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 40 * 60)))')"
printf '#!/bin/sh\nF="%s"\nSLEEP=%s\nSHA=%s\nDONE=%s\n' "${ROOT}" "${SLEEP}" "${SHA}" "${DONE}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'EOF'
# slow <read> — when ROOT has slow-<read>: log its start, sleep, log its end.
slow() { [ -f "$F/slow-$1" ] || return 0; echo "$1 start" >> "$F/slow.log"; sleep "$SLEEP"; echo "$1 done" >> "$F/slow.log"; }
path=""; for a in "$@"; do case "$a" in repos/*) path="${a%%\?*}" ;; esac; done
case "$1 $2" in
  "repo view") echo o/svc; exit 0 ;;
  "pr list") slow pr; echo "3 $SHA story/s1"; exit 0 ;;
esac
case "${path}" in
  repos/o/svc/commits/*/check-runs) slow runs
    echo '{"total_count":1,"check_runs":[{"status":"completed","conclusion":"success","completed_at":"'"$DONE"'"}]}' ;;
  repos/o/svc/commits/*/status) echo '{"statuses":[],"total_count":0}' ;;
  *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
# herdr: the agents in ROOT/agents ("<name> <pane>" lines), and a conductor start as next_test's stub
# makes one. slow-list makes the agent list slow; slow-start makes `agent start` take LIMIT + 3 s.
printf '#!/bin/sh\nF="%s"\nSLEEP=%s\nSTART=%s\n' "${ROOT}" "${SLEEP}" "$((LIMIT + 3))" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
slow() { [ -f "$F/slow-$1" ] || return 0; echo "$1 start" >> "$F/slow.log"; sleep "$2"; echo "$1 done" >> "$F/slow.log"; }
echo "$*" >> "$F/herdr.log"
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;
  "workspace list") echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  "tab create") echo '{"result":{"root_pane":{"pane_id":"w:8"}}}' ;;
  "agent start") slow start "$START"; echo "$3 w:8" >> "$F/agents" ;;
  "agent prompt") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent wait") echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent list") slow list "$SLEEP"
    awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
      { printf "%s{\"name\":\"%s\",\"agent_status\":\"working\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
      END { print "]}}" }' "$F/agents" ;;
esac
EOF
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr" "${ROOT}/bin/claude"

# The epic e1 has the code story s1 in review, whose PR #3 is green, and a working conductor,
# conduct-e1, in a pane this project recorded. No story is ready, so next starts no conductor until
# the last case adds one.
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
now() { perl -MTime::HiRes=time -e 'printf "%.3f\n", time'; }
# took <name> <cond> — the last next's run time (TOOK) meets the awk condition on t.
took() {
  if awk -v t="${TOOK}" "BEGIN { exit !($2) }"; then echo "ok   $1 (${TOOK} s)"
  else echo "FAIL $1: $2 with t=${TOOK} s"; fails=$((fails + 1)); fi
}
# nextrun [slow-file] — run next with the stubs and the deadline, with ROOT/<slow-file> there if named;
# OUT holds its stdout, TOOK its seconds, SLOW what slow.log holds (each line once, sorted).
nextrun() {
  local t0
  : > "${ROOT}/slow.log"; [[ -z "${1:-}" ]] || touch "${ROOT}/$1"
  t0="$(now)"
  OUT="$(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 SWARM_REPORT_SECONDS="${LIMIT}" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" next 2> "${ROOT}/next.err")" || true
  TOOK="$(awk -v a="${t0}" -v b="$(now)" 'BEGIN { printf "%.1f", b - a }')"
  [[ -z "${1:-}" ]] || rm "${ROOT}/$1"
  SLOW="$(sort -u "${ROOT}/slow.log" | paste -sd, -)"
}
first() { printf '%s\n' "${OUT%%$'\n'*}"; }
# skipped — next's skipped: line, or (none).
skipped() { grep '^skipped ' <<< "${OUT}" || echo "(none)"; }

# --- Every read fast: the queued: line, and no skipped: line.
nextrun
check "fast reads: next's step comes first" "wait conduct-e1" "$(first)"
check "fast reads: next prints its queued: line" \
  "queued: o/svc #3 story/s1 green 40m with no review on 1111111 (conduct-e1)" "$(grep '^queued: ' <<< "${OUT}" || echo "(none)")"
check "fast reads: next names no skipped read" "(none)" "$(skipped)"

# --- herdr's agent list is slow: next's step is worked out without it (no conductor seen, so the
# gate with s1's PR), and the list is named.
nextrun slow-list
took "a slow herdr list: next exits within the deadline plus ${SLACK} s" "t < ${LIMIT} + ${SLACK}"
check "a slow herdr list is cut, not waited for" "list start" "${SLOW}"
check "a slow herdr list: next's step comes first" "gate" "$(first)"
check "a slow herdr list: next names it skipped" "skipped (over ${LIMIT} s): herdr agent list" "$(skipped)"

# --- gh's PR list is slow: next's step stands, and the list is named.
nextrun slow-pr
took "a slow gh pr list: next exits within the deadline plus ${SLACK} s" "t < ${LIMIT} + ${SLACK}"
check "a slow gh pr list is cut, not waited for" "pr start" "${SLOW}"
check "a slow gh pr list: next's step comes first" "wait conduct-e1" "$(first)"
check "a slow gh pr list: next names it skipped" "skipped (over ${LIMIT} s): gh pr list" "$(skipped)"

# --- ci_gate's read of the head's check runs is slow: gh run by python, named as ci_gate's.
nextrun slow-runs
took "a slow ci_gate read: next exits within the deadline plus ${SLACK} s" "t < ${LIMIT} + ${SLACK}"
check "a slow ci_gate read is cut, not waited for" "runs start" "${SLOW}"
check "a slow ci_gate read: next's step comes first" "wait conduct-e1" "$(first)"
check "a slow ci_gate read: next names it skipped" "skipped (over ${LIMIT} s): ci_gate age" "$(skipped)"

# --- A conductor start slower than the deadline: the ready one-off b1 has no conductor, so next
# starts the backlog's, whose agent start takes LIMIT + 3 s. It runs to its end, is printed and is
# logged ok.
printf -- '---\nstatus: ready\nkind: code\n---\n' > "${p}/docs/stories/b1.md"
nextrun slow-start
check "a slow conductor start runs to its end" "start done,start start" "${SLOW}"
check "a slow conductor start: next's step comes first" "wait conduct-e1" "$(first)"
check "a slow conductor start is printed" "started" \
  "$(grep -q '^started: conduct-backlog-.* (swarm.sh conduct --backlog)$' <<< "${OUT}" && echo started || echo "not started: ${OUT}")"
check "a slow conductor start logs its conduct line ok" "--backlog ok" \
  "$(awk -F'\t' '$2 == "conduct" { print $3 " " $5 }' "${p}/.swarm/events.tsv" 2>/dev/null)"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failure(s)"; exit 1; fi
echo "all passed"
