#!/usr/bin/env bash
# grant_pinned_head_test.sh — with merge = human, swarm.sh merge --head <sha> judges the grant at the
# head and base it pinned: a PR whose head or base has moved off them resolves to no HLD and does not
# merge, the PR's files are read at the pin (compare <base>...<sha>) whatever head the PR lists them
# for by then, a file list cut short resolves to none, and an unmoved head still resolves to its HLD
# and merges. A workflow file puts the PR under none (.github/ is a path only the user changes, and
# the PR is epic g's, which no story lists, so a file off the board would too). The gh stub is
# merge_fixture.sh's, trimmed to what a merge reads; its pr view serves the head from ${FX}/head.<n> on
# the nth read, else ${FX}/head (the base likewise), and compare/<base>...<sha> serves
# ${FX}/compare.<sha>.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

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
  "pr view") printf '{"state":"%s","headRefOid":"%s","baseRefName":"%s","mergeCommit":%s,"changedFiles":%s}\n' \
               "$(cat "${FX}/state")" "$(serve head)" "$(serve base)" "$(cat "${FX}/mergecommit")" "$(cat "${FX}/nfiles")" ;;
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
      # The PR's commits, through merge's --jq filter: one plain commit at ${FX}/head, so no merge to scan.
      */pulls/*/commits*) q=.; prev=""; for a in "$@"; do [ "${prev}" != --jq ] || q="${a}"; prev="${a}"; done
                          printf '[{"sha":"%s","parents":[{"sha":"%040d"}]}]\n' "$(cat "${FX}/head")" 0 | jq -r "${q}" ;;
      # compare/<head>...main, merge's read of what the base gained: nothing.
      */compare/*...main) echo '{"ahead_by":0,"files":[]}' ;;
      */compare/*) serve "compare.${path##*...}" ;;
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

# fresh <files> — merge = human; epic g in review with prs: ${URL}, under agreed HLD h granting merge,
# and story s, ready under g; the PR at head ${H1}, green, listing <files> (a JSON list) now and at
# ${H1}; on the merge commit a green check run and a green run of the one workflow that runs on push
# to main.
fresh() {
  rm -rf "${FX}" "${P}/.swarm/events.tsv"; mkdir -p "${FX}"; : > "${ROOT}/gh.log"
  echo "merge = human" > "${P}/.claude/swarm/config"
  echo OPEN > "${FX}/state"; echo "${H1}" > "${FX}/head"; echo main > "${FX}/base"; echo null > "${FX}/mergecommit"
  echo "$1" > "${FX}/files"; at "${H1}" "$1"; grep -o '"filename"' <<< "$1" | wc -l | tr -d ' ' > "${FX}/nfiles"
  printf -- '---\nstatus: agreed\ngrants: [merge]\n---\n\n# h\n' > "${P}/docs/hld/h.md"
  printf -- '---\nstatus: review\nhld: h\nprs: %s\n---\n\n# g\n' "${URL}" > "${P}/docs/epics/g.md"
  printf -- '---\nstatus: ready\nkind: code\nepic: g\n---\n\n# s\n' > "${P}/docs/stories/s.md"
  cp "${P}/docs/epics/g.md" "${FX}/wf.g.md"; cp "${P}/docs/stories/s.md" "${FX}/wf.s.md"
  rm -rf "${P}/.swarm/board-state"
  page "${FX}/${H1}.checks" check_runs "$(run test completed success)"; page "${FX}/${H1}.status" statuses
  page "${FX}/${M}.checks" check_runs "$(run test completed success)"; page "${FX}/${M}.status" statuses
  echo '[{"name":"ci.yml","path":".github/workflows/ci.yml","type":"file"}]' > "${FX}/workflows"
  printf 'name: ci\non:\n  push:\n    branches: [main]\n' > "${FX}/wf.ci.yml"
  page "${FX}/${M}.runs" workflow_runs "$(run ci completed success "${M}")"
}
# at <sha> <files> — the PR's files at <sha> (a JSON list), as compare <base>...<sha> gives them.
at() { echo "{\"files\":$2}" > "${FX}/compare.$1"; }
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
MOVED="the head of ${URL} is 2222222, not 1111111, so no grant covers it: review the new head"
WAIT="${URL} waits on the user's merge (merge = human, and no HLD grants merge for it)"
EPIC='{"filename":"docs/epics/g.md","status":"modified"}'
STORY='{"filename":"docs/stories/s.md","status":"modified"}'
WORKFLOW='{"filename":".github/workflows/x.yml","status":"added"}'
ON="[${EPIC},${STORY}]"; OFF="[${EPIC},${WORKFLOW}]"   # two files each: on the board, and one off it

# merge's pr view reads ${H1}; pr_hld's, the PR's second read, finds ${H2}, which adds a workflow.
fresh "${OFF}"; at "${H1}" "${ON}"; at "${H2}" "${OFF}"; echo "${H2}" > "${FX}/head.2"
merge --head "${H1}" "${URL}"
is "the head moves to one adding a workflow: exits non-zero" 1 "${rc}"
check "the head moves to one adding a workflow: says it is 2222222, not 1111111" said "${MOVED}"
check "the head moves to one adding a workflow: no pr merge" not_merged

# merge's pr view reads base main; pr_hld's finds the PR retargeted at dev, its head unmoved.
fresh "${ON}"; echo dev > "${FX}/base.2"
merge --head "${H1}" "${URL}"
is "the PR retargeted after the pin: exits non-zero" 1 "${rc}"
check "the PR retargeted after the pin: says its base is dev, not main" said "the base of ${URL} is dev, not main, so no grant covers it: review it against dev"
check "the PR retargeted after the pin: no pr merge" not_merged

# pr_hld's read gets no head, then no base, from gh: the grant cannot tell, and says which. (With no
# head it reads no board file at all, so that PR is under none further on too.)
fresh "${ON}"; echo > "${FX}/head.2"
merge --head "${H1}" "${URL}"
check "gh gives the grant no head: says so" said "grants: gh gave no head SHA for ${URL}"
fresh "${ON}"; echo > "${FX}/base.2"
merge --head "${H1}" "${URL}"
is "gh gives the grant no base: exits non-zero" 1 "${rc}"
check "gh gives the grant no base: says so" said "grants: gh gave no base branch for ${URL}"
check "gh gives the grant no base: no pr merge" not_merged

# The head reads ${H1}, but the PR lists its files for another head by then (a push and a push back):
# the grant judges ${H1}'s, which add a workflow.
fresh "${ON}"; at "${H1}" "${OFF}"
merge --head "${H1}" "${URL}"
is "the pinned head adds a workflow the PR's file list lacks: exits non-zero" 1 "${rc}"
check "the pinned head adds a workflow the PR's file list lacks: no HLD grants merge" said "${WAIT}"
check "the pinned head adds a workflow the PR's file list lacks: no pr merge" not_merged

# The files at the pin come back fewer than the PR changes (compare lists 300 at most): under none.
# The epic guard's read of them is the first; the grant's, the second, is the one cut short.
fresh "${ON}"; echo "{\"files\":[${EPIC}]}" > "${FX}/compare.${H1}.2"
merge --head "${H1}" "${URL}"
is "the files at the pin cut short: exits non-zero" 1 "${rc}"
check "the files at the pin cut short: cannot tell which HLD" said "cannot tell which HLD ${URL} is under"
check "the files at the pin cut short: no pr merge" not_merged

# An unmoved head with no workflow resolves to h, which grants merge: it merges, its files listed
# and g.md read at the pinned head.
fresh "${ON}"
merge --head "${H1}" "${URL}"
is "an unmoved head: exits 0" 0 "${rc}"
check "an unmoved head: merged" merged
check "an unmoved head: the grant listed the files at the pinned head" grep -q "repos/o/r/compare/main...${H1}" "${ROOT}/gh.log"
check "an unmoved head: the grant read g.md at the pinned head" grep -q "repos/o/r/contents/docs/epics/g.md?ref=${H1}" "${ROOT}/gh.log"

echo
[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; cat "${ROOT}/out"; exit 1; }
echo "all passed"
