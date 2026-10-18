# shellcheck shell=bash

MERGE_CI_SECONDS=1800   # how long merge waits for CI on the merge commit (SWARM_MERGE_CI_SECONDS, for tests)
MERGE_POLL=20           # seconds between its reads of that CI (SWARM_MERGE_POLL)
MERGE_CI_GRACE=60       # with no workflow expected there, how long checks get to appear (SWARM_MERGE_CI_GRACE)
MERGE_READS=5           # reads of the PR after gh pr merge before its state counts as unconfirmed
MERGE_READ_WAIT=3       # seconds between those reads (SWARM_MERGE_READ_WAIT)

# ci_gate head <owner/repo> <sha> [base] — succeed when <sha> is green: at least one check run, every
# run completed as success, skipped or neutral, and every commit status success; with [base]
# (merge_admin), also every status check the base's rulesets or branch protection require present
# among them, since --admin skips GitHub's own check. Else print which checks and fail (1 red, 2 pending). It is the
# block-red-pr-merge hook's rule, which never sees a gh call made inside swarm.sh, and it fails
# closed: every page is read, and a gh error, unreadable JSON or fewer items than total_count is 3.
# ci_gate main <owner/repo> <sha> <base> <pr> <changed> <seconds> <poll> <grace> — wait, reading every
# <poll> seconds, until the merge commit <sha> is green as above (with no check run needed of its own,
# though with no workflow expected not before <grace> seconds),
# every workflow whose `on: push` covers <base> and the files PR <pr> changes (read from
# .github/workflows at <sha>) has a run on <sha>, and every workflow run on <sha> is green. A failed
# read is a missed poll; three in a row end it. Prints ok (0), red <checks> (1), timeout (<what it
# waited on>) (2) or error <why> (3); YAML it does not read is an error, never a skipped workflow.
# ci_gate files <owner/repo> <pr> <changed> — every path the PR changes, a renamed file's old path
# too; fails (3) unless there are <changed> of them.
ci_gate() {
  python3 "${SWARM_HOME}/bin/lib/ci_gate.py" "$@"
}

