# shellcheck shell=bash

# brief_trailers — the commit trailers the project's brief names, wherever a line has one (quoted or
# backticked in a sentence too): a <Word>-by: token, a name with a letter in it and no colon or
# quote (so a match starts at the last token before the email, never in the prose ahead of it), and
# <an email>. A placeholder such as Co-Authored-By: <who> <email> has no name, so it is not one. One
# per line, in the brief's order.
brief_trailers() {
  [[ -f "${PROJECT_BRIEF}" ]] || return 0
  # shellcheck disable=SC2016 # the backticks are literal: a name holds none
  grep -oE '[A-Z][A-Za-z]*(-[A-Za-z]+)*-[Bb]y: [^<>"`:]*[A-Za-z][^<>"`:]* <[^<>[:space:]]+@[^<>[:space:]]+>' "${PROJECT_BRIEF}" \
    | awk '!seen[$0]++' || true
}

# origin_has <branch> — true when the project's origin has <branch>, false when it has not (ls-remote
# exits 2); dies when it cannot tell, so a step never goes on from a guess.
origin_has() {
  local rc=0
  git -C "${PROJECT_DIR}" ls-remote --exit-code origin "refs/heads/$1" >/dev/null 2>&1 || rc=$?
  [[ ${rc} -eq 0 || ${rc} -eq 2 ]] || die "board-pr: cannot tell whether origin has $1"
  return "${rc}"
}

