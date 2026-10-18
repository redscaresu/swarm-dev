#!/usr/bin/env bash
# epic_wait_test.sh — wait on an idle builder: who is nudged, an expired login, and goal on.
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
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }

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
                      if [ -e "$H/idle" ]; then echo '{"result":{"agent":{"agent_status":"idle"}}}'
                      else echo '{"result":{"agent":{"agent_status":"working"}}}'; fi ;;
  "agent start")      sid=$(echo "$*" | sed -n 's/.*--session-id \([^ ]*\).*/\1/p')
                      if [ -n "$sid" ]; then mkdir -p "$CLAUDE_PROJECTS_DIR/p"; : > "$CLAUDE_PROJECTS_DIR/p/$sid.jsonl"
                        echo "$CLAUDE_PROJECTS_DIR/p/$sid.jsonl" > "$H/session"; fi
                      echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')" >> "$H/agents" ;;
  "agent rename")     [ -e "$H/norename" ] && exit 1
                      [ -e "$H/agents" ] && awk -v t="$3" -v n="$4" '$2 == t { $1 = n } { print }' "$H/agents" > "$H/agents.tmp" && mv "$H/agents.tmp" "$H/agents" ;;
  "agent list")       [ -e "$H/listfail" ] && exit 1
                      awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                           { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
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
# state is its session's, from the claude stub's fixture. A builder idle before its story has a PR
# is nudged; any other idle agent is left alone. The pane shows an API error throughout, so the old
# rule (nudge on an API error on screen) would nudge every case here: none of these read the pane.
export CLAUDE_STUB_AGENTS="${ROOT}/claude.json"
session() { # <file> <session>=<status>... — a `claude agents --json` fixture
  local f="$1" e out=""; shift
  for e in "$@"; do out+="${out:+,}{\"sessionId\":\"${e%%=*}\",\"status\":\"${e#*=}\"}"; done
  echo "[${out}]" > "${f}"
}
nudges() { grep -c '^agent prompt' "${ROOT}/herdr.log" || true; }
nudged() { grep -c $'\tnudge\ta\t' "${p}/.swarm/events.tsv" || true; }
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
printf '%s\n' "⏺ API Error: 401 invalid key" > "${ROOT}/screen"
: > "${ROOT}/herdr.log"
check "an idle agent with no story is not nudged" "idle|0" "$(run wait a)|$(nudges)"
# Story a, in svc (repos_dir set), has no PR: its idle builder is nudged three times, each logged.
item "${b}" stories/a.md "status: ready" "kind: code" "repo: svc"
printf '%s\n' "repos_dir = ${ROOT}" > "${p}/.claude/swarm/config"
: > "${ROOT}/herdr.log"; : > "${p}/.swarm/events.tsv"
got="$(SWARM_STALL_POLL_MS=1000 waitrc /dev/null a 20000)"
check "an idle builder with no PR is nudged IDLE_NUDGES times, each logged as nudge a" "idle|exit 0|3|3" \
  "$(cut -d'|' -f1-2 <<< "${got}")|$(nudges)|$(nudged)"
check "the nudge says why, and does not wait for herdr to see it working" "yes|0" \
  "$(has "you are idle and story/a has no PR" "$(grep '^agent prompt' "${ROOT}/herdr.log")")|$(grep '^agent prompt' "${ROOT}/herdr.log" | grep -c -- '--until' || true)"
# The session stays idle: three nudges with a 1 s slice between each take at least two slices.
check "three nudges on a session that stays idle are spread over two slices or more" "yes" \
  "$([[ ${got##*|} -ge 2 ]] && echo yes || echo "no, ${got##*|}s")"
check "after a nudge, wait wakes before it takes the session's word again" "yes" \
  "$(grep -E '^agent (wait|prompt)' "${ROOT}/herdr.log" | awk '/^agent prompt/ { if (p) bad = 1; p = 1; next } { p = 0 } END { print bad ? "no" : "yes" }')"
echo "${ROOT}/svc.git" > "${ROOT}/pr-in"; : > "${ROOT}/herdr.log"
check "a builder whose PR sits in its story's repo is not nudged" "idle|0" "$(run wait a | tail -1)|$(nudges)"
# A counted close left an earlier attempt's PR closed on story/a: the retry has no PR of its own yet.
echo '[{"state":"CLOSED"}]' > "${ROOT}/prs-a.json"; : > "${ROOT}/herdr.log"
got="$(SWARM_STALL_POLL_MS=1000 waitrc /dev/null a 20000)"
check "a retry whose only PR on story/a is an earlier attempt's, closed, is nudged" "idle|3" "${got%%|*}|$(nudges)"
echo '[{"state":"CLOSED"},{"state":"OPEN"}]' > "${ROOT}/prs-a.json"; : > "${ROOT}/herdr.log"
check "a retry with its own open PR beside the closed one is not nudged" "idle|0" "$(run wait a | tail -1)|$(nudges)"
rm -f "${ROOT}/pr-in"; touch "${ROOT}/ghfail"; : > "${ROOT}/herdr.log"
check "a builder whose gh call fails is not nudged" "idle|0" "$(run wait a | tail -1)|$(nudges)"
rm -f "${ROOT}/ghfail"
item "${b}" stories/a.md "status: ready" "kind: verify" "repo: svc"; : > "${ROOT}/herdr.log"
check "a verify story's builder is not nudged" "idle|0" "$(run wait a | tail -1)|$(nudges)"
item "${b}" stories/a.md "status: blocked" "kind: code" "repo: svc"; : > "${ROOT}/herdr.log"
check "the builder of a story that is not ready (blocked) is not nudged" "idle|0" "$(run wait a | tail -1)|$(nudges)"
# A nudge herdr could not deliver is not logged or counted: wait stops nudging and returns idle.
item "${b}" stories/a.md "status: ready" "kind: code" "repo: svc"
touch "${ROOT}/promptfail"; : > "${ROOT}/herdr.log"; : > "${p}/.swarm/events.tsv"
got="$(SWARM_STALL_POLL_MS=1000 waitrc "${ROOT}/wait.err" a 20000)"
check "a nudge that could not be delivered is not logged, and wait returns idle, saying so" "idle|exit 0|1|0|yes" \
  "$(cut -d'|' -f1-2 <<< "${got}")|$(nudges)|$(nudged)|$(has "could not be delivered" "$(cat "${ROOT}/wait.err")")"
rm -f "${ROOT}/promptfail"
# The same builder, its transcript ending on an expired login: only the user's /login helps, so wait
# returns auth at once (a minute's slice), naming it, and never nudges it. The fixture is a real
# transcript's shape, ids replaced; without its auth entry the last turn is ordinary and the
# builder is nudged as before. CLAUDE_PROJECTS_DIR is set for these waits only.
fixture="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/login-expired.jsonl"
tr_dir="${ROOT}/projects"; tr="${tr_dir}/p/sess-a.jsonl"; mkdir -p "${tr_dir}/p"
cp "${fixture}" "${tr}"; : > "${ROOT}/herdr.log"; : > "${p}/.swarm/events.tsv"
got="$(CLAUDE_PROJECTS_DIR="${tr_dir}" SWARM_STALL_POLL_MS=60000 waitrc "${ROOT}/wait.err" a 120000)"
check "an idle builder whose login expired: wait prints auth at once, names it, and does not nudge" "auth|exit 0|yes|0|0|yes" \
  "${got%|*}|$([[ ${got##*|} -lt 5 ]] && echo yes || echo "no, ${got##*|}s")|$(nudges)|$(nudged)|$(has "a: its login expired" "$(cat "${ROOT}/wait.err")")"
grep -v authentication_failed "${fixture}" > "${tr}"; : > "${ROOT}/herdr.log"
got="$(CLAUDE_PROJECTS_DIR="${tr_dir}" SWARM_STALL_POLL_MS=1000 waitrc /dev/null a 20000)"
check "an idle builder after an ordinary turn is still nudged" "idle|3" "${got%%|*}|$(nudges)"
# A resume sent after the /login (a user entry after the auth error) clears it, before the agent
# has written a new assistant entry: wait does not print auth again.
{ cat "${fixture}"; printf '%s\n' '{"parentUuid":"00000000-0000-4000-8000-000000000004","isSidechain":false,"type":"user","uuid":"00000000-0000-4000-8000-000000000007","timestamp":"2026-10-13T18:50:00.000Z","message":{"role":"user","content":"Your login is renewed: resume where you stopped."},"userType":"external","entrypoint":"cli","cwd":"/w","sessionId":"sess-fixture","version":"2.1.296","gitBranch":"story/a"}'; } > "${tr}"
: > "${ROOT}/herdr.log"
got="$(CLAUDE_PROJECTS_DIR="${tr_dir}" SWARM_STALL_POLL_MS=1000 waitrc /dev/null a 20000)"
check "a user entry after the auth error (a resume) is not auth: the idle builder is nudged" "idle|3" "${got%%|*}|$(nudges)"
# Claude Code's own user entries after the auth error are not a resume: a queued task notification
# (shape from a real transcript, ids and text replaced), an isMeta entry, an Esc interrupt, and a
# slash command run in the pane (/login there; a real /exit pair's shape, its command and output
# replaced), which Claude Code writes as two user entries that are not isMeta.
automated=(
  task-notification '{"parentUuid":"00000000-0000-4000-8000-000000000004","isSidechain":false,"promptId":"00000000-0000-4000-8000-000000000008","type":"user","message":{"role":"user","content":"<task-notification>\n<task-id>bfixture1</task-id>\n<tool-use-id>toolu_fixture</tool-use-id>\n<output-file>/tmp/fixture.output</output-file>\n<status>completed</status>\n<summary>Background command \"Wait on a builder\" completed (exit code 0)</summary>\n</task-notification>"},"uuid":"00000000-0000-4000-8000-000000000009","timestamp":"2026-10-13T16:10:00.000Z","permissionMode":"auto","origin":{"kind":"task-notification","producer":"session-task","runId":"fixture-run"},"promptSource":"system","turnOrigin":"task_notification","queueSkipAttachments":true,"userType":"external","entrypoint":"cli","cwd":"/w","sessionId":"sess-fixture","version":"2.1.296","gitBranch":"story/a"}'
  isMeta '{"parentUuid":"00000000-0000-4000-8000-000000000009","isSidechain":false,"type":"user","message":{"role":"user","content":"A scheduled fixture prompt."},"isMeta":true,"uuid":"00000000-0000-4000-8000-00000000000a","timestamp":"2026-10-13T16:20:00.000Z","promptSource":"system","turnOrigin":"scheduled","userType":"external","entrypoint":"cli","cwd":"/w","sessionId":"sess-fixture","version":"2.1.296","gitBranch":"story/a"}'
  interrupted '{"parentUuid":"00000000-0000-4000-8000-00000000000a","isSidechain":false,"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]},"uuid":"00000000-0000-4000-8000-00000000000b","timestamp":"2026-10-13T16:30:00.000Z","userType":"external","entrypoint":"cli","cwd":"/w","sessionId":"sess-fixture","version":"2.1.296","gitBranch":"story/a"}'
  slash-command '{"parentUuid":"00000000-0000-4000-8000-000000000004","isSidechain":false,"promptId":"00000000-0000-4000-8000-00000000000c","type":"user","message":{"role":"user","content":"<command-name>/login</command-name>\n            <command-message>login</command-message>\n            <command-args></command-args>"},"uuid":"00000000-0000-4000-8000-00000000000d","timestamp":"2026-10-13T16:40:00.000Z","userType":"external","entrypoint":"cli","cwd":"/w","sessionId":"sess-fixture","version":"2.1.296","gitBranch":"story/a"}
{"parentUuid":"00000000-0000-4000-8000-00000000000d","isSidechain":false,"promptId":"00000000-0000-4000-8000-00000000000c","type":"user","message":{"role":"user","content":"<local-command-stdout>Login successful</local-command-stdout>"},"uuid":"00000000-0000-4000-8000-00000000000e","timestamp":"2026-10-13T16:40:00.000Z","userType":"external","entrypoint":"cli","cwd":"/w","sessionId":"sess-fixture","version":"2.1.296","gitBranch":"story/a"}'
)
for ((i = 0; i < ${#automated[@]}; i += 2)); do
  { cat "${fixture}"; printf '%s\n' "${automated[i + 1]}"; } > "${tr}"; : > "${ROOT}/herdr.log"
  got="$(CLAUDE_PROJECTS_DIR="${tr_dir}" SWARM_STALL_POLL_MS=60000 waitrc /dev/null a 120000)"
  check "an automated user entry (${automated[i]}) after the auth error is not a resume: still auth" "auth|0" "${got%%|*}|$(nudges)"
done
# A transcript that cannot be read is not expired, and wait prints no traceback.
cp "${fixture}" "${tr}"; chmod 000 "${tr}"; : > "${ROOT}/herdr.log"
got="$(CLAUDE_PROJECTS_DIR="${tr_dir}" SWARM_STALL_POLL_MS=1000 waitrc "${ROOT}/wait.err" a 20000)"
check "an unreadable transcript is not auth, and wait prints no traceback" "idle|3|0" \
  "${got%%|*}|$(nudges)|$(grep -c Traceback "${ROOT}/wait.err" || true)"
chmod 600 "${tr}"
# With goal on, wait nudges no builder: whether its goal is set, met or missing, it returns idle at
# once, with no nudge and no nudge line in events.tsv, so the reply and goal entry stay last. The goal_status shapes are the ones Claude Code 2.1.299 wrote in the goal spike.
item "${b}" stories/a.md "status: ready" "kind: code" "repo: svc"
printf '%s\n' "goal = 5" "repos_dir = ${ROOT}" > "${p}/.claude/swarm/config"
gs() { # <met> <sentinel> — a goal_status entry
  printf '{"type":"attachment","timestamp":"2026-10-14T10:00:00.000Z","attachment":{"type":"goal_status","met":%s,"sentinel":%s,"condition":"DW-ONE holds"}}\n' "$1" "$2"
}
{ grep -v authentication_failed "${fixture}"; gs false true; gs false false; } > "${tr}"
: > "${ROOT}/herdr.log"; : > "${p}/.swarm/events.tsv"
got="$(CLAUDE_PROJECTS_DIR="${tr_dir}" SWARM_STALL_POLL_MS=1000 waitrc /dev/null a 20000)"
check "goal = 5 and a goal set in the session log: the idle builder with no PR is not nudged, nor logged" "idle|exit 0|0|0" \
  "$(cut -d'|' -f1-2 <<< "${got}")|$(nudges)|$(nudged)"
grep -v authentication_failed "${fixture}" > "${tr}"; : > "${ROOT}/herdr.log"; : > "${p}/.swarm/events.tsv"
got="$(CLAUDE_PROJECTS_DIR="${tr_dir}" SWARM_STALL_POLL_MS=1000 waitrc /dev/null a 20000)"
check "goal = 5 and no goal entry in the session log: the idle builder with no PR is not nudged, nor logged" "idle|0|0" \
  "${got%%|*}|$(nudges)|$(nudged)"
{ grep -v authentication_failed "${fixture}"; gs false true; gs true false; } > "${tr}"
: > "${ROOT}/herdr.log"; : > "${p}/.swarm/events.tsv"
got="$(CLAUDE_PROJECTS_DIR="${tr_dir}" SWARM_STALL_POLL_MS=1000 waitrc /dev/null a 20000)"
check "goal = 5 and the goal met: the idle builder with no PR is not nudged, nor logged" "idle|0|0" "${got%%|*}|$(nudges)|$(nudged)"
rm -f "${ROOT}/screen" "${b}/stories/a.md" "${tr}"
: > "${p}/.claude/swarm/config"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
