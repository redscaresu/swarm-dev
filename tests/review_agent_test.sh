#!/usr/bin/env bash
# review_agent_test.sh — swarm.sh review-agent <slug> <PR>: it starts review-<slug> in the story's
# worktree with role review and returns at once, with a brief scoped to the story and its PR's head;
# several run side by side, and each is waited on alone. herdr is a stub on PATH whose agents stay
# working until the test marks them done (done <name>): its agent wait blocks until then, or its
# timeout. The claude stub lists their sessions busy until then, idle after. gh's PR head is the
# file ${ROOT}/head, and its check runs on any commit the file ${ROOT}/checks. review-agent --next runs
# a later round in review-<slug>'s own session, and --recheck passes a wording fix on its diff alone.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
# No .claude.json here, so require_trusted lets the agents start. A wait checks the session often.
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects" SWARM_STALL_POLL_MS=200
export CLAUDE_STUB_AGENTS="${ROOT}/claude.json"
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
GIT=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main)
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }

# herdr: logs every call; panes are w:<n>. agent start records "<name> <pane> <session>" in agents;
# agent list shows each working, or idle once done/<name> exists. agent wait <pane> blocks until its
# agent is done, or fails with a timeout error after --timeout ms.
cat > "${STUB_BIN}/herdr" <<EOF
#!/bin/sh
H="${ROOT}"
EOF
cat >> "${STUB_BIN}/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
next() { n=$(($(cat "$H/n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/n"; }
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;   # start_agent's require_herdr_version
  "tab create")   next; echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "pane split")   next; echo "{\"result\":{\"pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "agent start")  [ -e "$H/startfail" ] && { echo '{"error":{"code":"start_failed"}}' >&2; exit 1; }
                  echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/') $(echo "$*" | sed -n 's/.*--session-id \([^ ]*\).*/\1/p')" >> "$H/agents"
                  "$H/sessions" ;;
  "agent prompt") # prompt holds how the brief goes: fail or blocked (herdr surely sent nothing), unread
                  # (no reply read), unreadgone (unread, and the agent's pane gone), unreadunlisted
                  # (unread, and herdr's agent list failing from then on), or sent (sent, never taken up).
                  case "$(cat "$H/prompt" 2>/dev/null)" in
                    fail) echo '{"error":{"code":"server_unavailable"}}' >&2; exit 1 ;;
                    blocked) echo '{"error":{"code":"agent_blocked"}}' >&2; exit 1 ;;
                    unread) exit 1 ;;
                    unreadgone) [ -e "$H/quick" ] && echo "head: NEW-REVIEW" > "$(echo "$4" | grep -o '/[^ ]*/\.swarm/reviews/[a-z0-9-]*\.md' | head -1)"
                                awk -v p="$3" '$2 != p' "$H/agents" > "$H/agents.new" && mv "$H/agents.new" "$H/agents"; exit 1 ;;
                    unreadunlisted) touch "$H/listfail"; exit 1 ;;
                    unreadlogged) # no reply read, and the agent's session log has the brief
                                  sid=$(awk -v p="$3" '$2 == p { print $3 }' "$H/agents"); mkdir -p "$H/projects/p"
                                  python3 -c 'import json, sys; print(json.dumps({"type": "user", "message": {"content": sys.argv[1]}}))' "$4" >> "$H/projects/p/$sid.jsonl"
                                  exit 1 ;;
                    latelog) touch "$H/sentprompt"; printf '%s' "$4" > "$H/lastbrief"; exit 1 ;;   # no reply read; the log has the brief once herdr lists agents
                    sent) exit 0 ;;
                  esac
                  # With quick, the agent writes its findings file while its brief is still being delivered.
                  [ -e "$H/quick" ] && echo "head: NEW-REVIEW" > "$(echo "$4" | grep -o '/[^ ]*/\.swarm/reviews/[a-z0-9-]*\.md' | head -1)"
                  echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent wait")   name=$(awk -v p="$3" '$2 == p { print $1 }' "$H/agents")
                  ms=$(echo "$*" | sed -n 's/.*--timeout \([0-9]*\).*/\1/p'); ticks=$(( ${ms:-10000} / 100 ))
                  while [ ! -e "$H/done/$name" ]; do
                    [ "$ticks" -gt 0 ] || { echo '{"error":{"code":"timeout"}}' >&2; exit 1; }
                    ticks=$((ticks - 1)); sleep 0.1
                  done
                  echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent get")    [ -e "$H/getidle" ] && echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "pane close")   awk -v p="$3" '$2 != p' "$H/agents" > "$H/agents.new" && mv "$H/agents.new" "$H/agents" ;;
  "agent list")   [ -e "$H/listfail" ] && { echo '{"error":{"code":"server_unavailable"}}' >&2; exit 1; }
                  if [ -e "$H/sentprompt" ] && [ ! -e "$H/latelogged" ]; then
                    touch "$H/latelogged"; sid=$(awk '{ s = $3 } END { print s }' "$H/agents"); mkdir -p "$H/projects/p"
                    python3 -c 'import json, sys; print(json.dumps({"type": "user", "message": {"content": sys.argv[1]}}))' "$(cat "$H/lastbrief")" >> "$H/projects/p/$sid.jsonl"
                    # With authfail, the turn the brief started stopped on an expired login.
                    [ ! -e "$H/authfail" ] || echo '{"type":"assistant","error":"authentication_failed","message":{"content":[{"type":"text","text":"Login expired · Please run /login"}]}}' >> "$H/projects/p/$sid.jsonl"
                  fi
                  awk -v d="$H/done" 'BEGIN { printf "{\"result\":{\"agents\":[" }
                    { s = system("test -e " d "/" $1) == 0 ? "idle" : "working"
                      printf "%s{\"name\":\"%s\",\"agent_status\":\"%s\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, s, $2 }
                    END { print "]}}" }' "$H/agents" 2>/dev/null || echo '{"result":{"agents":[]}}' ;;
esac
EOF
# sessions: Claude Code's list, one entry per agent started, busy until done/<name> exists, waiting
# while waiting/<name> does, and left out (gone) while gone/<name> does.
cat > "${ROOT}/sessions" <<EOF
#!/bin/sh
awk -v d="${ROOT}" 'BEGIN { printf "[" }
  system("test -e " d "/gone/" \$1) == 0 { next }
  { s = system("test -e " d "/done/" \$1) == 0 ? "idle" : "busy"
    if (system("test -e " d "/waiting/" \$1) == 0) s = "waiting"
    printf "%s{\"sessionId\":\"%s\",\"status\":\"%s\"}", (k++ ? "," : ""), \$3, s }
  END { print "]" }' "${ROOT}/agents" > "${ROOT}/claude.json"
EOF
# With ghhang its api reads hang for 300s, and with ghfail they fail.
cat > "${STUB_BIN}/gh" <<EOF
#!/bin/sh
if [ "\$1" = api ]; then
  [ ! -e "${ROOT}/ghhang" ] || sleep 300
  [ ! -e "${ROOT}/ghfail" ] || { echo "HTTP 502: Bad Gateway" >&2; exit 1; }
fi
case "\$1 \$3" in
  "api "*/check-runs*) cat "${ROOT}/checks" ;;
  "api "*/status*) echo '{"total_count":0,"statuses":[]}' ;;
  *) cat "${ROOT}/head" ;;
