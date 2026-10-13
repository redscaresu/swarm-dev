#!/usr/bin/env bash
# epic_test.sh — the layout (an epic's tab holds its conductor and a pane per story) and
# pr_per = epic (stories branch from, and merge into, epic/<slug>). herdr is a stub on PATH that
# hands out pane ids in order and remembers tab labels; the repo is a local bare remote.
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
echo "Ask k1" > "${p}/.swarm/state/brief-x.md"   # a codex brief's prose: never a tab record
: > "${ROOT}/herdr.log"
run close k1 >/dev/null; run close conduct-k >/dev/null
check "with keep_panes, closing a story or a conductor closes nothing and renames the agents by their panes" "no|yes|yes|Ask k1" \
  "$(grep -q 'close' "${ROOT}/herdr.log" && echo yes || echo no)|$(grep -qE '^agent rename w:[0-9]+ k1-done$' "${ROOT}/herdr.log" && echo yes || echo no)|$(grep -qE '^agent rename w:[0-9]+ conduct-k-done$' "${ROOT}/herdr.log" && echo yes || echo no)|$(cat "${p}/.swarm/state/brief-x.md")"
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

# --- wait: herdr's agent wait is only the wake-up (the stub always says done); a Claude agent's
# state is its session's, from the claude stub's fixture. An agent idle after an API error is told
# to carry on; any other idle agent is left alone.
export CLAUDE_STUB_AGENTS="${ROOT}/claude.json"
session() { # <file> <session>=<status>... — a `claude agents --json` fixture
  local f="$1" e out=""; shift
  for e in "$@"; do out+="${out:+,}{\"sessionId\":\"${e%%=*}\",\"status\":\"${e#*=}\"}"; done
  echo "[${out}]" > "${f}"
}
nudges() { grep -c '^agent prompt' "${ROOT}/herdr.log" || true; }
echo "a w:50" >> "${ROOT}/agents"; echo "w:50 a" > "${p}/.swarm/state/wait-a"   # this project's agent a, in a pane it recorded
printf '2026-10-13\tcode\ta\tclaude\topus\thigh\tsess-a\n' >> "${p}/.swarm/agents.tsv"
session "${ROOT}/claude.json" sess-a=idle
printf '%s\n' "⏺ I have opened the PR." "⏺ Error: Exit code 1 from make test" > "${ROOT}/screen"
: > "${ROOT}/herdr.log"
check "an idle session whose last event is not an API error is not nudged, whatever herdr says" "idle|0" "$(run wait a)|$(nudges)"
printf '%s\n' "⏺ Reviewing the commit." "⏺ API Error: The response stopped arriving." "✻ Crunched for 5m" > "${ROOT}/screen"
: > "${ROOT}/herdr.log"
check "an agent stopped by an API error is nudged, then waited on again" "idle|1" "$(run wait a | tail -1)|$(nudges)"
printf '%s\n' "⏺ API Error: 401 invalid key" > "${ROOT}/screen"; touch "${ROOT}/sticky"
: > "${ROOT}/herdr.log"
check "an error that does not clear stops after three nudges" "idle|3" "$(run wait a | tail -1)|$(nudges)"
# The session still reads idle after each nudge: wait wakes on herdr before it reads it again, so no
# two nudges go out without a wake between them.
check "after a nudge, wait wakes before it takes the session's word again" "yes" \
  "$(grep -E '^agent (wait|prompt)' "${ROOT}/herdr.log" | awk '/^agent prompt/ { if (p) bad = 1; p = 1; next } { p = 0 } END { print bad ? "no" : "yes" }')"
rm -f "${ROOT}/sticky" "${ROOT}/screen"
waitrc() { # <stderr file> <wait args...> — "<stdout>|exit <rc>|<seconds taken>"
  local e="$1" t0=${SECONDS} out rc=0; shift
  out="$(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" wait "$@" 2>"${e}")" || rc=$?
  echo "${out}|exit ${rc}|$((SECONDS - t0))"
}
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
printf '%s\n' "⏺ API Error: overloaded" > "${ROOT}/screen"; rm -f "${p}/.swarm/state/wait-a"
: > "${ROOT}/herdr.log"
check "wait never addresses another project's agent of the same name" "0|0" \
  "$(grep -c '^agent wait' <<< "$(run wait a >/dev/null 2>&1; cat "${ROOT}/herdr.log")" || true)|$(nudges)"
rm -f "${ROOT}/screen"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
