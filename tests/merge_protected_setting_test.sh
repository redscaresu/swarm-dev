#!/usr/bin/env bash
# merge_protected_setting_test.sh — merge_protected, under merge = agent: unset or off, swarm.sh merge
# holds a reviewed story PR that changes .github/workflows/x.yml for the user, and gh merges nothing; on,
# it merges that PR once, printing and logging the protected path and the setting. On lifts only that
# hold: a PR whose own merge of the base dropped a base line, and a costs: money story's PR, are still
# held. A value other than off or on fails, naming the key and its line. On merge_fixture.sh, as
# merge_protected_hold_test.sh is; the dropped-lines case builds its repos as merge_rules_test.sh does.
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

WF=.github/workflows/x.yml
LIFTED="protected path: ${WF}, merged under merge_protected = on"
# changes <path>... — the PR's files: story s's file and each <path>, all modified.
changes() {
  local p list='{"filename":"docs/stories/s.md","status":"modified"}'
  for p in "$@"; do list+=",{\"filename\":\"${p}\",\"status\":\"modified\"}"; done
  echo "[${list}]" > "${FX}/files"; echo $(($# + 1)) > "${FX}/nfiles"
}
merges() { grep -c '^pr merge' "${ROOT}/gh.log" || true; }

# --- Unset and off: the hold stands, and gh merges nothing.
for name in "merge_protected unset" "merge_protected off"; do
  if [[ "${name}" == *off ]]; then fresh "merge_protected = off"; else fresh; fi
  changes "${WF}"; merge "${URL}"
  refused "${name}: a story PR changing ${WF}" "held: s changes ${WF}, which only the user merges; the user merges it"
  check "${name}: events.tsv has the held line" logged "^merge s held: s changes ${WF}"
  check "${name}: no merge_protected line" bash -c "! grep -qF 'merged under merge_protected' '${ROOT}/out'"
done

# --- On: gh merges it once, and the output and events.tsv name the path and the setting.
fresh "merge_protected = on"; changes "${WF}"; merge "${URL}"
is "merge_protected on: a story PR changing ${WF} exits 0" 0 "${rc}"
is "merge_protected on: gh pr merge ran once" 1 "$(merges)"
check "merge_protected on: says ${LIFTED}" said "${LIFTED}"
is "merge_protected on: events.tsv names the path and the setting, then the merge" \
  "merge s ${LIFTED}|merge s ok|main-ci s ok|reconcile s ok (finished)" "$(events | paste -sd'|' -)"
# A PR with no protected path merges as before, with no such line.
fresh "merge_protected = on"; changes bin/x.sh; merge "${URL}"
is "merge_protected on: a story PR changing bin/x.sh merges with no protected path line" \
  "0|1|merge s ok|main-ci s ok|reconcile s ok (finished)" "${rc}|$(merges)|$(events | paste -sd'|' -)"

# --- On: a costs: money story's PR is still held.
fresh "merge_protected = on"; item s "status: review" "prs: ${URL}" "costs: money"; changes "${WF}"; merge "${URL}"
refused "merge_protected on: a costs: money story's PR changing ${WF}" "held: s costs money"

# --- On: a PR whose own merge of main dropped a base line is still held. dropped-lines reads ${ROOT}/r,
# the clone of o/r beside the project (repos_dir is the project's parent), whose origin is the bare
# ${ROOT}/o/r.git. W, a work repo, pushes main there: from main0, main replaces f's three with
# three-main and adds main-added. DROP, a branch that replaced three with three-pr, merges main and
# drops main-added.
OR="${ROOT}/o/r.git"; W="${ROOT}/w"
wg() { GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git -c user.name=t -c user.email=t@t "$@"; }
wput() { printf '%s\n' "${@:2}" > "${W}/$1"; wg -C "${W}" add -A; wg -C "${W}" commit -qm "$1"; }
wg init -q -b main "${W}"; mkdir -p "${ROOT}/o"; wg init -q --bare "${OR}"
wput f one two three four five; wg -C "${W}" branch drop
wput f one two three-main main-added four five
wg -C "${W}" push -q "${OR}" main; wg clone -q "${OR}" "${ROOT}/r"
wg -C "${W}" checkout -q drop; wput f one two three-pr four five
wg -C "${W}" merge -q --no-ff --no-commit main >/dev/null 2>&1 || true
printf '%s\n' one two three-pr three-main four five > "${W}/f"; wg -C "${W}" add -A; wg -C "${W}" commit -q --no-edit
DROP="$(wg -C "${W}" rev-parse HEAD)"
fresh "merge_protected = on"; changes "${WF}"
# PR 7's head is DROP: green, pushed to o/r's refs/pull/7/head, and gh lists W's main..DROP as its commits.
wg -C "${W}" push -q -f "${OR}" "${DROP}:refs/pull/7/head"
echo "${DROP}" > "${FX}/head"; checks "${FX}/${DROP}.checks" "$(run test completed success)"; statuses "${FX}/${DROP}.status"
json="["; sep=""
for c in $(wg -C "${W}" rev-list --reverse "main..${DROP}"); do
  ps="$(wg -C "${W}" rev-list --parents -n 1 "${c}" | cut -d' ' -f2- | sed -E 's/([0-9a-f]+)/{"sha":"\1"}/g; s/ /,/g')"
  json+="${sep}{\"sha\":\"${c}\",\"parents\":[${ps}]}"; sep=,
done
echo "${json}]" > "${FX}/prcommits"
merge "${URL}"
is "merge_protected on, dropped base line: exits non-zero" 1 "${rc}"
check "merge_protected on, dropped base line: held for the dropped line" said "merge: held: s (dropped base lines: 1, first f: main-added)"
check "merge_protected on, dropped base line: no pr merge" not_merged
check "merge_protected on, dropped base line: the protected path was passed first" said "${LIFTED}"
check "merge_protected on, dropped base line: events.tsv has the dropped-lines hold" logged "^merge s held: s (dropped base lines: 1"

# --- A value that is neither off nor on fails, naming the key and its line.
fresh "merge_protected = maybe"; changes "${WF}"; merge "${URL}"
is "merge_protected = maybe: exits non-zero" 1 "${rc}"
check "merge_protected = maybe: names the key and its line" said ".claude/swarm/config:2: merge_protected must be off or on, not 'maybe'"
check "merge_protected = maybe: no pr merge" not_merged

finish "merge protected setting"
