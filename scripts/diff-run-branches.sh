#!/usr/bin/env bash
# diff-run-branches.sh — the head branches whose allow-list entries the diff-run workflow's
# `tests/diff_run.sh --base` applies, one a line, each passed to it as --branch.
# A pull_request run has one: the PR's own head branch (HEAD_REF).
# A merge_group run has one per PR in the group, since the group's head holds them all: the entries
# of BASE_REF's merge queue, by position, up to and including the one whose head commit is HEAD_SHA,
# each by its PR's head branch (GraphQL's mergeQueue). A merge group whose entry is not in the queue,
# or a queue that cannot be read, is an error, never an empty list.
# Env: GITHUB_EVENT_NAME, HEAD_REF (pull_request), BASE_REF and HEAD_SHA (merge_group),
# GITHUB_REPOSITORY; gh reads GH_TOKEN.
# Exit 0 with the branches printed; 1, with why on stderr, otherwise.
set -euo pipefail

fail() { echo "diff-run-branches: $*" >&2; exit 1; }

case "${GITHUB_EVENT_NAME:-}" in
  pull_request)
    [[ -n "${HEAD_REF:-}" ]] || fail "a pull_request run needs HEAD_REF, the PR's head branch"
    printf '%s\n' "${HEAD_REF}" ;;
  merge_group)
    [[ "${HEAD_SHA:-}" =~ ^[0-9a-f]{40}$ ]] || fail "a merge_group run needs HEAD_SHA, the group's head commit"
    [[ "${GITHUB_REPOSITORY:-}" == */* ]] || fail "a merge_group run needs GITHUB_REPOSITORY as <owner>/<repo>"
    base="${BASE_REF#refs/heads/}"
    [[ -n "${base}" ]] || fail "a merge_group run needs BASE_REF, the queue's branch"
    # shellcheck disable=SC2016 # GraphQL's variables
    query='query($o: String!, $r: String!, $b: String!) { repository(owner: $o, name: $r) {
      mergeQueue(branch: $b) { entries(first: 100) { pageInfo { hasNextPage }
        nodes { position headCommit { oid } pullRequest { number headRefName } } } } } }'
    json="$(gh api graphql -f query="${query}" -f o="${GITHUB_REPOSITORY%%/*}" -f r="${GITHUB_REPOSITORY#*/}" -f b="${base}")" \
      || fail "gh cannot read ${GITHUB_REPOSITORY}'s merge queue on ${base}"
    JSON="${json}" python3 -c '
import json, os, sys
head, base = sys.argv[1], sys.argv[2]
try:
    q = json.loads(os.environ["JSON"])["data"]["repository"]["mergeQueue"]
except (ValueError, KeyError, TypeError):
    sys.exit("diff-run-branches: the merge queue read is no GraphQL answer")
if q is None:
    sys.exit("diff-run-branches: %s has no merge queue" % base)
nodes = sorted(q["entries"]["nodes"], key=lambda n: n["position"])
mine = [n for n in nodes if (n.get("headCommit") or {}).get("oid") == head]
if len(mine) != 1:
    more = ", and the queue has more entries than one read gives" if q["entries"]["pageInfo"]["hasNextPage"] else ""
    sys.exit("diff-run-branches: no entry in %s'"'"'s merge queue has head commit %s%s" % (base, head, more))
for n in nodes:
    if n["position"] <= mine[0]["position"]:
        print(n["pullRequest"]["headRefName"])
' "${HEAD_SHA}" "${base}" || exit 1 ;;
  *) fail "a ${GITHUB_EVENT_NAME:-local} run has no PR, so no head branch" ;;
esac
