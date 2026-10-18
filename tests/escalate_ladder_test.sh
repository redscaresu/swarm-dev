#!/usr/bin/env bash
# escalate_ladder_test.sh — swarm.sh step-up <slug> <trigger>: with escalate_ladder set, it closes a
# story's builder without counting an attempt and starts the ladder's next model in the same worktree
# and branch, with a handover brief, logging one escalate line; a start that fails says how to start
# the rung by hand; at the top rung or with the ladder empty it refuses. Then outcomes and dash read a
# sonnet -> opus -> fable chain of step-ups: one attempt, each replaced build closed, and only the
# step to fable paired with the Fable build and counted as an escalation. herdr, gh and claude
# (tests/claude_stub.sh) are stubs on PATH: herdr records each call (and fails agent start while
# ${ROOT}/startfail exists); gh lists an open PR on every branch, story/p1's its own, with one
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
  "agent start")  [ ! -e "$H/startfail" ] || { echo '{"error":{"code":"start_failed"}}' >&2; exit 1; }
                  echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')" >> "$H/agents" ;;
  "agent prompt") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent list")   awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                    { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                    END { print "]}}" }' "$H/agents" ;;
esac
EOF
cat > "${STUB_BIN}/gh" <<'EOF'
#!/bin/sh
case "$1 $2 $*" in
  "pr list "*story/p1*) echo "https://github.com/o/proj/pull/4" ;;
  "pr list "*)  echo "https://github.com/o/proj/pull/5" ;;
  "pr checks "*) echo "- test: https://ci/run/9" ;;
esac
EOF
chmod +x "${STUB_BIN}/herdr" "${STUB_BIN}/gh"

# A project whose board is in its repo, with story s1 stacked on p1 (whose PR is open) and started
# on sonnet: its worktree holds a commit, an uncommitted untracked file and a long untracked one, its
# builder is open in pane w:1, and a review agent left findings. main has moved on since.
P="${ROOT}/proj"; WT="${ROOT}/proj-wt/s1"
"${GIT[@]}" init -q --bare "${ROOT}/origin.git"
"${GIT[@]}" clone -q "${ROOT}/origin.git" "${P}" 2>/dev/null
mkdir -p "${P}/docs/stories" "${P}/.claude/swarm" "${P}/.swarm/state" "${P}/.swarm/reviews"
printf '%s\n' --- "status: ready" "kind: code" --- "" "# s1" "" "**Done when:**" "- it holds" > "${P}/docs/stories/s1.md"
"${GIT[@]}" -C "${P}" add -A && "${GIT[@]}" -C "${P}" commit -qm init && "${GIT[@]}" -C "${P}" push -q origin main
"${GIT[@]}" -C "${P}" worktree add -q -b story/p1 "${ROOT}/proj-wt/p1" origin/main
echo "PARENT-WORK" > "${ROOT}/proj-wt/p1/parent.txt"
"${GIT[@]}" -C "${ROOT}/proj-wt/p1" add parent.txt && "${GIT[@]}" -C "${ROOT}/proj-wt/p1" commit -qm parent && "${GIT[@]}" -C "${ROOT}/proj-wt/p1" push -q origin story/p1
"${GIT[@]}" -C "${P}" fetch -q origin && "${GIT[@]}" -C "${P}" worktree add -q --no-track -b story/s1 "${WT}" origin/story/p1
echo "SONNET-WORK" > "${WT}/work.txt"; "${GIT[@]}" -C "${WT}" add work.txt && "${GIT[@]}" -C "${WT}" commit -qm work
# zz-big.txt makes the diff far longer than the brief keeps (and than a pipe holds), after the rest.
echo "UNTRACKED-WORK" > "${WT}/new-work.txt"
awk 'BEGIN { for (i = 0; i < 5000; i++) print "a line of the long diff that the handover brief cuts off" }' > "${WT}/zz-big.txt"
echo "MAIN-ONLY" > "${P}/main.txt"; "${GIT[@]}" -C "${P}" add main.txt && "${GIT[@]}" -C "${P}" commit -qm main && "${GIT[@]}" -C "${P}" push -q origin main
printf '2026-10-01\tcode-sonnet\ts1\tclaude\tsonnet\thigh\tsess-1\n' > "${P}/.swarm/agents.tsv"
printf '%s\n' $'2026-10-01T09:00:00Z\tstacked\ts1\tw:1\tok (on p1)' $'2026-10-01T09:00:01Z\tstory\ts1\tw:1\tok' > "${P}/.swarm/events.tsv"
echo "w:1 s1" > "${P}/.swarm/state/s1"; echo "s1 w:1" > "${ROOT}/agents"
echo "REVIEW-FINDING: the guard is missing" > "${P}/.swarm/reviews/s1.md"
echo "escalate_ladder = sonnet,opus,fable" > "${P}/.claude/swarm/config"
run() { (cd "${P}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${STUB_BIN}:${PATH}" bash "${SWARM}" "$@" 2>&1); }
escalates() { grep -c $'\tescalate\t' "${P}/.swarm/events.tsv" 2>/dev/null || true; }
starts() { grep -c '^agent start' "${ROOT}/herdr.log" 2>/dev/null || true; }
# attempts — s1's attempts: as swarm.sh reads it (board.sh's get_fm: its state file, then its file).
# shellcheck source=/dev/null
attempts() { (export BOARD="${P}/docs" PROJECT_DIR="${P}"; . "${SWARM%/*}/lib/board.sh"; get_fm "${BOARD}/stories/s1.md" attempts) 2>/dev/null || true; }

