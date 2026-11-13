#!/usr/bin/env bash
# plan_lines_test.sh — wait --lead's planned: and plan-missing: lines (plan_lines). A plan swarm's tab record
# (.swarm/state/scope-<epic>, or plan-<hld>) lists its open agents, and the attempt's start marks
# (.swarm/<epic>/started/<name>, plan_mark) every agent it started; once each has written
# .swarm/<epic>/<name>.json, fresh by its planner's resume rule and valid JSON, and no plan board PR worktree
# exists, one read of the queue prints `planned: <epic> (<names> done), exit: /swarm-dev:plan-epic <epic>` and
# logs lead-woken <epic>. A marked agent that has ended without one gets `plan-missing: <epic> <name> ...`.
# gh is a stub whose pr list prints ${ROOT}/prs.json (no PR when it is missing); herdr a stub listing
# ${ROOT}/agents (no agent when it is missing), failing the list while ${ROOT}/no-list exists, and enough of
# a pane's start for `swarm.sh agent`: tab create opens pane ${ROOT}/next-pane, pane list prints
# ${ROOT}/panes.json, and agent start fails while ${ROOT}/start-fails exists.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; S="${P}/.swarm"
mkdir -p "${P}/.claude/swarm" "${P}/docs/stories" "${P}/docs/epics" "${P}/docs/hld" "${ROOT}/bin"
git -C "${P}" init -q
: > "${P}/.claude/swarm/config"

printf '#!/bin/sh\nR="%s"\n' "${ROOT}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
case "$*" in
  "pr list"*) cat "${R}/prs.json" 2>/dev/null || echo '[]' ;;
  *) exit 1 ;;
esac
STUB
printf '#!/bin/sh\nR="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'STUB'
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;
  "agent list") [ ! -f "${R}/no-list" ] || exit 1; printf '{"result":{"agents":[%s]}}\n' "$(cat "${R}/agents" 2>/dev/null)" ;;
  "tab create") printf '{"result":{"root_pane":{"pane_id":"%s"}}}\n' "$(cat "${R}/next-pane")" ;;
  "pane list") cat "${R}/panes.json" 2>/dev/null || echo '{"result":{"panes":[]}}' ;;
  "agent start") [ ! -f "${R}/start-fails" ] || { echo '{"error":{"code":"agent_name_taken"}}'; exit 1; } ;;
  "agent prompt") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  *) echo '{"result":{}}' ;;
