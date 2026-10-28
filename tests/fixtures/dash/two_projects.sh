# shellcheck shell=bash
# two_projects.sh <root> — sourced: builds two swarm projects under <root>, alpha and bravo, whose
# agents, costs, lead queues, needs-you items, epics, merges today and 7-day rates all differ, with
# stub claude, herdr and gh (and failing stty and tput) on PATH, and exports what a dash run needs.
# Every time in it is fixed against SWARM_DASH_NOW (2026-10-10 12:00 UTC, TZ=UTC): git dates,
# events.tsv, agents.tsv, session logs and their mtimes. Sets FIXTURE_A, FIXTURE_B and
# FIXTURE_SWARM, a swarm.sh whose plugin.json says 0.0.0, so a release bump changes no frame.
# dash_golden_test.sh renders it; dash --check's test reuses it.

FX_ROOT="$1"
FX_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# C collation, so the board globs sort the same on every machine.
unset LC_ALL
export SWARM_DASH_NOW=1791633600 TZ=UTC LC_COLLATE=C
# No global or system git config (hooksPath, templateDir, commit.template): the same git here and in CI.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
FIXTURE_A="${FX_ROOT}/alpha"; FIXTURE_B="${FX_ROOT}/bravo"
FIXTURE_SWARM="${FX_ROOT}/home/bin/swarm.sh"

# at <minutes before now> — an ISO time in UTC.
at() { python3 -c 'import datetime, sys; print(datetime.datetime.fromtimestamp(int(sys.argv[1]) - 60 * int(sys.argv[2]), datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))' "${SWARM_DASH_NOW}" "$1"; }
# touch_ago <minutes before now> <file>
touch_ago() { python3 -c 'import os, sys; t = int(sys.argv[1]) - 60 * int(sys.argv[2]); os.utime(sys.argv[3], (t, t))' "${SWARM_DASH_NOW}" "$1" "$2"; }
# fx_git <dir> <minutes before now> <git args...> — git with fixed author, committer and dates.
fx_git() {
  local d="$1" t=$((SWARM_DASH_NOW - 60 * $2)); shift 2
  GIT_AUTHOR_DATE="${t} +0000" GIT_COMMITTER_DATE="${t} +0000" \
    git -C "${d}" -c user.name=builder -c user.email=builder@example.com -c commit.gpgsign=false "$@"
}
# item <project> <path under board> <title> <front-matter line>... — a board file.
item() {
  local p="$1/board/$2" title="$3"; shift 3
  mkdir -p "$(dirname "${p}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${p}"
}
# session <project dir name> <session> <minutes before now> <model> <input> <output> <tool> — a
# session log whose one entry is a tool call at that time, its mtime the same.
session() {
  local f="${FX_ROOT}/projects/$1/$2.jsonl"
  mkdir -p "$(dirname "${f}")"
  printf '{"type":"assistant","timestamp":"%s","message":{"id":"%s-m","model":"%s","usage":{"input_tokens":%s,"output_tokens":%s},"content":[{"type":"tool_use","name":"%s"}]}}\n' \
    "$(at "$3")" "$2" "$4" "$5" "$6" "$7" > "${f}"
  touch_ago "$3" "${f}"
}
# merge_story <project> <minutes before now> <pr number> <slug> — story/<slug> deletes its story
# file and adds its work; merged with --no-ff, as a GitHub PR merge.
merge_story() {
  local p="$1" m="$2"
  fx_git "${p}" "$((m + 5))" checkout -q -b "story/$4"
  fx_git "${p}" "$((m + 5))" rm -q "board/stories/$4.md"
  echo "$4" > "${p}/$4.txt"; fx_git "${p}" "$((m + 5))" add "$4.txt"
  fx_git "${p}" "$((m + 5))" commit -qm "$4"
  fx_git "${p}" "${m}" checkout -q main
  fx_git "${p}" "${m}" merge -q --no-ff -m "Merge pull request #$3 from o/story/$4" "story/$4"
}
project() { # <dir> <config lines>...
  local p="$1"; shift
  mkdir -p "${p}/.claude/swarm" "${p}/.swarm/state" "${p}/board/stories" "${p}/board/epics"
  printf '%s\n' "board_dir = board" "$@" > "${p}/.claude/swarm/config"
  echo "# Stories" > "${p}/board/stories/README.md"
  git -C "${p}" init -q -b main
}

mkdir -p "${FX_ROOT}/bin" "${FX_ROOT}/tmp" "${FX_ROOT}/config" "${FX_ROOT}/home/.claude-plugin"
ln -s "${FX_REPO}/bin" "${FX_ROOT}/home/bin"
echo '{"name": "swarm-dev", "version": "0.0.0"}' > "${FX_ROOT}/home/.claude-plugin/plugin.json"

