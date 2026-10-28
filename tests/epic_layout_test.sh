#!/usr/bin/env bash
# epic_layout_test.sh — the layout (an epic's tab holds its conductor and a pane per story), the
# conductor's and builder's briefs, and conductors that fail to start.
# herdr is a stub on PATH that hands out pane ids in order and remembers tab labels; the repo is a
# local bare remote. gh is a stub too, so a close's PR lookup never reaches the real gh.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

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
# codex_form <base> <text> — <text> runs codex through codex-review against <base>, with the config's
# project, in the background (a foreground Bash call ends before the limit), and says what a timeout means.
codex_form() {
  printf '%s|%s|%s' "$(has "SWARM_PROJECT=${p} ${SWARM} codex-review $1\`" "$2")" \
    "$(has "Run codex-review in the background (Bash run_in_background) and wait for it to finish" "$2")" "$(has "codex skipped: timed out" "$2")"
}
# para <pattern> <text> — the paragraph of <text> that starts on the line matching <pattern>.
para() { awk -v pat="$1" 'index($0, pat) { on = 1 } on && /^$/ { exit } on' <<< "$2"; }
# gives_up <brief> — give_up_rule's parts, as has prints them: the give-up close of a code, docs or
# chore story, a retry on the model swarm.sh picks (Fable after escalate_after, 2 here), Fable's consent
# accepted through send-keys only on an escalate build and logged, a dialog never closed or counted,
# no other dialog or prompt answered, and an escalated story the lead's.
gives_up() {
  # shellcheck disable=SC2016 # the backticks are the brief's
  printf '%s|' "$(has 'Run `swarm.sh close <slug> --drop`: on a code, docs or chore story still `ready` it' "$1")" \
    "$(has 'model: swarm.sh picks Fable for build 3 (escalate_after = 2).' "$1")" "$(has 'waiting: dialog open' "$1")" \
    "$(has 'only when it is an escalate build (`swarm.sh _role <slug>` prints `escalate`)' "$1")" \
    "$(has 'herdr pane send-keys <pane>' "$1")" "$(has 'swarm.sh dialog <slug> accepted' "$1")" \
    "$(has 'dialog: a dialog is not an attempt. Any other dialog, and every permission or tool prompt' "$1")" \
    "$(has 'yours to answer: never send keys to it; leave it for the lead.' "$1")" \
    "$(has "is the lead's to decide: report it" "$1")"
  has "for the user, unless it has \`escalated_from:\`: that one is the lead's" "$1"
}
GIVES_UP="yes|yes|yes|yes|yes|yes|yes|yes|yes|yes"
# shellcheck disable=SC2016 # the backticks are the brief's
STRICT_RULE='Start every story, a retry too, with `swarm.sh story --strict <slug>`.'
# goal_on <brief> — goal_rule's parts, as has prints them: the six causes, the impossible close, one
# resume tell for a pause and then the paused close, cleared-on-error stopping the wave and its story
# held for the lead, the transcript under CLAUDE_PROJECTS from the current build's agents.tsv line
# (agent_name described in full), and the goal-on give-up: only a stall or an unconverged review,
# an idle builder left to the goal rule, no 'after wait's nudges', a stalled close. No `failed` entry.
goal_on() {
  local c
  # shellcheck disable=SC2016 # the backticks are the brief's
  printf '%s|' "$(has "\`${CLAUDE_PROJECTS_DIR}/*/<session>.jsonl\`" "$1")" \
    "$(has "whose name (field 3) is the builder's agent name" "$1")" \
    "$(has 'so no wave builds it until the lead lifts the hold.' "$1")" \
    "$(has 'an s in front unless it starts with a letter, then cut' "$1")" \
    "$(has '- none of the above fits (no reply, no refusal, no stall, and no goal entry, or a met entry whose' "$1")" \
    "$(has '`held_for: paused`): list it for the lead, as for cleared-on-error.' "$1")" \
    "$(has 'returns stalled with no hung command to' "$1")" "$(has "it is the goal rule's, which picks" "$1")" \
    "$(grep -qF 'with `failed`' <<< "$1" && echo failed || echo "no failed")"
  # shellcheck disable=SC2016 # the backticks are the brief's
  for c in '- met: ' '- impossible: ' '- stalled: ' '- bound: ' '- paused: ' '- cleared-on-error: ' \
    'Run `swarm.sh close <slug> impossible --drop`' 'Send it one `swarm.sh tell <slug> resume <file>`' \
    'If it stops paused again, run `swarm.sh close <slug> paused --drop`.' \
    'Run `swarm.sh close <slug> cleared-on-error --drop`, start nothing more in this wave' 'Run `swarm.sh close <slug> stalled --drop`'; do
    printf '%s|' "$(has "${c}" "$1")"
  done
  grep -qF "after wait's nudges" <<< "$1" && echo nudges || echo "no nudges"
}
GOAL_ON="yes|yes|yes|yes|yes|yes|yes|yes|no failed|yes|yes|yes|yes|yes|yes|yes|yes|yes|yes|yes|no nudges"
# inbox_rule <epic> <brief> — conduct_brief's inbox rule, as has prints them: the inbox; after each
# wait or watch, an interrupted read's copy first; then the mv to that exact copy, read, act and delete;
# and all of it once more before the report.
INBOX_RULE="yes|yes|yes|yes|yes"
inbox_rule() {
  local b i=".swarm/inbox/conduct-$1"; b="$(tr '\n' ' ' <<< "$2")"
  # shellcheck disable=SC2016 # the backticks are the brief's
  printf '%s|%s|%s|%s|%s' "$(has "${i}.md. After each \`swarm.sh wait\` or \`swarm.sh watch\` returns: if " "${b}")" \
    "$(has "${i}.reading.md is there (a read cut off before its delete), read it, act on it and delete it first." "${b}")" \
    "$(has 'Then, if the inbox exists, `mv` it to ' "${b}")" \
    "$(has "${i}.reading.md (atomic, so a note the lead adds meanwhile starts a new file), read the moved copy, act on it, and delete it." "${b}")" \
    "$(has "Do all this once more just before you write your report, so a note left after your last wait is not lost." "${b}")"
}
# goal_off <brief> — with goal off, give_up_rule as conductor-give-up-rule left it, and no goal rule.
goal_off() {
  printf '%s|' "$(has "after wait's nudges" "$1")" "$(grep -qF cleared-on-error <<< "$1" && echo yes || echo no)"
  # shellcheck disable=SC2016 # the backticks are the brief's
  grep -qF 'close <slug> impossible --drop`' <<< "$1" && echo yes || echo no
}