esac
EOF
GREEN='{"total_count":1,"check_runs":[{"name":"test","status":"completed","conclusion":"success"}]}'
echo "${GREEN}" > "${ROOT}/checks"
chmod +x "${STUB_BIN}/herdr" "${STUB_BIN}/gh" "${ROOT}/sessions"; mkdir -p "${ROOT}/done" "${ROOT}/waiting" "${ROOT}/gone"; echo '[]' > "${ROOT}/claude.json"
done_agent() { touch "${ROOT}/done/$1"; echo "done $1" >> "${ROOT}/herdr.log"; "${ROOT}/sessions"; }

# A repo svc, built stories s1..s4 of epic e (each with a worktree at the PR's head), and a project
# whose board names it, with a brief.
"${GIT[@]}" init -q --bare "${ROOT}/svc.git"
"${GIT[@]}" clone -q "${ROOT}/svc.git" "${ROOT}/svc" 2>/dev/null
"${GIT[@]}" -C "${ROOT}/svc" commit -q --allow-empty -m init && "${GIT[@]}" -C "${ROOT}/svc" push -q origin main
git -C "${ROOT}/svc" rev-parse HEAD > "${ROOT}/head"; HEAD_SHA="$(cat "${ROOT}/head")"
p="${ROOT}/proj"; b="${p}/docs"
mkdir -p "${p}/.claude/swarm" "${b}/stories"; : > "${p}/.claude/swarm/config"
printf "A PROJECT RULE every agent reads.\n" > "${p}/.claude/swarm/brief.md"
for s in s1 s2 s3 s4; do
  printf '%s\n' --- "status: review" "kind: code" "epic: e" "repo: svc" "touches: [bin/${s}.sh:fn_${s}]" --- "" "# ${s}" "" \
    "**Done when:**" "- ${s} DONE-ONE holds" "- ${s} DONE-TWO holds" > "${b}/stories/${s}.md"
  "${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b "story/${s}" "${ROOT}/svc-wt/${s}" origin/main
