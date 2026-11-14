#!/usr/bin/env bash
# codex_unavailable_test.sh — codex-review when codex could not review at all. A codex whose output ends
# in three reconnect lines, or in a "stream disconnected before completion" line, is stopped well before
# its timeout, logs a codex-unreachable incident, and with fallback_reviewer set a fallback reviews in its
# place ("reviewed by fallback <model>: codex unreachable"); with it empty, codex-review prints "codex
# skipped: unreachable" and fails. A codex that times out keeps its reap line, and with fallback_reviewer
# set the fallback gets a whole codex_minutes of its own (SWARM_CODEX_SECONDS stands in for it here); with
# it empty, "codex skipped: timed out" stays. One reconnect line, or three followed by a review, stops
# nothing, and neither does a rate limit whose reconnect lines come seconds apart, as on Azure Foundry.
# The reconnect line codex prints with no connection at all ("Reconnecting... waiting for network") counts
# as the "Reconnecting... N/5" one does. The builder's brief and the review brief name the new lines.
# codex, herdr and claude are stubs on PATH, as in codex_rate_limit_test.sh.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects" SWARM_STALL_POLL_MS=200 \
  SWARM_CONDUCTOR_POLL=1 CLAUDE_STUB_AGENTS="${ROOT}/claude.json"
BIN="${ROOT}/stub-bin"; mkdir -p "${BIN}" "${ROOT}/done"; echo '[]' > "${ROOT}/claude.json"; : > "${ROOT}/agents"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${BIN}/claude"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }
lacks() { if grep -qF -- "$1" <<< "$2"; then echo "no, got: $2"; else echo yes; fi; }
logged() { if grep -q -- "$1" "${ROOT}/herdr.log" 2>/dev/null; then echo yes; else echo no; fi; }
names() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo no; fi; }   # has, without the text: a brief is long

# codex <line>... — a codex stub: each argument is a shell line it runs, its output on stderr as codex's is.
# It writes the second it started to codex-start first. A hang is `sleep 120`, which stop_codex ends.
codex() {
  { printf '#!/bin/sh\ndate +%%s > "%s/codex-start"\nexec 1>&2\n' "${ROOT}"; printf '%s\n' "$@"; } > "${BIN}/codex"
  chmod +x "${BIN}/codex"
}
say() { printf 'echo "%s"' "$1"; }
# herdr: as in codex_rate_limit_test.sh. agent prompt writes the findings file the brief names and marks
# the agent done; agent list and wait report it idle once done.
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
cat > "${ROOT}/sessions" <<EOF
#!/bin/sh
awk -v d="${ROOT}/done" 'BEGIN { printf "[" }
  { s = system("test -e " d "/" \$1) == 0 ? "idle" : "busy"
    printf "%s{\"sessionId\":\"%s\",\"status\":\"%s\"}", (NR > 1 ? "," : ""), \$3, s }
  END { print "]" }' "${ROOT}/agents" > "${ROOT}/claude.json"
EOF
chmod +x "${BIN}/herdr" "${ROOT}/sessions"

p="${ROOT}/proj"
mkdir -p "${p}/.claude/swarm" "${p}/docs/stories"
git -c init.defaultBranch=main init -q "${p}"
printf '%s\n' --- "status: ready" "kind: code" "touches: [x.sh]" --- "" "# s1" "" "**Done when:**" "- it holds" > "${p}/docs/stories/s1.md"
# review <codex seconds> [config line] — codex-review main for SWARM_STORY=s1 in herdr, with that config and
# that many seconds of codex's time, a fallback's least time 1 s and a 1 s wait before a rate limit's
# retry: sets out, rc and ran (seconds from codex's start to codex-review's exit, which
# leaves out swarm.sh's own start on a busy machine). A run past 150 s is KILLed, failing the checks instead of
# hanging the test.
review() {
  local pid i
  printf '%s\n' "${@:2}" > "${p}/.claude/swarm/config"; : > "${ROOT}/herdr.log"; rm -f "${ROOT}/codex-start"
  (cd "${p}" && exec env -u SWARM_PROJECT -u SWARM_PR HERDR_ENV=1 SWARM_STORY=s1 SWARM_FALLBACK_MIN_SECONDS=1 HERDR_WORKSPACE_ID=w \
    SWARM_CODEX_GRACE=1 SWARM_CODEX_RETRY_SECONDS=1 SWARM_CODEX_SECONDS="$1" PATH="${BIN}:${PATH}" bash "${SWARM}" codex-review main > "${ROOT}/out" 2>&1) &
  pid=$!
  for ((i = 0; i < 750; i++)); do kill -0 "${pid}" 2>/dev/null || break; sleep 0.2; done
  kill -0 "${pid}" 2>/dev/null && kill -KILL "${pid}"
  rc=0; wait "${pid}" || rc=$?
  ran=$(($(date +%s) - $(cat "${ROOT}/codex-start" 2>/dev/null || echo 0)))
  out="$(cat "${ROOT}/out")"
}
# events <kind> — that kind's lines in events.tsv as "target|outcome" (events_outcome's, without the tail).
events() {
  [[ -f "${p}/.swarm/events.tsv" ]] || return 0
  python3 -c 'import sys; sys.path.insert(0, sys.argv[1])
from events_outcome import outcome
for r in (l.rstrip("\n").split("\t") for l in open(sys.argv[2])):
    if r[1] == sys.argv[3]:
        print(r[2] + "|" + outcome(r))' "${SWARM%/*}/lib" "${p}/.swarm/events.tsv" "$1"
}
count() { events "$1" | wc -l | tr -d ' '; }
within() { if [[ "$2" -le "$1" ]]; then echo yes; else echo "no, $2 s"; fi; } # <most seconds> <seconds taken>
# used — the seconds codex used before it was stopped: its time less the budget codex-review gave the
# fallback ("within <N> s"), so the fallback's own start is not counted.
used() { local n; n="$(sed -n 's/.*fallback sonnet reviews in its place, within \([0-9]*\) s$/\1/p' <<< "${out}")"; echo $((HIGH - ${n:-0})); }
HIGH=120   # codex's time in the unreachable cases: far past the 30 s they must stop in

