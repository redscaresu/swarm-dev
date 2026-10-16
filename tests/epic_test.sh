#!/usr/bin/env bash
# epic_test.sh — the layout (an epic's tab holds its conductor and a pane per story) and
# pr_per = epic (stories branch from, and merge into, epic/<slug>). herdr is a stub on PATH that
# hands out pane ids in order and remembers tab labels; the repo is a local bare remote. gh is a stub
# too, so a close's PR lookup never reaches the real gh.
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
first() { printf '%s' "${1%%$'\n'*}"; }
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
  printf '%s|' "$(has 'Run `swarm.sh close <slug>`: on a code, docs or chore story still `ready` it' "$1")" \
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
    "$(has 'returns stalled, or when review has' "$1")" "$(has "it is the goal rule's, which picks" "$1")" \
    "$(grep -qF 'with `failed`' <<< "$1" && echo failed || echo "no failed")"
  # shellcheck disable=SC2016 # the backticks are the brief's
  for c in '- met: ' '- impossible: ' '- stalled: ' '- bound: ' '- paused: ' '- cleared-on-error: ' \
    'Run `swarm.sh close <slug> impossible`' 'Send it one `swarm.sh tell <slug> resume <file>`' \
    'If it stops paused again, run `swarm.sh close <slug> paused`.' \
    'Run `swarm.sh close <slug> cleared-on-error`, start nothing more in this wave' 'Run `swarm.sh close <slug> stalled`'; do
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
  grep -qF 'close <slug> impossible`' <<< "$1" && echo yes || echo no
}

item() { # <board> <path> <front-matter line>...
  local path="$1/$2" title; shift 2
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

# goal_story <board> <slug> <front-matter line>... — a story with a Done when and a From review block,
# and a From the spike block that is not part of a goal.
goal_story() {
  local bd="$1" slug="$2"; shift 2
  item "${bd}" "stories/${slug}.md" "$@"
  printf '%s\n' "" "Scope." "" "**Done when:**" "- DW-ONE holds" "- DW-TWO holds" "" \
    "**From review (binding; overrides the scope above where they differ):**" "- FR-ONE holds" "" \
    "**From the spike (binding):**" "- SPIKE-ONE" >> "${bd}/stories/${slug}.md"
}
# goal_parts <goal file> <slug> <reply sentence> <bound> — has for each part a goal condition holds:
# the story's Done when and From review named by its path, none of its items inlined, the reply, the
# escape and the bound.
goal_parts() {
  local g; g="$(cat "$1" 2>&1)"
  printf '%s|' "$(has "Every item under **Done when:** and **From review**, if any, in ${b}/stories/$2.md" "${g}")" \
    "$(grep -qE 'DW-ONE|FR-ONE|SPIKE-ONE' <<< "${g}" && echo inlined || echo yes)" "$(has "$3" "${g}")" "$(has "IMPOSSIBLE: <why>" "${g}")"
  has "or stop after $4 more turns" "${g}"
}
GOAL_PARTS="yes|yes|yes|yes|yes"
# goal_path <brief> <goal file> — the story path the brief's Implement line gives, when the goal names
# that same path, or both.
goal_path() {
  local ref; ref="$(sed -n 's/^Implement \(.*\)\. Its \*\*Done when\*\* is the acceptance\.$/\1/p' "$1")"
  ref="${ref%% (this worktree is *}"
  if [[ -n "${ref}" ]] && grep -qF -- "in ${ref} (your brief's story" "$2"; then echo "${ref}"; else echo "brief: '${ref}', goal: $(cat "$2")"; fi
}
GOAL_SEND_MAX="$(sed -n 's/^GOAL_SEND_MAX=\([0-9]*\).*/\1/p' "${SWARM}")"
# The sentence finding_rule gives every conductor: which --reviewer value names which reviewer.
MAPPING="<who> is the reviewer that first raised it, whoever passed it on: codex for a finding from \`swarm.sh codex-review\`, code-review for /code-review's, ci for the PR review bot's or a \`swarm.sh findings\` note's, conductor for one from your own reading of the diff, and lead only for one from the lead's own reading."
# logs_findings <brief> — the brief's log-finding lines, filled in with --reviewer codex, a kind, a PR
# and text and run as written: the outcome and reviewer of the row each logs, then has for MAPPING.
logs_findings() {
  local f="${p}/.swarm/findings.tsv" line n
  while IFS= read -r line; do
    line="${line//<who>/codex}"; line="${line//<kind>/brief-kind}"; line="${line//<PR URL>/o/r#9}"; line="${line//<reason>/nit}"
    line="${line%%\"<*}\"text\""   # the text placeholder is the last word
    n=0; [[ ! -f "${f}" ]] || n="$(wc -l < "${f}")"
    if ! (cd "${ROOT}" && env -u SWARM_PROJECT bash -c "${line}" >/dev/null 2>&1); then printf 'failed: %s|' "${line}"; continue; fi
    [[ "$(wc -l < "${f}")" -eq $((n + 1)) ]] && printf '%s|' "$(tail -1 "${f}" | cut -f5,6 | tr '\t' ' ')" || printf 'no row|'
  done < <(grep -E '^    SWARM_PROJECT=.* log-finding ' <<< "$1")
  has "${MAPPING}" "$(tr -s '[:space:]' ' ' <<< "$1")"
}
LOGS_FINDINGS="fixed codex|declined codex|yes"
STORY_REPLY="When CI is green, reply with the PR URL, what changed in three lines, and the codex findings and the mutation, then stay open: the conductor may send review findings to fix on the same PR."
EPIC_REPLY="When your branch is pushed, reply with the branch, what changed in three lines, the codex findings and the mutation, then stop."

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
nx() { (cd "${p}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" next 2>&1); }

# --- Layout: the conductor opens the epic's tab; its stories fill it, then overflow to "<epic>-2".
item "${b}" epics/e.md "status: active"
for s in s1 s2 s3 s4; do item "${b}" "stories/${s}.md" "status: ready" "kind: code" "epic: e" "repo: svc"; done
item "${b}" stories/o1.md "status: ready" "kind: code" "repo: svc"
# A project that ships a plugin: its epic's release story bumps plugin.json, so a story PR need not.
BUMP="the epic's release story (the one whose touches name it) does"
# bumped <text> — whether <text> carries the bump line; missing when <text> is empty, so a check for
# its absence cannot pass on a brief or paragraph that was never written.
bumped() { if [[ -z "$1" ]]; then echo missing; elif grep -qF -- "${BUMP}" <<< "$1"; then echo yes; else echo no; fi; }
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
check "the conductor's brief includes the project's brief, so adopted lessons reach it" "yes" "$(has "A PROJECT RULE every agent reads." "${cbrief}")"
check "the story-mode conductor's log-finding lines name the reviewer, and log codex's findings as codex" "${LOGS_FINDINGS}" "$(logs_findings "${cbrief}")"
check "the conductor reviews with codex and /code-review, tells the builder, and closes only after" "yes|yes|yes|yes" \
  "$(has "codex-review <base>" "${cbrief}")|$(has "/code-review <PR>" "${cbrief}")|$(has "swarm.sh tell <slug> findings <file>" "${cbrief}")|$(has "Never merge a story, and never run" "${cbrief}")"
check "the conductor's brief says what a builder's auth means and to resume it after the login, then wait on it again" "yes|yes" \
  "$(has "stopped on an expired login, which only the user's" "${cbrief}")|$(has "again with \`swarm.sh wait <slug>\` in the background." "${cbrief}")"
check "the conductor gives up on a builder with close, accepts a Fable dialog itself, and leaves an escalated story to the lead" \
  "${GIVES_UP}" "$(gives_up "${cbrief}")"
check "with goal off, the story-mode conductor waits out wait's nudges, and has no goal rule" "yes|no|no" "$(goal_off "${cbrief}")"
check "the story-mode conductor moves its inbox aside after each wait, then reads and deletes the copy" "${INBOX_RULE}" "$(inbox_rule e "${cbrief}")"
check "the new workspace's placeholder tab is closed" "yes" "$(has "tab close t0" "$(log)")"
check "the story-mode conductor starts every story with --strict, waits for the merge on an is-open refusal, and retries on cannot-tell" "yes|yes|yes" \
  "$(has "${STRICT_RULE}" "${cbrief}")|$(has "start yours in a later wave, after the named story merges" "${cbrief}")|$(has "nothing is known to be open: retry the story in a later wave" "${cbrief}")"
check "the story-mode conductor's brief never starts a story without --strict" "0" "$(grep -c 'swarm.sh story <slug>' <<< "${cbrief}" || true)"
for s in s1 s2 s3; do run story "${s}" >/dev/null; done
mv "${p}/.claude-plugin/plugin.json" "${ROOT}/plugin.json"; run story s4 >/dev/null; mv "${ROOT}/plugin.json" "${p}/.claude-plugin/plugin.json"
check "with plugin.json, the story-mode builder and conductor say a missing bump is not a finding; without it, no line" "yes|yes|no" \
  "$(has "${BUMP}" "$(cat "${p}/.swarm/briefs/s1.md")")|$(has "${BUMP}" "$(para "A story is reviewed only when" "${cbrief}")")|$(bumped "$(cat "${p}/.swarm/briefs/s4.md" 2>/dev/null)")"
check "the story-mode conductor's line keeps the release story's own PR to the bump" "yes" \
  "$(has "On any other story a PR without the bump is not a finding" "$(para "A story is reviewed only when" "${cbrief}")")"
check "the story-mode builder and conductor run codex-review in the background, and know what a timeout means" "yes|yes|yes|yes|yes|yes" \
  "$(codex_form main "$(cat "${p}/.swarm/briefs/s1.md")")|$(codex_form '<base>' "$(para "A story is reviewed only when" "${cbrief}")")"
check "with no tagged rule, a builder gets no rules check and the conductor no rules-unchecked" "no|no" \
  "$(grep -q "Rules checked:" "${p}/.swarm/briefs/s1.md" && echo yes || echo no)|$(grep -q "rules-unchecked" <<< "${cbrief}" && echo yes || echo no)"
sid="$(grep '^agent start s1 ' "${ROOT}/herdr.log" | sed -n 's/.*--session-id \([^ ]*\).*/\1/p')"
check "a story starts with a --session-id, and its agents.tsv line ends in it" "yes|${sid}" \
  "$([[ -n "${sid}" ]] && echo yes || echo no)|$(awk -F'\t' 'NF == 7 && $3 == "s1" { print $7 }' "${p}/.swarm/agents.tsv")"
check "a story of the epic splits the conductor's pane, and is named" "yes|yes" \
  "$(has "pane split w:1 --direction right" "$(log)")|$(has "pane rename w:2 s1" "$(log)")"
check "the fourth pane splits the second, and the fifth opens <epic>-2" "yes|yes" \
  "$(has "pane split w:2 --direction down" "$(log)")|$(has "--label e-2 " "$(log)")"
run story o1 >/dev/null
check "a story outside any epic gets a tab of its own" "yes" "$(has "--label o1 " "$(log)")"
check "a one-off story has no release story, so its brief has no bump line" "no" "$(bumped "$(cat "${p}/.swarm/briefs/o1.md" 2>/dev/null)")"
: > "${ROOT}/herdr.log"
run close s1 >/dev/null
check "closing a story closes its pane and leaves the epic's tab" "yes|no|no" \
  "$(has "pane close w:2" "$(log)")|$(grep -q 'tab close' "${ROOT}/herdr.log" && echo yes || echo no)|$(grep -q ' s1$' "${p}/.swarm/state/e" && echo yes || echo no)"
check "closing a ready story's builder counts a failed build and removes its worktree" "1|no" \
  "$(sed -n 's/^attempts: //p' "${b}/stories/s1.md")|$([[ -d "${ROOT}/svc-wt/s1" ]] && echo yes || echo no)"
run close conduct-e >/dev/null
check "closing the conductor closes the epic's tabs" "tab close t1|tab close t5" "$(grep '^tab close' "${ROOT}/herdr.log" | paste -sd'|' -)"

# --- story warns when an open story of another epic touches the same function or file; --strict refuses.
# subject <slug> <touches> — a ready story of e1 in svc; other <front-matter line>... — xb, in svc unless
# a line says otherwise; warns <slug> — story's warning lines, or none.
subject() { item "${b}" "stories/$1.md" "status: ready" "kind: code" "epic: e1" "repo: svc" "touches: $2"; }
other() { item "${b}" stories/xb.md "kind: code" "repo: svc" "$@"; }
warns() { run story "$1" | grep '^warning:' || echo none; }
started_x() { if grep -q "^agent start $1 " "${ROOT}/herdr.log"; then echo started; else echo "not started"; fi; }
subject xa "[bin/swarm.sh:tell_agent (note), docs/x.md]"
other "status: review" "epic: e2" "touches: [bin/swarm.sh:tell_agent (kinds)]"
: > "${ROOT}/herdr.log"; : > "${p}/.swarm/events.tsv"
rc=0; out="$(run story --strict xa)" || rc=$?
check "story --strict refuses naming the open story; no agent, branch or worktree; events.tsv's story line targets xa" \
  "fail|yes|not started|no|no|xa" \
  "$([[ ${rc} -ne 0 ]] && echo fail || echo ok)|$(has "xa: xb (epic e2) is open and touches bin/swarm.sh:tell_agent; start xa after it merges" "${out}")|$(started_x xa)|$(
  git -C "${ROOT}/svc" rev-parse -q --verify story/xa >/dev/null && echo yes || echo no)|$([[ -e "${ROOT}/svc-wt/xa" ]] && echo yes || echo no)|$(
  awk -F'\t' '$2 == "story" { print $3 }' "${p}/.swarm/events.tsv")"
