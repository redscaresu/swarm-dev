#!/usr/bin/env bash
# wait_pr_expected_test.sh — swarm.sh wait-pr waits on each workflow that a pull_request into the base
# runs with the PR's files, read at the PR's merge commit: one with no run yet, or whose newest run has
# not finished, is pending, even when every check already there is green. A workflow whose paths or
# types leave this PR out, or that Actions has disabled, is not waited on; one whose triggers ci_gate
# cannot read is not waited on and is named on a line of its own; one that never starts ends the wait
# with exit 2 after the grace. ci_gate head with no base, PR and count judges the checks alone, as
# before. gh is a stub on PATH: it logs every call to gh.log and answers pr view with ${H}, MERGEABLE,
# main, OPEN and ${FX}/changed files (else 1); the nth check-runs read from ${FX}/checks.<n> (else
# ${FX}/checks) and the nth workflow-runs read from ${FX}/runs.<n> (else ${FX}/runs); refs/pull/7/merge
# from ${FX}/merge, failing with ${FX}/merge.err as stderr; Actions' workflow states from ${FX}/states
# (else none); the .github/workflows listing at a ref from the files in ${FX}/wf.<ref> (else ${FX}/wf),
# each file's text from there too;
# the PR's files at ${H} (compare main...${H}) from ${FX}/files, and from the PR files API from
# ${FX}/prfiles.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
GATE="$(dirname "${SWARM}")/lib/ci_gate.py"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; FX="${ROOT}/fx"; URL=https://github.com/o/r/pull/7
H=1111111111111111111111111111111111111111
mkdir -p "${P}/.claude/swarm" "${P}/docs/stories" "${ROOT}/bin"; : > "${P}/.claude/swarm/config"
git -C "${P}" init -q

printf '#!/usr/bin/env bash\nFX="%s"; LOG="%s"; H="%s"\n' "${FX}" "${ROOT}/gh.log" "${H}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "${LOG}"
# nth <key> — this read's number for <key>, counted in ${FX}/<key>.n.
nth() { n=$(( $(cat "${FX}/$1.n" 2>/dev/null || echo 0) + 1 )); echo "${n}" > "${FX}/$1.n"; }
case "$*" in
  "pr view"*) echo "${H} MERGEABLE main OPEN $(cat "${FX}/changed" 2>/dev/null || echo 1)" ;;
  *check-runs*) nth checks; if [ -e "${FX}/checks.${n}" ]; then cat "${FX}/checks.${n}"; else cat "${FX}/checks"; fi ;;
  */status*) echo '{"total_count":0,"statuses":[]}' ;;
  *actions/runs*) nth runs; if [ -e "${FX}/runs.${n}" ]; then cat "${FX}/runs.${n}"; else cat "${FX}/runs"; fi ;;
  *actions/workflows*) cat "${FX}/states" 2>/dev/null || echo '{"total_count":0,"workflows":[]}' ;;
  *commits/refs/pull/7/merge) [ ! -e "${FX}/merge.err" ] || { cat "${FX}/merge.err" >&2; exit 1; }; cat "${FX}/merge" ;;
  *contents/.github/workflows*) a="$*"; d="${FX}/wf"; [ ! -d "${FX}/wf.${a##*ref=}" ] || d="${FX}/wf.${a##*ref=}"
    case "${a}" in
      *"workflows?ref="*) printf '['; sep=""
        for f in "${d}"/*; do printf '%s{"type":"file","name":"%s","path":".github/workflows/%s"}' "${sep}" "${f##*/}" "${f##*/}"; sep=,; done
        echo ']' ;;
      *) f="${a##*/}"; cat "${d}/${f%%\?*}" ;;
    esac ;;
  *"compare/main...${H}") cat "${FX}/files" ;;
  *pulls/7/files*) cat "${FX}/prfiles" ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
chmod +x "${ROOT}/bin/gh"

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
said() { grep -qF -- "$1" "${ROOT}/out"; }

