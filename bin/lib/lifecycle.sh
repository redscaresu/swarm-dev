# shellcheck shell=bash

# config_trailers — commit_trailers from the config, one trailer per line.
config_trailers() {
  # shellcheck disable=SC2154 # assigned in another file
  [[ -z "${CFG_commit_trailers}" ]] || tr ';' '\n' <<< "${CFG_commit_trailers}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

# brief_trailers — the commit trailers: commit_trailers, then those the project's brief names, wherever
# a line has one (quoted or backticked in a sentence too): a <Word>-by: token, a name with a letter in
# it and no colon or quote (so a match starts at the last token before the email, never in the prose
# ahead of it), and <an email>. A placeholder such as Co-Authored-By: <who> <email> has no name, so it
# is not one. One per line, in that order, each once.
brief_trailers() {
  {
    config_trailers
    # shellcheck disable=SC2016 # the backticks are literal: a name holds none
    [[ ! -f "${PROJECT_BRIEF}" ]] || grep -oE '[A-Z][A-Za-z]*(-[A-Za-z]+)*-[Bb]y: [^<>"`:]*[A-Za-z][^<>"`:]* <[^<>[:space:]]+@[^<>[:space:]]+>' "${PROJECT_BRIEF}" || true
  } | awk '!seen[$0]++'
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

# keys_only <path> — true when the edit to the tracked file <path> changes only SET_FM_KEYS lines of
# its front matter (an older swarm.sh wrote its keys there).
keys_only() {
  # shellcheck disable=SC2016 # $0 is awk's
  local rest='/^---$/ { n++ } n == 1 && match($0, /^[a-z_]+:/) && index(keys, " " substr($0, 1, RLENGTH - 1) " ") { next } { print }'
  cmp -s <(git -C "${PROJECT_DIR}" show "HEAD:$1" | awk -v keys=" ${SET_FM_KEYS} " "${rest}") \
    <(awk -v keys=" ${SET_FM_KEYS} " "${rest}" "${PROJECT_DIR}/$1")
}

# key_moves <path> [given] — each SET_FM_KEYS key of the story or epic <path> whose value, read
# through its state (so a value swarm.sh wrote after the edit wins), differs from HEAD's, as
# <key><tab><value> lines: what keys_to_state moves. When the incoming commits change the file's
# status or prs, those two are left out: an older swarm.sh's status write gives way to theirs (a merged
# PR's status: done), so checking the file out drops it. With given, it prints instead each of those
# two whose uncommitted value in the file the checkout drops for a different incoming one, as
# <key><tab><value><tab><incoming value>, an empty one as (none); none when the incoming status is
# done over a review, building or held status, the finish an older swarm.sh's status write waited on.
key_moves() {
  local f="${PROJECT_DIR}/$1" head up="" k v u skip=""
  head="$(git -C "${PROJECT_DIR}" show "HEAD:$1")"
  if up="$(git -C "${PROJECT_DIR}" show "@{upstream}:$1" 2>/dev/null)"; then
    for k in status prs; do
      [[ "$(get_fm - "${k}" <<< "${up}")" == "$(get_fm - "${k}" <<< "${head}")" ]] || skip=" status prs "
    done
  fi
  if [[ -n "${2:-}" ]]; then
    [[ "$(get_fm - status <<< "${up}")" != "done" || " review building held " != *" $(get_fm - status < "${f}") "* ]] || return 0
    for k in ${skip}; do
      v="$(get_fm - "${k}" < "${f}")"; u="$(get_fm - "${k}" <<< "${up}")"
      [[ "${v}" == "$(get_fm - "${k}" <<< "${head}")" || "${v}" == "${u}" ]] \
        || printf '%s\t%s\t%s\n' "${k}" "${v:-(none)}" "${u:-(none)}"
    done
    return 0
  fi
  for k in ${SET_FM_KEYS}; do
    [[ "${skip}" != *" ${k} "* ]] || continue
    v="$(get_fm "${f}" "${k}")"
    [[ "${v}" == "$(get_fm - "${k}" <<< "${head}")" ]] || printf '%s\t%s\n' "${k}" "${v}"
  done
}

# keys_meet_base <path> — true when the incoming commits keep the story or epic <path> and change its
# depends_on, or set a key key_moves would move (never status or prs, which give way) to another value
# than the one moved: moved to its state, the old values would read over the new ones (a status
# flipped to ready over a new dependency). The same value on both sides goes through.
keys_meet_base() {
  local k v u head up
  up="$(git -C "${PROJECT_DIR}" show "@{upstream}:$1" 2>/dev/null)" || return 1
  head="$(git -C "${PROJECT_DIR}" show "HEAD:$1")"
  [[ "$(get_fm - depends_on <<< "${up}")" == "$(get_fm - depends_on <<< "${head}")" ]] || return 0
  while IFS=$'\t' read -r k v; do
    u="$(get_fm - "${k}" <<< "${up}")"
    [[ "${u}" == "$(get_fm - "${k}" <<< "${head}")" || "${u}" == "${v}" ]] || return 0
  done < <(key_moves "$1")
  return 1
}

# keys_to_state <path> — for the story or epic <path>, whose unstaged edit is keys_only: move each
# key_moves value into its state, with HEAD's value as its base, and check the file out, so fm reads it
# as before. Fails when a step does; the caller puts the file and its state back.
keys_to_state() {
  local f="${PROJECT_DIR}/$1" k v pairs=()
  while IFS=$'\t' read -r k v; do pairs+=("${k}" "${v}"); done < <(key_moves "$1")
  git -C "${PROJECT_DIR}" checkout -q -- "$1" || return 1
  [[ ${#pairs[@]} -eq 0 ]] || (state_set "${f}" "${pairs[@]}") || return 1
  if [[ ${#pairs[@]} -gt 0 ]]; then
    echo "reconcile: $1 changed only swarm.sh's own keys; they are in its board state now, and the file is checked out"
  else
    echo "reconcile: $1 changed only swarm.sh's own keys, which the pull replaces; the file is checked out"
  fi
}

# PULL_STOP: the outcome of the last pull-failed incident, kept until a pull goes through, so a stop
# that lasts across reconciles is logged once.
PULL_STOP="${PROJECT_DIR}/.swarm/pull-failed"

# blob_of <file> — the id of <file>'s bytes, written to git's object store, or - when there is no file.
blob_of() { if [[ -f "$1" ]]; then git -C "${PROJECT_DIR}" hash-object -w --no-filters -- "$1"; else echo -; fi; }

# put_back <file> <blob>... — write each <file> back from its <blob> in git's object store, or remove it
# for -: what pull_board_repo changed before a pull that failed.
put_back() {
  while [[ $# -gt 1 ]]; do
    if [[ "$2" == - ]]; then rm -f "$1"; else git -C "${PROJECT_DIR}" cat-file blob "$2" > "$1"; fi
    shift 2
  done
}

# pull_board_repo — pull the main checkout fast-forward, touching no edit. Once it has fetched, it
# succeeds, touching nothing, when there is nothing to pull (HEAD has every upstream commit). It
# stops, touching nothing, when it cannot fetch, the pull cannot fast-forward (local commits), or a
# tracked file the incoming commits change is changed here too, staged or not: that stop names those
# files and logs an incident, pull-failed: <files>, once while the same stop lasts (PULL_STOP). A
# story or epic among them whose edit is only to swarm.sh's own keys does not stop it: before the
# merge it moves those keys into board state (keys_to_state), unless the incoming commits change its
# depends_on or set those keys to other values (keys_meet_base), which stops it as a changed file
# does. Once the pull is in, it names each status or prs of such a file that gave way to a different
# incoming value, on stdout and in an incident, key-dropped: <file> <key>: <ours> -> <theirs>. It also
# removes each untracked board file whose bytes are already the incoming one's, which the pull brings
# back. If the merge then fails (git refuses it: another untracked file it would overwrite), it puts
# each of those changes back (put_back), so a failed pull changes nothing. A changed file the incoming
# commits leave alone stays as it is through the pull. On failure PULL_WHY says why and what to do
# before reconcile runs again.
PULL_WHY=""
pull_board_repo() {
  local incoming line p b o k v u rel stop="" meet="" given="" board other out keys=() undo=()
  git -C "${PROJECT_DIR}" fetch -q || { PULL_WHY="cannot fetch; pull it by hand"; return 1; }
  ! git -C "${PROJECT_DIR}" merge-base --is-ancestor '@{upstream}' HEAD || return 0
  if ! git -C "${PROJECT_DIR}" merge-base --is-ancestor HEAD '@{upstream}'; then
    PULL_WHY="it has commits the base does not ($(git -C "${PROJECT_DIR}" log --format=%h '@{upstream}..HEAD' | paste -sd' ' -)), so it cannot fast-forward; pull it by hand"
    return 1
  fi
  incoming="$(git -C "${PROJECT_DIR}" diff --name-only --no-renames HEAD '@{upstream}')"
  while IFS= read -r line; do
    p="${line:3}"
    grep -qxF -- "${p}" <<< "${incoming}" || continue   # the pull leaves it alone
    if [[ "${line:0:2}" == " M" && ( "${PROJECT_DIR}/${p}" == "${BOARD}/stories/"* || "${PROJECT_DIR}/${p}" == "${BOARD}/epics/"* ) ]] \
      && keys_only "${p}"; then
      if keys_meet_base "${p}"; then
        meet+="${meet:+ }${p}"
      else
        keys+=("${p}"); given+="$(key_moves "${p}" given | sed "s|^|${p}"$'\t'"|")"$'\n'
      fi
    else
      stop+="${stop:+$'\n'}${p}"
    fi
  done < <(git -C "${PROJECT_DIR}" status --porcelain --untracked-files=no)
  if [[ -n "${stop}${meet}" ]]; then
    o="pull-failed: $(paste -sd' ' - <<< "${stop}")${stop:+${meet:+ }}${meet}"
    if [[ "$(cat "${PULL_STOP}" 2>/dev/null)" != "${o}" ]]; then
      record_event incident - "${o}"
      { printf '%s\n' "${o}" > "${PULL_STOP}"; } 2>/dev/null || true
    fi
    # The board's path from the root with a trailing /, or empty when the board is the root.
    rel=""; [[ "${BOARD}" == "${PROJECT_DIR}" ]] || rel="${BOARD#"${PROJECT_DIR}"/}/"
    board="$(awk -v b="${rel}" 'substr($0, 1, length(b)) == b' <<< "${stop}" | paste -sd' ' -)"
    other="$(awk -v b="${rel}" 'substr($0, 1, length(b)) != b' <<< "${stop}" | paste -sd' ' -)"
    PULL_WHY=""
    [[ -z "${board}" ]] || PULL_WHY="board files are changed here: ${board}; land each edit through swarm.sh board-pr, or check the file out to drop it"
    [[ -z "${other}" ]] || PULL_WHY+="${PULL_WHY:+; }files outside the board are changed here: ${other}; commit or move each change"
    [[ -z "${meet}" ]] || PULL_WHY+="${PULL_WHY:+; }swarm.sh's keys are changed here in ${meet}, and the incoming commits change its depends_on or the same keys; check each file out, and once the pull is in, set its keys again through swarm.sh"
    return 1
  fi
  # From here undo lists each file changed and the blob it was (- for none), for put_back.
  for p in "${keys[@]+"${keys[@]}"}"; do
    state_name "${PROJECT_DIR}/${p}"
    if ! { b="$(blob_of "${PROJECT_DIR}/${p}")" && undo+=("${PROJECT_DIR}/${p}" "${b}") \
      && b="$(blob_of "${STATE_PATH}")" && undo+=("${STATE_PATH}" "${b}") && keys_to_state "${p}"; }; then
      put_back "${undo[@]+"${undo[@]}"}"
      PULL_WHY="cannot move swarm.sh's keys in ${p} into its board state, so every edit stays; fix what the error above names"
      return 1
    fi
  done
  while IFS= read -r p; do
    b="$(git -C "${PROJECT_DIR}" rev-parse -q --verify "@{upstream}:${p}")" || continue
    git -C "${PROJECT_DIR}" cat-file blob "${b}" | cmp -s - "${PROJECT_DIR}/${p}" || continue
    undo+=("${PROJECT_DIR}/${p}" "${b}"); rm "${PROJECT_DIR}/${p}"
  done < <(git -C "${PROJECT_DIR}" ls-files --others --exclude-standard -- "${BOARD}")
  # Fast-forward to the upstream fetched above, which every check here read: a pull would fetch again.
  if ! out="$(git -C "${PROJECT_DIR}" merge -q --ff-only '@{upstream}' 2>&1)"; then
    put_back "${undo[@]+"${undo[@]}"}"
    # shellcheck disable=SC2034 # PULL_WHY is read in another file
    PULL_WHY="git refused the pull ($(tr '\t' ' ' <<< "${out}" | paste -sd' ' -)); fix what it names"
    return 1
  fi
  rm -f "${PULL_STOP}"
  while IFS=$'\t' read -r p k v u; do
    [[ -n "${p}" ]] || continue
    echo "reconcile: ${p}: the pull's ${k}: ${u} replaced your uncommitted ${k}: ${v}; set it again if you meant it"
    record_event incident - "key-dropped: ${p} ${k}: ${v} -> ${u}"
  done <<< "${given}"
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

# shut_agent <name> — archive <name>'s session log, close what was opened for it (close_panes) and
# remove its ZDOTDIR (clean_env's). close_agent and step_up both end a builder this way.
shut_agent() {
  archive_session "$1"
  # One builder, two names: herdr's (agent_name, cut at 32 characters), which failed_build and
  # retire_agent map to, and the pane record's full slug (start_agent's pane name), which close_panes
  # matches. Passing close_panes the cut name would leave a long slug's pane open.
  close_panes "$1"
  rm -rf "${PROJECT_DIR}/.swarm/zdotdir/$(agent_name "$1")"
}

# close_agent <name> [cause] — close what was opened for <name> (shut_agent).
# An unknown cause is refused before anything closes, and so, with goal on, is a missing one while
# <name>'s story is still ready (its builder is giving up), and so is impossible for a story that
# cannot be handed on (impossible_refused). A close that ends a failed build (failed_build, decided
# before anything closes, while the builder can still be found) then clears the attempt away
# (clear_build), so the next build starts fresh. With no cause, met, stalled or bound it first raises
# the story's attempts: by one, and when that build was escalate, the story becomes the lead's
# (escalate_story). impossible, paused and cleared-on-error count nothing. impossible makes the story
# the lead's (impossible_story) whether or not there was a build to clear; paused and cleared-on-error
# hold it for the lead (held_story) when the close ends a build. A close that ends a build with no
# open or merged PR on story/<name> logs an idle-no-pr incident, the one place it is logged, unless
# the builder did not stop of itself (stalled, paused or cleared-on-error) or handed it on (impossible);
# with escalate_ladder set, that close then steps the build up (ladder_step no-pr) instead, if it can.
close_agent() {
  local cause="${2:-}" f="${BOARD}/stories/$1.md" prs counted=0 n why rc
  # The message never repeats the word: main logs a die's first line.
  [[ -z "${cause}" ]] || is_close_cause "${cause}" \
    || die "close: the cause must be ${CLOSE_CAUSES} (swarm.sh close <name> [cause])"
  # shellcheck disable=SC2154 # assigned in another file
  [[ -n "${cause}" || "${CFG_goal}" == off || ! -f "${f}" || "$(fm "${f}" status)" != ready ]] \
    || die "close: with goal on, $1's story is still ready, so say why its builder stopped: swarm.sh close $1 <cause>, the cause one of ${CLOSE_CAUSES}"
  if [[ "${cause}" == impossible ]] && why="$(impossible_refused "$1")"; then
    die "close: $1 cannot be closed impossible, because ${why}; nothing was closed"
  fi
  if prs="$(failed_build "$1")"; then
    counted=1
    if [[ ! "${cause}" =~ ^(stalled|paused|cleared-on-error|impossible)$ && "$(json "any(p['state'] != 'CLOSED' for p in d)" <<< "${prs}")" != True ]]; then
      record_event incident "$1" "idle-no-pr: closed (${cause:-no cause}) with no open or merged PR on story/$1"
      # With the ladder on, the next model takes the build over instead: no attempt, nothing cleared.
      # A step-up that failed partway closed the builder already: nothing more is done here.
      # main logs no close then (stepped_up_since): the escalate line ends the stepped-up build.
      rc=0; ladder_step "$1" no-pr || rc=$?
      [[ ${rc} != 0 ]] || return 0
      [[ ${rc} != "${STEP_UP_PARTWAY}" ]] || die "close: $1's step-up failed partway, after its builder was closed, so nothing more was closed or counted: list it for the lead"
      [[ ${rc} != "${STEP_UP_BUSY}" ]] || die "close: another step-up of $1 is running and may be starting its next builder, so nothing was closed or counted: wait on $1, then close it if it still needs closing"
    fi
  fi
  shut_agent "$1"
  if [[ "${cause}" == impossible ]]; then
    # The build is cleared even when failed_build declined (a builder gone, gh down),
    # so the story builds again after reset; only PRs failed_build listed are closed.
    # Handed on first, for the same reason as a hold below.
    impossible_story "$1" "${prs}" "${counted}"
    clear_build "$1" "the build of $1 stopped (impossible), which is not an attempt" "${prs:-[]}"
    return 0
  fi
  case "${cause}" in paused|cleared-on-error)
    # Held, its build cleared so it builds again once the hold is lifted, when the close ends a build
    # (counted). A story whose PR merged or is merging, or whose PRs gh could not list, is left as it was, and for a story
    # an agent builds the close says so (not held:).
    # The hold first: a block that cannot be written dies with the build still there, so the story is
    # not left ready with its build cleared for the next conductor to start again.
    if [[ ${counted} == 1 ]]; then
      held_story "$1" "${cause}" "${prs:-[]}"
      clear_build "$1" "the build of $1 stopped (${cause}), which is not an attempt" "${prs:-[]}"
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

# STEP_UP_TRIGGERS: why a build is handed up the ladder: a third round of review findings, CI red
# twice, a stalled builder, or a builder that stopped with no PR. step_trigger says each in prose.
# STEP_UP_FINDINGS: the findings tell since a build started that steps it up (tell_agent);
# STEP_UP_RED_HEADS: the red heads on its PR that do (ci_red_step). The trigger names carry them.
STEP_UP_FINDINGS=3
STEP_UP_RED_HEADS=2
# STEP_UP_PARTWAY: step-up's exit status when it failed after closing the builder, and only then.
# STEP_UP_BUSY: ladder_step's when another step-up of the story holds its lock: it may be starting
# the next builder, so the caller touches nothing.
STEP_UP_PARTWAY=4
STEP_UP_BUSY=5
STEP_UP_TRIGGERS="findings-${STEP_UP_FINDINGS} ci-red-${STEP_UP_RED_HEADS} stalled no-pr"
step_trigger() {
  case "$1" in
    "findings-${STEP_UP_FINDINGS}") echo "its builder was sent review findings ${STEP_UP_FINDINGS} times" ;;
    "ci-red-${STEP_UP_RED_HEADS}") echo "its PR's CI went red on ${STEP_UP_RED_HEADS} heads" ;;
    stalled) echo "its builder stalled" ;;
    no-pr) echo "its builder stopped with no PR" ;;
  esac
}
# HANDOVER_DIFF_LINES: how much of the diff a handover brief pastes; the builder reads the rest itself.
HANDOVER_DIFF_LINES=400

# step_up <slug> <trigger> [findings] — hand a story's build to escalate_ladder's next model: close its builder
# (its session archived, no attempt counted, its worktree, branch and PR kept) and start the next rung
# (start_rung) in the same worktree with handover_brief. The build is the newest agents.tsv line for
# its agent: a building role on one of LADDER_MODELS. The next rung is the ladder's first model above
# it, run as step_role picks. Refused, with nothing closed, with escalate_ladder empty, at or above its
# top rung, and for a story that is not ready, not an agent's kind, or has no worktree. [findings] is a file the brief pastes
# too (tell_agent's).
step_up() {
  local slug="$1" trigger="$2" f="${BOARD}/stories/$1.md" last fromrole from to rank role names src wt base prompt
  [[ "${trigger}" =~ ^[a-z0-9-]+$ && " ${STEP_UP_TRIGGERS} " == *" ${trigger} "* ]] \
    || die "step-up: the trigger must be one of ${STEP_UP_TRIGGERS// /, } (swarm.sh step-up <slug> <trigger>)"
  [[ -n "${CFG_escalate_ladder}" ]] || die "step-up: escalate_ladder is empty (off), so there is no next model; nothing was closed"
  step_up_story "${slug}"; src="${STEP_SRC}"; wt="$(worktree_for "${src}" "${slug}")"
  last="$(awk -F'\t' -v n="$(agent_name "${slug}")" '$3 == n { l = $2 " " $5 } END { print l }' "${AGENTS_LOG}" 2>/dev/null || true)"
  read -r fromrole from <<< "${last}"
  { [[ -n "${fromrole}" && " ${BUILDER_ROLES} " == *" ${fromrole} "* ]] && rank="$(model_rank "${from}")"; } \
    || die "step-up: ${slug}'s newest agents.tsv line is not a build on one of ${LADDER_MODELS} (${last:-none}); nothing was closed"
  to="$(ladder_next "${from}")" || die "step-up: ${slug}'s builder is on ${from}, at or above escalate_ladder's top rung, so there is no next model; nothing was closed"
  # What start_rung and start_agent would refuse on, before the builder is closed: a role policy no
  # longer knows (one of LEGACY_BUILDER_ROLES), an env: name not set here, an untrusted folder, a /goal.
  role="$(step_role "${fromrole}" "${to}")"
  (policy "${role}") >/dev/null 2>&1 \
    || die "step-up: ${slug}'s build is ${fromrole}, which steps up as ${role}, a role nothing starts now; nothing was closed"
  names="$(story_env "${f}")" || die "${names}"
  require_trusted "${wt}"; goal_preflight "${slug}" "${src}"
  base="$(base_for "${src}")"
  prompt="${PROJECT_DIR}/.swarm/briefs/${slug}.md"; mkdir -p "${prompt%/*}"
  handover_brief "${slug}" "${src}" "${base}" "${trigger}" "${from}" "${to}" "${3:-}" > "${prompt}"
  printf '%s %s %s %s\n' "${trigger}" "${from}" "${to}" "${role}" > "${prompt%.md}.step-up"
  # From here a failure is not a refusal: the old builder is closed. ladder_step's _step-up
  # (STEP_UP_AUTO) says so and exits STEP_UP_PARTWAY (step_up_failed).
  # shellcheck disable=SC2064 # expand now: the slug is local
  [[ -z "${STEP_UP_AUTO:-}" ]] || trap "step_up_failed '${slug}'" EXIT
  # The old builder goes first: the new one takes its name.
  shut_agent "${slug}"
  start_rung "${slug}"
}

# step_up_story <slug> — die, naming why, unless <slug>'s story can be stepped up: on the board, ready,
# of a kind an agent builds (agent_kind), with a worktree. STEP_SRC is its repo dir. Run in the
# caller's shell, so a die is the command's own.
step_up_story() {
  local f="${BOARD}/stories/$1.md"
  [[ "$1" =~ ^[a-z0-9-]+$ && -f "${f}" ]] || die "step-up: no story ${f}"
  [[ "$(fm "${f}" status)" == ready ]] || die "step-up: $1 is not status: ready; nothing was closed"
  agent_kind "$(fm "${f}" kind)" || die "step-up: $1 is kind: $(fm "${f}" kind), which no agent builds; nothing was closed"
  STEP_SRC="$(repo_dir "$(fm "${f}" repo)")" || die "step-up: $1: ${STEP_SRC}"
  [[ -d "$(worktree_for "${STEP_SRC}" "$1")" ]] \
    || die "step-up: $1 has no worktree at $(worktree_for "${STEP_SRC}" "$1"), so there is no build to hand on; nothing was closed"
}

# step_up_resume <slug> — `step-up --resume`: start the rung a step-up closed the old builder for but
# could not start, from the brief and .step-up marker it wrote, once the story still passes
# step_up_story (a story made kind: lead since gets no agent).
step_up_resume() {
  local slug="$1"
  [[ "${slug}" =~ ^[a-z0-9-]+$ && -f "${PROJECT_DIR}/.swarm/briefs/${slug}.step-up" ]] \
    || die "step-up --resume: no step-up of '${slug}' waits to start (no .swarm/briefs/${slug}.step-up)"
  step_up_story "${slug}"
  require_trusted "$(worktree_for "${STEP_SRC}" "${slug}")"; goal_preflight "${slug}" "${STEP_SRC}"
  start_rung "${slug}"
}

# start_rung <slug> — start the rung <slug>'s .step-up marker names (<trigger> <from> <to> <role>):
# <role> on <to> in its worktree with the brief beside the marker, then log escalate `ok (<trigger>:
# <from> -> <to>)`, drop the marker and send the /goal its caller's goal_preflight made. start_agent
# runs with errexit on, so a step that fails stops it with that step's own message; then the marker
# stays, the message says to run step-up --resume, and an agents.tsv line start_agent wrote before it
# failed (a brief not taken up) goes, so the rung is on record once, when it starts.
start_rung() {
  local slug="$1" f="${BOARD}/stories/$1.md" prompt="${PROJECT_DIR}/.swarm/briefs/$1.md" trigger from to role src names epic n rc goal="${PREFLIGHT_GOAL}"
  read -r trigger from to role < "${prompt%.md}.step-up"
  src="$(repo_dir "$(fm "${f}" repo)")" || die "step-up: ${slug}: ${src}"
  names="$(story_env "${f}")" || die "${names}"
  epic="$(fm "${f}" epic)"
  n="$(wc -l < "${AGENTS_LOG}")"; n=$((n))
  set +e
  (set -e; start_agent "${epic:-${slug}}" "${slug}" "$(worktree_for "${src}" "${slug}")" "${role}" "${prompt}" "${slug}" "${names}" "${to}")
  rc=$?
  set -e
  if [[ ${rc} -ne 0 ]]; then
    # ponytail: rewrites agents.tsv, so a line another process appends in the same instant is lost;
    # an append-only "start failed" event outcomes reads would avoid that.
    awk -F'\t' -v n="${n}" -v a="$(agent_name "${slug}")" 'NR <= n || $3 != a' "${AGENTS_LOG}" > "${AGENTS_LOG}.tmp" \
      && mv "${AGENTS_LOG}.tmp" "${AGENTS_LOG}"
  fi
  [[ ${rc} -eq 0 ]] \
    || die "step-up: ${slug}'s ${from} builder is closed, but the ${to} builder did not start (see above); its worktree, branch and brief are kept: once that is fixed, run swarm.sh step-up --resume ${slug}"
  # The rung runs: from here nothing is a failed step-up (step_up_failed's trap).
  trap - EXIT
  rm -f "${prompt%.md}.step-up"
  record_event escalate "${slug}" "ok (${trigger}: ${from} -> ${to})"
  echo "stepped up: ${slug} from ${from} to ${to} (${role}), in $(worktree_for "${src}" "${slug}")"
  [[ -n "${goal}" ]] || return 0
  printf '%s\n' "${goal}" > "${prompt%.md}.goal.md"
  # A /goal that does not set is said on its own: the step-up stands.
  set +e
  (set -e; send_goal "${slug}" "${prompt%.md}.goal.md" brief)
  rc=$?
  set -e
  [[ ${rc} -eq 0 ]] || echo "swarm: ${slug}: stepped up, and its ${to} builder runs, but its /goal did not set (see above): send ${prompt%.md}.goal.md as its /goal by hand" >&2
}

# step_up_failed <slug> — step_up's exit trap once the old builder is closed: on a failure (start_rung
# said why, and kept the .step-up marker for step-up --resume, which also keeps step_due from trying
# this build again), say so and exit STEP_UP_PARTWAY.
step_up_failed() {
  local rc=$?
  [[ ${rc} != 0 ]] || return 0
  echo "step-up failed: $1 stopped after its builder was closed: list it for the lead (swarm.sh step-up --resume $1 starts the rung once the cause is fixed); do not close, retry or tell it"
  exit "${STEP_UP_PARTWAY}"
}

# builder_model <slug> — the model of the newest agents.tsv line for <slug>'s builder.
builder_model() {
  awk -F'\t' -v n="$(agent_name "$1")" '$3 == n { m = $5 } END { print m }' "${AGENTS_LOG}" 2>/dev/null || true
}

# build_started <slug> — when <slug>'s current build started: its newest ok story or escalate line,
# or ok agent line (a builder started by hand, whose target is the agent name); empty with none.
build_started() {
  awk -F'\t' -v s="$1" -v n="$(agent_name "$1")" '$5 ~ /^ok/ && ((($2 == "story" || $2 == "escalate") && $3 == s) || ($2 == "agent" && $3 == n)) { t = $1 }
    END { print t }' "${EVENTS_LOG}" 2>/dev/null || true
}

# ladder_step <slug> <trigger> [findings] — step_up <slug> for a trigger swarm.sh saw itself (close,
# wait --stall, tell, watch): 0 when it stepped up; STEP_UP_PARTWAY when it failed after closing the
# builder, and the caller stops; STEP_UP_BUSY when another step-up of it holds the lock, and the caller
# touches nothing; any other status when nothing was closed (a refusal, said on stderr,
# or a failure before the close), and the caller carries on as before. One step-up of a story at a
# time, under its lock (step_lock); inside it step_due reads the build again, and with nothing due
# (another step-up came first, no rung above, a partway failure this build) it runs nothing and returns 1.
ladder_step() {
  local since lock="${PROJECT_DIR}/.swarm/locks/step-up-$1" rc=1
  # With the ladder off nothing is due, and no lock is taken: a step-up never runs.
  [[ -n "${CFG_escalate_ladder:-}" ]] || return 1
  since="$(build_started "$1")"
  step_lock "${lock}" || return "${STEP_UP_BUSY}"
  if step_due "$1" "${since}"; then
    # A swarm.sh of its own: step_up's die then ends only it, and set -e holds in it, which a subshell
    # called from a condition, as every caller does, would run without. As _step-up it is not logged:
    # a refusal is no sign of life (stall.py), and step_up logs its own escalate line.
    rc=0; "${BASH}" "${SWARM_HOME}/bin/swarm.sh" _step-up "$1" "$2" ${3:+"$3"} || rc=$?
  fi
  rm -rf "${lock}"
  return "${rc}"
}

# step_due <slug> <since> — a step-up of <slug> is due: its build is still the one that started at
# <since>, its builder's model has a rung above it (ladder_next; none has with the ladder empty), and
# no step-up of it waits on --resume (a .step-up marker: one that failed after closing the builder).
step_due() {
  [[ "$(build_started "$1")" == "$2" ]] || return 1
  ladder_next "$(builder_model "$1")" >/dev/null || return 1
  [[ ! -e "${PROJECT_DIR}/.swarm/briefs/$1.step-up" ]]
}

# ladder_next <model> — the first escalate_ladder model ranked above <model> (model_rank); fails when
# none is, or <model> is not one of LADDER_MODELS.
ladder_next() {
  local m rank
  rank="$(model_rank "$1")" || return 1
  for m in ${CFG_escalate_ladder//,/ }; do
    if (( $(model_rank "${m}") > rank )); then echo "${m}"; return 0; fi
  done
  return 1
}

# step_lock <dir> — take a lock: make <dir> with this shell's pid in it. Held by a live pid, or by
# one still writing its pid, it fails; held by a pid that is gone, it is taken over.
step_lock() {
  local pid
  mkdir -p "${1%/*}"
  if ! mkdir "$1" 2>/dev/null; then
    pid="$(cat "$1/pid" 2>/dev/null || true)"
    [[ -n "${pid}" ]] && ! kill -0 "${pid}" 2>/dev/null || return 1
    rm -rf "$1"; mkdir "$1" 2>/dev/null || return 1
  fi
  echo "$$" > "$1/pid"
}

# stepped_up_since <slug> <time> — <slug> has an ok escalate line at or after <time>.
stepped_up_since() {
  awk -F'\t' -v s="$1" -v t="$2" '$2 == "escalate" && $3 == s && $1 >= t && $5 ~ /^ok/ { f = 1 } END { exit !f }' "${EVENTS_LOG}" 2>/dev/null
}

# handover_brief <slug> <src> <base> <trigger> <from> <to> [findings] — the next rung's brief: the builder's
# brief (story_brief), then why the build was handed on, the PR body's Models: line, for a story
# stacked on parents with open PRs build_story's Merge after note, the story as the board holds it
# (the last builder may have deleted it from the worktree already), the diff from handover_from
# (committed, uncommitted and untracked; its first HANDOVER_DIFF_LINES lines, in a fence longer than
# any run of backticks in it), the review agent's findings when they are of this HEAD (and
# [findings], the tell the step-up took the place of), and the story PR's failing checks.
handover_brief() {
  local wt models from parents open="" p prs="" stack="" diff fence='```' pr checks head findings="${PROJECT_DIR}/.swarm/reviews/$1.md" reviewed found
  wt="$(worktree_for "$2" "$1")"
  parents="$(stacked_parents "$1")"
  for p in ${parents//,/ }; do if pr="$(open_pr "$2" "${p}")"; then prs+="${prs:+ }${pr}"; open+="${open:+ }${p}"; fi; done
  [[ -z "${prs}" ]] || stack=$'\n\n'"This story is stacked on ${open}: open your PR against \`$3\` all the same, with \`Merge after ${prs}\` in its body. The diff below starts at their branches, so their commits are not in it."
  from="$(handover_from "${wt}" "$2" "$3" "${open}")" || from="origin/$3"
  # Every model agents.tsv has building this story, in order, then this one.
  models="$({ awk -F'\t' -v n="$(agent_name "$1")" '$3 == n { print $5 }' "${AGENTS_LOG}" 2>/dev/null; echo "$6"; } | awk '!seen[$0]++' | paste -sd, - | sed 's/,/, /g')"
  # head stops reading at the cap, so git stops too: a writer it cut off dies of SIGPIPE (128 + 13),
  # which ends the untracked loop; git diff --no-index exits 1 for every file that differs. With
  # pipefail that SIGPIPE fails the pipeline, so || true. git's warnings stay out of the diff.
  diff="$( { git -C "${wt}" diff "${from}"
             git -C "${wt}" ls-files -z --others --exclude-standard | while IFS= read -r -d '' p; do
               git -C "${wt}" diff --no-index -- /dev/null "${p}" || (( $? < 128 )) || break
             done
           } 2>/dev/null | head -n "${HANDOVER_DIFF_LINES}" || true)"
  while [[ "${diff}" == *"${fence}"* ]]; do fence+='`'; done
  head="$(git -C "${wt}" rev-parse HEAD)"
  reviewed="$(sed -n 's/^head: *//p' "${findings}" 2>/dev/null | head -n 1 || true)"   # no findings file: none
  if [[ ! -f "${findings}" ]]; then found="No review findings on file."
  elif [[ "${reviewed}" == "${head}" ]]; then found="$(cat "${findings}")"
  else found="The last review (${findings}) was of ${reviewed:-an unnamed head}, not this branch's HEAD ${head}, so its findings are not pasted here: they may be fixed already. Read it, and check each one before you act on it."; fi
  if ! pr="$(open_pr "$2" "$1")"; then
    checks="No open PR on story/$1."
  else
    checks="$(gh pr checks "${pr}" --json name,bucket,link --jq '.[] | select(.bucket == "fail") | "- \(.name): \(.link)"' </dev/null 2>/dev/null)" \
      || checks="gh could not list ${pr}'s checks: run \`gh pr checks ${pr}\`."
    [[ -n "${checks}" ]] || checks="None failing on ${pr}."
  fi
  story_brief "$1" "$2" "$3"
  cat <<EOF

## Handover

You take this story over from a builder on $5, stepped up to you on $6 because $(step_trigger "$4").
This worktree and its branch story/$1 are as that builder left them: carry on from them, and never
start again from origin/$3. The PR body lists every model that worked on this story on one line, the
models line: \`Models: ${models}\`. If a PR is open, edit its body to add it (\`gh pr edit --body-file\`).${stack}

### The story, as the board holds it

$(story_text "$1")

### The diff since ${from}, committed or not, untracked files too (its first ${HANDOVER_DIFF_LINES} lines; \`git diff ${from}\` has the tracked files' all)

${fence}diff
${diff:-(no change yet)}
${fence}

### Open findings

${found}
$(if [[ -n "${7:-}" ]]; then printf '\nThe conductor was sending the last builder these when it was stepped up:\n\n'; cat "$7"; fi)

### Failing checks

${checks}
EOF
}

# handover_from <wt> <src> <base> <parents> — where a handover diff starts: the merge-base of HEAD
# and origin/<base>, or for a story stacked on <parents> (those with open PRs; fetched first) of HEAD
# and their branches, so neither the base's newer commits nor the parents' are in it.
# ponytail: with several parents git picks one merge-base, so the others' commits show; diff against
# a merge of their branches if that matters.
handover_from() {
  local refs="" p
  for p in $4; do
    git -C "$2" fetch -q origin "+refs/heads/story/${p}:refs/remotes/origin/story/${p}" 2>/dev/null || true
    if git -C "$1" rev-parse -q --verify "origin/story/${p}" >/dev/null; then refs+=" origin/story/${p}"; fi
  done
  # shellcheck disable=SC2086 # one ref per word
  git -C "$1" merge-base HEAD ${refs:-"origin/$3"}
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

# escalated_file <slug> — where lead_block writes the lead's block: .swarm/escalated/<slug>, never the
# tracked story file, and not STATE_DIR, whose top-level names are tab labels. reset_story deletes it.
escalated_file() { echo "${PROJECT_DIR}/.swarm/escalated/$1"; }
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
# no conductor or /swarm-dev:swarm run builds it again, logged as held. attempts: stays as it was. Lifting the hold with reset
# is not the story's one reset (main logs it as reset:held, which reset_at does not read).
held_story() {
  local why="it paused on its goal"
  [[ "$2" != cleared-on-error ]] || why="its goal was cleared on an error"
  lead_block "$1" "**Held ($2).** The builder stopped because ${why}, and this build was not counted as an attempt. No agent builds this story until the lead decides, then tells the user what it chose and why:"$'\n\n'"- Lift the hold: run \`swarm.sh reset $1 <reason>\`, which puts its kind back and leaves \`attempts:\` as it is, so it is built again. Lifting a hold is not the story's one reset, and a later pause or error holds it again."$'\n'"- Or drop it: run \`swarm.sh drop $1 <reason>\`, which takes this story off the board, and commit the change in a board PR." "$3" >/dev/null
  set_fm "${BOARD}/stories/$1.md" held_for "$2"
  record_event held "$1" "ok ($2)"
  echo "held: $1 is kind: lead now (${2}), for the lead to lift the hold with reset, or drop"
}

# lead_block <slug> <text> <prs> [none] — no agent builds the story now: kind: lead, escalated_from: its
# kind (NO_KIND_LINE when it has no kind: line), still ready, and a block in its escalated_file with <text>
# and every PR in <prs> (failed_build's gh list), or [none] when <prs> has none (by default, that no
# PR was found). Prints how many PRs it named.
lead_block() {
  local f="${BOARD}/stories/$1.md" e d tmp from urls k=0
  e="$(escalated_file "$1")"; d="$(dirname "${e}")"
  from="$(get_fm "${f}" kind)"
  urls="$(json "'\n'.join('- ' + p['url'] for p in d)" <<< "${3:-[]}")"
  [[ -z "${urls}" ]] || k="$(grep -c . <<< "${urls}")"
  # The block first: a story escalated with no block would leave the lead nothing to decide from.
  # Written whole to a temp file beside it, then moved into place, so a failure leaves no partial block.
  mkdir -p "${d}" 2>/dev/null || die "$1: could not create ${d} for its block, so the story is left as it was"
  tmp="$(mktemp "${d}/.$1.XXXXXX" 2>/dev/null)" || die "$1: could not write its block in ${d}, so the story is left as it was"
  if ! { printf '%s\n\n' "$2" \
           && if [[ -n "${urls}" ]]; then printf "The attempts' PRs:\n\n%s\n" "${urls}"; else echo "${4:-No PR was found on story/$1.}"; fi
       } 2>/dev/null > "${tmp}" || ! mv -f "${tmp}" "${e}"; then
    rm -f "${tmp}"; die "$1: could not write its block to ${e}, so the story is left as it was"
  fi
  set_fm "${f}" kind lead
  set_fm "${f}" escalated_from "${from:-${NO_KIND_LINE}}"
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

# fill <text> <placeholder> <value> — <text> with its one <placeholder> replaced by <value>, literally.
fill() { printf '%s' "${1%%"$2"*}$3${1#*"$2"}"; }

# CI_MARK — the line that names a workflow init wrote.
CI_MARK="# swarm-dev wrote this file with swarm.sh init"
ORIGIN_ASK_SECONDS="${SWARM_ORIGIN_ASK_SECONDS:-15}"   # how long init waits on origin for its default branch

# origin_head — origin's default branch, as origin/<branch>: the cached origin/HEAD, else the HEAD
# origin advertises (ls-remote --symref, which needs nothing fetched), asked once and never prompting:
# GIT_TERMINAL_PROMPT=0, ssh in BatchMode unless the user names their own ssh, and a new session with
# no terminal to prompt on, whose whole process group is killed after ORIGIN_ASK_SECONDS. Fails when
# there is still no telling.
origin_head() {
  local env=(GIT_TERMINAL_PROMPT=0)
  git symbolic-ref -q --short refs/remotes/origin/HEAD && return
  [[ -n "${GIT_SSH_COMMAND:-}" || -n "$(git config core.sshCommand || true)" ]] || env+=("GIT_SSH_COMMAND=ssh -o BatchMode=yes")
  env "${env[@]}" python3 -c '
import os, signal, subprocess, sys
p = subprocess.Popen(["git", "ls-remote", "--symref", "origin", "HEAD"], stdin=subprocess.DEVNULL,
                     stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, start_new_session=True)
try:
    out = p.communicate(timeout=float(sys.argv[1]))[0]
except subprocess.TimeoutExpired:
    os.killpg(p.pid, signal.SIGKILL)
    sys.exit(1)
for line in out.splitlines():
    ref, _, name = line.partition("\t")
    if name == "HEAD" and ref.startswith("ref: refs/heads/"):
        print("origin/" + ref[len("ref: refs/heads/"):])
        sys.exit(0)
sys.exit(1)' "${ORIGIN_ASK_SECONDS}"
}

# init_ci <board> — with no .github/workflows, write templates/ci/ci.yml there, which runs make check on
# a PR and on a push to origin's default branch, and, for a board in the repo, the gate it runs:
# templates/ci/board-only.sh as .github/swarm-board-only.sh, which skips the checks when every path
# changed is one of the board's own files under <board> (the board's path from the root with a
# trailing /, empty for the root). A board outside the repo (<board> is /) gets no gate. A workflow
# init wrote is left as it is, its gate written again if it is missing; with any other, init prints
# the gate step to add.
init_ci() {
  local t branch ci=.github/workflows/ci.yml gate=.github/swarm-board-only.sh ours
  ours="$(grep -lsF "${CI_MARK}" .github/workflows/* | head -1 || true)"
  if [[ -n "${ours}" ]]; then
    echo "left   ${ours} (swarm-dev wrote it; delete it and run init again to rewrite it)"
    [[ "$1" == / ]] || init_gate "$1" "${gate}"
    return
  fi
  if [[ -d .github/workflows ]]; then
    if [[ "$1" == / ]]; then echo "left   .github/workflows (it exists)"; return; fi
    init_gate "$1" "${gate}"
    echo "left   .github/workflows (it exists); add this step to the job that runs your checks, before them (its checkout needs fetch-depth: 0), and give each check if: steps.gate.outputs.board_only != 'true'"
    sed -n '/- name: Skip a board-only change/,/- name: make check/p' "${SWARM_HOME}/templates/ci/ci.yml" | sed '$d'
    return
  fi
  branch="$(origin_head)" \
    || { echo "wrote no CI: cannot tell origin's default branch; set origin, or make it reachable, and run init again"; return; }
  t="$(fill "$(cat "${SWARM_HOME}/templates/ci/ci.yml")" @BRANCH@ "${branch#origin/}")"
  # No gate: its comment to its last line, the if: it sets on make check, and the deep checkout.
  [[ "$1" != / ]] || t="$(sed '/# swarm-dev: a change to only/,/run: bash .github\/swarm-board-only.sh/d; /if: steps.gate/d; /fetch-depth: 0/d' <<< "${t}")"
  [[ "$1" == / ]] || init_gate "$1" "${gate}"
  mkdir -p .github/workflows && printf '%s\n' "${t}" > "${ci}"
  echo "wrote  ${ci} (it runs make check$([[ "$1" == / ]] || echo ", unless a change is board-only"))"
}

# init_gate <board> <path> — the board-only gate at <path>, unless a file is there.
init_gate() {
  [[ ! -e "$2" ]] || return 0
  mkdir -p "$(dirname "$2")" && fill "$(cat "${SWARM_HOME}/templates/ci/board-only.sh")" @BOARD@ "$1" > "$2" && echo >> "$2"
  echo "wrote  $2 (CI's board-only gate)"
}

# init_hook <board> — the git pre-commit hook from templates/pre-commit, with <board> as init_ci has it:
# make check, unless the commit changes only the board's own files. A hook that exists is left as it
# is, and none is written while core.hooksPath is set: a repo's own is tracked, so init prints the
# lines to add (to husky's own file, not the one it regenerates under .husky/_/), and a global one runs
# in every repo, so init says to add them nowhere there.
init_hook() {
  local hook t why="" hooks_path
  t="$(fill "$(cat "${SWARM_HOME}/templates/pre-commit")" @BOARD@ "$1")"
  hook="$(git rev-parse --git-path hooks/pre-commit)"
  hooks_path="$(git config core.hooksPath || true)"
  if [[ -n "${hooks_path}" && -z "$(git config --local core.hooksPath)" ]]; then
    echo "left   ${hook} (core.hooksPath is ${hooks_path}, set outside this repo): wrote no hook, since one there runs in every repo; this repo's checks belong in none of them"
  elif [[ -z "${hooks_path}" && -f "${hook}" && "$(cat "${hook}")" == "${t}" ]]; then echo "left   ${hook} (swarm-dev wrote it)"
  elif [[ -n "${hooks_path}" || -e "${hook}" ]]; then
    [[ -z "${hooks_path}" ]] || why="core.hooksPath is ${hooks_path}"
    [[ "${hook}" != *.husky/_/pre-commit ]] || hook="${hook%_/pre-commit}pre-commit"
    echo "left   ${hook} (${why:-it exists}); add these lines to it, before any exec (a line after one never runs):"
    tail -n +2 <<< "${t}"
  else
    mkdir -p "$(dirname "${hook}")" && printf '%s\n' "${t}" > "${hook}" && chmod +x "${hook}"
    echo "wrote  ${hook} (it runs make check$([[ "$1" == / ]] || echo ", unless a commit is board-only"))"
  fi
  make -n check >/dev/null 2>&1 \
    || echo "make has no check target: add one to the Makefile; until then CI fails every change that is not board-only, and the hook checks nothing"
}

# init_commit_step <board> — the files init wrote that git does not track yet, with a line saying to
# commit them: CI runs only once its workflow is committed.
init_commit_step() {
  local wrote=(.gitignore .claude/swarm/config .github/workflows/ci.yml .github/swarm-board-only.sh) untracked="" f
  if [[ "$1" != / ]]; then
    while IFS= read -r f; do wrote+=("$1${f}"); done < <(board_templates)
  fi
  # Each path as init names it, kept when it exists and git does not track it or has it changed (read
  # from the index and HEAD, so no status.showUntrackedFiles setting can hide it).
  for f in "${wrote[@]}"; do
    [[ -e "${f}" ]] || continue
    if ! git ls-files --error-unmatch -- "${f}" >/dev/null 2>&1 || ! git diff --quiet HEAD -- "${f}" 2>/dev/null; then
      untracked+=" ${f}"
    fi
  done
  [[ -z "${untracked}" ]] || echo "Commit what init wrote, so CI runs and the config travels with the repo:${untracked}"
}

# board_templates — the board's template files, relative to the board, one per line.
board_templates() { (cd "${SWARM_HOME}/templates/docs" && find . -type f | sed 's|^\./||' | LC_ALL=C sort); }

# init_config — a commented commit_trailers line in .claude/swarm/config, unless the file names the key.
init_config() {
  local f=.claude/swarm/config
  grep -q commit_trailers "${f}" 2>/dev/null && return
  [[ ! -s "${f}" || -z "$(tail -c1 "${f}")" ]] || echo >> "${f}"
  echo "# commit_trailers = Co-Authored-By: Your Name <you@example.com>" >> "${f}"
  echo "added a commented commit_trailers line to ${f}"
}

# init_project — set the project up from the installed plugin, from its git root: the board templates
# (never over a file that exists), .claude/swarm/ with a commented commit_trailers line, the .gitignore
# lines, a CI workflow and a pre-commit hook. A second run changes nothing.
init_project() {
  local rel board f line n=0
  mkdir -p "${BOARD}" && BOARD="$(cd "${BOARD}" && pwd -P)"
  # The board's path from the root with a trailing /, or empty when the board is the root.
  rel=""; [[ "${BOARD}" == "${PROJECT_DIR}" ]] || rel="${BOARD#"${PROJECT_DIR}/"}/"
  while IFS= read -r f; do
    if [[ -e "${BOARD}/${f}" ]]; then echo "left   ${rel}${f} (it exists)"; continue; fi
    mkdir -p "$(dirname "${BOARD}/${f}")" && cp "${SWARM_HOME}/templates/docs/${f}" "${BOARD}/${f}"
    echo "copied ${rel}${f}"; n=$((n + 1))
  done < <(board_templates)
  [[ ${n} -gt 0 ]] || echo "copied nothing: the board has every template file"
  [[ -d .claude/swarm ]] || { mkdir -p .claude/swarm; echo "created .claude/swarm/"; }
  init_config
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
  # The board for the CI gate and the hook: / for one outside the repo, which no repo path starts with.
  board="${rel}"; [[ "${BOARD}/" == "${PROJECT_DIR}/"* ]] || board=/
  init_ci "${board}"
  init_hook "${board}"
  init_commit_step "${board}"
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
