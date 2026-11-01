#!/usr/bin/env bash
# plan_lines_test.sh — wait --lead's planned: line (plan_lines). A plan swarm's tab record (.swarm/state/scope-<epic>,
# or plan-<hld>) lists its open agents; once each has written .swarm/<epic>/<name>.json, fresh by its planner's
# resume rule and valid JSON, and no plan board PR worktree exists, one read of the queue prints
# `planned: <epic> (<names> done), exit: /swarm-dev:plan-epic <epic>` and logs lead-woken <epic>.
# gh is a stub whose pr list prints ${ROOT}/prs.json (no PR when it is missing); herdr a stub listing no agent.
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
cat > "${ROOT}/bin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[]}}' ;;
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
# fresh — an active epic e an hour old, a scope-e record listing survey-e and critic, both outputs
# written now and valid; no HLD plan, no worktree, no earlier run.
fresh() {
  rm -rf "${S}" "${ROOT}/proj-wt" "${ROOT}/prs.json" "${P}/docs/hld"/*.md
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

fresh; echo '{"findings":[' > "${S}/e/critic.json"
check "with a malformed output, no planned: line" test -z "$(poll | grep '^planned: ')"

fresh; rm -f "${S}/e/critic.json"; echo '{"findings":[]}' > "${S}/e/critic.json.partial"
check "with an agent still at work (only its .partial), no planned: line" test -z "$(poll | grep '^planned: ')"

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