# --- Three reconnect lines, then a hang: stopped long before its time, a codex-unreachable incident, and
# the fallback reviews; with no fallback, codex skipped: unreachable.
codex "$(say "ERROR: Reconnecting... 1/5")" "$(say "ERROR: Reconnecting... 1/5")" "$(say "ERROR: Reconnecting... 1/5")" "sleep 120"
review "${HIGH}" "fallback_reviewer = sonnet"
check "three reconnect lines then a hang: stopped within 30 s, a codex-unreachable incident, and the fallback reviews" \
  "yes|0|codex-s1|codex-unreachable|yes|yes|yes" \
  "$(within 30 "$(used)")|${rc}|$(events incident)|$(logged '^agent start fallback-s1 .*--model sonnet ')|$(
    has "reviewed by fallback sonnet: codex unreachable" "${out}")|$(has "- [P1] STUB FINDING — x.sh:3" "${out}")"
check "the fallback's brief says codex could not reach its provider" "yes" \
  "$(has "codex could not reach its model provider, so you review in its place" "$(cat "${p}/.swarm/briefs/fallback/s1.md")")"
n="$(count incident)"
review "${HIGH}"
check "with fallback_reviewer empty, three reconnect lines stop codex within 30 s and print codex skipped: unreachable" \
  "yes|1|yes|$((n + 1))|codex-s1|codex-unreachable|no" \
  "$(within 30 "${ran}")|${rc}|$(has "codex skipped: unreachable" "${out}")|$(count incident)|$(events incident | tail -1)|$(logged '^agent start')"
# The line codex 0.164.0 printed, at 15, 22, 35 and 57 s, when run against a local port that refused it on
# 2026-11-14: no N/5 in it. Three of them are an unreachable codex too.
WAITING="ERROR: Reconnecting... waiting for network"
codex "$(say "${WAITING}")" "$(say "${WAITING}")" "$(say "${WAITING}")" "sleep 120"
n="$(count incident)"
review "${HIGH}"
check "three waiting-for-network reconnect lines then a hang: stopped within 30 s, a codex-unreachable incident, codex skipped: unreachable" \
  "yes|1|yes|$((n + 1))|codex-s1|codex-unreachable" \
  "$(within 30 "${ran}")|${rc}|$(has "codex skipped: unreachable" "${out}")|$(count incident)|$(events incident | tail -1)"

# --- One "stream disconnected before completion" line, then a hang: the same.
codex "$(say "ERROR: stream disconnected before completion: error sending request for url (https://x.openai.azure.com/openai/responses)")" "sleep 120"
n="$(count incident)"
review "${HIGH}" "fallback_reviewer = sonnet"
check "a stream-disconnected line then a hang: stopped within 30 s, a codex-unreachable incident, and the fallback reviews" \
  "yes|0|$((n + 1))|codex-s1|codex-unreachable|yes" \
  "$(within 30 "$(used)")|${rc}|$(count incident)|$(events incident | tail -1)|$(has "reviewed by fallback sonnet: codex unreachable" "${out}")"
n="$(count incident)"
review "${HIGH}"
check "with fallback_reviewer empty, a stream-disconnected line prints codex skipped: unreachable" \
  "yes|1|yes|$((n + 1))|codex-s1|codex-unreachable" \
  "$(within 30 "${ran}")|${rc}|$(has "codex skipped: unreachable" "${out}")|$(count incident)|$(events incident | tail -1)"

# --- A silent hang past codex's time: the reap line as before, then the fallback with a whole budget of
# its own, as codex-review prints it (codex's own time is spent, so what is left would be 0). 60 s, as
# the fallback's start can take over 30 s on a busy machine.
codex "sleep 120"
n="$(count reap)"; i="$(count incident)"
review 60 "fallback_reviewer = sonnet"
check "a timeout with fallback_reviewer set: the reap line, then the fallback with a whole 60 s budget, under codex timeout" \
  "0|$((n + 1))|codex-s1|timed out after 10 min|yes|yes|yes|${i}" \
  "${rc}|$(count reap)|$(events reap | tail -1)|$(has "codex timeout: fallback sonnet reviews in its place, within 60 s" "${out}")|$(
    has "reviewed by fallback sonnet: codex timeout" "${out}")|$(has "- [P1] STUB FINDING — x.sh:3" "${out}")|$(count incident)"
