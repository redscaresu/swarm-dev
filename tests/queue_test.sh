#!/usr/bin/env bash
# queue_test.sh — a story PR green and mergeable for queue_minutes with no review agent on its head:
# `watch` returns `queued: <repo> #<n> <branch> ...`, once per head, and `next` prints the same line
# after its step's why for every working conductor, naming it, for a head not yet sent (by watch or by
# a tell note). With a live review agent on that head (.swarm/reviews/<slug>.head) or a passing findings
# file for it, short of queue_minutes, for a lead story, or with a check or status that is not green on
# any page (ci_gate's rule), neither does; `status` and `dash` never look. One repo next cannot resolve
# is warned of, and the others still count, under bash 3.2 too. gh, herdr and claude are stubs on
# PATH; gh logs every call to gh.log, and herdr lists the agents in agents ("<name> <pane>" lines).
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
  "repo view") [ -n "$3" ] || exit 1; echo "${3#https://github.com/}"; exit 0 ;;
  "pr list")   f="$F/prlist.json"; [ "$r" = o/svc ] || f="$F/prlist-${r#o/}.json"; jq -r "$q" "$f"; exit 0 ;;
esac
# watch's REST reads, from the same fixture: the list, and each PR's mergeable state (null for UNKNOWN).
# With list-fails the list fails as gh does, its error JSON on stdout (with list-flaky, all but its third
# call); with pr-fails each PR read fails.
f="$F/prlist.json"; r="${path#repos/}"; r="${r%%/pulls*}"; [ "$r" = o/svc ] || f="$F/prlist-${r#o/}.json"
case "${path}" in
  repos/o/*/pulls) fail=""; [ ! -f "$F/list-fails" ] || fail=1
    if [ -f "$F/list-flaky" ]; then k=$(($(cat "$F/list-n" 2>/dev/null || echo 0) + 1)); echo "$k" > "$F/list-n"; [ "$k" = 3 ] || fail=1; fi
    [ -z "$fail" ] || { echo '{"message":"Forbidden","status":"403"}'; echo 'gh: Forbidden (HTTP 403)' >&2; exit 1; }
    jq '[.[] | {number, head: {ref: .headRefName, sha: .headRefOid}, updated_at: .updatedAt}]' "$f" | jq -r "$q" ;;
  repos/o/*/pulls/*) [ ! -f "$F/pr-fails" ] || { echo '{"message":"Server Error"}'; exit 1; }
    jq ".[] | select(.number == ${path##*/}) | {mergeable: {MERGEABLE: true, CONFLICTING: false}[.mergeable]}" "$f" | jq -r "$q" ;;
  repos/o/*/commits/*/check-runs) f="$F/runs-$(basename "${path%/check-runs}").json"
    if [ -n "$q" ]; then jq -r "$q" "$f" | head -1; else cat "$f"; fi ;;
  repos/o/*/commits/*/status) f="$F/status-$(basename "${path%/status}").json"
    if [ -f "$f" ]; then cat "$f"; else echo '{"statuses":[],"total_count":0}'; fi ;;
  *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
