#!/usr/bin/env bash
# epic_overlap_test.sh — story warns when an open story of another epic touches the same function
# or file, and story --strict refuses.
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
# events.tsv lives here.
mkdir -p "${p}/.swarm"

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
other "status: review" "epic: e2" "costs: money" "touches: [bin/swarm.sh:tell_agent (kinds)]"; subject xm "[bin/swarm.sh:tell_agent]"
check "story names an open story whose merge is the user's (costs money)" \
  "warning: xb (epic e2) is open and touches bin/swarm.sh:tell_agent; start xm after it merges (costs money)" "$(warns xm)"
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

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