out="$(run step-up s1 findings-3)" || true
check "step-up on a sonnet build closes its pane and starts opus as code in the same worktree" \
  "yes|yes|code opus" \
  "$(grep -qx 'tab close w:t1' "${ROOT}/herdr.log" && echo yes)|$(grep -q -- "--cwd ${WT} " "${ROOT}/herdr.log" && echo yes)|$(tail -1 "${P}/.swarm/agents.tsv" | cut -f2,5 | tr '\t' ' ')"
check "the worktree keeps its branch and commit, and no attempt is counted" "story/s1|SONNET-WORK|" \
  "$(git -C "${WT}" rev-parse --abbrev-ref HEAD)|$(cat "${WT}/work.txt")|$(attempts)"
brief="$(cat "${P}/.swarm/briefs/s1.md")"
check "the handover brief holds the story, the diff (cut to 400 lines), the findings and the failing check" "yes|yes|yes|yes|yes" \
  "$(has "Implement docs/stories/s1.md" "${brief}")|$(has "+SONNET-WORK" "${brief}")|$([[ $(grep -c "^+a line of the long diff" <<< "${brief}") -lt 400 ]] && echo yes)|$(has "REVIEW-FINDING: the guard is missing" "${brief}")|$(has "- test: https://ci/run/9" "${brief}")"
check "the diff holds an untracked file" "yes" "$(has "+UNTRACKED-WORK" "${brief}")"
# shellcheck disable=SC2016 # the backticks are the brief's, not a command
check "a stacked story's brief carries the Merge after note, and its diff starts at the parent's branch, so neither the parent's nor main's newer commits are in it" \
  "yes|no|no" "$(has 'with `Merge after https://github.com/o/proj/pull/4` in its body' "${brief}")|$(grep -qF PARENT-WORK <<< "${brief}" && echo yes || echo no)|$(grep -qF MAIN-ONLY <<< "${brief}" && echo yes || echo no)"
check "it pastes the story as the board holds it, which the last builder may have deleted" "yes" \
  "$(grep -A3 -x '### The story, as the board holds it' <<< "${brief}" | tail -2 | paste -sd' ' - | grep -qx -- '--- status: ready' && echo yes)"
# shellcheck disable=SC2016 # the backticks are the brief's, not a command
check "it names the PR body's models line, with every model in order" "yes" "$(has 'models line: `Models: sonnet, opus`' "${brief}")"
check "it logs one escalate line naming the trigger and both models" "1|ok (findings-3: sonnet -> opus)" \
  "$(escalates)|$(awk -F'\t' '$2 == "escalate" { print $5 }' "${P}/.swarm/events.tsv")"
check "and says so" "yes" "$(has "stepped up: s1 from sonnet to opus (code)" "${out}")"

# A start that fails: the opus builder is closed, nothing is logged as an escalation, and the
# message names the command that starts the fable rung from the brief, which then works. s1 is no
# longer stacked here, so its diff starts at its merge-base with origin/main.
grep -v $'\t\\(stacked\\|story\\)\t' "${P}/.swarm/events.tsv" > "${ROOT}/ev" && mv "${ROOT}/ev" "${P}/.swarm/events.tsv"
touch "${ROOT}/startfail"
out="$(run step-up s1 ci-red-2)" && rc=0 || rc=$?
brief="$(cat "${P}/.swarm/briefs/s1.md")"
check "when the next builder does not start, step-up fails, logs no escalation and says how to start it" "1|yes|1" \
  "${rc}|$(has "the fable builder did not start; its worktree, branch and brief are kept, so start it with: swarm.sh agent s1 s1 ${WT} escalate ${P}/.swarm/briefs/s1.md" "${out}")|$(escalates)"
check "a story that is not stacked has a diff from its merge-base with origin/main: main's newer commits are not in it" "yes|no" \
  "$(has "+PARENT-WORK" "${brief}")|$(grep -qF MAIN-ONLY <<< "${brief}" && echo yes || echo no)"
