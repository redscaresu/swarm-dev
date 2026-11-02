#!/usr/bin/env bash
# watch_cache_test.sh — concurrent swarm.sh watch runs on one repo share each poll's reads through the poll
# cache (bin/lib/poll_cache.py's command form, and SWARM_POLL_CACHE on queued_line's ci_gate age): one
# open-PR list read and one check-runs read per head per poll between two watch --epic runs, two of each
# with the cache off; each watch still reads every PR's mergeable state itself; a failed list read is not
# kept, so the other watch reads again, and it is said as before; a head that moves is read fresh; the
# ci_gate age reads of a finished, unqueued head are shared; and a wait-pr and a watch on one head each
# read their own output form and print what they print with the cache off.
# The watches run in rounds: a sleep stub on PATH logs each watch's nap (its scaled 60 s, NAP) to
# ${FX}/naps and holds the k-th until ${FX}/allowed is above k, then sleeps it (or, with NAP_SKIP set,
# returns at once), so the watches let go together poll together. gh is a stub that logs "<watcher> <args>" to gh.log for every call: the list
# answers prlist.json; watch's filtered check-runs read is "1 1" (pending), or "1 0" with ${FX}/green;
# ci_gate's pages answer one check run, completed now with ${FX}/green; with ${FX}/listfail the first
# list read fails with HTTP 403. The rest answers wait-pr's reads, as tests/wait_pr_cache_test.sh's does.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
REAL_SLEEP="$(command -v sleep)"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
PIDS=()
# The watches left running when the file ends early are killed, then the temp dir goes.
cleanup() { [[ ${#PIDS[@]} -eq 0 ]] || kill "${PIDS[@]}" 2>/dev/null || true; rm -rf "${ROOT}"; }
trap cleanup EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; FX="${ROOT}/fx"; CACHE="${P}/.swarm/poll-cache"; SEEN="${P}/.swarm/state/watch-seen"
A1=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; A2=cccccccccccccccccccccccccccccccccccccccc
B1=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
ON=0.05    # the sleep scale with the cache on: a 3 s poll, a max age of 2 s
OFF=0.02   # with it off: a 1.2 s poll, a max age of 0
# Epic e's stories a and b, built in the project, whose origin is o/svc.
mkdir -p "${P}/.claude/swarm" "${P}/docs/epics" "${P}/docs/stories" "${ROOT}/bin"; : > "${P}/.claude/swarm/config"
git -C "${P}" init -q && git -C "${P}" remote add origin https://github.com/o/svc
printf -- '---\nstatus: active\n---\n' > "${P}/docs/epics/e.md"
printf -- '---\nstatus: ready\nkind: code\nepic: e\n---\n' > "${P}/docs/stories/a.md"
printf -- '---\nstatus: ready\nkind: code\nepic: e\n---\n' > "${P}/docs/stories/b.md"

printf '#!/usr/bin/env bash\nFX="%s"; LOG="%s"\n' "${FX}" "${ROOT}/gh.log" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "${WATCHER:--} $*" >> "${LOG}"
a="$*"; q=""; p=""
for x in "$@"; do [ "${p}" != -q ] || q="${x}"; p="${x}"; done
now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
case "${a}" in
  "repo view"*) echo o/svc ;;
  "pr view"*) echo "$(cat "${FX}/head") MERGEABLE main OPEN 1" ;;
  "api --paginate repos/o/svc/pulls?"*)
    if [ -e "${FX}/listfail" ] && mkdir "${FX}/listfailed" 2>/dev/null; then
      echo '{"message":"Forbidden"}'; echo "gh: Forbidden (HTTP 403)" >&2; exit 1
    fi
    jq -r "${q}" "${FX}/prlist.json" ;;
  "api repos/o/svc/pulls/"*) echo MERGEABLE ;;
  "api repos/o/svc/commits/"*/check-runs*) if [ -e "${FX}/green" ]; then echo '1 0'; else echo '1 1'; fi ;;
  *check-runs*)
    if [ -e "${FX}/green" ]; then s=completed c='"success"'; else s=in_progress c=null; fi
    printf '{"total_count":1,"check_runs":[{"name":"test","status":"%s","conclusion":%s,"completed_at":"%s"}]}\n' "${s}" "${c}" "${now}" ;;
  */status*) echo '{"total_count":0,"statuses":[]}' ;;
  *actions/runs*) sha="${a#*head_sha=}"; sha="${sha%%&*}"
    printf '{"total_count":1,"workflow_runs":[{"id":1,"path":".github/workflows/ci.yml","event":"pull_request","head_sha":"%s","status":"completed","conclusion":"success"}]}\n' "${sha}" ;;
  *actions/workflows*) echo '{"total_count":0,"workflows":[]}' ;;
  *commits/refs/pull/1/merge) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  *"contents/.github/workflows?ref="*) echo '[{"type":"file","name":"ci.yml","path":".github/workflows/ci.yml"}]' ;;
  *contents/.github/workflows/ci.yml*) printf 'name: ci\non: pull_request\njobs: {}\n' ;;
  *compare/main...*) echo '{"files":[{"filename":"bin/swarm.sh","status":"modified"}]}' ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
