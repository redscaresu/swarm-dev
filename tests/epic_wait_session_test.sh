#!/usr/bin/env bash
# epic_wait_session_test.sh — wait reads a Claude agent's state from its session: busy, idle, gone,
# unknown, stalled, and an agent herdr answers for.
# herdr is a stub on PATH that hands out pane ids in order and remembers tab labels; the repo is a
# local bare remote. gh is a stub too, so a close's PR lookup never reaches the real gh.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
# No trust file here, so require_trusted lets the fixture agents start whatever ~/.claude.json says.
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
# The herdr stub starts each session's .jsonl here, and a /goal prompt appends the entry
# HERDR_STUB_GOAL picks: set (the default here), other (a goal for another condition), refused,
# pasted (the /goal queued as a pasted prompt), or none when empty. A goal wait is short.
export CLAUDE_PROJECTS_DIR="${ROOT}/projects" HERDR_STUB_GOAL=set SWARM_PROMPT_TIMEOUT_MS=3000
# The claude stub goes first on PATH, so no run here reaches the real claude.
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}"
fails=0
GIT=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main)

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

item() { # <board> <path> <front-matter line>... — a fresh item: its file, and no state file
  local path="$1/$2" title; rm -f "$(dirname "$1")/.swarm/board-state/${2%.md}"; shift 2
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

# herdr: logs every call; each new pane is w:<n>, each new tab t<n>, and tab list shows their labels.
# agent start makes the session's .jsonl; a /goal prompt is kept in goal.txt and writes its entry.
# listfail makes agent list fail.
mkdir -p "${ROOT}/bin"
cat > "${ROOT}/bin/herdr" <<EOF
#!/bin/sh
H="${ROOT}"
EOF
cat >> "${ROOT}/bin/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
next() { n=$(($(cat "$H/n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/n"; }
case "$1 $2" in
  "workspace list")   echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  "tab create")       next; label=$(echo "$*" | sed 's/.*--label \([^ ]*\).*/\1/')
                      echo "t$n $label" >> "$H/tabs"
                      echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "tab list")         awk 'BEGIN { printf "{\"result\":{\"tabs\":[" }
                           { printf "%s{\"tab_id\":\"%s\",\"label\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                           END { print "]}}" }' "$H/tabs" ;;
  "pane list")        [ -e "$H/live" ] && cat "$H/live" ;;
  "pane split")       [ -e "$H/nosplit" ] && { echo '{"error":{"code":"pane_not_found"}}'; exit 1; }
                      next; echo "{\"result\":{\"pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "agent prompt")     [ -e "$H/promptfail" ] && { echo '{"error":{"code":"pane_not_found"}}' >&2; exit 1; }
                      case "$4" in "/goal "*) printf '%s' "$4" > "$H/goal.txt"
                        [ -z "${HERDR_STUB_GOAL:-}" ] || python3 - "$HERDR_STUB_GOAL" "${4#/goal }" >> "$(cat "$H/session")" <<'PY'
import datetime, json, sys
now = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
if sys.argv[1] in ("set", "other"):   # the shapes Claude Code 2.1.299 wrote in the goal spike; other sets another goal
    cond = sys.argv[2] if sys.argv[1] == "set" else "another condition"
    print(json.dumps({"type": "attachment", "timestamp": now, "attachment": {"type": "goal_status", "met": False, "sentinel": True, "condition": cond}}))
elif sys.argv[1] == "pasted":   # the paste collapsed and queued as a prompt, as on 2026-10-16
    print(json.dumps({"type": "attachment", "timestamp": now, "attachment": {"type": "queued_command", "commandMode": "prompt",
                      "prompt": '<pasted_content id="p1">\n/goal %s\n</pasted_content>' % sys.argv[2]}}))
else:
    for c in ("<command-name>/goal</command-name>\n<command-args>%s</command-args>" % sys.argv[2],
              "<local-command-stdout>/goal can't run while hooks are restricted (disableAllHooks or allowManagedHooksOnly is set in settings or by policy).</local-command-stdout>"):
        print(json.dumps({"type": "system", "subtype": "local_command", "timestamp": now, "content": c}))
