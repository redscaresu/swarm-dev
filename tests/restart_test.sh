#!/usr/bin/env bash
# restart_test.sh — swarm.sh restart <slug>: for a started story whose builder herdr no longer lists, it
# starts one builder in the story's worktree, on its branch, in its tab (the epic's, or a one-off's own).
# With a resume command recorded for the builder's last Claude session it reopens that session; with
# none it starts a fresh builder on the last model with a handover brief. It refuses, starting nothing
# and saying why, while the builder is listed, with no worktree, with a .step-up marker, for kind:
# lead, once its PR merged, off its branch, and when herdr refuses its resume command. Its restart line moves neither build_started nor review_round, and the lead's next poll after
# it is silent. review_round also keeps its count across a build started after a kept close. herdr, gh and claude (tests/claude_stub.sh) are stubs on PATH: herdr logs each call,
# lists the agents in ${ROOT}/agents ("<name> <pane>" lines, all idle) and adds one on agent start.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TZ=UTC
export CLAUDE_STUB_AGENTS="${ROOT}/claude.json"; echo '[]' > "${CLAUDE_STUB_AGENTS}"
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}" "${ROOT}/projects"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
GIT=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main -c commit.gpgsign=false)
fails=0
check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }

printf '#!/bin/sh\nH="%s"\n' "${ROOT}" | tee "${STUB_BIN}/gh" > "${STUB_BIN}/herdr"
cat >> "${STUB_BIN}/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
next() { n=$(($(cat "$H/n" 2>/dev/null || echo 10) + 1)); echo "$n" > "$H/n"; }
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;
  "tab create")   next; echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "pane split")   next; echo "{\"result\":{\"pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "pane run"|"pane wait-output") [ -n "$3" ] || exit 1 ;;
  "pane report-agent") [ ! -e "$H/reportfail" ] || exit 1 ;;
  "agent start")  if [ -e "$H/startonce" ]; then rm "$H/startonce"; echo '{"error":{"code":"start_failed"}}' >&2; exit 1; fi
                  echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')" >> "$H/agents" ;;
  "agent prompt") [ ! -e "$H/promptsent" ] || { echo '{"result":{}}'; exit 0; }   # sent, with no status
                  echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent get")    awk -v p="$3" '$2 == p { f = 1 } END { exit !f }' "$H/agents" || exit 1
                  echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent list")   [ ! -e "$H/listhang" ] || sleep 30
                  awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                    { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                    END { print "]}}" }' "$H/agents" ;;
esac
EOF
cat >> "${STUB_BIN}/gh" <<'EOF'
case "$1 $2" in
  "pr list") [ ! -e "$H/ghhang" ] || sleep 30
             s="$(echo "$*" | sed 's/.*--head story\/\([^ ]*\).*/\1/')"
             if [ -e "$H/prs-$s.json" ]; then cat "$H/prs-$s.json"; else echo '[{"state":"OPEN","url":"https://github.com/o/proj/pull/7","autoMergeRequest":null}]'; fi ;;
  "pr checks") ;;
  *) exit 1 ;;
esac
EOF
chmod +x "${STUB_BIN}/herdr" "${STUB_BIN}/gh"
touch "${ROOT}/agents"