printf '#!/bin/sh\nF="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
case "$1 $2" in
  "agent list") awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
    { printf "%s{\"name\":\"%s\",\"agent_status\":\"working\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
    END { print "]}}" }' "$F/agents" ;;
esac
EOF
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr" "${ROOT}/bin/claude"

# e1 has the code story s1 (PR #3, head h1) and the lead story l1 (PR #4, head h2), both green.
p="${ROOT}/proj"
mkdir -p "${p}/.claude/swarm" "${p}/docs/epics" "${p}/docs/stories" "${p}/.swarm/briefs" "${p}/.swarm/state" "${p}/.swarm/reviews"
: > "${p}/.claude/swarm/config"
git -C "${p}" init -q && git -C "${p}" remote add origin https://github.com/o/svc
printf -- '---\nstatus: active\n---\n' > "${p}/docs/epics/e1.md"
printf -- '---\nstatus: ready\nkind: code\nepic: e1\n---\n' > "${p}/docs/stories/s1.md"
printf -- '---\nstatus: ready\nkind: lead\nepic: e1\n---\n' > "${p}/docs/stories/l1.md"
# A working conductor for e1, in a pane this project recorded (as start_agent records one).
touch "${p}/.swarm/briefs/conduct-e1.md"; echo "w:7 conduct-e1" > "${p}/.swarm/state/tab"
echo "conduct-e1 w:7" > "${ROOT}/agents"
# prs <mergeable> — the open PRs, #3 with that mergeable; #5 (head h5) is story/t1's, of the epic e2.
prs() {
  echo "[{\"number\": 3, \"headRefName\": \"story/s1\", \"headRefOid\": \"h1\", \"mergeable\": \"$1\", \"updatedAt\": \"2026-01-01T00:00:00Z\"},
   {\"number\": 4, \"headRefName\": \"story/l1\", \"headRefOid\": \"h2\", \"mergeable\": \"MERGEABLE\", \"updatedAt\": \"2026-01-01T00:00:00Z\"},
   {\"number\": 5, \"headRefName\": \"story/t1\", \"headRefOid\": \"h5\", \"mergeable\": \"MERGEABLE\", \"updatedAt\": \"2026-01-01T00:00:00Z\"}]" > "${ROOT}/prlist.json"
}
prs MERGEABLE
ago() { python3 -c 'import sys, time; print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 60 * int(sys.argv[1]))))' "$1"; }
# green <minutes> — h1's, h2's and h5's checks all passed, the last <minutes> ago, with no commit status;
# watch has already reported them finished, so only a queued line can wake it.
green() {
  local sha
  for sha in h1 h2 h5; do
    echo "{\"total_count\":2,\"check_runs\":[{\"status\":\"completed\",\"conclusion\":\"success\",\"completed_at\":\"2020-01-01T00:00:00Z\"},{\"status\":\"completed\",\"conclusion\":\"skipped\",\"completed_at\":\"$(ago "$1")\"}]}" > "${ROOT}/runs-${sha}.json"
    rm -f "${ROOT}/status-${sha}.json"
  done
  printf 'done h1\ndone h2\ndone h5\n' > "${p}/.swarm/state/watch-seen"
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
# nextq [step] [bash] — next's queued lines (none: "(none)"), after checking its step is [step] (default
# wait conduct-e1); run with [bash] (default bash), its stderr in next.err.
nextq() {
  local out
  out="$(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" "${2:-bash}" "${SWARM}" next 2> "${ROOT}/next.err")"
  [[ "${out%%$'\n'*}" == "${1:-wait conduct-e1}" ]] || { echo "next's step is not ${1:-wait conduct-e1}: ${out}"; return; }
  grep '^queued: ' <<< "${out}" || echo "(none)"
}
calls() { grep -c "$1" "${ROOT}/gh.log" || true; }
# extra_lists — gh pr list calls: watch polls through REST (watch_rows), so each is another read.
extra_lists() { grep -c 'pr list' "${ROOT}/gh.log" || true; }
Q31="queued: o/svc #3 story/s1 green 31m with no review on h1"
QN="${Q31} (conduct-e1)"   # next's line names the conductor to send it to

# watch reads a PR's mergeable state only on its own stories' PRs, and not on a head whose conflict it
# reported and that has nothing left to queue.
green 10
watchrun > /dev/null
check "watch reads no mergeable state of another epic's PR" 0 "$(calls 'api repos/o/svc/pulls/5 ')"
printf 'conflict h1\nqueued h1\n' >> "${p}/.swarm/state/watch-seen"
check "watch reads no mergeable state of a head whose conflict it reported" "(still watching)|0" "$(watchrun)|$(calls 'api repos/o/svc/pulls/3 ')"
# A failed read is UNKNOWN, said once a poll: a head green 31 minutes is not queued on it. A failed
# list is said, and read as no PR.
green 31; touch "${ROOT}/pr-fails"
check "watch reads a failed mergeable read as UNKNOWN, queues nothing on it, and says so" "(still watching)|yes" \
  "$(watchrun)|$(grep -q "^swarm: watch: gh cannot read o/svc #3's mergeable state; reading it as UNKNOWN this poll" "${ROOT}/watch.out" && echo yes)"
rm -f "${ROOT}/pr-fails"; touch "${ROOT}/list-fails"
check "watch says a failed list on stderr, once over many polls, reads no row from it, and polls on" "(still watching)|1|yes|no" \
  "$(SWARM_SLEEP_SCALE=0.01 watchrun)|$(grep -c "^swarm: watch: gh cannot list o/svc's open PRs: gh: Forbidden (HTTP 403)" "${ROOT}/watch.out")|$([[ "$(calls 'pulls?state=open')" -gt 2 ]] && echo yes)|$(grep -q 'unbound' "${ROOT}/watch.out" && echo yes || echo no)"
rm -f "${ROOT}/list-fails"; green 10; touch "${ROOT}/list-flaky"
check "watch says a failed list again once a list between succeeded" 2 \
  "$(SWARM_SLEEP_SCALE=0.01 watchrun >/dev/null; grep -c "^swarm: watch: gh cannot list o/svc's open PRs" "${ROOT}/watch.out")"
rm -f "${ROOT}/list-flaky" "${ROOT}/list-n"
# A PR updated after the local clock's now (a clock behind GitHub's) is listed, its age 0.
prs CONFLICTING; sed -i.bak 's/2026-01-01T00:00:00Z/2099-01-01T00:00:00Z/' "${ROOT}/prlist.json"; : > "${p}/.swarm/state/watch-seen"
check "watch lists a PR updated in the local clock's future" "o/svc #3 story/s1 CONFLICTS with its base" "$(watchrun)"
prs MERGEABLE

green 31
check "watch reports a PR green and mergeable for 31 minutes with no review agent, naming its repo, branch and head" "${Q31}" "$(watchrun)"
# watch polls through REST, whose budget is apart from GraphQL's: no gh pr list.
check "watch lists the open PRs through REST" 1 "$(calls 'api --paginate repos/o/svc/pulls?state=open&per_page=100')"
check "watch reads #3's mergeable state through REST" 1 "$(calls 'api repos/o/svc/pulls/3 ')"
check "watch reads no mergeable state past the PR it reports" 0 "$(calls 'api repos/o/svc/pulls/4 ')"
check "watch makes no GraphQL gh pr list" 0 "$(extra_lists)"
check "watch reports a queued head once, lists PRs only in its own poll, and reads no CI for a head it has reported" "(still watching)|0|0" \
  "$(watchrun)|$(extra_lists)|$(calls 'commits/h1/')"
check "watch reads no mergeable state of a head it has reported finished and queued" 0 "$(calls 'api repos/o/svc/pulls/3 ')"
check "next leaves out a head watch has reported" "(none)" "$(nextq)"
green 31
check "next prints the queued line under the conductor's wait, naming it, and none for the lead story's green PR" "${QN}" "$(nextq)"
: > "${ROOT}/gh.log"
(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" status >/dev/null 2>&1) || true
(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash >/dev/null 2>&1) || true
check "status and dash, which read next_step, judge no PR queued (no CI read)" "0" "$(calls 'commits/')"

# review-s1, open in a pane this project recorded, started on h1 and has written no findings file yet.
echo h1 > "${p}/.swarm/reviews/s1.head"
echo "review-s1 w:8" >> "${ROOT}/agents"; echo "w:8 review-s1" >> "${p}/.swarm/state/tab"
green 31
check "with a review agent on that head, watch does not report it, and reads no CI for it" "(still watching)|0" "$(watchrun)|$(calls 'commits/h1/')"
green 31   # watch's run above may have recorded h1 as sent: start clean
check "with a review agent on that head, next prints no queued line" "(none)" "$(nextq)"
echo h0 > "${p}/.swarm/reviews/s1.head"
check "a review agent on an earlier head does not count" "${QN}" "$(nextq)"
echo h1 > "${p}/.swarm/reviews/s1.head"
sed -i.bak '/^review-s1 /d' "${ROOT}/agents"
check "a review agent gone from herdr (crashed, closed or tidied) with no findings file is no review" "${QN}" "$(nextq)"
# The findings file for h1 decides once it exists: a pass counts, a head moved: or no ## Findings does not.
echo h1 > "${p}/.swarm/reviews/s1.head"
printf 'head: h1\nhead moved: the worktree moved\n## Findings\nNone.\n' > "${p}/.swarm/reviews/s1.md"
check "a review that found the head moved is no review, even with a ## Findings section, so the PR is queued" "${QN}" "$(nextq)"
printf 'head: h1\n' > "${p}/.swarm/reviews/s1.md"
check "a findings file with no ## Findings section is no review, so the PR is queued" "${QN}" "$(nextq)"
rm "${p}/.swarm/reviews/s1.head"
printf 'head: h1\n## Findings\nNone.\n' > "${p}/.swarm/reviews/s1.md"
check "a passing findings file for the head counts as its review, with no head file" "(none)" "$(nextq)"
rm "${p}/.swarm/reviews/s1.md"

green 29
check "at 29 minutes, watch does not report it" "(still watching)" "$(watchrun)"
green 29   # as above
check "at 29 minutes, next prints no queued line" "(none)" "$(nextq)"
echo "queue_minutes = 20" > "${p}/.claude/swarm/config"
check "queue_minutes sets the threshold" "queued: o/svc #3 story/s1 green 29m with no review on h1 (conduct-e1)" "$(nextq)"
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
echo '{"total_count":1,"statuses":[{"state":"success","context":"ext","updated_at":"2020-01-01T00:00:00Z"}]}' > "${ROOT}/status-h1.json"
check "a head with no check runs is not green, so not queued, even with a green commit status" "(none)" "$(nextq)"

# A story whose repo: names the project's own repo: its PRs are listed and printed once.
green 31
printf -- '---\nstatus: ready\nkind: code\nepic: e1\nrepo: proj\n---\n' > "${p}/docs/stories/s4.md"
: > "${ROOT}/gh.log"
check "a story naming the project's own repo prints each queued line once, from one PR list" "${QN}|1" "$(nextq)|$(calls 'pr list')"
rm "${p}/docs/stories/s4.md"

# Two more repos: gone, which next cannot resolve, and zsvc after it, with a green PR #9 (head h9). The
# bad one is warned of on stderr, and the repos on either side of it still count.
green 31
cp "${ROOT}/runs-h1.json" "${ROOT}/runs-h9.json"
git init -q "${ROOT}/zsvc" && git -C "${ROOT}/zsvc" remote add origin https://github.com/o/zsvc
echo '[{"number": 9, "headRefName": "story/s3", "headRefOid": "h9", "mergeable": "MERGEABLE"}]' > "${ROOT}/prlist-zsvc.json"
printf -- '---\nstatus: ready\nkind: code\nepic: e1\nrepo: gone\n---\n' > "${p}/docs/stories/s2.md"
printf -- '---\nstatus: ready\nkind: code\nepic: e1\nrepo: zsvc\n---\n' > "${p}/docs/stories/s3.md"
check "a repo next cannot resolve is warned of, and every other repo's queued line still prints" \
  "${QN}"$'\n'"queued: o/zsvc #9 story/s3 green 31m with no review on h9 (conduct-e1)|yes" \
  "$(nextq)|$(if grep -q '^warning: watch gone: .*its PRs waiting for a review are unknown' "${ROOT}/next.err"; then echo yes; else cat "${ROOT}/next.err"; fi)"
rm "${p}/docs/stories/s2.md" "${p}/docs/stories/s3.md"

# Under bash 3.2's set -u, with no repo that resolves (the project's origin gone): a warning, no crash.
git -C "${p}" remote remove origin
check "with no repo resolved, next warns and prints no queued line, with no unbound-variable error (bash 3.2)" "(none)|yes|no" \
  "$(nextq "wait conduct-e1" /bin/bash)|$(if grep -q '^warning: no GitHub origin' "${ROOT}/next.err"; then echo yes; else cat "${ROOT}/next.err"; fi)|$(if grep -q unbound "${ROOT}/next.err"; then echo yes; else echo no; fi)"
git -C "${p}" remote add origin https://github.com/o/svc

# Two conductors side by side: next prints each one's queued lines, naming each, whatever its step.
green 31
printf -- '---\nstatus: active\n---\n' > "${p}/docs/epics/e2.md"
printf -- '---\nstatus: ready\nkind: code\nepic: e2\n---\n' > "${p}/docs/stories/t1.md"
touch "${p}/.swarm/briefs/conduct-e2.md"; echo "w:9 conduct-e2" >> "${p}/.swarm/state/tab"; echo "conduct-e2 w:9" >> "${ROOT}/agents"
Q5="queued: o/svc #5 story/t1 green 31m with no review on h5 (conduct-e2)"
check "with two conductors at work, next prints both one's and the other's queued lines, each naming its conductor" "${QN}"$'\n'"${Q5}" "$(nextq)"
printf -- '---\nstatus: active\n---\n' > "${p}/docs/epics/e3.md"
check "while a conductor works and an epic is planned first (plan-epic), next still prints the queued lines" "${QN}"$'\n'"${Q5}" "$(nextq "plan-epic e3")"
rm "${p}/docs/epics/e3.md"

# The lead sends conduct-e1 its line (tell note): its head is recorded as sent, so next no longer prints
# it, and watch does not send it again; the other conductor's line is untouched.
echo "${QN}" > "${ROOT}/note.md"
(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" tell conduct-e1 note "${ROOT}/note.md" >/dev/null)
check "a queued line the lead sends with tell note is recorded, so next leaves it out and keeps the other" "${Q5}|yes" \
  "$(nextq)|$(if grep -qx 'queued h1' "${p}/.swarm/state/watch-seen"; then echo yes; else echo no; fi)"
check "after the lead sent it, watch does not report the same head" "(still watching)" "$(watchrun)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
