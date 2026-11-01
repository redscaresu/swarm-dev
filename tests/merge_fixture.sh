# shellcheck shell=bash
# merge_fixture.sh — sourced by merge_test.sh and the merge_*_test.sh files that share its cases, so
# each runs on a CI shard of its own: a project for swarm.sh merge, its stubs and the helpers the cases
# use. gh and herdr are stubs on PATH: gh logs every call to gh.log and answers from ${FX} (see
# serve); herdr lists the agents in ${ROOT}/agents ("<name> <pane>" lines). A file that sources it
# first sets ROOT, its own mktemp root, and exports CLAUDE_CONFIG_DIR under it (sleep_scale_test reads
# each test file for that), and ends with `finish`.
# shellcheck disable=SC2034,SC2120 # the cases that source it use these variables, and pass fresh its config lines
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
REPO="$(dirname "${SWARM}")/.."
P="${ROOT}/proj"; FX="${ROOT}/fx"; S="${P}/docs/stories/s.md"
H1=1111111111111111111111111111111111111111; H2=2222222222222222222222222222222222222222
M=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; URL=https://github.com/o/r/pull/7
mkdir -p "${P}/.claude/swarm" "${P}/docs/stories" "${P}/.swarm/state" "${ROOT}/bin"
# The user's settings allow swarm.sh merge, so a conductor may start under merge = agent (merge_rule_stop).
mkdir -p "${CLAUDE_CONFIG_DIR}"; echo '{"permissions":{"allow":["Bash(swarm.sh merge *)"]}}' > "${CLAUDE_CONFIG_DIR}/settings.json"
git -C "${P}" init -q
# The board's repo has an origin, a local bare repo the gh stub names o/r (${FX}/origin).
git init -q --bare "${ROOT}/origin.git"; git -C "${P}" remote add origin "${ROOT}/origin.git"