item() { # <board> <path> <front-matter line>... — a fresh item: its file, and no state file
  local path="$1/$2" title; rm -f "$(dirname "$1")/.swarm/board-state/${2%.md}"; shift 2
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}
# val <slug> <key> — <key> of a story on ${b} as swarm.sh reads it: board.sh's own get_fm.
# shellcheck source=/dev/null
val() { (export BOARD="${b}" PROJECT_DIR="${p}"; . "${SWARM%/*}/lib/board.sh"; get_fm "${b}/stories/$1.md" "$2"); }

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
  "--version ") echo "herdr 0.9.5" ;;   # start_agent's require_herdr_version
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
# gh: logs every call; pr list prints ${ROOT}/prs.json, or no PRs, and with --state open (close's
# call) the heads of its open PRs that name one, as its --jq asks; pr view <url> gives the state on
# <url>'s line in ${ROOT}/pr-states.
gh_stub() {
  printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/gh"
  # shellcheck disable=SC2016 # the stub's own shell expands these
  printf '%s\n' 'echo "$*" >> "$H/gh.log"' \
    'case "$1 $2 $*" in "pr list "*"--state open"*) [ -e "$H/prs.json" ] && python3 -c '\''import json, sys; [print(p["headRefName"]) for p in json.load(open(sys.argv[1])) if p.get("state") == "OPEN" and p.get("headRefName")]'\'' "$H/prs.json" ;; esac' \
    'case "$1 $2" in "pr list") case "$*" in *"--state open"*) ;; *) cat "$H/prs.json" 2>/dev/null || echo "[]" ;; esac ;;' \
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

