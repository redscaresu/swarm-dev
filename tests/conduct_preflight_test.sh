#!/usr/bin/env bash
# conduct_preflight_test.sh — under merge = agent, no conductor starts while Claude Code's settings have
# no allow rule for swarm.sh merge: next (its conduct_ready, behind a working conductor) prints why,
# starts none and logs no failed conduct line, and swarm.sh conduct dies with the same line before
# herdr opens a workspace or tab. With the rule, or under merge = human, both start one. A rule
# merge_allowed does not read still gets the line, naming the files read and the rule looked for.
# herdr, gh and claude are stubs on PATH; CLAUDE_CONFIG_DIR is a stub dir, never the real one.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/cc" CLAUDE_PROJECTS_DIR="${ROOT}/projects"
P="${ROOT}/p"; CC="${CLAUDE_CONFIG_DIR}"
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }
item() { # <path under docs> <front-matter line>...
  local path="${P}/docs/$1" title; shift
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

# herdr: logs each call; conduct-run already works in pane w:7, and each new tab's agent goes in w:<n>.
mkdir -p "${ROOT}/bin"
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;
  "workspace list")   echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  "tab create")       n=$(($(cat "$H/n" 2>/dev/null || echo 7) + 1)); echo "$n" > "$H/n"
                      echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "tab list")         echo '{"result":{"tabs":[]}}' ;;
  "agent prompt")     echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent wait")       echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent start")      echo "$3 w:$(cat "$H/n")" >> "$H/agents" ;;
  "agent list")       awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                           { printf "%s{\"name\":\"%s\",\"agent_status\":\"working\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                           END { print "]}}" }' "$H/agents" ;;
  "pane list")        echo '{"result":{"panes":[]}}' ;;
esac
EOF
printf '#!/bin/sh\necho "[]"\n' > "${ROOT}/bin/gh"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh"

# fresh <merge> [allow rule] — a new project with that merge setting, epic run's conductor working and
# epic e's story e1 ready with none; the user's settings hold <allow rule>, or another rule alone.
fresh() {
  rm -rf "${P}" "${CC}" "${ROOT}/herdr.log" "${ROOT}/n"
  mkdir -p "${P}/.claude/swarm" "${P}/.swarm/state" "${CC}"
  git -C "${P}" init -q
  echo "merge = $1" > "${P}/.claude/swarm/config"
  printf '{"permissions":{"allow":["Bash(git status)"%s]}}\n' "${2:+,\"$2\"}" > "${CC}/settings.json"
  item epics/run.md "status: active"; item stories/r1.md "status: review" "kind: code" "epic: run"
  item epics/e.md "status: active"; item stories/e1.md "status: ready" "kind: code" "epic: e"
  echo "w:7 conduct-run" > "${P}/.swarm/state/tab"; echo "conduct-run w:7" > "${ROOT}/agents"
}
run() { (cd "${P}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
# herdr_did <regex> — how many herdr calls match: 0 when herdr was never called.
herdr_did() { grep -cE "^($1)" <<< "$(cat "${ROOT}/herdr.log" 2>/dev/null)" || true; }
conduct_events() { awk -F'\t' '$2 == "conduct"' "${P}/.swarm/events.tsv" 2>/dev/null | wc -l | tr -d ' '; }
LINE="no conductor started: merge = agent and no allow rule for swarm.sh merge in ${CC}/settings.json, .claude/settings.json, .claude/settings.local.json; add \"Bash(swarm.sh merge *)\" to permissions.allow in one of them (swarm.sh init checks it)"

# --- merge = agent, no rule: next says why and starts nothing; conduct dies before herdr opens anything.
fresh agent
out="$(run next || echo "exit $?")"
check "merge = agent, no rule: next waits on the working conductor and prints why no conductor starts" "wait conduct-run|yes" \
  "$(head -1 <<< "${out}")|$(has "${LINE}" "${out}")"
check "merge = agent, no rule: next starts no conductor and logs no conduct line" "0|0|0" \
  "$(herdr_did 'agent start|tab create|workspace create')|$(conduct_events)|$(grep -c '^started: ' <<< "${out}" || true)"
fresh agent
out="$(run conduct e; echo "exit $?")"
check "merge = agent, no rule: conduct exits non-zero with the line" "exit 1|yes" "$(tail -1 <<< "${out}")|$(has "swarm: ${LINE}" "${out}")"
check "merge = agent, no rule: conduct opens no workspace or tab, starts no agent and writes no brief" "0|no" \
  "$(herdr_did 'workspace create|tab create|agent start')|$([[ -e "${P}/.swarm/briefs/conduct-e.md" ]] && echo yes || echo no)"

# --- The same with the rule, or under merge = human with none: both get past the check.
for setup in "agent|Bash(swarm.sh merge *)" "human|"; do
  m="${setup%%|*}"; rule="${setup#*|}"; what="merge = ${m}, ${rule:-no rule}"
  fresh "${m}" "${rule}"
  out="$(run next || echo "exit $?")"
  check "${what}: next starts epic e's conductor, with no line" "wait conduct-run|yes|1|no" \
    "$(head -1 <<< "${out}")|$(has "started: conduct-e (swarm.sh conduct e)" "${out}")|$(herdr_did 'agent start conduct-e ')|$(grep -qF 'no allow rule' <<< "${out}" && echo yes || echo no)"
  fresh "${m}" "${rule}"
  out="$(run conduct e; echo "exit $?")"
  check "${what}: conduct starts epic e's conductor in a workspace and tab of its own" "exit 0|1|1|1" \
    "$(tail -1 <<< "${out}")|$(herdr_did 'workspace create')|$(herdr_did 'tab create')|$(herdr_did 'agent start conduct-e ')"
done

# --- A false negative: a rule merge_allowed does not read (the plugin's full path) still gets the line
# on next, naming the files read and the rule looked for, never an empty or silent next.
fresh agent "Bash(${ROOT}/plugin/bin/swarm.sh merge *)"
out="$(run next || echo "exit $?")"
check "a rule merge_allowed does not read: next names the files read and the rule looked for" "wait conduct-run|yes|0" \
  "$(head -1 <<< "${out}")|$(has "${LINE}" "${out}")|$(herdr_did 'agent start')"

# --- Two epics with ready work and no rule: one line, not one per epic.
fresh agent
item epics/f.md "status: active"; item stories/f1.md "status: ready" "kind: code" "epic: f"
out="$(run next || echo "exit $?")"
check "merge = agent, no rule, two epics ready: next says why once and starts nothing" "1|0" \
  "$(grep -cF "${LINE}" <<< "${out}" || true)|$(herdr_did 'agent start')"

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