# gh: pr view, pr merge (fails unless --match-head-commit is ${FX}/head; marks the PR merged with
# merge commit ${FX}/oid, else ${M}, and then fails the next ${FX}/readback-fails pr views) and repo view (the merge
# methods, or with nameWithOwner ${FX}/origin) from ${FX}; each api path from serve's fixture.
# STUB_FX, when set, is a run's own fixtures (two merges at once).
# shellcheck disable=SC2016 # ${STUB_FX} is the stub's, expanded when it runs
printf '#!/usr/bin/env bash\nFX="${STUB_FX:-%s}"; LOG="%s"; M="%s"\n' "${FX}" "${ROOT}/gh.log" "${M}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "${LOG}"
# get <var> <file> [default] — <var> is <file>'s first line, else <default>: a builtin read, so no
# fork, as merge_test makes thousands of gh calls.
get() { local v="${3-}"; if [ -e "$2" ]; then v=""; IFS= read -r v < "$2" || true; fi; printf -v "$1" '%s' "${v}"; }
# put <file> — print <file>, as cat would but with no fork, ending its last line with a newline.
put() { local l; while IFS= read -r l || [ -n "${l}" ]; do printf '%s\n' "${l}"; done < "$1"; }
# serve <key> — the fixture <key>.<n> on the nth read of <key> when there is one, else <key>; with
# <key>.fail, print that (a partial answer) and fail; with <key>.<n>.fail, fail the nth read only, its
# text the error when it has one (else a 502); with <key>.404, a 404 with its message; with none of
# them, a 404 Not Found.
serve() {
  local n m; get n "${FX}/$1.n" 0; n=$((n + 1)); echo "${n}" > "${FX}/$1.n"
  if [ -e "${FX}/$1.fail" ]; then put "${FX}/$1.fail"; echo "gh: HTTP 502" >&2; exit 1; fi
  if [ -s "${FX}/$1.${n}.fail" ]; then put "${FX}/$1.${n}.fail" >&2; exit 1; fi
  if [ -e "${FX}/$1.${n}.fail" ]; then echo "gh: HTTP 502" >&2; exit 1; fi
  if [ -e "${FX}/$1.${n}" ]; then put "${FX}/$1.${n}"
  elif [ -e "${FX}/$1" ]; then put "${FX}/$1"
  elif [ -e "${FX}/$1.404" ]; then get m "${FX}/$1.404"; echo "gh: ${m} (HTTP 404)" >&2; exit 1
  else echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
}
case "$1 $2" in
  "pr view")
    [ ! -e "${FX}/pr-view.fail" ] || { echo "gh: could not resolve to a PullRequest" >&2; exit 1; }
    get left "${FX}/readback-left" 0
    if [ "${left}" -gt 0 ]; then echo $((left - 1)) > "${FX}/readback-left"; echo "gh: HTTP 502" >&2; exit 1; fi
    # The head update-branch moves, once its lag (pr views that still read the old head) is spent.
    if [ -e "${FX}/pending-head" ]; then get l "${FX}/pending-left" 0
      if [ "${l}" -gt 0 ]; then echo $((l - 1)) > "${FX}/pending-left"; else mv "${FX}/pending-head" "${FX}/head"; fi; fi
    get st "${FX}/state"; get st "${FX}/state.${3##*/}" "${st}"
    get h "${FX}/head"; get b "${FX}/base"; get mc "${FX}/mergecommit"; get nf "${FX}/nfiles"; get bd "${FX}/body" null; get cm "${FX}/commits" '[{}]'
    get mg "${FX}/mergeable" MERGEABLE
    # With -q (wait-pr's read), jq gives what gh would.
    q=""; prev=""; for a in "$@"; do [ "${prev}" != -q ] || q="${a}"; prev="${a}"; done
    out="$(printf '{"state":"%s","headRefOid":"%s","baseRefName":"%s","mergeCommit":%s,"changedFiles":%s,"body":%s,"commits":%s,"mergeable":"%s","headRefName":"story/s"}\n' \
      "${st}" "${h}" "${b}" "${mc}" "${nf}" "${bd}" "${cm}" "${mg}")"
    if [ -n "${q}" ]; then printf '%s\n' "${out}" | jq -r "${q}"; else printf '%s\n' "${out}"; fi ;;
  "pr merge")
    case " $* " in *" --disable-auto "*) exit 0 ;; esac
    want=""; prev=""; for a in "$@"; do [ "${prev}" != --match-head-commit ] || want="${a}"; prev="${a}"; done
    get h "${FX}/head"; [ "${want}" = "${h}" ] || { echo "GraphQL: Head branch was modified. Review and try the merge again." >&2; exit 1; }
    # --auto enqueues (with ${FX}/auto-fails, then fails with a 5xx): the queue fixture
    # (serve queue) says what happens next.
    # With ${FX}/auto-sleeps the enqueue lasts until term_merge has sent its TERM (${FX}/termed), 5 s at most.
    case " $* " in *" --auto "*) [ ! -e "${FX}/auto-sleeps" ] || for _ in $(seq 50); do [ ! -e "${FX}/termed" ] || break; sleep 0.1; done
      [ ! -e "${FX}/auto-fails" ] || { echo "gh: HTTP 502" >&2; exit 1; }; exit 0 ;; esac
    [ -e "${FX}/stays-open" ] || echo MERGED > "${FX}/state"
    get o "${FX}/oid" "${M}"; [ -e "${FX}/no-merge-commit" ] || printf '{"oid":"%s"}' "${o}" > "${FX}/mergecommit"
    [ ! -e "${FX}/readback-fails" ] || cp "${FX}/readback-fails" "${FX}/readback-left"
    # ${FX}/on-merge runs once the PR has merged: another command's work during merge's CI wait.
    [ ! -e "${FX}/on-merge" ] || sh "${FX}/on-merge"
    # A 5xx after GitHub merged it.
    [ ! -e "${FX}/merge-then-fail" ] || { echo "gh: HTTP 502" >&2; exit 1; } ;;
  # With ${FX}/origin.hang, the nameWithOwner read first sleeps a minute; with ${FX}/origin.fail it
  # prints that to stderr and fails.
  "repo view") case "$*" in
                 *nameWithOwner*) [ ! -e "${FX}/origin.hang" ] || sleep 60
                                  [ ! -e "${FX}/origin.fail" ] || { cat "${FX}/origin.fail" >&2; exit 1; }
                                  cat "${FX}/origin" ;;
                 *) cat "${FX}/repo" ;;
               esac ;;
  # The merged PRs of --head story/<slug>: ${FX}/prlist.<slug>, else none; with ${FX}/prlist.<slug>.fail, a 5xx.
  "pr list") h=""; prev=""; for a in "$@"; do [ "${prev}" != --head ] || h="${a##*/}"; prev="${a}"; done
             [ ! -e "${FX}/prlist.${h}.fail" ] || { echo "gh: HTTP 502" >&2; exit 1; }
             cat "${FX}/prlist.${h}" 2>/dev/null || echo '[]' ;;
  # A run's status (run.<id>.status, read like any fixture), or its failed-job log: --log-failed's
  # "<job>\t<step>\t<timestamp> <line>" lines, which hang with ${FX}/run.hang.
  "run view") case "$*" in
                *"--json status"*) [ ! -e "${FX}/run.$3.statushang" ] || sleep 60; serve "run.$3.status" ;;
                *) [ ! -e "${FX}/run.hang" ] || sleep 60; serve "run.$3.log" ;;
              esac ;;
  # A rerun of a run's failed jobs runs ${FX}/rerun.<id> (it writes what CI reads next); with none,
  # GitHub refuses it. With ${FX}/rerun-502, the first one fails with a 5xx.
  # With ${FX}/rerun-502.keep, every one does.
  "run rerun") [ ! -e "${FX}/rerun-502" ] || { rm "${FX}/rerun-502"; echo "gh: HTTP 502" >&2; exit 1; }
               [ ! -e "${FX}/rerun-502.keep" ] || { echo "gh: HTTP 502" >&2; exit 1; }
               [ -e "${FX}/rerun.$3" ] || { echo "gh: run $3 cannot be rerun (HTTP 403)" >&2; exit 1; }; sh "${FX}/rerun.$3" ;;
  # Coloured, as with CLICOLOR_FORCE or GH_FORCE_TTY, unless asked for --color never.
  "pr diff") case "$*" in *"--color never"*) cat "${FX}/diff" ;; *) sed "s/^/$(printf '\033')[1m/" "${FX}/diff" ;; esac ;;
  api*)
    # gh api rate_limit (wait-pr's read of a spent budget): ${FX}/rate_limit as the --jq filter gives it
    # ("<reset epoch> <reset time>"), else nothing (the budget is not spent).
    if [ "$2" = rate_limit ]; then [ ! -e "${FX}/rate_limit" ] || put "${FX}/rate_limit"; exit 0; fi
    # A PR's commits (pulls/<n>/commits, merge's dropped-lines reads), through its --jq filter: ${FX}/prcommits
    # as serve reads it (with prcommits.fail, a 5xx), else one plain commit at ${FX}/head, so no merge to scan.
    case "$*" in *"/pulls/"*"/commits?"*)
      q=.; prev=""; for a in "$@"; do [ "${prev}" != --jq ] || q="${a}"; prev="${a}"; done
      if [ -e "${FX}/prcommits" ] || [ -e "${FX}/prcommits.fail" ]; then out="$(serve prcommits)" || exit 1
      else get h "${FX}/head"; out="[{\"sha\":\"${h}\",\"parents\":[{\"sha\":\"0000000000000000000000000000000000000000\"}]}]"; fi
      printf '%s\n' "${out}" | jq -r "${q}"; exit ;;
    esac
    for a in "$@"; do path="${a}"; done
    sha="${path#*/commits/}"; sha="${sha%%/*}"
    case "${path}" in
      # The merge queue's read of the PR (api graphql); a read that says merged marks the PR so.
      *"mergeQueue(branch"*) serve mq ;;   # whether the base has a merge queue
      # Turning auto-merge off and dequeuing: they succeed, unless ${FX}/mutation.fail.
      *"mutation("*) [ ! -e "${FX}/mutation.fail" ] || { echo "gh: HTTP 502" >&2; exit 1; }; echo '{"data":{}}' ;;
      # With ${FX}/queue-sleeps the first read lasts until term_merge has sent its TERM (${FX}/termed), 5 s at most.
      query=*) [ ! -e "${FX}/queue-sleeps" ] || { rm -f "${FX}/queue-sleeps"; for _ in $(seq 50); do [ ! -e "${FX}/termed" ] || break; sleep 0.1; done; }
               out="$(serve queue)" || exit 1; echo "${out}"
               case "${out}" in *'"state":"MERGED"'*) echo MERGED > "${FX}/state"; printf '{"oid":"%s"}' "${M}" > "${FX}/mergecommit" ;; esac ;;
      */check-runs*) serve "${sha}.checks"
                     # The head moves once its checks are read, before the merge; with move-head.<sha>, once
                     # <sha>'s are read while it is the head (a push during merge's wait on it).
                     get h "${FX}/head"; [ "${sha}" != "${h}" ] || [ ! -e "${FX}/move-head" ] || cp "${FX}/move-head" "${FX}/head"
                     get h "${FX}/head"; [ "${sha}" != "${h}" ] || [ ! -e "${FX}/move-head.${sha}" ] || cp "${FX}/move-head.${sha}" "${FX}/head"
                     # ${FX}/on-checks runs once then: another PR landing on the base while merge runs.
                     get h "${FX}/head"; [ "${sha}" != "${h}" ] || [ ! -e "${FX}/on-checks" ] || { sh "${FX}/on-checks"; rm -f "${FX}/on-checks"; }
                     # ${FX}/on-checks.<sha> runs once when <sha>'s checks are read: another run's work during merge's wait.
                     [ ! -e "${FX}/on-checks.${sha}" ] || { sh "${FX}/on-checks.${sha}"; rm -f "${FX}/on-checks.${sha}"; } ;;
      */commits/*/status*) serve "${sha}.status" ;;
      *event=merge_group*) serve mgruns ;;
      */actions/runs*) sha="${path#*head_sha=}"; serve "${sha%%&*}.runs" ;;
      # --slurp (merge_gone's read) wraps the one page in a list of pages.
      */pulls/*/files*) case " $* " in *" --slurp "*) out="$(serve files)" || exit 1; echo "[${out}]" ;; *) serve files ;; esac ;;
      */rules/branches/*) serve rules ;;
      */git/ref/tags/*) serve tagref ;;     # the release's tag
      */releases/tags/*) serve release ;;   # its GitHub release
      */branches/main) serve basehead ;;   # the base's head (a merge queue's push)
      */branches/*) serve branch ;;
      # compare/<head>...<base branch>, merge's read of what the base gained: ${FX}/behind.<head> when
      # there is one, else ${FX}/behind (as serve
      # reads it, so behind.<n>.fail fails the nth read and behind.404 is a 404), else nothing (ahead_by
      # 0); with ${FX}/behind.hang it first sleeps a minute. compare/<base>...<head>: compare.<base>...<head>,
      # else compare.<base>, else compare, else for a branch
      # base the PR's files (the grant's read at the pinned head, failing as files does), else for a
      # commit base the head holds it (fix-main's compare of a red commit with a green one). A branch
      # base's compare lists the PR's files too, as GitHub's does: a fixture with no files key gets
      # ${FX}/files as it is, so protected_hold's read of the pinned head, at the same URL as merge_admin's
      # behind_by read, sees the files whatever a case wrote the fixture for. With ${FX}/compare.hang a
      # branch base's compare first sleeps a minute; compare.<base>.404 is a 404 with its message.
      */compare/*) c="${path##*/compare/}"; to="${c#*...}"; c="${c%%...*}"
                   [ "${#c}" = 40 ] || [ ! -e "${FX}/compare.hang" ] || sleep 60
                   if [ "${#c}" = 40 ] && [ "${#to}" != 40 ]; then
                     [ ! -e "${FX}/behind.hang" ] || sleep 60
                     if [ -e "${FX}/behind.${c}" ]; then serve "behind.${c}"
                     elif [ -e "${FX}/behind" ] || [ -e "${FX}/behind.fail" ] || [ -e "${FX}/behind.404" ]; then serve behind; else echo '{"ahead_by":0,"files":[]}'; fi
                   elif [ -e "${FX}/compare.${c}...${to}" ] || [ -e "${FX}/compare.${c}" ] || [ -e "${FX}/compare.${c}.404" ] || [ -e "${FX}/compare" ] || [ -e "${FX}/compare.fail" ]; then
                     if [ -e "${FX}/compare.${c}...${to}" ]; then out="$(serve "compare.${c}...${to}")" || exit 1   # one pair of commits
                     elif [ -e "${FX}/compare.${c}" ] || [ -e "${FX}/compare.${c}.404" ]; then out="$(serve "compare.${c}")" || exit 1
                     else out="$(serve compare)" || exit 1; fi
                     case "${out}" in
                       *'"files"'*) ;;
                       *) [ "${#c}" = 40 ] || { f="$(put "${FX}/files")"; if [ "${out}" = '{}' ]; then out="{\"files\":${f}}"; else out="${out%\}},\"files\":${f}}"; fi; } ;;
                     esac
                     echo "${out}"
                   elif [ "${#c}" != 40 ]; then out="$(serve files)" || exit 1; echo "{\"files\":${out}}"
                   else echo '{"status":"ahead","behind_by":0}'; fi ;;
      # PUT pulls/<n>/update-branch, merge's request to merge the base in: ${FX}/update as serve reads it,
      # and ${FX}/update.422 (or update.422.<expected_head_sha>, for that request alone) a 422 with its
      # message; with ${FX}/update.hang it first sleeps a minute, and with ${FX}/update.unread every pr
      # view after a 422 fails.
      # Whatever it answers, the PR's head becomes ${FX}/update-head.<expected_head_sha>, else
      # ${FX}/update-head, when there is one, after
      # ${FX}/update-lag more pr views (none by default): with update.422, another merge's request went first.
      */update-branch) [ ! -e "${FX}/update.hang" ] || sleep 60
                       e=""; for a in "$@"; do case "${a}" in expected_head_sha=*) e="${a#*=}" ;; esac; done
                       u="${FX}/update-head"; [ ! -e "${u}.${e}" ] || u="${u}.${e}"
                       [ ! -e "${u}" ] || { cp "${u}" "${FX}/pending-head"; get l "${FX}/update-lag" 0; echo "${l}" > "${FX}/pending-left"; }
                       k="${FX}/update.422"; [ ! -e "${k}.${e}" ] || k="${k}.${e}"
                       if [ -e "${k}" ]; then [ ! -e "${FX}/update.unread" ] || echo 99 > "${FX}/readback-left"
                         get m "${k}"; echo "gh: ${m} (HTTP 422)" >&2; exit 1; fi
                       serve update ;;
      */contents/.github/workflows\?*) serve workflows ;;
      # A file read at a ref with a fixture of its own (wf.<file>.<ref>) gets that one. With
      # ${FX}/contents.hang it first sleeps a minute.
      # ${FX}/on-contents runs once first: another process's fetch while release_check reads.
      */contents/*) [ ! -e "${FX}/contents.hang" ] || sleep 60
                    [ ! -e "${FX}/on-contents" ] || { sh "${FX}/on-contents"; rm -f "${FX}/on-contents"; }
                    f="${path%%\?*}"; f="wf.${f##*/}"; ref="${path##*ref=}"
                    [ ! -e "${FX}/${f}.${ref}" ] || f="${f}.${ref}"; serve "${f}" ;;
      # The PR's merge ref, which ci_gate head reads for the workflows a pull_request runs: a 422, as
      # before GitHub makes one, so they are read at the head. Actions' workflows: none disabled.
      */commits/refs/pull/*) echo "gh: No commit found for SHA: refs/pull/7/merge (HTTP 422)" >&2; exit 1 ;;
      */actions/workflows\?*) echo '{"total_count":0,"workflows":[]}' ;;
      # A branch's head commit (gh api repos/o/r/commits/<branch> --jq .sha): commit.<branch>. A
      # commit's files: commit.<sha>, else one file outside the board.
      */commits/*) [ -e "${FX}/commit.${sha}" ] || { echo '{"files":[{"filename":"bin/x"}]}'; exit 0; }; serve "commit.${sha}" ;;
      *) echo "stub: no fixture for ${path}" >&2; exit 1 ;;
    esac ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
printf '#!/bin/sh\nA="%s"\n' "${ROOT}/agents" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'STUB'
[ ! -e "$A.fail" ] || exit 1
echo "$*" >> "$A.log"
case "$1 $2" in
  # Enough for conduct to start a conductor: its agent joins the list, in pane w:new.
  "--version ") echo "herdr 0.9.5" ;;
  "workspace list") echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  "tab create") echo '{"result":{"root_pane":{"pane_id":"w:new"}}}' ;;
  "agent start") echo "$3 w:new" >> "$A" ;;
  "agent prompt") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent wait") echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent list") [ ! -e "$A.garbage" ] || { echo "not json"; exit 0; }
                awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                     { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\",\"cwd\":\"%s\",\"agent_session\":{\"value\":\"%s\"}}", (NR > 1 ? "," : ""), $1, $2, $3, $4 }
                     END { print "]}}" }' "$A" ;;
  "agent read") cat "$A.screen.$3" 2>/dev/null ;;   # a pane's text, when a case writes one
esac
STUB
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr"
# claude: never the real one. Logs each call; plugin update fails with ${FX}/update.fail.
# shellcheck disable=SC2016 # expanded when the stub runs
printf '#!/bin/sh\necho "$*" >> "%s"\n[ "$2" != update ] || [ ! -e "%s/update.fail" ]\n' "${ROOT}/claude.log" "${FX}" > "${ROOT}/bin/claude"
chmod +x "${ROOT}/bin/claude"
# This project's panes: the conductor of epic e and the builder of story t.
printf 'w:c conduct-e\nw:b t\n' > "${P}/.swarm/state/e"
printf 'conduct-e w:c\nt w:b\n' > "${ROOT}/agents"

# run <name> <status> [conclusion] [sha] — one check run, or with [sha] one workflow run on it
# (<name>.yml its path).
run() {
  local c=null; [[ -z "${3:-}" ]] || c="\"$3\""
  printf '{"name":"%s","status":"%s","conclusion":%s,"html_url":"https://github.com/o/r/runs/%s","path":".github/workflows/%s.yml","head_sha":"%s"}' \
    "$1" "$2" "${c}" "$1" "$1" "${4:-${M}}"
}
# page <file> <key> <total> <item>... — one page of a list, appended to <file>.
page() { local f="$1" k="$2" t="$3" IFS=,; shift 3; printf '{"total_count":%s,"%s":[%s]}\n' "${t}" "${k}" "$*" >> "${f}"; }
checks() { local f="$1"; shift; rm -f "${f}"; page "${f}" check_runs "$#" "$@"; }
statuses() { local f="$1"; shift; rm -f "${f}"; page "${f}" statuses "$#" "$@"; }
wfruns() { local f="$1"; shift; rm -f "${f}"; page "${f}" workflow_runs "$#" "$@"; }
workflows() { # <name>... — .github/workflows on the merge commit: each <name>.yml runs on push to main
  local w list=""
  for w in "$@"; do
    list+="${list:+,}{\"name\":\"${w}.yml\",\"path\":\".github/workflows/${w}.yml\",\"type\":\"file\"}"
    printf 'name: %s\non:\n  pull_request:\n    types: [opened]\n  push:\n    branches: [main]   # main only\n' "${w}" > "${FX}/wf.${w}.yml"
  done
  echo "[${list}]" > "${FX}/workflows"
}
# item <slug> <front-matter line>... — a fresh story: its file, and no state file.
item() { { echo ---; printf '%s\n' "${@:2}"; echo ---; echo; echo "# $1"; } > "${P}/docs/stories/$1.md"; rm -f "${P}/.swarm/board-state/stories/$1"; }

# fresh [config line]... — merge = agent (a later line overrides it), since with merge = human the
# lead merges only under an HLD that grants merge (the grant cases below); story s in review with
# prs: ${URL}; head ${H1} with one green check run and no status; squash allowed; on the merge commit
# a green check run and a green run of the one workflow that runs on push to main.
fresh() {
  rm -rf "${FX}" "${P}/.swarm/events.tsv" "${ROOT}/gh.log" "${P}"/docs/stories/fix-main-*; mkdir -p "${FX}"; : > "${ROOT}/gh.log"
  printf '%s\n' "merge = agent" "$@" > "${P}/.claude/swarm/config"
  echo OPEN > "${FX}/state"; echo "${H1}" > "${FX}/head"; echo null > "${FX}/mergecommit"; echo main > "${FX}/base"
  echo '[{"filename":"docs/stories/s.md","status":"modified"}]' > "${FX}/files"; echo 1 > "${FX}/nfiles"; : > "${FX}/diff"
  echo '{"nameWithOwner":"o/r"}' > "${FX}/origin"; echo '[]' > "${FX}/rules"; echo 'Branch not protected' > "${FX}/branch.404"
  echo '{"data":{"repository":{"mergeQueue":null}}}' > "${FX}/mq"
  echo '{"squashMergeAllowed":true,"mergeCommitAllowed":true,"rebaseMergeAllowed":true}' > "${FX}/repo"
  checks "${FX}/${H1}.checks" "$(run test completed success)"; statuses "${FX}/${H1}.status"
  checks "${FX}/${M}.checks" "$(run test completed success)"; statuses "${FX}/${M}.status"
  workflows ci; wfruns "${FX}/${M}.runs" "$(run ci completed success "${M}")"
  item s "status: review" "prs: ${URL}"
}
# merge [VAR=value]... <args> — swarm.sh merge outside herdr unless VARs say otherwise; sets rc,
# output in ${ROOT}/out. Its CI waits get ${MERGE_CI} seconds (5 unless the file sets it: a merge that
# merges the base in also reads the new head's workflows, which on a loaded machine can take longer).
# A caller's MERGE_RUN array, when set, is a command swarm.sh runs under (merge_rules_test.sh's on_tty).
merge() {
  local envs=()
  while [[ "${1:-}" == [A-Z]*=* ]]; do envs+=("$1"); shift; done
  rc=0
  (cd "${P}" && ${MERGE_RUN[@]+"${MERGE_RUN[@]}"} env -u HERDR_ENV -u HERDR_PANE_ID -u SWARM_PROJECT -u SWARM_AGENT PATH="${ROOT}/bin:${PATH}" SWARM_MERGE_POLL=0 SWARM_MERGE_READ_WAIT=0 SWARM_MERGE_CI_GRACE=0 \
    SWARM_MERGE_CI_SECONDS="${MERGE_CI:-5}" SWARM_RELEASE_WAIT=0 ${envs[@]+"${envs[@]}"} bash "${SWARM}" merge "$@" > "${ROOT}/out" 2>&1) || rc=$?
}
# events — each events.tsv line's command, target and outcome(), the outcome without its key=value tail
EVENT_AWK="$(PROJECT_DIR="${ROOT}" bash -c 'source "$1/agents.sh"; printf %s "${EVENT_OUTCOME_AWK}"' _ "${REPO}/bin/lib")"
events() { awk -F'\t' "${EVENT_AWK}"'{ print $2 " " $3 " " outcome($5) }' "${P}/.swarm/events.tsv" 2>/dev/null || true; }
merge_lines() { events | grep -c '^merge ' || true; }
logged() { events | grep -q -- "$1"; }
# and_logged <pattern> <command>... — the command succeeds and events.tsv has a line matching
# <pattern>: one check, so a miss counts as a FAIL and never ends the file under set -e.
and_logged() { local p="$1"; shift; "$@" && logged "${p}"; }

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
merged() { grep -q '^pr merge' "${ROOT}/gh.log"; }
not_merged() { ! merged; }
said() { grep -qF -- "$1" "${ROOT}/out"; }
# refused <name> <text> — the last merge failed naming <text>, called no pr merge, and logged one merge line.
refused() {
  is "$1: exits non-zero" 1 "${rc}"
  check "$1: says ${2}" said "$2"
  check "$1: no pr merge" not_merged
  is "$1: one merge line" 1 "$(merge_lines)"
}

# release_pr — fresh, with no story s: a PR that changes only .claude-plugin/plugin.json's version, 1.2.0 to
# 1.3.0, its merge commit's first parent origin's main.
release_pr() {
  fresh; rm "${S}"; echo '[{"filename":".claude-plugin/plugin.json","status":"modified"}]' > "${FX}/files"
  echo '{"name":"x","version":"1.2.0","hooks":{}}' > "${FX}/wf.plugin.json"
  echo '{"name":"x","version":"1.3.0","hooks":{}}' > "${FX}/wf.plugin.json.${H1}"
  parent "$(git -C "${ROOT}/origin.git" rev-parse main)"
}
# parent <sha> — the merge commit's first parent, as gh reads it.
parent() { printf '{"files":[{"filename":".claude-plugin/plugin.json"}],"parents":[{"sha":"%s"}]}' "$1" > "${FX}/commit.${M}"; }
# finish <what> — the file's last line: a summary, and exit 1 when any check failed.
finish() {
  echo
  if [[ ${fails} -eq 0 ]]; then echo "all $1 tests passed"; else echo "${fails} $1 test(s) failed"; exit 1; fi
}
