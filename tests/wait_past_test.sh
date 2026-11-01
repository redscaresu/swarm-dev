#!/usr/bin/env bash
# wait_past_test.sh — swarm.sh wait [--stall] --past <sha> <slug>: besides every way wait ends, it ends
# with `pushed <new sha>` and 0 on the first poll at which the story's worktree is clean at a commit
# other than <sha> that the PR's head names, for a Claude builder and for one herdr answers for (no
# recorded session). gh is asked for the PR's head only on a poll where the worktree has moved. --past
# refuses a short sha, a conductor, a review agent, --lead, --until-report and a name with no story
# or no worktree, and waits on nothing.
# herdr is a stub on PATH: its agent list shows each agent working (idle once ${ROOT}/idle exists),
# and its agent wait runs ${ROOT}/onwait-<N> on its N-th call (the push or the idle turn, landing inside
# that slice), then sleeps out its timeout and fails with a timeout error. The claude stub lists the
# sessions in ${ROOT}/claude.json. gh's PR head is the file ${ROOT}/head, and gh logs each call; with
# ${ROOT}/ghhang its pr view hangs for a minute, and with ${ROOT}/ghdirty it leaves s1's worktree with an
# uncommitted file before it answers. A wait's timeout is 2250 ms, two slices and a bit of
# 1000 ms: with shorter slices a loaded machine can spend the whole timeout before the first slice starts.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects" SWARM_STALL_POLL_MS=1000
export CLAUDE_STUB_AGENTS="${ROOT}/claude.json"
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
GIT=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main)
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

