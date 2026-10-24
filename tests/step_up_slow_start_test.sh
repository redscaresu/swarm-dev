#!/usr/bin/env bash
# step_up_slow_start_test.sh — a step-up to a model slow to show it is working is not read as a
# failure: start_agent gives a fable brief 300 s over both tries, and every other model's herdr's 60 s
# wait, unless SWARM_PROMPT_TIMEOUT_MS says otherwise; and a new rung whose brief may have gone out but
# reads as not taken up, or unsure, keeps its pane and is read once more over 300 s, closed (with the
# step-up --resume marker kept) only when it is still idle with no turn. One blocked on a question
# before its brief went is closed at once. herdr, gh and claude (tests/claude_stub.sh) are stubs on
# PATH. herdr keeps a clock of simulated milliseconds since the agent started: `agent prompt --timeout
# <ms>` moves it on by <ms> (to ${ROOT}/late, then answers working, when that comes first) and each
# `agent get` by 5000, so the new builder reads working once the clock reaches ${ROOT}/late (never,
# when it holds never); each `agent list` logs the clock. ${ROOT}/mode makes it fail: resend-fails
# answers the second prompt server_unavailable; nobase gives no status before the first prompt;
# blocked gives no reply to the first prompt, answers the second agent_blocked, and reads blocked from then on;
# hiccup gives no status once an `agent list` follows a prompt (rung_late's re-read).
set -euo pipefail

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
now=$(cat "$H/ms" 2>/dev/null || echo 0); late=$(cat "$H/late"); mode=$(cat "$H/mode")
up() { [ "$late" != never ] && [ "$1" -ge "$late" ]; }
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;
  "tab create")   next; echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "pane split")   next; echo "{\"result\":{\"pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "tab list")     echo '{"result":{"tabs":[{"tab_id":"w:t1","label":"s1"}]}}' ;;
  "tab close"|"pane close") : > "$H/agents" ;;
  "agent start")  echo 0 > "$H/ms"; echo 0 > "$H/prompts"; rm -f "$H/isblocked" "$H/reread"; echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')" >> "$H/agents" ;;
  "agent prompt") t=$(echo "$*" | grep -o -- '--timeout [0-9]*' | tail -1 | sed 's/.* //'); p=$(($(cat "$H/prompts") + 1)); echo "$p" > "$H/prompts"
                  case "$mode:$p" in
                    resend-fails:2) echo '{"error":{"code":"server_unavailable"}}' >&2; exit 1 ;;
                    blocked:1) echo $((now + t)) > "$H/ms"; exit 1 ;;
                    blocked:2) touch "$H/isblocked"; echo '{"error":{"code":"agent_blocked"}}' >&2; exit 1 ;;
                  esac
                  if up $((now + t)); then echo "$late" > "$H/ms"; echo '{"result":{"agent":{"agent_status":"working"}}}'
                  else echo $((now + t)) > "$H/ms"; echo '{"error":{"code":"timeout"}}' >&2; exit 1; fi ;;
  "agent get")    [ "$mode:$(cat "$H/prompts")" != nobase:0 ] || exit 1
                  [ "$mode" != hiccup ] || [ ! -e "$H/reread" ] || exit 1
                  now=$((now + 5000)); echo "$now" > "$H/ms"
                  if [ -e "$H/isblocked" ]; then s=blocked; elif up "$now"; then s=working; else s=idle; fi
                  echo "{\"result\":{\"agent\":{\"agent_status\":\"$s\"}}}" ;;
  "agent list")   echo "list at $now" >> "$H/herdr.log"; [ "$(cat "$H/prompts" 2>/dev/null || echo 0)" = 0 ] || touch "$H/reread"
                  awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                    { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                    END { print "]}}" }' "$H/agents" ;;
esac
EOF
cat >> "${STUB_BIN}/gh" <<'EOF'
case "$1 $2 $*" in
  "pr list "*"--state all"*) echo '[{"state":"OPEN","url":"https://github.com/o/proj/pull/5","autoMergeRequest":null}]' ;;
  "pr list "*) echo "https://github.com/o/proj/pull/5" ;;