# alpha: merge = agent; a conductor and a builder working; a green PR and a lead story with no
# **You:** step in the lead's queue; one **You:** step; 4 finished in 7 days, one merge today.
A="${FIXTURE_A}"
project "${A}" "merge = agent" "lead = session"
item "${A}" epics/alpha-core.md "Alpha core" "status: active"
item "${A}" epics/alpha-later.md "Alpha later" "status: later"
item "${A}" stories/a-building.md "Build the parser" "status: ready" "kind: code" "epic: alpha-core"
item "${A}" stories/a-ready.md "Add the cache" "status: ready" "kind: code" "epic: alpha-core"
item "${A}" stories/a-review.md "Wire the API" "status: review" "kind: code" "epic: alpha-core" "prs: https://github.com/o/alpha/pull/11"
item "${A}" stories/a-blocked.md "Ship the CLI" "status: blocked" "kind: code" "epic: alpha-core" "depends_on: [a-review]"
item "${A}" stories/a-key.md "Create the deploy key" "status: ready" "kind: lead" "epic: alpha-core"
printf '\n**You:** create the deploy key in the vault\n' >> "${A}/board/stories/a-key.md"
item "${A}" stories/a-tag.md "Tag the first release" "status: ready" "kind: lead"
item "${A}" stories/a-done-1.md "Lexer" "status: ready" "kind: code" "epic: alpha-core"
item "${A}" stories/a-done-2.md "Tokens" "status: ready" "kind: code" "epic: alpha-core"
fx_git "${A}" 4320 add -A; fx_git "${A}" 4320 commit -qm board
merge_story "${A}" 2880 9 a-done-1
merge_story "${A}" 90 10 a-done-2
printf 'w1:p1 conductor\nw1:p2 a-building\n' > "${A}/.swarm/state/alpha-core"
printf '2026-10-10\tconduct\tconduct-alpha-core\tclaude\topus\thigh\tsa-1\n2026-10-10\tcode\ta-building\tclaude\topus\thigh\tsa-2\n' > "${A}/.swarm/agents.tsv"
session alpha sa-1 2 claude-opus-5-5 400000 50000 Bash
session alpha sa-2 6 claude-opus-5-5 1500000 300000 Edit
{
  printf '%s\tfinish\ta-old\tw1:p1\tok\n' "$(at 7200)"
  printf '%s\tfinish\ta-done-1\tw1:p1\tok\n' "$(at 2870)"
  printf '%s\tfinish\ta-x\tw1:p1\tok\n' "$(at 1500)"
  printf '%s\tconduct\talpha-core\tw0:p1\tok\n' "$(at 180)"
  printf '%s\treview\ta-review\tw1:p1\tok\n' "$(at 120)"
  printf '%s\tfinish\ta-done-2\tw1:p1\tok\n' "$(at 85)"
  printf '%s\tstory\ta-building\tw1:p1\tok\n' "$(at 60)"
} > "${A}/.swarm/events.tsv"
printf '2026-10-09\tnil-check\thttps://github.com/o/alpha/pull/10\tparser accepted an empty file\n' > "${A}/.swarm/findings.tsv"

# bravo: merge = human; an idle conductor, a builder waiting on a prompt and a stalled one; a failing
# PR in the lead's queue; two **You:** steps (+1 more); a quiet epic; 6 finished in 7 days, two
# merges today.
B="${FIXTURE_B}"
project "${B}" "merge = human" "lead = session"
item "${B}" epics/bravo-api.md "Bravo API" "status: active"
item "${B}" epics/bravo-ui.md "Bravo UI" "status: active"
item "${B}" epics/bravo-docs.md "Bravo docs" "status: active"
item "${B}" stories/b-fix.md "Fix the retry" "status: review" "kind: code" "epic: bravo-api" "prs: https://github.com/o/bravo/pull/21"
item "${B}" stories/b-page.md "Draw the page" "status: ready" "kind: code" "epic: bravo-ui"
item "${B}" stories/b-form.md "Draw the form" "status: blocked" "kind: code" "epic: bravo-ui" "depends_on: [b-page]"
item "${B}" stories/b-dns.md "Point the DNS" "status: ready" "kind: lead" "epic: bravo-api"
printf '\n**You:** add the CNAME at the registrar\n' >> "${B}/board/stories/b-dns.md"
item "${B}" stories/b-cert.md "Renew the cert" "status: ready" "kind: lead" "epic: bravo-api"
printf '\n**You:** approve the renewal email\n' >> "${B}/board/stories/b-cert.md"
item "${B}" stories/b-done-1.md "Routes" "status: ready" "kind: code" "epic: bravo-api"
item "${B}" stories/b-done-2.md "Styles" "status: ready" "kind: code" "epic: bravo-ui"
fx_git "${B}" 5760 add -A; fx_git "${B}" 5760 commit -qm board
merge_story "${B}" 240 20 b-done-1
merge_story "${B}" 30 22 b-done-2
printf 'w2:p1 conductor\nw2:p2 b-fix\nw2:p3 b-page\n' > "${B}/.swarm/state/bravo-api"
printf '2026-10-09\tconduct\tconduct-bravo-api\tclaude\topus\thigh\tsb-1\n2026-10-10\tcode\tb-fix\tclaude\tsonnet\thigh\tsb-2\n2026-10-10\tcode\tb-page\tclaude\topus\thigh\tsb-3\n' > "${B}/.swarm/agents.tsv"
session bravo sb-1 300 claude-opus-5-5 900000 90000 Read
session bravo sb-2 12 claude-sonnet-5-5 600000 40000 Bash
session bravo sb-3 45 claude-opus-5-5 200000 20000 Grep
{
  for i in 1 2 3 4; do printf '%s\tfinish\tb-old-%s\tw2:p1\tok\n' "$(at $((i * 1200)))" "${i}"; done
  printf '%s\tfinish\tb-done-1\tw2:p1\tok\n' "$(at 235)"
  printf '%s\tstory\tb-page\tw2:p1\tok\n' "$(at 200)"
  printf '%s\treview\tb-fix\tw2:p1\tok\n' "$(at 50)"
  printf '%s\tfinish\tb-done-2\tw2:p1\tok\n' "$(at 25)"
  printf '%s\ttell:findings\tb-fix\tw2:p1\tok\n' "$(at 15)"
} > "${B}/.swarm/events.tsv"
printf '2026-10-10\tretry-loop\thttps://github.com/o/bravo/pull/21\tretry never backed off\n' > "${B}/.swarm/findings.tsv"