# --- Layout: the conductor opens the epic's tab; its stories fill it, then overflow to "<epic>-2".
item "${b}" epics/e.md "status: active"
for s in s1 s2 s3; do item "${b}" "stories/${s}.md" "status: ready" "kind: code" "epic: e" "repo: svc"; done
item "${b}" stories/s4.md "status: ready" "kind: code" "epic: e" "repo: svc" "touches: [.claude-plugin/plugin.json]"
item "${b}" stories/o1.md "status: ready" "kind: code" "repo: svc"
# A project that ships a plugin: no brief names plugin.json, the release story's (s4's touches name it) included.
# plugin <brief> — whether the brief names plugin.json; missing when it was never written, so a check
# for its absence cannot pass on a brief that does not exist.
plugin() { if [[ ! -s "$1" ]]; then echo missing; elif grep -qF plugin.json "$1"; then echo yes; else echo no; fi; }
mkdir -p "${p}/.claude-plugin"; echo '{"version": "1.0.0"}' > "${p}/.claude-plugin/plugin.json"
mkdir -p "${p}/.swarm/inbox"; echo "a note for the last run" | tee "${p}/.swarm/inbox/conduct-e.md" > "${p}/.swarm/inbox/conduct-e.reading.md"
run conduct e >/dev/null
check "a new conductor starts with no inbox or reading copy left from the run before" "no|no" \
  "$([[ -e "${p}/.swarm/inbox/conduct-e.md" ]] && echo yes || echo no)|$([[ -e "${p}/.swarm/inbox/conduct-e.reading.md" ]] && echo yes || echo no)"
check "the conductor opens a tab named for the epic" "yes" "$(has "tab create --workspace w --cwd ${p} --label e --no-focus" "$(log)")"
check "and its pane is named conductor" "yes" "$(has "pane rename w:1 conductor" "$(log)")"
check "the conductor's brief watches only its own epic's PRs" "yes" \
  "$(grep -q 'swarm.sh watch --epic e`' "${p}/.swarm/briefs/conduct-e.md" && echo yes || echo no)"
cbrief="$(cat "${p}/.swarm/briefs/conduct-e.md")"
check "the conductor's brief includes the project's brief, so the project's rules reach it" "yes" "$(has "A PROJECT RULE every agent reads." "${cbrief}")"
# The review agent waits for green, triages, tells its builder and merges or hands over: the conductor
# only starts it, once per PR. If the brief again has the conductor wait on a review, triage it, tell
# findings or log one, a review is driven twice and its findings go out twice, and these go red.
review="$(para "A story is reviewed only by" "${cbrief}")"; rflat="$(tr -s '[:space:]' ' ' <<< "${review}")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "the review paragraph starts review-agent once on watch's opened line, on a queued: line and for a kept: PR" "yes|yes|yes|yes" \
  "$(has "When \`swarm.sh watch\` prints \`<repo> #<n> story/<slug> opened\`, a PR of yours has opened: start its review agent once, at once, with \`${SWARM} review-agent <slug> <PR URL>\`." "${rflat}")|$(has '`queued: <repo> #<n> <branch> green <m>m with no review on <sha>`, that head has had no review: start its review agent then, the same way.' "${rflat}")|$(has 'A story `swarm.sh status` lists as `kept:` (a close kept its PR unreviewed) gets one the same way' "${rflat}")|$(has "then start the review agent on the line's PR." "${rflat}")"
