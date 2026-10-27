#!/usr/bin/env bash
# lead_handler_test.sh — every kind of line wait --lead prints has an arm in /swarm-dev:swarm's wait --lead
# handler (commands/swarm.md). For each kind on KINDS it builds a board that makes lead_queue print that
# kind, reads the queue once (`swarm.sh wait --lead 0`), and checks the line came out and that the handler
# names it as a backticked `<kind>: ` line. A kind on GAPS is a known gap, printed but not yet handled.
# Both lists are |-separated, as a kind may hold a space.
# gh is a stub answering a green head, whose pr list prints ${ROOT}/prs.json (no PR when it is missing) and
# repo view the origin's owner/name;
# herdr a stub listing ${ROOT}/agents (no agent when it is missing), whose agent read prints ${ROOT}/pane.txt.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWARM="${HOME_DIR}/bin/swarm.sh"
KINDS="held|escalated|merge|kept|no-agent|no-review|step-up failed|unsent brief|idle|prompt|unmerged|conflict"
GAPS=""   # none now: every kind has its arm
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; B="${P}/docs/stories"
H=1111111111111111111111111111111111111111; URL=https://github.com/na-owner/na-repo/pull/41
mkdir -p "${P}/.claude/swarm" "${B}" "${P}/.swarm/state" "${ROOT}/bin"
git -C "${P}" init -q
git -C "${P}" remote add origin https://github.com/na-owner/na-repo.git

printf '#!/bin/sh\nH="%s"\nR="%s"\n' "${H}" "${ROOT}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
case "$*" in
  "pr list"*) cat "${R}/prs.json" 2>/dev/null || echo '[]' ;;
  "repo view"*) echo na-owner/na-repo ;;
  "pr view"*) read -r _ || true; echo "${H}" ;;
  *check-runs*) echo '{"total_count":1,"check_runs":[{"name":"test","status":"completed","conclusion":"success","html_url":"u"}]}' ;;
  *status*) echo '{"total_count":0,"statuses":[]}' ;;
  *) exit 1 ;;
esac
STUB
printf '#!/bin/sh\nR="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'STUB'
case "$1 $2" in
  "agent list") printf '{"result":{"agents":[%s]}}\n' "$(cat "${R}/agents" 2>/dev/null)" ;;
  "agent read") cat "${R}/pane.txt" 2>/dev/null ;;
  *) echo '{"result":{}}' ;;
