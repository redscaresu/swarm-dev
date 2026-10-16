#!/usr/bin/env bash
# stacked_test.sh — stacked builds: unblock readies a story whose open parents all have open PRs,
# story starts it on their branches (or refuses and blocks it again), story --strict leaves its own
# parents out of the overlap check, review holds it while a parent is on the board (and merge then
# refuses it), and the conductor briefs say so. The repo is a local bare remote; herdr, gh and claude
# are stubs on PATH. gh pr list answers from ${ROOT}/open/<branch>, one URL, or fails with ${ROOT}/ghfail.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
# No trust file here, so require_trusted lets the fixture agents start whatever ~/.claude.json says.
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects"
# swarm.sh's own merges commit too: a known identity, and none of the user's settings (signing).
printf '[user]\n\tname = t\n\temail = t@t\n[init]\n\tdefaultBranch = main\n' > "${ROOT}/gitconfig"
export GIT_CONFIG_GLOBAL="${ROOT}/gitconfig" GIT_CONFIG_NOSYSTEM=1
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }
hasnt() { if grep -qF -- "$1" <<< "$2"; then echo "has '$1'"; else echo no; fi; }
item() { # <board> <path> <front-matter line>...
  local path="$1/$2" title; shift 2
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

# herdr: logs every call; each new pane is w:<n>, each tab t<n>; agent start and list track agents.
mkdir -p "${ROOT}/bin" "${ROOT}/open"
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
next() { n=$(($(cat "$H/n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/n"; }
case "$1 $2" in
  "workspace list")   echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  "tab create")       next; echo "t$n $(echo "$*" | sed 's/.*--label \([^ ]*\).*/\1/')" >> "$H/tabs"
                      echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "tab list")         awk 'BEGIN { printf "{\"result\":{\"tabs\":[" }
                           { printf "%s{\"tab_id\":\"%s\",\"label\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                           END { print "]}}" }' "$H/tabs" 2>/dev/null || echo '{"result":{"tabs":[]}}' ;;
  "agent prompt")     echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent start")      echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')" >> "$H/agents" ;;
  "agent list")       awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                           { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                           END { print "]}}" }' "$H/agents" 2>/dev/null || echo '{"result":{"agents":[]}}' ;;
  "pane close"|"tab close") p=$3; [ "$1" = tab ] && p="w:${3#t}"
                      [ -e "$H/agents" ] && awk -v p="$p" '$2 != p' "$H/agents" > "$H/agents.tmp" && mv "$H/agents.tmp" "$H/agents" ;;
esac
EOF
# gh: logs every call. pr list reads ${ROOT}/open/<head, / as ->, the open PR's URL: with --jq it
# prints the URL (or nothing), as gh's jq would; without, the JSON list close reads. For merge, every
# PR is open with one green check and any merge method, so only the board stops it before gh pr merge,
# which fails.
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'EOF'
echo "$*" >> "$H/gh.log"
[ ! -e "$H/ghfail" ] || exit 1
case "$1 $2" in
  "pr list") jq=""; while [ $# -gt 0 ]; do [ "$1" = --head ] && h="$2"; [ "$1" = --jq ] && jq=1; shift; done
             f="$H/open/$(echo "$h" | tr / -)"
             if [ -n "$jq" ]; then [ ! -e "$f" ] || cat "$f"
             elif [ -e "$f" ]; then echo "[{\"number\":1,\"state\":\"OPEN\",\"url\":\"$(cat "$f")\",\"autoMergeRequest\":null}]"
             else echo '[]'; fi ;;
  "pr view") echo '{"state":"OPEN","headRefOid":"1111111111111111111111111111111111111111","baseRefName":"main","changedFiles":1}' ;;
  "repo view") echo '{"squashMergeAllowed":true,"mergeCommitAllowed":true,"rebaseMergeAllowed":true}' ;;
  "pr merge") exit 1 ;;
  api*) case "$*" in
          *check-runs*) echo '{"total_count":1,"check_runs":[{"name":"t","status":"completed","conclusion":"success"}]}' ;;
          *status*) echo '{"total_count":0,"statuses":[]}' ;;
        esac ;;
