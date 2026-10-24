#!/usr/bin/env bash
# grant_pinned_head_test.sh — with merge = human, swarm.sh merge --head <sha> judges the grant at the
# head it pinned: a PR whose head moves off it while pr_hld reads the PR (before or after the files
# are listed) resolves to no HLD and does not merge, and an unmoved head still resolves to its HLD and
# merges. The gh stub is merge_test.sh's, trimmed to what a story merge reads; its pr view serves the
# head from ${FX}/head.<n> on the nth read, else ${FX}/head.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'chmod -R u+rwx "${ROOT}" 2>/dev/null; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; FX="${ROOT}/fx"
H1=1111111111111111111111111111111111111111; H2=2222222222222222222222222222222222222222
M=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; URL=https://github.com/o/r/pull/7
mkdir -p "${P}/.claude/swarm" "${P}/docs/stories" "${P}/docs/epics" "${P}/docs/hld" "${P}/.swarm/state" "${ROOT}/bin"
git -C "${P}" init -q
git init -q --bare "${ROOT}/origin.git"; git -C "${P}" remote add origin "${ROOT}/origin.git"

# gh: pr view, pr merge (fails unless --match-head-commit is ${H1}; marks the PR merged with merge
# commit ${M}), repo view (the merge methods, or with nameWithOwner o/r) and each api path from
# serve's fixture.
printf '#!/usr/bin/env bash\nFX="%s"; LOG="%s"; M="%s"; H1="%s"\n' "${FX}" "${ROOT}/gh.log" "${M}" "${H1}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "${LOG}"
# serve <key> — the fixture <key>.<n> on the nth read of <key> when there is one, else <key>; with
# neither, a 404 Not Found.
serve() {
  local n; n=$(( $(cat "${FX}/$1.n" 2>/dev/null || echo 0) + 1 )); echo "${n}" > "${FX}/$1.n"
  if [ -e "${FX}/$1.${n}" ]; then cat "${FX}/$1.${n}"
  elif [ -e "${FX}/$1" ]; then cat "${FX}/$1"
  else echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
}
case "$1 $2" in
  "pr view") printf '{"state":"%s","headRefOid":"%s","baseRefName":"main","mergeCommit":%s,"changedFiles":%s}\n' \
               "$(cat "${FX}/state")" "$(serve head)" "$(cat "${FX}/mergecommit")" "$(cat "${FX}/nfiles")" ;;
  "pr merge") want=""; prev=""; for a in "$@"; do [ "${prev}" != --match-head-commit ] || want="${a}"; prev="${a}"; done
              [ "${want}" = "${H1}" ] || { echo "GraphQL: Head branch was modified. Review and try the merge again." >&2; exit 1; }
              echo MERGED > "${FX}/state"; printf '{"oid":"%s"}' "${M}" > "${FX}/mergecommit" ;;
  "repo view") case "$*" in *nameWithOwner*) echo '{"nameWithOwner":"o/r"}' ;;
                 *) echo '{"squashMergeAllowed":true,"mergeCommitAllowed":true,"rebaseMergeAllowed":true}' ;; esac ;;
  "pr list") echo '[]' ;;
  api*)
    for a in "$@"; do path="${a}"; done
    sha="${path#*/commits/}"; sha="${sha%%/*}"
    case "${path}" in
      *"mergeQueue(branch"*) echo '{"data":{"repository":{"mergeQueue":null}}}' ;;
      */check-runs*) serve "${sha}.checks" ;;
      */commits/*/status*) serve "${sha}.status" ;;
      */actions/runs*) sha="${path#*head_sha=}"; serve "${sha%%&*}.runs" ;;
      */pulls/*/files*) serve files ;;
      */rules/branches/*) echo '[]' ;;
      */branches/*) echo "gh: Branch not protected (HTTP 404)" >&2; exit 1 ;;
      */contents/.github/workflows\?*) serve workflows ;;
      */contents/*) f="${path%%\?*}"; serve "wf.${f##*/}" ;;
      *) echo "stub: no fixture for ${path}" >&2; exit 1 ;;
    esac ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
chmod +x "${ROOT}/bin/gh"
# claude: never the real one.
printf '#!/bin/sh\nexit 0\n' > "${ROOT}/bin/claude"; chmod +x "${ROOT}/bin/claude"

# run <name> <status> [conclusion] [sha] — one check run, or with [sha] one workflow run on it.
run() {
  local c=null; [[ -z "${3:-}" ]] || c="\"$3\""
  printf '{"name":"%s","status":"%s","conclusion":%s,"html_url":"https://github.com/o/r/runs/%s","path":".github/workflows/%s.yml","head_sha":"%s"}' \
    "$1" "$2" "${c}" "$1" "$1" "${4:-${M}}"
}
page() { local f="$1" k="$2" IFS=,; shift 2; printf '{"total_count":%s,"%s":[%s]}\n' "$#" "${k}" "$*" > "${f}"; }

