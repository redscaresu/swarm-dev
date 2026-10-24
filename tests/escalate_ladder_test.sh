#!/usr/bin/env bash
# escalate_ladder_test.sh — swarm.sh step-up <slug> <trigger>: with escalate_ladder set, it closes a
# story's builder without counting an attempt and starts the ladder's next model in the same worktree
# and branch, in the build's own role family, with a handover brief, logging one escalate line; a
# start that fails stops at the failing step and leaves step-up --resume to start the rung; at the top
# rung or with the ladder empty it refuses. Then outcomes and dash read sonnet -> opus -> fable chains
# of step-ups: one attempt each, each replaced build closed, only the step to fable paired with the
# Fable build and counted as an escalation, and the rung's start taken from its step-up. herdr, gh and
# claude (tests/claude_stub.sh) are stubs on PATH: herdr records each call, and fails tab create
# while ${ROOT}/tabfail exists, agent start while ${ROOT}/startfail does and agent prompt (the brief,
# after the agent is recorded) while ${ROOT}/promptfail does; while ${ROOT}/startghost exists an agent
# starts but is gone at once (never listed); a tab or pane it closes while ${ROOT}/late names a
# worktree writes late.txt there, as a builder's last write. gh lists an open PR on
# every branch (story/p1's its own, none once ${ROOT}/p1-closed exists; story/p2's and story/p3's
# merged, none open), with one failing check (exit 1, as gh's is); PR #21 has no checks reported,
# gh cannot read #22's, and #23's pass. A list of every PR on story/<slug> (step-up's own) is
# ${ROOT}/prs-<slug>.json, else that open PR #5, and fails while ${ROOT}/ghfail exists.
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
lacks() { if grep -qF -- "$1" <<< "$2"; then echo "no, it has $1"; else echo yes; fi; }

# herdr: logs every call; panes are w:<n>; agents lists "<name> <pane>" lines, all idle (agent get of a
# listed pane too), until a tab closes (each story's builder has a tab of its own, and one is open at a
# time); tab and pane close fail while ${ROOT}/closefail exists. While ${ROOT}/promptsent exists, agent
# prompt replies with no status (sent), and agent get reads the agent idle with no completion_seq: a
# prompt never taken up; with ${ROOT}/getnone too, agent get gives nothing, so whether it was taken up
# is unknown.
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" | tee "${STUB_BIN}/gh" > "${STUB_BIN}/herdr"
cat >> "${STUB_BIN}/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
next() { n=$(($(cat "$H/n" 2>/dev/null || echo 10) + 1)); echo "$n" > "$H/n"; }
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;   # start_agent's require_herdr_version
  "tab create")   [ ! -e "$H/tabfail" ] || { echo '{"error":{"code":"tab_failed"}}' >&2; exit 1; }
                  next; echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "pane split")   next; echo "{\"result\":{\"pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "pane run"|"pane wait-output") [ -n "$3" ] || exit 1 ;;   # herdr fails with no pane
  "tab list")     echo '{"result":{"tabs":[{"tab_id":"w:t1","label":"s1"},{"tab_id":"w:t2","label":"d1"},{"tab_id":"w:t3","label":"c1"},{"tab_id":"w:t4","label":"m1"},{"tab_id":"w:t5","label":"m2"},{"tab_id":"w:t6","label":"k1"},{"tab_id":"w:t7","label":"k2"},{"tab_id":"w:t8","label":"k3"},{"tab_id":"w:t9","label":"w1"},{"tab_id":"w:t10","label":"f1"},{"tab_id":"w:t11","label":"f2"},{"tab_id":"w:t12","label":"f3"},{"tab_id":"w:t13","label":"f4"},{"tab_id":"w:t14","label":"f5"},{"tab_id":"w:t15","label":"f6"},{"tab_id":"w:t16","label":"f7"}]}}' ;;
  "tab close")    [ ! -e "$H/closefail" ] || exit 1
                  : > "$H/agents"; [ ! -e "$H/late" ] || echo LATE-WORK > "$(cat "$H/late")/late.txt" ;;
  "pane close")   [ ! -e "$H/closefail" ] || exit 1
                  [ ! -e "$H/late" ] || echo LATE-WORK > "$(cat "$H/late")/late.txt" ;;
  "agent start")  [ ! -e "$H/startfail" ] || { echo '{"error":{"code":"start_failed"}}' >&2; exit 1; }
                  [ -e "$H/startghost" ] || echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')" >> "$H/agents" ;;
  "agent rename") awk -v p="$3" -v n="$4" '$2 == p { $1 = n } { print }' "$H/agents" > "$H/agents.tmp" && mv "$H/agents.tmp" "$H/agents" ;;
  "agent prompt") [ ! -e "$H/promptfail" ] || exit 1
                  [ ! -e "$H/promptsent" ] || { echo '{"result":{}}'; exit 0; }   # sent, with no status
                  echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent get")    awk -v p="$3" '$2 == p { f = 1 } END { exit !f }' "$H/agents" || exit 1
                  [ -e "$H/getnone" ] || echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent list")   awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                    { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                    END { print "]}}" }' "$H/agents" ;;
esac
EOF
cat >> "${STUB_BIN}/gh" <<'EOF'
case "$1 $2 $*" in
  "pr list "*"--state all"*) [ ! -e "$H/ghfail" ] || exit 1
                s="$(echo "$*" | sed 's/.*--head story\/\([^ ]*\).*/\1/')"
                if [ -e "$H/prs-$s.json" ]; then cat "$H/prs-$s.json"; else echo '[{"state":"OPEN","url":"https://github.com/o/proj/pull/5","autoMergeRequest":null}]'; fi ;;
  "pr list "*story/p1*) [ -e "$H/p1-closed" ] || echo "https://github.com/o/proj/pull/4" ;;
  "pr list "*story/p[23]*"--state merged"*) echo 1 ;;
  "pr list "*story/p[23]*) ;;
  "pr list "*)  echo "https://github.com/o/proj/pull/5" ;;
  "pr checks "*/pull/21*) echo "no checks reported on the 'story/k1' branch" >&2; exit 1 ;;
  "pr checks "*/pull/22*) echo "GraphQL: API rate limit exceeded" >&2; exit 1 ;;
  "pr checks "*/pull/23*) ;;
  "pr checks "*) echo "- test: https://ci/run/9"; exit 1 ;;
