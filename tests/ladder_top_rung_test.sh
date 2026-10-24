#!/usr/bin/env bash
# ladder_top_rung_test.sh — with escalate_ladder = sonnet,opus,fable, a builder on the top rung (fable)
# that has had one findings tell since its step-up is not sent the next: the story is held for the lead
# (held_for: top-rung, kind: lead) with the findings in its block and kept in a file reset leaves, its
# builder and PR kept, and next names it; a retried tell is refused, and the kept file sent as a later
# round holds it again. A tell from before the step-up does not count; a build that started on fable
# counts from its start, and so does one above a ladder that tops out at opus. A later round is named
# as it is. Where a step-up could not run (a story in review, a merged or auto-merging PR, another
# step-up running) nothing is held; a hold that fails after its block is written sends nothing. On opus
# the findings tells go on as before: the second is sent and the third steps it up. herdr, gh and claude (tests/claude_stub.sh) are stubs on PATH.
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
# tab closes; agent wait returns at once. With quick, a started session's first turn has ended by the
# time anyone reads it: the brief writes an assistant entry in its log, a second passes, and Claude
# Code lists it idle; a /goal writes its goal_status set entry.
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${STUB_BIN}/herdr"
cat >> "${STUB_BIN}/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
next() { n=$(($(cat "$H/n" 2>/dev/null || echo 10) + 1)); echo "$n" > "$H/n"; }
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;   # start_agent's require_herdr_version
  "tab create")   next; echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "pane split")   next; echo "{\"result\":{\"pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "tab list")     echo '{"result":{"tabs":[{"tab_id":"w:t1","label":"s1"}]}}' ;;
  "tab close")    : > "$H/agents" ;;
  "agent start")  [ -e "$H/startfail" ] && { echo "start refused" >&2; exit 1; }
                  echo "$*" | sed -n 's/.*--session-id \([^ ]*\).*/\1/p' > "$H/sid"
                  echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')" >> "$H/agents" ;;
  "agent prompt") if [ -e "$H/quick" ] && [ -s "$H/sid" ]; then
                    sid=$(cat "$H/sid"); mkdir -p "$CLAUDE_PROJECTS_DIR/p"
                    python3 -c 'import datetime, json, sys
now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
t = sys.argv[1]
if t.startswith("/goal "):
    print(json.dumps({"type": "attachment", "timestamp": now, "attachment": {"type": "goal_status", "met": False, "sentinel": True, "condition": t[6:]}}))
else:
    print(json.dumps({"type": "assistant", "timestamp": now, "message": {"model": "m", "content": []}}))' "$4" >> "$CLAUDE_PROJECTS_DIR/p/$sid.jsonl"
                    case "$4" in "/goal "*) ;; *) sleep 1; echo "[{\"sessionId\":\"$sid\",\"status\":\"idle\"}]" > "$CLAUDE_STUB_AGENTS" ;; esac
                  fi
                  echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent list")   awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                    { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                    END { print "]}}" }' "$H/agents" ;;
esac
EOF
# gh: story/s1 has no PR for close (prs.json), and one open PR whose head is the sha in head for
# watch. A head's one check run failed unless runs-<sha> says otherwise, and it has a commit status
# only when status-<sha> names its state.
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${STUB_BIN}/gh"
cat >> "${STUB_BIN}/gh" <<'EOF'
case "$*" in
  "pr list"*"--state all"*) cat "$H/prs.json" ;;
  "api --paginate repos/"*"/pulls?"*) echo "5 $(cat "$H/head") story/s1 $(($(date +%s) - 10))" ;;
  "api repos/"*"/pulls/5 "*) echo MERGEABLE ;;
  "repo view"*other*) echo o/other ;;
  "repo view"*) echo o/proj ;;
  "api --paginate"*check-runs*) sha=$(echo "$*" | sed 's|.*/commits/\([^/]*\)/.*|\1|'); c=$(cat "$H/runs-$sha" 2>/dev/null || echo failure)
    echo "{\"total_count\":1,\"check_runs\":[{\"name\":\"test\",\"status\":\"completed\",\"conclusion\":\"$c\",\"html_url\":\"https://ci/1\"}]}" ;;
  "api --paginate"*status*) sha=$(echo "$*" | sed 's|.*/commits/\([^/]*\)/.*|\1|')
    if [ -e "$H/status-$sha" ]; then echo "{\"total_count\":1,\"statuses\":[{\"context\":\"ext\",\"state\":\"$(cat "$H/status-$sha")\"}]}"
    else echo '{"total_count":0,"statuses":[]}'; fi ;;
  "api"*check-runs*) echo "1 0" ;;
