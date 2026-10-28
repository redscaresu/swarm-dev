#!/usr/bin/env bash
# merge_base_update_wait_test.sh — once swarm.sh merge has had GitHub merge a moved base into a story
# PR's branch (merge_base_update_test.sh has that step), it waits for green on the new head (ci_gate
# head polled, with the workflows a pull_request runs), checks the base again right before gh pr merge,
# and merges the new head with --match-head-commit. A base that moved again is merged in and waited on
# again, for MERGE_BASE_ROUNDS rounds at most. A red new head, no check runs, a timeout and a base still
# moving refuse, naming the cause and telling the builder to pull its branch first, with no pr merge.
# watch sends no head merge made this way to review, and still reports a builder's later push. On
# merge_fixture.sh, whose stub serves the base's gain per head (behind.<head>), the head GitHub's merge
# makes per head (update-head.<head>), each commit (commit.<sha>) and each compare (compare.<a>...<b>).
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
# Merging the base in waits for the new head's CI, whose first read also reads its workflows: 60 s for it.
# shellcheck disable=SC2034 # merge_fixture.sh's merge reads it
MERGE_CI=60

# The PR's heads after each merge of main, and main's head at each.
H3=3333333333333333333333333333333333333333; H4=4444444444444444444444444444444444444444
H5=5555555555555555555555555555555555555555
B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; B2=dddddddddddddddddddddddddddddddddddddddd
B3=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
# PRX — the PR's own change, which no merge of main touches.
PRX='{"filename":"bin/pr.sh","status":"modified","sha":"p1"}'
# moves <old> <new> <second> <file> — main gained <file> after <old>'s CI ran, and GitHub's merge of
# main into the PR's branch at <old> makes <new>: a merge of <old> and <second> (main's head from now
# on), as web-flow with its signature verified, that changes only <file>, as <second> has it. <new> has
# one green check run and no status; with no behind.<new>, it is up to date with main.
moves() {
  local x="{\"filename\":\"$4\",\"status\":\"modified\",\"sha\":\"${3:0:7}\"}"
  echo "{\"ahead_by\":1,\"files\":[${x}]}" > "${FX}/behind.$1"
  echo "$2" > "${FX}/update-head.$1"; echo '{"message":"Updating pull request branch."}' > "${FX}/update"
  printf '{"committer":{"login":"web-flow"},"commit":{"verification":{"verified":true}},"parents":[{"sha":"%s"},{"sha":"%s"}]}\n' "$1" "$3" > "${FX}/commit.$2"
  echo "{\"files\":[${x}]}" > "${FX}/compare.$1...$2"; echo "{\"files\":[${x}]}" > "${FX}/compare.$1...$3"
  echo "{\"files\":[${PRX}]}" > "${FX}/compare.$3...$1"
  printf '{"commit":{"sha":"%s"}}\n' "$3" > "${FX}/basehead"
  checks "${FX}/$2.checks" "$(run test completed success)"; statuses "${FX}/$2.status"
}
merged_at() { grep -qxF "pr merge 7 --repo o/r --squash --match-head-commit $1" "${ROOT}/gh.log"; }
not_merged_at() { ! merged_at "$1"; }
merge_events() { events | grep '^merge ' | paste -sd'|' -; }
reads_of() { grep -c "commits/$1/check-runs" "${ROOT}/gh.log" || true; }
# line_of <text> — the gh.log line number of the first call holding <text>, else 0.
line_of() { grep -nF -- "$1" "${ROOT}/gh.log" | head -1 | cut -d: -f1 | grep . || echo 0; }
PULL="the builder pulls its branch (git pull --ff-only) before it pushes: GitHub's merge commit is not in its worktree"
WHO="${URL}'s head 3333333 (1111111 with main merged in)"
NEXT="wait-pr --head ${H3} ${URL}, then merge --head ${H3} ${URL}; ${PULL}"
MERGED3="merge s base-merged ${H3} from ${H1}"
# refused_after <name> <cause> <text>... — the last merge merged main in (${MERGED3}), then refused, its
# events.tsv line starting <cause>:, saying each <text>, with no pr merge; events.tsv has the base-merged
# line, then the refusal.
refused_after() {
  local name="$1" cause="$2" t; shift 2
  is "${name}: exits non-zero" 1 "${rc}"
  for t in "$@"; do check "${name}: says ${t}" said "${t}"; done
  check "${name}: no pr merge" not_merged
  is "${name}: base-merged, then the refusal" "${MERGED3}|merge s ${cause}:" \
    "$(events | grep '^merge ' | sed -E 's/^(merge s [^:]*:).*/\1/' | paste -sd'|' -)"
}

