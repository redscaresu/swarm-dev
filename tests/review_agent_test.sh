#!/usr/bin/env bash
# review_agent_test.sh — swarm.sh review-agent <slug> <PR>: it starts review-<slug> in the story's
# worktree with role review and returns at once, with a brief scoped to the story; several run side by
# side, and each is waited on alone. herdr is a stub on PATH whose agents stay working until the test
# marks them done (done <name>); the claude stub lists their sessions busy until then, idle after.
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
# agent list shows each working, or idle once done/<name> exists. agent wait returns at once.
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
  "agent wait")   echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
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
chmod +x "${STUB_BIN}/herdr" "${ROOT}/sessions"; mkdir -p "${ROOT}/done"; echo '[]' > "${ROOT}/claude.json"
done_agent() { touch "${ROOT}/done/$1"; echo "done $1" >> "${ROOT}/herdr.log"; "${ROOT}/sessions"; }

# A repo svc, built stories s1..s4 of epic e (each with a worktree), and a project whose board names it.
"${GIT[@]}" init -q --bare "${ROOT}/svc.git"
"${GIT[@]}" clone -q "${ROOT}/svc.git" "${ROOT}/svc" 2>/dev/null
"${GIT[@]}" -C "${ROOT}/svc" commit -q --allow-empty -m init && "${GIT[@]}" -C "${ROOT}/svc" push -q origin main
p="${ROOT}/proj"; b="${p}/docs"
mkdir -p "${p}/.claude/swarm" "${b}/stories"; : > "${p}/.claude/swarm/config"
for s in s1 s2 s3 s4; do
  printf '%s\n' --- "status: review" "kind: code" "epic: e" "repo: svc" "touches: [bin/${s}.sh:fn_${s}]" --- "" "# ${s}" "" \
    "**Done when:**" "- ${s} DONE-ONE holds" "- ${s} DONE-TWO holds" > "${b}/stories/${s}.md"
  "${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b "story/${s}" "${ROOT}/svc-wt/${s}" origin/main
done
PR=https://github.com/o/svc/pull/1
run() { (cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${STUB_BIN}:${PATH}" bash "${SWARM}" "$@" 2>&1); }

# --- One review agent: started in s1's worktree with role review, its brief scoped to s1.
out="$(run review-agent s1 "${PR}")" || { echo "FAIL review-agent s1 failed: ${out}"; exit 1; }
check "review-agent s1 starts review-s1 in s1's worktree, with review's model and effort" "yes|yes|yes" \
  "$(has "tab create --workspace w --cwd ${ROOT}/svc-wt/s1 --label e" "$(cat "${ROOT}/herdr.log")")|$(has "agent start review-s1 " "$(cat "${ROOT}/herdr.log")")|$(has "review-s1 w:1 claude:opus:high" "${out}")"
check "agents.tsv records review-s1 with role review" "review" "$(awk -F'\t' '$3 == "review-s1" { print $2 }' "${p}/.swarm/agents.tsv")"
brief="$(cat "${p}/.swarm/briefs/review-s1.md")"
check "the brief holds s1's touches, each Done when item, SWARM_STORY=s1, /code-review <PR>, not a finding and the absolute reviews file" \
  "yes|yes|yes|yes|yes|yes|yes" \
  "$(has "bin/s1.sh:fn_s1" "${brief}")|$(has "- s1 DONE-ONE holds" "${brief}")|$(has "- s1 DONE-TWO holds" "${brief}")|$(has "SWARM_STORY=s1 " "${brief}")|$(has "/code-review ${PR}" "${brief}")|$(has "not a finding" "${brief}")|$(has "${p}/.swarm/reviews/s1.md" "${brief}")"
check "the reviews directory exists" "yes" "$([[ -d "${p}/.swarm/reviews" ]] && echo yes || echo no)"
check "events.tsv gains a review-agent line whose target is s1" "s1	ok" \
  "$(awk -F'\t' '$2 == "review-agent" { print $3 "\t" $5 }' "${p}/.swarm/events.tsv")"

# --- Four at once: each returns while its agent still works, and each is waited on alone.
for s in s2 s3 s4; do run review-agent "${s}" "${PR}" >/dev/null || { echo "FAIL review-agent ${s} failed"; exit 1; }; done
check "herdr lists review-s1 to review-s4 working at once" "review-s1 working|review-s2 working|review-s3 working|review-s4 working" \
  "$(PATH="${STUB_BIN}:${PATH}" herdr agent list | python3 -c 'import json, sys; print("|".join(a["name"] + " " + a["agent_status"] for a in json.load(sys.stdin)["result"]["agents"]))')"
done_agent review-s3
check "the stub's log shows four starts before any review is marked done" "4" \
  "$(awk '/^done / { exit } /^agent start review-s[1-4] / { n++ } END { print n + 0 }' "${ROOT}/herdr.log")"
check "with review-s3 done first, wait review-s3 returns idle" "idle" "$(run wait review-s3 5000)"
check "while the other three still work: a wait on review-s1 times out busy" "busy|1" \
  "$(set +e; o="$(run wait review-s1 600 2>/dev/null)"; echo "${o}|$?")"
check "and herdr still lists them working" "review-s1 working|review-s2 working|review-s4 working" \
  "$(PATH="${STUB_BIN}:${PATH}" herdr agent list | python3 -c 'import json, sys; print("|".join(a["name"] + " " + a["agent_status"] for a in json.load(sys.stdin)["result"]["agents"] if a["name"] != "review-s3"))')"
for s in s1 s2 s3 s4; do
  check "review-${s}'s brief names only its own story's reviews file" "${p}/.swarm/reviews/${s}.md" \
    "$(grep -o "${p}/.swarm/reviews/[a-z0-9-]*\.md" "${p}/.swarm/briefs/review-${s}.md" | sort -u | paste -sd' ' -)"
done

# --- A story named review-s1 would share the review agent's name: refused, nothing started.
printf '%s\n' --- "status: ready" "kind: code" --- > "${b}/stories/review-s1.md"
: > "${ROOT}/herdr.log"
check "a board with a story named review-s1 makes review-agent s1 fail with nothing started" "1|no" \
  "$(set +e; run review-agent s1 "${PR}" >/dev/null; echo "$?")|$(grep -q 'agent start\|tab create\|pane split' "${ROOT}/herdr.log" && echo yes || echo no)"
check "policy review prints claude opus high" "claude opus high" "$(run policy review)"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