esac
EOF
chmod +x "${STUB_BIN}/herdr" "${STUB_BIN}/gh"

P="${ROOT}/proj"; WT="${ROOT}/proj-wt/s1"
# fresh <model> <prior tells> — a project whose story s1 was stepped up to <model> at 10:00 (an
# escalate line), its builder idle in pane w:1, with a findings tell at 09:30, before the step-up, and
# <prior tells> since; story/s1 has one open PR.
fresh() {
  local i
  rm -rf "${ROOT}/origin.git" "${P}" "${ROOT}/proj-wt" "${ROOT}/herdr.log" "${ROOT}/sid"; : > "${ROOT}/run.log"
  "${GIT[@]}" init -q --bare "${ROOT}/origin.git"
  "${GIT[@]}" clone -q "${ROOT}/origin.git" "${P}" 2>/dev/null
  mkdir -p "${P}/docs/stories" "${P}/.claude/swarm" "${P}/.swarm/state"
  printf '%s\n' --- "status: ready" "kind: code" --- "" "# s1" "" "**Done when:**" "- it holds" > "${P}/docs/stories/s1.md"
  "${GIT[@]}" -C "${P}" add -A && "${GIT[@]}" -C "${P}" commit -qm init && "${GIT[@]}" -C "${P}" push -q origin main
  "${GIT[@]}" -C "${P}" worktree add -q -b story/s1 "${WT}" origin/main
  echo work > "${WT}/work.txt"; "${GIT[@]}" -C "${WT}" add work.txt; "${GIT[@]}" -C "${WT}" commit -qm work
  printf '2026-10-01\tcode-sonnet\ts1\tclaude\tsonnet\thigh\tsess-0\n2026-10-18\tcode\ts1\tclaude\t%s\thigh\tsess-1\n' "$1" > "${P}/.swarm/agents.tsv"
  printf '2026-10-18T09:00:00Z\tstory\ts1\tw:1\tok\n2026-10-18T09:30:00Z\ttell:findings\ts1\tw:1\tok\n2026-10-18T10:00:00Z\tescalate\ts1\tw:1\tok (findings-3: sonnet -> %s)\n' "$1" > "${P}/.swarm/events.tsv"
  for ((i = 1; i <= $2; i++)); do printf '2026-10-18T10:0%s:00Z\ttell:findings\ts1\tw:1\tok\n' "${i}" >> "${P}/.swarm/events.tsv"; done
  echo "w:1 s1" > "${P}/.swarm/state/s1"; echo "s1 w:1" > "${ROOT}/agents"
  echo '[{"sessionId":"sess-1","status":"idle"}]' > "${CLAUDE_STUB_AGENTS}"
  echo "escalate_ladder = sonnet,opus,fable" > "${P}/.claude/swarm/config"
}
OPEN_PR='[{"url":"https://github.com/o/proj/pull/5","state":"OPEN"}]'
echo "add the missing guard" > "${ROOT}/f.md"
run() { (cd "${P}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${STUB_BIN}:${PATH}" bash "${SWARM}" "$@" 2>&1) | tee -a "${ROOT}/run.log"; }
# fm_of <key> — s1's <key>: its board-state file's, else the story file's.
fm_of() { sed -n "s/^$1: *//p" "${P}/.swarm/board-state/stories/s1" "${P}/docs/stories/s1.md" 2>/dev/null | head -1 || true; }
kind() { fm_of kind; }
# held — the held lines' outcomes; escalated — the escalated lines'; stepped — step-ups after 10:00.
held() { awk -F'\t' '$2 == "held" { print $5 }' "${P}/.swarm/events.tsv" | paste -sd, -; }
escalated() { awk -F'\t' '$2 == "escalated" { print $5 }' "${P}/.swarm/events.tsv" | paste -sd, -; }
stepped() { awk -F'\t' '$2 == "escalate" && $1 > "2026-10-18T10:00:00Z" { print $5 }' "${P}/.swarm/events.tsv" | paste -sd, -; }
told() { grep -q 'told s1' <<< "$1" && echo yes || echo no; }
block="${P}/.swarm/escalated/s1"; kept="${P}/.swarm/briefs/s1.held-findings.md"
HELD="ok (top-rung: findings round 2 on fable)"

