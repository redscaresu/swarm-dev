#!/usr/bin/env bash
# codex_rate_limit_test.sh — codex-review on codex's rate limit: the line codex printed on Azure Foundry
# (and its 429 retry line) is a limit as codex's usage limit is. It logs a `codex-limit: rate limit`
# incident, and with fallback_reviewer set a fallback reviews in codex's place under "reviewed by fallback
# <model>: codex rate limit". A review that only quotes the words (codex exits 0, the words sit above its
# last 5 lines, or a diff line holds them) logs no incident. A failed codex keeps its last 20 lines in
# .swarm/codex/<story>.tail. The briefs codex_rule and review_brief say "usage or rate limit". codex,
# herdr and claude are stubs on PATH, as in fallback_reviewer_test.sh: herdr's agent writes its findings
# file as its brief arrives, then goes idle.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
# No .claude.json here, so require_trusted lets the agent start. A wait checks the session often.
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects" SWARM_STALL_POLL_MS=200 \
  SWARM_CONDUCTOR_POLL=1 CLAUDE_STUB_AGENTS="${ROOT}/claude.json"
BIN="${ROOT}/stub-bin"; mkdir -p "${BIN}" "${ROOT}/done"; echo '[]' > "${ROOT}/claude.json"; : > "${ROOT}/agents"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${BIN}/claude"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }
logged() { if grep -q -- "$1" "${ROOT}/herdr.log" 2>/dev/null; then echo yes; else echo no; fi; }

