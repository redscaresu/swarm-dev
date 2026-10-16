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
  "tab create")   next; echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "pane split")   next; echo "{\"result\":{\"pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "agent start")  echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/') $(echo "$*" | sed -n 's/.*--session-id \([^ ]*\).*/\1/p')" >> "$H/agents"
                  "$H/sessions" ;;
  "agent prompt") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent wait")   name=$(awk -v p="$3" '$2 == p { print $1 }' "$H/agents")
                  ms=$(echo "$*" | sed -n 's/.*--timeout \([0-9]*\).*/\1/p'); ticks=$(( ${ms:-10000} / 100 ))
                  while [ ! -e "$H/done/$name" ]; do
                    [ "$ticks" -gt 0 ] || { echo '{"error":{"code":"timeout"}}' >&2; exit 1; }
                    ticks=$((ticks - 1)); sleep 0.1
                  done
                  echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
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
check "the reviews file exists and starts with the head reviewed" "head: ${HEAD_SHA}" "$(cat "${p}/.swarm/reviews/s1.md")"
check "events.tsv gains a review-agent line whose target is s1 (the newest, after the refusals')" "s1	ok" \
  "$(awk -F'\t' '$2 == "review-agent" { l = $3 "\t" $5 } END { print l }' "${p}/.swarm/events.tsv")"

# --- A refused second start leaves the findings file and the brief as they were.
echo "head: ${HEAD_SHA} FINDINGS-KEPT" > "${p}/.swarm/reviews/s1.md"; echo BRIEF-KEPT >> "${p}/.swarm/briefs/review-s1.md"
echo mark >> "${ROOT}/herdr.log"
check "with review-s1 still working, review-agent s1 fails, starts nothing, and keeps its findings file and brief" "1|0|yes|yes" \
  "$(set +e; run review-agent s1 "${PR}" >/dev/null; echo "$?")|$(started)|$(has FINDINGS-KEPT "$(cat "${p}/.swarm/reviews/s1.md")")|$(has BRIEF-KEPT "$(cat "${p}/.swarm/briefs/review-s1.md")")"

# --- Four at once: each start returns while every agent still works (herdr's wait would block),
# and each is waited on alone.
back=""
for s in s2 s3 s4; do back+="${s}:$(start "${s}") "; done
check "review-agent s2 to s4 each return within 10s while no review is done" "s2:back:0 s3:back:0 s4:back:0 " "${back}"
check "herdr lists review-s1 to review-s4 working at once" "review-s1 working|review-s2 working|review-s3 working|review-s4 working" "$(working)"
done_agent review-s3
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
for s in s1 s2 s4; do done_agent "review-${s}"; done
wait

check "policy review prints claude opus high" "claude opus high" "$(run policy review)"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