esac
EOF
# awk: the real one. While ${ROOT}/race names agents.tsv, once start_rung's drop of an unstarted
# rung has read it, another conductor's record_agent appends a line there: at once when the log's
# lock is free (the drop would then replace the file without it), else once the lock is let go.
printf '#!/bin/sh\nH="%s"\nA="%s"\n' "${ROOT}" "$(command -v awk)" > "${STUB_BIN}/awk"
cat >> "${STUB_BIN}/awk" <<'EOF'
"$A" "$@" || exit $?
case "$*" in *"NR <= n"*) [ -e "$H/race" ] || exit 0 ;; *) exit 0 ;; esac
log="$(cat "$H/race")"; rm "$H/race"
add() { printf '2026-10-01\tcode\tother-epic\tclaude\topus\thigh\tsess-other\n' >> "$log"; rmdir "$log.lock"; touch "$H/raced"; }
if mkdir "$log.lock" 2>/dev/null; then add; exit 0; fi
( i=0; until mkdir "$log.lock" 2>/dev/null; do i=$((i + 1)); [ "$i" -lt 100 ] || exit 1; sleep 0.1; done; add ) </dev/null >/dev/null 2>&1 &
EOF
chmod +x "${STUB_BIN}/herdr" "${STUB_BIN}/gh" "${STUB_BIN}/awk"

# A project whose board is in its repo, with story s1 stacked on p1 (whose PR is open) and started
# on sonnet: its worktree holds a commit (with a Markdown file holding a ``` fence), an untracked
# file and a long untracked one, its builder is open in pane w:1, and a review agent left findings of
# its HEAD. main has moved on since.
P="${ROOT}/proj"; WT="${ROOT}/proj-wt/s1"
"${GIT[@]}" init -q --bare "${ROOT}/origin.git"
"${GIT[@]}" clone -q "${ROOT}/origin.git" "${P}" 2>/dev/null
mkdir -p "${P}/docs/stories" "${P}/.claude/swarm" "${P}/.swarm/state" "${P}/.swarm/reviews"
printf '%s\n' --- "status: ready" "kind: code" --- "" "# s1" "" "**Done when:**" "- it holds" > "${P}/docs/stories/s1.md"
printf '%s\n' --- "status: ready" "kind: docs" --- "" "# d1" "" "**Done when:**" "- it reads" > "${P}/docs/stories/d1.md"
printf '%s\n' --- "status: ready" "kind: chore" --- "" "# c1" "" "**Done when:**" "- it is done" > "${P}/docs/stories/c1.md"
"${GIT[@]}" -C "${P}" add -A && "${GIT[@]}" -C "${P}" commit -qm init && "${GIT[@]}" -C "${P}" push -q origin main
"${GIT[@]}" -C "${P}" worktree add -q -b story/p1 "${ROOT}/proj-wt/p1" origin/main
echo "PARENT-WORK" > "${ROOT}/proj-wt/p1/parent.txt"
"${GIT[@]}" -C "${ROOT}/proj-wt/p1" add parent.txt && "${GIT[@]}" -C "${ROOT}/proj-wt/p1" commit -qm parent && "${GIT[@]}" -C "${ROOT}/proj-wt/p1" push -q origin story/p1
"${GIT[@]}" -C "${P}" fetch -q origin && "${GIT[@]}" -C "${P}" worktree add -q --no-track -b story/s1 "${WT}" origin/story/p1
echo "SONNET-WORK" > "${WT}/work.txt"; printf '%s\n' '# notes' '```sh' 'echo hi' '```' > "${WT}/notes.md"
"${GIT[@]}" -C "${WT}" add work.txt notes.md && "${GIT[@]}" -C "${WT}" commit -qm work
# zz-big.txt makes the diff far longer than the brief keeps (and than a pipe holds), after the rest.
echo "UNTRACKED-WORK" > "${WT}/new-work.txt"
awk 'BEGIN { for (i = 0; i < 5000; i++) print "a line of the long diff that the handover brief cuts off" }' > "${WT}/zz-big.txt"
for i in $(seq 10 39); do echo "past the cap" > "${WT}/zz-past-${i}.txt"; done   # never diffed: the cap is reached first
echo "MAIN-ONLY" > "${P}/main.txt"; "${GIT[@]}" -C "${P}" add main.txt && "${GIT[@]}" -C "${P}" commit -qm main && "${GIT[@]}" -C "${P}" push -q origin main
printf '2026-10-01\tcode-sonnet\ts1\tclaude\tsonnet\thigh\tsess-1\n' > "${P}/.swarm/agents.tsv"
printf '%s\n' $'2026-10-01T09:00:00Z\tstacked\ts1\tw:1\tok (on p1)' $'2026-10-01T09:00:01Z\tstory\ts1\tw:1\tok' > "${P}/.swarm/events.tsv"
echo "w:1 s1" > "${P}/.swarm/state/s1"; echo "s1 w:1" > "${ROOT}/agents"
printf '%s\n' "head: $(git -C "${WT}" rev-parse HEAD)" "REVIEW-FINDING: the guard is missing" > "${P}/.swarm/reviews/s1.md"
echo "escalate_ladder = sonnet,opus,fable" > "${P}/.claude/swarm/config"
run() { (cd "${P}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${STUB_BIN}:${PATH}" bash "${SWARM}" "$@" 2>&1); }
escalates() { grep -c $'\tescalate\t' "${P}/.swarm/events.tsv" 2>/dev/null || true; }
starts() { grep -c '^agent start' "${ROOT}/herdr.log" 2>/dev/null || true; }
newest() { awk -F'\t' -v n="$1" '$3 == n { l = $2 " " $5 " " $6 } END { print l }' "${P}/.swarm/agents.tsv"; }
# attempts — s1's attempts: as swarm.sh reads it (board.sh's get_fm: its state file, then its file).
# shellcheck source=/dev/null
attempts() { (export BOARD="${P}/docs" PROJECT_DIR="${P}"; . "${SWARM%/*}/lib/board.sh"; get_fm "${BOARD}/stories/s1.md" attempts) 2>/dev/null || true; }

