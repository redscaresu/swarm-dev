#!/usr/bin/env bash
# wait_pr_expected_test.sh — swarm.sh wait-pr waits on each workflow at the head that a pull_request
# into the base runs with the PR's files: one with no run yet, or a run not finished, is pending, even
# when every check already there is green. A workflow whose paths or types leave this PR out is not
# waited on; one whose triggers ci_gate cannot read is not waited on and is named; one that never
# starts ends the wait with exit 2 after the grace. ci_gate head with no base, PR and count judges the
# checks alone, as before. gh is a stub on PATH: it logs every call to gh.log and answers pr view with
# ${H}, MERGEABLE, main, OPEN and one changed file; the nth check-runs read from ${FX}/checks.<n>
# (else ${FX}/checks) and the nth workflow-runs read from ${FX}/runs.<n> (else ${FX}/runs); the
# .github/workflows listing from the files in ${FX}/wf, each file's text from there too; the PR's
# files at ${H} (compare main...${H}) from ${FX}/files.
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
  "pr view"*) echo "${H} MERGEABLE main OPEN 1" ;;
  *check-runs*) nth checks; if [ -e "${FX}/checks.${n}" ]; then cat "${FX}/checks.${n}"; else cat "${FX}/checks"; fi ;;
  */status*) echo '{"total_count":0,"statuses":[]}' ;;
  *actions/runs*) nth runs; if [ -e "${FX}/runs.${n}" ]; then cat "${FX}/runs.${n}"; else cat "${FX}/runs"; fi ;;
  *"contents/.github/workflows?ref=${H}") printf '['; sep=""
    for f in "${FX}"/wf/*; do printf '%s{"type":"file","name":"%s","path":".github/workflows/%s"}' "${sep}" "${f##*/}" "${f##*/}"; sep=,; done
    echo ']' ;;
  *"contents/.github/workflows/"*) a="$*"; f="${a##*/}"; cat "${FX}/wf/${f%%\?*}" ;;
  *"compare/main...${H}") cat "${FX}/files" ;;
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
# wf_run takes the event as EVENT, pull_request by default.
wf_run() { local c=null; [[ -z "${3:-}" ]] || c="\"$3\""; printf '{"path":".github/workflows/%s","event":"%s","head_sha":"%s","status":"%s","conclusion":%s}' "$1" "${EVENT:-pull_request}" "${H}" "$2" "${c}"; }
# page <file> <key> <item>... — one page of items under <key>.
page() { local f="$1" k="$2" IFS=,; shift 2; printf '{"total_count":%s,"%s":[%s]}\n' "$#" "${k}" "$*" > "${f}"; }
GITLEAKS="$(check_run gitleaks completed success)"; GITLEAKS_RUN="$(wf_run gitleaks.yml completed success)"
SHARDS="$(check_run "test-shard (1)" completed success),$(check_run "test-shard (2)" completed success),$(check_run test completed success)"
CI_RUN="$(wf_run ci.yml completed success)"
# fresh — gitleaks.yml (on: [push, pull_request]) and ci.yml (on: pull_request into main) at the head,
# the PR changing bin/swarm.sh; only gitleaks' run and check exist, green.
fresh() {
  rm -rf "${FX}"; mkdir -p "${FX}/wf"; : > "${ROOT}/gh.log"
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
check "triggers not read: named in the output" said ".github/workflows/ci.yml (triggers not read, so not waited on:"

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