n="$(count reap)"
review 3
check "a timeout with fallback_reviewer empty keeps codex skipped: timed out, its exit and its reap line, with no agent" \
  "1|yes|$((n + 1))|no" "${rc}|$(has "codex skipped: timed out after 10 min" "${out}")|$(count reap)|$(logged '^agent start')"

# --- One reconnect line that outlasts the wait, then a review: not stopped, no incident.
codex "$(say "ERROR: Reconnecting... 1/5")" "sleep 17" "$(say "review: the change holds")" "exit 0"
i="$(count incident)"
review "${HIGH}" "fallback_reviewer = sonnet"
check "one reconnect line held for 17 s, then a review: codex finishes, with no incident and no fallback" \
  "0|yes|yes|${i}|no" \
  "${rc}|$(has "review: the change holds" "${out}")|$(lacks "codex skipped" "${out}")|$(count incident)|$(logged '^agent start')"
# Three reconnect lines followed by review output: the reconnects are no longer the last thing codex said.
codex "$(say "ERROR: Reconnecting... 1/5")" "$(say "ERROR: Reconnecting... 2/5")" "$(say "ERROR: Reconnecting... 3/5")" \
  "$(say "review: reading x.sh")" "sleep 17" "$(say "review: the change holds")" "exit 0"
review "${HIGH}" "fallback_reviewer = sonnet"
check "three reconnect lines then review output, held for 17 s: codex finishes, with no incident" \
  "0|yes|${i}|no" "${rc}|$(has "review: the change holds" "${out}")|$(count incident)|$(logged '^agent start')"

# --- A Foundry rate limit as it comes: reconnect lines seconds apart, then the rate-limit line. It is a
# rate limit (with its retry), not an unreachable codex.
codex "$(say "ERROR: Reconnecting... 1/5")" "$(say "ERROR: Reconnecting... 2/5")" "$(say "ERROR: Reconnecting... 3/5")" "sleep 4" \
  "$(say "ERROR: Reconnecting... 4/5")" "$(say "ERROR: Reconnecting... 5/5")" \
  "$(say "ERROR: rate limit exceeded: Your requests to m for m in r have exceeded token rate limit.")" "exit 1"
n="$(count incident)"
review "${HIGH}"
check "reconnect lines 4 s before a rate-limit line: a codex-limit: rate limit incident and its retry, no codex-unreachable" \
  "1|$((n + 1))|codex-s1|codex-limit: rate limit|1" \
  "${rc}|$(count incident)|$(events incident | tail -1)|$(count codex-retry)"

# --- The briefs: codex_rule (in a builder's brief) and the review brief name the line an unreachable codex
# ends on, and the two new lines a fallback's review comes under.
brief="$(cd "${p}" && env -u SWARM_PROJECT -u HERDR_ENV PATH="${BIN}:${PATH}" bash "${SWARM}" _brief s1 2>&1 | tr -s '[:space:]' ' ')"
check "the builder brief's codex rule names codex skipped: unreachable, and the unreachable and timeout fallback lines" "yes|yes" \
  "$(names '"codex skipped: unreachable" when codex could not reach its provider' "${brief}")|$(
    names '(or "codex rate limit", "codex unreachable" or "codex timeout")' "${brief}")"
rbrief="$(cd "${p}" && env -u SWARM_PROJECT -u HERDR_ENV PATH="${BIN}:${PATH}" bash "${SWARM}" _review-brief s1 https://github.com/o/r/pull/1 main \
  "${p}/.swarm/reviews/s1.md" 0123456789abcdef0123456789abcdef01234567 2>&1 | tr -s '[:space:]' ' ')"
# shellcheck disable=SC2016 # the backquotes are the brief's own
check "the review brief names codex skipped: unreachable, and the unreachable and timeout fallback lines" "yes|yes" \
  "$(names '`codex skipped: unreachable` when codex could not reach its provider' "${rbrief}")|$(
    names '(or `codex rate limit`, `codex unreachable` or `codex timeout`)' "${rbrief}")"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
