#!/usr/bin/env bash
# merge_queue_test.sh — merge_test.sh's cases on merge_admin = on, a merge queue on the base, and the
# note a board merge sends a running conductor. On merge_fixture.sh, as merge_test.sh is.
# shellcheck disable=SC2153,SC2154 # merge_fixture.sh sets URL, rc and the rest
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'chmod -R u+rwx "${ROOT}" 2>/dev/null; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
# shellcheck source=merge_fixture.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
. "$(dirname "${BASH_SOURCE[0]}")/merge_fixture.sh"

# origin's default branch is main, tagged v1.2.0 (as merge_rules_test.sh sets it up for --release).
git -C "${P}" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init; git -C "${P}" tag v1.2.0
git -C "${P}" push -q origin HEAD:refs/heads/main v1.2.0; git -C "${ROOT}/origin.git" symbolic-ref HEAD refs/heads/main

# --- merge_admin = on: --admin on the pinned merge, only once every check has passed.
fresh "merge_admin = on"; merge "${URL}"
is "merge_admin = on: exits 0" 0 "${rc}"
check "merge_admin = on: pr merge passes --admin" grep -qxF "pr merge 7 --repo o/r --squash --match-head-commit ${H1} --admin" "${ROOT}/gh.log"
fresh "merge_admin = off"; merge "${URL}"
check "merge_admin = off: pr merge without --admin" grep -qxF "pr merge 7 --repo o/r --squash --match-head-commit ${H1}" "${ROOT}/gh.log"
fresh "merge_admin = on"; checks "${FX}/${H1}.checks" "$(run test completed failure)"
merge "${URL}"; refused "merge_admin = on, a red head" "test (failure)"
fresh "merge = agent" "merge_admin = on"; item s "status: review" "prs: ${URL}" "costs: money"
merge HERDR_ENV=1 HERDR_PANE_ID=w:c --head "${H1}" "${URL}"; refused "merge_admin = on, costs: money" "held: s costs money"
fresh "merge_admin = on"; echo "${H2}" > "${FX}/head"
merge --head "${H1}" "${URL}"; refused "merge_admin = on, a moved head" "is 2222222, not 1111111"
# --admin skips every rule on the base, so merge checks each required check is on the head, the head
# is up to date where the base says strict, and the base has no other rule --admin would skip.
# protected <context>... — main's classic branch protection requires these checks, from any app.
protected() {
  local c list=""; for c in "$@"; do list+="${list:+,}\"${c}\""; done
  echo "{\"required_status_checks\":{\"strict\":false,\"contexts\":[${list}],\"checks\":[]}}" > "${FX}/branch"
}
fresh "merge_admin = on"
echo '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"test"}]}}]' > "${FX}/rules"
protected test; merge "${URL}"
is "merge_admin = on, required checks present: exits 0" 0 "${rc}"
fresh "merge_admin = on"
echo '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"test"},{"context":"build"}]}}]' > "${FX}/rules"
merge "${URL}"; refused "merge_admin = on, a ruleset's required check absent from the head" "build (required, absent)"
fresh "merge_admin = on"; protected
echo '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"test","integration_id":99}]}}]' > "${FX}/rules"
merge "${URL}"; refused "merge_admin = on, a required check whose app never reported it" "test (required, absent)"
fresh "merge_admin = on"; protected
echo '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"test","integration_id":99}]}}]' > "${FX}/rules"
checks "${FX}/${H1}.checks" '{"name":"test","status":"completed","conclusion":"success","app":{"id":99}}'; merge "${URL}"
is "merge_admin = on, a required check its app reported: exits 0" 0 "${rc}"
fresh "merge_admin = on"; protected test lint
merge "${URL}"; refused "merge_admin = on, branch protection's required check absent from the head" "lint (required, absent)"
fresh "merge_admin = on"
echo '{"required_status_checks":{"strict":false,"contexts":["test"],"checks":[{"context":"test","app_id":99}]}}' > "${FX}/branch"
merge "${URL}"; refused "merge_admin = on, branch protection's check bound to an app that never reported it" "test (required, absent)"
fresh "merge_admin = on"; echo release/1.x > "${FX}/base"; merge "${URL}"
check "merge_admin = on, base release/1.x: the rules path encodes the branch" grep -q -- "repos/o/r/rules/branches/release%2F1.x?" "${ROOT}/gh.log"
check "merge_admin = on, base release/1.x: so does branch protection's" grep -q -- "repos/o/r/branches/release%2F1.x/protection" "${ROOT}/gh.log"
fresh "merge_admin = on"; touch "${FX}/branch.fail"
merge "${URL}"; refused "merge_admin = on, branch protection unreadable" "HTTP 502"
fresh; echo '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"build"}]}}]' > "${FX}/rules"
merge "${URL}"; is "merge_admin off: the required checks are GitHub's, not read" 0 "${rc}"
# Strict (up to date required), from a ruleset or classic protection: a head behind the base is refused.
strict_rule='[{"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":true,"required_status_checks":[{"context":"test"}]}}]'
fresh "merge_admin = on"; echo "${strict_rule}" > "${FX}/rules"; echo '{"behind_by":2}' > "${FX}/compare"
merge "${URL}"; refused "merge_admin = on, a strict ruleset and a head behind main" "it is 2 commit(s) behind main"
check "merge_admin = on, strict: compares main with the head" grep -q -- "repos/o/r/compare/main...${H1}" "${ROOT}/gh.log"
fresh "merge_admin = on"; echo "${strict_rule}" > "${FX}/rules"; echo '{"behind_by":0}' > "${FX}/compare"; merge "${URL}"
is "merge_admin = on, a strict ruleset and a head up to date: exits 0" 0 "${rc}"
fresh "merge_admin = on"; echo '{"required_status_checks":{"strict":true,"contexts":[],"checks":[]}}' > "${FX}/branch"
echo '{"behind_by":1}' > "${FX}/compare"
merge "${URL}"; refused "merge_admin = on, strict branch protection and a head behind main" "it is 1 commit(s) behind main"
fresh "merge_admin = on"; touch "${FX}/compare.fail"; echo "${strict_rule}" > "${FX}/rules"
merge "${URL}"; refused "merge_admin = on, strict and the compare unreadable" "HTTP 502"
fresh "merge_admin = on"; echo '{"behind_by":3}' > "${FX}/compare"; merge "${URL}"
is "merge_admin = on, not strict: a head behind main merges" 0 "${rc}"
# Any rule --admin would skip besides the review: refused, naming it. Push-only rules are not.
fresh "merge_admin = on"; echo '[{"type":"pull_request","parameters":{}},{"type":"merge_queue","parameters":{}}]' > "${FX}/rules"
merge "${URL}"; refused "merge_admin = on, a ruleset's merge_queue rule" "ruleset rule merge_queue, which --admin would skip"
fresh "merge_admin = on"; echo '[{"type":"workflows","parameters":{}}]' > "${FX}/rules"
merge "${URL}"; refused "merge_admin = on, a ruleset's workflows rule" "ruleset rule workflows"
fresh "merge_admin = on"; echo '{"required_signatures":{"enabled":true},"required_linear_history":{"enabled":false}}' > "${FX}/branch"
merge "${URL}"; refused "merge_admin = on, branch protection's required signatures" "branch protection required_signatures, which --admin would skip"
check "merge_admin = on, required signatures: not linear history, which is off" bash -c "! grep -q required_linear_history '${ROOT}/out'"
fresh "merge_admin = on"; echo '{"restrictions":{"users":[],"teams":[],"apps":[]}}' > "${FX}/branch"
merge "${URL}"; refused "merge_admin = on, branch protection's push restrictions" "branch protection restrictions"
fresh "merge_admin = on"
echo '[{"type":"pull_request","parameters":{}},{"type":"deletion"},{"type":"non_fast_forward"},{"type":"creation"}]' > "${FX}/rules"
echo '{"required_pull_request_reviews":{"required_approving_review_count":1},"allow_deletions":{"enabled":false},"enforce_admins":{"enabled":false}}' > "${FX}/branch"
merge "${URL}"; is "merge_admin = on, only the review and push rules: exits 0" 0 "${rc}"
check "merge_admin = on, only the review and push rules: --admin" grep -q -- "^pr merge 7 .*--admin" "${ROOT}/gh.log"