PY
                        ;;
                        # Any other prompt starts a turn: the goal tests list its session as busy.
                        *) [ -e "$H/session" ] && echo "[{\"sessionId\":\"$(basename "$(cat "$H/session")" .jsonl)\",\"status\":\"busy\"}]" > "$H/started.json" ;;
                      esac
                      [ -e "$H/resumed" ] && mv "$H/resumed" "$H/screen"   # the pane after the prompt
                      if [ -e "$H/idle" ]; then echo '{"result":{"agent":{"agent_status":"idle"}}}'
                      else echo '{"result":{"agent":{"agent_status":"working"}}}'; fi ;;
  "agent start")      sid=$(echo "$*" | sed -n 's/.*--session-id \([^ ]*\).*/\1/p')
                      if [ -n "$sid" ]; then mkdir -p "$CLAUDE_PROJECTS_DIR/p"; : > "$CLAUDE_PROJECTS_DIR/p/$sid.jsonl"
                        echo "$CLAUDE_PROJECTS_DIR/p/$sid.jsonl" > "$H/session"; fi
                      echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')" >> "$H/agents" ;;
  "agent rename")     [ -e "$H/norename" ] && exit 1
                      [ -e "$H/agents" ] && awk -v t="$3" -v n="$4" '$2 == t { $1 = n } { print }' "$H/agents" > "$H/agents.tmp" && mv "$H/agents.tmp" "$H/agents" ;;
  "agent list")       [ -e "$H/listfail" ] && exit 1   # each agent's status is the file hstatus's, else idle
                      awk -v st="$(cat "$H/hstatus" 2>/dev/null || echo idle)" 'BEGIN { printf "{\"result\":{\"agents\":[" }
                           { printf "%s{\"name\":\"%s\",\"agent_status\":\"%s\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, st, $2 }
                           END { print "]}}" }' "$H/agents" 2>/dev/null || echo '{"result":{"agents":[]}}' ;;
  "agent wait")       [ -e "$H/swap" ] && mv "$H/swap" "$H/claude.json"   # the session changes while herdr waits
                      [ -e "$H/waiterr" ] && { echo '{"error":{"code":"agent_not_found"}}' >&2; exit 1; }
                      echo '{"result":{"agent":{"agent_status":"done"}}}' ;;
  "agent read")       cat "$H/screen" 2>/dev/null ;;
  # A closed pane takes its agent with it; a tab t<n> closes its first pane, w:<n>.
  "pane close"|"tab close") p=$3; [ "$2" = close ] && [ "$1" = tab ] && p="w:${3#t}"
                      [ -e "$H/agents" ] && awk -v p="$p" '$2 != p' "$H/agents" > "$H/agents.tmp" && mv "$H/agents.tmp" "$H/agents" ;;
esac
EOF
chmod +x "${ROOT}/bin/herdr"
log() { cat "${ROOT}/herdr.log"; }
# gh: logs every call; pr list prints ${ROOT}/prs.json, or no PRs; pr view <url> gives the state on
# <url>'s line in ${ROOT}/pr-states.
gh_stub() {
  printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/gh"
  # shellcheck disable=SC2016 # the stub's own shell expands these
  printf '%s\n' 'echo "$*" >> "$H/gh.log"' 'case "$1 $2" in "pr list") cat "$H/prs.json" 2>/dev/null || echo "[]" ;;' \
    '  "pr view") echo "{\"state\":\"$(awk -v u="$3" '\''$1 == u { print $2 }'\'' "$H/pr-states")\"}" ;; esac' >> "${ROOT}/bin/gh"
  chmod +x "${ROOT}/bin/gh"
}
gh_stub