esac
STUB
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr"

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
story() { { echo ---; printf '%s\n' "${@:2}"; echo ---; echo; echo "# $1"; } > "${B}/$1.md"; }
ev() { printf '%s\t%s\t%s\t-\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "${3:-ok}" >> "${P}/.swarm/events.tsv"; }

# pr_json <mergeable> — gh pr list's one PR: story s's, opened two hours ago, its one check passed.
pr_json() {
  printf '[{"url":"%s","headRefName":"story/s","headRefOid":"%s","mergeable":"%s","createdAt":"%s","statusCheckRollup":[{"__typename":"CheckRun","status":"COMPLETED","conclusion":"SUCCESS"}]}]\n' \
    "${URL}" "${H}" "$1" "$(perl -MPOSIX -e 'print strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time - 7200))')" > "${ROOT}/prs.json"
}

# board <kind> — a board on which lead_queue prints a line of <kind>, and nothing else.
board() {
  rm -rf "${B:?}"/*.md "${P}/.swarm/events.tsv" "${P}/.swarm/lead" "${P}/.swarm/briefs" "${ROOT}/proj-wt" \
    "${ROOT}/agents" "${ROOT}/pane.txt" "${P}/.swarm/state/tab" "${ROOT}/prs.json" "${P}/.swarm/reviews"
  mkdir -p "${P}/.swarm/lead"; : > "${P}/.swarm/lead/seen"
  echo "merge = human" > "${P}/.claude/swarm/config"
  case "$1" in
    held) story s "kind: lead" "status: ready" "escalated_from: code" "held_for: paused" ;;
    escalated) story s "kind: lead" "status: ready" "escalated_from: code" ;;
    merge) story s "kind: code" "status: review" "prs: ${URL}" ;;
    kept) story s "kind: code" "status: review" "prs: ${URL}" "kept: 2026-10-25 close stalled (not reviewed)" ;;
    no-agent) story s "kind: code" "status: ready"; ev story s; mkdir -p "${ROOT}/proj-wt/s"; ev close s ;;
    # A review agent whose start failed after its brief, its builder at work in pane w:p1.
    no-review) story s "kind: code" "status: ready"; ev story s; mkdir -p "${P}/.swarm/briefs"
               echo "Review ${URL}, the PR of story s, at its head ${H}, in this worktree." > "${P}/.swarm/briefs/review-s.md"
               ev review-agent s "review-agent: review-s did not start"; echo "w:p1 s" > "${P}/.swarm/state/tab"
               echo '{"name":"s","agent_status":"working","pane_id":"w:p1"}' > "${ROOT}/agents" ;;
    # A failed step-up's marker, its pid (above every system's limit) gone.
    "step-up failed") story s "kind: code" "status: ready"; ev story s; mkdir -p "${ROOT}/proj-wt/s" "${P}/.swarm/briefs"
                      printf 'stalled opus fable code\npid 999999999\n' > "${P}/.swarm/briefs/s.step-up"; ev step-up:failed s "ok (start failed)" ;;
    # A brief the resend did not send: its marker, and its builder idle in pane w:p1 with the paste in its box.
    "unsent brief") story s "kind: code" "status: ready"; mkdir -p "${P}/.swarm/briefs"
                    printf 's w:p1 builder\npid 999999999\n' > "${P}/.swarm/briefs/s.unsent"; echo "w:p1 s" > "${P}/.swarm/state/tab"
                    echo '{"name":"s","agent_status":"idle","pane_id":"w:p1"}' > "${ROOT}/agents"
                    printf '────────────────\n❯ [Pasted text #1 +40 lines]\n────────────────\n' > "${ROOT}/pane.txt" ;;
    # A blocked story whose dependency, still to build, shares no file in touches with it.
    idle) story s "kind: code" "status: blocked" "depends_on: [d]" "touches: [a.sh]"
          story d "kind: code" "status: ready" "touches: [b.sh]" ;;
    # An agent blocked on a permission prompt in pane w:p1.
    prompt) story s "kind: code" "status: ready"; echo "w:p1 s" > "${P}/.swarm/state/tab"
            echo '{"name":"s","agent_status":"blocked","pane_id":"w:p1"}' > "${ROOT}/agents"
            cp "${HOME_DIR}/tests/fixtures/panes/prompt.txt" "${ROOT}/pane.txt" ;;
    # A ready story's PR, reviewed on its green head two hours ago and still open.
    unmerged) story s "kind: code" "status: ready"; mkdir -p "${P}/.swarm/reviews"
              printf 'head: %s\n\n## Findings\n\nnone\n' "${H}" > "${P}/.swarm/reviews/s.md"
              perl -e 'my $t = time - 7200; utime $t, $t, shift' "${P}/.swarm/reviews/s.md"
              pr_json MERGEABLE ;;
    conflict) story s "kind: code" "status: ready"; pr_json CONFLICTING ;;
    *) echo "FAIL no board for kind ${1}: add one"; fails=$((fails + 1)) ;;
  esac
}

# The handler: the paragraph of commands/swarm.md that starts wait --lead beside the conductor's wait.
handler="$(awk '/also run `swarm.sh wait --lead`/ { s = 1 } s && /^[[:space:]]*$/ { exit } s' "${HOME_DIR}/commands/swarm.md")"
check "the wait --lead handler is found in commands/swarm.md" test -n "${handler}"

while IFS= read -r kind; do
  board "${kind}"
  out="$(cd "${P}" && env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" HERDR_ENV=1 bash "${SWARM}" wait --lead 0 2>&1)" || true
  check "wait --lead prints a ${kind}: line" grep -q "^${kind}: s" <<< "${out}"
  while IFS= read -r line; do
    [[ -n "${line}" && "|${KINDS}|" != *"|${line%%: *}|"* ]] || continue
    echo "FAIL wait --lead printed '${line%%: *}', a kind not on KINDS: add it, and an arm for it"; fails=$((fails + 1))
  done <<< "${out}"
  if [[ "|${GAPS}|" == *"|${kind}|"* ]]; then
    echo "gap  ${kind}: has no arm yet (GAPS)"
  else
    # shellcheck disable=SC2016 # the backtick is the Markdown's own
    check "the wait --lead handler has an arm for ${kind}: lines" grep -qF '`'"${kind}"': ' <<< "${handler}"
  fi
done < <(tr '|' '\n' <<< "${KINDS}")

# The plan-hld arm reads grants from origin's copy (the plan worktree), after the step that makes it.
# shellcheck disable=SC2016 # the backticks are the Markdown's own
planarm="$(tr '\n' ' ' < "${HOME_DIR}/commands/swarm.md" | tr -s ' ' | sed -n 's/.*\(- `plan-hld <hld>`: follow\)/\1/p' | cut -c1-1200)"
# shellcheck disable=SC2016 # the backticks are the Markdown's own
check "the plan-hld arm reads grants from origin's copy, after /plan-hld makes its worktree" grep -qE 'Read the grants from origin.s copy of the HLD, never the main checkout.s.* once `/plan-hld` has made its plan worktree `<wt>` .* run `SWARM_PROJECT=<wt> swarm\.sh grants <hld>`' <<< "${planarm}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