# --- A merge queue on the base: enqueue the pinned head, wait for the queue, no main-ci wait.
G=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb   # the merge group's commit
# now / ago — a fixture event's time: a minute after the enqueue the test is about to make (this
# run's), or ten seconds before it (an earlier run's, such as its stop()'s dequeue).
stamp() { python3 -c 'import sys, time; print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + int(sys.argv[1]))))' "$1"; }
now() { stamp 60; }
ago() { stamp -10; }
# qread <file> <state> <in queue> <auto-merge> <group|-> <merge commit|-> [reason [when]] — one graphql
# read of the PR, its head ${QHEAD:-H1}; a reason is a removal from the queue at <when> (default now).
# Its queue entry is in state ${QSTATE:-AWAITING_CHECKS} (its group's CI runs) with a group, and
# with QSTATE=QUEUED and no group it waits its turn.
qread() {
  local g=null m=null r=""
  [[ "$5" == - ]] || g="{\"state\":\"${QSTATE:-AWAITING_CHECKS}\",\"headCommit\":{\"oid\":\"$5\"}}"
  [[ "$5" != - || -z "${QSTATE:-}" ]] || g="{\"state\":\"${QSTATE}\",\"headCommit\":null}"
  [[ "$6" == - ]] || m="{\"oid\":\"$6\"}"
  [[ -z "${7:-}" ]] || r="{\"reason\":\"$7\",\"createdAt\":\"${8:-$(now)}\"}"
  printf '{"data":{"repository":{"pullRequest":{"id":"PR_7","state":"%s","headRefOid":"%s","isInMergeQueue":%s,"autoMergeRequest":%s,"mergeCommit":%s,"mergeQueueEntry":%s,"timelineItems":{"nodes":[%s]}}}}}\n' \
    "$2" "${QHEAD:-${H1}}" "$3" "$4" "${m}" "${g}" "${r}" > "$1"
}
WAITING='{"enabledAt":"x"}'
# qfresh — fresh, with a merge queue on main, and lint red on the merge group's commit.
qfresh() {
  fresh; echo '{"data":{"repository":{"mergeQueue":{"id":"MQ_1"}}}}' > "${FX}/mq"
  checks "${FX}/${G}.checks" "$(run test completed success)" "$(run lint completed failure)"; statuses "${FX}/${G}.status"
}
# auto_off / dequeued_it — the PR's auto-merge was turned off / it was taken out of the queue.
auto_off() { grep -q "disablePullRequestAutoMerge" "${ROOT}/gh.log"; }
dequeued_it() { grep -q "dequeuePullRequest" "${ROOT}/gh.log"; }
LINT="lint (failure) https://github.com/o/r/runs/lint"
qfresh; qread "${FX}/queue.1" OPEN false "${WAITING}" - -; qread "${FX}/queue.2" OPEN true null "${G}" -
qread "${FX}/queue.3" MERGED false null - "${M}"; merge "${URL}"
is "queue: exits 0" 0 "${rc}"
check "queue: enqueued with --auto pinned to the head, no method" grep -qxF "pr merge 7 --repo o/r --auto --match-head-commit ${H1}" "${ROOT}/gh.log"
check "queue: no direct merge" bash -c "! grep -E -- '^pr merge .*--(squash|merge|rebase)' '${ROOT}/gh.log'"
is "queue: merge ok, then CI on the merge commit, then reconcile" "merge s ok|main-ci s ok|reconcile s ok (finished)" "$(events | paste -sd'|' -)"
check "queue: says it is queued, then that it merged through the queue" bash -c "grep -qF 'queued: s #7 (head 1111111)' '${ROOT}/out' && grep -qF 'merged: #7 through the merge queue (head 1111111, merge commit aaaaaaa)' '${ROOT}/out'"
qfresh; qread "${FX}/queue.1" OPEN true null "${G}" -; qread "${FX}/queue.2" OPEN false null - - "MERGE_QUEUE_STATUS_CHECK_FAILED"
merge "${URL}"
is "dequeue: exits non-zero" 1 "${rc}"
check "dequeue: names the failing check on the merge group's commit" said "dequeued (MERGE_QUEUE_STATUS_CHECK_FAILED): ${LINT}"
is "dequeue: one merge line naming the check, no reconcile" "merge s dequeued (MERGE_QUEUE_STATUS_CHECK_FAILED): ${LINT}" "$(events)"
check "dequeue: the story stays on the board" test -e "${S}"
# In and out of the queue between two reads: the group commit is found from its merge_group run.
qfresh; qread "${FX}/queue.1" OPEN false "${WAITING}" - -; qread "${FX}/queue.2" OPEN false null - - "MERGE_QUEUE_STATUS_CHECK_FAILED"
printf '{"workflow_runs":[{"head_branch":"gh-readonly-queue/main/pr-7-%s-%s","head_sha":"%s","created_at":"%s"}]}\n' "${H1}" "${M}" "${G}" "$(now)" > "${FX}/mgruns"
merge "${URL}"
check "a dequeue between two reads: names the check on the group commit its run names" said "dequeued (MERGE_QUEUE_STATUS_CHECK_FAILED): ${LINT}"
# In and out before the first read: a removal since the enqueue is a dequeue, not "never queued".
qfresh; qread "${FX}/queue" OPEN false null - - "MERGE_CONFLICT"; merge "${URL}"
is "a removal before the first read: one dequeue line naming GitHub's reason" "merge s dequeued (MERGE_CONFLICT): no red check on the head 1111111" "$(events)"
# A removal from an earlier enqueue is not this one's reason.
qfresh; qread "${FX}/queue.1" OPEN true null "${G}" -; qread "${FX}/queue" OPEN false null - - "AN_OLD_REASON" 2020-01-01T00:00:00Z
merge "${URL}"
check "an earlier enqueue's removal: not its reason" said "dequeued (no reason given): ${LINT}"
# A batch: the queue merged #7 and a PR after it in one push, at M2. The push-only runs are on M2,
# none on #7's own merge commit, which is not waited on.
M2=cccccccccccccccccccccccccccccccccccccccc
qfresh; rm -f "${FX}/${M}.checks" "${FX}/${M}.runs"
printf '{"commit":{"sha":"%s"}}\n' "${M2}" > "${FX}/basehead"; echo '{"status":"ahead"}' > "${FX}/compare"
checks "${FX}/${M2}.checks" "$(run test completed success)"; statuses "${FX}/${M2}.status"
wfruns "${FX}/${M2}.runs" "$(run ci completed success "${M2}")"
qread "${FX}/queue.1" OPEN true null "${G}" -; qread "${FX}/queue.2" MERGED false null - "${M}"; merge "${URL}"
is "two PRs merged in one push: CI waited on at the pushed commit that holds this merge" "0|merge s ok|main-ci s ok" \
  "${rc}|$(events | head -2 | paste -sd'|' -)"