# merge_caller — why the pane running this may not merge, or nothing when it may. Outside herdr it
# is the lead's own session, which merges for the user under merge = human too. Inside herdr the pane
# must be one this project did not start (the lead's), or, with merge = agent, a conductor's; when the
# pane cannot be identified (no HERDR_PANE_ID, an unreadable tab record, herdr cannot list its
# agents) it may not. start_agent's guard blocks only a bare `gh pr merge`, so this is what stops a
# builder merging through swarm.sh.
merge_caller() {
  local f agents panes
  [[ -n "${HERDR_ENV:-}" ]] || return 0
  [[ -n "${HERDR_PANE_ID:-}" ]] || { echo "inside herdr with no HERDR_PANE_ID, the pane running this is unknown"; return 0; }
  [[ ! -e "${STATE_DIR}" || ( -r "${STATE_DIR}" && -x "${STATE_DIR}" ) ]] || { echo "cannot read ${STATE_DIR}, so whose pane this is is unknown"; return 0; }
  for f in "${STATE_DIR}"/*; do
    [[ ! -f "${f}" || -r "${f}" ]] || { echo "cannot read ${f}, so whose pane this is is unknown"; return 0; }
  done
  agents="$(herdr agent list 2>/dev/null)" || { echo "herdr cannot list its agents, so whose pane this is is unknown"; return 0; }
  # A here-string, not a pipe: grep -q may exit before own_panes has written all of it, and pipefail
  # would then read a match as none.
  panes="$(own_panes)"
  grep -qxF -- "${HERDR_PANE_ID}" <<< "${panes}" || return 0
  # shellcheck disable=SC2154 # assigned in another file
  if [[ "${CFG_merge}" == agent ]] && [[ "$(SWARM_PANE="${HERDR_PANE_ID}" json "any(a.get('pane_id') == e['SWARM_PANE'] and a.get('name', '').startswith('conduct-') and not a['name'].rstrip('0123456789').endswith('-done') for a in d['result']['agents'])" <<< "${agents}" 2>/dev/null)" == True ]]; then
    return 0
  fi
  echo "pane ${HERDR_PANE_ID} is one this project started, and only a conductor with merge = agent merges from one"
}

# merged_state <pr> <owner/repo> — "<state> <merge commit>" once the PR reads MERGED with one, read up
# to MERGE_READS times, MERGE_READ_WAIT apart: GitHub may take a moment to say so, and a read may
# fail. The state is unreadable when no read succeeded.
merged_state() {
  local try info state="" oid=""
  for ((try = 1; try <= MERGE_READS; try++)); do
    info="$(gh pr view "$1" --repo "$2" --json state,mergeCommit | json "d['state'] + ' ' + ((d['mergeCommit'] or {}).get('oid') or '')")" || info=unreadable
    read -r state oid <<< "${info}"
    [[ "${state}" != MERGED || ! "${oid}" =~ ^[0-9a-f]{40}$ ]] || break
    [[ ${try} -eq ${MERGE_READS} ]] || sleep "${SWARM_MERGE_READ_WAIT:-${MERGE_READ_WAIT}}"
  done
  echo "${state:-unreadable} ${oid}"
}

# merge_fail <why> — merge's one line for a refusal, then stop. main logs nothing for merge.
merge_fail() { record_event merge "${MERGE_TARGET}" "$1"; die "merge: $1"; }

# merge [--board|--release] [--head <sha>] <pr-url> — merge a green, open PR with its head pinned:
# refuse unless merge_caller allows it, the head is <sha> (with --head), a story or epic in review
# lists the URL (with merge = agent, by any route, pr_held finds nothing: whoever calls it, a PR whose
# story or stacked parent costs money is the user's) (with --board instead: the PR is in the board's own repo and every path it changes,
# old or new, is on the board; with --release: the PR is in the project's own repo and every path it
# changes is .claude-plugin/plugin.json, release_check's), and ci_gate passes on the head.
# Merge with the repo's method (squash, else merge, else rebase), --match-head-commit and, only with
# merge_admin = on, --admin; never --auto. Then wait for CI on the merge commit and, without --board or --release, run
# reconcile, even after a red main, since the PR has merged. Each step is one events.tsv line, under
# the slug (or the URL with --board or --release): merge <why> for a refusal, merge unconfirmed (...) when gh pr
# merge ran but the PR never read as merged, else merge ok, main-ci ok|red|timeout|error, then
# reconcile's own. Fails on anything but a green main.
merge_pr() {
  local only="" clash="" whose want="" url repo n info state head base changed f="" any="" p rel origin own method oid why rc=0 rrc ran=1 admin req
  while [[ $# -gt 1 ]]; do
    case "$1" in
      --board|--release) [[ -z "${only}" || "${only}" == "$1" ]] || clash=1; only="$1"; shift ;;
      --head) want="$2"; shift 2 ;;
      *) break ;;
    esac
  done
  url="${1:-}"; MERGE_TARGET="${url:--}"
  [[ -z "${clash}" ]] || merge_fail "--board and --release do not go together"
  [[ $# -eq 1 ]] || merge_fail "usage: swarm.sh merge [--board|--release] [--head <sha>] <pr-url>"
  [[ "${url}" =~ ^https://github\.com/([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)/pull/([0-9]+)$ ]] || merge_fail "not a PR URL: ${url}"
  repo="${BASH_REMATCH[1]}"; n="${BASH_REMATCH[2]}"
  [[ -z "${want}" || "${want}" =~ ^[0-9a-f]{40}$ ]] || merge_fail "--head takes a full 40-character SHA, not '${want}'"
  why="$(merge_caller)" || why="cannot tell whose pane this is"
  [[ -z "${why}" ]] || merge_fail "${why}"
  info="$(gh pr view "${n}" --repo "${repo}" --json state,headRefOid,baseRefName,changedFiles \
    | json "'%s %s %s %d' % (d['state'], d['headRefOid'], d['baseRefName'], d['changedFiles'])")" \
    || merge_fail "gh cannot read ${url}"
  read -r state head base changed <<< "${info}"
  [[ "${head}" =~ ^[0-9a-f]{40}$ && "${base}" =~ ^[A-Za-z0-9._/-]+$ && "${changed}" =~ ^[0-9]+$ ]] \
    || merge_fail "gh gave no head SHA, base branch or file count for ${url}"
  [[ "${state}" == OPEN ]] || merge_fail "${url} is ${state}, not open"
  [[ -z "${want}" || "${want}" == "${head}" ]] || merge_fail "the head of ${url} is ${head:0:7}, not ${want:0:7}: review the new head"
  # With merge = agent a PR whose story costs money is the user's, by any route (--board and --release too).
  if [[ "${CFG_merge}" == agent ]]; then
    why="$(pr_held "${url}")"
    [[ -z "${why}" ]] || { MERGE_TARGET="${why%% *}"; merge_fail "held: ${why}; the user merges it"; }
  fi
  if [[ -z "${only}" ]]; then
    # Any item listing the URL may be the one in review.
    while IFS= read -r p; do
      [[ " $(fm "${p}" prs) " == *" ${url} "* ]] || continue
      [[ -n "${any}" ]] || any="${p}"
      [[ "$(fm "${p}" status)" != review ]] || { f="${p}"; break; }
    done < <(board stories; board epics)
    [[ -n "${any}" ]] || merge_fail "no story or epic lists ${url} on its prs: line: run swarm.sh review <slug> ${url} first, or pass --board for a board-only PR"
    if [[ -z "${f}" ]]; then MERGE_TARGET="$(basename "${any}" .md)"; merge_fail "${MERGE_TARGET} is $(fm "${any}" status), not review"; fi
    MERGE_TARGET="$(basename "${f}" .md)"
  else
    whose="the project's"
    if [[ "${only}" == --board ]]; then
      [[ ${BOARD_IN_REPO} == 1 ]] || merge_fail "--board: the board is not in the project's repo"
      whose="the board's"
    fi
    origin="$(git -C "${PROJECT_DIR}" remote get-url origin 2>/dev/null)" || merge_fail "${only}: ${PROJECT_DIR}, ${whose} repo, has no origin"
    own="$(gh repo view "${origin}" --json nameWithOwner | json "d['nameWithOwner'].lower()")" \
      || merge_fail "${only}: gh cannot tell which GitHub repo ${origin} is"
    [[ "$(tr '[:upper:]' '[:lower:]' <<< "${repo}")" == "${own}" ]] || merge_fail "${only}: ${url} is not in ${own}, ${whose} repo"
    rel="${BOARD#"${PROJECT_DIR}"/}"
    # A renamed file's old path counts too: renaming bin/x to the board is not a board-only change.
    info="$(ci_gate files "${repo}" "${n}" "${changed}")" || merge_fail "${only}: cannot list every file ${url} changes: ${info}"
    while IFS= read -r p; do
      if [[ "${only}" == --board ]]; then
        [[ "${p}" == "${rel}/"* ]] || merge_fail "--board: ${url} changes ${p}, outside ${rel}/"
      else
        [[ "${p}" == .claude-plugin/plugin.json ]] || merge_fail "--release: ${url} changes ${p}, not only .claude-plugin/plugin.json"
      fi
    done <<< "${info}"
    if [[ "${only}" == --board && "${CFG_merge}" == agent ]]; then
      # A board PR could lift a hold (costs: money to none, or a story deleted) before the agent merges it.
      info="$(gh pr diff "${n}" --repo "${repo}" --color never)" || merge_fail "--board: gh cannot read the diff of ${url}, so whether it changes a costs: line is unknown"
      p="$(costs_diff <<< "${info}")"
      [[ -z "${p}" ]] || merge_fail "held: ${url} changes a costs: line in ${p}; with merge = agent the user merges it"
    fi
    [[ "${only}" == --board ]] || release_check "${repo}" "${base}" "${head}"
  fi
  # merge_admin = on: --admin skips GitHub's own required checks too, so ci_gate checks them first.
  admin=(); req=""
  # shellcheck disable=SC2154 # assigned in another file
  if [[ "${CFG_merge_admin}" == on ]]; then admin=(--admin); req="${base}"; fi
  why="$(ci_gate head "${repo}" "${head}" ${req:+"${req}"})" || merge_fail "the head ${head:0:7} is not green: ${why}"
  method="$(gh repo view "${repo}" --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed \
    | json "'squash' if d['squashMergeAllowed'] else 'merge' if d['mergeCommitAllowed'] else 'rebase' if d['rebaseMergeAllowed'] else ''")" \
    || merge_fail "gh cannot read ${repo}'s merge methods"
  [[ -n "${method}" ]] || merge_fail "${repo} allows no merge method"
  why="$(gh pr merge "${n}" --repo "${repo}" "--${method}" --match-head-commit "${head}" ${admin[@]+"${admin[@]}"} 2>&1)" || ran=""
  # Read the PR back either way: a 5xx or a dropped connection can follow a merge GitHub made.
  read -r state oid <<< "$(merged_state "${n}" "${repo}")"
  if [[ "${state}" != MERGED || ! "${oid}" =~ ^[0-9a-f]{40}$ ]]; then
    # A failed gh pr merge on a PR that still reads open or closed never reached a merge.
    [[ -n "${ran}" || "${state}" == unreadable ]] || merge_fail "gh pr merge failed: ${why##*$'\n'}"
    [[ "${state}" != MERGED ]] || state="MERGED, no merge commit"
    merge_fail "unconfirmed (${state}): gh pr merge ran, but ${url} does not read as merged; check it by hand"
  fi
  record_event merge "${MERGE_TARGET}" ok
  echo "merged: ${url} (${method}, head ${head:0:7}, merge commit ${oid:0:7}); waiting for CI on ${base}"
  if why="$(ci_gate main "${repo}" "${oid}" "${base}" "${n}" "${changed}" "${SWARM_MERGE_CI_SECONDS:-${MERGE_CI_SECONDS}}" \
      "${SWARM_MERGE_POLL:-${MERGE_POLL}}" "${SWARM_MERGE_CI_GRACE:-${MERGE_CI_GRACE}}")"; then
    why=ok
  else
    rc=$?; why="${why:-error (exit ${rc})}"
  fi
  record_event main-ci "${MERGE_TARGET}" "${why}"
  echo "main-ci: ${why}"
  if [[ -z "${only}" ]]; then
    # In the background, so set -e holds inside it; its die line is reconcile's, as main would log it.
    # shellcheck disable=SC2034 # read in another file
    ( DIE_LEVEL="${BASH_SUBSHELL}"; set -e; reconcile ) &
    wait $! || {
      rrc=$?; why="$(head -1 "${DIE_FILE:-/dev/null}" 2>/dev/null || true)"
      record_event reconcile - "${why:-failed (exit ${rrc})}"
      die "merge: reconcile failed after the merge; run swarm.sh reconcile"
    }
  fi
  [[ ${rc} -eq 0 ]] || die "merge: CI on ${base} at ${oid:0:7} is not green: ${why}"
}

# release_check <owner/repo> <base> <head> — merge --release's checks past the file list: the PR goes
# into the project's base, its plugin.json differs from the base's only in "version" (compared as
# sorted JSON text, so true and 1 differ), since hooks, mcpServers and command paths there run code,
# and that version is MAJOR.MINOR.PATCH and greater than the base's.
release_check() {
  local want old new why
  want="$(base_for "${PROJECT_DIR}")" || merge_fail "--release: cannot tell the project's base branch"
  [[ "$2" == "${want}" ]] || merge_fail "--release: ${MERGE_TARGET} goes into $2, not ${want}, the project's base"
  old="$(gh api -H "Accept: application/vnd.github.raw" "repos/$1/contents/.claude-plugin/plugin.json?ref=$2")" \
    || merge_fail "--release: gh cannot read .claude-plugin/plugin.json on $2"
  new="$(gh api -H "Accept: application/vnd.github.raw" "repos/$1/contents/.claude-plugin/plugin.json?ref=$3")" \
    || merge_fail "--release: gh cannot read .claude-plugin/plugin.json at ${3:0:7}"
  why="$(OLD="${old}" NEW="${new}" BASE="$2" python3 -c 'import json,os,re
e = os.environ
o, n = json.loads(e["OLD"]), json.loads(e["NEW"])
v, w = n.pop("version", None), o.pop("version", None)
semver = lambda x: tuple(map(int, x.split("."))) if isinstance(x, str) and re.fullmatch(r"\d+\.\d+\.\d+", x) else None
if semver(v) is None:
    print("its version %r is not MAJOR.MINOR.PATCH" % (v,))
elif semver(w) is None or semver(v) <= semver(w):
    print("its version %s is not greater than %r on %s" % (v, w, e["BASE"]))
elif json.dumps(o, sort_keys=True) != json.dumps(n, sort_keys=True):
    print("it changes more of .claude-plugin/plugin.json than its version; if %s changed plugin.json after the release branch was cut, merge origin/%s into it and retry" % (e["BASE"], e["BASE"]))' 2>/dev/null)" \
    || why="cannot read .claude-plugin/plugin.json as JSON"
  [[ -z "${why}" ]] || merge_fail "--release: ${MERGE_TARGET}: ${why}"
}

# watch [--epic <slug>|--backlog] [repo...] — block until a story/* PR in these repos needs the lead, print
# one line saying which and why, and exit 0. With --epic, only that epic's stories' story/<slug> PRs
# count, and with --backlog only those of stories with no epic; the default repos are then those
# stories' repos: a conductor must not wake for another epic's PR on the same board. A PR needs the lead when its checks on a new head have all finished,
# when it conflicts with its base (a conflicted PR runs no checks, so waiting on checks never ends),
# or when its head has had no check at all for WATCH_STALL_SECS (default 600). An agent of this
# project whose session is waiting (herdr's blocked, for an agent herdr answers for) also needs the
# lead, named with what it waits for. Each head is reported once, and each agent's wait once, until a
# poll finds that agent no longer waiting (state in .swarm/state).
watch_prs() {
  local epic="" stories=("${BOARD}"/stories/*.md) heads="" f
  if [[ "${1:-}" == --epic || "${1:-}" == --backlog ]]; then
    # The backlog's stories are those whose epic: is empty; heads stays non-empty, so no other PR counts.
    if [[ "$1" == --epic ]]; then
      epic="${2:?watch --epic needs an epic slug}"; shift 2
      [[ -f "${BOARD}/epics/${epic}.md" ]] || die "watch: no epic ${BOARD}/epics/${epic}.md"
    else shift; fi
    stories=(); heads="-"
    for f in "${BOARD}"/stories/*.md; do
      [[ -f "${f}" && "$(basename "${f}")" != README.md && "$(fm "${f}" epic)" == "${epic}" ]] || continue
      stories+=("${f}"); heads="${heads} story/$(basename "${f}" .md)"
    done
  fi
  local repos=("$@") seen="${STATE_DIR}/watch-seen" stall="${WATCH_STALL_SECS:-600}" repo n sha br mergeable age total pending
  # Default: the project (when it is a repo) plus every repo a story names, so a new repo needs no edit here.
  if [[ ${#repos[@]} -eq 0 ]]; then
    local own=""; [[ ${PROJECT_IS_GIT} == 1 ]] && own="$(basename "${PROJECT_DIR}")"
    read -r -a repos <<< "${own} $( (( ${#stories[@]} )) && sed -n 's/^repo: *//p' "${stories[@]}" 2>/dev/null | sort -u | tr '\n' ' ')"
  fi
  # With nothing to poll, the loop below would sleep forever.
  [[ ${#repos[@]} -gt 0 ]] || die "watch: no repo to watch${epic:+ for epic ${epic}}"
  # Each repo as owner/name, from its own origin: repos on one board need not share an owner.
  local full=() r src
  for r in "${repos[@]}"; do
    src="$(repo_dir "${r}")" || die "watch ${r}: ${src}"
    r="$(gh repo view "$(git -C "${src}" remote get-url origin)" --json nameWithOwner -q .nameWithOwner)" \
      || die "no GitHub origin for ${src}"
    [[ " ${full[*]-} " == *" ${r} "* ]] || full+=("${r}")
  done
  repos=("${full[@]}")
  mkdir -p "${STATE_DIR}"; touch "${seen}"
  while :; do
    for repo in "${repos[@]}"; do
      while read -r n sha br mergeable age; do
        [[ -n "${n}" ]] || continue
        [[ -z "${heads}" || " ${heads} " == *" ${br} "* ]] || continue
        if [[ "${mergeable}" == CONFLICTING ]] && ! grep -qx "conflict ${sha}" "${seen}"; then
          echo "conflict ${sha}" >> "${seen}"; echo "${repo} #${n} ${br} CONFLICTS with its base"; return 0
        fi
        grep -qx "done ${sha}" "${seen}" && continue
        read -r total pending < <(gh api "repos/${repo}/commits/${sha}/check-runs" \
          -q '"\(.check_runs|length) \([.check_runs[]|select(.status!="completed")]|length)"')
        if [[ "${total:-0}" -gt 0 && "${pending}" == 0 ]]; then
          echo "done ${sha}" >> "${seen}"; echo "${repo} #${n} ${br} checks finished on ${sha:0:7}"; return 0
        fi
        if [[ "${total:-0}" == 0 && "${age}" -gt "${stall}" ]] && ! grep -qx "stall ${sha}" "${seen}"; then
          echo "stall ${sha}" >> "${seen}"; echo "${repo} #${n} ${br} has had no checks for ${age}s"; return 0
        fi
      done < <(gh pr list -R "${repo}" --state open --json number,headRefName,headRefOid,mergeable,updatedAt \
        -q '.[]|select(.headRefName|startswith("story/"))|"\(.number) \(.headRefOid) \(.headRefName) \(.mergeable) \((now - (.updatedAt|fromdateiso8601))|floor)"')
    done
    if [[ "${HERDR_ENV:-}" == 1 ]]; then
      local agents sessions now e news="" tmp
      # Only agents in panes this project opened: herdr lists every project's. Each one's state is
      # panes.py's agent_state: its session's, else herdr's (codex, or no session recorded). One line
      # per agent waiting, "<name> (<what it waits for>)". A read that fails (herdr's list, Claude
      # Code's, or the reader) changes nothing: a failed Claude list would read every session unknown.
      if agents="$(herdr agent list 2>/dev/null)" && sessions="$(claude_agents)" \
        && now="$(printf '%s' "${agents}" | SWARM_OWN="$(own_panes)" SWARM_SESSIONS="${sessions}" \
        SWARM_LIB="${SWARM_HOME}/bin/lib" python3 -I -c '
import json, os, sys
sys.path.insert(0, os.environ["SWARM_LIB"]); from panes import *
own = set(os.environ["SWARM_OWN"].split())
for a in json.load(sys.stdin)["result"]["agents"]:
    name = a.get("name")
    if name and a.get("pane_id") in own:
        s = session_state(sys.argv[1], name, os.environ["SWARM_SESSIONS"])
        if agent_state(a, name, s)[0] == "WAITING":
            print(name + (f" ({s[1]})" if s and s[1] else ""))' "${AGENTS_LOG}" 2>/dev/null)"; then
        while IFS= read -r e; do
          if [[ -n "${e}" ]] && ! grep -qxF "waiting ${e}" "${seen}"; then news=1; fi
        done <<< "${now}"
        # seen's waiting lines become exactly the agents waiting now: an agent that stopped waiting is
        # forgotten at once, so its next wait is reported again, whoever else still waits.
        if [[ "$(sed -n 's/^waiting //p' "${seen}" | sort)" != "$(sort <<< "${now}")" ]]; then
          tmp="$(mktemp "${STATE_DIR}/watch-seen.XXXXXX")"
          { grep -v '^waiting ' "${seen}" || true; [[ -z "${now}" ]] || printf 'waiting %s\n' "${now//$'\n'/$'\n'waiting }"; } > "${tmp}"
          mv "${tmp}" "${seen}"
        fi
        if [[ -n "${news}" ]]; then echo "agent(s) waiting: ${now//$'\n'/, }"; return 0; fi
      fi
    fi
    sleep 60
  done
}

# ref_in <repo-dir> <ref> <branch> — 0 when <ref>'s head is in <branch>, 1 when it is not, 2 when
# git cannot tell (a missing ref).
ref_in() { local rc=0; git -C "$1" merge-base --is-ancestor "$2" "$3" 2>/dev/null || rc=$?; (( rc <= 1 )) || rc=2; return "${rc}"; }

# fetch_branch <repo-dir> <branch> — fetch origin's <branch> into origin/<branch>; returns 2 when
# origin answered and has no such branch, 1 for any other failure.
fetch_branch() {
  local rc=0
  git -C "$1" fetch -q origin "+refs/heads/$2:refs/remotes/origin/$2" 2>/dev/null && return 0
  git -C "$1" ls-remote --exit-code -q origin "refs/heads/$2" >/dev/null 2>&1 || rc=$?
  [[ ${rc} == 2 ]] && return 2
  return 1
}

# stacked_parents <child> — the parents the child's current build stacked on: the `stacked <child>`
# event just before its last ok `story <child>` (main logs story once the build is done), or one
# with no story after it yet (a build still starting). A later ok build with no stacked event
# (rebuilt from the base) has none. A stacked event a story that failed, a close or a reset
# follows belongs to no build: a failed or abandoned start.
stacked_parents() {
  awk -F'\t' -v s="$1" '$3 != s { next }
    $2 == "stacked" && index($5, "ok (on ") == 1 { pend = substr($5, 8, length($5) - 8) }
    $2 == "story" && index($5, "ok") == 1 { cur = pend; pend = ""; next }
    $2 == "story" || $2 ~ /^(close|reset)(:|$)/ { pend = "" }
    END { print (pend != "" ? pend : cur) }' "${EVENTS_LOG}" 2>/dev/null || true
}

# stacked_parent <repo-dir> <child-ref> <p> — what the child must do about parent p: `merge
# origin/story/<p>` when p's PR is open (or p, on the board, has none) and its head is not in
# <child-ref>; `merged` when p's PR merged, or p's file is gone and it has no PR; `lost story/<p>`
# when p's only PRs closed unmerged (a dropped p too), or its branch is gone while its PR is open or
# it is on the board. Nothing when the child has it. A gh or git call that fails returns 1.
stacked_parent() {
  local src="$1" have="$2" p="$3" state rc=0
  state="$( (cd "${src}" && gh pr list --head "story/${p}" --state all --json state) 2>/dev/null \
    | json "next((s for s in ('OPEN', 'MERGED', 'CLOSED') if any(x['state'] == s for x in d)), '')" 2>/dev/null)" || return 1
  [[ -n "${state}" || -f "${BOARD}/stories/${p}.md" ]] || state=MERGED   # finished with no PR
  case "${state}" in
    CLOSED) echo "lost story/${p}" ;;
    MERGED) echo merged ;;
    *)
      fetch_branch "${src}" "story/${p}" || rc=$?
      case ${rc} in 0) ;; 2) echo "lost story/${p}"; return ;; *) return 1 ;; esac
      rc=0; ref_in "${src}" "origin/story/${p}" "${have}" || rc=$?
      case ${rc} in 0) ;; 1) echo "merge origin/story/${p}" ;; *) return 1 ;; esac ;;
  esac
}

