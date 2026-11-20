# shellcheck shell=bash
# diff_fixtures_dash.sh — tests/diff_run.sh's fixture for swarm.sh's dash: one project whose board, agents
# and PRs are stubbed, drawn once at 100 columns with its clock fixed. diff_run.sh sources this file, and
# every other tests/diff_fixtures_*.sh, by a glob; its header says what a fixture sets.
#
# Every time in it is fixed against SWARM_DASH_NOW (2026-10-10 12:00 UTC, TZ=UTC): the git dates,
# events.tsv, agents.tsv and the session logs and their mtimes. herdr and gh answer through diff_run's
# shims from stubs written here; claude, stty and tput are stubs on the fixture's PATH, behind the
# shims, so no real one runs. SWARM_NO_CI_REFRESH=1, so dash starts no detached ci refresh, which would
# outlive the command and run flow on the project.
#
# dash names its cache under TMPDIR by a checksum of the project's path (dash_slow), and each side's
# project is at a path of its own. So the command, a bash, runs dash and then renames that one file to
# swarm-dash-3-<key>, which keeps its content compared. It adds that bash and one mv to the process
# starts tests/speed_run.sh counts, the same on each tree.
# shellcheck disable=SC2034 # diff_run.sh reads the FX_ settings

DASH_FX_NOW=1791633600

# dash_fx_at <minutes before now> — an ISO time in UTC.
dash_fx_at() { perl -MPOSIX=strftime -e 'print strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($ARGV[0] - 60 * $ARGV[1])), "\n"' "${DASH_FX_NOW}" "$1"; }
# dash_fx_touch <minutes before now> <file> — set <file>'s mtime to that time.
dash_fx_touch() { perl -e '$t = $ARGV[0] - 60 * $ARGV[1]; utime($t, $t, $ARGV[2]) or die "utime $ARGV[2]: $!\n"' "${DASH_FX_NOW}" "$1" "$2"; }
# dash_fx_git <minutes before now> <git args...> — git in the project with fixed author, committer
# and dates, and no global or system config.
dash_fx_git() {
  local t=$((DASH_FX_NOW - 60 * $1)); shift
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_DATE="${t} +0000" GIT_COMMITTER_DATE="${t} +0000" \
    git -C "${ROOT}/proj" -c user.name=builder -c user.email=builder@example.com -c commit.gpgsign=false "$@"
}
# dash_fx_item <path under board> <title> <front-matter line>... — a board file.
dash_fx_item() {
  local p="${ROOT}/proj/board/$1" title="$2"; shift 2
  mkdir -p "$(dirname "${p}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${p}"
}
# dash_fx_session <session> <minutes before now> <input tokens> <output tokens> <tool> — a session
# log whose one entry is a tool call at that time, its mtime the same.
dash_fx_session() {
  local f="${ROOT}/projects/proj/$1.jsonl"
  mkdir -p "$(dirname "${f}")"
  printf '{"type":"assistant","timestamp":"%s","message":{"id":"%s-m","model":"claude-opus-5-5","usage":{"input_tokens":%s,"output_tokens":%s},"content":[{"type":"tool_use","name":"%s"}]}}\n' \
    "$(dash_fx_at "$2")" "$1" "$3" "$4" "$5" > "${f}"
  dash_fx_touch "$2" "${f}"
}