# A red main after a queued merge: main-ci red, reconcile, and a failure, as for a direct merge.
qfresh; checks "${FX}/${M}.checks" "$(run test completed success)" "$(run e2e completed failure)"
qread "${FX}/queue.1" OPEN true null "${G}" -; qread "${FX}/queue.2" MERGED false null - "${M}"; merge "${URL}"
check "a red main after a queued merge: main-ci red, reconcile still runs, exits non-zero" \
  bash -c "[[ ${rc} -eq 1 ]] && grep -q 'main-ci	s	.*red .*e2e (failure)' '${P}/.swarm/events.tsv' && grep -q 'reconcile	s	.*ok (finished)' '${P}/.swarm/events.tsv'"
# Dropped from the queue while auto-merge still reads on: a dequeue at once, and auto-merge turned off.
qfresh; qread "${FX}/queue.1" OPEN true null "${G}" -; qread "${FX}/queue" OPEN false "${WAITING}" - - "MERGE_QUEUE_STATUS_CHECK_FAILED"
merge SWARM_MERGE_CI_SECONDS=1 "${URL}"
is "dropped from the queue with auto-merge still on: a dequeue naming the check, auto-merge off" \
  "merge s dequeued (MERGE_QUEUE_STATUS_CHECK_FAILED): ${LINT}; auto-merge is off" "$(events)"
# An earlier run's dequeue (its stop(), seconds before this enqueue) is not this one's.
qfresh; qread "${FX}/queue.1" OPEN false null - - "MANUAL" "$(ago)"; qread "${FX}/queue.2" OPEN true null "${G}" -
qread "${FX}/queue.3" MERGED false null - "${M}"; merge "${URL}"
is "an earlier run's dequeue seconds before this enqueue: not this one's, and it merges" "0|merge s ok" "${rc}|$(events | head -1)"
# One read out of the queue, before GitHub says merged, is not a dequeue.
qfresh; qread "${FX}/queue.1" OPEN true null "${G}" -; qread "${FX}/queue.2" OPEN false null - -
qread "${FX}/queue.3" MERGED false null - "${M}"; merge "${URL}"
is "out of the queue for one read before it reads merged: not a dequeue" "0|merge s ok" "${rc}|$(events | head -1)"
# Merged before its merge commit shows: read again, then merge ok and reconcile.
qfresh; qread "${FX}/queue.1" OPEN true null "${G}" -; qread "${FX}/queue.2" MERGED false null - -
qread "${FX}/queue.3" MERGED false null - "${M}"; merge "${URL}"
is "merged before its merge commit shows: reads again, merge ok, then reconcile" "0|merge s ok|main-ci s ok|reconcile s ok (finished)" "${rc}|$(events | paste -sd'|' -)"
# Waiting its turn is not CI time: four reads queued behind others, past a 1 s CI deadline, then its
# own group runs and merges. Waiting has the queue's own bound, six deadlines.
qfresh; for i in 1 2 3 4; do QSTATE=QUEUED qread "${FX}/queue.${i}" OPEN true null - -; done
qread "${FX}/queue.5" OPEN true null "${G}" -; qread "${FX}/queue.6" MERGED false null - "${M}"
merge SWARM_MERGE_CI_SECONDS=1 SWARM_MERGE_POLL=0.5 "${URL}"
is "waiting its turn past the CI deadline: still merges, nothing dequeued" "0|merge s ok|no" \
  "${rc}|$(events | head -1)|$(grep -q 'mutation(' "${ROOT}/gh.log" && echo yes || echo no)"
# A group taken apart (a PR ahead failed) after the turn bound has passed: it waits its turn afresh.
# Seven reads, each a rebuilt group (its 0.3 s deadline restarts), take it past the 1.8 s bound.
qfresh; for i in 1 2 3 4 5 6 7; do qread "${FX}/queue.${i}" OPEN true null "c$(printf '%039d' "${i}")" -; done
QSTATE=QUEUED qread "${FX}/queue.8" OPEN true null - -; qread "${FX}/queue.9" MERGED false null - "${M}"
merge SWARM_MERGE_CI_SECONDS=0.3 SWARM_MERGE_POLL=0.4 "${URL}"
is "a group taken apart after the turn bound passed: waits its turn afresh, and merges" "0|merge s ok" "${rc}|$(events | head -1)"
qfresh; QSTATE=QUEUED qread "${FX}/queue" OPEN true "${WAITING}" - -
merge SWARM_MERGE_CI_SECONDS=0.3 SWARM_MERGE_POLL=0.3 "${URL}"
check "waiting its turn past the queue's own bound: a timeout, out of the queue" \
  logged "^merge s unconfirmed (timeout (waiting its turn in the merge queue)): #7 did not merge; auto-merge is off and it is out of the merge queue$"
# A first read that lags the enqueue is not a dequeue; READ_TRIES reads never queued are.
qfresh; qread "${FX}/queue.1" OPEN false null - -; qread "${FX}/queue.2" OPEN true null "${G}" -; qread "${FX}/queue.3" MERGED false null - "${M}"
merge "${URL}"; is "a first read before the queue shows it: still merges" 0 "${rc}"
qfresh; qread "${FX}/queue" OPEN false null - -; merge "${URL}"
is "never read as queued: exits non-zero" 1 "${rc}"
check "never read as queued: unconfirmed, not a dequeue" logged "^merge s unconfirmed (never read as queued or waiting for auto-merge)"
check "never read as queued: auto-merge off and out of the queue all the same" \
  bash -c "grep -q disablePullRequestAutoMerge '${ROOT}/gh.log' && grep -q dequeuePullRequest '${ROOT}/gh.log'"
# gh failing on the enqueue: read the PR back, and wait on it if GitHub queued it (or it already was).
qfresh; touch "${FX}/auto-fails"; qread "${FX}/queue.1" OPEN true null "${G}" -; qread "${FX}/queue.2" MERGED false null - "${M}"
merge "${URL}"; is "an enqueue that errors, but the PR reads queued: waits and merges" 0 "${rc}"
check "an enqueue that errors: no queued line, says it reads the PR back" bash -c "! grep -qF 'queued: s #7' '${ROOT}/out' && grep -qF 'reading #7 back' '${ROOT}/out'"
check "an enqueue that errors: still says the base has a merge queue, the line the conductor keys on" said "merge queue: main has one, so #7 goes through it"
qfresh; touch "${FX}/auto-fails"; qread "${FX}/queue" OPEN false null - -; merge "${URL}"
is "an enqueue that errors and never queues: exits non-zero" 1 "${rc}"
check "an enqueue that errors and never queues: says gh failed" logged "^merge s gh pr merge --auto failed: gh: HTTP 502"
# The head is read on every poll: one that moves stops the wait and turns auto-merge off.
qfresh; qread "${FX}/queue.1" OPEN false "${WAITING}" - -; QHEAD="${H2}" qread "${FX}/queue.2" OPEN false "${WAITING}" - -
merge "${URL}"
is "a head that moves while queued: exits non-zero" 1 "${rc}"
check "a head that moves while queued: names both heads" said "the head is 2222222, not 1111111, the head that was checked; auto-merge is off: review the new head"
check "a head that moves while queued: auto-merge turned off" auto_off
# A merge at another head: said and logged, never merge ok, no auto-merge call, but reconciled.
qfresh; QHEAD="${H2}" qread "${FX}/queue" MERGED false null - "${M}"; merge "${URL}"
is "a merge of another head: exits non-zero" 1 "${rc}"
is "a merge of another head: logged as one, then reconciled" \
  "merge s merged at head 2222222, not 1111111, the head that was checked (merge commit aaaaaaa)|reconcile s ok (finished)" "$(events | paste -sd'|' -)"
