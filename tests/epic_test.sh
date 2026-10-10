#!/usr/bin/env bash
# epic_test.sh — the layout (an epic's tab holds its conductor and a pane per story) and
# pr_per = epic (stories branch from, and merge into, epic/<slug>). herdr is a stub on PATH that
# hands out pane ids in order and remembers tab labels; the repo is a local bare remote.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
ROOT="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
# No trust file here, so require_trusted lets the fixture agents start whatever ~/.claude.json says.
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
fails=0
GIT=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main)

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }
first() { printf '%s' "${1%%$'\n'*}"; }

item() { # <board> <path> <front-matter line>...
  local path="$1/$2" title; shift 2
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

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
  "agent prompt")     [ -e "$H/sticky" ] || rm -f "$H/screen"   # a nudge clears the error, unless it is sticky
                      if [ -e "$H/idle" ]; then echo '{"result":{"agent":{"agent_status":"idle"}}}'
                      else echo '{"result":{"agent":{"agent_status":"working"}}}'; fi ;;
  "agent list")       echo '{"result":{"agents":[]}}' ;;
  "agent wait")       echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent read")       cat "$H/screen" 2>/dev/null ;;
esac
EOF
chmod +x "${ROOT}/bin/herdr"
log() { cat "${ROOT}/herdr.log"; }

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
  "$(has "codex exec review --base" "${cbrief}")|$(has "/code-review <PR>" "${cbrief}")|$(has "swarm.sh tell <slug> <file>" "${cbrief}")|$(has "Never merge a story, and never run" "${cbrief}")"
check "the new workspace's placeholder tab is closed" "yes" "$(has "tab close t0" "$(log)")"
for s in s1 s2 s3 s4; do run story "${s}" >/dev/null; done
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
run close conduct-e >/dev/null
check "closing the conductor closes the epic's tabs" "tab close t1|tab close t5" "$(grep '^tab close' "${ROOT}/herdr.log" | paste -sd'|' -)"
# A conductor that never takes its brief (an agent not logged in) must not leave the placeholder behind.
: > "${ROOT}/herdr.log"; touch "${ROOT}/idle"
run conduct e >/dev/null || true
rm "${ROOT}/idle"
check "a conductor that fails to start still closes the placeholder tab" "yes" "$(has "tab close t0" "$(log)")"

# --- keep_panes = true: close leaves everything open, frees the agent's name, and keeps its slot.
echo "keep_panes = true" > "${p}/.claude/swarm/config"
item "${b}" epics/k.md "status: active"
for s in k1 k2; do item "${b}" "stories/${s}.md" "status: ready" "kind: code" "epic: k" "repo: svc"; done
run conduct k >/dev/null; run story k1 >/dev/null
: > "${ROOT}/herdr.log"
run close k1 >/dev/null; run close conduct-k >/dev/null
check "with keep_panes, closing a story or a conductor closes nothing and renames the agents" "no|yes|yes" \
  "$(grep -q 'close' "${ROOT}/herdr.log" && echo yes || echo no)|$(has "agent rename k1 k1-done" "$(log)")|$(has "agent rename conduct-k conduct-k-done" "$(log)")"
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
run conduct f >/dev/null
brief="$(cat "${p}/.swarm/briefs/conduct-f.md")"
check "the conductor merges stories into the epic branch, then opens one PR per repo" "yes|yes|yes" \
  "$(has "git merge --no-ff origin/story/<slug>" "${brief}")|$(has "epic check \`make test\`" "${brief}")|$(has "open one PR per repo from epic/f" "${brief}")"
check "the one-PR-per-epic brief also watches only its own epic's PRs" "yes" "$(has "swarm.sh watch --epic f\`" "${brief}")"
check "the one-PR-per-epic conductor runs /code-review on each epic PR" "yes" \
  "$(has "An epic PR that changes code is reviewed only once the /code-review skill" "${brief}")"
# lessons_file elsewhere: its tagged rules (only those) reach a builder in another repo's worktree.
printf 'lessons_file = AGENTS.md\n' >> "${p}/.claude/swarm/config"
printf 'Untagged guidance.\nTag rules with <!-- lesson: <kind> -->.\nProve it. <!-- lesson: agents-kind -->\n' > "${p}/AGENTS.md"
printf 'A PROJECT RULE every agent reads.' > "${p}/.claude/swarm/brief.md"   # no final newline
item "${b}" stories/g1.md "status: ready" "kind: code" "repo: svc"
run story g1 >/dev/null
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

# --- wait: an agent idle after an API error is told to carry on; any other idle agent is left alone.
nudges() { grep -c '^agent prompt' "${ROOT}/herdr.log" || true; }
printf '%s\n' "⏺ I have opened the PR." "⏺ Error: Exit code 1 from make test" > "${ROOT}/screen"
: > "${ROOT}/herdr.log"
check "an idle agent whose last event is not an API error is not nudged" "idle|0" "$(run wait a)|$(nudges)"
printf '%s\n' "⏺ Reviewing the commit." "⏺ API Error: The response stopped arriving." "✻ Crunched for 5m" > "${ROOT}/screen"
: > "${ROOT}/herdr.log"
check "an agent stopped by an API error is nudged, then waited on again" "idle|1" "$(run wait a | tail -1)|$(nudges)"
printf '%s\n' "⏺ API Error: 401 invalid key" > "${ROOT}/screen"; touch "${ROOT}/sticky"
: > "${ROOT}/herdr.log"
check "an error that does not clear stops after three nudges" "idle|3" "$(run wait a | tail -1)|$(nudges)"
rm -f "${ROOT}/sticky" "${ROOT}/screen"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