# A project whose board is in its repo: e1 in epic ep and the one-off o1 started, each with a commit in
# its worktree; c1 whose builder ran /clear, w1 whose brief never landed, y1 whose first start herdr fails,
# pf (fresh) and pr (resumed) whose prompt herdr sends but never shows taken up; and k1, u1, l1, m1, b1, r1, g1,
# h1, k3 and m3 started for the refusals, n1 never built.
P="${ROOT}/proj"
"${GIT[@]}" init -q --bare "${ROOT}/origin.git"
"${GIT[@]}" clone -q "${ROOT}/origin.git" "${P}" 2>/dev/null
mkdir -p "${P}/docs/stories" "${P}/.claude/swarm" "${P}/.swarm/briefs"
story() { printf '%s\n' --- "status: ready" "$2" "${3:-}" --- "" "# $1" "" "**Done when:**" "- it holds" > "${P}/docs/stories/$1.md"; }
story e1 "kind: code" "epic: ep"; story o1 "kind: code"; story k1 "kind: code"; story n1 "kind: code"
story u1 "kind: code"; story l1 "kind: lead"; story m1 "kind: code"; story b1 "kind: code"; story r1 "kind: code"
story c1 "kind: code" "epic: ep"; story w1 "kind: code"; story y1 "kind: code"; story k3 "kind: code"; story m3 "kind: code"; story pf "kind: code"; story pr "kind: code"; story g1 "kind: code"; story h1 "kind: code"
: > "${P}/.claude/swarm/config"
"${GIT[@]}" -C "${P}" add -A && "${GIT[@]}" -C "${P}" commit -qm init && "${GIT[@]}" -C "${P}" push -q origin main
for s in e1 o1 k1 u1 l1 m1 b1 r1 c1 w1 y1 g1 h1 k3 m3 pf pr; do
  "${GIT[@]}" -C "${P}" worktree add -q -b "story/${s}" "${ROOT}/proj-wt/${s}" origin/main
  echo "${s}-WORK" > "${ROOT}/proj-wt/${s}/work.txt"
  "${GIT[@]}" -C "${ROOT}/proj-wt/${s}" add work.txt && "${GIT[@]}" -C "${ROOT}/proj-wt/${s}" commit -qm work
done
for s in e1 o1 k1 u1 l1 m1 b1 r1 c1 w1 y1 g1 h1 k3 m3 pf pr; do printf '2026-10-01\tcode\t%s\tclaude\t%s\thigh\tsess-%s\n' "${s}" "$([[ ${s} == o1 ]] && echo opus || echo sonnet)" "${s}"; done > "${P}/.swarm/agents.tsv"
# e1's build: started, a findings round sent, its review agent closed, its builder's pane gone.
printf '%s\n' $'2026-10-01T09:00:00Z\tstory\te1\tw:1\tok' $'2026-10-01T09:30:00Z\ttell:findings\te1\tw:1\tok' \
  $'2026-10-01T09:40:00Z\tclose\te1\tw:1\tok' $'2026-10-01T09:00:00Z\tstory\to1\tw:1\tok' > "${P}/.swarm/events.tsv"
# e1's last session left the resume command resume_file writes; o1's left none.
R="${CLAUDE_CONFIG_DIR}/swarm-dev/resume"; mkdir -p "${R}"
# c1's builder ran /clear: hooks/agent-state.sh moved its command's --resume to the new session sess-c1b.
# w1's session never took its brief: its command is on file, its log holds no prompt.
for s in e1 r1 c1 w1 y1 pr; do printf '%s\n' python3 -I "${R}/sess-${s}.py" claude --resume "sess-${s}" --model sonnet --effort high --permission-mode auto > "${R}/sess-${s}.argv"; done
sed -i.bak 's/^sess-c1$/sess-c1b/' "${R}/sess-c1.argv" && rm "${R}/sess-c1.argv.bak"
# The Claude session logs: a user prompt in each session that took its brief.
mkdir -p "${CLAUDE_PROJECTS_DIR}/p"
for s in e1 r1 c1b y1 pr; do echo '{"type":"user","message":{"role":"user","content":"Implement the story."}}' > "${CLAUDE_PROJECTS_DIR}/p/sess-${s}.jsonl"; done
echo '{"type":"summary","summary":"none"}' > "${CLAUDE_PROJECTS_DIR}/p/sess-w1.jsonl"