check "a merge of another head: says so" said "merge: #7 merged at head 2222222, not 1111111, the head that was checked (merge commit aaaaaaa): review what merged"
check "a merge of another head: no auto-merge or dequeue call" bash -c "! grep -qE 'mutation\(|--disable-auto' '${ROOT}/gh.log'"
# A timeout: auto-merge off and out of the queue, as the last read showed them.
qfresh; qread "${FX}/queue" OPEN true "${WAITING}" "${G}" -
merge SWARM_MERGE_CI_SECONDS=0.3 SWARM_MERGE_POLL=0.3 "${URL}"
is "a queue that never merges: exits non-zero" 1 "${rc}"
check "a queue that never merges: unconfirmed, auto-merge off and out of the queue" \
  logged "^merge s unconfirmed (timeout (in the merge queue)): #7 did not merge; auto-merge is off and it is out of the merge queue$"
check "a queue that never merges: both calls made" bash -c "grep -q disablePullRequestAutoMerge '${ROOT}/gh.log' && grep -q dequeuePullRequest '${ROOT}/gh.log'"
qfresh; touch "${FX}/mutation.fail"; qread "${FX}/queue" OPEN true null "${G}" -
merge SWARM_MERGE_CI_SECONDS=0.3 SWARM_MERGE_POLL=0.3 "${URL}"
check "a timeout whose dequeue fails: names it, and says to do it by hand" \
  bash -c "grep -qF 'dequeuePullRequest failed (gh api graphql' '${ROOT}/out' && grep -qF 'take it out of the merge queue and turn auto-merge off by hand' '${ROOT}/out'"
# term_merge <text> — merge in the background, TERM it once gh.log holds <text> (then mark it sent,
# ${FX}/termed), and wait for it.
term_merge() {
  local mpid
  (cd "${P}" && exec env -u HERDR_ENV -u HERDR_PANE_ID -u SWARM_PROJECT -u SWARM_AGENT PATH="${ROOT}/bin:${PATH}" SWARM_MERGE_POLL=1 \
    SWARM_MERGE_READ_WAIT=0 SWARM_MERGE_CI_SECONDS=60 bash "${SWARM}" merge "${URL}" > "${ROOT}/out" 2>&1) &
  mpid=$!
  for _ in $(seq 100); do grep -qF -- "$1" "${ROOT}/gh.log" && break; sleep 0.1; done
  kill -TERM "${mpid}"; : > "${FX}/termed"; rc=0; wait "${mpid}" || rc=$?
}
# Three failed reads after one that showed auto-merge only: both undone, as GitHub may have queued it since.
qfresh; qread "${FX}/queue.1" OPEN false "${WAITING}" - -; touch "${FX}/queue.2.fail" "${FX}/queue.3.fail" "${FX}/queue.4.fail"
merge "${URL}"
check "three failed reads after one with auto-merge only: auto-merge off and out of the queue" \
  logged "^merge s unconfirmed (error .*): #7 did not merge; auto-merge is off and it is out of the merge queue$"
# A TERM the moment queued() installs its handler: caught as a stop (7), the PR stopped, not an
# error that escapes it. ci_gate's functions run here with signal.signal wrapped to TERM itself.
qfresh; qread "${FX}/queue" OPEN true null "${G}" -
early="$(cd "${P}" && PATH="${ROOT}/bin:${PATH}" python3 - "${REPO}/bin/lib/ci_gate.py" "${H1}" <<'PY'
import os, signal, sys
src = open(sys.argv[1]).read()
ns = {"__name__": "ci_gate"}
exec(compile(src[:src.index("\ntry:\n    mode, repo, args")], sys.argv[1], "exec"), ns)
def install(sig, handler):
    signal.signal(sig, handler)
    if handler is ns["on_signal"] and sig == signal.SIGTERM:
        os.kill(os.getpid(), signal.SIGTERM)
ns["signal"] = type("Wrapped", (), {"signal": staticmethod(install), "SIG_IGN": signal.SIG_IGN, "Signals": signal.Signals})
try:
    print(ns["queued"]("o/r", "7", sys.argv[2], "main", 0, 5, 0)[0])
except ns["Stopped"]:
    print("escaped")