# With herdr unable to close s1's builder (its tab, then its pane), the step-up is refused: no rung
# starts in the worktree beside it, no escalation is logged, and no step-up marker is left.
touch "${ROOT}/closefail"; out="$(run step-up s1 findings-3)" && rc=0 || rc=$?; rm "${ROOT}/closefail"
check "with s1's pane failing to close, step-up refuses: no rung started, no escalation, no marker, and it says so" "1|0|0|none|yes" \
  "${rc}|$(starts)|$(escalates)|$([[ -e "${P}/.swarm/briefs/s1.step-up" ]] && echo kept || echo none)|$(has "s1's builder pane could not be closed, so it may still be working in its worktree; nothing was stepped up" "${out}")"
: > "${ROOT}/herdr.log"
echo "${WT}" > "${ROOT}/late"
out="$(GIT_TRACE="${ROOT}/git.trace" run step-up s1 findings-3)" || true
rm "${ROOT}/late" "${WT}/late.txt"
check "step-up on a sonnet build closes its pane and starts opus as code in the same worktree" \
  "yes|yes|code opus high" \
  "$(grep -qx 'tab close w:t1' "${ROOT}/herdr.log" && echo yes)|$(grep -q -- "--cwd ${WT} " "${ROOT}/herdr.log" && echo yes)|$(newest s1)"
check "the worktree keeps its branch and commit, and no attempt is counted" "story/s1|SONNET-WORK|" \
  "$(git -C "${WT}" rev-parse --abbrev-ref HEAD)|$(cat "${WT}/work.txt")|$(attempts)"
brief="$(cat "${P}/.swarm/briefs/s1.md")"
check "the handover brief holds the story, the diff (cut to 400 lines), the findings and the failing check" "yes|yes|yes|yes|yes" \
  "$(has "Implement docs/stories/s1.md" "${brief}")|$(has "+SONNET-WORK" "${brief}")|$([[ $(grep -c "^+a line of the long diff" <<< "${brief}") -lt 400 ]] && echo yes)|$(has "REVIEW-FINDING: the guard is missing" "${brief}")|$(has "- test: https://ci/run/9" "${brief}")"
check "the diff holds an untracked file" "yes" "$(has "+UNTRACKED-WORK" "${brief}")"
check "the brief is written once the old builder is closed, so it holds that builder's last write" "yes" "$(has "+LATE-WORK" "${brief}")"
check "it stops diffing untracked files at the cap: the 30 past it are never diffed" "yes" \
  "$([[ $(grep -c 'diff --no-index' "${ROOT}/git.trace") -lt 10 ]] && echo yes || echo "no, $(grep -c 'diff --no-index' "${ROOT}/git.trace") diffs")"
check "the diff's fence is longer than the \`\`\` in a Markdown file it holds" "yes|yes" \
  "$(has '````diff' "${brief}")|$(has '+```sh' "${brief}")"
# shellcheck disable=SC2016 # the backticks are the brief's, not a command
check "a stacked story's brief carries the Merge after note, and its diff starts at the parent's branch, so neither the parent's nor main's newer commits are in it" \
  "yes|yes|yes" "$(has 'with `Merge after https://github.com/o/proj/pull/4` in its body' "${brief}")|$(lacks PARENT-WORK "${brief}")|$(lacks MAIN-ONLY "${brief}")"
check "it pastes the story as the board holds it, which the last builder may have deleted" "yes" \
  "$(grep -A3 -x '### The story, as the board holds it' <<< "${brief}" | tail -2 | paste -sd' ' - | grep -qx -- '--- status: ready' && echo yes)"
# shellcheck disable=SC2016 # the backticks are the brief's, not a command
check "it names the PR body's models line, with every model in order" "yes" "$(has 'models line: `Models: sonnet, opus`' "${brief}")"
check "it logs one escalate line naming the trigger and both models" "1|ok (findings-3: sonnet -> opus)" \
  "$(escalates)|$(awk -F'\t' '$2 == "escalate" { print $5 }' "${P}/.swarm/events.tsv")"
check "and says so" "yes" "$(has "stepped up: s1 from sonnet to opus (code)" "${out}")"

# A start that fails at its first herdr step (the tab) stops there with that step's own message,
# logs no escalation, and keeps the rung for step-up --resume; a resume whose start fails keeps it
# too, and one that starts logs the step-up then. p1's PR is closed now while a stale origin/story/p1
# still resolves, and the review is of an older head.
touch "${ROOT}/p1-closed" "${ROOT}/tabfail"
printf '%s\n' "head: $(git -C "${ROOT}/proj-wt/p1" rev-parse HEAD)" "STALE-FINDING: fixed long ago" > "${P}/.swarm/reviews/s1.md"
out="$(run step-up s1 ci-red-2)" && rc=0 || rc=$?
brief="$(cat "${P}/.swarm/briefs/s1.md")"
check "a start that fails stops at the failing step, logs no escalation and names step-up --resume" "1|yes|yes|1" \
  "${rc}|$(has "herdr could not open a pane" "${out}")|$(has "the fable builder did not start (see above); its worktree, branch and brief are kept: once that is fixed, run swarm.sh step-up --resume s1" "${out}")|$(escalates)"
check "and never carries on to a later step with no pane" "yes" "$(lacks "did not take the agent's environment" "${out}")"
check "a story whose parents' PRs are no longer open has a diff from its merge-base with origin/main, though a stale origin/story/p1 still resolves" "yes|yes|yes" \
  "$(has "+PARENT-WORK" "${brief}")|$(lacks MAIN-ONLY "${brief}")|$(lacks "Merge after" "${brief}")"
check "findings of an older head are not pasted as open, and the brief says why" "yes|yes" \
  "$(lacks "STALE-FINDING" "${brief}")|$(has "The last review (${P}/.swarm/reviews/s1.md) was of $(git -C "${ROOT}/proj-wt/p1" rev-parse HEAD), not this branch's HEAD" "${brief}")"
