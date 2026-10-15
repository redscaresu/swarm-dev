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
# goal_parts <goal file> <reply sentence> <bound> — has for each part a goal condition holds.
goal_parts() {
  local g; g="$(cat "$1" 2>&1)"
  printf '%s|' "$(has "- DW-ONE holds" "${g}")" "$(has "- DW-TWO holds" "${g}")" "$(has "- FR-ONE holds" "${g}")" \
    "$(grep -q SPIKE-ONE <<< "${g}" && echo spike || echo yes)" "$(has "$2" "${g}")" "$(has "IMPOSSIBLE: <why>" "${g}")"
  has "or stop after $3 more turns" "${g}"
}
GOAL_PARTS="yes|yes|yes|yes|yes|yes|yes"
STORY_REPLY="When CI is green, reply with the PR URL, what changed in three lines, and the codex findings and the mutation, then stay open: the conductor may send review findings to fix on the same PR."
EPIC_REPLY="When your branch is pushed, reply with the branch, what changed in three lines, the codex findings and the mutation, then stop."

# herdr: logs every call; each new pane is w:<n>, each new tab t<n>, and tab list shows their labels.
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
                      if [ -e "$H/idle" ]; then echo '{"result":{"agent":{"agent_status":"idle"}}}'
                      else echo '{"result":{"agent":{"agent_status":"working"}}}'; fi ;;
  "agent start")      echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')" >> "$H/agents" ;;
  "agent rename")     [ -e "$H/norename" ] && exit 1
                      [ -e "$H/agents" ] && awk -v t="$3" -v n="$4" '$2 == t { $1 = n } { print }' "$H/agents" > "$H/agents.tmp" && mv "$H/agents.tmp" "$H/agents" ;;
  "agent list")       awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
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
# gh: logs every call; pr list prints ${ROOT}/prs.json, or no PRs.
gh_stub() {
  printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/gh"
  # shellcheck disable=SC2016 # the stub's own shell expands these
  printf '%s\n' 'echo "$*" >> "$H/gh.log"' 'case "$1 $2" in "pr list") cat "$H/prs.json" 2>/dev/null || echo "[]" ;; esac' >> "${ROOT}/bin/gh"
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
run conduct e >/dev/null
check "the conductor opens a tab named for the epic" "yes" "$(has "tab create --workspace w --cwd ${p} --label e --no-focus" "$(log)")"
check "and its pane is named conductor" "yes" "$(has "pane rename w:1 conductor" "$(log)")"
check "the conductor's brief watches only its own epic's PRs" "yes" \
  "$(grep -q 'swarm.sh watch --epic e`' "${p}/.swarm/briefs/conduct-e.md" && echo yes || echo no)"
cbrief="$(cat "${p}/.swarm/briefs/conduct-e.md")"
check "the conductor's brief includes the project's brief, so adopted lessons reach it" "yes" "$(has "A PROJECT RULE every agent reads." "${cbrief}")"
check "the conductor reviews with codex and /code-review, tells the builder, and closes only after" "yes|yes|yes|yes" \
  "$(has "codex exec review --base" "${cbrief}")|$(has "/code-review <PR>" "${cbrief}")|$(has "swarm.sh tell <slug> findings <file>" "${cbrief}")|$(has "Never merge a story, and never run" "${cbrief}")"
check "the conductor's brief says what a builder's auth means and to resume it after the login, then wait on it again" "yes|yes" \
  "$(has "stopped on an expired login, which only the user's" "${cbrief}")|$(has "again with \`swarm.sh wait <slug>\` in the background." "${cbrief}")"
check "the conductor gives up on a builder with close, accepts a Fable dialog itself, and leaves an escalated story to the lead" \
  "${GIVES_UP}" "$(gives_up "${cbrief}")"
check "the new workspace's placeholder tab is closed" "yes" "$(has "tab close t0" "$(log)")"
for s in s1 s2 s3 s4; do run story "${s}" >/dev/null; done
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
: > "${ROOT}/herdr.log"
run close s1 >/dev/null
check "closing a story closes its pane and leaves the epic's tab" "yes|no|no" \
  "$(has "pane close w:2" "$(log)")|$(grep -q 'tab close' "${ROOT}/herdr.log" && echo yes || echo no)|$(grep -q ' s1$' "${p}/.swarm/state/e" && echo yes || echo no)"
check "closing a ready story's builder counts a failed build and removes its worktree" "1|no" \
  "$(sed -n 's/^attempts: //p' "${b}/stories/s1.md")|$([[ -d "${ROOT}/svc-wt/s1" ]] && echo yes || echo no)"
run close conduct-e >/dev/null
check "closing the conductor closes the epic's tabs" "tab close t1|tab close t5" "$(grep '^tab close' "${ROOT}/herdr.log" | paste -sd'|' -)"
# A conductor that never takes its brief (an agent not logged in) must not leave the placeholder behind.
: > "${ROOT}/herdr.log"; touch "${ROOT}/idle"
run conduct e >/dev/null || true
rm "${ROOT}/idle"
check "a conductor that fails to start still closes the placeholder tab" "yes" "$(has "tab close t0" "$(log)")"
# goal: off writes no goal file; goal = N writes the condition beside the brief, with the brief's reply.
goal_story "${b}" gl0 "status: ready" "kind: code" "repo: svc"
run story gl0 >/dev/null
check "with goal off, story writes no .goal.md, and the brief holds the story-mode reply" "no|yes" \
  "$([[ -e "${p}/.swarm/briefs/gl0.goal.md" ]] && echo yes || echo no)|$(has "${STORY_REPLY}" "$(cat "${p}/.swarm/briefs/gl0.md")")"
echo "goal = 7" > "${p}/.claude/swarm/config"
goal_story "${b}" gl1 "status: ready" "kind: code" "repo: svc"
run story gl1 >/dev/null || true
check "with goal = 7, story writes the condition: Done when, From review, the brief's reply, the escape and the bound" \
  "${GOAL_PARTS}|yes" "$(goal_parts "${p}/.swarm/briefs/gl1.goal.md" "${STORY_REPLY}" 7)|$(has "${STORY_REPLY}" "$(cat "${p}/.swarm/briefs/gl1.md")")"
: > "${p}/.claude/swarm/config"; rm -f "${b}/stories/gl0.md" "${b}/stories/gl1.md"

# --- keep_panes = true: close leaves everything open, frees the agent's name, and keeps its slot.
echo "keep_panes = true" > "${p}/.claude/swarm/config"
item "${b}" epics/k.md "status: active"
for s in k1 k2; do item "${b}" "stories/${s}.md" "status: ready" "kind: code" "epic: k" "repo: svc"; done
run conduct k >/dev/null; run story k1 >/dev/null
echo "Ask k1" > "${p}/.swarm/state/brief-x.md"   # a codex brief's prose: never a tab record
: > "${ROOT}/herdr.log"
run close k1 >/dev/null; run close conduct-k >/dev/null
check "with keep_panes, closing a story or a conductor closes nothing and renames the agents by their panes" "no|yes|yes|Ask k1" \
  "$(grep -q 'close' "${ROOT}/herdr.log" && echo yes || echo no)|$(grep -qE '^agent rename w:[0-9]+ k1-done$' "${ROOT}/herdr.log" && echo yes || echo no)|$(grep -qE '^agent rename w:[0-9]+ conduct-k-done$' "${ROOT}/herdr.log" && echo yes || echo no)|$(cat "${p}/.swarm/state/brief-x.md")"
check "with keep_panes, closing a ready story's builder still counts a failed build" "1" "$(sed -n 's/^attempts: //p' "${b}/stories/k1.md")"
rm -f "${p}/.swarm/state/brief-x.md"
# Another project's agent with this project's name is never renamed (herdr names span workspaces).
echo "k1 w:99" >> "${ROOT}/agents"; : > "${ROOT}/herdr.log"
run close k1 >/dev/null
check "with keep_panes, closing never renames another project's agent of the same name" "no" \
  "$(grep -q '^agent rename' "${ROOT}/herdr.log" && echo yes || echo no)"
awk '$2 != "w:99"' "${ROOT}/agents" > "${ROOT}/agents.tmp" && mv "${ROOT}/agents.tmp" "${ROOT}/agents"
# A rename herdr refuses leaves the tab record as it was, and close says the name is not free.
echo "k3 w:98" >> "${ROOT}/agents"; echo "w:98 k3" > "${p}/.swarm/state/k3"; touch "${ROOT}/norename"
out="$(run close k3 2>&1 || true)"
check "with keep_panes, a refused rename keeps the record and says the name is not free" "w:98 k3|yes" \
  "$(cat "${p}/.swarm/state/k3")|$(has "is not free" "${out}")"
rm -f "${ROOT}/norename" "${p}/.swarm/state/k3"
run story k2 >/dev/null
check "and the next story gets a pane of its own" "3|k1-done|k2" \
  "$(wc -l < "${p}/.swarm/state/k" | tr -d ' ')|$(awk 'NR == 2 { print $2 }' "${p}/.swarm/state/k")|$(awk 'NR == 3 { print $2 }' "${p}/.swarm/state/k")"
: > "${p}/.claude/swarm/config"; rm -f "${b}"/epics/k.md "${b}"/stories/k?.md

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
  "$(has "open no PR" "${brief}")|$(has "codex exec review --base origin/epic/f" "${brief}")|$(has "Before you reply, also run the epic's check" "${brief}")"
check "the epic story brief asks for a mutation" "yes" \
  "$(has "prove each new or changed test can fail" "${brief}")"
# Someone merged into the epic branch: the next story starts from there, and the repo is listed once.
"${GIT[@]}" -C "${ROOT}/svc" fetch -q origin && "${GIT[@]}" -C "${ROOT}/svc" checkout -q -b m origin/epic/f
"${GIT[@]}" -C "${ROOT}/svc" commit -q --allow-empty -m f1 && "${GIT[@]}" -C "${ROOT}/svc" push -q origin m:epic/f
merged="$(tip "${ROOT}/svc" HEAD)"
run story f2 >/dev/null
check "a later story branches from the epic branch as it is now" "${merged}|${merged}" "$(tip "${ROOT}/svc-wt/f2" HEAD)|$(tip "${ROOT}/svc.git" epic/f)"
check "the repo is listed once" "svc" "$(sed -n 's/^repos: //p' "${b}/epics/f.md")"
check "with goal off, the epic story brief holds the epic-mode reply, and no .goal.md is written" "yes|no" \
  "$(has "${EPIC_REPLY}" "$(cat "${p}/.swarm/briefs/f2.md")")|$([[ -e "${p}/.swarm/briefs/f2.goal.md" ]] && echo yes || echo no)"
printf '%s\n' "pr_per = epic" "base_branches = dev main" "goal = 7" > "${p}/.claude/swarm/config"
goal_story "${b}" gf1 "status: ready" "kind: code" "epic: f" "repo: svc"
run story gf1 >/dev/null || true
check "with goal = 7 and pr_per = epic, the condition carries the epic-mode reply the brief holds" \
  "${GOAL_PARTS}|yes" "$(goal_parts "${p}/.swarm/briefs/gf1.goal.md" "${EPIC_REPLY}" 7)|$(has "${EPIC_REPLY}" "$(cat "${p}/.swarm/briefs/gf1.md")")"
# A condition over Claude Code's 4000 characters is refused before the epic branch or worktree exists.
item "${b}" epics/gx.md "status: active"; cp "${b}/epics/gx.md" "${ROOT}/gx-epic.md"
goal_story "${b}" gx1 "status: ready" "kind: code" "epic: gx" "repo: svc"
python3 -c 'print("**Done when:**"); print("\n".join("- line %d of a long acceptance" % i for i in range(200)))' > "${ROOT}/long.md"
python3 - "${b}/stories/gx1.md" "${ROOT}/long.md" <<'PY2'
import sys; s = open(sys.argv[1]).read(); open(sys.argv[1], "w").write(s.replace("**Done when:**", open(sys.argv[2]).read().rstrip("\n"), 1))
PY2
out="$(run story gx1 || true)"
check "with goal on, an over-long condition fails naming the story, and leaves no worktree, branch, epic branch or epic edit" \
  "yes|no|no|no|no|same" \
  "$(has "gx1: its goal condition is" "${out}")|$([[ -e "${ROOT}/svc-wt/gx1" ]] && echo yes || echo no)|$(git -C "${ROOT}/svc" show-ref -q --verify refs/heads/story/gx1 && echo yes || echo no)|$(git -C "${ROOT}/svc.git" show-ref -q --verify refs/heads/story/gx1 && echo yes || echo no)|$(git -C "${ROOT}/svc.git" show-ref -q --verify refs/heads/epic/gx && echo yes || echo no)|$(cmp -s "${ROOT}/gx-epic.md" "${b}/epics/gx.md" && echo same || echo changed)"
printf '%s\n' "pr_per = epic" "base_branches = dev main" > "${p}/.claude/swarm/config"
rm -f "${b}/stories/gf1.md" "${b}/stories/gx1.md" "${b}/epics/gx.md"
run conduct f >/dev/null
brief="$(cat "${p}/.swarm/briefs/conduct-f.md")"
check "the conductor merges stories into the epic branch, then opens one PR per repo" "yes|yes|yes" \
  "$(has "git merge --no-ff origin/story/<slug>" "${brief}")|$(has "epic check \`make test\`" "${brief}")|$(has "open one PR per repo from epic/f" "${brief}")"
check "the one-PR-per-epic brief also watches only its own epic's PRs" "yes" "$(has "swarm.sh watch --epic f\`" "${brief}")"
check "the one-PR-per-epic conductor runs /code-review on each epic PR" "yes" \
  "$(has "An epic PR that changes code is reviewed only once the /code-review skill" "${brief}")"
check "the one-PR-per-epic conductor's brief says what a builder's auth means, then wait on it again" "yes|yes" \
  "$(has "stopped on an expired login, which only the user's" "${brief}")|$(has "again with \`swarm.sh wait <slug>\` in the background." "${brief}")"
check "the one-PR-per-epic conductor gives up with close, accepts a Fable dialog itself, and leaves an escalated story to the lead" \
  "${GIVES_UP}" "$(gives_up "${brief}")"
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
brief="$(cat "${p}/.swarm/briefs/conduct-f.md")"
check "with merge = agent, the conductor waits out a queued merge, then pulls and finishes through review and reconcile" "yes|yes|yes" \
  "$(has "A queued merge (auto-merge, a merge queue) has not" "${brief}")|$(has "run \`swarm.sh review <slug> <PR URL>\` and" "${brief}")|$(has "\`swarm.sh reconcile\`, never a plain \`git pull\`" "${brief}")"
printf '%s\n' "escalate_after = 0" "base_branches = dev main" > "${p}/.claude/swarm/config"
run conduct f >/dev/null || true
brief="$(cat "${p}/.swarm/briefs/conduct-f.md")"
check "with escalate_after = 0, the conductor stops retrying a story that failed twice and reports it to the lead" "yes|yes|no" \
  "$(has "model: escalation is off (escalate_after = 0), so once a story has failed twice" "${brief}")|$(has "do not start it again: report it to the lead." "${brief}")|$(grep -q "picks Fable for build" <<< "${brief}" && echo yes || echo no)"
printf '%s\n' "${cfg}" > "${p}/.claude/swarm/config"
# shellcheck disable=SC2016 # the backticks are the Markdown's
oneoff="$(sed -n '/`story <slug>`: a one-off/,/`plan-epic <epic>`/p' "$(dirname "${SWARM}")/../commands/swarm.md")"
check "/swarm-dev:swarm's one-off merge = agent step waits for the merge, then reviews and reconciles" "yes|yes|yes" \
  "$(has "wait until the PR has merged" "${oneoff}")|$(has "\`swarm.sh review <slug> <PR URL>\` and \`swarm.sh reconcile\`" "${oneoff}")|$(has "never a plain \`git pull\`" "${oneoff}")"
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
echo "a w:50" >> "${ROOT}/agents"; echo "w:50 a" > "${p}/.swarm/state/wait-a"   # this project's agent a, in a pane it recorded
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
  "code opus high|code-risky opus xhigh|docs sonnet medium|chore haiku medium|verify haiku medium" \
  "$(build r0-code "kind: code")|$(build r0-risky "kind: code" "risk: high")|$(build r0-docs "kind: docs")|$(build r0-chore "kind: chore")|$(build r0-verify "kind: verify")"
echo "sonnet_share = 4" >> "${p}/.claude/swarm/config"
check "sonnet_share = 4: code stories split by cksum mod 4, and a sampled one starts on code-sonnet sonnet high" \
  "code opus high|code opus high|code-sonnet sonnet high|code-sonnet sonnet high" \
  "$(build r4-a "kind: code")|$(build r4-b)|$(build r4-f "kind: code")|$(build r4-g "kind: code")"
check "sonnet_share = 4: risk: high stays code-risky, and docs, chore and verify are unchanged" \
  "code-risky opus xhigh|docs sonnet medium|chore haiku medium|verify haiku medium" \
  "$(build s4-risky4 "kind: code" "risk: high")|$(build s4-docs4 "kind: docs")|$(build s4-chore2 "kind: chore")|$(build s4-verify2 "kind: verify")"
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
  "code code escalate|code-risky code-risky escalate|code-sonnet code-sonnet escalate|docs docs escalate|chore chore escalate|verify verify escalate" \
  "$(ladder e4-a 0 1 2 -- "kind: code")|$(ladder e4-a 0 1 2 -- "kind: code" "risk: high")|$(ladder e4-f 0 1 2 -- "kind: code")|$(ladder e4-a 0 1 2 -- "kind: docs")|$(ladder e4-a 0 1 2 -- "kind: chore")|$(ladder e4-a 0 1 2 -- "kind: verify")"
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
left() { # which of x1's worktree, local story/x1 and origin's are still there
  [[ ! -d "${wt}" ]] || printf ' worktree'
  ! git -C "${ROOT}/svc" show-ref -q --verify refs/heads/story/x1 || printf ' branch'
  ! git -C "${ROOT}/svc.git" show-ref -q --verify refs/heads/story/x1 || printf ' origin'
}
for i in 1 2 3; do
  if run story x1 >/dev/null; then adds+="ok "; else adds+="failed "; fi
  fresh+="$([[ "$(tip "${wt}" HEAD)" == "$(tip "${ROOT}/svc.git" dev)" && ! -e "${wt}/untracked" ]] && echo yes || echo no) "
  [[ ${i} -lt 3 ]] || break
  "${GIT[@]}" -C "${wt}" commit -q --allow-empty -m "attempt ${i}" && "${GIT[@]}" -C "${wt}" push -q origin story/x1
  touch "${wt}/untracked"
  echo "[{\"number\":${i},\"state\":\"OPEN\",\"url\":\"https://github.com/o/svc/pull/${i}\"}]" > "${ROOT}/prs.json"
  run close x1 >/dev/null
  cleared+="$(left)|"
done
check "story, close, story, close, story builds code, code, then escalate" "code code escalate" \
  "$(awk -F'\t' '$3 == "x1" { print $2 }' "${p}/.swarm/agents.tsv" | paste -sd' ' -)"
check "every worktree add succeeds, and starts fresh from the base" "ok ok ok |yes yes yes " "${adds}|${fresh}"
check "after each close the worktree, local and origin's story/x1 are gone" "||" "${cleared}"
check "each close closed its attempt's open PR" "2|yes|yes" \
  "$(grep -c '^pr close' "${ROOT}/gh.log")|$(has "pr close https://github.com/o/svc/pull/1 --comment" "$(cat "${ROOT}/gh.log")")|$(has "pr close https://github.com/o/svc/pull/2 --comment" "$(cat "${ROOT}/gh.log")")"
rm -f "${b}/stories/x1.md" "${ROOT}/prs.json"

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

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
