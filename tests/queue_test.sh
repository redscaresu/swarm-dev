#!/usr/bin/env bash
# queue_test.sh — a story PR green and mergeable for queue_minutes with no review agent on its head:
# `watch` returns `queued: <repo> #<n> <branch> ...`, once per head, and `next` prints the same line
# under a working conductor's wait for a head watch has not reported. With a review agent on that head
# (.swarm/reviews/<slug>.head), short of queue_minutes, for a lead story, or with a check or status
# that is not green on any page (ci_gate's rule), neither does; `status` and `dash` never look. One
# repo next cannot resolve is warned of, and the others still count. gh, herdr and claude are stubs on
# PATH; gh logs every call to gh.log.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
# No real Claude config or session is read: claude's state lives under ROOT.
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
mkdir -p "${ROOT}/bin"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${ROOT}/bin/claude"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# gh answers from fixture files: the PR list, each head's check runs (runs-<sha>.json, which may hold
# several pages) and commit statuses (status-<sha>.json, else none).
printf '#!/bin/sh\nF="%s"\n' "${ROOT}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'EOF'
echo "$*" >> "$F/gh.log"
q=""; r=""; path=""; for a in "$@"; do [ "$p" = -q ] && q="$a"; [ "$p" = -R ] && r="$a"; case "$a" in repos/*) path="${a%%\?*}" ;; esac; p="$a"; done
case "$1 $2" in
  "repo view") echo "${3#https://github.com/}"; exit 0 ;;
  "pr list")   f="$F/prlist.json"; [ "$r" = o/svc ] || f="$F/prlist-${r#o/}.json"; jq -r "$q" "$f"; exit 0 ;;
esac
case "${path}" in
  repos/o/*/commits/*/check-runs) f="$F/runs-$(basename "${path%/check-runs}").json"
    if [ -n "$q" ]; then jq -r "$q" "$f" | head -1; else cat "$f"; fi ;;
  repos/o/*/commits/*/status) f="$F/status-$(basename "${path%/status}").json"
    if [ -f "$f" ]; then cat "$f"; else echo '{"statuses":[],"total_count":0}'; fi ;;
  *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
# herdr lists a working conductor for e1, in a pane this project recorded.
printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"agents\":[{\"name\":\"conduct-e1\",\"agent_status\":\"working\",\"pane_id\":\"w:7\"}]}}'" > "${ROOT}/bin/herdr"
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr" "${ROOT}/bin/claude"

# e1 has the code story s1 (PR #3, head h1) and the lead story l1 (PR #4, head h2), both green.
p="${ROOT}/proj"
mkdir -p "${p}/.claude/swarm" "${p}/docs/epics" "${p}/docs/stories" "${p}/.swarm/briefs" "${p}/.swarm/state" "${p}/.swarm/reviews"
: > "${p}/.claude/swarm/config"
git -C "${p}" init -q && git -C "${p}" remote add origin https://github.com/o/svc
printf -- '---\nstatus: active\n---\n' > "${p}/docs/epics/e1.md"
printf -- '---\nstatus: ready\nkind: code\nepic: e1\n---\n' > "${p}/docs/stories/s1.md"
printf -- '---\nstatus: ready\nkind: lead\nepic: e1\n---\n' > "${p}/docs/stories/l1.md"
touch "${p}/.swarm/briefs/conduct-e1.md"; echo "w:7 conduct-e1" > "${p}/.swarm/state/tab"
# prs <mergeable> — the open PRs, #3 with that mergeable.
prs() {
  echo "[{\"number\": 3, \"headRefName\": \"story/s1\", \"headRefOid\": \"h1\", \"mergeable\": \"$1\", \"updatedAt\": \"2026-01-01T00:00:00Z\"},
   {\"number\": 4, \"headRefName\": \"story/l1\", \"headRefOid\": \"h2\", \"mergeable\": \"MERGEABLE\", \"updatedAt\": \"2026-01-01T00:00:00Z\"}]" > "${ROOT}/prlist.json"
}
prs MERGEABLE
ago() { python3 -c 'import sys, time; print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 60 * int(sys.argv[1]))))' "$1"; }
# green <minutes> — h1's and h2's checks all passed, the last <minutes> ago, with no commit status;
# watch has already reported them finished, so only a queued line can wake it.
green() {
  local sha
  for sha in h1 h2; do
    echo "{\"total_count\":2,\"check_runs\":[{\"status\":\"completed\",\"conclusion\":\"success\",\"completed_at\":\"2020-01-01T00:00:00Z\"},{\"status\":\"completed\",\"conclusion\":\"skipped\",\"completed_at\":\"$(ago "$1")\"}]}" > "${ROOT}/runs-${sha}.json"
    rm -f "${ROOT}/status-${sha}.json"
  done
  printf 'done h1\ndone h2\n' > "${p}/.swarm/state/watch-seen"
}
# watchrun — what watch --epic e1 printed, or "(still watching)" if it has not returned in 10 seconds.
# gh.log then holds only this run's calls.
watchrun() {
  local pid
  : > "${ROOT}/gh.log"
  (cd "${p}" && exec env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" watch --epic e1 > "${ROOT}/watch.out" 2>&1) &
  pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do kill -0 "${pid}" 2>/dev/null || break; sleep 0.5; done
  if kill -0 "${pid}" 2>/dev/null; then pkill -P "${pid}" 2>/dev/null || true; kill "${pid}" 2>/dev/null || true; wait "${pid}" 2>/dev/null || true; echo "(still watching)"; return; fi
  cat "${ROOT}/watch.out"
}
# nextq — next's queued lines (none: "(none)"), after checking it still waits on the conductor; its
# stderr goes to next.err.
nextq() {
  local out
  out="$(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" next 2> "${ROOT}/next.err")"
  [[ "${out%%$'\n'*}" == "wait conduct-e1" ]] || { echo "next did not wait: ${out}"; return; }
  grep '^queued: ' <<< "${out}" || echo "(none)"
}
calls() { grep -c "$1" "${ROOT}/gh.log" || true; }
# extra_lists — gh pr list calls other than watch's own poll (which alone asks for updatedAt).
extra_lists() { grep 'pr list' "${ROOT}/gh.log" | grep -vc updatedAt || true; }
Q31="queued: o/svc #3 story/s1 green 31m with no review on h1"

green 31
check "watch reports a PR green and mergeable for 31 minutes with no review agent, naming its repo, branch and head" "${Q31}" "$(watchrun)"
check "watch reports a queued head once, lists PRs only in its own poll, and reads no CI for a head it has reported" "(still watching)|0|0" \
  "$(watchrun)|$(extra_lists)|$(calls 'commits/h1/')"
check "next leaves out a head watch has reported" "(none)" "$(nextq)"
green 31
check "next prints the queued line under the conductor's wait, and none for the lead story's green PR" "${Q31}" "$(nextq)"
: > "${ROOT}/gh.log"
(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" status >/dev/null 2>&1) || true
(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash >/dev/null 2>&1) || true
check "status and dash, which read next_step, judge no PR queued (no CI read)" "0" "$(calls 'commits/')"

echo h1 > "${p}/.swarm/reviews/s1.head"
green 31
check "with a review agent on that head, watch does not report it, and reads no CI for it" "(still watching)|0" "$(watchrun)|$(calls 'commits/h1/')"
check "with a review agent on that head, next prints no queued line" "(none)" "$(nextq)"
echo h0 > "${p}/.swarm/reviews/s1.head"
check "a review agent on an earlier head does not count" "${Q31}" "$(nextq)"
rm "${p}/.swarm/reviews/s1.head"

green 29
check "at 29 minutes, watch does not report it" "(still watching)" "$(watchrun)"
check "at 29 minutes, next prints no queued line" "(none)" "$(nextq)"
echo "queue_minutes = 20" > "${p}/.claude/swarm/config"
check "queue_minutes sets the threshold" "queued: o/svc #3 story/s1 green 29m with no review on h1" "$(nextq)"
: > "${p}/.claude/swarm/config"

green 31
prs CONFLICTING
check "a PR that is not mergeable is not queued" "(none)" "$(nextq)"
prs MERGEABLE
sed -i.bak 's/"skipped"/"failure"/' "${ROOT}/runs-h1.json"
check "a PR with a failed check run is not queued" "(none)" "$(nextq)"
green 31
echo '{"total_count":1,"statuses":[{"state":"pending","context":"ext","updated_at":"2020-01-01T00:00:00Z"}]}' > "${ROOT}/status-h1.json"
check "a PR with a pending commit status is not queued" "(none)" "$(nextq)"
echo "{\"total_count\":1,\"statuses\":[{\"state\":\"success\",\"context\":\"ext\",\"updated_at\":\"$(ago 10)\"}]}" > "${ROOT}/status-h1.json"
check "a commit status that turned green 10 minutes ago makes the head green for 10" "(none)" "$(nextq)"
green 31
echo "{\"total_count\":2,\"check_runs\":[{\"status\":\"completed\",\"conclusion\":\"success\",\"completed_at\":\"$(ago 31)\"}]}
{\"total_count\":2,\"check_runs\":[{\"status\":\"in_progress\",\"conclusion\":null,\"completed_at\":null}]}" > "${ROOT}/runs-h1.json"
check "a check run still pending on a later page keeps the PR off the queue" "(none)" "$(nextq)"
echo '{"total_count":0,"check_runs":[]}' > "${ROOT}/runs-h1.json"
check "a head with no check runs is not green, so not queued" "(none)" "$(nextq)"

# Two more repos: gone, which next cannot resolve, and zsvc after it, with a green PR #9 (head h9). The
# bad one is warned of on stderr, and the repos on either side of it still count.
green 31
cp "${ROOT}/runs-h1.json" "${ROOT}/runs-h9.json"
git init -q "${ROOT}/zsvc" && git -C "${ROOT}/zsvc" remote add origin https://github.com/o/zsvc
echo '[{"number": 9, "headRefName": "story/s3", "headRefOid": "h9", "mergeable": "MERGEABLE"}]' > "${ROOT}/prlist-zsvc.json"
printf -- '---\nstatus: ready\nkind: code\nepic: e1\nrepo: gone\n---\n' > "${p}/docs/stories/s2.md"
printf -- '---\nstatus: ready\nkind: code\nepic: e1\nrepo: zsvc\n---\n' > "${p}/docs/stories/s3.md"
check "a repo next cannot resolve is warned of, and every other repo's queued line still prints" \
  "${Q31}"$'\n'"queued: o/zsvc #9 story/s3 green 31m with no review on h9|yes" \
  "$(nextq)|$(if grep -q '^warning: watch gone: .*its PRs waiting for a review are unknown' "${ROOT}/next.err"; then echo yes; else cat "${ROOT}/next.err"; fi)"
rm "${p}/docs/stories/s2.md" "${p}/docs/stories/s3.md"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
