#!/usr/bin/env bash
# lead_stop_test.sh — hooks/lead-stop.sh against stubs. The hook (and lead-session.sh, which it
# sources) is copied beside a bin/swarm.sh stub that prints $STUB_NEXT for _step (next's step) and
# $STUB_BOARD for config (_step sleeps $STUB_SLEEP first, or exits 1 after with STUB_FAIL; config sleeps $STUB_CONFIG_SLEEP, or fails with STUB_CONFIG_FAIL), and a
# herdr stub (HERDR_BIN_PATH) whose agent list is $STUB_AGENTS. `agents` writes the project's
# .swarm/state panes and STUB_AGENTS together. Each stub records the command it ran; every case
# checks the hook's stdout and, in run, the events.tsv line it left.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/hooks/lead-stop.sh"
root="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${root}"' EXIT
root="$(cd "${root}" && pwd -P)"   # as git prints it, so paths compare
export CLAUDE_CONFIG_DIR="${root}/claude-config"   # under its own root, so parallel runs share no ~/.claude
project="${root}/project"
mkdir -p "${root}/plugin/hooks" "${root}/plugin/bin" "${project}/.claude/swarm" "${project}/docs/stories" "${project}/docs/epics"
: > "${project}/.claude/swarm/config"
cp "${HOOK}" "$(dirname "${HOOK}")/lead-session.sh" "${root}/plugin/hooks/"
cat > "${root}/plugin/bin/swarm.sh" <<'EOF'
#!/usr/bin/env bash
echo "$1" >> "${STUB_RAN}"; echo "${SWARM_PROJECT}" > "${STUB_RAN}.project"
case "$1" in
  _step) [[ -z "${STUB_SLEEP:-}" ]] || sleep "${STUB_SLEEP}"
        printf '%s\nwhy\n' "${STUB_NEXT}"
        [[ -z "${STUB_FAIL:-}" ]] || exit 1 ;;   # after its line, so only the exit status says it failed
  config) [[ -z "${STUB_CONFIG_SLEEP:-}" ]] || sleep "${STUB_CONFIG_SLEEP}"
          [[ -z "${STUB_CONFIG_FAIL:-}" ]] || exit 1
          echo "${STUB_BOARD}" ;;
esac
EOF
cat > "${root}/plugin/herdr" <<'EOF'
#!/usr/bin/env bash
echo herdr >> "${STUB_RAN}"
[[ -z "${STUB_HERDR_FAIL:-}" ]] || exit 1
printf '{"result":{"agents":%s}}\n' "${STUB_AGENTS:-[]}"
EOF
chmod +x "${root}/plugin/bin/swarm.sh" "${root}/plugin/herdr"
# A total deadline of 45 x 0.05 = 2.25 seconds.
export STUB_RAN="${root}/ran" STUB_BOARD="${project}/docs" SWARM_SLEEP_SCALE=0.05 HERDR_ENV=1 HERDR_BIN_PATH="${root}/plugin/herdr"
unset SWARM_AGENT SWARM_GH_CALLER SWARM_PROJECT
fails=0 cases=0

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}

