#!/usr/bin/env bash
# merge_test.sh — swarm.sh merge: the gate on the PR's head (every check run and status, every page,
# failing closed), the pinned merge, the wait for CI on the merge commit, reconcile after it, who may
# run it, and its events.tsv lines. gh and herdr are stubs on PATH: gh logs every call to gh.log and
# answers from ${FX} (see serve); herdr lists the agents in ${ROOT}/agents ("<name> <pane>" lines).
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
REPO="$(dirname "${SWARM}")/.."
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'chmod -R u+rwx "${ROOT}" 2>/dev/null; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; FX="${ROOT}/fx"; S="${P}/docs/stories/s.md"
H1=1111111111111111111111111111111111111111; H2=2222222222222222222222222222222222222222
M=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; URL=https://github.com/o/r/pull/7
mkdir -p "${P}/.claude/swarm" "${P}/docs/stories" "${P}/.swarm/state" "${ROOT}/bin"
git -C "${P}" init -q
# The board's repo has an origin, a local bare repo the gh stub names o/r (${FX}/origin).
git init -q --bare "${ROOT}/origin.git"; git -C "${P}" remote add origin "${ROOT}/origin.git"

# gh: pr view, pr merge (fails unless --match-head-commit is ${FX}/head; marks the PR merged with
# merge commit ${M}, and then fails the next ${FX}/readback-fails pr views) and repo view (the merge
# methods, or with nameWithOwner ${FX}/origin) from ${FX}; each api path from serve's fixture.
printf '#!/usr/bin/env bash\nFX="%s"; LOG="%s"; M="%s"\n' "${FX}" "${ROOT}/gh.log" "${M}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "${LOG}"
# serve <key> — the fixture <key>.<n> on the nth read of <key> when there is one, else <key>; with
# <key>.fail, print that (a partial answer) and fail; with <key>.<n>.fail, fail the nth read only;
# with none of them, a 404.
serve() {
  local n; n=$(( $(cat "${FX}/$1.n" 2>/dev/null || echo 0) + 1 )); echo "${n}" > "${FX}/$1.n"
  if [ -e "${FX}/$1.fail" ]; then cat "${FX}/$1.fail"; echo "gh: HTTP 502" >&2; exit 1; fi
  if [ -e "${FX}/$1.${n}.fail" ]; then echo "gh: HTTP 502" >&2; exit 1; fi
  if [ -e "${FX}/$1.${n}" ]; then cat "${FX}/$1.${n}"
  elif [ -e "${FX}/$1" ]; then cat "${FX}/$1"
  else echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
}
case "$1 $2" in
  "pr view")
    [ ! -e "${FX}/pr-view.fail" ] || { echo "gh: could not resolve to a PullRequest" >&2; exit 1; }
    left="$(cat "${FX}/readback-left" 2>/dev/null || echo 0)"
    if [ "${left}" -gt 0 ]; then echo $((left - 1)) > "${FX}/readback-left"; echo "gh: HTTP 502" >&2; exit 1; fi
    printf '{"state":"%s","headRefOid":"%s","baseRefName":"%s","mergeCommit":%s,"changedFiles":%s}\n' \
      "$(cat "${FX}/state")" "$(cat "${FX}/head")" "$(cat "${FX}/base")" "$(cat "${FX}/mergecommit")" "$(cat "${FX}/nfiles")" ;;
  "pr merge")
    want=""; prev=""; for a in "$@"; do [ "${prev}" != --match-head-commit ] || want="${a}"; prev="${a}"; done
    [ "${want}" = "$(cat "${FX}/head")" ] || { echo "GraphQL: Head branch was modified. Review and try the merge again." >&2; exit 1; }
    [ -e "${FX}/stays-open" ] || echo MERGED > "${FX}/state"
    [ -e "${FX}/no-merge-commit" ] || printf '{"oid":"%s"}' "${M}" > "${FX}/mergecommit"
    [ ! -e "${FX}/readback-fails" ] || cp "${FX}/readback-fails" "${FX}/readback-left"
    # A 5xx after GitHub merged it.
    [ ! -e "${FX}/merge-then-fail" ] || { echo "gh: HTTP 502" >&2; exit 1; } ;;
  "repo view") case "$*" in *nameWithOwner*) cat "${FX}/origin" ;; *) cat "${FX}/repo" ;; esac ;;
  api*)
    for a in "$@"; do path="${a}"; done
    sha="${path#*/commits/}"; sha="${sha%%/*}"
    case "${path}" in
      */check-runs*) serve "${sha}.checks"
                     # The head moves once its checks are read, before the merge.
                     [ "${sha}" != "$(cat "${FX}/head")" ] || [ ! -e "${FX}/move-head" ] || cp "${FX}/move-head" "${FX}/head" ;;
      */commits/*/status*) serve "${sha}.status" ;;
      */actions/runs*) sha="${path#*head_sha=}"; serve "${sha%%&*}.runs" ;;
      */pulls/*/files*) serve files ;;
      */rules/branches/*) serve rules ;;
      */branches/*) serve branch ;;
      */contents/.github/workflows\?*) serve workflows ;;
      # A file read at a ref with a fixture of its own (wf.<file>.<ref>) gets that one.
      */contents/*) f="${path%%\?*}"; f="wf.${f##*/}"; ref="${path##*ref=}"
                    [ ! -e "${FX}/${f}.${ref}" ] || f="${f}.${ref}"; serve "${f}" ;;
      *) echo "stub: no fixture for ${path}" >&2; exit 1 ;;
    esac ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
