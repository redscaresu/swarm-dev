#!/usr/bin/env bash
# review_test.sh — merge = human and the review status: the merge guard on every agent, `review`,
# `reconcile`, the gate in `next`, and `findings`; also how an agent starts (a name already
# taken, a failed start, codex's update check). gh and herdr are stubs on PATH.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
ROOT="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
# No trust file here, so require_trusted lets the fixture agents start whatever ~/.claude.json says.
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
fails=0
GIT=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main)
U="https://github.com/o/svc/pull"

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }

item() { # <board> <path> <front-matter line>...
  local path="$1/$2" title; shift 2
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

# Stubs. gh answers from fixture files; herdr accepts everything and logs its arguments.
mkdir -p "${ROOT}/bin" "${ROOT}/gh"
cat > "${ROOT}/bin/gh" <<EOF
#!/bin/sh
F="${ROOT}/gh"
EOF
cat >> "${ROOT}/bin/gh" <<'EOF'
case "$1 $2" in
  "pr view") st=$(awk -v u="$3" '$1 == u { print $2 }' "$F/prs"); [ -n "$st" ] || exit 1
             echo "{\"state\":\"$st\"}"; exit 0 ;;
  "repo view") case " $* " in *" -q "*) echo o/svc ;; *) echo '{"nameWithOwner":"o/svc"}' ;; esac; exit 0 ;;
  "pr list") while [ $# -gt 0 ]; do [ "$1" = -q ] && q="$2"; shift; done
             jq -r "$q" "$F/prlist.json"; exit 0 ;;
esac
case "$2" in
  repos/o/svc/pulls/7) echo '{"head":{"sha":"abc1234def"}}' ;;
  repos/o/svc/commits/abc1234def/check-runs*) cat "$F/runs.json" ;;
  repos/o/svc/check-runs/1/annotations*) cat "$F/annotations.json" ;;
  repos/o/svc/code-scanning/alerts*) cat "$F/alerts.json" ;;
  repos/o/svc/commits/head*/check-runs) while [ $# -gt 0 ]; do [ "$1" = -q ] && q="$2"; shift; done
             echo '{"check_runs":[{"status":"completed"}]}' | jq -r "$q" ;;
  *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
cat > "${ROOT}/bin/herdr" <<EOF
#!/bin/sh
echo "\$*" >> "${ROOT}/herdr.log"
EOF
cat >> "${ROOT}/bin/herdr" <<EOF
A="${ROOT}/agents.json"; F="${ROOT}/start-fails"; P="${ROOT}/panes.json"
EOF
cat >> "${ROOT}/bin/herdr" <<'EOF'
case "$1 $2" in
  "tab create")   echo '{"result":{"root_pane":{"pane_id":"w:1"}}}' ;;
  "pane split")   echo '{"result":{"pane":{"pane_id":"w:2"}}}' ;;
  "agent prompt") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent list")   if [ -f "$A" ]; then cat "$A"; else echo '{"result":{"agents":[]}}'; fi ;;
  "agent rename") if [ -f "$A" ]; then sed -i.bak "s/\"name\":\"$3\"/\"name\":\"$4\"/" "$A"; fi ;;
  "agent start")  if [ -f "$F" ]; then echo '{"error":{"code":"agent_name_taken"}}'; exit 1; fi ;;
  "pane list")    if [ -f "$P" ]; then cat "$P"; fi ;;
esac
EOF
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr"