check "story warns naming the open story and the function, and still starts it" \
  "warning: xb (epic e2) is open and touches bin/swarm.sh:tell_agent; start xa after it merges|started" "$(warns xa)|$(started_x xa)"
for s in xc1 xc2 xc3; do subject "${s}" "[bin/swarm.sh:tell_agent]"; done
check "no warning for a ready story with no builder, a story of the same epic, or another function" "none|none|none" \
  "$(other "status: ready" "epic: e2" "touches: [bin/swarm.sh:tell_agent]"; warns xc1)|$(
  other "status: review" "epic: e1" "touches: [bin/swarm.sh:tell_agent]"; warns xc2)|$(
  other "status: review" "epic: e2" "touches: [bin/swarm.sh:tell_agent_x]"; warns xc3)"
other "status: review" "epic: e2" "touches: [docs/method.md (§ A; § B, C)]"; subject xd "[docs/method.md]"
check "a parenthetical with commas and semicolons stays in its entry" \
  "warning: xb (epic e2) is open and touches docs/method.md; start xd after it merges" "$(warns xd)"
other "status: review" "epic: e2" "touches: [bin/swarm.sh:x, FOO, CONFIG_KEYS]"; subject xe "[bin/swarm.sh:CONFIG_KEYS]"
check "an entry with no file inherits the previous entry's, after another such entry too" \
  "warning: xb (epic e2) is open and touches bin/swarm.sh:CONFIG_KEYS; start xe after it merges" "$(warns xe)"
touch "${ROOT}/svc/Makefile"   # a bare head is a file only when the repo's checkout has it
other "status: review" "epic: e2" "touches: [Makefile]"; subject xk "[src/app.go, Makefile]"
check "an extensionless root file after another entry is still a file" \
  "warning: xb (epic e2) is open and touches Makefile; start xk after it merges" "$(warns xk)"
other "status: review" "epic: e2" "touches: [Makefile:lint]"; subject xl "[src/app.go, Makefile:lint]"
check "and so is one with a function" \
  "warning: xb (epic e2) is open and touches Makefile:lint; start xl after it merges" "$(warns xl)"
other "status: review" "epic: e2" "touches: [Makefile]"; subject xr "[other: src/a.go, Makefile]"
check "an unprefixed file after another repo's entry is in the story's repo" \
  "warning: xb (epic e2) is open and touches Makefile; start xr after it merges" "$(warns xr)"
rm -f "${ROOT}/svc/Makefile"
other "status: review" "epic: e2" "touches: [tests/x_test.sh:setup, main]"; subject xm "[bin/swarm.sh:dispatch, main]"
check "a shorthand that names no file is a function only, so the same name in other files does not overlap" "none" "$(warns xm)"
other "status: review" "epic: e2" "touches: [other: src/a.go:y]"; subject xn "[other: src/a.go:x, y]"
check "a shorthand inherits the previous entry's repo with its file" \
  "warning: xb (epic e2) is open and touches src/a.go:y; start xn after it merges" "$(warns xn)"
other "status: review" "epic: e2" "touches: [other: docs/y.md]"; subject xf "[docs/y.md]"
check "the same file in another repo does not overlap" "none" "$(warns xf)"
other "status: review" "epic: e2" "touches: [bin/swarm.sh:tell_agent]"; subject xg "[bin/swarm.sh]"
check "a file-only entry overlaps any function in that file" \
  "warning: xb (epic e2) is open and touches bin/swarm.sh:tell_agent; start xg after it merges" "$(warns xg)"
# xb's builder open: built in e2 (its own warnings about e1's open builders are not this check's).
other "status: ready" "epic: e2" "touches: [bin/swarm.sh:tell_agent]"; run story xb >/dev/null; subject xh "[bin/swarm.sh:tell_agent]"
check "a ready story whose builder herdr lists open warns" \
  "warning: xb (epic e2) is open and touches bin/swarm.sh:tell_agent; start xh after it merges" "$(warns xh)"
subject xi "[bin/swarm.sh:tell_agent]"; touch "${ROOT}/listfail"; : > "${ROOT}/herdr.log"
rc=0; out="$(run story --strict xi)" || rc=$?
check "when herdr cannot list agents, --strict refuses and starts nothing" "fail|yes|not started|no" \
  "$([[ ${rc} -ne 0 ]] && echo fail || echo ok)|$(has "xi: cannot tell whether the builder of xb (epic e2), which touches bin/swarm.sh:tell_agent, is open (herdr cannot list its agents); retry xi" "${out}")|$(started_x xi)|$([[ -e "${ROOT}/svc-wt/xi" ]] && echo yes || echo no)"
check "and plain story warns that it cannot tell" \
  "warning: cannot tell whether the builder of xb (epic e2), which touches bin/swarm.sh:tell_agent, is open (herdr cannot list its agents); retry xi" "$(warns xi)"
rm -f "${ROOT}/listfail"
item "${b}" stories/xb.md "status: review" "kind: code" "repo: svc" "touches: [bin/swarm.sh:tell_agent]"
item "${b}" stories/xj.md "status: ready" "kind: code" "repo: svc" "touches: [bin/swarm.sh:tell_agent]"
# xj, with no epic, also warns about e1's open builders above; only xb's line is this check's.
check "two stories with no epic are of different epics" \
  "warning: xb (epic none) is open and touches bin/swarm.sh:tell_agent; start xj after it merges" "$(warns xj | grep '^warning: xb ')"