sed -i.bak 's/^kind: code$/kind: lead/' "${P}/docs/stories/s1.md"
out="$(run step-up --resume s1)" && rc=0 || rc=$?
check "a resume of a story made kind: lead since refuses, starting nothing" "1|yes|1" "${rc}|$(has "s1 is kind: lead, which no agent builds" "${out}")|$(escalates)"
mv "${P}/docs/stories/s1.md.bak" "${P}/docs/stories/s1.md"
rm "${ROOT}/tabfail"; touch "${ROOT}/promptfail" "${ROOT}/startghost"
out="$(SWARM_PROMPT_TIMEOUT_MS=100 run step-up --resume s1)" && rc=0 || rc=$?
check "a resume whose agent is gone before its brief is taken up keeps the rung to resume again, and takes back the agents.tsv line it wrote" "1|yes|1|code opus high" \
  "${rc}|$(has "run swarm.sh step-up --resume s1" "${out}")|$(escalates)|$(newest s1)"
rm "${ROOT}/startghost"
c="$(grep -c '^tab close' "${ROOT}/herdr.log")"
echo "${P}/.swarm/agents.tsv" > "${ROOT}/race"
out="$(SWARM_PROMPT_TIMEOUT_MS=100 run step-up --resume s1)" && rc=0 || rc=$?
for _ in $(seq 50); do [[ ! -e "${ROOT}/raced" ]] || break; sleep 0.1; done
check "a resume whose agent runs but never took up its brief has not started: it is closed, off agents.tsv, and the rung waits to resume" "1|yes|$((c + 1))|code opus high|1|kept" \
  "${rc}|$(has "run swarm.sh step-up --resume s1" "${out}")|$(grep -c '^tab close' "${ROOT}/herdr.log")|$(newest s1)|$(escalates)|$([[ -e "${P}/.swarm/briefs/s1.step-up" ]] && echo kept)"
check "a line another conductor records while that drop runs is kept" "1|none" \
  "$(grep -c $'\tother-epic\t' "${P}/.swarm/agents.tsv")|$(ls -d "${P}/.swarm/agents.tsv.lock" 2>/dev/null || echo none)"
rm "${ROOT}/promptfail"
out="$(run step-up --resume s1)" && rc=0 || rc=$?
check "a resume whose brief is taken up has started: the step-up stands, on record once" "0|escalate fable xhigh|1|2|ok (ci-red-2: opus -> fable)|gone" \
  "${rc}|$(newest s1)|$(grep -c $'\ts1\tclaude\tfable\t' "${P}/.swarm/agents.tsv")|$(escalates)|$(awk -F'\t' '$2 == "escalate" { l = $5 } END { print l }' "${P}/.swarm/events.tsv")|$([[ -e "${P}/.swarm/briefs/s1.step-up" ]] || echo gone)"
out="$(run step-up --resume s1)" && rc=0 || rc=$?
check "with nothing to resume, --resume refuses" "1|yes" "${rc}|$(has "no step-up of 's1' waits to start" "${out}")"

# The top rung: a build on fable has no next model. Nothing closes or starts.
n="$(starts)"
out="$(run step-up s1 stalled)" && rc=0 || rc=$?
check "at the top rung step-up refuses, closing and starting nothing" "1|yes|${n}|2" \
  "${rc}|$(has "at or above escalate_ladder's top rung" "${out}")|$(starts)|$(escalates)"
: > "${P}/.claude/swarm/config"
out="$(run step-up s1 stalled)" && rc=0 || rc=$?
check "with escalate_ladder empty step-up refuses" "1|yes|${n}" "${rc}|$(has "escalate_ladder is empty (off)" "${out}")|$(starts)"
out="$(run step-up s1 bored)" && rc=0 || rc=$?
check "an unknown trigger is refused" "1|yes" "${rc}|$(has "the trigger must be one of findings-3, ci-red-2, stalled, no-pr" "${out}")"

# A docs build on sonnet steps up as docs on opus, and a chore build on haiku, below the ladder's
# first rung, as a chore on sonnet: each keeps its role and its effort.
echo "escalate_ladder = sonnet,opus,fable" > "${P}/.claude/swarm/config"
echo '[{"state":"CLOSED","url":"https://github.com/o/proj/pull/6","autoMergeRequest":null}]' > "${ROOT}/prs-c1.json"
for s in d1:docs:sonnet c1:chore:haiku; do
  IFS=: read -r slug role model <<< "${s}"
  "${GIT[@]}" -C "${P}" worktree add -q -b "story/${slug}" "${ROOT}/proj-wt/${slug}" origin/main
  printf '2026-10-01\t%s\t%s\tclaude\t%s\tmedium\tsess-%s\n' "${role}" "${slug}" "${model}" "${slug}" >> "${P}/.swarm/agents.tsv"
  echo "w:2 ${slug}" > "${P}/.swarm/state/${slug}"; echo "${slug} w:2" > "${ROOT}/agents"
  run step-up "${slug}" stalled >/dev/null || true
done
check "a docs build steps up as docs, and a chore below the first rung as a chore on it" "docs opus medium|chore sonnet medium" "$(newest d1)|$(newest c1)"
check "a story whose only PR closed unmerged has no open PR, and its brief says so" "yes" "$(has "No open PR on story/c1." "$(cat "${P}/.swarm/briefs/c1.md")")"

# The open PR's checks: k1's PR has none reported, gh cannot read k2's, and k3's all pass. Each is
# said plainly, never as gh failing when it did not.
for k in k1:21 k2:22 k3:23; do
  slug="${k%:*}"
  printf '%s\n' --- "status: ready" "kind: code" --- "" "# ${slug}" "" "**Done when:**" "- it holds" > "${P}/docs/stories/${slug}.md"
  "${GIT[@]}" -C "${P}" worktree add -q -b "story/${slug}" "${ROOT}/proj-wt/${slug}" origin/main
  printf '2026-10-01\tcode-sonnet\t%s\tclaude\tsonnet\thigh\tsess-%s\n' "${slug}" "${slug}" >> "${P}/.swarm/agents.tsv"
  echo "[{\"state\":\"OPEN\",\"url\":\"https://github.com/o/proj/pull/${k#*:}\",\"autoMergeRequest\":null}]" > "${ROOT}/prs-${slug}.json"
  echo "w:2 ${slug}" > "${P}/.swarm/state/${slug}"; echo "${slug} w:2" > "${ROOT}/agents"
  run step-up "${slug}" ci-red-2 >/dev/null || true
