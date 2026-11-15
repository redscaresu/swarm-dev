# shellcheck shell=bash
# handover.sh — swarm.sh handover: what another machine needs to carry on a project that git does not
# carry. Sourced by bin/swarm.sh; bin/lib/handover.py does the copy and writes the two notes.

# path_within <path> <dir> — true when <path> is <dir> or under it; both are real paths (pwd -P).
# / holds every path: its prefix is not "//".
path_within() { [[ "$2" == / || "$1" == "$2" || "${1#"$2"/}" != "$1" ]]; }   # loose-match: ok both quoted, so exact text

# handover_report <dir> [--memory <dir>] — write into <dir>, a new or empty folder outside the project's
# repo, the board's repo and the memory folder: swarm/ (the project's .swarm/ without session logs, agent
# session ids or what belongs to this machine (pane records, launch wrappers, locks and pid files), and
# with no file whose name looks like a credential),
# board.patch (the main checkout's uncommitted board edits, untracked files too, against its HEAD),
# snapshot.md (the open PRs and this project's agents) and RESTORE.md (the commands that restore each part into a fresh clone,
# naming the handover by HANDOVER_DIR wherever it was moved to, and every path left out). The lead's
# memory folder goes in memory/ only when --memory names it; nothing is ever pushed or published.
handover_report() {
  local usage="usage: swarm.sh handover <dir> [--memory <dir>]" out="" memory="" made="" bdir top spec \
    common pcommon ocommon entries sdir tmp commit p paths=() branch prs="" prs_err="" agents="" agents_err="" rc=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --memory) [[ -n "${2:-}" ]] || die "${usage}"; memory="$2"; shift 2 ;;
      -*) die "${usage}" ;;
      *) [[ -z "${out}" ]] || die "${usage}"; out="$1"; shift ;;
    esac
  done
  [[ -n "${out}" ]] || die "${usage}"
  if [[ -n "${memory}" ]]; then
    [[ -d "${memory}" ]] || die "handover: --memory ${memory} is not a folder"
    memory="$(cd "${memory}" && pwd -P)"
  fi
  # The board as it sits in the main checkout, whose uncommitted edits are the ones another machine lacks.
  bdir="$(main_checkout "${BOARD}" 2>/dev/null)" || die "handover: the board ${BOARD} is not in a git repo"
  top="$(git -C "${bdir}" rev-parse --show-toplevel)" || die "handover: no checkout holds the board ${bdir}"
  spec="${bdir#"${top}"}"; spec="${spec#/}"; spec="${spec:-.}"
  commit="$(git -C "${top}" rev-parse -q --verify HEAD)" || die "handover: ${top} has no commit for the board patch to be against"
  branch="$(git -C "${top}" rev-parse --abbrev-ref HEAD)"
  common="$(git -C "${top}" rev-parse --path-format=absolute --git-common-dir)"
  # A project that is no git repo has none, and is then never the board's repo.
  pcommon="$(git -C "${PROJECT_DIR}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || pcommon=""
  if [[ -e "${out}" ]]; then
    # A folder ls cannot list may hold anything, so it is not taken as empty.
    [[ -d "${out}" ]] && entries="$(ls -A "${out}" 2>/dev/null)" && [[ -z "${entries}" ]] \
      || die "handover: ${out} is not an empty folder; name a new one"
  else
    mkdir -p "${out}" || die "handover: cannot make ${out}"; made=1
  fi
  out="$(cd "${out}" && pwd -P)"
  # Inside the project's repo or the board's (any worktree of either), the handover could be committed and
  # pushed; inside .swarm/ or the memory folder, it would copy itself.
  ocommon="$(git -C "${out}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || ocommon=""
  if [[ -n "${ocommon}" && ( "${ocommon}" == "${common}" || "${ocommon}" == "${pcommon}" ) ]] || path_within "${out}" "${PROJECT_DIR}"; then
    [[ -z "${made}" ]] || rmdir "${out}"
    die "handover: ${out} is inside the project's repo, where it could be committed; name a folder outside it"
  fi
  # .swarm/ may be a symlink to a folder elsewhere, which the copy would follow into the handover.
  sdir="$(cd "${PROJECT_DIR}/.swarm" 2>/dev/null && pwd -P)" || sdir=""
  if [[ -n "${sdir}" ]] && path_within "${out}" "${sdir}"; then
    [[ -z "${made}" ]] || rmdir "${out}"
    die "handover: ${out} is inside ${sdir}, the project's .swarm/, which it would copy into itself; name a folder outside it"
  fi
  if [[ -n "${memory}" ]] && path_within "${out}" "${memory}"; then
    [[ -z "${made}" ]] || rmdir "${out}"
    die "handover: ${out} is inside --memory ${memory}, which it would copy into itself; name a folder outside it"
  fi
  chmod 700 "${out}"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/handover.XXXXXX")" || die "handover: cannot make a temp folder"
  # A board in the project's repo is board_paths' paths (a board_dir of . is the project's root, whose
  # other files are no board edit); one in a repo of its own is its whole folder, nested in the project's
  # folder or not: board_paths names paths in the project's repo, which match nothing in the board's.
  if [[ "${pcommon}" == "${common}" ]]; then
    while IFS= read -r p; do paths+=("${p}"); done < <(board_paths)
  fi
  (( ${#paths[@]} > 0 )) || paths=("${spec}")
  # A throwaway index, so the patch takes untracked board files too without touching the checkout's own.
  # It stages the board's own files only, tracked, deleted or new, as ls-files lists them: staging the
  # project's other files would run their clean filters and hash them, and one it cannot read would stop
  # the handover. ls-files takes a path that matches nothing (a board with no hld/ yet), which git add
  # refuses, and an empty list stages nothing (git add -A with none would take every file). The prefixes,
  # --no-color, --no-ext-diff, --no-textconv and --unified=3 are set, as diff.noprefix would drop the a/
  # and b/ that RESTORE.md's git apply expects, color.diff = always would add escapes, a diff.external or
  # textconv driver would write something else than a patch, and diff.context = 0 hunks git apply refuses.
  { GIT_INDEX_FILE="${tmp}/index" git -C "${top}" read-tree HEAD \
      && GIT_INDEX_FILE="${tmp}/index" git -C "${top}" ls-files -z --cached --others --exclude-standard -- "${paths[@]}" \
        > "${tmp}/files" \
      && { [[ ! -s "${tmp}/files" ]] || GIT_LITERAL_PATHSPECS=1 GIT_INDEX_FILE="${tmp}/index" git -C "${top}" add -A \
        --pathspec-from-file="${tmp}/files" --pathspec-file-nul; } \
      && GIT_INDEX_FILE="${tmp}/index" git -C "${top}" diff --cached --binary --no-renames --no-color --no-ext-diff --no-textconv \
        --unified=3 --src-prefix=a/ --dst-prefix=b/ \
        HEAD -- "${paths[@]}" > "${out}/board.patch"
  } || { rm -rf "${tmp}"; die "handover: cannot write the board patch from ${top}"; }
  rm -rf "${tmp}"
  prs="$(cd "${PROJECT_DIR}" && within 60 gh pr list --state open --limit 200 --json number,title,headRefName,isDraft,url 2>/dev/null)" \
    || { prs=""; prs_err="gh pr list failed in ${PROJECT_DIR}"; }
  if [[ "${HERDR_ENV:-}" != 1 ]]; then
    agents_err="not inside a herdr pane, so herdr's agent list was not asked"
  elif ! agents="$(herdr agent list 2>/dev/null)"; then
    agents=""; agents_err="herdr gave no agent list"
  fi
  # The last argument is the board's checkout again when the board is in the project's repo, else the
  # project's, so RESTORE.md can tell the user to apply the patch in the board repo's clone.
  # handover.py reads this project's pane records itself: own_panes would open a file named like a token.
  HANDOVER_PRS="${prs}" HANDOVER_PRS_ERR="${prs_err}" HANDOVER_AGENTS="${agents}" HANDOVER_AGENTS_ERR="${agents_err}" \
    HANDOVER_BOARD="${bdir}" python3 -I "${SWARM_HOME}/bin/lib/handover.py" "${out}" "${PROJECT_DIR}/.swarm" "${memory}" "${top}" "${commit}" \
    "${branch}" "$([[ "${pcommon}" == "${common}" ]] && echo "${top}" || echo "${PROJECT_DIR}")" || rc=$?
  (( rc == 0 )) || die "handover: copying into ${out} failed; delete it before you try again"
}
