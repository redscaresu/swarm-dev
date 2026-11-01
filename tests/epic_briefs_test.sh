#!/usr/bin/env bash
# epic_briefs_test.sh — an epic's check:, AGENTS.md's tagged rules and merge = agent in the briefs,
# the role a build gets (sonnet_share, escalate_after) and builder_subagent_model.
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
# The user's settings allow swarm.sh merge, so a conductor may start under merge = agent (merge_rule_stop).
mkdir -p "${CLAUDE_CONFIG_DIR}"; echo '{"permissions":{"allow":["Bash(swarm.sh merge *)"]}}' > "${CLAUDE_CONFIG_DIR}/settings.json"
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
# gh: logs every call; pr list prints ${ROOT}/prs.json, or no PRs; pr view <url> --json headRefOid
# prints ${ROOT}/head while that file exists, and any other pr view <url> gives the state on <url>'s
# line in ${ROOT}/pr-states.
gh_stub() {
  printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/gh"
  # shellcheck disable=SC2016 # the stub's own shell expands these
  printf '%s\n' 'echo "$*" >> "$H/gh.log"' 'case "$1 $2" in "pr list") cat "$H/prs.json" 2>/dev/null || echo "[]" ;;' \
    '  "pr view") [ -f "$H/head" ] && case " $* " in *" headRefOid "*) cat "$H/head"; exit 0 ;; esac' \
    '    echo "{\"state\":\"$(awk -v u="$3" '\''$1 == u { print $2 }'\'' "$H/pr-states")\"}" ;; esac' >> "${ROOT}/bin/gh"
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
# started_x <slug> — whether herdr started <slug>'s agent.
started_x() { if grep -q "^agent start $1 " "${ROOT}/herdr.log"; then echo started; else echo "not started"; fi; }