cat > "${STUB_BIN}/herdr" <<EOF
#!/bin/sh
H="${ROOT}"
EOF
cat >> "${STUB_BIN}/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
case "$1 $2" in
  "agent list") st=working; [ -e "$H/idle" ] && st=idle
                printf '{"result":{"agents":[{"name":"s1","agent_status":"%s","pane_id":"w:1"},{"name":"s2","agent_status":"%s","pane_id":"w:2"}]}}\n' "$st" "$st" ;;
  "agent wait") n=$(($(cat "$H/waits" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/waits"
                [ ! -x "$H/onwait-$n" ] || "$H/onwait-$n"
                [ -e "$H/idle" ] && { echo '{"result":{"agent":{"agent_status":"idle"}}}'; exit 0; }
                ms=$(echo "$*" | sed -n 's/.*--timeout \([0-9]*\).*/\1/p')
                sleep "$(awk -v m="${ms:-0}" 'BEGIN { printf "%.3f", m / 1000 }')"
                echo '{"error":{"code":"timeout"}}' >&2; exit 1 ;;
esac
EOF
cat > "${STUB_BIN}/gh" <<EOF
#!/bin/sh
echo "\$*" >> "${ROOT}/gh.log"
case "\$1 \$2" in
  "pr view") [ ! -e "${ROOT}/ghhang" ] || sleep 60
             [ ! -e "${ROOT}/ghdirty" ] || echo x > "${ROOT}/svc-wt/s1/dirty"
             cat "${ROOT}/head" ;;
  *) echo '[]' ;;
esac
EOF
chmod +x "${STUB_BIN}/herdr" "${STUB_BIN}/gh"

# A repo svc, stories s1 (a Claude builder) and s2 (no recorded session: herdr answers for it), each
# with a worktree on story/<slug> at OLD, which the PR's head names; s3 has a story but no worktree.
"${GIT[@]}" init -q --bare "${ROOT}/svc.git"
"${GIT[@]}" clone -q "${ROOT}/svc.git" "${ROOT}/svc" 2>/dev/null
"${GIT[@]}" -C "${ROOT}/svc" commit -q --allow-empty -m init && "${GIT[@]}" -C "${ROOT}/svc" push -q origin main
OLD="$(git -C "${ROOT}/svc" rev-parse HEAD)"
p="${ROOT}/proj"; b="${p}/docs"
mkdir -p "${p}/.claude/swarm" "${b}/stories" "${p}/.swarm/state"; : > "${p}/.claude/swarm/config"
for s in s1 s2 s3; do
  printf '%s\n' --- "status: review" "kind: code" "repo: svc" "touches: [bin/${s}.sh:fn]" --- "" "# ${s}" > "${b}/stories/${s}.md"
done
for s in s1 s2; do "${GIT[@]}" -C "${ROOT}/svc" worktree add -q -b "story/${s}" "${ROOT}/svc-wt/${s}" origin/main; done
printf 'w:1 s1\nw:2 s2\n' > "${p}/.swarm/state/wait-past"   # this project's panes
printf '2026-11-01\tcode\ts1\tclaude\topus\thigh\tsess-s1\n2026-11-01\tcode\ts2\tclaude\topus\thigh\t-\n' > "${p}/.swarm/agents.tsv"

# fresh — the PR and both worktrees at OLD and clean, the s1 session busy, herdr working, and no logs or hooks.
fresh() {
  local s
  for s in s1 s2; do "${GIT[@]}" -C "${ROOT}/svc-wt/${s}" reset -q --hard "${OLD}"; rm -f "${ROOT}/svc-wt/${s}/dirty"; done
  echo "${OLD}" > "${ROOT}/head"
  echo '[{"sessionId":"sess-s1","status":"busy"}]' > "${ROOT}/claude.json"
  rm -f "${ROOT}/idle" "${ROOT}/ghhang" "${ROOT}/ghdirty" "${ROOT}/waits" "${ROOT}"/onwait-* "${ROOT}/herdr.log" "${ROOT}/gh.log"
}
# commit <slug> — a new commit in the story's worktree; prints its sha. push <slug> — that commit, and the PR's head names it.
commit() { "${GIT[@]}" -C "${ROOT}/svc-wt/$1" commit -q --allow-empty -m fix; git -C "${ROOT}/svc-wt/$1" rev-parse HEAD; }
push() { commit "$1" > "${ROOT}/head"; }
# hook <n> <commands> — run <commands> inside herdr's n-th agent wait (the n-th slice).
hook() { printf '#!/bin/sh\n%s\n' "$2" > "${ROOT}/onwait-$1"; chmod +x "${ROOT}/onwait-$1"; }
# waitrc <args...> — "<stdout>|exit <rc>"; stderr goes to ${ROOT}/wait.err.
waitrc() {
  local out rc=0
  out="$(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 PATH="${STUB_BIN}:${PATH}" bash "${SWARM}" wait "$@" 2>"${ROOT}/wait.err")" || rc=$?
  echo "${out}|exit ${rc}"
}
# count <pattern> <log> — how many lines of <log> match; 0 when the log was never written.
count() { if [[ -f "$2" ]]; then grep -c -- "$1" "$2" || true; else echo 0; fi; }
# hook_push <slug> — a hook's body that does what push does, from herdr's agent wait.
hook_push() { echo "git -c user.name=t -c user.email=t@t -C '${ROOT}/svc-wt/$1' commit -q --allow-empty -m fix && git -C '${ROOT}/svc-wt/$1' rev-parse HEAD > '${ROOT}/head'"; }

# A busy Claude builder that pushes during the first slice: the read after it ends the wait.
fresh; hook 1 "$(hook_push s1)"
got="$(waitrc --stall --past "${OLD}" s1 2250)"
check "a push in the first slice, the session busy, ends wait --stall --past with pushed <new sha>" \
  "pushed $(cat "${ROOT}/head")|exit 0" "${got}"
check "it ends on the first poll after the push: one herdr agent wait" "1" "$(count '^agent wait' "${ROOT}/herdr.log")"
check "gh is asked for the PR's head only on the poll after the push, never while the worktree was at <sha>" \
  "1" "$(count '^pr view' "${ROOT}/gh.log")"

# A push made before the wait starts: the first read ends it, before any slice.
fresh; push s1
got="$(waitrc --stall --past "${OLD}" s1 2250)"
check "a push made before the wait starts ends it on its first read" "pushed $(cat "${ROOT}/head")|exit 0|0" \
  "${got}|$(count '^agent wait' "${ROOT}/herdr.log")"

# A commit the PR's head does not name yet (not pushed) does not end the wait.
fresh; commit s1 > /dev/null
got="$(waitrc --stall --past "${OLD}" s1 2250)"
check "a commit not yet pushed: the wait times out busy" "busy|exit 1" "${got}"

# A gh that hangs on a moved worktree is cut at the wait's time left (a second at least), not
# PAST_GH_WAIT: its two reads (the first, and the one after the first slice, by then past the deadline)
# take PAST_GH_MIN (5 s) each, not 30 s.
fresh; commit s1 > /dev/null; touch "${ROOT}/ghhang"; t0=${SECONDS}
got="$(waitrc --stall --past "${OLD}" s1 2250)"
check "a hung gh read is cut at the wait's time left: the 2250 ms wait times out busy within 40 s" "busy|exit 1|yes" \
  "${got}|$( (( SECONDS - t0 < 40 )) && echo yes || echo "no, $((SECONDS - t0))s")"

# A pushed commit with uncommitted changes on top does not end it either.
fresh; push s1; echo x > "${ROOT}/svc-wt/s1/dirty"
got="$(waitrc --stall --past "${OLD}" s1 2250)"
check "a pushed commit with uncommitted changes in the worktree: the wait times out busy, and gh is never asked" \
  "busy|exit 1|0" "${got}|$(count '^pr view' "${ROOT}/gh.log")"

# The builder edits while gh reads the PR's head: the head names the commit, but the worktree is no
# longer clean once gh answers, so it is not pushed.
fresh; push s1; touch "${ROOT}/ghdirty"
got="$(waitrc --stall --past "${OLD}" s1 2250)"
check "an edit made while gh answers: the wait times out busy, not pushed" "busy|exit 1" "${got}"

# No new commit and the session stays busy: a timeout, with no gh call at all.
fresh
got="$(waitrc --stall --past "${OLD}" s1 2250)"
check "no new commit: the wait times out busy, and gh is never asked" "busy|exit 1|0" "${got}|$(count '^pr view' "${ROOT}/gh.log")"

# No new commit, and the session goes idle: idle and 0, as plain wait --stall.
fresh; hook 1 "echo '[{\"sessionId\":\"sess-s1\",\"status\":\"idle\"}]' > '${ROOT}/claude.json'"
got="$(waitrc --stall --past "${OLD}" s1 2250)"
check "no new commit and the session going idle ends the wait with idle, as plain wait --stall" \
  "idle|exit 0|0" "${got}|$(count '^pr view' "${ROOT}/gh.log")"

# The herdr-only path (s2 has no recorded session): the same check after each step, the first read
# and the last step too. 2250 ms in 1000 ms steps is three steps: 1000, 1000 and the last 250.
fresh; hook 1 "$(hook_push s2)"
got="$(waitrc --stall --past "${OLD}" s2 2250)"
check "herdr-only, herdr working: a push in the first step ends the wait with pushed <new sha> after that step" \
  "pushed $(cat "${ROOT}/head")|exit 0|1" "${got}|$(count '^agent wait' "${ROOT}/herdr.log")"
fresh; push s2
got="$(waitrc --stall --past "${OLD}" s2 2250)"
check "herdr-only: a push made before the wait starts ends it on its first read" \
  "pushed $(cat "${ROOT}/head")|exit 0|0" "${got}|$(count '^agent wait' "${ROOT}/herdr.log")"
fresh; hook 3 "$(hook_push s2)"
got="$(waitrc --stall --past "${OLD}" s2 2250)"
check "herdr-only: a push in the last step still ends it with pushed <new sha>" \
  "pushed $(cat "${ROOT}/head")|exit 0|3" "${got}|$(count '^agent wait' "${ROOT}/herdr.log")"
fresh
got="$(waitrc --stall --past "${OLD}" s2 2250)"
check "herdr-only, no new commit: the wait times out, and gh is never asked" "|exit 1|0" "${got}|$(count '^pr view' "${ROOT}/gh.log")"

# Refusals: each exits non-zero with a line naming the form and its own reason, and waits on nothing
# (no herdr call).
printf '2026-11-01\treview\treview-s1\tclaude\topus\thigh\tsess-r\n' >> "${p}/.swarm/agents.tsv"
FORM='wait [--stall] --past <sha> <slug>'
refused() { # <name> <reason the line gives> <wait args...>
  local name="$1" why="$2" got; shift 2
  fresh; got="$(waitrc "$@")"
  check "${name}: refused with a line naming the form and '${why}', and no herdr call" "yes|yes|yes|0" \
    "$([[ "${got}" != *"|exit 0" ]] && echo yes || echo "no, ${got}")|$(grep -qF -- "${FORM}" "${ROOT}/wait.err" && echo yes || echo "no: $(cat "${ROOT}/wait.err")")|$(grep -qF -- "${why}" "${ROOT}/wait.err" && echo yes || echo "no: $(cat "${ROOT}/wait.err")")|$(count . "${ROOT}/herdr.log")"
}
refused "a short sha" "is a full 40-character commit sha" --stall --past "${OLD:0:12}" s1 450
refused "a conductor" "not the conductor conduct-e" --past "${OLD}" conduct-e 450
refused "a review agent" "not the review agent review-s1" --past "${OLD}" review-s1 450
refused "a name with no story file" "no story file" --past "${OLD}" nosuch 450
refused "a story with no worktree" "s3 has no worktree" --past "${OLD}" s3 450
refused "--past with --lead" "it takes no --lead" --past "${OLD}" --lead 450
refused "--lead with --past after it" "it takes no --lead" --lead --past "${OLD}" 450
refused "--past with --until-report" "it takes no --until-report" --until-report --past "${OLD}" conduct-e

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