# --- main moved: merge merges it in, waits for the new head's green, checks main again, merges that head.
fresh; moves "${H1}" "${H3}" "${B}" bin/x.sh; checks "${FX}/${H3}.checks.1" "$(run test in_progress)"; merge "${URL}"
is "a moved base: exits 0" 0 "${rc}"
check "a moved base: says main merged in, and that it waits for the new head's CI" said \
  "base merged: ${URL} is now 3333333 (1111111 with main merged in); waiting up to 60s for its CI"
is "a moved base: reads the new head's checks until they are green (in progress, then green)" 2 "$(reads_of "${H3}")"
check "a moved base: merges the new head, pinned with --match-head-commit" merged_at "${H3}"
check "a moved base: never merges the old head" not_merged_at "${H1}"
is "a moved base: events.tsv has base-merged with the head it was made from, then merge ok" "${MERGED3}|merge s ok" "$(merge_events)"
green_at="$(grep -n "commits/${H3}/check-runs" "${ROOT}/gh.log" | tail -1 | cut -d: -f1)"
is "a moved base: compares the new head with main after its green read, before the merge" "yes" \
  "$(c="$(line_of "compare/${H3}...main")"; (( green_at < c && c < $(line_of "pr merge") )) && echo yes || echo no)"

# --- main moves again while the new head's CI runs: main is at B when GitHub makes H3, H3's CI is still
# running on its first read, and main is at B2, with bin/y.sh, once H3 is green. merge merges main in
# again after that green, waits again, and merges the second new head.
fresh; moves "${H1}" "${H3}" "${B}" bin/x.sh; moves "${H3}" "${H4}" "${B2}" bin/y.sh
printf '{"commit":{"sha":"%s"}}\n' "${B}" > "${FX}/basehead.1"; checks "${FX}/${H3}.checks.1" "$(run test in_progress)"; merge "${URL}"
is "a second move: exits 0" 0 "${rc}"
check "a second move: asks GitHub again, pinned to the first new head" \
  grep -qxF "api -X PUT -f expected_head_sha=${H3} repos/o/r/pulls/7/update-branch" "${ROOT}/gh.log"
is "a second move: waits for each new head's CI (H3 in progress, then green)" "2|1" "$(reads_of "${H3}")|$(reads_of "${H4}")"
green_at="$(grep -n "commits/${H3}/check-runs" "${ROOT}/gh.log" | tail -1 | cut -d: -f1)"
is "a second move: compares H3 with main after its green read, then asks GitHub to merge main in again" "yes" \
  "$(c="$(line_of "compare/${H3}...main")"; (( green_at < c && c < $(line_of "expected_head_sha=${H3}") )) && echo yes || echo no)"
check "a second move: merges the second new head" merged_at "${H4}"
check "a second move: not the first" not_merged_at "${H3}"
is "a second move: events.tsv has both base-merged lines, each with the head it was made from, then merge ok" \
  "${MERGED3}|merge s base-merged ${H4} from ${H3}|merge s ok" "$(merge_events)"
# GitHub cannot merge main in on the second round: the builder's worktree lacks GitHub's first merge.
fresh; moves "${H1}" "${H3}" "${B}" bin/x.sh; echo '{"ahead_by":1,"files":[{"filename":"bin/y.sh","status":"modified"}]}' > "${FX}/behind.${H3}"
echo "merge conflict between base and head" > "${FX}/update.422.${H3}"; merge "${URL}"
refused_after "a conflict on the second round" "the base main moved past 3333333's CI (1 commits it lacks), and GitHub cannot merge it in, a conflict (HTTP 422" \
  "the base main moved past 3333333's CI (1 commits it lacks), and GitHub cannot merge it in, a conflict (HTTP 422: merge conflict between base and head): pull the branch first (it holds GitHub's merge 3333333), then merge origin/main in, push, and merge the new head"