# --- An epic with a check:, in story mode: its story branches from the base and runs the check
# before its PR; its conductor's brief. From here on dev is origin's default, so every story's base.
git -C "${ROOT}/svc.git" symbolic-ref HEAD refs/heads/dev
: > "${p}/.claude/swarm/config"
item "${b}" epics/f.md "status: active" "check: make test"
item "${b}" stories/f1.md "status: ready" "kind: code" "epic: f" "repo: svc"
run story f1 >/dev/null
brief="$(cat "${p}/.swarm/briefs/f1.md")"
check "an epic's story branches from the base (dev), opens its PR against it, runs the epic's check first, and asks for a mutation" "$(git -C "${ROOT}/svc.git" rev-parse dev)|yes|yes|yes" \
  "$(git -C "${ROOT}/svc-wt/f1" rev-parse HEAD)|$(has "Open the PR against \`dev\`" "${brief}")|$(has "Before you open the PR, also run the epic's check from the worktree root, and make it pass: \`make test\`" "${brief}")|$(has "prove each new or changed test can fail" "${brief}")"
check "the load rule caps load at 4 CPUs in all (docker run --cpus 4), cleans up as soon as the check ends, starts each process itself with a marker, checks at the end of a turn including orphans, and says the load in the PR" "yes|yes|yes|yes|yes|yes|yes" \
  "$(has "use at most 4 CPUs in all, across everything you run at once (\`docker run --cpus 4\`, or that many loops)" "${brief}")|$(has "Stop and remove what you started as soon as the check ends, with a trap that kills each recorded PID on EXIT, INT and TERM, and never leave it running between steps" "${brief}")|$(has "Start each load process itself, with no wrapper that forks, record each" "${brief}")|$(has "and give it a marker in its command line (an argument \`f1-load\`)" "${brief}")|$(has "Before you end any turn, check that none of it is still running, orphaned children too" "${brief}")|$(has "\`pgrep -f '[f]1-load'\`, killing what it finds by PID" "${brief}")|$(has "Say in the PR how you loaded the machine." "${brief}")"
check "the load rule names the leftover cleanup, the labelled container cleanup, no run_in_background, the runner cap with no project flag, a timeout no longer than the check, and the labelled docker check" "yes|yes|yes|yes|yes|yes|yes|yes" \
  "$(has "Remove leftovers from an earlier step first (\`docker rm -f \$(docker ps -aq --filter label=swarm=f1)\`)" "${brief}")|$(has "Name and label every container (\`--name f1-load-<n> --label swarm=f1\`), and remove them by that label in the trap, or use \`--rm\` and still remove them by name" "${brief}")|$(has "Never start load with run_in_background" "${brief}")|$(has "Cap your test runner's parallelism at 4 (its jobs or workers setting) too" "${brief}")|$(has "make test JOBS=4" "${brief}" | grep -q '^yes' && echo "project flag in brief" || echo yes)|$(has "no longer than the check and you kill it when the check ends" "${brief}")|$(has "or wrap each in \`timeout <seconds>\`" "${brief}")|$(has "\`docker ps --filter label=swarm=f1\`" "${brief}")"
check "a builder re-reads, before it pushes, the comments and docs naming what its diff changes, and fixes the stale ones" "yes" \
  "$(has "Before you push, for each function, command-line flag or error message the diff changes, re-read its header comment, error text and every README, doc, command or skill line that names it, and fix each one that no longer matches." "$(tr -s '[:space:]' ' ' <<< "${brief}")")"
# f1's review brief: its checklist names the docs-move-with-behaviour line, with swarm-dev's env:
# line as the example. The gh stub answers the PR's head with the worktree's while ${ROOT}/head
# exists; it is removed after the check. The review-f1 agent in the herdr stub, its events and f1's
# Done when stay for the checks below.
printf '%s\n' "" "**Done when:**" "- f1 works" >> "${b}/stories/f1.md"
git -C "${ROOT}/svc-wt/f1" rev-parse HEAD > "${ROOT}/head"
run review-agent f1 https://github.com/o/svc/pull/8 >/dev/null
rbrief="$(cat "${p}/.swarm/briefs/review-f1.md" 2>/dev/null)"
check "a review brief holds, as an exception to the scope rule, a PR that changes what a user runs, sees or must do and does not update its docs, where to report it, and the env: line as its example" "yes|yes" \
  "$(has "- Another exception to the scope rule: a PR that changes what a user runs, sees or must do and does not update README.md, AGENTS.md, docs/ or command text to match is a finding." "${rbrief}")|$(has "- Report it at the stale doc's file:line, or at the change when no doc covers it. Example: swarm-dev's env: line, which kept the old env allowlist in AGENTS.md and README.md after the code changed." "${rbrief}")"
rm -f "${ROOT}/head"
# The builder brief (_brief) of f1, whose worktree lacks scripts/select-tests.sh (only svc's own
# checkout has it), then has it: before the first push and after review fixes only the change's tests,
# then a push once they pass (select-tests.sh only where the builder works), and no self-matching pgrep poll.
selected="run only the tests mapped to the change (\`scripts/select-tests.sh --run\`), push once they pass, and let CI run the full suite."
own="Before your first push, and after review fixes, run only the project's own tests for the change, push once they pass, and let CI run the full suite."
nopoll="Never poll with a \`pgrep -f\` pattern that matches the poll's own command line or another poll's: such a loop finds itself or its twin and never ends. Poll the PIDs you recorded with \`ps -p <pids>\` (a later step's shell cannot \`wait\` on them), and find load by its \`f1-load\` marker with the bracketed pattern above, keeping the bare marker out of the poll's own command."
mkdir -p "${ROOT}/svc/scripts"; : > "${ROOT}/svc/scripts/select-tests.sh"
plain="$(run _brief f1 | tr -s '[:space:]' ' ')"
rm -r "${ROOT}/svc/scripts"; mkdir -p "${ROOT}/svc-wt/f1/scripts"; : > "${ROOT}/svc-wt/f1/scripts/select-tests.sh"
withsel="$(run _brief f1 | tr -s '[:space:]' ' ')"
rm -r "${ROOT}/svc-wt/f1/scripts"
check "a worktree without scripts/select-tests.sh (its repo's checkout has one): after review fixes the brief names the project's own tests and CI, and no select-tests" "yes|no" \
  "$(has "${own}" "${plain}")|$(grep -qF 'select-tests' <<< "${plain}" && echo yes || echo no)"
check "a worktree with scripts/select-tests.sh: before the first push and after review fixes the brief names select-tests.sh --run, a push once they pass, and CI" "yes|no" \
  "$(has "Before your first push, and after review fixes, ${selected}" "${withsel}")|$(grep -qF "${own}" <<< "${withsel}" && echo yes || echo no)"
# The builder acts when its own background test run ends, stops any run still going before a push by
# a route the guard allows, and after the PR opens pushes what is ready with further points in the body.
bgrun="Run a long test run in the background (Bash run_in_background), so its end wakes you, and act on its result when it ends."
stoprun="Before you push, stop any test run of yours still going: kill it by the PID you started (\`kill <pid>\`), or stop its background task (the guard refuses pkill and killall)."
oncepr="After the PR opens, push what is ready and put further points in the PR body, rather than a push for each: every push restarts CI."
check "the builder brief runs a long test run in the background and acts when it ends" "yes" "$(has "${bgrun}" "${plain}")"
check "the builder brief stops its own test run before a push, by PID or its background task, never pkill or killall" "yes" "$(has "${stoprun}" "${plain}")"
check "the builder brief, after the PR opens, pushes what is ready and puts further points in the PR body" "yes" "$(has "${oncepr}" "${plain}")"
check "with and without select-tests.sh, the brief forbids a pgrep -f poll that matches itself and points to the bracketed marker" "yes|yes" \
  "$(has "${nopoll}" "${plain}")|$(has "${nopoll}" "${withsel}")"
# A /goal message over GOAL_SEND_MAX, here through a long story path, is refused before the worktree
# exists, and nothing is sent.
printf '%s\n' "goal = 7" > "${p}/.claude/swarm/config"
gx="gx1-$(printf 'long%.0s' {1..60})"
goal_story "${b}" "${gx}" "status: ready" "kind: code" "repo: svc"
: > "${ROOT}/herdr.log"
out="$(run story "${gx}" || true)"
check "with goal on, a /goal message over GOAL_SEND_MAX fails naming the story, sends nothing, and leaves no worktree or branch" \
  "yes|nothing sent|no|no|no" \
  "$(has "${gx}: its /goal message is" "${out}")|$(grep -qE '^agent (start|prompt) ' "${ROOT}/herdr.log" && echo sent || echo "nothing sent")|$([[ -e "${ROOT}/svc-wt/${gx}" ]] && echo yes || echo no)|$(git -C "${ROOT}/svc" show-ref -q --verify "refs/heads/story/${gx}" && echo yes || echo no)|$(git -C "${ROOT}/svc.git" show-ref -q --verify "refs/heads/story/${gx}" && echo yes || echo no)"
rm -f "${b}/stories/${gx}.md"
# The project's AGENTS.md: its tagged rules (only those) reach a builder in another repo's worktree.
: > "${p}/.claude/swarm/config"
printf 'Untagged guidance.\nTag rules with <!-- lesson: <kind> -->.\nProve it. <!-- lesson: agents-kind -->\n' > "${p}/AGENTS.md"
printf 'A PROJECT RULE every agent reads. <!-- lesson: brief-kind -->' > "${p}/.claude/swarm/brief.md"   # no final newline
item "${b}" stories/g1.md "status: ready" "kind: code" "repo: svc"
run story g1 >/dev/null
gbrief="$(cat "${p}/.swarm/briefs/g1.md")"
check "with tagged rules, a builder gets no rules check step" "no" "$(grep -q "Rules checked:" <<< "${gbrief}" && echo yes || echo no)"
# commit_trailers: the brief names each trailer, one per line.
printf '%s\n' "commit_trailers = Co-Authored-By: Ann <a@x.io> ; Signed-off-by: Bo <b@x.io>" > "${p}/.claude/swarm/config"
item "${b}" stories/t1.md "status: ready" "kind: code" "repo: svc"
run story t1 >/dev/null
check "with commit_trailers set, a builder's brief names each trailer for every commit" \
  $'End every commit message with these trailers, one per line:\nCo-Authored-By: Ann <a@x.io>\nSigned-off-by: Bo <b@x.io>' \
  "$(grep -A2 '^End every commit message' "${p}/.swarm/briefs/t1.md")"
check "without commit_trailers, a brief names none" "no" "$(grep -q '^End every commit message' "${p}/.swarm/briefs/g1.md" && echo yes || echo no)"
# Why: an org that requires every commit and merge GPG-signed sets sign_commits = true.
# Boards outside swarm-dev and infrafactory set this key, so checking those two configs is not
# enough to remove it.
# sign_commits = true: the builder's and the conductor's brief each carry the sign rule; unset, neither does.
SIGN="Sign every commit and merge with -S. If signing fails, stop and report that you are blocked; never commit unsigned."
printf '%s\n' "sign_commits = true" > "${p}/.claude/swarm/config"
item "${b}" stories/s1.md "status: ready" "kind: code" "repo: svc"
run story s1 >/dev/null
run conduct f >/dev/null || true
check "with sign_commits = true, a builder's and a conductor's brief carry the sign rule" "yes|yes" \
  "$(has "${SIGN}" "$(cat "${p}/.swarm/briefs/s1.md")")|$(has "${SIGN}" "$(cat "${p}/.swarm/briefs/conduct-f.md")")"
: > "${p}/.claude/swarm/config"
run conduct f >/dev/null || true
check "without sign_commits, neither a builder's nor a conductor's brief says to sign" "no|no" \
  "$(grep -qF -- "-S" "${p}/.swarm/briefs/g1.md" && echo yes || echo no)|$(grep -qF -- "-S" "${p}/.swarm/briefs/conduct-f.md" && echo yes || echo no)"
check "the builder's brief says what to do on wait-pr's other exit 2s, ending with a report, never a loop" "yes|yes" \
  "$(has "Its other exit 2s print why: on a timeout or no check runs, read the checks once (\`gh pr checks <PR URL>\`), fix a workflow that never started, else run wait-pr again; on a gh error, run it again. If it ends the same way twice, stop and" "$(cat "${p}/.swarm/briefs/f1.md")")|$(has "If it ends the same way twice, stop and say so in your reply." "$(cat "${p}/.swarm/briefs/f1.md")")"
check "the builder briefs wait on CI only with wait-pr, never a loop of their own" "yes|yes" \
  "$(has "<PR URL>\` (in the background), never a loop of your own: on exit 1 fix the red check; on a conflict, do as above." "$(cat "${p}/.swarm/briefs/f1.md")")|$(has "<PR URL>\` (in the background), never a loop of your own" "$(cat "${p}/.swarm/briefs/g1.md")")"
# Why: right after its own push GitHub can still report the old head, whose green ends an unpinned
# wait-pr before the pushed head ran a check. A builder pins its worktree's head.
check "the builder's wait-pr is pinned to its worktree's head" "yes|yes" \
  "$(has "wait-pr --head \"\$(git rev-parse HEAD)\" <PR URL>\` (in the background)" "$(cat "${p}/.swarm/briefs/f1.md")")|$(has "wait-pr --head \"\$(git rev-parse HEAD)\" <PR URL>\` (in the background)" "$(cat "${p}/.swarm/briefs/g1.md")")"
check "the builder's brief reads a head the PR never got as its branch having moved: pull it by name, then wait on the new HEAD" "yes|yes" \
  "$(has "the PR's branch is past your checkout (a merge GitHub made, or a push that did not land): pull it (\`git pull --ff-only origin story/f1\`)" "$(cat "${p}/.swarm/briefs/f1.md")")|$(has "push, and wait again on the new HEAD." "$(cat "${p}/.swarm/briefs/f1.md")")"
# clash_brief <brief> — the clash rule (per repo), the merge-base-in rule (a nudge sent once a wait on
# the builder returns, sent again after a wait that sent nothing; a closed builder started again), then the old file-level wording. The pass rule is the review agent's.
clash_brief() {
  local b; b="$(tr -s '[:space:]' ' ' <<< "$1")"
  echo "$(has "Two stories clash only when their \`touches\` name the same file in the same repo and the same first word of a part (\`file:part\`), or when both name the bare file (no \`:part\`). A bare file does not clash with a part of it. A part's first word skips a leading \`§\`, \`#\`, \"the\", \"a\" or \"an\". Otherwise both build at once" "${b}")|$(has "A builder whose PR conflicts with its base merges the base in, resolves it, re-runs the tests and pushes. A conflict never sends a story back to \`ready\`" "${b}")|$(has "Send it with \`swarm.sh wait --stall --idle <slug> && swarm.sh tell <slug> nudge <file>\` in the background, never as findings, which would count as a review round." "${b}")|$(has "when its wait sent nothing, send it again the same way once you have dealt with what the wait printed (after \`auth\`, once you have told the builder to resume). If the story has no builder (closed after \`swarm.sh review\`), start one in its worktree with \`swarm.sh agent <tab> <slug> <worktree> <role> <brief>\`" "${b}")|$(grep -qF "do not overlap" <<< "${b}" && echo old || echo gone)"
}
check "with merge = human, the conductor builds stories that share a file but no symbol at once, and has a conflicted PR's builder merge the base in" \
  "yes|yes|yes|yes|gone" "$(clash_brief "$(cat "${p}/.swarm/briefs/conduct-f.md")")"
check "the conductor brief's story --strict rule says the same part or the bare file, never the same function or file" "yes|gone" \
  "$(has "touches the same part (by its first word) of a file, or both name the bare file. On a refusal" "$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/conduct-f.md")")|$(grep -qF "the same function or file" "${p}/.swarm/briefs/conduct-f.md" && echo old || echo gone)"
# A could-not-reach tell refusal is final, in the conductor's brief and the lead's /swarm command alike.
TELL_FINAL="A \`could not reach <name>:\` refusal from \`swarm.sh tell\` is final: the agent has no pane, or its session has ended, and the refusal names who acts on it. List the story under no agent"
check "the conductor brief and commands/swarm.md say a could-not-reach tell refusal is final: list the story under no agent, never tell it again" "yes|yes" \
  "$(has "${TELL_FINAL} in your report and never tell it again." "$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/conduct-f.md")")|$(has "${TELL_FINAL} and never tell it again." "$(tr -s '[:space:]' ' ' < "$(dirname "${SWARM}")/../commands/swarm.md")")"
# startable_brief <brief> — the startable rule after a merge, after each wait (its inbox pass first) and
# after the last inbox pass (three times), the last pass's go-back, and no wording that starts only what unblock readied.
startable_brief() {
  local b; b="$(tr -s '[:space:]' ' ' <<< "$1")"
  # shellcheck disable=SC2016 # the backticks are the brief's
  echo "$(grep -oF "run \`swarm.sh unblock --startable f\`, and start each story it prints as \`startable:\` (every ready story of this epic whose build has not started, whether or not this unblock readied it) that clashes with no running one, with \`swarm.sh story --strict <slug>\`. It reads the board as reconcile last left it, and never pulls. Skip a story you closed in this wave (the give-up rule starts it again in a later one), one the give-up rule says not to start again, and one a \`not held:\` line left \`ready\` for the lead. Never start a line that ends \`(its PR <url> was closed unmerged)\`: list it in your report for the lead." <<< "${b}" | wc -l | tr -d ' ')|$(has "If that last pass read a note, then run \`swarm.sh unblock --startable f\`" "${b}")|$(has "Do this before that wait's \`swarm.sh unblock --startable\` run (above), so one run starts what the notes made ready too." "${b}")|$(has "and after a builder opens a PR, run \`swarm.sh unblock --startable f\`" "${b}")|$(has "If that starts a builder, do not write the report: go back to waiting." "${b}")|$(grep -qE 'start what it readies|it prints as `ready:`|starts? (only )?(the )?stories (its own )?unblock readie' <<< "${b}" && echo limited || echo no)"
}
check "with merge = human, the conductor starts every ready story of the epic with no build after a merge and after a note, not only what unblock printed" \
  "3|yes|yes|yes|yes|no" "$(startable_brief "$(cat "${p}/.swarm/briefs/conduct-f.md")")"
# hands_off <brief> — a conductor's brief leaves each story's PR to its review agent, which waits for
# green, merges or hands over: no swarm.sh wait-pr step, no green rule, no merge --head, and no close
# after a review (of the review agent, of the builder after swarm.sh review, or after reconcile's).
# Each count is 0 on a brief that leaves it out; one that carries the conductor's old review and merge
# steps again drives a PR beside its review agent, and this goes red. The one close of a review agent
# left is the stop rule's, on a finish: line, once no agent work is left (FINISH_CLOSE): it is cut out first.
# shellcheck disable=SC2016 # the backticks are the brief's
FINISH_CLOSE='that `herdr agent list` still lists as idle, with `swarm.sh close review-<slug>` (leave a working one: it is still handing its PR on, and reconcile or tidy closes it), then write your report.'
hands_off() {
  local b; b="$(tr -s '[:space:]' ' ' <<< "$1")"; b="${b//"${FINISH_CLOSE}"/}"
  printf '%s|' "$(grep -c 'swarm.sh wait-pr' <<< "${b}" || true)" "$(grep -c 'A PR is green only when' <<< "${b}" || true)" \
    "$(grep -c 'swarm.sh merge --head' <<< "${b}" || true)" "$(grep -c 'swarm.sh close review-' <<< "${b}" || true)" \
    "$(grep -c 'Reconcile has closed the builder' <<< "${b}" || true)"
  # shellcheck disable=SC2016 # the backticks are the brief's
  grep -c 'swarm.sh review <slug> <PR URL>` and `swarm.sh close <slug>`' <<< "${b}" || true
}
HANDS_OFF="0|0|0|0|0|0"
# report_rules <brief> <finish scope> — the conductor's report rules: never while agent work is left,
# on a finish: line close each review-<slug> left and then report, and a lead-blocked story listed for
# the user, holding nothing up; and the old rule, which let it report while a review agent still owned
# a PR (gone). A conductor that reports early leaves that PR with nobody to act on its escalations: if
# a brief drops any of these, or brings the old sentence back, this goes red.
report_rules() {
  local b; b="$(tr -s '[:space:]' ' ' <<< "$1")"
  # shellcheck disable=SC2016 # the backticks are the brief's
  printf '%s|%s|%s|%s|%s\n' "$(has "Never write your report while agent work is left:" "${b}")" \
    "$(has "A merge or handover note that ends \`finish: $2 has no agent work left\` says none is: on it, close each \`review-<slug>\` of yours ${FINISH_CLOSE}" "${b}")" \
    "$(has "A story blocked only on a \`kind: lead\` story, a hand step, or stories that themselves wait on the lead that way (or in a depends_on cycle) waits on the user, not on you: list it in your report under Waits on the user; it holds nothing up." "${b}")" \
    "$(has "only once no agent work is left (the stop rule above): write your report" "${b}")" \
    "$(grep -qF "Write your report only when no story of this epic that is yours to start is ready and none is running" <<< "${b}" && echo there || echo gone)"
}
REPORT_RULES="yes|yes|yes|yes|gone"
# merge_note <brief> <unblock arg> — the startable pass after each inbox pass, cued by a merge note.
merge_note() {
  # shellcheck disable=SC2016 # the backticks are the brief's
  has "A note in your inbox that a story's PR just merged is the cue to start what that merge made ready. After each inbox pass, run \`swarm.sh unblock --startable $2\`, and start each story it prints as \`startable:\`" "$(tr -s '[:space:]' ' ' <<< "$1")"
}
run conduct --backlog >/dev/null || true
check "with merge = human, neither the epic's nor the backlog's conductor brief has a wait-pr step, a green rule, a merge or a close after a review" "${HANDS_OFF}|${HANDS_OFF}" \
  "$(hands_off "$(cat "${p}/.swarm/briefs/conduct-f.md")")|$(hands_off "$(cat "${p}/.swarm/briefs/conduct-backlog.md")")"
# Under merge = human an HLD's merge grant lets a review agent merge and turn the base red: if the
# human-mode brief drops the fix-main rule, the lead's note asks for a build the brief never allows.
# Under merge = human the user may take days to merge a handed-over PR: if the brief drops the close on
# the handover note, every such builder stays open that long.
# shellcheck disable=SC2016 # the backticks are the brief's
check "with merge = human, both briefs close the builder on the handover note unless an HLD grants merge" "yes|yes" \
  "$(has 'unless `swarm.sh grants <PR URL>` lists `merge` (the review agent then merges it, and the merge closes the builder), close the story'"'"'s builder with a bare `swarm.sh close <slug>`' "$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/conduct-f.md")")|$(has 'unless `swarm.sh grants <PR URL>` lists `merge` (the review agent then merges it, and the merge closes the builder), close the story'"'"'s builder with a bare `swarm.sh close <slug>`' "$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/conduct-backlog.md")")"
check "with merge = human, both briefs start a fix-main story at once whatever their scope, and its review agent from the builder's reply" "yes|yes|yes|yes" \
  "$(has "start its builder at once with \`swarm.sh story --strict fix-main-<short sha>\`, ahead of every other story and whatever your scope" "$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/conduct-f.md")")|$(has "once its builder replies with the PR URL." "$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/conduct-f.md")")|$(has "start its builder at once with \`swarm.sh story --strict fix-main-<short sha>\`, ahead of every other story and whatever your scope" "$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/conduct-backlog.md")")|$(has "once its builder replies with the PR URL." "$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/conduct-backlog.md")")"
check "with merge = human, both conductor briefs start every startable story after each inbox pass, and the epic's still puts the epic in review" "yes|yes|yes" \
  "$(merge_note "$(cat "${p}/.swarm/briefs/conduct-f.md")" f)|$(merge_note "$(cat "${p}/.swarm/briefs/conduct-backlog.md")" --backlog)|$(has "swarm.sh review <epic> <every PR URL still waiting>" "$(cat "${p}/.swarm/briefs/conduct-f.md")")"
check "with merge = human, the epic's and the backlog's conductor briefs report only once no agent work is left, on a finish: line after closing their review agents left" \
  "${REPORT_RULES}|${REPORT_RULES}" \
  "$(report_rules "$(cat "${p}/.swarm/briefs/conduct-f.md")" "epic f")|$(report_rules "$(cat "${p}/.swarm/briefs/conduct-backlog.md")" "the backlog")"
docs="$(cd "$(dirname "${SWARM}")/../docs" && cat method.md reference*.md | tr -s '[:space:]' ' ')"
check "method.md and docs/reference*.md § Building give the clash rule, the merge-base-in rule and the pass rule" "2|2|2|0|1" \
  "$(grep -oF "Two stories clash only when their \`touches\` name the same file in the same repo and the same first word of a part (\`file:part\`), or when both name the bare file. A bare file does not clash with a part of it. A part's first word skips a leading \`§\`, \`#\`, \"the\", \"a\" or \"an\". Otherwise both build at once" <<< "${docs}" | wc -l | tr -d ' ')|$(grep -oF "A builder whose PR conflicts with its base merges its base in, resolves it, reruns the tests and pushes; a conflict never sends a story back to \`ready\`" <<< "${docs}" | wc -l | tr -d ' ')|$(grep -oF "whose findings are all declined is a pass" <<< "${docs}" | wc -l | tr -d ' ')|$(grep -oF "round 4" <<< "${docs}" | wc -l | tr -d ' ')|$(grep -oF "logged with \`log-finding --declined <reason> --reviewer <who>\`: \`nit\` for a nit, an edge case or a low-value point, \`out-of-scope\` or \`wrong\` where they apply" <<< "${docs}" | wc -l | tr -d ' ')"
cfg="$(cat "${p}/.claude/swarm/config")"; printf '%s\n' "merge = agent" > "${p}/.claude/swarm/config"
run conduct f >/dev/null || true
brief="$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/conduct-f.md")"
run conduct --backlog >/dev/null || true
check "with merge = agent, neither the epic's nor the backlog's conductor brief has a wait-pr step, a green rule, a merge or a close after a review" "${HANDS_OFF}|${HANDS_OFF}" \
  "$(hands_off "${brief}")|$(hands_off "$(cat "${p}/.swarm/briefs/conduct-backlog.md")")"
check "with merge = agent, both conductor briefs leave the merge to the review agent and start every startable story after each inbox pass" "yes|yes|yes|yes" \
  "$(has "A story's review agent merges its PR itself, with \`swarm.sh merge\`: never merge a story's PR yourself." "${brief}")|$(has "A story's review agent merges its PR itself, with \`swarm.sh merge\`: never merge a story's PR yourself." "$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/conduct-backlog.md")")|$(merge_note "${brief}" f)|$(merge_note "$(cat "${p}/.swarm/briefs/conduct-backlog.md")" --backlog)"
check "with merge = agent, a costs: money PR is listed for the user, and a wave with a cleared-on-error close or a give-up starts nothing more" "yes|yes" \
  "$(has "List each such PR (\`swarm.sh status\` shows it as \`awaiting your merge (costs money)\`, \`(protected path)\` or \`(dropped base lines)\`) in your report under Waits on the user." "${brief}")|$(has "After a cleared-on-error close or a give-up, start nothing more in this wave." "${brief}")"
check "with merge = agent, the same clash rule and merge-base-in rule" "yes|yes|yes|yes|gone" "$(clash_brief "${brief}")"
# A merge that turns the base red writes a fix-main story outside every epic, and watch says no fix-main
# PR opened: if the brief drops the out-of-scope start or the review agent from the builder's reply,
# the base stays red.
check "with merge = agent, both briefs start a fix-main story at once whatever their scope, and its review agent from the builder's reply" "yes|yes|yes|yes" \
  "$(has "start its builder at once with \`swarm.sh story --strict fix-main-<short sha>\`, ahead of every other story and whatever your scope" "${brief}")|$(has "once its builder replies with the PR URL." "${brief}")|$(has "start its builder at once with \`swarm.sh story --strict fix-main-<short sha>\`, ahead of every other story and whatever your scope" "$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/conduct-backlog.md")")|$(has "once its builder replies with the PR URL." "$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/conduct-backlog.md")")"
check "with merge = agent, the conductor starts every ready story of the epic with no build after a merge and after a note, not only what unblock printed" \
  "3|yes|yes|yes|yes|no" "$(startable_brief "${brief}")"
check "with merge = agent, the epic's and the backlog's conductor briefs report only once no agent work is left, on a finish: line after closing their review agents left" \
  "${REPORT_RULES}|${REPORT_RULES}" \
  "$(report_rules "${brief}" "epic f")|$(report_rules "$(cat "${p}/.swarm/briefs/conduct-backlog.md")" "the backlog")"
# A broken base is the one stop while agent work is left, and the merge rule's report sentence names it.
check "with merge = agent, the epic conductor's report rules stop it on a broken base, and count a fix-main story it started until its PR merges" "yes|yes|yes|no" \
  "$(has "The one exception: stop and report at once when CI on the base timed out, or is red with no \`fix-main:\` line." "${brief}")|$(has "Write your report only as the stop rule below says: never while agent work is left, unless CI on the base timed out" "${brief}")|$(has "kept by a close with one PR and still to be reviewed (a fix-main story you started counts as running until its PR merges)." "${brief}")|$(grep -qF "nothing ready is left" <<< "${brief}" && echo yes || echo no)"
check "the brief makes no claim about the block-red-pr-merge hook, which never sees swarm.sh's own gh calls" "no" \
  "$(grep -qF "block-red-pr-merge" <<< "${brief}" && echo yes || echo no)"
printf '%s\n' "escalate_after = 0" > "${p}/.claude/swarm/config"
run conduct f >/dev/null || true
brief="$(cat "${p}/.swarm/briefs/conduct-f.md")"
check "with escalate_after = 0, the conductor stops retrying a story that failed twice and reports it to the lead" "yes|yes|no" \
  "$(has "model: escalation is off (escalate_after = 0), so once a story has failed twice" "${brief}")|$(has "do not start it again: report it to the lead." "${brief}")|$(grep -q "picks Fable for build" <<< "${brief}" && echo yes || echo no)"
# With the ladder on, a failed step-up is the lead's through wait --lead: the conductor leaves it out of
# its report. If the brief again says to list it for the lead, this goes red.
printf '%s\n' "escalate_ladder = sonnet,opus,fable" > "${p}/.claude/swarm/config"
run conduct f >/dev/null || true
para="$(awk -v RS= '/step-up failed: <slug>/' "${p}/.swarm/briefs/conduct-f.md" | tr -s '[:space:]' ' ')"
check "with escalate_ladder set, a failed step-up is left alone and out of the report: wait --lead tells the lead" "yes|no" \
  "$(has "A \`step-up failed: <slug>\` line means the step-up stopped after closing the builder. Leave that story alone: \`wait --lead\` tells the lead, so it does not go in your report." "${para}")|$(grep -qiE "list[^.]*for the lead" <<< "${para}" && echo yes || echo no)"
printf '%s\n' "${cfg}" > "${p}/.claude/swarm/config"
check "a builder gets AGENTS.md's tagged rules, and only those" "yes|yes|no" \
  "$(has "<!-- lesson: agents-kind -->" "$(cat "${p}/.swarm/briefs/g1.md")")|$(has "A PROJECT RULE every agent reads." "$(cat "${p}/.swarm/briefs/g1.md")")|$(grep -q "Untagged guidance\|Tag rules with" "${p}/.swarm/briefs/g1.md" && echo yes || echo no)"
check "a brief without a final newline keeps its rules apart" "yes" "$(grep -q '^Prove it. <!-- lesson: agents-kind -->' "${p}/.swarm/briefs/g1.md" && echo yes || echo no)"
run close g1 >/dev/null; rm -f "${b}/stories/g1.md" "${p}/AGENTS.md"
# A project that set lessons_file = CLAUDE.md (or .claude/CLAUDE.md) keeps those files' tagged rules.
printf '%s\n' "lessons_file = CLAUDE.md" > "${p}/.claude/swarm/config"
printf 'Untagged.\nKeep it. <!-- lesson: claude-kind -->\n' > "${p}/CLAUDE.md"
printf 'Name it. <!-- lesson: dot-claude-kind -->\n' > "${p}/.claude/CLAUDE.md"
item "${b}" stories/g2.md "status: ready" "kind: code" "repo: svc"
run story g2 >/dev/null
check "a builder gets CLAUDE.md's and .claude/CLAUDE.md's tagged rules, and only those" "yes|yes|no" \
  "$(has "Keep it. <!-- lesson: claude-kind -->" "$(cat "${p}/.swarm/briefs/g2.md")")|$(has "Name it. <!-- lesson: dot-claude-kind -->" "$(cat "${p}/.swarm/briefs/g2.md")")|$(grep -q "^Untagged.$" "${p}/.swarm/briefs/g2.md" && echo yes || echo no)"
run close g2 >/dev/null; rm -f "${b}/stories/g2.md" "${p}/CLAUDE.md" "${p}/.claude/CLAUDE.md"
# CLAUDE.md a symlink to AGENTS.md: each tagged rule reaches the brief once.
printf 'Prove it. <!-- lesson: agents-kind -->\n' > "${p}/AGENTS.md"; ln -s AGENTS.md "${p}/CLAUDE.md"
item "${b}" stories/g3.md "status: ready" "kind: code" "repo: svc"
run story g3 >/dev/null
check "a rule in AGENTS.md and a CLAUDE.md that links to it reaches the brief once" "1" \
  "$(grep -c '^Prove it. <!-- lesson: agents-kind -->$' "${p}/.swarm/briefs/g3.md")"
run close g3 >/dev/null; rm -f "${b}/stories/g3.md" "${p}/CLAUDE.md" "${p}/AGENTS.md"
check "base prints a repo's base" "dev" "$(run base svc)"
rm -f "${b}"/epics/e.md "${b}"/epics/f.md "${b}"/stories/s*.md "${b}/stories/o1.md" "${b}/stories/f1.md"
: > "${p}/.claude/swarm/config"

# --- sonnet_share: a story's role is its kind, code-risky for risk: high, and with sonnet_share = N,
# code-sonnet for the other code stories marked easy: true whose slug's cksum mod N is 0 (r0-code, r4-f,
# r4-g, the s4-* slugs; r4-a and r4-b are not). Each build's role, model and effort are read off its agents.tsv line.
row() { awk -F'\t' -v n="$1" '$3 == n { r = $2 " " $5 " " $6 } END { print r }' "${p}/.swarm/agents.tsv"; }
build() { # <slug> <front-matter line>... — build a ready story in svc, then print its agents.tsv line
  local s="$1"; shift
  item "${b}" "stories/${s}.md" "status: ready" "repo: svc" "$@"
  run story "${s}" >/dev/null || true   # a start that fails shows as the FAIL, not an abort
  row "${s}"
}
: > "${p}/.claude/swarm/config"
check "sonnet_share = 0 (the default): roles resolve as before" \
  "code opus high|code-risky opus xhigh|docs sonnet medium|chore haiku medium" \
  "$(build r0-code "kind: code")|$(build r0-risky "kind: code" "risk: high")|$(build r0-docs "kind: docs")|$(build r0-chore "kind: chore")"
item "${b}" stories/r0-verify.md "status: ready" "repo: svc" "kind: verify"
rc=0; out="$(run story r0-verify)" || rc=$?
check "story refuses a verify story, naming code, docs and chore, and starts no agent, worktree or branch" "fail|yes|not started|no|no|no" \
  "$([[ ${rc} -ne 0 ]] && echo fail || echo ok)|$(has "r0-verify has kind: verify; an agent builds only code, docs or chore" "${out}")|$(started_x r0-verify)|$(
  [[ -e "${ROOT}/svc-wt/r0-verify" ]] && echo yes || echo no)|$(git -C "${ROOT}/svc" show-ref -q --verify refs/heads/story/r0-verify && echo yes || echo no)|$(
  git -C "${ROOT}/svc.git" show-ref -q --verify refs/heads/story/r0-verify && echo yes || echo no)"
echo "sonnet_share = 4" >> "${p}/.claude/swarm/config"
check "sonnet_share = 4: code stories split by cksum mod 4, and a sampled one starts on code-sonnet sonnet high" \
  "code opus high|code opus high|code-sonnet sonnet high|code-sonnet sonnet high" \
  "$(build r4-a "kind: code" "easy: true")|$(build r4-b "easy: true")|$(build r4-f "kind: code" "easy: true")|$(build r4-g "kind: code" "easy: true")"
check "sonnet_share = 4: risk: high stays code-risky, and docs and chore are unchanged" \
  "code-risky opus xhigh|docs sonnet medium|chore haiku medium" \
  "$(build s4-risky4 "kind: code" "risk: high")|$(build s4-docs4 "kind: docs")|$(build s4-chore2 "kind: chore")"
printf '2026-10-13\tcode-sonnet\ts4-retry2\tclaude\tsonnet\thigh\tsess-r\n' >> "${p}/.swarm/agents.tsv"
check "only a first attempt is sampled: a slug already in agents.tsv goes back to code" "code opus high" \
  "$(build s4-retry2 "kind: code" "easy: true")"

# --- escalate_after: a story an agent builds whose attempts: (absent is 0) reaches escalate_after
# (default 2; 0 is off) is built as escalate, ahead of code-risky and code-sonnet. Read through _role.
role() { local s="$1"; shift; item "${b}" "stories/${s}.md" "status: ready" "$@"; run _role "${s}"; }
ladder() { # <slug> <attempts>... -- <front-matter line>... — _role at each attempts:, space-separated
  local s="$1" n ns=() out=(); shift
  while [[ "$1" != -- ]]; do ns+=("$1"); shift; done; shift
  for n in "${ns[@]}"; do out+=("$(role "${s}" "attempts: ${n}" "$@")"); done
  echo "${out[*]}"
}
printf '%s\n' "sonnet_share = 4" > "${p}/.claude/swarm/config"
check "escalate_after = 2 (the default): every kind an agent builds escalates at attempts: 2" \
  "code code escalate|code-risky code-risky escalate|code-sonnet code-sonnet escalate|docs docs escalate|chore chore escalate" \
  "$(ladder e4-a 0 1 2 -- "kind: code")|$(ladder e4-a 0 1 2 -- "kind: code" "risk: high")|$(ladder e4-f 0 1 2 -- "kind: code" "easy: true")|$(ladder e4-a 0 1 2 -- "kind: docs")|$(ladder e4-a 0 1 2 -- "kind: chore")"
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
  "$(build e4-g "kind: code" "easy: true" "attempts: 2")"
item "${b}" stories/e4-bad.md "status: ready" "repo: svc" "kind: code" "attempts: two"; : > "${p}/.swarm/events.tsv"
check "swarm.sh story at attempts: two fails, and its events.tsv line carries the reason" "fails|yes" \
  "$(run story e4-bad >/dev/null && echo starts || echo fails)|$(has "attempts must be a non-negative whole number, not 'two'" "$(cut -f5 "${p}/.swarm/events.tsv")")"
rm -f "${b}/stories/e4-bad.md"
echo "escalate_after = 0" >> "${p}/.claude/swarm/config"
check "escalate_after = 0: attempts 0, 1, 2 and 5 never escalate" "code code code code|code-risky code-risky code-risky code-risky" \
  "$(ladder e4-a 0 1 2 5 -- "kind: code")|$(ladder e4-a 0 1 2 5 -- "kind: code" "risk: high")"
printf '%s\n' "escalate_after = 3" > "${p}/.claude/swarm/config"
check "escalate_after = 3: attempts: 2 is code, 3 is escalate" "code escalate" "$(ladder e4-a 2 3 -- "kind: code")"
rm -f "${b}/stories/e4-a.md" "${b}/stories/e4-f.md"

# --- swarm-dev's rules.md (project_rules): on a project with no brief, AGENTS.md or CLAUDE.md, the
# builder's and the conductor's briefs carry every line of it; with a brief and a lesson: marker, it
# comes before both. If project_rules stops printing it, or story_brief or conduct_brief stops calling
# project_rules, this goes red.
RULES="$(dirname "${SWARM}")/../rules.md"
rm -f "${p}/.claude/swarm/brief.md" "${p}/AGENTS.md" "${p}/CLAUDE.md" "${p}/.claude/CLAUDE.md"
: > "${p}/.claude/swarm/config"
item "${b}" epics/rf.md "status: active"
item "${b}" stories/rf1.md "status: ready" "kind: code" "epic: rf" "repo: svc"
run story rf1 >/dev/null
run conduct rf >/dev/null || true
# missing_rules <brief file> — the non-empty lines of rules.md the brief lacks, as whole lines.
missing_rules() { local l n=0; while IFS= read -r l; do [[ -z "${l}" ]] || grep -qxF -- "${l}" "$1" || n=$((n + 1)); done < "${RULES}"; echo "${n}"; }
check "with no brief of the project's, the builder's and the conductor's briefs carry every line of rules.md" "0|0" \
  "$(missing_rules "${p}/.swarm/briefs/rf1.md")|$(missing_rules "${p}/.swarm/briefs/conduct-rf.md")"
check "the conductor's heading over the rules names swarm-dev's rules and the project's" "yes" \
  "$(has "swarm-dev's rules and the project's, which every builder also gets:" "$(cat "${p}/.swarm/briefs/conduct-rf.md")")"
printf 'RF-BRIEF-RULE\n' > "${p}/.claude/swarm/brief.md"; printf 'RF-MARKED <!-- lesson: rf-kind -->\n' > "${p}/AGENTS.md"
order="$(run _brief rf1 | awk -v first="$(grep -m1 '^- ' "${RULES}")" -v last="$(tail -1 "${RULES}")" '
  $0 == first { f = NR } $0 == last { l = NR } /^RF-BRIEF-RULE$/ { b = NR } /^RF-MARKED / { m = NR }
  END { print (f && f < l && l < b && b < m) ? "rules, brief, marker" : "out of order: " f " " l " " b " " m }')"
check "with a brief and a lesson: marker, rules.md's text comes before the brief, and the brief before the marker" "rules, brief, marker" "${order}"
# A plugin copy with no rules.md: the brief is still written, and stderr names the missing file.
mkdir -p "${ROOT}/norules"; cp -R "$(dirname "${SWARM}")" "${ROOT}/norules/bin"
nr_err="$(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${ROOT}/norules/bin/swarm.sh" _brief rf1 2>&1 >/dev/null)"
check "with no rules.md in the plugin, building a brief says so on stderr" "yes" \
  "$(has "swarm: ${ROOT}/norules/rules.md is missing, so this brief carries none of swarm-dev's rules" "${nr_err}")"
rm -rf "${ROOT}/norules"
rm -f "${p}/.claude/swarm/brief.md" "${p}/AGENTS.md" "${b}/epics/rf.md" "${b}/stories/rf1.md"
# rules.md itself: at least fifteen rule lines, each with a Why: line under it, and each rule this
# test names found by its own phrase on a rule line, so a rule swapped for filler goes red.
check "rules.md has at least fifteen rule lines, each followed by its Why: line" "yes|0" \
  "$( (( $(grep -c '^- ' "${RULES}") >= 15 )) && echo yes || echo "no, $(grep -c '^- ' "${RULES}")")|$(
  awk '/^- / { if (r) n++; r = 1; next } r && /^  Why: / { r = 0; next } { if (r) n++; r = 0 } END { print n + r + 0 }' "${RULES}")"
RULE_PHRASES=("shared upstream cause" "narrow sample is not a conclusion" "against a stand-in (a mock, a sibling API, a narrower sample)"
  "scoped to one file, when the defect class spans many" "new code path must enforce every rule the existing paths enforce"
  "zero or empty value shown to a person must say what it means" "repair path that changes something must say what it did"
  "allowlist of its fields" "never shares the fail-closed guard" "exact records" "test can fail" "by the contract it checks"
  "ongoing LLM cost" "Never generate load" "any session log")
for w in "${RULE_PHRASES[@]}"; do
  check "rules.md has the rule: ${w}" "1" "$(grep '^- ' "${RULES}" | grep -cF -- "${w}" || true)"
done

# --- builder_subagent_model: a building role's start carries it, a planning or conducting role's does not.
printf '%s\n' "builder_subagent_model = haiku" > "${p}/.claude/swarm/config"
sub='"CLAUDE_CODE_SUBAGENT_MODEL":"haiku","CLAUDE_CODE_SUBAGENT_MODEL_FORCE":"1"}}'
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
: > "${p}/.claude/swarm/config"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