# The line codex 0.164.0 printed on three runs against Azure Foundry on 2026-11-01, after five
# reconnect lines, verbatim.
RATE_MSG="ERROR: rate limit exceeded: Your requests to gpt-6.1-sol for gpt-6.1-sol in swedencentral have exceeded token rate limit."
RECONNECTS=("ERROR: Reconnecting... 1/5" "ERROR: Reconnecting... 2/5" "ERROR: Reconnecting... 3/5" "ERROR: Reconnecting... 4/5" "ERROR: Reconnecting... 5/5")
codex_says() { printf '#!/bin/sh\n'; printf 'echo "%s" >&2\n' "${@:2}"; printf 'exit %s\n' "$1"; } # <exit> <line>...
# herdr: logs every call. Tab t:<n> holds pane w:<n>. agent start records "<name> <pane> <session>";
# agent prompt writes the findings file the brief names and marks the agent done; a pane or tab close
# drops its agent. agent list and wait report it idle once done.
cat > "${BIN}/herdr" <<EOF
#!/bin/sh
H="${ROOT}"
EOF
cat >> "${BIN}/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
drop() { awk -v p="$1" '$2 != p' "$H/agents" > "$H/agents.tmp" && mv "$H/agents.tmp" "$H/agents"; }
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;
  "tab create")   n=$(($(cat "$H/n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/n"
                  echo "t:$n $(echo "$*" | sed 's/.*--label \([^ ]*\).*/\1/')" >> "$H/tabs"
                  echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "tab list")     awk 'BEGIN { printf "{\"result\":{\"tabs\":[" }
                    { printf "%s{\"tab_id\":\"%s\",\"label\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                    END { print "]}}" }' "$H/tabs" ;;
  "tab close")    drop "w:${3#t:}" ;;
  "pane close")   drop "$3" ;;
  "agent start")  rm -f "$H/done/$3"
                  echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/') $(echo "$*" | sed -n 's/.*--session-id \([^ ]*\).*/\1/p')" >> "$H/agents"
                  "$H/sessions" ;;
  "agent prompt") f=$(echo "$4" | grep -o '/[^ ]*/\.swarm/reviews/fallback/[a-z0-9-]*\.md' | head -1)
                  printf '%s\n' '- [P1] STUB FINDING — x.sh:3' '  drops the error' > "$f"
                  touch "$H/done/$(awk -v p="$3" '$2 == p { print $1 }' "$H/agents")"; "$H/sessions"
                  echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent wait")   echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent list")   awk -v d="$H/done" 'BEGIN { printf "{\"result\":{\"agents\":[" }
                    { s = system("test -e " d "/" $1) == 0 ? "idle" : "working"
                      printf "%s{\"name\":\"%s\",\"agent_status\":\"%s\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, s, $2 }
                    END { print "]}}" }' "$H/agents" ;;
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
codex_says 1 "${RECONNECTS[@]}" "${RATE_MSG}" > "${BIN}/codex"
chmod +x "${BIN}/codex" "${BIN}/herdr" "${ROOT}/sessions"

# A git project with story s1.
p="${ROOT}/proj"
mkdir -p "${p}/.claude/swarm" "${p}/docs/stories"
git -c init.defaultBranch=main init -q "${p}"
printf '%s\n' --- "status: ready" "kind: code" "touches: [x.sh]" --- "" "# s1" "" "**Done when:**" "- it holds" > "${p}/docs/stories/s1.md"
# review [config line] — codex-review main for SWARM_STORY=s1 (none with NOSTORY set), with that
# config, 60 s of codex's time, a fallback's least time 1 s and HERDR_ENV=1 unless NOHERDR is set:
# sets out and rc. A run past 30 s is KILLed, failing the checks instead of hanging the test.
review() {
  local pid i set=()
  # env takes no -u after an assignment: both are unset first, then set unless NOHERDR or NOSTORY.
  [[ -n "${NOHERDR:-}" ]] || set+=(HERDR_ENV=1)
  [[ -n "${NOSTORY:-}" ]] || set+=(SWARM_STORY=s1)
  printf '%s\n' "$@" > "${p}/.claude/swarm/config"; : > "${ROOT}/herdr.log"
  # umask 022, the usual one, so a file codex-review leaves open to group or other shows it.
  (cd "${p}" && umask 022 && exec env -u SWARM_PROJECT -u SWARM_PR -u HERDR_ENV -u SWARM_STORY "${set[@]+"${set[@]}"}" SWARM_FALLBACK_MIN_SECONDS=1 HERDR_WORKSPACE_ID=w \
    SWARM_CODEX_SECONDS=60 PATH="${BIN}:${PATH}" bash "${SWARM}" codex-review main > "${ROOT}/out" 2>&1) &
  pid=$!
  for ((i = 0; i < 150; i++)); do kill -0 "${pid}" 2>/dev/null || break; sleep 0.2; done
  kill -0 "${pid}" 2>/dev/null && kill -KILL "${pid}"
  rc=0; wait "${pid}" || rc=$?
  out="$(cat "${ROOT}/out")"
}
# incidents — the incident lines as "target|outcome" (events_outcome's, without the tail).
incidents() {
  [[ -f "${p}/.swarm/events.tsv" ]] || return 0
  python3 -c 'import sys; sys.path.insert(0, sys.argv[1])
from events_outcome import outcome
for r in (l.rstrip("\n").split("\t") for l in open(sys.argv[2])):
    if r[1] == "incident":
        print(r[2] + "|" + outcome(r))' "${SWARM%/*}/lib" "${p}/.swarm/events.tsv"
}
count() { incidents | wc -l | tr -d ' '; }

# --- Key empty: codex's Foundry rate-limit line is a limit: the incident names it, no agent starts,
# and codex-review exits as codex did.
review
check "with fallback_reviewer empty, codex's rate limit exits as codex did, with a codex-limit: rate limit incident and no agent" \
  "1|codex-s1|codex-limit: rate limit|no" "${rc}|$(incidents)|$(logged '^agent start')"

# --- fallback_reviewer = sonnet: the fallback reviews in codex's place and the line names the rate limit.
review "fallback_reviewer = sonnet"
check "with fallback_reviewer = sonnet, codex's rate limit starts fallback-s1 and prints its findings under the rate-limit line" \
  "0|yes|yes|yes" "${rc}|$(logged '^agent start fallback-s1 .*--model sonnet ')|$(has "reviewed by fallback sonnet: codex rate limit" "${out}")|$(has "- [P1] STUB FINDING — x.sh:3" "${out}")"
check "the fallback run logs its own codex-limit: rate limit incident" "2|codex-s1|codex-limit: rate limit" "$(count)|$(incidents | tail -1)"
check "the fallback's brief says codex hit its rate limit" "yes" "$(has "codex hit its rate limit, so you review in its place" "$(cat "${p}/.swarm/briefs/fallback/s1.md")")"

# --- A fallback that cannot start says codex was skipped on its rate limit.
NOHERDR=1 review "fallback_reviewer = sonnet"
check "outside herdr, codex-review says codex was skipped on its rate limit" "1|yes" \
  "${rc}|$(has "codex skipped: rate limit (fallback did not start: not in a herdr pane" "${out}")"

# --- codex's other rate-limit line, its retries spent on a 429, is a rate limit too.
codex_says 1 "ERROR: exceeded retry limit, last status: 429 Too Many Requests, request id: req-1" > "${BIN}/codex"
n="$(count)"; review
check "codex's 429 retry-limit line logs a codex-limit: rate limit incident" "$((n + 1))|codex-s1|codex-limit: rate limit" "$(count)|$(incidents | tail -1)"
codex_says 1 "ERROR: exceeded retry limit, last status: 500 Internal Server Error" > "${BIN}/codex"
n="$(count)"; review "fallback_reviewer = sonnet"
check "a retry limit on a 500 is no rate limit: no incident, no agent" "1|${n}|no" "${rc}|$(count)|$(logged '^agent start')"

# --- A review that only quotes the rate-limit words is no limit: no incident, no agent.
codex_says 0 "${RATE_MSG}" > "${BIN}/codex"
n="$(count)"; review "fallback_reviewer = sonnet"
check "codex that exits 0 with the rate-limit line logs no incident and starts no agent" "0|${n}|no" "${rc}|$(count)|$(logged '^agent start')"
codex_says 1 "${RATE_MSG}" "review: one" "review: two" "review: three" "review: four" "ERROR: stream disconnected" > "${BIN}/codex"
n="$(count)"; review "fallback_reviewer = sonnet"
check "a failed codex whose rate-limit line sits above its last 5 lines logs no incident" "1|${n}|no" "${rc}|$(count)|$(logged '^agent start')"
codex_says 1 "a diff about the token rate limit" "+${RATE_MSG}" "ERROR: stream disconnected" > "${BIN}/codex"
n="$(count)"; review "fallback_reviewer = sonnet"
check "a failed codex whose diff quotes the rate-limit line logs no incident" "1|${n}|no" "${rc}|$(count)|$(logged '^agent start')"

# --- A failed codex keeps its last 20 lines, under a line with its exit, readable by its owner alone;
# a run with no story names the file by its base.
{ printf '#!/bin/sh\n'; for i in $(seq 1 25); do printf 'echo "codex line %s"\n' "${i}"; done; printf 'exit 3\n'; } > "${BIN}/codex"
review
tl="${p}/.swarm/codex/s1.tail"
check "a failed codex's last 20 lines are kept in .swarm/codex/s1.tail under its exit" \
  "3|yes|21|codex line 6|codex line 25" \
  "${rc}|$(head -1 "${tl}" 2>/dev/null | grep -qE '^# [0-9T:Z-]+ codex exited 3; its last 20 lines:$' && echo yes || echo no)|$(wc -l < "${tl}" 2>/dev/null | tr -d ' ')|$(sed -n 2p "${tl}" 2>/dev/null)|$(tail -1 "${tl}" 2>/dev/null)"
# group_other <path> — its mode's group and other bits, in octal: 0 when only the owner may read it.
group_other() { python3 -c 'import os, sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o077))' "$1" 2>&1; }
check "the kept lines and their directory are the owner's alone, whatever the caller's umask" "0o0|0o0" \
  "$(group_other "${tl}")|$(group_other "${tl%/*}")"
codex_says 1 "${RECONNECTS[@]}" "${RATE_MSG}" > "${BIN}/codex"
NOSTORY=1 review
check "with no SWARM_STORY, a rate limit's last lines go to .swarm/codex/main.tail, ending in codex's line" "1|${RATE_MSG}" \
  "${rc}|$(tail -1 "${p}/.swarm/codex/main.tail" 2>/dev/null)"

# --- The briefs: codex_rule (in a builder's brief) and review_brief say "usage or rate limit".
brief="$(cd "${p}" && env -u SWARM_PROJECT -u HERDR_ENV PATH="${BIN}:${PATH}" bash "${SWARM}" _brief s1 2>&1 | tr -s '[:space:]' ' ')"
check "the builder brief's codex rule says usage or rate limit, and names both skip lines" "yes|yes|yes" \
  "$(has "a usage or rate limit it prints early" "${brief}")|$(has "If it ends on codex's usage or rate limit or on" "${brief}")|$(
    has '"codex skipped: usage limit", "codex skipped: rate limit" or "codex skipped: timed out"' "${brief}")"
rbrief="$(cd "${p}" && env -u SWARM_PROJECT -u HERDR_ENV PATH="${BIN}:${PATH}" bash "${SWARM}" _review-brief s1 https://github.com/o/r/pull/1 main \
  "${p}/.swarm/reviews/s1.md" 0123456789abcdef0123456789abcdef01234567 2>&1 | tr -s '[:space:]' ' ')"
# shellcheck disable=SC2016 # the backquotes are the brief's own
check "the review brief says usage or rate limit, and names both skip lines" "yes|yes|yes" \
  "$(has "a usage or rate limit it prints early" "${rbrief}")|$(has "If it ends on codex's usage or rate limit or on" "${rbrief}")|$(
    has '`codex skipped: usage limit`, `codex skipped: rate limit` or `codex skipped: timed out`' "${rbrief}")"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
