#!/usr/bin/env bash
# backlog_test.sh — `swarm.sh conduct --backlog`: the backlog conductor for the ready stories with no
# epic. Its brief (scope, waves, review, merge rule by merge mode), its refusal on a board with an
# epics/backlog.md, and how `next` waits on it and collects it. herdr, gh and claude are stubs on PATH.
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
# para <pattern> <text> — the paragraph of <text> that starts on the line matching <pattern>.
para() { awk -v pat="$1" 'index($0, pat) { on = 1 } on && /^$/ { exit } on' <<< "$2"; }
item() { # <board> <path> <front-matter line>...
  local path="$1/$2" title; shift 2
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

# herdr: logs every call; each new pane is w:<n>, each tab t<n>; agent start and list track agents.
mkdir -p "${ROOT}/bin"
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
next() { n=$(($(cat "$H/n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/n"; }
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;   # start_agent's require_herdr_version
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
printf '#!/bin/sh\necho "[]"\n' > "${ROOT}/bin/gh"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh"

p="${ROOT}/proj"; b="${p}/docs"
mkdir -p "${p}/.claude/swarm"; : > "${p}/.claude/swarm/config"
git -C "${p}" init -q
run() { (cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
item "${b}" epics/e.md "status: active"
item "${b}" stories/s1.md "status: ready" "kind: code" "epic: e"
item "${b}" stories/o1.md "status: ready" "kind: code"
brief="${p}/.swarm/briefs/conduct-backlog.md"

# --- A board with an epic named backlog: conduct --backlog starts nothing.
item "${b}" epics/backlog.md "status: active"
out="$(run conduct --backlog || echo "exit $?")"
check "with an epics/backlog.md, conduct --backlog fails naming it, and starts nothing" "yes|yes|no|no" \
  "$(has "exit 1" "${out}")|$(has "epics/backlog.md" "${out}")|$(grep -q '^agent start' "${ROOT}/herdr.log" 2>/dev/null && echo yes || echo no)|$([[ -e "${brief}" ]] && echo yes || echo no)"
out="$(run conduct backlog || echo "exit $?")"
check "conduct backlog (an epic of that name) is refused too, and starts nothing" "yes|no" \
  "$(has "exit 1" "${out}")|$(grep -q '^agent start' "${ROOT}/herdr.log" 2>/dev/null && echo yes || echo no)"
rm "${b}/epics/backlog.md"

# --- merge = human: the brief, and next waiting on it, then collecting it.
run conduct --backlog >/dev/null
bl="$(cat "${brief}" 2>/dev/null || true)"
bn="$(sed -n 's/^agent start \(conduct-backlog-[^ ]*\) .*/\1/p' "${ROOT}/herdr.log" | head -1)"
check "conduct --backlog starts conduct-backlog-<project dir>-<path hash> in a workspace named backlog" "yes|yes" \
  "$([[ "${bn}" =~ ^conduct-backlog-proj-[0-9a-f]{6}$ ]] && echo yes || echo "no, got: ${bn}")|$(has "workspace create --label backlog" "$(cat "${ROOT}/herdr.log")")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "the backlog brief names stories with no epic:, story --strict and watch --backlog" "yes|yes|yes|yes" \
  "$(has 'You are the backlog conductor: you build the ready stories on the board with no `epic:`.' "${bl}")|$(has 'Start only stories with no `epic:`, and leave every epic and its stories alone.' "${bl}")|$(has 'swarm.sh story --strict <slug>' "${bl}")|$(has 'swarm.sh watch --backlog` in the background' "${bl}")"
check "the backlog brief has no epic file, no epic scope and no 'of this epic'" "no|no|no|no" \
  "$(hasnt "epics/backlog.md" "${bl}")|$(hasnt "Stay inside this epic" "${bl}")|$(hasnt "of this epic" "${bl}")|$(hasnt "or verify" "${bl}")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "the backlog brief never runs story for a started story, and reports one it could not start or whose build died" "yes|yes|yes|0" \
  "$(has 'has already started: never
run `swarm.sh story` for it again.' "${bl}")|$(has 'report it as not started, with the reason `build died`.' "${bl}")|$(has 'one line each:
`not started: <slug> (<the refusal'"'"'s first line>)`.' "${bl}")|$(grep -c 'swarm.sh story <slug>' <<< "${bl}" || true)"
# shellcheck disable=SC2016 # the backticks are the brief's
check "with merge = human, the backlog brief hands over with swarm.sh review, never swarm.sh merge, and stops when nothing is left" "yes|no|yes|no" \
  "$(has 'run `swarm.sh review <slug> <PR URL>`' "${bl}")|$(hasnt "swarm.sh merge" "${bl}")|$(has 'Stop when no ready story with no `epic:` that you may start is left and none is running.' "${bl}")|$(hasnt "swarm.sh review <epic>" "${bl}")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "with merge = human, a refusal naming another one-off in review is reported as not started, not waited on" "yes" \
  "$(has "Report the
refused story as \`not started: <slug> (waits on <other>'s merge)\`." "${bl}")"
check "the backlog conductor reports to conduct-backlog.report.md" "yes" "$(has "${p}/.swarm/conduct-backlog.report.md" "${bl}")"
nx="$(run next)"
check "with the backlog conductor alive, next waits on it" "wait ${bn}" "${nx%%$'\n'*}"
echo reported > "${p}/.swarm/conduct-backlog.report.md"; TZ=UTC touch -t 202610010800 "${p}/.swarm/conduct-backlog.report.md"
nx="$(run next)"
check "once the backlog conductor has reported, next collects it" "collect ${bn}" "${nx%%$'\n'*}"
run close "${bn}" >/dev/null
run close conduct-e >/dev/null   # next started it: e has a ready story and no conductor

# --- The epic conductor's brief: the same review paragraph, and no 'or verify'.
run conduct e >/dev/null
eb="$(cat "${p}/.swarm/briefs/conduct-e.md")"
check "the backlog brief's review paragraph is the epic conductor's" "same" \
  "$([[ -n "$(para "A story is reviewed only when" "${bl}")" && "$(para "A story is reviewed only when" "${bl}")" == "$(para "A story is reviewed only when" "${eb}")" ]] && echo same || echo differs)"
check "the epic conductor keeps its scope and drops 'or verify'" "yes|no" "$(has "Stay inside this epic" "${eb}")|$(hasnt "or verify" "${eb}")"
flat="$(tr -s '[:space:]' ' ' <<< "${eb}")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "the conductor briefs review each PR the moment it is green and merge the moment it passes, with no batch wording" "yes|yes|yes|yes|no|no|no|no" \
  "$(has "The moment a story's PR head is green and mergeable, start one with" "${flat}")|$(has 'run one review agent for every green PR at once, with no cap below the number of green PRs.' "${flat}")|$(has '`queued: <repo> #<n> <branch> green <m>m with no review on <sha>`, that PR has waited: start its review agent now.' "${flat}")|$(has "once a PR's latest head has passed, merge it (or hand it over, as below) at once, and never hold a finished review result back while other reviews run." "${flat}")|$(hasnt batch "${eb}${bl}")|$(hasnt "later round" "${eb}${bl}")|$(hasnt "wait for any" "${eb}${bl}")|$(hasnt "Do not wait for other PRs" "${eb}${bl}")"
check "with merge = human, the epic conductor still puts the epic in review" "yes" "$(has "swarm.sh review <epic> <every PR URL still waiting>" "${eb}")"
run close conduct-e >/dev/null

# --- merge = agent: the conductor merges each pinned head.
echo "merge = agent" > "${p}/.claude/swarm/config"
run conduct --backlog >/dev/null
check "a conduct that removes an earlier run's report logs the report's time first, for outcomes' held_min" "ok (2026-10-01T08:00:00Z)|gone" \
  "$(awk -F'\t' '$2 == "report" && $3 == "backlog" { print $5 }' "${p}/.swarm/events.tsv")|$([[ -e "${p}/.swarm/conduct-backlog.report.md" ]] && echo there || echo gone)"
bl="$(cat "${brief}")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "with merge = agent, the backlog conductor waits on its own one-off's merge, as an epic's does, unless it costs money" "yes" \
  "$(has 'If the refusal ends `(costs money)`, only the user merges the named story, maybe days later: do not wait for it, and report yours as `not started: <slug> (waits on <other>'"'"'s merge)`.' "${bl}")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "with merge = agent, the backlog conductor also stops when CI on the base timed out or is red with no fix-main line" "yes|yes" \
  "$(has 'that you may start is left and none is running, or when CI on the base timed out, or is red with no `fix-main:` line.' "${bl}")|$(has 'On `fix-main`, start its builder at once' "${bl}")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "with merge = agent, the backlog brief merges with swarm.sh merge --head, starts unblocked stories with no epic, and finishes no epic" "yes|yes|no|no" \
  "$(has "swarm.sh merge --head <the SHA on the findings file's head: line> <PR URL>" "${bl}")|$(has 'start each story with no epic it prints as `ready:`' "${bl}")|$(hasnt "of this epic" "${bl}")|$(hasnt "swarm.sh finish <epic>" "${bl}")"

run close "${bn}" >/dev/null
run conduct e >/dev/null
# shellcheck disable=SC2016 # the backticks are the brief's
check "with merge = agent, the epic conductor still finishes the epic" "yes" "$(has '`swarm.sh finish <epic>` only on a board outside the repo' "$(cat "${p}/.swarm/briefs/conduct-e.md")")"

# --- An epic conductor's workspace: the epic's parent:, read as the template writes it (a trailing
# comment) or quoted, else the epic's own slug.
item "${b}" epics/c1.md "status: active" "parent: big-epic            # only on a child epic of a split one"
item "${b}" epics/c2.md "status: active" 'parent: "big-epic"'
item "${b}" stories/c1s.md "status: ready" "kind: code" "epic: c1"
item "${b}" stories/c2s.md "status: ready" "kind: code" "epic: c2"
item "${b}" epics/solo.md "status: active"
item "${b}" stories/solos.md "status: ready" "kind: code" "epic: solo"
: > "${ROOT}/herdr.log"
o1="$(run conduct c1 || echo "exit $?")"; o2="$(run conduct c2 || echo "exit $?")"; o3="$(run conduct solo || echo "exit $?")"
check "conduct names the workspace for a commented or quoted parent:, else the epic" "yes|yes|yes|2|yes" \
  "$(has "workspace big-epic (w)" "${o1}")|$(has "workspace big-epic (w)" "${o2}")|$(has "workspace solo (w)" "${o3}")|$(grep -c 'workspace create --label big-epic' "${ROOT}/herdr.log")|$(has "workspace create --label solo " "$(cat "${ROOT}/herdr.log")")"

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