run() { (cd "${P}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w HERDR_PANE_ID=w:lead PATH="${STUB_BIN}:${PATH}" bash "${SWARM}" "$@" 2>&1); }
starts() { grep -c '^agent start' "${ROOT}/herdr.log" 2>/dev/null || true; }
last_event() { tail -1 "${P}/.swarm/events.tsv" | awk -F'\t' '{ print $2 " " $3 " " $5 }'; }
restarts() { grep -c $'\trestart\t'"$1"$'\tw:lead\tok' "${P}/.swarm/events.tsv" || true; }
# lifecycle <slug> — build_started and review_round for <slug>, as swarm.sh's libraries compute them.
lifecycle() {
  # shellcheck disable=SC1090,SC1091 # the libraries, from the repo under test
  PROJECT_DIR="${P}" BOARD="${P}/docs" SWARM_HOME="${SWARM%/bin/swarm.sh}" bash -c '
    agent_name() { printf "%s" "$1"; }
    for f in agents board build lifecycle; do . "${SWARM_HOME}/bin/lib/${f}.sh"; done 2>/dev/null
    echo "$(build_started "$1") $(review_round "$1")"' _ "$1"
}

# --- an epic's story with a recorded session: that session is reopened.
before="$(lifecycle e1)"
out="$(run wait --lead 0)" || true
check "before the restart, the lead's poll names the restart exit" "no-agent: e1, exit: swarm.sh restart e1, or swarm.sh hold e1 <reason>" "$(grep '^no-agent: e1' <<< "${out}" || true)"
: > "${ROOT}/herdr.log"
out="$(run restart e1)" && rc=0 || rc=$?
check "restart e1 succeeds" "0" "${rc}"
check "it starts one builder" "1" "$(starts)"
check "in epic ep's tab, at e1's worktree" "yes" "$(has "tab create --workspace w --cwd ${ROOT}/proj-wt/e1 --label ep" "$(cat "${ROOT}/herdr.log")")"
check "reopening its recorded session with its flags" "agent start e1 --kind claude --pane w:11 --timeout 60000 -- --resume sess-e1 --model sonnet --effort high --permission-mode auto" \
  "$(grep '^agent start' "${ROOT}/herdr.log")"
check "and reports the recorded resume command to herdr" "yes" "$(has "--agent-session-id sess-e1 -- python3 -I ${R}/sess-e1.py claude --resume sess-e1" "$(cat "${ROOT}/herdr.log")")"
check "and tells it, in its new pane, to carry on" "yes" "$(has "agent prompt w:11 swarm.sh restart reopened this session" "$(cat "${ROOT}/herdr.log")")"
check "its worktree is still on story/e1" "story/e1" "$(git -C "${ROOT}/proj-wt/e1" rev-parse --abbrev-ref HEAD)"
check "a resumed session adds no agents.tsv line" "17" "$(wc -l < "${P}/.swarm/agents.tsv" | tr -d ' ')"
check "it logs one restart line, naming the session" "restart e1 ok (resumed session sess-e1)|1" "$(last_event)|$(restarts e1)"
check "build_started and review_round read the same after the restart line" "${before}" "$(lifecycle e1)"
check "and they read e1's build and its second round" "2026-10-01T09:00:00Z 2" "${before}"
out="$(run wait --lead 0)" || true
check "the lead's next poll after it is silent on e1, and its queue no longer lists e1" "0|0" \
  "$(grep -c 'e1' <<< "${out}" || true)|$(grep -c '^no-agent: e1' "${P}/.swarm/lead/seen" || true)"

# --- a one-off with no recorded session: a fresh builder on the last model, with a handover brief.
: > "${ROOT}/herdr.log"
out="$(run restart o1)" && rc=0 || rc=$?
check "restart o1 succeeds" "0" "${rc}"
check "it starts one builder" "1" "$(starts)"
check "in a tab of its own, at o1's worktree" "yes" "$(has "tab create --workspace w --cwd ${ROOT}/proj-wt/o1 --label o1" "$(cat "${ROOT}/herdr.log")")"
start="$(grep '^agent start o1' "${ROOT}/herdr.log")"
check "a fresh session on o1's last model" "yes|yes|no" \
  "$(has "--session-id" "${start}" | cut -c1-3)|$(has "--model opus" "${start}" | cut -c1-3)|$(grep -q -- '--resume' <<< "${start}" && echo yes || echo no)"
check "recorded in agents.tsv on the same role and model, with a new session" "code opus new" \
  "$(awk -F'\t' '$3 == "o1" { l = $2 " " $5 " " ($7 == "sess-o1" ? "old" : "new") } END { print l }' "${P}/.swarm/agents.tsv")"
brief="$(cat "${P}/.swarm/briefs/o1.md")"
check "its brief is a handover" "yes" "$(has "## Handover" "${brief}")"
check "saying it was started again on the same model" "yes" "$(has "from a builder on opus, started again on opus by swarm.sh restart" "${brief}")"
check "with the build's diff" "yes" "$(has "+o1-WORK" "${brief}")"
check "it logs one restart line, naming the model" "restart o1 ok (fresh on opus: no session to resume)|1" "$(last_event)|$(restarts o1)"

# --- a session moved by /clear: the new one is reopened, by the command's own --resume.
: > "${ROOT}/herdr.log"
out="$(run restart c1)" && rc=0 || rc=$?
check "restart c1 succeeds" "0" "${rc}"
check "it reopens the session /clear moved it to" "yes|restart c1 ok (resumed session sess-c1b)" \
  "$(has "--resume sess-c1b --model sonnet" "$(grep '^agent start c1' "${ROOT}/herdr.log")" | cut -c1-3)|$(last_event)"

# --- a session whose brief never landed: a fresh builder, with the brief.
: > "${ROOT}/herdr.log"
out="$(run restart w1)" && rc=0 || rc=$?
start="$(grep '^agent start w1' "${ROOT}/herdr.log")"
check "restart w1 starts a fresh builder, not its empty session" "0|yes|no|restart w1 ok (fresh on sonnet: no session to resume)" \
  "${rc}|$(has "--session-id" "${start}" | cut -c1-3)|$(grep -q -- '--resume' <<< "${start}" && echo yes || echo no)|$(last_event)"

# --- herdr failing the first start of a resumed session: one retry, as start_agent makes.
: > "${ROOT}/herdr.log"; touch "${ROOT}/startonce"
out="$(run restart y1)" && rc=0 || rc=$?
check "a resume herdr fails once is retried, and starts" "0|2|restart y1 ok (resumed session sess-y1)" \
  "${rc}|$(grep -c '^agent start y1' "${ROOT}/herdr.log")|$(last_event)"

# --- herdr sends the prompt but never shows the turn start (deliver_prompt's warning), and reads the
# builder idle with no turn again: no ok line, its pane kept, and the lead told what to do.
for s in pf pr; do
  : > "${ROOT}/herdr.log"; touch "${ROOT}/promptsent"
  out="$(run restart "${s}")" && rc=0 || rc=$?; rm "${ROOT}/promptsent"
  check "a ${s} prompt never shown taken up: it fails, logs no ok line, keeps the pane" "1|0|0" \
    "${rc}|$(restarts "${s}")|$(grep -c "^pane close" "${ROOT}/herdr.log" || true)"
  check "a ${s} prompt never shown taken up: it says so" "yes" "$(has "restart: ${s}'s builder runs in its pane, but herdr does not show that it took up its prompt" "${out}")"
  if [[ ${s} == pf ]]; then what="swarm.sh tell pf nudge ${P}/.swarm/briefs/pf.md"; else what="swarm.sh tell pr resume <file>"; fi
  check "a ${s} prompt never shown taken up: it names what to send" "yes" "$(has "${what}" "${out}")"
done

# --- refusals: nothing starts, and the message says why.
refused() { # <name> <slug> <why>
  local out rc
  : > "${ROOT}/herdr.log"
  out="$(run restart "$2")" && rc=0 || rc=$?
  check "$1: refused, nothing started, no restart ok line" "1|0|0" "${rc}|$(starts)|$(restarts "$2")"
  check "$1: it says why" "yes" "$(has "$3" "${out}")"
}
echo "k1 w:5" >> "${ROOT}/agents"
refused "a builder herdr lists" k1 "restart: k1's builder k1 is still listed"
mkdir -p "${P}/.swarm/locks/step-up-g1"; echo $$ > "${P}/.swarm/locks/step-up-g1/pid"
refused "a story whose step-up lock is held" g1 "restart: a step-up, restart or top-rung hold of g1 is running"
check "and the lock it did not take is kept" "$$" "$(cat "${P}/.swarm/locks/step-up-g1/pid")"
touch "$(git -C "${ROOT}/proj-wt/h1" rev-parse --absolute-git-dir)/MERGE_HEAD"
refused "a worktree with a merge left unfinished" h1 "MERGE_HEAD, a git step left unfinished"
check "a refused restart lets its lock go" "no" "$(test -e "${P}/.swarm/locks/step-up-h1" && echo yes || echo no)"
# A hung herdr list or gh read stops after SWARM_RESTART_READ_WAIT seconds, refuses, and lets the lock go.
export SWARM_RESTART_READ_WAIT=1
touch "${ROOT}/listhang"; t0="$(date +%s)"
refused "a herdr agent list that hangs" k3 "restart: herdr could not list its agents (it failed or took over 1s)"
rm "${ROOT}/listhang"
touch "${ROOT}/ghhang"
refused "a gh pr list that hangs" m3 "restart: could not list the PRs on story/m3 (git or gh failed, or gh took over 1s)"
rm "${ROOT}/ghhang"
check "both stop well before the hung reads' 30s, and let the lock go" "yes|no|no" \
  "$( (( $(date +%s) - t0 < 25 )) && echo yes || echo no)|$(test -e "${P}/.swarm/locks/step-up-k3" && echo yes || echo no)|$(test -e "${P}/.swarm/locks/step-up-m3" && echo yes || echo no)"
unset SWARM_RESTART_READ_WAIT
refused "a story with no worktree" n1 "restart: n1 has no worktree at ${ROOT}/proj-wt/n1"
echo "stalled sonnet opus code" > "${P}/.swarm/briefs/u1.step-up"
refused "a story with a .step-up marker" u1 "run swarm.sh step-up --resume u1 instead"
refused "a kind: lead story" l1 "restart: l1 is kind: lead"
echo '[{"state":"MERGED","url":"https://github.com/o/proj/pull/8","autoMergeRequest":null}]' > "${ROOT}/prs-m1.json"
refused "a story whose PR merged" m1 "restart: a PR on story/m1 has merged or is set to auto-merge"
git -C "${ROOT}/proj-wt/b1" checkout -q --detach
refused "a worktree not on its story branch" b1 "restart: b1's worktree ${ROOT}/proj-wt/b1 is not on story/b1"
# herdr refusing the resume command it would restore r1 with: r1's new pane is closed and no restart logged.
touch "${ROOT}/reportfail"; : > "${ROOT}/herdr.log"
out="$(run restart r1)" && rc=0 || rc=$?; rm "${ROOT}/reportfail"
pane="$(sed -n 's/^agent start r1 .*--pane \([^ ]*\).*/\1/p' "${ROOT}/herdr.log")"
check "a resume command herdr refuses: it fails, closes the pane it opened, logs no restart ok line" "1|yes|0" \
  "${rc}|$(has "pane close ${pane:-none}" "$(cat "${ROOT}/herdr.log")" | cut -c1-3)|$(restarts r1)"
check "a resume command herdr refuses: it says why" "yes" "$(has "so a herdr restart would drop its guards; its pane is closed" "${out}")"

# --- review_round across a kept close: a build started after one (keep_build's kept line, then that
# close's own line) keeps the kept PR's count; a later close or reset line, a reconcile that reopened the
# story, or no kept line, starts it again.
FOUR=("story ok" "tell:findings ok" "tell:findings ok" "escalate ok (findings-3: sonnet -> opus)")
KEPT=("kept ok (https://github.com/o/proj/pull/9)" "close:stalled ok")
round_after() { # <slug> <event>... — <slug>'s review_round once events.tsv gains these "<command> <outcome>" lines
  local e
  for e in "${@:2}"; do printf '2026-10-02T09:00:00Z\t%s\t%s\tw:lead\t%s\n' "${e%% *}" "$1" "${e#* }"; done >> "${P}/.swarm/events.tsv"
  lifecycle "$1" | cut -d' ' -f2
}
check "after a story ok line, two ok findings tells and a findings-3 escalate, review_round is 4" 4 "$(round_after rk1 "${FOUR[@]}")"
check "it stays 4 across a story ok line that follows a kept line and its close" 4 "$(round_after rk1 "${KEPT[@]}" "story ok")"
check "a story ok line after a kept line, its close and a later close resets it to 1" 1 \
  "$(round_after rk2 "${FOUR[@]}" "${KEPT[@]}" "close ok" "story ok")"
check "a story ok line after a kept line, its close and a later reset resets it to 1" 1 \
  "$(round_after rk3 "${FOUR[@]}" "${KEPT[@]}" "reset ok (re-scoped)" "story ok")"
check "a story ok line after a kept line, its close and a reconcile that reopened it (its PR closed unmerged) resets it to 1" 1 \
  "$(round_after rk5 "${FOUR[@]}" "${KEPT[@]}" "reconcile ok (reopened)" "story ok")"
check "a story ok line with no kept line resets it to 1" 1 "$(round_after rk4 "${FOUR[@]}" "story ok")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
