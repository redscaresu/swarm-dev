# shellcheck shell=bash
# diff_fixtures_dropped.sh — tests/diff_run.sh's fixtures for dropped-lines-own-story-file (#1021):
# `swarm.sh dropped-lines --story` and merge's story route skip a story PR's own story file when its
# head deletes it. diff_run.sh sources this file, and every other tests/diff_fixtures_*.sh, by a glob;
# its header says what a fixture sets. scripts/allow/stage-1/dropped-lines-own-story-file.md names
# what #1021 changed on each of them, and on the seed usage fixture.
# The fixtures need nothing else under tests/: tests/diff_run_test.sh copies only diff_run.sh and the
# diff_fixtures_*.sh files into the trees it compares.
# shellcheck disable=SC2034 # diff_run.sh reads the FX_ settings

# Every commit has this date, so its SHA is the same in each run and on each tree.
DROPPED_GIT_DATE="2026-11-19T12:00:00Z"
DROPPED_URL=https://github.com/o/r/pull/7
DROPPED_MERGE_SHA=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa   # the merge commit gh pr merge makes

# dropped_git <args> — git with no user config and the fixed date.
dropped_git() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_DATE="${DROPPED_GIT_DATE}" \
    GIT_COMMITTER_DATE="${DROPPED_GIT_DATE}" git -c user.name=t -c user.email=t@t -c init.defaultBranch=main "$@"
}

# dropped_stubs <head> — ${ROOT}/bin/gh and ${ROOT}/bin/herdr. gh answers PR 7 of o/r, its head
# <head>, with fixed answers: open until gh pr merge (pinned to <head>) marks it merged in
# ${ROOT}/fx/state, its merge commit then ${DROPPED_MERGE_SHA}; one green check run on <head> and on
# that commit, and on that commit a green run of ci.yml, the one workflow, which runs on push to main;
# its commits from ${ROOT}/fx/prcommits through --jq; the PRs that hold any commit
# (commits/<sha>/pulls, merged_parent's read) from ${ROOT}/fx/pulls through --jq, while a fixture has
# written it; its one file the story's; no merge queue, no rules and no branch protection; the base
# gained nothing since the head; and the project's origin named o/r, so the board is in the PR's repo.
# Any other call fails, naming itself. herdr lists no agent.
dropped_stubs() {
  mkdir -p "${ROOT}/bin" "${ROOT}/fx"; echo OPEN > "${ROOT}/fx/state"
  printf '#!/usr/bin/env bash\nFX=%q H=%q M=%q\n' "${ROOT}/fx" "$1" "${DROPPED_MERGE_SHA}" > "${ROOT}/bin/gh"
  cat >> "${ROOT}/bin/gh" <<'DROPPED_GH'
run() { printf '{"name":"%s","status":"completed","conclusion":"success","html_url":"https://github.com/o/r/runs/%s","path":".github/workflows/%s.yml","head_sha":"%s"}' "$1" "$1" "$1" "$2"; }
st="$(cat "${FX}/state")"; mc=null; [ "${st}" != MERGED ] || mc="{\"oid\":\"${M}\"}"
files='[{"filename":"docs/stories/s.md","status":"modified"}]'
for a in "$@"; do path="${a}"; done
q=.; prev=""; for a in "$@"; do [ "${prev}" != --jq ] || q="${a}"; prev="${a}"; done
case "$1 $2" in
  "pr view") printf '{"state":"%s","headRefOid":"%s","baseRefName":"main","mergeCommit":%s,"changedFiles":1,"body":null,"commits":[{}],"mergeable":"MERGEABLE","headRefName":"story/s"}\n' "${st}" "${H}" "${mc}" ;;
  "pr merge") want=""; prev=""; for a in "$@"; do [ "${prev}" != --match-head-commit ] || want="${a}"; prev="${a}"; done
              [ "${want}" = "${H}" ] || { echo "GraphQL: Head branch was modified. Review and try the merge again." >&2; exit 1; }
              echo MERGED > "${FX}/state" ;;
  "repo view") case "$*" in *nameWithOwner*) echo '{"nameWithOwner":"o/r"}' ;;
                 *) echo '{"squashMergeAllowed":true,"mergeCommitAllowed":true,"rebaseMergeAllowed":true}' ;; esac ;;
  "api graphql") echo '{"data":{"repository":{"mergeQueue":null}}}' ;;
  api*) case "$*" in *"/pulls/7/commits?"*) jq -r "${q}" "${FX}/prcommits"; exit ;;   # its --jq comes after the path
          *"/commits/"*"/pulls?"*) [ -f "${FX}/pulls" ] || { echo "stub: no answer for gh $*" >&2; exit 1; }
                                   jq -r "${q}" "${FX}/pulls"; exit ;;
        esac
        case "${path}" in
          */pulls/7/files\?*) echo "${files}" ;;
          */commits/refs/pull/*) echo "gh: No commit found for SHA: refs/pull/7/merge (HTTP 422)" >&2; exit 1 ;;
          */commits/"${H}"/check-runs\?*|*/commits/"${M}"/check-runs\?*) printf '{"total_count":1,"check_runs":[%s]}\n' "$(run test "${M}")" ;;
          */commits/"${H}"/status\?*|*/commits/"${M}"/status\?*) echo '{"total_count":0,"statuses":[]}' ;;
          */contents/.github/workflows\?*) echo '[{"name":"ci.yml","path":".github/workflows/ci.yml","type":"file"}]' ;;
          */contents/.github/workflows/ci.yml\?*) printf 'name: ci\non:\n  pull_request:\n    types: [opened]\n  push:\n    branches: [main]\n' ;;
          */actions/workflows\?*) echo '{"total_count":0,"workflows":[]}' ;;
          */actions/runs\?head_sha="${M}"\&*) printf '{"total_count":1,"workflow_runs":[%s]}\n' "$(run ci "${M}")" ;;
          */compare/main..."${H}") echo "{\"files\":${files}}" ;;
          */compare/"${H}"...main) echo '{"ahead_by":0,"files":[]}' ;;
          */rules/branches/main\?*) echo '[]' ;;
          */branches/main/protection) echo "gh: Branch not protected (HTTP 404)" >&2; exit 1 ;;
          *) echo "stub: no answer for gh $*" >&2; exit 1 ;;
        esac ;;
  *) echo "stub: no answer for gh $*" >&2; exit 1 ;;
