#!/usr/bin/env bash
# next_watch_cache_test.sh — `swarm.sh next`'s queued: lines take the CI reads a watch kept in the poll
# cache (SWARM_POLL_CACHE on queued_line's ci_gate age call, which next_queued runs through report_read).
# A conductor's watch --epic polls once and queues PR #3's head, green 40 minutes; next then runs within
# the cache's max age (59 s, at sleep scale 1) and reads none of that head's check runs or status from
# GitHub, printing the queued: line it prints with the cache off. With the cache off (a sleep scale
# under which the max age is 0) next reads both itself. A head that moved after the watch's poll is
# read fresh by next. The watch's queued <sha7> line in watch-seen is dropped before next runs, as it
# would be for a head the watch's conductor has not had sent.
# gh, herdr and claude are stubs on PATH. gh logs "<caller> <args>" to gh.log, the caller being w for
# the watch and n for next (WATCHER); its head is ${ROOT}/head. herdr lists one working conductor,
# conduct-e1, in a pane this project recorded.
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
ON=1        # the sleep scale with the cache on: a 60 s poll, a max age of 59 s
OFF=0.02    # with it off: a 1.2 s poll, a max age of 0
GUARD=120   # the most a watch or next run may take before it is killed
A1=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; A2=cccccccccccccccccccccccccccccccccccccccc

# gh: the project's repo; PR #3 on story/s1 at the head in ROOT/head, open and mergeable, in next's
# list (gh pr list, its -q applied) and in the watch's (the pulls list, its -q applied); and that head's
# check runs, all passed 40 minutes to the second before gh is asked. ci_gate counts whole minutes, so
# it counts 40 on a fresh read and on a kept one, which is under 59 s old when next takes it.
printf '#!/bin/sh\nF="%s"\n' "${ROOT}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'EOF'
echo "${WATCHER:--} $*" >> "$F/gh.log"
head="$(cat "$F/head")"
case "$*" in
  "repo view"*) echo o/svc ;;
  "pr list"*) echo "3 ${head} story/s1" ;;
  "api --paginate repos/o/svc/pulls?"*) echo "3 ${head} story/s1 0" ;;
  "api repos/o/svc/pulls/3 "*) echo MERGEABLE ;;
  "api --paginate repos/o/svc/commits/${head}/check-runs"*)
    DONE="$(perl -MPOSIX=strftime -e 'print strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time - 40 * 60))')"
    echo '{"total_count":1,"check_runs":[{"name":"test","status":"completed","conclusion":"success","completed_at":"'"$DONE"'"}]}' ;;
  "api --paginate repos/o/svc/commits/${head}/status"*) echo '{"statuses":[],"total_count":0}' ;;
  *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
# herdr: conduct-e1, working, in pane w:7.
cat > "${ROOT}/bin/herdr" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;
  "agent list") echo '{"result":{"agents":[{"name":"conduct-e1","agent_status":"working","pane_id":"w:7"}]}}' ;;
  "workspace list") echo '{"result":{"workspaces":[]}}' ;;
esac
EOF
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr" "${ROOT}/bin/claude"