# Claude Code's sessions: alpha's two busy; bravo's conductor idle, b-fix waiting on input, b-page busy.
printf '[{"sessionId":"sa-1","status":"busy"},{"sessionId":"sa-2","status":"busy"},{"sessionId":"sb-1","status":"idle"},{"sessionId":"sb-2","status":"waiting","waitingFor":"input"},{"sessionId":"sb-3","status":"busy"}]' > "${FX_ROOT}/claude.json"
cp "${FX_REPO}/tests/claude_stub.sh" "${FX_ROOT}/bin/claude"
cat > "${FX_ROOT}/bin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"conduct-alpha-core","agent_status":"working","pane_id":"w1:p1","agent_session":{"value":"sa-1"}},{"name":"a-building","agent_status":"working","pane_id":"w1:p2","agent_session":{"value":"sa-2"}},{"name":"conduct-bravo-api","agent_status":"idle","pane_id":"w2:p1","agent_session":{"value":"sb-1"}},{"name":"b-fix","agent_status":"blocked","pane_id":"w2:p2","agent_session":{"value":"sb-2"}},{"name":"b-page","agent_status":"working","pane_id":"w2:p3","agent_session":{"value":"sb-3"}}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t1"},{"pane_id":"w1:p2","tab_id":"w1:t1"},{"pane_id":"w2:p1","tab_id":"w2:t1"},{"pane_id":"w2:p2","tab_id":"w2:t1"},{"pane_id":"w2:p3","tab_id":"w2:t2"}]}}' ;;
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"alpha"},{"workspace_id":"w2","label":"bravo"}]}}' ;;
  "tab list") echo '{"result":{"tabs":[{"tab_id":"w1:t1","label":"alpha-core"},{"tab_id":"w2:t1","label":"bravo-api"},{"tab_id":"w2:t2","label":"bravo-ui"}]}}' ;;
  *) exit 1 ;;
esac
STUB
cat > "${FX_ROOT}/bin/gh" <<'STUB'
#!/bin/sh
case "$1 $2 $3" in
  "pr view https://github.com/o/alpha/pull/11") echo '{"state":"OPEN","mergeStateStatus":"CLEAN","updatedAt":"2026-10-10T10:00:00Z","statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}]}' ;;
  "pr view https://github.com/o/bravo/pull/21") echo '{"state":"OPEN","mergeStateStatus":"BEHIND","updatedAt":"2026-10-10T11:45:00Z","statusCheckRollup":[{"status":"COMPLETED","conclusion":"FAILURE"}]}' ;;
  *) exit 1 ;;
esac
STUB
for b in stty tput; do printf '#!/bin/sh\nexit 1\n' > "${FX_ROOT}/bin/${b}"; done
chmod +x "${FX_ROOT}/bin/"*

unset COLUMNS LINES DASH_COLOR DASH_W DASH_H DASH_CLOCK DASH_KEYS NO_COLOR SWARM_PROJECT HERDR_ENV HERDR_PANE_ID
export PATH="${FX_ROOT}/bin:${PATH}" TMPDIR="${FX_ROOT}/tmp" CLAUDE_PROJECTS_DIR="${FX_ROOT}/projects" \
  CLAUDE_CONFIG_DIR="${FX_ROOT}/config" CLAUDE_STUB_AGENTS="${FX_ROOT}/claude.json" FIXTURE_A FIXTURE_B FIXTURE_SWARM