esac
DROPPED_GH
  cat > "${ROOT}/bin/herdr" <<'DROPPED_HERDR'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[]}}' ;;
  *) echo "stub: no answer for herdr $*" >&2; exit 1 ;;
esac
DROPPED_HERDR
  chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr"
}

# dropped_pr <head> — PR 7's head is <head>, a commit of ${ROOT}/w: pushed to refs/pull/7/head, gh's
# stubs written for it (dropped_stubs), and gh listing w's main..<head> as its commits, each with its
# parents.
dropped_pr() {
  local c ps sep="" json="["
  dropped_git -C "${ROOT}/w" push -q -f "${ROOT}/o/r.git" "$1:refs/pull/7/head"
  dropped_stubs "$1"
  for c in $(dropped_git -C "${ROOT}/w" rev-list --reverse "main..$1"); do
    ps="$(dropped_git -C "${ROOT}/w" rev-list --parents -n 1 "${c}" | cut -d' ' -f2- | sed -E 's/([0-9a-f]+)/{"sha":"\1"}/g; s/ /,/g')"
    json+="${sep}{\"sha\":\"${c}\",\"parents\":[${ps}]}"; sep=,
  done
  echo "${json}]" > "${ROOT}/fx/prcommits"
}

# dropped_project — a project ${ROOT}/proj under merge = agent, its board docs/ in its own repo, with
# story s in review on PR 7, and its origin a local bare repo that gh names o/r. The user's settings
# allow swarm.sh merge. Beside it, the bare ${ROOT}/o/r.git and its clone ${ROOT}/r, which
# dropped-lines reads. A work repo ${ROOT}/w pushes main there with docs/stories/s.md; its branch own
# deletes that file, main then adds `fix: true` to it (as board PR #1002 did), and own's merge of main
# keeps the deletion. PR 7's head is that merge (OWN): pushed to refs/pull/7/head, and gh lists
# main..OWN as its commits (dropped_pr). The command's cwd is the project, with no waits for merge's polls and reads
# and 5 s for its CI waits.
dropped_project() {
  local p="${ROOT}/proj" w="${ROOT}/w"
  mkdir -p "${p}/.claude/swarm" "${p}/docs/stories" "${p}/.swarm" "${ROOT}/claude-config" "${ROOT}/o"
  echo '{"permissions":{"allow":["Bash(swarm.sh merge *)"]}}' > "${ROOT}/claude-config/settings.json"
  echo "merge = agent" > "${p}/.claude/swarm/config"
  printf -- '---\nstatus: review\nprs: %s\n---\n\n# s\n' "${DROPPED_URL}" > "${p}/docs/stories/s.md"
  dropped_git init -q "${p}"; dropped_git init -q --bare "${ROOT}/origin.git"; dropped_git -C "${p}" remote add origin "${ROOT}/origin.git"
  dropped_git init -q "${w}"; mkdir -p "${w}/docs/stories"; dropped_git init -q --bare "${ROOT}/o/r.git"
  printf '%s\n' one two > "${w}/f"; printf '%s\n' 'status: ready' x > "${w}/docs/stories/s.md"
  dropped_git -C "${w}" add -A; dropped_git -C "${w}" commit -qm main0
  dropped_git -C "${w}" checkout -q -b own; dropped_git -C "${w}" rm -q docs/stories/s.md; dropped_git -C "${w}" commit -qm 'the story is done'
  dropped_git -C "${w}" checkout -q main; printf '%s\n' 'status: ready' 'fix: true' x > "${w}/docs/stories/s.md"
  dropped_git -C "${w}" commit -qam 'fix: true'; dropped_git -C "${w}" push -q "${ROOT}/o/r.git" main
  dropped_git clone -q "${ROOT}/o/r.git" "${ROOT}/r"
  dropped_git -C "${w}" checkout -q own; dropped_git -C "${w}" merge -q --no-ff --no-commit main > /dev/null 2>&1 || true
  rm -f "${w}/docs/stories/s.md"; dropped_git -C "${w}" add -A; dropped_git -C "${w}" commit -q --no-edit
  OWN="$(dropped_git -C "${w}" rev-parse HEAD)"
  dropped_pr "${OWN}"
  FX_CWD="${p}"; FX_GH="${ROOT}/bin/gh"; FX_HERDR="${ROOT}/bin/herdr"
  FX_ENV=("PATH=${ROOT}/bin:${PATH}" SWARM_MERGE_POLL=0 SWARM_MERGE_READ_WAIT=0 SWARM_MERGE_CI_GRACE=0
    SWARM_MERGE_CI_SECONDS=5 SWARM_RELEASE_WAIT=0)
}