done
PR=https://github.com/o/svc/pull/1
run() { (cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${STUB_BIN}:${PATH}" bash "${SWARM}" "$@" 2>&1); }
# start <slug> — review-agent <slug> in the background, its output in start-<slug>.out: back:<rc>
# once it returns, or blocked when it has not within 10s (it finishes once its agent is done), so a
# review-agent that waits on its agent fails a check instead of hanging the test.
start() {
  local pid rc=0
  run review-agent "$1" "${PR}" > "${ROOT}/start-$1.out" & pid=$!
  for _ in $(seq 100); do kill -0 "${pid}" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "${pid}" 2>/dev/null; then echo blocked; return; fi
  wait "${pid}" || rc=$?; echo "back:${rc}"
}
# started — the panes and agents herdr opened since the last mark line in its log.
started() { awk '/^mark$/ { n = 0; next } /^(agent start|tab create|pane split)/ { n++ } END { print n + 0 }' "${ROOT}/herdr.log" 2>/dev/null || echo 0; }
working() { # the agents herdr lists, with their status, but <except>
  PATH="${STUB_BIN}:${PATH}" herdr agent list | python3 -c 'import json, sys
print("|".join(a["name"] + " " + a["agent_status"] for a in json.load(sys.stdin)["result"]["agents"] if a["name"] != sys.argv[1]))' "${1:-}"
}

# --- Refusals that start nothing. A story named review-s1 would share s1's review agent's name; no
# review agent runs yet, so only the refusal can stop it. A worktree not at the PR's head is not
# the commit the PR asks to review.
printf '%s\n' --- "status: ready" "kind: code" --- > "${b}/stories/review-s1.md"
check "a board with a story named review-s1 makes review-agent s1 fail with nothing started" "1|0" \
  "$(set +e; run review-agent s1 "${PR}" >/dev/null; echo "$?")|$(started)"
rm "${b}/stories/review-s1.md"
echo 0123456789abcdef0123456789abcdef01234567 > "${ROOT}/head"
check "a PR head the worktree is not at makes review-agent s1 fail with nothing started" "1|yes|0" \
  "$(set +e; o="$(run review-agent s1 "${PR}")"; echo "$?|$(has "not the PR's head 0123456789abcdef" "${o}")")|$(started)"
echo "${HEAD_SHA}" > "${ROOT}/head"
# Uncommitted work in the worktree would be reviewed as if it were the head.
echo wip > "${ROOT}/svc-wt/s1/wip.txt"
check "a worktree with uncommitted changes makes review-agent s1 fail with nothing started" "1|yes|0" \
  "$(set +e; o="$(run review-agent s1 "${PR}")"; echo "$?|$(has "has uncommitted changes" "${o}")")|$(started)"
rm "${ROOT}/svc-wt/s1/wip.txt"
check "no refused start records a reviewed head for watch and next" "no" "$([[ -e "${p}/.swarm/reviews/s1.head" ]] && echo yes || echo no)"

# --- One review agent: started in s1's worktree with role review, its brief scoped to s1.
check "review-agent s1 returns at once, its agent still working" "back:0" "$(start s1)"
out="$(cat "${ROOT}/start-s1.out")"
check "review-agent s1 starts review-s1 in s1's worktree, with review's model and effort" "yes|yes|yes" \
  "$(has "tab create --workspace w --cwd ${ROOT}/svc-wt/s1 --label e" "$(cat "${ROOT}/herdr.log")")|$(has "agent start review-s1 " "$(cat "${ROOT}/herdr.log")")|$(has "review-s1 w:1 claude:opus:high" "${out}")"
check "agents.tsv records review-s1 with role review" "review" "$(awk -F'\t' '$3 == "review-s1" { print $2 }' "${p}/.swarm/agents.tsv")"
brief="$(cat "${p}/.swarm/briefs/review-s1.md")"
check "the brief holds s1's touches, each Done when item, SWARM_STORY=s1, /code-review <PR>, not a finding and the absolute reviews file" \
  "yes|yes|yes|yes|yes|yes|yes" \
  "$(has "bin/s1.sh:fn_s1" "${brief}")|$(has "- s1 DONE-ONE holds" "${brief}")|$(has "- s1 DONE-TWO holds" "${brief}")|$(has "SWARM_STORY=s1 " "${brief}")|$(has "/code-review ${PR}" "${brief}")|$(has "not a finding" "${brief}")|$(has "${p}/.swarm/reviews/s1.md" "${brief}")"
check "the brief names the head it reviews, lists out-of-scope points apart, and carries the project's brief" "yes|yes|yes" \
  "$(has "at its head ${HEAD_SHA}" "${brief}")|$(has '## Out of scope' "${brief}")|$(has "A PROJECT RULE every agent reads." "${brief}")"
check "the brief has the agent write the file, starting with the head reviewed and any codex skip, and the reviews directory exists" "yes|yes|yes" \
  "$(has "Its first line is \`head: ${HEAD_SHA}\`; when codex was skipped, its second is \`codex skipped: <why>\`." "${brief}")|$(has "prints nothing" "${brief}")|$([[ -d "${p}/.swarm/reviews" ]] && echo yes || echo no)"
check "the brief says to wait for codex-review to exit, never to stop early on a usage limit" "yes|no" \
  "$(has "Wait for it to exit, and act on what it prints last" "$(tr -s '[:space:]' ' ' <<< "${brief}")")|$(grep -q "do not wait" <<< "${brief}" && echo yes || echo no)"
# The green step comes before the review: wait-pr, then the triage green_rule asks of a conductor.
# Each swarm.sh call names the project: the agent runs in the story's worktree, outside it.
flat="$(tr -s '[:space:]' ' ' <<< "${brief}")"; sw="SWARM_PROJECT=${p} ${SWARM}"
check "the brief waits for green with wait-pr on the PR, naming the project, before the review, and again after each push" "yes|yes|yes" \
  "$(has "Before you review, wait for the PR's checks to go green. Run \`${sw} wait-pr ${PR}\` in the background and wait for it to exit, never a loop of your own" "${flat}")|$(awk '/ wait-pr / && !w { w = NR } / codex-review / && !c { c = NR } END { print (w && c && w < c) ? "yes" : "no" }' <<< "${brief}")|$(has "After each nudge, wait for the builder the same way, then wait for green again on the head it pushed." "${flat}")"
check "the brief triages check-run notes and code-scanning alerts before the head counts green, as green_rule does" "yes|yes|yes|yes" \
  "$(has "Exit 0: the head counts green only once you have triaged what \`${sw} findings svc 1\` prints: the notes on every check run, whatever its conclusion, and the PR's open code-scanning alerts." "${flat}")|$(has "Nudge the builder with each real one. Rebut the rest with a reason in the PR (\`gh pr comment ${PR} --body" "${flat}")|$(has "Never dismiss an alert." "${flat}")|$(has "\`${sw} tell s1 nudge ${p}/.swarm/reviews/s1.nudge.md\` (never findings, which count as a review round)" "${flat}")"
check "a red head or a conflict is a nudge naming the check or the base, and with the ladder off no step-up is named" "yes|0" \
  "$(has "Exit 1 (a red check) or a conflict: nudge the builder, naming the red check or the base to merge in." "${flat}")|$(grep -c 'stepped up' <<< "${brief}" || true)"
# The green step ends: two nudges or two red heads at most, then a findings file the conductor's rules
# send to the builder (a file with no ## Findings is a review started again, for ever on a PR that
# stays red); and each nudge file is removed before the Write tool writes it (an earlier round's
# survives, and the tool refuses to overwrite a file the session has not read).
check "the green step is bounded, its not-green file is a findings file with the red check as its one item, and the nudge file is removed before each write" "yes|yes|yes" \
  "$(has "The green step is bounded: at most two nudges, and at most two heads that wait-pr calls red." "${flat}")|$(has "The not-green file is ${p}/.swarm/reviews/s1.md, written with the Write tool: \`head: ${HEAD_SHA}\`, then a \`## Findings\` heading with one line for the builder, \`wait-pr: not green: <the red check, the conflict, or what wait-pr printed last>\`, then a \`## Out of scope\` heading with \`none\`. The conductor sends it to the builder as a findings round, as any finding." "${flat}")|$(has "first remove any earlier nudge file (\`rm -f ${p}/.swarm/reviews/s1.nudge.md\`: the Write tool refuses to overwrite a file this session has not read), then write ${p}/.swarm/reviews/s1.nudge.md with the Write tool" "${flat}")"
check "a started review agent records the head it reviews, so watch and next do not call the PR queued" "${HEAD_SHA}" \
  "$(cat "${p}/.swarm/reviews/s1.head")"
check "events.tsv gains a review-agent line whose target is s1 (the newest, after the refusals')" "s1	ok" \
  "$(awk -F'\t' '$2 == "review-agent" { l = $3 "\t" $5 } END { print l }' "${p}/.swarm/events.tsv")"

# --- A refused second start leaves the findings file and the brief as they were.
echo "head: ${HEAD_SHA} FINDINGS-KEPT" > "${p}/.swarm/reviews/s1.md"; echo BRIEF-KEPT >> "${p}/.swarm/briefs/review-s1.md"
echo mark >> "${ROOT}/herdr.log"
check "with review-s1 still working, review-agent s1 fails, starts nothing, and keeps its findings file and brief" "1|0|yes|yes" \
  "$(set +e; run review-agent s1 "${PR}" >/dev/null; echo "$?")|$(started)|$(has FINDINGS-KEPT "$(cat "${p}/.swarm/reviews/s1.md")")|$(has BRIEF-KEPT "$(cat "${p}/.swarm/briefs/review-s1.md")")"

# --- Four at once: each start returns while every agent still works (herdr's wait would block),
# and each is waited on alone.
# s2's build stacked on s1 (#215's stacked event, then its story line).
printf '%s\t%s\t%s\t%s\t%s\n' 2026-10-16T10:00:00Z stacked s2 - "ok (on s1)" 2026-10-16T10:01:00Z story s2 - ok >> "${p}/.swarm/events.tsv"
# s3's builder was sent findings once since its build started (one before it, from an older build,
# does not count), then stepped up, which keeps its PR: its review is round 2. s4 is on round 2 too,
# with no step-up.
printf '%s\t%s\t%s\t%s\t%s\n' 2026-10-16T09:00:00Z tell:findings s3 - ok 2026-10-16T10:00:00Z story s3 - ok \
  2026-10-16T10:30:00Z tell:findings s3 - ok 2026-10-16T10:40:00Z escalate s3 - ok \
  2026-10-16T10:00:00Z story s4 - ok 2026-10-16T10:30:00Z tell:findings s4 - ok >> "${p}/.swarm/events.tsv"
back=""; echo "head: STALE" > "${p}/.swarm/reviews/s2.md"
# With the ladder on, the briefs say what a step-up printed by wait-pr means.
echo "escalate_ladder = sonnet,opus" > "${p}/.claude/swarm/config"
for s in s2 s3 s4; do back+="${s}:$(start "${s}") "; done
: > "${p}/.claude/swarm/config"
check "a start removes the story's findings file from an earlier head, and leaves no copy aside, so its wait cannot end on it" "no|no" \
  "$([[ -e "${p}/.swarm/reviews/s2.md" ]] && echo yes || echo no)|$([[ -e "${p}/.swarm/reviews/s2.md.prev" ]] && echo yes || echo no)"
check "review-agent s2 to s4 each return within 10s while no review is done" "s2:back:0 s3:back:0 s4:back:0 " "${back}"
check "a stacked story's brief leaves its parents' code out; another's says nothing of stacking" "yes|yes|0" \
  "$(has "This story is stacked on s1: their branches (origin/story/s1) are in its diff against origin/main" "$(cat "${p}/.swarm/briefs/review-s2.md")")|$(has "it is neither a finding nor out of scope" "$(cat "${p}/.swarm/briefs/review-s2.md")")|$(grep -c stacked "${p}/.swarm/briefs/review-s3.md" || true)"
r1="$(cat "${p}/.swarm/briefs/review-s1.md")"; r3="$(cat "${p}/.swarm/briefs/review-s3.md")"; r4="$(cat "${p}/.swarm/briefs/review-s4.md")"
check "round 1's brief asks for codex and /code-review" "yes|yes|yes" \
  "$(has " codex-review " "${r1}")|$(has "review round 1 of the story" "${r1}")|$(has "then run \`/code-review ${PR}\`" "${r1}")"
check "a round after a step-up is still round 2, and asks for codex alone" "yes|yes|yes|no" \
  "$(has " codex-review " "${r3}")|$(has "review round 2 of the story" "${r3}")|$(has "run codex alone, not \`/code-review\`" "${r3}")|$(grep -qF "/code-review ${PR}" <<< "${r3}" && echo yes || echo no)"
# A step-up from wait-pr leaves no head to review (stop with head moved:); one that failed after the
# builder closed leaves no builder to nudge (stop with that line as the one finding, which tell refuses).
check "with escalate_ladder set, the brief says a stepped-up build gets no nudge and ends the review, and a step-up failed partway ends it with that line as its finding" "yes|yes" \
  "$(has "When it also prints \`stepped up: s4\`, the build's red heads handed it to the next model on the escalation ladder, and ${HEAD_SHA} is gone: send no nudge; write ${p}/.swarm/reviews/s4.md with the Write tool holding two lines, \`head: ${HEAD_SHA}\` and \`head moved: <that stepped up: line>\`, then stop." "$(tr -s '[:space:]' ' ' <<< "${r4}")")|$(has "When it prints \`step-up failed: s4\` instead, the builder was closed and no new one runs, so no nudge can reach it: write ${p}/.swarm/reviews/s4.md with the Write tool holding \`head: ${HEAD_SHA}\`, a \`## Findings\` heading with that \`step-up failed:\` line as its one item, and a \`## Out of scope\` heading with \`none\`, then stop." "$(tr -s '[:space:]' ' ' <<< "${r4}")")"
check "round 2 asks for codex only" "yes|yes|yes|no" \
  "$(has " codex-review " "${r4}")|$(has "review round 2 of the story" "${r4}")|$(has "run codex alone, not \`/code-review\`" "${r4}")|$(grep -qF "/code-review ${PR}" <<< "${r4}" && echo yes || echo no)"
check "herdr lists review-s1 to review-s4 working at once" "review-s1 working|review-s2 working|review-s3 working|review-s4 working" "$(working)"
# done_review <slug> — the agent writes its findings file, then goes idle.
done_review() { echo "head: ${HEAD_SHA}" > "${p}/.swarm/reviews/$1.md"; done_agent "review-$1"; }
done_review s3
check "the stub's log shows four starts before any review is marked done" "4" \
  "$(awk '/^done / { exit } /^agent start review-s[1-4] / { n++ } END { print n + 0 }' "${ROOT}/herdr.log")"
check "with review-s3 done first, wait review-s3 returns idle" "idle" "$(run wait review-s3 5000)"
check "while the other three still work: a wait on review-s1 times out busy" "busy|1" \
  "$(set +e; o="$(run wait review-s1 600 2>/dev/null)"; echo "${o}|$?")"
check "and herdr still lists them working" "review-s1 working|review-s2 working|review-s4 working" "$(working review-s3)"
for s in s1 s2 s3 s4; do
  check "review-${s}'s brief names only its own story's reviews file" "${p}/.swarm/reviews/${s}.md" \
    "$(grep -o "${p}/.swarm/reviews/[a-z0-9-]*\.md" "${p}/.swarm/briefs/review-${s}.md" | sort -u | paste -sd' ' -)"
done
# An idle review agent with no findings file has not finished (its codex runs in the background):
# wait holds on until the file is written or the timeout.
done_agent review-s4
check "an idle review-s4 with no findings file is still waited on, to the timeout, and then fails" "yes|yes|1" \
  "$(t0=${SECONDS}; o="$(SWARM_CONDUCTOR_POLL=1 run wait review-s4 2500)"; rc=$?; echo "$(has "idle with no findings file" "${o}")|$( (( SECONDS - t0 >= 2 )) && echo yes || echo no)|${rc}")"
echo mark >> "${ROOT}/herdr.log"
check "and review-agent s4 again refuses to replace it while it has no findings file, starting nothing" "1|yes|0" \
  "$(set +e; o="$(run review-agent s4 "${PR}")"; echo "$?|$(has "review-s4 is still reviewing" "${o}")")|$(started)"
for s in s1 s2; do done_review "${s}"; done
wait

# fast_wait <name> — wait on <name> (10s timeout, polling each second): its state, and fast when it
# returned within 5s, well before a wait held to the timeout would (a wait costs nearly 2s on a slow
# machine).
fast_wait() {
  local t0=${SECONDS} o
  o="$(SWARM_CONDUCTOR_POLL=1 run wait "$1" 10000)"
  echo "${o}|$( (( SECONDS - t0 < 5 )) && echo fast || echo slow)"
}
# --- A slug long enough that review-<slug> is cut at 32 characters: its wait still finds the file.
sl=s5-a-long-slug-past-the-name-cut
sed "s/s4/${sl}/g" "${b}/stories/s4.md" > "${b}/stories/${sl}.md"
"${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b "story/${sl}" "${ROOT}/svc-wt/${sl}" origin/main
check "review-agent on a long slug returns at once" "back:0" "$(start "${sl}")"
cut="$(run _name "review-${sl}")"
echo "head: ${HEAD_SHA}" > "${p}/.swarm/reviews/${sl}.md"; done_agent "${cut}"
check "its name is cut, and wait review-<long slug> returns once the full slug's file exists" "yes|idle|fast" \
  "$([[ ${#cut} -eq 32 && "review-${sl}" != "${cut}" ]] && echo yes || echo no)|$(fast_wait "review-${sl}")"
# --- A builder whose slug starts review- is waited on as a builder, not held for a findings file.
echo brief > "${ROOT}/builder-brief.md"
run agent e review-s9 "${ROOT}/svc" code "${ROOT}/builder-brief.md" >/dev/null || { echo "FAIL agent review-s9 failed"; exit 1; }
done_agent review-s9
check "a code agent named review-s9, idle, is not held for a findings file" "idle|fast" "$(fast_wait review-s9)"

# --- A start herdr refuses leaves the last review's findings file as it was.
sed "s/s4/s6/g" "${b}/stories/s4.md" > "${b}/stories/s6.md"
"${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b story/s6 "${ROOT}/svc-wt/s6" origin/main
echo "head: OLD-REVIEW" > "${p}/.swarm/reviews/s6.md"; touch "${ROOT}/startfail"
check "when herdr cannot start review-s6, review-agent fails and s6's last findings file is put back" "1|head: OLD-REVIEW|no" \
  "$(set +e; run review-agent s6 "${PR}" >/dev/null; echo "$?")|$(cat "${p}/.swarm/reviews/s6.md")|$([[ -e "${p}/.swarm/reviews/s6.md.prev" ]] && echo yes || echo no)"
rm "${ROOT}/startfail"
# --- A start that fails once review-<slug>'s pane exists. herdr surely sent nothing: the pane is
# closed, the last review put back, and a new start is not refused as still reviewing.
for s in s8 s10 s11; do
  sed "s/s4/${s}/g" "${b}/stories/s4.md" > "${b}/stories/${s}.md"
  "${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b "story/${s}" "${ROOT}/svc-wt/${s}" origin/main
  echo "head: OLD-REVIEW" > "${p}/.swarm/reviews/${s}.md"
done
echo fail > "${ROOT}/prompt"; touch "${ROOT}/done/review-s8"   # a new agent with no brief is idle
check "when herdr sends review-s8 no brief, review-agent closes its pane, fails and puts s8's last findings back" "1|yes|head: OLD-REVIEW|no|no|" \
  "$(set +e; o="$(run review-agent s8 "${PR}")"; echo "$?|$(has "is closed)" "${o}")")|$(cat "${p}/.swarm/reviews/s8.md")|$([[ -e "${p}/.swarm/reviews/s8.md.prev" ]] && echo yes || echo no)|$([[ -e "${p}/.swarm/reviews/s8.head" ]] && echo yes || echo no)|$(working | tr '|' '\n' | grep review-s8 || true)"
rm "${ROOT}/prompt"
check "and review-agent s8 again starts it" "back:0|${HEAD_SHA}" "$(start s8)|$(cat "${p}/.swarm/reviews/s8.head" 2>/dev/null)"
# The brief may have gone out: herdr's reply could not be read, and the agent reads working. It runs,
# so the last review stays aside, its head goes on record, and its wait holds for a new file.
echo unread > "${ROOT}/prompt"
check "when review-s10's brief may or may not have gone out and it works, review-agent exits 0, says it runs, and the old findings stay aside" "0|yes|no|head: OLD-REVIEW|${HEAD_SHA}" \
  "$(set +e; o="$(SWARM_SLEEP_SCALE=0.02 run review-agent s10 "${PR}")"; echo "$?|$(has "the agent is running" "${o}")")|$([[ -e "${p}/.swarm/reviews/s10.md" ]] && echo yes || echo no)|$(cat "${p}/.swarm/reviews/s10.md.prev")|$(cat "${p}/.swarm/reviews/s10.head" 2>/dev/null)"
# Sent twice and not taken up, the agent idle: it may have the brief, so the old findings stay aside,
# but review-agent fails, with no head on record, and says how to clear the pane.
echo sent > "${ROOT}/prompt"; touch "${ROOT}/getidle" "${ROOT}/done/review-s11"
check "when review-s11's brief was not taken up after 2 tries, review-agent fails, says to close the pane, keeps the old findings aside and records no head" "1|yes|yes|no|head: OLD-REVIEW|no" \
  "$(set +e; o="$(SWARM_SLEEP_SCALE=0.02 run review-agent s11 "${PR}")"; echo "$?|$(has "may have its brief" "${o}")|$(has "herdr pane close" "${o}")")|$([[ -e "${p}/.swarm/reviews/s11.md" ]] && echo yes || echo no)|$(cat "${p}/.swarm/reviews/s11.md.prev")|$([[ -e "${p}/.swarm/reviews/s11.head" ]] && echo yes || echo no)"
# A .prev an earlier unclear start left, with no findings file now, is the last real review: a failed
# start neither puts it back nor removes it.
sed "s/s4/s12/g" "${b}/stories/s4.md" > "${b}/stories/s12.md"
"${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b story/s12 "${ROOT}/svc-wt/s12" origin/main
echo "head: OLDER-REVIEW" > "${p}/.swarm/reviews/s12.md.prev"; echo fail > "${ROOT}/prompt"; touch "${ROOT}/done/review-s12"
check "a failed start of review-s12 leaves an earlier start's findings aside, neither put back nor removed, and says so" "1|yes|no|head: OLDER-REVIEW" \
  "$(set +e; o="$(run review-agent s12 "${PR}")"; echo "$?|$(has "the last review is kept aside in ${p}/.swarm/reviews/s12.md.prev" "${o}")")|$([[ -e "${p}/.swarm/reviews/s12.md" ]] && echo yes || echo no)|$(cat "${p}/.swarm/reviews/s12.md.prev" 2>/dev/null)"
rm "${ROOT}/prompt" "${ROOT}/getidle"
# With no pane left, an error that says the brief may have gone out still fails and puts the file back.
sed "s/s4/s13/g" "${b}/stories/s4.md" > "${b}/stories/s13.md"
"${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b story/s13 "${ROOT}/svc-wt/s13" origin/main
echo "head: OLD-REVIEW" > "${p}/.swarm/reviews/s13.md"; echo unreadgone > "${ROOT}/prompt"
check "when review-s13's brief may have gone out but its pane is gone, review-agent fails and puts the findings back" "1|head: OLD-REVIEW|no" \
  "$(set +e; SWARM_SLEEP_SCALE=0.02 run review-agent s13 "${PR}" >/dev/null; echo "$?")|$(cat "${p}/.swarm/reviews/s13.md")|$([[ -e "${p}/.swarm/reviews/s13.md.prev" ]] && echo yes || echo no)"
rm "${ROOT}/prompt"
# A definite no-send to an agent waiting on a startup question is no review: its pane is closed, and
# the findings go back. So is an unclear start whose session is gone.
for s in s14 s15; do
  sed "s/s4/${s}/g" "${b}/stories/s4.md" > "${b}/stories/${s}.md"
  "${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b "story/${s}" "${ROOT}/svc-wt/${s}" origin/main
  echo "head: OLD-REVIEW" > "${p}/.swarm/reviews/${s}.md"
done
echo blocked > "${ROOT}/prompt"; touch "${ROOT}/waiting/review-s14"
check "when herdr sends review-s14 no brief while it waits on a question, review-agent closes it, fails, puts the findings back and records no head" "1|yes|head: OLD-REVIEW|no|no" \
  "$(set +e; o="$(run review-agent s14 "${PR}")"; echo "$?|$(has "is closed)" "${o}")")|$(cat "${p}/.swarm/reviews/s14.md")|$([[ -e "${p}/.swarm/reviews/s14.md.prev" ]] && echo yes || echo no)|$([[ -e "${p}/.swarm/reviews/s14.head" ]] && echo yes || echo no)"
echo unread > "${ROOT}/prompt"; touch "${ROOT}/gone/review-s15"
check "when review-s15's start is unclear but its session is gone, review-agent closes it, fails and puts the findings back" "1|yes|head: OLD-REVIEW|no" \
  "$(set +e; o="$(SWARM_SLEEP_SCALE=0.02 run review-agent s15 "${PR}")"; echo "$?|$(has "is closed)" "${o}")")|$(cat "${p}/.swarm/reviews/s15.md")|$([[ -e "${p}/.swarm/reviews/s15.head" ]] && echo yes || echo no)"
rm "${ROOT}/prompt"
# An unclear start whose pane is gone, after its agent wrote a review of the new head: that review
# stays, and the old one stays aside.
for s in s16 s17; do
  sed "s/s4/${s}/g" "${b}/stories/s4.md" > "${b}/stories/${s}.md"
  "${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b "story/${s}" "${ROOT}/svc-wt/${s}" origin/main
  echo "head: OLD-REVIEW" > "${p}/.swarm/reviews/${s}.md"
done
echo unreadgone > "${ROOT}/prompt"; touch "${ROOT}/quick"
check "when review-s16's pane is gone after it wrote a new review, review-agent fails, keeps the new review, and the old one stays aside" "1|head: NEW-REVIEW|head: OLD-REVIEW" \
  "$(set +e; SWARM_SLEEP_SCALE=0.02 run review-agent s16 "${PR}" >/dev/null; echo "$?")|$(cat "${p}/.swarm/reviews/s16.md")|$(cat "${p}/.swarm/reviews/s16.md.prev" 2>/dev/null)"
rm "${ROOT}/quick"
# An unclear start while herdr cannot list its agents: no answer is not no pane, so the old review
# stays aside and the state is said to be unknown.
echo unreadunlisted > "${ROOT}/prompt"
check "when herdr cannot list agents after review-s17's unclear start, review-agent fails, says its state is unknown, and keeps the old review aside" "1|yes|no|head: OLD-REVIEW" \
  "$(set +e; o="$(SWARM_SLEEP_SCALE=0.02 run review-agent s17 "${PR}")"; echo "$?|$(has "its state is unknown" "${o}")")|$([[ -e "${p}/.swarm/reviews/s17.md" ]] && echo yes || echo no)|$(cat "${p}/.swarm/reviews/s17.md.prev" 2>/dev/null)"
rm -f "${ROOT}/prompt" "${ROOT}/listfail"

# An unclear start whose agent took the brief, though herdr never said so: the session's log has it,
# and the agent sits idle (its codex runs). review-agent returns 0 and records the head. s18's session
# is not listed (gone) while the brief goes, which is the old start reading's blind spot; s19's log
# gets the brief only after the start's reads, so only the failure's own check finds it.
for s in s18 s19 s20 s21; do
  sed "s/s4/${s}/g" "${b}/stories/s4.md" > "${b}/stories/${s}.md"
  "${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b "story/${s}" "${ROOT}/svc-wt/${s}" origin/main
  echo "head: OLD-REVIEW" > "${p}/.swarm/reviews/${s}.md"
done
echo unreadlogged > "${ROOT}/prompt"; touch "${ROOT}/getidle" "${ROOT}/done/review-s18" "${ROOT}/gone/review-s18"
check "when review-s18's session took the brief (it is in the log) though herdr read no reply, review-agent exits 0, closes nothing, records the head and drops the old findings" "0|no|${HEAD_SHA}|no" \
  "$(set +e; o="$(SWARM_SLEEP_SCALE=0.02 run review-agent s18 "${PR}")"; echo "$?|$(grep -qF 'is closed)' <<< "${o}" && echo yes || echo no)")|$(cat "${p}/.swarm/reviews/s18.head" 2>/dev/null)|$([[ -e "${p}/.swarm/reviews/s18.md" ]] && echo yes || echo no)"
echo latelog > "${ROOT}/prompt"; touch "${ROOT}/done/review-s19"
check "when review-s19 sits idle with the brief in its session log after the start's reads, review-agent exits 0 and records the head" "0|yes|${HEAD_SHA}" \
  "$(set +e; o="$(SWARM_SLEEP_SCALE=0.02 run review-agent s19 "${PR}")"; echo "$?|$(has "the agent is running" "${o}")")|$(cat "${p}/.swarm/reviews/s19.head" 2>/dev/null)"
# The same idle agent whose log has no brief did not take it: that start still fails.
rm -f "${ROOT}/sentprompt" "${ROOT}/latelogged"; echo unread > "${ROOT}/prompt"; touch "${ROOT}/done/review-s20"
check "when review-s20 sits idle and its log has no brief, review-agent still fails, and records no head" "1|yes|no" \
  "$(set +e; o="$(SWARM_SLEEP_SCALE=0.02 run review-agent s20 "${PR}")"; echo "$?|$(has "may have its brief" "${o}")")|$([[ -e "${p}/.swarm/reviews/s20.head" ]] && echo yes || echo no)"
# An idle agent that took the brief and then stopped on an expired login runs nothing: that start fails.
echo latelog > "${ROOT}/prompt"; touch "${ROOT}/authfail" "${ROOT}/done/review-s21"
check "when review-s21 took the brief and stopped on an expired login, review-agent fails, says so, and records no head" "1|yes|no" \
  "$(set +e; o="$(SWARM_SLEEP_SCALE=0.02 run review-agent s21 "${PR}")"; echo "$?|$(has "took its brief and stopped on an expired login" "${o}")")|$([[ -e "${p}/.swarm/reviews/s21.head" ]] && echo yes || echo no)"
rm -f "${ROOT}/sentprompt" "${ROOT}/latelogged" "${ROOT}/authfail"
rm -f "${ROOT}/prompt" "${ROOT}/getidle"

# --- An agent that writes its findings before review-agent returns keeps them: only the last
# review's file is removed.
sed "s/s4/s7/g" "${b}/stories/s4.md" > "${b}/stories/s7.md"
"${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b story/s7 "${ROOT}/svc-wt/s7" origin/main
echo "head: OLD-REVIEW" > "${p}/.swarm/reviews/s7.md"; touch "${ROOT}/quick"
check "a review written while its brief is delivered survives the start, and the old one is gone" "back:0|head: NEW-REVIEW|no" \
  "$(start s7)|$(cat "${p}/.swarm/reviews/s7.md" 2>/dev/null)|$([[ -e "${p}/.swarm/reviews/s7.md.prev" ]] && echo yes || echo no)"
rm "${ROOT}/quick"

# --- review-agent --next: review-n1's next round, run from its own pane in the same session.
# reviews_now — every file under .swarm/reviews with its checksum, so a refusal is seen to change none.
reviews_now() { (cd "${p}/.swarm/reviews" && cksum -- * | sort); }
for s in n1 n2; do
  sed "s/s4/${s}/g" "${b}/stories/s4.md" > "${b}/stories/${s}.md"
  "${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b "story/${s}" "${ROOT}/svc-wt/${s}" origin/main
done
# Started in the foreground, so its pane is on record (and its files written) before the checks below.
printf '%s\t%s\t%s\t%s\t%s\n' 2026-10-16T11:00:00Z story n1 - ok >> "${p}/.swarm/events.tsv"
check "review-agent n1 starts review-n1 for round 1" "0" "$(set +e; run review-agent n1 "${PR}" >/dev/null; echo "$?")"
NP="$(awk '$1 == "review-n1" { p = $2 } END { print p }' "${ROOT}/agents")"
check "review-n1 has a pane on record" "yes" "$([[ -n "${NP}" ]] && echo yes || echo no)"
echo "head: ${HEAD_SHA} ROUND-ONE" > "${p}/.swarm/reviews/n1.md"; done_agent review-n1
echo STALE > "${p}/.swarm/reviews/n1.head"
echo mark >> "${ROOT}/herdr.log"; was="$(reviews_now)"
check "--next before any findings tell refuses, as round 1 has started, and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(HERDR_PANE_ID="${NP}" run review-agent --next n1 "${PR}")"; echo "$?|$(has "round 1 of n1 has started already" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
printf '%s\t%s\t%s\t%s\t%s\n' 2026-10-16T11:30:00Z tell:findings n1 - ok >> "${p}/.swarm/events.tsv"
check "--next from another pane refuses, naming review-n1's pane, and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(HERDR_PANE_ID=w:999 run review-agent --next n1 "${PR}")"; echo "$?|$(has "only review-n1, in its pane ${NP}" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
check "--next with no review-n2 listed refuses and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(HERDR_PANE_ID="${NP}" run review-agent --next n2 "${PR}")"; echo "$?|$(has "herdr lists no review-n2" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
echo 0123456789abcdef0123456789abcdef01234567 > "${ROOT}/head"
check "--next with the worktree off the PR's head refuses and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(HERDR_PANE_ID="${NP}" run review-agent --next n1 "${PR}")"; echo "$?|$(has "not the PR's head 0123456789abcdef" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
echo "${HEAD_SHA}" > "${ROOT}/head"; echo wip > "${ROOT}/svc-wt/n1/wip.txt"
check "--next with uncommitted work refuses and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(HERDR_PANE_ID="${NP}" run review-agent --next n1 "${PR}")"; echo "$?|$(has "has uncommitted changes" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
rm "${ROOT}/svc-wt/n1/wip.txt"
o="$(HERDR_PANE_ID="${NP}" run review-agent --next n1 "${PR}")" || echo "FAIL review-agent --next n1 exited non-zero: ${o}"
check "after one ok findings tell, --next from review-n1's pane prints round 2 and the codex-alone instruction" "yes|yes" \
  "$(has "Review round 2 of story n1" "${o}")|$(has "This is review round 2 of the story: run codex alone, not \`/code-review\`" "${o}")"
check "and it writes the PR's head, moves n1.md to n1.md.prev, and starts no agent" "${HEAD_SHA}|no|head: ${HEAD_SHA} ROUND-ONE|0" \
  "$(cat "${p}/.swarm/reviews/n1.head")|$([[ -e "${p}/.swarm/reviews/n1.md" ]] && echo yes || echo no)|$(cat "${p}/.swarm/reviews/n1.md.prev")|$(started)"
check "events.tsv gets review-agent:next n1 ok (round 2), and no review-agent line for it" "review-agent:next	n1	ok (round 2)|1" \
  "$(awk -F'\t' '$3 == "n1" && $2 ~ /^review-agent/ { l = $2 "\t" $3 "\t" $5 } END { print l }' "${p}/.swarm/events.tsv")|$(awk -F'\t' '$2 == "review-agent" && $3 == "n1"' "${p}/.swarm/events.tsv" | wc -l | tr -d ' ')"
check "with review-n1 live and no findings file, a plain review-agent n1 still refuses, starting nothing" "1|yes|0" \
  "$(set +e; o="$(run review-agent n1 "${PR}")"; echo "$?|$(has "review-n1 is still reviewing" "${o}")")|$(started)"
# Round 2's review is written; a second --next with no findings tell since would put it aside unread.
echo "head: ${HEAD_SHA} ROUND-TWO" > "${p}/.swarm/reviews/n1.md"; was="$(reviews_now)"
check "a second --next with no findings tell since refuses and keeps round 2's review" "1|yes|yes" \
  "$(set +e; o="$(HERDR_PANE_ID="${NP}" run review-agent --next n1 "${PR}")"; echo "$?|$(has "round 2 of n1 has started already" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
# A findings tell herdr sent but did not see taken up is a round, as the ladder counts it.
printf '%s\t%s\t%s\t%s\t%s\n' 2026-10-16T12:00:00Z tell:findings n1 - "review-n1: the brief was not taken up: herdr sent it the brief twice" >> "${p}/.swarm/events.tsv"
check "after a findings tell logged 'herdr sent it the brief', --next prints round 3, not round 2 again" "yes" \
  "$(has "Review round 3 of story n1" "$(HERDR_PANE_ID="${NP}" run review-agent --next n1 "${PR}")")"
# A new build: two ok findings tells, then a findings-3 step-up whose brief carried the third findings.
printf '%s\t%s\t%s\t%s\t%s\n' 2026-10-16T13:00:00Z story n1 - ok 2026-10-16T13:10:00Z tell:findings n1 - ok \
  2026-10-16T13:20:00Z tell:findings n1 - ok 2026-10-16T13:30:00Z escalate n1 - "ok (findings-3: sonnet -> opus)" >> "${p}/.swarm/events.tsv"
check "after two ok findings tells and a findings-3 step-up, --next prints round 4" "yes" \
  "$(has "Review round 4 of story n1" "$(HERDR_PANE_ID="${NP}" run review-agent --next n1 "${PR}")")"

# --- review-agent --recheck: review-r1 passes a wording fix to the named lines on its diff alone.
RW="${ROOT}/svc-wt/r1"
sed "s/s4/r1/g" "${b}/stories/s4.md" > "${b}/stories/r1.md"
"${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b story/r1 "${RW}" origin/main
seq 1 10 | sed 's/^/line /' > "${RW}/doc.md"
"${GIT[@]}" -C "${RW}" add doc.md && "${GIT[@]}" -C "${RW}" commit -q -m doc
OLD="$(git -C "${RW}" rev-parse HEAD)"; echo "${OLD}" > "${ROOT}/head"
printf '%s\t%s\t%s\t%s\t%s\n' 2026-10-16T14:00:00Z story r1 - ok >> "${p}/.swarm/events.tsv"
check "review-agent r1 starts review-r1 for round 1 at the old head" "0|${OLD}" \
  "$(set +e; run review-agent r1 "${PR}" >/dev/null; echo "$?")|$(cat "${p}/.swarm/reviews/r1.head")"
RP="$(awk '$1 == "review-r1" { p = $2 } END { print p }' "${ROOT}/agents")"
# findings <line>... — round 1's findings file for OLD, those lines under ## Findings; was, its state now.
findings() { printf '%s\n' "head: ${OLD}" "## Findings" "$@" > "${p}/.swarm/reviews/r1.md"; was="$(reviews_now)"; }
ROUND1="doc.md:3 misstates it (ROUND-ONE)"   # the point at the start of the line
findings "${ROUND1}"; done_agent review-r1
printf '%s\t%s\t%s\t%s\t%s\n' 2026-10-16T14:30:00Z tell:findings r1 - ok >> "${p}/.swarm/events.tsv"
# fix <sed script> [new file] — a commit on OLD in r1's worktree that edits doc.md (and adds the new file); prints it.
fix() {
  "${GIT[@]}" -C "${RW}" reset -q --hard "${OLD}"
  sed -e "$1" "${RW}/doc.md" > "${RW}/doc.new" && mv "${RW}/doc.new" "${RW}/doc.md"
  [[ -z "${2:-}" ]] || echo new > "${RW}/$2"
  "${GIT[@]}" -C "${RW}" add -A && "${GIT[@]}" -C "${RW}" commit -q -m fix && git -C "${RW}" rev-parse HEAD
}
WIDE="$(fix 's/^line 3$/line three/; s/^line 8$/line eight/')"
ADJ="$(fix 's/^line [34]$/line three-ish/')"
OTHER="$(fix 's/^line 3$/line three/' other.txt)"
NARROW="$(fix 's/^line 3$/line three/')"
GROW="$(fix '3s/$/ X/; 3G')"   # line 3 reworded, and a line added after it
# at <sha> — r1's worktree and its PR's head at <sha>. recheck [old head] — review-r1's recheck of doc.md:3.
at() { "${GIT[@]}" -C "${RW}" reset -q --hard "$1"; echo "$1" > "${ROOT}/head"; }
recheck() { HERDR_PANE_ID="${RP}" run review-agent --recheck r1 "${PR}" "${1:-${OLD}}" doc.md:3; }
was="$(reviews_now)"
at "${WIDE}"
check "--recheck on a diff that also changes an unnamed line refuses, naming the line and --next, and changes no file under .swarm/reviews" "1|yes|yes|yes" \
  "$(set +e; o="$(recheck)"; echo "$?|$(has "changes doc.md at line 8, which no file:line point names" "${o}")|$(has "a full round is due: swarm.sh review-agent --next r1 ${PR}" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
# git joins edits to lines 3 and 4 into one hunk, which holds the named line 3.
at "${ADJ}"
check "--recheck on a diff that also changes the unnamed line next to the named one refuses, naming it, and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(recheck)"; echo "$?|$(has "changes doc.md at line 4, which no file:line point names" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
# Line 8 passes the hunk check once named, but round 1's findings named only doc.md:3.
at "${WIDE}"
check "--recheck naming a point round 1's findings never named refuses, naming it, and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(HERDR_PANE_ID="${RP}" run review-agent --recheck r1 "${PR}" "${OLD}" doc.md:3 doc.md:8)"; echo "$?|$(has "doc.md:8 is no point the ## Findings of" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
at "${OTHER}"
check "--recheck on a diff that also adds another file refuses, naming it and --next, and changes no file under .swarm/reviews" "1|yes|yes|yes" \
  "$(set +e; o="$(recheck)"; echo "$?|$(has "changes more than lines of a/other.txt b/other.txt" "${o}")|$(has "swarm.sh review-agent --next r1" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
at "${GROW}"
check "--recheck on a diff that rewords a named line and adds one after it refuses, naming --next, and changes no file under .swarm/reviews" "1|yes|yes|yes" \
  "$(set +e; o="$(recheck)"; echo "$?|$(has "adds 1 line(s) to doc.md at line 3, more than it removes" "${o}")|$(has "swarm.sh review-agent --next r1" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
at "${NARROW}"
findings "${ROUND1}" "codex, doc.md:8, also misstates it"
check "--recheck that leaves a finding unnamed refuses, naming it and --next, and changes no file under .swarm/reviews" "1|yes|yes|yes" \
  "$(set +e; o="$(recheck)"; echo "$?|$(has "names no point given, which a pass would drop: codex, doc.md:8, also misstates it" "${o}")|$(has "swarm.sh review-agent --next r1" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
findings "${ROUND1}" "codex, doc.md:5, also misstates it"
check "--recheck naming a point the diff does not change refuses, naming it, and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(HERDR_PANE_ID="${RP}" run review-agent --recheck r1 "${PR}" "${OLD}" doc.md:3 doc.md:5)"; echo "$?|$(has "does not change doc.md:5, a named point" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
findings "codex, other/doc.md:3, misstates it"
check "--recheck of doc.md:3 when the findings name other/doc.md:3 refuses and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(recheck)"; echo "$?|$(has "doc.md:3 is no point the ## Findings of" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
findings "${ROUND1}"
echo '{"total_count":1,"check_runs":[{"name":"test","status":"in_progress","conclusion":null}]}' > "${ROOT}/checks"
check "--recheck while CI runs refuses, saying to wait and run --recheck again, not --next, and changes no file under .swarm/reviews" "1|yes|yes|yes|yes" \
  "$(set +e; o="$(recheck)"; echo "$?|$(has "CI on ${NARROW:0:7} has not finished: test (in_progress)" "${o}")|$(has "wait for it (swarm.sh wait-pr ${PR}), then run swarm.sh review-agent --recheck r1" "${o}")|$([[ "${o}" != *--next* ]] && echo yes || echo "no, got: ${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
echo "${GREEN}" > "${ROOT}/checks"; touch "${ROOT}/ghfail"
check "--recheck when gh cannot read CI refuses, saying to run --recheck again, not --next, and changes no file under .swarm/reviews" "1|yes|yes|yes|yes" \
  "$(set +e; o="$(recheck)"; echo "$?|$(has "could not read CI on ${NARROW:0:7}: error gh api" "${o}")|$(has "run swarm.sh review-agent --recheck r1" "${o}")|$([[ "${o}" != *--next* ]] && echo yes || echo "no, got: ${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
rm "${ROOT}/ghfail"; touch "${ROOT}/ghhang"
# The stub's read sleeps 300s; with SWARM_RECHECK_CI_SECONDS=1 the recheck ends long before it, under 120s
# on a loaded machine too. The kill can reach gh first, so ci_gate's own error may come back in place of
# the timeout: either says the same.
t0=${SECONDS}
check "--recheck whose CI read hangs ends after SWARM_RECHECK_CI_SECONDS, saying to run it again, and changes no file under .swarm/reviews" "1|yes|yes|yes" \
  "$(set +e; o="$(SWARM_RECHECK_CI_SECONDS=1 recheck)"; echo "$?|$(has "could not read CI on ${NARROW:0:7}: " "${o}")|$( (( SECONDS - t0 < 120 )) && echo yes || echo "no, took $((SECONDS - t0))s")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
rm "${ROOT}/ghhang"
echo '{"total_count":1,"check_runs":[{"name":"test","status":"completed","conclusion":"failure","html_url":"u"}]}' > "${ROOT}/checks"
check "--recheck on a head that is not green refuses, naming --next, and changes no file under .swarm/reviews" "1|yes|yes|yes" \
  "$(set +e; o="$(recheck)"; echo "$?|$(has "the head ${NARROW:0:7} is not green: test (failure)" "${o}")|$(has "swarm.sh review-agent --next r1" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
echo "${GREEN}" > "${ROOT}/checks"
check "--recheck from an old head other than the one review-r1 last reviewed refuses and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(recheck "${WIDE}")"; echo "$?|$(has "${WIDE} is not the head review-r1 last reviewed" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
# .head names OLD from the moment round 1 started: until its findings file is written there is no review to recheck.
mv "${p}/.swarm/reviews/r1.md" "${ROOT}/r1.md.aside"; was="$(reviews_now)"
check "--recheck before the old head's round wrote its findings refuses and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(recheck)"; echo "$?|$(has "holds no finished review of ${OLD}" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
mv "${ROOT}/r1.md.aside" "${p}/.swarm/reviews/r1.md"
o="$(recheck)" || echo "FAIL review-agent --recheck r1 exited non-zero: ${o}"
check "a green head whose diff changes only doc.md:3, named at the start of its finding, passes: the new head's findings file and .head, the old findings kept" \
  "head: ${NARROW}|yes|yes|${NARROW}|head: ${OLD}" \
  "$(head -1 "${p}/.swarm/reviews/r1.md")|$(grep -qx '## Findings' "${p}/.swarm/reviews/r1.md" && echo yes || echo no)|$(has "the wording recheck passed" "$(cat "${p}/.swarm/reviews/r1.md")")|$(cat "${p}/.swarm/reviews/r1.head")|$(head -1 "${p}/.swarm/reviews/r1.md.prev")"
check "events.tsv gets review-agent:recheck r1 ok" "review-agent:recheck	r1	ok" \
  "$(awk -F'\t' '$3 == "r1" && $2 ~ /^review-agent/ { l = $2 "\t" $3 "\t" $5 } END { print l }' "${p}/.swarm/events.tsv")"
# A round on NARROW names doc.md:10, the last line; its fix leaves it with no newline, which git marks after it.
printf '%s\n' "head: ${NARROW}" "## Findings" "codex, ${RW}/doc.md:10, misstates it" > "${p}/.swarm/reviews/r1.md"
sed '$d' "${RW}/doc.md" > "${RW}/doc.new" && printf 'line ten' >> "${RW}/doc.new" && mv "${RW}/doc.new" "${RW}/doc.md"
"${GIT[@]}" -C "${RW}" commit -q -am "fix 10" && TEN="$(git -C "${RW}" rev-parse HEAD)" && echo "${TEN}" > "${ROOT}/head"
check "a fix to a named last line that leaves no newline at its end, its finding under the worktree's path, passes" "0|head: ${TEN}" \
  "$(set +e; HERDR_PANE_ID="${RP}" run review-agent --recheck r1 "${PR}" "${NARROW}" doc.md:10 >/dev/null; echo "$?")|$(head -1 "${p}/.swarm/reviews/r1.md")"
check "the recheck counts no round: the next --next prints round 2, as the one findings tell gives" "yes" \
  "$(has "Review round 2 of story r1" "$(HERDR_PANE_ID="${RP}" run review-agent --next r1 "${PR}")")"

check "policy review prints claude opus high" "claude opus high" "$(run policy review)"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