# A repo with main and dev (dev one commit ahead), and a project whose board names it.
"${GIT[@]}" init -q --bare "${ROOT}/svc.git"
"${GIT[@]}" clone -q "${ROOT}/svc.git" "${ROOT}/svc" 2>/dev/null
"${GIT[@]}" -C "${ROOT}/svc" commit -q --allow-empty -m init && "${GIT[@]}" -C "${ROOT}/svc" push -q origin main
"${GIT[@]}" -C "${ROOT}/svc" checkout -q -b dev && "${GIT[@]}" -C "${ROOT}/svc" commit -q --allow-empty -m dev
"${GIT[@]}" -C "${ROOT}/svc" push -q origin dev && "${GIT[@]}" -C "${ROOT}/svc" checkout -q main
p="${ROOT}/proj"; b="${p}/docs"
mkdir -p "${p}/.claude/swarm"; : > "${p}/.claude/swarm/config"
printf "A PROJECT RULE every agent reads.\n" > "${p}/.claude/swarm/brief.md"
run() { (cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
# The pane records wait reads live here.
mkdir -p "${p}/.swarm/state"

# --- wait: herdr's agent wait is only the wake-up (the stub always says done); a Claude agent's
# state is its session's, from the claude stub's fixture.
export CLAUDE_STUB_AGENTS="${ROOT}/claude.json"
session() { # <file> <session>=<status>... — a `claude agents --json` fixture
  local f="$1" e out=""; shift
  for e in "$@"; do out+="${out:+,}{\"sessionId\":\"${e%%=*}\",\"status\":\"${e#*=}\"}"; done
  echo "[${out}]" > "${f}"
}
nudges() { grep -c '^agent prompt' "${ROOT}/herdr.log" || true; }
waitrc() { # <stderr file> <wait args...> — "<stdout>|exit <rc>|<seconds taken>"
  local e="$1" t0=${SECONDS} out rc=0; shift
  out="$(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" wait "$@" 2>"${e}")" || rc=$?
  echo "${out}|exit ${rc}|$((SECONDS - t0))"
}
# gh: story/a has the PRs in prs-a.json only in the repo whose origin URL is in pr-in, and none
# elsewhere; the call's -q runs over them through jq. ghfail makes every call fail.
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/gh"
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '%s\n' '[ -e "$H/ghfail" ] && exit 1' \
  'prs="[]"; case "$*" in "pr list -R $(cat "$H/pr-in" 2>/dev/null) --head story/a --state all "*) prs="$(cat "$H/prs-a.json")" ;; esac' \
  'q=.; while [ $# -gt 0 ]; do [ "$1" = -q ] && q="$2"; shift; done; echo "$prs" | jq -r "$q"' >> "${ROOT}/bin/gh"
chmod +x "${ROOT}/bin/gh"
echo '[{"state":"OPEN"}]' > "${ROOT}/prs-a.json"
echo "a w:950" >> "${ROOT}/agents"; echo "w:950 a" > "${p}/.swarm/state/wait-a"   # a pane id the stub never reaches; this project's agent a, in a pane it recorded
printf '2026-10-13\tcode\ta\tclaude\topus\thigh\tsess-a\n' >> "${p}/.swarm/agents.tsv"
session "${ROOT}/claude.json" sess-a=idle
# herdr says done at once, but the session is busy: wait sleeps out each slice until it turns idle.
session "${ROOT}/claude.json" sess-a=busy
(sleep 2; session "${ROOT}/claude.json.new" sess-a=idle; mv "${ROOT}/claude.json.new" "${ROOT}/claude.json") &
got="$(SWARM_STALL_POLL_MS=1000 waitrc /dev/null a 20000)"; wait
check "herdr done and the session busy: wait holds until the session is idle" "idle|exit 0|yes" \
  "${got%|*}|$([[ ${got##*|} -ge 2 && ${got##*|} -lt 10 ]] && echo yes || echo "no, ${got##*|}s")"
# The session turns idle during the last slice's sleep-out (2 s slices, a 4 s timeout, idle at 3 s):
# wait takes its read after the sleep-out, so it returns idle in time, not the busy read before it.
session "${ROOT}/claude.json" sess-a=busy
(sleep 3; session "${ROOT}/claude.json.new" sess-a=idle; mv "${ROOT}/claude.json.new" "${ROOT}/claude.json") &
got="$(SWARM_STALL_POLL_MS=2000 waitrc /dev/null a 4000)"; wait
check "a session that turns idle in the last slice's sleep-out is returned idle" "idle|exit 0" "${got%|*}"
# herdr wakes at once and the session has settled by then: wait returns on that read, not a minute's
# slice later.
fast() { [[ ${1##*|} -lt 5 ]] && echo yes || echo "no, ${1##*|}s"; }
session "${ROOT}/claude.json" sess-a=busy; session "${ROOT}/swap" sess-a=idle
got="$(SWARM_STALL_POLL_MS=60000 waitrc /dev/null a 120000)"
check "a session idle on the read after an early wake is returned at once" "idle|exit 0|yes" "${got%|*}|$(fast "${got}")"
session "${ROOT}/claude.json" sess-a=busy; echo '[]' > "${ROOT}/swap"
got="$(SWARM_STALL_POLL_MS=60000 waitrc /dev/null a 120000)"
check "a session gone on the read after an early wake is returned at once" "gone|exit 0|yes" "${got%|*}|$(fast "${got}")"
# Claude Code lists pid and status only while the process is alive: an entry with neither has exited.
echo '[{"sessionId":"sess-a","cwd":"/w","kind":"interactive","startedAt":"2026-10-13T10:00:00Z"}]' > "${ROOT}/claude.json"
got="$(SWARM_STALL_POLL_MS=1000 waitrc /dev/null a 2000)"
check "a listed session with no pid or status reads gone" "gone|exit 0" "${got%|*}"
# A recorded session with no entry is gone, read on the first wake, even when herdr's wait fails
# (the pane is gone too); a slice of a minute shows it does not wait a slice out first.
session "${ROOT}/claude.json" sess-a=busy; echo '[]' > "${ROOT}/swap"; touch "${ROOT}/waiterr"
got="$(SWARM_STALL_POLL_MS=60000 waitrc /dev/null a 120000)"
check "a gone session is returned on the first wake, though herdr's wait failed" "gone|exit 0|yes" \
  "${got%|*}|$([[ ${got##*|} -lt 10 ]] && echo yes || echo "no, ${got##*|}s")"
# A herdr wait that fails for another reason, with the session still busy, fails the wait at once:
# the state and a non-zero exit, not slices slept out to the timeout.
session "${ROOT}/claude.json" sess-a=busy
got="$(SWARM_STALL_POLL_MS=10000 waitrc /dev/null a 20000)"
check "a herdr wait that fails, the session busy, fails the wait within a slice" "busy|exit 1|yes" \
  "${got%|*}|$([[ ${got##*|} -lt 8 ]] && echo yes || echo "no, ${got##*|}s")"
rm -f "${ROOT}/waiterr"
# A reader that fails (python3 here fails it) is unknown: a Claude agent never falls back to herdr.
mkdir -p "${ROOT}/badpy"
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\n[ -n "${SWARM_LIST_OK+x}" ] && exit 1\nexec "%s" "$@"\n' "$(command -v python3)" > "${ROOT}/badpy/python3"
chmod +x "${ROOT}/badpy/python3"
got="$(PATH="${ROOT}/badpy:${PATH}" SWARM_STALL_POLL_MS=1000 waitrc /dev/null a 2000)"
check "a reader that fails reads as unknown, never as herdr's word" "unknown|exit 1" "${got%|*}"
# A list call that fails is unknown, never gone: wait keeps stepping, says so once, and times out.
got="$(CLAUDE_STUB_AGENTS="${ROOT}/no-such-file" SWARM_STALL_POLL_MS=1000 waitrc "${ROOT}/wait.err" a 3000)"
check "a failed list call reads as unknown, said once on stderr, until the timeout" "unknown|exit 1|1" \
  "${got%|*}|$(grep -c 'unknown' "${ROOT}/wait.err")"
# A reused name: the older line's session is idle, the newer one's busy. wait reads the newer.
printf '2026-10-14\tcode\ta\tclaude\topus\thigh\tsess-a2\n' >> "${p}/.swarm/agents.tsv"
session "${ROOT}/claude.json" sess-a=idle sess-a2=busy
got="$(SWARM_STALL_POLL_MS=1000 waitrc /dev/null a 2000)"
check "with two agents.tsv lines for a name, wait reads the newer line's session" "busy|exit 1" "${got%|*}"
# Stalls: story a's builder is busy, its worktree's last commit 2 hours old, no events.tsv line, and
# the wait begun 2 hours ago. A file edited a minute ago in the worktree is a sign of life; aged past
# stall_minutes (or gone, the worktree clean) it is not, and wait --stall returns on the stall.
item "${b}" stories/a.md "status: ready" "kind: code" "repo: svc"
printf '%s\n' "repos_dir = ${ROOT}" > "${p}/.claude/swarm/config"
: > "${p}/.swarm/events.tsv"; wt="${ROOT}/svc-wt/a"; old=$(($(date +%s) - 7200))
"${GIT[@]}" init -q "${wt}" && GIT_COMMITTER_DATE="@${old}" "${GIT[@]}" -C "${wt}" commit -q --allow-empty -m old
mins_ago() { python3 -c 'import sys, time; print(time.strftime("%Y%m%d%H%M", time.localtime(time.time() - 60 * int(sys.argv[1]))))' "$1"; }
stallrc() { local got; got="$(SWARM_WAIT_STARTED="${old}" SWARM_STALL_POLL_MS=1000 waitrc /dev/null --stall a 3000)"; got="${got%|*}"; echo "${got##*|}"; }
echo wip > "${wt}/wip.txt"; touch -t "$(mins_ago 1)" "${wt}/wip.txt"
check "a busy builder with a file edited a minute ago in its worktree is not stalled: wait --stall times out" "exit 1" "$(stallrc)"
touch -t "$(mins_ago 120)" "${wt}/wip.txt"
check "the same file edited 2 hours ago is no sign of life: wait --stall exits 3, stalled" "exit 3" "$(stallrc)"
rm "${wt}/wip.txt"
check "a clean worktree with an old commit is stalled, as before" "exit 3" "$(stallrc)"
# Its session log (sess-a2, the newer agents.tsv line) written a minute ago is a sign of life too.
mkdir -p "${CLAUDE_PROJECTS_DIR}/p"; echo '{}' > "${CLAUDE_PROJECTS_DIR}/p/sess-a2.jsonl"
check "a busy builder whose session log was written a minute ago is not stalled" "exit 1" "$(stallrc)"
rm "${CLAUDE_PROJECTS_DIR}/p/sess-a2.jsonl"
rm -rf "${wt}" "${b}/stories/a.md"; : > "${p}/.claude/swarm/config"
# API errors: the session reads busy (background shells left open), herdr says done, and the pane's
# last turn ended on an API Error: line. wait resumes it up to 3 times in a row, then returns
# stalled: api error; tell delivers. A pane with a reply after the error is still working.
api_screen() { printf '%s\n' '⏺ Waiting on the builders.' '  ⎿  API Error: Connection dropped (ECONNRESET)' '' '> ' > "$1"; }
prompts() { grep -c "^agent prompt w:950 ${1:-}" "${ROOT}/herdr.log" || true; }
session "${ROOT}/claude.json" sess-a2=busy; echo "done" > "${ROOT}/hstatus"; api_screen "${ROOT}/screen"; : > "${ROOT}/herdr.log"
got="$(SWARM_STALL_POLL_MS=1000 waitrc /dev/null a 20000)"
check "an API-error stop, resumed 3 times, comes back a 4th time: wait returns stalled: api error with no 4th resume" \
  "stalled: api error|exit 3|3" "${got%|*}|$(prompts "Your last turn stopped on an API error; carry on where you stopped.")"
printf '%s\n' '  ⎿  API Error: Connection dropped (ECONNRESET)' '⏺ Carrying on.' > "${ROOT}/resumed"; : > "${ROOT}/herdr.log"
got="$(SWARM_STALL_POLL_MS=1000 waitrc /dev/null a 3000)"
check "a resumed agent whose turn then goes on: wait sends one resume and keeps waiting to the timeout" "busy|exit 1|1" "${got%|*}|$(prompts)"
echo "findings" > "${ROOT}/tell.txt"; api_screen "${ROOT}/screen"; : > "${ROOT}/herdr.log"
got="$(run tell a resume "${ROOT}/tell.txt")" || true
check "tell delivers to a busy session whose turn stopped on an API error" "told a|1" "${got}|$(prompts)"
printf '%s\n' '⏺ Waiting on the builders.' '' '> ' > "${ROOT}/screen"; : > "${ROOT}/herdr.log"
got="$(run tell a resume "${ROOT}/tell.txt")" || true
check "the same pane without the API Error: line: tell refuses" "yes|0" "$([[ "${got}" == *"still working"* ]] && echo yes || echo "no, ${got}")|$(prompts)"
# A busy session whose pane has not changed since the wait began, 2 hours ago (past stall_minutes):
# stalled: no output, naming the pane, and nothing sent. The earlier waits' pane record (pane_check)
# saw another screen, so it goes: this pane is first seen when the wait began.
echo working > "${ROOT}/hstatus"; rm -f "${p}/.swarm/panes/a"
got="$(SWARM_WAIT_STARTED=$(($(date +%s) - 7200)) SWARM_STALL_POLL_MS=1000 waitrc /dev/null a 5000)"
check "a pane unchanged past stall_minutes: wait returns stalled: no output naming the pane, and sends nothing" \
  "stalled: no output for 120m (w:950)|exit 3|0" "${got%|*}|$(prompts)"
rm -f "${ROOT}/hstatus" "${ROOT}/screen"
# A codex agent has no session: herdr answers for it.
printf '2026-10-15\tcode\ta\tcodex\tgpt\thigh\t-\n' >> "${p}/.swarm/agents.tsv"
check "a codex agent is still waited on through herdr" "done|exit 0" "$(SWARM_STALL_POLL_MS=1000 waitrc /dev/null a 2000 | cut -d'|' -f1-2)"
# The same name held only by another project's agent is never waited on or nudged.
item "${b}" stories/a.md "status: ready" "kind: code" "repo: svc"; rm -f "${p}/.swarm/state/wait-a"
: > "${ROOT}/herdr.log"
check "wait never addresses another project's agent of the same name" "0|0" \
  "$(grep -c '^agent wait' <<< "$(run wait a >/dev/null 2>&1; cat "${ROOT}/herdr.log")" || true)|$(nudges)"
rm -f "${b}/stories/a.md"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