esac
EOF
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh"

# The repo svc: main with f.txt, and a bare origin. The project is not a git repo; its stories name svc.
git init -q --bare "${ROOT}/svc.git"
git clone -q "${ROOT}/svc.git" "${ROOT}/svc" 2>/dev/null
echo base > "${ROOT}/svc/f.txt"; git -C "${ROOT}/svc" add f.txt; git -C "${ROOT}/svc" commit -q -m init; git -C "${ROOT}/svc" push -q origin main
git init -q "${ROOT}/other"   # another repo in repos_dir
p="${ROOT}/proj"; b="${p}/docs"
mkdir -p "${p}/.claude/swarm"; : > "${p}/.claude/swarm/config"
run() { (cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
outside() { (cd "${p}" && env -u SWARM_PROJECT -u HERDR_ENV PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
URL=https://github.com/o/svc/pull
# parent <slug> <file> <text> [open] — story/<slug> pushed with one commit writing <text> to <file>;
# with open, an open PR on it (${URL}/<slug>).
parent() {
  git -C "${ROOT}/svc" checkout -q -b "story/$1" main
  echo "$3" > "${ROOT}/svc/$2"; git -C "${ROOT}/svc" add "$2"; git -C "${ROOT}/svc" commit -q -m "$1"
  git -C "${ROOT}/svc" push -q origin "story/$1"; git -C "${ROOT}/svc" checkout -q main
  [[ -z "${4:-}" ]] || echo "${URL}/$1" > "${ROOT}/open/story-$1"
}
head_of() { git -C "${ROOT}/svc" rev-parse "story/$1"; }
st() { sed -n 's/^status: //p' "${b}/stories/$1.md"; }
exists() { if [[ -e "$1" ]]; then echo yes; else echo no; fi; }
branch() { if git -C "${ROOT}/svc" show-ref -q --verify "refs/heads/story/$1"; then echo yes; else echo no; fi; }

# --- Start: one parent with an open PR.
item "${b}" stories/p.md "status: ready" "kind: code" "repo: svc"
item "${b}" stories/child.md "status: blocked" "kind: code" "repo: svc" "depends_on: [p]"
parent p p.txt p open
check "unblock readies a child whose one parent has an open PR, stacked on it" "ready: child (stacked on p)|ready" \
  "$(run unblock)|$(st child)"
run story child >/dev/null || true   # a start that fails shows as the FAIL, not an abort
check "story makes a worktree whose HEAD is origin/story/p's head" "$(head_of p)" \
  "$(git -C "${ROOT}/svc-wt/child" rev-parse HEAD 2>&1)"
check "events.tsv gains stacked child, ok (on p)" "ok (on p)" \
  "$(awk -F'\t' '$2 == "stacked" && $3 == "child" { print $5 }' "${p}/.swarm/events.tsv")"
brief="$(cat "${p}/.swarm/briefs/child.md" 2>&1 || true)"
# shellcheck disable=SC2016 # the backticks are the brief's
check "the child's brief says to open the PR against the base, with Merge after and the parent's PR URL" "yes" \
  "$(has 'Open your PR against `main` all the same, with `Merge after '"${URL}/p"'` in its body.' "${brief}")"

# --- Two parents: the worktree holds both heads; conflicting parents leave nothing behind.
item "${b}" stories/q.md "status: ready" "kind: code" "repo: svc"
item "${b}" stories/two.md "status: blocked" "kind: code" "repo: svc" "depends_on: [p, q]"
parent q q.txt q open
check "unblock readies a child of two parents with open PRs" "ready: two (stacked on p q)" "$(run unblock)"
run story two >/dev/null || true
check "the worktree contains both parents' heads" "yes|yes" \
  "$(git -C "${ROOT}/svc-wt/two" merge-base --is-ancestor "$(head_of p)" HEAD && echo yes || echo no)|$(
  git -C "${ROOT}/svc-wt/two" merge-base --is-ancestor "$(head_of q)" HEAD && echo yes || echo no)"
item "${b}" stories/r1.md "status: ready" "kind: code" "repo: svc"
item "${b}" stories/r2.md "status: ready" "kind: code" "repo: svc"
item "${b}" stories/clash.md "status: blocked" "kind: code" "repo: svc" "depends_on: [r1, r2]"
parent r1 f.txt one open; parent r2 f.txt two open
run unblock >/dev/null || true
rc=0; out="$(run story clash)" || rc=$?
check "parents whose branches conflict fail story naming both, with no worktree and no story/clash branch" "fail|yes|yes|no|no" \
  "$([[ ${rc} -ne 0 ]] && echo fail || echo ok)|$(has "origin/story/r2" "${out}")|$(has "origin/story/r1" "${out}")|$(
  exists "${ROOT}/svc-wt/clash")|$(branch clash)"

# --- A parent ready with no open PR, blocked, or in another repo, or gh failing, keeps the child blocked.
item "${b}" stories/nopr.md "status: ready" "kind: code" "repo: svc"
item "${b}" stories/held.md "status: blocked" "kind: code" "repo: svc"
item "${b}" stories/away.md "status: ready" "kind: code" "repo: other"
item "${b}" stories/gh.md "status: ready" "kind: code" "repo: svc"
parent nopr n.txt n; parent held h.txt h open; parent gh g.txt g open; echo "${URL}/away" > "${ROOT}/open/story-away"
for s in nopr held away gh; do item "${b}" "stories/on-${s}.md" "status: blocked" "kind: code" "repo: svc" "depends_on: [${s}]"; done
touch "${ROOT}/ghfail"; out="$(run unblock)"; rm "${ROOT}/ghfail"
check "a gh failure keeps the child blocked" "|blocked" "$(grep 'on-gh' <<< "${out}" || true)|$(st on-gh)"
check "a parent with no open PR, a blocked one, or one in another repo keeps the child blocked" "|blocked|blocked|blocked" \
  "$(run unblock | grep -E 'on-(nopr|held|away)' || true)|$(st on-nopr)|$(st on-held)|$(st on-away)"

# --- story --strict leaves the child's own parents out of the overlap check, and no other story.
item "${b}" stories/pa.md "status: review" "kind: code" "repo: svc" "prs: ${URL}/pa" "touches: [bin/x.sh:f]"
item "${b}" stories/kid.md "status: blocked" "kind: code" "repo: svc" "depends_on: [pa]" "touches: [bin/x.sh:f]"
item "${b}" stories/u.md "status: review" "kind: code" "repo: svc" "prs: ${URL}/u" "touches: [bin/x.sh:f]"
parent pa pa.txt pa open
check "a parent in review with a prs: line readies its child" "yes" "$(has "ready: kid (stacked on pa)" "$(run unblock)")"
rc=0; out="$(run story --strict kid)" || rc=$?
check "an unrelated no-epic story in review that touches the function still makes --strict refuse" "fail|yes|no" \
  "$([[ ${rc} -ne 0 ]] && echo fail || echo ok)|$(has "u (epic none) is open and touches bin/x.sh:f" "${out}")|$(hasnt "pa (epic none)" "${out}")"
rm "${b}/stories/u.md"
rc=0; out="$(run story --strict kid)" || rc=$?
check "story --strict succeeds when only its no-epic parent, in review, touches the same function" "0|yes" \
  "${rc}|$(exists "${ROOT}/svc-wt/kid")"

# --- The parent's PR closes after unblock readied the child: story refuses, makes nothing, blocks it.
item "${b}" stories/pc.md "status: ready" "kind: code" "repo: svc"
item "${b}" stories/late.md "status: blocked" "kind: code" "repo: svc" "depends_on: [pc]"
parent pc c.txt c open
run unblock >/dev/null || true
rm "${ROOT}/open/story-pc"
rc=0; out="$(run story late)" || rc=$?
check "story exits non-zero naming pc, makes no worktree or branch, and leaves late blocked" "fail|yes|no|no|blocked|no" \
  "$([[ ${rc} -ne 0 ]] && echo fail || echo ok)|$(has "pc has no open PR on story/pc" "${out}")|$(exists "${ROOT}/svc-wt/late")|$(
  branch late)|$(st late)|$(grep -q '^agent start late ' "${ROOT}/herdr.log" && echo yes || echo no)"

# --- Hold: while p is on the board, review holds the child and merge refuses it.
rc=0; out="$(run review child "${URL}/9")" || rc=$?
check "review child exits non-zero naming p, sets it blocked with no prs:, and keeps its worktree and branch" \
  "fail|yes|blocked|no|yes|yes" \
  "$([[ ${rc} -ne 0 ]] && echo fail || echo ok)|$(has "held: child waits for p to merge; once it has, merge origin/main into it and review it again" "${out}")|$(
  st child)|$(grep -q '^prs:' "${b}/stories/child.md" && echo yes || echo no)|$(exists "${ROOT}/svc-wt/child")|$(branch child)"