# dropped-lines with a --story that is no slug: a usage error on both trees, whose usage line #1021
# changed.
fx_dropped_story_usage() { dropped_project; FX_CMD=(bash "${TREE}/bin/swarm.sh" dropped-lines --story ../s o/r 7 "${OWN}" main); }
# dropped-lines --story s on OWN: a usage error on v0.31.2, which has no --story; from v0.31.3, no
# line of s's own story file is a drop, so it exits 0.
fx_dropped_own_story() { dropped_project; FX_CMD=(bash "${TREE}/bin/swarm.sh" dropped-lines --story s o/r 7 "${OWN}" main); }
# dropped-lines on OWN with no --story (a board or lead PR): `fix: true` is a drop on both trees.
fx_dropped_no_story() { dropped_project; FX_CMD=(bash "${TREE}/bin/swarm.sh" dropped-lines o/r 7 "${OWN}" main); }
# merge of story s's PR, its head OWN: v0.31.2 holds it for `fix: true`; from v0.31.3 dropped_hold
# passes --story s, origin_repo's gh repo view names the board's repo, and it merges.
# A hold's record in the story's board state carries the time it was written (`protected: <url> <head>
# <epoch seconds> <what>`, from date +%s), which no diff_run.sh mask covers. Once merge exits, the
# command puts <epoch> in that field of each entry, and only there, so the record compares run to run.
# shellcheck disable=SC2016 # bash -c's own arguments
DROPPED_MERGE_CMD='rc=0; bash "$1/bin/swarm.sh" merge "$2" || rc=$?
for s in .swarm/board-state/stories/*; do
  [ ! -f "${s}" ] || perl -pi -e '"'"'s/(^protected: | \| )(\S+ [0-9a-f]{40}) \d+ /$1$2 <epoch> /g'"'"' "${s}"
done
exit "${rc}"'
fx_dropped_merge_own_story() { dropped_project; FX_CMD=(bash -c "${DROPPED_MERGE_CMD}" _ "${TREE}" "${DROPPED_URL}"); }

# dropped_merge <branch> [<line>...] — w merges <branch> into the branch checked out, with t resolved to
# the lines given (else the auto-merge's result), and commits
dropped_merge() {
  local w="${ROOT}/w" b="$1"; shift
  dropped_git -C "${w}" merge -q --no-ff --no-commit "${b}" > /dev/null 2>&1 || true
  [[ $# -eq 0 ]] || printf '%s\n' "$@" > "${w}/t"
  dropped_git -C "${w}" add -A; dropped_git -C "${w}" commit -q --no-edit
}

# dropped_octopus — dropped_project, then PR 7's head is OCT, an octopus: w's branch oct, off main, adds p
# and merges b1 and b2, each off main with a file of its own, in one merge of three parents.
dropped_octopus() {
  local w="${ROOT}/w" b
  dropped_project
  for b in b1 b2 oct; do
    dropped_git -C "${w}" checkout -q -b "${b}" main; echo "${b}" > "${w}/${b}"
    dropped_git -C "${w}" add -A; dropped_git -C "${w}" commit -qm "${b}"
  done
  dropped_git -C "${w}" merge -q --no-edit b1 b2 > /dev/null
  OCT="$(dropped_git -C "${w}" rev-parse HEAD)"
  dropped_pr "${OCT}"
}
# dropped-lines on OCT: sides() stops on its three parents, exit 2.
fx_dropped_octopus() { dropped_octopus; FX_CMD=(bash "${TREE}/bin/swarm.sh" dropped-lines o/r 7 "${OCT}" main); }
# merge of story s's PR, its head OCT: dropped_hold holds it as `dropped base lines unchecked: <the
# octopus stop line>` and records that in s's board state, its time masked as in fx_dropped_merge_own_story.
fx_dropped_merge_unchecked() { dropped_octopus; FX_CMD=(bash -c "${DROPPED_MERGE_CMD}" _ "${TREE}" "${DROPPED_URL}"); }

# dropped-lines on a stacked build's merge of a merged parent's branch that drops a base line
# (tests/dropped_lines_test.sh's PMD, in w on t): par, off main, replaces t2; kid, stacked on par, adds
# k; main appends t-main, which kid merges and par lacks; par appends t-par, so kid's merge of par
# conflicts, and its resolution keeps t-par alone (PMD), dropping main's line from kid's side. par then
# merges main, keeping both, and squash-merges into main (SQ), pushed to o/r. gh lists PR #6, which
# holds PMD's second parent, as merged with SQ, so merged_parent passes `--merged <par's tip>:<SQ>` and
# the scan prints t-main, exit 1.
fx_dropped_merged_parent() {
  local w="${ROOT}/w" sq
  dropped_project
  dropped_git -C "${w}" checkout -q main; printf '%s\n' t1 t2 t3 > "${w}/t"
  dropped_git -C "${w}" add -A; dropped_git -C "${w}" commit -qm t
  dropped_git -C "${w}" checkout -q -b par main; printf '%s\n' t1 t2-par t3 > "${w}/t"; dropped_git -C "${w}" commit -qam 'par: t2'
  dropped_git -C "${w}" checkout -q -b kid par; echo k > "${w}/k"
  dropped_git -C "${w}" add -A; dropped_git -C "${w}" commit -qm 'kid: k'
  dropped_git -C "${w}" checkout -q main; printf '%s\n' t1 t2 t3 t-main > "${w}/t"; dropped_git -C "${w}" commit -qam 'main: t-main'
  dropped_git -C "${w}" checkout -q kid; dropped_merge main
  dropped_git -C "${w}" checkout -q par; printf '%s\n' t1 t2-par t3 t-par > "${w}/t"; dropped_git -C "${w}" commit -qam 'par: t-par'
  dropped_git -C "${w}" checkout -q kid; dropped_merge par t1 t2-par t3 t-par
  PMD="$(dropped_git -C "${w}" rev-parse HEAD)"
  dropped_git -C "${w}" checkout -q par; dropped_merge main t1 t2-par t3 t-main t-par
  dropped_git -C "${w}" checkout -q main; dropped_git -C "${w}" merge -q --squash par > /dev/null
  dropped_git -C "${w}" commit -qm 'the parent (#6)'; sq="$(dropped_git -C "${w}" rev-parse HEAD)"
  dropped_git -C "${w}" push -q "${ROOT}/o/r.git" main
  dropped_pr "${PMD}"
  printf '[{"number":6,"merged_at":"2026-11-22T00:00:00Z","merge_commit_sha":"%s"}]\n' "${sq}" > "${ROOT}/fx/pulls"
  FX_CMD=(bash "${TREE}/bin/swarm.sh" dropped-lines o/r 7 "${PMD}" main)
}