esac
EOF
chmod +x "${STUB_BIN}/herdr" "${STUB_BIN}/gh"

# A project whose board is in its repo, with story s1 building in its worktree.
P="${ROOT}/proj"; WT="${ROOT}/proj-wt/s1"
"${GIT[@]}" init -q --bare "${ROOT}/origin.git"
"${GIT[@]}" clone -q "${ROOT}/origin.git" "${P}" 2>/dev/null
mkdir -p "${P}/docs/stories" "${P}/.claude/swarm" "${P}/.swarm/state"
printf '%s\n' --- "status: ready" "kind: code" --- "" "# s1" "" "**Done when:**" "- it holds" > "${P}/docs/stories/s1.md"
"${GIT[@]}" -C "${P}" add -A && "${GIT[@]}" -C "${P}" commit -qm init && "${GIT[@]}" -C "${P}" push -q origin main
"${GIT[@]}" -C "${P}" worktree add -q -b story/s1 "${WT}" origin/main
echo "escalate_ladder = sonnet,opus,fable" > "${P}/.claude/swarm/config"
run() { (cd "${P}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${STUB_BIN}:${PATH}" bash "${SWARM}" "$@" 2>&1); }
escalate() { awk -F'\t' '$2 == "escalate" { l = $5 } END { print l }' "${P}/.swarm/events.tsv" 2>/dev/null; }
timeouts() { grep -o -- '--until blocked --timeout [0-9]*' "${ROOT}/herdr.log" | sed 's/.* //' | paste -sd, -; }
closes() { grep -c '^tab close\|^pane close' "${ROOT}/herdr.log" || true; }
# build_on <model> <late> [mode] — s1's builder is <model> in pane w:1, with no step-up waiting, and
# the next one started reads working at <late> ms, its herdr failing as [mode] says.
build_on() {
  printf '2026-10-01\tcode\ts1\tclaude\t%s\thigh\tsess-1\n' "$1" > "${P}/.swarm/agents.tsv"
  echo "w:1 s1" > "${P}/.swarm/state/s1"; echo "s1 w:1" > "${ROOT}/agents"; echo "$2" > "${ROOT}/late"; echo "${3:-}" > "${ROOT}/mode"
  rm -f "${P}/.swarm/events.tsv" "${P}/.swarm/briefs/s1.step-up"; : > "${ROOT}/herdr.log"
}
marker() { if [[ -e "${P}/.swarm/briefs/s1.step-up" ]]; then echo kept; else echo gone; fi; }
newest() { awk -F'\t' '$3 == "s1" { l = $2 " " $5 } END { print l }' "${P}/.swarm/agents.tsv"; }
# reread_at — the clock when rung_late looked the new builder up (the first list after a prompt).
reread_at() { awk '/^agent prompt/ { p = 1 } p && /^list at / { print $3; exit }' "${ROOT}/herdr.log"; }
SAID="its pane is kept and read again for 300s"; AFTER="s1's fable builder took up its brief after all"

# Working at 130 s: past a 60 s try (herdr's wait, then 60 s of reads), within fable's 150 s.
build_on sonnet 130000
out="$(run step-up s1 stalled)" && rc=0 || rc=$?
check "a step-up to opus gives its brief 60 s" "0|60000,60000|ok (stalled: sonnet -> opus)" "${rc}|$(timeouts)|$(escalate)"

build_on opus 90000
out="$(run step-up s1 stalled)" && rc=0 || rc=$?
check "a step-up to a fable that shows working only after 90 s succeeds at the first try, with no re-read" \
  "0|60000|ok (stalled: opus -> fable)|1|no" "${rc}|$(timeouts)|$(escalate)|$(closes)|$(grep -qF "${SAID}" <<< "${out}" && echo yes || echo no)"

