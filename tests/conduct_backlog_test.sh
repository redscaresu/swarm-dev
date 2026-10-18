#!/usr/bin/env bash
# conduct_backlog_test.sh — two projects under one herdr each run `conduct --backlog`. herdr names span
# projects, so each backlog conductor is named for its project's dir; next, wait, close and status in
# each project find its own and not the other's, and a name held by another project's agent is refused
# naming where it runs. herdr, gh and claude are stubs on PATH; herdr's state is shared by both projects.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
# No trust file here, so require_trusted lets the fixture agents start whatever ~/.claude.json says.
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects"
# The claude stub goes first on PATH, so no run here reaches the real claude.
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

# herdr: one for both projects. Each new pane is w:<n> with the tab's --cwd; an agent's cwd is its pane's.
mkdir -p "${ROOT}/bin"
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
next() { n=$(($(cat "$H/n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/n"; }
case "$1 $2" in
  "workspace list")   echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  "tab create")       next; echo "t$n $(echo "$*" | sed 's/.*--label \([^ ]*\).*/\1/')" >> "$H/tabs"
                      echo "w:$n $(echo "$*" | sed 's/.*--cwd \([^ ]*\).*/\1/')" >> "$H/cwds"
                      echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "tab list")         awk 'BEGIN { printf "{\"result\":{\"tabs\":[" }
                           { printf "%s{\"tab_id\":\"%s\",\"label\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                           END { print "]}}" }' "$H/tabs" 2>/dev/null || echo '{"result":{"tabs":[]}}' ;;
  "agent prompt")     echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent wait")       echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent start")      p="$(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')"
                      echo "$3 $p $(awk -v p="$p" '$1 == p { print $2 }' "$H/cwds")" >> "$H/agents" ;;
  "agent list")       awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                           { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\",\"cwd\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2, $3 }
                           END { print "]}}" }' "$H/agents" 2>/dev/null || echo '{"result":{"agents":[]}}' ;;
  "pane list")        awk 'BEGIN { printf "{\"result\":{\"panes\":[" }
                           { printf "%s{\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $2 }
                           END { print "]}}" }' "$H/agents" 2>/dev/null || echo '{"result":{"panes":[]}}' ;;
  "pane close"|"tab close") p=$3; [ "$1" = tab ] && p="w:${3#t}"
                      [ -e "$H/agents" ] && awk -v p="$p" '$2 != p' "$H/agents" > "$H/agents.tmp" && mv "$H/agents.tmp" "$H/agents" ;;
esac
EOF
printf '#!/bin/sh\necho "[]"\n' > "${ROOT}/bin/gh"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh"

# Two projects, each with a ready story outside any epic.
for p in alpha bravo; do
  mkdir -p "${ROOT}/${p}/.claude/swarm"; : > "${ROOT}/${p}/.claude/swarm/config"
  git -C "${ROOT}/${p}" init -q
  item "${ROOT}/${p}/docs" "stories/${p}1.md" "status: ready" "kind: code"
  : > "${ROOT}/${p}/docs/stories/README.md"   # dash's mark of a board