# stacked_child <story> — stacked_lines' lines for one story. The child's branch is origin's (fetched),
# so a merge not yet pushed still shows; its local branch only while origin has none. Parents that
# merged give one base line; the base is looked up once per repo in a row (STACKED_SRC).
stacked_child() {
  local child src parents p line have builder="" done_ps="" rc=0
  child="$(basename "$1" .md)"
  src="$(repo_dir "$(fm "$1" repo)")" || return 0
  [[ -d "$(worktree_for "${src}" "${child}")" ]] || return 0
  parents="$(stacked_parents "${child}")"; [[ -n "${parents}" ]] || return 0
  # Outside herdr the agents cannot be read, so no line claims the builder is gone.
  [[ "${HERDR_ENV:-}" != 1 || "$(builder_state "${child}")" != none ]] || builder=" (no builder)"
  fetch_branch "${src}" "story/${child}" || rc=$?
  case ${rc} in
    0) have="origin/story/${child}" ;;
    2) have="story/${child}" ;;
    *) echo "${child}: could not check story/${child} on origin${builder}"; return 0 ;;
  esac
  for p in ${parents//,/ }; do
    if [[ ! "${p}" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then echo "${child}: could not check ${p}${builder}"; continue; fi
    line="$(stacked_parent "${src}" "${have}" "${p}")" || line="could not check ${p}"
    case "${line}" in merged) done_ps+="${done_ps:+, }${p}" ;; ?*) echo "${child}: ${line}${builder}" ;; esac
  done
  [[ -n "${done_ps}" ]] || return 0
  # ponytail: caches the last repo's base only; boards span few repos, so a miss is one more fetch.
  [[ "${STACKED_SRC}" == "${src}" ]] || { STACKED_BASE="$(base_for "${src}" 2>/dev/null)" || STACKED_BASE=""; STACKED_SRC="${src}"; }
  rc=2; [[ -z "${STACKED_BASE}" ]] || { rc=0; ref_in "${src}" "origin/${STACKED_BASE}" "${have}" || rc=$?; }
  case ${rc} in
    0) ;;
    1) echo "${child}: merge origin/${STACKED_BASE} (${done_ps} merged)${builder}" ;;
    *) echo "${child}: could not check the base for ${done_ps}${builder}" ;;
  esac
}