# A board the parse cannot read fails closed under --strict: a directory named like a story.
mkdir "${b}/stories/xbroken.md"; subject xo "[bin/swarm.sh:merge_cmd]"; : > "${ROOT}/herdr.log"
rc=0; out="$(run story --strict xo)" || rc=$?
check "when the touches cannot be read, --strict refuses and starts nothing, and plain story warns" "fail|yes|not started|yes" \
  "$([[ ${rc} -ne 0 ]] && echo fail || echo ok)|$(has "xo: cannot read the board's touches" "${out}")|$(started_x xo)|$(
  has "warning: cannot read the board's touches, so cannot tell whether another epic's open story overlaps xo; retry xo once they can be read" "$(run story xo)")"
rmdir "${b}/stories/xbroken.md"
# Only a ready story can have a builder: a blocked or done one is never asked about, even when herdr fails.
touch "${ROOT}/listfail"
subject xp-blocked "[bin/swarm.sh:merge_cmd]"; subject xp-done "[bin/swarm.sh:merge_cmd]"
check "an overlapping blocked or done story is not open, even when herdr cannot list agents" "ok|ok" \
  "$(other "status: blocked" "epic: e2" "touches: [bin/swarm.sh:merge_cmd]"; run story --strict xp-blocked >/dev/null && echo ok || echo refused)|$(
  other "status: done" "epic: e2" "touches: [bin/swarm.sh:merge_cmd]"; run story --strict xp-done >/dev/null && echo ok || echo refused)"
rm -f "${ROOT}/listfail"
other "status: review" "epic: e2" "touches: [bin/swarm.sh:merge_cmd]"; subject xq "[bin/swarm.sh:merge_cmd]"; : > "${ROOT}/herdr.log"
rc=0; out="$(run story xq --strict)" || rc=$?
check "--strict after the slug is strict too; any other extra argument stops story" "fail|yes|not started|yes" \
  "$([[ ${rc} -ne 0 ]] && echo fail || echo ok)|$(has "xq: xb (epic e2) is open and touches bin/swarm.sh:merge_cmd" "${out}")|$(started_x xq)|$(
  has "story: unknown argument '--strct'" "$(run story xq --strct || true)")"
for s in xa xc1 xc2 xc3 xd xe xk xl xr xm xn xf xg xb xh xi xj xo xp-blocked xp-done xq; do run close "${s}" >/dev/null 2>&1 || true; rm -f "${b}/stories/${s}.md"; done
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
# goal: off writes no goal file; goal = N writes the condition beside the brief, with the brief's reply.
# prompts and goals count the herdr agent prompt calls since herdr.log was emptied, and the /goal ones.
prompts() { grep -c '^agent prompt ' "${ROOT}/herdr.log" || true; }
goals() { grep -c '^agent prompt [^ ]* /goal ' "${ROOT}/herdr.log" || true; }
closes() { if grep -qE '^(pane|tab) close' "${ROOT}/herdr.log"; then echo closed; else echo "none closed"; fi; }
goal_story "${b}" gl0 "status: ready" "kind: code" "repo: svc"
mkdir -p "${p}/.swarm/briefs"; echo "an earlier build's condition" > "${p}/.swarm/briefs/gl0.goal.md"
: > "${ROOT}/herdr.log"
run story gl0 >/dev/null
check "with goal off, story writes no .goal.md (and drops an earlier one), and the brief holds the story-mode reply" "no|yes" \
  "$([[ -e "${p}/.swarm/briefs/gl0.goal.md" ]] && echo yes || echo no)|$(has "${STORY_REPLY}" "$(cat "${p}/.swarm/briefs/gl0.md")")"
check "with goal off, story sends one agent prompt: the brief" "1|0" "$(prompts)|$(goals)"
echo "goal = 7" > "${p}/.claude/swarm/config"
# send_goal types the /goal only into a started turn: the claude stub lists the brief's session busy.
echo '[]' > "${ROOT}/started.json"; export CLAUDE_STUB_AGENTS="${ROOT}/started.json"
goal_story "${b}" gl1 "status: ready" "kind: code" "repo: svc"
: > "${ROOT}/herdr.log"
rc=0; out="$(run story gl1)" || rc=$?
[[ ${rc} -eq 0 ]] || echo "story gl1: ${out}"
check "with goal = 7, story writes the condition: the story's path for its Done when and From review, the brief's reply, the escape and the bound" \
  "${GOAL_PARTS}|yes" "$(goal_parts "${p}/.swarm/briefs/gl1.goal.md" gl1 "${STORY_REPLY}" 7)|$(has "${STORY_REPLY}" "$(cat "${p}/.swarm/briefs/gl1.md")")"
check "built in another repo, the goal names the story by the board's path, as the brief does" "${b}/stories/gl1.md" \
  "$(goal_path "${p}/.swarm/briefs/gl1.md" "${p}/.swarm/briefs/gl1.goal.md")"
sent="$(cat "${ROOT}/goal.txt" 2>/dev/null || true)"
check "with goal = 7 and the goal set, a second prompt follows the brief: /goal and the .goal.md on one line; story exits 0" \
  "0|2|/goal|one line|same" "${rc}|$(prompts)|$(grep '^agent prompt ' "${ROOT}/herdr.log" | sed -n '2s/^agent prompt [^ ]* \(\/goal\) .*/\1/p')|$(
    [[ "${sent}" == *$'\n'* ]] && echo "has a newline" || echo "one line")|$(
    [[ "${sent}" == "/goal $(python3 -c 'import sys; print(" ".join(open(sys.argv[1]).read().split()))' "${p}/.swarm/briefs/gl1.goal.md")" ]] && echo same || echo differs)"
