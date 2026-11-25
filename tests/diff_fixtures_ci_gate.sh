# shellcheck shell=bash
# diff_fixtures_ci_gate.sh — tests/diff_run.sh's ci_gate fixtures: each runs a command of the tree under
# test that reads CI through bin/lib/ci_gate.py, other than merge (tests/diff_fixtures_merge.sh): wait-pr,
# review-agent --recheck, review --head and next's queued: line. Each runs on the project
# tests/merge_fixture.sh builds (fresh, its gh, herdr and claude stubs), with every stub answer fixed,
# and names ci_gate's check-runs read on the head it judges in FX_CALLS, so a run that never reaches
# ci_gate is red. diff_run.sh sources this file, and every other tests/diff_fixtures_*.sh, by a glob;
# its header says what a fixture sets.
# shellcheck disable=SC2034,SC2154 # diff_run.sh reads the FX_ settings; merge_fixture.sh sets P, FX, URL and the rest

DIFF_CI_GATE_FIXTURE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/merge_fixture.sh"

# diff_ci_gate_project — merge_fixture.sh's project under ${ROOT}, fresh: story s in review on ${URL},
# head ${H1} green. The command runs in the project, with the stubs as herdr and, through gh-jq, gh.
# gh-jq runs the gh stub, and for a pr view, pr list or repo view applies the call's -q or --jq filter
# with jq, as gh would: the stub applies only pr view's -q. Before a check-runs read, with
# ${FX}/checks-age, it writes that head's one green check run as finished 45 minutes before the read,
# so ci_gate age's whole minutes are the same however long the run takes to reach it.
# wait-pr polls once a second, which leaves its poll cache off and keeps a tree whose ci_gate never
# passes to one read a second. Every CI wait ends on a read the fixture fixes: the CI limit only bounds
# a slow machine, or such a tree.
diff_ci_gate_project() {
  export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
  # shellcheck source=tests/merge_fixture.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
  . "${DIFF_CI_GATE_FIXTURE}"
  fresh
  cat > "${ROOT}/gh-jq" <<STUB
#!/usr/bin/env bash
FX="${FX}"; GH="${ROOT}/bin/gh"
STUB
  cat >> "${ROOT}/gh-jq" <<'STUB'
case "$1 $2" in
  "pr view"|"pr list"|"repo view") ;;
  "api --paginate")
    case "$3" in */check-runs*)
      if [ -e "${FX}/checks-age" ]; then
        sha="${3#*/commits/}"; sha="${sha%%/*}"; t=$(($(date +%s) - 2700)); f=+%Y-%m-%dT%H:%M:%SZ
        at="$(date -u -d "@${t}" "${f}" 2>/dev/null || date -u -r "${t}" "${f}")"
        printf '{"total_count":1,"check_runs":[{"name":"test","status":"completed","conclusion":"success","html_url":"https://github.com/o/r/runs/test","completed_at":"%s"}]}\n' "${at}" > "${FX}/${sha}.checks"
      fi ;;
    esac
    exec "${GH}" "$@" ;;
  *) exec "${GH}" "$@" ;;
esac
q=""; args=()
while [ $# -gt 0 ]; do
  case "$1" in -q|--jq) q="$2"; shift 2 ;; *) args+=("$1"); shift ;; esac
done
[ -n "${q}" ] || exec "${GH}" "${args[@]}"
out="$("${GH}" "${args[@]}")" || exit
printf '%s\n' "${out}" | jq -r "${q}"
STUB
  chmod +x "${ROOT}/gh-jq"
  FX_CWD="${P}"; FX_GH="${ROOT}/gh-jq"; FX_HERDR="${ROOT}/bin/herdr"
  FX_ENV=("PATH=${ROOT}/bin:${PATH}" SWARM_MERGE_POLL=1 SWARM_MERGE_CI_SECONDS=120)
}

# diff_ci_gate_git <args>... — git with a fixed author, committer and date, and no signing or hooks,
# so each commit a fixture makes has the same SHA on every run and both trees.
diff_ci_gate_git() {
  GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z \
    git -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"
}

# diff_ci_gate_head <sha> — the PR's head is <sha>, with one green check run, no status, and no
# workflow listed at it, so ci_gate head waits on no pull_request workflow.
diff_ci_gate_head() {
  echo "$1" > "${FX}/head"; echo '[]' > "${FX}/workflows.$1"
  checks "${FX}/$1.checks" "$(run test completed success)"; statuses "${FX}/$1.status"
}

# diff_ci_gate_calls <sha> — FX_CALLS: ci_gate's check-runs read on <sha>, as the calls stream logs it
# (the ? quoted). The backslash is doubled because diff_run.sh hands each FX_CALLS value to awk -v,
# which reads \? as ?.
diff_ci_gate_calls() { FX_CALLS=("gh api --paginate repos/o/r/commits/$1/check-runs\\\\?per_page=100"); }

# wait-pr on a green head: the head read, then ci_gate head finds ${H1}'s one check green; exit 0.
fx_ci_gate_wait_pr_green() {
  diff_ci_gate_project
  diff_ci_gate_calls "${H1}"
  FX_CMD=(bash "${TREE}/bin/swarm.sh" wait-pr --head "${H1}" "${URL}")
}