done
run() { local p="$1"; shift; (cd "${ROOT}/${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }

out_a="$(run alpha conduct --backlog || echo "exit $?")"
out_b="$(run bravo conduct --backlog || echo "exit $?")"
log="$(cat "${ROOT}/herdr.log")"
check "both projects start a backlog conductor, each named for its project" "yes|yes|no|no" \
  "$(has "agent start conduct-backlog-alpha " "${log}")|$(has "agent start conduct-backlog-bravo " "${log}")|$(hasnt "exit" "${out_a}")|$(hasnt "exit" "${out_b}")"
check "each gets its own brief, under its own project" "yes|yes" \
  "$([[ -f "${ROOT}/alpha/.swarm/briefs/conduct-backlog.md" ]] && echo yes || echo no)|$([[ -f "${ROOT}/bravo/.swarm/briefs/conduct-backlog.md" ]] && echo yes || echo no)"
check "each brief reports to its own project's report" "yes|no|yes|no" \
  "$(has "${ROOT}/alpha/.swarm/conduct-backlog.report.md" "$(cat "${ROOT}/alpha/.swarm/briefs/conduct-backlog.md")")|$(hasnt "${ROOT}/bravo/" "$(cat "${ROOT}/alpha/.swarm/briefs/conduct-backlog.md")")|$(has "${ROOT}/bravo/.swarm/conduct-backlog.report.md" "$(cat "${ROOT}/bravo/.swarm/briefs/conduct-backlog.md")")|$(hasnt "${ROOT}/alpha/" "$(cat "${ROOT}/bravo/.swarm/briefs/conduct-backlog.md")")"

# next: each waits on its own; once alpha has reported, alpha collects and bravo still waits.
check "next in each project waits on its own backlog conductor" "wait conduct-backlog-alpha|wait conduct-backlog-bravo" \
  "$(run alpha next | head -1)|$(run bravo next | head -1)"
echo reported > "${ROOT}/alpha/.swarm/conduct-backlog.report.md"
check "alpha's report is alpha's alone: alpha collects, bravo still waits" "collect conduct-backlog-alpha|wait conduct-backlog-bravo" \
  "$(run alpha next | head -1)|$(run bravo next | head -1)"

# dash: alpha's conductor, its session idle, has reported (its report is found by its name).
sess="$(grep -F "conduct-backlog-alpha" "${ROOT}/alpha/.swarm/agents.tsv" | grep -oE '[0-9a-f]{8}-[0-9a-f-]{27}' | head -1)"
echo "[{\"sessionId\":\"${sess}\",\"status\":\"idle\"}]" > "${ROOT}/claude.json"
check "dash in alpha shows its backlog conductor as reported" "yes" \
  "$(has "reported" "$(CLAUDE_STUB_AGENTS="${ROOT}/claude.json" run alpha dash | grep "conduct-backlog-alpha" || true)")"

# wait: alpha's conductor has reported, so the wait returns; the other project's name is never waited on.
w_a="$(run alpha wait conduct-backlog-alpha 2000 || echo "exit $?")"
w_x="$(run alpha wait conduct-backlog-bravo 2000 || echo "exit $?")"
check "wait in alpha returns on alpha's conductor, and refuses bravo's" "no|no|yes|yes" \
  "$(hasnt "exit" "${w_a}")|$(hasnt "no agent this project started" "${w_a}")|$(has "exit 1" "${w_x}")|$(has "no agent this project started holds this name" "${w_x}")"

# status --all: each lists its own backlog conductor and not the other's.
st_a="$(run alpha status --all)"; st_b="$(run bravo status --all)"
check "status in each project lists only its own backlog conductor" "yes|no|yes|no" \
  "$(has "conduct-backlog-alpha" "${st_a}")|$(hasnt "conduct-backlog-bravo" "${st_a}")|$(has "conduct-backlog-bravo" "${st_b}")|$(hasnt "conduct-backlog-alpha" "${st_b}")"

# close: alpha's close of bravo's name closes nothing; alpha's own closes alpha's alone.
run alpha close conduct-backlog-bravo >/dev/null 2>&1 || true
check "close in alpha leaves bravo's conductor" "yes" "$(has "conduct-backlog-bravo " "$(cat "${ROOT}/agents")")"
run alpha close conduct-backlog-alpha >/dev/null 2>&1 || true
check "close in alpha closes alpha's conductor and keeps bravo's" "no|yes" \
  "$(hasnt "conduct-backlog-alpha " "$(cat "${ROOT}/agents")")|$(has "conduct-backlog-bravo " "$(cat "${ROOT}/agents")")"

# The name-held refusal: a third project in a dir named bravo would want bravo's name.
mkdir -p "${ROOT}/other/bravo/.claude/swarm"; : > "${ROOT}/other/bravo/.claude/swarm/config"
git -C "${ROOT}/other/bravo" init -q
item "${ROOT}/other/bravo/docs" stories/o1.md "status: ready" "kind: code"
out="$(run other/bravo conduct --backlog || echo "exit $?")"
check "a name held by another project's agent is refused, naming that project's dir" "yes|yes|yes" \
  "$(has "exit 1" "${out}")|$(has "an agent this project did not start" "${out}")|$(has "it runs in ${ROOT}/bravo" "${out}")"

# A dir named like a retired agent (work-done) still gives a live conductor's name: next waits on it.
mkdir -p "${ROOT}/work-done/.claude/swarm"; : > "${ROOT}/work-done/.claude/swarm/config"
git -C "${ROOT}/work-done" init -q
item "${ROOT}/work-done/docs" stories/w1.md "status: ready" "kind: code"
run work-done conduct --backlog >/dev/null || true
check "a project dir ending -done gets a name that is not a retired one, and next waits on it" "wait conduct-backlog-work-done_" \
  "$(run work-done next | head -1)"

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