# A head an earlier merge run made (events.tsv's base-merged line) is GitHub's merge too: a later run's
# refusals say to pull first. So does a base check that fails after this run merged the base in.
fresh; echo "${H3}" > "${FX}/head"; checks "${FX}/${H3}.checks" "$(run test completed success)"; statuses "${FX}/${H3}.status"
printf '2026-10-28T00:00:00Z\tmerge\ts\t-\tbase-merged %s from %s\n' "${H3}" "${H1}" > "${P}/.swarm/events.tsv"
echo '{"ahead_by":1,"files":[{"filename":"bin/y.sh","status":"modified"}]}' > "${FX}/behind.${H3}"
echo "merge conflict between base and head" > "${FX}/update.422.${H3}"; merge "${URL}"
is "a head an earlier merge run made, and GitHub cannot merge main in again: says to pull the branch first, and merges nothing" "1|yes|no" \
  "${rc}|$(said "a conflict (HTTP 422: merge conflict between base and head): pull the branch first (it holds GitHub's merge 3333333), then merge origin/main in, push, and merge the new head" && echo yes)|$(merged && echo yes || echo no)"
# A head an earlier merge run made gets the same wait as one this run makes: a run of merge on it
# waits on the workflows a pull_request runs, which merge's plain check on the head does not read.
fresh; echo "${H3}" > "${FX}/head"; checks "${FX}/${H3}.checks" "$(run test completed success)"; statuses "${FX}/${H3}.status"
printf '2026-10-28T00:00:00Z\tmerge\ts\t-\tbase-merged %s from %s\n' "${H3}" "${H1}" > "${P}/.swarm/events.tsv"
wfruns "${FX}/${H3}.runs"; printf 'name: ci\non:\n  pull_request:\n    types: [opened, synchronize]\n' > "${FX}/wf.ci.yml.${H3}"; merge --head "${H3}" "${URL}"
is "merge --head on a head an earlier merge run made waits on its pull_request workflows: one with no run refuses, no pr merge" "1|yes|no" \
  "${rc}|$(said "base merged, no workflow run: ${WHO}: .github/workflows/ci.yml: a pull_request into main runs it" && echo yes)|$(merged && echo yes || echo no)"
fresh; moves "${H1}" "${H3}" "${B}" bin/x.sh; echo x > "${FX}/behind.${H3}"; touch "${FX}/behind.${H3}.fail"; merge "${URL}"
refused_after "a base check that fails after the base merged in" "cannot tell whether main moved past 3333333's CI" \
  "cannot tell whether main moved past 3333333's CI: " "${PULL}"

# --- main moves on every round: after MERGE_BASE_ROUNDS (3) rounds merge refuses, naming them, and merges nothing.
fresh; moves "${H1}" "${H3}" "${B}" bin/x.sh; moves "${H3}" "${H4}" "${B2}" bin/y.sh; moves "${H4}" "${H5}" "${B3}" bin/z.sh
echo '{"ahead_by":1,"files":[{"filename":"bin/w.sh","status":"modified"}]}' > "${FX}/behind.${H5}"; merge "${URL}"
is "a base moving on every round: exits non-zero" 1 "${rc}"
check "a base moving on every round: refuses after 3 rounds, naming them and the wait-pr and merge --head of the last new head" said \
  "base merged, still moving: main gained code 5555555 lacks again after 3 rounds of merging it into ${URL} and waiting for CI (MERGE_BASE_ROUNDS); 5555555 is green on main as it was: once main is quiet, wait-pr --head ${H5} ${URL}, then merge --head ${H5} ${URL}; ${PULL}"
check "a base moving on every round: no pr merge" not_merged
is "a base moving on every round: three requests to merge main in, three base-merged lines, then the refusal" "3|3|merge s base merged, still moving:" \
  "$(grep -c '/update-branch$' "${ROOT}/gh.log")|$(merge_events | tr '|' '\n' | grep -c 'base-merged')|$(merge_events | tr '|' '\n' | tail -1 | cut -d: -f1):"

# --- The PR merged elsewhere (another merge run, or by hand) while this one waited on the new head's
# CI: the PR reads MERGED from then on, and main holds that merge. This run says so, merges nothing,
# logs no merge ok and reconciles, as nothing else may.
landed() {
  moves "${H1}" "${H3}" "${B}" bin/x.sh; echo '{"ahead_by":1,"files":[{"filename":"bin/pr.sh","status":"modified"}]}' > "${FX}/behind.${H3}"
  echo "echo MERGED > '${FX}/state'" > "${FX}/on-checks.${H3}"
}
fresh; landed; merge "${URL}"
is "a PR merged elsewhere during the wait: exits 0, one request to merge main in, no pr merge, no merge ok" \
  "0|1|no|${MERGED3}|merge s merged elsewhere" \
  "${rc}|$(grep -c '/update-branch$' "${ROOT}/gh.log")|$(merged && echo yes || echo no)|$(merge_events)"
check "a PR merged elsewhere during the wait: says so" said "already merged: ${URL} merged while this run waited on 3333333, by another swarm.sh merge or by hand; reconciling"
check "a PR merged elsewhere during the wait: reconciles the story it finished" logged "^reconcile s "
fresh "merge_admin = on"; landed; merge "${URL}"
is "merge_admin = on, a PR merged elsewhere during the wait: exits 0 with no --admin refusal" "0|no" \
  "${rc}|$(said "--admin may not merge" && echo yes || echo no)"

# --- A push while merge waits: the PR's head is no longer the one GitHub's merge made.
fresh; moves "${H1}" "${H3}" "${B}" bin/x.sh; echo "${H5}" > "${FX}/move-head.${H3}"; merge "${URL}"
refused_after "a push during the wait, the new head green" "base merged, head moved" \
  "base merged, head moved: ${URL}'s head moved from 3333333, GitHub's merge of main, to 5555555 while merge waited on its CI: review the new head as for any new head" "${PULL}"
fresh; moves "${H1}" "${H3}" "${B}" bin/x.sh; checks "${FX}/${H3}.checks" "$(run test completed failure)"; echo "${H5}" > "${FX}/move-head.${H3}"; merge "${URL}"
refused_after "a push during the wait, the new head red: the push, not the red" "base merged, head moved" \
  "to 5555555 while merge waited on its CI: review the new head as for any new head" "${PULL}"

# --- merge cannot take its lock again after the wait: another merge into main holds it.
fresh; moves "${H1}" "${H3}" "${B}" bin/x.sh
printf 'mkdir -p "%s"; echo %s > "%s/pid"\n' "${P}/.swarm/merge-o-r-main.lock" "$$" "${P}/.swarm/merge-o-r-main.lock" > "${FX}/on-checks.${H3}"
merge SWARM_MERGE_LOCK_WAIT=1 "${URL}"; rm -rf "${P}/.swarm/merge-o-r-main.lock"
refused_after "the lock held by another merge after the wait" "another swarm.sh merge into main of o/r has held ${P}/.swarm/merge-o-r-main.lock (pid $$) for 1s; nothing was merged" \
  "nothing was merged: GitHub's merge of main made 3333333, which is green: once that merge is done, ${NEXT}"

# --- merge_admin = on: --admin skips every rule on main, so ci_gate admin checks the new head too, not only
# the head merge read: main requires lint, which ran on the old head.
admin_lint() {
  fresh "merge_admin = on"; echo '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"lint"}]}}]' > "${FX}/rules"
  checks "${FX}/${H1}.checks" "$(run test completed success)" "$(run lint completed success)"; moves "${H1}" "${H3}" "${B}" bin/x.sh
}
admin_lint; merge "${URL}"
refused_after "merge_admin = on, a check main requires with no run on the new head" "--admin may not merge 3333333 into main" \
  "--admin may not merge 3333333 into main: lint (required, absent); ${PULL}"
admin_lint; checks "${FX}/${H3}.checks" "$(run test completed success)" "$(run lint completed success)"; merge "${URL}"
is "merge_admin = on, the required check green on the new head too: merges it with --admin" "0|yes" \
  "${rc}|$(grep -qxF "pr merge 7 --repo o/r --squash --match-head-commit ${H3} --admin" "${ROOT}/gh.log" && echo yes)"

# --- The new head is not green: merge refuses, naming the cause, and merges nothing.
fresh; moves "${H1}" "${H3}" "${B}" bin/x.sh; checks "${FX}/${H3}.checks" "$(run test completed failure)"; merge "${URL}"
refused_after "a red new head" "base merged, red" "base merged, red: ${WHO} is red: test (failure) https://github.com/o/r/runs/test; ${PULL}, then fixes it and pushes"
fresh; moves "${H1}" "${H3}" "${B}" bin/x.sh; checks "${FX}/${H3}.checks"; merge "${URL}"
refused_after "no check runs on the new head" "base merged, no check runs" \
  "base merged, no check runs: ${WHO}: no check runs on 3333333 after " "(no check runs): ${NEXT}"
# None on the first read is no refusal while MERGE_CI_GRACE lasts.
fresh; moves "${H1}" "${H3}" "${B}" bin/x.sh; checks "${FX}/${H3}.checks.1"; merge SWARM_MERGE_CI_GRACE=30 "${URL}"
is "no check runs on the first read, green on the next, within the grace: merges the new head" "0|yes" "${rc}|$(merged_at "${H3}" && echo yes)"
fresh; moves "${H1}" "${H3}" "${B}" bin/x.sh; checks "${FX}/${H3}.checks" "$(run test in_progress)"
merge SWARM_MERGE_CI_SECONDS=6 SWARM_MERGE_POLL=1 "${URL}"
refused_after "a new head still pending at the deadline" "base merged, timed out" \
  "base merged, timed out: ${WHO}: timed out after " ", still pending: test (in_progress): ${NEXT}"
# A green check is not enough: each workflow a pull_request runs must have run on the new head; one with
# no run MERGE_CI_GRACE after the first read that found none refuses.
fresh; moves "${H1}" "${H3}" "${B}" bin/x.sh; wfruns "${FX}/${H3}.runs"
printf 'name: ci\non:\n  pull_request:\n    types: [opened, synchronize]\n' > "${FX}/wf.ci.yml.${H3}"; merge "${URL}"
refused_after "a pull_request workflow with no run on the new head" "base merged, no workflow run" \
  "base merged, no workflow run: ${WHO}: .github/workflows/ci.yml: a pull_request into main runs it, but it has no run on 3333333 after " "${PULL}"
fresh; moves "${H1}" "${H3}" "${B}" bin/x.sh; echo CONFLICTING > "${FX}/mergeable"; merge "${URL}"
refused_after "a new head that conflicts with main" "base merged, conflict" \
  "base merged, conflict: ${WHO} conflicts with main: pull the branch first (it holds GitHub's merge 3333333), then merge origin/main in, push, and merge the new head"
fresh; moves "${H1}" "${H3}" "${B}" bin/x.sh; rm "${FX}/${H3}.checks"; merge "${URL}"
refused_after "CI on the new head gh cannot read" "base merged, unread" "base merged, unread: ${WHO}: error " "${PULL}"
# A spent rate limit is waited out to its reset, as wait-pr does, and the three reads after it are
# retried: four failed reads in all, one more than retries alone get past.
fresh; moves "${H1}" "${H3}" "${B}" bin/x.sh
for i in 1 2 3 4; do echo "gh: API rate limit exceeded for user ID 1. (HTTP 403)" > "${FX}/${H3}.checks.${i}.fail"; done
echo "$(( $(date +%s) + 1 )) soon" > "${FX}/rate_limit"; merge SWARM_WAIT_PR_RETRY=0 "${URL}"
is "a spent rate limit during the wait: waits for its reset, then merges the new head" "0|yes|yes" \
  "${rc}|$(said "rate limited: GitHub's API budget resets at soon; waiting until then" && echo yes)|$(merged_at "${H3}" && echo yes)"

# --- watch: a head merge made by merging the base in is no new work, and a builder's later push is.
# gh is a stub of its own here, answering from w/prlist.json; every PR's one check run has finished,
# and it is mergeable unless w/mergeable says otherwise. Story a, of the epic e, is built in svc; its PR is #1.
W="${ROOT}/w"; WP="${W}/proj"
mkdir -p "${W}/bin" "${WP}/.claude/swarm" "${WP}/docs/epics" "${WP}/docs/stories" "${WP}/.swarm" "${W}/repos"
printf '#!/bin/sh\nF="%s"\n' "${W}" > "${W}/bin/gh"
cat >> "${W}/bin/gh" <<'EOF'
echo "$*" >> "$F/calls"
q=""; for a in "$@"; do [ "$p" = -q ] && q="$a"; p="$a"; done
case "$1 $2" in
  "repo view") echo o/svc; exit 0 ;;