printf '#!/bin/sh\nA="%s"\n' "${ROOT}/agents" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'STUB'
[ ! -e "$A.fail" ] || exit 1
case "$1 $2" in
  "agent list") awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                     { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                     END { print "]}}" }' "$A" ;;
esac
STUB
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr"
# This project's panes: the conductor of epic e and the builder of story t.
printf 'w:c conduct-e\nw:b t\n' > "${P}/.swarm/state/e"
printf 'conduct-e w:c\nt w:b\n' > "${ROOT}/agents"

# run <name> <status> [conclusion] [sha] — one check run, or with [sha] one workflow run on it
# (<name>.yml its path).
run() {
  local c=null; [[ -z "${3:-}" ]] || c="\"$3\""
  printf '{"name":"%s","status":"%s","conclusion":%s,"html_url":"https://github.com/o/r/runs/%s","path":".github/workflows/%s.yml","head_sha":"%s"}' \
    "$1" "$2" "${c}" "$1" "$1" "${4:-${M}}"
}
# page <file> <key> <total> <item>... — one page of a list, appended to <file>.
page() { local f="$1" k="$2" t="$3" IFS=,; shift 3; printf '{"total_count":%s,"%s":[%s]}\n' "${t}" "${k}" "$*" >> "${f}"; }
checks() { local f="$1"; shift; rm -f "${f}"; page "${f}" check_runs "$#" "$@"; }
statuses() { local f="$1"; shift; rm -f "${f}"; page "${f}" statuses "$#" "$@"; }
wfruns() { local f="$1"; shift; rm -f "${f}"; page "${f}" workflow_runs "$#" "$@"; }
workflows() { # <name>... — .github/workflows on the merge commit: each <name>.yml runs on push to main
  local w list=""
  for w in "$@"; do
    list+="${list:+,}{\"name\":\"${w}.yml\",\"path\":\".github/workflows/${w}.yml\",\"type\":\"file\"}"
    printf 'name: %s\non:\n  pull_request:\n    types: [opened]\n  push:\n    branches: [main]   # main only\n' "${w}" > "${FX}/wf.${w}.yml"
  done
  echo "[${list}]" > "${FX}/workflows"
}
item() { { echo ---; printf '%s\n' "${@:2}"; echo ---; echo; echo "# $1"; } > "${P}/docs/stories/$1.md"; }

# fresh [config line]... — story s in review with prs: ${URL}; head ${H1} with one green check run
# and no status; squash allowed; on the merge commit a green check run and a green run of the one
# workflow that runs on push to main.
fresh() {
  rm -rf "${FX}" "${P}/.swarm/events.tsv" "${ROOT}/gh.log"; mkdir -p "${FX}"; : > "${ROOT}/gh.log"
  printf '%s\n' "$@" > "${P}/.claude/swarm/config"
  echo OPEN > "${FX}/state"; echo "${H1}" > "${FX}/head"; echo null > "${FX}/mergecommit"; echo main > "${FX}/base"
  echo '[{"filename":"docs/stories/s.md","status":"modified"}]' > "${FX}/files"; echo 1 > "${FX}/nfiles"
  echo '{"nameWithOwner":"o/r"}' > "${FX}/origin"
  echo '{"squashMergeAllowed":true,"mergeCommitAllowed":true,"rebaseMergeAllowed":true}' > "${FX}/repo"
  checks "${FX}/${H1}.checks" "$(run test completed success)"; statuses "${FX}/${H1}.status"
  checks "${FX}/${M}.checks" "$(run test completed success)"; statuses "${FX}/${M}.status"
  workflows ci; wfruns "${FX}/${M}.runs" "$(run ci completed success "${M}")"
  item s "status: review" "prs: ${URL}"
}
# merge [VAR=value]... <args> — swarm.sh merge outside herdr unless VARs say otherwise; sets rc,
# output in ${ROOT}/out.
merge() {
  local envs=()
  while [[ "${1:-}" == [A-Z]*=* ]]; do envs+=("$1"); shift; done
  rc=0
  (cd "${P}" && env -u HERDR_ENV -u HERDR_PANE_ID -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" SWARM_MERGE_POLL=0 SWARM_MERGE_READ_WAIT=0 SWARM_MERGE_CI_GRACE=0 \
    SWARM_MERGE_CI_SECONDS=5 ${envs[@]+"${envs[@]}"} bash "${SWARM}" merge "$@" > "${ROOT}/out" 2>&1) || rc=$?
}
events() { awk -F'\t' '{ print $2 " " $3 " " $5 }' "${P}/.swarm/events.tsv" 2>/dev/null || true; }
merge_lines() { events | grep -c '^merge ' || true; }
logged() { events | grep -q -- "$1"; }

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
merged() { grep -q '^pr merge' "${ROOT}/gh.log"; }
not_merged() { ! merged; }
said() { grep -qF -- "$1" "${ROOT}/out"; }
# refused <name> <text> — the last merge failed naming <text>, called no pr merge, and logged one merge line.
refused() {
  is "$1: exits non-zero" 1 "${rc}"
  check "$1: says ${2}" said "$2"
  check "$1: no pr merge" not_merged
  is "$1: one merge line" 1 "$(merge_lines)"
}

# --- Green: merged pinned to the head, with the repo's method, then main's CI, then reconcile.
fresh; merge "${URL}"
is "green: exits 0" 0 "${rc}"
check "green: pr merge pins the head and squashes" grep -qxF "pr merge 7 --repo o/r --squash --match-head-commit ${H1}" "${ROOT}/gh.log"
check "green: no --admin, no --auto" bash -c "! grep -E -- '--(admin|auto)' '${ROOT}/gh.log'"
is "green: merge, main-ci, reconcile, in order, one line each" "merge s ok|main-ci s ok|reconcile s ok (finished)" "$(events | paste -sd'|' -)"
check "green: reconcile finished s" test ! -e "${S}"
fresh; merge --head "${H1}" "${URL}"
is "--head naming the head: exits 0" 0 "${rc}"

# --- Red, pending or no checks on the head refuse before any pr merge.
for v in "completed failure" "in_progress" "queued" "completed cancelled" "completed timed_out" "completed action_required"; do
  fresh; read -r st co <<< "${v}"
  checks "${FX}/${H1}.checks" "$(run test completed success)" "$(run lint "${st}" "${co:-}")"
  merge "${URL}"; refused "a head run ${v}" "lint (${co:-${st}})"
done
fresh; checks "${FX}/${H1}.checks"; merge "${URL}"; refused "a head with no check runs" "no check runs"
fresh; statuses "${FX}/${H1}.status" '{"context":"ci/legacy","state":"pending","target_url":"https://ci.example/1"}'
merge "${URL}"; refused "a pending legacy status" "ci/legacy (pending)"
fresh; statuses "${FX}/${H1}.status" '{"context":"ci/legacy","state":"failure","target_url":"https://ci.example/1"}'
merge "${URL}"; refused "a failed legacy status" "ci/legacy (failure)"
# 100 green runs on page 1, a red one on page 2.
fresh; rm -f "${FX}/${H1}.checks"; green=()
for i in $(seq 1 100); do green+=("$(run "t${i}" completed success)"); done
page "${FX}/${H1}.checks" check_runs 101 "${green[@]}"; page "${FX}/${H1}.checks" check_runs 101 "$(run late completed failure)"
merge "${URL}"; refused "a red run on page 2" "late (failure)"
check "the check runs are read with --paginate" grep -q -- "--paginate repos/o/r/commits/${H1}/check-runs" "${ROOT}/gh.log"
fresh; rm -f "${FX}/${H1}.checks"; page "${FX}/${H1}.checks" check_runs 101 "${green[@]}"
merge "${URL}"; refused "fewer runs read than total_count" "read 100 of 101"
fresh; rm -f "${FX}/${H1}.checks"; page "${FX}/${H1}.checks.fail" check_runs 101 "${green[@]}"
merge "${URL}"; refused "check runs that fail after a green page" "HTTP 502"
fresh; echo '{"total_count":1,"check_runs":[' > "${FX}/${H1}.checks"
merge "${URL}"; refused "check runs that are not JSON" "error"
fresh; touch "${FX}/pr-view.fail"; merge "${URL}"; refused "gh pr view failing" "gh cannot read ${URL}"
fresh; echo MERGED > "${FX}/state"; merge "${URL}"; refused "a PR that is not open" "is MERGED, not open"

# --- A head that moves: --match-head-commit stops the merge; --head refuses first.
fresh; echo "${H2}" > "${FX}/move-head"; merge "${URL}"
is "changed head: exits non-zero" 1 "${rc}"
check "changed head: pr merge was pinned to the head that was checked" grep -q -- "--match-head-commit ${H1}" "${ROOT}/gh.log"
check "changed head: no main-ci line" bash -c "! grep -q main-ci '${P}/.swarm/events.tsv'"
check "changed head: s still in review" grep -qx 'status: review' "${S}"
is "changed head: one merge line" 1 "$(merge_lines)"
fresh; merge --head "${H2}" "${URL}"; refused "--head naming another SHA" "is 1111111, not 2222222"
fresh; merge --head abc "${URL}"; refused "--head that is not a full SHA" "full 40-character SHA"

# --- Main's CI after the merge.
fresh; checks "${FX}/${M}.checks" "$(run test completed success)" "$(run e2e completed failure)"; merge "${URL}"
is "red main: exits non-zero" 1 "${rc}"
check "red main: names the check and its URL" said "e2e (failure) https://github.com/o/r/runs/e2e"
check "red main: main-ci s red, naming it" logged '^main-ci s red .*e2e (failure)'
check "red main: reconcile still ran" logged '^reconcile s ok (finished)$'
is "red main: one merge line" 1 "$(merge_lines)"
fresh; checks "${FX}/${M}.checks" "$(run test in_progress)"; start=${SECONDS}
merge SWARM_MERGE_CI_SECONDS=2 SWARM_MERGE_POLL=1 "${URL}"
is "pending main: exits non-zero" 1 "${rc}"
check "pending main: within 10 s" test $((SECONDS - start)) -lt 10
check "pending main: main-ci s timeout" logged '^main-ci s timeout'
is "pending main: one merge line" 1 "$(merge_lines)"
fresh; wfruns "${FX}/${M}.runs"; merge SWARM_MERGE_CI_SECONDS=1 "${URL}"
is "a workflow with no run on the merge commit: exits non-zero" 1 "${rc}"
check "a workflow with no run on the merge commit: main-ci timeout naming it" logged '^main-ci s timeout (.github/workflows/ci.yml (no run'
fresh; wfruns "${FX}/${M}.runs" "$(run ci completed success "${H2}")"; merge SWARM_MERGE_CI_SECONDS=1 "${URL}"
check "a green run on another SHA does not count: main-ci timeout" logged '^main-ci s timeout'
# A fast workflow is green before a slower one has a run; the slow one then fails.
fresh; workflows ci slow; wfruns "${FX}/${M}.runs.1" "$(run ci completed success)"
wfruns "${FX}/${M}.runs" "$(run ci completed success)" "$(run slow completed failure)"; merge "${URL}"
is "a slow workflow failing after a fast green one: exits non-zero" 1 "${rc}"
check "a slow workflow failing after a fast green one: main-ci red names it" logged '^main-ci s red slow (failure)'
fresh; workflows ci tags; printf 'on:\n  push:\n    tags: [v*]\n' > "${FX}/wf.tags.yml"; merge "${URL}"
is "a tag-only workflow is not waited for" 0 "${rc}"
# Path filters, against the files the PR changes (docs/stories/s.md).
paths() { # <name> <key> <pattern> — workflow <name> also runs on push to main, filtered by <key>
  workflows ci "$1"; printf 'on:\n  push:\n    branches: [main]\n    %s:\n      - %s\n' "$2" "$3" > "${FX}/wf.$1.yml"
}
fresh; paths code paths 'bin/**'; merge "${URL}"
is "a workflow whose paths the PR misses is not waited for" 0 "${rc}"
fresh; paths nodocs paths-ignore 'docs/**'; merge "${URL}"
is "a workflow whose paths-ignore covers every file the PR changes is not waited for" 0 "${rc}"
fresh; paths docs paths "'docs/**'"; merge SWARM_MERGE_CI_SECONDS=1 "${URL}"
check "a workflow whose paths the PR touches is waited for: main-ci timeout" logged '^main-ci s timeout (.github/workflows/docs.yml (no run'
fresh; paths go paths "'**/*.go'"; echo '[{"filename":"main.go"}]' > "${FX}/files"; merge SWARM_MERGE_CI_SECONDS=1 "${URL}"
check "**/ matches a file at the root: main-ci timeout" logged '^main-ci s timeout (.github/workflows/go.yml (no run'
fresh; workflows ci multi; printf 'on:\n  push:\n    branches: [\n      main ]\n' > "${FX}/wf.multi.yml"; merge "${URL}"
check "a [list] over several lines is not skipped: main-ci error naming it" logged '^main-ci s error .github/workflows/multi.yml'
fresh; workflows ci multi; printf 'on: [pull_request,\n  push]\n' > "${FX}/wf.multi.yml"; merge "${URL}"
check "an on: [list] over several lines is not skipped: main-ci error naming it" logged '^main-ci s error .github/workflows/multi.yml'
fresh; paths flat paths "'docs/*'"; merge "${URL}"
is "* stops at /: docs/* does not cover docs/stories/s.md" 0 "${rc}"
fresh; paths code paths 'bin/**'; echo 101 > "${FX}/nfiles"; merge SWARM_MERGE_CI_SECONDS=1 "${URL}"
check "with not every file listed, a path-filtered workflow is waited for" logged '^main-ci s timeout (.github/workflows/code.yml (no run'
fresh; touch "${FX}/no-merge-commit"; merge "${URL}"
is "no merge commit: exits non-zero" 1 "${rc}"
is "no merge commit: one merge line, unconfirmed, no main-ci" \
  "merge s unconfirmed (MERGED, no merge commit): gh pr merge ran, but ${URL} does not read as merged; check it by hand" "$(events)"
fresh; touch "${FX}/stays-open"; merge "${URL}"
is "a merge that leaves the PR open: unconfirmed, never 'not merged', no main-ci" \
  "merge s unconfirmed (OPEN): gh pr merge ran, but ${URL} does not read as merged; check it by hand" "$(events)"
check "a merge that leaves the PR open: it read the PR back 5 times" test "$(grep -c '^pr view 7 --repo o/r --json state,mergeCommit' "${ROOT}/gh.log")" = 5
check "a merge that leaves the PR open: says check it by hand" said "check it by hand"
fresh; echo 1 > "${FX}/readback-fails"; merge "${URL}"
is "a read-back that fails once, then reads MERGED: the ok path" "merge s ok|main-ci s ok|reconcile s ok (finished)" "$(events | paste -sd'|' -)"
fresh; touch "${FX}/merge-then-fail"; merge "${URL}"
is "pr merge exits 1 but the PR reads MERGED: the ok path" "merge s ok|main-ci s ok|reconcile s ok (finished)" "$(events | paste -sd'|' -)"
# The merge commit needs no check run of its own when no workflow is expected on it, but ok waits
# out the grace for checks that appear just after the push.
fresh; rm "${FX}/workflows"; checks "${FX}/${M}.checks"; wfruns "${FX}/${M}.runs"; merge "${URL}"
is "no expected workflow and no runs on the merge commit: main-ci ok" "merge s ok|main-ci s ok|reconcile s ok (finished)" "$(events | paste -sd'|' -)"
fresh; rm "${FX}/workflows"; wfruns "${FX}/${M}.runs"; checks "${FX}/${M}.checks.1"
checks "${FX}/${M}.checks" "$(run ext completed failure)"; merge SWARM_MERGE_CI_GRACE=5 "${URL}"
is "nothing expected, a red check appearing within the grace: exits non-zero" 1 "${rc}"
check "nothing expected, a red check appearing within the grace: main-ci red names it" logged '^main-ci s red ext (failure)'
fresh; rm "${FX}/workflows"; checks "${FX}/${M}.checks"; wfruns "${FX}/${M}.runs"; merge SWARM_MERGE_CI_GRACE=1 SWARM_MERGE_POLL=0.2 "${URL}"
is "nothing at all through the grace: main-ci ok" "merge s ok|main-ci s ok|reconcile s ok (finished)" "$(events | paste -sd'|' -)"
check "nothing at all through the grace: read more than once" test "$(cat "${FX}/${M}.checks.n")" -gt 1
# A truncated contents answer is a missed read too.
fresh; echo '[{"name":' > "${FX}/workflows.1"; merge "${URL}"
is "one unreadable .github/workflows listing between good reads: main-ci ok" "merge s ok|main-ci s ok|reconcile s ok (finished)" "$(events | paste -sd'|' -)"
fresh; echo '[{"name":"ci.yml"}]' > "${FX}/workflows.1"; merge "${URL}"
is "one listing missing its keys between good reads: main-ci ok" "merge s ok|main-ci s ok|reconcile s ok (finished)" "$(events | paste -sd'|' -)"
# A failed read is a missed poll; three in a row end the wait.
fresh; checks "${FX}/${M}.checks.1" "$(run test in_progress)"; touch "${FX}/${M}.checks.2.fail"; merge "${URL}"
is "one failed read between pending and green: main-ci ok" "merge s ok|main-ci s ok|reconcile s ok (finished)" "$(events | paste -sd'|' -)"
fresh; touch "${FX}/${M}.checks.1.fail" "${FX}/${M}.checks.2.fail" "${FX}/${M}.checks.3.fail"; merge "${URL}"
is "three failed reads in a row: exits non-zero" 1 "${rc}"
check "three failed reads in a row: main-ci error" logged '^main-ci s error .*3 reads in a row failed'
fresh; workflows ci comma; printf "on:\n  push:\n    paths: ['data/a,b.csv']\n" > "${FX}/wf.comma.yml"; merge "${URL}"
check "a quoted entry holding a comma is not split: main-ci error naming it" logged '^main-ci s error .github/workflows/comma.yml: .*comma is not read'
for v in "*branches" "[main, *other]" "&b [main]"; do
  fresh; workflows ci alias; printf 'on:\n  push:\n    branches: %s\n' "${v}" > "${FX}/wf.alias.yml"; merge "${URL}"
  check "an anchor or alias (branches: ${v}) is not read as a glob: main-ci error naming it" logged '^main-ci s error .github/workflows/alias.yml'
done
fresh; workflows ci alias; printf 'on:\n  push:\n    branches:\n      - *b\n' > "${FX}/wf.alias.yml"; merge "${URL}"
check "an alias in a block list is not read as a glob: main-ci error naming it" logged '^main-ci s error .github/workflows/alias.yml'
fresh; workflows ci star; printf "on:\n  push:\n    branches: ['*']\n" > "${FX}/wf.star.yml"; merge SWARM_MERGE_CI_SECONDS=1 "${URL}"
check "a quoted '*' is a glob, not an alias: the workflow is waited for" logged '^main-ci s timeout (.github/workflows/star.yml (no run'

# --- What is merged, and how.
fresh; item s "status: ready" "prs: ${URL}"; merge "${URL}"; refused "a story that is ready" "s is ready, not review"
# A done story (finished = mark keeps prs:) lists the URL before the epic in review that also does.
fresh; rm "${S}"; item a "status: done" "prs: ${URL}"; mkdir -p "${P}/docs/epics"
printf -- '---\nstatus: review\nprs: %s\n---\n\n# e\n' "${URL}" > "${P}/docs/epics/e.md"; merge "${URL}"
is "a done story and an epic in review list the URL: the epic merges" "merge e ok|main-ci e ok|reconcile e ok (finished)" "$(events | paste -sd'|' -)"
rm -rf "${P}/docs/stories/a.md" "${P}/docs/epics"
fresh; rm "${S}"; merge "${URL}"; refused "a PR no story or epic lists" "no story or epic lists"
is "a PR no story lists: the line's target is the URL" "merge ${URL}" "$(events | cut -d' ' -f1-2)"
fresh; rm "${S}"; merge --board "${URL}"
is "--board: exits 0" 0 "${rc}"
check "--board: merged" merged
is "--board: merge and main-ci under the URL, no reconcile" "merge ${URL} ok|main-ci ${URL} ok" "$(events | paste -sd'|' -)"
# Another story in review, whose PR the stub also reports merged: reconcile would finish it.
fresh; item s "status: review" "prs: https://github.com/o/r/pull/8"; merge --board "${URL}"
is "--board runs no reconcile: only merge and main-ci lines" "merge ${URL} ok|main-ci ${URL} ok" "$(events | paste -sd'|' -)"
check "--board runs no reconcile: the other story stays in review" grep -qx 'status: review' "${S}"
fresh; rm "${S}"; echo '[{"filename":"docs/stories/s.md"},{"filename":"bin/swarm.sh"}]' > "${FX}/files"; echo 2 > "${FX}/nfiles"
merge --board "${URL}"; refused "--board with a file off the board" "changes bin/swarm.sh, outside docs/"
fresh; rm "${S}"; echo 2 > "${FX}/nfiles"; merge --board "${URL}"; refused "--board with files missing from gh's list" "cannot list every file"
fresh; rm "${S}"; echo '[{"filename":"docs/x.sh","previous_filename":"bin/swarm.sh","status":"renamed"}]' > "${FX}/files"
merge --board "${URL}"; refused "--board with a file renamed onto the board" "changes bin/swarm.sh, outside docs/"
check "--board reads the files with --paginate" grep -q -- "--paginate repos/o/r/pulls/7/files" "${ROOT}/gh.log"
fresh; rm "${S}"; echo '{"nameWithOwner":"other/repo"}' > "${FX}/origin"
merge --board "${URL}"; refused "--board for a PR outside the board's repo" "is not in other/repo, the board's repo"
# --release: a PR into the project's base that changes only the version in .claude-plugin/plugin.json,
# in the project's own repo, merges with no story listing it and runs no reconcile; any other file or
# field, another base, or another repo, is refused. origin's default branch is main.
git -C "${P}" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "${P}" push -q origin HEAD:refs/heads/main; git -C "${ROOT}/origin.git" symbolic-ref HEAD refs/heads/main
release_pr() {
  fresh; rm "${S}"; echo '[{"filename":".claude-plugin/plugin.json","status":"modified"}]' > "${FX}/files"
  echo '{"name":"x","version":"1.2.0","hooks":{}}' > "${FX}/wf.plugin.json.main"
  echo '{"name":"x","version":"1.3.0","hooks":{}}' > "${FX}/wf.plugin.json.${H1}"
}
release_pr; item s "status: review" "prs: https://github.com/o/r/pull/8"; merge --release "${URL}"
is "--release: exits 0" 0 "${rc}"
check "--release: merged" merged
is "--release: merge and main-ci under the URL, no reconcile" "merge ${URL} ok|main-ci ${URL} ok" "$(events | paste -sd'|' -)"
release_pr; echo '[{"filename":".claude-plugin/plugin.json"},{"filename":"bin/swarm.sh"}]' > "${FX}/files"; echo 2 > "${FX}/nfiles"
merge --release "${URL}"; refused "--release with another file" "changes bin/swarm.sh, not only .claude-plugin/plugin.json"
release_pr; echo '[{"filename":"docs/stories/s.md"}]' > "${FX}/files"
merge --release "${URL}"; refused "--release with a board file" "changes docs/stories/s.md, not only"
release_pr; echo '{"nameWithOwner":"other/repo"}' > "${FX}/origin"
merge --release "${URL}"; refused "--release for a PR outside the project's repo" "is not in other/repo, the project's repo"
release_pr; merge --release --board "${URL}"; refused "--release with --board" "do not go together"
release_pr; echo '{"name":"x","version":"1.3.0","hooks":{},"mcpServers":{"m":{"command":"sh"}}}' > "${FX}/wf.plugin.json.${H1}"
merge --release "${URL}"; refused "--release that adds mcpServers to plugin.json" "changes more of .claude-plugin/plugin.json than its version"
release_pr; echo '{"name":"x","hooks":{}}' > "${FX}/wf.plugin.json.${H1}"
merge --release "${URL}"; refused "--release that drops the version" "its version None is not MAJOR.MINOR.PATCH"
release_pr; echo '{"name":"x","version":"1.3.0","hooks":{},"strict":true}' > "${FX}/wf.plugin.json.main"
echo '{"name":"x","version":"1.4.0","hooks":{},"strict":1}' > "${FX}/wf.plugin.json.${H1}"
merge --release "${URL}"; refused "--release that turns true into 1" "changes more of .claude-plugin/plugin.json than its version; if main changed plugin.json after the release branch was cut, merge origin/main into it and retry"
for v in 1.2.0:"is not greater than '1.2.0' on main" 1.1.9:"is not greater than '1.2.0' on main" 1.3.0-rc:"its version '1.3.0-rc' is not MAJOR.MINOR.PATCH"; do
  release_pr; echo "{\"name\":\"x\",\"version\":\"${v%%:*}\",\"hooks\":{}}" > "${FX}/wf.plugin.json.${H1}"
  merge --release "${URL}"; refused "--release to version ${v%%:*}" "${v#*:}"
done
release_pr; echo feature > "${FX}/base"; cp "${FX}/wf.plugin.json.main" "${FX}/wf.plugin.json.feature"
merge --release "${URL}"; refused "--release for a PR into another branch" "goes into feature, not main, the project's base"
fresh; echo '{"squashMergeAllowed":false,"mergeCommitAllowed":true,"rebaseMergeAllowed":true}' > "${FX}/repo"; merge "${URL}"
check "squash off, merge commits on: --merge" grep -qxF "pr merge 7 --repo o/r --merge --match-head-commit ${H1}" "${ROOT}/gh.log"

# --- Who may merge: outside herdr (above), the lead's own pane, and with merge = agent a conductor.
fresh; merge HERDR_ENV=1 HERDR_PANE_ID=w:b "${URL}"; refused "a builder's pane" "pane w:b is one this project started"
fresh; merge HERDR_ENV=1 HERDR_PANE_ID=w:c "${URL}"; refused "a conductor's pane with merge = human" "pane w:c"
fresh "merge = agent"; merge HERDR_ENV=1 HERDR_PANE_ID=w:c "${URL}"
is "a conductor's pane with merge = agent: exits 0" 0 "${rc}"
fresh "merge = agent"; merge HERDR_ENV=1 HERDR_PANE_ID=w:b "${URL}"; refused "a builder's pane with merge = agent" "pane w:b"
fresh; mkdir -p "${P}/.swarm/state/reconcile-backup"; merge HERDR_ENV=1 HERDR_PANE_ID=w:b "${URL}"
refused "a builder's pane beside a reconcile backup directory" "pane w:b"
fresh; merge HERDR_ENV=1 HERDR_PANE_ID=w:lead "${URL}"
is "the lead's own pane beside a reconcile backup directory: exits 0" 0 "${rc}"; rmdir "${P}/.swarm/state/reconcile-backup"
fresh "merge = agent"; printf 'conduct-e-done w:c\nt w:b\n' > "${ROOT}/agents"; merge HERDR_ENV=1 HERDR_PANE_ID=w:c "${URL}"
refused "a retired conductor's pane" "pane w:c"; printf 'conduct-e w:c\nt w:b\n' > "${ROOT}/agents"
fresh; merge HERDR_ENV=1 HERDR_PANE_ID=w:lead "${URL}"
is "the lead's own pane: exits 0" 0 "${rc}"
fresh; merge HERDR_ENV=1 "${URL}"; refused "herdr with no HERDR_PANE_ID" "no HERDR_PANE_ID"
fresh; touch "${ROOT}/agents.fail"; merge HERDR_ENV=1 HERDR_PANE_ID=w:lead "${URL}"; refused "herdr that cannot list its agents" "herdr cannot list"
rm "${ROOT}/agents.fail"
fresh; chmod 000 "${P}/.swarm/state/e"; merge HERDR_ENV=1 HERDR_PANE_ID=w:lead "${URL}"; refused "an unreadable tab record" "cannot read"
chmod 644 "${P}/.swarm/state/e"
fresh; rm "${S}"; merge HERDR_ENV=1 HERDR_PANE_ID=w:b --board "${URL}"; refused "--board from a builder's pane" "pane w:b"
fresh "merge = agent"; rm "${S}"; merge HERDR_ENV=1 HERDR_PANE_ID=w:c --board "${URL}"
is "--board from a conductor's pane with merge = agent: exits 0" 0 "${rc}"

# --- A story marked costs: money is the user's to merge: merge holds it whoever calls, status lists
# it for the user, and the conductor's and plan-epic's briefs say so.
fresh "merge = agent"; item s "status: review" "prs: ${URL}" "costs: money"
merge HERDR_ENV=1 HERDR_PANE_ID=w:c --head "${H1}" "${URL}"; refused "costs: money with merge = agent" "held: s costs money"
check "costs: money: s stays in review" grep -qx 'status: review' "${S}"
fresh "merge = agent"; printf 'costs: money\n' >> "${S}"; merge HERDR_ENV=1 HERDR_PANE_ID=w:c --head "${H1}" "${URL}"
is "the same story without costs: (only its body says costs: money) merges" "merge s ok|main-ci s ok|reconcile s ok (finished)" "$(events | paste -sd'|' -)"
fresh "merge = agent"; item s "status: review" "prs: ${URL}" "costs: money"
(cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" status > "${ROOT}/out" 2>&1) || true
check "status lists it as awaiting your merge (costs money) under merge = agent" said "awaiting your merge (costs money): s ${URL}"
# conduct writes the brief before it opens a workspace, which a failing herdr then refuses.
cp "${REPO}/tests/claude_stub.sh" "${ROOT}/bin/claude"; touch "${ROOT}/agents.fail"
mkdir -p "${P}/docs/epics"; printf -- '---\nstatus: active\n---\n\n# e\n' > "${P}/docs/epics/e.md"
for c in e --backlog; do
  b="${P}/.swarm/briefs/conduct-${c#--}.md"; rm -f "${b}"
  (cd "${P}" && env -u SWARM_PROJECT -u HERDR_PANE_ID HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" conduct "${c}" >/dev/null 2>&1) || true
  check "the ${c#--} conductor's brief (merge = agent) names costs: money" grep -qF 'costs: money' "${b}"
  check "the ${c#--} conductor's brief (merge = agent) leaves such a PR for the user" grep -qF 'Leave the PR for the user' "${b}"
done
rm -rf "${P}/docs/epics" "${ROOT}/agents.fail"
# step <from> <to> — plan-epic.md from the line holding <from> up to the one holding <to>.
step() { awk -v from="$1" -v to="$2" 'index($0, to) { on = 0 } index($0, from) { on = 1 } on' "${REPO}/commands/plan-epic.md"; }
check "plan-epic's decompose brief names costs: money" grep -qF 'costs: money' <<< "$(step '**2. Decompose**' '**3. Verify**')"
# shellcheck disable=SC2016 # the backticks are plan-epic's
check "plan-epic's skeptic brief names costs: money" grep -qF 'costs: money' <<< "$(step 'skeptic-<slug>' 'one `codex`')"

# --- The docs say to merge with it.
check "commands/swarm.md merges with swarm.sh merge" grep -q 'swarm.sh merge' "${REPO}/commands/swarm.md"
check "method.md § Merging merges with swarm.sh merge" \
  bash -c "sed -n '/^\*\*Merging\.\*\*/,/^\*\*Merge one at a time/p' '${REPO}/docs/method.md' | grep -q 'swarm.sh merge'"

echo
if [[ ${fails} -eq 0 ]]; then echo "all merge tests passed"; else echo "${fails} merge test(s) failed"; exit 1; fi