# wait-pr on a pending head: the first read finds ${H1}'s check in progress, the next a second later
# finds it green; exit 0 after a pending: line.
fx_ci_gate_wait_pr_pending() {
  diff_ci_gate_project
  checks "${FX}/${H1}.checks.1" "$(run test in_progress)"
  diff_ci_gate_calls "${H1}"
  FX_CMD=(bash "${TREE}/bin/swarm.sh" wait-pr --head "${H1}" "${URL}")
}

# review-agent --recheck, run from review-s's own pane: round 1's findings on <old> name doc.md:3, the
# builder's <new> rewrites only that line, and ci_gate head finds <new> green, so the recheck passes and
# writes the findings file for <new>.
fx_ci_gate_recheck() {
  local old new wt="${ROOT}/proj-wt/s"
  diff_ci_gate_project
  seq 1 10 | sed 's/^/line /' > "${P}/doc.md"
  diff_ci_gate_git -C "${P}" add doc.md; diff_ci_gate_git -C "${P}" commit -q -m doc
  old="$(git -C "${P}" rev-parse HEAD)"
  diff_ci_gate_git -C "${P}" worktree add -q -b story/s "${wt}" "${old}"
  sed 's/^line 3$/line three/' "${wt}/doc.md" > "${wt}/doc.new"; mv "${wt}/doc.new" "${wt}/doc.md"
  diff_ci_gate_git -C "${wt}" commit -q -am fix
  new="$(git -C "${wt}" rev-parse HEAD)"
  diff_ci_gate_head "${new}"
  mkdir -p "${P}/.swarm/reviews"
  echo "${old}" > "${P}/.swarm/reviews/s.head"
  printf '%s\n' "head: ${old}" "" "## Findings" "" "doc.md:3 misstates it" > "${P}/.swarm/reviews/s.round.md"
  # review-s, in pane w:r, which this project's tab record names.
  echo 'w:r review-s' > "${P}/.swarm/state/review-s"; echo 'review-s w:r' >> "${ROOT}/agents"
  FX_ENV+=(HERDR_ENV=1 HERDR_PANE_ID=w:r)
  diff_ci_gate_calls "${new}"
  FX_CMD=(bash "${TREE}/bin/swarm.sh" review-agent --recheck s "${URL}" "${old}" doc.md:3)
}

# review --head <r>: the PR's head <n> is git's own clean merge of main into the reviewed head <r>, so
# review_heads fetches both from origin (o/r.git, the clone ${ROOT}/r), walks the merge, and takes <n>
# once ci_gate head finds it green: an accepted: line, and s stays in review.
fx_ci_gate_review_head() {
  local b0 r b1 n
  diff_ci_gate_project
  git init -q --bare "${ROOT}/o/r.git"; git -C "${P}" remote set-url origin "${ROOT}/o/r.git"; ln -s proj "${ROOT}/r"
  echo a > "${P}/a.txt"; diff_ci_gate_git -C "${P}" add a.txt; diff_ci_gate_git -C "${P}" commit -q -m base
  b0="$(git -C "${P}" rev-parse HEAD)"
  diff_ci_gate_git -C "${P}" checkout -q -b story/s
  echo s > "${P}/s.txt"; diff_ci_gate_git -C "${P}" add s.txt; diff_ci_gate_git -C "${P}" commit -q -m story
  r="$(git -C "${P}" rev-parse HEAD)"
  diff_ci_gate_git -C "${P}" checkout -q -b base "${b0}"
  echo b > "${P}/b.txt"; diff_ci_gate_git -C "${P}" add b.txt; diff_ci_gate_git -C "${P}" commit -q -m main
  b1="$(git -C "${P}" rev-parse HEAD)"
  diff_ci_gate_git -C "${P}" checkout -q story/s
  diff_ci_gate_git -C "${P}" merge -q --no-ff -m "Merge main" "${b1}"
  n="$(git -C "${P}" rev-parse HEAD)"
  git -C "${P}" push -q origin "${b1}:refs/heads/main" "${n}:refs/pull/7/head"
  diff_ci_gate_head "${n}"
  printf '[{"url":"%s"}]\n' "${URL}" > "${FX}/prlist.s"
  diff_ci_gate_calls "${n}"
  FX_CMD=(bash "${TREE}/bin/swarm.sh" review s --head "${r}" "${URL}")
}

# next, inside herdr, with conductor conduct-e working on epic e and story s's PR #7 open, mergeable and
# green 45 minutes on ${H1} with no review: ci_gate age gives the minutes for next's queued: line.
# .swarm/poll-cache is a plain file, so the cache is off: an entry keeps its read's time, which differs
# on every run. The report deadline is 240 s, under diff_run.sh's 300 s timeout, so a loaded machine
# cuts none of next's reads.
fx_ci_gate_next_queued() {
  diff_ci_gate_project
  mkdir -p "${P}/docs/epics"
  printf -- '---\nstatus: active\n---\n\n# e\n' > "${P}/docs/epics/e.md"
  item s "status: review" "prs: ${URL}" "epic: e" "kind: code"
  : > "${FX}/checks-age"
  printf '[{"number":7,"url":"%s","headRefOid":"%s","headRefName":"story/s","mergeable":"MERGEABLE"}]\n' "${URL}" "${H1}" > "${FX}/prlist"
  : > "${P}/.swarm/poll-cache"
  FX_ENV+=(HERDR_ENV=1 SWARM_REPORT_SECONDS=240)
  diff_ci_gate_calls "${H1}"
  FX_CMD=(bash "${TREE}/bin/swarm.sh" next)
}