build_on opus 90000
out="$(SWARM_PROMPT_TIMEOUT_MS=10000 run step-up s1 stalled)" && rc=0 || rc=$?
check "SWARM_PROMPT_TIMEOUT_MS overrides fable's window" "10000,10000|45000" "$(timeouts)|$(reread_at)"
check "a rung whose brief reads as not taken up keeps its pane, warns, is read again until it shows working, and says so: the step-up succeeds" \
  "0|yes|yes|ok (stalled: opus -> fable)|1|gone" \
  "${rc}|$(has "s1's fable builder has not shown it took up its brief; ${SAID}" "${out}")|$(has "${AFTER}" "${out}")|$(escalate)|$(closes)|$(marker)"

build_on opus 90000 resend-fails
out="$(SWARM_PROMPT_TIMEOUT_MS=10000 run step-up s1 stalled)" && rc=0 || rc=$?
check "a rung herdr sent the brief once and could not send again is read again, and rescued" \
  "0|yes|yes|ok (stalled: opus -> fable)" "${rc}|$(has "could not send it again (server_unavailable)" "${out}")|$(has "${AFTER}" "${out}")|$(escalate)"

build_on opus 90000 nobase
out="$(SWARM_PROMPT_TIMEOUT_MS=10000 run step-up s1 stalled)" && rc=0 || rc=$?
check "a rung that may or may not have its brief is read again, and rescued" \
  "0|yes|yes|ok (stalled: opus -> fable)" "${rc}|$(has "may or may not have the brief" "${out}")|$(has "${AFTER}" "${out}")|$(escalate)"

build_on opus 90000 blocked
out="$(SWARM_PROMPT_TIMEOUT_MS=10000 run step-up s1 stalled)" && rc=0 || rc=$?
check "a rung blocked on a question before its brief went is closed at once, never read again" \
  "1|yes|no||2|kept|code opus" \
  "${rc}|$(has "(agent_blocked)" "${out}")|$(grep -qF "${SAID}" <<< "${out}" && echo yes || echo no)|$(escalate)|$(closes)|$(marker)|$(newest)"

build_on opus never hiccup
out="$(SWARM_PROMPT_TIMEOUT_MS=10000 run step-up s1 stalled)" && rc=0 || rc=$?
check "a rung herdr gives no status for during the re-read keeps its pane and agents.tsv line, and says to look before resuming" \
  "1|yes|yes|yes||1|kept|escalate fable" \
  "${rc}|$(has "s1's fable builder: herdr gave no status for it" "${out}")|$(has "its pane is kept: look at it (herdr agent read" "${out}")|$(has "step-up --resume s1" "${out}")|$(escalate)|$(closes)|$(marker)|$(newest)"

build_on opus never
out="$(run step-up s1 stalled)" && rc=0 || rc=$?
check "a fable that never shows a turn fails its start after 300 s, and is read again for 300 s more" \
  "60000,60000|305000|605000" "$(timeouts)|$(reread_at)|$(cat "${ROOT}/ms")"
check "then it is closed, and says so: no escalation, and the --resume marker is kept" \
  "1|yes|yes|yes||2|kept" \
  "${rc}|$(has "${SAID}" "${out}")|$(has "step-up: s1's fable builder is closed" "${out}")|$(has "run swarm.sh step-up --resume s1" "${out}")|$(escalate)|$(closes)|$(marker)"
check "and its agents.tsv line is taken back" "code opus" "$(newest)"

# The marker it kept: a resume whose fable shows working only after 90 s, past the start's window.
echo 90000 > "${ROOT}/late"; : > "${ROOT}/herdr.log"
out="$(SWARM_PROMPT_TIMEOUT_MS=10000 run step-up --resume s1)" && rc=0 || rc=$?
check "step-up --resume reads a slow rung again too, and rescues it" "0|yes|ok (stalled: opus -> fable)|gone" \
  "${rc}|$(has "${AFTER}" "${out}")|$(escalate)|$(marker)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