done
check "a PR with no checks reported, one gh cannot read and one with none failing are each said so in the brief" "yes|yes|yes" \
  "$(has "No checks reported on https://github.com/o/proj/pull/21." "$(cat "${P}/.swarm/briefs/k1.md")")|$(has "gh could not list https://github.com/o/proj/pull/22's checks" "$(cat "${P}/.swarm/briefs/k2.md")")|$(has "None failing on https://github.com/o/proj/pull/23." "$(cat "${P}/.swarm/briefs/k3.md")")"

# A git step the closed builder left unfinished in its worktree (an index.lock, then a merge in
# progress) stops the step-up before the brief is written or a builder starts, and names it; once it
# is cleared, --resume writes the brief and starts the rung.
printf '%s\n' --- "status: ready" "kind: code" --- "" "# w1" "" "**Done when:**" "- it holds" > "${P}/docs/stories/w1.md"
"${GIT[@]}" -C "${P}" worktree add -q -b story/w1 "${ROOT}/proj-wt/w1" origin/main
printf '2026-10-01\tcode-sonnet\tw1\tclaude\tsonnet\thigh\tsess-w1\n' >> "${P}/.swarm/agents.tsv"
echo "w:2 w1" > "${P}/.swarm/state/w1"; echo "w1 w:2" > "${ROOT}/agents"
gd="$(git -C "${ROOT}/proj-wt/w1" rev-parse --absolute-git-dir)"; touch "${gd}/index.lock"
n="$(starts)"; e="$(escalates)"
out="$(run step-up w1 stalled)" && rc=0 || rc=$?
check "an index.lock left in the worktree stops the step-up, naming it, before a brief or a start" "1|yes|${n}|${e}|none|kept" \
  "${rc}|$(has "w1's sonnet builder is closed, but its worktree ${ROOT}/proj-wt/w1 holds ${gd}/index.lock, a git step left unfinished: finish or abort it there, then run swarm.sh step-up --resume w1" "${out}")|$(starts)|$(escalates)|$([[ -e "${P}/.swarm/briefs/w1.md" ]] && echo written || echo none)|$([[ -e "${P}/.swarm/briefs/w1.step-up" ]] && echo kept)"
rm "${gd}/index.lock"; git -C "${ROOT}/proj-wt/w1" rev-parse HEAD > "${gd}/MERGE_HEAD"
out="$(run step-up --resume w1)" && rc=0 || rc=$?
check "and so does a merge in progress, on resume too" "1|yes|${n}" "${rc}|$(has "holds ${gd}/MERGE_HEAD" "${out}")|$(starts)"
rm "${gd}/MERGE_HEAD"; mv "${ROOT}/origin.git" "${ROOT}/origin.gone"
out="$(run step-up --resume w1)" && rc=0 || rc=$?
check "an origin whose default branch cannot be read stops it too, with the rung kept to resume" "1|yes|${n}|kept" \
  "${rc}|$(has "origin's default branch could not be read (see above); once it can, run swarm.sh step-up --resume w1" "${out}")|$(starts)|$([[ -e "${P}/.swarm/briefs/w1.step-up" ]] && echo kept)"
mv "${ROOT}/origin.gone" "${ROOT}/origin.git"
out="$(run step-up --resume w1)" && rc=0 || rc=$?
# w1 is untracked here, so its brief names it by its full path (story_path); either form names w1.
check "once cleared, --resume writes the brief and starts the rung" "0|yes|code opus high" "${rc}|$(has "stories/w1.md (this worktree is proj)" "$(cat "${P}/.swarm/briefs/w1.md" 2>/dev/null)")|$(newest w1)"