esac
STUB
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr"

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
# old <file>... — set each file's mtime an hour back, so an output written now is newer than it.
# older <file>... — two hours back, older than a file old set.
old() { perl -e 'my $t = time - 3600; utime $t, $t, @ARGV' "$@"; }
older() { perl -e 'my $t = time - 7200; utime $t, $t, @ARGV' "$@"; }
# mark <name>... — a start mark for each, half an hour old: newer than the epic file, past PLAN_START_GRACE.
mark() {
  local n; mkdir -p "${S}/e/started"
  for n in "$@"; do touch "${S}/e/started/${n}"; done
  (cd "${S}/e/started" && perl -e 'my $t = time - 1800; utime $t, $t, @ARGV' "$@")
}
# fresh — an active epic e an hour old, a scope-e record listing survey-e and critic, both outputs
# written now and valid; no HLD plan, no worktree, no earlier run.
fresh() {
  rm -rf "${S}" "${ROOT}/proj-wt" "${ROOT}/prs.json" "${P}/docs/hld"/*.md "${ROOT}/agents" "${ROOT}/no-list" "${ROOT}/start-fails" "${ROOT}/panes.json"
  mkdir -p "${S}/state" "${S}/e"
  printf -- '---\nstatus: active\n---\n\n# e\n' > "${P}/docs/epics/e.md"; old "${P}/docs/epics/e.md"
  printf 'w:p1 survey-e\nw:p2 critic\n' > "${S}/state/scope-e"
  echo '{"summary":"s","facts":[]}' > "${S}/e/survey.json"
  echo '{"findings":[]}' > "${S}/e/critic.json"
}
# poll — one read of the lead's queue.
poll() { (cd "${P}" && env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" HERDR_ENV=1 bash "${SWARM}" wait --lead 0 2>&1) || true; }
LINE='planned: e (survey, critic done), exit: /swarm-dev:plan-epic e'

# The first read of a run with no .swarm/lead prints it: planned is no quiet kind.
fresh
out="$(poll)"
check "a plan swarm whose agents all wrote their output gets its planned: line, on a run's first read" grep -qxF "${LINE}" <<< "${out}"
# The outcome's key=value tail (append_event) follows "ok (planned)".
# shellcheck disable=SC2016 # awk's own fields
check "the planned: line logs lead-woken e" awk -F'\t' '$2 == "lead-woken" && $3 == "e" && index($5, "ok (planned)") == 1 { f = 1 } END { exit !f }' "${S}/events.tsv"
check "the next read prints it again only once it has gone from the queue" test -z "$(poll)"

fresh; mkdir -p "${ROOT}/proj-wt/_board-scope-e"
check "with the plan board PR's worktree there, no planned: line" test -z "$(poll | grep '^planned: ')"

fresh; older "${S}/e/critic.json"
check "with an output older than the epic file (an earlier plan's), no planned: line" test -z "$(poll | grep '^planned: ')"

fresh; echo '{"findings":[' > "${S}/e/critic.json"   # vacuous-test: ok, malformed on purpose
check "with a malformed output, no planned: line" test -z "$(poll | grep '^planned: ')"

fresh; rm -f "${S}/e/critic.json"; echo '{"findings":[]}' > "${S}/e/critic.json.partial"
check "with an agent still at work (only its .partial), no planned: line" test -z "$(poll | grep '^planned: ')"

# plan-missing: an agent of the attempt (its start mark) that has ended without a counted output. A poll
# takes tens of seconds, so one board holds every case, one agent each, each mark half an hour old unless
# said: critic (in the record, not listed: its pane closed), skeptic-a (working, only a .partial),
# skeptic-b (listed idle, only a .partial), skeptic-c (listed done), skeptic-d (not listed, its output
# malformed), skeptic-h (not listed, its output older than the epic file), skeptic-g (its mark only: its
# start failed and a later start pruned its pane from the record), skeptic-f (not listed, marked now:
# its start may still be under way), skeptic-i (its mark only, older than the epic file: an earlier
# attempt's), skeptic-j (listed working, but in a pane no record of this project has).
# missing_line <epic> <name> — the plan-missing: line for <name> of epic <epic>'s plan.
missing_line() { echo "plan-missing: $1 $2 ended without its output, exit: /swarm-dev:plan-epic $1 (it starts that agent again)"; }
many() {
  fresh; rm -f "${S}/e/critic.json"
  printf 'w:p1 survey-e\nw:p2 critic\nw:p3 skeptic-a\nw:p4 skeptic-b\n' > "${S}/state/scope-e"
  printf 'w:p5 skeptic-c\nw:p6 skeptic-d\nw:p7 skeptic-f\nw:p8 skeptic-h\n' > "${S}/state/scope-e-2"
  mark survey-e critic skeptic-a skeptic-b skeptic-c skeptic-d skeptic-g skeptic-h skeptic-j
  touch "${S}/e/started/skeptic-f" "${S}/e/started/skeptic-i"; older "${S}/e/started/skeptic-i"
  echo '{"findings":[]}' > "${S}/e/skeptic-a.json.partial"; echo '{"findings":[]}' > "${S}/e/skeptic-b.json.partial"
  echo '{"findings":[' > "${S}/e/skeptic-d.json"   # vacuous-test: ok, malformed on purpose
  echo '{"findings":[]}' > "${S}/e/skeptic-h.json"; older "${S}/e/skeptic-h.json"
  printf '%s,%s,%s,%s' '{"name":"skeptic-a","agent_status":"working","pane_id":"w:p3"}' '{"name":"skeptic-b","agent_status":"idle","pane_id":"w:p4"}' \
    '{"name":"skeptic-c","agent_status":"done","pane_id":"w:p5"}' '{"name":"skeptic-j","agent_status":"working","pane_id":"w:p99"}' > "${ROOT}/agents"
}
many; touch "${ROOT}/no-list"
check "a poll with no herdr list prints no plan-missing: line" test -z "$(poll | grep '^plan-missing: ')"
rm -f "${ROOT}/no-list"
out="$(poll)"
check "a marked critic with no critic.json, no longer running, gets plan-missing: e critic" grep -qxF "$(missing_line e critic)" <<< "${out}"
check "a swarm with an agent missing its output gets no planned: line" test -z "$(grep '^planned: ' <<< "${out}")"
# shellcheck disable=SC2016 # awk's own fields
check "the plan-missing: line logs lead-woken e" awk -F'\t' '$2 == "lead-woken" && $3 == "e" && index($5, "ok (plan-missing)") == 1 { f = 1 } END { exit !f }' "${S}/events.tsv"
check "a skeptic still working, with only its .partial, gets no line" test -z "$(grep '^plan-missing: e skeptic-a ' <<< "${out}")"
check "a skeptic herdr still lists but as idle, with only its .partial, gets plan-missing:" grep -qxF "$(missing_line e skeptic-b)" <<< "${out}"
check "a skeptic herdr lists as done gets plan-missing:" grep -qxF "$(missing_line e skeptic-c)" <<< "${out}"
check "an ended skeptic whose output is malformed gets plan-missing:" grep -qxF "$(missing_line e skeptic-d)" <<< "${out}"
check "an ended skeptic whose output is older than the epic file gets plan-missing:" grep -qxF "$(missing_line e skeptic-h)" <<< "${out}"
check "a skeptic whose pane left the record still gets plan-missing: from its mark" grep -qxF "$(missing_line e skeptic-g)" <<< "${out}"
check "a skeptic marked within PLAN_START_GRACE (its start may still be under way) gets no line" test -z "$(grep '^plan-missing: e skeptic-f ' <<< "${out}")"
check "a mark older than the epic file (an earlier attempt's) gets no line" test -z "$(grep '^plan-missing: e skeptic-i ' <<< "${out}")"
check "an agent of that name in a pane no record of this project has is not the skeptic: plan-missing:" grep -qxF "$(missing_line e skeptic-j)" <<< "${out}"
check "survey, its output counted, gets no line" test -z "$(grep '^plan-missing: e survey ' <<< "${out}")"
touch "${ROOT}/no-list"
check "a later poll with no herdr list keeps the seen lines, so it wakes no one" test -z "$(poll)"
rm -f "${ROOT}/no-list"
check "nor does the good poll after it: the lines never left the seen queue" test -z "$(poll)"

# The marks start_agent writes: a critic whose start fails (herdr agent start refused twice, its pane closed),
# then survey-e's start, which prunes the closed pane from the record before it opens its own. The same
# poll reads an HLD plan h whose marked hld-lead has ended without its output.
fresh; rm -f "${S}/state/scope-e" "${S}/e/critic.json"; echo 'brief' > "${ROOT}/brief.md"
start() { (cd "${P}" && env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" HERDR_ENV=1 HERDR_WORKSPACE_ID=w bash "${SWARM}" agent scope-e "$1" "${P}" codex "${ROOT}/brief.md" >/dev/null 2>&1); }
echo 'w:p1' > "${ROOT}/next-pane"; touch "${ROOT}/start-fails"
check "the critic's start fails" test -n "$(start critic || echo failed)"
rm -f "${ROOT}/start-fails"; echo 'w:p9' > "${ROOT}/next-pane"; echo '{"result":{"panes":[{"pane_id":"w:p9"}]}}' > "${ROOT}/panes.json"
start survey-e
check "survey-e's start pruned the critic's pane from the record" test "$(cat "${S}/state/scope-e")" = 'w:p9 survey-e'
check "each start left its mark" test -f "${S}/e/started/critic" -a -f "${S}/e/started/survey-e"
perl -e 'my $t = time - 1800; utime $t, $t, @ARGV' "${S}/e/started/critic" "${S}/e/started/survey-e"
echo '{"name":"survey-e","agent_status":"working","pane_id":"w:p9"}' > "${ROOT}/agents"
printf -- '---\nstatus: agreed\n---\n\n# h\n' > "${P}/docs/hld/h.md"
mkdir -p "${S}/h/started"; echo 0123abc > "${S}/h/base-rev"; old "${S}/h/base-rev"
echo 'w:p4 hld-lead' > "${S}/state/plan-h"; touch "${S}/h/started/hld-lead"
perl -e 'my $t = time - 1800; utime $t, $t, @ARGV' "${S}/h/started/hld-lead"
out="$(poll)"
check "a critic that failed to start, its pane pruned by a sibling's start, still gets plan-missing: e critic" grep -qxF "$(missing_line e critic)" <<< "${out}"
check "and survey, with its output written, gets no plan-missing: line" test -z "$(grep '^plan-missing: e survey ' <<< "${out}")"
check "an HLD plan's ended agent gets plan-missing: with the /swarm-dev:plan-hld exit" \
  grep -qxF 'plan-missing: h hld-lead ended without its output, exit: /swarm-dev:plan-hld h (it starts that agent again)' <<< "${out}"

# An HLD plan: the record plan-h, its outputs newer than .swarm/h/base-rev.
hld() {
  fresh; rm -f "${S}/state/scope-e"
  printf -- '---\nstatus: agreed\n---\n\n# h\n' > "${P}/docs/hld/h.md"
  mkdir -p "${S}/h"; echo 0123abc > "${S}/h/base-rev"; old "${S}/h/base-rev"
  printf 'w:p3 survey-code\nw:p4 hld-lead\n' > "${S}/state/plan-h"
  echo '{"summary":"s","facts":[]}' > "${S}/h/survey-code.json"
  echo '{"epics":[]}' > "${S}/h/hld-lead.json"
}
hld
check "a plan-<hld> record gives the /swarm-dev:plan-hld exit" \
  grep -qxF 'planned: h (survey-code, hld-lead done), exit: /swarm-dev:plan-hld h' <<< "$(poll)"
hld; older "${S}/h/hld-lead.json"
check "an HLD plan output older than base-rev gives no planned: line" test -z "$(poll | grep '^planned: ')"
hld; mkdir -p "${ROOT}/proj-wt/_board-plan-h"
check "a plan-<hld> record with the plan worktree but no PR yet gives no planned: line" test -z "$(poll | grep '^planned: ')"
hld; mkdir -p "${ROOT}/proj-wt/_board-plan-h"
echo '[{"url":"https://github.com/o/r/pull/9","headRefName":"board/plan-h"}]' > "${ROOT}/prs.json"
check "a plan-<hld> record with its plan PR opened gives no planned: line" test -z "$(poll | grep '^planned: ')"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