# A goal that does not set fails story, naming it and why, with the one /goal sent and the builder left open.
goal_story "${b}" gl4 "status: ready" "kind: code" "repo: svc"
: > "${ROOT}/herdr.log"
rc=0; out="$(HERDR_STUB_GOAL=refused run story gl4)" || rc=$?
check "a refused /goal fails story naming the story and Claude Code's reason; one /goal, and no pane closed" "fail|yes|1|none closed" \
  "$([[ ${rc} -ne 0 ]] && echo fail || echo "exit ${rc}")|$(has "gl4: the brief was delivered, but Claude Code refused its /goal (/goal can't run while hooks are restricted" "${out}")|$(goals)|$(closes)"
goal_story "${b}" gl5 "status: ready" "kind: code" "repo: svc"
: > "${ROOT}/herdr.log"; echo "Goal set: DW-ONE holds" > "${ROOT}/screen"   # the pane alone would show a goal set
rc=0; out="$(HERDR_STUB_GOAL='' run story gl5)" || rc=$?
rm -f "${ROOT}/screen"
check "with no goal entry in the session log, whatever the pane shows, story fails naming the story; one /goal, no pane closed" \
  "fail|yes|1|none closed" "$([[ ${rc} -ne 0 ]] && echo fail || echo "exit ${rc}")|$(has "gl5: the brief was delivered, but its session log shows no goal set for its condition" "${out}")|$(goals)|$(closes)"
goal_story "${b}" gl6 "status: ready" "kind: code" "repo: svc"
: > "${ROOT}/herdr.log"
rc=0; out="$(HERDR_STUB_GOAL=other run story gl6)" || rc=$?
check "a goal set for another condition is not this goal: story fails; one /goal" "fail|yes|1" \
  "$([[ ${rc} -ne 0 ]] && echo fail || echo "exit ${rc}")|$(has "gl6: the brief was delivered, but its session log shows no goal set for its condition" "${out}")|$(goals)"
goal_story "${b}" gl7 "status: ready" "kind: code" "repo: svc"
: > "${ROOT}/herdr.log"
rc=0; out="$(HERDR_STUB_GOAL=pasted run story gl7)" || rc=$?
check "a /goal the session log shows queued as a pasted prompt fails story saying it was pasted as text; one /goal" "fail|yes|1" \
  "$([[ ${rc} -ne 0 ]] && echo fail || echo "exit ${rc}")|$(has "gl7: the brief was delivered, but its /goal was pasted as text, not run" "${out}")|$(goals)"
# A Done when over 2,500 characters stays in the story: the /goal names its path and fits GOAL_SEND_MAX.
goal_story "${b}" gl8 "status: ready" "kind: code" "repo: svc"
python3 - "${b}/stories/gl8.md" <<'PY2'
import sys; s = open(sys.argv[1]).read()
long = "\n".join("- line %d of a long acceptance that the builder must show holds" % i for i in range(60))
open(sys.argv[1], "w").write(s.replace("- DW-TWO holds", "- DW-TWO holds\n" + long, 1))
PY2
: > "${ROOT}/herdr.log"; rm -f "${ROOT}/goal.txt"   # an earlier case's /goal must not stand in for this one
rc=0; out="$(run story gl8)" || rc=$?
[[ ${rc} -eq 0 ]] || echo "story gl8: ${out}"
sent="$(cat "${ROOT}/goal.txt" 2>/dev/null || true)"
dw="$(awk '/^\*\*Done when/ { on = 1 } on && /^$/ { exit } on' "${b}/stories/gl8.md")"
check "a Done when of over 2,500 characters: story exits 0, and the /goal it sends fits GOAL_SEND_MAX, names the story's path and ends on the bound" \
  "over 2500|0|fits|yes|yes" "$( (( ${#dw} > 2500 )) && echo "over 2500" || echo "${#dw} characters")|${rc}|$(
    (( ${#sent} > 0 && ${#sent} <= GOAL_SEND_MAX )) && echo fits || echo "${#sent} characters, max ${GOAL_SEND_MAX}")|$(
    has "${b}/stories/gl8.md" "${sent}")|$([[ "${sent}" == *"or stop after 7 more turns." ]] && echo yes || echo "no, ends: ${sent: -60}")"
# A blank line under a heading does not end its block; the next bold line that is not one does.
item "${b}" stories/gl2.md "status: ready" "kind: code" "repo: svc"
printf '%s\n' "" "**Done when:**" "" "- DW-ONE holds" "- DW-TWO holds" "**Out of scope:** OUT-ONE" "" \
  "**From review (binding):**" "- FR-ONE holds" "**From the spike (binding):**" "- SPIKE-ONE" "**You:** YOU-ONE" >> "${b}/stories/gl2.md"
rc=0; out="$(run story gl2)" || rc=$?   # the exit is checked: a refusal shows as a FAIL, not an abort
[[ ${rc} -eq 0 ]] || echo "story gl2: ${out}"
g="$(cat "${p}/.swarm/briefs/gl2.goal.md" 2>&1 || true)"
check "a blank line before the first item still finds the Done when; the condition inlines no block" "0|yes|no" \
  "${rc}|$(has "${b}/stories/gl2.md" "${g}")|$(grep -qE 'DW-ONE|FR-ONE|OUT-ONE|SPIKE-ONE|YOU-ONE' <<< "${g}" && echo yes || echo no)"
item "${b}" stories/gl3.md "status: ready" "kind: code" "repo: svc"
printf '%s\n' "" "**Done when:**" "" "**Out of scope:** OUT-ONE" >> "${b}/stories/gl3.md"
check "a Done when with no item under it fails like a missing one, before any worktree" "yes|no" \
  "$(if out="$(run story gl3)"; then echo "it succeeded"; else has "gl3 has no **Done when**" "${out}"; fi)|$([[ -e "${ROOT}/svc-wt/gl3" ]] && echo yes || echo no)"
: > "${p}/.claude/swarm/config"; rm -f "${b}"/stories/gl[0-8].md; unset CLAUDE_STUB_AGENTS

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

# --- pr_per = epic: a story branches from epic/<epic>, which is made from the base the first time.
printf '%s\n' "pr_per = epic" "base_branches = dev main" > "${p}/.claude/swarm/config"
item "${b}" epics/f.md "status: active" "check: make test"
item "${b}" stories/f1.md "status: ready" "kind: code" "epic: f" "repo: svc"
item "${b}" stories/f2.md "status: ready" "kind: code" "epic: f" "repo: svc"
run story f1 >/dev/null
tip() { git -C "$1" rev-parse "$2"; }
check "epic/<epic> is made from the base (dev), and the story branches from it" \
  "$(tip "${ROOT}/svc.git" dev)|$(tip "${ROOT}/svc.git" dev)" \
  "$(tip "${ROOT}/svc.git" epic/f)|$(tip "${ROOT}/svc-wt/f1" HEAD)"
check "the epic lists the repo" "svc" "$(sed -n 's/^repos: //p' "${b}/epics/f.md")"
brief="$(cat "${p}/.swarm/briefs/f1.md")"
check "the story brief opens no PR and names the epic branch" "yes|yes|yes" \
  "$(has "open no PR" "${brief}")|$(has "codex-review epic/f" "${brief}")|$(has "Before you reply, also run the epic's check" "${brief}")"
check "the epic-mode builder runs codex-review in the background, and knows what a timeout means" "yes|yes|yes" "$(codex_form epic/f "${brief}")"
check "the epic story brief asks for a mutation" "yes" \
  "$(has "prove each new or changed test can fail" "${brief}")"
check "the epic-mode builder says a missing bump is not a finding" "yes" "$(has "${BUMP}" "${brief}")"
# The release story does the bump, so its brief must not tell it not to.
item "${b}" stories/f3.md "status: ready" "kind: code" "epic: f" "repo: svc" "touches: [.claude-plugin/plugin.json]"
run story f3 >/dev/null
check "a story whose touches name plugin.json (the release story) gets no bump line" "no" \
  "$(bumped "$(cat "${p}/.swarm/briefs/f3.md" 2>/dev/null)")"
rm -f "${b}/stories/f3.md"
# Someone merged into the epic branch: the next story starts from there, and the repo is listed once.
"${GIT[@]}" -C "${ROOT}/svc" fetch -q origin && "${GIT[@]}" -C "${ROOT}/svc" checkout -q -b m origin/epic/f
"${GIT[@]}" -C "${ROOT}/svc" commit -q --allow-empty -m f1 && "${GIT[@]}" -C "${ROOT}/svc" push -q origin m:epic/f
merged="$(tip "${ROOT}/svc" HEAD)"
run story f2 >/dev/null
check "a later story branches from the epic branch as it is now" "${merged}|${merged}" "$(tip "${ROOT}/svc-wt/f2" HEAD)|$(tip "${ROOT}/svc.git" epic/f)"
check "the repo is listed once" "svc" "$(sed -n 's/^repos: //p' "${b}/epics/f.md")"
check "with goal off, the epic story brief holds the epic-mode reply, and no .goal.md is written" "yes|no" \
  "$(has "${EPIC_REPLY}" "$(cat "${p}/.swarm/briefs/f2.md")")|$([[ -e "${p}/.swarm/briefs/f2.goal.md" ]] && echo yes || echo no)"
printf '%s\n' "pr_per = epic" "base_branches = dev main" "goal = 7" > "${p}/.claude/swarm/config"; export CLAUDE_STUB_AGENTS="${ROOT}/started.json"
goal_story "${b}" gf1 "status: ready" "kind: code" "epic: f" "repo: svc"
run story gf1 >/dev/null
check "with goal = 7 and pr_per = epic, the condition carries the epic-mode reply the brief holds" \
  "${GOAL_PARTS}|yes" "$(goal_parts "${p}/.swarm/briefs/gf1.goal.md" gf1 "${EPIC_REPLY}" 7)|$(has "${EPIC_REPLY}" "$(cat "${p}/.swarm/briefs/gf1.md")")"
# A /goal message over GOAL_SEND_MAX, here through a long story path, is refused before the epic
# branch or worktree exists, and nothing is sent.
item "${b}" epics/gx.md "status: active"; cp "${b}/epics/gx.md" "${ROOT}/gx-epic.md"
gx="gx1-$(printf 'long%.0s' {1..60})"
goal_story "${b}" "${gx}" "status: ready" "kind: code" "epic: gx" "repo: svc"
: > "${ROOT}/herdr.log"
out="$(run story "${gx}" || true)"
check "with goal on, a /goal message over GOAL_SEND_MAX fails naming the story, sends nothing, and leaves no worktree, branch, epic branch or epic edit" \
  "yes|nothing sent|no|no|no|no|same" \
  "$(has "${gx}: its /goal message is" "${out}")|$(grep -qE '^agent (start|prompt) ' "${ROOT}/herdr.log" && echo sent || echo "nothing sent")|$([[ -e "${ROOT}/svc-wt/${gx}" ]] && echo yes || echo no)|$(git -C "${ROOT}/svc" show-ref -q --verify "refs/heads/story/${gx}" && echo yes || echo no)|$(git -C "${ROOT}/svc.git" show-ref -q --verify "refs/heads/story/${gx}" && echo yes || echo no)|$(git -C "${ROOT}/svc.git" show-ref -q --verify refs/heads/epic/gx && echo yes || echo no)|$(cmp -s "${ROOT}/gx-epic.md" "${b}/epics/gx.md" && echo same || echo changed)"
printf '%s\n' "pr_per = epic" "base_branches = dev main" > "${p}/.claude/swarm/config"; unset CLAUDE_STUB_AGENTS
rm -f "${b}/stories/gf1.md" "${b}/stories/${gx}.md" "${b}/epics/gx.md"
run conduct f >/dev/null
brief="$(cat "${p}/.swarm/briefs/conduct-f.md")"
check "the conductor merges stories into the epic branch, then opens one PR per repo" "yes|yes|yes" \
  "$(has "git merge --no-ff origin/story/<slug>" "${brief}")|$(has "epic check \`make test\`" "${brief}")|$(has "open one PR per repo from epic/f" "${brief}")"
check "the one-PR-per-epic brief also watches only its own epic's PRs" "yes" "$(has "swarm.sh watch --epic f\`" "${brief}")"
check "the one-PR-per-epic conductor starts every story with --strict, waits for the merge on an is-open refusal, and retries on cannot-tell" "yes|yes|yes" \
  "$(has "${STRICT_RULE}" "${brief}")|$(has "start yours in a later wave, after the named story merges" "${brief}")|$(has "nothing is known to be open: retry the story in a later wave" "${brief}")"
check "the one-PR-per-epic conductor's brief never starts a story without --strict" "0" "$(grep -c 'swarm.sh story <slug>' <<< "${brief}" || true)"
check "with merge = human, the story-mode and one-PR-per-epic conductors stop when the Done when holds or nothing ready is left" "yes|yes" \
  "$(has "Stop when the epic's **Done when** holds or when nothing ready is left." "${cbrief}")|$(has "Stop when the epic's **Done when** holds or when nothing ready is left." "${brief}")"
check "with merge = human, neither the story-mode nor the one-PR-per-epic brief pins a merge" "no|no" \
  "$(grep -qF -- --match-head-commit <<< "${cbrief}" && echo yes || echo no)|$(grep -qF -- --match-head-commit <<< "${brief}" && echo yes || echo no)"
check "the epic-mode conductor's log-finding lines name the reviewer, and log codex's findings as codex" "${LOGS_FINDINGS}" "$(logs_findings "${brief}")"
check "the whole-epic review runs codex-review in the background, and knows what a timeout means" "yes|yes|yes" \
  "$(codex_form '<base>' "$(para "review the whole epic" "${brief}")")"
check "the epic-mode conductor's per-story review says a missing bump is not a finding; its whole-epic review, which must see the bump, does not" "yes|no" \
  "$(has "${BUMP}" "$(para "When a builder reports, review its branch." "${brief}")")|$(bumped "$(para "review the whole epic" "${brief}")")"
check "the epic-mode conductor's line keeps the release story's own branch to the bump" "yes" \
  "$(has "On any other story a PR without the bump is not a finding" "$(para "When a builder reports, review its branch." "${brief}")")"
check "the one-PR-per-epic conductor runs /code-review on each epic PR" "yes" \
  "$(has "An epic PR that changes code is reviewed only once the /code-review skill" "${brief}")"
check "the one-PR-per-epic conductor's brief says what a builder's auth means, then wait on it again" "yes|yes" \
  "$(has "stopped on an expired login, which only the user's" "${brief}")|$(has "again with \`swarm.sh wait <slug>\` in the background." "${brief}")"
check "the one-PR-per-epic conductor gives up with close, accepts a Fable dialog itself, and leaves an escalated story to the lead" \
  "${GIVES_UP}" "$(gives_up "${brief}")"
check "with goal off, the one-PR-per-epic conductor waits out wait's nudges, and has no goal rule" "yes|no|no" "$(goal_off "${brief}")"
check "the one-PR-per-epic conductor moves its inbox aside after each wait, then reads and deletes the copy" "${INBOX_RULE}" "$(inbox_rule f "${brief}")"
printf '%s\n' "pr_per = epic" "base_branches = dev main" "goal = 5" > "${p}/.claude/swarm/config"
run conduct f >/dev/null || true
check "with goal = 5, the one-PR-per-epic conductor reads why a builder stopped and closes it with that cause" \
  "${GOAL_ON}" "$(goal_on "$(cat "${p}/.swarm/briefs/conduct-f.md")")"
printf '%s\n' "pr_per = epic" "base_branches = dev main" > "${p}/.claude/swarm/config"
# lessons_file elsewhere: its tagged rules (only those) reach a builder in another repo's worktree.
printf 'lessons_file = AGENTS.md\n' >> "${p}/.claude/swarm/config"
printf 'Untagged guidance.\nTag rules with <!-- lesson: <kind> -->.\nProve it. <!-- lesson: agents-kind -->\n' > "${p}/AGENTS.md"
printf 'A PROJECT RULE every agent reads. <!-- lesson: brief-kind -->' > "${p}/.claude/swarm/brief.md"   # no final newline
item "${b}" stories/g1.md "status: ready" "kind: code" "repo: svc"
run story g1 >/dev/null
gbrief="$(cat "${p}/.swarm/briefs/g1.md")"
check "a builder walks its diff against each tagged rule, and lists both kinds in the PR body" "yes|yes|yes|yes" \
  "$(has "Before you open the PR, walk your diff against each rule tagged" "${gbrief}")|$(has "the PR body a \`Rules checked:\` section" "${gbrief}")|$(has "- agents-kind: <file:line>, or n/a: <why>" "${gbrief}")|$(has "- brief-kind: <file:line>, or n/a: <why>" "${gbrief}")"
for mode in story epic; do   # epic last: the tests below run with pr_per = epic
  printf '%s\n' "pr_per = ${mode}" "base_branches = dev main" "lessons_file = AGENTS.md" > "${p}/.claude/swarm/config"
  run conduct f >/dev/null || true
  check "with tagged rules, the ${mode}-mode conductor treats an unchecked rule as a rules-unchecked finding" "yes" \
    "$(has "is a finding of kind \`rules-unchecked\`" "$(cat "${p}/.swarm/briefs/conduct-f.md")")"
done
cfg="$(cat "${p}/.claude/swarm/config")"; printf '%s\n' "merge = agent" "base_branches = dev main" > "${p}/.claude/swarm/config"
run conduct f >/dev/null || true
brief="$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/conduct-f.md")"
check "with merge = agent, the conductor reviews a pinned head, puts the story in review, then merges that head with swarm.sh merge, which reconciles" "yes|yes|yes|yes" \
  "$(has "note its head SHA (\`gh pr view <PR URL> --json headRefOid --jq .headRefOid\`)" "${brief}")|$(has "if the head moved, review the new head" "${brief}")|$(has "run \`swarm.sh review <slug> <PR URL>\`, then \`swarm.sh merge --head <the SHA you reviewed> <PR URL>\`, never \`gh pr merge\` or \`gh api\`" "${brief}")|$(has "\`swarm.sh reconcile\`, never a plain \`git pull\`" "${brief}")"
check "it merges by the literal PR number, pinned with --match-head-commit, in the repo's method, never --auto" "yes|yes|yes|yes" \
  "$(has "by the literal PR number" "${brief}")|$(has "\`--match-head-commit <sha>\`" "${brief}")|$(has "(\`gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed\`)" "${brief}")|$(has "never --auto" "${brief}")"
check "it runs one swarm.sh merge at a time, the next only once the last has exited" "yes" "$(has "Run one \`swarm.sh merge\` at a time: start the next only after the previous one has exited, its base CI and reconcile done." "${brief}")"
check "a red base stops its merging: it finds the PR pair, opens the fix or lists it, and reports it" "yes" \
  "$(has "A red or timed-out CI on the base means the PR merged and the base is broken: merge nothing more, find the PR pair that broke it" "${brief}")"
after="${brief#*swarm.sh merge --head}"; after="${after%%Stay inside this epic*}"
check "after the merge it closes a builder only when reconcile printed build cleared, and starts the stories unblock readied in this run, unless the wave had a cleared-on-error or a give-up" "1|yes|yes|yes" \
  "$(grep -oF 'swarm.sh close <slug>' <<< "${after}" | wc -l | tr -d ' ')|$(has "Reconcile has closed the builder, so leave it, unless it printed \`build cleared: <slug>\`: then run \`swarm.sh close <slug>\` as it says." "${after}")|$(has "start each story of this epic it prints as \`ready:\` whose \`touches\` do not overlap a running one, with \`swarm.sh story --strict <slug>\`" "${brief}")|$(has "After a cleared-on-error close or a give-up, start nothing more in this wave." "${brief}")"
check "it reports, and stops, only once no story of the epic is ready or running, never just because nothing is ready" "yes|yes|no" \
  "$(has "Write your report only when no story of this epic that is yours to start is ready and none is running" "${brief}")|$(has "Stop when the epic's **Done when** holds, when no story of this epic that is yours to start is ready and none is running, or when CI on the base is red or timed out." "${brief}")|$(grep -qF "nothing ready is left" <<< "${brief}" && echo yes || echo no)"
check "the brief makes no claim about the block-red-pr-merge hook, which never sees swarm.sh's own gh calls" "no" \
  "$(grep -qF "block-red-pr-merge" <<< "${brief}" && echo yes || echo no)"
printf '%s\n' "merge = agent" "pr_per = epic" "base_branches = dev main" > "${p}/.claude/swarm/config"
run conduct f >/dev/null || true
brief="$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/conduct-f.md")"
check "with merge = agent, the one-PR-per-epic conductor stops once every epic PR has merged, or what is left needs the lead, not when no story is left" "yes|yes|yes|yes|no" \
  "$(has "Stop when every PR from epic/f has merged and the epic's **Done when** holds, or when what is left needs the lead:" "${brief}")|$(has "a story of this epic only the lead can finish (a \`lead\` story, or one escalated to the lead) with none that is yours to start ready or running;" "${brief}")|$(has "a merge that \`swarm.sh merge\` refused or left unconfirmed and you cannot fix on the branch;" "${brief}")|$(has "or CI on the base red or timed out." "${brief}")|$(grep -qF "none is running" <<< "${brief}" && echo yes || echo no)"
check "with merge = agent, the one-PR-per-epic conductor notes the epic branch's head before the whole-epic review, re-reads the PR's head before each merge, and merges one at a time" "yes|yes|yes" \
  "$(has "review the whole epic: first note the head SHA of epic/f in each repo's epic worktree (\`git rev-parse HEAD\`)" "${brief%codex-review <base>*}")|$(has "Before each merge, read the PR's head (\`gh pr view <PR URL> --json headRefOid --jq .headRefOid\`): if it is not the head you reviewed, review the new head." "${brief}")|$(has "Run one \`swarm.sh merge\` at a time: start the next only after the previous one has exited, its base CI and reconcile done." "${brief}")"
check "with merge = agent, the one-PR-per-epic conductor puts the epic in review, then merges each pinned head with swarm.sh merge" "yes|yes" \
  "$(has "run \`swarm.sh review f <every PR URL>\`, then \`swarm.sh merge --head <the SHA you reviewed> <PR URL>\`" "${brief}")|$(has "\`--match-head-commit <sha>\`" "${brief}")"
printf '%s\n' "escalate_after = 0" "base_branches = dev main" > "${p}/.claude/swarm/config"
run conduct f >/dev/null || true
brief="$(cat "${p}/.swarm/briefs/conduct-f.md")"
check "with escalate_after = 0, the conductor stops retrying a story that failed twice and reports it to the lead" "yes|yes|no" \
  "$(has "model: escalation is off (escalate_after = 0), so once a story has failed twice" "${brief}")|$(has "do not start it again: report it to the lead." "${brief}")|$(grep -q "picks Fable for build" <<< "${brief}" && echo yes || echo no)"
printf '%s\n' "${cfg}" > "${p}/.claude/swarm/config"
# shellcheck disable=SC2016 # the backticks are the Markdown's
oneoff="$(sed -n '/`story <slug>`: a one-off/,/`plan-epic <epic>`/p' "$(dirname "${SWARM}")/../commands/swarm.md")"
oneoff_flat="$(tr -s '[:space:]' ' ' <<< "${oneoff}")"
check "/swarm-dev:swarm's one-off merge = agent step reviews, then merges the reviewed head with swarm.sh merge, in the background, which reconciles" "yes|yes|yes|yes" \
  "$(has "run \`swarm.sh review <slug> <PR URL>\`, then \`swarm.sh merge --head <the SHA you reviewed> <PR URL>\`, the only route: never \`gh pr merge\` or \`gh api\`" "${oneoff_flat}")|$(has "Run it in the background (Bash \`run_in_background\`) and wait for it" "${oneoff_flat}")|$(has "runs \`swarm.sh reconcile\`" "${oneoff_flat}")|$(has "a red or timed-out CI on the base means the PR merged" "${oneoff_flat}")"
check "/swarm-dev:swarm's one-off merge = agent step notes the head before the review starts, re-reads it after, and leaves the builder to reconcile" "yes|yes|yes|yes" \
  "$(has "If \`swarm.sh config merge\` is \`agent\`, first note the PR's head SHA (\`gh pr view <PR URL> --json headRefOid --jq .headRefOid\`)" "${oneoff_flat%%codex-review <base>*}")|$(has "read the head SHA again once review passes; if it moved from the one you noted, review the new head." "${oneoff_flat}")|$(has "by the literal PR number with \`--match-head-commit\`" "${oneoff_flat}")|$(has "Then \`swarm.sh unblock\`; reconcile has closed the builder, so leave it, unless it printed \`build cleared: <slug>\`: then run \`swarm.sh close <slug>\` as it says." "${oneoff_flat}")"
check "/swarm-dev:swarm's one-off step gives up with close, sends an escalated story to its step, and answers only Fable's consent" "yes|yes|yes|yes|yes|yes" \
  "$(has "run \`swarm.sh close <slug>\`, which, on a code, docs or chore story still \`ready\`," "${oneoff}")|$(has "go back to 1, where \`next\` names its \`escalated <slug>\` step" "${oneoff}")|$(has "\`waiting: dialog open\` for an escalate build" "${oneoff}")|$(has "only if it shows that consent" "${oneoff}")|$(has "\`swarm.sh dialog <slug> accepted\`" "${oneoff}")|$(has "every permission or tool prompt, is the user's: never send keys to it" "${oneoff}")"
check "a builder gets lessons_file's tagged rules, and only those" "yes|yes|no" \
  "$(has "<!-- lesson: agents-kind -->" "$(cat "${p}/.swarm/briefs/g1.md")")|$(has "A PROJECT RULE every agent reads." "$(cat "${p}/.swarm/briefs/g1.md")")|$(grep -q "Untagged guidance\|Tag rules with" "${p}/.swarm/briefs/g1.md" && echo yes || echo no)"
check "a brief without a final newline keeps its rules apart" "yes" "$(grep -q '^Prove it. <!-- lesson: agents-kind -->' "${p}/.swarm/briefs/g1.md" && echo yes || echo no)"
run close g1 >/dev/null; rm -f "${b}/stories/g1.md" "${p}/AGENTS.md"
grep -v '^lessons_file' "${p}/.claude/swarm/config" > "${p}/cfg.tmp" || true; mv "${p}/cfg.tmp" "${p}/.claude/swarm/config"
check "base prints a repo's base" "dev" "$(run base svc)"

# --- next: an active epic whose stories are all in its branch, with no PR yet, gets a conductor.
rm -f "${b}"/epics/e.md "${b}"/stories/s*.md "${b}/stories/o1.md" "${b}/stories/f1.md"
perl -pi -e 's/^status: ready/status: blocked/' "${b}/stories/f2.md"
check "while a story of the epic is open, it is not stalled" "no" "$(grep -q '^conduct' <<< "$(nx)" && echo yes || echo no)"
perl -pi -e 's/^status: blocked/status: done/' "${b}/stories/f2.md"
check "every story done (finished = mark): conduct the epic" "conduct f" "$(first "$(nx)")"
rm "${b}/stories/f2.md"
check "every story gone (finished = delete): conduct the epic" "conduct f" "$(first "$(nx)")"
perl -ni -e 'print unless /^repos:/' "${b}/epics/f.md"
check "with no repos: line nothing was built, so it is not stalled" "plan-epic f" "$(first "$(nx)")"
item "${b}" epics/f.md "status: active" "repos: svc"
printf '%s\n' "base_branches = dev main" > "${p}/.claude/swarm/config"
check "with pr_per = story the rule does not apply" "plan-epic f" "$(first "$(nx)")"

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
printf '%s\n' "repos_dir = ${ROOT}" "base_branches = dev main" > "${p}/.claude/swarm/config"
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
# pr_per = epic: a pushed story/a is an epic story's hand-off; until then it is nudged.
item "${b}" stories/a.md "status: ready" "kind: code" "epic: f" "repo: svc"
printf '%s\n' "pr_per = epic" "repos_dir = ${ROOT}" "base_branches = dev main" > "${p}/.claude/swarm/config"
"${GIT[@]}" -C "${ROOT}/svc" push -q origin main:refs/heads/story/a; : > "${ROOT}/herdr.log"
check "epic mode: a builder whose story branch is pushed is not nudged" "idle|0" "$(run wait a | tail -1)|$(nudges)"
# A one-off story (no epic:) opens its own PR even with pr_per = epic: pushed with no PR, it is nudged.
item "${b}" stories/a.md "status: ready" "kind: code" "repo: svc"; : > "${ROOT}/herdr.log"
got="$(SWARM_STALL_POLL_MS=1000 waitrc /dev/null a 20000)"
check "epic mode: a one-off story pushed with no PR is nudged for its PR" "idle|3|yes" \
  "${got%%|*}|$(nudges)|$(has "you are idle and story/a has no PR" "$(log)")"
item "${b}" stories/a.md "status: ready" "kind: code" "epic: f" "repo: svc"
"${GIT[@]}" -C "${ROOT}/svc" push -q origin :refs/heads/story/a; : > "${ROOT}/herdr.log"
# A tag named story/a on origin is not the branch: the story still reads as not pushed.
"${GIT[@]}" -C "${ROOT}/svc" tag story/a && "${GIT[@]}" -C "${ROOT}/svc" push -q origin refs/tags/story/a
got="$(SWARM_STALL_POLL_MS=1000 waitrc /dev/null a 20000)"
check "epic mode: a builder whose story branch is not pushed (only a tag story/a) is nudged, and told so" "idle|3|yes" \
  "${got%%|*}|$(nudges)|$(has "you are idle and story/a is not pushed" "$(log)")"
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
printf '%s\n' "goal = 5" "repos_dir = ${ROOT}" "base_branches = dev main" > "${p}/.claude/swarm/config"
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
printf '%s\n' "base_branches = dev main" > "${p}/.claude/swarm/config"
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
printf '%s\n' "repos_dir = ${ROOT}" "base_branches = dev main" > "${p}/.claude/swarm/config"
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
rm -rf "${wt}" "${b}/stories/a.md"; printf '%s\n' "base_branches = dev main" > "${p}/.claude/swarm/config"
# A codex agent has no session: herdr answers for it.
printf '2026-10-15\tcode\ta\tcodex\tgpt\thigh\t-\n' >> "${p}/.swarm/agents.tsv"
check "a codex agent is still waited on through herdr" "done|exit 0" "$(SWARM_STALL_POLL_MS=1000 waitrc /dev/null a 2000 | cut -d'|' -f1-2)"
# The same name held only by another project's agent is never waited on or nudged.
item "${b}" stories/a.md "status: ready" "kind: code" "repo: svc"; rm -f "${p}/.swarm/state/wait-a"
: > "${ROOT}/herdr.log"
check "wait never addresses another project's agent of the same name" "0|0" \
  "$(grep -c '^agent wait' <<< "$(run wait a >/dev/null 2>&1; cat "${ROOT}/herdr.log")" || true)|$(nudges)"
rm -f "${b}/stories/a.md"

# --- sonnet_share: a story's role is its kind, code-risky for risk: high, and with sonnet_share = N,
# code-sonnet for the other code stories whose slug's cksum mod N is 0 (r0-code, r4-f, r4-g, the s4-*
# slugs; r4-a and r4-b are not). Each build's role, model and effort are read off its agents.tsv line.
row() { awk -F'\t' -v n="$1" '$3 == n { r = $2 " " $5 " " $6 } END { print r }' "${p}/.swarm/agents.tsv"; }
build() { # <slug> <front-matter line>... — build a ready story in svc, then print its agents.tsv line
  local s="$1"; shift
  item "${b}" "stories/${s}.md" "status: ready" "repo: svc" "$@"
  run story "${s}" >/dev/null || true   # a start that fails shows as the FAIL, not an abort
  row "${s}"
}
printf '%s\n' "base_branches = dev main" > "${p}/.claude/swarm/config"
check "sonnet_share = 0 (the default): roles resolve as before" \
  "code opus high|code-risky opus xhigh|docs sonnet medium|chore haiku medium" \
  "$(build r0-code "kind: code")|$(build r0-risky "kind: code" "risk: high")|$(build r0-docs "kind: docs")|$(build r0-chore "kind: chore")"
echo "sonnet_share = 4" >> "${p}/.claude/swarm/config"
check "sonnet_share = 4: code stories split by cksum mod 4, and a sampled one starts on code-sonnet sonnet high" \
  "code opus high|code opus high|code-sonnet sonnet high|code-sonnet sonnet high" \
  "$(build r4-a "kind: code")|$(build r4-b)|$(build r4-f "kind: code")|$(build r4-g "kind: code")"
check "sonnet_share = 4: risk: high stays code-risky, and docs and chore are unchanged" \
  "code-risky opus xhigh|docs sonnet medium|chore haiku medium" \
  "$(build s4-risky4 "kind: code" "risk: high")|$(build s4-docs4 "kind: docs")|$(build s4-chore2 "kind: chore")"
printf '2026-10-13\tcode-sonnet\ts4-retry2\tclaude\tsonnet\thigh\tsess-r\n' >> "${p}/.swarm/agents.tsv"
check "only a first attempt is sampled: a slug already in agents.tsv goes back to code" "code opus high" \
  "$(build s4-retry2 "kind: code")"

# --- escalate_after: a story an agent builds whose attempts: (absent is 0) reaches escalate_after
# (default 2; 0 is off) is built as escalate, ahead of code-risky and code-sonnet. Read through _role.
role() { local s="$1"; shift; item "${b}" "stories/${s}.md" "status: ready" "$@"; run _role "${s}"; }
ladder() { # <slug> <attempts>... -- <front-matter line>... — _role at each attempts:, space-separated
  local s="$1" n ns=() out=(); shift
  while [[ "$1" != -- ]]; do ns+=("$1"); shift; done; shift
  for n in "${ns[@]}"; do out+=("$(role "${s}" "attempts: ${n}" "$@")"); done
  echo "${out[*]}"
}
printf '%s\n' "base_branches = dev main" "sonnet_share = 4" > "${p}/.claude/swarm/config"
check "escalate_after = 2 (the default): every kind an agent builds escalates at attempts: 2" \
  "code code escalate|code-risky code-risky escalate|code-sonnet code-sonnet escalate|docs docs escalate|chore chore escalate" \
  "$(ladder e4-a 0 1 2 -- "kind: code")|$(ladder e4-a 0 1 2 -- "kind: code" "risk: high")|$(ladder e4-f 0 1 2 -- "kind: code")|$(ladder e4-a 0 1 2 -- "kind: docs")|$(ladder e4-a 0 1 2 -- "kind: chore")"
check "no attempts: and no kind: is a first attempt at code" "code" "$(role e4-a)"
item "${b}" stories/e4-a.md "status: ready" "kind: code"; echo "attempts: 2" >> "${b}/stories/e4-a.md"
check "attempts: is read from the front matter, never from a body line" "code" "$(run _role e4-a)"
check "a kind: lead story never escalates" "lead" "$(ladder e4-a 3 -- "kind: lead")"
check "attempts: two is refused, naming the story file" "yes" \
  "$(has "${b}/stories/e4-a.md: attempts must be a non-negative whole number, not 'two'" "$(role e4-a "attempts: two")")"
# shellcheck disable=SC2016 # the $(...) is the story's, and must never run
check "attempts: BASH_VERSINFO[\$(touch X)] is refused and never evaluated" "yes|no" \
  "$(has "attempts must be a non-negative whole number" "$(role e4-a 'attempts: BASH_VERSINFO[$(touch '"${ROOT}"'/pwned)]')")|$([[ -e "${ROOT}/pwned" ]] && echo yes || echo no)"
check "swarm.sh story of a code story at attempts: 2 starts escalate on fable xhigh" "escalate fable xhigh" \
  "$(build e4-build "kind: code" "attempts: 2")"
check "a slug sampled for code-sonnet at attempts: 2 starts escalate" "escalate fable xhigh" \
  "$(build e4-g "kind: code" "attempts: 2")"
item "${b}" stories/e4-bad.md "status: ready" "repo: svc" "kind: code" "attempts: two"; : > "${p}/.swarm/events.tsv"
check "swarm.sh story at attempts: two fails, and its events.tsv line carries the reason" "fails|yes" \
  "$(run story e4-bad >/dev/null && echo starts || echo fails)|$(has "attempts must be a non-negative whole number, not 'two'" "$(cut -f5 "${p}/.swarm/events.tsv")")"
rm -f "${b}/stories/e4-bad.md"
echo "escalate_after = 0" >> "${p}/.claude/swarm/config"
check "escalate_after = 0: attempts 0, 1, 2 and 5 never escalate" "code code code code|code-risky code-risky code-risky code-risky" \
  "$(ladder e4-a 0 1 2 5 -- "kind: code")|$(ladder e4-a 0 1 2 5 -- "kind: code" "risk: high")"
printf '%s\n' "base_branches = dev main" "escalate_after = 3" > "${p}/.claude/swarm/config"
check "escalate_after = 3: attempts: 2 is code, 3 is escalate" "code escalate" "$(ladder e4-a 2 3 -- "kind: code")"
rm -f "${b}/stories/e4-a.md" "${b}/stories/e4-f.md"

# --- close counts a failed build: story, close, story, close, story on one ready code story builds it
# as code, code, then escalate, each in a fresh worktree. Before each close the builder has committed
# and pushed story/x1, left an untracked file and opened a PR; the close clears them all away.
gh_stub; : > "${ROOT}/gh.log"
printf '%s\n' "base_branches = dev main" > "${p}/.claude/swarm/config"
item "${b}" stories/x1.md "status: ready" "kind: code" "repo: svc"
wt="${ROOT}/svc-wt/x1"; adds=""; fresh=""; cleared=""
left() { # <slug> — which of its worktree, local story/<slug> and origin's are still there
  [[ ! -d "${ROOT}/svc-wt/$1" ]] || printf ' worktree'
  ! git -C "${ROOT}/svc" show-ref -q --verify "refs/heads/story/$1" || printf ' branch'
  ! git -C "${ROOT}/svc.git" show-ref -q --verify "refs/heads/story/$1" || printf ' origin'
}
for i in 1 2 3; do
  if run story x1 >/dev/null; then adds+="ok "; else adds+="failed "; fi
  fresh+="$([[ "$(tip "${wt}" HEAD)" == "$(tip "${ROOT}/svc.git" dev)" && ! -e "${wt}/untracked" ]] && echo yes || echo no) "
  [[ ${i} -lt 3 ]] || break
  "${GIT[@]}" -C "${wt}" commit -q --allow-empty -m "attempt ${i}" && "${GIT[@]}" -C "${wt}" push -q origin story/x1
  touch "${wt}/untracked"
  echo "[{\"number\":${i},\"state\":\"OPEN\",\"url\":\"https://github.com/o/svc/pull/${i}\"}]" > "${ROOT}/prs.json"
  run close x1 >/dev/null
  cleared+="$(left x1)|"
done
check "story, close, story, close, story builds code, code, then escalate" "code code escalate" \
  "$(awk -F'\t' '$3 == "x1" { print $2 }' "${p}/.swarm/agents.tsv" | paste -sd' ' -)"
check "every worktree add succeeds, and starts fresh from the base" "ok ok ok |yes yes yes " "${adds}|${fresh}"
check "after each close the worktree, local and origin's story/x1 are gone" "||" "${cleared}"
check "each close closed its attempt's open PR" "2|yes|yes" \
  "$(grep -c '^pr close' "${ROOT}/gh.log")|$(has "pr close https://github.com/o/svc/pull/1 --comment" "$(cat "${ROOT}/gh.log")")|$(has "pr close https://github.com/o/svc/pull/2 --comment" "$(cat "${ROOT}/gh.log")")"
# An uncounted close (paused, cleared-on-error, impossible) clears its build away the same way, and a
# story closed impossible builds again once it is reset. paused and cleared-on-error hold the story
# (kind: lead), so each hold is lifted with reset before the next build.
echo '[]' > "${ROOT}/prs.json"; item "${b}" stories/y1.md "status: ready" "kind: code" "repo: svc"; cleared=""; adds=""; holds=""
for c in paused cleared-on-error impossible; do
  if run story y1 >/dev/null; then adds+="ok "; else adds+="failed "; fi
  "${GIT[@]}" -C "${ROOT}/svc-wt/y1" commit -q --allow-empty -m "${c}" && "${GIT[@]}" -C "${ROOT}/svc-wt/y1" push -q origin story/y1
  touch "${ROOT}/svc-wt/y1/untracked"
  run close y1 "${c}" >/dev/null
  cleared+="$(left y1)|"
  [[ "${c}" == impossible ]] || holds+="$(sed -n 's/^kind: //p' "${b}/stories/y1.md")$(run reset y1 lift the hold >/dev/null && echo ok || echo failed) "
done
check "each build of y1 starts, and after each uncounted close its worktree, local and origin's story/y1 are gone" "ok ok ok |||" "${adds}${cleared}"
check "paused and cleared-on-error each hold y1 (kind: lead), and reset lifts each hold" "leadok leadok " "${holds}"
got="$(sed -n 's/^kind: //p' "${b}/stories/y1.md")|$(run reset y1 its Done when is fixed >/dev/null && echo ok || echo failed)"
check "close y1 impossible leaves it kind: lead; reset y1 succeeds, and then story y1 succeeds" "lead|ok|ok" \
  "${got}|$(run story y1 >/dev/null && echo ok || echo failed)"
rm -f "${b}/stories/x1.md" "${b}/stories/y1.md" "${ROOT}/prs.json"

# --- reconcile clears a story's build before the pull: once its PR merged always, closing its open
# builder first (in review, so the close counts nothing); once its PR closed unmerged only when no
# builder is open. built <slug> <n> — build the story, push story/<slug> and put it in review with PR <n>.
printf '%s\n' "base_branches = dev main" > "${p}/.claude/swarm/config"
UR="https://github.com/o/svc/pull"
built() {
  item "${b}" "stories/$1.md" "status: ready" "kind: code" "repo: svc" "attempts: 1"
  run story "$1" >/dev/null
  "${GIT[@]}" -C "${ROOT}/svc-wt/$1" commit -q --allow-empty -m "$1" && "${GIT[@]}" -C "${ROOT}/svc-wt/$1" push -q origin "story/$1"
  run review "$1" "${UR}/$2" >/dev/null
}
fmv() { sed -n "s/^$2: //p" "${b}/stories/$1.md"; }   # <slug> <key>
gone() { [[ -e "${b}/stories/$1.md" ]] && echo there || echo gone; }   # <slug>: finish deletes its file
built ru1 11; run close ru1 >/dev/null; echo "${UR}/11 CLOSED" >> "${ROOT}/pr-states"
run reconcile >/dev/null
check "a PR closed unmerged with no builder open: reconcile clears its worktree and both branches" "|ready" "$(left ru1)|$(fmv ru1 status)"
rc=0; run story ru1 >/dev/null || rc=$?
"${GIT[@]}" -C "${ROOT}/svc-wt/ru1" commit -q --allow-empty -m again
check "and story builds it again, and its builder can push story/ru1" "0|pushed" \
  "${rc}|$(git -C "${ROOT}/svc-wt/ru1" push -q origin story/ru1 2>/dev/null && echo pushed || echo refused)"
built ru2 12; echo "${UR}/12 CLOSED" >> "${ROOT}/pr-states"
rout="$(run reconcile)"
check "with its builder still open, reconcile leaves the worktree and both branches, naming the story" " worktree branch origin|yes|ready" \
  "$(left ru2)|$(has "build kept: ru2" "${rout}")|$(fmv ru2 status)"
built ru3 16; echo "${UR}/16 CLOSED" >> "${ROOT}/pr-states"; touch "${ROOT}/listfail"
rout="$(run reconcile)"; rm "${ROOT}/listfail"
check "when herdr cannot list its agents, the builder may be open: reconcile keeps the build, saying why" " worktree branch origin|yes" \
  "$(left ru3)|$(has "build kept: ru3's builder may be open (herdr cannot list its agents)" "${rout}")"
built rm3 17; echo "${UR}/17 MERGED" >> "${ROOT}/pr-states"; touch "${ROOT}/listfail"
rout="$(run reconcile)"; rm "${ROOT}/listfail"
check "after a merge, when herdr cannot list its agents, reconcile still clears the build and says its builder may be open" "|yes" \
  "$(left rm3)|$(has "build cleared: rm3's builder may still be open (herdr cannot list its agents); close its pane with swarm.sh close rm3" "${rout}")"
built rm1 13; echo "${UR}/13 MERGED" >> "${ROOT}/pr-states"; : > "${ROOT}/herdr.log"; : > "${ROOT}/gh.log"
run reconcile >/dev/null
check "a merged story with its builder open: reconcile closes it, clears its build and finishes it, closing no PR" \
  "closed|gone||gone|0" \
  "$(closes)|$(grep -q '^rm1 ' "${ROOT}/agents" && echo open || echo gone)|$(left rm1)|$(gone rm1)|$(grep -c '^pr close' "${ROOT}/gh.log" || true)"
# Outside herdr no builder is open, and herdr is never called.
built rm2 14; run close rm2 >/dev/null; echo "${UR}/14 MERGED" >> "${ROOT}/pr-states"; : > "${ROOT}/herdr.log"
(cd "${p}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" reconcile >/dev/null 2>&1)
check "a merged story with no builder open still loses its worktree and both branches, and outside herdr no herdr call is made" "|gone|" \
  "$(left rm2)|$(gone rm2)|$(cat "${ROOT}/herdr.log")"
# The board in the project repo, goal = 5, and the review status uncommitted: the builder is closed
# while the story still says review (with goal on, closing a ready story with no cause is refused), then
# the pull takes the story off as its PR did. A second reconcile does nothing, and leaves qy (never
# built) alone.
q="${ROOT}/q"
"${GIT[@]}" init -q --bare "${q}.git" && "${GIT[@]}" clone -q "${q}.git" "${q}" 2>/dev/null
mkdir -p "${q}/.claude/swarm"; echo "goal = 5" > "${q}/.claude/swarm/config"
goal_story "${q}/docs" qz "status: ready" "kind: code"; item "${q}/docs" stories/qy.md "status: ready" "kind: code"
"${GIT[@]}" -C "${q}" add docs && "${GIT[@]}" -C "${q}" commit -q -m board && "${GIT[@]}" -C "${q}" push -q origin main
qrun() { (cd "${q}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
# send_goal types the /goal only into a started turn: the claude stub lists the brief's session busy.
echo '[]' > "${ROOT}/started.json"; export CLAUDE_STUB_AGENTS="${ROOT}/started.json"
qrun story qz >/dev/null
check "with the board in the repo it builds, the goal names the worktree's copy of the story, as the brief does" "docs/stories/qz.md" \
  "$(goal_path "${q}/.swarm/briefs/qz.md" "${q}/.swarm/briefs/qz.goal.md")"
"${GIT[@]}" -C "${q}-wt/qz" rm -q docs/stories/qz.md && "${GIT[@]}" -C "${q}-wt/qz" commit -q -m qz
"${GIT[@]}" -C "${q}-wt/qz" push -q origin story/qz story/qz:main   # the PR, merged
qrun review qz "${UR}/15" >/dev/null; echo "${UR}/15 MERGED" >> "${ROOT}/pr-states"; : > "${ROOT}/herdr.log"
rc=0; qrun reconcile >/dev/null || rc=$?
check "goal = 5, board in the repo, review uncommitted: reconcile exits 0, closes the builder, clears its build and pulls" \
  "0|closed|||gone" \
  "${rc}|$(closes)|$([[ -d "${q}-wt/qz" ]] && echo worktree)|$(git -C "${q}" show-ref --heads story/qz; git -C "${q}.git" show-ref --heads story/qz)|$([[ -e "${q}/docs/stories/qz.md" ]] && echo there || echo gone)"
: > "${ROOT}/herdr.log"; rc=0; rout="$(qrun reconcile)" || rc=$?
check "a second reconcile is a no-op" "0|||ready" "${rc}|${rout}|$(cat "${ROOT}/herdr.log")|$(sed -n "s/^status: //p" "${q}/docs/stories/qy.md")"
rm -f "${b}"/stories/r[um][123].md

# --- builder_subagent_model: a building role's start carries it, a planning or conducting role's does not.
printf '%s\n' "base_branches = dev main" "builder_subagent_model = haiku" > "${p}/.claude/swarm/config"
sub='--settings {"env":{"CLAUDE_CODE_SUBAGENT_MODEL":"haiku","CLAUDE_CODE_SUBAGENT_MODEL_FORCE":"1"}}'
started() { # <name> — with or without the setting, or "not started" when herdr never started <name>
  local l; l="$(grep "^agent start $1 " "${ROOT}/herdr.log")" || { echo "not started"; return; }
  if grep -qF -- "${sub}" <<< "${l}"; then echo with; else echo without; fi
}
: > "${ROOT}/herdr.log"
build sub1 "kind: code" >/dev/null
echo brief > "${ROOT}/survey-brief.md"
run agent scope-sub sv1 "${ROOT}/svc" survey "${ROOT}/survey-brief.md" >/dev/null || true
item "${b}" epics/sube.md "status: active"
run conduct sube >/dev/null || true
check "builder_subagent_model: the builder's start sets it; a survey's and a conductor's do not" "with|without|without" \
  "$(started sub1)|$(started sv1)|$(started conduct-sube)"
rm -f "${b}"/stories/r[04]-*.md "${b}"/stories/s4-*.md "${b}/stories/sub1.md" "${b}/epics/sube.md"
printf '%s\n' "base_branches = dev main" > "${p}/.claude/swarm/config"

# --- Every codex run goes through codex-review: the arm is the one place that runs codex's review.
REPO="$(dirname "${SWARM}")/.."
check "only codex-review runs codex exec review, and no command tells anyone to" "1|" \
  "$(grep -c 'codex exec review' "${SWARM}")|$(grep -l 'codex exec review' "${REPO}"/commands/*.md || true)"
check "/swarm-dev:swarm runs the lead's codex-review in the background" "yes" \
  "$(has "swarm.sh codex-review <base>\` in its worktree, run in the background (Bash \`run_in_background\`)" "$(tr -s '[:space:]' ' ' < "${REPO}/commands/swarm.md")")"

# notreviewed <file> — how many of <file>'s log-finding lines lack --reviewer, or none when it has none.
notreviewed() { if ! grep -q 'log-finding' "$1"; then echo none; else grep 'log-finding' "$1" | grep -vc -- '--reviewer' || true; fi; }
check "every log-finding line of commands/swarm.md and method.md names --reviewer" "0|0" \
  "$(notreviewed "${REPO}/commands/swarm.md")|$(notreviewed "${REPO}/docs/method.md")"
# shellcheck disable=SC2016 # the backticks are the Markdown's
check "/swarm-dev:swarm maps each reviewer to its --reviewer value, the lead's own reading to lead" "yes" \
  "$(has '`codex` for codex-review'"'"'s, `code-review` for /code-review'"'"'s, `ci` for the review bot'"'"'s or a `swarm.sh findings` note'"'"'s, or `lead` for your own reading' "$(tr -s '[:space:]' ' ' < "${REPO}/commands/swarm.md")")"
# bare_declined — each --declined in finding_rule's text or method.md's outer-loop paragraph that is
# not followed by a reason (out-of-scope, nit, wrong or the <reason> placeholder), or none.
bare_declined() {
  { sed -n '/^finding_rule() {/,/^}/p' "${SWARM}"; sed -n '/^\*\*Learning across epics/,/^$/p' "${REPO}/docs/method.md"; } \
    | grep -oE -- '--declined( +[^ `]+)?' | grep -vE -- '--declined +(out-of-scope|nit|wrong|<reason>)$' || echo none
}
check "every --declined in finding_rule and the outer-loop paragraph is followed by a reason" "none" "$(bare_declined)"
check "finding_rule names out-of-scope, nit, wrong and --reviewer escaped" "yes|yes|yes|yes" \
  "$(f="$(sed -n '/^finding_rule() {/,/^}/p' "${SWARM}")"; for w in out-of-scope nit wrong '--reviewer escaped'; do has "${w}" "${f}"; done | paste -sd'|' -)"
check "the conductors' reviewer mapping is written once, in finding_rule" "1" "$(grep -c "<who> is the reviewer that first raised it, whoever passed it on" "${SWARM}")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