printf '#!/bin/sh\nFX="%s"; REAL="%s"\n' "${FX}" "${REAL_SLEEP}" > "${ROOT}/bin/sleep"
cat >> "${ROOT}/bin/sleep" <<'STUB'
if [ -n "${WATCHER:-}" ] && [ "$1" = "${NAP:-}" ]; then
  echo "${WATCHER}" >> "${FX}/naps"
  k=$(grep -cx "${WATCHER}" "${FX}/naps")
  while [ "${k}" -ge "$(cat "${FX}/allowed")" ]; do
    kill -0 "${PPID}" 2>/dev/null || exit 0
    "${REAL}" 0.05
  done
  [ -z "${NAP_SKIP:-}" ] || exit 0
fi
exec "${REAL}" "$@"
STUB
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/sleep"

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }

# prlist <sha of #1> — the open PRs: #1 story/a at <sha>, #2 story/b at B1.
prlist() {
  local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '[{"number":1,"head":{"ref":"story/a","sha":"%s"},"updated_at":"%s"},{"number":2,"head":{"ref":"story/b","sha":"%s"},"updated_at":"%s"}]\n' \
    "$1" "${now}" "${B1}" "${now}" > "${FX}/prlist.json"
}
# fresh [seen line]... — a cold start: no cache, no logs, both PRs at their first heads, pending, already
# said opened, and each <seen line> in watch-seen; no nap let go.
fresh() {
  rm -rf "${FX}" "${CACHE}" "${P}/.swarm/state"; mkdir -p "${FX}" "${P}/.swarm/state"; : > "${ROOT}/gh.log"
  : > "${FX}/naps"; echo 1 > "${FX}/allowed"; echo "${A1}" > "${FX}/head"; prlist "${A1}"
  printf 'opened o/svc#1\nopened o/svc#2\n' > "${SEEN}"
  [[ $# -eq 0 ]] || printf '%s\n' "$@" >> "${SEEN}"
}
# calls <ERE> [watcher] — the gh calls in gh.log whose args start with <ERE> (of <watcher> alone, if named).
calls() { grep -cE "^${2:-[^ ]+} $1" "${ROOT}/gh.log" || true; }
LIST='api --paginate repos/o/svc/pulls[?]state=open'
merge_reads() { calls "api repos/o/svc/pulls/$1 " "${2:-}"; }   # watch_mergeable's reads of PR <n>
runs_q() { calls "api repos/o/svc/commits/$1/check-runs" "${2:-}"; }   # watch's filtered check-runs reads
runs_p() { calls "api --paginate repos/o/svc/commits/$1/check-runs" "${2:-}"; }   # ci_gate's
status_p() { calls "api --paginate repos/o/svc/commits/$1/status" "${2:-}"; }
naps() { grep -cx "$1" "${FX}/naps" || true; }
# await <seconds> <command>... — runs <command> every 0.1 s until it succeeds; fails after <seconds>.
await() {
  local end=$((SECONDS + $1)); shift
  until "$@"; do (( SECONDS < end )) || return 1; sleep 0.1; done
}
both_napped() { [[ $(naps a) -ge $1 && $(naps b) -ge $1 ]]; }
# watch <watcher> <scale> [VAR=value]... [arg]... — swarm.sh watch [arg]... in the background as <watcher>,
# at sleep scale <scale>, with each VAR set; its output in ${ROOT}/out.<watcher>, its pid in LAST.
watch() {
  local w="$1" scale="$2" nap envs=(); shift 2
  while [[ "${1:-}" == [A-Z]*=* ]]; do envs+=("$1"); shift; done
  nap="$(awk -v k="${scale}" 'BEGIN { printf "%.3f", 60 * k }')"
  (cd "${P}" && exec env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" WATCHER="${w}" NAP="${nap}" \
    SWARM_SLEEP_SCALE="${scale}" ${envs[@]+"${envs[@]}"} bash "${SWARM}" watch "$@" > "${ROOT}/out.${w}" 2>&1) &
  LAST=$!; PIDS+=("${LAST}")
}
# pair <scale> — watch --epic e as a and b, at <scale>, both held at their first nap.
pair() {
  watch a "$1" --epic e; pa=${LAST}; watch b "$1" --epic e; pb=${LAST}
  await 60 both_napped 1 || echo "warning: the watches did not finish their first poll in 60 s"
}
# round <n> — lets both watches poll until their <n>-th nap.
round() { echo "$1" > "${FX}/allowed"; await 60 both_napped "$1" || echo "warning: the watches did not reach nap $1 in 60 s"; }
# stop_pair — ends both watches.
stop_pair() { kill "${pa}" "${pb}" 2>/dev/null || true; wait "${pa}" "${pb}" 2>/dev/null || true; }
# snap — the counts so far: the list, each first head's filtered check runs, each PR's mergeable reads.
snap() { echo "$(calls "${LIST}") $(runs_q "${A1}") $(runs_q "${B1}") $(merge_reads 1) $(merge_reads 2)"; }
# since <counter> <before> — <counter>'s counts (snap's or ages') less <before>'s.
since() {
  local b n i out=""
  read -r -a b <<< "$2"; read -r -a n <<< "$("$1")"
  for i in "${!n[@]}"; do out="${out:+${out} }$((n[i] - b[i]))"; done
  echo "${out}"
}
# ages — the ci_gate reads so far: A1's check runs and status, B1's check runs and status.
ages() { echo "$(runs_p "${A1}") $(status_p "${A1}") $(runs_p "${B1}") $(status_p "${B1}")"; }

# --- Two watch --epic runs, both PRs pending, let go together for three polls after the first: with the
# cache on, one list read and one check-runs read per head per poll between them; each reads both PRs'
# mergeable state itself, every poll. With the cache off, two of each.
fresh; pair "${ON}"; before="$(snap)"
round 2; round 3; round 4
is "cache on: per poll, one list and one check-runs read per head between them; each reads both mergeables" \
  "3 3 3 6 6" "$(since snap "${before}")"
is "cache on: watch_mergeable reads pulls/1 itself on every poll (a, b: polls a, b)" "$(naps a) $(naps b)" \
  "$(merge_reads 1 a) $(merge_reads 1 b)"
check "cache on: the list's and the check runs' reads are kept" test -n "$(grep -l "pulls?state=open" "${CACHE}"/*.json 2>/dev/null)"
check "cache on: no mergeable read is kept" test -z "$(grep -l '"repos/o/svc/pulls/[12]"' "${CACHE}"/*.json 2>/dev/null)"
check "cache on: neither watch said anything" test ! -s "${ROOT}/out.a" -a ! -s "${ROOT}/out.b"
stop_pair

fresh; pair "${OFF}"; before="$(snap)"
round 2; round 3; round 4
is "cache off: per poll, two of each" "6 6 6 6 6" "$(since snap "${before}")"
check "cache off: nothing is kept" test ! -e "${CACHE}"
stop_pair

# --- The first list read fails (HTTP 403): it is not kept, so the other watch reads the list again, and
# the failure is said as before, once.
fresh; touch "${FX}/listfail"; pair "${ON}"
is "failed list: two list reads, the failed one and the other watch's own" 2 "$(calls "${LIST}")"
is "failed list: 'gh cannot list' is said once, gh's error last" 1 \
  "$(cat "${ROOT}/out.a" "${ROOT}/out.b" | grep -cx "swarm: watch: gh cannot list o/svc's open PRs: gh: Forbidden (HTTP 403)" || true)"
check "failed list: the failure is not kept" test -z "$(grep -l Forbidden "${CACHE}"/*.json 2>/dev/null)"
stop_pair

# --- #1's head moves from A1 to A2 between polls of one watch (scale 0.5: a max age of 29 s, its nap
# skipped once let go), while its first poll's entry for A1's check runs (pending) is still fresh: its
# next poll reads A2's from GitHub (green) and says them finished. The list's entry is dropped, as it
# would be past the max age, so that poll lists A2.
fresh; echo 1 > "${FX}/allowed"; watch c 0.5 NAP_SKIP=1 --epic e; pc=${LAST}
c_napped() { [[ $(naps c) -ge 1 ]]; }
await 60 c_napped || echo "warning: the watch did not finish its first poll in 60 s"
is "moved head: the first poll reads A1's check runs from GitHub" 1 "$(runs_q "${A1}")"
check "moved head: A1's pending check runs are kept" test -n "$(grep -l "commits/${A1}/check-runs" "${CACHE}"/*.json 2>/dev/null)"
while IFS= read -r f; do rm -f "${f}"; done < <(grep -l 'pulls?state=open' "${CACHE}"/*.json 2>/dev/null || true)
prlist "${A2}"; touch "${FX}/green"; echo 2 > "${FX}/allowed"
c_done() { ! kill -0 "${pc}" 2>/dev/null || [[ $(naps c) -ge 2 ]]; }
await 60 c_done || echo "warning: the watch neither returned nor reached its second nap in 60 s"
kill "${pc}" 2>/dev/null || true; wait "${pc}" 2>/dev/null || true
is "moved head: the next poll reads A2's check runs from GitHub" 1 "$(runs_q "${A2}")"
is "moved head: and says A2's checks finished" "o/svc #1 story/a checks finished on ${A2:0:7}" "$(cat "${ROOT}/out.c")"

# --- Both heads finished and reported (done), green under queue_minutes, so not queued: each poll's
# queued_line runs ci_gate age on each, whose check-runs and status reads the watches share; with the
# cache off each reads its own.
fresh "done ${A1}" "done ${B1}"; touch "${FX}/green"; pair "${ON}"
before="$(ages)"
round 2; round 3
is "ci_gate age, cache on: one check-runs and one status read per head per poll between them" "2 2 2 2" "$(since ages "${before}")"
check "ci_gate age, cache on: neither watch said anything" test ! -s "${ROOT}/out.a" -a ! -s "${ROOT}/out.b"
stop_pair
fresh "done ${A1}" "done ${B1}"; touch "${FX}/green"; pair "${OFF}"
before="$(ages)"
round 2; round 3
is "ci_gate age, cache off: two of each per head per poll" "4 4 4 4" "$(since ages "${before}")"
stop_pair

# --- A wait-pr and a watch on #1's head A1, green: each reads its own output form of the check runs
# (wait-pr ci_gate's raw pages, watch's filtered line) while the other's is kept, and prints what it
# prints with the cache off. The watch runs at scale 0.5 (a max age of 29 s), the wait-pr polls every 20 s
# (19 s), so each would take the other's entry if the key were the path alone.
# waitpr <retry> — swarm.sh wait-pr --head A1 on #1, polling every 20 s and retrying after <retry> s (1: the
# cache off); its output in ${ROOT}/out.w, its exit in rc.
waitpr() {
  rc=0
  (cd "${P}" && exec env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" WATCHER=w SWARM_MERGE_POLL=20 \
    SWARM_WAIT_PR_RETRY="$1" SWARM_MERGE_CI_SECONDS=120 bash "${SWARM}" wait-pr --head "${A1}" \
    https://github.com/o/svc/pull/1 > "${ROOT}/out.w" 2>&1) || rc=$?
}
# watch1 <scale> — one watch --epic e as c until it returns; its output in ${ROOT}/out.c, its exit in rc.
watch1() { watch c "$1" --epic e; rc=0; wait "${LAST}" || rc=$?; }
fresh; touch "${FX}/green"; echo 9 > "${FX}/allowed"
watch1 "${OFF}"; off_c="${rc}|$(cat "${ROOT}/out.c")"
waitpr 1; off_w="${rc}|$(cat "${ROOT}/out.w")"
is "wait-pr and watch, cache off: watch says #1's checks finished" "0|o/svc #1 story/a checks finished on ${A1:0:7}" "${off_c}"
check "wait-pr and watch, cache off: wait-pr ends green" grep -q '^green:' "${ROOT}/out.w"
# The watch first: its filtered read is kept, and wait-pr then reads the raw pages from GitHub.
fresh; touch "${FX}/green"; echo 9 > "${FX}/allowed"
watch1 0.5; on_c="${rc}|$(cat "${ROOT}/out.c")"; : > "${ROOT}/gh.log"
waitpr 20
is "watch then wait-pr, cache on: wait-pr prints what it prints with the cache off" "${off_w}" "${rc}|$(cat "${ROOT}/out.w")"
is "watch then wait-pr, cache on: wait-pr read the raw check runs from GitHub" 1 "$(runs_p "${A1}" w)"
is "watch then wait-pr, cache on: the watch printed what it prints with the cache off" "${off_c}" "${on_c}"
# wait-pr first: its raw pages are kept, and the watch then reads its filtered line from GitHub.
fresh; touch "${FX}/green"; echo 9 > "${FX}/allowed"
waitpr 20; : > "${ROOT}/gh.log"
watch1 0.5
is "wait-pr then watch, cache on: the watch prints what it prints with the cache off" "${off_c}" "${rc}|$(cat "${ROOT}/out.c")"
is "wait-pr then watch, cache on: the watch read its filtered check runs from GitHub" 1 "$(runs_q "${A1}" c)"

if [[ ${fails} -eq 0 ]]; then echo "all watch poll-cache tests passed"; else echo "${fails} watch poll-cache test(s) failed"; exit 1; fi