# fresh <files> — merge = human; story s in review with prs: ${URL} under epic g, under agreed HLD h
# granting merge; the PR at head ${H1}, green, changing <files> (a JSON list); on the merge commit a
# green check run and a green run of the one workflow that runs on push to main.
fresh() {
  rm -rf "${FX}" "${P}/.swarm/events.tsv"; mkdir -p "${FX}"; : > "${ROOT}/gh.log"
  echo "merge = human" > "${P}/.claude/swarm/config"
  echo OPEN > "${FX}/state"; echo "${H1}" > "${FX}/head"; echo null > "${FX}/mergecommit"
  echo "$1" > "${FX}/files"; grep -o '"filename"' <<< "$1" | wc -l | tr -d ' ' > "${FX}/nfiles"
  printf -- '---\nstatus: agreed\ngrants: [merge]\n---\n\n# h\n' > "${P}/docs/hld/h.md"
  printf -- '---\nstatus: active\nhld: h\n---\n\n# g\n' > "${P}/docs/epics/g.md"
  printf -- '---\nstatus: review\nprs: %s\nepic: g\n---\n\n# s\n' "${URL}" > "${P}/docs/stories/s.md"
  rm -rf "${P}/.swarm/board-state"
  page "${FX}/${H1}.checks" check_runs "$(run test completed success)"; page "${FX}/${H1}.status" statuses
  page "${FX}/${M}.checks" check_runs "$(run test completed success)"; page "${FX}/${M}.status" statuses
  echo '[{"name":"ci.yml","path":".github/workflows/ci.yml","type":"file"}]' > "${FX}/workflows"
  printf 'name: ci\non:\n  push:\n    branches: [main]\n' > "${FX}/wf.ci.yml"
  page "${FX}/${M}.runs" workflow_runs "$(run ci completed success "${M}")"
}
merge() {
  rc=0
  (cd "${P}" && env -u HERDR_ENV -u HERDR_PANE_ID -u SWARM_PROJECT -u SWARM_AGENT PATH="${ROOT}/bin:${PATH}" SWARM_MERGE_POLL=0 SWARM_MERGE_READ_WAIT=0 \
    SWARM_MERGE_CI_GRACE=0 SWARM_MERGE_CI_SECONDS=5 bash "${SWARM}" merge "$@" > "${ROOT}/out" 2>&1) || rc=$?
}

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
merged() { grep -q '^pr merge' "${ROOT}/gh.log"; }
not_merged() { ! merged; }
said() { grep -qF -- "$1" "${ROOT}/out"; }
MOVED="the head of ${URL} moved off 1111111 while the grant read it, so no grant covers the head: review the new head"
STORY='{"filename":"docs/stories/s.md","status":"modified"}'
WORKFLOW='{"filename":".github/workflows/x.yml","status":"added"}'

# merge's own pr view reads ${H1}; pr_hld's, the PR's second read, finds ${H2}, which adds a workflow.
fresh "[${STORY},${WORKFLOW}]"; echo "${H2}" > "${FX}/head.2"
merge --head "${H1}" "${URL}"
is "the head moves before the grant lists its files: exits non-zero" 1 "${rc}"
check "the head moves before the grant lists its files: says the head moved" said "${MOVED}"
check "the head moves before the grant lists its files: no pr merge" not_merged

# pr_hld's first read finds ${H1}, the files listed are ${H2}'s, and its read after them finds ${H2}.
fresh "[${STORY},${WORKFLOW}]"; echo "${H2}" > "${FX}/head.3"
merge --head "${H1}" "${URL}"
is "the head moves while the grant lists its files: exits non-zero" 1 "${rc}"
check "the head moves while the grant lists its files: says the head moved" said "${MOVED}"
check "the head moves while the grant lists its files: no pr merge" not_merged

# An unmoved head resolves to h, which grants merge: it merges, s.md read at the pinned head.
fresh "[${STORY}]"
merge --head "${H1}" "${URL}"
is "an unmoved head: exits 0" 0 "${rc}"
check "an unmoved head: merged" merged
check "an unmoved head: the grant read s.md at the pinned head" grep -q "repos/o/r/contents/docs/stories/s.md?ref=${H1}" "${ROOT}/gh.log"

echo
[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; cat "${ROOT}/out"; exit 1; }
echo "all passed"
