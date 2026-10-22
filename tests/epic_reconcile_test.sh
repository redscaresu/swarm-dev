#!/usr/bin/env bash
# epic_reconcile_test.sh — close --drop counts a failed build and clears it away; reconcile clears a
# story's build before the pull.
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
# val <slug> <key> — <key> of a story on ${b} as swarm.sh reads it: board.sh's own get_fm.
# shellcheck source=/dev/null
val() { (export BOARD="${b}" PROJECT_DIR="${p}"; . "${SWARM%/*}/lib/board.sh"; get_fm "${b}/stories/$1.md" "$2"); }

# goal_story <board> <slug> <front-matter line>... — a story with a Done when and a From review block,
# and a From the spike block that is not part of a goal.
goal_story() {
  local bd="$1" slug="$2"; shift 2
  item "${bd}" "stories/${slug}.md" "$@"
  printf '%s\n' "" "Scope." "" "**Done when:**" "- DW-ONE holds" "- DW-TWO holds" "" \
    "**From review (binding; overrides the scope above where they differ):**" "- FR-ONE holds" "" \
    "**From the spike (binding):**" "- SPIKE-ONE" >> "${bd}/stories/${slug}.md"
}
# goal_path <brief> <goal file> — the story path the brief's Implement line gives, when the goal names
# that same path, or both.
goal_path() {
  local ref; ref="$(sed -n 's/^Implement \(.*\)\. Its \*\*Done when\*\* is the acceptance\.$/\1/p' "$1")"
  ref="${ref%% (this worktree is *}"
  if [[ -n "${ref}" ]] && grep -qF -- "in ${ref} (your brief's story" "$2"; then echo "${ref}"; else echo "brief: '${ref}', goal: $(cat "$2")"; fi
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
# closes — whether a pane or tab was closed since herdr.log was emptied.
closes() { if grep -qE '^(pane|tab) close' "${ROOT}/herdr.log"; then echo closed; else echo "none closed"; fi; }
# dev is origin's default, so every story here branches from it.
git -C "${ROOT}/svc.git" symbolic-ref HEAD refs/heads/dev

# --- close --drop counts a failed build: story, close, story, close, story on one ready code story builds it
# as code, code, then escalate, each in a fresh worktree. Before each close the builder has committed
# and pushed story/x1, left an untracked file and opened a PR; the close clears them all away.
gh_stub; : > "${ROOT}/gh.log"
: > "${p}/.claude/swarm/config"
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
  run close x1 --drop >/dev/null
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
  [[ "${c}" == impossible ]] || holds+="$(val y1 kind)$(run reset y1 lift the hold >/dev/null && echo ok || echo failed) "
done
check "each build of y1 starts, and after each uncounted close its worktree, local and origin's story/y1 are gone" "ok ok ok |||" "${adds}${cleared}"
check "paused and cleared-on-error each hold y1 (kind: lead), and reset lifts each hold" "leadok leadok " "${holds}"
got="$(val y1 kind)|$(run reset y1 its Done when is fixed >/dev/null && echo ok || echo failed)"
check "close y1 impossible leaves it kind: lead; reset y1 succeeds, and then story y1 succeeds" "lead|ok|ok" \
  "${got}|$(run story y1 >/dev/null && echo ok || echo failed)"
rm -f "${b}/stories/x1.md" "${b}/stories/y1.md" "${ROOT}/prs.json"

# --- reconcile clears a story's build before the pull: once its PR merged always, closing its open
# builder first (in review, so the close counts nothing); once its PR closed unmerged only when no
# builder is open. built <slug> <n> — build the story, push story/<slug> and put it in review with PR <n>.
: > "${p}/.claude/swarm/config"
UR="https://github.com/o/svc/pull"
built() {
  item "${b}" "stories/$1.md" "status: ready" "kind: code" "repo: svc" "attempts: 1"
  run story "$1" >/dev/null
  "${GIT[@]}" -C "${ROOT}/svc-wt/$1" commit -q --allow-empty -m "$1" && "${GIT[@]}" -C "${ROOT}/svc-wt/$1" push -q origin "story/$1"
  run review "$1" "${UR}/$2" >/dev/null
}
fmv() { val "$@"; }   # <slug> <key>
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
goal_story "${q}/docs" qz "status: ready" "kind: code"; item "${q}/docs" stories/qy.md "status: ready" "kind: code" "epic: qe"
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
# With the board in the repo, every builder deletes its story file in its PR: a one-off (qz) and an
# epic's story (qy).
: > "${q}/.claude/swarm/config"
qrun story qy >/dev/null
check "with the board in the repo, a one-off's and an epic story's briefs say to delete the story file" "yes|yes" \
  "$(has "Delete docs/stories/qz.md in your PR, and nothing else under docs/stories/." "$(cat "${q}/.swarm/briefs/qz.md")")|$(
  has "Delete docs/stories/qy.md in your PR, and nothing else under docs/stories/." "$(cat "${q}/.swarm/briefs/qy.md")")"
rm -f "${b}"/stories/r[um][123].md

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
