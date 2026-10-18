#!/usr/bin/env bash
# epic_goal_test.sh — goal = N: the condition story writes beside the brief, the /goal it sends,
# and the ways a /goal fails to set.
# herdr is a stub on PATH that hands out pane ids in order and remembers tab labels; the repo is a
# local bare remote. gh is a stub too, so a close's PR lookup never reaches the real gh.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
SH=("${SWARM}" "$(dirname "${SWARM}")"/lib/*.sh)   # swarm.sh and the bin/lib/*.sh it sources
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
GOAL_SEND_MAX="$(sed -n 's/^GOAL_SEND_MAX=\([0-9]*\).*/\1/p' "${SH[@]}")"
STORY_REPLY="When CI is green, reply with the PR URL, what changed in three lines, and the codex findings and the mutation, then stay open: the conductor may send review findings to fix on the same PR."

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

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