# The epic e1 has the code story s1 in review, PR #3, and the working conductor conduct-e1. No story is
# ready, so next starts no conductor.
p="${ROOT}/proj"; SEEN="${p}/.swarm/state/watch-seen"; CACHE="${p}/.swarm/poll-cache"
mkdir -p "${p}/.claude/swarm" "${p}/docs/epics" "${p}/docs/stories" "${p}/.swarm/briefs" "${p}/.swarm/state"
: > "${p}/.claude/swarm/config"
git -C "${p}" init -q && git -C "${p}" remote add origin https://github.com/o/svc
printf -- '---\nstatus: active\n---\n' > "${p}/docs/epics/e1.md"
printf -- '---\nstatus: review\nkind: code\nepic: e1\nprs: https://github.com/o/svc/pull/3\n---\n' > "${p}/docs/stories/s1.md"
touch "${p}/.swarm/briefs/conduct-e1.md"; echo "w:7 conduct-e1" > "${p}/.swarm/state/tab"

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
# fresh <sha> — a cold start: no cache, no gh log, PR #3 at <sha>, which watch-seen has said opened and
# finished (done), so the watch's one poll queues it.
fresh() {
  rm -rf "${CACHE}"; : > "${ROOT}/gh.log"; echo "$1" > "${ROOT}/head"
  printf 'opened o/svc#3\ndone %s\n' "$1" > "${SEEN}"
}
# watch1 <scale> — one swarm.sh watch --epic e1 at sleep scale <scale>, to its return; its output in
# WOUT. Then watch-seen forgets the queued head, so next does not leave it out.
watch1() {
  WOUT="$(cd "${p}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" WATCHER=w SWARM_SLEEP_SCALE="$1" \
    perl -e 'alarm shift; exec @ARGV' "${GUARD}" bash "${SWARM}" watch --epic e1 2>&1)" || true
  grep -v '^queued ' "${SEEN}" > "${SEEN}.new" || true; mv "${SEEN}.new" "${SEEN}"
}
# next1 <scale> — swarm.sh next at sleep scale <scale> inside herdr; its queued: line in QUEUED.
next1() {
  local out
  out="$(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" WATCHER=n SWARM_SLEEP_SCALE="$1" \
    SWARM_REPORT_SECONDS=600 perl -e 'alarm shift; exec @ARGV' "${GUARD}" bash "${SWARM}" next 2>/dev/null)" || true
  QUEUED="$(grep '^queued: ' <<< "${out}" || echo "(none)")"
}
# reads <caller> <sha> — "<check-runs reads> <status reads>" ci_gate made for <sha>, as <caller>.
reads() {
  echo "$(grep -c "^$1 api --paginate repos/o/svc/commits/$2/check-runs" "${ROOT}/gh.log" || true)" \
    "$(grep -c "^$1 api --paginate repos/o/svc/commits/$2/status" "${ROOT}/gh.log" || true)"
}
line() { echo "queued: o/svc #3 story/s1 green 40m with no review on ${1:0:7} (conduct-e1)"; }

# --- The cache off: the watch and next each read the head's check runs and status themselves.
fresh "${A1}"; watch1 "${OFF}"; next1 "${OFF}"
check "cache off: the watch queues #3" "queued: o/svc #3 story/s1 green 40m with no review on ${A1:0:7}" "${WOUT}"
check "cache off: the watch reads the check runs and status" "1 1" "$(reads w "${A1}")"
check "cache off: next reads the check runs and status itself" "1 1" "$(reads n "${A1}")"
check "cache off: next prints its queued: line" "$(line "${A1}")" "${QUEUED}"
OFF_LINE="${QUEUED}"

# --- The cache on: next, within the max age of the watch's poll, takes the watch's reads.
fresh "${A1}"; watch1 "${ON}"; next1 "${ON}"
check "cache on: the watch queues #3" "queued: o/svc #3 story/s1 green 40m with no review on ${A1:0:7}" "${WOUT}"
check "cache on: the watch reads the check runs and status" "1 1" "$(reads w "${A1}")"
check "cache on: next reads neither the check runs nor the status" "0 0" "$(reads n "${A1}")"
check "cache on: next's queued: line is the one it prints with the cache off" "${OFF_LINE}" "${QUEUED}"

# --- The cache on, and #3's head moves from A1 to A2 after the watch's poll: next reads A2's check runs
# and status from GitHub, none of A1's, and queues A2 as it would with the cache off.
fresh "${A1}"; watch1 "${ON}"; echo "${A2}" > "${ROOT}/head"; next1 "${ON}"
check "moved head: next reads A2's check runs and status from GitHub" "1 1" "$(reads n "${A2}")"
check "moved head: next reads nothing of A1's" "0 0" "$(reads n "${A1}")"
check "moved head: next queues A2" "$(line "${A2}")" "${QUEUED}"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failure(s)"; exit 1; fi
echo "all passed"