# board_pr start|open|done <name> ... — the lead's board edits, each in its own worktree, never the
# main checkout: start makes <repo>-wt/_board-<name> (a path no story slug makes) on a new
# board/<name> from origin/<base> and prints its path; open <name> "<title>" <body-file> commits every change (all under the board) with
# the brief's trailers, pushes and opens the PR (or pushes to the one open), printing its URL, and
# refuses once the branch's PR has merged or closed; done <name> removes board/<name> on origin, then
# the worktree and board/<name> here, once the PR on the branch's tip has merged or closed, or, with
# no PR, when the branch has no commit past the base. It checks everything before removing anything. main logs each as board-pr:<step> <name>, with a refusal's
# reason.
board_pr() {
  local step="${1:-}" name="${2:-}" wt b base dir real url rel files f msg prs tip rtip why
  [[ "${step}" == start || "${step}" == open || "${step}" == "done" ]] \
    || die "usage: swarm.sh board-pr start <name> | open <name> \"<title>\" <body-file> | done <name>"
  [[ "${name}" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "board-pr: '${name}' is not a name (a-z, 0-9 and -)"
  [[ ${BOARD_IN_REPO} == 1 ]] || die "board-pr: the board is not in the project's repo"
  # The _ keeps it apart from story worktrees, <repo>-wt/<slug>: a slug never has one.
  wt="$(worktree_for "${PROJECT_DIR}" "_board-${name}")"; b="board/${name}"
  case "${step}" in
    start)
      # Resolved through any symlink or .., so a worktree can never land in the main checkout.
      dir="$(dirname "${wt}")"; real="${wt}"
      [[ ! -d "${dir}" ]] || real="$(cd "${dir}" && pwd -P)/$(basename "${wt}")"
      [[ "${real}" != "${PROJECT_DIR}" && "${real}" != "${PROJECT_DIR}/"* ]] \
        || die "board-pr: ${wt} resolves to ${real}, in the main checkout"
      [[ ! -e "${wt}" && ! -L "${wt}" ]] || die "board-pr: ${wt} exists"
      ! git -C "${PROJECT_DIR}" show-ref -q --verify "refs/heads/${b}" || die "board-pr: the branch ${b} exists"
      ! origin_has "${b}" || die "board-pr: origin has ${b}; run swarm.sh board-pr done ${name}, or delete it there"
      base="$(base_for "${PROJECT_DIR}")"
      git -C "${PROJECT_DIR}" worktree add -q -b "${b}" "${wt}" "origin/${base}" >&2 \
        || die "board-pr: git worktree add failed for ${wt} from origin/${base}"
      echo "${wt}" ;;
    open)
      [[ $# -eq 4 && -n "$3" ]] || die "usage: swarm.sh board-pr open <name> \"<title>\" <body-file>"
      [[ -f "$4" && -r "$4" ]] || die "board-pr: no body file at $4"
      [[ "$(git -C "${wt}" symbolic-ref -q --short HEAD 2>/dev/null)" == "${b}" ]] \
        || die "board-pr: ${wt} is not a worktree on ${b}; run swarm.sh board-pr start ${name}"
      base="$(base_for "${PROJECT_DIR}")"
      # The board's path from the root with a trailing /, or empty when the board is the root.
      rel=""; [[ "${BOARD}" == "${PROJECT_DIR}" ]] || rel="${BOARD#"${PROJECT_DIR}"/}/"
      # Committed and uncommitted changes since the base, a rename's old path too, and new files.
      files="$(git -C "${wt}" -c core.quotepath=off diff --name-only --no-renames "$(git -C "${wt}" merge-base HEAD "origin/${base}")" \
        && git -C "${wt}" -c core.quotepath=off ls-files --others --exclude-standard)" || die "board-pr: cannot list the changes in ${wt}"
      [[ -n "${files}" ]] || die "board-pr: ${wt} changes nothing"
      while IFS= read -r f; do [[ "${f}" == "${rel}"* ]] || die "board-pr: ${f} is outside ${rel}"; done <<< "${files}"
      url="$(git -C "${PROJECT_DIR}" remote get-url origin)"
      prs="$(gh pr list -R "${url}" --head "${b}" --state all --json state,url,headRefOid)" || die "board-pr: gh cannot list the PRs on ${b}"
      # A second open pushes more edits to the PR the first one opened. Once that PR merged or closed,
      # the branch still holds its commits: a new PR would apply them again (squashed) or mix them in.
      # A PR is this branch's when its head came after the branch's start (its reflog's first entry;
      # origin/<base> when that is gone): an earlier use of the name merged before it.
      url="$(json "next((p['url'] for p in d if p['state'] == 'OPEN'), '')" <<< "${prs}")"
      if [[ -z "${url}" ]]; then
        tip="$(git -C "${wt}" reflog --format=%H "refs/heads/${b}" 2>/dev/null | tail -1)"
        for f in $(json "' '.join(p['headRefOid'] for p in d)" <<< "${prs}"); do
          if git -C "${wt}" merge-base --is-ancestor "${f}" HEAD 2>/dev/null && ! git -C "${wt}" merge-base --is-ancestor "${f}" "${tip:-origin/${base}}"; then
            die "board-pr: the PR on ${b} has merged or closed; run swarm.sh board-pr done ${name}, then start again"
          fi
        done
      fi
      git -C "${wt}" add -A
      if ! git -C "${wt}" diff --cached --quiet; then
        msg="$3"; f="$(brief_trailers)"; [[ -z "${f}" ]] || msg+=$'\n\n'"${f}"
        git -C "${wt}" commit -q -m "${msg}" || die "board-pr: the commit failed in ${wt}"
      fi
      git -C "${wt}" push -q -u origin "${b}" || die "board-pr: cannot push ${b}"
      [[ -n "${url}" ]] || url="$(gh pr create -R "$(git -C "${PROJECT_DIR}" remote get-url origin)" --base "${base}" --head "${b}" --title "$3" --body-file "$4")" \
        || die "board-pr: gh pr create failed for ${b}"
      echo "${url##*$'\n'}" ;;
    done)
      url="$(git -C "${PROJECT_DIR}" remote get-url origin)" || die "board-pr: ${PROJECT_DIR} has no origin"
      tip="$(git -C "${PROJECT_DIR}" rev-parse -q --verify "refs/heads/${b}" || true)"
      # origin's tip, or nothing when origin has no such branch; one that moved past ours is not ours to drop.
      rtip="$(git -C "${PROJECT_DIR}" ls-remote origin "refs/heads/${b}")" || die "board-pr: cannot tell whether origin has ${b}"
      rtip="${rtip%%[[:space:]]*}"
      [[ -z "${rtip}" || -z "${tip}" || "${rtip}" == "${tip}" ]] \
        || die "board-pr: origin's ${b} is at ${rtip:0:7}, not ${tip:0:7} here; pull it into the worktree, or delete it there"
      tip="${tip:-${rtip}}"
      [[ -n "${tip}" ]] || die "board-pr: there is no ${b} here or on origin"
      # Any open PR on the branch stops it. Of the rest, only a PR on the branch's tip counts: an
      # earlier use of the name leaves its merged PR behind.
      prs="$(gh pr list -R "${url}" --head "${b}" --state all --json state,headRefOid \
        | SWARM_TIP="${tip}" json "'OPEN' if any(p['state'] == 'OPEN' for p in d) else ' '.join(p['state'] for p in d if p['headRefOid'] == e['SWARM_TIP'])")" \
        || die "board-pr: gh cannot list the PRs on ${b}"
      [[ "${prs}" != OPEN ]] || die "board-pr: the PR on ${b} is still open"
      # With no PR, only a branch with nothing past the base goes (a start that was abandoned).
      if [[ -z "${prs}" ]]; then
        base="$(base_for "${PROJECT_DIR}")"
        [[ -z "$(git -C "${PROJECT_DIR}" rev-list "origin/${base}..${tip}" 2>/dev/null || echo unknown)" ]] \
          || die "board-pr: no PR on ${b} has its tip ${tip:0:7}, and it has commits past origin/${base}; open it first"
      fi
      if [[ -e "${wt}" ]]; then
        [[ "$(git -C "${wt}" symbolic-ref -q --short HEAD 2>/dev/null)" == "${b}" ]] || die "board-pr: ${wt} is not a worktree on ${b}; it is left alone"
        [[ -z "$(git -C "${wt}" status --porcelain --untracked-files=all)" ]] || die "board-pr: ${wt} has uncommitted changes"
        [[ ! -e "$(git -C "${wt}" rev-parse --absolute-git-dir)/locked" ]] || die "board-pr: ${wt} is locked; git worktree unlock it first"
      fi
      # branch -D fails on a branch checked out anywhere: the main checkout, or another worktree.
      f="$(git -C "${PROJECT_DIR}" worktree list --porcelain \
        | awk -v b="branch refs/heads/${b}" -v w="${wt}" '/^worktree / { p = substr($0, 10) } $0 == b && p != w { print p; exit }')"
      [[ -z "${f}" ]] || die "board-pr: ${b} is checked out at ${f}; switch that checkout off it first"
      # origin first: its delete can fail (the lease, a protected branch), and the local state must
      # then stay for the next run.
      [[ -z "${rtip}" ]] || git -C "${PROJECT_DIR}" push -q --force-with-lease="refs/heads/${b}:${rtip}" origin --delete "${b}" \
        || die "board-pr: cannot delete ${b} on origin"
      if [[ -e "${wt}" ]]; then
        why="$(git -C "${PROJECT_DIR}" worktree remove "${wt}" 2>&1)" || die "board-pr: cannot remove ${wt}: ${why%%$'\n'*}"
      fi
      git -C "${PROJECT_DIR}" worktree prune
      ! git -C "${PROJECT_DIR}" show-ref -q --verify "refs/heads/${b}" || git -C "${PROJECT_DIR}" branch -q -D "${b}"
      echo "removed ${wt} and ${b}" ;;
  esac
}

# pull_board_repo — pull the main checkout fast-forward, never losing an edit. It stops, touching
# nothing, when the pull cannot fast-forward (local commits) or a tracked file outside the board is
# changed. Otherwise it backs up, then puts back, each unstaged board edit (` M`, or `??` untracked)
# whose bytes are already the upstream branch's, so the pull that brings the same content is not
# stopped by it. It also backs up and checks out each unstaged board file the pull changes whose edit
# is only to SET_FM_KEYS (swarm_edit), and puts those keys back after the pull; one the pull deletes
# stays deleted, named. It stops, touching nothing, naming the file, when the base changed one of
# those keys too, or a dependency under a status flip (key_clash). Any other edit is left alone. If
# the pull still fails, every file is restored from the backup in STATE_DIR/reconcile-backup/; the
# backup also stays, named, when the pull deleted a kept file or a key could not be set again. On
# failure PULL_WHY says why.
PULL_WHY=""
pull_board_repo() {
  local line path rel bak changed old k lost=0 put=() keep=()
  git -C "${PROJECT_DIR}" fetch -q || { PULL_WHY="cannot fetch"; return 1; }
  if ! git -C "${PROJECT_DIR}" merge-base --is-ancestor HEAD '@{upstream}'; then
    PULL_WHY="it has commits the base does not ($(git -C "${PROJECT_DIR}" log --format=%h '@{upstream}..HEAD' | paste -sd' ' -)), so it cannot fast-forward"
    return 1
  fi
  rel="${BOARD#"${PROJECT_DIR}"/}/"
  changed="$(git -C "${PROJECT_DIR}" status --porcelain --untracked-files=no | cut -c4- | awk -v b="${rel}" 'index($0, b) != 1' | paste -sd' ' -)"
  [[ -z "${changed}" ]] || { PULL_WHY="files outside the board are changed: ${changed}"; return 1; }
  while IFS= read -r line; do
    path="${line:3}"
    [[ "${line:0:2}" == " M" || "${line:0:2}" == "??" ]] || continue   # staged, deleted or renamed: left alone
    if git -C "${PROJECT_DIR}" cat-file -e "@{upstream}:${path}" 2>/dev/null \
      && git -C "${PROJECT_DIR}" show "@{upstream}:${path}" | cmp -s - "${PROJECT_DIR}/${path}"; then
      put+=("${path}")
    elif [[ "${line:0:2}" == " M" ]] && swarm_edit "${path}"; then
      k="$(key_clash "${path}")"
      [[ -z "${k}" ]] || { PULL_WHY="${path} has an uncommitted front-matter edit, and the base changed its ${k}: too"; return 1; }
      keep+=("${path}")
    fi
  done < <(git -C "${PROJECT_DIR}" status --porcelain --untracked-files=all -- "${BOARD}")
  bak="${STATE_DIR}/reconcile-backup/$(date +%Y%m%dT%H%M%S)-$$"
  for path in "${put[@]+"${put[@]}"}" "${keep[@]+"${keep[@]}"}"; do
    if ! { mkdir -p "$(dirname "${bak}/${path}")" && cp -p "${PROJECT_DIR}/${path}" "${bak}/${path}"; }; then
      PULL_WHY="cannot back up ${path}"; return 1
    fi
  done
  for path in "${put[@]+"${put[@]}"}"; do
    if git -C "${PROJECT_DIR}" ls-files --error-unmatch -- "${path}" >/dev/null 2>&1; then
      git -C "${PROJECT_DIR}" checkout -q -- "${path}"
    else
      rm -f "${PROJECT_DIR}/${path}"
    fi
    echo "reconcile: ${path} was already the base's; put it back before the pull (backup in ${bak})"
  done
  for path in "${keep[@]+"${keep[@]}"}"; do
    echo "reconcile: ${path} changes only swarm.sh's front-matter keys; checking it out for the pull, to set them again after it (backup in ${bak})"
    git -C "${PROJECT_DIR}" checkout -q -- "${path}"
  done
  old="$(git -C "${PROJECT_DIR}" rev-parse HEAD)"
  # Fast-forward to the upstream fetched above, which every check here read: a pull would fetch again.
  if ! git -C "${PROJECT_DIR}" merge -q --ff-only '@{upstream}'; then
    for path in "${put[@]+"${put[@]}"}" "${keep[@]+"${keep[@]}"}"; do cp -p "${bak}/${path}" "${PROJECT_DIR}/${path}"; done
    # shellcheck disable=SC2034 # read in another file
    PULL_WHY="the pull failed, and every board edit is as it was$(board_edits_named)"
    return 1
  fi
  for path in "${keep[@]+"${keep[@]}"}"; do keys_back "${path}" "${old}" "${bak}/${path}" || lost=1; done
  if [[ ${lost} -eq 1 ]]; then echo "reconcile: the backup stays in ${bak}"; return 0; fi
  rm -rf "${bak}"; rmdir "${STATE_DIR}/reconcile-backup" 2>/dev/null || true
}

# fm_rest <file> — <file> without the SET_FM_KEYS lines of its front matter; <file> may be - for stdin.
fm_rest() {
  awk -v keys=" ${SET_FM_KEYS} " '/^---$/ { n++ }
    n == 1 && match($0, /^[a-z_]+:/) && index(keys, " " substr($0, 1, RLENGTH - 1) " ") { next }
    { print }' "$1"
}

# swarm_edit <path> — true when the pull changes the board file <path> and its unstaged edit is only
# to SET_FM_KEYS (an unblock flip, a review), so it can be checked out for the pull and put back.
swarm_edit() {
  [[ "$(git -C "${PROJECT_DIR}" rev-parse -q --verify "HEAD:$1")" != "$(git -C "${PROJECT_DIR}" rev-parse -q --verify "@{upstream}:$1")" ]] \
    && cmp -s <(git -C "${PROJECT_DIR}" show "HEAD:$1" | fm_rest -) <(fm_rest "${PROJECT_DIR}/$1")
}

# key_clash <path> — the first SET_FM_KEYS key the unstaged board file <path> changes from HEAD's that
# the base changed to another value too, or, when the edit changes status, depends_on if the base
# changed it (a status is not set again over a new dependency); nothing when there is
# none, or the base deleted <path>.
key_clash() {
  local k l h u head up deps=""
  up="$(git -C "${PROJECT_DIR}" show "@{upstream}:$1" 2>/dev/null)" || return 0
  head="$(git -C "${PROJECT_DIR}" show "HEAD:$1")"
  # The file as it is (- reads stdin), never its state in STATE_DIR.
  [[ "$(get_fm - status < "${PROJECT_DIR}/$1")" == "$(get_fm - status <<< "${head}")" ]] || deps="depends_on"
  for k in ${SET_FM_KEYS} ${deps}; do
    l="$(get_fm - "${k}" < "${PROJECT_DIR}/$1")"; h="$(get_fm - "${k}" <<< "${head}")"; u="$(get_fm - "${k}" <<< "${up}")"
    [[ "${u}" == "${h}" || "${u}" == "${l}" ]] && continue
    [[ "${l}" == "${h}" && " ${deps} " != *" ${k} "* ]] && continue
    echo "${k}"; return 0
  done
}

# keys_back <path> <rev> <saved> — after the pull, set on the board file <path> each SET_FM_KEYS key
# whose value in <saved>, its copy from before, differs from <rev>'s. It fails, naming <saved>, when
# the pull deleted <path> or a key cannot be set.
keys_back() {
  local k v was bad=""
  [[ -f "${PROJECT_DIR}/$1" ]] || { echo "reconcile: the pull deleted $1, and its uncommitted front-matter edit with it (its copy is in $3)"; return 1; }
  was="$(git -C "${PROJECT_DIR}" show "$2:$1")"
  for k in ${SET_FM_KEYS}; do
    v="$(get_fm "$3" "${k}")"
    [[ "${v}" == "$(get_fm - "${k}" <<< "${was}")" ]] || set_file_fm "${PROJECT_DIR}/$1" "${k}" "${v}" || bad+=" ${k}"
  done
  [[ -z "${bad}" ]] || { echo "reconcile: cannot set${bad} again on $1 after the pull (its copy is in $3)"; return 1; }
  echo "reconcile: $1 took the pull and keeps its uncommitted front-matter edit"
}

# board_edits_named — "; board files changed here: <files>" for the board files the main checkout
# has changed, or nothing when there are none.
board_edits_named() {
  local files
  files="$(git -C "${PROJECT_DIR}" status --porcelain --untracked-files=all -- "${BOARD}" | cut -c4- | paste -sd' ' -)"
  [[ -z "${files}" ]] || echo "; board files changed here: ${files}"
}

# tab_label <name> — the tab label an agent name came from. Agent names stop at 32 characters
# (agent_name), tab labels do not, so `next` can hand back a name that is not the label. The first
# state file whose agent name matches wins: the base tab sorts before its "-2", "-3" overflow.
tab_label() {
  local want state
  want="$(agent_name "$1")"
  for state in "${STATE_DIR}"/*; do
    [[ -f "${state}" && "$(agent_name "$(basename "${state}")")" == "${want}" ]] || continue
    basename "${state}"; return
  done
  echo "$1"
}

# archive_session <name> — keep a gzip'd copy of <name>'s Claude session log (its newest agents.tsv
# line's session) as .swarm/sessions/<date>-<name>-<session>.jsonl.gz, once per session: Claude Code
# deletes session logs after cleanupPeriodDays. .swarm/ is git-ignored, so the copy stays on this
# machine, readable by its user only; nothing is redacted. An agent with no session (codex) has nothing to keep. A copy that
# fails is reported and never stops the close: the session log itself is untouched.
archive_session() {
  local name session src dir f
  name="$(agent_name "$1")"
  [[ -f "${AGENTS_LOG}" ]] || return 0
  session="$(awk -F'\t' -v n="${name}" 'NF == 7 && $3 == n { s = $7 } END { print s }' "${AGENTS_LOG}" 2>/dev/null || true)"
  [[ -n "${session}" && "${session}" != - ]] || return 0
  dir="${SESSIONS_DIR}"
  for f in "${dir}"/*-"${session}".jsonl.gz; do [[ ! -e "${f}" ]] || return 0; done
  src="$(SWARM_LIB="${SWARM_HOME}/bin/lib" python3 -I -c 'import os, sys; sys.path.insert(0, os.environ["SWARM_LIB"]); from report import *; print(session_log(*sys.argv[1:3]))' \
    "${CLAUDE_PROJECTS}" "${session}" 2>/dev/null || true)"
  [[ -n "${src}" ]] || return 0
  # Readable by this user only: the copy may hold secrets.
  ( umask 077 && mkdir -p "${dir}" && gzip -c "${src}" > "${dir}/.${session}.tmp" \
    && mv "${dir}/.${session}.tmp" "${dir}/$(date +%F)-${name}-${session}.jsonl.gz" ) \
    || { rm -f "${dir}/.${session}.tmp"; echo "${name}: could not archive session ${session}; its log is still at ${src}" >&2; }
}

# is_close_cause <word> — true for a cause close takes: why the builder stopped. met, stalled and
# bound are attempts; impossible, paused and cleared-on-error are not. CLOSE_CAUSE_WORDS is the one
# list; CLOSE_CAUSES is it as prose, for messages.
CLOSE_CAUSE_WORDS="met impossible stalled bound paused cleared-on-error"
is_close_cause() { [[ "$1" =~ ^[a-z-]+$ && " ${CLOSE_CAUSE_WORDS} " == *" $1 "* ]]; }
CLOSE_CAUSES="${CLOSE_CAUSE_WORDS// /, }"; CLOSE_CAUSES="${CLOSE_CAUSES%, *} or ${CLOSE_CAUSES##*, }"

# close_agent <name> [cause] — close what was opened for <name> (close_panes), its session log
# archived first.
# An unknown cause is refused before anything closes, and so, with goal on, is a missing one while
# <name>'s story is still ready (its builder is giving up), and so is impossible for a story that
# cannot be handed on (impossible_refused). A close that ends a failed build (failed_build, decided
# before anything closes, while the builder can still be found) then clears the attempt away
# (clear_build), so the next build starts fresh. With no cause, met, stalled or bound it first raises
# the story's attempts: by one, and when that build was escalate, the story becomes the lead's
# (escalate_story). impossible, paused and cleared-on-error count nothing. impossible makes the story
# the lead's (impossible_story) whether or not there was a build to clear; paused and cleared-on-error
# hold it for the lead (held_story) when the close ends a build.
close_agent() {
  local cause="${2:-}" f="${BOARD}/stories/$1.md" prs counted=0 n why
  # The message never repeats the word: main logs a die's first line.
  [[ -z "${cause}" ]] || is_close_cause "${cause}" \
    || die "close: the cause must be ${CLOSE_CAUSES} (swarm.sh close <name> [cause])"
  # shellcheck disable=SC2154 # assigned in another file
  [[ -n "${cause}" || "${CFG_goal}" == off || ! -f "${f}" || "$(fm "${f}" status)" != ready ]] \
    || die "close: with goal on, $1's story is still ready, so say why its builder stopped: swarm.sh close $1 <cause>, the cause one of ${CLOSE_CAUSES}"
  if [[ "${cause}" == impossible ]] && why="$(impossible_refused "$1")"; then
    die "close: $1 cannot be closed impossible, because ${why}; nothing was closed"
  fi
  archive_session "$1"
  if prs="$(failed_build "$1")"; then counted=1; fi
  # One builder, two names: herdr's (agent_name, cut at 32 characters), which failed_build and
  # retire_agent map to, and the pane record's full slug (start_agent's pane name), which close_panes
  # matches. Passing close_panes the cut name would leave a long slug's pane open.
  close_panes "$1"
  if [[ "${cause}" == impossible ]]; then
    # The build is cleared even when failed_build declined (a builder gone, gh down),
    # so the story builds again after reset; only PRs failed_build listed are closed.
    clear_build "$1" "the build of $1 stopped (impossible), which is not an attempt" "${prs:-[]}"
    impossible_story "$1" "${prs}" "${counted}"
    return 0
  fi
  case "${cause}" in paused|cleared-on-error)
    # Held, its build cleared so it builds again once the hold is lifted, when the close ends a build
    # (counted). A story whose PR merged or is merging, or whose PRs gh could not list, is left as it was, and for a story
    # an agent builds the close says so (not held:).
    if [[ ${counted} == 1 ]]; then
      clear_build "$1" "the build of $1 stopped (${cause}), which is not an attempt" "${prs:-[]}"
      held_story "$1" "${cause}" "${prs:-[]}"
    elif ! impossible_refused "$1" >/dev/null; then
      echo "not held: $1 (${cause}) ended no build here (no builder open, a PR merged or merging, or gh could not list its PRs), so its story is as it was: list it for the lead and do not start it again"
    fi
    return 0 ;;
  esac
  [[ ${counted} == 1 ]] || return 0
  n="$(get_fm "${f}" attempts)"
  # Checked before the arithmetic, which would evaluate it.
  [[ "${n}" =~ ^(0|[1-9][0-9]*)?$ ]] \
    || { echo "swarm: ${f}: attempts must be a non-negative whole number, not '${n}'; this failed build is not counted or cleared" >&2; return 0; }
  n=$((${n:-0} + 1))
  set_fm "${f}" attempts "${n}"
  clear_build "$1" "attempt ${n} at $1 failed" "${prs}"
  escalate_story "$1" "${n}" "${prs}"
}

# impossible_refused <name> — print why `close <name> impossible` cannot hand <name>'s story on, and
# succeed; fail, printing nothing, when it can: a story on the board, still ready, of a kind an agent
# builds (agent_kind). Whether its build can be cleared does not matter.
impossible_refused() {
  local f="${BOARD}/stories/$1.md" st kind
  [[ "$1" =~ ^[a-z0-9-]+$ && -f "${f}" ]] || { echo "there is no story file ${f}"; return 0; }
  st="$(fm "${f}" status)"
  [[ "${st}" == ready ]] || { echo "its story is ${st:-without a status}, not ready"; return 0; }
  kind="$(fm "${f}" kind)"
  agent_kind "${kind}" || { echo "its story is kind: ${kind}, which no agent builds"; return 0; }
  return 1
}

# ESCALATED_OPEN, ESCALATED_CLOSE: the markers around the lead's block, which escalate_story appends
# to a story and reset_story removes.
ESCALATED_OPEN="<!-- swarm.sh escalated: swarm.sh reset removes this block -->"
ESCALATED_CLOSE="<!-- /swarm.sh escalated -->"
# NO_KIND_LINE: escalated_from:'s value for a story that had no kind: line (built as code), so reset
# takes the line out again and the file is its committed text.
NO_KIND_LINE="code (default)"

# escalate_story <slug> <attempt> <prs> — after a counted close of an escalate build (the role on
# the newest agents.tsv line for the slug's agent), the story is the lead's to decide (lead_block),
# with a block naming the lead's choices. A story reset once already (reset_at) is offered only drop.
# The close of any other build changes nothing here.
escalate_story() {
  local f="${BOARD}/stories/$1.md" role from text when put k
  role="$(awk -F'\t' -v n="$(agent_name "$1")" '$3 == n { r = $2 } END { print r }' "${AGENTS_LOG}" 2>/dev/null || true)"
  [[ "${role}" == escalate ]] || return 0
  from="$(get_fm "${f}" kind)"; from="${from:-${NO_KIND_LINE}}"
  put="puts back \`kind: ${from}\`"
  [[ "${from}" != "${NO_KIND_LINE}" ]] || put="takes the \`kind:\` line out again (it had none, so it builds as code)"
  when="$(reset_at "$1")"
  text="**Escalated.** Attempt $2, built on Fable, failed, so no agent builds this story until the lead decides, then tells the user what it chose and why:"$'\n\n'
  if [[ -n "${when}" ]]; then
    text+="- It was reset once already (${when}), and \`swarm.sh reset\` refuses a second, so drop it: run \`swarm.sh drop $1 <reason>\`, which takes this story off the board, and commit the change in a board PR."
  else
    text+="- Re-scope the story, then run \`swarm.sh reset $1 <reason>\`, which ${put} while it still says \`kind: lead\` (a kind you set yourself stays), and clears \`attempts:\`. When the board is in the story's repo, a builder reads the story from the branch it starts from: merge the re-scope as a board PR first, then reset and pull the board in one go. At most one reset per story: after a second failed escalate build, drop it."$'\n'
    text+="- Or drop it: run \`swarm.sh drop $1 <reason>\`, which takes this story off the board, and commit the change in a board PR."
  fi
  k="$(lead_block "$1" "${text}" "$3")"
  record_event escalated "$1" "ok (attempts $2, ${k} PRs)"
  echo "escalated: $1 is kind: lead now, for the lead to reset or drop"
}

# impossible_story <slug> <prs> <listed> — after `close <slug> impossible`, the builder replied
# IMPOSSIBLE: the story's **Done when** cannot be met, so, like a failed Fable build, it is the lead's
# to decide: a lead_block with no **You:** step, naming the lead's choices, with <prs> (failed_build's
# list). Unless <listed> is 1, failed_build listed no PRs, and the block says so. attempts: stays as it was.
impossible_story() {
  local when choice none=""
  when="$(reset_at "$1")"
  choice="- Re-scope its **Done when** (the judge called it impossible from the builder's session), then run \`swarm.sh reset $1 <reason>\`, which puts its kind back so it is built again. When the board is in the story's repo, a builder reads the story from the branch it starts from: merge the re-scope as a board PR first, then reset and pull the board in one go."$'\n'"- Or drop it: run \`swarm.sh drop $1 <reason>\`, which takes this story off the board, and commit the change in a board PR."
  [[ -z "${when}" ]] || choice="- It was reset once already (${when}), and \`swarm.sh reset\` refuses a second, so drop it: run \`swarm.sh drop $1 <reason>\`, and put a re-scoped **Done when** in a new story if it is still wanted."
  [[ "$3" == 1 ]] || none="swarm.sh did not list the PRs on story/$1, so look at them before you reset it: \`gh pr list --head story/$1 --state all\` in its repo."
  lead_block "$1" "**Impossible.** The builder replied \`IMPOSSIBLE:\`, and this build was not counted as an attempt. No agent builds this story until the lead decides, then tells the user what it chose and why:"$'\n\n'"${choice}" "$2" "${none}" >/dev/null
  echo "impossible: $1 is kind: lead now, for the lead to re-scope or drop"
}

# held_story <slug> <cause> <prs> — after `close <slug> paused` or `close <slug> cleared-on-error`
# ends a build, the story is held for the lead: a lead_block with no **You:** step and held_for: <cause>, so
# no conductor or /swarm-dev:swarm run builds it again. attempts: stays as it was. Lifting the hold with reset
# is not the story's one reset (main logs it as reset:held, which reset_at does not read).
held_story() {
  local why="it paused on its goal"
  [[ "$2" != cleared-on-error ]] || why="its goal was cleared on an error"
  lead_block "$1" "**Held ($2).** The builder stopped because ${why}, and this build was not counted as an attempt. No agent builds this story until the lead decides, then tells the user what it chose and why:"$'\n\n'"- Lift the hold: run \`swarm.sh reset $1 <reason>\`, which puts its kind back and leaves \`attempts:\` as it is, so it is built again. Lifting a hold is not the story's one reset, and a later pause or error holds it again."$'\n'"- Or drop it: run \`swarm.sh drop $1 <reason>\`, which takes this story off the board, and commit the change in a board PR." "$3" >/dev/null
  set_fm "${BOARD}/stories/$1.md" held_for "$2"
  echo "held: $1 is kind: lead now (${2}), for the lead to lift the hold with reset, or drop"
}

# lead_block <slug> <text> <prs> [none] — no agent builds the story now: kind: lead, escalated_from: its
# kind (NO_KIND_LINE when it has no kind: line), still ready, and a marked block at its end with <text>
# and every PR in <prs> (failed_build's gh list), or [none] when <prs> has none (by default, that no
# PR was found). Prints how many PRs it named.
lead_block() {
  local f="${BOARD}/stories/$1.md" from urls k=0
  from="$(get_fm "${f}" kind)"
  urls="$(json "'\n'.join('- ' + p['url'] for p in d)" <<< "${3:-[]}")"
  [[ -z "${urls}" ]] || k="$(grep -c . <<< "${urls}")"
  set_fm "${f}" kind lead
  set_fm "${f}" escalated_from "${from:-${NO_KIND_LINE}}"
  [[ -z "$(tail -c1 "${f}")" ]] || echo >> "${f}"
  { echo "${ESCALATED_OPEN}"
    echo
    printf '%s\n' "$2"
    echo
    if [[ -n "${urls}" ]]; then printf "The attempts' PRs:\n\n%s\n" "${urls}"; else echo "${4:-No PR was found on story/$1.}"; fi
    echo "${ESCALATED_CLOSE}"; } >> "${f}"
  echo "${k}"
}

# failed_build <name> — succeed when closing <name> ends a failed build, and print gh's list of the
# PRs on story/<name>: <name> is a story on the board, still ready, of kind code, docs or chore,
# whose builder this project has open in herdr under that name (not closed by hand, not already
# retired), and none of its PRs merged or is open with auto-merge set: with merge = agent a close
# that comes before the board is pulled, or while the merge waits on auto-merge, finds the story still
# ready, so only the PR tells. One gh call answers both; when it fails, nothing is counted or cleared,
# and stderr says so.
failed_build() {
  local slug="$1" f="${BOARD}/stories/$1.md" src url prs merging
  [[ "${slug}" =~ ^[a-z0-9-]+$ && -f "${f}" && "$(fm "${f}" status)" == ready ]] || return 1
  case "$(fm "${f}" kind)" in ""|code|docs|chore) ;; *) return 1 ;; esac
  [[ -n "$(agent_field "$(agent_name "${slug}")" pane_id)" ]] || return 1
  src="$(repo_dir "$(fm "${f}" repo)")" \
    || { echo "swarm: ${slug}: ${src}, so this close counts no failed build and clears nothing" >&2; return 1; }
  if ! url="$(git -C "${src}" remote get-url origin)" \
     || ! prs="$(gh pr list -R "${url}" --head "story/${slug}" --state all --json number,state,url,autoMergeRequest)" \
     || ! merging="$(json "any(p['state'] == 'MERGED' or (p['state'] == 'OPEN' and p.get('autoMergeRequest')) for p in d)" <<< "${prs}")"; then
    echo "swarm: ${slug}: could not list the PRs on story/${slug}, so this close counts no failed build and clears nothing" >&2
    return 1
  fi
  [[ "${merging}" == False ]] || return 1
  printf '%s\n' "${prs}"
}

# clear_build <slug> <why> <prs> — clear a build away (a failed one, or one reconcile found merged or
# closed), so the next one starts fresh: in
# the story's repo, its worktree and story/<slug>; each of <prs> (failed_build's gh list) still open,
# closed unmerged with a comment saying <why> (the attempt, or the cause); then story/<slug> on origin. A step that fails
# is said on stderr, and the rest still run. A held child (held_by:) loses the hold and its prs: line,
# so it no longer counts as open in touches_rows.
clear_build() {
  local slug="$1" b="story/$1" src wt url
  src="$(repo_dir "$(fm "${BOARD}/stories/$1.md" repo)")" || { echo "swarm: ${slug}: ${src}; nothing cleared" >&2; return 0; }
  wt="$(worktree_for "${src}" "${slug}")"
  if [[ -e "${wt}" ]]; then git -C "${src}" worktree remove --force "${wt}" || echo "swarm: ${slug}: could not remove ${wt}" >&2; fi
  # A worktree whose directory went by hand is still registered, and would keep the branch.
  git -C "${src}" worktree prune || echo "swarm: ${slug}: could not prune ${src}'s worktrees" >&2
  if git -C "${src}" show-ref -q --verify "refs/heads/${b}"; then
    git -C "${src}" branch -q -D "${b}" || echo "swarm: ${slug}: could not delete ${b} in ${src}" >&2
  fi
  while IFS= read -r url; do
    [[ -n "${url}" ]] || continue
    gh pr close "${url}" --comment "swarm.sh close: $2, so this PR is closed unmerged and the next build starts fresh." >/dev/null \
      || echo "swarm: ${slug}: gh could not close ${url}" >&2
  done < <(json "'\n'.join(p['url'] for p in d if p['state'] == 'OPEN')" <<< "${3:-[]}")
  if git -C "${src}" ls-remote --exit-code origin "refs/heads/${b}" >/dev/null 2>&1; then
    git -C "${src}" push -q origin --delete "${b}" || echo "swarm: ${slug}: could not delete ${b} on origin" >&2
  fi
  # A held child's hold goes with its build, and so does the prs: line the hold kept.
  if [[ -n "$(get_fm "${BOARD}/stories/$1.md" held_by)" ]]; then
    state_set "${BOARD}/stories/$1.md" held_by "" prs ""
  fi
}

# close_panes <name> — close <name>'s pane, or its tab when that was the tab's last pane. A
# conductor's name closes its epic's tabs, with any story panes left in them.
close_panes() {
  local state pane epic
  for state in "${STATE_DIR}"/*; do
    [[ -f "${state}" ]] || continue
    pane="$(awk -v n="$1" 'NF > 1 && $2 == n { print $1; exit }' "${state}")"
    [[ -n "${pane}" ]] || continue
    if [[ $(wc -l < "${state}") -le 1 ]]; then close_tabs "$(basename "${state}")"; return; fi
    herdr pane close "${pane}" >/dev/null
    awk -v p="${pane}" '$1 != p' "${state}" > "${state}.tmp" && mv "${state}.tmp" "${state}"
    echo "closed pane $1"; return
  done
  if [[ "$(agent_name "$1")" == conduct-* ]]; then
    epic="$(conduct_epic "$1")"
    close_tabs "${epic}"
  fi
  close_tabs "$1"
}

# tidy [--yes] — the panes this script opened that hold nothing to read any more: no agent in them
# (a start that failed) or a retired agent (<name>-done, left open by retire_agent). Lists them; with
# --yes, closes them and drops them from the tab records. Working, waiting and idle agents are never
# touched, nor the pane this runs in. Run it when nothing is starting: a pane whose agent is still
# starting has no agent yet, so it looks empty.
tidy_panes() {
  local yes="${1:-}" agents panes closable pane name reason file n=0
  [[ "${yes}" != --yes || -n "${HERDR_PANE_ID:-}" ]] || die "tidy --yes: HERDR_PANE_ID is not set, so this pane could not be kept open"
  agents=$(herdr agent list 2>/dev/null) || die "tidy: herdr gave no agent list"
  panes=$(herdr pane list 2>/dev/null) || die "tidy: herdr gave no pane list"
  closable=$(SWARM_OWN="$(own_panes)" python3 "${SWARM_HOME}/bin/lib/tidy_panes.py" "${STATE_DIR}" "${agents}" "${panes}" "${HERDR_PANE_ID:-}") || die "tidy: could not read herdr's lists"
  if [[ -z "${closable}" ]]; then echo "nothing to tidy"; return 0; fi
  while IFS=$'\t' read -r pane name reason file; do echo "  ${name}  ${reason}  [${file} ${pane}]"; done <<< "${closable}"
  if [[ "${yes}" != --yes ]]; then echo "(swarm.sh tidy --yes closes them)"; return 0; fi
  while IFS=$'\t' read -r pane name reason file; do
    herdr pane close "${pane}" >/dev/null 2>&1 || { echo "could not close ${pane} (${name})"; continue; }
    { awk -v p="${pane}" '$1 != p' "${STATE_DIR}/${file}" > "${STATE_DIR}/${file}.tmp" && mv "${STATE_DIR}/${file}.tmp" "${STATE_DIR}/${file}"; } \
      || die "tidy: closed ${pane} but could not update ${STATE_DIR}/${file}"
    [[ -s "${STATE_DIR}/${file}" ]] || rm -f "${STATE_DIR}/${file}"
    n=$((n + 1))
  done <<< "${closable}"
  echo "closed ${n}"
}

# init_check — refuse init anywhere but the project's git root. main runs it before logging, since a
# project found from a subdirectory is that subdirectory, and a refused run must write nothing there.
init_check() {
  local top
  top="$(git rev-parse --show-toplevel 2>/dev/null)" || die "init: not in a git repo; run it from your project's root"
  [[ "$(pwd -P)" == "${top}" ]] || die "init: run it from the root of the git repo, ${top}"
  [[ "${PROJECT_DIR}" == "${top}" ]] || die "init: the project is ${PROJECT_DIR}; run init there"
}

# init_project — set the project up from the installed plugin, from its git root: the board templates
# (never over a file that exists), .claude/swarm/, and the .gitignore lines. A second run changes nothing.
init_project() {
  local rel f line n=0
  mkdir -p "${BOARD}" && BOARD="$(cd "${BOARD}" && pwd -P)"
  # The board's path from the root with a trailing /, or empty when the board is the root.
  rel=""; [[ "${BOARD}" == "${PROJECT_DIR}" ]] || rel="${BOARD#"${PROJECT_DIR}/"}/"
  while IFS= read -r f; do
    if [[ -e "${BOARD}/${f}" ]]; then echo "left   ${rel}${f} (it exists)"; continue; fi
    mkdir -p "$(dirname "${BOARD}/${f}")" && cp "${SWARM_HOME}/templates/docs/${f}" "${BOARD}/${f}"
    echo "copied ${rel}${f}"; n=$((n + 1))
  done < <(cd "${SWARM_HOME}/templates/docs" && find . -type f | sed 's|^\./||' | sort)
  [[ ${n} -gt 0 ]] || echo "copied nothing: the board has every template file"
  [[ -d .claude/swarm ]] || { mkdir -p .claude/swarm; echo "created .claude/swarm/"; }
  n=0
  for line in .swarm/ "${rel}.obsidian/*" "!${rel}.obsidian/app.json"; do
    # A board outside the repo is not the repo's to ignore.
    [[ "${line}" == .swarm/ || "${BOARD}/" == "${PROJECT_DIR}/"* ]] || continue
    # CRs stripped, so a CRLF file's lines still match.
    tr -d '\r' 2>/dev/null < .gitignore | grep -qxF -- "${line}" && continue
    [[ ! -s .gitignore || -z "$(tail -c1 .gitignore)" ]] || echo >> .gitignore
    echo "${line}" >> .gitignore; echo "added ${line} to .gitignore"; n=$((n + 1))
  done
  [[ ${n} -gt 0 ]] || echo ".gitignore already has every line"
  echo "One step left: run claude once in ${PROJECT_DIR} and accept the folder trust prompt. Agents won't start until it is trusted."
}

# close_tabs <label> — close every tab this script opened under <label>, and its state, archiving the
# session of each agent in it first. A tab may be in another workspace (a conductor's is its HLD's):
# its first pane id, "<workspace>:<pane>", says which.
close_tabs() {
  local label state tab_label id ws n
  label="$(tab_label "$1")"
  for state in "${STATE_DIR}/${label}" "${STATE_DIR}/${label}"-*; do
    [[ -f "${state}" ]] || continue
    while read -r _ n; do [[ -z "${n}" ]] || archive_session "${n}"; done < "${state}"
    tab_label="$(basename "${state}")"
    ws="$(head -1 "${state}")"; ws="${ws%%:*}"; ws="${ws:-${HERDR_WORKSPACE_ID}}"
    id=$(herdr tab list --workspace "${ws}" | python3 -c "
import json,sys
for t in json.load(sys.stdin)['result']['tabs']:
    if t.get('label') == sys.argv[1]: print(t['tab_id'])" "${tab_label}")
    # Two tabs can carry one label (a run that reopened it); close each, one id per call.
    while read -r t; do [[ -z "${t}" ]] || herdr tab close "${t}" >/dev/null; done <<< "${id}"
    rm -f "${state}"
    echo "closed ${tab_label}"
  done
}

LEAD_POLL="${SWARM_LEAD_POLL:-30}"    # seconds between wait --lead's reads of the board, at least 1
# wait --lead's own files, kept out of STATE_DIR, whose files close reads as tab records.
LEAD_DIR="${PROJECT_DIR}/.swarm/lead"
LEAD_SEEN="${LEAD_DIR}/seen"          # the lead's queue at wait --lead's last read, kept across runs
LEAD_GREEN="${LEAD_DIR}/green"        # "<PR URL> <sha>" per head ci_gate passed, so it runs once per head
LEAD_PID="${LEAD_DIR}/pid"            # the running wait --lead, which a new one takes over from

# heads_green <pr-url>... — 0 when there is at least one PR and every one's head is green, 1 when one is
# not or a URL is not a PR, 2 when none is red but gh or ci_gate could not read one. ci_gate head is
# skipped for a head LEAD_GREEN holds, setting LEAD_CACHED, unless LEAD_FRESH is set; each green head
# goes to LEAD_GREEN.new. A red or pending head is read again each time: a re-run can turn it green
# with no new SHA.
heads_green() {
  local url repo head rc=0 g
  LEAD_CACHED=""
  [[ $# -gt 0 ]] || return 1
  for url in "$@"; do
    [[ "${url}" =~ ^https://github\.com/([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)/pull/([0-9]+)$ ]] || return 1
    repo="${BASH_REMATCH[1]}"
    head="$(gh pr view "${BASH_REMATCH[2]}" --repo "${repo}" --json headRefOid --jq .headRefOid </dev/null 2>/dev/null)" || head=""
    [[ "${head}" =~ ^[0-9a-f]{40}$ ]] || { rc=2; continue; }
    if [[ -z "${LEAD_FRESH:-}" ]] && grep -qxF "${url} ${head}" "${LEAD_GREEN}" 2>/dev/null; then
      LEAD_CACHED=1
    else
      g=0; ci_gate head "${repo}" "${head}" >/dev/null 2>&1 || g=$?
      [[ ${g} -eq 0 ]] || { [[ ${g} -eq 3 ]] || return 1; rc=2; continue; }
    fi
    echo "${url} ${head}" >> "${LEAD_GREEN}.new"
  done
  return "${rc}"
}

# lead_queue — one line per item waiting on the lead, as wait --lead prints it: `held: <slug> (<cause>)`
# for a story with held_for:, `escalated: <slug>` for any other escalated one, and with merge = human (or
# for a costs: money story, under merge = agent too) `merge: <slug> <PR URL>...` for a story or epic in
# review (waiting_on_user) whose every PR head is green.
# A review item whose heads could not be read stays as LEAD_SEEN has it, so a gh error wakes no one.
lead_queue() {
  local f held line slug prs rc urls="" tag u new seen=" "
  while IFS= read -r f; do
    held="$(get_fm "${f}" held_for)"
    if [[ -n "${held}" ]]; then echo "held: $(basename "${f}" .md) (${held})"
    elif is_escalated "${f}"; then echo "escalated: $(basename "${f}" .md)"; fi
  done < <(board stories)
  : > "${LEAD_GREEN}.new"
  # waiting_on_user's last line has no newline.
  while IFS= read -r line || [[ -n "${line}" ]]; do
    # With merge = agent only a costs: money item waits on the user: merge holds it for them.
    # shellcheck disable=SC2154 # assigned in another file
    [[ "${CFG_merge}" == human || "${line}" == "  awaiting your merge (costs money): "* ]] || continue
    tag=""; [[ "${line}" != "  awaiting your merge (costs money): "* ]] || tag=1
    line="${line/#  awaiting your merge (costs money): /  awaiting your merge: }"
    [[ "${line}" == "  awaiting your merge: "* ]] || continue
    line="${line#  awaiting your merge: }"; line="${line#epic }"
    slug="${line%% *}"; prs="${line#"${slug}"}"; line="merge: ${slug}${prs}"; rc=0; urls+="${prs}"
    if [[ -n "${tag}" ]]; then
      # A held PR is reported once, under the first item listing it (a story and its epic both may).
      new=""; for u in ${prs}; do [[ "${seen}" == *" ${u} "* ]] || new=1; done
      [[ -n "${new}" ]] || continue
    fi
    # shellcheck disable=SC2086 # prs: is a space-separated list of URLs
    heads_green ${prs} || rc=$?
    if [[ ${rc} -eq 0 && -n "${LEAD_CACHED}" ]] && ! grep -qxF "${line}" "${LEAD_SEEN}" 2>/dev/null; then
      # About to wake the lead: a cached head can have gone red on a re-run since, so read each one again.
      # shellcheck disable=SC2086 # as above
      LEAD_FRESH=1 heads_green ${prs} || rc=$?
    fi
    if [[ ${rc} -eq 0 ]] || { [[ ${rc} -eq 2 ]] && grep -qxF "${line}" "${LEAD_SEEN}" 2>/dev/null; }; then
      # Seen once reported: a later item listing the PR still wakes the lead when this one was not green.
      echo "${line}"; [[ -z "${tag}" ]] || seen+="${prs# } "
    fi
  done < <(waiting_on_user)
  # A green head this read did not reach (gh failed, or an earlier PR of its item was red) stays cached
  # while its PR is still in review.
  touch "${LEAD_GREEN}"
  awk -v keep="${urls} " 'FILENAME == ARGV[1] { if (!($1 in got)) print; got[$1] = 1; next }
    !($1 in got) && index(keep, " " $1 " ") { print }' "${LEAD_GREEN}.new" "${LEAD_GREEN}" > "${LEAD_GREEN}.tmp"
  mv "${LEAD_GREEN}.tmp" "${LEAD_GREEN}"; rm -f "${LEAD_GREEN}.new"
}

# lead_wake [quiet] — read the lead's queue once and save it as LEAD_SEEN. Print each item that was not in
# LEAD_SEEN before and log `lead-woken <slug>` for it; true when there was one. quiet only saves.
lead_wake() {
  local now line new=""
  now="$(lead_queue)"
  while IFS= read -r line; do
    [[ -z "${line}" ]] || grep -qxF "${line}" "${LEAD_SEEN}" 2>/dev/null || new+="${line}"$'\n'
  done <<< "${now}"
  printf '%s\n' "${now}" > "${LEAD_SEEN}.tmp" && mv "${LEAD_SEEN}.tmp" "${LEAD_SEEN}"
  [[ -z "${1:-}" && -n "${new}" ]] || return 1
  while IFS= read -r line; do
    echo "${line}"; line="${line#*: }"; record_event lead-woken "${line%% *}"
  done <<< "${new%$'\n'}"
}

# lead_holder — the pid in LEAD_PID when it is a live wait --lead, else nothing.
lead_holder() {
  local pid
  pid="$(cat "${LEAD_PID}" 2>/dev/null)" || return 0
  if [[ "${pid}" =~ ^[0-9]+$ ]] && ps -p "${pid}" -o command= 2>/dev/null | grep -q -- 'swarm.sh wait --lead'; then echo "${pid}"; fi
}

# lead_lock — make this run the one wait --lead: stop any live holder of LEAD_PID (an earlier run, whose
# output may go unread), then link a file holding $$ into place, so LEAD_PID is never seen half written.
# The pid file goes on exit, only while it still names this run.
lead_lock() {
  local pid tmp i
  mkdir -p "${LEAD_DIR}" || die "wait --lead: cannot make ${LEAD_DIR}"
  tmp="${LEAD_PID}.$$"
  echo "$$" > "${tmp}" || die "wait --lead: cannot write ${tmp}"
  until ln "${tmp}" "${LEAD_PID}" 2>/dev/null; do
    [[ -e "${LEAD_PID}" ]] || { rm -f "${tmp}"; die "wait --lead: cannot write ${LEAD_PID}"; }
    pid="$(lead_holder)"
    if [[ -n "${pid}" ]]; then
      echo "swarm: wait --lead: stopping the earlier run (pid ${pid}); this one watches now" >&2
      kill "${pid}" 2>/dev/null || true
      for ((i = 0; i < 50; i++)); do [[ -n "$(lead_holder)" ]] || break; sleep 0.1; done
      [[ -z "$(lead_holder)" ]] || { rm -f "${tmp}"; die "wait --lead: the earlier run (pid ${pid}) did not stop"; }
    fi
    # Gone, or stale: free the name, unless another new run took it in the meantime.
    [[ -n "$(lead_holder)" ]] || rm -f "${LEAD_PID}"
  done
  rm -f "${tmp}"
  trap '[[ "$(cat "${LEAD_PID}" 2>/dev/null)" != "$$" ]] || rm -f "${LEAD_PID}"' EXIT
}

# wait_lead [timeout-ms] — wait --lead: one run at a time, the newest (lead_lock). It reads the lead's
# queue every LEAD_POLL seconds and returns 0 as soon as it holds an item that LEAD_SEEN does not
# (lead_wake). The first read of a run reports what landed since the last run; with no LEAD_SEEN yet
# it only notes the queue. At the timeout (default an hour) it fails with nothing printed. It nudges no
# one and edits no board file.
wait_lead() {
  local timeout="${1:-3600000}" start left
  [[ "${timeout}" =~ ^[0-9]+$ ]] || die "wait --lead: the timeout is in milliseconds, not '${timeout}'"
  timeout=$((10#${timeout}))   # 090000 is not octal
  [[ "${LEAD_POLL}" =~ ^[1-9][0-9]*$ ]] || die "SWARM_LEAD_POLL is whole seconds, at least 1, not '${LEAD_POLL}'"
  lead_lock
  start=${SECONDS}
  if [[ -f "${LEAD_SEEN}" ]]; then ! lead_wake || return 0; else lead_wake quiet || true; fi
  while (( (SECONDS - start) * 1000 < timeout )); do
    left=$(( (timeout + 999) / 1000 - (SECONDS - start) ))
    sleep $(( left < LEAD_POLL ? left : LEAD_POLL ))
    ! lead_wake || return 0
  done
  return 1
}

# wait_command [--stall | --until-report] <name> [timeout-ms] | --lead [timeout-ms] — the wait command:
# a conductor's wait, with no timeout under --until-report, any other agent's, or the lead's (wait_lead).
wait_command() {
  local stall until n
  [[ "${1:-}" != --lead ]] || { wait_lead "${2:-}"; return; }
  require_herdr; stall=""; until=""
  case "${1:-}" in --stall) stall=--stall; shift ;; --until-report) until=1; shift ;; esac
  n="$(agent_name "${1:?name}")"
  if [[ -n "${until}" ]]; then
    [[ "${n}" == conduct-* && ! "${n}" =~ -done[0-9]*$ ]] || die "wait --until-report waits only on a conductor (conduct-<epic>), not ${n}"
    wait_conductor "${n}" 0
  elif [[ "${n}" == conduct-* && ! "${n}" =~ -done[0-9]*$ ]]; then wait_conductor "${n}" "${2:-3600000}"
  # A review agent by its recorded role (a builder's slug may start review-), and its findings file by
  # the full slug given here: the agent name may be cut at 32 characters.
  # An idle one whose file never came fails, so a caller never takes a timeout for a finished review.
  elif [[ "$1" =~ ^review-([a-z0-9-]+)$ && "$(awk -F'\t' -v n="${n}" '$3 == n { r = $2 } END { print r }' "${AGENTS_LOG}" 2>/dev/null)" == review ]]; then
    local f="${PROJECT_DIR}/.swarm/reviews/${BASH_REMATCH[1]}.md" out rc=0
    out="$(wait_conductor "${n}" "${2:-3600000}" "${f}")" || rc=$?
    echo "${out}"
    [[ ${rc} -ne 0 || "${out}" != idle || -f "${f}" ]] || { echo "swarm: ${n}: idle with no findings file (${f}) at the timeout" >&2; return 1; }
    return "${rc}"
  else wait_agent "${n}" "${2:-3600000}" "${stall}"; fi
}