rm "${ROOT}/startfail"
cmd="${out##*start it with: swarm.sh }"
# shellcheck disable=SC2086 # the printed words, as a user pastes them
run ${cmd} >/dev/null || true
check "and that command starts the fable rung in the worktree" "escalate fable" "$(tail -1 "${P}/.swarm/agents.tsv" | cut -f2,5 | tr '\t' ' ')"

# The top rung: a build on fable has no next model. Nothing closes or starts.
n="$(starts)"
out="$(run step-up s1 stalled)" && rc=0 || rc=$?
check "at the top rung step-up refuses, closing and starting nothing" "1|yes|${n}|1" \
  "${rc}|$(has "escalate_ladder's top rung" "${out}")|$(starts)|$(escalates)"
: > "${P}/.claude/swarm/config"
out="$(run step-up s1 stalled)" && rc=0 || rc=$?
check "with escalate_ladder empty step-up refuses" "1|yes|${n}" \
  "${rc}|$(has "escalate_ladder is empty (off)" "${out}")|$(starts)"
out="$(run step-up s1 bored)" && rc=0 || rc=$?
check "an unknown trigger is refused" "1|yes" "${rc}|$(has "the trigger must be one of findings-3, ci-red-2, stalled, no-pr" "${out}")"

# --- A sonnet -> opus -> fable chain of step-ups on s2, today. In outcomes the three builds are one
# attempt, the two replaced builds each have a close with cause step-up:<trigger>, and the Fable
# build's escalate column is the opus -> fable step, never the sonnet -> opus one. dash counts one
# escalation, and the Fable builder's card says where it came from and when.
Q="${ROOT}/q"; mkdir -p "${Q}/.swarm/state" "${Q}/docs/stories" "${ROOT}/projects/q"; : > "${Q}/docs/stories/README.md"; git -C "${Q}" init -q
NOW="$(python3 -c 'import datetime; print(int(datetime.datetime(2026, 10, 10, 12).timestamp()))')"
for s in 1:09:00 2:10:00 3:11:00; do
  printf '{"type":"user","cwd":"%s/q-wt/s2","timestamp":"2026-10-10T%s:01Z"}\n' "${ROOT}" "${s#*:}" > "${ROOT}/projects/q/q${s%%:*}.jsonl"
done
printf '%s\n' $'2026-10-10\tcode-sonnet\ts2\tclaude\tsonnet\thigh\tq1' $'2026-10-10\tcode\ts2\tclaude\topus\thigh\tq2' \
  $'2026-10-10\tescalate\ts2\tclaude\tfable\txhigh\tq3' > "${Q}/.swarm/agents.tsv"
printf '%s\n' $'2026-10-10T10:00:00Z\tescalate\ts2\tw:1\tok (no-pr: sonnet -> opus)' \
  $'2026-10-10T11:00:00Z\tescalate\ts2\tw:1\tok (findings-3: opus -> fable)' > "${Q}/.swarm/events.tsv"
qrun() { (cd "${Q}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${STUB_BIN}:${PATH}" bash "${SWARM}" "$@" 2>&1); }
qout="$(qrun outcomes | tail -n +2 | cut -f5,13,17,23,24)"
check "outcomes counts the three rungs as one attempt and closes each replaced build, cause step-up:<trigger>" \
  "$(printf '%s\n' "code-sonnet	1	1	step-up:no-pr" "code	1	1	step-up:findings-3" "escalate	0	1	")" "$(cut -f1-4 <<< "${qout}")"
check "outcomes' escalate column for the Fable build has the opus -> fable step's time" \
  "$(printf '%s\n' "code-sonnet	" "code	" "escalate	2026-10-10T11:00:00Z")" "$(cut -f1,5 <<< "${qout}")"
# dash: s2's Fable builder is working in pane w2:p8, its session q3 busy.
QBIN="${ROOT}/q-bin"; mkdir -p "${QBIN}"
cat > "${QBIN}/herdr" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"s2","agent_status":"working","pane_id":"w2:p8"}]}}' ;;
  "pane list")  echo '{"result":{"panes":[{"pane_id":"w2:p8"}]}}' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "${QBIN}/herdr"; echo "w2:p8 s2" > "${Q}/.swarm/state/s2"
printf '[{"sessionId":"q3","status":"busy"}]' > "${ROOT}/q-claude.json"
qdash="$(cd "${Q}" && env -u SWARM_PROJECT HERDR_ENV=1 CLAUDE_STUB_AGENTS="${ROOT}/q-claude.json" SWARM_DASH_NOW="${NOW}" COLUMNS=100 LINES=80 PATH="${QBIN}:${STUB_BIN}:${PATH}" bash "${SWARM}" dash 2>&1)"
check "dash counts one escalation today" "yes" "$(has "1 escalation today" "${qdash}")"
check "and the stepped-up Fable builder's row says it came from opus, and when" "yes" \
  "$(grep -qE '● s2 +escalate +fable·xhigh .*from opus · 11:00' <<< "${qdash}" && echo yes || echo "no, got: ${qdash}")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