p="${ROOT}/proj"; b="${p}/docs"
mkdir -p "${p}/.claude/swarm"; : > "${p}/.claude/swarm/config"
run() { (cd "${p}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
first() { printf '%s' "${1%%$'\n'*}"; }

# --- review: the item waits on a human merge, with its PRs on the board.
item "${b}" stories/a.md "status: ready" "kind: code" "epic: e1"
item "${b}" stories/n.md "status: blocked" "kind: code" "epic: e1" "blocked_by: [a]"
item "${b}" epics/e1.md "status: active"
run review a "${U}/1" >/dev/null
check "review sets the status and the PRs" "review|${U}/1" \
  "$(sed -n 's/^status: //p' "${b}/stories/a.md")|$(sed -n 's/^prs: //p' "${b}/stories/a.md")"
check "review refuses what is not a PR URL, and leaves the item alone" "yes|review|${U}/1" \
  "$(has 'not a PR URL' "$(run review a "https://example.com/x" || true)")|$(sed -n 's/^status: //p' "${b}/stories/a.md")|$(sed -n 's/^prs: //p' "${b}/stories/a.md")"

# --- next: a PR waiting on a human is a gate, and never restarts a conductor.
out="$(run next)"
check "a story in review is a gate, not conduct" "gate" "$(first "${out}")"
check "the gate names the PR to merge" "yes" "$(has "awaiting your merge: a ${U}/1" "${out}")"

# --- reconcile: finish when every PR merged; back to ready if one closed; else wait.
printf '%s\n' "${U}/1 MERGED" "${U}/2 CLOSED" "${U}/3 OPEN" "${U}/4 MERGED" > "${ROOT}/gh/prs"
item "${b}" stories/c.md "status: review" "kind: code" "prs: ${U}/2"
echo "prs: a line in the body" >> "${b}/stories/c.md"
item "${b}" epics/e2.md "status: review" "prs: ${U}/1 ${U}/3"
item "${b}" epics/e3.md "status: review" "prs: ${U}/1 ${U}/4"
out="$(run reconcile)"
check "a merged story is finished" "gone" "$([[ -e "${b}/stories/a.md" ]] && echo there || echo gone)"
check "a closed PR sends its story back to ready" "ready" "$(sed -n 's/^status: //p' "${b}/stories/c.md")"
check "its prs: line goes, and a body line like it stays" "prs: a line in the body" "$(grep '^prs:' "${b}/stories/c.md")"
check "reconcile says which PR closed" "yes" "$(has "back to ready: c (closed without merging: ${U}/2)" "${out}")"
check "an epic with one of two PRs merged stays in review" "review" "$(sed -n 's/^status: //p' "${b}/epics/e2.md")"
check "an epic with both PRs merged is finished" "gone" "$([[ -e "${b}/epics/e3.md" ]] && echo there || echo gone)"
check "its dependent unblocks once it is finished" "ready: n" "$(run unblock)"

# --- A board in the project repo: the merged PR took the story off itself. reconcile undoes its
# own review edit so the pull goes through, and if the pull cannot, keeps the item in review.
"${GIT[@]}" init -q --bare "${ROOT}/app.git"
"${GIT[@]}" clone -q "${ROOT}/app.git" "${ROOT}/app" 2>/dev/null
item "${ROOT}/app/docs" stories/r.md "status: ready" "kind: code"
item "${ROOT}/app/docs" stories/s.md "status: ready" "kind: code"
"${GIT[@]}" -C "${ROOT}/app" add docs && "${GIT[@]}" -C "${ROOT}/app" commit -q -m board
"${GIT[@]}" -C "${ROOT}/app" push -q origin main
"${GIT[@]}" clone -q "${ROOT}/app.git" "${ROOT}/pr"
"${GIT[@]}" -C "${ROOT}/pr" rm -q docs/stories/r.md && "${GIT[@]}" -C "${ROOT}/pr" commit -q -m "the PR"
inrepo() { (cd "${ROOT}/app" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
inrepo review r "${U}/1" >/dev/null
inrepo review s "${U}/4" >/dev/null
"${GIT[@]}" -C "${ROOT}/app" commit -q --allow-empty -m "diverged"
"${GIT[@]}" -C "${ROOT}/pr" push -q origin main
inrepo reconcile >/dev/null || true
check "a pull that fails keeps merged items in review, with their PRs" "review ${U}/1|review ${U}/4" \
  "$(sed -n 's/^status: //p;s/^prs: //p' "${ROOT}/app/docs/stories/r.md" | paste -sd' ' -)|$(sed -n 's/^status: //p;s/^prs: //p' "${ROOT}/app/docs/stories/s.md" | paste -sd' ' -)"
"${GIT[@]}" -C "${ROOT}/app" reset -q --keep HEAD~1
inrepo reconcile >/dev/null || true
gone() { if [[ -e "$1" ]]; then echo there; else echo gone; fi; }
check "the PR's own delete is pulled, and finish takes off what it left" "gone|gone|$(git -C "${ROOT}/app.git" rev-parse main)" \
  "$(gone "${ROOT}/app/docs/stories/r.md")|$(gone "${ROOT}/app/docs/stories/s.md")|$(git -C "${ROOT}/app" rev-parse HEAD)"

# --- The merge guard: every Claude agent starts unable to run gh pr merge, unless merge = agent.
"${GIT[@]}" init -q --bare "${ROOT}/svc.git"
"${GIT[@]}" clone -q "${ROOT}/svc.git" "${ROOT}/svc" 2>/dev/null
"${GIT[@]}" -C "${ROOT}/svc" commit -q --allow-empty -m init && "${GIT[@]}" -C "${ROOT}/svc" push -q origin main
start() { # <slug> — start a story with the stubs, and print herdr's agent start line
  item "${b}" "stories/$1.md" "status: ready" "kind: code" "repo: svc"
  (cd "${p}" && HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" story "$1" >/dev/null 2>&1)
  grep "^agent start $1 " "${ROOT}/herdr.log"
}
check "merge = human (the default) starts a story agent with gh pr merge disallowed" "yes" \
  "$(has '--disallowedTools Bash(gh pr merge:*)' "$(start g1)")"
echo "merge = agent" > "${p}/.claude/swarm/config"
check "merge = agent starts a story agent without the guard" "no" \
  "$(grep -q disallowedTools <<< "$(start g2)" && echo yes || echo no)"

# --- Starting an agent: a taken name, a failed start, codex's update check.
echo brief > "${ROOT}/brief.md"
agent() { # <name> <role> — start one agent with the stubs, and print swarm's output
  : > "${ROOT}/herdr.log"
  (cd "${p}" && HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" agent t "$1" "${p}" "$2" "${ROOT}/brief.md" 2>&1) || true
}
taken() { echo "{\"result\":{\"agents\":[{\"name\":\"lead\",\"agent_status\":\"$1\",\"pane_id\":\"w:9\"}]}}" > "${ROOT}/agents.json"; }
taken idle; agent lead lead >/dev/null
check "a finished agent holding the name is retired before the new one starts" "agent rename lead lead-done|agent start lead" \
  "$(grep -E '^agent (rename|start) ' "${ROOT}/herdr.log" | awk '{print $1, $2, $3, ($2 == "rename" ? $4 : "")}' | sed 's/ $//' | paste -sd'|' -)"
echo '{"result":{"agents":[{"name":"lead","agent_status":"idle"},{"name":"lead-done","agent_status":"idle"}]}}' > "${ROOT}/agents.json"
agent lead lead >/dev/null
check "a name reused a second time retires to the next free -done name" "agent rename lead lead-done2|agent start lead" \
  "$(grep -E '^agent (rename|start) ' "${ROOT}/herdr.log" | awk '{print $1, $2, $3, ($2 == "rename" ? $4 : "")}' | sed 's/ $//' | paste -sd'|' -)"
taken working; out=$(agent lead lead)
check "a working agent holding the name stops the start before any pane opens" "yes|no" \
  "$(has 'still working' "${out}")|$(grep -qE '^(tab create|pane split)' "${ROOT}/herdr.log" && echo yes || echo no)"
rm -f "${ROOT}/agents.json"; touch "${ROOT}/start-fails"; out=$(agent l2 lead)
check "a failed start closes its pane and shows herdr's error" "yes|yes" \
  "$(grep -q '^pane close ' "${ROOT}/herdr.log" && echo yes || echo no)|$(has agent_name_taken "${out}")"
rm -f "${ROOT}/start-fails"; agent cx codex >/dev/null
check "codex starts with its update check off" "yes" "$(has 'check_for_update_on_startup=false' "$(grep '^agent start cx ' "${ROOT}/herdr.log")")"

# --- status: each open pane's agent, an empty pane, and what waits on the user.
mkdir -p "${p}/.swarm/state"
printf '%s\n' 'w:5 lead' 'w:6 builder' 'w:7 gone' > "${p}/.swarm/state/t"
printf '%s\n' 'w:8 finished' >> "${p}/.swarm/state/t"
printf '%s\n' 'w:8 finished' > "${p}/.swarm/state/t-2"
echo '{"result":{"agents":[{"name":"builder","agent_status":"working","pane_id":"w:6"},{"name":"finished","agent_status":"idle","pane_id":"w:8"}]}}' > "${ROOT}/agents.json"
echo '{"result":{"panes":[{"pane_id":"w:5"},{"pane_id":"w:6"},{"pane_id":"w:8"}]}}' > "${ROOT}/panes.json"
item "${b}" stories/ls.md "status: ready" "kind: lead"
out=$(cd "${p}" && HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" status 2>&1)
check "status shows a pane whose agent never started as empty" "yes" \
  "$(grep -qE '^  lead +EMPTY' <<< "${out}" && echo yes || echo "no, got: ${out}")"
check "status shows a working agent, and leaves out a pane closed by hand" "yes|no" \
  "$(grep -qE '^  builder +working' <<< "${out}" && echo yes || echo no)|$(grep -q 'gone' <<< "${out}" && echo yes || echo no)"
check "status lists a lead story under Waiting on you" "yes" "$(has 'lead: ls' "$(sed -n '/^Waiting on you/,/^Next/p' <<< "${out}")")"
all=$(cd "${p}" && HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" status --all 2>&1)
check "status counts an idle agent instead of listing it, and --all lists it" "yes|no|yes" \
  "$(has '1 idle or done' "${out}")|$(grep -qE '^  finished ' <<< "${out}" && echo yes || echo no)|$(grep -qE '^  finished +idle' <<< "${all}" && echo yes || echo no)"
rm -f "${ROOT}/agents.json" "${ROOT}/panes.json" "${p}/.swarm/state/t" "${p}/.swarm/state/t-2" "${b}/stories/ls.md"

# --- findings: a success check can still carry a failure note (the CodeQL case), and open alerts.
echo '{"check_runs":[{"id":1,"name":"CodeQL","conclusion":"success","output":{"annotations_count":1}},{"id":2,"name":"test","conclusion":"success","output":{"annotations_count":0}}]}' > "${ROOT}/gh/runs.json"
printf '%s\n' '[{"annotation_level":"failure","path":"a.py","start_line":3,"message":"Clear-text logging of sensitive information\nmore"}]' > "${ROOT}/gh/annotations.json"
echo '[{"number":5,"rule":{"id":"py/clear-text-logging","severity":"error","security_severity_level":"high"},"most_recent_instance":{"location":{"path":"a.py","start_line":3},"message":{"text":"This logs a password."}}}]' > "${ROOT}/gh/alerts.json"
out="$(run findings svc 7)"
check "findings prints a failure note on a successful check" "yes" \
  "$(has "check CodeQL (success): failure a.py:3 Clear-text logging of sensitive information" "${out}")"
check "findings prints open code-scanning alerts" "yes" "$(has "alert #5 high py/clear-text-logging a.py:3 This logs a password." "${out}")"

# --- watch --epic: a conductor wakes only for its own epic's PRs. Two epics share a repo; the other
# epic's PR comes first and has finished its checks too.
w="${ROOT}/watch"
mkdir -p "${w}/.claude/swarm" "${ROOT}/wrepos"
echo "repos_dir = ${ROOT}/wrepos" > "${w}/.claude/swarm/config"
git init -q "${ROOT}/wrepos/svc" && git -C "${ROOT}/wrepos/svc" remote add origin https://github.com/o/svc
item "${w}/docs" epics/mine.md "status: active"
item "${w}/docs" epics/other.md "status: active"
item "${w}/docs" stories/a.md "status: ready" "kind: code" "epic: mine" "repo: svc"
item "${w}/docs" stories/b.md "status: ready" "kind: code" "epic: other" "repo: svc"
cat > "${ROOT}/gh/prlist.json" <<'EOF'
[{"number": 1, "headRefName": "story/b", "headRefOid": "head1", "mergeable": "MERGEABLE", "updatedAt": "2026-01-01T00:00:00Z"},
 {"number": 2, "headRefName": "epic/mine", "headRefOid": "head2", "mergeable": "MERGEABLE", "updatedAt": "2026-01-01T00:00:00Z"}]
EOF
check "watch --epic skips another epic's PR in the same repo" "o/svc #2 epic/mine checks finished on head2" \
  "$(cd "${w}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" watch --epic mine 2>&1)"
# One PR per epic: the stories are finished (deleted) before the epic PR opens, so only the epic's
# repos: line still names the repo.
rm "${w}/docs/stories/a.md" "${w}/.swarm/state/watch-seen"
printf -- '---\nstatus: active\nrepos: svc\n---\n\n# mine\n' > "${w}/docs/epics/mine.md"
check "watch --epic finds the repo from the epic's repos: line once its stories are gone" "o/svc #2 epic/mine checks finished on head2" \
  "$(cd "${w}" && env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" watch --epic mine 2>&1)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
