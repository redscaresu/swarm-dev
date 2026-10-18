#!/usr/bin/env bash
# escalate_triggers_test.sh — with escalate_ladder set, swarm.sh runs step-up itself on each of the four
# triggers: a close of a builder with no PR (no-pr), a wait --stall that finds it stalled (stalled), a
# third findings tell (findings-3), and checks finishing red on a second head of its PR (ci-red-2).
# With the ladder empty none does. conduct_brief names the step-ups only with the ladder on. herdr, gh
# and claude (tests/claude_stub.sh) are stubs on PATH; gh's answers come from files under the root.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TZ=UTC
export CLAUDE_STUB_AGENTS="${ROOT}/claude.json"
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}" "${ROOT}/projects"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
GIT=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main -c commit.gpgsign=false)
fails=0
check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# herdr: logs every call; panes are w:<n>; agents lists "<name> <pane>" lines, all idle, until the
# tab closes; agent wait returns at once.
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${STUB_BIN}/herdr"
cat >> "${STUB_BIN}/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
next() { n=$(($(cat "$H/n" 2>/dev/null || echo 10) + 1)); echo "$n" > "$H/n"; }
case "$1 $2" in
  "tab create")   next; echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "pane split")   next; echo "{\"result\":{\"pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "tab list")     echo '{"result":{"tabs":[{"tab_id":"w:t1","label":"s1"}]}}' ;;
  "tab close")    : > "$H/agents" ;;
  "agent start")  echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')" >> "$H/agents" ;;
  "agent prompt") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent list")   awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                    { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                    END { print "]}}" }' "$H/agents" ;;
esac
EOF
# gh: story/s1 has no PR for close (prs.json), one open PR whose head is the sha in head for watch,
# and that head's one check run failed.
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${STUB_BIN}/gh"
cat >> "${STUB_BIN}/gh" <<'EOF'
case "$*" in
  "pr list"*"--state all"*) cat "$H/prs.json" ;;
  "pr list"*"--state open --json number"*) echo "5 $(cat "$H/head") story/s1 MERGEABLE 10" ;;
  "repo view"*) echo o/proj ;;
  "api --paginate"*check-runs*) echo '{"total_count":1,"check_runs":[{"name":"test","status":"completed","conclusion":"failure","html_url":"https://ci/1"}]}' ;;
  "api --paginate"*status*) echo '{"total_count":0,"statuses":[]}' ;;
  "api"*check-runs*) echo "1 0" ;;
esac
EOF
chmod +x "${STUB_BIN}/herdr" "${STUB_BIN}/gh"