# stacked_lines — one line per parent of a stacked build that needs action (stacked_child): a ready
# or blocked story with a worktree whose current build stacked on parents. A line ends (no builder)
# when herdr shows no builder open for the child; a gh or git call that fails gives a `could not
# check` line. herdr, gh and git read no stdin, which feeds the loop, and git never prompts for a
# credential or an ssh passphrase on the terminal: status must not hang, so such a fetch fails into
# a could-not-check line.
stacked_lines() {
  local story
  STACKED_SRC=""; STACKED_BASE=""
  while IFS= read -r story; do
    case "$(fm "${story}" status)" in
      ready|blocked)
        GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes" stacked_child "${story}" </dev/null ;;
    esac
  done < <(board stories)
}

# status [--all] — one summary for the user: the agents that need a look or are working, the stacked
# builds whose parent moved or merged (stacked_lines; no section when there are none), what is
# waiting on them, and what `next` would do; idle agents and blocked stories are only counted unless
# --all. A pane with no agent in it is shown as empty: a start that failed. Panes closed by hand are
# left out. A Claude agent's state is its session's (one claude_agents call per run); herdr's word
# only for codex, an agent with no session recorded, and a retired one.
status_report() {
  local all="${1:-}" agents panes waiting sessions
  if [[ "${HERDR_ENV:-}" == 1 ]] && agents=$(herdr agent list 2>/dev/null) && panes=$(herdr pane list 2>/dev/null); then
    sessions="$(claude_agents)" || sessions=""   # a failed call reads as unknown, as an empty one does
    SWARM_OWN="$(own_panes)" SWARM_SESSIONS="${sessions}" \
      python3 "${SWARM_HOME}/bin/lib/status_report.py" "${STATE_DIR}" "${agents}" "${panes}" "${all}" "${AGENTS_LOG}" "${CLAUDE_PROJECTS}"
  else
    echo "Agents: not inside herdr, so their states are not available"
  fi
  local stacked; stacked="$(stacked_lines)" || true
  [[ -z "${stacked}" ]] || printf '\nStacked\n  %s\n' "${stacked//$'\n'/$'\n'  }"
  echo; echo "Waiting on you"
  waiting="$(waiting_on_user)"
  if [[ "${all}" != --all ]]; then
    local blocked
    blocked=$(grep -c '^  blocked:' <<< "${waiting}" || true)
    waiting="$(grep -v '^  blocked:' <<< "${waiting}" || true)"
    [[ "${blocked}" -eq 0 ]] || waiting+="${waiting:+$'\n'}  ${blocked} blocked stories wait on others (swarm.sh status --all lists them)"
  fi
  if [[ -n "${waiting}" ]]; then printf '%s\n' "${waiting}"; else echo "  nothing"; fi
  echo; echo "Next"
  next_step | sed 's/^/  /'
}

# stacked_on <story> <open slugs> — print <open slugs> when a blocked story with no build yet can
# start on them: each is a story in its own repo, ready or in review, with an open PR (review's prs:
# line, else gh's on story/<p>). Fails otherwise, a gh failure too, and a child review held
# (held_by:) waits until its parents finish. Fails with 2 when only a build already there (its
# worktree or story/<slug>) is in the way.
stacked_on() {
  local story="$1" p f src
  [[ -z "$(get_fm "${story}" held_by)" ]] || return 1
  src="$(repo_dir "$(fm "${story}" repo)")" || return 1
  for p in $2; do
    f="${BOARD}/stories/${p}.md"
    [[ -f "${f}" && "$(repo_dir "$(fm "${f}" repo)")" == "${src}" ]] || return 1
    case "$(fm "${f}" status)" in
      review) [[ -z "$(fm "${f}" prs)" ]] || continue ;;
      ready) ;;
      *) return 1 ;;
    esac
    open_pr "${src}" "${p}" >/dev/null || return 1
  done
  ! build_exists "${src}" "$(basename "${story}" .md)" || return 2
  echo "$2"
}