# shellcheck disable=SC2016 # the backticks are the brief's
# A review agent started on the opened line can stop on a head the builder pushes before its first
# round; queued: waits queue_minutes. If the paragraph drops the restart on watch's checks-finished
# line, that head waits half an hour for a review, and this goes red.
# shellcheck disable=SC2016 # the backticks are the brief's
check "the review paragraph starts the review agent again on each checks finished line, and review-agent's refusal stops a second one" "yes|yes" \
  "$(has 'When `swarm.sh watch` prints `<repo> #<n> story/<slug> checks finished on <sha>` for a PR of yours, start its review agent again the same way' "${rflat}")|$(has 'While it still reviews, review-agent refuses and nothing starts.' "${rflat}")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "the review paragraph starts a refused review agent again once its builder's wait returns or on watch's next line, and never waits on a PR or a review agent" "yes|yes" \
  "$(has 'whatever the refusal says to do next, start it again once `swarm.sh wait <slug>` on that builder returns, or on `swarm.sh watch`'"'"'s next line for that PR, whichever comes first.' "${rflat}")|$(has "Never wait on a PR or a review agent, read a review file, triage, tell a builder findings, log a finding, close a review agent or merge a story's PR" "${rflat}")"
# A review agent's stop reaches the conductor only as a note, and a base-merged head refuses review-agent
# for as long as the merge runs: if the brief drops the note rule, the story sits; if it drops the
# second-refusal rule, the conductor retries in a loop.
# shellcheck disable=SC2016 # the backticks are the brief's
check "the review paragraph acts on a review agent's stop note, and starts nothing on a second refusal of the same head" "yes|yes|yes" \
  "$(has 'A note in your inbox that says `review-<slug> stopped on <sha>: <why>` is a review agent that stopped before a pass, and the story is yours again.' "${rflat}")|$(has 'nudge it once, with a file naming the stop line, as `swarm.sh wait --stall --idle <slug> && swarm.sh tell <slug> nudge <file>` in the background (the clash rule above says how that form sends). Once that tell has gone, start the review agent again when the next `swarm.sh wait <slug>` on the builder returns.' "${rflat}")|$(has 'If it refuses so again on the same head with the builder idle, start nothing more for that head' "${rflat}")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "the review paragraph nudges the builder on a dequeued merge's stop note in the wait-then-tell form, waits on an already-nudged builder after a base merge, closes the builder on a merge hold, and reports the rest for the lead" "yes|yes|yes|yes" \
  "$(has 'for a `dequeued` merge, nudge the builder with a file naming the failing checks, telling it to merge origin/<base> in and push, in the same form, `swarm.sh wait --stall --idle <slug> && swarm.sh tell <slug> nudge <file>` in the background, and its new head gets a new review agent as above' "${rflat}")|$(has 'the review agent has nudged the builder already, so wait on it and start the review agent again on the head it pushes' "${rflat}")|$(has 'the user merges the PR, maybe days later, so close its builder with a bare `swarm.sh close <slug>`' "${rflat}")|$(has 'an `unconfirmed` merge or a base red or timed out after it goes in your report for the lead.' "${rflat}")"
cflat="$(tr -s '[:space:]' ' ' <<< "${cbrief}")"
check "the conductor's brief never waits on a review agent, tells findings, logs a finding or reviews the moment a head is green" "0|0|0|0|0" \
  "$(grep -c 'swarm.sh wait review-<slug>' <<< "${cflat}" || true)|$(grep -c 'tell <slug> findings' <<< "${cflat}" || true)|$(grep -c 'log-finding --declined' <<< "${cflat}" || true)|$(grep -c "The moment a story's PR head is green" <<< "${cflat}" || true)|$(grep -c 'log-finding' <<< "${cflat}" || true)"
check "the conductor's brief says what a builder's auth means and to resume it after the login, then wait on it again" "yes|yes" \
  "$(has "stopped on an expired login, which only the user's" "${cbrief}")|$(has "again with \`swarm.sh wait <slug>\` in the background." "${cbrief}")"