: > "${ROOT}/gh.log"
rc=0; out="$(outside merge "${URL}/9")" || rc=$?
check "merge on the held child's PR refuses before gh pr merge runs" "fail|no" \
  "$([[ ${rc} -ne 0 ]] && echo fail || echo ok)|$(grep -q '^pr merge' "${ROOT}/gh.log" && echo yes || echo no)"
run close child >/dev/null || true
check "a bare close of the held child's builder counts nothing and keeps its build" "|yes|yes" \
  "$(sed -n 's/^attempts: //p' "${b}/stories/child.md")|$(exists "${ROOT}/svc-wt/child")|$(branch child)"
check "unblock does not ready the held child while p's PR is open" "|blocked" \
  "$(run unblock | grep -E '^ready: child( |$)' || true)|$(st child)"
rm "${b}/stories/p.md"
check "once p's file is gone, unblock readies it" "yes" "$(grep -qx 'ready: child' <<< "$(run unblock)" && echo yes || echo no)"
run review child "${URL}/9" >/dev/null || true
check "and review child puts it in review" "review|${URL}/9" "$(st child)|$(sed -n 's/^prs: //p' "${b}/stories/child.md")"

# --- The conductor briefs: start stacked stories, hold, and close (human) or keep (agent) the builder.
run conduct --backlog >/dev/null || true
cb="$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/conduct-backlog.md")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "the merge = human brief drops 'stays blocked until the human merges', and names stacked starts, the hold and the bare close" \
  "no|yes|yes|yes" \
  "$(hasnt "stays blocked until the human merges" "${cb}")|$(has 'A story printed `(stacked on <parents>)` starts on its parents'"'"' branches' "${cb}")|$(
  has 'When `swarm.sh review` holds a stacked story instead (`held: <slug> waits for <p> to merge`)' "${cb}")|$(
  has 'close its builder with a bare `swarm.sh close <slug>`, which counts nothing for a blocked story and keeps its build' "${cb}")"
run close conduct-backlog >/dev/null || true
echo "merge = agent" > "${p}/.claude/swarm/config"
run conduct --backlog >/dev/null || true
cb="$(tr -s '[:space:]' ' ' < "${p}/.swarm/briefs/conduct-backlog.md")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "the merge = agent brief keeps a held child's builder open until unblock readies it again" "yes|yes" \
  "$(has 'leave its builder open' "${cb}")|$(has 'Once its parents merge, `swarm.sh unblock` readies it again' "${cb}")"

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
