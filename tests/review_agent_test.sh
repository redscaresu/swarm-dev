#!/usr/bin/env bash
# review_agent_test.sh — swarm.sh review-agent <slug> <PR>: it starts review-<slug> in the story's
# worktree with role review and returns at once, with a brief scoped to the story and its PR's head;
# several run side by side, and each is waited on alone. herdr is a stub on PATH whose agents stay
# working until the test marks them done (done <name>): its agent wait blocks until then, or its
# timeout. The claude stub lists their sessions busy until then, idle after. gh's PR head is the
# file ${ROOT}/head.
set -euo pipefail

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
  "agent prompt") # prompt holds how the brief goes: fail (herdr surely sent nothing), unread (no reply
                  # read), unreadgone (unread, and review-s13's pane gone), or sent (sent, and never taken up).
                  case "$(cat "$H/prompt" 2>/dev/null)" in
                    fail) echo '{"error":{"code":"server_unavailable"}}' >&2; exit 1 ;;
                    unread) exit 1 ;;
                    unreadgone) awk '$1 != "review-s13"' "$H/agents" > "$H/agents.new" && mv "$H/agents.new" "$H/agents"; exit 1 ;;
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
  "agent list")   awk -v d="$H/done" 'BEGIN { printf "{\"result\":{\"agents\":[" }
                    { s = system("test -e " d "/" $1) == 0 ? "idle" : "working"
                      printf "%s{\"name\":\"%s\",\"agent_status\":\"%s\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, s, $2 }
                    END { print "]}}" }' "$H/agents" 2>/dev/null || echo '{"result":{"agents":[]}}' ;;
esac
EOF
# sessions: Claude Code's list, one entry per agent started, busy until done/<name> exists.
cat > "${ROOT}/sessions" <<EOF
#!/bin/sh
awk -v d="${ROOT}/done" 'BEGIN { printf "[" }
  { s = system("test -e " d "/" \$1) == 0 ? "idle" : "busy"
    printf "%s{\"sessionId\":\"%s\",\"status\":\"%s\"}", (NR > 1 ? "," : ""), \$3, s }
  END { print "]" }' "${ROOT}/agents" > "${ROOT}/claude.json"
EOF
printf '#!/bin/sh\ncat "%s/head"\n' "${ROOT}" > "${STUB_BIN}/gh"
chmod +x "${STUB_BIN}/herdr" "${STUB_BIN}/gh" "${ROOT}/sessions"; mkdir -p "${ROOT}/done"; echo '[]' > "${ROOT}/claude.json"
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
back=""; echo "head: STALE" > "${p}/.swarm/reviews/s2.md"
for s in s2 s3 s4; do back+="${s}:$(start "${s}") "; done
check "a start removes the story's findings file from an earlier head, and leaves no copy aside, so its wait cannot end on it" "no|no" \
  "$([[ -e "${p}/.swarm/reviews/s2.md" ]] && echo yes || echo no)|$([[ -e "${p}/.swarm/reviews/s2.md.prev" ]] && echo yes || echo no)"
check "review-agent s2 to s4 each return within 10s while no review is done" "s2:back:0 s3:back:0 s4:back:0 " "${back}"
check "a stacked story's brief leaves its parents' code out; another's says nothing of stacking" "yes|yes|0" \
  "$(has "This story is stacked on s1: their branches (origin/story/s1) are in its diff against origin/main" "$(cat "${p}/.swarm/briefs/review-s2.md")")|$(has "it is neither a finding nor out of scope" "$(cat "${p}/.swarm/briefs/review-s2.md")")|$(grep -c stacked "${p}/.swarm/briefs/review-s3.md" || true)"
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
# but no head goes on record, so watch and next still call the PR unreviewed.
echo sent > "${ROOT}/prompt"; touch "${ROOT}/getidle" "${ROOT}/done/review-s11"
check "when review-s11's brief was not taken up after 2 tries, review-agent exits 0, says it may have it, keeps the old findings aside and records no head" "0|yes|no|head: OLD-REVIEW|no" \
  "$(set +e; o="$(SWARM_SLEEP_SCALE=0.02 run review-agent s11 "${PR}")"; echo "$?|$(has "may have its brief" "${o}")")|$([[ -e "${p}/.swarm/reviews/s11.md" ]] && echo yes || echo no)|$(cat "${p}/.swarm/reviews/s11.md.prev")|$([[ -e "${p}/.swarm/reviews/s11.head" ]] && echo yes || echo no)"
# A .prev an earlier run left, with no findings file now, is an older head's: a failed start never
# puts it back.
sed "s/s4/s12/g" "${b}/stories/s4.md" > "${b}/stories/s12.md"
"${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b story/s12 "${ROOT}/svc-wt/s12" origin/main
echo "head: OLDER-REVIEW" > "${p}/.swarm/reviews/s12.md.prev"; echo fail > "${ROOT}/prompt"; touch "${ROOT}/done/review-s12"
check "a failed start of review-s12 does not bring back an older run's findings left aside" "1|no|no" \
  "$(set +e; run review-agent s12 "${PR}" >/dev/null; echo "$?")|$([[ -e "${p}/.swarm/reviews/s12.md" ]] && echo yes || echo no)|$([[ -e "${p}/.swarm/reviews/s12.md.prev" ]] && echo yes || echo no)"
rm "${ROOT}/prompt" "${ROOT}/getidle"
# With no pane left, an error that says the brief may have gone out still fails and puts the file back.
sed "s/s4/s13/g" "${b}/stories/s4.md" > "${b}/stories/s13.md"
"${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b story/s13 "${ROOT}/svc-wt/s13" origin/main
echo "head: OLD-REVIEW" > "${p}/.swarm/reviews/s13.md"; echo unreadgone > "${ROOT}/prompt"
check "when review-s13's brief may have gone out but its pane is gone, review-agent fails and puts the findings back" "1|head: OLD-REVIEW|no" \
  "$(set +e; SWARM_SLEEP_SCALE=0.02 run review-agent s13 "${PR}" >/dev/null; echo "$?")|$(cat "${p}/.swarm/reviews/s13.md")|$([[ -e "${p}/.swarm/reviews/s13.md.prev" ]] && echo yes || echo no)"
rm "${ROOT}/prompt"

# --- An agent that writes its findings before review-agent returns keeps them: only the last
# review's file is removed.
sed "s/s4/s7/g" "${b}/stories/s4.md" > "${b}/stories/s7.md"
"${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b story/s7 "${ROOT}/svc-wt/s7" origin/main
echo "head: OLD-REVIEW" > "${p}/.swarm/reviews/s7.md"; touch "${ROOT}/quick"
check "a review written while its brief is delivered survives the start, and the old one is gone" "back:0|head: NEW-REVIEW|no" \
  "$(start s7)|$(cat "${p}/.swarm/reviews/s7.md" 2>/dev/null)|$([[ -e "${p}/.swarm/reviews/s7.md.prev" ]] && echo yes || echo no)"
rm "${ROOT}/quick"

check "policy review prints claude opus high" "claude opus high" "$(run policy review)"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
