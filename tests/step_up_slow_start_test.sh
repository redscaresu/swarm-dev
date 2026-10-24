#!/usr/bin/env bash
# step_up_slow_start_test.sh — a step-up to a model slow to show it is working is not read as a
# failure: start_agent gives fable 300 s to take up its brief and every other model 60 s, unless
# SWARM_PROMPT_TIMEOUT_MS says otherwise; and a new rung whose brief reads as not taken up keeps its
# pane and is read once more over 300 s, closed (with the step-up --resume marker kept) only when it
# is still idle with no turn. herdr, gh and claude (tests/claude_stub.sh) are stubs on PATH. herdr
# keeps a clock of simulated milliseconds since the brief: `agent prompt --timeout <ms>` moves it on by
# <ms> (to ${ROOT}/late, then answers working, when that comes first) and each `agent get` by 5000, so
# the new builder reads working once the clock reaches ${ROOT}/late (never, when it holds never).
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
now=$(cat "$H/ms" 2>/dev/null || echo 0); late=$(cat "$H/late")
up() { [ "$late" != never ] && [ "$1" -ge "$late" ]; }
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;
  "tab create")   next; echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "pane split")   next; echo "{\"result\":{\"pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "tab list")     echo '{"result":{"tabs":[{"tab_id":"w:t1","label":"s1"}]}}' ;;
  "tab close"|"pane close") : > "$H/agents" ;;
  "agent start")  echo 0 > "$H/ms"; echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')" >> "$H/agents" ;;
  "agent prompt") t=$(echo "$*" | sed 's/.*--timeout \([0-9]*\).*/\1/')
                  if up $((now + t)); then echo "$late" > "$H/ms"; echo '{"result":{"agent":{"agent_status":"working"}}}'
                  else echo $((now + t)) > "$H/ms"; echo '{"error":{"code":"timeout"}}' >&2; exit 1; fi ;;
  "agent get")    now=$((now + 5000)); echo "$now" > "$H/ms"
                  if up "$now"; then s=working; else s=idle; fi
                  echo "{\"result\":{\"agent\":{\"agent_status\":\"$s\"}}}" ;;
  "agent list")   awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
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
# build_on <model> <late> — s1's builder is <model> in pane w:1, with no step-up waiting, and the next
# one started reads working at <late> ms.
build_on() {
  printf '2026-10-01\tcode\ts1\tclaude\t%s\thigh\tsess-1\n' "$1" > "${P}/.swarm/agents.tsv"
  echo "w:1 s1" > "${P}/.swarm/state/s1"; echo "s1 w:1" > "${ROOT}/agents"; echo "$2" > "${ROOT}/late"
  rm -f "${P}/.swarm/events.tsv" "${P}/.swarm/briefs/s1.step-up"; : > "${ROOT}/herdr.log"
}

build_on sonnet 0
out="$(run step-up s1 stalled)" && rc=0 || rc=$?
check "a step-up to opus gives its brief 60 s" "0|60000|ok (stalled: sonnet -> opus)" "${rc}|$(timeouts)|$(escalate)"

build_on opus 90000
out="$(run step-up s1 stalled)" && rc=0 || rc=$?
check "a step-up to a fable that shows working only after 90 s succeeds, its brief given 300 s" \
  "0|300000|ok (stalled: opus -> fable)|1" "${rc}|$(timeouts)|$(escalate)|$(closes)"

build_on opus 90000
out="$(SWARM_PROMPT_TIMEOUT_MS=10000 run step-up s1 stalled)" && rc=0 || rc=$?
check "SWARM_PROMPT_TIMEOUT_MS overrides fable's window" "10000,10000" "$(timeouts)"
check "a rung whose brief reads as not taken up keeps its pane, warns, and is read again until it shows working: the step-up succeeds" \
  "0|yes|ok (stalled: opus -> fable)|1|gone" \
  "${rc}|$(has "s1's fable builder has not shown it took up its brief; its pane is kept and read again for 300s" "${out}")|$(escalate)|$(closes)|$([[ -e "${P}/.swarm/briefs/s1.step-up" ]] && echo kept || echo gone)"

build_on opus never
out="$(SWARM_PROMPT_TIMEOUT_MS=10000 run step-up s1 stalled)" && rc=0 || rc=$?
check "a rung that never shows a turn is read again, then closed: no escalation, and the --resume marker is kept" \
  "1|yes|yes||2|kept" \
  "${rc}|$(has "its pane is kept and read again" "${out}")|$(has "run swarm.sh step-up --resume s1" "${out}")|$(escalate)|$(closes)|$([[ -e "${P}/.swarm/briefs/s1.step-up" ]] && echo kept || echo gone)"
check "and its agents.tsv line is taken back" "code opus" "$(awk -F'\t' '$3 == "s1" { l = $2 " " $5 } END { print l }' "${P}/.swarm/agents.tsv")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