check "the conductor gives up on a builder with close, accepts a Fable dialog itself, and leaves an escalated story to the lead" \
  "${GIVES_UP}" "$(gives_up "${cbrief}")"
check "with goal off, the story-mode conductor waits out wait's nudges, and has no goal rule" "yes|no|no" "$(goal_off "${cbrief}")"
# The review agent and the ladder limit a PR's rounds; a conductor that gives up on an unconverged
# review clears the build (close --drop) under a live review agent. If either clause comes back, this goes red.
check "the conductor gives up on no unconverged review, and leaves rounds to the review agent and the ladder" "no|yes" \
  "$(grep -qF "review has not converged" <<< "$(tr -s '[:space:]' ' ' <<< "${cbrief}")" && echo yes || echo no)|$(has "A PR's review rounds are its review agent's and the ladder's to limit, never yours." "$(tr -s '[:space:]' ' ' <<< "${cbrief}")")"
check "the story-mode conductor moves its inbox aside after each wait, then reads and deletes the copy" "${INBOX_RULE}" "$(inbox_rule e "${cbrief}")"
check "the new workspace's placeholder tab is closed" "yes" "$(has "tab close t0" "$(log)")"
check "the story-mode conductor starts every story with --strict, waits for the merge on an is-open refusal, and retries on cannot-tell" "yes|yes|yes" \
  "$(has "${STRICT_RULE}" "${cbrief}")|$(has "start yours in a later wave, after the named story merges" "${cbrief}")|$(has "nothing is known to be open: retry the story in a later wave" "${cbrief}")"
check "the story-mode conductor's brief never starts a story without --strict" "0" "$(grep -c 'swarm.sh story <slug>' <<< "${cbrief}" || true)"
check "with merge = human, the story-mode conductor stops when the Done when holds or nothing ready is left, and pins no merge" "yes|no" \
  "$(has "Stop when the epic's **Done when** holds or when nothing ready is left." "${cbrief}")|$(grep -qF -- --match-head-commit <<< "${cbrief}" && echo yes || echo no)"