P="${ROOT}/proj"; WT="${ROOT}/proj-wt/s1"
# fresh <ladder> <session state> — a new project whose story s1 is built on sonnet in its worktree
# (one commit, 2 hours old), its builder open in pane w:1, and escalate_ladder = <ladder>.
fresh() {
  rm -rf "${ROOT}/origin.git" "${P}" "${ROOT}/proj-wt" "${ROOT}/herdr.log"
  "${GIT[@]}" init -q --bare "${ROOT}/origin.git"
  "${GIT[@]}" clone -q "${ROOT}/origin.git" "${P}" 2>/dev/null
  mkdir -p "${P}/docs/stories" "${P}/.claude/swarm" "${P}/.swarm/state"
  printf '%s\n' --- "status: ready" "kind: code" --- "" "# s1" "" "**Done when:**" "- it holds" > "${P}/docs/stories/s1.md"
  "${GIT[@]}" -C "${P}" add -A && "${GIT[@]}" -C "${P}" commit -qm init && "${GIT[@]}" -C "${P}" push -q origin main
  "${GIT[@]}" -C "${P}" worktree add -q -b story/s1 "${WT}" origin/main
  echo work > "${WT}/work.txt"; "${GIT[@]}" -C "${WT}" add work.txt
  GIT_COMMITTER_DATE="@${OLD}" "${GIT[@]}" -C "${WT}" commit -qm work
  printf '2026-10-01\tcode-sonnet\ts1\tclaude\tsonnet\thigh\tsess-1\n' > "${P}/.swarm/agents.tsv"
  : > "${P}/.swarm/events.tsv"
  echo "w:1 s1" > "${P}/.swarm/state/s1"; echo "s1 w:1" > "${ROOT}/agents"
  echo "[{\"sessionId\":\"sess-1\",\"status\":\"$2\"}]" > "${CLAUDE_STUB_AGENTS}"
  echo "escalate_ladder = $1" > "${P}/.claude/swarm/config"
}
OLD=$(($(date +%s) - 7200))
echo '[]' > "${ROOT}/prs.json"
run() { (cd "${P}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w SWARM_STALL_POLL_MS=1000 PATH="${STUB_BIN}:${PATH}" bash "${SWARM}" "$@" 2>&1); }
# stepped — the escalate lines' results, and any step-up that was refused, comma-separated.
stepped() { awk -F'\t' '$2 == "escalate" { print $5 } $2 == "step-up" && $5 != "ok" { print "refused: " $5 }' "${P}/.swarm/events.tsv" | paste -sd, -; }
findings_tells() { printf '2026-10-18T10:0%s:00Z\ttell:findings\ts1\tw:1\tok\n' 1 2 >> "${P}/.swarm/events.tsv"; echo "fix it" > "${ROOT}/f.md"; }

for ladder in sonnet,opus,fable ""; do
  want="ok (no-pr: sonnet -> opus)"; [[ -n "${ladder}" ]] || want=""
  fresh "${ladder}" idle; run close s1 >/dev/null || true
  check "ladder '${ladder}': a close with no PR logs idle-no-pr and steps up only with the ladder on" "1|${want}" "$(grep -c 'idle-no-pr' "${P}/.swarm/events.tsv")|$(stepped)"

  want="ok (stalled: sonnet -> opus)"; [[ -n "${ladder}" ]] || want=""
  fresh "${ladder}" busy; out="$(SWARM_WAIT_STARTED="${OLD}" run wait --stall s1 3000)" || true
  check "ladder '${ladder}': a stall found by wait --stall steps up only with the ladder on" "yes|${want}" \
    "$(grep -q '^stalled:' <<< "${out}" && echo yes)|$(stepped)"

  fresh "${ladder}" idle; findings_tells; out="$(run tell s1 findings "${ROOT}/f.md")" || true
  if [[ -n "${ladder}" ]]; then
    check "ladder '${ladder}': a third findings tell steps it up instead, the findings in its brief" \
      "ok (findings-3: sonnet -> opus)|yes|yes" \
      "$(stepped)|$(grep -q 'was not told: these were its third findings' <<< "${out}" && echo yes)|$(grep -qx 'fix it' "${P}/.swarm/briefs/s1.md" && echo yes)"
  else
    check "ladder '${ladder}': a third findings tell is sent" "|yes" "$(stepped)|$(grep -q 'told s1' <<< "${out}" && echo yes)"
  fi

  want="ok (ci-red-2: sonnet -> opus)"; [[ -n "${ladder}" ]] || want=""
  fresh "${ladder}" idle
  echo aaaa1111 > "${ROOT}/head"; run watch >/dev/null || true
  first="$(stepped)"
  echo bbbb2222 > "${ROOT}/head"; run watch >/dev/null || true
  check "ladder '${ladder}': one red head steps nothing, a second steps up only with the ladder on" "|${want}" "${first}|$(stepped)"

  # The brief is written before the conductor starts, whatever the stub makes of the start.
  run conduct --backlog >/dev/null || true
  check "ladder '${ladder}': conduct_brief names the step-ups only with the ladder on" "$([[ -n "${ladder}" ]] && echo 1 || echo 0)" \
    "$(grep -c 'swarm.sh steps a build up the escalation ladder' "${P}/.swarm/briefs/conduct-backlog.md" || true)"
done

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
