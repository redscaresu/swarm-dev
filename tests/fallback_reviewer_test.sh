#!/usr/bin/env bash
# fallback_reviewer_test.sh — codex-review on a codex usage limit: it always logs a codex-limit
# incident; with fallback_reviewer set it starts fallback-<story> (role review-fallback, on that
# model), waits for its findings file and prints it in codex's place; with the key empty no agent
# starts and the output is codex's own, as before. Also the builder brief's codex rule, which names the
# PR body's "reviewed by fallback" line. codex, herdr and claude are stubs on PATH: herdr's agent
# writes its findings file as its brief arrives, then goes idle.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
# No .claude.json here, so require_trusted lets the agent start. A wait checks the session often.
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects" SWARM_STALL_POLL_MS=200 \
  SWARM_CONDUCTOR_POLL=1 CLAUDE_STUB_AGENTS="${ROOT}/claude.json"
BIN="${ROOT}/stub-bin"; mkdir -p "${BIN}" "${ROOT}/done"; echo '[]' > "${ROOT}/claude.json"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${BIN}/claude"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }

LIMIT_MSG="ERROR: You've hit your usage limit. Try again later."
printf '#!/bin/sh\necho "%s" >&2\nexit 1\n' "${LIMIT_MSG}" > "${BIN}/codex"
# herdr: logs every call; panes are w:<n>. agent start records "<name> <pane> <session>"; agent
# prompt writes the findings file the brief names and marks the agent done; agent list and wait
# report it idle once done.
cat > "${BIN}/herdr" <<EOF
#!/bin/sh
H="${ROOT}"
EOF
cat >> "${BIN}/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
case "$1 $2" in
  "tab create")   echo '{"result":{"root_pane":{"pane_id":"w:1"}}}' ;;
  "agent start")  echo "$3 w:1 $(echo "$*" | sed -n 's/.*--session-id \([^ ]*\).*/\1/p')" >> "$H/agents"
                  "$H/sessions" ;;
  "agent prompt") f=$(echo "$4" | grep -o '/[^ ]*/\.swarm/reviews/[a-z0-9-]*\.md' | head -1)
                  printf '%s\n' '- [P1] STUB FINDING — x.sh:3' '  drops the error' > "$f"
                  touch "$H/done/$(awk '{ print $1 }' "$H/agents" | tail -1)"; "$H/sessions"
                  echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent wait")   echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
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
chmod +x "${BIN}/codex" "${BIN}/herdr" "${ROOT}/sessions"

# A git project with story s1.
p="${ROOT}/proj"
mkdir -p "${p}/.claude/swarm" "${p}/docs/stories"
git -c init.defaultBranch=main init -q "${p}"
printf '%s\n' --- "status: ready" "kind: code" "touches: [x.sh]" --- "" "# s1" "" "**Done when:**" "- it holds" > "${p}/docs/stories/s1.md"
# review [config line] — codex-review main for s1 with that config: sets out and rc.
review() {
  printf '%s\n' "$@" > "${p}/.claude/swarm/config"
  rc=0; out="$(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w SWARM_STORY=s1 PATH="${BIN}:${PATH}" \
    bash "${SWARM}" codex-review main 2>&1)" || rc=$?
}
incidents() { awk -F'\t' '$2 == "incident" { print $3 "|" $5 }' "${p}/.swarm/events.tsv"; }

# --- Key empty: no agent, codex's output and exit as before, and the incident.
review
check "with fallback_reviewer empty, codex-review exits as codex did, with codex's output alone" "1|${LIMIT_MSG}" "${rc}|${out}"
check "with fallback_reviewer empty, no agent starts" "no" "$(grep -q '^agent start' "${ROOT}/herdr.log" 2>/dev/null && echo yes || echo no)"
check "with fallback_reviewer empty, the codex-limit incident is logged" "s1|codex-limit: usage limit" "$(incidents)"

# --- fallback_reviewer = sonnet: the fallback agent starts on sonnet, and its findings are printed.
review "fallback_reviewer = sonnet"
check "with fallback_reviewer = sonnet, codex-review exits 0" "0" "${rc}"
check "the fallback agent starts as fallback-s1 on sonnet" "yes" \
  "$(grep -q '^agent start fallback-s1 .*--model sonnet ' "${ROOT}/herdr.log" && echo yes || echo no)"
check "agents.tsv records it with role review-fallback" "review-fallback" \
  "$(awk -F'\t' '$3 == "fallback-s1" { print $2 }' "${p}/.swarm/agents.tsv")"
check "its brief holds codex's story prompt" "yes" "$(has "Its Done when:" "$(cat "${p}/.swarm/briefs/fallback-s1.md")")"
check "the stub's findings appear in codex-review's stdout" "yes" "$(has "- [P1] STUB FINDING — x.sh:3" "${out}")"
check "stdout names the fallback for the PR body" "yes" "$(has "reviewed by fallback sonnet: codex usage limit" "${out}")"
check "with fallback_reviewer set, the codex-limit incident is logged too" "s1|codex-limit: usage limit" "$(incidents | tail -1)"
check "one incident per run" "2" "$(incidents | wc -l | tr -d ' ')"

# --- A codex that fails without a usage limit logs no incident and starts no fallback.
printf '#!/bin/sh\necho "boom" >&2\nexit 2\n' > "${BIN}/codex"
: > "${ROOT}/herdr.log"
review "fallback_reviewer = sonnet"
check "another failure exits as codex did, with no incident and no agent" "2|2|no" \
  "${rc}|$(incidents | wc -l | tr -d ' ')|$(grep -q '^agent start' "${ROOT}/herdr.log" && echo yes || echo no)"

# --- Its findings are logged with --reviewer fallback.
check "log-finding --reviewer fallback is accepted and recorded" "0|fallback" \
  "$(cd "${p}" && env -u SWARM_PROJECT -u HERDR_ENV bash "${SWARM}" log-finding --reviewer fallback drops-error https://github.com/o/r/pull/1 "x.sh drops the error" >/dev/null 2>&1; echo "$?")|$(cut -f6 "${p}/.swarm/findings.tsv" 2>/dev/null | tail -1)"

# --- The builder brief's codex rule names the PR body's line.
brief="$(cd "${p}" && env -u SWARM_PROJECT -u HERDR_ENV PATH="${BIN}:${PATH}" bash "${SWARM}" _brief s1 2>&1)"
check "the built brief's codex rule names 'reviewed by fallback' for the PR body" "yes" \
  "$(has 'the PR says "reviewed by fallback <model>: codex usage limit"' "${brief}")"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
