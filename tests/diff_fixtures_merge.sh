# shellcheck shell=bash
# diff_fixtures_merge.sh — tests/diff_run.sh's merge fixtures: each runs the tree under test's own
# swarm.sh merge on a project merge_fixture.sh builds (fresh, its gh, herdr and claude stubs), with
# every stub answer fixed. Not merge_fixture.sh's merge(), which runs the harness checkout's swarm.sh
# and folds stderr into stdout: the command here is the tree's, with merge()'s env (SWARM_MERGE_POLL=0
# and the zero waits), so no poll count follows the clock. diff_run.sh sources this file, and every
# other tests/diff_fixtures_*.sh, by a glob; its header says what a fixture sets.
# shellcheck disable=SC2034,SC2154 # diff_run.sh reads the FX_ settings; merge_fixture.sh sets P, FX, URL and the rest

DIFF_MERGE_FIXTURE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/merge_fixture.sh"

# diff_merge_project [config line]... — merge_fixture.sh's project under ${ROOT}, fresh with these
# config lines: story s in review on ${URL}, head ${H1} green, no merge queue, and CI on the merge
# commit ${M} green. The command runs in the project, with the stubs as gh and herdr and the
# claude stub first on PATH.
diff_merge_project() {
  export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
  # shellcheck source=tests/merge_fixture.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
  . "${DIFF_MERGE_FIXTURE}"
  fresh "$@"
  FX_CWD="${P}"; FX_GH="${ROOT}/bin/gh"; FX_HERDR="${ROOT}/bin/herdr"
  # merge()'s env, and merge_fixture.sh's git config for tags. Every CI wait ends on its first read,
  # so the CI limit only bounds a slow machine.
  FX_ENV=("PATH=${ROOT}/bin:${PATH}" SWARM_MERGE_POLL=0 SWARM_MERGE_READ_WAIT=0 SWARM_MERGE_CI_GRACE=0
    SWARM_MERGE_CI_SECONDS=60 SWARM_RELEASE_WAIT=0 "GIT_CONFIG_COUNT=${GIT_CONFIG_COUNT}"
    "GIT_CONFIG_KEY_0=${GIT_CONFIG_KEY_0}" "GIT_CONFIG_VALUE_0=${GIT_CONFIG_VALUE_0}"
    "GIT_CONFIG_KEY_1=${GIT_CONFIG_KEY_1}" "GIT_CONFIG_VALUE_1=${GIT_CONFIG_VALUE_1}")
}
# diff_merge <args>... — the command: the tree's swarm.sh merge <args>.
diff_merge() { FX_CMD=(bash "${TREE}/bin/swarm.sh" merge "$@"); }

# A direct merge: squash at ${H1}, CI green on ${M}, reconcile finishes s.
fx_merge_direct() { diff_merge_project; diff_merge "${URL}"; }

# diff_queue_read <file> <state> <isInMergeQueue> <mergeCommit> <mergeQueueEntry> — one read of the
# PR in merge queue's api graphql query, at head ${H1}, with no removal from the queue.
diff_queue_read() {
  printf '{"data":{"repository":{"pullRequest":{"id":"PR_7","state":"%s","headRefOid":"%s","isInMergeQueue":%s,"autoMergeRequest":null,"mergeCommit":%s,"mergeQueueEntry":%s,"timelineItems":{"nodes":[]}}}}}\n' \
    "$2" "${H1}" "$3" "$4" "$5" > "$1"
}

# A merge queue on main: the enqueue (--auto), one read with the PR's group in the queue at ${g} (its
# checks green), then one that reads it merged at ${M}.
fx_merge_queue() {
  local g=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  diff_merge_project
  echo '{"data":{"repository":{"mergeQueue":{"id":"MQ_1"}}}}' > "${FX}/mq"
  checks "${FX}/${g}.checks" "$(run test completed success)"; statuses "${FX}/${g}.status"
  diff_queue_read "${FX}/queue.1" OPEN true null "{\"state\":\"AWAITING_CHECKS\",\"headCommit\":{\"oid\":\"${g}\"}}"
  diff_queue_read "${FX}/queue.2" MERGED false "{\"oid\":\"${M}\"}" null
  diff_merge "${URL}"
}

# A board PR (--board): its one file is on the board, and no story names it.
fx_merge_board() { diff_merge_project; rm "${S}"; diff_merge --board "${URL}"; }

# A story marked costs: money, under merge = agent: held for the user, with no pr merge.
fx_merge_money_hold() {
  diff_merge_project "merge = agent"; item s "status: review" "prs: ${URL}" "costs: money"
  diff_merge --head "${H1}" "${URL}"
}

# Red CI on main: the merge goes through, e2e fails on ${M}, and fix_main writes its story.
fx_merge_red_main() {
  diff_merge_project; checks "${FX}/${M}.checks" "$(run test completed success)" "$(run e2e completed failure)"
  diff_merge "${URL}"
}

# Merged elsewhere while this run waited: main gained bin/x.sh after ${H1}'s CI ran, so merge has GitHub
# merge main in (head ${H3}, a web-flow merge of ${H1} and main's ${B}), and the PR reads MERGED once
# ${H3}'s checks are read. merge says so, makes no pr merge and reconciles.
fx_merge_elsewhere() {
  local h3=3333333333333333333333333333333333333333 b=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb x pr
  x='{"filename":"bin/x.sh","status":"modified","sha":"bbbbbbb"}'; pr='{"filename":"bin/pr.sh","status":"modified","sha":"p1"}'
  diff_merge_project
  echo "{\"ahead_by\":1,\"files\":[${x}]}" > "${FX}/behind.${H1}"; echo '{"ahead_by":1,"files":[{"filename":"bin/pr.sh","status":"modified"}]}' > "${FX}/behind.${h3}"
  echo "${h3}" > "${FX}/update-head.${H1}"; echo '{"message":"Updating pull request branch."}' > "${FX}/update"
  printf '{"committer":{"login":"web-flow"},"commit":{"verification":{"verified":true}},"parents":[{"sha":"%s"},{"sha":"%s"}]}\n' "${H1}" "${b}" > "${FX}/commit.${h3}"
  echo "{\"files\":[${x}]}" > "${FX}/compare.${H1}...${h3}"; echo "{\"files\":[${x}]}" > "${FX}/compare.${H1}...${b}"
  echo "{\"files\":[${pr}]}" > "${FX}/compare.${b}...${H1}"
  printf '{"commit":{"sha":"%s"}}\n' "${b}" > "${FX}/basehead"
  checks "${FX}/${h3}.checks" "$(run test completed success)"; statuses "${FX}/${h3}.status"
  echo "echo MERGED > '${FX}/state'" > "${FX}/on-checks.${h3}"
  diff_merge "${URL}"
}
