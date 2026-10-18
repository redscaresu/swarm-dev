#!/usr/bin/env bash
# escalate_ladder_test.sh — swarm.sh step-up <slug> <trigger>: with escalate_ladder set, it closes a
# story's builder without counting an attempt and starts the ladder's next model in the same worktree
# and branch, with a handover brief, logging one escalate line; at the top rung or with the ladder
# empty it refuses. Then outcomes and dash read a sonnet -> opus -> fable chain of step-ups: only the
# step to fable pairs with the Fable build and counts as an escalation. herdr, gh and claude
# (tests/claude_stub.sh) are stubs on PATH: herdr records each call, gh lists one open PR with one
# failing check.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TZ=UTC
export CLAUDE_STUB_AGENTS="${ROOT}/claude.json"; echo '[]' > "${CLAUDE_STUB_AGENTS}"
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}" "${ROOT}/projects"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
GIT=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main -c commit.gpgsign=false)
fails=0
check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }

# herdr: logs every call; panes are w:<n>; agents lists "<name> <pane>" lines, all idle, until
# the tab closes.
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${STUB_BIN}/herdr"
cat >> "${STUB_BIN}/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
next() { n=$(($(cat "$H/n" 2>/dev/null || echo 10) + 1)); echo "$n" > "$H/n"; }
case "$1 $2" in
  "tab create")   next; echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "pane split")   next; echo "{\"result\":{\"pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "tab list")     echo '{"result":{"tabs":[{"tab_id":"w:t1","label":"s1"}]}}' ;;
  "tab close")    : > "$H/agents" ;;   # the one tab: its agent goes with it
  "agent start")  echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')" >> "$H/agents" ;;
  "agent prompt") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent list")   awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                    { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                    END { print "]}}" }' "$H/agents" ;;
esac
EOF
cat > "${STUB_BIN}/gh" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "pr list")   echo "https://github.com/o/proj/pull/5" ;;
  "pr checks") echo "- test: https://ci/run/9" ;;
esac
EOF
chmod +x "${STUB_BIN}/herdr" "${STUB_BIN}/gh"

# A project whose board is in its repo, with story s1 started on sonnet: its worktree holds a
# commit, its builder is open in pane w:1, and a review agent left findings.
P="${ROOT}/proj"; WT="${ROOT}/proj-wt/s1"
"${GIT[@]}" init -q --bare "${ROOT}/origin.git"
"${GIT[@]}" clone -q "${ROOT}/origin.git" "${P}" 2>/dev/null
mkdir -p "${P}/docs/stories" "${P}/.claude/swarm" "${P}/.swarm/state" "${P}/.swarm/reviews"
printf '%s\n' --- "status: ready" "kind: code" --- "" "# s1" "" "**Done when:**" "- it holds" > "${P}/docs/stories/s1.md"
"${GIT[@]}" -C "${P}" add -A && "${GIT[@]}" -C "${P}" commit -qm init && "${GIT[@]}" -C "${P}" push -q origin main
"${GIT[@]}" -C "${P}" worktree add -q -b story/s1 "${WT}" origin/main
# zz-big.txt makes the diff far longer than the brief keeps (and than a pipe holds), after work.txt.
echo "SONNET-WORK" > "${WT}/work.txt"; awk 'BEGIN { for (i = 0; i < 5000; i++) print "a line of the long diff that the handover brief cuts off" }' > "${WT}/zz-big.txt"
"${GIT[@]}" -C "${WT}" add work.txt zz-big.txt && "${GIT[@]}" -C "${WT}" commit -qm work
printf '2026-10-01\tcode-sonnet\ts1\tclaude\tsonnet\thigh\tsess-1\n' > "${P}/.swarm/agents.tsv"
echo "w:1 s1" > "${P}/.swarm/state/s1"; echo "s1 w:1" > "${ROOT}/agents"
echo "REVIEW-FINDING: the guard is missing" > "${P}/.swarm/reviews/s1.md"
echo "escalate_ladder = sonnet,opus,fable" > "${P}/.claude/swarm/config"
run() { (cd "${P}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${STUB_BIN}:${PATH}" bash "${SWARM}" "$@" 2>&1); }
escalates() { grep -c $'\tescalate\t' "${P}/.swarm/events.tsv" 2>/dev/null || true; }

out="$(run step-up s1 findings-3)" || true
check "step-up on a sonnet build closes its pane and starts opus as code in the same worktree" \
  "yes|yes|code opus" \
  "$(grep -qx 'tab close w:t1' "${ROOT}/herdr.log" && echo yes)|$(grep -q -- "--cwd ${WT} " "${ROOT}/herdr.log" && echo yes)|$(tail -1 "${P}/.swarm/agents.tsv" | cut -f2,5 | tr '\t' ' ')"
check "the worktree keeps its branch and commit, and no attempt is counted" "story/s1|SONNET-WORK|" \
  "$(git -C "${WT}" rev-parse --abbrev-ref HEAD)|$(cat "${WT}/work.txt")|$(sed -n 's/^attempts: *//p' "${P}/docs/stories/s1.md")"