# agents [<name> <tab> <status>]... — herdr runs each agent in a pane of tab <tab> (a .swarm/state
# line); status EMPTY writes the pane with no agent in it. Read by the next run, which clears them.
agents() {
  local json="" n=0
  mkdir -p "${project}/.swarm/state"
  while [[ $# -gt 0 ]]; do
    n=$((n + 1)); echo "w1:p${n} $1" >> "${project}/.swarm/state/$2"
    [[ "$3" == EMPTY ]] || json+="${json:+,}{\"name\":\"$1\",\"pane_id\":\"w1:p${n}\",\"agent_status\":\"$3\"}"
    shift 3
  done
  export STUB_AGENTS="[${json}]"
}

# run <events line, or nothing> [<stop_hook_active>] — the hook on a Stop input from $CWD (the
# project by default); stdout in out, the stubs' commands in ran. It checks the one events.tsv line
# the run left in the project, or that it left none, then clears the agents.
run() {
  local events="${project}/.swarm/events.tsv" ev
  rm -f "${events}" "${STUB_RAN}"
  out="$(printf '{"hook_event_name":"Stop","cwd":"%s","stop_hook_active":%s}' "${CWD:-${project}}" "${2:-false}" \
    | "${root}/plugin/hooks/lead-stop.sh")"
  ev="$(cut -f2,3,5 "${events}" 2>/dev/null | tr '\t' ' ')" || ev=""
  ran="$(cat "${STUB_RAN}" 2>/dev/null | tr '\n' ' ')" || ran=""
  cases=$((cases + 1))
  check "case ${cases} (${STUB_NEXT:-}) logs: ${1:-nothing}" [ "${ev}" = "$1" ]
  rm -rf "${project}/.swarm/state"; export STUB_AGENTS="[]"
}

# blocked <line> — out is the block decision naming <line>.
blocked() {
  [[ "$(python3 -c 'import json, sys; d = json.loads(sys.argv[1]); print(d["decision"], d["reason"])' "${out}" 2>/dev/null)" \
    == "block next says: $1. Start it now, or tell the user why it cannot start." ]]
}

STUB_NEXT="plan-epic X" run "lead-stop plan-epic blocked"
check "plan-epic with no agent blocks, naming the line" blocked "plan-epic X"

agents survey scope-X working
STUB_NEXT="plan-epic X" run "lead-stop plan-epic allowed"
check "plan-epic with survey in scope-X allows" [ -z "${out}" ]

agents survey scope-X EMPTY
STUB_NEXT="plan-epic X" run "lead-stop plan-epic blocked"
check "plan-epic with survey's pane empty blocks" blocked "plan-epic X"
agents survey scope-X unknown
STUB_NEXT="plan-epic X" run "lead-stop plan-epic blocked"
check "plan-epic with survey unknown to herdr blocks" blocked "plan-epic X"

STUB_NEXT="plan-epic X" STUB_HERDR_FAIL=1 run "lead-stop plan-epic allowed"
check "plan-epic when herdr's agent list fails allows" [ -z "${out}" ]
STUB_NEXT="plan-epic X" STUB_AGENTS='"junk"' run "lead-stop plan-epic allowed"
check "plan-epic when herdr's agent list is not one allows" [ -z "${out}" ]
STUB_NEXT="plan-epic X" HERDR_ENV='' run "lead-stop plan-epic allowed"
check "plan-epic outside herdr allows" [ -z "${out}" ]

agents conduct-e safer working
STUB_NEXT="conduct E" run "lead-stop conduct allowed"
check "conduct with its conductor working allows" [ -z "${out}" ]

agents other other working
STUB_NEXT="story s1" run "lead-stop story blocked"
check "story with only another agent blocks" blocked "story s1"
agents s1 elsewhere working
STUB_NEXT="story s1" run "lead-stop story allowed"
check "story with its builder working allows" [ -z "${out}" ]

long="a-story-slug-well-past-thirty-two-characters"
agents "${long:0:32}" epic working
STUB_NEXT="resume ${long}" run "lead-stop resume allowed"
check "resume with a slug past 32 characters finds its builder" [ -z "${out}" ]
agents "conduct-${long:0:24}" epic working
STUB_NEXT="conduct ${long}" run "lead-stop conduct allowed"
check "conduct with an epic past 24 characters finds its conductor" [ -z "${out}" ]
agents big_slug epic working
STUB_NEXT="story Big_Slug" run "lead-stop story allowed"
check "story finds its builder by agent_name's lowercase name" [ -z "${out}" ]

agents critic scope-X-2 working
STUB_NEXT="plan-epic X" run "lead-stop plan-epic allowed"
check "plan-epic with an agent in scope-X-2 allows" [ -z "${out}" ]
agents critic scope-X2 working other scope-X-y working
STUB_NEXT="plan-epic X" run "lead-stop plan-epic blocked"
check "plan-epic with agents in scope-X2 and scope-X-y only blocks" blocked "plan-epic X"
agents "" other working
STUB_NEXT="plan-epic X" run "lead-stop plan-epic blocked"
check "plan-epic with only a nameless agent elsewhere blocks" blocked "plan-epic X"

CWD="${project}/docs/stories" STUB_NEXT="plan-epic X" run "lead-stop plan-epic blocked"
check "from a folder inside the project it blocks as at its root" blocked "plan-epic X"
check "and runs swarm.sh on the project" [ "$(cat "${STUB_RAN}.project")" = "${project}" ]

agents survey scope-X idle
STUB_NEXT="plan-epic X" run "lead-stop plan-epic allowed"
check "plan-epic with survey idle in scope-X allows" [ -z "${out}" ]
mkdir -p "${project}/.swarm/X"; echo '{}' > "${project}/.swarm/X/survey.json"
echo "# X" > "${project}/docs/epics/X.md"; touch -t 202001010000 "${project}/docs/epics/X.md"
STUB_NEXT="plan-epic X" run "lead-stop plan-epic blocked"
check "plan-epic with only survey's answer (the plan not yet verified) blocks" blocked "plan-epic X"
echo '{}' > "${project}/.swarm/X/critic.json"
STUB_NEXT="plan-epic X" run "lead-stop plan-epic allowed"
check "plan-epic with its planners closed and the critic's answer in .swarm/X allows" [ -z "${out}" ]
STUB_NEXT="plan-epic X" STUB_CONFIG_FAIL=1 run "lead-stop plan-epic allowed"
check "plan-epic when config board_dir fails allows" [ -z "${out}" ]
touch -t 201901010000 "${project}/.swarm/X/critic.json"
STUB_NEXT="plan-epic X" run "lead-stop plan-epic blocked"
check "plan-epic with only an answer older than the epic (a previous plan) blocks" blocked "plan-epic X"
echo '{"cut' > "${project}/.swarm/X/critic.json" # vacuous-test: ok, a cut-off answer on purpose
STUB_NEXT="plan-epic X" run "lead-stop plan-epic blocked"
check "plan-epic with only an answer that is not JSON blocks" blocked "plan-epic X"
rm -rf "${project}/.swarm/X" "${project}/docs/epics/X.md"

STUB_NEXT="plan-hld H" run "lead-stop plan-hld blocked"
check "plan-hld with no agent blocks, naming the line" blocked "plan-hld H"
agents planner plan-H working
STUB_NEXT="plan-hld H" run "lead-stop plan-hld allowed"
check "plan-hld with an agent in plan-H allows" [ -z "${out}" ]
agents critic plan-H-2 working
STUB_NEXT="plan-hld H" run "lead-stop plan-hld allowed"
check "plan-hld with an agent in plan-H-2 allows" [ -z "${out}" ]
agents survey scope-H working
STUB_NEXT="plan-hld H" run "lead-stop plan-hld blocked"
check "plan-hld with an agent in scope-H only blocks" blocked "plan-hld H"
mkdir -p "${project}/.swarm/H" "${project}/docs/hld"
echo "# H" > "${project}/docs/hld/H.md"; touch -t 202001010000 "${project}/docs/hld/H.md"
echo '{}' > "${project}/.swarm/H/critic.json"
STUB_NEXT="plan-hld H" run "lead-stop plan-hld allowed"
check "plan-hld with the critic's answer newer than the HLD allows" [ -z "${out}" ]
touch -t 201901010000 "${project}/.swarm/H/critic.json"
STUB_NEXT="plan-hld H" run "lead-stop plan-hld blocked"
check "plan-hld with only an answer older than the HLD blocks" blocked "plan-hld H"
echo '{"cut' > "${project}/.swarm/H/critic.json" # vacuous-test: ok, a cut-off answer on purpose
STUB_NEXT="plan-hld H" run "lead-stop plan-hld blocked"
check "plan-hld with only an answer that is not JSON blocks" blocked "plan-hld H"
rm -rf "${project}/.swarm/H" "${project}/docs/hld"

STUB_NEXT="hld H" run "lead-stop hld blocked"
check "hld with no _board-finish-H blocks, naming the line" blocked "hld H"
mkdir -p "${root}/project-wt/_board-finish-H"
STUB_NEXT="hld H" run "lead-stop hld allowed"
check "hld with _board-finish-H allows" [ -z "${out}" ]
STUB_NEXT="hld G" run "lead-stop hld blocked"
check "hld G with only _board-finish-H blocks" blocked "hld G"
rm -rf "${root}/project-wt"

start=$(date +%s)
STUB_NEXT="plan-epic X" STUB_SLEEP=1.5 STUB_CONFIG_SLEEP=1.5 run "lead-stop plan-epic allowed"
check "next and config board_dir past the one deadline together allow" [ -z "${out}" ]
check "that deadline ends the hook within 5 seconds" [ $(($(date +%s) - start)) -lt 5 ]

g() { git -C "${project}" -c user.name=t -c user.email=t@t "$@"; }
g init -q && g add .claude && g commit -q -m init && g branch board/scope-X   # board-pr start: no stories yet
STUB_NEXT="plan-epic X" run "lead-stop plan-epic allowed"
check "plan-epic with board/scope-X and no origin/HEAD to compare (a lookup error) allows" [ -z "${out}" ]
g update-ref refs/remotes/origin/main HEAD && g symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
STUB_NEXT="plan-epic X" run "lead-stop plan-epic blocked"
check "plan-epic with board/scope-X at the base (started, no stories) blocks" blocked "plan-epic X"
g update-ref refs/heads/board/scope-X "$(g commit-tree -p HEAD -m stories "HEAD^{tree}")"
STUB_NEXT="plan-epic X" run "lead-stop plan-epic allowed"
check "plan-epic with stories committed on board/scope-X (planned alone, waiting on approval) allows" [ -z "${out}" ]
STUB_NEXT="plan-epic Y" run "lead-stop plan-epic blocked"
check "plan-epic Y with only board/scope-X blocks" blocked "plan-epic Y"
g branch board/plan-H   # board-pr start: at the base
STUB_NEXT="plan-hld H" run "lead-stop plan-hld blocked"
check "plan-hld with board/plan-H at the base blocks" blocked "plan-hld H"
g update-ref refs/heads/board/plan-H "$(g commit-tree -p HEAD -m epics "HEAD^{tree}")"
STUB_NEXT="plan-hld H" run "lead-stop plan-hld allowed"
check "plan-hld with commits on board/plan-H allows" [ -z "${out}" ]
g worktree add -q "${root}/wt" -b wt
CWD="${root}/wt" STUB_NEXT="plan-epic Y" run ""
check "from a worktree (not the lead) it allows" [ -z "${out}" ]
check "and runs nothing" [ -z "${ran}" ]
check "and logs nothing in the worktree" [ ! -e "${root}/wt/.swarm/events.tsv" ]
CWD="${root}/wt/.claude" STUB_NEXT="plan-epic Y" SWARM_PROJECT="${project}" run ""
check "from a worktree folder with SWARM_PROJECT set it runs nothing" [ -z "${out}${ran}" ]
g worktree remove --force "${root}/wt"
rm -rf "${project}/.git"

# A plan PR that closed unmerged: the real swarm.sh board-pr done, in a project of its own with a
# local bare origin and a gh stub listing ${root}/prs, clears its critic's answer, so the hook no
# longer counts that plan as drafted. The run() above checks the project it names.
lead_project="${project}" project="${root}/bp"
mkdir -p "${project}/.claude/swarm" "${project}/docs/epics" "${project}/docs/hld" "${root}/bp-bin"
: > "${project}/.claude/swarm/config"
echo .swarm/ > "${project}/.gitignore"
echo "# x" > "${project}/docs/epics/x.md"; echo "# h" > "${project}/docs/hld/h.md"
touch -t 202001010000 "${project}/docs/epics/x.md" "${project}/docs/hld/h.md"
git init -q --bare "${root}/bp-origin.git"; git -C "${root}/bp-origin.git" symbolic-ref HEAD refs/heads/main
g init -q -b main && g add -A && g commit -q -m init && g remote add origin "${root}/bp-origin.git" && g push -q -u origin main
# shellcheck disable=SC2016 # $1 and $2 are the stub's
printf '#!/usr/bin/env bash\ncase "$1 $2" in "pr list") cat "%s" ;; *) exit 1 ;; esac\n' "${root}/prs" > "${root}/bp-bin/gh"
chmod +x "${root}/bp-bin/gh"
# bpr <args> — the real swarm.sh board-pr on this project; its exit status in bpr_rc.
bpr() {
  bpr_rc=0
  (cd "${project}" && env -u HERDR_PANE_ID PATH="${root}/bp-bin:${PATH}" GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t bash "$(dirname "${HOOK}")/../bin/swarm.sh" board-pr "$@" >/dev/null 2>&1) || bpr_rc=$?
}
# closed_plan <step> <name> <subject> — a plan drafted on board/<name>, reported (the critic's answer
# in .swarm/<subject>), its PR closed unmerged, then board-pr done.
closed_plan() {
  local wt="${root}/bp-wt/_board-$2"
  bpr start "$2"
  echo plan > "${wt}/docs/plan.md"; git -C "${wt}" add -A; git -C "${wt}" -c user.name=t -c user.email=t@t commit -q -m plan
  mkdir -p "${project}/.swarm/$3"; echo '{}' > "${project}/.swarm/$3/critic.json"
  printf '[{"state":"CLOSED","headRefOid":"%s"}]\n' "$(g rev-parse "board/$2")" > "${root}/prs"
  bpr "done" "$2"
}
export STUB_BOARD="${project}/docs"
mkdir -p "${project}/.swarm/x"; echo '{}' > "${project}/.swarm/x/critic.json"
STUB_NEXT="plan-epic x" run "lead-stop plan-epic allowed"
check "plan-epic with a reported plan and no board PR yet allows" [ -z "${out}" ]
closed_plan plan-epic scope-x x
check "board-pr done scope-x after its PR closed exits 0" [ "${bpr_rc}" -eq 0 ]
STUB_NEXT="plan-epic x" run "lead-stop plan-epic blocked"
check "plan-epic after its plan PR closed and board-pr done blocks" blocked "plan-epic x"
closed_plan plan-hld plan-h h
check "board-pr done plan-h after its PR closed exits 0" [ "${bpr_rc}" -eq 0 ]
STUB_NEXT="plan-hld h" run "lead-stop plan-hld blocked"
check "plan-hld after its plan PR closed and board-pr done blocks" blocked "plan-hld h"
project="${lead_project}"; export STUB_BOARD="${project}/docs"

agents conduct-e safer working
STUB_NEXT="collect conduct-e" run "lead-stop collect blocked"
check "collect blocks while its conductor still works: the report waits on the lead" blocked "collect conduct-e"
STUB_NEXT="collect conduct-e" run "lead-stop collect blocked"
check "collect blocks with its conductor gone" blocked "collect conduct-e"

agents conduct-backlog-proj-abc123 conduct-backlog-proj-abc123 working
STUB_NEXT="story s1" run "lead-stop story allowed"
check "story with the backlog conductor working allows" [ -z "${out}" ]
agents conduct-backlog-proj-abc123-done2 conduct-backlog-proj-abc123 "done"
STUB_NEXT="story s1" run "lead-stop story blocked"
check "story with only a retired backlog conductor blocks" blocked "story s1"

report="${project}/.swarm/conduct-backlog.report.md"
echo "not started: s1 (waits on s2's merge)" > "${report}"
touch -t 202001010000 "${project}/docs/stories" "${project}/docs/epics"
touch -t 202101010000 "${report}"   # after the board, and well before anything written below
STUB_NEXT="story s1" run "lead-stop story allowed"
check "story with the backlog report newer than every board item allows" [ -z "${out}" ]
STUB_NEXT="story s1" STUB_CONFIG_FAIL=1 run "lead-stop story allowed"
check "story when config board_dir fails allows" [ -z "${out}" ]
echo x > "${project}/docs/stories/s3.md"
STUB_NEXT="story s1" run "lead-stop story blocked"
check "story with a board item newer than the report blocks" blocked "story s1"
STUB_NEXT="resume s1" run "lead-stop resume allowed"
check "resume of a slug the report lists as not started allows" [ -z "${out}" ]
STUB_NEXT="resume s" run "lead-stop resume blocked"
check "resume of a slug the report names only as a prefix blocks" blocked "resume s"
rm -f "${report}" "${project}/docs/stories/s3.md"

for step in "wait conduct-E" gate "done"; do
  STUB_NEXT="${step}" run "lead-stop ${step%% *} allowed"
  check "${step} allows" [ -z "${out}" ]
  check "${step} looks up nothing else" [ "${ran}" = "_step " ]
done

STUB_NEXT="plan-epic X" run "" true
check "stop_hook_active allows" [ -z "${out}" ]
check "stop_hook_active runs nothing" [ -z "${ran}" ]

STUB_NEXT="plan-epic X" SWARM_AGENT=builder run ""
check "SWARM_AGENT allows" [ -z "${out}" ]
check "SWARM_AGENT runs no next" [ -z "${ran}" ]
STUB_NEXT="plan-epic X" SWARM_GH_CALLER=builder run ""
check "SWARM_GH_CALLER (any agent's) allows and runs no next" [ -z "${out}${ran}" ]

start=$(date +%s)
STUB_NEXT="plan-epic X" STUB_SLEEP=30 run "lead-stop - allowed"
check "a next past the timeout allows with empty stdout" [ -z "${out}" ]
check "the timeout ends it within 10 seconds" [ $(($(date +%s) - start)) -lt 10 ]

start=$(date +%s)
STUB_NEXT="plan-epic X" STUB_SLEEP=30 SWARM_SLEEP_SCALE=0 run "lead-stop - allowed"
check "with SWARM_SLEEP_SCALE=0 the timeout is a second, not none" [ $(($(date +%s) - start)) -lt 10 ]
check "that timeout allows with empty stdout" [ -z "${out}" ]
STUB_NEXT="plan-epic X" SWARM_SLEEP_SCALE=0 run "lead-stop plan-epic blocked"
check "with SWARM_SLEEP_SCALE=0 next still gets its second" blocked "plan-epic X"

STUB_NEXT="plan-epic X" STUB_FAIL=1 run "lead-stop - allowed"
check "a next that exits 1 allows with empty stdout" [ -z "${out}" ]

mv "${project}/.claude" "${project}/.claude-off"
STUB_NEXT="plan-epic X" run ""
check "outside a swarm project it allows and runs nothing" [ -z "${out}${ran}" ]
STUB_NEXT="plan-epic X" SWARM_PROJECT="${root}/elsewhere" run ""
check "a SWARM_PROJECT that is not one changes nothing" [ -z "${out}${ran}" ]
mkdir -p "${root}/other/.claude/swarm"; : > "${root}/other/.claude/swarm/config"
STUB_NEXT="plan-epic X" SWARM_PROJECT="${root}/other" run ""
check "a SWARM_PROJECT that is one runs the hook there" blocked "plan-epic X"
check "it logs to that project" [ "$(cut -f2,3,5 "${root}/other/.swarm/events.tsv" | tr '\t' ' ')" = "lead-stop plan-epic blocked" ]
mv "${project}/.claude-off" "${project}/.claude"

# The hook's name is swarm.sh's agent_name copied: a drift would let a builder run unseen, and the lead
# start it again.
eval "$(sed -n '/^name() {/,/^}/p' "${HOOK}")"
SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
for slug in "${long}" Big_Slug 9lives "fix main/sha:1.2" "conduct-${long}" "a.b,c" "x"; do
  check "the hook's name and swarm.sh's agent_name agree on '${slug}'" \
    [ "$(name "${slug}")" = "$(SWARM_PROJECT="${project}" "${SWARM}" _name "${slug}")" ]
done

[ "${fails}" -eq 0 ] || { echo "${fails} failed"; exit 1; }