esac
case "$2 $3" in
  "--paginate repos/o/svc/pulls?"*) out="$(jq -r "$q" "$F/prlist.json")"; printf '%s\n' "${out}"; exit 0 ;;
esac
case "$2" in
  repos/o/svc/pulls/*) cat "$F/mergeable" 2>/dev/null || echo MERGEABLE ;;
  repos/o/svc/commits/*/check-runs*) echo '1 0' ;;
  *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
chmod +x "${W}/bin/gh"
echo "repos_dir = ${W}/repos" > "${WP}/.claude/swarm/config"
git init -q "${W}/repos/svc" && git -C "${W}/repos/svc" remote add origin https://github.com/o/svc
printf -- '---\nstatus: active\n---\n' > "${WP}/docs/epics/e.md"
printf -- '---\nstatus: review\nkind: code\nepic: e\nrepo: svc\n---\n' > "${WP}/docs/stories/a.md"
printf '2026-10-28T00:00:00Z\tmerge\ta\t-\tbase-merged %s from %s\n' "${H3}" "${H1}" > "${WP}/.swarm/events.tsv"
# head_at <sha> — PR #1 (story/a) is at <sha>.
head_at() { printf '[{"number": 1, "head": {"ref": "story/a", "sha": "%s"}, "updated_at": "%s"}]\n' "$1" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${W}/prlist.json"; }
# watch_for <watch args...> — what watch printed, a |, then how it ended: its exit code, or "polling"
# once it has listed the PRs three times (two whole polls said nothing), or "timeout" after 60 s. A
# watch still running is stopped, and its children.
watch_for() {
  local pid i end=timeout kids k out
  : > "${W}/calls"; rm -f "${W}/watch.out"
  (cd "${WP}" && exec env -u HERDR_ENV -u SWARM_PROJECT SWARM_SLEEP_SCALE=0.002 PATH="${W}/bin:${PATH}" \
    bash "${SWARM}" watch "$@" > "${W}/watch.out" 2>&1) &
  pid=$!
  for ((i = 0; i < 300; i++)); do
    if ! kill -0 "${pid}" 2>/dev/null; then { wait "${pid}"; } 2>/dev/null && end=0 || end=$?; break; fi
    if [[ $(grep -c 'pulls?state=open' "${W}/calls" || true) -ge 3 ]]; then end=polling; break; fi
    sleep 0.2
  done
  out="$(cat "${W}/watch.out")"
  if [[ "${end}" == polling || "${end}" == timeout ]]; then
    kids="$(pgrep -P "${pid}" || true)"; kill "${pid}" 2>/dev/null || true; { wait "${pid}"; } 2>/dev/null || true
    for k in ${kids}; do kill "${k}" 2>/dev/null || true; done
  fi
  printf '%s|%s' "${out}" "${end}"
}
head_at "${H3}"
check_watch() { is "$1" "$2" "$(watch_for "${@:3}")"; }
check_watch "watch prints no line for a base-merged head whose checks finished, and polls on" "|polling" svc
# Its conflict read stays: a base-merged head that then conflicts with its base is said, as any head is.
echo CONFLICTING > "${W}/mergeable"
check_watch "watch still says a base-merged head it marked done conflicts with its base" "o/svc #1 story/a CONFLICTS with its base|0" svc
rm "${W}/mergeable"
check_watch "a conductor's watch --epic does not say the PR opened on a base-merged head, and polls on" "|polling" --epic e
# With escalate_ladder set, a conductor's watch notes each head of its stories for the ladder's red-head
# count (.swarm/red-heads.tsv), but not a head merge made: its red is merge's to handle, not the builder's.
echo "escalate_ladder = sonnet,opus" >> "${WP}/.claude/swarm/config"
check_watch "with escalate_ladder, a conductor's watch says nothing of a base-merged head" "|polling" --epic e
is "with escalate_ladder, a conductor's watch notes no base-merged head for the ladder" 0 "$( { cat "${WP}/.swarm/red-heads.tsv" 2>/dev/null || true; } | grep -c "^a ${H3} " || true)"
head_at "${H4}"
check_watch "a builder's later push is reported as before: checks finished on its head" "o/svc #1 story/a checks finished on 4444444|0" svc

finish "merge base-update wait"