echo "${OPEN_PR}" > "${ROOT}/prs.json"
fresh fable 1; out="$(run tell s1 findings "${ROOT}/f.md")" || true
check "fable: the 2nd findings tell since the step-up is not sent" "yes|no" \
  "$(grep -q 'was not told: these were findings round 2 on or above the ladder' <<< "${out}" && echo yes)|$(told "${out}")"
check "fable: the story is escalated to the lead, logged, with no step-up" "lead|code|top-rung|${HELD}||" \
  "$(kind)|$(fm_of escalated_from)|$(fm_of held_for)|$(held)|$(escalated)|$(stepped)"
check "fable: its block holds the findings and the PR" "yes|yes|yes|yes" \
  "$(grep -qx 'add the missing guard' "${block}" && echo yes)|$(grep -qx -- '- https://github.com/o/proj/pull/5' "${block}" && echo yes)|$(grep -qF "swarm.sh tell s1 findings ${kept}" "${block}" && echo yes)|$(cmp -s "${ROOT}/f.md" "${kept}" && echo yes)"
check "fable: its block says to close the builder, PR and worktree before a drop" "yes|yes|yes" \
  "$(grep -qF 'swarm.sh close s1' "${block}" && echo yes)|$(grep -qF 'gh pr close https://github.com/o/proj/pull/5 --delete-branch' "${block}" && echo yes)|$(grep -qF "worktree remove ${WT}" "${block}" && echo yes)"
check "fable: the builder is kept" "s1 w:1" "$(cat "${ROOT}/agents")"
check "fable: next names it escalated" "yes|yes" "$(run next > "${ROOT}/next.out"; grep -qx 'escalated s1' "${ROOT}/next.out" && echo yes)|$(grep -q 'held (top-rung)' "${ROOT}/next.out" && echo yes)"
out="$(run tell s1 findings "${ROOT}/f.md")" || true
check "fable: a retried tell is refused, and the block stays" "yes|${HELD}|code|yes" \
  "$(grep -q 'held for the lead already' <<< "${out}" && echo yes)|$(held)|$(fm_of escalated_from)|$(grep -qx 'add the missing guard' "${block}" && echo yes)"
# Held, then moved to review by hand: escalated_from: still refuses the retry, whatever the status.
cp "${P}/.swarm/board-state/stories/s1" "${ROOT}/state.bak"
sed -i.x '/^status:/d' "${P}/.swarm/board-state/stories/s1"; echo "status: review" >> "${P}/.swarm/board-state/stories/s1"
out="$(run tell s1 findings "${ROOT}/f.md")" || true
check "fable: a retried tell to a held story in review is refused, and no second block is written" "review|yes|${HELD}|code" \
  "$(fm_of status)|$(grep -q 'held for the lead already' <<< "${out}" && echo yes)|$(held)|$(fm_of escalated_from)"
cp "${ROOT}/state.bak" "${P}/.swarm/board-state/stories/s1"
out="$(run reset s1 rescoped)" || true
check "fable: reset puts its kind back" "code|reset:held|yes" \
  "$(kind)|$(awk -F'\t' '$2 ~ /^reset/ { print $2 }' "${P}/.swarm/events.tsv")|$([[ -f "${kept}" ]] && echo yes)"
out="$(run tell s1 findings "${kept}")" || true
check "fable: after the lead's reset, the kept builder's next findings tell is sent" "yes|${HELD}" "$(told "${out}")|$(held)"
out="$(run tell s1 findings "${kept}")" || true
check "fable: the kept file sent as the next round holds it again, and stays as it was" "no|${HELD},${HELD}|yes|yes" \
  "$(told "${out}")|$(held)|$(grep -qx 'add the missing guard' "${kept}" && echo yes)|$(grep -qx 'add the missing guard' "${block}" && echo yes)"

fresh fable 0; out="$(run tell s1 findings "${ROOT}/f.md")" || true
check "fable: a tell from before the step-up does not count, so the first since is sent" "yes|" "$(told "${out}")|$(held)"

# A build that started on fable (no step-up) counts its top-rung rounds from its start.
fresh fable 0; sed -i.x '/\tescalate\t/d' "${P}/.swarm/events.tsv"; out="$(run tell s1 findings "${ROOT}/f.md")" || true
check "fable: a build that started there counts from its start" "no|${HELD}" "$(told "${out}")|$(held)"