for s in s1 s2 s3 s4; do run story "${s}" >/dev/null; done
check "the story-mode builder runs codex-review against its story in the background, and knows what a timeout means" "yes|yes|yes|yes" \
  "$(codex_form main "$(cat "${p}/.swarm/briefs/s1.md")")|$(has "SWARM_STORY=s1 SWARM_PROJECT=${p} ${SWARM} codex-review main\`" "$(cat "${p}/.swarm/briefs/s1.md")")"
check "the builder's brief says nothing of review agents" "0" "$(grep -c 'review agent' "${p}/.swarm/briefs/s1.md" || true)"
sid="$(grep '^agent start s1 ' "${ROOT}/herdr.log" | sed -n 's/.*--session-id \([^ ]*\).*/\1/p')"
check "a story starts with a --session-id, and its agents.tsv line ends in it" "yes|${sid}" \
  "$([[ -n "${sid}" ]] && echo yes || echo no)|$(awk -F'\t' 'NF == 7 && $3 == "s1" { print $7 }' "${p}/.swarm/agents.tsv")"
check "a story of the epic splits the conductor's pane, and is named" "yes|yes" \
  "$(has "pane split w:1 --direction right" "$(log)")|$(has "pane rename w:2 s1" "$(log)")"
check "the fourth pane splits the second, and the fifth opens <epic>-2" "yes|yes" \
  "$(has "pane split w:2 --direction down" "$(log)")|$(has "--label e-2 " "$(log)")"
run story o1 >/dev/null
check "a story outside any epic gets a tab of its own" "yes" "$(has "--label o1 " "$(log)")"
check "with plugin.json, no builder brief (an epic's story, the release story, a one-off) and no story-mode conductor brief names it" "no|no|no|no" \
  "$(plugin "${p}/.swarm/briefs/s1.md")|$(plugin "${p}/.swarm/briefs/s4.md")|$(plugin "${p}/.swarm/briefs/o1.md")|$(plugin "${p}/.swarm/briefs/conduct-e.md")"
: > "${ROOT}/herdr.log"
run close s1 >/dev/null
check "closing a story closes its pane and leaves the epic's tab" "yes|no|no" \
  "$(has "pane close w:2" "$(log)")|$(grep -q 'tab close' "${ROOT}/herdr.log" && echo yes || echo no)|$(grep -q ' s1$' "${p}/.swarm/state/e" && echo yes || echo no)"
check "closing a ready story's builder counts a failed build and removes its worktree" "1|no" \
  "$(val s1 attempts)|$([[ -d "${ROOT}/svc-wt/s1" ]] && echo yes || echo no)"
run close conduct-e >/dev/null
check "closing the conductor closes the epic's tabs" "tab close t1|tab close t5" "$(grep '^tab close' "${ROOT}/herdr.log" | paste -sd'|' -)"

# A conductor that never takes its brief (an agent not logged in) must not leave the placeholder behind.
: > "${ROOT}/herdr.log"; touch "${ROOT}/idle"
run conduct e >/dev/null || true
rm "${ROOT}/idle"
check "a conductor that fails to start still closes the placeholder tab" "yes" "$(has "tab close t0" "$(log)")"
echo "goal = 5" > "${p}/.claude/swarm/config"
run conduct e >/dev/null || true
check "with goal = 5, the story-mode conductor reads why a builder stopped and closes it with that cause" \
  "${GOAL_ON}" "$(goal_on "$(cat "${p}/.swarm/briefs/conduct-e.md")")"
# A second conduct e, refused while conduct-e's session is busy, leaves the live conductor's notes.
mkdir -p "${p}/.swarm/inbox"; echo "a note for the live conductor" | tee "${p}/.swarm/inbox/conduct-e.md" > "${p}/.swarm/inbox/conduct-e.reading.md"
out="$(CLAUDE_STUB_AGENTS="${ROOT}/started.json" run conduct e || true)"
check "a refused second conduct leaves the live conductor's inbox and reading copy" "yes|yes|yes" \
  "$(has "still working" "${out}")|$([[ -e "${p}/.swarm/inbox/conduct-e.md" ]] && echo yes || echo no)|$([[ -e "${p}/.swarm/inbox/conduct-e.reading.md" ]] && echo yes || echo no)"
rm -f "${p}/.swarm/inbox/conduct-e.md" "${p}/.swarm/inbox/conduct-e.reading.md"
run close conduct-e >/dev/null; : > "${p}/.claude/swarm/config"

# --- A pane closed by hand is dropped from the state, so the next agent does not split it.
item "${b}" epics/d.md "status: active"
item "${b}" stories/d1.md "status: ready" "kind: code" "epic: d" "repo: svc"
mkdir -p "${p}/.swarm/state"; echo "w:gone conductor" > "${p}/.swarm/state/d"
echo '{"result":{"panes":[]}}' > "${ROOT}/live"
: > "${ROOT}/herdr.log"
run conduct d >/dev/null
check "a closed pane is pruned: the conductor opens a fresh tab instead of splitting it" "yes|no|1" \
  "$(has "--label d " "$(log)")|$(grep -q 'split w:gone' "${ROOT}/herdr.log" && echo yes || echo no)|$(wc -l < "${p}/.swarm/state/d" | tr -d ' ')"
# A split herdr refuses must not record an empty pane, which would break every later run.
echo "{\"result\":{\"panes\":[{\"pane_id\":\"$(awk '{ print $1 }' "${p}/.swarm/state/d")\"}]}}" > "${ROOT}/live"
touch "${ROOT}/nosplit"
run story d1 >/dev/null || true
check "a failed split records no pane" "1" "$(wc -l < "${p}/.swarm/state/d" | tr -d ' ')"
rm -f "${ROOT}/live" "${ROOT}/nosplit" "${b}/epics/d.md" "${b}/stories/d1.md"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