# dash at 100 columns on a project with an active epic, a builder working, a story in review with an
# open PR whose checks pass, a blocked story, a lead story with a **You:** step and two merges.
fx_dash() {
  local p="${ROOT}/proj" bin="${ROOT}/bin" s m n
  mkdir -p "${p}/.claude/swarm" "${p}/.swarm/state" "${p}/board/stories" "${p}/board/epics" "${bin}"
  printf '%s\n' "board_dir = board" "merge = human" "lead = session" > "${p}/.claude/swarm/config"
  echo "# Stories" > "${p}/board/stories/README.md"
  dash_fx_git 4320 init -q -b main
  dash_fx_item epics/core.md "Core" "status: active"
  dash_fx_item stories/parser.md "Build the parser" "status: ready" "kind: code" "epic: core"
  dash_fx_item stories/api.md "Wire the API" "status: review" "kind: code" "epic: core" "prs: https://github.com/o/proj/pull/11"
  dash_fx_item stories/cli.md "Ship the CLI" "status: blocked" "kind: code" "epic: core" "depends_on: [api]"
  dash_fx_item stories/key.md "Create the deploy key" "status: ready" "kind: lead" "epic: core"
  printf '\n**You:** create the deploy key in the vault\n' >> "${p}/board/stories/key.md"
  dash_fx_item stories/lexer.md "Lexer" "status: ready" "kind: code" "epic: core"
  dash_fx_item stories/tokens.md "Tokens" "status: ready" "kind: code" "epic: core"
  dash_fx_git 4320 add -A; dash_fx_git 4320 commit -qm board
  for s in lexer:2880:9 tokens:90:10; do
    IFS=: read -r s m n <<< "${s}"
    dash_fx_git "$((m + 5))" checkout -q -b "story/${s}"
    dash_fx_git "$((m + 5))" rm -q "board/stories/${s}.md"
    echo "${s}" > "${p}/${s}.txt"; dash_fx_git "$((m + 5))" add "${s}.txt"
    dash_fx_git "$((m + 5))" commit -qm "${s}"
    dash_fx_git "${m}" checkout -q main
    dash_fx_git "${m}" merge -q --no-ff -m "Merge pull request #${n} from o/story/${s}" "story/${s}"
  done
  printf 'w1:p1 conductor\nw1:p2 parser\n' > "${p}/.swarm/state/core"
  printf '2026-10-10\tconduct\tconduct-core\tclaude\topus\thigh\ts-1\n2026-10-10\tcode\tparser\tclaude\topus\thigh\ts-2\n' > "${p}/.swarm/agents.tsv"
  dash_fx_session s-1 2 400000 50000 Bash
  dash_fx_session s-2 6 1500000 300000 Edit
  {
    printf '%s\tfinish\tlexer\tw1:p1\tok\n' "$(dash_fx_at 2870)"
    printf '%s\tconduct\tcore\tw0:p1\tok\n' "$(dash_fx_at 180)"
    printf '%s\treview\tapi\tw1:p1\tok\n' "$(dash_fx_at 120)"
    printf '%s\tfinish\ttokens\tw1:p1\tok\n' "$(dash_fx_at 85)"
    printf '%s\tstory\tparser\tw1:p1\tok\n' "$(dash_fx_at 60)"
  } > "${p}/.swarm/events.tsv"

  printf '[{"sessionId":"s-1","status":"busy"},{"sessionId":"s-2","status":"busy"}]' > "${ROOT}/claude.json"
  # claude as tests/claude_stub.sh answers it, written here: diff_run_test.sh copies only the
  # fixture files into its trees.
  cat > "${bin}/claude" <<'STUB'
#!/bin/sh
case "$*" in
  --version) echo '2.1.296 (Claude Code)' ;;
  "agents --json") cat "${CLAUDE_STUB_AGENTS}" ;;
  *) echo "claude stub: unexpected call: $*" >&2; exit 1 ;;
esac
STUB
  for s in stty tput; do printf '#!/bin/sh\nexit 1\n' > "${bin}/${s}"; done
  cat > "${ROOT}/herdr-stub" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"conduct-core","agent_status":"working","pane_id":"w1:p1","agent_session":{"value":"s-1"}},{"name":"parser","agent_status":"working","pane_id":"w1:p2","agent_session":{"value":"s-2"}}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w1:p1","tab_id":"w1:t1"},{"pane_id":"w1:p2","tab_id":"w1:t1"}]}}' ;;
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"proj"}]}}' ;;
  "tab list") echo '{"result":{"tabs":[{"tab_id":"w1:t1","label":"core"}]}}' ;;
  *) exit 1 ;;
esac
STUB
  cat > "${ROOT}/gh-stub" <<'STUB'
#!/bin/sh
case "$1 $2 $3" in
  "pr view https://github.com/o/proj/pull/11") echo '{"state":"OPEN","mergeStateStatus":"CLEAN","updatedAt":"2026-10-10T10:00:00Z","statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}]}' ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "${bin}/"* "${ROOT}/herdr-stub" "${ROOT}/gh-stub"
  FX_GH="${ROOT}/gh-stub"; FX_HERDR="${ROOT}/herdr-stub"
  FX_CWD="${p}"
  FX_ENV=("PATH=${bin}:${PATH}" "SWARM_DASH_NOW=${DASH_FX_NOW}" TZ=UTC LC_COLLATE=C DASH_W=100
    SWARM_NO_CI_REFRESH=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    "CLAUDE_PROJECTS_DIR=${ROOT}/projects" "CLAUDE_STUB_AGENTS=${ROOT}/claude.json")
  # shellcheck disable=SC2016 # expanded by the command's own bash
  FX_CMD=(bash -c 'bash "$1" dash; rc=$?
    for f in "${TMPDIR}"/swarm-dash-3-*; do case "${f##*-}" in *[!0-9]*) ;; *) mv "${f}" "${TMPDIR}/swarm-dash-3-<key>" ;; esac; done
    exit "${rc}"' fx_dash "${TREE}/bin/swarm.sh")
}