# Where a step-up could not run, nothing is held and the findings go as usual.
fresh fable 1; mkdir -p "${P}/.swarm/board-state/stories"; printf '%s\n' --- "status: review" "kind: code" --- > "${P}/.swarm/board-state/stories/s1"
out="$(run tell s1 findings "${ROOT}/f.md")" || true
check "fable: a story in review is not held, and is told" "yes|code||yes" \
  "$(told "${out}")|$(kind)|$(held)|$(grep -q 'was not held for the lead' <<< "${out}" && echo yes)"
echo '[{"url":"https://github.com/o/proj/pull/5","state":"MERGED"}]' > "${ROOT}/prs.json"
fresh fable 1; out="$(run tell s1 findings "${ROOT}/f.md")" || true
check "fable: a PR that merged holds nothing, and is told" "yes|code|" "$(told "${out}")|$(kind)|$(held)"
echo '[{"url":"https://github.com/o/proj/pull/5","state":"OPEN","autoMergeRequest":{"enabledAt":"x"}}]' > "${ROOT}/prs.json"
fresh fable 1; out="$(run tell s1 findings "${ROOT}/f.md")" || true
check "fable: a PR that is set to auto-merge holds nothing, and is told" "yes|code|" "$(told "${out}")|$(kind)|$(held)"
echo "${OPEN_PR}" > "${ROOT}/prs.json"

# Another step-up or hold of it running: the tell is refused, and nothing is held.
fresh fable 1; mkdir -p "${P}/.swarm/locks/step-up-s1"; echo "$$" > "${P}/.swarm/locks/step-up-s1/pid"
out="$(run tell s1 findings "${ROOT}/f.md")" || true
check "fable: a held step-up lock refuses the tell, holding nothing" "yes|no|code|" \
  "$(grep -q 'a step-up or hold of it is running' <<< "${out}" && echo yes)|$(told "${out}")|$(kind)|$(held)"

# A hold that fails after its block is written (the board state cannot be written): the tell fails,
# and the findings are not sent.
fresh fable 1; mkdir -p "${P}/.swarm/board-state/stories"; chmod a-w "${P}/.swarm/board-state/stories"
out="$(run tell s1 findings "${ROOT}/f.md")" || true
chmod u+w "${P}/.swarm/board-state/stories"
check "fable: a hold that fails after its block is written fails the tell, sending nothing" "yes|no|yes" \
  "$(grep -q 'its top-rung hold failed partway' <<< "${out}" && echo yes)|$(told "${out}")|$([[ -f "${block}" ]] && echo yes)"

fresh fable 2; out="$(run tell s1 findings "${ROOT}/f.md")" || true
check "fable: a later round holds it, naming that round" "yes|no|ok (top-rung: findings round 3 on fable)|yes" \
  "$(grep -q 'these were findings round 3 on or above' <<< "${out}" && echo yes)|$(told "${out}")|$(held)|$(grep -q 'drew review findings round 3 there' "${block}" && echo yes)"

fresh fable 1; echo "top_rung_rounds = 3" >> "${P}/.claude/swarm/config"; out="$(run tell s1 findings "${ROOT}/f.md")" || true
check "fable, top_rung_rounds = 3: the 2nd findings tell since the step-up is sent" "yes|" "$(told "${out}")|$(held)"
fresh fable 2; echo "top_rung_rounds = 3" >> "${P}/.claude/swarm/config"; out="$(run tell s1 findings "${ROOT}/f.md")" || true
check "fable, top_rung_rounds = 3: the 3rd is held for the lead" "no|lead|ok (top-rung: findings round 3 on fable)" "$(told "${out}")|$(kind)|$(held)"

# A fable build above a ladder that tops out at opus is on no rung with one above it: held as on the top.
fresh fable 0; sed -i.x '/\tescalate\t/d' "${P}/.swarm/events.tsv"; echo "escalate_ladder = sonnet,opus" > "${P}/.claude/swarm/config"
out="$(run tell s1 findings "${ROOT}/f.md")" || true
check "fable above a sonnet,opus ladder: its 2nd findings round holds it" "no|${HELD}" "$(told "${out}")|$(held)"

fresh opus 1; out="$(run tell s1 findings "${ROOT}/f.md")" || true
check "opus: the 2nd findings tell since the step-up is sent, as today" "yes|code|" "$(told "${out}")|$(kind)|$(held)"
fresh opus 2; out="$(run tell s1 findings "${ROOT}/f.md")" || true
check "opus: the 3rd steps it up to fable, as today" "ok (findings-3: opus -> fable)|" "$(stepped)|$(held)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