# m1 was stacked on p2, whose PR has since squash-merged into main (its change on main under another
# commit), and main moved on. The diff is against origin/main with the branch merged in: m1's own
# work only, and the brief says to merge main in.
"${GIT[@]}" -C "${P}" worktree add -q -b story/p2 "${ROOT}/proj-wt/p2" origin/main
echo "PARENT2-WORK" > "${ROOT}/proj-wt/p2/parent2.txt"
"${GIT[@]}" -C "${ROOT}/proj-wt/p2" add parent2.txt && "${GIT[@]}" -C "${ROOT}/proj-wt/p2" commit -qm parent2 && "${GIT[@]}" -C "${ROOT}/proj-wt/p2" push -q origin story/p2
"${GIT[@]}" -C "${P}" fetch -q origin && "${GIT[@]}" -C "${P}" worktree add -q --no-track -b story/m1 "${ROOT}/proj-wt/m1" origin/story/p2
echo "M1-WORK" > "${ROOT}/proj-wt/m1/m1.txt"; "${GIT[@]}" -C "${ROOT}/proj-wt/m1" add m1.txt && "${GIT[@]}" -C "${ROOT}/proj-wt/m1" commit -qm m1
"${GIT[@]}" -C "${P}" pull -q origin main
echo "PARENT2-WORK" > "${P}/parent2.txt"; "${GIT[@]}" -C "${P}" add parent2.txt && "${GIT[@]}" -C "${P}" commit -qm "p2 (#2)"
echo "MAIN2-ONLY" > "${P}/main2.txt"; "${GIT[@]}" -C "${P}" add main2.txt && "${GIT[@]}" -C "${P}" commit -qm main2 && "${GIT[@]}" -C "${P}" push -q origin main
printf '%s\n' --- "status: ready" "kind: code" --- "" "# m1" "" "**Done when:**" "- it holds" > "${P}/docs/stories/m1.md"
printf '2026-10-01\tcode-sonnet\tm1\tclaude\tsonnet\thigh\tsess-m1\n' >> "${P}/.swarm/agents.tsv"
printf '%s\n' $'2026-10-01T09:00:00Z\tstacked\tm1\tw:1\tok (on p2)' $'2026-10-01T09:00:01Z\tstory\tm1\tw:1\tok' >> "${P}/.swarm/events.tsv"
echo "w:2 m1" > "${P}/.swarm/state/m1"; echo "m1 w:2" > "${ROOT}/agents"
run step-up m1 no-pr >/dev/null || true
brief="$(cat "${P}/.swarm/briefs/m1.md")"
check "a story whose parent's PR squash-merged has a diff of its own work against origin/main with the branch merged in, and is told to merge main in" "yes|yes|yes|yes" \
  "$(has "+M1-WORK" "${brief}")|$(lacks PARENT2-WORK "${brief}")|$(lacks MAIN2-ONLY "${brief}")|$(has "This story was stacked on p2, whose PRs have merged: merge \`origin/main\` into your branch before you push" "${brief}")"

# m2 is stacked on p3, also merged since, but merging main in would conflict: main changed main.txt
# as m2 did. The diff stays the merge-base one (no conflict markers, no main-only file), and the
# brief says to merge main in and resolve it.
"${GIT[@]}" -C "${P}" worktree add -q -b story/p3 "${ROOT}/proj-wt/p3" origin/main
echo "PARENT3-WORK" > "${ROOT}/proj-wt/p3/parent3.txt"
"${GIT[@]}" -C "${ROOT}/proj-wt/p3" add parent3.txt && "${GIT[@]}" -C "${ROOT}/proj-wt/p3" commit -qm parent3 && "${GIT[@]}" -C "${ROOT}/proj-wt/p3" push -q origin story/p3
"${GIT[@]}" -C "${P}" fetch -q origin && "${GIT[@]}" -C "${P}" worktree add -q --no-track -b story/m2 "${ROOT}/proj-wt/m2" origin/story/p3
echo "M2-EDIT" > "${ROOT}/proj-wt/m2/main.txt"; "${GIT[@]}" -C "${ROOT}/proj-wt/m2" commit -qam m2
echo "PARENT3-WORK" > "${P}/parent3.txt"; echo "MAIN3-EDIT" > "${P}/main.txt"; echo "MAIN3-ONLY" > "${P}/main3.txt"
"${GIT[@]}" -C "${P}" add parent3.txt main.txt main3.txt && "${GIT[@]}" -C "${P}" commit -qm "p3 (#3), and main moves" && "${GIT[@]}" -C "${P}" push -q origin main
printf '%s\n' --- "status: ready" "kind: code" --- "" "# m2" "" "**Done when:**" "- it holds" > "${P}/docs/stories/m2.md"
printf '2026-10-01\tcode-sonnet\tm2\tclaude\tsonnet\thigh\tsess-m2\n' >> "${P}/.swarm/agents.tsv"
printf '%s\n' $'2026-10-01T09:00:00Z\tstacked\tm2\tw:1\tok (on p3)' $'2026-10-01T09:00:01Z\tstory\tm2\tw:1\tok' >> "${P}/.swarm/events.tsv"
echo "w:2 m2" > "${P}/.swarm/state/m2"; echo "m2 w:2" > "${ROOT}/agents"
run step-up m2 no-pr >/dev/null || true
brief="$(cat "${P}/.swarm/briefs/m2.md")"
check "when merging main in would conflict, the diff stays the merge-base one, with no markers or main-only file, and the brief says to resolve it" "yes|yes|yes|yes" \
  "$(has "+M2-EDIT" "${brief}")|$(lacks "<<<<<<<" "${brief}")|$(lacks MAIN3-ONLY "${brief}")|$(has "This story was stacked on p3, whose PRs have merged, and merging \`origin/main\` into your branch conflicts" "${brief}")"

# Refused before the builder closes: an env: name not set here, a legacy verify build (a role nothing
# starts now), and a trigger that is two words. Each leaves the builder open and writes no marker.
printf '%s\n' --- "status: ready" "kind: code" "env: [LADDER_TEST_UNSET_NAME]" --- "" "# e1" "" "**Done when:**" "- it holds" > "${P}/docs/stories/e1.md"
printf '%s\n' --- "status: ready" "kind: code" --- "" "# v1" "" "**Done when:**" "- it holds" > "${P}/docs/stories/v1.md"
for s in e1:code-sonnet:sonnet v1:verify:haiku; do
  IFS=: read -r slug role model <<< "${s}"
  "${GIT[@]}" -C "${P}" worktree add -q -b "story/${slug}" "${ROOT}/proj-wt/${slug}" origin/main
  printf '2026-10-01\t%s\t%s\tclaude\t%s\tmedium\tsess-%s\n' "${role}" "${slug}" "${model}" "${slug}" >> "${P}/.swarm/agents.tsv"
done
closes() { grep -c '^tab close' "${ROOT}/herdr.log" || true; }
c="$(closes)"
o1="$(run step-up e1 stalled)" || true; o2="$(run step-up v1 stalled)" || true; o3="$(run step-up s1 'stalled no-pr')" || true
check "an unset env: name, a legacy verify build and a two-word trigger are refused before anything closes" "yes|yes|yes|${c}|none" \
  "$(has "env: LADDER_TEST_UNSET_NAME is not set here" "${o1}")|$(has "v1's build is verify, which steps up as verify, a role nothing starts now; nothing was closed" "${o2}")|$(has "the trigger must be one of" "${o3}")|$(closes)|$(ls "${P}/.swarm/briefs/"*.step-up 2>/dev/null || echo none)"

# Refused before anything closes too: a stacked child held for review (held_by:), a build whose PR
# merged or is set to auto-merge (done, not stuck), and one whose PRs gh cannot list.
for slug in h1 a1 g1 n1; do
  printf '%s\n' --- "status: ready" "kind: code" --- "" "# ${slug}" "" "**Done when:**" "- it holds" > "${P}/docs/stories/${slug}.md"
  "${GIT[@]}" -C "${P}" worktree add -q -b "story/${slug}" "${ROOT}/proj-wt/${slug}" origin/main
  printf '2026-10-01\tcode-sonnet\t%s\tclaude\tsonnet\thigh\tsess-%s\n' "${slug}" "${slug}" >> "${P}/.swarm/agents.tsv"
done
printf '%s\n' --- "status: ready" "kind: code" "held_by: p1" --- "" "# h1" "" "**Done when:**" "- it holds" > "${P}/docs/stories/h1.md"
echo '[{"state":"OPEN","url":"https://github.com/o/proj/pull/7","autoMergeRequest":{"enabledAt":"2026-10-01T00:00:00Z"}}]' > "${ROOT}/prs-a1.json"
echo '[{"state":"MERGED","url":"https://github.com/o/proj/pull/8","autoMergeRequest":null}]' > "${ROOT}/prs-g1.json"
c="$(closes)"
o1="$(run step-up h1 stalled)" || true; o2="$(run step-up a1 ci-red-2)" || true; o3="$(run step-up g1 ci-red-2)" || true
touch "${ROOT}/ghfail"; o4="$(run step-up n1 stalled)" || true; rm "${ROOT}/ghfail"
check "a held stacked child, an auto-merging or merged PR, and PRs gh cannot list are refused before anything closes" "yes|yes|yes|yes|${c}|none" \
  "$(has "h1 is held until its parents merge (held_by:)" "${o1}")|$(has "a PR on story/a1 has merged or is set to auto-merge" "${o2}")|$(has "a PR on story/g1 has merged or is set to auto-merge" "${o3}")|$(has "could not list the PRs on story/n1" "${o4}")|$(closes)|$(ls "${P}/.swarm/briefs/"*.step-up 2>/dev/null || echo none)"

# A findings tell herdr sent, though the builder was not seen taking it up, is a round the builder
# had: after one ok tell and one such (f1, f3, f4: each outcome deliver_prompt logs once herdr sent
# it), the next is round 3 and steps it up. One herdr never sent (f2), or whose reply could not be
# read (f5), is not: after one ok tell and one of those, the next tell is round 2, and is sent.
echo "fix it" > "${ROOT}/f.md"
# f_story <slug> — a ready code story built on sonnet since 09:00, its builder idle in w:2.
f_story() {
  printf '%s\n' --- "status: ready" "kind: code" --- "" "# $1" "" "**Done when:**" "- it holds" > "${P}/docs/stories/$1.md"
  "${GIT[@]}" -C "${P}" worktree add -q -b "story/$1" "${ROOT}/proj-wt/$1" origin/main
  printf '2026-10-01\tcode-sonnet\t%s\tclaude\tsonnet\thigh\tsess-%s\n' "$1" "$1" >> "${P}/.swarm/agents.tsv"
  printf '2026-10-02T09:00:00Z\tstory\t%s\tw:2\tok\n2026-10-02T09:01:00Z\ttell:findings\t%s\tw:2\tok\n' "$1" "$1" >> "${P}/.swarm/events.tsv"
  echo "w:2 $1" > "${P}/.swarm/state/$1"; echo "$1 w:2" > "${ROOT}/agents"
  echo "[{\"sessionId\":\"sess-$1\",\"status\":\"idle\"}]" > "${CLAUDE_STUB_AGENTS}"
}
for f in "f1:the brief was not taken up: herdr sent it the brief twice, and herdr reads it idle with no turn finished since; see herdr agent read f1" \
  "f3:it may or may not have the brief: herdr sent it the brief once, then herdr gave no status for it; it was not sent again, see herdr agent read f3" \
  "f4:herdr sent it the brief once, then could not send it again (pane_not_found); see herdr agent read f4" \
  "f2:herdr did not send it the brief (agent_not_found); see herdr agent read f2" \
  "f5:it may or may not have the brief: herdr's reply to the brief could not be read once, then herdr gave no status for it; it was not sent again, see herdr agent read f5"; do
  slug="${f%%:*}"; f_story "${slug}"
  printf '2026-10-02T09:02:00Z\ttell:findings\t%s\tw:2\t%s: %s\n' "${slug}" "${slug}" "${f#*:}" >> "${P}/.swarm/events.tsv"
  run tell "${slug}" findings "${ROOT}/f.md" > "${ROOT}/tell-${slug}.out" || true
done
# stepped_f <slug> — "up" when the tell stepped <slug> up (one escalate line, and it says so), "told"
# when it sent the findings with no escalate line.
stepped_f() {
  if [[ "$(grep -c $'\tescalate\t'"$1"$'\t' "${P}/.swarm/events.tsv")" == 1 ]] && grep -q "findings round 3 of its build" "${ROOT}/tell-$1.out"; then echo up
  elif ! grep -q $'\tescalate\t'"$1"$'\t' "${P}/.swarm/events.tsv" && grep -q "told $1" "${ROOT}/tell-$1.out"; then echo told
  else echo "neither: $(cat "${ROOT}/tell-$1.out")"; fi
}
check "a findings tell herdr sent but not seen taken up counts toward round 3; one herdr never sent does not" "up|up|up|told|told" \
  "$(stepped_f f1)|$(stepped_f f3)|$(stepped_f f4)|$(stepped_f f2)|$(stepped_f f5)"
# f6, for real: herdr sends the findings twice and reads f6 idle with no turn finished each time. The
# tell fails saying they count as a round, to be sent again only if f6's pane shows they never
# arrived, and the next one steps f6 up. f7: herdr sends them once and then gives no status, so f7
# may or may not have them: they count as delivered and are not to be sent again.
f_story f6; touch "${ROOT}/promptsent"
out6="$(SWARM_SLEEP_SCALE=0.02 run tell f6 findings "${ROOT}/f.md")" || true; rm "${ROOT}/promptsent"
run tell f6 findings "${ROOT}/f.md" > "${ROOT}/tell-f6.out" || true
f_story f7; touch "${ROOT}/promptsent" "${ROOT}/getnone"
out7="$(SWARM_SLEEP_SCALE=0.02 run tell f7 findings "${ROOT}/f.md")" || true; rm "${ROOT}/promptsent" "${ROOT}/getnone"
run tell f7 findings "${ROOT}/f.md" > "${ROOT}/tell-f7.out" || true
check "a findings tell herdr sent but did not see taken up counts as a round, and says to resend only if its pane shows they never arrived" "yes|yes|up" \
  "$(has "the brief was not taken up: herdr sent it the brief twice" "${out6}")|$(has "the findings count as a round: read its pane (herdr agent read f6) and send them again only if it shows they never arrived" "${out6}")|$(stepped_f f6)"
check "a findings tell herdr sent that may or may not have arrived counts as delivered, not to be sent again" "yes|yes|yes|up" \
  "$(has "it may or may not have the brief: herdr sent it the brief once" "${out7}")|$(has "the findings count as delivered, a findings round of its build, so do not send them again" "${out7}")|$(lacks "read its pane" "${out7}")|$(stepped_f f7)"

# --- A sonnet -> opus -> fable chain of step-ups on s2, today. In outcomes the three builds are one
# attempt, the two replaced builds each have a close with cause step-up:<trigger>, and the Fable
# build's escalate column is the opus -> fable step, never the sonnet -> opus one. dash counts one
# escalation, and the Fable builder's row says where it came from and when, and is up since its
# step-up. s3 went up the same chain twice yesterday with no session logs, so every build starts at
# midnight: the step-ups still pair with their own builds, in order. s4 had a sonnet and an opus
# build that were attempts of their own, then a sonnet build stepped up to opus: the step-up takes
# the pair started on its day, never the older one. s5 did the same within one day, each build with a
# session log: the step-up takes the pair whose opus build started nearest it.
Q="${ROOT}/q"; mkdir -p "${Q}/.swarm/state" "${Q}/docs/stories" "${ROOT}/projects/q"; : > "${Q}/docs/stories/README.md"; git -C "${Q}" init -q
NOW="$(python3 -c 'import datetime; print(int(datetime.datetime(2026, 10, 10, 12).timestamp()))')"
for s in 1:09:00 2:10:00 3:11:00; do
  printf '{"type":"user","cwd":"%s/q-wt/s2","timestamp":"2026-10-10T%s:01Z"}\n' "${ROOT}" "${s#*:}" > "${ROOT}/projects/q/q${s%%:*}.jsonl"
done
printf '%s\n' $'2026-10-10\tcode-sonnet\ts2\tclaude\tsonnet\thigh\tq1' $'2026-10-10\tcode\ts2\tclaude\topus\thigh\tq2' \
  $'2026-10-10\tescalate\ts2\tclaude\tfable\txhigh\tq3' > "${Q}/.swarm/agents.tsv"
for _ in 1 2; do
  printf '%s\n' $'2026-10-09\tcode-sonnet\ts3\tclaude\tsonnet\thigh\t-' $'2026-10-09\tcode\ts3\tclaude\topus\thigh\t-' \
    $'2026-10-09\tescalate\ts3\tclaude\tfable\txhigh\t-' >> "${Q}/.swarm/agents.tsv"
done
printf '%s\n' $'2026-10-09T09:00:00Z\tescalate\ts3\tw:1\tok (stalled: sonnet -> opus)' $'2026-10-09T10:00:00Z\tescalate\ts3\tw:1\tok (stalled: opus -> fable)' \
  $'2026-10-09T13:00:00Z\tescalate\ts3\tw:1\tok (no-pr: sonnet -> opus)' $'2026-10-09T14:00:00Z\tescalate\ts3\tw:1\tok (no-pr: opus -> fable)' \
  $'2026-10-03T09:00:00Z\tescalate\ts4\tw:1\tok (stalled: sonnet -> opus)' \
  $'2026-10-04T13:00:30Z\tescalate\ts5\tw:1\tok (stalled: sonnet -> opus)' \
  $'2026-10-10T10:00:00Z\tescalate\ts2\tw:1\tok (no-pr: sonnet -> opus)' \
  $'2026-10-10T11:00:00Z\tescalate\ts2\tw:1\tok (findings-3: opus -> fable)' > "${Q}/.swarm/events.tsv"
printf '%s\n' $'2026-10-01\tcode-sonnet\ts4\tclaude\tsonnet\thigh\t-' $'2026-10-02\tcode\ts4\tclaude\topus\thigh\t-' \
  $'2026-10-03\tcode-sonnet\ts4\tclaude\tsonnet\thigh\t-' $'2026-10-03\tcode\ts4\tclaude\topus\thigh\t-' >> "${Q}/.swarm/agents.tsv"
for s in 51:08 52:09 53:12 54:13; do
  printf '{"type":"user","cwd":"%s/q-wt/s5","timestamp":"2026-10-04T%s:00:01Z"}\n' "${ROOT}" "${s#*:}" > "${ROOT}/projects/q/q${s%%:*}.jsonl"
done
printf '%s\n' $'2026-10-04\tcode-sonnet\ts5\tclaude\tsonnet\thigh\tq51' $'2026-10-04\tcode\ts5\tclaude\topus\thigh\tq52' \
  $'2026-10-04\tcode-sonnet\ts5\tclaude\tsonnet\thigh\tq53' $'2026-10-04\tcode\ts5\tclaude\topus\thigh\tq54' >> "${Q}/.swarm/agents.tsv"
qrun() { (cd "${Q}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${STUB_BIN}:${PATH}" bash "${SWARM}" "$@" 2>&1); }
qout="$(qrun outcomes | tail -n +2)"
check "outcomes counts the three rungs as one attempt and closes each replaced build, cause step-up:<trigger>" \
  "$(printf '%s\n' "code-sonnet	1	1	step-up:no-pr" "code	1	1	step-up:findings-3" "escalate	0	1	")" "$(awk -F'\t' '$2 == "s2"' <<< "${qout}" | cut -f5,13,17,23)"
check "outcomes' escalate column for the Fable build has the opus -> fable step's time" \
  "$(printf '%s\n' "code-sonnet	" "code	" "escalate	2026-10-10T11:00:00Z")" "$(awk -F'\t' '$2 == "s2"' <<< "${qout}" | cut -f5,24)"
check "two chains on one day with no session logs pair each step-up with its own builds: two attempts, one close per replaced build" \
  "$(printf '%s\n' "1	1	step-up:stalled" "1	1	step-up:stalled" "0	1	" "1	2	step-up:no-pr" "1	2	step-up:no-pr" "0	2	")" "$(awk -F'\t' '$2 == "s3"' <<< "${qout}" | cut -f13,17,23)"
check "a step-up takes the pair of builds started on its day, never an older pair that were attempts of their own" \
  "$(printf '%s\n' "0	1	" "0	2	" "1	3	step-up:stalled" "0	3	")" "$(awk -F'\t' '$2 == "s4"' <<< "${qout}" | cut -f13,17,23)"
check "within one day too, the step-up takes the pair whose new build started nearest it" \
  "$(printf '%s\n' "0	1	" "0	2	" "1	3	step-up:stalled" "0	3	")" "$(awk -F'\t' '$2 == "s5"' <<< "${qout}" | cut -f13,17,23)"
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
check "and it is up since its step-up, not since the first build" "yes" \
  "$(grep -qE '● s2 +up 1h00m' <<< "${qdash}" && echo yes || echo "no, got: ${qdash}")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
