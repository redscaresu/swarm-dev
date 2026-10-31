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
                  printf '%s\n' "$4" > "$H/prompted-$(echo "$3" | tr : -)"   # what the agent in pane $3 received last
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
# while waiting/<name> does, and left out (gone) while gone/<name> does. Written aside, then moved, so a
# wait reading it meanwhile never finds it empty.
cat > "${ROOT}/sessions" <<EOF
#!/bin/sh
awk -v d="${ROOT}" 'BEGIN { printf "[" }
  system("test -e " d "/gone/" \$1) == 0 { next }
  { s = system("test -e " d "/done/" \$1) == 0 ? "idle" : "busy"
    if (system("test -e " d "/waiting/" \$1) == 0) s = "waiting"
    printf "%s{\"sessionId\":\"%s\",\"status\":\"%s\"}", (k++ ? "," : ""), \$3, s }
  END { print "]" }' "${ROOT}/agents" > "${ROOT}/claude.json.new" && mv "${ROOT}/claude.json.new" "${ROOT}/claude.json"
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
# The green step comes before the review: wait-pr, then the triage of check-run notes and alerts.
# Each swarm.sh call names the project: the agent runs in the story's worktree, outside it.
flat="$(tr -s '[:space:]' ' ' <<< "${brief}")"; sw="SWARM_PROJECT=${p} ${SWARM}"
# The sentence finding_rule gives every review agent: which --reviewer value names which reviewer.
MAPPING="<who> is the reviewer that first raised it, whoever passed it on: codex for a finding from \`swarm.sh codex-review\` (fallback when it printed \"reviewed by fallback\"), code-review for /code-review's, ci for the PR review bot's or a \`swarm.sh findings\` note's, conductor for one from your own reading of the diff (a review agent's own reading keeps the conductor's old value), and lead only for one from the lead's own reading."
# logs_findings <brief> — the brief's log-finding lines, filled in with --reviewer codex, a kind, a PR
# and text and run as written: the outcome and reviewer of the row each logs, then has for MAPPING.
logs_findings() {
  local f="${p}/.swarm/findings.tsv" line n
  while IFS= read -r line; do
    line="${line//<who>/codex}"; line="${line//<kind>/brief-kind}"; line="${line//<PR URL>/o/r#9}"; line="${line//<reason>/nit}"; line="${line//<n>/1}"
    line="${line%%\"<*}\"text\""   # the text placeholder is the last word
    n=0; [[ ! -f "${f}" ]] || n="$(wc -l < "${f}")"
    if ! (cd "${ROOT}" && env -u SWARM_PROJECT bash -c "${line}" >/dev/null 2>&1); then printf 'failed: %s|' "${line}"; continue; fi
    [[ "$(wc -l < "${f}")" -eq $((n + 1)) ]] && printf '%s|' "$(tail -1 "${f}" | cut -f5,6 | tr '\t' ' ')" || printf 'no row|'
  done < <(grep -E '^    SWARM_PROJECT=.* log-finding ' <<< "$1")
  has "${MAPPING}" "$(tr -s '[:space:]' ' ' <<< "$1")"
}
LOGS_FINDINGS="fixed codex|declined codex|yes"
check "the review agent's log-finding lines name the reviewer, and log codex's findings as codex" "${LOGS_FINDINGS}" "$(logs_findings "${brief}")"
# A base line the PR's own merge dropped reaches the base unseen unless the review agent checks for it
# on the PR's owner/repo, number, head and base before it reads the diff. If review_brief drops the
# rule, or fills it from the wrong place, this goes red.
dl_cmd="${sw} dropped-lines o/svc 1 ${HEAD_SHA} main"
dl_at="$(grep -bo -F "${dl_cmd}" <<< "${flat}" | head -1 | cut -d: -f1 || true)"
codex_at="$(grep -bo -F "Run \`SWARM_STORY=s1 " <<< "${flat}" | head -1 | cut -d: -f1 || true)"
check "the round-1 brief runs dropped-lines on o/svc 1, its head and main, in the background before its codex paragraph, logs a drop as conductor's dropped-lines, has the builder restore it in a commit of its own, and stops with no pass on a second exit 2" \
  "yes|yes|yes|yes|yes" \
  "$( [[ -n "${dl_at}" && -n "${codex_at}" && "${dl_at}" -lt "${codex_at}" ]] && echo yes || echo "no, at '${dl_at}', codex at '${codex_at}'")|$(has "log-finding --reviewer conductor --round <n> dropped-lines ${PR} \"<the first line it printed>\"" "${flat}")|$(has "Each line not back is a regression this PR brings in, and a finding to fix this round, whatever else the round finds and whatever its round: list it under \`## Findings\`, from conductor, and send it to the builder with the round's findings, telling it to restore the line in a commit of its own (never by rewriting the merge)." "${flat}")|$(has "Exit 2: it could not check. Run it once more first: a GitHub or fetch error, or a PR head GitHub has not updated yet, can clear on a second run. A second exit 2 means the round cannot pass. Nudge the builder with its last line as the green step says, without waiting on the builder, then stop as above:" "${flat}")|$(has "Run it in the background (Bash run_in_background) and wait for it to exit: its reads of GitHub and git can outlast a foreground Bash call. A run that is killed, or that exits with anything but 0 or 1, counts as exit 2." "${flat}")"
# dropped-lines reads each merge, never the head, so it prints a line again after the builder restored
# it: the brief's count of whole-line copies, in the merge and in the round's head, is how the agent
# tells a restored line from one still gone. Here the check printed a dropped `fi` once (n = 1), and the
# merge's file keeps another, tab-indented `fi` and a longer line holding it. Run as the brief writes
# it: the merge and a head that restored nothing count 1 each, so 1 < 1 + 1 is not back; a head that
# put the line back counts 2, which is. If the count takes any line holding the text, or misses a copy
# whose tab the check took off, the agent passes a live drop or loops on a fixed one, and this goes red.
back_cmd="$({ grep -o "\`git show <rev>:<file> | [^\`]*\`" <<< "${flat}" || true; } | head -1 | tr -d '\`')"
DL="${ROOT}/dl"; "${GIT[@]}" init -q "${DL}"
printf 'if a; then\n\tfi\necho fi done\n' > "${DL}/f.sh"; "${GIT[@]}" -C "${DL}" add f.sh; "${GIT[@]}" -C "${DL}" commit -q -m merge
DL_MERGE="$(git -C "${DL}" rev-parse HEAD)"
echo "x=1" >> "${DL}/f.sh"; "${GIT[@]}" -C "${DL}" commit -q -am other
DL_GONE="$(git -C "${DL}" rev-parse HEAD)"
echo "fi" >> "${DL}/f.sh"; "${GIT[@]}" -C "${DL}" commit -q -am restore
DL_BACK="$(git -C "${DL}" rev-parse HEAD)"
copies() { local c="${back_cmd//<rev>/$1}"; c="${c//<file>/f.sh}"; c="${c//<text>/fi}"; (cd "${DL}" && bash -c "${c}" 2>&1 || true); }
back() { if [[ "$(copies "$1")" -ge $(( $(copies "${DL_MERGE}") + 1 )) ]]; then echo back; else echo "not back"; fi; }
check "the brief's is-it-back count: whole lines, tabs off, 1 in the merge and in a head that restored nothing (not back), 2 once restored (back)" \
  "1|1|2|not back|back|yes" \
  "$(copies "${DL_MERGE}")|$(copies "${DL_GONE}")|$(copies "${DL_BACK}")|$(back "${DL_GONE}")|$(back "${DL_BACK}")|$(has "The line is back, so fixed, only when the head's count is at least the merge's count plus the number of times the check printed that same line" "${flat}")"
# The kinds command finding_rule gives, run as written against another log: only kinds with a fixed,
# escaped or pre-outcome row (never one only declined or filed), and no error with no log at all.
kinds_cmd="$(grep -B1 '^already lists when it fits' <<< "${brief}" | head -1 | tr -d '`')"
kinds_log="${ROOT}/kinds/.swarm/findings.tsv"; mkdir -p "${kinds_log%/*}"
printf '2026-01-01\tfixed-kind\to/r#1\tx\tfixed\tcodex\n2026-01-01\tdeclined-kind\to/r#2\tx\tdeclined\tcodex\tnit\n2026-01-01\told-kind\to/r#3\tx\n2026-01-01\tescaped-kind\to/r#4\tx\tescaped\tescaped\n2026-01-01\tfiled-kind\to/r#5\tx\tfiled\tcodex\n' > "${kinds_log}"
check "finding_rule's kinds command lists only kinds with a fixed, escaped or pre-outcome row" "escaped-kind|fixed-kind|old-kind" \
  "$(bash -c "${kinds_cmd//${p}/${ROOT}/kinds}" | paste -sd'|' -)"
check "finding_rule's kinds command prints nothing, not an error, with no findings log" "" "$(bash -c "${kinds_cmd//${p}/${ROOT}/none}" 2>&1)"
# A failed merge after the pass (a base merged in whose CI goes red, a moved base merge refuses on) has
# nobody else to act on it: the conductor reads no review reply. If the handoff drops the agent's own
# nudge, or names the conductor as the one that acts, the PR sits unmerged, and this goes red.
# The conductor reads no review file, so a stop before a pass reaches it only as a note; and a round
# whose codex was skipped, with no /code-review, would pass on no review at all. If the brief drops the
# note or the agent's own reading, this goes red.
check "a stop tells the story's conductor in a note, the lead takes it when that fails, and a skipped codex with no /code-review is read in its place" "yes|yes|yes" \
  "$(has "write ${p}/.swarm/reviews/s1.stop.md with the Write tool holding one line, \`review-s1 stopped on <that head>: <the stopped: line's why>\`, and run \`${sw} tell conduct-e note ${p}/.swarm/reviews/s1.stop.md\`." "${flat}")|$(has "When that tell fails (no conductor runs for the story), your reply's first line says so: the lead takes it." "${flat}")|$(has "in a round with no \`/code-review\`, you read the diff yourself in codex's place, so the round is never a pass on no review at all." "${flat}")"
# A dequeue, an unconfirmed merge or a red base after the merge used to reach the conductor's wait on
# the review; with no such wait, the stop note is their only way to an owner. If the handoff drops it,
# the PR sits with nobody on it, and this goes red.
check "the handoff sends the conductor the stop note after a base-merged nudge and on a merge hold" "yes|yes" \
  "$(has "Then send the conductor the stop note, as for any other refusal below, naming that line, and stop:" "${flat}")|$(has "When merge refuses with \`held:\`, the user merges the PR: the review is the handoff. Send the conductor the stop note, as for any other refusal below, naming that line, so it closes the builder." "${flat}")"
check "the handoff sends the conductor the stop note on any other refusal or failure, keeping the pass file" "yes|yes" \
  "$(has "On any other refusal or failure (a merge \`dequeued\` or \`unconfirmed\`, CI on the base red or timed out after the merge, a story held until its parents merge, a story with a PR you did not review), first send the conductor the stop note, leaving ${p}/.swarm/reviews/s1.md as it is" "${flat}")|$(has "\`review-s1 stopped on <the PR's head>: <the line that command printed>\`, and run \`${sw} tell conduct-e note ${p}/.swarm/reviews/s1.stop.md\`. Then reply the same way." "${flat}")"
check "the handoff nudges the builder on a red or conflicting base-merged head and a moved base, and names the conductor's restart on the new head" "yes|yes|yes|yes|no" \
  "$(has "When it refuses with \`base merged, red:\` or \`base merged, conflict:\`, or with a line that ends \`merge origin/<base> in, push, and merge the new head\`, it merged nothing: nudge the builder as the green step says" "${flat}")|$(has "telling it to pull its branch first (\`git pull --ff-only origin story/s1\`): the PR's head may be GitHub's merge commit, which its worktree does not have. Then send the conductor the stop note" "${flat}")|$(has "the head the builder pushes gets a new review agent from the conductor once watch reports its checks finished." "${flat}")|$(has "the conductor starts a new review agent on the new head on that note" "${flat}")|$(grep -qF "the conductor or the lead acts on it" <<< "${flat}" && echo yes || echo no)"
check "the brief waits for green with wait-pr on the PR, naming the project, before the review, and again after each push" "yes|yes|yes" \
  "$(has "Before you review, wait for the PR's checks to go green. Run \`${sw} wait-pr ${PR}\` in the background and wait for it to exit, never a loop of your own" "${flat}")|$(awk '/ wait-pr / && !w { w = NR } / codex-review / && !c { c = NR } END { print (w && c && w < c) ? "yes" : "no" }' <<< "${brief}")|$(has "After each nudge, wait for the builder the same way, then wait for green again on the head it pushed." "${flat}")"
check "the brief triages check-run notes and code-scanning alerts before the head counts green" "yes|yes|yes|yes" \
  "$(has "Exit 0: the head counts green only once you have triaged what \`${sw} findings svc 1\` prints: the notes on every check run, whatever its conclusion, and the PR's open code-scanning alerts." "${flat}")|$(has "Nudge the builder with each real one. Rebut the rest with a reason in the PR (\`gh pr comment ${PR} --body" "${flat}")|$(has "Never dismiss an alert." "${flat}")|$(has "\`${sw} tell s1 nudge ${p}/.swarm/reviews/s1.nudge.md\` (never findings, which count as a review round)" "${flat}")"
check "a red head or a conflict is a nudge naming the check or the base, and with the ladder off no step-up, running or done, is named" "yes|0|0" \
  "$(has "Exit 1 (a red check) or a conflict: nudge the builder, naming the red check or the base to merge in." "${flat}")|$(grep -c 'stepped up' <<< "${brief}" || true)|$(grep -c 'stepping up' <<< "${brief}" || true)"
# The green step ends: two nudges or two red heads at most, then a findings file the agent sends the
# builder as any finding (a file with no ## Findings is a review started again, for ever on a PR that
# stays red); and each nudge file is removed before the Write tool writes it (an earlier round's
# survives, and the tool refuses to overwrite a file the session has not read).
check "the green step is bounded per round, its not-green file names the head it ran on and holds the red check as its one finding to fix, and the nudge file is removed before each write" "yes|yes|yes" \
  "$(has "The green step runs once per round: on the first head, then on the head the builder pushes after each findings tell. Each run is bounded: at most two nudges, and at most two heads that wait-pr calls red. Write the not-green file, which ends the green step," "${flat}")|$(has "The not-green file is ${p}/.swarm/reviews/s1.round.md, written with the Write tool after \`rm -f ${p}/.swarm/reviews/s1.round.md\`: \`head: <the head wait-pr waited on last>\`, then a \`## Findings\` heading with one line for the builder, \`wait-pr: not green: <the red check, the conflict, or what wait-pr printed last>\`, then a \`## Handled by the review agent\` heading with \`none\`. Its one finding is to fix, from ci: send it to the builder as findings, as below, and log it as any finding to fix." "${flat}")|$(has "first remove any earlier nudge file (\`rm -f ${p}/.swarm/reviews/s1.nudge.md\`: the Write tool refuses to overwrite a file this session has not read), then write ${p}/.swarm/reviews/s1.nudge.md with the Write tool" "${flat}")"
# After each review the agent triages its own findings: it fixes (through the builder) or declines each,
# logs each with its round, and tells the builder only once the builder is idle. A round with nothing
# to fix is a pass. The conductor no longer triages this file, and the agent still edits nothing.
check "the brief has the agent fix or decline each finding and log each with log-finding --round, its round 1 here, then --next's, a fallback's as fallback" "yes|yes|yes|yes|yes" \
  "$(has "Otherwise, fix or decline each finding. One that is real and inside the story is to fix: the builder fixes it, never you." "${flat}")|$(has "log-finding --declined <reason> --reviewer <who> --round <n> <kind> <PR URL>" "${flat}")|$(has "Log each declined one now, as below; log each one to fix only once the builder has pushed, as below. A finding's round is 1 on this first review, then the round \`review-agent --next\` prints." "${flat}")|$(has "Log nothing before then: a fix in this worktree is not on the PR until the push lands. With the PR at that head, read the new diff (\`git diff <the head you reviewed> HEAD\`) and log each finding you sent: as fixed when the diff fixes it, and as declined, with the reason that fits and \`--because \"<the builder's reason, one line>\"\`, when the builder declined it with a reason you accept;" "${flat}")|$(has "report its findings as codex's, under that line, and log each with \`--reviewer fallback\`, as below." "${flat}")"
check "the declined findings are rebutted in one PR comment with its body given" "yes" \
  "$(has "Rebut the declined ones in the PR, in one comment: \`gh pr comment ${PR} --body '<each declined finding and its reason>'\`." "${flat}")"
check "the brief waits for the builder before its findings tell, then runs --next on the green head, and stops on a moved head only before any findings went out" "yes|yes|yes|yes" \
  "$(has "With findings to fix, write it to ${p}/.swarm/reviews/s1.round.md instead, after \`rm -f ${p}/.swarm/reviews/s1.round.md\` (the Write tool refuses to overwrite a file this session has not read), and never to ${p}/.swarm/reviews/s1.md, which would end the round as a finished review." "${flat}")|$(has "Otherwise wait before you tell, so the findings go at once and count their round now: wait for the builder as above, then run \`${sw} tell s1 findings ${p}/.swarm/reviews/s1.round.md\`." "${flat}")|$(has "run \`${sw} review-agent --next s1 ${PR}\` and do the round it prints (codex alone from round 2)" "${flat}")|$(has "When the builder pushed past ${HEAD_SHA} before any findings or wording nudge went to it, write ${p}/.swarm/reviews/s1.md with the Write tool holding two lines, \`head: ${HEAD_SHA}\` and \`head moved: <the green head>\`, then stop; once findings went to it, run \`review-agent --next\` on the green head, and once a wording nudge did, \`review-agent --recheck\` first, as below." "${flat}")"
# Every wait on the builder is wait --stall, which a stall steps up with the ladder on, and one that
# ends any other way than idle ends the agent's turn: a tell refused as still working then cannot loop.
check "the brief waits on the builder with wait --stall, carries on when it prints idle or done, and stops when it ends any other way" "yes|yes|yes" \
  "$(has "To wait for the builder, run \`${sw} wait --stall s1\` in the background and wait for it to exit, never a loop of your own." "${flat}")|$(has "It prints \`idle\`, or \`done\` for a builder with no Claude session, once the builder's turn has ended." "${flat}")|$(has "When it ends any other way (\`stalled:\`, \`stuck:\`, a timeout or an error), stop with what it printed, as below" "${flat}")"
# The review file is read as a finished review of its head the moment it exists (review_pass, the
# conductor's wait review-<slug>): a round with findings to fix goes to the round file, which the builder
# is told, and the review file is written only on a pass or a stop, whose file has no ## Findings.
check "the brief writes the review file only on a pass or a stop, tells the round file, never the review file, a stop file has head: and stopped: lines, and declines the builder gives reasons for can pass the round" "yes|yes|yes|yes|0" \
  "$(has "${p}/.swarm/reviews/s1.md is read as a finished review of the head on its \`head:\` line the moment it exists, so write it only when a round passes, or when you stop." "${flat}")|$(has "To stop before a round passes, write ${p}/.swarm/reviews/s1.md with the Write tool holding two lines, \`head: <the PR's head as you last saw it>\` and \`stopped: <why: what tell or wait printed, or that no fix was pushed>\`. Then tell the conductor, which reads no review file:" "${flat}")|$(has "When \`git rev-parse HEAD\` is still the head you reviewed (no fix was committed), and the builder declined each finding you sent with a reason you accept, the round passes on that head, as one with nothing to fix does: log each as declined, with \`--because \"<the builder's reason, one line>\"\`, rebut them in the PR as above, in one comment with each finding and the builder's reason, and do the pass step above on that head, its review listing them under \`## Handled by the review agent\` with those reasons." "${flat}")|$(has "When HEAD is still the same otherwise, stop with \`no fix pushed: <the builder's reply, in one line>\`, as above." "${flat}")|$(grep -c "tell s1 findings ${p}/.swarm/reviews/s1.md" <<< "${flat}" || true)"
# A findings tell herdr sent but did not see taken up fails, yet counts as a round: the agent carries on,
# and resends the findings as a nudge only when the builder's pane shows they never arrived.
# A wait right after the builder's push names the pushed head, since GitHub can still report the old one;
# and the pass file's declined and out-of-scope points sit under the agent's own heading, logged and
# rebutted already.
check "the brief waits on a just-pushed head with wait-pr --head, names the exit for a push that never landed, and ends the green step on a builder idle without a commit" "yes|yes|yes|yes" \
  "$(has "A wait on a head the builder has just pushed is \`${sw} wait-pr --head <that head, from git rev-parse HEAD> ${PR}\`: right after a push GitHub can still report the old head, which the plain wait-pr would call green." "${flat}")|$(has "When HEAD moved, run the green step above on it, with wait-pr --head as there: its first line names the head it waits on, so once it has run on that head the PR has it" "${flat}")|$(has "when wait-pr exits 2 with \`the PR's head is <X>, not <sha>\`, the PR never got the head you named (a push that did not land): never wait on <X> instead; nudge the builder naming both shas, so it pushes again, then wait for it and run wait-pr --head again on its HEAD, which a push alone does not change." "${flat}")|$(has "when the builder goes idle without a commit (\`git rev-parse HEAD\` is still the head you waited on) after a nudge that asked for a fix (after one that asked for a push, run wait-pr --head on that HEAD first, as above, and only a second miss ends the step)" "${flat}")"
# The agent's declined and out-of-scope points go under one heading of its own: it has logged and
# rebutted them, and no ## Declined or ## Out of scope heading asks anyone to again.
check "the brief puts declined and out-of-scope points under one heading of the review agent's own, and has the agent write no ## Declined or ## Out of scope heading" "yes|0|0" \
  "$(has "Under a \`## Handled by the review agent\` heading, the same for each finding you declined, with its reason, and for each point a reviewer raised that only a change to a file outside the touches can fix, marked out of scope; with none, say so. Use no \`## Declined\` or \`## Out of scope\` heading: you have logged and rebutted those already." "${flat}")|$(grep -c "a \`## Declined\` heading" <<< "${flat}" || true)|$(grep -c "a \`## Out of scope\` heading" <<< "${flat}" || true)"
# A tell to a busy builder is queued, not refused (main's tell queue): the brief tells nothing again,
# and waits out the turn the tell was queued behind and its delivery before it waits for the fix.
# shellcheck disable=SC2016 # the brief's command, pinned as the text it prints
check "the brief treats a queued tell as sent later: no second tell, one bounded background command for the delivery, and a stop on a dropped one" "yes|yes|yes|yes|yes" \
  "$(has "A tell to a busy builder is queued, not refused: it prints \`queued: s1 (busy); delivered when its turn ends, so do not tell it again\` and exits 0, and its queue's check sends it once the builder's turn has ended (a findings tell counts its round then, not before). After a queued tell, wait for the builder as above, then for the delivery, with this one command in the background (Bash run_in_background), waiting for it to exit, never a loop of your own:" "${flat}")|$(has 'for i in $(seq 90); do ls '"${p}"'/.swarm/tells/s1.findings* 2>/dev/null | grep -qv -e '"'"'\.sent$'"'"' -e undelivered || break; [ -e '"${p}"'/.swarm/tells/s1.findings.undelivered.md ] && break; sleep 10; done; ls '"${p}"'/.swarm/tells/` (for a queued nudge, `nudge` in place of `findings`, in both places).' "${flat}")|$(has "when \`s1.<kind>.undelivered.md\` appears, which means the check dropped the tell, which \`wait --lead\` tells the lead: stop with that, as below;" "${flat}")|$(has "When tell prints \`queued:\` (the builder took a turn meanwhile), do as above, and tell it nothing more." "${flat}")|$(has "When tell prints \`queued:\`, the nudge goes when the builder's turn ends: do as above." "${flat}")"
check "the delivery wait has a limit and a stop line, and a delivery that held the story or stepped the build up is seen before the agent waits on the builder" "yes|yes|yes" \
  "$(has "or after 15 minutes with the marks still there: a check that has not looked for 10 minutes counts as stopped, and \`wait --lead\` then hands its tells to the lead: stop with \`stopped: the queued <kind> tell was not delivered in 15 minutes\`, as below." "${flat}")|$(has "when ${b}/stories/s1.md now has a \`held_for:\` line, stop with \`held for the lead: <that line>\`, as below" "${flat}")|$(has "when ${p}/.swarm/events.tsv gained an \`escalate\` line for s1 since your tell whose outcome starts \`ok (findings-\`, the delivery stepped the build up with the findings in its handover brief: tell it nothing, and wait on the new builder as above." "${flat}")"
check "a builder's decline is logged only when the agent accepts its reason, and is rebutted in the PR" "yes" \
  "$(has "as declined, with the reason that fits and \`--because \"<the builder's reason, one line>\"\`, when the builder declined it with a reason you accept; rebut those in the PR as above, in one comment with each finding and the builder's reason. One it did neither to, or declined with a reason you do not accept, is not logged; the next round raises it again if it still holds." "${flat}")"
check "a findings tell that fails but counts as delivered is sent: never told again, a nudge only if they never arrived" "yes|yes" \
  "$(has "When tell fails but says the findings count as delivered or as a round, herdr sent them: never tell them as findings again." "${flat}")|$(has "if they never arrived, send them as a nudge, which is no round: write ${p}/.swarm/reviews/s1.nudge.md as above holding what ${p}/.swarm/reviews/s1.round.md holds, and run \`${sw} tell s1 nudge ${p}/.swarm/reviews/s1.nudge.md\`. Then wait on it as below." "${flat}")"
check "a round with nothing to fix is a pass that hands the PR on, and the agent still never edits, commits or pushes" "yes|yes|yes" \
  "$(has "A round with nothing to fix is a pass, of ${HEAD_SHA}, the head on ${p}/.swarm/reviews/s1.md's \`head:\` line. Write the review to ${p}/.swarm/reviews/s1.md first" "${flat}")|$(has "Then hand the PR on: run \`${sw} review s1 --head ${HEAD_SHA} ${PR}\`" "${flat}")|$(has "Never edit, commit or push here: the builder changes the code." "${flat}")"
# The conductor's wait ends once the review file exists, and once the PR merges, the merge's reconcile
# (run from the review pane) retires the agent and removes its worktree: on a pass the file comes
# first, and nothing runs in the worktree once merge has exited.
check "on a pass the review file is written before the handoff, and nothing runs in the worktree after it" "yes|yes" \
  "$(python3 -c 'import sys; t = sys.argv[1]; a = t.find(sys.argv[2]); b = t.find(sys.argv[3]); print("yes" if 0 <= a < b else "no")' "${flat}" "Write the review to ${p}/.swarm/reviews/s1.md first" "review s1 --head ${HEAD_SHA}")|$(has "Once the last of these commands has exited, run nothing more in this worktree (a merge removes it): reply with ${p}/.swarm/reviews/s1.md, what the last command printed, and \`codex skipped: <why>\` when codex was, then stop." "${flat}")"
check "the brief leaves no finding for the conductor to decline or send" "0|0" \
  "$(grep -c 'the conductor can decline' <<< "${flat}" || true)|$(grep -c 'The conductor sends it' <<< "${flat}" || true)"
# Findings that are all wording go as a nudge, no round, and the pushed head is rechecked on its diff
# alone; a refused recheck counts the round, and --next runs the full round (#560 spent a round on two).
check "the brief sends all-wording findings as a nudge, rechecks the pushed head with --recheck, hands the PR on after its pass, and runs --next on its refusal" "yes|yes|yes|yes" \
  "$(has "When every finding to fix is wording (a comment, doc or error-text line that misstates the code) and each cites the one file:line it rewrites, send them as a wording nudge in place of the findings tell below: a nudge is no round, so the ladder does not move. Write ${p}/.swarm/reviews/s1.nudge.md as above holding what ${p}/.swarm/reviews/s1.round.md holds, wait for the builder as above, run \`${sw} tell s1 nudge ${p}/.swarm/reviews/s1.nudge.md\`, and from there go on as below for a findings tell, a \`queued:\` one included." "${flat}")|$(has "Once that head is green and triaged with nothing to nudge, after a wording nudge run \`${sw} review-agent --recheck s1 ${PR} <the head you reviewed> <each file:line ${p}/.swarm/reviews/s1.round.md cites>\`, each path relative to the repo root (never under the worktree's path), which counts no round." "${flat}")|$(has "When it prints \`wording recheck passed\`, it has written ${p}/.swarm/reviews/s1.md, a pass of the head it names: do the pass step above from \`Then hand the PR on\`, with that head in place of ${HEAD_SHA}." "${flat}")|$(has "When it refuses naming \`review-agent --next\` (the diff changes more than those lines, say), a full round is due, and the refusal counts the round the nudge did not. Then, or after a findings tell, run \`${sw} review-agent --next s1 ${PR}\`" "${flat}")"
check "a started review agent records the head it reviews, so watch and next do not call the PR queued" "${HEAD_SHA}" \
  "$(cat "${p}/.swarm/reviews/s1.head")"
check "events.tsv gains a review-agent line whose target is s1 (the newest, after the refusals'), with round=1, the round it starts" "s1	ok ~~ round=1" \
  "$(awk -F'\t' '$2 == "review-agent" { l = $3 "\t" $5 } END { print l }' "${p}/.swarm/events.tsv" | no_version)"

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
  "$(has "When it also prints \`stepped up: s4\`, the build's red heads handed it to the next model on the escalation ladder, and the head it waited on is gone: send no nudge; write ${p}/.swarm/reviews/s4.md with the Write tool holding two lines, \`head: <the head wait-pr waited on>\` and \`head moved: <that stepped up: line>\`, then stop." "$(tr -s '[:space:]' ' ' <<< "${r4}")")|$(has "When it prints \`step-up failed: s4\` instead, the builder was closed and no new one runs, so no nudge can reach it: write ${p}/.swarm/reviews/s4.md with the Write tool holding \`head: <the head wait-pr waited on>\`, a \`## Findings\` heading with that \`step-up failed:\` line as its one item, and a \`## Handled by the review agent\` heading with \`none\`, then stop." "$(tr -s '[:space:]' ' ' <<< "${r4}")")"
check "with escalate_ladder set, the brief's builder wait says a stalled build stepped up, or a step-up still running, is waited on again, and one stepped up after the findings were told gets the round file as a nudge" "yes|yes" \
  "$(has "When it prints \`stepped up: s4\`, the stalled build went to the next model on the escalation ladder, and when it prints \`stepping up: s4\`, another step-up or a restart of it is running: in both cases, wait on it the same way." "$(tr -s '[:space:]' ' ' <<< "${r4}")")|$(has "A build stepped up after this round's findings were told has none of them in its handover brief (that brief pastes ${p}/.swarm/reviews/s4.md, which holds no findings to fix): once the new builder is idle, send it ${p}/.swarm/reviews/s4.round.md as a nudge, which is no round (write ${p}/.swarm/reviews/s4.nudge.md as below holding what ${p}/.swarm/reviews/s4.round.md holds, then \`${sw} tell s4 nudge ${p}/.swarm/reviews/s4.nudge.md\`), and wait on it again." "$(tr -s '[:space:]' ' ' <<< "${r4}")")"
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
check "--next before any findings tell refuses, as round 1 is a plain review-agent start, and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(HERDR_PANE_ID="${NP}" run review-agent --next n1 "${PR}")"; echo "$?|$(has "there is no next round" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
printf '%s\t%s\t%s\t%s\t%s\n' 2026-10-16T11:30:00Z tell:findings n1 - ok >> "${p}/.swarm/events.tsv"
check "--next from another pane refuses, naming review-n1's pane, and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(HERDR_PANE_ID=w:999 run review-agent --next n1 "${PR}")"; echo "$?|$(has "only review-n1, in its pane ${NP}" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
check "--next with no review-n2 listed refuses and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(HERDR_PANE_ID="${NP}" run review-agent --next n2 "${PR}")"; echo "$?|$(has "herdr lists no review-n2" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
echo 0123456789abcdef0123456789abcdef01234567 > "${ROOT}/head"
check "--next with the worktree off the PR's head refuses and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(HERDR_PANE_ID="${NP}" run review-agent --next n1 "${PR}")"; echo "$?|$(has "not the PR's head 0123456789abcdef" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
echo "${HEAD_SHA}" > "${ROOT}/head"
printf '%s\n' --- "status: ready" "kind: code" --- > "${b}/stories/review-n1.md"
check "--next with a board story named review-n1 refuses and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(HERDR_PANE_ID="${NP}" run review-agent --next n1 "${PR}")"; echo "$?|$(has "the board has a story named review-n1" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
rm "${b}/stories/review-n1.md"; touch "${ROOT}/listfail"
check "--next when herdr cannot list its agents says to run --next again, not to start a review agent, and changes no file under .swarm/reviews" "1|yes|no|yes" \
  "$(set +e; o="$(HERDR_PANE_ID="${NP}" run review-agent --next n1 "${PR}")"; echo "$?|$(has "run swarm.sh review-agent --next n1 <PR URL> again once herdr answers" "${o}")|$(grep -qF "start one with" <<< "${o}" && echo yes || echo no)")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
rm "${ROOT}/listfail"; echo wip > "${ROOT}/svc-wt/n1/wip.txt"
check "--next with uncommitted work refuses and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(HERDR_PANE_ID="${NP}" run review-agent --next n1 "${PR}")"; echo "$?|$(has "has uncommitted changes" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
rm "${ROOT}/svc-wt/n1/wip.txt"
o="$(HERDR_PANE_ID="${NP}" run review-agent --next n1 "${PR}")" || echo "FAIL review-agent --next n1 exited non-zero: ${o}"
check "after one ok findings tell, --next from review-n1's pane prints round 2 and the codex-alone instruction" "yes|yes" \
  "$(has "Review round 2 of story n1" "${o}")|$(has "This is review round 2 of the story: run codex alone, not \`/code-review\`" "${o}")"
check "and it writes the PR's head, moves n1.md to n1.md.prev, and starts no agent" "${HEAD_SHA}|no|head: ${HEAD_SHA} ROUND-ONE|0" \
  "$(cat "${p}/.swarm/reviews/n1.head")|$([[ -e "${p}/.swarm/reviews/n1.md" ]] && echo yes || echo no)|$(cat "${p}/.swarm/reviews/n1.md.prev")|$(started)"
check "events.tsv gets review-agent:next n1 ok (round 2), with round=2 to match, and no review-agent line for it" "review-agent:next	n1	ok (round 2) ~~ round=2|1" \
  "$(awk -F'\t' '$3 == "n1" && $2 ~ /^review-agent/ { l = $2 "\t" $3 "\t" $5 } END { print l }' "${p}/.swarm/events.tsv" | no_version)|$(awk -F'\t' '$2 == "review-agent" && $3 == "n1"' "${p}/.swarm/events.tsv" | wc -l | tr -d ' ')"
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
printf '%s\t%s\t%s\t%s\t%s\n' 2026-10-16T13:00:00Z story n1 - ok 2026-10-16T13:05:00Z review-agent n1 - ok 2026-10-16T13:10:00Z tell:findings n1 - ok \
  2026-10-16T13:20:00Z tell:findings n1 - ok 2026-10-16T13:30:00Z escalate n1 - "ok (findings-3: sonnet -> opus)" >> "${p}/.swarm/events.tsv"
check "after two ok findings tells and a findings-3 step-up, --next prints round 4" "yes" \
  "$(has "Review round 4 of story n1" "$(HERDR_PANE_ID="${NP}" run review-agent --next n1 "${PR}")")"
# A new build starts while review-n1's pane is still open: its story event resets the count, so no
# findings went to this build and --next has no round to start. Once findings go to it, the open
# review-n1 is still the earlier build's: no review-agent start is on record in this one.
echo "head: ${HEAD_SHA} ROUND-FOUR" > "${p}/.swarm/reviews/n1.md"
printf '%s\t%s\t%s\t%s\t%s\n' 2026-10-16T14:00:00Z story n1 - ok >> "${p}/.swarm/events.tsv"; was="$(reviews_now)"
check "after a new build's story event, --next refuses, as round 1 is a plain review-agent start, and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(HERDR_PANE_ID="${NP}" run review-agent --next n1 "${PR}")"; echo "$?|$(has "there is no next round" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
printf '%s\t%s\t%s\t%s\t%s\n' 2026-10-16T14:10:00Z tell:findings n1 - ok >> "${p}/.swarm/events.tsv"
check "after findings to a new build with no review-agent start in it, --next refuses the earlier build's review-n1 and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(HERDR_PANE_ID="${NP}" run review-agent --next n1 "${PR}")"; echo "$?|$(has "review-n1 is from an earlier build" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"

# --- A findings round run as the brief writes it: review-f1's wait, tell and --next commands, taken
# from its brief and run from its pane, in f1's worktree. f1's builder, in pane w:900 of f1's tab, has
# a Claude session that is busy until done/f1 exists.
sed "s/s4/f1/g" "${b}/stories/s4.md" > "${b}/stories/f1.md"
"${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b story/f1 "${ROOT}/svc-wt/f1" origin/main
mkdir -p "${p}/.swarm/state"; echo "w:900 f1" >> "${p}/.swarm/state/f1"; echo "f1 w:900 sess-f1" >> "${ROOT}/agents"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 2026-10-16 code f1 claude sonnet high sess-f1 >> "${p}/.swarm/agents.tsv"; "${ROOT}/sessions"
check "review-agent f1 starts review-f1 for round 1" "0" "$(set +e; run review-agent f1 "${PR}" >/dev/null; echo "$?")"
FP="$(awk '$1 == "review-f1" { p = $2 } END { print p }' "${ROOT}/agents")"
fbrief="$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/review-f1.md")"
# brief_cmd <words> — the one backquoted command in review-f1's brief that holds <words>, or nothing.
brief_cmd() { { grep -o "\`[^\`]*$1[^\`]*\`" <<< "${fbrief}" || true; } | sort -u | tr -d '\`'; }
wait_cmd="$(brief_cmd " wait --stall f1")"; tell_cmd="$(brief_cmd " tell f1 findings ")"; next_cmd="$(brief_cmd " review-agent --next f1 ")"
delivery_cmd="$(brief_cmd "for i in ")"   # the queued tell's delivery wait, one bounded command
check "review-f1's brief has one wait, one findings tell, one --next command and one delivery wait, each naming the project" "yes|yes|yes|yes" \
  "$(has "SWARM_PROJECT=${p} ${SWARM} wait --stall f1" "${wait_cmd}")|$(has "SWARM_PROJECT=${p} ${SWARM} tell f1 findings ${p}/.swarm/reviews/f1.round.md" "${tell_cmd}")|$(has "SWARM_PROJECT=${p} ${SWARM} review-agent --next f1 ${PR}" "${next_cmd}")|$(has "ls ${p}/.swarm/tells/f1.findings* 2>/dev/null" "${delivery_cmd}")"
# in_review_pane <command> — <command> as review-f1 runs it: from its pane, in f1's worktree.
in_review_pane() { (cd "${ROOT}/svc-wt/f1" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w HERDR_PANE_ID="${FP}" SWARM_NOTE_WAKE_SECS=1 PATH="${STUB_BIN}:${PATH}" bash -c "$1" 2>&1); }
# until_ok <test...> — wait (60 s at most) until <test> succeeds. settle — wait (60 s at most) for a queued
# tell's check to end, so none outlives this test.
until_ok() { local i; for ((i = 0; i < 300; i++)); do "$@" && return 0; sleep 0.2; done; return 1; }
settle() { local i; for ((i = 0; i < 300; i++)); do compgen -G "${p}/.swarm/tells/*.later" >/dev/null || compgen -G "${p}/.swarm/tells/*.lock" >/dev/null || return 0; sleep 0.2; done; }
QF="queued: f1 (busy); delivered when its turn ends, so do not tell it again"
# The round file the agent wrote, after its triage: findings to fix go there, never to f1.md.
printf '%s\n' "head: ${HEAD_SHA}" "## Findings" "- codex: bin/f1.sh:3 F1-FIX-ME" "## Handled by the review agent" "none" > "${p}/.swarm/reviews/f1.round.md"
check "with f1's builder busy, the brief's tell is queued: exit 0, the queued: line, nothing sent, logged as queued and no round yet" "0|yes|no|${QF}|0" \
  "$(set +e; o="$(in_review_pane "${tell_cmd}")"; echo "$?|$(has "${QF}" "${o}")")|$([[ -e "${ROOT}/prompted-w-900" ]] && echo yes || echo no)|$(awk -F'\t' '$2 == "tell:findings" && $3 == "f1" { l = $5 } END { print l }' "${p}/.swarm/events.tsv" | no_version)|$(awk -F'\t' '$2 == "tell:findings" && $3 == "f1" { o = $5; sub(/ ~~ .*/, "", o); if (o == "ok") n++ } END { print n + 0 }' "${p}/.swarm/events.tsv")"
# The brief's wait returns once the builder goes idle, not before (60 s at most, for a loaded machine).
in_review_pane "${wait_cmd} 60000" > "${ROOT}/wait-f1.out" & wpid=$!
sleep 1; check "the brief's wait on f1 holds while f1's builder works" "yes" "$(kill -0 "${wpid}" 2>/dev/null && echo yes || echo no)"
done_agent f1
rc=0; for _ in $(seq 600); do kill -0 "${wpid}" 2>/dev/null || break; sleep 0.1; done; wait "${wpid}" || rc=$?
check "and returns 0, idle, once it is idle" "0|idle" "${rc}|$(tail -1 "${ROOT}/wait-f1.out")"
# The queued tell's check (looking every second here) delivers it now that f1 is idle: no second tell runs.
# The brief's delivery wait, run as the brief writes it, ends once only f1.findings.sent is left (the .sending
# and .claimed marks go once herdr has the prompt, a moment after the stub records it), and prints the queue dir.
in_review_pane "${delivery_cmd}" > "${ROOT}/delivery-f1.out" & dpid=$!
delivered_f1() { [[ "$(compgen -G "${p}/.swarm/tells/f1.findings*" | sed 's#.*/##' | tr '\n' ' ')" == "f1.findings.sent " ]]; }
until_ok test -e "${ROOT}/prompted-w-900" || echo "FAIL the queued findings never reached f1's builder"
until_ok delivered_f1 || echo "FAIL the queued tell's marks never cleared: $(compgen -G "${p}/.swarm/tells/f1.*" | sed 's#.*/##' | tr '\n' ' ')"
rc=0; for _ in $(seq 300); do kill -0 "${dpid}" 2>/dev/null || break; sleep 0.1; done; wait "${dpid}" || rc=$?
check "the brief's delivery wait ends within 30 s of the delivery, exit 0, listing the sent mark and no mark still on its way" "0|yes|no" \
  "${rc}|$(has "f1.findings.sent" "$(cat "${ROOT}/delivery-f1.out")")|$(grep -qE 'f1\.findings(\.sending|\.claimed|$)' "${ROOT}/delivery-f1.out" && echo yes || echo no)"
check "once f1's builder is idle, its queue's check delivers the tell: logged tell:findings f1 ok, round=1 verdict=findings, from the review agent, the queue left with its sent mark" "tell:findings	f1	ok ~~ round=1 verdict=findings|yes|f1.findings.sent" \
  "$(awk -F'\t' '$2 ~ /^tell/ && $3 == "f1" { l = $2 "\t" $3 "\t" $5 } END { print l }' "${p}/.swarm/events.tsv" | no_version)|$(has "From the review agent:" "$(cat "${ROOT}/prompted-w-900" 2>/dev/null)")|$(compgen -G "${p}/.swarm/tells/f1.findings*" | sed 's#.*/##' | tr '\n' ' ' | sed 's/ $//')"
check "and f1's builder receives the round file" "yes" \
  "$(diff <(tail -n +3 "${ROOT}/prompted-w-900") "${p}/.swarm/reviews/f1.round.md" >/dev/null 2>&1 && echo yes || echo no)"
o="$(in_review_pane "${next_cmd}")" || echo "FAIL the brief's --next for f1 exited non-zero: ${o}"
check "the brief's --next then prints round 2, with codex alone, names the round file for findings to fix and the review file for a pass or a stop, and the tell and --next left no review file for f1 (no pass on record)" "yes|yes|yes|no" \
  "$(has "Review round 2 of story f1" "${o}")|$(has "This is review round 2 of the story: run codex alone, not \`/code-review\`" "${o}")|$(has "write this round's findings to fix to ${p}/.swarm/reviews/f1.round.md, and ${p}/.swarm/reviews/f1.md only on a pass or a stop, each afresh with \`head: ${HEAD_SHA}\` as its first line" "${o}")|$([[ -e "${p}/.swarm/reviews/f1.md" ]] && echo yes || echo no)"
settle
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
# findings <line>... — round 1's round file for OLD, those lines under ## Findings; was, its state now.
findings() { printf '%s\n' "head: ${OLD}" "## Findings" "$@" > "${p}/.swarm/reviews/r1.round.md"; was="$(reviews_now)"; }
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
findings "${ROUND1}" "codex: the summary misstates the flow"
check "--recheck that leaves a finding with no file:line refuses, naming it and --next, and changes no file under .swarm/reviews" "1|yes|yes|yes" \
  "$(set +e; o="$(recheck)"; echo "$?|$(has "names no point given, which a pass would drop: codex: the summary misstates the flow" "${o}")|$(has "swarm.sh review-agent --next r1" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
# One finding citing two points, rechecked with one: the other half would go unfixed.
findings "codex, doc.md:3 and doc.md:8 misstate it"
check "--recheck of one point of a finding that cites two refuses, naming the other and --next, and changes no file under .swarm/reviews" "1|yes|yes|yes" \
  "$(set +e; o="$(recheck)"; echo "$?|$(has "cite doc.md:8, which is no point given, so a pass would drop it: codex, doc.md:3 and doc.md:8 misstate it" "${o}")|$(has "swarm.sh review-agent --next r1" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
# The same two lines in shorthand: a list after the citation, and a bare :8 later in the finding.
findings "codex, doc.md:3,8 misstate it"
check "--recheck of doc.md:3 when a finding cites doc.md:3,8 refuses, naming the list and --next, and changes no file under .swarm/reviews" "1|yes|yes|yes" \
  "$(set +e; o="$(recheck)"; echo "$?|$(has "cite doc.md:3,8, which is no point given" "${o}")|$(has "swarm.sh review-agent --next r1" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
findings "codex, doc.md:3 (and :8) misstate it"
check "--recheck of doc.md:3 when a finding cites doc.md:3 (and :8) refuses, naming :8 and --next, and changes no file under .swarm/reviews" "1|yes|yes|yes" \
  "$(set +e; o="$(recheck)"; echo "$?|$(has "cite :8, which is no point given" "${o}")|$(has "swarm.sh review-agent --next r1" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
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
# .head names OLD from the moment round 1 started: until its round file is written there is no review to recheck.
mv "${p}/.swarm/reviews/r1.round.md" "${ROOT}/r1.round.md.aside"; was="$(reviews_now)"
check "--recheck before the old head's round wrote its findings refuses and changes no file under .swarm/reviews" "1|yes|yes" \
  "$(set +e; o="$(recheck)"; echo "$?|$(has "holds no finished review of ${OLD}" "${o}")")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
mv "${ROOT}/r1.round.md.aside" "${p}/.swarm/reviews/r1.round.md"
o="$(recheck)" || echo "FAIL review-agent --recheck r1 exited non-zero: ${o}"
check "a green head whose diff changes only doc.md:3, named at the start of its finding, passes: the new head's findings file and .head, the round file kept" \
  "head: ${NARROW}|yes|yes|${NARROW}|head: ${OLD}" \
  "$(head -1 "${p}/.swarm/reviews/r1.md")|$(grep -qx '## Findings' "${p}/.swarm/reviews/r1.md" && echo yes || echo no)|$(has "the wording recheck passed" "$(cat "${p}/.swarm/reviews/r1.md")")|$(cat "${p}/.swarm/reviews/r1.head")|$(head -1 "${p}/.swarm/reviews/r1.round.md")"
check "events.tsv gets review-agent:recheck r1 ok" "review-agent:recheck	r1	ok" \
  "$(awk -F'\t' '$3 == "r1" && $2 ~ /^review-agent/ { l = $2 "\t" $3 "\t" $5 } END { print l }' "${p}/.swarm/events.tsv" | no_version)"
# A round on NARROW names doc.md:10, the last line; its fix leaves it with no newline, which git marks after it.
printf '%s\n' "head: ${NARROW}" "## Findings" "codex, ${RW}/doc.md:10, misstates it" > "${p}/.swarm/reviews/r1.round.md"
sed '$d' "${RW}/doc.md" > "${RW}/doc.new" && printf 'line ten' >> "${RW}/doc.new" && mv "${RW}/doc.new" "${RW}/doc.md"
"${GIT[@]}" -C "${RW}" commit -q -am "fix 10" && TEN="$(git -C "${RW}" rev-parse HEAD)" && echo "${TEN}" > "${ROOT}/head"
check "a fix to a named last line that leaves no newline at its end, its finding under the worktree's path, passes, keeping the first pass aside as r1.md.prev" "0|head: ${TEN}|head: ${NARROW}" \
  "$(set +e; HERDR_PANE_ID="${RP}" run review-agent --recheck r1 "${PR}" "${NARROW}" doc.md:10 >/dev/null; echo "$?")|$(head -1 "${p}/.swarm/reviews/r1.md")|$(head -1 "${p}/.swarm/reviews/r1.md.prev")"
o="$(HERDR_PANE_ID="${RP}" run review-agent --next r1 "${PR}")" || echo "FAIL review-agent --next r1 exited non-zero: ${o}"
check "the recheck counts no round: the next --next prints round 2, as the one findings tell gives" "yes" "$(has "Review round 2 of story r1" "${o}")"
# Round 2 reviews the head --next pinned, which a builder's merge of the base may have made: a check left
# on round 1's head would pass a drop that merge brought in. If --next stops printing the check, or
# names another head, this goes red.
check "--next's round 2 runs dropped-lines on the new head it pins, ${TEN:0:7}, not an earlier head" "yes|no" \
  "$(has "run \`SWARM_PROJECT=${p} ${SWARM} dropped-lines o/svc 1 ${TEN} main\` in the background and act on its exit" "${o}")|$(grep -qF -e "dropped-lines o/svc 1 ${OLD}" -e "dropped-lines o/svc 1 ${NARROW}" <<< "${o}" && echo yes || echo no)"

# --- The wording route run as the brief writes it: the nudge and --recheck commands, taken from the
# review agents' briefs and run from their panes, in their worktrees. w1's one finding is wording, so it
# goes to w1's builder (idle in pane w:901) as a nudge, and --recheck passes the wording-only fix. w2's
# fix also changes code: the same --recheck refuses, counting the round, and the brief's --next runs it.
for s in w1 w2; do
  sed "s/s4/${s}/g" "${b}/stories/s4.md" > "${b}/stories/${s}.md"
  "${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b "story/${s}" "${ROOT}/svc-wt/${s}" origin/main
  seq 1 10 | sed 's/^/line /' > "${ROOT}/svc-wt/${s}/doc.md"; echo 'echo one' > "${ROOT}/svc-wt/${s}/code.sh"
  "${GIT[@]}" -C "${ROOT}/svc-wt/${s}" add -A && "${GIT[@]}" -C "${ROOT}/svc-wt/${s}" commit -q -m base
  printf '%s\t%s\t%s\t%s\t%s\n' 2026-10-16T15:00:00Z story "${s}" - ok >> "${p}/.swarm/events.tsv"
done
echo "w:901 w1" >> "${p}/.swarm/state/w1"; echo "w1 w:901 sess-w1" >> "${ROOT}/agents"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 2026-10-16 code w1 claude sonnet high sess-w1 >> "${p}/.swarm/agents.tsv"; done_agent w1
# wording_start <slug> — review-<slug> started on its worktree's head, its round file holding one wording
# finding at doc.md:3; sets WOLD to that head, WPANE to its pane and WBRIEF to its brief, flattened.
wording_start() {
  WOLD="$(git -C "${ROOT}/svc-wt/$1" rev-parse HEAD)"; echo "${WOLD}" > "${ROOT}/head"
  run review-agent "$1" "${PR}" >/dev/null || echo "FAIL review-agent $1 exited non-zero"
  WPANE="$(awk -v n="review-$1" '$1 == n { p = $2 } END { print p }' "${ROOT}/agents")"
  WBRIEF="$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/review-$1.md")"
  printf '%s\n' "head: ${WOLD}" "## Findings" "- codex: doc.md:3 misstates what the code does" "## Handled by the review agent" \
    "- codex: code.sh:1 could name its echo (declined: nit)" > "${p}/.swarm/reviews/$1.round.md"
}
# wording_cmd <words> — the one backquoted command in WBRIEF that holds <words>.
wording_cmd() { { grep -o "\`[^\`]*$1[^\`]*\`" <<< "${WBRIEF}" || true; } | sort -u | tr -d '\`'; }
# push <slug> <sed script> — the builder's fix, committed in <slug>'s worktree and made the PR's head.
push() {
  sed -e "$2" "${ROOT}/svc-wt/$1/doc.md" > "${ROOT}/doc.new" && mv "${ROOT}/doc.new" "${ROOT}/svc-wt/$1/doc.md"
  "${GIT[@]}" -C "${ROOT}/svc-wt/$1" commit -q -am fix && git -C "${ROOT}/svc-wt/$1" rev-parse HEAD > "${ROOT}/head"
}
# in_pane <slug> <command> — <command> as review-<slug> runs it: from its pane, in <slug>'s worktree.
in_pane() { (cd "${ROOT}/svc-wt/$1" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w HERDR_PANE_ID="${WPANE}" PATH="${STUB_BIN}:${PATH}" bash -c "$2" 2>&1); }
# recheck_of <slug> — the brief's --recheck command, its placeholders filled in: WOLD and doc.md:3.
recheck_of() { local c; c="$(wording_cmd " review-agent --recheck $1 ")"; echo "${c%%<the head you reviewed>*}${WOLD} doc.md:3"; }

wording_start w1
cp "${p}/.swarm/reviews/w1.round.md" "${p}/.swarm/reviews/w1.nudge.md"
nudge_cmd="$(wording_cmd " tell w1 nudge ")"
check "review-w1's brief has one nudge and one --recheck command, each naming the project" "SWARM_PROJECT=${p} ${SWARM} tell w1 nudge ${p}/.swarm/reviews/w1.nudge.md|SWARM_PROJECT=${p} ${SWARM} review-agent --recheck w1 ${PR} <the head you reviewed> <each file:line ${p}/.swarm/reviews/w1.round.md cites>" \
  "${nudge_cmd}|$(wording_cmd " review-agent --recheck w1 ")"
check "the brief's nudge to w1's idle builder exits 0 and is logged tell:nudge w1 ok, with no findings tell, so no round is counted" "0|tell:nudge	w1	ok|0|yes" \
  "$(set +e; in_pane w1 "${nudge_cmd}" >/dev/null; echo "$?")|$(awk -F'\t' '$2 ~ /^tell/ && $3 == "w1" { l = $2 "\t" $3 "\t" $5 } END { print l }' "${p}/.swarm/events.tsv" | no_version)|$(awk -F'\t' '$2 == "tell:findings" && $3 == "w1"' "${p}/.swarm/events.tsv" | wc -l | tr -d ' ')|$(has "doc.md:3 misstates what the code does" "$(cat "${ROOT}/prompted-w-901" 2>/dev/null)")"
check "and counts no review round: the brief's --next from review-w1's pane still refuses, as round 1 is a plain review-agent start" "1|yes" \
  "$(set +e; o="$(in_pane w1 "$(wording_cmd " review-agent --next w1 ")")"; echo "$?|$(has "there is no next round" "${o}")")"
push w1 's/^line 3$/line three/'; WNEW="$(cat "${ROOT}/head")"
check "the brief's --recheck on w1's wording-only fix passes, writing the pass on the new head, logged review-agent:recheck w1 ok" "0|yes|head: ${WNEW}|review-agent:recheck	w1	ok" \
  "$(set +e; o="$(in_pane w1 "$(recheck_of w1)")"; echo "$?|$(has "wording recheck passed" "${o}")")|$(head -1 "${p}/.swarm/reviews/w1.md")|$(awk -F'\t' '$3 == "w1" && $2 ~ /^review-agent/ { l = $2 "\t" $3 "\t" $5 } END { print l }' "${p}/.swarm/events.tsv" | no_version)"
# The conductor reads the pass: the round's declined point goes under the agent's own heading, logged and
# rebutted already, and no ## Out of scope heading, which the conductor's rules would log and rebut again.
check "the pass carries the round's declined point under ## Handled by the review agent, marked logged and rebutted, with no ## Out of scope heading" "yes|yes|0" \
  "$(has "## Handled by the review agent" "$(cat "${p}/.swarm/reviews/w1.md")")|$([[ "$(cat "${p}/.swarm/reviews/w1.md")" == *"Carried from the round on ${WOLD:0:7}, each logged and rebutted then:"$'\n'"- codex: code.sh:1 could name its echo (declined: nit)"* ]] && echo yes || echo "no, got: $(cat "${p}/.swarm/reviews/w1.md")")|$(grep -c '^## Out of scope' "${p}/.swarm/reviews/w1.md" || true)"

wording_start w2
printf '%s\t%s\t%s\t%s\t%s\n' 2026-10-16T15:10:00Z tell:nudge w2 - ok >> "${p}/.swarm/events.tsv"
push w2 's/^line 3$/line three/'
echo 'echo two' > "${ROOT}/svc-wt/w2/code.sh"; "${GIT[@]}" -C "${ROOT}/svc-wt/w2" commit -q -am code
git -C "${ROOT}/svc-wt/w2" rev-parse HEAD > "${ROOT}/head"; was="$(reviews_now)"
# Refused twice: the round counts once.
for _ in 1 2; do o="$(set +e; in_pane w2 "$(recheck_of w2)"; echo "rc:$?")"; done
check "the same --recheck on a fix that also changes code is refused, naming the code file and --next, and changes no file under .swarm/reviews" "yes|yes|yes|yes" \
  "$(has "rc:1" "${o}")|$(has "changes code.sh, which no file:line point names" "${o}")|$(has "a full round is due: swarm.sh review-agent --next w2 ${PR}" "${o}")|$([[ "$(reviews_now)" == "${was}" ]] && echo yes || echo no)"
next_cmd="$(wording_cmd " review-agent --next w2 ")"
check "the brief's next step on that refusal is its --next, which runs round 2 from review-w2's pane: the refusals count that round once" "SWARM_PROJECT=${p} ${SWARM} review-agent --next w2 ${PR}|yes|yes" \
  "${next_cmd}|$(has "When it refuses naming \`review-agent --next\` (the diff changes more than those lines, say), a full round is due, and the refusal counts the round the nudge did not. Then, or after a findings tell, run \`${next_cmd}\`" "${WBRIEF}")|$(has "Review round 2 of story w2" "$(in_pane w2 "${next_cmd}")")"
# --- The handoff on a pass: the brief's review --head, grants and merge --head commands, taken from
# its brief and run from the review pane, in the story's worktree. gh is the merge tests' stub
# (tests/merge_fixture.sh): it answers every read swarm.sh merge makes from ${FXH}, its PR head
# ${FXH}/head, and logs each call to ${MX}/gh.log. h1 is reviewed under merge = agent, h2 under
# merge = human with no HLD, so no grant; each story is still ready, as while its builder works.
echo "${HEAD_SHA}" > "${ROOT}/head"
MX="${ROOT}/mx"; FXH="${MX}/fx"; MGH="${ROOT}/mgh"; mkdir -p "${MX}" "${MGH}"
# In a bash of its own, so the fixture's names stay out of this file's.
# shellcheck disable=SC2016 # expanded by that bash
ROOT="${MX}" CLAUDE_CONFIG_DIR="${MX}/claude-config" H="${HEAD_SHA}" bash -c 'source "$1"; fresh; echo "${H}" > "${FX}/head"
  checks "${FX}/${H}.checks" "$(run test completed success)"; statuses "${FX}/${H}.status"' _ "$(dirname "${BASH_SOURCE[0]}")/merge_fixture.sh" > /dev/null
cp "${MX}/bin/gh" "${MGH}/gh"   # its gh alone: the herdr and claude stubs here stay this file's
PRA=https://github.com/o/svc/pull/11; PRB=https://github.com/o/svc/pull/12
for s in h1 h2; do
  sed -e "s/s4/${s}/g" -e "s/^status: review$/status: ready/" "${b}/stories/s4.md" > "${b}/stories/${s}.md"
  "${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b "story/${s}" "${ROOT}/svc-wt/${s}" origin/main
done
: > "${p}/.claude/swarm/config"
check "review-agent h2 starts review-h2 under merge = human" "0" "$(set +e; run review-agent h2 "${PRB}" >/dev/null; echo "$?")"
echo "merge = agent" > "${p}/.claude/swarm/config"
check "review-agent h1 starts review-h1 under merge = agent" "0" "$(set +e; run review-agent h1 "${PRA}" >/dev/null; echo "$?")"
abrief="$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/review-h1.md")"; hbrief="$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/review-h2.md")"
# cmd_in <brief> <words> — the backquoted commands in <brief> that hold <words>, one per line.
cmd_in() { { grep -o "\`[^\`]*$2[^\`]*\`" <<< "$1" || true; } | sort -u | tr -d '\`'; }
# unpinned <brief file> — each swarm.sh mention left once every SWARM_PROJECT=<project> <swarm.sh> is
# taken out, one per line: only finding_rule's names for where a finding came from.
unpinned() { python3 -c 'import re, sys; t = open(sys.argv[1]).read().replace(sys.argv[2], ""); print("\n".join(sorted(set(re.findall(r"\S*swarm\.sh \S+", t)))))' "$1" "SWARM_PROJECT=${p} ${SWARM}"; }
fwhere=$'`swarm.sh codex-review`\n`swarm.sh findings`'
check "every swarm.sh call in both briefs names the project, and the only bare mentions are finding_rule's two sources" "yes|${fwhere}|${fwhere}" \
  "$( [[ "$(grep -o "${SWARM} " "${p}/.swarm/briefs/review-h1.md" | wc -l)" == "$(grep -o "SWARM_PROJECT=${p} ${SWARM} " "${p}/.swarm/briefs/review-h1.md" | wc -l)" ]] && echo yes || echo no)|$(unpinned "${p}/.swarm/briefs/review-h1.md")|$(unpinned "${p}/.swarm/briefs/review-h2.md")"
check "both briefs' first line is still the one review_brief_url reads, and neither says never merge" "yes|yes|0|0" \
  "$(has "Review ${PRA}, the PR of story h1, at its head ${HEAD_SHA}, in this worktree." "$(head -1 "${p}/.swarm/briefs/review-h1.md")")|$(has "Review ${PRB}, the PR of story h2, at its head ${HEAD_SHA}, in this worktree." "$(head -1 "${p}/.swarm/briefs/review-h2.md")")|$(grep -ci 'never merge' <<< "${abrief}" || true)|$(grep -ci 'never merge' <<< "${hbrief}" || true)"
a_review="$(cmd_in "${abrief}" "swarm.sh review h1 --head ")"; a_merge="$(cmd_in "${abrief}" "swarm.sh merge --head ")"
h_review="$(cmd_in "${hbrief}" "swarm.sh review h2 --head ")"; h_grants="$(cmd_in "${hbrief}" "swarm.sh grants ")"; h_merge="$(cmd_in "${hbrief}" "swarm.sh merge --head ${HEAD_SHA} ")"
check "the merge = agent brief has one review --head and one merge --head command on the head it reviews; the merge = human one adds a grants command and none to merge outside it" \
  "SWARM_PROJECT=${p} ${SWARM} review h1 --head ${HEAD_SHA} ${PRA}|SWARM_PROJECT=${p} ${SWARM} merge --head ${HEAD_SHA} ${PRA}|SWARM_PROJECT=${p} ${SWARM} review h2 --head ${HEAD_SHA} ${PRB}|SWARM_PROJECT=${p} ${SWARM} grants ${PRB}|0" \
  "${a_review}|$(grep -v '<new head>' <<< "${a_merge}")|${h_review}|${h_grants}|$(grep -c "grants ${PRA}" <<< "${abrief}" || true)"
check "a grants lookup that fails twice hands the PR to the user, saying so" "yes" \
  "$(has "When it exits 0 with no \`merge\` line, the review is the handoff: the PR waits on the user's merge, so merge nothing. When it fails, run it once more; a second failure hands the PR to the user too, and your reply says grants failed." "${hbrief}")"
# A head pushed since the review is not reviewed in this session: it ends the agent with head moved:
# and a stop note, on which the conductor starts a new review agent on the new head.
check "a moved head after a pass writes head moved: and stops, names who restarts the review, and flags a story left in review" "yes|yes|yes|0" \
  "$(has "When review or merge refuses because the PR's head is no longer ${HEAD_SHA} (a push since your review), that head has had no review, and you do not review it in this session." "${abrief}")|$(has "Write ${p}/.swarm/reviews/h1.md again with the Write tool, holding two lines, \`head: ${HEAD_SHA}\` and \`head moved: <the head review or merge named>\`, then send the conductor the stop note, as below, naming that \`head moved:\` line, and stop: the conductor starts a new review agent on the new head on that note (the lead does when no conductor runs)." "${abrief}")|$(has "your reply's first line says \`h1 is in review on <the new head>, which nobody reviewed\`" "${abrief}")|$(grep -c "that head has had no review: run" <<< "${abrief}" || true)"
# A merge whose base moved merges the base in, waits and merges the new head itself: the review agent
# leaves it running, reads already merged: as done, nudges the builder on a red or conflicting
# base-merged head, takes any other base merged, <cause>: refusal as any other, and never runs
# wait-pr or merge --head on a new head of its own.
check "the hand-off says merge may merge the base in, wait and merge the new head itself, which the agent leaves to finish" "yes|yes|yes|0" \
  "$(has "When the base gained code since ${HEAD_SHA}'s CI ran, it first has GitHub merge the base into the PR's branch and waits up to 30 minutes for that new head's CI, 3 rounds at most; after the merge it waits up to 30 minutes for CI on the base, then reconciles." "${abrief}")|$(has "When merge prints \`base merged: <PR URL> is now ...\`, GitHub merged the base into the PR's branch: that head needs no new review, and merge goes on to wait for its CI and merge it, so leave it running until it exits." "${abrief}")|$(has "When it prints \`already merged:\`, the PR merged elsewhere while it waited, and merge reconciled the board. When it refuses with \`base merged, red:\` or \`base merged, conflict:\`," "${abrief}")|$(grep -c "merge --head <new head>" <<< "${abrief}" || true)"
# from_pane <slug> <command> — <command> as review-<slug> runs it: from its pane, in its story's
# worktree, with SWARM_AGENT its name as start_agent gives it, the merge stub's gh first and merge's
# CI waits cut short.
from_pane() {
  local pane; pane="$(awk -v n="review-$1" '$1 == n { p = $2 } END { print p }' "${ROOT}/agents")"
  (cd "${ROOT}/svc-wt/$1" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w HERDR_PANE_ID="${pane}" PATH="${MGH}:${STUB_BIN}:${PATH}" \
    SWARM_AGENT="review-$1" SWARM_MERGE_POLL=0 SWARM_MERGE_READ_WAIT=0 SWARM_MERGE_CI_GRACE=0 SWARM_MERGE_CI_SECONDS=5 bash -c "$2" 2>&1)
}
# fm_of <slug> <key> — <key> of the story as swarm.sh reads it: its state over its front matter.
# shellcheck source=/dev/null
fm_of() { (export BOARD="${b}" PROJECT_DIR="${p}"; . "${SWARM%/*}/lib/board.sh"; get_fm "${b}/stories/$1.md" "$2"); }
: > "${p}/.claude/swarm/config"
echo bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb > "${FXH}/head"
check "merge = human: the brief's review --head on a PR whose head moved exits non-zero, names review-agent --next, and leaves h2 ready" "1|yes|ready" \
  "$(set +e; o="$(from_pane h2 "${h_review}")"; echo "$?|$(has "swarm.sh review-agent --next h2 ${PRB} once this round sent the builder findings; after a pass, a new swarm.sh review-agent h2 ${PRB}" "${o}")")|$(fm_of h2 status)"
echo "${HEAD_SHA}" > "${FXH}/head"
# One review agent passes one PR, and prs: is empty until review: a second open PR from story/h2 would be
# left behind when the first merged and the story finished.
echo '[{"url":"https://github.com/o/svc/pull/14"}]' > "${FXH}/prlist.h2"
check "review --head while story/h2 has another open PR refuses, naming it, and leaves h2 ready" "1|yes|ready" \
  "$(set +e; o="$(from_pane h2 "${h_review}")"; echo "$?|$(has "h2 also has https://github.com/o/svc/pull/14, which this review did not cover; h2 is unchanged" "${o}")")|$(fm_of h2 status)"
rm "${FXH}/prlist.h2"
o="$(from_pane h2 "${h_review}")" || echo "FAIL the brief's review --head for h2 exited non-zero: ${o}"
check "with the head the review passed, h2 goes to review with its PR, logged as review h2 ok (<PR URL>) with round=1 verdict=pass" "review|${PRB}|ok (${PRB}) ~~ round=1 verdict=pass" \
  "$(fm_of h2 status)|$(fm_of h2 prs)|$(awk -F'\t' '$2 == "review" && $3 == "h2" { l = $5 } END { print l }' "${p}/.swarm/events.tsv" | no_version)"
# One review agent passes one PR: a review --head that does not name every PR on prs: would replace the
# line and drop the others, so the story could finish without them.
check "review --head naming one PR while prs: lists another refuses, naming it, and leaves prs: as it was" "1|yes|${PRB}" \
  "$(set +e; o="$(from_pane h2 "SWARM_PROJECT=${p} ${SWARM} review h2 --head ${HEAD_SHA} https://github.com/o/svc/pull/13")"; echo "$?|$(has "h2 also has ${PRB}, which this review did not cover; h2 is unchanged" "${o}")")|$(fm_of h2 prs)"
# The grants step as the brief writes it: merge only when grants prints a merge line.
g="$(from_pane h2 "${h_grants}")"
if grep -qx merge <<< "${g}"; then from_pane h2 "${h_merge}" > /dev/null || true; fi
check "merge = human with no grant: grants prints none, no gh pr merge runs, and h2 stays in review" "none|0|review" \
  "${g}|$(grep -c '^pr merge' "${MX}/gh.log" || true)|$(fm_of h2 status)"
echo "merge = agent" > "${p}/.claude/swarm/config"
# The pass as the brief orders it: the review file first, so the conductor's wait returns on it before
# the merge's reconcile retires review-h1 (a wait on a retired name has no agent to wait on).
check "the brief writes h1's review file before its review --head" "yes" \
  "$(python3 -c 'import sys; t = sys.argv[1]; a = t.find(sys.argv[2]); b = t.find(sys.argv[3]); print("yes" if 0 <= a < b else "no")' "${abrief}" "Write the review to ${p}/.swarm/reviews/h1.md first" "review h1 --head ${HEAD_SHA}")"
# The steps the brief puts before its review --head, in its order: the review file is written there
# only when the brief writes it first.
before="${abrief%%"review h1 --head ${HEAD_SHA}"*}"
if [[ "${before}" == *"Write the review to ${p}/.swarm/reviews/h1.md first"* ]]; then
  printf '%s\n' "head: ${HEAD_SHA}" "## Findings" "none" "## Handled by the review agent" "none" > "${p}/.swarm/reviews/h1.md"
fi
done_agent review-h1
check "with the pass file written and review-h1 idle while its merge runs, the conductor's wait on it returns idle" "idle" \
  "$(run wait review-h1 5000)"
o="$(from_pane h1 "${a_review}")" || echo "FAIL the brief's review --head for h1 exited non-zero: ${o}"
from_pane h1 "$(grep -v '<new head>' <<< "${a_merge}")" > "${ROOT}/merge-h1.out" || true
check "merge = agent: the brief's merge --head from review-h1's pane reaches gh pr merge, pinned to the head it reviewed" \
  "pr merge 11 --repo o/svc --squash --match-head-commit ${HEAD_SHA}" "$(grep '^pr merge' "${MX}/gh.log" || cat "${ROOT}/merge-h1.out")"
# The lead's backlog review arm (commands/swarm.md's kept: line) starts the review agent and leaves the
# PR to it: no findings tell or merge of its own beside the agent's.
# shellcheck disable=SC2016 # the backticks are the doc's
kept="$(python3 -c 'import re, sys; t = " ".join(open(sys.argv[1]).read().split()); m = re.search(r"`kept: <slug> <PR URL>\.\.\. \(not reviewed\)` line.*?Run `swarm\.sh close <slug> --drop`", t); print(m.group(0) if m else "")' "$(dirname "${SWARM}")/../commands/swarm.md")"
# The lead merges only on the multi-PR path, once every PR's agent has stopped.
single="${kept%%Once every PR has passed*}"
check "the lead's kept arm starts review-agent once, waits on it (again while busy, and with no file checks the board before a restart), restarts it on a moved head, and never tells findings or merges beside it" "yes|yes|yes|yes|0|0" \
  "$(has "Then run \`swarm.sh review-agent <slug> <PR URL>\` for the line's first PR, unless \`review-<slug>\` is already open on it, and wait on it with \`swarm.sh wait review-<slug>\` in the background." "${kept}")|$(has "When the wait returns with no review file and printed \`busy\`, it ran its 60 minutes while the agent works: wait again. When it returns with no review file any other way (the agent waits on a prompt, is gone, or a merge's reconcile retired it), check the board first" "${kept}")|$(has "Once the file is there, read it before the board. If it has a \`head moved:\` line, the PR has a head nobody reviewed and the agent stopped: once the worktree is at the PR's head, start \`swarm.sh review-agent <slug> <PR URL>\` again" "${kept}")|$(has "While it is open, never triage its review file, tell the builder findings or merge the PR yourself" "${kept}")|$(grep -c 'tell <slug> findings' <<< "${kept}" || true)|$(grep -c 'swarm.sh merge' <<< "${single}" || true)"
# A story in review is no pass while its file says head moved: (merge refused a push after review put it
# there), and a multi-PR line's heads may have moved since each agent passed its PR.
check "the kept arm reads head moved: and stopped: before taking a story in review as a pass, and re-reads each PR's head before a multi-PR review" "yes|yes" \
  "$(python3 -c 'import sys; t = sys.argv[1]; a = t.find(sys.argv[2]); b = t.find(sys.argv[3]); c = t.find(sys.argv[4]); print("yes" if 0 <= a < b < c else "no")' "${kept}" "If it has a \`head moved:\` line" "If the file has a \`stopped:\` line" "Otherwise the file is a pass. If the story is in review with no \`kept:\` line")|$(has "Once every PR has passed, read each PR's head again (\`gh pr view <PR URL> --json headRefOid --jq .headRefOid\`) and compare it with the head noted for it: a PR whose head moved since has had no review, so start the review agent on it again. Only when every PR's head is still the one that passed, run \`swarm.sh review <slug>\` with every PR URL on the line" "${kept}")"

check "policy review prints claude opus high" "claude opus high" "$(run policy review)"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