brief="$(cat "${P}/.swarm/briefs/s1.md")"
check "the handover brief holds the story, the diff (cut to 400 lines), the findings and the failing check" "yes|yes|yes|yes|yes" \
  "$(has "Implement docs/stories/s1.md" "${brief}")|$(has "+SONNET-WORK" "${brief}")|$([[ $(grep -c "^+a line of the long diff" <<< "${brief}") -lt 400 ]] && echo yes)|$(has "REVIEW-FINDING: the guard is missing" "${brief}")|$(has "- test: https://ci/run/9" "${brief}")"
check "it pastes the story as the board holds it, which the last builder may have deleted" "yes" \
  "$(grep -A3 -x '### The story, as the board holds it' <<< "${brief}" | tail -2 | paste -sd' ' - | grep -qx -- '--- status: ready' && echo yes)"
# shellcheck disable=SC2016 # the backticks are the brief's, not a command
check "it names the PR body's models line, with every model in order" "yes" "$(has 'models line: `Models: sonnet, opus`' "${brief}")"
check "it logs one escalate line naming the trigger and both models" "1|ok (findings-3: sonnet -> opus)" \
  "$(escalates)|$(awk -F'\t' '$2 == "escalate" { print $5 }' "${P}/.swarm/events.tsv")"
check "and says so" "yes" "$(has "stepped up: s1 from sonnet to opus (code)" "${out}")"

# The top rung: a build on fable has no next model. Nothing closes or starts.
printf '2026-10-01\tescalate\ts1\tclaude\tfable\txhigh\tsess-3\n' >> "${P}/.swarm/agents.tsv"
starts="$(grep -c '^agent start' "${ROOT}/herdr.log")"
out="$(run step-up s1 stalled)" && rc=0 || rc=$?
check "at the top rung step-up refuses, closing and starting nothing" "1|yes|${starts}|1" \
  "${rc}|$(has "escalate_ladder's top rung" "${out}")|$(grep -c '^agent start' "${ROOT}/herdr.log")|$(escalates)"
: > "${P}/.claude/swarm/config"
out="$(run step-up s1 stalled)" && rc=0 || rc=$?
check "with escalate_ladder empty step-up refuses" "1|yes|${starts}" \
  "${rc}|$(has "escalate_ladder is empty (off)" "${out}")|$(grep -c '^agent start' "${ROOT}/herdr.log")"
out="$(run step-up s1 bored)" && rc=0 || rc=$?
check "an unknown trigger is refused" "1|yes" "${rc}|$(has "the trigger must be one of findings-3, ci-red-2, stalled, no-pr" "${out}")"

# --- A sonnet -> opus -> fable chain of step-ups on s2, today. outcomes' escalate column for the
# Fable build is the opus -> fable step, never the sonnet -> opus one; dash counts one escalation.
Q="${ROOT}/q"; mkdir -p "${Q}/.swarm" "${Q}/docs/stories" "${ROOT}/projects/q"; : > "${Q}/docs/stories/README.md"; git -C "${Q}" init -q
NOW="$(python3 -c 'import datetime; print(int(datetime.datetime(2026, 10, 10, 12).timestamp()))')"
for s in 1:09:00 2:10:00 3:11:00; do
  printf '{"type":"user","cwd":"%s/q-wt/s2","timestamp":"2026-10-10T%s:01Z"}\n' "${ROOT}" "${s#*:}" > "${ROOT}/projects/q/q${s%%:*}.jsonl"
done
printf '%s\n' $'2026-10-10\tcode-sonnet\ts2\tclaude\tsonnet\thigh\tq1' $'2026-10-10\tcode\ts2\tclaude\topus\thigh\tq2' \
  $'2026-10-10\tescalate\ts2\tclaude\tfable\txhigh\tq3' > "${Q}/.swarm/agents.tsv"
printf '%s\n' $'2026-10-10T10:00:00Z\tescalate\ts2\tw:1\tok (no-pr: sonnet -> opus)' \
  $'2026-10-10T11:00:00Z\tescalate\ts2\tw:1\tok (findings-3: opus -> fable)' > "${Q}/.swarm/events.tsv"
qrun() { (cd "${Q}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${STUB_BIN}:${PATH}" bash "${SWARM}" "$@" 2>&1); }
check "outcomes' escalate column for the Fable build has the opus -> fable step's time" \
  "$(printf '%s\n' "code-sonnet	" "code	" "escalate	2026-10-10T11:00:00Z")" "$(qrun outcomes | tail -n +2 | cut -f5,24)"
check "dash counts one escalation today" "yes" \
  "$(has "1 escalation today" "$(cd "${Q}" && env -u SWARM_PROJECT HERDR_ENV=1 SWARM_DASH_NOW="${NOW}" COLUMNS=100 LINES=80 PATH="${STUB_BIN}:${PATH}" bash "${SWARM}" dash 2>&1)")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