# check_run <name> <status> [conclusion] — one check run; wf_run <workflow file> <status> [conclusion] — one workflow run on ${H}.
check_run() { local c=null; [[ -z "${3:-}" ]] || c="\"$3\""; printf '{"name":"%s","status":"%s","conclusion":%s}' "$1" "$2" "${c}"; }
# wf_run takes the event as EVENT, pull_request by default, and the run's id as ID, 1 by default.
wf_run() { local c=null; [[ -z "${3:-}" ]] || c="\"$3\""; printf '{"id":%s,"path":".github/workflows/%s","event":"%s","head_sha":"%s","status":"%s","conclusion":%s}' "${ID:-1}" "$1" "${EVENT:-pull_request}" "${H}" "$2" "${c}"; }
# page <file> <key> <item>... — one page of items under <key>.
page() { local f="$1" k="$2" IFS=,; shift 2; printf '{"total_count":%s,"%s":[%s]}\n' "$#" "${k}" "$*" > "${f}"; }
GITLEAKS="$(check_run gitleaks completed success)"; GITLEAKS_RUN="$(wf_run gitleaks.yml completed success)"
SHARDS="$(check_run "test-shard (1)" completed success),$(check_run "test-shard (2)" completed success),$(check_run test completed success)"
CI_RUN="$(wf_run ci.yml completed success)"
# MERGE is the PR's merge commit, B the base's head it merges ${H} into.
MERGE=2222222222222222222222222222222222222222; B=3333333333333333333333333333333333333333
# fresh — gitleaks.yml (on: [push, pull_request]) and ci.yml (on: pull_request into main) at the head and
# at MERGE, which merges ${H}; the PR changing bin/swarm.sh; only gitleaks' run and check exist, green.
fresh() {
  rm -rf "${FX}"; mkdir -p "${FX}/wf"; : > "${ROOT}/gh.log"
  printf '{"sha":"%s","parents":[{"sha":"%s"},{"sha":"%s"}]}\n' "${MERGE}" "${B}" "${H}" > "${FX}/merge"
  printf 'name: gitleaks\non: [push, pull_request]\njobs: {}\n' > "${FX}/wf/gitleaks.yml"
  printf 'name: ci\non:\n  pull_request:\n    branches: [main]\n  push:\n    branches: [main]\njobs: {}\n' > "${FX}/wf/ci.yml"
  echo '{"files":[{"filename":"bin/swarm.sh","status":"modified"}]}' > "${FX}/files"
  page "${FX}/checks" check_runs "${GITLEAKS}"; page "${FX}/runs" workflow_runs "${GITLEAKS_RUN}"
}
# wait_pr [VAR=value]... — swarm.sh wait-pr ${URL}, polling with no pause unless VARs say otherwise;
# sets rc, output in ${ROOT}/out.
wait_pr() {
  local envs=(); rc=0
  while [[ "${1:-}" == [A-Z]*=* ]]; do envs+=("$1"); shift; done
  (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" SWARM_MERGE_POLL=0 SWARM_WAIT_PR_RETRY=0 \
    ${envs[@]+"${envs[@]}"} bash "${SWARM}" wait-pr "${URL}" > "${ROOT}/out" 2>&1) || rc=$?
}

# --- ci.yml has no run while gitleaks is green: pending, naming it. Once its run and shard checks
# are there, all green, it exits 0. The workflows are read once for the whole wait.
fresh; page "${FX}/checks.3" check_runs "${GITLEAKS}" "${SHARDS}"; page "${FX}/runs.3" workflow_runs "${GITLEAKS_RUN}" "${CI_RUN}"
page "${FX}/checks.4" check_runs "$(check_run gitleaks completed failure)"   # red from the 4th read: a wait that missed green shows
cp "${FX}/checks.3" "${FX}/checks.2"; page "${FX}/runs.2" workflow_runs "${GITLEAKS_RUN}" "$(wf_run ci.yml in_progress)"
wait_pr
is "a pull_request workflow with no run yet: exits 0 once it ran" 0 "${rc}"
check "a pull_request workflow with no run yet: pending, naming it" said "pending: .github/workflows/ci.yml (no run on ${H:0:7})"
check "a run not finished, its checks all green: pending" said "pending: .github/workflows/ci.yml (in_progress)"
is "a pull_request workflow with no run yet: three check reads" 3 "$(grep -c check-runs "${ROOT}/gh.log")"
check "a pull_request workflow with no run yet: prints the shards green" grep -qxF "  test-shard (1) (success)" "${ROOT}/out"
is "the workflow files are read once in a wait" 1 "$(grep -c 'contents/.github/workflows/ci.yml' "${ROOT}/gh.log")"
is "the workflows are read at the merge commit" 1 "$(grep -c "contents/.github/workflows?ref=${MERGE}" "${ROOT}/gh.log")"

# --- Only the newest pull_request run counts: an older red run (a reopen, a run a newer one cancelled)
# beside a newer green one is over.
fresh; page "${FX}/checks" check_runs "${GITLEAKS}" "${SHARDS}"
page "${FX}/runs" workflow_runs "${GITLEAKS_RUN}" "$(ID=5 wf_run ci.yml completed failure)" "$(ID=9 wf_run ci.yml completed success)"; wait_pr
is "an older red run beside a newer green one: exits 0" 0 "${rc}"
fresh; page "${FX}/checks" check_runs "${GITLEAKS}" "${SHARDS}"
page "${FX}/runs" workflow_runs "${GITLEAKS_RUN}" "$(ID=9 wf_run ci.yml completed failure)" "$(ID=5 wf_run ci.yml completed success)"; wait_pr
is "a newer red run beside an older green one: exits 1" 1 "${rc}"

# --- Read at the merge commit: a workflow the base has dropped since the PR branched is not waited on.
# When refs/pull/7/merge does not merge ${H} yet (stale), the head's own workflows are. Red from the
# 2nd read, so a wait shows as exit 1.
fresh; mkdir "${FX}/wf.${MERGE}"; cp "${FX}/wf/gitleaks.yml" "${FX}/wf.${MERGE}/"
page "${FX}/checks.2" check_runs "$(check_run gitleaks completed failure)"; wait_pr
is "a workflow the merge commit does not have: exits 0" 0 "${rc}"
fresh; mkdir "${FX}/wf.${MERGE}"; cp "${FX}/wf/gitleaks.yml" "${FX}/wf.${MERGE}/"
printf '{"sha":"%s","parents":[{"sha":"%s"},{"sha":"%s"}]}\n' "${MERGE}" "${B}" "${B}" > "${FX}/merge"
page "${FX}/checks.4" check_runs "$(check_run gitleaks completed failure)"; wait_pr
is "a stale merge ref: the head's workflows are waited on" 1 "${rc}"
check "a stale merge ref: pending, naming the head's workflow" said "pending: .github/workflows/ci.yml (no run on ${H:0:7})"
# The head's answer is kept too: three pending reads read the merge ref and the workflows once.
is "a stale merge ref: read once per wait" 1 "$(grep -c 'commits/refs/pull/7/merge' "${ROOT}/gh.log")"
is "a stale merge ref: the workflows read once per wait" 1 "$(grep -c 'contents/.github/workflows/ci.yml' "${ROOT}/gh.log")"

# A merge ref GitHub has not made yet (422) gives the head's workflows; any other failed read of it
# is an error, never a quiet fall back to the head.
fresh; mkdir "${FX}/wf.${MERGE}"; cp "${FX}/wf/gitleaks.yml" "${FX}/wf.${MERGE}/"
echo "gh: No commit found for SHA: refs/pull/7/merge (HTTP 422)" > "${FX}/merge.err"
page "${FX}/checks.2" check_runs "$(check_run gitleaks completed failure)"; wait_pr
is "no merge ref yet: the head's workflows are waited on" 1 "${rc}"
fresh; mkdir "${FX}/wf.${MERGE}"; cp "${FX}/wf/gitleaks.yml" "${FX}/wf.${MERGE}/"
echo "gh: Resource not accessible by integration (HTTP 403)" > "${FX}/merge.err"; wait_pr
is "a merge ref read refused: exits 2" 2 "${rc}"
check "a merge ref read refused: says why" said "HTTP 403"

# --- A workflow Actions has disabled is not waited on.
fresh; echo '{"total_count":1,"workflows":[{"path":".github/workflows/ci.yml","state":"disabled_manually"}]}' > "${FX}/states"
page "${FX}/checks.2" check_runs "$(check_run gitleaks completed failure)"; wait_pr
is "a disabled workflow: exits 0" 0 "${rc}"

# --- A PR past the compare API's 300 files is read from the PR files API, so a paths filter that misses
# all 301 is not waited on.
fresh; echo 301 > "${FX}/changed"; printf 'on:\n  pull_request:\n    paths: ["bin/**"]\n' > "${FX}/wf/ci.yml"
{ printf '['; for i in $(seq 1 301); do [[ ${i} -eq 1 ]] || printf ','; printf '{"filename":"docs/f%s.md"}' "${i}"; done; echo ']'; } > "${FX}/prfiles"
page "${FX}/checks.2" check_runs "$(check_run gitleaks completed failure)"; wait_pr
is "301 files, none on the paths filter: exits 0" 0 "${rc}"

# --- A red check is red whatever has run: the workflow runs are not read.
fresh; page "${FX}/checks" check_runs "$(check_run gitleaks completed failure)"; wait_pr
is "a red check: exits 1" 1 "${rc}"
is "a red check: no workflow runs read" 0 "$(grep -c 'actions/runs' "${ROOT}/gh.log" || true)"

# --- A push run of ci.yml on the head, green, is not the PR's run: still pending (red from the 2nd read,
# so a wait that took it for the PR's run shows as exit 0, one that waits as exit 1).
fresh; page "${FX}/runs" workflow_runs "${GITLEAKS_RUN}" "$(EVENT=push wf_run ci.yml completed success)"
page "${FX}/checks.2" check_runs "$(check_run gitleaks completed failure)"; wait_pr
is "a push run of the workflow, green: still waited on" 1 "${rc}"
check "a push run of the workflow, green: pending, naming it" said "pending: .github/workflows/ci.yml (no run on ${H:0:7})"
# --- An expected workflow's run that failed with no check run of its own (startup_failure) is red.
fresh; page "${FX}/runs" workflow_runs "${GITLEAKS_RUN}" "$(wf_run ci.yml completed startup_failure)"; wait_pr
is "an expected run that failed with no check: exits 1" 1 "${rc}"
check "an expected run that failed with no check: names it" said "red: .github/workflows/ci.yml (startup_failure)"

# --- A paths filter that misses every file the PR changes, or types with no synchronize: not waited on.
fresh; printf 'on:\n  pull_request:\n    paths:\n      - "docs/**"\n      - README.md\n' > "${FX}/wf/ci.yml"; wait_pr
is "a paths filter that misses the PR's files: exits 0" 0 "${rc}"
check "a paths filter that misses the PR's files: no pending line" test "$(grep -c '^pending' "${ROOT}/out")" -eq 0
fresh; printf 'on:\n  pull_request:\n    paths: ["bin/**"]\n' > "${FX}/wf/ci.yml"; page "${FX}/checks.2" check_runs "$(check_run gitleaks completed failure)"; wait_pr
is "a paths filter that matches the PR's files: waited on" 1 "${rc}"
check "a paths filter that matches the PR's files: pending, naming it" said "pending: .github/workflows/ci.yml (no run on ${H:0:7})"
# A head may be the PR's first (opened) or a later push (synchronize): types without both are not waited on.
fresh; printf 'on:\n  pull_request:\n    types: [synchronize]\n' > "${FX}/wf/ci.yml"; wait_pr
is "types with no opened: exits 0" 0 "${rc}"
fresh; printf 'on:\n  pull_request:\n    types: [closed]\n' > "${FX}/wf/ci.yml"; wait_pr
is "types with neither: exits 0" 0 "${rc}"
fresh; printf 'on:\n  pull_request:\n    types: [opened, synchronize, reopened]\n' > "${FX}/wf/ci.yml"; page "${FX}/checks.2" check_runs "$(check_run gitleaks completed failure)"; wait_pr
is "types with opened and synchronize: waited on" 1 "${rc}"

# --- A workflow whose triggers ci_gate cannot read is not waited on, and the output names it.
fresh; printf 'on: {pull_request: {branches: [main]}}\n' > "${FX}/wf/ci.yml"; wait_pr
is "triggers not read: exits 0" 0 "${rc}"
check "triggers not read: named on a line of its own" grep -q '^not waited on: .github/workflows/ci.yml (triggers not read: ' "${ROOT}/out"
is "triggers not read: named once" 1 "$(grep -c 'triggers not read' "${ROOT}/out")"

# --- An expected workflow that never starts ends the wait with exit 2 after the grace, naming it.
# Red from the 12th read, so a grace that never ends shows as exit 1, not a hang.
fresh; page "${FX}/checks.12" check_runs "$(check_run gitleaks completed failure)"; wait_pr SWARM_WAIT_PR_GRACE=2 SWARM_MERGE_POLL=1
is "a workflow that never starts: exits 2" 2 "${rc}"
check "a workflow that never starts: names it" said "swarm: wait-pr: .github/workflows/ci.yml: a pull_request into main runs it, but it has no run on ${H:0:7}"

# --- ci_gate head with no base, PR and count: today's verdict, the checks alone (green).
fresh; rc=0; PATH="${ROOT}/bin:${PATH}" python3 "${GATE}" head o/r "${H}" > "${ROOT}/out" 2>&1 || rc=$?
is "ci_gate head with no extra args: green on gitleaks alone" 0 "${rc}"
is "ci_gate head with no extra args: prints the check" "gitleaks (success)" "$(cat "${ROOT}/out")"
is "ci_gate head with no extra args: reads no workflow" 0 "$(grep -c 'actions/runs\|contents/' "${ROOT}/gh.log" || true)"

if [[ ${fails} -eq 0 ]]; then echo "all wait-pr expected-workflow tests passed"; else echo "${fails} wait-pr expected-workflow test(s) failed"; exit 1; fi