PY
)"
is "a TERM as queued() installs its handler: a stop (7), and the PR stopped" "7|yes" "${early}|$(dequeued_it && echo yes || echo no)"
# queue_rc: a merge ci_gate printed stands, whatever status a signal left; nothing else is changed.
# shellcheck source=/dev/null
# shellcheck disable=SC2034 # merge.sh reads PROJECT_DIR as it loads
qrc() { (PROJECT_DIR="${P}"; . "${REPO}/bin/lib/merge.sh"; queue_rc "$@"); }
# retire_fixes retires only the fix-main stories of its key logged before its own main-red: one logged
# after it is a newer red main's, which stays (two runs in one batch never retire each other).
# shellcheck disable=SC2034 # merge.sh's functions read these
older="$(
  PROJECT_DIR="${ROOT}/rf"; BOARD="${ROOT}/rf/board"; EVENTS_LOG="${ROOT}/rf/events.tsv"; mkdir -p "${BOARD}/stories"
  for s in aaaaaaa ccccccc eeeeeee; do : > "${BOARD}/stories/fix-main-${s}.md"
    printf '2026-10-18T10:00:00Z\tmain-red\t%s\t-\to/r main test (failure)\n' "${s}$(printf '0%.0s' $(seq 1 33))" >> "${EVENTS_LOG}"; done
  # shellcheck source=/dev/null
  . "${REPO}/bin/lib/merge.sh"
  # retire_fixes calls these.
  # shellcheck disable=SC2317,SC2329
  fm() { echo ready; }
  # shellcheck disable=SC2317,SC2329
  one_off_started() { return 1; }
  # shellcheck disable=SC2317,SC2329
  delete_item() { rm "$1"; }
  # shellcheck disable=SC2317,SC2329
  record_event() { :; }
  retire_fixes "o/r main" "ccccccc$(printf '0%.0s' $(seq 1 33))" why > /dev/null
  find "${BOARD}/stories" -type f -exec basename {} \; | sort | paste -sd' ' -
)"
is "retire_fixes retires only the fix-main stories logged before its own" "fix-main-ccccccc.md fix-main-eeeeeee.md" "${older}"
# unit <dir> — a board in <dir> for merge.sh's functions alone, its gh-free helpers stubbed (sourced
# in the caller's subshell).
# shellcheck disable=SC2034 # merge.sh's functions read these
unit() {
  PROJECT_DIR="$1"; BOARD="$1/board"; EVENTS_LOG="$1/events.tsv"; BOARD_IN_REPO=0; SWARM_HOME="${REPO}"; MERGE_TARGET=s
  rm -rf "$1"; mkdir -p "${BOARD}/stories"
}
red_at() { printf '2026-10-18T10:00:00Z\tmain-red\t%s\t-\to/r main test (failure)\n' "$1" >> "${EVENTS_LOG}"; : > "${BOARD}/stories/fix-main-${1:0:7}.md"; }
A40=$(printf 'a%.0s' $(seq 1 40)); B40=$(printf 'b%.0s' $(seq 1 40)); G40=$(printf 'c%.0s' $(seq 1 40))
# Codex's sequence: clear_red_main reads CI for red A, and meanwhile fix_main logs red B. The green
# clears nothing, so B and its fix stay.
# shellcheck disable=SC2034 # merge.sh's functions read these
cx="$(
  unit "${ROOT}/cx"; red_at "${A40}"; : > "${BOARD}/stories/fix-main-${B40:0:7}.md"
  # shellcheck source=/dev/null
  . "${REPO}/bin/lib/merge.sh"
  # shellcheck disable=SC2317,SC2329
  fm() { echo ready; }
  # shellcheck disable=SC2317,SC2329
  one_off_started() { return 1; }
  # shellcheck disable=SC2317,SC2329
  delete_item() { rm "$1"; }
  # shellcheck disable=SC2317,SC2329
  record_event() { printf 'T\t%s\t%s\t-\t%s\n' "$1" "$2" "$3" >> "${EVENTS_LOG}"; }
  # shellcheck disable=SC2317,SC2329
  state_lock() { mkdir "$1"; }
  # shellcheck disable=SC2317,SC2329
  within() { printf '2026-10-18T10:00:01Z\tmain-red\t%s\t-\to/r main test (failure)\n' "${B40}" >> "${EVENTS_LOG}"; }
  clear_red_main "o/r main" "${G40}" "green" > /dev/null
  echo "$(red_mains | cut -d' ' -f1)|$(cut -f2 "${EVENTS_LOG}" | paste -sd, -)|$([ -e "${BOARD}/stories/fix-main-${B40:0:7}.md" ] && echo kept)"
)"
is "a red main logged while clear_red_main reads CI: no main-green, and the newer red and its fix stay" "${B40}|main-red,main-red|kept" "${cx}"
# main-green clears the red it names alone; one naming no red (an older record) clears its key.
# shellcheck disable=SC2034 # merge.sh's functions read these
rm_="$(
  unit "${ROOT}/rm"; red_at "${A40}"; red_at "${B40}"
  # shellcheck source=/dev/null
  . "${REPO}/bin/lib/merge.sh"
  printf '2026-10-18T11:00:00Z\tmain-green\t%s\t-\to/r main %s\n' "${G40}" "${A40}" >> "${EVENTS_LOG}"; one="$(red_mains | cut -d' ' -f1)"
  printf '2026-10-18T11:00:00Z\tmain-green\t%s\t-\to/r main %s\n' "${G40}" "${B40}" >> "${EVENTS_LOG}"; two="$(red_mains | cut -d' ' -f1)"
  red_at "${A40}"; printf '2026-10-18T11:00:00Z\tmain-green\t%s\t-\to/r main\n' "${G40}" >> "${EVENTS_LOG}"
  echo "${one}|${two}|$(red_mains | cut -d' ' -f1)"
)"
is "red_mains: a main-green naming an older red leaves the newer one; naming it, or no red, clears it" "${B40}||" "${rm_}"
# fix_main's lock is freed once, inside it: the next run's lock, taken as this run's subshell ends,
# stays. A .swarm/ it cannot make stops it before it writes anything.
# shellcheck disable=SC2034 # merge.sh's functions read these
tl="$(
  unit "${ROOT}/tl"
  # shellcheck source=/dev/null
  . "${REPO}/bin/lib/merge.sh"
  # shellcheck disable=SC2317,SC2329
  record_event() { :; }
  # shellcheck disable=SC2317,SC2329
  retire_fixes() { :; }
  # shellcheck disable=SC2317,SC2329
  state_lock() { mkdir "$1"; }
  lock="$(fix_lock "o/r main")"
  ( fix_main o/r "${A40}" main "e2e (failure)" > /dev/null; mkdir "${lock}" )
  kept="$([ -d "${lock}" ] && echo kept || echo gone)"; rmdir "${lock}" 2>/dev/null || true
  rm -rf "${PROJECT_DIR}/.swarm"; : > "${PROJECT_DIR}/.swarm"; rm -f "${BOARD}"/stories/*
  frc=0; ( fix_main o/r "${B40}" main "e2e (failure)" > /dev/null ) || frc=$?
  echo "${kept}|${frc}|$(find "${BOARD}/stories" -type f | wc -l | tr -d ' ')"
)"
is "fix_main frees its own lock once, and a .swarm/ it cannot make stops it unwritten" "kept|1|0" "${tl}"
is "a printed merge stands over a signal's status, and nothing else does" "0|0|143|7" \
  "$(qrc 143 "merged ${M}")|$(qrc 3 "merged ")|$(qrc 143 "merged at head 2222222, not 1111111, the head that was checked (merge commit none)")|$(qrc 7 "stopped by SIGTERM")"
# A TERM while it waits on the queue, or during the enqueue: auto-merge off and out of the queue
# before it exits.
qfresh; qread "${FX}/queue" OPEN true null "${G}" -; term_merge isInMergeQueue
check "a TERM while queued: auto-merge off and out of the queue, logged as unconfirmed" \
  logged "^merge s unconfirmed (stopped by SIGTERM): #7 did not merge; auto-merge is off and it is out of the merge queue$"
qfresh; touch "${FX}/queue-sleeps"; qread "${FX}/queue" OPEN true null "${G}" -; term_merge isInMergeQueue
check "a TERM before any read of the queue: stopped by its number, logged as unconfirmed" \
  logged "^merge s unconfirmed (stopped by SIGTERM): #7 did not merge; auto-merge is off and it is out of the merge queue$"
qfresh; touch "${FX}/auto-sleeps"; qread "${FX}/queue" OPEN true null "${G}" -; term_merge "--auto"
check "a TERM during the enqueue: auto-merge off and out of the queue, logged as unconfirmed" \
  logged "^merge s unconfirmed (stopped by SIGTERM): #7 did not merge; auto-merge is off and it is out of the merge queue$"
# A null repository on the queue read is a failed read, tried again, not a crash.
fresh; echo '{"data":{"repository":null}}' > "${FX}/mq.1"; merge "${URL}"
is "a null repository on the queue read: read again, then merges" "0|2" "${rc}|$(grep -c mergeQueue "${ROOT}/gh.log")"
# --release on a base with a merge queue, merge_admin off: refused, naming the queue, with no merge,
# no enqueue and never --admin.
release_pr; echo '{"data":{"repository":{"mergeQueue":{"id":"MQ_1"}}}}' > "${FX}/mq"; echo '[{"type":"merge_queue"}]' > "${FX}/rules"
merge --release "${URL}"
refused "--release on a base with a merge queue, merge_admin off" "--release: main requires a merge queue, which a release must not join"
check "--release on a base with a merge queue, merge_admin off: never passes --admin" bash -c "! grep -q -- '--admin' '${ROOT}/gh.log'"
# A queue that cannot be read (three tries) refuses: a direct merge would enqueue unwatched.
fresh; touch "${FX}/mq.fail"; merge "${URL}"
refused "a queue that cannot be read" "could not read whether main has a merge queue"
is "a queue that cannot be read: tried three times" 3 "$(grep -c mergeQueue "${ROOT}/gh.log")"
# The review rule's own settings: thread resolution, and merge methods that leave out the one used.
fresh "merge_admin = on"; echo '[{"type":"pull_request","parameters":{"required_review_thread_resolution":true}}]' > "${FX}/rules"
merge "${URL}"; refused "merge_admin = on, the review rule's required_review_thread_resolution" "pull_request's required_review_thread_resolution"
fresh "merge_admin = on"; echo '[{"type":"pull_request","parameters":{"required_review_thread_resolution":false,"allowed_merge_methods":["merge","rebase"]}}]' > "${FX}/rules"
merge "${URL}"; refused "merge_admin = on, allowed_merge_methods without squash" "allowed_merge_methods (merge, rebase, not squash)"
fresh "merge_admin = on"; echo '[{"type":"pull_request","parameters":{"allowed_merge_methods":["squash"]}}]' > "${FX}/rules"; merge "${URL}"
is "merge_admin = on, allowed_merge_methods with squash: exits 0" 0 "${rc}"
# Classic fields outside the known-safe set are refused, whatever their name.
fresh "merge_admin = on"; echo '{"required_widget_review":{"enabled":true},"allow_force_pushes":{"enabled":true}}' > "${FX}/branch"
merge "${URL}"; refused "merge_admin = on, an unknown classic field enabled" "branch protection required_widget_review, which --admin would skip"
check "merge_admin = on, an unknown classic field: not allow_force_pushes, which is safe" bash -c "! grep -q allow_force_pushes '${ROOT}/out'"
fresh "merge_admin = on"; echo '{"required_widget_review":{"enabled":false},"enforce_admins":{"enabled":true}}' > "${FX}/branch"; merge "${URL}"
is "merge_admin = on, an unknown classic field disabled: exits 0" 0 "${rc}"
# Branch protection's 404 is unprotected only when GitHub says so; Not Found (no access) refuses.
fresh "merge_admin = on"; rm "${FX}/branch.404"
merge "${URL}"; refused "merge_admin = on, branch protection Not Found" "Not Found (HTTP 404)"

# --- A board merge that makes stories ready notes their epic's running conductor (conduct-e, the
# herdr stub's) at once, through its inbox, once reconcile has pulled the board. origin's main is P's
# HEAD here; put and land commit board files to it from another clone, as a board PR's merge does,
# and bfresh makes origin's tip the merge commit, green. The block ends with P, origin and the clone
# as it found them.
pre_block="$(git -C "${P}" rev-parse HEAD)"
# conduct, which a board merge starts, needs a claude --version: tests/claude_stub.sh answers it.
cp "${REPO}/tests/claude_stub.sh" "${ROOT}/bin/claude"
git clone -q "${ROOT}/origin.git" "${ROOT}/up"; git -C "${P}" fetch -q origin; git -C "${P}" branch -q -u origin/main
INBOX="${P}/.swarm/inbox/conduct-e.md"; rm -rf "${P}/.swarm/inbox"
put() { # <path> <front-matter line>... — a board file in that clone, staged
  mkdir -p "$(dirname "${ROOT}/up/$1")"; { echo ---; printf '%s\n' "${@:2}"; echo ---; } > "${ROOT}/up/$1"; git -C "${ROOT}/up" add -f "$1"
}
land() { git -C "${ROOT}/up" -c user.name=t -c user.email=t@t commit -q -m land; git -C "${ROOT}/up" push -q origin HEAD:main; }
pulled() { git -C "${P}" fetch -q; git -C "${P}" merge -q --ff-only '@{upstream}'; }
# With lead_epics = on: these board PRs set epics active with no ticket, which merge --board's epic
# guard (its own cases above) would refuse; what they test is ready_tell.
bfresh() { # [config line]... — fresh, no story s, the PR the last land's commit, and the merge commit origin's tip (OID), green
  fresh "lead_epics = on" "$@"; rm "${S}"; OID="$(git -C "${ROOT}/up" rev-parse HEAD)"; echo "${OID}" > "${FX}/oid"
  git -C "${ROOT}/up" diff --name-only HEAD~1 HEAD | python3 -c 'import json, sys; print(json.dumps([{"filename": l.strip(), "status": "modified"} for l in sys.stdin]))' > "${FX}/files"
  git -C "${ROOT}/up" diff --name-only HEAD~1 HEAD | wc -l | tr -d ' ' > "${FX}/nfiles"
  checks "${FX}/${OID}.checks" "$(run test completed success)"; statuses "${FX}/${OID}.status"
  wfruns "${FX}/${OID}.runs" "$(run ci completed success "${OID}")"
}
notes() { grep -c '^From the lead' "${INBOX}" 2>/dev/null || true; }
# Already pulled: epic e, its story r0 ready and r2 blocked.
put docs/epics/e.md "status: active"; put docs/stories/r0.md "status: ready" "kind: code" "epic: e"
put docs/stories/r2.md "status: blocked" "kind: code" "epic: e"; land; pulled
# The board PR adds r1, readies r2, and adds b1 with no epic, whose backlog conductor is not running.
put docs/stories/r1.md "status: ready" "kind: code" "epic: e"; put docs/stories/r2.md "status: ready" "kind: code" "epic: e"
put docs/stories/b1.md "status: ready" "kind: code"; land
bfresh; : > "${ROOT}/agents.log"; merge HERDR_ENV=1 HERDR_PANE_ID=w:lead --board "${URL}"
is "a board merge that readies r1 and r2: exits 0" 0 "${rc}"
is "a board merge that readies r1 and r2: one note to conduct-e" 1 "$(notes)"
check "a board merge that readies r1 and r2: the note names both, not r0" \
  grep -qF "The board PR ${URL} just merged, and these stories of epic e are ready now: r1 r2. Start them now" "${INBOX}"
check "a board merge that readies r1 and r2: says it noted conduct-e" said "noted conduct-e"
check "a board merge that readies a backlog story with no conductor: says none runs yet" \
  said "ready now: b1 (with no epic); no conductor runs for it yet"
# No conductor holds b1, so the merge starts the backlog's (conduct, against the herdr stub); conduct-e runs already.
check "a board merge that readies a backlog story, with only an epic conductor running: starts conduct --backlog" \
  grep -q "^agent start conduct-backlog-proj-[0-9a-f]\{6\} " "${ROOT}/agents.log"
check "a board merge that readies a backlog story: says it started the backlog conductor" said "(swarm.sh conduct --backlog)"
check "a board merge that readies stories of an epic whose conductor runs: starts no second one" \
  bash -c "! grep -q '^agent start conduct-e ' '${ROOT}/agents.log' && ! grep -qF 'swarm.sh conduct e' '${ROOT}/out'"
# It edits r0, ready already: not newly ready.
put docs/stories/r0.md "status: ready" "kind: code" "epic: e" "estimate_lines: 2"; land
bfresh; merge --board "${URL}"
is "a board merge that readies nothing: exits 0" 0 "${rc}"
is "a board merge that readies nothing: no note" 1 "$(notes)"
check "a board merge that readies nothing: says nothing of ready stories" bash -c "! grep -qE 'ready now|noted' '${ROOT}/out'"
# A reconcile pulls the board during the CI wait: what was ready is read before the merge.
put docs/stories/r4.md "status: ready" "kind: code" "epic: e"; land
bfresh; echo "git -C '${P}' fetch -q && git -C '${P}' merge -q --ff-only '@{upstream}'" > "${FX}/on-merge"; merge --board "${URL}"
check "a board merge whose board a reconcile pulled during the CI wait: still notes r4" \
  grep -qF "these stories of epic e are ready now: r4." "${INBOX}"
# q's PR merged, deleting q.md, and is not reconciled yet: reconcile clears its build before it pulls.
put docs/stories/q.md "status: review" "kind: code" "epic: e" "prs: https://github.com/o/r/pull/9"; land; pulled
git -C "${ROOT}/up" rm -q docs/stories/q.md; put docs/stories/r5.md "status: ready" "kind: code" "epic: e"; land
bfresh; merge --board "${URL}"
check "a board merge whose pull deletes q, in review: reconcile finishes q" logged "^reconcile q ok"
check "a board merge whose pull deletes q, in review: still notes r5" grep -qF "these stories of epic e are ready now: r5." "${INBOX}"
# A story of a draft epic is not ready to build: no conductor starts for it.
put docs/epics/d.md "status: draft"; put docs/stories/d1.md "status: ready" "kind: code" "epic: d"; land
bfresh; : > "${ROOT}/agents.log"; merge HERDR_ENV=1 HERDR_PANE_ID=w:lead --board "${URL}"
is "a board merge that readies a draft epic's story: exits 0" 0 "${rc}"
check "a board merge that readies a draft epic's story: starts no conductor" bash -c "! grep -q '^agent start' '${ROOT}/agents.log'"
check "a board merge with the backlog conductor running: starts no second one" bash -c "! grep -qF 'conduct --backlog' '${ROOT}/out'"
# Two board PRs merge one after the other before either pulls: this one (r10's) names r10 alone,
# though it also edits epic e, active already.
put docs/stories/r9.md "status: ready" "kind: code" "epic: e"; land
put docs/stories/r10.md "status: ready" "kind: code" "epic: e"; put docs/epics/e.md "status: active" "title: e10"; land
bfresh; merge --board "${URL}"
check "a board merge beside another board PR: the note names its own r10, not r9" grep -qF "these stories of epic e are ready now: r10." "${INBOX}"
# z's PR closed unmerged: reconcile sends z back to ready, which the PR did not do, so no note names it,
# though the PR also edits z's file. z has a build's worktree, which reconcile removes.
put docs/stories/z.md "status: review" "kind: code" "epic: e" "prs: https://github.com/o/r/pull/11"; land; pulled
git -C "${P}" worktree add -q -b story/z "${ROOT}/proj-wt/z"
put docs/stories/r8.md "status: ready" "kind: code" "epic: e"
put docs/stories/z.md "status: review" "kind: code" "epic: e" "prs: https://github.com/o/r/pull/11" "estimate_lines: 3"; land
bfresh; echo CLOSED > "${FX}/state.11"; merge --board "${URL}"
check "a board merge whose reconcile reopens z: z is back to ready" said "back to ready: z"
check "a board merge whose reconcile reopens z: the note names r8 alone" grep -qF "these stories of epic e are ready now: r8." "${INBOX}"
rm -rf "${ROOT}/proj-wt"; git -C "${P}" worktree prune
# A red main: no conductor is told to start builds on it, not even of r11, which this PR readies.
put docs/stories/r11.md "status: ready" "kind: code" "epic: e"; land
bfresh; checks "${FX}/${OID}.checks" "$(run test completed failure)"; merge --board "${URL}"
check "a board merge onto a red main: tells no conductor of r11" bash -c "! grep -q 'ready now' '${ROOT}/out' && ! grep -q r11 '${INBOX}'"
rm -f "${P}/docs/stories/fix-main-${OID:0:7}.md"
# A PR that only sets epic f active readies f1, ready already: f has no conductor, so the merge says to start one.
put docs/epics/f.md "status: draft"; put docs/stories/f1.md "status: ready" "kind: code" "epic: f"; land; pulled
put docs/epics/f.md "status: active"; land
bfresh; merge --board "${URL}"
check "a board merge that sets epic f active: says f1 is ready with no conductor" said "ready now: f1 (of epic f); no conductor runs for it yet"
check "a board merge that sets epic f active, outside herdr: says to run conduct f" said "no conductor: run swarm.sh conduct f for its ready stories"
# A conductor's own board merge (SWARM_AGENT set, merge = agent) starts k1's conductor too, as the lead's would.
put docs/epics/k.md "status: active"; put docs/stories/k1.md "status: ready" "kind: code" "epic: k"; land
bfresh "merge = agent"; : > "${ROOT}/agents.log"; merge SWARM_AGENT=conduct-e HERDR_ENV=1 HERDR_PANE_ID=w:c --board "${URL}"
check "a conductor's board merge: starts conduct-k" grep -q '^agent start conduct-k ' "${ROOT}/agents.log"
check "a conductor's board merge: says it started conduct-k" said "started: conduct-k (swarm.sh conduct k)"
# conduct-e stopped on an API error: a conductor started for m1 now would stop on it too.
put docs/epics/m.md "status: active"; put docs/stories/m1.md "status: ready" "kind: code" "epic: m"; land
bfresh; : > "${ROOT}/agents.log"; printf '%s\n' '⏺ API Error: Connection dropped (ECONNRESET)' > "${ROOT}/agents.screen.w:c"
merge HERDR_ENV=1 HERDR_PANE_ID=w:lead --board "${URL}"; rm "${ROOT}/agents.screen.w:c"
check "a board merge while a conductor is stopped on an API error: starts no conductor" bash -c "! grep -q '^agent start' '${ROOT}/agents.log'"
check "a board merge while a conductor is stopped on an API error: says why" said "no conductor started: conduct-e stopped on an API error"
# o1, with no epic, was blocked and has a worktree (its build started): readied, it is not new.
put docs/stories/o1.md "status: blocked" "kind: code"; land; pulled; mkdir -p "${ROOT}/proj-wt/o1"
put docs/stories/o1.md "status: ready" "kind: code"; land
bfresh; merge --board "${URL}"
check "a board merge that readies o1, already started: says nothing of o1" bash -c "! grep -qw o1 '${ROOT}/out' && ! grep -rqw o1 '${P}/.swarm/inbox'"
rm -rf "${ROOT}/proj-wt"
# Board PR A, merged and never pulled here, sets epic g active and readies r12; this PR, B, only
# edits g's and r12's files. What was ready is the board at B's first parent, so B names neither.
put docs/epics/g.md "status: draft"; put docs/stories/g1.md "status: ready" "kind: code" "epic: g"
put docs/stories/r12.md "status: blocked" "kind: code" "epic: e"; land; pulled
put docs/epics/g.md "status: active"; put docs/stories/r12.md "status: ready" "kind: code" "epic: e"; land
put docs/epics/g.md "status: active" "title: g2"; put docs/stories/r12.md "status: ready" "kind: code" "epic: e" "estimate_lines: 1"; land
bfresh; merge --board "${URL}"
check "a board merge after an unpulled one: names neither g1 nor r12" bash -c "! grep -qE 'g1|r12' '${ROOT}/out' && ! grep -q r12 '${INBOX}'"
# conduct-e has written its report: it has finished, so it gets no note, and r13 has no conductor yet.
put docs/stories/r13.md "status: ready" "kind: code" "epic: e"; land
bfresh; touch "${P}/.swarm/conduct-e.report.md"; merge --board "${URL}"; rm "${P}/.swarm/conduct-e.report.md"
check "a board merge whose conductor has reported: says r13 has no conductor yet" said "ready now: r13 (of epic e); no conductor runs for it yet"
check "a board merge whose conductor has reported: no note names r13" bash -c "! grep -q r13 '${INBOX}'"
check "a board merge whose conductor has reported: says to collect it first" said "no conductor started: conduct-e has reported; collect it first"
# r15, ready in draft epic h, moves to epic e: it was not buildable before, so it is new.
put docs/epics/h.md "status: draft"; put docs/stories/r15.md "status: ready" "kind: code" "epic: h"; land; pulled
put docs/stories/r15.md "status: ready" "kind: code" "epic: e"; land
bfresh; merge --board "${URL}"
check "a board merge that moves ready r15 into active epic e: notes it" grep -qF "these stories of epic e are ready now: r15." "${INBOX}"
# Through a merge queue, in one push with a later PR (its commit Y, the batch's tip): what was ready
# is read at the parent of this PR's own merge commit X, not at Y's, where r14 is ready already.
put docs/stories/r14.md "status: ready" "kind: code" "epic: e"; land; X="$(git -C "${ROOT}/up" rev-parse HEAD)"
put docs/stories/r0.md "status: ready" "kind: code" "epic: e" "estimate_lines: 4"; land
bfresh; echo '[{"filename":"docs/stories/r14.md","status":"added"}]' > "${FX}/files"; echo 1 > "${FX}/nfiles"
echo '{"data":{"repository":{"mergeQueue":{"id":"MQ_1"}}}}' > "${FX}/mq"; checks "${FX}/${G}.checks" "$(run test completed success)"; statuses "${FX}/${G}.status"
qread "${FX}/queue.1" OPEN true null "${G}" -; qread "${FX}/queue.2" MERGED false null - "${X}"
printf '{"commit":{"sha":"%s"}}\n' "${OID}" > "${FX}/basehead"; echo '{"status":"ahead"}' > "${FX}/compare"; merge --board "${URL}"
check "a queued board merge batched with a later PR: notes r14" grep -qF "these stories of epic e are ready now: r14." "${INBOX}"
# A two-commit PR rebased onto main: the first readies r16, the second edits it. The board before
# it is two commits back, where r16 did not exist.
put docs/stories/r16.md "status: ready" "kind: code" "epic: e"; land
put docs/stories/r16.md "status: ready" "kind: code" "epic: e" "estimate_lines: 5"; land
bfresh; echo '{"squashMergeAllowed":false,"mergeCommitAllowed":false,"rebaseMergeAllowed":true}' > "${FX}/repo"; echo '[{},{}]' > "${FX}/commits"
merge --board "${URL}"
check "a rebased two-commit board PR: notes r16" grep -qF "these stories of epic e are ready now: r16." "${INBOX}"
# This PR (P) only edits blocked r17; a later PR readies it, and the pull brings both: P made
# nothing live, so it names nothing.
put docs/stories/r17.md "status: blocked" "kind: code" "epic: e"; land; pulled
put docs/stories/r17.md "status: blocked" "kind: code" "epic: e" "estimate_lines: 6"; land; PC="$(git -C "${ROOT}/up" rev-parse HEAD)"
put docs/stories/r17.md "status: ready" "kind: code" "epic: e" "estimate_lines: 6"; land
bfresh; echo "${PC}" > "${FX}/oid"; checks "${FX}/${PC}.checks" "$(run test completed success)"; statuses "${FX}/${PC}.status"
wfruns "${FX}/${PC}.runs" "$(run ci completed success "${PC}")"; merge --board "${URL}"
check "a board merge pulled with a later PR that readies r17: names r17 nowhere" bash -c "! grep -q r17 '${ROOT}/out' && ! grep -q r17 '${INBOX}'"
# herdr cannot list its agents: no ready now: line, which would say no conductor runs.
put docs/stories/r7.md "status: ready" "kind: code" "epic: e"; land
bfresh; touch "${ROOT}/agents.fail"; merge --board "${URL}"; rm "${ROOT}/agents.fail"
check "a board merge while herdr cannot list its agents: says conduct-e was not told" \
  said "warning: herdr cannot list its agents, so conduct-e was not told that r7 are ready"
check "a board merge while herdr cannot list its agents: no ready now: line" bash -c "! grep -q 'ready now' '${ROOT}/out'"
check "a board merge outside herdr while herdr cannot list its agents: says what runs is not known" \
  said "warning: herdr cannot list its agents, so which conductors run is not known; none was started for ready work"
check "a board merge outside herdr while herdr cannot list its agents: tells no one to run conduct" bash -c "! grep -q 'no conductor: run' '${ROOT}/out'"
# reconcile cannot fetch (origin gone while CI ran), so exits 0 without pulling: a warning, not silence.
# Nor does it start a conductor from the unpulled board, though b1 is ready and the backlog's is gone.
printf 'conduct-e w:c\nt w:b\n' > "${ROOT}/agents"
put docs/stories/r6.md "status: ready" "kind: code" "epic: e"; land
bfresh; : > "${ROOT}/agents.log"; echo "git -C '${P}' remote set-url origin '${ROOT}/gone.git'" > "${FX}/on-merge"
merge HERDR_ENV=1 HERDR_PANE_ID=w:lead --board "${URL}"
git -C "${P}" remote set-url origin "${ROOT}/origin.git"
is "a board merge that reconcile did not pull: exits 0" 0 "${rc}"
check "a board merge that reconcile did not pull: warns that no conductor was told" \
  said "warning: reconcile did not pull ${OID:0:7} into ${P}, so no conductor was told what ${URL} made ready; run swarm.sh reconcile"
check "a board merge that reconcile did not pull: starts no conductor" \
  bash -c "! grep -q '^agent start' '${ROOT}/agents.log' && ! grep -qF 'conduct --backlog' '${ROOT}/out'"
# reconcile fails (r6 is edited here, and the pull changes it): logged as merge logs it, and a warning.
pulled; echo edit >> "${P}/docs/stories/r6.md"; put docs/stories/r6.md "status: ready" "kind: code" "epic: e" "estimate_lines: 1"; land
bfresh; : > "${ROOT}/agents.log"; merge HERDR_ENV=1 HERDR_PANE_ID=w:lead --board "${URL}"
is "a board merge whose reconcile fails: exits 0" 0 "${rc}"
check "a board merge whose reconcile fails: logs its die line under reconcile" logged "^reconcile - reconcile: cannot pull"
check "a board merge whose reconcile fails: warns to run swarm.sh reconcile" \
  bash -c "grep -q 'warning: reconcile failed after the merge (reconcile: cannot pull' '${ROOT}/out' && grep -q 'run swarm.sh reconcile\$' '${ROOT}/out'"
check "a board merge whose reconcile fails: starts no conductor" \
  bash -c "! grep -q '^agent start' '${ROOT}/agents.log' && ! grep -qF 'conduct --backlog' '${ROOT}/out'"
git -C "${P}" show HEAD:docs/stories/r6.md > "${P}/docs/stories/r6.md"
put docs/stories/r3.md "status: ready" "kind: code" "epic: e"; land
rm -rf "${P}/.swarm/inbox"; : > "${P}/.swarm/inbox"   # the note cannot be written
bfresh; merge --board "${URL}"
is "a board merge whose tell fails: exits 0" 0 "${rc}"
check "a board merge whose tell fails: warns" said "warning: could not note conduct-e that r3 are ready"
# Leave P, origin and the clone as the block found them.
rm -f "${P}/.swarm/inbox"; git -C "${P}" branch -q --unset-upstream; printf 'conduct-e w:c\nt w:b\n' > "${ROOT}/agents"
git -C "${P}" reset -q --hard "${pre_block}"; git -C "${P}" push -q -f origin "${pre_block}:refs/heads/main"
rm -rf "${ROOT}/up" "${P}/.swarm/board-state"/stories/{r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12,r13,r14,r15,r16,r17,b1,d1,f1,g1,k1,m1,o1,q,z} "${P}/docs/epics/e.md"

finish merge-queue
