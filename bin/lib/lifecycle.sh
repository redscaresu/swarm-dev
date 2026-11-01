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

# board_read base|head <path> — epic_unticketed's reader for board_pr open: <path> at origin/<base>, or
# in the worktree <wt> (board_pr's locals); fails 1 when it is absent and 2 when it cannot be read.
# board_read from <path> — the old path of the rename to <path> in board_pr's local changes
# (board_changes), or nothing. board_read ref — origin/<base>, which open has fetched (stage_gate's).
board_read() {
  local t
  if [[ "$1" == from ]]; then
    P="$2" awk -F'\t' '$1 ~ /^R/ && $3 == ENVIRON["P"] { print $2; exit }' <<< "${changes}"
  elif [[ "$1" == ref ]]; then
    echo "origin/${base}"
  elif [[ "$1" == base ]]; then
    t="$(git -C "${wt}" ls-tree --name-only "origin/${base}" -- "$2")" || return 2
    [[ -n "${t}" ]] || return 1
    git -C "${wt}" show "origin/${base}:$2" || return 2
  else
    [[ -e "${wt}/$2" || -L "${wt}/$2" ]] || return 1
    cat -- "${wt}/$2" 2>/dev/null || return 2
  fi
}

# board_changes <commit> — git diff -M --name-status from <commit> to the worktree <wt> (board_pr's
# local): its commits, uncommitted edits and new files alike, so a file moved with mv and not added
# pairs as a rename. Run over a throwaway index holding the real index's entries (a file staged with
# git add -f past .gitignore too, which open's git add -A commits) with each new file added as
# intent-to-add: it leaves the real index alone and puts no file in the object store. --index-info
# records no stat data, so git compares every file by its bytes; a copy of the real index trusted a
# stat match, and a file rewritten to the same size within the second it was checked out (review to
# active) read as unchanged.
board_changes() (
  # Not local: the EXIT trap runs once the locals are gone.
  tmp="$(mktemp -d)" || exit 1
  trap 'rm -rf "${tmp}"' EXIT
  git -C "${wt}" ls-files -s -z > "${tmp}/entries" || exit 1
  export GIT_INDEX_FILE="${tmp}/index"
  git -C "${wt}" update-index -z --index-info < "${tmp}/entries" || exit 1
  git -C "${wt}" add -A -N . || exit 1
  git -C "${wt}" -c core.quotepath=off diff --no-color -M --name-status "$1"
)

# board_pr_kind <name> <board> — the kind of the board PR <name>: plan (plan-<hld>, scope-<epic>),
# agreement (agree-<hld or epic>), finish (finish-<slug>, drop-<slug>), hold (hold-<slug>), else
# story-scope edit. A plan or agreement name counts only when it names an HLD or epic in <board> (the
# PR's worktree's), by its file name made clean (board_pr_names); a story slug such as plan-hld-gaps
# or scope-creep is a story-scope edit.
board_pr_kind() {
  local x="${1#*-}"
  case "$1" in
    plan-?*) board_pr_names "$2/hld" "${x}" && { echo plan; return; } ;;
    scope-?*) board_pr_names "$2/epics" "${x}" && { echo plan; return; } ;;
    agree-?*) { board_pr_names "$2/hld" "${x}" || board_pr_names "$2/epics" "${x}"; } && { echo agreement; return; } ;;
    finish-?* | drop-?*) echo finish; return ;;
    hold-?*) echo hold; return ;;
  esac
  echo "story-scope edit"
}

# board_pr_names <dir> <x> — true when a file <dir>/<f>.md other than the README has <f>, lower-cased
# with each run of characters other than a-z and 0-9 turned into one - and - trimmed from both ends,
# equal to <x>: the name /hld and /epic give an agreement PR (agree-<x>).
board_pr_names() {
  local f names=""
  [[ "$2" != readme ]] || return 1
  for f in "$1"/*.md; do [[ ! -f "${f}" ]] || names+="$(basename "${f}" .md)"$'\n'; done
  names="$(tr '[:upper:]' '[:lower:]' <<< "${names}" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  grep -qxF -- "$2" <<< "${names}"
}

# board_pr_kind_line <name> <board> — open's line on stderr: a plan or agreement PR needs one
# codex-review pass before it merges (the commands run it before open, so it may be done); the other
# kinds none. How a PR lands is not here: merge and grants decide that (finish's own line, and
# board_pr_merge_rule in the conductor's brief, say it).
board_pr_kind_line() {
  local kind; kind="$(board_pr_kind "$1" "$2")"
  case "${kind}" in
    plan | agreement) echo "board-pr: $1 is a ${kind} PR: it needs one swarm.sh codex-review pass before it merges; skip it if you ran it" ;;
    *) echo "board-pr: $1 is a ${kind} PR: no codex-review" ;;
  esac
}

# board_pr start|open|done <name> ... — the lead's board edits, each in its own worktree, never the
# main checkout: start makes <repo>-wt/_board-<name> (a path no story slug makes) on a new
# board/<name> from origin/<base> and prints its path; open <name> "<title>" <body-file> commits every change (all under the board, or on its own paths for a board at the root) with
# the brief's trailers, pushes and opens the PR (or pushes to the one open), printing its URL (its
# kind's line, board_pr_kind_line, goes to stderr), and refuses once the branch's PR has merged or closed; done <name> removes board/<name> on origin, then
# the worktree and board/<name> here, once the PR on the branch's tip has merged or closed, or, with
# no PR, when the branch has no commit past the base; for a plan PR that closed unmerged, it also
# removes .swarm/<hld or epic>/critic.json when that is no newer than the branch's tip commit, and
# names it. It checks everything before removing anything. main logs each as board-pr:<step> <name>, with a refusal's
# reason.
board_pr() {
  local step="${1:-}" name="${2:-}" wt b base dir real url rel where changes files f msg prs tip rtip why critic ct split="" sign=()
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
      # base_for fetches origin/<base>, with the tags on it, so the epic checks read it as it is now (an
      # HLD superseded since the start counts, and so does a tag pushed since).
      base="$(base_for "${PROJECT_DIR}")" || die "board-pr: cannot fetch origin's base branch, so whether an epic goes active with no ticket is unknown"
      rel="$(board_rel)"
      # Committed and uncommitted changes since the base, new files too: each changed path, a rename's
      # old path included (a copy's source is unchanged, so not that).
      changes="$(board_changes "$(git -C "${wt}" merge-base HEAD "origin/${base}")")" || die "board-pr: cannot list the changes in ${wt}"
      files="$(awk -F'\t' '{ print ($1 ~ /^C/ ? $3 : $2) } $1 ~ /^R/ { print $3 }' <<< "${changes}")"
      [[ -n "${files}" ]] || die "board-pr: ${wt} changes nothing"
      where="${rel}"; [[ -n "${rel}" ]] || where="the board's paths ($(board_paths | paste -sd' ' - | sed 's/ /, /g'))"
      # git C-quotes a path holding a ", \, tab or newline, and a quoted path would slip past the prefix
      # checks here and in epic_unticketed.
      while IFS= read -r f; do
        [[ "${f}" != \"* ]] || die "board-pr: ${f} has a quote, backslash, tab or newline in its name; rename it"
        in_board "${f}" || die "board-pr: ${f} is outside ${where}"
      done <<< "${files}"
      # An epic that goes active with no ticket is refused before anything is pushed. Checked outside
      # the $(...), where a die would not stop this.
      f="$(epic_unticketed board_read "${files}")" || die "board-pr: ${f}"
      [[ -z "${f}" ]] || { f="${f%%$'\n'*}"; die "board-pr: ${f} goes active with no ticket (agreed: within the last ${AGREED_MAX_AGE} days, parent:, hld: of an agreed HLD granting epics, or lead_epics = on); commit it as status: draft first, then run /swarm-dev:epic ${f}"; }
      # So is one that goes active above the stage the base allows, whatever lead_epics says.
      f="$(stage_gate board_read "${files}")" || die "board-pr: ${f}"
      [[ -z "${f}" ]] || die "board-pr: ${f}"
      # A large epic's split (scope-<epic> leaves <epic> at status: split) waits for its split critic's
      # answer (commands/plan-epic.md step 0), written since this worktree started: an older one is an
      # abandoned draft's. Not since the children: the lead edits them after, to fix its findings. A
      # later board PR on an epic the base already has split (a missed child, a split-gap fix) is no
      # new split, and neither is any other board PR: they start no critic.
      f="${wt}/${rel}epics/${name#scope-}.md"
      if [[ "${name}" == scope-?* && -f "${f}" && "$(fm "${f}" status)" == split ]] \
        && [[ "$(git -C "${wt}" show "origin/${base}:${rel}epics/${name#scope-}.md" 2>/dev/null | sed -n 's/^status: *//p' | head -1)" != split ]]; then
        split="${PROJECT_DIR}/.swarm/${name#scope-}"
        [[ "$(json "isinstance(d.get('findings'), list)" 2>/dev/null < "${split}/split-critic.json")" == True ]] \
          || die "board-pr: ${name#scope-} is split, but .swarm/${name#scope-}/split-critic.json holds no {findings:[...]}; start the split critic first"
        [[ "${split}/split-critic.json" -nt "${wt}/.git" ]] \
          || die "board-pr: ${name#scope-} is split, but .swarm/${name#scope-}/split-critic.json is older than this board PR's worktree (an earlier draft's); start the split critic again"
      fi
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
        # shellcheck disable=SC2154 # assigned in another file
        [[ "${CFG_sign_commits}" != true ]] || sign=(-S)
        git -C "${wt}" commit -q ${sign[@]+"${sign[@]}"} -m "${msg}" || die "board-pr: the commit failed in ${wt}"
      fi
      git -C "${wt}" push -q -u origin "${b}" || die "board-pr: cannot push ${b}"
      [[ -n "${url}" ]] || url="$(gh pr create -R "$(git -C "${PROJECT_DIR}" remote get-url origin)" --base "${base}" --head "${b}" --title "$3" --body-file "$4")" \
        || die "board-pr: gh pr create failed for ${b}"
      url="${url##*$'\n'}"
      # A split's board PR, its day and URL, so flow's split block shows every split, a clean one too.
      # A second open of the same PR keeps the first day.
      if [[ -n "${split}" ]] && ! grep -qsF "${url}" "${split}/split-pr"; then
        printf '%s\t%s\n' "$(date +%F)" "${url}" > "${split}/split-pr"
      fi
      board_pr_kind_line "${name}" "${wt}${rel:+/${rel%/}}" >&2
      echo "${url}" ;;
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
      # A plan PR that closed unmerged leaves its critic's answer behind, which lead-stop's plan_drafted
      # would count as a plan still waiting on the user. Only an answer no newer than the branch's tip
      # commit is that plan's; a re-plan begun before this done writes a newer one, which stays. The kind
      # is read from the PR's worktree, as open read it: the main checkout may be behind origin.
      critic=""
      if [[ " ${prs} " == *" CLOSED "* && " ${prs} " != *" MERGED "* ]]; then
        rel="$(board_rel)"
        dir="${BOARD}"; [[ ! -d "${wt}" ]] || dir="${wt}${rel:+/${rel%/}}"
        if [[ "$(board_pr_kind "${name}" "${dir}")" == plan ]]; then
          critic="${PROJECT_DIR}/.swarm/${name#*-}/critic.json"
          ct="$(git -C "${PROJECT_DIR}" log -1 --format=%ct "${tip}" 2>/dev/null)" && [[ -f "${critic}" ]] \
            && python3 -I -c 'import os, sys; sys.exit(int(os.path.getmtime(sys.argv[1])) > int(sys.argv[2]))' "${critic}" "${ct}" \
            || critic=""
        fi
      fi
      # origin first: its delete can fail (the lease, a protected branch), and the local state must
      # then stay for the next run.
      [[ -z "${rtip}" ]] || git -C "${PROJECT_DIR}" push -q --force-with-lease="refs/heads/${b}:${rtip}" origin --delete "${b}" \
        || die "board-pr: cannot delete ${b} on origin"
      if [[ -e "${wt}" ]]; then
        why="$(git -C "${PROJECT_DIR}" worktree remove "${wt}" 2>&1)" || die "board-pr: cannot remove ${wt}: ${why%%$'\n'*}"
      fi
      git -C "${PROJECT_DIR}" worktree prune
      ! git -C "${PROJECT_DIR}" show-ref -q --verify "refs/heads/${b}" || git -C "${PROJECT_DIR}" branch -q -D "${b}"
      if [[ -n "${critic}" ]]; then
        rm -f "${critic}"
        echo "removed ${wt}, ${b} and .swarm/${name#*-}/critic.json"
      else
        echo "removed ${wt} and ${b}"
      fi ;;
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
    [[ "$(get_fm - status <<< "${up}")" != "done" || " review building held " != *" $(get_fm - status < "${f}") "* ]] || return 0   # loose-match: ok space-padded, so a whole word
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

# board_story <path> — the slug when <path> (from the project's root) is one story file on the board;
# nothing for any other path, or for more than one.
board_story() {
  local f="${PROJECT_DIR}/$1"
  f="${f#"${BOARD}/stories/"}"
  [[ "${f}" != "${PROJECT_DIR}/$1" && "${f}" == *.md && "${f}" != *[/[:space:]]* && "${f}" != README.md ]] || return 0
  echo "${f%.md}"
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
# incoming value, on stdout and in an incident, key-dropped: <file> <key>: <ours> -> <theirs>, with slug=
# when <file> is a story (board_story), as a pull-failed incident has when it names one story file and nothing else. It also
# removes each untracked board file whose bytes are already the incoming one's, which the pull brings
# back. If the merge then fails (git refuses it: another untracked file it would overwrite), it puts
# each of those changes back (put_back), so a failed pull changes nothing. A changed file the incoming
# commits leave alone stays as it is through the pull. On failure PULL_WHY says why and what to do
# before reconcile runs again.
PULL_WHY=""
pull_board_repo() {
  local incoming line p b o k v u stop="" meet="" given="" board other out keys=() undo=()
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
      record_incident - "${o}" "$(board_story "${o#pull-failed: }")"
      { printf '%s\n' "${o}" > "${PULL_STOP}"; } 2>/dev/null || true
    fi
    board=""; other=""
    while IFS= read -r p; do
      [[ -n "${p}" ]] || continue
      if in_board "${p}"; then board+="${board:+ }${p}"; else other+="${other:+ }${p}"; fi
    done <<< "${stop}"
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
    record_incident - "key-dropped: ${p} ${k}: ${v} -> ${u}" "$(board_story "${p}")"
  done <<< "${given}"
}

# archive_session <name> — keep a gzip'd copy of <name>'s Claude session log (its newest agents.tsv
# line's session) as .swarm/sessions/<date>-<name>-<session>.jsonl.gz, once per session: Claude Code
# deletes session logs after cleanupPeriodDays. .swarm/ is git-ignored, so the copy stays on this
# machine, readable by its user only; nothing is redacted. An agent with no session (codex) has nothing to keep. A copy that
# fails is reported and never stops the close: the session log itself is untouched.
archive_session() {
  local name session src dir f
  # agents.tsv holds names cut at 32 characters, so a longer name's session is not known: the newest
  # line under its cut may be another agent's that shares it, still running.
  name="$(agent_name "$1")"; [[ "${name}" == "$1" ]] || return 0
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
# CLOSE_DROP: set by close --drop, which clears a build whose PR is open (close_agent).
CLOSE_DROP=""

# shut_agent <name> — archive <name>'s session log, close what was opened for it (close_panes) and
# remove its ZDOTDIR (clean_env's), unless its pane could not be closed (CLOSE_PANE_KEPT). close_agent
# and step_up both end a builder this way, and each checks CLOSE_PANE_KEPT after.
shut_agent() {
  # One builder, two names: herdr's (agent_name, cut at 32 characters), which failed_build and
  # retire_agent map to, and the pane record's full slug (start_agent's pane name), which close_panes
  # matches. Passing close_panes the cut name would leave a long slug's pane open.
  close_panes "$1"
  # Kept while its pane is (close_pane could not close it, or close refused it): the agent may still
  # be using it, and the session and ZDOTDIR under the cut name may be another live agent's.
  [[ -z "${CLOSE_PANE_KEPT}" ]] || return 0
  archive_session "$1"
  rm -rf "${PROJECT_DIR}/.swarm/zdotdir/$(agent_name "$1")"
}

# NOT_CLOSED: what a close prints when the builder's pane could not be closed (<name> is the name).
NOT_CLOSED="not closed: <name>'s pane is still open, so nothing was counted or cleared; close it again once herdr answers"

# keep_build <slug> <cause> <urls> <heads> — a bare close of a story's builder whose PRs <urls> are
# open (<heads> their head SHAs, - for one gh did not give). A give-up's PR may be red or unreviewed:
# its heads' checks (heads_green, read fresh) and review (review_pass) are read once, and what has not
# passed goes in the note. The story then goes in review with those PRs as review puts it
# (review_state), or is held as review holds it, with kept: <date> <close> (<note>) so nothing takes it
# for reviewed: waiting_on_user and lead_queue list it as kept, never merge, and review clears the
# line. It is logged as kept, never review, so no report counts a give-up as a hand-off. The state is
# written before the builder closes (shut_agent), so a state_set that dies leaves the builder open;
# when the pane could not be closed, the state goes back to ready (NOT_CLOSED). The worktree and
# branches stay, and nothing is counted.
keep_build() {
  local f="${BOARD}/stories/$1.md" head rc=0 reviewed=1 note="" money=""
  mkdir -p "${LEAD_DIR}"   # heads_green records a green head beside LEAD_GREEN
  # shellcheck disable=SC2086 # one URL per word
  LEAD_FRESH=1 heads_green $3 || rc=$?
  case "${rc}" in 0) ;; 2) note="checks not read" ;; *) note="not green" ;; esac
  for head in $4; do [[ "${head}" != - ]] && review_pass "$1" "${head}" || reviewed=0; done
  [[ ${reviewed} == 1 ]] || note="${note:+${note}, }not reviewed"
  # shellcheck disable=SC2086 # one URL per word
  review_state "${f}" "$(date +%F) close${2:+ $2}${note:+ (${note})}" $3
  shut_agent "$1"
  if [[ -n "${CLOSE_PANE_KEPT}" ]]; then
    state_set "${f}" status ready prs "" held_by "" kept ""
    [[ -n "${CLOSE_REFUSED}" ]] || echo "${NOT_CLOSED/<name>/$1}"
    return 0
  fi
  record_event kept "$1" "ok ($3${note:+; ${note}})"
  if [[ -n "${REVIEW_HELD}" ]]; then
    # A parent that costs money waits on the user's merge (money_walk), as mark_review says.
    [[ -z "$(money_walk "${REVIEW_HELD}")" ]] || money=" (costs money)"
    echo "kept${note:+ (${note})}: $1's PR $3, its branch story/$1 and its worktree stay, and nothing was counted or cleared; held: it waits for ${REVIEW_HELD}${money} to merge, as review holds it. swarm.sh close $1 ${2:+$2 }--drop closes the PR and clears the build"
    return 0
  fi
  echo "kept${note:+ (${note})}: $1 is in review with its PR $3, its branch story/$1 and its worktree, and nothing was counted or cleared; it is not offered to merge until swarm.sh review $1 $3 marks it reviewed. swarm.sh close $1 ${2:+$2 }--drop closes the PR and sends the story back to ready"
}

# back_to_ready <slug> — a story in review that --drop clears goes back to ready, its PRs no longer
# its. Called once the close's hold or count is written, so a step that fails first leaves it in review.
back_to_ready() {
  local f="${BOARD}/stories/$1.md"
  [[ "$(fm "${f}" status)" != review ]] || state_set "${f}" status ready prs "" kept ""
}

# conductor_busy <conductor> — why closing <conductor> now could cut its work short, or nothing (and
# it fails): it is working (session_state busy, unless its turn stopped on an API error (api_stopped),
# whose exit is this close; or herdr's status working where herdr answers for it), or its epic's
# Finish PR (swarm.sh finish <epic>, on board/finish-<epic>) is open, whose swarm.sh merge --board may
# be running in its pane, where a close would kill it. A list of that branch's PRs gh could not give
# says so: whether such a merge runs is not known (fail closed). The backlog conductor finishes no
# epic, and a board outside the project's repo, or a project with no origin, opens no Finish PR.
conductor_busy() {
  local state pane epic origin prs open head
  state="$(session_state "$1")"
  if [[ "${state}" == herdr || "${state}" == gone ]]; then state="herdr:$(agent_status "$1")"
  elif [[ "${state}" == busy ]]; then pane="$(agent_field "$1" pane_id)"; ! api_stopped "$1" "${pane}" || state=stopped; fi
  if [[ "${state}" == busy || "${state}" == herdr:working ]]; then echo "is working"; return 0; fi
  epic="$(conduct_epic "$1")"
  [[ "${epic}" != backlog && ${BOARD_IN_REPO} == 1 ]] || return 1
  origin="$(git -C "${PROJECT_DIR}" remote get-url origin 2>/dev/null)" || return 1
  head="board/finish-${epic}"
  if ! prs="$(gh pr list -R "${origin}" --head "${head}" --state all --json url,state,headRefName 2>/dev/null)" \
     || ! open="$(SWARM_HEAD="${head}" json "' '.join(p['url'] for p in d if p.get('headRefName') == e['SWARM_HEAD'] and p['state'] == 'OPEN')" <<< "${prs}")"; then
    echo "could not have its Finish PR read (gh could not list the PRs on ${head}), so whether a swarm.sh merge --board of it still runs in its pane is not known"; return 0
  fi
  [[ -n "${open}" ]] || return 1
  echo "has its Finish PR ${open} open, and the swarm.sh merge --board that lands it may be running in its pane"
}

# close_agent <name> [cause] — close what was opened for <name> (shut_agent).
# A conductor (conduct-<name>, no story of that name) that conductor_busy names a reason for is
# refused before anything closes, the refusal naming it.
# A close that would end a failed build whose PR is still open closes the builder alone and puts the
# story in review with that PR (keep_build); impossible, paused and cleared-on-error, which would hand
# the story on, are refused instead. Only with CLOSE_DROP set (close --drop) does it go on to clear
# the build, printing what it dropped (clear_build). A bare impossible close whose PRs failed_build
# did not list is refused, since its clear_build would delete story/<name> on origin and so close
# any PR still open there, and so is any impossible close while a PR merged or is merging.
# An unknown cause is refused before anything closes, and so, with goal on, is a missing one while
# <name>'s story is still ready (its builder is giving up), and so is impossible for a story that
# cannot be handed on (impossible_refused). A close that ends a failed build (failed_build, decided
# before anything closes, while the builder can still be found) then clears the attempt away
# (clear_build), so the next build starts fresh. With no cause, met, stalled or bound it first raises
# the story's attempts: by one, and when that build was escalate, the story becomes the lead's
# (escalate_story). impossible, paused and cleared-on-error count nothing. impossible makes the story
# the lead's (impossible_story) whether or not there was a build to clear; paused and cleared-on-error
# hold it for the lead (held_story) when the close ends a build. A close that ends a build with no
# open or merged PR on story/<name> logs an idle-no-pr incident (record_incident, its slug= <name>), the one place it is logged, unless
# the builder did not stop of itself (stalled, paused or cleared-on-error) or handed it on (impossible);
# with escalate_ladder set, that close then steps the build up (ladder_step no-pr) instead, if it can.
close_agent() {
  local cause="${2:-}" f="${BOARD}/stories/$1.md" prs counted=0 n why rc open="" heads=""
  # The message never repeats the word: main logs a die's first line.
  [[ -z "${cause}" ]] || is_close_cause "${cause}" \
    || die "close: the cause must be ${CLOSE_CAUSES} (swarm.sh close <name> [cause])"
  if [[ "$1" == conduct-* && ! -f "${f}" ]] && why="$(conductor_busy "$1")"; then
    die "close: $1 ${why}, so nothing was closed: close it again once it is idle and no Finish PR of its is open. A swarm.sh merge --board that lands its Finish PR closes $1 itself, once that merge has exited and $1 is idle, as this close was tried"
  fi
  # shellcheck disable=SC2154 # assigned in another file
  [[ -n "${cause}" || "${CFG_goal}" == off || ! -f "${f}" || "$(fm "${f}" status)" != ready ]] \
    || die "close: with goal on, $1's story is still ready, so say why its builder stopped: swarm.sh close $1 <cause>, the cause one of ${CLOSE_CAUSES}"
  if [[ "${cause}" == impossible ]] && why="$(impossible_refused "$1")"; then
    die "close: $1 cannot be closed impossible, because ${why}; nothing was closed"
  fi
  rc=0; prs="$(failed_build "$1")" || rc=$?
  if [[ ${rc} == 0 ]]; then
    counted=1
    # The open PRs' URLs, then their heads, on two lines. A list that cannot be read keeps
    # everything: nothing has closed yet.
    [[ -n "${CLOSE_DROP}" ]] || open="$(json "' '.join(p['url'] for p in d if p['state'] == 'OPEN') + '\n' + ' '.join(p.get('headRefOid') or '-' for p in d if p['state'] == 'OPEN')" <<< "${prs}")" \
      || die "close: $1's PR list could not be read, so nothing was closed or counted"
    heads="${open#*$'\n'}"; open="${open%%$'\n'*}"
  elif [[ "${cause}" == impossible && ${rc} == "${BUILD_MERGING}" ]]; then
    die "close: a PR on story/$1 merged or is merging (auto-merge set), so $1 cannot be closed impossible: clearing its build would delete the branch under that PR; nothing was closed"
  elif [[ "${cause}" == impossible && -z "${CLOSE_DROP}" ]]; then
    # Clearing the build would delete story/$1 on origin, which closes any PR still open on it.
    die "close: $1's PRs were not listed (no builder open, or gh could not list them), so a PR may be open: swarm.sh close $1 impossible --drop clears its build anyway; nothing was closed"
  fi
  if [[ -n "${open}" ]]; then
    [[ ! "${cause}" =~ ^(impossible|paused|cleared-on-error)$ ]] \
      || die "close: $1's PR ${open} is open, and a ${cause} close hands the story to the lead and clears its build, closing that PR: run swarm.sh close $1 ${cause} --drop for that, or close it with no cause (met, stalled or bound with goal on) to keep the PR in review; nothing was closed"
    keep_build "$1" "${cause}" "${open}" "${heads}"
    return 0
  fi
  if [[ ${counted} == 1 ]]; then
    if [[ ! "${cause}" =~ ^(stalled|paused|cleared-on-error|impossible)$ && "$(json "any(p['state'] != 'CLOSED' for p in d)" <<< "${prs}")" != True ]]; then
      record_incident "$1" "idle-no-pr: closed (${cause:-no cause}) with no open or merged PR on story/$1" "$1"
      # With the ladder on, the next model takes the build over instead: no attempt, nothing cleared.
      # A step-up that failed partway closed the builder already: nothing more is done here.
      # main logs no close then (stepped_up_since): the escalate line ends the stepped-up build.
      rc=0; ladder_step "$1" no-pr || rc=$?
      [[ ${rc} != 0 ]] || return 0
      [[ ${rc} != "${STEP_UP_PARTWAY}" ]] || die "close: $1's step-up failed partway, after its builder was closed, so nothing more was closed or counted; wait --lead tells the lead, so leave $1 alone"
      [[ ${rc} != "${STEP_UP_BUSY}" ]] || die "close: another step-up or a restart of $1 is running and may be starting its next builder, so nothing was closed or counted: wait on $1, then close it if it still needs closing"
    fi
  fi
  shut_agent "$1"
  # Its pane could not be closed (close_pane said why): the builder may still be working in its
  # worktree, so nothing is counted, held, handed on or cleared.
  if [[ -n "${CLOSE_PANE_KEPT}" ]]; then
    [[ -n "${CLOSE_REFUSED}" ]] || echo "${NOT_CLOSED/<name>/$1}"   # a refusal said why (close_panes)
    return 0
  fi
  if [[ "${cause}" == impossible ]]; then
    # With --drop, the build is cleared even when failed_build declined (a builder gone, gh down),
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
      back_to_ready "$1"
      clear_build "$1" "the build of $1 stopped (${cause}), which is not an attempt" "${prs:-[]}"
    elif ! impossible_refused "$1" >/dev/null; then
      echo "not held: $1 (${cause}) ended no build here (no builder open, a PR merged or merging, or gh could not list its PRs), so its story is as it was: list it for the lead and do not start it again"
    fi
    return 0 ;;
  esac
  if [[ ${counted} != 1 ]]; then
    [[ -z "${CLOSE_DROP}" || ! -f "${f}" ]] \
      || echo "not dropped: $1 has no build this close can drop (it is neither ready nor in review or held with a PR open, its builder is closed with no PR open, a PR merged or is merging, or gh could not list its PRs)"
    return 0
  fi
  n="$(get_fm "${f}" attempts)"
  # Checked before the arithmetic, which would evaluate it.
  [[ "${n}" =~ ^(0|[1-9][0-9]*)?$ ]] \
    || { echo "swarm: ${f}: attempts must be a non-negative whole number, not '${n}'; this failed build is not counted or cleared" >&2; return 0; }
  n=$((${n:-0} + 1))
  set_fm "${f}" attempts "${n}"
  back_to_ready "$1"
  clear_build "$1" "attempt ${n} at $1 failed" "${prs}"
  escalate_story "$1" "${n}" "${prs}"
}

# STEP_UP_TRIGGERS: why a build is handed up the ladder: round STEP_UP_FINDINGS of review findings, CI red
# twice, a stalled builder, or a builder that stopped with no PR. step_trigger says each in prose.
# STEP_UP_FINDINGS: the findings tell since a build started that steps it up (tell_agent; the
# step_up_findings setting); STEP_UP_RED_HEADS: the red heads on its PR that do (ci_red_step). The
# trigger names carry them.
# shellcheck disable=SC2154 # assigned in another file
STEP_UP_FINDINGS="${CFG_step_up_findings}"
STEP_UP_RED_HEADS=2
# TOP_RUNG_FINDINGS: the findings tell since a build reached the ladder's top rung (or started on or above it)
# that holds the story for the lead instead (tell_agent, top_rung_story; the top_rung_rounds setting):
# past the top, only the lead.
# shellcheck disable=SC2034,SC2154 # read in another file; CFG_top_rung_rounds is assigned in another file
TOP_RUNG_FINDINGS="${CFG_top_rung_rounds}"
# STEP_UP_PARTWAY: step-up's exit status when it failed after closing the builder, and only then.
# STEP_UP_BUSY: ladder_step's when another step-up of the story, or a restart, holds its lock: it may be
# starting the next builder, so the caller touches nothing.
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
# top rung, and for a story that is not ready, not an agent's kind, or has no worktree; refused too,
# with no rung started, when the old builder's pane could not be closed. [findings] is a file the brief pastes
# too (tell_agent's). A stalled step-up keeps bg= test= sign= on its marker for its escalate line: as
# wait_agent's agent_stalled read them, passed in SWARM_STALL_READS, when it runs as _step-up (STEP_UP_AUTO);
# else read fresh with stall_reads before the builder is closed, so a 1 can show.
step_up() {
  local slug="$1" trigger="$2" f="${BOARD}/stories/$1.md" last fromrole from to rank role names src wt b reads="" n
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
  # longer knows (one of LEGACY_BUILDER_ROLES), an env: name not set here, an untrusted folder, a /goal,
  # a worktree git cannot read (which exits with git's status: a refusal, not a failure partway).
  role="$(step_role "${fromrole}" "${to}")"
  (policy "${role}") >/dev/null 2>&1 \
    || die "step-up: ${slug}'s build is ${fromrole}, which steps up as ${role}, a role nothing starts now; nothing was closed"
  names="$(story_env "${f}")" || die "${names}"
  require_trusted "${wt}"; goal_preflight "${slug}" "${src}"; git -C "${wt}" rev-parse --git-dir >/dev/null
  b="${PROJECT_DIR}/.swarm/briefs/${slug}"; mkdir -p "${b%/*}"
  # [findings] kept beside the marker, so start_rung's brief (and a resume's) pastes them. Copied
  # first: a marker is left only by a step-up that got as far as closing the builder.
  rm -f "${b}.findings.md"; [[ -z "${3:-}" ]] || cp "$3" "${b}.findings.md"
  if [[ "${trigger}" == stalled ]]; then
    if [[ -n "${STEP_UP_AUTO:-}" && "${SWARM_STALL_READS:-}" =~ ^bg=[01]\ test=[01]\ sign=[01]$ ]]; then reads="${SWARM_STALL_READS}"
    else n="$(agent_name "${slug}")"; reads="$(stall_reads "${n}" "$(agent_field "${n}" pane_id)")"; fi
  fi
  # Not passed on to the rung: SWARM_* reaches every agent.
  unset SWARM_STALL_READS
  # The marker (step_up_marker): while this swarm.sh runs, the lead's poll reads it as a step-up under way.
  step_up_marker "${b}.step-up" "${trigger} ${from} ${to} ${role}${reads:+ ${reads}}"
  # From here a failure is not a refusal: the old builder is closed. step_up_failed logs it, and
  # ladder_step's _step-up (STEP_UP_AUTO) says so and exits STEP_UP_PARTWAY.
  # shellcheck disable=SC2064 # expand now: the slug is local
  trap "step_up_failed '${slug}'" EXIT
  STEP_UP_CLOSED=""
  # The old builder goes first: the new one takes its name, and start_rung reads the worktree for the
  # brief only once nothing writes to it.
  shut_agent "${slug}"
  if [[ -n "${CLOSE_PANE_KEPT}" ]]; then
    # Its pane could not be closed (close_pane said why), or close refused a live agent under its cut
    # (close_panes said why): the old builder may still be working in the worktree, so no second one
    # starts there. A refusal, not a failure partway: nothing changed.
    trap - EXIT
    rm -f "${b}.step-up" "${b}.findings.md"
    [[ -z "${CLOSE_REFUSED}" ]] || die "step-up: ${slug}'s builder pane was not closed (see above), so nothing was stepped up"
    die "step-up: ${slug}'s builder pane could not be closed, so it may still be working in its worktree; nothing was stepped up"
  fi
  STEP_UP_CLOSED=1
  # The old builder is gone: the marker says so, and a pane herdr lists under its name from here is
  # the new rung's (step_up_closed).
  step_up_marker "${b}.step-up" "${trigger} ${from} ${to} ${role}${reads:+ ${reads}}" closed
  start_rung "${slug}"
}

# step_up_story <slug> — die, naming why, unless <slug>'s story can be stepped up: on the board, ready,
# of a kind an agent builds (agent_kind), not a stacked child held for review (held_by:, which
# build_story never starts again), with a worktree, and, as failed_build asks, no PR on story/<slug>
# merged or set to auto-merge (its build is done, not stuck) and gh able to list them. STEP_SRC is its
# repo dir, STEP_PR its open PR's URL, or empty when it has none, and STEP_PRS gh's list of them. Run in the caller's shell, so a
# die is the command's own.
step_up_story() {
  local f="${BOARD}/stories/$1.md" url prs
  [[ "$1" =~ ^[a-z0-9-]+$ && -f "${f}" ]] || die "step-up: no story ${f}"
  [[ "$(fm "${f}" status)" == ready ]] || die "step-up: $1 is not status: ready; nothing was closed"
  agent_kind "$(fm "${f}" kind)" || die "step-up: $1 is kind: $(fm "${f}" kind), which no agent builds; nothing was closed"
  [[ -z "$(get_fm "${f}" held_by)" ]] \
    || die "step-up: $1 is held until its parents merge (held_by:), and is reviewed again, never built again; nothing was closed"
  STEP_SRC="$(repo_dir "$(fm "${f}" repo)")" || die "step-up: $1: ${STEP_SRC}"
  [[ -d "$(worktree_for "${STEP_SRC}" "$1")" ]] \
    || die "step-up: $1 has no worktree at $(worktree_for "${STEP_SRC}" "$1"), so there is no build to hand on; nothing was closed"
  if ! url="$(git -C "${STEP_SRC}" remote get-url origin 2>/dev/null)" \
     || ! prs="$(gh pr list -R "${url}" --head "story/$1" --state all --json state,url,autoMergeRequest </dev/null 2>/dev/null)" \
     || ! STEP_PR="$(json "next((p['url'] for p in d if p['state'] == 'OPEN'), '')" <<< "${prs}" 2>/dev/null)"; then
    die "step-up: could not list the PRs on story/$1 (git or gh), so nothing was closed"
  fi
  STEP_PRS="${prs}"
  [[ "$(json "any(p['state'] == 'MERGED' or (p['state'] == 'OPEN' and p.get('autoMergeRequest')) for p in d)" <<< "${prs}")" == False ]] \
    || die "step-up: a PR on story/$1 has merged or is set to auto-merge, so its build is done, not stuck; nothing was closed"
}

# step_up_resume <slug> — `step-up --resume`: start the rung a step-up closed the old builder for but
# could not start, from the brief and .step-up marker it wrote, once the story still passes
# step_up_story (a story made kind: lead since gets no agent).
step_up_resume() {
  local slug="$1" rung
  local lock="${PROJECT_DIR}/.swarm/locks/step-up-$1"
  [[ "${slug}" =~ ^[a-z0-9-]+$ && -f "${PROJECT_DIR}/.swarm/briefs/${slug}.step-up" ]] \
    || die "step-up --resume: no step-up of '${slug}' waits to start (no .swarm/briefs/${slug}.step-up)"
  # One step-up of a story at a time (ladder_step's lock): a refused resume leaves the marker as it is.
  step_lock "${lock}" || die "step-up --resume: another step-up of ${slug} is running; nothing was started"
  # The rung read under the lock: a resume that ran between the check above and the lock started it
  # (start_rung removes the marker) and freed the lock, so this one must start no second builder, and
  # nothing failed, so it logs nothing. A marker with an empty first line is no rung to start either.
  rung="$(head -1 "${PROJECT_DIR}/.swarm/briefs/${slug}.step-up" 2>/dev/null)" || rung=""
  [[ -n "${rung}" ]] || { rm -rf "${lock}"; die "step-up --resume: ${slug}'s .swarm/briefs/${slug}.step-up is gone or empty since the check above (a resume that ran meanwhile started the rung); nothing was started"; }
  # Its own pid next, and closed, since a resume only follows a close, so the lead's poll reads the
  # resume as under way from here. From here a refusal is a failed resume too: it logs its
  # step-up:failed line, and the lock goes on any exit.
  step_up_marker "${PROJECT_DIR}/.swarm/briefs/${slug}.step-up" "${rung}" closed
  # shellcheck disable=SC2064 # expand now: the slug and lock are local
  trap "step_up_failed '${slug}'; rm -rf '${lock}'" EXIT
  STEP_UP_CLOSED=1   # the step-up that wrote the marker closed the builder
  STEP_UP_RESUMING=1
  step_up_story "${slug}"
  require_trusted "$(worktree_for "${STEP_SRC}" "${slug}")"; goal_preflight "${slug}" "${STEP_SRC}"
  # start_rung clears the trap once the rung runs.
  start_rung "${slug}"
  rm -rf "${lock}"
}

# step_up_marker <file> <first line> [closed] — write a .step-up marker: <first line> (<trigger> <from>
# <to> <role>, then a stalled one's bg= test= sign=, which start_rung reads), then `pid <n>`, this
# swarm.sh's pid, then `closed` once the old builder is closed. While that process runs, the step-up
# is under way; once it is gone and the marker is still there, the step-up failed (no_agent_lines
# prints `step-up failed:`), and with `closed` a pane herdr lists under the builder's name is the new
# rung's, not the old builder (step_up_closed).
step_up_marker() {
  { printf '%s\npid %s\n' "$2" "$$"; [[ -z "${3:-}" ]] || echo closed; } > "$1.tmp" && mv "$1.tmp" "$1"
}

# step_up_die <slug> <why> <message> — a step-up of <slug> stopped after its builder was closed: log
# `step-up:failed <slug> ok (<why>)`, the line flow reads, then die with <message>. Its .step-up marker
# stays for step-up --resume, and wait --lead tells the lead.
# STEP_UP_CLOSED: set once step_up has closed the old builder (and by a resume, whose step-up did).
# STEP_UP_WHY: the <why> step_up_die logged, which step_up_note names. STEP_UP_RESUMING: set by
# step_up_resume, whose failure step_up_failed notes no conductor (the lead ran it).
STEP_UP_LOGGED=""; STEP_UP_CLOSED=""; STEP_UP_WHY=""; STEP_UP_RESUMING=""
step_up_die() {
  STEP_UP_LOGGED=1; STEP_UP_WHY="$2"; record_event step-up:failed "$1" "ok ($2)"
  die "$3"
}

# start_rung <slug> — start the rung <slug>'s .step-up marker names (<trigger> <from> <to> <role>, and a
# stalled one's bg= test= sign=),
# once the old builder is closed: refuse while the worktree holds a git step it left unfinished (an
# index.lock, a merge, rebase, cherry-pick or revert) or with origin's default branch unread, write
# handover_brief beside the marker (with the step-up's findings.md, when it has one), start <role> on <to> in the worktree with it, then log escalate
# `ok (<trigger>: <from> -> <to>)`, with the marker's bg= test= sign= in its tail, drop the marker and send the /goal its caller's goal_preflight made. start_agent runs with errexit on, so a
# step that fails stops it with that step's own message; then the marker stays and the message says
# to run step-up --resume. The rung has started only once its brief is taken up: an agent start_agent
# recorded before deliver_prompt failed is closed and loses its agents.tsv line, so a resume starts it
# afresh and the rung is on record once.
start_rung() {
  local slug="$1" f="${BOARD}/stories/$1.md" prompt="${PROJECT_DIR}/.swarm/briefs/$1.md" trigger from to role src names epic n rc wt gd p base since errf err late goal="${PREFLIGHT_GOAL}"
  local reads=() rest
  read -r trigger from to role rest < "${prompt%.md}.step-up"
  read -r -a reads <<< "${rest}"
  src="$(repo_dir "$(fm "${f}" repo)")" || die "step-up: ${slug}: ${src}"
  names="$(story_env "${f}")" || die "${names}"
  epic="$(fm "${f}" epic)"
  wt="$(worktree_for "${src}" "${slug}")"
  gd="$(git -C "${wt}" rev-parse --absolute-git-dir)" || step_up_die "${slug}" "worktree unreadable" "step-up: ${slug}: git cannot read the worktree ${wt}; once that is fixed, run swarm.sh step-up --resume ${slug}"
  for p in index.lock MERGE_HEAD rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD; do
    [[ ! -e "${gd}/${p}" ]] \
      || step_up_die "${slug}" "git step unfinished: ${p}" "step-up: ${slug}'s ${from} builder is closed, but its worktree ${wt} holds ${gd}/${p}, a git step left unfinished: finish or abort it there, then run swarm.sh step-up --resume ${slug}"
  done
  base="$(base_for "${src}")" \
    || step_up_die "${slug}" "default branch unread" "step-up: ${slug}'s ${from} builder is closed, but origin's default branch could not be read (see above); once it can, run swarm.sh step-up --resume ${slug}"
  handover_brief "${slug}" "${src}" "${base}" "${trigger}" "${from}" "${to}" \
    "$( [[ ! -f "${prompt%.md}.findings.md" ]] || echo "${prompt%.md}.findings.md")" > "${prompt}"
  n="$(wc -l < "${AGENTS_LOG}")"; n=$((n)); since="$(date +%s)"   # before the brief, for send_goal
  # start_agent's stderr goes out as it comes, and a copy tells rung_late whether the brief may have
  # gone out. The copy is read and removed at once, and on a signal before that (step_up's EXIT trap
  # still runs on that exit, 128 + the signal's number).
  errf="$(mktemp)" || step_up_die "${slug}" "mktemp failed" "step-up: ${slug}'s ${from} builder is closed, but mktemp failed, so no ${to} builder was started; run swarm.sh step-up --resume ${slug}"
  # shellcheck disable=SC2064 # expand now: errf is local
  { trap "rm -f '${errf}'; exit 129" HUP; trap "rm -f '${errf}'; exit 130" INT; trap "rm -f '${errf}'; exit 143" TERM; }
  set +e
  { (set -e; start_agent "${epic:-${slug}}" "${slug}" "${wt}" "${role}" "${prompt}" "${slug}" "${names}" "${to}") 2>&1 1>&3 \
      | { tee "${errf}" >&2 || cat >/dev/null; }; rc=${PIPESTATUS[0]}; } 3>&1
  err="$(cat "${errf}")"; rm -f "${errf}"; trap - HUP INT TERM
  set -e
  if { [[ ${rc} -ne 0 ]] || [[ "${err}" == *"herdr did not show the turn start"* ]]; } \
    && awk -F'\t' -v n="${n}" -v a="$(agent_name "${slug}")" 'NR > n && $3 == a { f = 1 } END { exit !f }' "${AGENTS_LOG}"; then
    # Recorded, but its brief may not have been taken up (start_agent failed, or herdr sent it once and
    # deliver_prompt only warned): a slow starter may only need longer than its window, so it is read
    # once more (rung_late) before anything is closed.
    late=0; rung_late "${slug}" "${to}" "${err}" || late=$?
    if [[ ${late} -eq 0 ]]; then
      rc=0
      echo "step-up: ${slug}'s ${to} builder took up its brief after all"
    elif [[ ${late} -eq 2 ]]; then
      step_up_die "${slug}" "start unclear" "step-up: ${slug}'s ${from} builder is closed, and herdr could not say whether the ${to} builder took up its brief; its pane is kept: look at it (herdr agent read $(agent_name "${slug}")) before resuming with swarm.sh step-up --resume ${slug}"
    else
      # Its brief was not taken up: closed (it would sit idle with no brief), and not on record
      # until a resume starts it. A pane already gone is no reason to stop.
      rc=1; shut_agent "${slug}" >/dev/null 2>&1 || true
      if [[ -n "${CLOSE_PANE_KEPT:-}" ]]; then echo "step-up: ${slug}'s ${to} builder's pane could not be closed: look at it (herdr agent read $(agent_name "${slug}")) before resuming; the resume retires an idle agent there and refuses one that works or waits" >&2
      else echo "step-up: ${slug}'s ${to} builder is closed" >&2; fi
      # Its line goes under the lock record_agent appends under, held from the read to the replace, so
      # a line another conductor records meanwhile is kept.
      state_lock "${AGENTS_LOG}.lock"
      { awk -F'\t' -v n="${n}" -v a="$(agent_name "${slug}")" 'NR <= n || $3 != a' "${AGENTS_LOG}" > "${AGENTS_LOG}.tmp" \
          && mv "${AGENTS_LOG}.tmp" "${AGENTS_LOG}"; } || echo "step-up: could not take ${slug}'s unstarted ${to} builder off ${AGENTS_LOG}" >&2
      rm -f "${AGENTS_LOG}.tmp"; rmdir "${AGENTS_LOG}.lock"
    fi
  fi
  [[ ${rc} -eq 0 ]] \
    || step_up_die "${slug}" "start failed" "step-up: ${slug}'s ${from} builder is closed, but the ${to} builder did not start (see above); its worktree, branch and brief are kept: once that is fixed, run swarm.sh step-up --resume ${slug}"
  # The rung runs: from here nothing is a failed step-up (step_up_failed's trap).
  trap - EXIT
  rm -f "${prompt%.md}.step-up" "${prompt%.md}.findings.md"
  record_event escalate "${slug}" "ok (${trigger}: ${from} -> ${to})" "${reads[@]+"${reads[@]}"}"
  echo "stepped up: ${slug} from ${from} to ${to} (${role}), in ${wt}"
  [[ -n "${goal}" ]] || return 0
  printf '%s\n' "${goal}" > "${prompt%.md}.goal.md"
  # A /goal that does not set is said on its own: the step-up stands.
  set +e
  (set -e; send_goal "${slug}" "${prompt%.md}.goal.md" brief "${since}")
  rc=$?
  set -e
  [[ ${rc} -eq 0 ]] || echo "swarm: ${slug}: stepped up, and its ${to} builder runs, but its /goal did not set (see above): send ${prompt%.md}.goal.md as its /goal by hand" >&2
}

# rung_late <slug> <model> <err> [who] — when start_agent's stderr <err> says the brief may have gone out
# (the tries review_start_failed reads as unclear) and the agent was not blocked on a question before
# it, warn that <slug>'s new <model> builder has not shown it took up its brief, and read it by its
# pane once more over SLOW_PROMPT_TIMEOUT_MS (prompt_settle, against a fresh agent: idle, no turn).
# Succeeds when that read finds it working, blocked or past a turn; fails on any other <err>, with no
# pane (gone), or when it is still idle with no turn, and start_rung closes it. Returns 2 when the read
# is unsure (herdr gave no status twice in a row), and start_rung keeps the pane. [who] names the caller
# in its messages: step-up (start_rung's), or restart (restart_settle's), whose pane is never closed here.
rung_late() {
  # shellcheck disable=SC2034 # prompt_settle reads SETTLE_READS
  local SETTLE_READS=$((SLOW_PROMPT_TIMEOUT_MS / 5000)) pane v who="${4:-step-up}"
  case "$3" in
    *agent_blocked*) return 1 ;;
    *"may or may not have the brief"*|*"herdr sent it the brief"*|*"could not be read"*) ;;
    *) return 1 ;;
  esac
  pane="$(agent_field "$(agent_name "$1")" pane_id)"
  [[ -n "${pane}" ]] || return 1
  echo "${who}: warning: $1's $2 builder has not shown it took up its brief; its pane is kept and read again for $((SLOW_PROMPT_TIMEOUT_MS / 1000))s$([[ "${who}" != step-up ]] || echo " before it is closed")" >&2
  v="$(prompt_settle "${pane}" idle -)"
  case "${v}" in
    taken) return 0 ;;
    "again idle") return 1 ;;
  esac
  echo "${who}: $1's $2 builder: ${v#unsure }" >&2
  return 2
}

# step_up_failed <slug> — the exit trap of step_up once the old builder is closed, and of step_up_resume
# once it rewrote the marker: on a failure (the .step-up marker kept for step-up --resume, which also
# keeps step_due from trying this build again), log its step-up:failed line unless step_up_die did, the
# why being the die's message (DIE_FILE, set for a logged command) or the exit status, and note the
# story's conductor (step_up_note) unless it is a resume. A _step-up (STEP_UP_AUTO) then says so and
# exits STEP_UP_PARTWAY; any other keeps its status. One that stopped inside the close with the pane
# still open (STEP_UP_CLOSED unset, CLOSE_PANE_KEPT set) is a refusal: its marker goes, and nothing is
# logged or noted.
step_up_failed() {
  local rc=$? why=""
  [[ ${rc} != 0 ]] || return 0
  if [[ -z "${STEP_UP_CLOSED}" && -n "${CLOSE_PANE_KEPT:-}" ]]; then
    # Stopped inside the close with the pane still open (close_panes died on it): a refusal, as when
    # step_up sees CLOSE_PANE_KEPT itself. The marker goes, and so does the PARTWAY status.
    rm -f "${PROJECT_DIR}/.swarm/briefs/$1.step-up" "${PROJECT_DIR}/.swarm/briefs/$1.findings.md"
    return 0
  fi
  [[ -z "${DIE_FILE}" ]] || read -r why 2>/dev/null < "${DIE_FILE}" || true
  [[ -n "${STEP_UP_LOGGED}" ]] || record_event step-up:failed "$1" "ok (${why:-exit ${rc}})"
  # Outside any set -e: a note that fails must not change how the step-up ends. A resume is the
  # lead's own, so it notes no one.
  [[ -n "${STEP_UP_RESUMING}" ]] || step_up_note "$1" "${STEP_UP_WHY:-${why:-exit ${rc}}}" || true
  [[ -n "${STEP_UP_AUTO:-}" ]] || return 0
  echo "step-up failed: $1 stopped after its builder was closed. wait --lead tells the lead, whose exit is swarm.sh step-up --resume $1 once the cause is fixed; leave $1 alone: do not close, retry, tell or list it"
  exit "${STEP_UP_PARTWAY}"
}

# STEP_UP_NOTE_WAIT: how long step_up_note's read of herdr's list and its tell may take together
# (within): it runs under the story's step-up lock, so a hung herdr must not hold that, or the
# caller's tell, for longer.
STEP_UP_NOTE_WAIT=120

# step_up_note <slug> <why> — step_up_failed's note to <slug>'s conductor (conduct-<epic>, or the
# backlog's with no epic), so one whose builder a review agent's tell stepped up hears of it: the
# story, <why> and the resume. Sent as `swarm.sh tell <conductor> note`, so it is logged as tell:note
# and note_wake prompts one whose turn has ended, all within STEP_UP_NOTE_WAIT seconds. Nothing is sent
# with no conductor of this project listed, or one that wrote its report (nobody reads its inbox). A
# note that fails or runs out of time, or a list that cannot be read, is warned of.
step_up_note() {
  local e name note listed left rc=0 end=$((SECONDS + STEP_UP_NOTE_WAIT))
  e="$(fm "${BOARD}/stories/$1.md" epic 2>/dev/null)" || e=""
  if [[ -n "${e}" ]]; then name="$(conductor_name "${e}")"; else name="$(conductor_name backlog)"; fi
  [[ ! -f "$(conductor_report "${name}")" ]] || return 0
  # agent_field's test, on a list read within the deadline: a pane this project opened holds the name.
  listed="$(within "${STEP_UP_NOTE_WAIT}" herdr agent list </dev/null 2>/dev/null | SWARM_NAME="${name}" SWARM_PANES="$(own_panes)" \
    json "any(a.get('name') == e['SWARM_NAME'] and a.get('pane_id') in e['SWARM_PANES'].split() for a in d['result']['agents'])" 2>/dev/null)" || listed=""
  if [[ "${listed}" != True ]]; then
    # False is a list with no such conductor; anything else is a read that failed or ran out of time.
    [[ "${listed}" == False ]] || echo "warning: ${name} was not noted that $1's step-up failed (herdr's agent list could not be read); wait --lead still tells the lead" >&2
    return 0
  fi
  left=$((end - SECONDS))
  note="$(mktemp "${TMPDIR:-/tmp}/swarm-note.XXXXXX")" || { echo "warning: ${name} was not noted that $1's step-up failed (mktemp failed)" >&2; return 0; }
  printf '%s\n\n%s\n' "swarm.sh sent this note itself, on a failed step-up; the lead may not know of it yet." \
    "$1's step-up failed after its builder was closed ($2). wait --lead tells the lead, whose exit is swarm.sh step-up --resume $1 once the cause is fixed. Leave $1 alone: do not close, retry, tell or list it." > "${note}"
  # Its stdout to stderr: a caller reads this step-up's stdout (wait_agent's ladder_step).
  SWARM_PROJECT="${PROJECT_DIR}" within "${left}" "${BASH}" "${SWARM_HOME}/bin/swarm.sh" tell "${name}" note "${note}" >&2 || rc=$?
  rm -f "${note}"
  (( rc != 142 )) || { echo "warning: ${name} was not noted that $1's step-up failed (it took over ${STEP_UP_NOTE_WAIT}s); wait --lead still tells the lead" >&2; return 0; }
  [[ ${rc} -eq 0 ]] || echo "warning: ${name} was not noted that $1's step-up failed (exit ${rc}); wait --lead still tells the lead" >&2
}

# restart_build <slug> — `restart`: start a started story's builder again once herdr no longer lists it
# (no_agent_exit's exit for a ready story), in its worktree and on its branch, in the tab build_story puts
# it in. Its newest agents.tsv line gives its role, kind, model and session. When the resume command
# resume_file wrote for that Claude session (RESUME_DIR/<session>.argv) names a session that took a
# prompt (restart_session, restart_took), it reopens that session (restart_resume); else it starts a
# fresh builder in that role on that model, the one builder_model reads, with handover_brief
# (restart_fresh). It holds the story's step-up lock (step_lock) throughout, so no second restart and
# no step-up starts a builder beside it. Refused, with nothing started, for a story that is not ready,
# not of a kind an agent builds (kind: lead, as every escalated story is), held (held_for:, or held_by:
# until its parents merge), or has a .step-up marker (step-up --resume starts that rung); with no
# worktree, one holding a git step left unfinished, one not on story/<slug>, or no builder in
# agents.tsv; while herdr lists its builder, or cannot list its agents; when a PR on story/<slug> has
# merged or is set to auto-merge; while its lock is held; and when its read of herdr's list or of the PRs
# fails or takes over SWARM_RESTART_READ_WAIT seconds (default HERDR_LIST_WAIT). It logs its own `restart <slug> ok
# (<how>)` line (main logs only a failure), which build_started and review_round never read.
restart_build() {
  local slug="$1" f="${BOARD}/stories/$1.md" src wt gd p name listed role kind model session resume names tab url prs
  local lock="${PROJECT_DIR}/.swarm/locks/step-up-$1" wait="${SWARM_RESTART_READ_WAIT:-${HERDR_LIST_WAIT}}"
  [[ "${slug}" =~ ^[a-z0-9-]+$ && -f "${f}" ]] || die "restart: no story ${f} (swarm.sh restart <slug>)"
  step_lock "${lock}" || die "restart: a step-up, restart or top-rung hold of ${slug} is running (it holds ${lock}); nothing was started"
  # shellcheck disable=SC2064 # expand now: the lock is local
  trap "rm -rf '${lock}'" EXIT
  [[ "$(fm "${f}" status)" == ready ]] || die "restart: ${slug} is not status: ready; nothing was started"
  agent_kind "$(fm "${f}" kind)" \
    || die "restart: ${slug} is kind: $(fm "${f}" kind), which the lead runs, not an agent (an escalated story is too); nothing was started"
  [[ -z "$(get_fm "${f}" held_for)" ]] \
    || die "restart: ${slug} is held for the lead (held_for: $(get_fm "${f}" held_for)): reset or drop it; nothing was started"
  [[ -z "$(get_fm "${f}" held_by)" ]] \
    || die "restart: ${slug} is held until its parents merge (held_by:), and is reviewed again, never built again; nothing was started"
  [[ ! -e "${PROJECT_DIR}/.swarm/briefs/${slug}.step-up" ]] \
    || die "restart: ${slug} has a step-up waiting to start (.swarm/briefs/${slug}.step-up): run swarm.sh step-up --resume ${slug} instead; nothing was started"
  src="$(repo_dir "$(fm "${f}" repo)")" || die "restart: ${slug}: ${src}"
  wt="$(worktree_for "${src}" "${slug}")"
  [[ -d "${wt}" ]] || die "restart: ${slug} has no worktree at ${wt}, so there is no build to start again; nothing was started"
  gd="$(git -C "${wt}" rev-parse --absolute-git-dir 2>/dev/null)" || die "restart: git cannot read ${slug}'s worktree ${wt}; nothing was started"
  for p in index.lock MERGE_HEAD rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD; do
    [[ ! -e "${gd}/${p}" ]] \
      || die "restart: ${slug}'s worktree ${wt} holds ${gd}/${p}, a git step left unfinished: finish or abort it there first; nothing was started"
  done
  [[ "$(git -C "${wt}" symbolic-ref -q --short HEAD 2>/dev/null)" == "story/${slug}" ]] \
    || die "restart: ${slug}'s worktree ${wt} is not on story/${slug} (switched or detached): put it back there first; nothing was started"
  name="$(agent_name "${slug}")"
  # Both reads below are bounded (within): a hung herdr or gh would keep the lock from every step-up.
  listed="$(within "${wait}" herdr agent list </dev/null 2>/dev/null | SWARM_NAME="${name}" json "any(a.get('name') == e['SWARM_NAME'] for a in d['result']['agents'])" 2>/dev/null)" || listed=""
  [[ "${listed}" != True ]] || die "restart: ${slug}'s builder ${name} is still listed (herdr agent list): wait on it or tell it; nothing was started"
  [[ "${listed}" == False ]] \
    || die "restart: herdr could not list its agents (it failed or took over ${wait}s), so whether ${slug}'s builder is there is not known; nothing was started"
  read -r role kind model session <<< "$(awk -F'\t' -v n="${name}" '$3 == n { l = $2 " " $4 " " $5 " " $7 } END { print l }' "${AGENTS_LOG}" 2>/dev/null || true)"
  [[ -n "${session}" ]] || die "restart: ${slug} has no builder in ${AGENTS_LOG}, so there is no build to start again; nothing was started"
  # As step_up_story reads them: a merged or auto-merging PR is a build that is done. STEP_PR, the open PR
  # or empty, is what handover_brief names.
  if ! url="$(git -C "${src}" remote get-url origin 2>/dev/null)" \
     || ! prs="$(within "${wait}" gh pr list -R "${url}" --head "story/${slug}" --state all --json state,url,autoMergeRequest </dev/null 2>/dev/null)" \
     || ! STEP_PR="$(json "next((p['url'] for p in d if p['state'] == 'OPEN'), '')" <<< "${prs}" 2>/dev/null)"; then
    die "restart: could not list the PRs on story/${slug} (git or gh failed, or gh took over ${wait}s); nothing was started"
  fi
  [[ "$(json "any(p['state'] == 'MERGED' or (p['state'] == 'OPEN' and p.get('autoMergeRequest')) for p in d)" <<< "${prs}")" == False ]] \
    || die "restart: a PR on story/${slug} has merged or is set to auto-merge, so its build is done; nothing was started"
  names="$(story_env "${f}")" || die "${names}"
  tab="$(fm "${f}" epic)"; tab="${tab:-${slug}}"   # as build_story: the epic's tab, or a one-off's own
  resume=""
  if [[ "${kind}" == claude && "${session}" != - && -f "${RESUME_DIR}/${session}.argv" ]]; then
    resume="$(restart_session "${session}")" \
      || die "restart: ${RESUME_DIR}/${session}.argv is not a resume command swarm.sh wrote (python3 -I <wrapper> claude --resume <session> ...); nothing was started"
    # A builder whose brief never landed has nothing to resume: it starts fresh, with the brief.
    restart_took "${resume}" || resume=""
  fi
  if [[ -n "${resume}" ]]; then
    restart_resume "${slug}" "${tab}" "${wt}" "${session} ${resume}" "${names}"
    record_event restart "${slug}" "ok (resumed session ${resume})"
    echo "restarted: ${slug}, its session ${resume} reopened in ${wt}"
  else
    restart_fresh "${slug}" "${tab}" "${src}" "${role} ${model}" "${names}"
  fi
}

# restart_session <session> — the session <session>'s resume command (resume_file's .argv) resumes: its
# --resume argument, which hooks/agent-state.sh moves to the new session after a /clear. Fails when the
# file is not the shape resume_file writes.
restart_session() {
  local a=() l
  while IFS= read -r l; do a+=("${l}"); done < "${RESUME_DIR}/$1.argv"
  [[ ${#a[@]} -ge 6 && "${a[0]} ${a[1]}" == "python3 -I" && "${a[2]}" == "${RESUME_DIR}/$1.py" \
     && "${a[3]} ${a[4]}" == "claude --resume" && "${a[5]}" =~ ^[A-Za-z0-9-]+$ ]] || return 1
  echo "${a[5]}"
}

# restart_took <session> — succeed when Claude session <session>'s main log (report.py's session_log)
# holds a user prompt (panes.py's is_prompt, not a Task subagent's entry): its brief, or a later one,
# landed. Fails with no log.
restart_took() {
  SWARM_LIB="${SWARM_HOME}/bin/lib" python3 -I -c '
import json, os, sys
sys.path.insert(0, os.environ["SWARM_LIB"]); from panes import is_prompt; from report import session_log
path = session_log(sys.argv[1], sys.argv[2])
for l in (open(path, errors="replace") if path else ()):
    try:
        d = json.loads(l)
    except ValueError:
        continue
    if isinstance(d, dict) and d.get("type") == "user" and not d.get("isSidechain") and is_prompt(d):
        sys.exit(0)
sys.exit(1)' "${CLAUDE_PROJECTS}" "$1" 2>/dev/null
}

# restart_resume <slug> <tab> <wt> "<session> <resume>" <names> — reopen <slug>'s builder's Claude session
# <resume> (restart_session of its agents.tsv <session>) in a new pane in <tab>, at <wt>, with the flags
# of its resume command (resume_file's .argv), as upgrade_one starts one again (one retry of herdr's
# agent start, as start_agent, but none in a fresh pane: a shell that does not take the environment
# dies), report that command to herdr as start_agent does, and tell the builder why.
restart_resume() {
  local name argv a resume=() flags=() pane out seq msg try session id
  read -r session id <<< "$4"
  name="$(agent_name "$1")"; argv="${RESUME_DIR}/${session}.argv"
  while IFS= read -r a; do resume+=("${a}"); done < "${argv}"
  flags=("${resume[@]:6}")
  require_trusted "$3"   # a fresh start's start_agent checks it, for a Claude builder only
  # shellcheck disable=SC2119 # takes no argument here
  require_claude
  require_herdr_version
  rm -f "${PANE_DIR:?}/${name}"   # the last holder's pane record (pane_check), as start_agent
  pane="$(next_pane "$2" "$3" "$1")"
  local -x SWARM_RESUME="${argv}"
  a="$(agent_env_names)"
  clean_env "${pane}" "${name}" "${a}${a:+ }$5"
  for try in 1 2; do
    out="$(herdr agent start "${name}" --kind claude --pane "${pane}" --timeout 60000 -- --resume "${id}" ${flags[@]+"${flags[@]}"} 2>&1)" && break
    if [[ ${try} -eq 2 ]]; then
      herdr pane close "${pane}" >/dev/null 2>&1 || out="${out} (and pane ${pane} could not be closed: close it by hand)"
      die "restart: herdr could not reopen ${name}'s session ${id}: ${out}"
    fi
    nap 3
  done
  # As start_agent: without it a herdr restart would resume the session without its guards, and the
  # builder has done nothing in this pane yet, so a refusal closes it.
  seq="$(python3 -I -c 'import time; print(time.time_ns())')" || seq=""
  if [[ -z "${seq}" ]] || ! out="$(herdr pane report-agent "${pane}" --source swarm --agent claude --state idle --seq "${seq}" \
      --agent-session-id "${id}" -- "${resume[@]}" 2>&1)"; then
    herdr pane close "${pane}" >/dev/null 2>&1 || out="${out} (and pane ${pane} could not be closed: close it by hand)"
    die "restart: herdr did not take ${name}'s resume command, so a herdr restart would drop its guards; its pane is closed: ${out:-could not read the clock (python3)}"
  fi
  msg="$(mktemp "${TMPDIR:-/tmp}/swarm-restart.XXXXXX")" || die "restart: ${name}'s session ${id} is open in pane ${pane}, but it could not be told to carry on: tell it (swarm.sh tell $1 resume <file>)"
  printf '%s\n' "swarm.sh restart reopened this session in a new pane: your last one was gone, and with it any background command, subagent or monitor you had running (a wait-pr, a codex-review). You are in the same worktree, ${3}, on story/$1. Check git status and your PR, start again any wait you still need, and carry on where you stopped." > "${msg}"
  restart_run deliver_prompt "${name}" "${msg}" "${pane}"
  rm -f "${msg}"
  [[ ${RESTART_RC} -eq 0 ]] || die "restart: ${name}'s session ${id} is open in pane ${pane}, but it was not told to carry on: tell it (swarm.sh tell $1 resume <file>)"
  restart_settle "$1" "$(builder_model "$1")" \
    "it may not have taken up the prompt to carry on: read it (herdr agent read ${name}) and, if it sits idle, tell it to carry on (swarm.sh tell $1 resume <file>)"
}

# RESTART_ERR, RESTART_RC: restart_run's copy of its command's stderr, and its exit status.
RESTART_ERR=""; RESTART_RC=0

# restart_run <cmd>... — run <cmd>... in a subshell with errexit on (never in an || or if, where bash
# drops it), its stderr shown as it comes and kept in RESTART_ERR, its status in RESTART_RC, as
# start_rung runs start_agent. Its temp file goes on a signal too.
restart_run() {
  local f
  f="$(mktemp "${TMPDIR:-/tmp}/swarm-restart-err.XXXXXX")" || die "restart: mktemp failed, so nothing was started"
  # shellcheck disable=SC2064 # expand now: f is local
  { trap "rm -f '${f}'; exit 129" HUP; trap "rm -f '${f}'; exit 130" INT; trap "rm -f '${f}'; exit 143" TERM; }
  set +e
  { (set -e; "$@") 2>&1 1>&3 | { tee "${f}" >&2 || cat >/dev/null; }; RESTART_RC=${PIPESTATUS[0]}; } 3>&1
  set -e
  RESTART_ERR="$(cat "${f}")"; rm -f "${f}"; trap - HUP INT TERM
}

# restart_settle <slug> <model> <what to do> — after a start or prompt that exited 0, when RESTART_ERR
# is deliver_prompt's warning that herdr sent the prompt but did not show the turn start, read the
# builder once more (rung_late, as start_rung does). Unless it took the prompt up after all, die with
# <what to do>, its pane kept: herdr lists it, so no no-agent line would ever name it.
restart_settle() {
  local late=0
  [[ "${RESTART_ERR}" == *"herdr did not show the turn start"* ]] || return 0
  rung_late "$1" "$2" "${RESTART_ERR}" restart || late=$?
  if [[ ${late} -eq 0 ]]; then echo "restart: $1's builder took up its prompt after all"; return 0; fi
  die "restart: $1's builder runs in its pane, but herdr does not show that it took up its prompt$([[ ${late} -ne 2 ]] || echo " (herdr could not say)"); $3"
}

# restart_fresh <slug> <tab> <src> "<role> <model>" <names> — start a fresh builder for <slug> in <role> on
# <model> in its worktree, in <tab>, with handover_brief (trigger restart, from and to both <model>), as
# start_rung starts a rung, then log the restart line and send the /goal goal_preflight made.
restart_fresh() {
  local slug="$1" role model wt base prompt="${PROJECT_DIR}/.swarm/briefs/$1.md" since goal rc=0
  read -r role model <<< "$4"
  (policy "${role}") >/dev/null 2>&1 \
    || die "restart: ${slug}'s last build ran as ${role}, a role nothing starts now; nothing was started"
  wt="$(worktree_for "$3" "${slug}")"
  goal_preflight "${slug}" "$3"; goal="${PREFLIGHT_GOAL}"
  base="$(base_for "$3")" || die "restart: origin's default branch could not be read (see above); nothing was started"
  mkdir -p "${prompt%/*}"
  handover_brief "${slug}" "$3" "${base}" restart "${model}" "${model}" > "${prompt}"
  since="$(date +%s)"   # before the brief, for send_goal
  # start_agent said why it failed. Once it has recorded the builder, its pane is kept: it may lack its
  # brief. restart_run keeps its errexit (start_rung's form) and its stderr for restart_settle.
  restart_run start_agent "$2" "${slug}" "${wt}" "${role}" "${prompt}" "${slug}" "$5" "${model}"
  [[ ${RESTART_RC} -eq 0 ]] \
    || die "restart: ${slug}'s fresh builder did not start cleanly (see above); if herdr lists it, read it (herdr agent read $(agent_name "${slug}")) and, with no brief taken up, send ${prompt} (swarm.sh tell ${slug} nudge ${prompt})"
  restart_settle "${slug}" "${model}" \
    "read it (herdr agent read $(agent_name "${slug}")) and, if it sits idle with no brief, send it (swarm.sh tell ${slug} nudge ${prompt})"
  record_event restart "${slug}" "ok (fresh on ${model}: no session to resume)"
  echo "restarted: ${slug}, a fresh ${role} builder on ${model} in ${wt}"
  [[ -n "${goal}" ]] || return 0
  printf '%s\n' "${goal}" > "${prompt%.md}.goal.md"
  set +e
  (set -e; send_goal "${slug}" "${prompt%.md}.goal.md" brief "${since}")
  rc=$?
  set -e
  [[ ${rc} -eq 0 ]] || echo "swarm: ${slug}: restarted, and its builder runs, but its /goal did not set (see above): send ${prompt%.md}.goal.md as its /goal by hand" >&2
}

# builder_model <slug> — the model of the newest agents.tsv line for <slug>'s builder.
builder_model() {
  awk -F'\t' -v n="$(agent_name "$1")" '$3 == n { m = $5 } END { print m }' "${AGENTS_LOG}" 2>/dev/null || true
}

# build_started <slug> — when <slug>'s current build started: its newest ok story or escalate line,
# or ok agent line (a builder started by hand, whose target is the agent name); empty with none.
build_started() {
  awk -F'\t' -v s="$1" -v n="$(agent_name "$1")" "${EVENT_OUTCOME_AWK}"'
    outcome($5) ~ /^ok/ && ((($2 == "story" || $2 == "escalate") && $3 == s) || ($2 == "agent" && $3 == n)) { t = $1 }
    END { print t }' "${EVENTS_LOG}" 2>/dev/null || true
}

# ladder_step <slug> <trigger> [findings] — step_up <slug> for a trigger swarm.sh saw itself (close,
# wait --stall, tell, watch, a review pane's wait-pr): 0 when it stepped up; STEP_UP_PARTWAY when it failed after closing the
# builder, and the caller stops; STEP_UP_BUSY when another step-up or a restart of it holds the lock, and the caller
# touches nothing; any other status when nothing was closed (a refusal, said on stderr,
# or a failure before the close), and the caller carries on as before. One step-up of a story at a
# time, under its lock (step_lock); inside it step_due reads the build again, and with nothing due
# (another step-up came first, no rung above, a partway failure this build) it runs nothing and returns 1.
# The _step-up it runs inherits its environment, so a stalled one gets its caller's SWARM_STALL_READS
# (wait_agent's).
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
  awk -F'\t' -v s="$1" -v t="$2" "${EVENT_OUTCOME_AWK}"'
    $2 == "escalate" && $3 == s && $1 >= t && outcome($5) ~ /^ok/ { f = 1 } END { exit !f }' "${EVENTS_LOG}" 2>/dev/null
}

# handover_brief <slug> <src> <base> <trigger> <from> <to> [findings] — the next rung's brief, or with
# trigger restart a fresh builder's on the same model (restart_fresh): the builder's
# brief (story_brief), then why the build was handed on, the PR body's Models: line, for a story
# stacked on parents with open PRs build_story's Merge after note, the story as the board holds it
# (the last builder may have deleted it from the worktree already), the diff from handover_from
# (committed, uncommitted and untracked; its first HANDOVER_DIFF_LINES lines, in a fence longer than
# any run of backticks in it), the review agent's review file when it is of this HEAD (a pass or a
# stop: its findings to fix go to the builder by tell, in a .round.md file), [findings], the file of
# the tell the step-up took the place of, and the story PR's failing checks.
handover_brief() {
  local wt models from parents open="" merged="" p prs="" stack="" tree="" out rc diff fence='```' pr checks head findings="${PROJECT_DIR}/.swarm/reviews/$1.md" reviewed found
  wt="$(worktree_for "$2" "$1")"
  parents="$(stacked_parents "$1")"
  for p in ${parents//,/ }; do
    if pr="$(open_pr "$2" "${p}")"; then prs+="${prs:+ }${pr}"; open+="${open:+ }${p}"
    elif merged_pr "$2" "${p}"; then merged+="${merged:+ }${p}"; fi
  done
  from="$(handover_from "${wt}" "$2" "$3" "${open}")" || from="origin/$3"
  if [[ -n "${prs}" ]]; then
    stack=$'\n\n'"This story is stacked on ${open}: open your PR against \`$3\` all the same, with \`Merge after ${prs}\` in its body. The diff below starts at their branches, so their commits are not in it."
  elif [[ -n "${merged}" ]]; then
    # A parent's PR merged, squashed most often, so its commits are on the base under other ids: the
    # diff is of origin/<base> to this branch as if the base were merged in (merge-tree's tree), then
    # what is not committed. A merge that conflicts (merge-tree exits 1, its tree full of markers)
    # keeps the merge-base diff, and says so.
    out="$(git -C "${wt}" merge-tree --write-tree "origin/$3" HEAD 2>/dev/null)" && rc=0 || rc=$?
    if [[ ${rc} -eq 0 && "${out%%$'\n'*}" =~ ^[0-9a-f]{40,64}$ ]]; then
      tree="${out%%$'\n'*}"; from="origin/$3"
      stack=$'\n\n'"This story was stacked on ${merged}, whose PRs have merged: merge \`origin/$3\` into your branch before you push, so its PR shows only this story's work. The diff below is against \`origin/$3\` as if you had."
    else
      stack=$'\n\n'"This story was stacked on ${merged}, whose PRs have merged, and merging \`origin/$3\` into your branch conflicts: merge it in and resolve that before you push. The diff below is from the merge-base with \`origin/$3\`, so it holds their commits too."
    fi
  fi
  # Every model agents.tsv has building this story, in order, then this one.
  models="$({ awk -F'\t' -v n="$(agent_name "$1")" '$3 == n { print $5 }' "${AGENTS_LOG}" 2>/dev/null; echo "$6"; } | awk '!seen[$0]++' | paste -sd, - | sed 's/,/, /g')"
  # head stops reading at the cap, so git stops too: a writer it cut off dies of SIGPIPE (128 + 13),
  # which ends the untracked loop; git diff --no-index exits 1 for every file that differs. With
  # pipefail that SIGPIPE fails the pipeline, so || true. git's warnings stay out of the diff.
  diff="$( { if [[ -n "${tree}" ]]; then git -C "${wt}" diff "${from}" "${tree}"; git -C "${wt}" diff HEAD; else git -C "${wt}" diff "${from}"; fi
             git -C "${wt}" ls-files -z --others --exclude-standard | while IFS= read -r -d '' p; do
               git -C "${wt}" diff --no-index -- /dev/null "${p}" || (( $? < 128 )) || break
             done
           } 2>/dev/null | head -n "${HANDOVER_DIFF_LINES}" || true)"
  while [[ "${diff}" == *"${fence}"* ]]; do fence+='`'; done   # loose-match: ok any run of backticks in the diff
  head="$(git -C "${wt}" rev-parse HEAD)"
  reviewed="$(sed -n 's/^head: *//p' "${findings}" 2>/dev/null | head -n 1 || true)"   # no findings file: none
  if [[ ! -f "${findings}" ]]; then found="No review findings on file."
  elif [[ "${reviewed}" == "${head}" ]]; then found="$(cat "${findings}")"
  else found="The last review (${findings}) was of ${reviewed:-an unnamed head}, not this branch's HEAD ${head}, so its findings are not pasted here: they may be fixed already. Read it, and check each one before you act on it."; fi
  pr="${STEP_PR}"   # step_up_story's list: gh read it, so empty is no open PR
  if [[ -z "${pr}" ]]; then
    checks="No open PR on story/$1."
  else
    # gh pr checks exits 1 when a check failed and 8 while one is pending, printing them all the same;
    # with no failing line printed, its exit and error tell none failing, no checks and a gh error apart.
    out="$(gh pr checks "${pr}" --json name,bucket,link --jq '.[] | select(.bucket == "fail") | "- \(.name): \(.link)"' </dev/null 2>&1)" && rc=0 || rc=$?
    checks="$(grep '^- ' <<< "${out}" || true)"
    if [[ -z "${checks}" ]]; then
      case "${rc}:${out}" in
        0:*|8:*) checks="None failing on ${pr}." ;;
        *"no checks reported"*) checks="No checks reported on ${pr}." ;;
        *) checks="gh could not list ${pr}'s checks: run \`gh pr checks ${pr}\`." ;;
      esac
    fi
  fi
  story_brief "$1" "$2" "$3"
  cat <<EOF

## Handover

You take this story over from a builder on $5, $(if [[ "$4" == restart ]]; then echo "started again on $6 by swarm.sh restart because its pane was gone and it left no session to resume"; else echo "stepped up to you on $6 because $(step_trigger "$4")"; fi).
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
$(if [[ -n "${7:-}" ]]; then printf '\nThese findings were being sent to the last builder when it was stepped up:\n\n'; cat "$7"; fi)

### Failing checks

${checks}
EOF
}

# merged_pr <repo-dir> <slug> — true when a PR on story/<slug> in the repo's origin has merged.
merged_pr() {
  local url
  url="$(git -C "$1" remote get-url origin 2>/dev/null)" || return 1
  [[ "$(gh pr list -R "${url}" --head "story/$2" --state merged --json number --jq length </dev/null 2>/dev/null)" =~ ^[1-9] ]]
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

# top_rung <slug> — with escalate_ladder set, <slug>'s builder is on or above the ladder's top rung: on
# one of LADDER_MODELS with no rung above it (ladder_next), as an escalate_after Fable build is with a
# ladder that tops out lower (sonnet,opus), so no step-up is left.
top_rung() {
  local m
  [[ -n "${CFG_escalate_ladder:-}" ]] || return 1
  m="$(builder_model "$1")"
  model_rank "${m}" >/dev/null && ! ladder_next "${m}" >/dev/null
}

# top_rung_since <slug> — when top-rung findings rounds count from: the newer of build_started and an
# ok reset of <slug>, so a builder kept through the lead's reset gets fresh rounds.
top_rung_since() {
  awk -F'\t' -v s="$1" -v t="$(build_started "$1")" "${EVENT_OUTCOME_AWK}"'
    $2 ~ /^reset/ && $3 == s && index(outcome($5), "ok") == 1 && $1 > t { t = $1 }
    END { print t }' "${EVENTS_LOG}" 2>/dev/null || true
}

# top_rung_hold <slug> <findings> <round> — tell_agent's hold of a build on or above the ladder's top
# rung (top_rung) drawing findings round <round> (TOP_RUNG_FINDINGS or more) there. Under the story's
# step-up lock (ladder_step's), so two tells never both hold it: a story held already (escalated_from:,
# whatever its status) is refused, and it is held (top_rung_story) only where a step-up could run
# (step_up_story: ready, an agent's kind, no held_by:, a worktree, no PR merged or set to auto-merge, gh
# able to list them). The caller runs it with set +e and outside any condition, so the set -e in its
# subshell holds (bash ignores set -e under ! or ||). 0 when held; non-zero when nothing was held (said on
# stderr), and the findings go as usual. A failure after lead_block ran dies: the story is the lead's
# already, so its findings are never sent.
top_rung_hold() {
  local lock="${PROJECT_DIR}/.swarm/locks/step-up-$1" rc
  step_lock "${lock}" || die "tell: $1 was not told: a step-up, restart or hold of it is running; wait on it, then tell it"
  if [[ -n "$(get_fm "${BOARD}/stories/$1.md" escalated_from)" ]]; then
    rm -rf "${lock}"; die "tell: $1 was not told: it is held for the lead already (escalated_from:); the lead decides it"
  fi
  (set -e; step_up_story "$1"; top_rung_story "$1" "$2" "$3")
  rc=$?
  rm -rf "${lock}"
  [[ ${rc} != 0 ]] || return 0
  [[ ! -e "$(escalated_file "$1")" && -z "$(get_fm "${BOARD}/stories/$1.md" escalated_from)" ]] \
    || die "tell: $1 was not told: its top-rung hold failed partway (see above), after its lead block was written, so it is kind: lead without all of its hold (held_for: top-rung, a held line); list it for the lead"
  echo "swarm: tell: $1 was not held for the lead (see above), so its findings go as usual" >&2
  return "${rc}"
}

# top_rung_story <slug> <findings> <round> — after step_up_story (STEP_PRS, STEP_PR, STEP_SRC), hold the
# story for the lead as held_story does (held_for: top-rung, logged held; reset lifts it, leaves attempts:
# as it is, and is not the story's one reset), with <findings> in its block and kept in
# .swarm/briefs/<slug>.held-findings.md (unless they are that file), which reset leaves, for the lead to
# send after it. The builder, its worktree and PR are kept, so the block says to close them before a drop.
# The review ends there: it writes review-finished <slug> ok with verdict=held and round=, review_round's,
# the round whose findings were held.
top_rung_story() {
  local kept="${PROJECT_DIR}/.swarm/briefs/$1.held-findings.md" wt m
  m="$(builder_model "$1")"; wt="$(worktree_for "${STEP_SRC}" "$1")"
  [[ "$2" -ef "${kept}" ]] || { mkdir -p "${kept%/*}" && cp "$2" "${kept}"; } \
    || die "$1: could not keep its findings in ${kept}, so the story is left as it was"
  lead_block "$1" "**Held (top-rung).** Its builder on ${m}, on or above the ladder's top rung, drew review findings round $3 there, so they were not sent and no step-up is left. The builder and its PR are kept, and no attempt was counted. No agent builds this story until the lead decides, then tells the user what it chose and why:"$'\n\n'"- Narrow the scope to something that fails closed, split the story, or accept the PR with the findings filed as follow-up stories. Then lift the hold: run \`swarm.sh reset $1 <reason>\`, which puts its kind back and leaves \`attempts:\` as it is (lifting a hold is not the story's one reset), and send the kept builder the findings it still needs: \`swarm.sh tell $1 findings ${kept}\` (reset leaves that file)."$'\n'"- Or drop it. A drop leaves what this hold kept, so close that first: the builder with \`swarm.sh close $1\` (a held story counts nothing; with goal on, give a cause such as \`stalled\`), ${STEP_PR:+its open PR with \`gh pr close ${STEP_PR} --delete-branch\`, }and its worktree and branch with \`git -C ${STEP_SRC} worktree remove ${wt} && git -C ${STEP_SRC} branch -D story/$1\`. Then run \`swarm.sh drop $1 <reason>\`, which takes this story off the board, and commit the change in a board PR."$'\n\n'"The findings that were not sent (kept in ${kept}):"$'\n\n'"$(cat "$2")" "${STEP_PRS}" >/dev/null
  set_fm "${BOARD}/stories/$1.md" held_for top-rung
  record_event held "$1" "ok (top-rung: findings round $3 on ${m})"
  record_event review-finished "$1" ok "round=$(review_round "$1")" verdict=held
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
# retired), and none of its PRs merged or is open with auto-merge set (else it fails with
# BUILD_MERGING). With CLOSE_DROP set, a story in review or a held child (blocked, held_by:), or one whose builder is closed, will do
# while a PR on story/<name> is open, so a build a bare close kept (keep_build) can be dropped. With merge = agent a close
# that comes before the board is pulled, or while the merge waits on auto-merge, finds the story still
# ready, so only the PR tells. One gh call answers both; when it fails, nothing is counted or cleared,
# and stderr says so.
BUILD_MERGING=3
failed_build() {
  local slug="$1" f="${BOARD}/stories/$1.md" src url prs merging st need_open=""
  [[ "${slug}" =~ ^[a-z0-9-]+$ && -f "${f}" ]] || return 1
  st="$(fm "${f}" status)"
  # A held child (blocked, held_by:) is one a bare close kept, as review holds it.
  [[ "${st}" == ready || ( -n "${CLOSE_DROP}" && ( "${st}" == review || ( "${st}" == blocked && -n "$(get_fm "${f}" held_by)" ) ) ) ]] || return 1
  [[ "${st}" == ready ]] || need_open=1
  case "$(fm "${f}" kind)" in ""|code|docs|chore) ;; *) return 1 ;; esac
  if [[ -z "$(agent_field "$(agent_name "${slug}")" pane_id)" ]]; then
    [[ -n "${CLOSE_DROP}" ]] || return 1
    need_open=1
  fi
  src="$(repo_dir "$(fm "${f}" repo)")" \
    || { echo "swarm: ${slug}: ${src}, so this close counts no failed build and clears nothing" >&2; return 1; }
  if ! url="$(git -C "${src}" remote get-url origin)" \
     || ! prs="$(gh pr list -R "${url}" --head "story/${slug}" --state all --json number,state,url,autoMergeRequest,headRefOid)" \
     || ! merging="$(json "any(p['state'] == 'MERGED' or (p['state'] == 'OPEN' and p.get('autoMergeRequest')) for p in d)" <<< "${prs}")"; then
    echo "swarm: ${slug}: could not list the PRs on story/${slug}, so this close counts no failed build and clears nothing" >&2
    return 1
  fi
  [[ "${merging}" == False ]] || return "${BUILD_MERGING}"
  [[ -z "${need_open}" || "$(json "any(p['state'] == 'OPEN' for p in d)" <<< "${prs}")" == True ]] || return 1
  printf '%s\n' "${prs}"
}

# clear_build <slug> <why> <prs> — clear a build away (a failed one, or one reconcile found merged or
# closed), so the next one starts fresh: in
# the story's repo, its worktree and story/<slug>; each of <prs> (failed_build's gh list) still open,
# closed unmerged with a comment saying <why> (the attempt, or the cause); then story/<slug> on origin. With
# CLOSE_DROP set (close --drop), each step that succeeds is printed as dropped:, with the head SHA of
# each branch (read before it goes) and each PR. A step that fails
# is said on stderr, and the rest still run. A held child (held_by:) loses the hold and its prs: line,
# so it no longer counts as open in touches_rows. A story a pulled commit took off the board is
# cleared in the repo its deleted copy names (fm_gone), and has no hold left to lose.
clear_build() {
  local slug="$1" b="story/$1" src wt url head sha
  src="$(repo_dir "$(fm_gone "${BOARD}/stories/$1.md" repo)")" || { echo "swarm: ${slug}: ${src}; nothing cleared" >&2; return 0; }
  wt="$(worktree_for "${src}" "${slug}")"
  if [[ -e "${wt}" ]]; then
    git -C "${src}" worktree remove --force "${wt}" || echo "swarm: ${slug}: could not remove ${wt}" >&2
    [[ -z "${CLOSE_DROP}" || -e "${wt}" ]] || echo "dropped: the worktree ${wt}"
  fi
  # A worktree whose directory went by hand is still registered, and would keep the branch.
  git -C "${src}" worktree prune || echo "swarm: ${slug}: could not prune ${src}'s worktrees" >&2
  if sha="$(git -C "${src}" rev-parse -q --verify "refs/heads/${b}")"; then
    if git -C "${src}" branch -q -D "${b}"; then
      [[ -z "${CLOSE_DROP}" ]] || echo "dropped: ${b} in ${src}, head ${sha}"
    else
      echo "swarm: ${slug}: could not delete ${b} in ${src}" >&2
    fi
  fi
  while read -r url head; do
    [[ -n "${url}" ]] || continue
    gh pr close "${url}" --comment "swarm.sh close: $2, so this PR is closed unmerged and the next build starts fresh." >/dev/null \
      || { echo "swarm: ${slug}: gh could not close ${url}" >&2; continue; }
    [[ -z "${CLOSE_DROP}" ]] || echo "dropped: ${url}, closed unmerged, head ${head:-unknown} (git push origin ${head:-<sha>}:refs/heads/${b} and reopen it to restore)"
  done < <(json "'\n'.join(p['url'] + ' ' + p.get('headRefOid', '') for p in d if p['state'] == 'OPEN')" <<< "${3:-[]}")
  if sha="$(git -C "${src}" ls-remote --exit-code origin "refs/heads/${b}" 2>/dev/null)"; then
    if git -C "${src}" push -q origin --delete "${b}"; then
      [[ -z "${CLOSE_DROP}" ]] || echo "dropped: ${b} on origin, head ${sha%%[[:space:]]*}"
    else
      echo "swarm: ${slug}: could not delete ${b} on origin" >&2
    fi
  fi
  [[ -f "${BOARD}/stories/$1.md" ]] || return 0
  # A held child's hold goes with its build, and so does the prs: line the hold kept; so does a kept: line.
  if [[ -n "$(get_fm "${BOARD}/stories/$1.md" held_by)" ]]; then
    state_set "${BOARD}/stories/$1.md" held_by "" prs ""
  fi
  [[ -z "$(get_fm "${BOARD}/stories/$1.md" kept)" ]] || state_set "${BOARD}/stories/$1.md" kept ""
}

# close_panes <name> — close <name>'s pane, or its tab when that was the tab's last pane. Only what
# .swarm/state records under exactly <name> is taken: its pane line, its tab records, and for a
# conductor its epic's (close_epic). A conductor's name closes its epic's tabs, with any story panes
# left in them, except a tab close_tabs keeps for a live agent; the conductor's own pane (own_pane)
# then closes alone. A conductor whose pane cannot be found while herdr gives no agent list, or could
# not be closed, is said, and fails; a builder whose pane could not be closed is said, and
# CLOSE_PANE_KEPT is set (close_pane). herdr's names stop at AGENT_NAME_MAX characters, so with
# nothing recorded under a name that long, a live agent herdr lists under its cut (cut_live) may be
# another's: nothing closes, CLOSE_REFUSED says why and CLOSE_PANE_KEPT is set, so nothing is counted,
# cleared or kept. With nothing recorded and nothing live under the cut, nothing closes, as for a
# pane closed by hand.
CLOSE_PANE_KEPT=""; CLOSE_REFUSED=""
close_panes() {
  local state pane own e="" live
  CLOSE_READ=""; CLOSE_PANE_KEPT=""; CLOSE_REFUSED=""
  for state in "${STATE_DIR}"/*; do
    [[ -f "${state}" ]] || continue
    pane="$(awk -v n="$1" 'NF > 1 && $2 == n { print $1; exit }' "${state}")"
    [[ -z "${pane}" ]] || { close_pane "${pane}" "$1" "${state}"; return; }
  done
  close_lists
  [[ "$(agent_name "$1")" != conduct-* ]] || e="$(close_epic "$1")"
  if [[ ${#1} -ge ${AGENT_NAME_MAX} ]] && ! has_records "$1" && { [[ -z "${e}" ]] || ! has_records "${e}"; }; then
    live="$(cut_live "$1")"
    if [[ -n "${live}" ]]; then
      CLOSE_REFUSED="close: nothing in .swarm/state is recorded as $1, and herdr lists $(agent_name "$1"), its first ${AGENT_NAME_MAX} characters, on pane ${live}, which may be another agent's that shares the cut, so nothing was closed, counted, cleared or kept: close by the full recorded name, or, if that pane is $1's, close it by hand (herdr pane close <pane>) and close $1 again"
      echo "swarm: ${CLOSE_REFUSED}" >&2; CLOSE_PANE_KEPT=1; return 0
    fi
  fi
  own="$(own_pane "$1" "${e}")"
  [[ -z "${e}" ]] || close_tabs "${e}" "${own}"
  close_tabs "$1" "${own}"
  [[ -z "${own}" ]] || close_pane "${own}" "$1" "" alone || true
  [[ -z "${CLOSE_PANE_KEPT}" ]] || die "close: $1's pane ${own} could not be closed, so it is still open"
  [[ -n "${own}" || -n "${CLOSE_AGENTS_OK}" || "$(agent_name "$1")" != conduct-* ]] \
    || die "close: herdr gave no agent list and no tab record names $1's pane, so it could not be found and is still open"
}

# has_records <label> — a tab record of <label>, or of its numbered overflow, is in .swarm/state.
has_records() {
  local s
  for s in "${STATE_DIR}/$1" "${STATE_DIR}/$1"-*; do
    [[ -f "${s}" ]] && label_record "${s}" "$1" && return 0
  done
  return 1
}

# close_epic <conductor> — the label of its epic's tabs, or nothing. It is the name without conduct-
# when a brief of that name exists (.swarm/briefs/<name>.md, whoever's: start_conductor's, or a
# builder's whose slug it is, as on main), when the name is not AGENT_NAME_MAX long, so not cut, or
# when the records hold no name under it. A cut that is the backlog conductor's (conductor_name
# backlog: AGENT_NAME_MAX long for a project directory name of 9 or more characters, its brief under
# conduct-backlog, so no record is under the name) is backlog's, as conduct_epic maps it. Else, when
# the records hold one name under the cut (cut_record), it is that one's epic if it is a conductor's:
# conduct-<epic> with its brief, and no story of that name, since a story's slug may start with
# conduct- too. Two names under the cut, or one that is no conductor's, give nothing: the cut is not
# this conductor's alone, and the name without conduct- may be a third epic's label. With two it says
# so on stderr, since the close goes on and closes no epic's tabs, and stdout is the label.
close_epic() {
  local full rc=0
  if [[ -f "${PROJECT_DIR}/.swarm/briefs/$1.md" || ${#1} -ne ${AGENT_NAME_MAX} ]]; then echo "${1#conduct-}"; return 0; fi
  [[ "$1" != "$(conductor_name backlog)" ]] || { echo backlog; return 0; }
  full="$(cut_record "$1")" || rc=$?
  if [[ ${rc} -eq 1 ]]; then echo "${1#conduct-}"
  elif [[ ${rc} -eq 0 && "${full}" == conduct-* && -f "${PROJECT_DIR}/.swarm/briefs/${full}.md" && ! -f "${BOARD}/stories/${full}.md" ]]; then
    echo "${full#conduct-}"
  elif [[ ${rc} -eq 2 ]]; then
    echo "swarm: close: $1 is the cut of more than one recorded name, so no epic's tabs were closed: close by the conductor's full name (conduct-<epic>)" >&2
  fi
}

# cut_live <name> — the panes this project recorded where herdr lists an agent under <name>'s agent
# name (CLOSE_AGENTS), comma-separated.
cut_live() {
  local p ours out=""
  ours="$(own_panes)"
  while read -r p; do
    # A here-string, not a pipe: grep -q stops at its match, and under pipefail own_panes' SIGPIPE would fail it.
    if [[ -n "${p}" ]] && grep -qxF -- "${p}" <<< "${ours}"; then out+="${out:+, }${p}"; fi
  done < <(awk -v n="$(agent_name "$1")" '$3 == n { print $1 }' <<< "${CLOSE_AGENTS}")
  printf '%s' "${out}"
}

# own_pane <name> [epic] — the pane this project's agent <name> holds. A conductor's (with its epic)
# is its tab records' line named conductor (<epic>'s and their numbered overflow's, or its own
# label's for the backlog), confirmed by herdr's pane list when herdr gave one, so a line a gone pane
# left is passed over. Else, for a name shorter than AGENT_NAME_MAX, it is herdr's (CLOSE_AGENTS)
# under that name, on a pane a tab record has: herdr holds a longer name only cut, which never says
# whose it is.
own_pane() {
  local p n s
  if [[ -n "${2:-}" ]]; then
    for s in "${STATE_DIR}/$2" "${STATE_DIR}/$2"-* "${STATE_DIR}/$1"; do
      [[ -f "${s}" ]] || continue
      label_record "${s}" "$2" || [[ "${s##*/}" == "$1" ]] || continue
      while read -r p n; do
        [[ "${n}" == conductor ]] || continue
        [[ -z "${CLOSE_PANES}" ]] || awk -v p="${p}" '$1 == p { f = 1 } END { exit !f }' <<< "${CLOSE_PANES}" || continue
        echo "${p}"; return 0
      done < "${s}"
    done
  fi
  [[ ${#1} -lt ${AGENT_NAME_MAX} ]] || return 0
  p="$(awk -v n="$(agent_name "$1")" '$3 == n { print $1; exit }' <<< "${CLOSE_AGENTS}")"
  # A here-string, not a pipe: grep -q stops at its match, and under pipefail own_panes' SIGPIPE would fail it.
  if [[ -n "${p}" ]] && grep -qxF -- "${p}" <<< "$(own_panes)"; then echo "${p}"; fi
}

# close_pane <pane> <name> [tab-record] [alone] — close <pane> and drop it from its tab record (found
# when not given), or close that record's own tab (close_tab, never close_tabs' label sweep, which
# takes sibling and overflow tabs) when it is the record's last pane, unless alone is given; when that
# tab is kept for a live agent herdr has in it besides, or herdr has no tab of that label, <pane>
# closes alone. Fails when no tab record has it. When herdr could not list that tab or close the pane,
# the pane and its record are kept, that is said, CLOSE_PANE_KEPT is set for the caller to act on,
# and it succeeds: under errexit a failure here would stop reconcile's loop over merged stories.
close_pane() {
  local state="${3:-}" id
  if [[ -z "${state}" ]]; then
    for state in "${STATE_DIR}"/*; do
      [[ -f "${state}" ]] && record_has "${state}" "$1" && break
      state=""
    done
  fi
  [[ -n "${state}" ]] || return 1
  if [[ -z "${4:-}" && $(wc -l < "${state}") -le 1 ]]; then
    if ! id="$(tab_ids "${state}")"; then
      echo "kept pane $2 ($1) in tab ${state##*/}: herdr could not list its workspace's tabs, so neither was checked nor closed"
      CLOSE_PANE_KEPT=1; return 0
    fi
    # With no herdr tab of that label there is none to close: the pane closes by itself below.
    [[ -z "${id}" ]] || close_tab "${state}" "${id}" "$1"
  fi
  [[ -f "${state}" ]] || return 0
  # Checked, not left to errexit: a caller's `|| true` turns that off here.
  if ! herdr pane close "$1" >/dev/null 2>&1; then
    echo "swarm: could not close pane $2 ($1): it is still open, and its tab record keeps it" >&2
    CLOSE_PANE_KEPT=1; return 0
  fi
  record_drop "${state}" "$1"
  echo "closed pane $2"
}

# label_record <tab-record> <label> — succeed when the record is <label>'s own or its numbered
# overflow's (<label>-2 ...), never a longer label's: epic ce-foo's, or a story backlog-x's, is not
# ce's or the backlog's.
label_record() {
  local r="${1#"${STATE_DIR}/$2"}"
  [[ "${1}" == "${STATE_DIR}/$2"* && ( -z "${r}" || "${r}" =~ ^-[0-9]+$ ) ]]   # loose-match: ok r, the rest after the prefix, is checked to be empty or -<n>
}

# record_has <tab-record> <pane> — succeed when the record has a line for <pane>.
record_has() { awk -v p="$2" 'NF <= 2 && $1 == p { f = 1 } END { exit !f }' "$1"; }

# record_drop <tab-record> <pane> — drop <pane>'s line from the record, and the record once it is empty.
record_drop() {
  awk -v p="$2" '!(NF <= 2 && $1 == p)' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
  [[ -s "$1" ]] || rm -f "$1"
}

# record_kept <tab-record> <pane> <name> <agent> — put a pane close_tabs kept in <tab-record>, its line
# moved from any other tab record, so the kept tab stays recorded; succeed when the record has it then.
# Only this project's: a pane in no record whose <agent> has no agents.tsv line here (a user's own
# session, another project's agent, one with no name) is kept open but never recorded, and fails.
record_kept() {
  local s ours=""
  record_has "$1" "$2" 2>/dev/null && return 0
  for s in "${STATE_DIR}"/*; do
    [[ -f "${s}" && "${s}" != "$1" && "${s}" != *.tmp ]] || continue
    record_has "${s}" "$2" || continue
    ours=1; record_drop "${s}" "$2"
  done
  if [[ -z "${ours}" ]]; then
    [[ -n "$4" && -f "${AGENTS_LOG}" ]] || return 1
    awk -F'\t' -v n="$4" '$3 == n { f = 1 } END { exit !f }' "${AGENTS_LOG}" || return 1
  fi
  echo "$2 $3" >> "$1"
}

# close_lists — what close's guard reads once per close (close_panes clears CLOSE_READ): herdr's
# panes as "<pane> <tab>" lines (CLOSE_PANES, empty when herdr gave none) and agents as "<pane>
# <status> <name>" lines, "-" for an agent with no name (CLOSE_AGENTS; CLOSE_AGENTS_OK is empty when
# herdr gave no agent list), Claude Code's list (CLOSE_CLAUDE, claude_agents' JSON or empty when it
# failed), the tab records' lines (CLOSE_RECORDS) and the names agents started under (CLOSE_STARTED,
# agents.tsv's). The open PRs (close_heads) and the records' full names (close_stories) are read
# when first asked for. herdr's status is the word for an agent no session answers for, as in
# read_state.
CLOSE_READ=""
close_lists() {
  [[ -z "${CLOSE_READ}" ]] || return 0
  CLOSE_READ=1
  CLOSE_PANES="$(herdr pane list 2>/dev/null </dev/null | json "'\n'.join('%s %s' % (p['pane_id'], p.get('tab_id') or '-') for p in d['result']['panes'])" 2>/dev/null)" || CLOSE_PANES=""
  CLOSE_AGENTS_OK=1
  CLOSE_AGENTS="$(herdr agent list 2>/dev/null </dev/null | json "'\n'.join('%s %s %s' % (a['pane_id'], a.get('agent_status') or 'unknown', a.get('name') or '-') for a in d['result']['agents'])" 2>/dev/null)" \
    || { CLOSE_AGENTS=""; CLOSE_AGENTS_OK=""; }
  CLOSE_CLAUDE="$(claude_agents </dev/null)" || CLOSE_CLAUDE=""
  CLOSE_RECORDS="$(cat "${STATE_DIR}"/* 2>/dev/null || true)"
  CLOSE_STARTED="$(awk -F'\t' 'NF == 7 { print $3 }' "${AGENTS_LOG}" 2>/dev/null || true)"
  CLOSE_HEADS=""; CLOSE_HEAD_SRCS=""; CLOSE_STORIES=""; CLOSE_STORIES_READ=""
}

# close_heads <repo-dir> — read the heads of the open PRs on the repo's origin into CLOSE_HEADS
# ("<repo-dir>\t<head>" lines), once per repo per close; fails (1) with no origin, which has no PR,
# and (2) when gh cannot tell.
close_heads() {
  local rc url heads
  rc="$(awk -F'\t' -v s="$1" '$1 == s { print $2; exit }' <<< "${CLOSE_HEAD_SRCS}")"
  if [[ -z "${rc}" ]]; then
    rc=0
    if ! url="$(git -C "$1" remote get-url origin 2>/dev/null)"; then rc=1
    # ponytail: 1000 open PRs per repo; page through gh api if a repo ever holds more.
    elif ! heads="$(gh pr list -R "${url}" --state open --limit 1000 --json headRefName --jq '.[].headRefName' </dev/null 2>/dev/null)"; then rc=2
    else CLOSE_HEADS+="$(awk -v s="$1" 'NF { print s "\t" $0 }' <<< "${heads}")"$'\n'; fi
    CLOSE_HEAD_SRCS+="$1"$'\t'"${rc}"$'\n'
  fi
  return "${rc}"
}

# close_stories — the full names the records hold (cut_names: the stories', the briefs' and the tab
# records' pane names) into CLOSE_STORIES, once per close, for cut_record to match each herdr name
# against: a long name's agent is known to herdr by its first AGENT_NAME_MAX characters (agent_name).
close_stories() {
  [[ -z "${CLOSE_STORIES_READ}" ]] || return 0
  CLOSE_STORIES_READ=1
  CLOSE_STORIES="$(cut_names)"
}

# live_agents <tab-ids> <tab-record> [pane] — set LIVE to each agent in a pane of those tabs, <pane>'s
# aside, that a tab close must not take, as "<pane>\t<name>\t<why>\t<herdr's name or ->" lines: the
# pane running this command (HERDR_PANE_ID), whatever is in it, since a review agent idles there while
# its own swarm.sh tell or merge runs in the background and steps the build up or reconciles; working
# or waiting (session_state, else herdr's status), its state unknown (herdr gave no agent list too)
# or any other not known to be idle or finished, its story's PR open on story/<name>
# (close_heads) or gh could not say, or, for a name agent_name may have cut, no story found: the
# records hold no name under it, or two (cut_record), or one that is no story's. The panes are
# herdr's (close_lists), since a pane moved in by hand closes with the tab and one moved out does
# not; the record's stand in when herdr lists none in those tabs. <name> is the record's
# (record_name), else that story's, else herdr's, else the pane. A recorded pane with no agent yet
# is kept (starting); an unrecorded one, or a story whose repo has no origin, has nothing to keep.
# It runs in close_tabs' own shell, so what close_heads and close_stories read lasts the close.
live_agents() {
  local panes pane st who name s f src rc
  LIVE=""
  # The ids space-separated (two tabs can share a label; close_tabs joins them), matched as " <id> ".
  panes="$(awk -v t=" $1 " 'index(t, " " $2 " ") { print $1 }' <<< "${CLOSE_PANES}")"
  [[ -n "${panes}" || ! -f "$2" ]] || panes="$(awk '{ print $1 }' "$2")"
  while read -r pane; do
    [[ -n "${pane}" && "${pane}" != "${3:-}" ]] || continue
    name="$(record_name "${pane}" "${CLOSE_RECORDS}")"
    if [[ "${pane}" == "${HERDR_PANE_ID:-}" ]]; then
      who="$(awk -v p="${pane}" '$1 == p && $3 != "-" { print $3; exit }' <<< "${CLOSE_AGENTS}")"
      live_line "${pane}" "${name:-${who:-${pane}}}" "the pane running this command" "${who:--}"; continue
    fi
    if [[ -z "${CLOSE_AGENTS_OK}" ]]; then live_line "${pane}" "${name:-${pane}}" "herdr gave no agent list, so its state is unknown" -; continue; fi
    read -r _ st who <<< "$(awk -v p="${pane}" '$1 == p { print; exit }' <<< "${CLOSE_AGENTS}")"
    if [[ -z "${st}" ]]; then
      # No agent in it: one a tab record has may be one still starting (next_pane records the pane
      # before start_agent's agent start), so it is kept; any other holds nothing to lose.
      ! awk -v p="${pane}" '$1 == p { f = 1 } END { exit !f }' <<< "${CLOSE_RECORDS}" \
        || live_line "${pane}" "${name:-${pane}}" "starting: no agent in it yet" -
      continue
    fi
    [[ "${who}" != - ]] || who=""
    if [[ -z "${name}" && ${#who} -eq ${AGENT_NAME_MAX} ]]; then
      close_stories
      # Only a story's: any other name (a review agent's brief) says nothing of what its agent holds.
      name="$(cut_record "${who}" "${CLOSE_STORIES}")" && [[ -f "${BOARD}/stories/${name}.md" ]] \
        || { live_line "${pane}" "${who}" "its story could not be found" "${who}"; continue; }
    fi
    name="${name:-${who:-${pane}}}"
    s=herdr; [[ -z "${who}" ]] || s="$(session_state "${who}" "${CLOSE_CLAUDE}" </dev/null)"
    # No session to ask, or Claude Code lists none live under the recorded id (gone: exited, or a new
    # session): herdr's status answers, so an agent herdr has working is kept.
    [[ "${s}" != herdr && "${s}" != gone ]] || s="herdr:${st}"
    case "${s}" in
      busy|herdr:working) live_line "${pane}" "${name}" working "${who:--}"; continue ;;
      waiting*|herdr:blocked) live_line "${pane}" "${name}" waiting "${who:--}"; continue ;;
      # Finished, as tell and free_agent_name read it.
      idle|herdr:idle|herdr:done) ;;
      *)
        # A retired builder is finished too: retire_agent renames it <slug>-done, a name no agent
        # started under, so agents.tsv has no line for it (a live builder whose slug ends in -done
        # was started under it). Any other state (herdr's starting or error, or one that could not
        # be read) is not known to be idle: kept.
        if [[ "${who}" =~ -done[0-9]*$ ]] && ! grep -qxF -- "${who}" <<< "${CLOSE_STARTED}"; then :
        elif [[ "${s}" == unknown || "${s}" == herdr:unknown ]]; then live_line "${pane}" "${name}" "its state could not be read" "${who:--}"; continue
        else live_line "${pane}" "${name}" "state ${s#herdr:}" "${who:--}"; continue; fi ;;
    esac
    f="${BOARD}/stories/${name}.md"
    [[ "${name}" =~ ^[a-z0-9-]+$ && -f "${f}" ]] || continue
    src="$(repo_dir "$(fm "${f}" repo)")" || { echo "swarm: ${name}: ${src}, so no PR of its was looked for" >&2; continue; }
    rc=0; close_heads "${src}" || rc=$?
    case ${rc} in
      0) ! grep -qxF -- "${src}"$'\t'"story/${name}" <<< "${CLOSE_HEADS}" || live_line "${pane}" "${name}" "PR open" "${who:--}" ;;
      2) live_line "${pane}" "${name}" "gh could not list its PRs" "${who:--}" ;;
    esac
  done <<< "${panes}"
}

# live_line <pane> <name> <why> <agent> — one line of LIVE.
live_line() { LIVE+="$1"$'\t'"$2"$'\t'"$3"$'\t'"$4"$'\n'; }

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

# CLOSE_IDLE_SECONDS: how long close_when_idle's waiter waits for a retired review agent's turn to end
# (a conductor's, and the lead's collect of it) once the command that started the wait has exited,
# before it leaves the pane open (under 30 minutes, so a stuck agent is not waited on for long). CLOSE_CMD_SECONDS: how long it waits for that command to exit
# first; a merge's own waits end well inside it. CLOSE_IDLE_POLL: how often it looks, in seconds.
# CLOSING_DIR holds each waiter's <name>.pid while it runs, and its output, <name>.log.
CLOSE_IDLE_SECONDS="${SWARM_CLOSE_IDLE_SECONDS:-1200}"
CLOSE_CMD_SECONDS=1200
CLOSE_IDLE_POLL="${SWARM_CLOSE_IDLE_POLL:-5}"
CLOSING_DIR="${PROJECT_DIR}/.swarm/closing"

# close_when_idle <name> <pane> — close <pane> once the command running now has exited, where closing
# it now would kill that command, and once <name>'s turn has ended. <name> is either herdr's name for
# review-<slug>, which merged_review just retired because that command (a swarm.sh merge in its pane,
# or its reconcile) runs there, or a conductor, conduct-<epic>, whose Finish PR a swarm.sh merge
# --board just landed (merge_pr), maybe from the conductor's own pane. So it starts the waiter,
# swarm.sh _close-when-idle (close_idle_wait), detached as review_restart starts its run: nohup, in a
# session of its own (setsid), so closing the pane does not end it, pinned to this project, and given
# $$, the swarm.sh process running now. Its output goes to CLOSING_DIR/<name>.log, never to this
# command's, so the agent's Bash call does not wait on it; its pid goes to CLOSING_DIR/<name>.pid.
# What it will do is said; a CLOSING_DIR it cannot make is said, and the pane stays open.
close_when_idle() {
  local how="close it with swarm.sh tidy --yes once it is done" when=" and its turn has ended"
  if [[ "$1" == conduct-* ]]; then
    how="close it with swarm.sh close $1 once it is idle"
    when=", its turn has ended and the lead has collected it (collect's swarm.sh close $1, refused or not)"
  fi
  mkdir -p "${CLOSING_DIR}" 2>/dev/null \
    || { echo "$1 stays open in pane $2: ${CLOSING_DIR} could not be made, so nothing waits to close it; ${how}"; return 0; }
  SWARM_PROJECT="${PROJECT_DIR}" nohup python3 -I -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
    "${BASH}" "${SWARM_HOME}/bin/swarm.sh" _close-when-idle "$1" "$2" "$$" </dev/null > "${CLOSING_DIR}/$1.log" 2>&1 &
  echo "$!" > "${CLOSING_DIR}/$1.pid"
  echo "$1 closes once this command has exited${when}; if that has not happened ${CLOSE_IDLE_SECONDS}s after this command exits, it is left open, with a close-when-idle line in .swarm/events.tsv"
}

# close_idle_wait <name> <pane> <pid> — swarm.sh _close-when-idle, close_when_idle's waiter. Every
# CLOSE_IDLE_POLL seconds, once <pid> has exited, it reads the tab record's name for <pane>: for a
# review agent the -done name retire_agent gave <name>, for a conductor (conduct-<epic>) the name
# start_agent records its pane under, conductor; anything else, and it stops with nothing closed (a
# tidy, a close or a deleted project took the pane first). Then it reads the agent's state:
# session_state's word for <name>'s session, or, where herdr answers for it (no session, or one Claude
# Code no longer lists), herdr's status for this project's agent under the recorded -done name, or
# <name> for a conductor (list_field over one herdr agent list; a list herdr fails to give reads as
# unknown, never as no agent). Idle, done, or no agent under that name any more: a review agent's pane
# closes (close_pane, which closes its tab too when the pane was the record's last). A conductor closes
# as collect's close closes it (shut_agent: its epic's tabs, its own pane, its session archived), but
# only once its report is there and the lead has collected it (report_collected tried: a swarm.sh close
# of it since the report, refused or not); until then it reads as uncollected, since closing it would
# take collect off next, which finds a conductor to collect by its pane. Either logs
# `close-when-idle <name> closed (pane <pane>)`. A pane herdr could not close is logged as
# `close-when-idle <name> left open: ...`. So is one whose agent is still not idle (or, for a
# conductor, not collected) CLOSE_IDLE_SECONDS after <pid> exited, naming its state, or whose <pid>
# still runs CLOSE_CMD_SECONDS after the waiter started: that pane stays open for tidy --yes, or a
# conductor for collect's close. On its way out it removes CLOSING_DIR/<name>.pid while that holds its
# own pid.
close_idle_wait() {
  local name="$1" pane="$2" pid="$3" who state agents end="" cap conductor="" agent how cmd="the command that retired it"
  [[ -n "${name}" && -n "${pane}" && "${pid}" =~ ^[0-9]+$ ]] || die "usage: swarm.sh _close-when-idle <name> <pane> <pid>"
  how="close its pane ${pane} with swarm.sh tidy --yes"
  [[ "${name}" != conduct-* ]] || { conductor=1; how="close it with swarm.sh close ${name}"; cmd="the merge that landed its Finish PR"; }
  cap=$((SECONDS + CLOSE_CMD_SECONDS))
  while :; do
    # Nothing is read while <pid> runs: close_when_idle writes the pid file before <pid> can exit.
    if kill -0 "${pid}" 2>/dev/null; then
      if (( SECONDS >= cap )); then
        record_event close-when-idle "${name}" "left open: ${cmd} (pid ${pid}) was still running ${CLOSE_CMD_SECONDS}s later; ${how} once it is done"
        break
      fi
    else
      [[ -n "${end}" ]] || end=$((SECONDS + CLOSE_IDLE_SECONDS))
      who="$(awk -v p="${pane}" 'NF == 2 && $1 == p { print $2 }' "${STATE_DIR}"/* 2>/dev/null | sort -u)" || who=""
      if [[ -n "${conductor}" && "${who}" != conductor ]]; then
        echo "pane ${pane} is no longer recorded as ${name}'s (its record says '${who}'), so nothing was closed"; break
      elif [[ -z "${conductor}" && "${who}" != "${name:0:27}-done" && "${who}" != "${name:0:26}-done"[2-9] ]]; then
        echo "pane ${pane} is no longer recorded as retired ${name} (its record says '${who}'), so nothing was closed"; break
      fi
      agent="${who}"; [[ -z "${conductor}" ]] || agent="${name}"
      state="$(session_state "${name}")"
      if [[ "${state}" == herdr || "${state}" == gone ]]; then
        if agents="$(herdr agent list 2>/dev/null)"; then
          state="herdr:$(list_field "${agent}" agent_status <<< "${agents}")"
        else state="herdr:unknown"; fi
      fi
      case "${state}" in
        idle|herdr:idle|herdr:done|herdr:)
          if [[ -n "${conductor}" ]] && ! report_collected "${name}" "$(conductor_report "${name}")" tried; then
            state=uncollected
          elif [[ -n "${conductor}" ]]; then
            # In a subshell, as merged_review closes one: close_panes dies on a pane it cannot find.
            if ( set -e; CLOSE_PANE_KEPT=""; shut_agent "${name}"; [[ -z "${CLOSE_PANE_KEPT}" ]] ); then
              record_event close-when-idle "${name}" "closed (pane ${pane})"
            else record_event close-when-idle "${name}" "left open: its pane ${pane} could not be closed (see .swarm/closing/${name}.log); ${how}"; fi
            break
          else
            CLOSE_PANE_KEPT=""
            close_pane "${pane}" "${who}" || { echo "pane ${pane} left its tab record while it was closed, so nothing was closed"; break; }
            if [[ -z "${CLOSE_PANE_KEPT}" ]]; then record_event close-when-idle "${name}" "closed (pane ${pane})"
            else record_event close-when-idle "${name}" "left open: herdr could not close its pane ${pane}; close it with swarm.sh tidy --yes"; fi
            break
          fi ;;
      esac
      if (( SECONDS >= end )); then
        if [[ "${state}" == uncollected ]]; then
          record_event close-when-idle "${name}" "left open: its report was still not collected ${CLOSE_IDLE_SECONDS}s after ${cmd} exited; collect it, and its close closes it"
        else
          record_event close-when-idle "${name}" "left open: it was still ${state#herdr:} ${CLOSE_IDLE_SECONDS}s after ${cmd} exited; ${how} once it is done"
        fi
        break
      fi
    fi
    sleep "${CLOSE_IDLE_POLL}"
  done
  [[ "$(cat "${CLOSING_DIR}/${name}.pid" 2>/dev/null)" != "$$" ]] || rm -f "${CLOSING_DIR}/${name}.pid"
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

# MERGE_RULE: the Claude Code permissions.allow rule that lets an agent run swarm.sh merge as the
# conductor's and the lead's briefs write it. Without one, Claude Code refuses an agent every merge
# (v0.28.0: the user merged 8 approved PRs by hand).
MERGE_RULE='Bash(swarm.sh merge *)'

# user_settings — the user's Claude Code settings file.
user_settings() { echo "${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/settings.json"; }

# claude_settings — the Claude Code settings files that can hold MERGE_RULE, one per line: the user's
# first, then the project's shared and local ones.
claude_settings() {
  user_settings
  echo "${PROJECT_DIR}/.claude/settings.json"
  echo "${PROJECT_DIR}/.claude/settings.local.json"
}

# merge_allowed — true when the permissions.allow lists of the claude_settings files, pooled, let
# through every form of swarm.sh merge an agent runs: --head and --board (a conductor), --release
# --head and the plain form (the lead), each on two PRs and SHAs of the project's GitHub origin (o/r
# with none), so a rule tied to one PR or SHA does not count.
# A rule is Bash(<command>), with * for any text and the older :* suffix. Bash alone, or a pattern of
# only *, does not count: agents run in auto mode, which sets such broad rules aside. It reads only
# those allow lists, so a deny or ask rule, or managed settings, can still block a merge it passes.
# It prints nothing (these files can hold tokens under env) and writes no file. A missing or broken
# file counts as no rule.
merge_allowed() {
  local origin
  origin="$(git -C "${PROJECT_DIR}" remote get-url origin 2>/dev/null)" || origin=""
  claude_settings | python3 -I -c '
import json, re, sys
m = re.search(r"github\.com[:/]+([^/]+)/([^/]+?)(?:\.git)?/*$", sys.argv[1])
prs = "https://github.com/%s/%s/pull/" % (m.groups() if m else ("o", "r"))
FORMS = ("--head {0} ", "--board ", "--release --head {0} ", "")
CMDS = ["swarm.sh merge %s%s%d" % (f.format(sha), prs, n) for sha, n in (("0123abc", 1), ("fedcba9", 98765)) for f in FORMS]
def allows(rule, cmd):
    m = re.fullmatch(r"Bash\((.*)\)", rule, re.S) if isinstance(rule, str) else None
    if not m:
        return False
    pat = m.group(1)[:-2] + "*" if m.group(1).endswith(":*") else m.group(1)
    if not pat.strip("*"):
        return False
    return re.fullmatch(".*".join(re.escape(p) for p in pat.split("*")), cmd, re.S) is not None
rules = []
for f in sys.stdin.read().splitlines():
    try:
        allow = json.load(open(f, encoding="utf-8"))["permissions"]["allow"]
    except (OSError, ValueError, LookupError, TypeError):
        continue
    rules += allow if isinstance(allow, list) else []
sys.exit(0 if all(any(allows(r, c) for r in rules) for c in CMDS) else 1)' "${origin}"
}

# AUTO_MODE_DONE — the user's word that auto mode's setup ran, the date swarm.sh init --auto-mode-done
# wrote. v0.28.0: the 'Teach auto mode' dialog and permission prompts froze builder panes for hours.
AUTO_MODE_DONE="${PROJECT_DIR}/.swarm/auto-mode-done"

# auto_mode_set_up — true when auto mode's setup has run: the user said so (AUTO_MODE_DONE), or the
# user's settings hold a non-empty autoMode.environment, the list /auto-mode-setup writes there. Claude
# Code offers the 'Teach auto mode' dialog only while that list, merged from the user's, flag and
# managed policy settings, is empty; it takes autoMode from no project settings file. This reads only
# the user's settings file, so a user whose org sets the list in managed settings runs
# init --auto-mode-done. It reads only that list, prints nothing and writes no file.
auto_mode_set_up() {
  [[ -f "${AUTO_MODE_DONE}" ]] && return
  python3 -I -c '
import json, sys
try:
    env = json.load(open(sys.argv[1], encoding="utf-8"))["autoMode"]["environment"]
except (OSError, ValueError, LookupError, TypeError):
    sys.exit(1)
sys.exit(0 if isinstance(env, list) and env else 1)' "$(user_settings)"
}

# auto_mode_done — swarm.sh init --auto-mode-done: record the user's word that auto mode's setup ran,
# today's date in AUTO_MODE_DONE, so init stops printing that step. With main's line for the command
# in .swarm/events.tsv, that is all it writes: nothing outside .swarm/.
auto_mode_done() {
  { mkdir -p "${PROJECT_DIR}/.swarm" && date +%F > "${AUTO_MODE_DONE}"; } || die "init: cannot write ${AUTO_MODE_DONE}"
  echo "recorded that auto mode's setup ran, in ${AUTO_MODE_DONE#"${PROJECT_DIR}/"}; init no longer prints that step"
}

# init_claude — the Claude Code steps only the user can take: when merge_allowed finds no rule, the
# step that adds MERGE_RULE to the user's settings, naming the files it read; until auto_mode_set_up,
# the step that runs /auto-mode-setup, and the command that records it ran.
init_claude() {
  local f user="" files=""
  if ! merge_allowed; then
    while IFS= read -r f; do
      [[ -n "${user}" ]] || user="${f}"
      files+="${files:+, }${f#"${PROJECT_DIR}/"}"
    done < <(claude_settings)
    echo "Claude Code's settings have no permissions.allow rule that lets swarm.sh merge run (read ${files})."
    echo "Your step: add \"${MERGE_RULE}\" to permissions.allow in ${user}. Under merge = agent, or an HLD that grants merge, Claude Code refuses every swarm.sh merge an agent runs without it, and you merge each PR by hand."
  fi
  auto_mode_set_up && return
  echo "Auto mode has not learned your environment: $(user_settings) has no autoMode.environment, and nobody ran swarm.sh init --auto-mode-done here."
  echo "Your step: run /auto-mode-setup once in claude, so no agent's pane stops on the 'Teach auto mode' dialog. Then run swarm.sh init --auto-mode-done here, and init stops printing this step."
}

# BOARD_BASE_PAST: the sha256 of each Board.base the plugin shipped before the current one (git log --
# templates/docs/Board.base), one per line. A board's Board.base that matches one is a template nobody
# edited, so init replaces it with the current one. When the template changes, add the outgoing
# version's sha256 here; init_test.sh checks every past version in git history is listed.
BOARD_BASE_PAST='2da305247898d622618058c62cd705560ea90b83ce9b225687e565080f255103
302798ca551553b5d24d68577a24630f5d31dd7b6b9d006c66981a0810d02d62
9956edaf77067f1c503bbc52572022998ba127a653c5960ce164a8a8fa6ed102
ec19a467c31c0b2b5a168b1aee132727d8a0e6d5b26d4780d913227d53a5b5f9'

# init_board_base <rel> — init's line for the board's Board.base, which exists (a dangling symlink too):
# replaced with the current template when it is a regular file, not a symlink, holding a past one nobody
# edited (BOARD_BASE_PAST); otherwise left, with how to compare when it is an edited file. A symlink is
# left as it is: replacing it would drop what the board linked to. A directory, a fifo or a file that
# cannot be read is left unread, since cmp or a hash would block on a fifo. The replacement is cp's copy
# into a directory of its own beside the file (mktemp -d), moved over the old one: a hard link to the old
# one keeps its bytes, no file beside it is written, and the new file has the mode cp gives init's other
# copies. Fails when it left the file; init stops when the replacement cannot be written.
init_board_base() {
  local have="${BOARD}/Board.base" want="${SWARM_HOME}/templates/docs/Board.base" sum="" dir=""
  if [[ -L "${have}" || ! -f "${have}" || ! -r "${have}" ]] || cmp -s "${have}" "${want}"; then
    echo "left   $1Board.base (it exists)"; return 1
  fi
  sum="$(python3 -I -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "${have}" 2>/dev/null)" \
    || { echo "left   $1Board.base (it exists)"; return 1; }
  if grep -qxF -- "${sum}" <<< "${BOARD_BASE_PAST}"; then
    { dir="$(mktemp -d "${have}.XXXXXX")" && cp "${want}" "${dir}/Board.base" && mv -f "${dir}/Board.base" "${have}"; } \
      || { [[ -z "${dir}" ]] || rm -rf "${dir}"; die "init: could not replace $1Board.base with the current template"; }
    rmdir "${dir}"
    echo "updated $1Board.base (an older template nobody edited, now the current one)"
    return
  fi
  echo "left   $1Board.base (edited): the template changed since; compare with diff $(printf '%q %q' "$1Board.base" "${want}")"
  return 1
}

# init_project — set the project up from the installed plugin, from its git root: the board templates
# (never over a file that exists, but for an unedited older Board.base, init_board_base), .claude/swarm/
# with a commented commit_trailers line, the .gitignore lines, a CI workflow and a pre-commit hook, then
# the Claude Code steps the user must take (init_claude). A second run changes nothing.
init_project() {
  local rel board f line n=0
  mkdir -p "${BOARD}" && BOARD="$(cd "${BOARD}" && pwd -P)"
  rel="$(board_rel)"
  while IFS= read -r f; do
    if [[ "${f}" == Board.base && ( -e "${BOARD}/${f}" || -L "${BOARD}/${f}" ) ]]; then
      if init_board_base "${rel}"; then n=$((n + 1)); fi
      continue
    fi
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
  init_claude
  echo "Last step: run claude once in ${PROJECT_DIR} and accept the folder trust prompt. Agents won't start until it is trusted."
}

# close_tabs <label> [pane] — close every tab this script opened under <label> and its numbered
# overflow (label_record; close_tab each), <pane>'s agent aside from the check. Every tab, with its herdr ids (tab_ids), is
# listed before any is kept or closed: keeping one can move a later one's last line out of its
# record, which then goes, and that tab is visited all the same. A tab whose ids herdr could not list
# is kept and said (kept_unlisted), and the rest go on.
CLOSE_ALL=""
close_tabs() {
  local state id tabs=""
  for state in "${STATE_DIR}/$1" "${STATE_DIR}/$1"-*; do
    [[ -f "${state}" ]] || continue
    label_record "${state}" "$1" || continue
    if id="$(tab_ids "${state}")"; then tabs+="${state}"$'\t'"${id}"$'\n'; else kept_unlisted "${state}"; fi
  done
  while IFS=$'\t' read -r -u 3 state id; do
    [[ -z "${state}" ]] || close_tab "${state}" "${id}" "${2:-}"
  done 3<<< "${tabs}"
}

# tab_ids <tab-record> — the ids of the herdr tabs labelled as the record is, space-separated (two
# tabs can carry one label: a run that reopened it); fails when herdr cannot list them. A tab may be
# in another workspace (a conductor's is its HLD's): the record's first pane id,
# "<workspace>:<pane>", says which.
tab_ids() {
  local ws
  ws="$(head -1 "$1")"; ws="${ws%%:*}"; ws="${ws:-${HERDR_WORKSPACE_ID}}"
  herdr tab list --workspace "${ws}" </dev/null 2>/dev/null | python3 -c "
import json,sys
print(' '.join(t['tab_id'] for t in json.load(sys.stdin)['result']['tabs'] if t.get('label') == sys.argv[1]))" "${1##*/}"
}

# kept_unlisted <tab-record> — say a tab whose ids herdr could not list is kept, unchecked.
kept_unlisted() { echo "kept tab ${1##*/}: herdr could not list its workspace's tabs, so it was neither checked nor closed"; }

# close_tab <tab-record> <tab-ids> [pane] — close the record's herdr tabs (<tab-ids>) and the record,
# archiving the session of each agent in it first. herdr's tab close asks nothing, so a tab that
# holds a live agent besides <pane>'s (live_agents) is kept, unless CLOSE_ALL is set (close --all):
# each such agent is printed as kept and, when it is this project's, joins the tab's record
# (record_kept), so a later close --all, and tidy, still find the tab once the panes recorded there
# close; one that is not is said to stay unrecorded. With no tab of that label, nothing is closed and
# the record goes. A tab herdr could not close keeps its record, and that is said.
close_tab() {
  local tab_label="${1##*/}" n p why a t
  if [[ -z "${CLOSE_ALL}" && -n "$2" ]]; then
    close_lists
    live_agents "$2" "$1" "${3:-}"
    if [[ -n "${LIVE}" ]]; then
      while IFS=$'\t' read -r p n why a; do
        if record_kept "$1" "${p}" "${n}" "${a#-}"; then echo "kept ${n} (${why}) in tab ${tab_label}: --all closes it too"
        else echo "kept ${n} (${why}) in tab ${tab_label}: no tab record of this project has it, so it stays unrecorded"; fi
      done <<< "${LIVE%$'\n'}"
      return 0
    fi
  fi
  if [[ -f "$1" ]]; then while read -r _ n; do [[ -z "${n}" ]] || archive_session "${n}"; done < "$1"; fi
  for t in $2; do
    # Checked, as close_pane checks its pane close: errexit would stop reconcile here, and a caller's
    # `|| true` would drop the record of a tab still open.
    if ! herdr tab close "${t}" >/dev/null 2>&1 </dev/null; then
      echo "swarm: could not close tab ${tab_label} (${t}): it is still open, and its record keeps it" >&2
      return 0
    fi
  done
  rm -f "$1"
  echo "closed ${tab_label}"
}

LEAD_POLL="${SWARM_LEAD_POLL:-30}"    # seconds between wait --lead's reads of the board, at least 1
# wait --lead's own files and lead_rename's record, kept out of STATE_DIR, whose files close reads
# as tab records.
LEAD_DIR="${PROJECT_DIR}/.swarm/lead"
LEAD_SEEN="${LEAD_DIR}/seen"          # the lead's queue at wait --lead's last read, kept across runs
# shellcheck disable=SC2034 # board.sh reads it
NEXT_SEEN="${LEAD_DIR}/next-seen"     # the no-agent: lines swarm.sh next named as its step (next_report)
LEAD_GREEN="${LEAD_DIR}/green"        # "<PR URL> <sha>" per head ci_gate passed, so it runs once per head
LEAD_PID="${LEAD_DIR}/pid"            # the running wait --lead, which a new one takes over from
LEAD_HEADS="${LEAD_DIR}/heads"        # each review item's verdict from the last heads pass (lead_heads)
LEAD_HEADS_EVERY="${SWARM_LEAD_HEADS_EVERY:-300}"   # seconds between heads passes, at least 1
LEAD_HEADS_AT=""                      # SECONDS at this run's last heads pass, empty before the first
# shellcheck disable=SC2034 # board.sh reads it
LEAD_HELD="${LEAD_DIR}/held"          # "<PR URL> <sha> <epoch>" per PR a protected hold names, read by the last heads pass (held_heads)
LEAD_KNOWN=""                         # "<PR URL> <sha>" lines this heads pass has read already, which heads_green takes
LEAD_WORKSPACE="${LEAD_DIR}/workspace"   # "<herdr workspace id>\t<its label, refused or kept>[\t<note>]" per line (lead_rename)
LEAD_HERDR_WAIT="${SWARM_LEAD_HERDR_WAIT:-5}"   # seconds each herdr call of lead_label may take (within)

# The plugin ships hooks/ beside bin/; a copy of bin/ alone (a test's stand-in plugin) has no lead.
# shellcheck source=hooks/lead-session.sh
[[ ! -f "${SWARM_HOME}/hooks/lead-session.sh" ]] || source "${SWARM_HOME}/hooks/lead-session.sh"

# lead_caller — true when the lead's own session runs this command, as hooks/lead-session.sh's
# lead_project tells it: no agent's environment (SWARM_AGENT, SWARM_GH_CALLER), a cwd outside any
# worktree, and a swarm project. False without the hook.
lead_caller() { declare -F lead_project > /dev/null && lead_project "${PWD}" > /dev/null; }

# lead_rename — the lead's first command in a herdr workspace labels that workspace and its tab
# `swarm-lead · <project_label>` (lead_label) and adds the workspace to LEAD_WORKSPACE, so a later
# command from any workspace there sends herdr nothing. It sends nothing outside herdr, without
# herdr's socket (HERDR_SOCKET_PATH, which the tests drop), from a swarm.sh another one runs
# (NESTED_CALL: dash --project and upgrade name other projects), with stderr going to /dev/null (the
# Stop hook's calls, through within: a refusal said there is lost), or from anyone but the lead: one
# lead_project walk from the cwd finds the project whose folder it is, which must be this one; a
# folder in no project (a board kept outside the repo) is the lead's of SWARM_PROJECT's (lead_caller).
# It runs before every command, so the record is read before any of that.
lead_rename() {
  local ws="${HERDR_WORKSPACE_ID:-}" id rest kept="" own
  [[ "${HERDR_ENV:-}" == 1 && -n "${ws}" && -z "${NESTED_CALL}" && -S "${HERDR_SOCKET_PATH:-}" ]] || return 0
  [[ ! /dev/stderr -ef /dev/null ]] || return 0
  if [[ -f "${LEAD_WORKSPACE}" ]]; then
    while IFS=$'\t' read -r id rest; do
      [[ "${id}" != "${ws}" ]] || return 0
      kept+="${id}"$'\t'"${rest}"$'\n'
    done < "${LEAD_WORKSPACE}"
  fi
  declare -F lead_project > /dev/null || return 0
  if own="$(SWARM_PROJECT="" lead_project "${PWD}")"; then [[ "${own}" == "${PROJECT_DIR}" ]] || return 0
  else lead_caller || return 0; fi
  # A subshell, so the bounded herdr ends with it.
  # shellcheck disable=SC2329 # called by name, by herdr_workspaces and lead_label
  ( herdr() { within "${LEAD_HERDR_WAIT}" herdr "$@"; }; lead_label "${ws}" "${kept}" )
}

# lead_label <workspace> <record lines> — lead_rename's herdr part. With no workspace or pane list,
# or a list without the workspace (herdr busy or restarting), it records nothing, so the next
# command tries again. A label swarm.sh gave another workspace (`<project> · <label>`, or an older
# swarm.sh's bare `backlog` or `<epic>`) is kept, so a lead opened in a conductor's workspace never
# takes it from the conductor; so is another project's lead's `swarm-lead · <name>`, told by the
# workspace's directory (neither in this project nor in its board), so a second lead opened there
# never takes the label the first lead's record holds. Otherwise the label is
# `swarm-lead · <project_label>`, where another lead's `swarm-lead · <name>` workspace counts as
# another dir's `<name> · ...` does, so the second lead of one dir name gets a label of its own. A
# lead workspace is this project's, not another lead's, when its dir is in the project or its board,
# or the record holds its id with the label it has now. A rename herdr refuses is said once on
# stderr, naming the record to delete to try again, and recorded all the same. The record is read
# again just before it is written, keeping only workspaces herdr still lists, and a lead workspace
# only while it has the label recorded for it (a refused or kept one stays whatever its label): two
# first commands at once both label, and only writes that land at the same instant lose a line,
# whose workspace its next command labels again.
lead_label() {
  local ws="$1" kept="$2" list others cur dir theirs="" label why="" note="" out rec tmp rc
  local prefix="swarm-lead${WORKSPACE_SEP}"   # the lead's label, before its project's (build.sh sets the separator)
  list="$(herdr_workspaces)" || return 0
  cur="$(W="${ws}" awk -F'\t' '$1 == ENVIRON["W"] { print "+" $2 "\t" $3; exit }' <<< "${list}")"
  [[ -n "${cur}" ]] || return 0
  dir="${cur#*$'\t'}"; cur="${cur#+}"; cur="${cur%%$'\t'*}"
  if [[ "${cur}" == "${prefix}"* ]]; then   # loose-match: ok a lead's label is the prefix, then its project's
    # Another project's lead's when its directory is in neither this project nor its board; with no
    # directory known, it is taken as this lead's own.
    [[ -z "${dir}" || "${dir}" == "${PROJECT_DIR}" || "${dir}" == "${PROJECT_DIR}/"* || "${dir}" == "${BOARD}" || "${dir}" == "${BOARD}/"* ]] || theirs="another project's lead"
  elif [[ "${cur}" == *"${WORKSPACE_SEP}"* || "${cur}" == backlog || ( -n "${cur}" && "${cur}" == "${cur##*/}" && -f "${BOARD}/epics/${cur}.md" ) ]]; then   # loose-match: ok any other label with ` · ` is a conductor's or its agents'
    theirs="a conductor or its agents"
  fi
  if [[ -n "${theirs}" ]]; then
    rec=kept; label="${cur}"
    echo "swarm: the lead runs in ${cur}, a workspace swarm.sh labelled for ${theirs}, so it keeps that label" >&2
  else
    others="$(P="${prefix}" S="${WORKSPACE_SEP}" W="${ws}" R="${kept}" D="${PROJECT_DIR}" B="${BOARD}" awk -F'\t' -v OFS='\t' '
      function own(c) { return c == ENVIRON["D"] || index(c, ENVIRON["D"] "/") == 1 || c == ENVIRON["B"] || index(c, ENVIRON["B"] "/") == 1 }
      BEGIN { n = split(ENVIRON["R"], r, "\n"); for (i = 1; i <= n; i++) if (split(r[i], f, "\t") > 1) rec[f[1]] = f[2] }
      index($2, ENVIRON["P"]) == 1 && $1 != ENVIRON["W"] && !($1 in rec && rec[$1] == $2) && !own($3) {
        $2 = substr($2, length(ENVIRON["P"]) + 1) ENVIRON["S"] "lead"; $3 = "-" }
      { print }' <<< "${list}")"
    label="${prefix}$(project_label "${others}")"; rec="${label}"
    # A call cut off (within's 142) is no answer from herdr: nothing is recorded, so the next command
    # sends both renames again.
    rc=0; out="$(herdr workspace rename "${ws}" "${label}" 2>&1 > /dev/null < /dev/null)" || rc=$?
    (( rc != 142 )) || return 0
    if (( rc != 0 )); then
      rec=refused; why="herdr would not label the lead's workspace ${ws} ${label} (${out%%$'\n'*})"
    elif [[ -n "${HERDR_TAB_ID:-}" ]]; then
      rc=0; out="$(herdr tab rename "${HERDR_TAB_ID}" "${label}" 2>&1 > /dev/null < /dev/null)" || rc=$?
      (( rc != 142 )) || return 0
      (( rc == 0 )) || { note="tab refused"; why="herdr labelled the lead's workspace ${label} but would not label its tab ${HERDR_TAB_ID} (${out%%$'\n'*})"; }
    fi
    [[ -z "${why}" ]] || echo "swarm: ${why}; swarm.sh will not try again in this workspace until you delete ${LEAD_WORKSPACE}" >&2
    [[ -z "${note}" ]] || rec+=$'\t'"${note}"
  fi
  mkdir -p "${LEAD_DIR}" 2>/dev/null && tmp="$(mktemp "${LEAD_WORKSPACE}.XXXXXX" 2>/dev/null)" || return 0
  if {
    [[ ! -f "${LEAD_WORKSPACE}" ]] || P="${prefix}" L="${list}" W="${ws}" awk -F'\t' '
      BEGIN { n = split(ENVIRON["L"], l, "\n"); for (i = 1; i <= n; i++) if (split(l[i], f, "\t") > 1) cur[f[1]] = f[2] }
      $1 != ENVIRON["W"] && ($1 in cur) && (index($2, ENVIRON["P"]) != 1 || $2 == cur[$1])' "${LEAD_WORKSPACE}"
    printf '%s\t%s\n' "${ws}" "${rec}"
  } > "${tmp}" 2>/dev/null; then mv -f "${tmp}" "${LEAD_WORKSPACE}" 2>/dev/null || rm -f "${tmp}"
  else rm -f "${tmp}"; fi
}

# heads_green <pr-url>... — 0 when there is at least one PR and every one's head is green, 1 when one is
# not or a URL is not a PR, 2 when none is red but gh or ci_gate could not read one. ci_gate head is
# skipped for a head LEAD_GREEN holds, setting LEAD_CACHED, unless LEAD_FRESH is set; each green head
# goes to LEAD_GREEN.new. A red or pending head is read again each time: a re-run can turn it green
# with no new SHA. LEAD_RED is "<url> <head>" for the red or pending head it stopped at, else empty. A
# head LEAD_KNOWN holds is taken from it, not read again.
heads_green() {
  local url repo head rc=0 g
  LEAD_CACHED=""; LEAD_RED=""
  [[ $# -gt 0 ]] || return 1
  for url in "$@"; do
    [[ "${url}" =~ ^https://github\.com/([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)/pull/([0-9]+)$ ]] || return 1
    repo="${BASH_REMATCH[1]}"
    head="${LEAD_KNOWN#*$'\n'"${url} "}"   # loose-match: ok quoted, a whole "<url> " line start
    if [[ "${head}" != "${LEAD_KNOWN}" ]]; then head="${head%%$'\n'*}"; else head="$(pr_head "${url}")"; fi
    [[ "${head}" =~ ^[0-9a-f]{40}$ ]] || { rc=2; continue; }
    if [[ -z "${LEAD_FRESH:-}" ]] && grep -qxF "${url} ${head}" "${LEAD_GREEN}" 2>/dev/null; then
      LEAD_CACHED=1
    else
      g=0; ci_gate head "${repo}" "${head}" >/dev/null 2>&1 || g=$?
      [[ ${g} -eq 0 ]] || { [[ ${g} -eq 3 ]] || { LEAD_RED="${url} ${head}"; return 1; }; rc=2; continue; }
    fi
    echo "${url} ${head}" >> "${LEAD_GREEN}.new"
  done
  return "${rc}"
}

# pr_head <pr-url> — the PR's head SHA as gh reads it, or nothing when it cannot, or when the read runs
# over LEAD_PRS_WAIT seconds (within): a hung gh must not stall the poll.
pr_head() {
  [[ "$1" =~ ^https://github\.com/([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)/pull/([0-9]+)$ ]] || return 0
  within "${LEAD_PRS_WAIT}" gh pr view "${BASH_REMATCH[2]}" --repo "${BASH_REMATCH[1]}" --json headRefOid --jq .headRefOid </dev/null 2>/dev/null || true
}

# held_heads — the heads pass's first read: the head of each PR a protected hold names (protected_holds
# urls), story PR or not, to LEAD_HELD as `<PR URL> <head> <epoch>`, which protected_holds weighs a hold
# against, and to LEAD_KNOWN, so heads_green reads none of them twice. <epoch> is the second the pass
# began, before any read, so a read it stamps later than a hold came after that hold. A PR whose head
# cannot be read is left out: its hold stands.
held_heads() {
  local u h t held=""
  LEAD_KNOWN=""; t="$(date +%s)"
  while IFS= read -r u; do
    h="$(pr_head "${u}")"
    [[ "${h}" =~ ^[0-9a-f]{40}$ ]] || continue
    LEAD_KNOWN+=$'\n'"${u} ${h}"; held+="${u} ${h} ${t}"$'\n'
  done < <(protected_holds urls)
  printf '%s' "${held}" > "${LEAD_HELD}.tmp" && mv "${LEAD_HELD}.tmp" "${LEAD_HELD}"
  LEAD_KNOWN+=$'\n'
}

# lead_review_items — waiting_on_user's review items as the lead's queue weighs them: a `kept: <slug>
# <PR URL>... (not reviewed)` line as it is, and with merge = human (or for a held item, under merge =
# agent too) `<tag> merge: <slug> <PR URL>...` for a story or epic awaiting a merge, <tag> p for a row
# of PRs held for a protected path or for dropped base lines (its ` (protected path)` or ` (dropped base
# lines)` tag, with or without costs money), 1 for a costs: money one, else -. It reads files only. [holds] goes to waiting_on_user.
lead_review_items() {
  local line tag
  # waiting_on_user's last line has no newline.
  while IFS= read -r line || [[ -n "${line}" ]]; do
    # A kept story (a give-up's PR, not reviewed) is the lead's to look at, never one to merge.
    if [[ "${line}" == "  kept: "* ]]; then echo "${line#  }"; continue; fi
    case "${line}" in
      "  awaiting your merge (protected path): "* | "  awaiting your merge (costs money) (protected path): "* \
        | "  awaiting your merge (dropped base lines): "* | "  awaiting your merge (costs money) (dropped base lines): "*) tag=p ;;
      "  awaiting your merge (costs money): "*) tag=1 ;;
      "  awaiting your merge: "*) tag=- ;;
      *) continue ;;
    esac
    # With merge = agent only a held item waits on the user: merge holds it for them.
    # shellcheck disable=SC2154 # assigned in another file
    [[ "${CFG_merge}" == human || "${tag}" != - ]] || continue
    line="${line#*): }"; line="${line#  awaiting your merge: }"; line="${line#epic }"
    echo "${tag} merge: ${line}"
  done < <(waiting_on_user "$@")
}

# lead_merge_shown <tag> <merge: line> <holds> — the line as lead_queue prints it, and so as LEAD_SEEN
# holds it: for a held row (tag p) the line, then ` (held: <why>; exit: <exit>)`, <why> from each PR's
# entry in <holds> (protected_holds), joined by "; ": `changes <path>[, <path>]...` for the paths and
# `its files could not be read: <why>` for each unreadable one, with the exit `the user merges it`; a
# dropped-lines entry (dropped_lines_what) as it is, with the exit `the builder restores them in a commit
# of its own, or the user reads the PR's answer and merges by hand`, or for an unchecked one `the user
# checks the merge by hand and merges it, or runs swarm.sh merge again`. A row with more than one exit
# joins them by "; ". Any other line as it is.
# LEAD_HEADS keeps the bare line, whose every word after the slug is a PR URL.
lead_merge_shown() {
  local u w e paths="" why="" exits=""
  [[ "$1" == p ]] || { echo "$2"; return 0; }
  for u in ${2#merge: * }; do
    w="$(awk -v u="${u}" '$1 == u { sub(/^[^ ]+ /, ""); print; exit }' <<< "$3")"
    e="the user merges it"
    case "${w}" in
      "") continue ;;
      "unreadable: "*) w="its files could not be read: ${w#unreadable: }" ;;
      *) if ! dropped_lines_what "${w}"; then
           [[ ", ${paths}, " == *", ${w}, "* ]] || paths+="${paths:+, }${w}"   # loose-match: ok quoted, a whole ", <path>, " entry
           w=""
         elif [[ "${w}" == "dropped base lines: "* ]]; then
           e="the builder restores them in a commit of its own, or the user reads the PR's answer and merges by hand"
         else e="the user checks the merge by hand and merges it, or runs swarm.sh merge again"; fi ;;
    esac
    [[ -z "${w}" || "; ${why}; " == *"; ${w}; "* ]] || why+="${why:+; }${w}"   # loose-match: ok quoted, a whole "; <why>; " entry
    [[ "; ${exits}; " == *"; ${e}; "* ]] || exits+="${exits:+; }${e}"   # loose-match: ok quoted, a whole "; <exit>; " entry
  done
  [[ -z "${paths}" ]] || why="changes ${paths}${why:+; }${why}"
  echo "$2 (held: ${why:-a protected path}; exit: ${exits:-the user merges it})"
}

# lead_unreported <seen> <PR URL>... — each URL that <seen> (space-separated) does not hold, after a space.
lead_unreported() {
  local s=" $1 " u
  shift
  for u in "$@"; do [[ "${s}" == *" ${u} "* ]] || printf ' %s' "${u}"; done
}

# lead_heads — the heads pass: read the PR heads of each review item lead_review_items lists
# (heads_green) and write its verdict to LEAD_HEADS, `<verdict> merge: <slug> <PR URL>...`: green when
# every head is, unread when none is red but one could not be read, red otherwise. wait_lead runs it on a
# run's first read and then at most once every LEAD_HEADS_EVERY seconds, as does open_story_prs beside it,
# so the polls between make no gh call. A held PR (costs: money, a protected path or dropped base lines) an earlier item already
# reports is not read again: a later held row loses it (lead_unreported), and a row left with none gets no
# verdict. It reads the heads of the held PRs first (held_heads), so a hold the builder pushed past is
# stale before the holds are read. The verdict is keyed by the item's whole line, as lead_queue looks it up. Whether the lead has seen
# an item is read from LEAD_SEEN in its printed form (lead_merge_shown).
lead_heads() {
  local tag line slug prs rc v urls="" seen=" " red="|" holds shown
  : > "${LEAD_GREEN}.new"; : > "${LEAD_HEADS}.new"
  held_heads
  holds="$(protected_holds)"
  while read -r tag line; do
    [[ "${tag}" != kept: ]] || continue
    slug="${line#merge: }"; slug="${slug%% *}"; prs="${line#merge: "${slug}"}"; urls+="${prs}"; rc=0
    if [[ "${tag}" != - ]]; then
      # A held PR is reported once, under the first item listing it (a story and its epic both may).
      # shellcheck disable=SC2086 # prs: is a space-separated list of URLs
      prs="$(lead_unreported "${seen}" ${prs})"
      [[ -n "${prs}" ]] || continue
    fi
    shown="$(lead_merge_shown "${tag}" "merge: ${slug}${prs}" "${holds}")"
    # shellcheck disable=SC2086 # prs: is a space-separated list of URLs
    heads_green ${prs} || rc=$?
    if [[ ${rc} -eq 0 && -n "${LEAD_CACHED}" ]] && ! grep -qxF "${shown}" "${LEAD_SEEN}" 2>/dev/null; then
      # About to wake the lead: a cached head can have gone red on a re-run since, so read each one again.
      # shellcheck disable=SC2086 # as above
      LEAD_FRESH=1 heads_green ${prs} || rc=$?
      # A cached head the re-read found red or pending leaves the cache, or every pass reads it fresh again.
      [[ -z "${LEAD_RED}" ]] || red+="${LEAD_RED}|"
    fi
    case "${rc}" in 0) v=green ;; 2) v=unread ;; *) v=red ;; esac
    echo "${v} ${line}" >> "${LEAD_HEADS}.new"
    # Seen once reported: a later item listing the PR still wakes the lead when this one was not green.
    [[ "${tag}" == - ]] || ! lead_head_wakes "${v}" "${shown}" || seen+="${prs# } "
  done < <(lead_review_items "${holds}")
  mv "${LEAD_HEADS}.new" "${LEAD_HEADS}"
  # A green head this pass did not reach (gh failed, or an earlier PR of its item was red) stays cached
  # while its PR is still in review. A head this pass's fresh re-read found red or pending (red) goes.
  touch "${LEAD_GREEN}"
  awk -v keep="${urls} " -v red="${red}" 'index(red, "|" $0 "|") { next }
    FILENAME == ARGV[1] { if (!($1 in got)) print; got[$1] = 1; next }
    !($1 in got) && index(keep, " " $1 " ") { print }' "${LEAD_GREEN}.new" "${LEAD_GREEN}" > "${LEAD_GREEN}.tmp"
  mv "${LEAD_GREEN}.tmp" "${LEAD_GREEN}"; rm -f "${LEAD_GREEN}.new"; LEAD_KNOWN=""
}

# lead_head_wakes <verdict> <merge: line> — true when a review item with that verdict is in the lead's
# queue: green, or unread while LEAD_SEEN has the line (as lead_merge_shown prints it), so a gh error wakes no one.
lead_head_wakes() { [[ "$1" == green ]] || { [[ "$1" == unread ]] && grep -qxF "$2" "${LEAD_SEEN}" 2>/dev/null; }; }

LEAD_PRS="${LEAD_DIR}/prs"            # the open story PRs the last heads pass read (open_story_prs), for pr_lines
LEAD_PRS_WAIT="${SWARM_LEAD_PRS_WAIT:-30}"   # seconds one gh read of the heads pass (open_story_prs, pr_head) may take before it counts as failed
LEAD_PRS_WARN_AFTER="${SWARM_LEAD_PRS_WARN_AFTER:-3}"   # heads passes in a row a repo's or a base's read fails before wait --lead warns
LEAD_REPOS=""                         # "<name> <owner/repo>" per repo this run resolved, so each costs one gh repo view a run
LEAD_PRS_FAILS=""                     # "<name> <n>": the heads passes in a row that could not read the repo's open PRs
LEAD_NWO=""                           # the owner/repo lead_nwo last resolved
LEAD_BASES="${LEAD_DIR}/bases"        # each base's head and its CI as the last heads pass read them (lead_bases), for main_red_lines
LEAD_BASE_RECHECK=7200                # seconds a base head read green is read again, for a rerun that fails on the same sha
LEAD_BASE_OF=""                       # "<owner/repo> <base>" per repo this run resolved the base of (lead_base)
LEAD_BASE=""                          # the base lead_base last resolved
LEAD_FIXES="${LEAD_DIR}/fixes"        # the fix-main runs main_red_fix started for each red base head, for main_red_lines
LEAD_FIX_TRIES=2                      # runs main_red_fix starts for a red head before its main-red: line names the lead's check
LEAD_FIX_LOG_SECONDS=60               # how long a run's reads of the failed runs' logs may take (its SWARM_FIX_MAIN_LOG_SECONDS)
LEAD_FIX_SECONDS=600                  # how long a run may live before main_red_fix stops it and counts it failed
# What git refuses in a branch name (a space, a control character, ~ ^ : ? * [ \), as a regex held in a
# variable, so bash 3.2 and 5 read its backslash alike.
LEAD_REF_BAD='[[:space:][:cntrl:]~^:?*[\]'
LEAD_BASE_FAILS=""                    # "<what>\t<n>": the heads passes in a row that could not read a base (lead_base_failed)

# lead_nwo <name> — set LEAD_NWO to the owner/repo of a repo a story names (<name>, `.` for the project's own):
# LEAD_REPOS' entry, else resolved as repo_slug does (gh repo view on its origin, within LEAD_PRS_WAIT) and added
# to LEAD_REPOS, so each costs one gh read a run. Fails 2 for a repo with no clone or no origin, 1 when gh
# fails or answers no owner/repo. It runs in the caller's shell, which keeps LEAD_REPOS.
lead_nwo() {
  local src origin
  LEAD_NWO="$(awk -v n="$1" '$1 == n { print $2; exit }' <<< "${LEAD_REPOS}")"
  [[ -z "${LEAD_NWO}" ]] || return 0
  if [[ "$1" == . ]]; then src="$(repo_dir "")" || return 2; else src="$(repo_dir "$1")" || return 2; fi
  origin="$(git -C "${src}" remote get-url origin 2>/dev/null)" || return 2
  LEAD_NWO="$(within "${LEAD_PRS_WAIT}" gh repo view "${origin}" --json nameWithOwner -q .nameWithOwner </dev/null 2>/dev/null)" || LEAD_NWO=""
  [[ "${LEAD_NWO}" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || { LEAD_NWO=""; return 1; }
  LEAD_REPOS+="$1 ${LEAD_NWO}"$'\n'
}

# open_story_prs — the heads pass's read of the open story PRs, for pr_lines to read each poll with no gh call (LEAD_PRS).
# For each repo a story names (its repo:, `.` for the project's own), resolved once a run to its owner/name
# (lead_nwo), it prints `= <name> <owner/repo>`, then one `gh pr list` per
# owner/repo, each gh read bounded by LEAD_PRS_WAIT seconds (within): `+ <owner/repo> <slug> <PR URL> <head>
# <mergeable> <checks> <opened, epoch seconds>` per open story/* PR from the repo itself, never a fork's. <checks> is green when the rollup GitHub returns
# has at least one check run and every check run and status in it passed (success, skipped or neutral); a required
# check that never reported is not seen, and `swarm.sh merge` runs ci_gate's full rule. A repo whose read failed or
# timed out is `- <name>`; at LEAD_PRS_WARN_AFTER such passes in a row it warns once on stderr (open_prs_failed).
# A repo with no clone or no origin has no PR to list and prints nothing. It runs in the caller's shell, which
# keeps LEAD_REPOS and LEAD_PRS_FAILS across passes.
open_story_prs() {
  local name nwo listed="" failed="" rows rc
  while IFS= read -r name; do
    [[ -n "${name}" ]] || continue
    rc=0; lead_nwo "${name}" || rc=$?
    (( rc != 2 )) || continue
    if (( rc != 0 )); then echo "- ${name}"; open_prs_failed "${name}"; continue; fi
    nwo="${LEAD_NWO}"
    echo "= ${name} ${nwo}"
    if grep -qxF "${nwo}" <<< "${failed}"; then echo "- ${name}"; open_prs_failed "${name}"; continue; fi
    if ! grep -qxF "${nwo}" <<< "${listed}"; then
      rows="$(within "${LEAD_PRS_WAIT}" gh pr list -R "${nwo}" --state open --limit 1000 --json url,headRefName,headRefOid,mergeable,statusCheckRollup,createdAt,isCrossRepository </dev/null 2>/dev/null \
        | python3 -I -c '
import datetime, json, sys
OK = ("SUCCESS", "SKIPPED", "NEUTRAL")
prs = json.load(sys.stdin)
if not isinstance(prs, list):
    sys.exit(1)
for p in prs:
    ref = (p.get("headRefName") or "") if isinstance(p, dict) else ""
    # A fork PR whose branch is named story/<slug> does not belong to the story.
    if not ref.startswith("story/") or p.get("isCrossRepository"):
        continue
    roll = p.get("statusCheckRollup") or []
    green = any(c.get("__typename") == "CheckRun" for c in roll) and all(((c.get("state") or "") if c.get("__typename") == "StatusContext" else (c.get("conclusion") or "") if (c.get("status") or "") == "COMPLETED" else "").upper() in OK for c in roll)
    opened = datetime.datetime.fromisoformat(p["createdAt"].replace("Z", "+00:00"))
    print(ref[6:], p["url"], p["headRefOid"], p.get("mergeable") or "UNKNOWN", "green" if green else "not", int(opened.timestamp()))
' 2>/dev/null)" || { failed+="${nwo}"$'\n'; echo "- ${name}"; open_prs_failed "${name}"; continue; }
      listed+="${nwo}"$'\n'
      awk -v n="${nwo}" 'NF { print "+ " n " " $0 }' <<< "${rows}"
    fi
    LEAD_PRS_FAILS="$(awk -v r="${name}" '$1 != r' <<< "${LEAD_PRS_FAILS}")"
  done < <(stories_fm repo | awk -F $'\x1f' '{ r = $2; gsub(/["\047]/, "", r); if (r == "") r = "."; if (r == "." || r ~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/) print r }' | sort -u)
}

# open_prs_failed <name> — count a heads pass that could not read <name>'s open PRs; the LEAD_PRS_WARN_AFTER-th
# in a row warns on stderr, once until a read succeeds, saying who clears it.
open_prs_failed() {
  local n
  n="$(awk -v r="$1" '$1 == r { print $2 }' <<< "${LEAD_PRS_FAILS}")"; n=$(( ${n:-0} + 1 ))
  LEAD_PRS_FAILS="$(awk -v r="$1" '$1 != r' <<< "${LEAD_PRS_FAILS}")"$'\n'"$1 ${n}"
  [[ ${n} -eq ${LEAD_PRS_WARN_AFTER} ]] || return 0
  echo "warning: wait --lead could not read the open PRs of $([[ "$1" == . ]] && echo "the project's repo" || echo "repo $1") on ${n} heads passes in a row (gh failed or timed out), so its unmerged: and conflict: lines stand as last seen and no new one comes: check gh auth status and that gh can see the repo" >&2
}

# lead_base_failed <key> <what> — count a heads pass that could not read a base: <key> is `<owner/repo>` when it
# could not tell the base, `<owner/repo> <base>` when it could not read the head or its CI, <what> what it could
# not do. The LEAD_PRS_WARN_AFTER-th in a row warns on stderr, once until a read succeeds (lead_base_read).
lead_base_failed() {
  local n
  n="$(awk -F'\t' -v k="$1" '$1 == k { print $2 }' <<< "${LEAD_BASE_FAILS}")"; n=$(( ${n:-0} + 1 ))
  LEAD_BASE_FAILS="$(awk -F'\t' -v k="$1" '$1 != k' <<< "${LEAD_BASE_FAILS}")"$'\n'"$1"$'\t'"${n}"
  [[ ${n} -eq ${LEAD_PRS_WARN_AFTER} ]] || return 0
  echo "warning: wait --lead could not $2 on ${n} heads passes in a row (gh failed or timed out), so its main-red: line stands as last seen and no new one comes: check gh auth status, that gh can see the repo, and base_branches" >&2
}

# lead_base_read <key> — a heads pass read that base: its count of failed passes starts again.
lead_base_read() { LEAD_BASE_FAILS="$(awk -F'\t' -v k="$1" '$1 != k' <<< "${LEAD_BASE_FAILS}")"; }

# lead_base <owner/repo> — set LEAD_BASE to the repo's base as base_for picks it: the first base_branches entry
# GitHub has, or the repo's default branch when the list is empty. Each gh read is bounded (within
# BASE_HEAD_WAIT) and nothing is fetched, as base_for would. Resolved once a run (LEAD_BASE_OF); fails, and
# is asked again on the next pass, when a read fails or GitHub has none of the branches. Never a guess.
lead_base() {
  local b refs
  LEAD_BASE="$(awk -v r="$1" '$1 == r { print $2; exit }' <<< "${LEAD_BASE_OF}")"
  [[ -z "${LEAD_BASE}" ]] || return 0
  if [[ -n "${CFG_base_branches// /}" ]]; then
    # shellcheck disable=SC2086 # branch names separated by spaces, which load_config checked
    for b in ${CFG_base_branches}; do
      # A ref prefix, so it also lists dev-x for dev: only the whole name counts.
      refs="$(within "${BASE_HEAD_WAIT}" gh api --paginate --jq '.[].ref' "repos/$1/git/matching-refs/heads/${b}" </dev/null 2>/dev/null)" || return 1
      if grep -qxF "refs/heads/${b}" <<< "${refs}"; then LEAD_BASE="${b}"; break; fi
    done
  else
    LEAD_BASE="$(within "${BASE_HEAD_WAIT}" gh api --jq .default_branch "repos/$1" </dev/null 2>/dev/null)" || LEAD_BASE=""
  fi
  [[ -n "${LEAD_BASE}" && ! "${LEAD_BASE}" =~ ${LEAD_REF_BAD} ]] || { LEAD_BASE=""; return 1; }   # loose-match: ok LEAD_REF_BAD is a regex on purpose
  LEAD_BASE_OF+="$1 ${LEAD_BASE}"$'\n'
}

# lead_bases — the heads pass's read of each base's CI, for main_red_lines to read each poll with no gh call
# (LEAD_BASES). It covers the base (lead_base) of the project's repo and of each repo LEAD_REPOS holds, which
# open_story_prs resolved earlier in the same pass, and the repo and base of each live red main (red_mains).
# For each it reads the base's head (gh api, within BASE_HEAD_WAIT) and that head's CI (ci_gate base, within
# BASE_CI_WAIT): green, red, pending (running, or no check run or status yet) or unread. It writes `<owner/repo> <base>
# <sha> <verdict> <epoch> [<red checks>]` a base, the repo lowercased as main_key has it, <epoch> when <sha>
# first read as <verdict>, and the checks cut by ci_data. A pending, unread or red head is read again on every
# pass, and a green one for LEAD_BASE_RECHECK seconds, so a rerun that fails on the same sha still turns it
# red; past that a green head's CI is read again only once the base moves. A red head read red again keeps its
# line as first read, so a check that finishes later does not change the line and wake the lead twice. A head
# that cannot be read, a head whose CI cannot be read (the line's own head or a new one: a failed read replaces
# nothing), a base not resolved (its repo's lines stand, with no read of the base they name, which may be one no
# longer), a repo gh could not name (every line no read this pass replaced stays), and a red head whose CI now reads
# pending (a rerun under way) keep the line they had; a green head whose CI reads pending is written pending, so
# it is read again every pass, past LEAD_BASE_RECHECK too, until the rerun concludes. Each failed read counts
# towards a warning (lead_base_failed). A repo with no clone or no origin, which no pass can read, loses its
# lines, as open_story_prs lists no PR for it. On a concluded head (green or red) of a base red_mains holds, it
# runs clear_red_main, as reconcile's green_mains does on every head: that logs main-green and retires the base's
# unstarted fix-main stories once ci_gate fixed shows the red fixed, which a head red only on checks the base
# does not require does. It prints nothing on stdout.
lead_bases() {
  local name nwo base todo="" reds old x sha v at head out rc nv checks line now lost="" unresolved=""
  now="$(date +%s)"; reds="$(red_mains)"
  while read -r name; do
    [[ -n "${name}" ]] || continue
    # A repo gh could not name: which of the old lines are its is unknown, so none goes this pass.
    lead_nwo "${name}" || { [[ $? -ne 1 ]] || lost=1; continue; }
    nwo="$(tr '[:upper:]' '[:lower:]' <<< "${LEAD_NWO}")"
    if lead_base "${nwo}"; then todo+="${nwo} ${LEAD_BASE}"$'\n'; lead_base_read "${nwo}"
    else
      # Its lines stand as last read: the base they name may be one no longer, so nothing reads it.
      unresolved+="${nwo} "
      lead_base_failed "${nwo}" "tell the base of ${nwo}"
    fi
  done < <({ echo .; awk 'NF { print $1 }' <<< "${LEAD_REPOS}"; } | sort -u)
  todo+="$(awk 'NF { print $2, $3 }' <<< "${reds}")"
  : > "${LEAD_BASES}.new" || return 0
  while read -r nwo base; do
    [[ -n "${base}" ]] || continue
    old="$(awk -v r="${nwo}" -v b="${base}" '$1 == r && $2 == b { print; exit }' "${LEAD_BASES}" 2>/dev/null)"
    sha=""; v=""; at=""; [[ -z "${old}" ]] || read -r x x sha v at x <<< "${old}"
    [[ "${sha}" =~ ^[0-9a-f]{40}$ && "${at}" =~ ^[0-9]+$ ]] || { sha=""; v=""; }
    head="$(within "${BASE_HEAD_WAIT}" gh api --jq .sha "repos/${nwo}/commits/${base}" </dev/null 2>/dev/null)" || head=""
    if [[ ! "${head}" =~ ^[0-9a-f]{40}$ ]]; then
      [[ -z "${old}" ]] || echo "${old}" >> "${LEAD_BASES}.new"
      lead_base_failed "${nwo} ${base}" "read CI on ${base} of ${nwo}"; continue
    fi
    [[ "${head}" == "${sha}" ]] || v=""
    if [[ "${v}" == green ]] && (( now - at >= LEAD_BASE_RECHECK )); then
      line="${old}"
    else
      rc=0; out="$(within "${BASE_CI_WAIT}" python3 "${SWARM_HOME}/bin/lib/ci_gate.py" base "${nwo}" "${head}" </dev/null 2>/dev/null)" || rc=$?
      case ${rc} in 0) nv=green ;; 1) nv=red ;; 2) nv=pending ;; *) nv=unread ;; esac
      if [[ "${nv}" == unread ]]; then lead_base_failed "${nwo} ${base}" "read CI on ${base} of ${nwo}"; else lead_base_read "${nwo} ${base}"; fi
      # A CI read that fails, on the line's head or a new one, replaces nothing: the line stands as last read. A red
      # head whose rerun is under way keeps its line too, so main-red: stands until the rerun concludes. A green one
      # is written pending, so it is read again every pass, past LEAD_BASE_RECHECK too, until the rerun concludes.
      if [[ "${nv}" == unread && -n "${sha}" ]] || [[ "${v}" == red && ( "${nv}" == pending || "${nv}" == red ) ]]; then
        line="${old}"
      else
        [[ "${nv}" == "${v}" ]] || at="${now}"
        checks=""; [[ "${nv}" != red ]] || checks=" $(red_names_only "${out%%$'\n'*}" | ci_data)"
        line="${nwo} ${base} ${head} ${nv} ${at}${checks}"
      fi
    fi
    echo "${line}" >> "${LEAD_BASES}.new"
    # Concluded while a red main of the base stands: clear it as reconcile (green_mains) does, once ci_gate fixed
    # shows this head fixed. fixed judges the required checks alone once each has a run, so a head red only on a
    # check the base does not require clears the red too; the base's pass-found line then names that check.
    read -r x x x v x <<< "${line}"
    if [[ "${v}" == green || "${v}" == red ]] && awk -v k="${nwo} ${base}" '$2 " " $3 == k { f = 1 } END { exit !f }' <<< "${reds}"; then
      clear_red_main "${nwo} ${base}" "${head}" "CI on ${base} is green at ${head:0:7}" </dev/null >/dev/null 2>&1 || true
    fi
  done < <(awk 'NF == 2 && !seen[$0]++' <<< "${todo}")
  # The lines no read this pass replaced: every one when a repo could not be named (which lines are its is
  # unknown), else those of each repo whose base could not be told. FILENAME, not FNR == NR: the new file may be empty.
  out=""; [[ -z "${lost}${unresolved}" ]] || out="$(awk -v lost="${lost}" -v keep="${unresolved}" \
    'FILENAME == ARGV[1] { got[$1 " " $2] = 1; next } !(($1 " " $2) in got) && (lost != "" || index(" " keep, " " $1 " "))' \
    "${LEAD_BASES}.new" "${LEAD_BASES}" 2>/dev/null)" || out=""
  [[ -z "${out}" ]] || echo "${out}" >> "${LEAD_BASES}.new"
  mv "${LEAD_BASES}.new" "${LEAD_BASES}"
}

# findings_open <file> — true when the ## Findings section of a review's findings file lists a finding: a
# non-empty line that does not say none.
findings_open() {
  awk '/^## / { f = ($0 ~ /^## Findings/); next }
    f && NF { l = tolower($0); sub(/^[-*] +/, "", l); if (l !~ /^(none|no findings)([^a-z]|$)/) o = 1 }
    END { exit !o }' "$1" 2>/dev/null
}

# story_pr_rows — the last heads pass's LEAD_PRS joined with the board as it is now, for pr_lines and
# stuck_lines: `<slug> <PR URL> <head> <mergeable> <checks> <opened> <kept 0|1>` for each open PR whose story is
# ready or in review, is one an agent builds (agent_kind) and names the PR's repo as its own (repo:, else the
# project's), and `<slug> -` for each such story of a repo the pass could not read.
story_pr_rows() {
  awk -v kinds=" ${AGENT_KINDS} " -v sep=$'\x1f' '
  FILENAME == ARGV[1] {
    split($0, v, sep); r = v[5]; gsub(/["\047]/, "", r); if (r == "") r = "."
    if ((v[2] == "ready" || v[2] == "review") && (v[3] == "" || index(kinds, " " v[3] " "))) { home[v[1]] = r; kept[v[1]] = (v[4] != "") }
    next
  }
  $1 == "=" { nwo[$2] = $3; next }
  $1 == "-" { lost[$2] = 1; next }
  $1 == "+" { row[++n] = $0; next }
  END {
    for (s in home) if (home[s] in lost) print s " -"
    for (i = 1; i <= n; i++) {
      split(row[i], f, " ")
      if ((f[3] in home) && nwo[home[f[3]]] == f[2] && !(home[f[3]] in lost))
        print f[3], f[4], f[5], f[6], f[7], f[8], kept[f[3]]
    }
  }' <(stories_fm status kind kept repo) "${LEAD_PRS}"
}

# pr_lines — the lead's queue's lines for open story PRs, from the last heads pass's LEAD_PRS joined with the board
# as it is now (story_pr_rows), so a poll makes no gh call. A PR counts when its story is ready or in review, is one an agent builds
# (agent_kind: a lead story's PR is the lead's), and names the PR's repo as its own (repo:, else the project's).
# `conflict: <slug> <PR URL>, exit: tell its builder to merge the base in` for one CONFLICTING with its base,
# unless stuck_lines named it this poll (STUCK_PRS): one line per PR.
# `unmerged: <slug> <PR URL>, exit: swarm.sh merge --head <sha> <PR URL>` for one MERGEABLE and green whose findings
# file is a pass on its head (review_pass), opened and reviewed queue_minutes or more ago (the findings file's
# mtime); when that file lists findings the exit is `triage .swarm/reviews/<slug>.md, then swarm.sh merge --head
# <sha> <PR URL> once every finding is declined`. No unmerged: for a kept story's PR (the kept: line's), a PR that
# already has a merge: line (lead_review_items), or one a `swarm.sh merge` is merging now (one ps read, only
# when such a line is due). A PR whose mergeable state GitHub is still working out (UNKNOWN), and each story of a
# repo the pass could not read, keeps its lines from LEAD_SEEN, so a lapse in the read neither drops a line nor
# wakes the lead with it again. So does, for its unmerged: line, a PR on a poll whose ps read failed: as in
# no_agent_lines, a process list that could not be read says nothing about a running merge.
pr_lines() {
  local slug url head mg ck opened kept m out items="" ps="" got=0 psok=1
  [[ -s "${LEAD_PRS}" ]] || return 0
  while read -r slug url head mg ck opened kept; do
    if [[ "${url}" == - ]]; then
      awk -v s="${slug}" '($1 == "unmerged:" || $1 == "conflict:") && $2 == s' "${LEAD_SEEN}" 2>/dev/null || true; continue
    fi
    if [[ "${mg}" == UNKNOWN ]]; then
      grep -F -e "unmerged: ${slug} ${url}," -e "conflict: ${slug} ${url}," "${LEAD_SEEN}" 2>/dev/null || true; continue
    fi
    # A PR stuck_lines named this poll has its stuck: line in place of this one.
    [[ "${mg}" != CONFLICTING || " ${STUCK_PRS} " == *" ${url} "* ]] || echo "conflict: ${slug} ${url}, exit: tell its builder to merge the base in"
    [[ "${mg}" == MERGEABLE && "${ck}" == green && "${kept}" == 0 ]] || continue
    review_pass "${slug}" "${head}" || continue
    m="$(perl -e 'my ($f, $o) = @ARGV; my @s = stat $f or exit 1; my $g = time - $s[9]; $g = time - $o if time - $o < $g; print int($g / 60)' \
      "${PROJECT_DIR}/.swarm/reviews/${slug}.md" "${opened}")" || continue
    # shellcheck disable=SC2154 # assigned in another file
    (( m >= CFG_queue_minutes )) || continue
    # The reads below are the poll's, made once and only for a line that is due.
    if (( got == 0 )); then got=1; items="$(lead_review_items)"; ps="$(ps -A -ww -o command= 2>/dev/null)" || psok=0; fi
    awk -v u="${url}" '$2 == "merge:" { for (i = 4; i <= NF; i++) if ($i == u) f = 1 } END { exit !f }' <<< "${items}" && continue
    # A process list that could not be read may hide a merge of this PR: keep the line it had, and add none.
    if (( psok == 0 )); then grep -F "unmerged: ${slug} ${url}," "${LEAD_SEEN}" 2>/dev/null || true; continue; fi
    awk -v u="${url}" 'index($0, "swarm.sh merge") { for (i = 1; i <= NF; i++) if ($i == u) f = 1 } END { exit !f }' <<< "${ps}" && continue
    out="swarm.sh merge --head ${head} ${url}"
    ! findings_open "${PROJECT_DIR}/.swarm/reviews/${slug}.md" \
      || out="triage .swarm/reviews/${slug}.md, then swarm.sh merge --head ${head} ${url} once every finding is declined"
    echo "unmerged: ${slug} ${url}, exit: ${out}"
  done < <(story_pr_rows)
}

# STOP_GRACE: how many seconds a stop note waits before stop_lines reports it (SWARM_STOP_GRACE). The
# review agent writes the note, then tells it a model turn later; a poll between the two would wake the
# lead with a note its conductor is about to get, and the conductor would get it twice.
STOP_GRACE="${SWARM_STOP_GRACE:-120}"

# user_merges <story-file> — true for a story in review whose PR waits on the user's merge: under merge
# = human with no HLD merge grant (no_agent_granted), one that costs money (costs_tag), or one swarm.sh
# merge held for the user since its last review (a held: line, or one that ends the user merges it or
# waits on the user's merge). An unconfirmed merge, one to check by hand or the epic guard's goes to
# the lead, so it is not the user's. A kept story waits on its review agent or the lead, not the user.
user_merges() {
  local slug
  slug="$(basename "$1" .md)"
  [[ -z "$(get_fm "$1" kept)" ]] || return 1
  # shellcheck disable=SC2154 # load_config assigns it with printf -v
  if [[ "${CFG_merge}" != agent ]] && ! no_agent_granted "${slug}"; then return 0; fi
  [[ -z "$(costs_tag "$1")" ]] || return 0
  awk -F'\t' -v s="${slug}" "${EVENT_OUTCOME_AWK}"'
    $3 == s && $2 == "review" && index(outcome($5), "ok") == 1 { m = "" }
    $3 == s && $2 == "merge" { m = outcome($5) }
    END { exit !(m ~ /^held:/ || m ~ /the user merges it|waits on the user.s merge/) }' "${EVENTS_LOG}" 2>/dev/null
}

# stop_lines — `stopped: <slug> (<the stop note>), exit: <exit>` for each review agent's stop note
# (.swarm/reviews/<slug>.stop.md, which review_brief has it write and tell its conductor) that no
# conductor has, once it is STOP_GRACE seconds old. Its story is on the board and not done
# (review_agent removes the note when it starts a new agent, so one left is the newest agent's), and,
# in review, not one whose PR waits on the user's merge (user_merges: a merge held: hand-off), which is
# not the lead's.
# A conductor has the note only when its tell reached one (tell's .told marker beside the note, no
# older than it, naming the conductor) that still runs in a pane of the poll's herdr list (LEAD_AGENTS)
# with no report written and was not started again since (its brief no newer than the marker: a new
# start clears its inbox). A tell that failed leaves no marker, so a conductor started later, which
# never got the note, hides nothing. A poll with no herdr list keeps the stopped: lines LEAD_SEEN has,
# so a missed read neither drops a line nor wakes the lead with it again.
stop_lines() {
  local f slug story cond note told age
  [[ -n "${LEAD_AGENTS_READ}" ]] || lead_agents
  if [[ -z "${LEAD_AGENTS_OK}" ]]; then grep '^stopped: ' "${LEAD_SEEN}" 2>/dev/null || true; return 0; fi
  for f in "${PROJECT_DIR}"/.swarm/reviews/*.stop.md; do
    [[ -f "${f}" ]] || continue
    slug="${f##*/}"; slug="${slug%.stop.md}"; story="${BOARD}/stories/${slug}.md"
    [[ -f "${story}" ]] || continue
    case "$(fm "${story}" status)" in
      done) continue ;;
      review) ! user_merges "${story}" || continue ;;
    esac
    age="$(perl -e 'print time - (stat shift)[9]' "${f}" 2>/dev/null)" || age=0
    (( ${age:-0} >= STOP_GRACE )) || continue
    told="$(cat "${f%.md}.told" 2>/dev/null)" || told=""
    if [[ -n "${told}" && ! "${f}" -nt "${f%.md}.told" && -n "$(list_field "${told}" pane_id <<< "${LEAD_AGENTS}")" \
          && ! -f "$(conductor_report "${told}")" && ! "${PROJECT_DIR}/.swarm/briefs/conduct-$(conduct_epic "${told}").md" -nt "${f%.md}.told" ]]; then
      continue
    fi
    cond="$(story_conductor "${slug}")"
    note="$(head -1 "${f}" | tr -d '\r')"
    echo "stopped: ${slug} (${note}), exit: act on its why as ${cond}'s review rule says, or start a conductor for the story and send it the note with swarm.sh tell <conductor> note ${f}"
  done
}

# lead_queue — one line per item waiting on the lead, as wait --lead prints it: `held: <slug> (<cause>)`
# for a story with held_for:, `escalated: <slug>` for any other escalated one, a `kept:` line
# (lead_review_items), `merge: <slug> <PR URL>...` for a review item whose verdict in LEAD_HEADS, the last
# heads pass's (lead_heads), wakes the lead (lead_head_wakes), with ` (held: changes <path>; exit: the user
# merges it)` after the URLs of a row held for a protected path, or its dropped-lines why and exit after
# those of a row held for dropped base lines (lead_merge_shown), and less any held PR an
# earlier line reported (lead_unreported). It reads the holds once (protected_holds) for its rows and its
# lines. Then, from no_agent_lines record: `step-up
# failed: <slug>, exit: swarm.sh step-up --resume <slug>` for a ready story whose step-up stopped
# after closing its builder, `no-agent: <slug>, exit: <exit>` for a started story no agent works
# on, and `no-review: <slug> <pr>, exit: ...` for one whose review agent never started or went. Those read the poll's herdr list (lead_agents) and one ps, and write a `no-agent <slug>`
# events.tsv line for a story whose missing agent no event explains yet, and start again a review agent
# whose start was cut short with tries left (no_review_line's restart). Then stop_lines' `stopped: <slug>
# (<note>), exit: ...` for a review agent's stop note no running conductor has, off the same list. wait --lead adds `unsent brief:
# <stem>, exit: <exit>` lines (unsent_lines) after its resend pass, which writes their .unsent markers,
# then `prompt: <agent> (<kind>), exit: <exit>` lines (prompt_lines). Before those, after no_agent_lines',
# come pr_lines' `conflict:` and `unmerged:` lines, from the file the last heads pass wrote (open_story_prs),
# with stuck_lines' just before them and main_red_lines' `main-red:` lines (from events.tsv and the file the
# last heads pass wrote, lead_bases), reported_lines' and sign_blocked_lines' after.
# It never calls gh. It drops
# from LEAD_HEADS the verdict of an item no longer in review, so a review item that entered review, or
# came back to it, since the last pass waits for the next. next's idle: lines (idle_warned) come before
# no_agent_lines', read afresh each poll, so one goes once its dependency is in review or done; a poll
# whose check fails keeps the ones the last poll saw.
lead_queue() {
  local f held tag line v keep="" holds shown slug prs seen=" "
  holds="$(protected_holds)"
  while IFS= read -r f; do
    held="$(get_fm "${f}" held_for)"
    if [[ -n "${held}" ]]; then echo "held: $(basename "${f}" .md) (${held})"
    elif is_escalated "${f}"; then echo "escalated: $(basename "${f}" .md)"; fi
  done < <(board stories)
  while read -r tag line; do
    if [[ "${tag}" == kept: ]]; then echo "kept: ${line}"; continue; fi
    v="$(awk -v l="${line}" 'substr($0, index($0, " ") + 1) == l { print $1; exit }' "${LEAD_HEADS}" 2>/dev/null)" || v=""
    [[ -z "${v}" ]] || keep+="${v} ${line}"$'\n'
    shown="${line}"
    if [[ "${tag}" != - ]]; then
      # As lead_heads: a held PR an earlier line reported leaves this one, and a line left with none goes.
      slug="${line#merge: }"; slug="${slug%% *}"
      # shellcheck disable=SC2086 # the words after the slug are PR URLs
      prs="$(lead_unreported "${seen}" ${line#merge: "${slug}"})"
      [[ -n "${prs}" ]] || continue
      shown="$(lead_merge_shown "${tag}" "merge: ${slug}${prs}" "${holds}")"
    fi
    lead_head_wakes "${v}" "${shown}" || continue
    echo "${shown}"; [[ "${tag}" == - ]] || seen+="${prs# } "
  done < <(lead_review_items "${holds}")
  # A verdict on a head read before its item left review says nothing about the head it comes back with.
  [[ ! -f "${LEAD_HEADS}" ]] || { printf '%s' "${keep}" > "${LEAD_HEADS}.tmp" && mv "${LEAD_HEADS}.tmp" "${LEAD_HEADS}"; }
  # Advisory, as in next: a failed check warns on stderr, one line per poll, and keeps the idle: lines
  # the last poll saw (LEAD_SEEN), so the queue does not lose them and the next good poll wakes no one again.
  idle_warned "the idle: lines the last poll saw stand" || grep '^idle: ' "${LEAD_SEEN}" 2>/dev/null || true
  # A list it could not check (2) wakes no one; the other lines above still do.
  no_agent_lines record || true
  stop_lines
  stuck_lines
  pr_lines
  main_red_lines
  reported_lines
  sign_blocked_lines
}

# STUCK_MINUTES: how long a builder's pending findings or conflict may sit on an unchanged PR head before
# stuck_lines names it (SWARM_STUCK_MINUTES). STUCK_READ_WAIT: seconds each of stuck_lines' claude and herdr
# reads may take (within). LEAD_PR_HEADS: `<slug> <head> <first seen> <conflict first seen, or ->` per open
# story PR, epochs, rewritten each poll. STUCK_PRS: the PR URLs stuck_lines named this poll, for pr_lines.
STUCK_MINUTES="${SWARM_STUCK_MINUTES:-60}"
STUCK_READ_WAIT=10
LEAD_PR_HEADS="${LEAD_DIR}/pr-heads"
STUCK_PRS=""

# stuck_lines — `stuck: <slug> <PR URL> (<findings|conflict> pending <N> min), exit: swarm.sh tell <slug> resume
# <file>` for an open story PR (story_pr_rows) whose builder sits idle on a pending item, N being STUCK_MINUTES,
# never the minutes elapsed: LEAD_SEEN dedupes whole lines, so a count would wake the lead every poll. The item
# is a findings tell (findings_told's: tell or tell:findings, ok or sent, since the build started) newest at least
# N minutes ago and no older than the head, on a head no review has passed (review_pass), or a CONFLICTING mergeable
# first seen on this head at least N minutes ago; a conflict wins over findings. A head counts from when a poll first saw it (LEAD_PR_HEADS, which drops a PR no longer open), so a
# tell made before wait --lead first saw the head is not one. Checks, cheapest first: those file reads, the builder
# live in the poll's herdr list (LEAD_AGENTS), its state idle (read_state's, over one claude agents read and that
# list), no background task (bg_running), no test run in its pane (stuck_test_run). A PR of a repo the pass could
# not read, one whose mergeable is UNKNOWN on the same head, and a poll with no herdr list or no state for the
# builder keep the stuck: line LEAD_SEEN has.
stuck_lines() {
  local slug url head mg ck opened kept now rows old told rec="" oh of oc first conf kind name pane st claude="" read=""
  STUCK_PRS=""
  [[ -s "${LEAD_PRS}" ]] || return 0
  now="$(date +%s)"
  rows="$(story_pr_rows)"
  old="$(cat "${LEAD_PR_HEADS}" 2>/dev/null)" || old=""
  # One read of events.tsv for every PR, as epochs: `T <target> <newest findings tell>`, and the newest ok build
  # start, as build_started reads it: `S <slug>` for a story or escalate line, `A <name>` for an agent line. $o is
  # the outcome without its key=value tail: the text before the first EVENT_SEP (EVENT_OUTCOME_AWK's outcome).
  told="$(EVENT_SEP="${EVENT_SEP}" perl -MTime::Local=timegm -F'\t' -lane 'next unless $F[0] =~ /^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)Z$/; $e = timegm($6, $5, $4, $3, $2 - 1, $1);
    $o = $F[4]; $i = index($o, $ENV{EVENT_SEP}); $o = substr($o, 0, $i) if $i >= 0;
    if (($F[1] eq "tell" || $F[1] eq "tell:findings") && ($o eq "ok" || $o =~ /herdr sent it the brief/)) { $t{"T $F[2]"} = $e }
    elsif ($o =~ /^ok/ && ($F[1] eq "story" || $F[1] eq "escalate")) { $t{"S $F[2]"} = $e }
    elsif ($o =~ /^ok/ && $F[1] eq "agent") { $t{"A $F[2]"} = $e }
    END { print "$_ $t{$_}" for sort keys %t }' "${EVENTS_LOG}" 2>/dev/null)" || told=""
  while read -r slug url head mg ck opened kept; do
    [[ -n "${slug}" ]] || continue
    name=""
    read -r oh of oc <<< "$(awk -v s="${slug}" '$1 == s { print $2, $3, $4; exit }' <<< "${old}")"
    if [[ "${url}" == - ]]; then
      [[ -z "${oh}" ]] || rec+="${slug} ${oh} ${of} ${oc}"$'\n'
      stuck_seen "${slug}"; continue
    fi
    first="${now}"; conf=-
    if [[ "${head}" == "${oh}" ]]; then first="${of}"; conf="${oc:--}"; fi
    if [[ "${mg}" == UNKNOWN ]]; then
      rec+="${slug} ${head} ${first} ${conf}"$'\n'
      # A new head is no longer the one the line was about.
      [[ "${head}" != "${oh}" ]] || stuck_seen "${slug}" "${url}"
      continue
    fi
    if [[ "${mg}" == CONFLICTING ]]; then [[ "${conf}" != - ]] || conf="${now}"; else conf=-; fi
    rec+="${slug} ${head} ${first} ${conf}"$'\n'
    kind=""
    if [[ "${conf}" != - ]] && (( now - conf >= STUCK_MINUTES * 60 )); then kind=conflict
    else
      # A tell before this build started (findings_told's bound) reached an earlier builder.
      no_agent_name name "${slug}"
      st="$(awk -v s="${slug}" -v n="${name}" '$1 == "T" && $2 == s { t = $3 } ($1 == "S" && $2 == s) || ($1 == "A" && $2 == n) { if ($3 > b) b = $3 }
        END { if (t != "" && t >= b) print t }' <<< "${told}")"
      [[ -z "${st}" ]] || (( st < first || now - st < STUCK_MINUTES * 60 )) || kind=findings
      # A review that passed on this head leaves the builder no findings to act on (the PR waits on its merge).
      [[ "${kind}" != findings ]] || ! review_pass "${slug}" "${head}" || kind=""
    fi
    [[ -n "${kind}" ]] || continue
    # The builder: live, idle, with no background task and no test run.
    [[ -n "${LEAD_AGENTS_READ}" ]] || lead_agents
    if [[ -z "${LEAD_AGENTS_OK}" ]]; then stuck_seen "${slug}" "${url}"; continue; fi
    [[ -n "${name}" ]] || no_agent_name name "${slug}"
    pane="$(list_field "${name}" pane_id <<< "${LEAD_AGENTS}")"
    [[ -n "${pane}" ]] || continue
    if [[ -z "${read}" ]]; then read=1; claude="$(within "${STUCK_READ_WAIT}" claude agents --json </dev/null 2>/dev/null)" || claude=""; fi
    st="$(session_state "${name}" "${claude}" </dev/null)"
    [[ "${st}" != herdr ]] || st="herdr:$(list_field "${name}" agent_status <<< "${LEAD_AGENTS}")"
    case "${st}" in
      idle|herdr:idle|herdr:done) ;;
      unknown|herdr:unknown) stuck_seen "${slug}" "${url}"; continue ;;
      *) continue ;;
    esac
    ! bg_running "${name}" || continue
    ! stuck_test_run "${pane}" || continue
    STUCK_PRS+=" ${url}"
    echo "stuck: ${slug} ${url} (${kind} pending ${STUCK_MINUTES} min), exit: swarm.sh tell ${slug} resume <file>"
  done <<< "${rows}"
  mkdir -p "${LEAD_DIR}" 2>/dev/null && printf '%s' "${rec}" > "${LEAD_PR_HEADS}.tmp" && mv -f "${LEAD_PR_HEADS}.tmp" "${LEAD_PR_HEADS}" || true
}

# stuck_seen <slug> [PR URL] — print the stuck: lines LEAD_SEEN has for <slug> (and that PR), and note their PRs in
# STUCK_PRS, for a PR stuck_lines cannot check this poll.
stuck_seen() {
  local line u
  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    u="${line#stuck: "$1" }"; u="${u%% *}"
    STUCK_PRS+=" ${u}"; echo "${line}"
  done < <(awk -v s="$1" -v u="${2:-}" '$1 == "stuck:" && $2 == s && (u == "" || $3 == u)' "${LEAD_SEEN}" 2>/dev/null || true)
}

# stuck_test_run <pane> — succeed when a test suite runs under <pane>'s shell (panes.py's test_running, as
# agents.sh's test_running reads it), with herdr's process info read within STUCK_READ_WAIT seconds: a read that
# fails or hangs sees no run.
stuck_test_run() {
  local info
  info="$(within "${STUCK_READ_WAIT}" herdr pane process-info --pane "$1" </dev/null 2>/dev/null)" || info=""
  # shellcheck disable=SC2154 # assigned in another file
  SWARM_LIB="${SWARM_HOME}/bin/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["SWARM_LIB"]); from panes import test_running
sys.exit(0 if test_running(*sys.argv[1:3]) else 1)' "${info}" "${CFG_stall_minutes}"
}

# main_red_lines — `main-red: <short sha> <owner/repo> <base> (<red checks>), exit: <exit>`, one line per red base:
# its red main in events.tsv (red_mains: a main-red no main-green has cleared, whoever logged it), else the head
# the last heads pass read red there (LEAD_BASES, lead_bases). The checks are cut by ci_data. The exit follows
# fix-main-<short sha>: `fix-main-<short sha> waits on the lead: handle its held: or escalated: line` when it is
# held or escalated; `wait for fix-main-<short sha>, whose build has started, to merge` once its build has begun
# or it is in review; `build fix-main-<short sha>, which next names first` while next would name it (main_red's
# test: buildable, no build begun), or, when main_red picks another base's red over it, `build fix-main-<short
# sha>, which next names after fix-main-<the pick's short sha>`; `fix-main-<short sha> is not one next builds:
# check its status and kind` otherwise. With no story yet, it is what main_red_fix wrote for that head this poll
# (LEAD_FIXES): `wait for fix-main-<short sha>, which a fix-main run is writing and next then names first` while
# a run is going or due, `read .swarm/lead/fix-main-<short sha>.log, as no run wrote fix-main-<short sha>, then
# fix <base> by hand` once every run failed, and `fix <base> by hand, as no fix-main story covers it yet` with
# no row (a logged red whose story has left the board) or for a head red only on checks the base does not
# require (skip). It reads events.tsv, those files and the board, never gh.
main_red_lines() {
  local sha repo base checks out f reds pick st
  reds="$(red_mains)"; pick="$(main_red)"; pick="${pick%% *}"
  while read -r sha repo base checks; do
    [[ -n "${base}" ]] || continue
    f="${BOARD}/stories/fix-main-${sha:0:7}.md"
    if [[ ! -f "${f}" ]]; then
      # No story yet: what main_red_fix wrote for this head this poll says why.
      st="$(awk -v k="${repo} ${base} ${sha}" '$1 " " $2 " " $3 == k { print $8; exit }' "${LEAD_FIXES}" 2>/dev/null)" || st=""
      if [[ "${st}" == failed ]]; then out="read .swarm/lead/fix-main-${sha:0:7}.log, as no run wrote fix-main-${sha:0:7}, then fix ${base} by hand"
      elif [[ -n "${st}" && "${st}" != skip ]]; then out="wait for fix-main-${sha:0:7}, which a fix-main run is writing and next then names first"
      else out="fix ${base} by hand, as no fix-main story covers it yet"; fi
    elif [[ -n "$(get_fm "${f}" held_for)" ]] || is_escalated "${f}"; then out="fix-main-${sha:0:7} waits on the lead: handle its held: or escalated: line"
    elif one_off_started "fix-main-${sha:0:7}" || [[ "$(fm "${f}" status)" == review ]]; then out="wait for fix-main-${sha:0:7}, whose build has started, to merge"
    elif buildable_story "${f}"; then
      if [[ -z "${pick}" || "${pick}" == "${sha}" ]]; then out="build fix-main-${sha:0:7}, which next names first"
      else out="build fix-main-${sha:0:7}, which next names after fix-main-${pick:0:7}"; fi
    else out="fix-main-${sha:0:7} is not one next builds: check its status and kind"; fi
    echo "main-red: ${sha:0:7} ${repo} ${base} ($(ci_data <<< "${checks}")), exit: ${out}"
  done < <(printf '%s\n' "${reds}"
    # FILENAME, not FNR == NR: the first file may be empty.
    awk 'FILENAME == ARGV[1] { if (NF) logged[$2 " " $3] = 1; next }
      $4 == "red" && !(($1 " " $2) in logged) { c = ""; for (i = 6; i <= NF; i++) c = c " " $i; print $3 " " $1 " " $2 c }' \
      <(printf '%s\n' "${reds}") "${LEAD_BASES}" 2>/dev/null)
}

# main_red_fix — for each base head the last heads pass read red (LEAD_BASES) that no main-red covers (key_reds
# live: none logged, or one a main-green has cleared), start `swarm.sh _fix-main <repo> <base> <sha>`
# (main_red_run), which writes its fix-main story. <repo> is the board's name for the repo (LEAD_REPOS, `.` for
# the project's own). The run is detached in a session of its own (setsid, as upgrade_detach), pinned to the
# project (SWARM_PROJECT), its log reads cut to LEAD_FIX_LOG_SECONDS, its output appended to
# .swarm/lead/fix-main-<short sha>.log, so neither wait --lead returning nor lead_lock stopping it ends it.
# None starts while a run for that head is alive, while ps shows a `swarm.sh merge` of a PR in that repo (ps
# shows neither the base nor the project, so any such merge holds it: its own fix_main may log the red), while
# ps cannot be read, or while this run has not resolved the repo's name. A run that is gone with the red still
# not logged failed, and a later poll starts the next, up to LEAD_FIX_TRIES a head; one alive past
# LEAD_FIX_SECONDS is stopped and counts as failed. Each stop and each failed run gets a line in the run's log,
# which a killed run leaves with nothing of its own. A run whose log ends `stale:` found the pass's read out of
# date (main_red_run) and counts as none; no run starts for that head again until a heads pass has rewritten
# LEAD_BASES since. One whose log ends `not required:` found the head red only on checks the base does not
# require, which the next pass clears at once (clear_red_main); it counts as none, and no run starts for that
# head again (state skip). One whose log ends `absent:` waited on a required check with no run: it counts, and
# the next starts only after a heads pass too, so a check that never reports ends in the lead's check. It writes `<owner/repo> <base> <sha> <at> <runs> <pid> <started> <state>` a head to
# LEAD_FIXES, for main_red_lines: <at> as LEAD_BASES has it, so a head read red again after it read green
# starts afresh, <runs> the runs that count, and <state> run, wait, stale, absent, skip or failed (every run failed). A
# repo this run has not named keeps its row's state, and no run starts for it. It reads LEAD_BASES, events.tsv,
# the logs' last lines and one ps (only when such a head is there), and calls no gh: the run does.
main_red_fix() {
  local nwo base sha v at x old runs pid started state name log ps="" got=0 psok=1 now rows
  rows="$(cat "${LEAD_BASES}" 2>/dev/null)" || rows=""
  [[ -n "${rows}" ]] || { rm -f "${LEAD_FIXES}"; return 0; }
  now="$(date +%s)"
  { : > "${LEAD_FIXES}.new"; } 2>/dev/null || return 0
  while read -r nwo base sha v at x; do
    [[ "${v}" == red && "${sha}" =~ ^[0-9a-f]{40}$ ]] || continue
    ! grep -qxF "${sha}" <<< "$(key_reds "${nwo} ${base}" live)" || continue
    old="$(awk -v k="${nwo} ${base} ${sha} ${at}" '$1 " " $2 " " $3 " " $4 == k { print $5, $6, $7, $8; exit }' "${LEAD_FIXES}" 2>/dev/null)" || old=""
    runs=0; pid=-; started=0; state="wait"; [[ -z "${old}" ]] || read -r runs pid started state <<< "${old}"
    log="${LEAD_DIR}/fix-main-${sha:0:7}.log"
    if (( got == 0 )); then got=1; ps="$(ps -A -ww -o pid=,command= 2>/dev/null)" || psok=0; fi
    if (( psok == 1 )) && awk -v p="${pid}" -v s="${sha}" '$1 == p && index($0, "swarm.sh _fix-main ") && index($0, s) { f = 1 } END { exit !f }' <<< "${ps}"; then
      state=run
      # Past its time: stop it, its session with it, once; the next poll counts it failed.
      if (( now - started >= LEAD_FIX_SECONDS )); then
        kill -TERM -- "-${pid}" 2>/dev/null || true
        x="wait --lead: stopped run ${runs} of ${LEAD_FIX_TRIES} after ${LEAD_FIX_SECONDS} s"
        [[ "$(tail -n 1 "${log}" 2>/dev/null)" == "${x}" ]] || echo "${x}" >> "${log}" 2>/dev/null || true
      fi
    elif (( psok == 1 )) && [[ "${state}" == run ]]; then
      # Gone since the last poll: failed, unless it found the pass's read out of date or the head red only on
      # checks the base does not require, which count as no run.
      case "$(tail -n 1 "${log}" 2>/dev/null)" in
        "stale: "*) runs=$((runs - 1)); state=stale ;;
        "not required: "*) runs=$((runs - 1)); state=skip ;;
        "absent: "*) state=absent ;;   # counted: the log says which required check never ran
        *) state="wait"; echo "wait --lead: run ${runs} of ${LEAD_FIX_TRIES} ended with no main-red logged: it failed" >> "${log}" 2>/dev/null || true ;;
      esac
    fi
    if (( psok == 0 )) || [[ "${state}" == run || "${state}" == skip ]]; then
      :   # alive, red only on checks the base does not require, or what is alive is not known: the row stays
    elif (( runs >= LEAD_FIX_TRIES )); then
      state=failed
    elif [[ ( "${state}" == stale || "${state}" == absent ) && ! "${LEAD_BASES}" -nt "${log}" ]]; then
      :   # until a heads pass reads the base again
    else
      name="$(awk -v r="${nwo}" 'tolower($2) == r && (n == "" || $1 == ".") { n = $1 } END { print n }' <<< "${LEAD_REPOS}")"
      if [[ -z "${name}" ]]; then
        # Its story's repo: is unknown (no story names it, or gh failed this run): no run, none counted, and the
        # row keeps this poll's state, so a gh failure does not change the line. A later pass that names it starts one.
        :
      elif awk -v u="https://github.com/${nwo}/pull/" \
          'index($0, "swarm.sh merge") { for (i = 1; i <= NF; i++) if (index(tolower($i), u) == 1) f = 1 } END { exit !f }' <<< "${ps}"; then
        state="wait"
      else
        runs=$((runs + 1)); started="${now}"; state=run
        echo "run ${runs} of ${LEAD_FIX_TRIES}, $(date -u +%Y-%m-%dT%H:%M:%SZ): swarm.sh _fix-main ${name} ${base} ${sha}" >> "${log}" 2>/dev/null || true
        SWARM_PROJECT="${PROJECT_DIR}" SWARM_FIX_MAIN_LOG_SECONDS="${LEAD_FIX_LOG_SECONDS}" \
          nohup python3 -I -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
          bash "${SWARM_HOME}/bin/swarm.sh" _fix-main "${name}" "${base}" "${sha}" >> "${log}" 2>&1 </dev/null &
        pid=$!
      fi
    fi
    echo "${nwo} ${base} ${sha} ${at} ${runs} ${pid} ${started} ${state}" >> "${LEAD_FIXES}.new"
  done <<< "${rows}"
  mv "${LEAD_FIXES}.new" "${LEAD_FIXES}" 2>/dev/null || true
}

# main_red_run <repo> <base> <sha> — swarm.sh _fix-main, which main_red_fix starts detached: CI on <base> of
# <repo> (the board's name for it, `.` for the project's own) is red at <sha>, and no main-red covers it. It
# resolves the repo's owner/repo (lead_nwo), reads <sha>'s CI again (ci_gate base, within BASE_CI_WAIT) for the
# red checks and their URLs (a red head's line holds those alone, not the checks still running), and hands them
# to fix_main with no merge named (MERGE_TARGET empty), which writes
# fix-main-<short sha> with <repo> as its repo: and logs main-red. First it reads <base>'s head (within
# BASE_HEAD_WAIT): the pass's read is out of date when the base has moved off <sha>, or <sha>'s CI reads green
# or pending now, and then it writes nothing and its last line is `stale: <why>`, which main_red_fix counts
# as no run. It writes nothing either when ci_gate fixed reads the head as its own red's fix (the base requires
# checks and each passed), as clear_red_main would on the next pass: its last line is then `not required:`.
# When none of the red checks is one the base requires (ci_gate required) and fixed waits on a required check, it
# writes nothing either: `absent: <checks>` for a required check with no run yet, which main_red_fix counts as a
# run, and `stale:` for one still running. It fails, writing nothing, on a bad argument, a repo it cannot resolve,
# or a head or CI it cannot read.
main_red_run() {
  local rc out head n why req hard names=()
  [[ "$3" =~ ^[0-9a-f]{40}$ ]] || die "_fix-main: '$3' is not a whole commit sha"
  [[ -n "$2" && ! "$2" =~ ${LEAD_REF_BAD} ]] || die "_fix-main: '$2' is not a branch name"   # loose-match: ok LEAD_REF_BAD is a regex on purpose
  rc=0; lead_nwo "$1" || rc=$?
  (( rc == 0 )) || die "_fix-main: cannot read the owner/repo of repo $1 ($( (( rc == 2 )) && echo "no clone or no origin" || echo "gh failed"))"
  head="$(within "${BASE_HEAD_WAIT}" gh api --jq .sha "repos/${LEAD_NWO}/commits/$2" </dev/null 2>/dev/null)" || head=""
  [[ "${head}" =~ ^[0-9a-f]{40}$ ]] || die "_fix-main: cannot read the head of $2; no fix-main story written"
  [[ "${head}" == "$3" ]] || { echo "stale: $2 is at ${head:0:7} now, not ${3:0:7}; no fix-main story written"; return 0; }
  rc=0; out="$(within "${BASE_CI_WAIT}" python3 "${SWARM_HOME}/bin/lib/ci_gate.py" base "${LEAD_NWO}" "$3" </dev/null 2>/dev/null)" || rc=$?
  case ${rc} in
    1) ;;
    0) echo "stale: CI on $2 at ${3:0:7} reads green now; no fix-main story written"; return 0 ;;
    2) echo "stale: CI on $2 at ${3:0:7} reads pending now; no fix-main story written"; return 0 ;;
    *) die "_fix-main: CI on $2 at ${3:0:7} could not be read (exit ${rc}); no fix-main story written" ;;
  esac
  # The red checks' names, as clear_red_main takes them from main-red.
  while IFS= read -r n; do [[ -z "${n}" ]] || names+=("${n}"); done \
    <<< "$(awk '{ n = split($0, c, "; "); for (i = 1; i <= n; i++) { sub(" \\((" r ")\\)( .*)?$", "", c[i]); print c[i] } }' r="${CI_CONCLUSIONS}" <<< "${out%%$'\n'*}")"
  rc=0; why="$(within "${BASE_CI_WAIT}" python3 "${SWARM_HOME}/bin/lib/ci_gate.py" fixed "${LEAD_NWO}" "$3" "$2" "$3" "$(board_paths)" \
    ${names[@]+"${names[@]}"} </dev/null 2>/dev/null)" || rc=$?
  if (( rc == 0 )); then
    echo "not required: CI on $2 at ${3:0:7} is red only on checks $2 does not require; no fix-main story written"; return 0
  fi
  # A red check the base requires (ci_gate required) is a red it requires, whatever fixed waits on: with a required
  # check absent, fixed counts every check, so its own red entries cannot tell. A list it cannot read names none.
  req="$(within "${BASE_CI_WAIT}" python3 "${SWARM_HOME}/bin/lib/ci_gate.py" required "${LEAD_NWO}" "$2" </dev/null 2>/dev/null)" || req=""
  hard=""; for n in ${names[@]+"${names[@]}"}; do if grep -qxF -- "${n}" <<< "${req}"; then hard=1; fi; done
  why="$(tr ';' '\n' <<< "${why%%$'\n'*}")"
  if (( rc == 1 )) && [[ -z "${hard}" ]]; then
    # A required check with no run yet, none failed: `absent:`, which counts as a run, so one that never reports
    # on the base ends in the lead's check after LEAD_FIX_TRIES heads passes, never in an endless wait.
    if grep -qF '(required, absent)' <<< "${why}"; then
      n="$(awk '/[(]required, absent[)]$/ { sub(/^ /, ""); sub(/ [(]required, absent[)]$/, ""); print }' <<< "${why}" | paste -sd, -)"
      echo "absent: CI on $2 at ${3:0:7} has no run yet of ${n}, which $2 requires, and no check it requires has failed; no fix-main story written"
      return 0
    fi
    # A required check still running, none failed: whether the red is one the base requires is not known, so the
    # next heads pass decides again.
    if grep -qE ' [(](queued|in_progress|waiting|requested|pending)[)]$' <<< "${why}" \
      && ! grep -qE " [(](${CI_CONCLUSIONS})[)]" <<< "${why}"; then   # loose-match: ok CI_CONCLUSIONS is a regex on purpose
      echo "stale: CI on $2 at ${3:0:7} has a check $2 requires still running; no fix-main story written"; return 0
    fi
  fi
  # shellcheck disable=SC2034 # fix_main, in merge.sh, reads both
  MERGE_TARGET="" FIX_MAIN_REPO="$1"
  fix_main "${LEAD_NWO}" "$3" "$2" "${out%%$'\n'*}"
}

# reported_lines — `reported: <epic> (<n> stories still an agent's), exit: swarm.sh conduct <epic>` for each
# conductor report on disk (conductor_report) while its group still has agent work (agent_work_left), n being
# how many stories it counts. start_conductor removes an earlier run's report, so the one on disk is the
# newest run's. conduct-backlog.report.md is the backlog's (-), with exit `swarm.sh conduct --backlog`.
# Reports pile up until a new conduct, so one grep of the stories' epic: lines (epic is no SET_FM_KEYS key,
# so the file's line is fm's) skips a report whose group no story names before agent_work_left's walk; any
# fix-main story turns the skip off, as it counts for the group whose conductor started it. No herdr or gh call.
reported_lines() {
  local f epic group n run named bare fix_main=""
  set -- "${PROJECT_DIR}"/.swarm/conduct-*.report.md
  [[ -f "$1" ]] || return 0
  named="$(grep -h '^epic:' "${BOARD}"/stories/*.md 2>/dev/null || true)"
  [[ -z "${named}" ]] || named="$(sed 's/^epic: *//; s/^ *$/-/' <<< "${named}" | tr '\n' ' ')"
  named=" ${named} "
  # A story with no epic: line is the backlog's; the README has none either.
  bare="$(grep -L '^epic:' "${BOARD}"/stories/*.md 2>/dev/null || true)"
  [[ "${bare//${BOARD}\/stories\/README.md/}" != *.md* ]] || named+="- "
  ! compgen -G "${BOARD}/stories/fix-main-*.md" > /dev/null || fix_main=1
  for f in "$@"; do
    [[ -f "${f}" ]] || continue
    epic="${f##*/conduct-}"; epic="${epic%.report.md}"
    group="${epic}"; run="${epic}"
    [[ "${epic}" != backlog ]] || { group=-; run=--backlog; }
    [[ -n "${fix_main}" || "${named}" == *" ${group} "* ]] || continue
    n="$(agent_work_left "${group}" count)" || continue
    echo "reported: ${epic} (${n} stories still an agent's), exit: swarm.sh conduct ${run}"
  done
}

# SIGN_STATUS_WAIT: how many seconds each of sign_blocked_lines' git reads of one builder's worktree may take.
SIGN_STATUS_WAIT=10

# sign_blocked_lines — `sign-blocked: <slug>, <slug> (their signing key is locked; unsigned work in their
# worktrees), exit: unlock your signing key in your shell (gpg-agent or ssh-agent), then swarm.sh tell
# <slug> resume <file> for each`, one line for every builder that cannot sign its work: its newest
# sign-blocked or sign-clear incident in events.tsv (sign_held's, which the conductors' wait --stall
# writes) is a sign-blocked one, it still runs in a pane of the poll's herdr list (LEAD_AGENTS), its
# worktree still holds uncommitted work (git status --porcelain), and its last commit is still the one
# the incident names (sign_held's `unsigned work since <time>`): a builder that committed since has signed,
# and no probe logs sign-clear for a builder that is not stalled. Each git read runs with
# GIT_OPTIONAL_LOCKS=0, so one cut off after SIGN_STATUS_WAIT seconds leaves no index.lock to fail the
# builder's next commit. A read that fails or is cut off says nothing: the builder stays on the line when
# the line in LEAD_SEEN names it (sign_seen), and is left off otherwise. A worktree that is gone drops it.
# The slugs are sorted, so the line reads the same each poll for LEAD_SEEN. It asks no signer: the line
# comes once a builder's stall check has run, so up to stall_minutes late. A poll with no herdr list keeps
# the sign-blocked: line LEAD_SEEN has.
sign_blocked_lines() {
  local name slug since src wt st at slugs=""
  [[ -f "${EVENTS_LOG}" ]] || return 0
  [[ -n "${LEAD_AGENTS_READ}" ]] || lead_agents
  if [[ -z "${LEAD_AGENTS_OK}" ]]; then grep '^sign-blocked: ' "${LEAD_SEEN}" 2>/dev/null || true; return 0; fi
  while IFS=$'\t' read -r name slug since; do
    [[ -n "$(list_field "${name}" pane_id <<< "${LEAD_AGENTS}")" ]] || continue
    src="$(repo_dir "$(fm "${BOARD}/stories/${slug}.md" repo 2>/dev/null)")" || continue
    wt="$(worktree_for "${src}" "${slug}")"
    [[ -d "${wt}" ]] || continue
    if ! st="$(within "${SIGN_STATUS_WAIT}" env GIT_OPTIONAL_LOCKS=0 git -C "${wt}" status --porcelain </dev/null 2>/dev/null)"; then
      ! sign_seen "${slug}" || slugs+="${slug}"$'\n'
      continue
    fi
    [[ -n "${st}" ]] || continue
    if ! at="$(within "${SIGN_STATUS_WAIT}" env GIT_OPTIONAL_LOCKS=0 TZ=UTC git -C "${wt}" log -1 --format=%cd \
          --date=format-local:%Y-%m-%dT%H:%M:%SZ </dev/null 2>/dev/null)"; then
      ! sign_seen "${slug}" || slugs+="${slug}"$'\n'
      continue
    fi
    [[ "${at}" == "${since}" ]] || continue
    slugs+="${slug}"$'\n'
  done < <(awk -F'\t' "${EVENT_OUTCOME_AWK}"'
    $2 == "incident" && (o = outcome($5)) ~ /^sign-(blocked|clear): / { l[$3] = o }
    END {
      for (n in l) if (l[n] ~ /^sign-blocked: /) {
        s = substr(l[n], 15); sub(/ .*/, "", s)
        t = l[n]; sub(/^[^(]*\(unsigned work since /, "", t); sub(/\)$/, "", t)
        print n "\t" s "\t" t
      }
    }' "${EVENTS_LOG}")
  [[ -n "${slugs}" ]] || return 0
  slugs="$(printf '%s' "${slugs}" | LC_ALL=C sort -u | paste -sd, - | sed 's/,/, /g')"
  echo "sign-blocked: ${slugs} (their signing key is locked; unsigned work in their worktrees), exit: unlock your signing key in your shell (gpg-agent or ssh-agent), then swarm.sh tell <slug> resume <file> for each"
}

# sign_seen <slug> — true when the sign-blocked: line in LEAD_SEEN names <slug>.
sign_seen() {
  awk -v s="$1" 'index($0, "sign-blocked: ") == 1 {
      l = substr($0, 15); sub(/ \(.*/, "", l); n = split(l, a, ", ")
      for (i = 1; i <= n; i++) if (a[i] == s) f = 1
    } END { exit !f }' "${LEAD_SEEN}" 2>/dev/null
}

# prompt_lines — `prompt: <agent> (<kind>), exit: <exit>` for each agent in a pane this project opened
# (own_panes) that the poll's herdr list (lead_agents) shows blocked, idle or done, and whose pane
# panes.py's stuck_kind finds stuck: on a prompt or dialog (prompt), an expired login (login), an API
# error (api-error) or manual mode (manual). A prompt with the manual-mode footer under it is manual
# for a ready story's builder (manual_slug), whose restart clears both, and for any other agent a
# prompt whose exit also turns manual mode off. Skipped: a retired agent (<name>-done), one whose agents.tsv role is in CO_WRITER_ROLES, and
# one a swarm.sh command is delivering to (resend_busy, over one ps read). While an upgrade runs
# (upgrade_holder) it reads nothing, as resend_pass. lead_wake runs it after resend_pass, inside that
# pass's read budget (LEAD_READ_DEADLINE: no read starts past it; RESEND_HERDR_WAIT seconds a read),
# and takes a pane resend_pass read this poll from LEAD_READS, never reading it twice; a pane
# resend_pass failed to read is not read again. LEAD_STUCK keeps each agent's key (herdr's status and
# the mtime of its Claude session log, - with none), what its pane showed and when it was last read.
# A pane last found clear is read again only when its key changed or STUCK_RECHECK seconds have passed;
# one last found stuck is read every poll, as a user can clear it with no turn. Agents are read in the
# order of their last read, oldest first, so slow reads that use up the budget leave the rest first in
# line for the next poll; its first read goes even past the deadline, so each poll reads at least one. An api-error line comes only while no `swarm.sh wait` naming the agent runs
# (resend_busy's wait mode, the same ps): a running wait resumes it, and ends once it stops resuming;
# meanwhile a line already in LEAD_SEEN stays. An agent skipped, unread or whose read failed keeps its
# line from LEAD_SEEN; a herdr list, ps, list parse or read directory that failed keeps every prompt:
# line there (prompt_seen); so a missed read neither drops a line nor wakes the lead with it again. A
# new stop wakes the lead even when its line reads the same, since LEAD_SEEN forgets the old line: a
# prompt, login or api-error found in a pane with no record (the agent came back in a new pane), or in
# one last found stuck after a turn (its session log changed). Manual mode is a state, not a stop: a
# builder in it answering prompts wakes no one again, and while it works (no candidate) its manual
# record and line are kept (key carry), so a poll that sees it working does not end the state. A pane
# resend_pass sent Enter to this poll (<pane>.sent in LEAD_READS) is not classified: its read is gone. The exit: for a prompt, the user answers it in
# its pane; for login, the user runs /login, then a resume tell; for api-error, read the pane and tell
# the user; for manual, a ready story's builder has its pane closed and then no_agent_exit's restart
# (restart refuses a builder herdr still lists; cut_record finds its story), and any other agent has
# the user turn manual mode off in its pane.
# STUCK_RECHECK: seconds after which a pane last found clear is read again with nothing changed: manual
# mode turned on, or a dialog opened at an idle box, needs no turn and no status change.
STUCK_RECHECK=300
# CO_WRITER_ROLES: the roles of agents that talk with the user in their own pane (/hld, /epic): their
# questions are the user's to answer there, never the lead's to pass on.
CO_WRITER_ROLES="hld epic"
LEAD_STUCK="${LEAD_DIR}/stuck"
LEAD_READS=""; LEAD_READ_DEADLINE=""
# prompt_wanted — true when the poll's herdr list may hold a pane this project opened (own_panes) whose
# agent is blocked, idle or done: one awk over the list's text, an object to a record, with no python.
# A record that names the pane but no status (an object a nested one split) counts, so it never skips
# a candidate; herdr's list covers every project's agents, so a status alone says nothing.
prompt_wanted() {
  local own
  own="$(own_panes | tr '\n' ' ')"
  [[ -n "${own// }" ]] || return 1
  awk -v own=" ${own} " 'BEGIN { RS = "{" }
    match($0, /"pane_id" *: *"[^"]*"/) {
      p = substr($0, RSTART, RLENGTH); sub(/^"pane_id" *: *"/, "", p); sub(/"$/, "", p)
      if (index(own, " " p " ") && ($0 !~ /"agent_status"/ || $0 ~ /"agent_status" *: *"(blocked|idle|done)"/)) { f = 1; exit }
    } END { exit !f }' <<< "${LEAD_AGENTS}"
}
# manual_slug <agent> — the story of a ready story's builder, the one full name its cut agent name maps
# to (cut_record, none when two share it); nothing for any other agent.
manual_slug() {
  local slug
  is_builder "$1" || return 0
  slug="$(cut_record "$1")" || return 0
  [[ -f "${BOARD}/stories/${slug}.md" && "$(fm "${BOARD}/stories/${slug}.md" status)" == ready ]] && echo "${slug}"
  return 0
}
# prompt_seen — the prompt: lines in LEAD_SEEN: what prompt_lines prints when it cannot check, so a
# stop already seen stays seen.
prompt_seen() { awk 'index($0, "prompt: ") == 1' "${LEAD_SEEN}" 2>/dev/null || true; }
prompt_lines() {
  local rows name pane key last lkey lkind lat at kind out slug footer dir n=0 tried=0 text state="" files=() kinds=() i backlog now
  [[ -n "${LEAD_AGENTS_READ}" ]] || lead_agents
  [[ -n "${LEAD_AGENTS_OK}" ]] || { prompt_seen; return 0; }
  if [[ -f "${UPGRADE_PID}" ]] && [[ -n "$(upgrade_holder)" ]]; then prompt_seen; return 0; fi
  # The candidates, oldest read first (LEAD_STUCK's time; never read, 0), then in herdr's order.
  rows="$(SWARM_PANES="$(own_panes)" SWARM_ROLES="${CO_WRITER_ROLES}" python3 -I -c '
import glob, json, os, re, sys
own, skip = set(os.environ["SWARM_PANES"].split()), set(os.environ["SWARM_ROLES"].split())
agents = {}
try:
    for l in open(sys.argv[1], encoding="utf-8", errors="replace"):
        f = l.rstrip("\n").split("\t")
        if len(f) == 7:
            agents[f[2]] = (f[1], f[6])
except OSError:
    pass
read = {}
try:
    for l in open(sys.argv[3], encoding="utf-8", errors="replace"):
        f = l.rstrip("\n").split("\t")
        if len(f) == 5 and f[4].isdigit():
            read[(f[0], f[1])] = (int(f[4]), f[3])
except OSError:
    pass
rows = []
for a in json.loads(sys.stdin.read())["result"]["agents"]:
    n, p, st = a.get("name") or "", a.get("pane_id"), a.get("agent_status")
    if p not in own or not re.fullmatch("[a-z][a-z0-9_-]*", n) \
            or not re.fullmatch("[A-Za-z0-9]+:[A-Za-z0-9]+", p) or re.search(r"-done\d*$", n):
        continue
    # Manual mode outlasts a turn: an agent at work whose pane last showed it keeps its record and line
    # (key carry, never read), so its next stop in manual mode is the same one.
    if st not in ("blocked", "idle", "done"):
        if read.get((n, p), (0, ""))[1] == "manual":
            rows.append((read[(n, p)][0], n, p, "carry"))
        continue
    role, sid = agents.get(n, ("", ""))
    if role in skip:
        continue
    at = "-"
    for path in glob.glob(os.path.join(glob.escape(sys.argv[2]), "*", glob.escape(sid) + ".jsonl")) if sid not in ("", "-") else []:
        try:
            at = str(os.stat(path).st_mtime_ns)
        except OSError:
            pass
    rows.append((read.get((n, p), (0, ""))[0], n, p, st + ":" + at))
for _, n, p, k in sorted(rows, key=lambda r: r[0]):
    print("\t".join((n, p, k)))' "${AGENTS_LOG}" "${CLAUDE_PROJECTS}" "${LEAD_STUCK}" <<< "${LEAD_AGENTS}" 2>/dev/null)" \
    || { prompt_seen; return 0; }
  [[ -n "${rows}" ]] || { rm -f "${LEAD_STUCK}"; return 0; }
  # With no process list, a delivery or a wait under way cannot be ruled out.
  NO_AGENT_PS="$(ps -A -ww -o command= 2>/dev/null)" || { prompt_seen; return 0; }
  dir="${LEAD_READS:-${LEAD_DIR}/reads}"
  mkdir -p "${dir}" 2>/dev/null || { prompt_seen; return 0; }
  backlog="$(conductor_name backlog)"; now="$(date +%s)"
  # Each agent's kind: - for a clear pane taken as it was, @<n> for a read to classify below, unread to keep.
  while IFS=$'\t' read -r name pane key; do
    last="$(awk -F'\t' -v n="${name}" -v p="${pane}" '$1 == n && $2 == p { print $3 "\t" $4 "\t" $5; exit }' "${LEAD_STUCK}" 2>/dev/null)" || last=""
    lkey="" lkind="" lat=""; [[ -z "${last}" ]] || IFS=$'\t' read -r lkey lkind lat <<< "${last}"
    kind=unread; text=""; at="${lat:-0}"
    if [[ "${key}" == carry ]] || resend_busy "${name}" "$([[ "${name}" != "${backlog}" ]] || echo 1)"; then :
    # resend_pass submitted the brief in this pane this poll: what it read is gone; the next poll reads.
    elif [[ -e "${dir}/${pane}.sent" ]]; then :
    elif [[ -f "${dir}/${pane}" ]]; then text="$(cat "${dir}/${pane}")"; at="${now}"
    elif [[ -e "${dir}/${pane}.fail" ]]; then at="${now}"
    elif [[ "${lkey}" == "${key}" && "${lkind}" == - && $((now - ${lat:-0})) -lt ${STUCK_RECHECK} ]]; then kind=-
    # The poll's first read of its own always goes, past the deadline too: with the oldest read first, a
    # poll whose budget went before it read anything (a loaded machine) still moves on by one.
    elif (( ! tried || SECONDS < ${LEAD_READ_DEADLINE:-$((SECONDS + 1))} )); then
      tried=1; at="${now}"; text="$(within "${RESEND_HERDR_WAIT}" herdr agent read "${pane}" --source recent-unwrapped </dev/null 2>/dev/null)" || text=""
    fi
    if [[ -n "${text}" ]]; then n=$((n + 1)); printf '%s' "${text}" > "${dir}/@${n}"; files+=("${dir}/@${n}"); kind="@${n}"; fi
    state+="${name}"$'\t'"${pane}"$'\t'"${key}"$'\t'"${kind}"$'\t'"${at}"$'\t'"${lkey:--}"$'\t'"${lkind:--}"$'\n'
  done <<< "${rows}"
  # One python classifies every pane read: its stuck_kind, manual for a prompt over the manual-mode
  # footer (a builder in manual mode is nearly always on a permission prompt), - for none.
  if [[ ${n} -gt 0 ]]; then
    while IFS= read -r i; do kinds+=("${i}"); done < <(SWARM_LIB="${SWARM_HOME}/bin/lib" python3 -I -c '
import os, re, sys
sys.path.insert(0, os.environ["SWARM_LIB"]); from panes import stuck_kind, MANUAL_MODE
for f in sys.argv[1:]:
    t = open(f, encoding="utf-8", errors="replace").read()
    k = stuck_kind(t) or "-"
    if k == "prompt":
        lines = t.splitlines()
        reply = max([i for i, l in enumerate(lines) if re.match("(⏺|●)", l)] or [-1])
        if any(MANUAL_MODE.match(l) for l in lines[reply + 1:]):
            k = "manual-prompt"
    print(k)' "${files[@]}" 2>/dev/null)
  fi
  # The new record: what each read found and when; an agent left unread keeps its last kind and key, so
  # its next poll reads it again, with its read time moved on only when a read was tried.
  : > "${LEAD_STUCK}.tmp" 2>/dev/null || true
  while IFS=$'\t' read -r name pane key kind at lkey lkind; do
    [[ -n "${name}" ]] || continue
    if [[ "${kind}" == @* ]]; then kind="${kinds[$((${kind#@} - 1))]:-unread}"; fi
    # A prompt over the manual-mode footer: manual for a ready story's builder, whose restart clears both;
    # for any other agent a prompt the user answers, turning manual mode off too, so each new one reminds.
    slug=""; footer=""; [[ "${kind}" != manual* ]] || slug="$(manual_slug "${name}")"
    if [[ "${kind}" == manual-prompt ]]; then if [[ -n "${slug}" ]]; then kind=manual; else kind=prompt; footer=1; fi; fi
    if [[ "${kind}" == unread ]]; then
      [[ "${at}" == 0 && "${lkey}" == - ]] || printf '%s\t%s\t%s\t%s\t%s\n' "${name}" "${pane}" "${lkey}" "${lkind/#-/unread}" "${at}" >> "${LEAD_STUCK}.tmp" 2>/dev/null || true
    else printf '%s\t%s\t%s\t%s\t%s\n' "${name}" "${pane}" "${key}" "${kind}" "${at}" >> "${LEAD_STUCK}.tmp" 2>/dev/null || true; fi
    # A wait naming it is still resuming it.
    if [[ "${kind}" == api-error ]] && resend_busy "${name}" "" wait; then kind=unread; fi
    case "${kind}" in
      prompt) out="the user answers it in pane ${pane}${footer:+, and turns manual mode off there}" ;;
      login) out="the user runs /login, then swarm.sh tell ${name} resume <file>" ;;
      api-error) out="herdr agent read ${name}, then tell the user what it shows" ;;
      manual)
        if [[ -n "${slug}" ]]; then out="herdr pane close ${pane} then $(no_agent_exit "${slug}")"
        else out="the user turns manual mode off in pane ${pane}"; fi ;;
      unread) awk -v p="prompt: ${name} (" 'index($0, p) == 1 { print; exit }' "${LEAD_SEEN}" 2>/dev/null || true; continue ;;
      *) continue ;;
    esac
    # A new stop: no record for this pane, or a stuck pane read again after a turn. A status change alone
    # (done, then idle) is the same stop, and manual mode is no stop.
    if [[ "${kind}" != manual ]] && { [[ "${lkey}" == - ]] \
         || [[ "${lkind}" =~ ^(prompt|login|api-error|manual)$ && "${key#*:}" != - && "${lkey#*:}" != "${key#*:}" ]]; }; then
      if awk -v p="prompt: ${name} (" 'index($0, p) != 1' "${LEAD_SEEN}" > "${LEAD_SEEN}.drop" 2>/dev/null; then
        mv -f "${LEAD_SEEN}.drop" "${LEAD_SEEN}" 2>/dev/null || true
      fi
      rm -f "${LEAD_SEEN}.drop"
    fi
    echo "prompt: ${name} (${kind}), exit: ${out}"
  done <<< "${state}"
  mv -f "${LEAD_STUCK}.tmp" "${LEAD_STUCK}" 2>/dev/null || true
}

# lead_agents — read `herdr agent list` once into LEAD_AGENTS, for everything in this poll that asks
# which agents are live (no_agent_lines). LEAD_AGENTS_OK is set when herdr answered within
# SWARM_LEAD_LIST_WAIT seconds (default HERDR_LIST_WAIT); a hung herdr counts as a failed list, so the
# poll's other lines still wake the lead. Outside herdr (HERDR_ENV unset) it asks nothing.
LEAD_AGENTS=""; LEAD_AGENTS_OK=""; LEAD_AGENTS_READ=""
lead_agents() {
  LEAD_AGENTS=""; LEAD_AGENTS_OK=""; LEAD_AGENTS_READ=1
  [[ "${HERDR_ENV:-}" == 1 ]] || return 0
  if LEAD_AGENTS="$(within "${SWARM_LEAD_LIST_WAIT:-${HERDR_LIST_WAIT}}" herdr agent list </dev/null 2>/dev/null)"; then
    LEAD_AGENTS_OK=1
  else
    LEAD_AGENTS=""
  fi
}

# NO_AGENT_STARTS: the commands whose ok line starts an agent on a story, and whose failed line is a start
# that failed. NO_AGENT_ASKS: the commands that, while one runs for a slug, may start or answer its agent
# (a tell pending). Each answers with its own events.tsv line, written when it exits.
NO_AGENT_STARTS="story escalate agent step-up _step-up restart review-agent"
NO_AGENT_ASKS="tell story review-agent step-up _step-up restart agent"
# NO_AGENT_LIVE: the agent names the poll's herdr list shows in panes this project opened (no_agent_lines).
NO_AGENT_LIVE=""

# no_agent_name <var> <name> — set <var> to agent_name <name>, with no subshell for a name that is
# already one: the poll names every ready story twice.
no_agent_name() {
  if [[ "$2" =~ ^[a-z][a-z0-9_-]*$ && ${#2} -le ${AGENT_NAME_MAX} ]]; then printf -v "$1" '%s' "$2"
  else printf -v "$1" '%s' "$(agent_name "$2")"; fi
}

# no_agent_events <slug name review-name epic>... — per slug (epic - for none), from one read of
# events.tsv in order: "<slug> <build> <event> <name> <review-name>". build is 1 when a builder's ok start
# is newer than its last ok close, - when the slug has no start line at all (never started), else 0.
# An ok upgrade line (its target the epic, backlog, or - for every agent) restarted its agents, so it
# counts as a start for the stories in its scope, but never clears a reopen: it restarts only running
# agents, and a reopened story's builder was not one. event is the time of the newest event that
# explains why no agent is there (an ok close of the builder or review agent, a failed start, a
# no-agent line) when no sign of a live agent (an ok start, an ok tell) and no hold line came after it,
# else -. A slug whose newest reconcile reopen (its PR
# closed unmerged) has no ok start after it is left out: unblock --startable names it for the lead from
# that reopen being its last event, which a lead-woken, no-agent or hold line would hide.
no_agent_events() {
  local log="${EVENTS_LOG}"
  [[ -f "${log}" ]] || log=/dev/null   # BSD awk stops at a missing file before its END
  awk -F'\t' -v rows="$*" -v starts=" ${NO_AGENT_STARTS} " "${EVENT_OUTCOME_AWK}"'
    BEGIN {
      n = split(rows, w, " ")
      # A close names the review agent in full (review-<slug>), herdr and agent lines by its cut name.
      for (i = 1; i + 3 <= n; i += 4) {
        own[w[i]] = own[w[i + 1]] = own[w[i + 2]] = own["review-" w[i]] = w[i]
        rev[w[i + 2]] = rev["review-" w[i]] = 1; order[++k] = w[i]; name[w[i]] = w[i + 1]; rname[w[i]] = w[i + 2]
        epic[w[i]] = w[i + 3]
      }
    }
    { o = outcome($5) }
    NF == 5 && $2 == "upgrade" && o ~ /^ok/ {
      for (x in epic) if ($3 == "-" || $3 == epic[x] || ($3 == "backlog" && epic[x] == "-")) ev[x] = ""
      next
    }
    NF == 5 && ($3 in own) {
      s = own[$3]; c = $2; sub(/:.*/, "", c); ok = o ~ /^ok/
      if ($2 == "step-up:failed") ev[s] = $1
      else if (index(starts, " " c " ")) {
        if (!($3 in rev)) tried[s] = 1
        if (!ok) ev[s] = $1
        else { ev[s] = ""; reo[s] = 0; if (c != "review-agent" && !($3 in rev)) build[s] = 1 }
      } else if (c == "close") {
        if (ok) { ev[s] = $1; if (!($3 in rev)) build[s] = 0 }
      } else if ($2 == "reconcile" && o == "ok (reopened)") reo[s] = 1
      else if ($2 == "no-agent") ev[s] = $1
      else if ((c == "tell" && ok) || $2 == "hold") ev[s] = ""
    }
    END { for (i = 1; i <= k; i++) { s = order[i]; if (!reo[s]) print s, (tried[s] ? build[s] + 0 : "-"), (ev[s] == "" ? "-" : ev[s]), name[s], rname[s] } }' \
    "${log}" 2>/dev/null || true
}

# no_agent_busy <slug> <name> <urls> — true while a process runs that answers for <slug> though no agent
# is listed: a tell pending (a swarm.sh NO_AGENT_ASKS command naming <slug> or its builder's <name>) or a
# `swarm.sh wait-pr` or `swarm.sh merge` on one of <urls>. Reads NO_AGENT_PS, one `ps` read, and only matches it:
# a command line may hold a token, so none is ever printed.
no_agent_busy() {
  awk -v s="$1" -v n="$2" -v urls=" $3 " -v asks=" ${NO_AGENT_ASKS} " '{
    m = split($0, w, " ")
    for (i = 1; i < m; i++) {
      if (w[i] !~ /(^|\/)swarm\.sh$/) continue
      for (j = i + 2; j <= m; j++)
        if ((index(asks, " " w[i + 1] " ") && (w[j] == s || w[j] == n)) || ((w[i + 1] == "wait-pr" || w[i + 1] == "merge") && index(urls, " " w[j] " "))) { f = 1; exit }
    } } END { exit !f }' <<< "${NO_AGENT_PS}"
}

# no_review_events <slug review-name>... — per slug with a review start on record since its newest ok
# `story` start or reopen, from one read of events.tsv: "<slug> <ok> <url> <under> <wrote>". ok is 1 when
# the newest `review-agent <slug>` line is ok, else 0. An ok `review-agent:next` line (review-<slug>'s next
# round, run in its own session) counts as an ok start: the review agent owns the PR again, so a findings
# tell before it says nothing about this round, and the brief on record is the one that agent started
# with. A failed one started no round and changes nothing. url is the PR URL a failed line's message names,
# when review_agent took it as one (never from its "is not a PR URL" refusal), else -. under is 1 when a round is under way by the
# events: a findings round came after that line (the builder fixing what it was told: a findings tell
# that is ok or that herdr sent, or a findings step-up, as review_rounds counts them, but not its refused
# --recheck, which leaves the builder nothing to fix), or that line is a
# start refused because the builder is still at work (its worktree not at the PR's head, or with
# uncommitted changes) with a findings round on record. wrote is 1 when that start wrote
# .swarm/briefs/review-<slug>.md: an ok one, or one that failed after the brief (review_start_failed's
# messages, or its mktemp), else 0: a preflight that fails leaves an earlier attempt's brief. A refusal that leaves an earlier ok start of this build, not closed since, in place
# (review-<slug> still reviewing, or its name still held: free_agent_name's refusals name it) changes
# nothing; with no such start, the name is held by something else, and the refusal is a failed start. A
# refusal of a head whose findings file passes it changes nothing either, whatever came before it. A slug whose
# ok start an ok close of review-<slug> (full or cut name) followed is left out: the close is the
# conductor's own act.
no_review_events() {
  local log="${EVENTS_LOG}"
  [[ -f "${log}" ]] || log=/dev/null   # BSD awk stops at a missing file before its END
  awk -F'\t' -v rows="$*" -v q="'" "${EVENT_OUTCOME_AWK}"'
    BEGIN {
      n = split(rows, w, " "); pr = "https://[^ " q "]*/pull/[0-9]+"
      for (i = 1; i + 1 <= n; i += 2) { me[w[i]] = 1; rn[w[i]] = w[i + 1]; rv[w[i + 1]] = rv["review-" w[i]] = w[i]; order[++k] = w[i] }
    }
    NF != 5 { next }
    { o = outcome($5) }
    ($3 in me) && (($2 == "story" && o ~ /^ok/) || ($2 == "reconcile" && o == "ok (reopened)")) {
      s = $3; on[s] = 0; told[s] = 0; next
    }
    ($3 in me) && ($2 == "review-agent" || ($2 == "review-agent:next" && o ~ /^ok/)) {
      s = $3; ok1 = o ~ /^ok/
      if (!ok1 && on[s] && ok[s] && !shut[s] && (index(o, " is still reviewing ") || index(o, rn[s] ": ") == 1 || index(o, "review-" s ": ") == 1)) next
      # A refusal of a head that passed its review starts nothing and leaves that review in place.
      if (!ok1 && index(o, "review-agent: ") == 1 && index(o, " is a pass of ")) next
      on[s] = 1; ok[s] = ok1; shut[s] = 0; url[s] = "-"; after[s] = 0
      wrote[s] = ok1 || o == "review-agent: mktemp failed; nothing was started" ||
        index(o, "review-agent: review-" s " did not start") == 1 || index(o, "review-agent: review-" s q "s start was unclear") == 1 ||
        index(o, "review-agent: review-" s " took its brief") == 1
      atwork[s] = !ok1 && (o ~ /worktree is at .*, not the PR.s head/ || o ~ /worktree has uncommitted changes/)
      # Only a URL review_agent took as one: every message but its "is not a PR URL" refusal names
      # a URL that passed its check.
      if (!ok1 && !index(o, " is not a PR URL") && match(o, pr))
        url[s] = substr(o, RSTART, RLENGTH)
      next
    }
    # A findings round, counted as review_rounds counts it: a tell that is ok or that herdr sent, or a
    # findings step-up, whose brief carried the findings in place of a tell. A --recheck refused with a
    # full round due, which review_rounds counts too, is left out: the builder has nothing to fix, and
    # the review agent runs that round itself (--next), so with it gone no review is under way.
    ($3 in me) && ((($2 == "tell" || $2 == "tell:findings") && (o == "ok" || o ~ /herdr sent it the brief/)) ||
      ($2 == "escalate" && o ~ /^ok \(findings-[0-9]+:/)) { told[$3] = 1; after[$3] = 1; next }
    ($3 in rv) && $2 ~ /^close(:|$)/ && o ~ /^ok/ { shut[rv[$3]] = 1 }
    END {
      for (i = 1; i <= k; i++) {
        s = order[i]
        if (on[s] && !(ok[s] && shut[s])) print s, ok[s] + 0, url[s], (after[s] || (atwork[s] && told[s])) ? 1 : 0, wrote[s] + 0
      }
    }' "${log}" 2>/dev/null || true
}

# review_brief_url <slug> — the PR URL on the first line of .swarm/briefs/review-<slug>.md (review_brief
# writes `Review <PR URL>, the PR of story <slug>, ...`), or nothing.
review_brief_url() {
  sed -n '1s/^Review \(https:[^ ,]*\), the PR of story .*/\1/p' "${PROJECT_DIR}/.swarm/briefs/review-$1.md" 2>/dev/null || true
}

# no_review_pr <slug> <wrote> <prs> — the PR a review of <slug> is for, when no failed start named one:
# the URL on the first line of .swarm/briefs/review-<slug>.md when the newest start wrote that brief
# (<wrote> 1), else <prs> when it holds one URL, else nothing: a preflight that failed cannot be tied
# to an earlier attempt's brief, and with several PRs, not to one of them.
no_review_pr() {
  local u=""
  [[ "$2" != 1 ]] || u="$(review_brief_url "$1")"
  [[ -n "${u}" || "$3" == *" "* ]] || u="$3"
  printf '%s' "${u}"
}

# review_restart_try <slug> — whether a review-agent start of <slug> was cut short, from events.tsv since
# the newest ok `story` start or reopen, or ok `review-agent` start: `restart <N>` when the newest outcome is a
# start that ran nothing (a `review-agent` line ending (try N of STARTS_PER_REVIEW)) or wait --lead's
# restart (a `review-agent:restart` line), a trailing `interrupted` changing nothing, and fewer than
# STARTS_PER_REVIEW tries are spent; `unclear <N>` when try N began (its `review-agent:try` line) and has
# no outcome, so it may have sent the brief; else nothing. The tries spent are the highest try number
# on record, since each try takes the next: a restart's own command logs its try again, so a count of
# lines would count that try twice, and a restart line always raises the number, so the restarts stop.
review_restart_try() {
  local log="${EVENTS_LOG}"
  [[ -f "${log}" ]] || return 0
  awk -F'\t' -v s="$1" -v max="${STARTS_PER_REVIEW}" "${EVENT_OUTCOME_AWK}"'
    function num(t) { sub(/.*\(try /, "", t); sub(/ of .*/, "", t); return t + 0 }
    NF != 5 || $3 != s { next }
    { o = outcome($5) }
    ($2 == "story" && o ~ /^ok/) || ($2 == "reconcile" && o == "ok (reopened)") || ($2 == "review-agent" && o ~ /^ok/) {
      hi = 0; go = 0; open = 0; next
    }
    $2 == "review-agent:try" && o ~ /^\(try [0-9]+ of [0-9]+\) started$/ { n = num(o); if (n > hi) hi = n; open = n; next }
    $2 == "review-agent:restart" && o ~ /^started \(try [0-9]+ of [0-9]+\)$/ { n = num(o); if (n > hi) hi = n; go = 1; open = 0; next }
    $2 != "review-agent" || o == "interrupted" { next }
    o ~ / \(try [0-9]+ of [0-9]+\)$/ { n = num(o); if (n > hi) hi = n; go = 1; open = 0; next }
    { go = 0; open = 0 }
    END { if (open) print "unclear", open; else if (go && hi < max) print "restart", hi + 1 }' "${log}" 2>/dev/null || true
}

# review_restart <slug> <PR URL> <try> — wait --lead's restart of review-<slug> at try <try>: log it first
# (review-agent:restart, which review_restart_try counts, so a restart killed before its own line still
# spends its try), then run swarm.sh review-agent detached, as upgrade_detach runs its worker, pinned to
# this project, with SWARM_START_TRY for its first try and its output in .swarm/lead/review-<slug>.restart.
# The poll runs inside lead_queue's $(...): every stream of the child is a file, so the poll never waits
# on it, and while it runs no_agent_busy keeps the next poll quiet. Two polls can overlap while a new
# wait --lead takes over, and the second's ps read may come before the first's start. So it holds <slug>'s
# restart lock (mkdir, tried once), and under it starts nothing while the last restart's pid, in
# .swarm/lead/review-<slug>.restart.pid, is alive, or unless review_restart_try still says this try: the
# second poll reads the first one's restart line and pid. False when it started nothing. A poll killed
# holding the lock leaves it, as does a pid another process took since, and the story then gets its line
# with no restart until the lock is removed or that process ends.
review_restart() {
  local outf="${LEAD_DIR}/review-$1.restart" lock="${LEAD_DIR}/review-$1.restart.lock" pid rc=1
  mkdir -p "${LEAD_DIR}" 2>/dev/null || true
  perl -e 'mkdir shift or exit 1' "${lock}" 2>/dev/null || return 1
  pid="$(cat "${outf}.pid" 2>/dev/null)" || pid=""
  if ! { [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; } && [[ "$(review_restart_try "$1")" == "restart $3" ]]; then
    record_event review-agent:restart "$1" "started (try $3 of ${STARTS_PER_REVIEW})"
    SWARM_START_TRY="$3" SWARM_PROJECT="${PROJECT_DIR}" nohup python3 -I -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
      "${BASH}" "${SWARM_HOME}/bin/swarm.sh" review-agent "$1" "$2" </dev/null > "${outf}" 2>&1 &
    echo "$!" > "${outf}.pid"; rc=0
  fi
  rmdir "${lock}" 2>/dev/null || true
  return "${rc}"
}

# no_review_line <slug> <fields> <prs repo> [record] — `no-review: <slug> <pr>, exit: swarm.sh review-agent
# <slug> <pr>, or the fallback reviewer` for a story whose review agent never started or started and
# went (no_agent_lines' review case), from <fields>, its no_review_events line past the slug, and the
# poll's NO_AGENT_LIVE list and NO_AGENT_PS. Nothing while a round is under way: review-<slug> listed,
# a round the events show (no_review_events' under), or a process that answers for the story: a tell,
# a start, or a wait-pr or merge on its PR, on prs:, or on its review brief's (no_agent_busy). Nothing either for an ok start with no
# .swarm/reviews/<slug>.head, or with a findings file that passes on that head (review_pass). A URL a
# failed line names counts only when <prs> is empty or holds it. With no PR known, the exit finds it
# first, as no_agent_exit's does. A start cut short (review_restart_try) takes its PR from its brief
# when that names one, over prs: and the rest: its command wrote that brief. With record (wait --lead's poll), one with
# tries left and a PR is started again at its next try (review_restart), and the line says
# ` (started <N> of STARTS_PER_REVIEW)` after the PR; next, status and dash only read. A try cut off
# mid-start is never started again: its line says so and names the lead's check.
no_review_line() {
  local slug="$1" ok url under wrote prs repo rname f="${PROJECT_DIR}/.swarm/reviews/$1.md" head origin what n brief note="" check=""
  read -r ok url under wrote <<< "$2"; read -r repo prs <<< "$3"
  [[ "${repo}" != - ]] || repo=""
  no_agent_name rname "review-${slug}"
  ! grep -qxF -e "${rname}" <<< "${NO_AGENT_LIVE}" || return 0
  [[ "${under}" == 0 ]] || return 0
  if [[ "${ok}" == 1 ]]; then
    [[ -s "${f%.md}.head" ]] || return 0
    head="$(cat "${f%.md}.head")"
    ! review_pass "${slug}" "${head}" || return 0
  fi
  [[ "${url}" == - || -z "${prs}" || " ${prs} " == *" ${url} "* ]] || url=-
  [[ "${url}" != - ]] || url="$(no_review_pr "${slug}" "${wrote}" "${prs}")"
  # A wait-pr or merge on the PR of any earlier start of this review answers for the story too.
  ! no_agent_busy "${slug}" "${rname}" "${prs} ${url} $(review_brief_url "${slug}")" || return 0
  read -r what n <<< "$(review_restart_try "${slug}")"
  # A start cut short wrote its brief before its first try, so the brief names its PR, whatever prs: holds.
  [[ -z "${what}" ]] || { brief="$(review_brief_url "${slug}")"; [[ -z "${brief}" ]] || url="${brief}"; }
  if [[ "${what}" == restart && -n "${url}" && "${4:-}" == record ]]; then
    ! review_restart "${slug}" "${url}" "${n}" || note=" (started ${n} of ${STARTS_PER_REVIEW})"
  elif [[ "${what}" == unclear ]]; then
    note=" (try ${n} of ${STARTS_PER_REVIEW} was cut off mid-start and may have sent the brief)"
    check="check that no pane holds review-${slug} (swarm.sh status, then swarm.sh tidy for an empty one), then "
  fi
  if [[ -z "${url}" ]]; then
    origin="$(git -C "$(repo_dir "${repo}")" remote get-url origin 2>/dev/null)" || origin="<its repo's origin>"
    echo "no-review: ${slug}${note}, exit: ${check}gh pr list -R ${origin} --head story/${slug}, then swarm.sh review-agent ${slug} <PR URL>, or the fallback reviewer"
    return 0
  fi
  echo "no-review: ${slug} ${url}${note}, exit: ${check}swarm.sh review-agent ${slug} ${url}, or the fallback reviewer"
}

# pr_words <prs value> — a prs: value's URLs, space-separated: split on spaces and commas as pr_stories
# splits them, YAML's [ ] and quotes gone. No subshell, so the poll can split every story's.
PR_WORDS=""
pr_words() {
  local v="${1//[][\"\']/}" u
  PR_WORDS=""
  for u in ${v//,/ }; do PR_WORDS+="${PR_WORDS:+ }${u}"; done
}

# story_prs <story-file> — its prs: URLs, space-separated (pr_words).
story_prs() { pr_words "$(fm "$1" prs)"; printf '%s' "${PR_WORDS}"; }

# stories_fm <key>... — one line per story on the board, read in one pass: its slug, then each key's
# value, separated by \x1f (not a tab: read merges empty fields between tabs). A value is fm's: the
# state file's (BOARD_STATE_DIR) unless the front matter changed from its <key>@base: line, else the
# front matter's first <key>: line. A story file or state file that is there but unreadable when the
# board is listed is named on stderr, its story left out, and stories_fm fails. awk then opens each
# file itself (getline) and takes one it cannot open as gone since the list, saying nothing: a story
# file a merge deleted is left out, and a state file gone (emptied or dropped) is read as none. One
# made unreadable in that gap is left out too, and the next call's check names it (a wait --lead poll
# calls stories_fm more than once).
stories_fm() {
  local f s files=() n=0 rc=0
  for f in "${BOARD}"/stories/*.md; do
    [[ -e "${f}" && "${f##*/}" != README.md ]] || continue
    s="${f##*/}"; s="${BOARD_STATE_DIR}/stories/${s%.md}"
    [[ -r "${f}" ]] || { [[ ! -e "${f}" ]] || { echo "swarm: cannot read ${f}" >&2; rc=1; }; continue; }
    [[ ! -f "${s}" || -r "${s}" ]] || { echo "swarm: cannot read ${s}" >&2; rc=1; continue; }
    files+=("${f}"); n=$((n + 1))
    [[ ! -f "${s}" ]] || files+=("${s}")
  done
  [[ ${n} -gt 0 ]] || return "${rc}"
  awk -v keys="$*" -v sdir="${BOARD_STATE_DIR}/stories/" '
    function val(l, k) { l = substr(l, length(k) + 1); sub(/^ +/, "", l); sub(/\r$/, "", l); return l }
    function flush(   i, k, v, line) {
      if (slug == "") return
      line = slug
      for (i = 1; i <= nk; i++) { k = K[i]; v = ((k in st) && (!(k in base) || base[k] == own[k])) ? st[k] : own[k]; line = line "\x1f" v }
      print line
    }
    BEGIN {
      nk = split(keys, K, " ")
      for (a = 1; a < ARGC; a++) {
        # Read here alone: POSIX lets an awk whose BEGIN calls getline read ARGV after it.
        f = ARGV[a]; delete ARGV[a]
        if (index(f, sdir) == 1) {
          while (slug != "" && (getline l < f) > 0)
            for (i = 1; i <= nk; i++) {
              if (!(K[i] in st) && index(l, K[i] ":") == 1) st[K[i]] = val(l, K[i] ":")
              if (!(K[i] in base) && index(l, K[i] "@base:") == 1) base[K[i]] = val(l, K[i] "@base:")
            }
          close(f); continue
        }
        flush(); slug = f; sub(/.*\//, "", slug); sub(/\.md$/, "", slug)
        n = 0; got = 0; split("", own); split("", st); split("", base)
        while ((r = (getline l < f)) > 0) {
          got = 1
          if (l == "---") n++
          else if (n == 1) for (i = 1; i <= nk; i++) if (!(K[i] in own) && index(l, K[i] ":") == 1) own[K[i]] = val(l, K[i] ":")
        }
        close(f)
        # Gone since the list, or empty (no line, as before): left out.
        if (r < 0 || !got) slug = ""
      }
      flush()
    }' "${files[@]}" || return
  return "${rc}"
}

# no_agent_theirs <slug> <status> <prs> — true for a story in review that is the user's to merge: a PR
# held for their merge (pr_held, as costs_tag asks, on prs: split on commas too), or the story's own
# costs: or its parents' (money_walk), which also holds one whose prs: is still empty.
no_agent_theirs() {
  local u
  [[ "$2" == review ]] || return 1
  [[ -z "$(money_walk "$1")" ]] || return 0
  for u in $3; do [[ -z "$(pr_held "${u}")" ]] || return 0; done
  return 1
}

# no_agent_exit <slug> — what the lead does for a no-agent: line, never an unpinned merge. A ready story:
# `swarm.sh restart <slug>` (restart_build), or `swarm.sh hold <slug> <reason>`; only the hold when
# restart would refuse it as no_agent_lines lets it through: held_by:, no worktree (a branch left), or no
# builder in agents.tsv (a first start that failed before it was recorded). A story in review with one PR whose findings file is a pass on its
# 40-hex head: line (review_pass): `swarm.sh merge --head <sha> <pr>` (merge refuses a head that moved
# since). With several PRs, which one head cannot pin, or no passing review, `swarm.sh review-agent
# <slug> <pr>` for each. A story in review with no PR URL: find it by hand in the story's repo (gh pr
# list -R <its origin> --head story/<slug>, as open_pr asks), then the review-agent exit; hold takes
# only a ready story, so it is never that.
no_agent_exit() {
  local f="${BOARD}/stories/$1.md" head u prs src out="" url
  prs="$(story_prs "${f}")"
  if [[ "$(fm "${f}" status)" != review ]]; then
    if [[ -z "$(get_fm "${f}" held_by)" && -n "$(builder_model "$1")" ]] && src="$(repo_dir "$(fm "${f}" repo)")" \
       && [[ -d "$(worktree_for "${src}" "$1")" ]]; then
      echo "swarm.sh restart $1, or swarm.sh hold $1 <reason>"
    else echo "swarm.sh hold $1 <reason>"; fi
    return 0
  fi
  if [[ -z "${prs}" ]]; then
    url="$(git -C "$(repo_dir "$(fm "${f}" repo)")" remote get-url origin 2>/dev/null)" || url="<its repo's origin>"
    echo "gh pr list -R ${url} --head story/$1, then swarm.sh review-agent $1 <PR URL>"; return 0
  fi
  head="$(sed -n 's/^head: *//p' "${PROJECT_DIR}/.swarm/reviews/$1.md" 2>/dev/null | head -1)"
  if [[ "${head}" =~ ^[0-9a-f]{40}$ && "${prs}" != *" "* ]] && review_pass "$1" "${head}"; then
    echo "swarm.sh merge --head ${head} ${prs}"; return 0
  fi
  for u in ${prs}; do out+="${out:+, then }swarm.sh review-agent $1 ${u}"; done
  echo "${out}"
}

# no_agent_granted <slug> — true when the agreed HLD over the story (item_hld) grants merge (hld_grants):
# under merge = human the lead, not the user, merges its PR once it is reviewed, so a review agent gone
# leaves it unreviewed with no one to act. Board files only, no gh; a grants: that cannot be read grants
# nothing.
no_agent_granted() {
  local h g
  h="$(item_hld "${BOARD}/stories/$1.md")"
  [[ -n "${h}" ]] && g="$(hld_grants "${h}" 2>/dev/null)" && grep -qxF merge <<< "${g}"
}

# no_agent_lines [record] — `no-agent: <slug>, exit: <exit>` (no_agent_exit) for each started story that
# no agent works on and that is not the user's to move: status ready, or review under merge = agent;
# of a kind an agent builds, so never kind: lead, held or escalated; not kept: or costs: money
# (waiting_on_user hands those to the user); with a build record (an ok builder start no close ended,
# or, for a slug with a start line, its worktree or story/<slug> branch, build_exists); not in the
# scope of an upgrade running here (upgrade_holder), which stops and restarts agents; no pane this
# project opened (own_panes) listed under its builder's or review-<slug>'s name; no tell pending and no
# wait-pr or merge on its PR (no_agent_busy); and, for a ready story, no .swarm/briefs/<slug>.step-up
# marker. It prints one only when an event explains the agent's absence (no_agent_events); with record
# set, a story with none gets a `no-agent <slug>` events.tsv line, so the next poll prints it, and
# no_review_line may start a review agent again (its restart of a start cut short). A hold
# line answers the alert until a new event: the next poll writes one. A ready story with a .step-up
# marker gets `step-up failed: <slug>, exit: swarm.sh step-up --resume <slug>` instead, unless its
# step-up still runs (step_up_running), or a pane is listed under its builder's name while the marker
# does not say the old builder was closed (step_up_closed). Each story with a build record, whether
# its builder is listed or not, also gets no_review_line's `no-review:` line when its review agent
# never started or started and went (no_review_events): a build a close cleared has no PR to review.
# Under merge = human, a story in review whose HLD grants merge (no_agent_granted, read once per such
# story, after the cheaper checks) gets that no-review: line only once its builder's build ended (an ok
# close after its newest start): its builder's close after the handover (swarm.sh review, then close)
# is the normal path, and the lead's merge: item covers the PR. A builder started again since, to fix
# a later review's findings, and gone with no close still gets its no-agent: line.
# Cost: the poll's herdr list (lead_agents, read here when the poll has none); every story's front
# matter in one pass (stories_fm), a review story's epic chain and HLD under merge = human
# (no_agent_granted), events.tsv once (no_agent_events), then once more
# (no_review_events) for the stories with a build record, and once more for each that reaches its
# no-review: line (review_restart_try); per story only for one that passed those: its
# costs: walk (a review story), git (a start line but no current builder, or no-review: with no PR
# known), then herdr's JSON and one ps once a started story or a marker is left. No gh. dash (dash_render) hands it its own herdr list
# instead, in LEAD_AGENTS and LEAD_AGENTS_OK with LEAD_AGENTS_READ set, so it runs from outside a herdr
# pane too. Prints nothing and returns 2 when it could not check: no herdr list (outside a pane,
# unless dash handed it one), or herdr's list, its JSON or ps failed. Returns 0 once it has checked,
# with or without lines.
no_agent_lines() {
  local live slug st kind held kept e repo prs rows="" data="" built="" build ev src name rname up="" d marked="" revs="" rv fields said="" revonly="" handed=""
  [[ -n "${LEAD_AGENTS_READ}" ]] || lead_agents
  [[ -n "${LEAD_AGENTS_OK}" ]] || return 2
  if [[ -f "${UPGRADE_PID}" ]] && up="$(upgrade_holder)"; then up="${up%% *}"; else up=""; fi
  while IFS=$'\x1f' read -r slug st kind held kept e repo prs; do
    # shellcheck disable=SC2154 # CFG_merge is assigned in another file
    case "${st}" in
      ready) ;;
      review) [[ -z "${kept}" ]] || continue ;;
      *) continue ;;
    esac
    # Not kind: lead, which every escalated story is (lead_block), and a held one too.
    agent_kind "${kind}" && [[ -z "${held}" ]] || continue
    # Under merge = human, a review story counts only under a merge grant. Its builder's line is dropped
    # once the handover closed it (handed, below), so it gets no-review: alone; a builder started again,
    # to fix a later review's findings, and gone with no close still gets its no-agent: line.
    if [[ "${st}" == review && "${CFG_merge}" != agent ]]; then
      no_agent_granted "${slug}" || continue
      revonly+=" ${slug}"
    fi
    # A step-up runs only on a ready story, so only a ready one's marker is a failed step-up. It is
    # reported while an upgrade runs too: the upgrade restarts agents, and this story has none.
    if [[ "${st}" == ready && -e "${PROJECT_DIR}/.swarm/briefs/${slug}.step-up" ]]; then marked+=" ${slug}"; continue; fi
    e="${e:--}"
    [[ -z "${up}" || ( "${up}" != - && "${up}" != "${e}" && ! ( "${up}" == backlog && "${e}" == - ) ) ]] || continue
    no_agent_name name "${slug}"; no_agent_name rname "review-${slug}"; pr_words "${prs}"
    rows+=" ${slug} ${name} ${rname} ${e}"
    data+="${slug}"$'\x1f'"${st}"$'\x1f'"${repo}"$'\x1f'"${PR_WORDS}"$'\n'
  done < <(stories_fm status kind held_for kept epic repo prs)
  [[ -n "${rows}${marked}" ]] || return 0
  # shellcheck disable=SC2086 # rows: space-separated 4-tuples
  [[ -z "${rows}" ]] || while read -r slug build ev name rname; do
    # Never started (no start line): nothing more is read for it.
    [[ -n "${slug}" && "${build}" != - ]] || continue
    d="$(awk -F $'\x1f' -v s="${slug}" '$1 == s { print; exit }' <<< "${data}")"
    IFS=$'\x1f' read -r _ st repo prs <<< "${d}"
    ! no_agent_theirs "${slug}" "${st}" "${prs}" || continue
    if [[ "${build}" != 1 ]]; then
      src="$(repo_dir "${repo}")" || continue
      build_exists "${src}" "${slug}" || continue
    fi
    built+="${slug} ${ev} ${name} ${rname} ${prs}"$'\n'; revs+=" ${slug} ${rname}"
    # Its build ended: an ok close of the builder after its newest start, as the handover leaves it.
    [[ "${build}" == 1 || " ${revonly} " != *" ${slug} "* ]] || handed+=" ${slug}"
  done < <(no_agent_events ${rows})
  [[ -n "${built}${marked}" ]] || return 0
  # The review case reads events.tsv once more, for the stories with a build record only: a build a
  # close cleared (its worktree and branch removed) has no PR left to review.
  # shellcheck disable=SC2086 # revs: space-separated pairs
  [[ -z "${revs}" ]] || rv="$(no_review_events ${revs})"
  live="$(SWARM_PANES="$(own_panes)" json "'\n'.join(a.get('name') or '' for a in d['result']['agents'] if a.get('pane_id') in e['SWARM_PANES'].split())" <<< "${LEAD_AGENTS}" 2>/dev/null)" || return 2
  NO_AGENT_LIVE="${live}"
  # -ww: the whole command line, never cut at a width. With no process list a pending tell, wait-pr or
  # merge, or a running step-up, cannot be ruled out, so nothing is printed, as for herdr's list.
  NO_AGENT_PS="$(ps -A -ww -o pid=,command= 2>/dev/null)" || return 2
  for slug in ${marked}; do
    # A pane listed under the builder's name may be the old builder, never closed, unless the marker
    # says the close was done (step_up_closed): then it is the new rung's, kept or left behind.
    no_agent_name name "${slug}"
    ! grep -qxF -e "${name}" <<< "${live}" || step_up_closed "${slug}" || continue
    step_up_running "${slug}" || echo "step-up failed: ${slug}, exit: swarm.sh step-up --resume ${slug}"
  done
  [[ -z "${built}" ]] || while read -r slug ev name rname prs; do
    [[ -n "${slug}" && " ${handed} " != *" ${slug} "* ]] || continue
    ! grep -qxF -e "${name}" -e "${rname}" <<< "${live}" || continue
    ! no_agent_busy "${slug}" "${name}" "${prs}" || continue
    if [[ "${ev}" == - ]]; then
      [[ "${1:-}" != record ]] || record_event no-agent "${slug}"
      continue
    fi
    echo "no-agent: ${slug}, exit: $(no_agent_exit "${slug}")"; said+=" ${slug}"
  done <<< "${built}"
  # The review case: whether the builder is listed or not.
  while read -r slug fields; do
    [[ -n "${slug}" ]] || continue
    d="$(awk -F $'\x1f' -v s="${slug}" '$1 == s { print; exit }' <<< "${data}")"
    IFS=$'\x1f' read -r _ st repo prs <<< "${d}"
    # One line per story: its no-agent: exit comes first (a restart, or in review the review-agent
    # exit already), and the next poll brings no-review: once the builder is back.
    [[ " ${said} " != *" ${slug} "* ]] || continue
    no_review_line "${slug}" "${fields}" "${repo:--} ${prs}" "${1:-}"
  done <<< "${rv:-}"
  return 0
}

# no_agent_from <herdr agent list JSON> — no_agent_lines read from a list the caller already holds
# (status, dash), so herdr is not asked again, with its exit (2: could not check). Read-only (no
# record). The list is local to the call, so it never reaches a later lead_agents.
no_agent_from() {
  # shellcheck disable=SC2034 # no_agent_lines reads them
  local LEAD_AGENTS="$1" LEAD_AGENTS_OK="${1:+1}" LEAD_AGENTS_READ=1
  no_agent_lines
}

# step_up_running <slug> — true while the process <slug>'s .step-up marker names on its `pid <n>` line
# (step_up_marker) is in NO_AGENT_PS as a swarm.sh step-up or _step-up naming <slug>. A marker with no
# pid line, or whose process is gone (a step-up that failed, or was killed before it could log that),
# is not running, whatever events.tsv or its lock says. A marker gone by now counts as running, and so
# does a pid missing from NO_AGENT_PS but alive now: a resume that rewrote the marker after the ps read.
step_up_running() {
  local k v pid="" rc=0
  # Gone since the poll listed it: the rung started (start_rung removes it), so nothing failed.
  [[ -e "${PROJECT_DIR}/.swarm/briefs/$1.step-up" ]] || return 0
  while read -r k v; do [[ "${k}" != pid ]] || pid="${v}"; done 2>/dev/null < "${PROJECT_DIR}/.swarm/briefs/$1.step-up" || true
  # No pid read: a marker with no pid line, or one start_rung removed since the check above.
  [[ "${pid}" =~ ^[0-9]+$ ]] || { [[ ! -e "${PROJECT_DIR}/.swarm/briefs/$1.step-up" ]]; return; }
  # 0: a step-up of <slug>; 1: the pid runs something else; 2: the pid is not in the list.
  awk -v pid="${pid}" -v s="$1" '$1 == pid { seen = 1; for (i = 2; i < NF; i++) if ($i ~ /(^|\/)swarm\.sh$/ && ($(i + 1) == "step-up" || $(i + 1) == "_step-up"))
      for (j = i + 2; j <= NF; j++) if ($j == s) { f = 1; exit } }
    END { exit f ? 0 : seen ? 1 : 2 }' <<< "${NO_AGENT_PS}" || rc=$?
  [[ ${rc} == 2 ]] || return "${rc}"
  kill -0 "${pid}" 2>/dev/null
}

# step_up_closed <slug> — <slug>'s .step-up marker has a `closed` line: the step-up that wrote it got
# past closing the old builder (step_up rewrites the marker then; a resume writes it, since a resume
# only follows a close). A pane herdr lists under the builder's name is then the new rung's, kept by
# start_rung or left by a step-up killed after start_agent opened it, and no reason to stay quiet: a
# resume's start_agent refuses the name while that pane's agent works or waits and retires it when
# idle (free_agent_name), so it starts no second builder beside a live one. Without the line the
# step-up stopped inside the close, so that pane may be the old builder, and the alert waits.
step_up_closed() {
  grep -qx closed "${PROJECT_DIR}/.swarm/briefs/$1.step-up" 2>/dev/null
}

# LEAD_RESENT: "<agent>\t<time>\t<command>\t<n>" per events.tsv delivery line resend_pass is done with,
# <n> telling apart lines alike to the second; the same with "\tpending" for an Enter about to go,
# "\tresent" once it went, and "\trechecked" once the read after it is done. RESEND_SLACK: how long, in seconds, before a tell's line
# a turn its prompt started can be stamped: tell sends nothing to a working agent (it queues the tell); each of deliver_prompt's two
# tries waits up to PROMPT_TIMEOUT_MS in herdr's prompt and as long again in prompt_settle; with goal on,
# findings_goal's send_goal waits two more; and one more covers the reads between them.
LEAD_RESENT="${LEAD_DIR}/resend"
RESEND_SLACK=$(( 7 * PROMPT_TIMEOUT_MS / 1000 ))
RESEND_HERDR_WAIT=10   # seconds each herdr read or key press of resend_pass may take, as pane_text gives a read
RESEND_PASS_WAIT=20    # seconds after which resend_pass starts no more pane reads, leaving them for the next poll

# resend_busy <name> [backlog] [wait] — true while a swarm.sh command that may deliver <name> a prompt runs:
# one of NO_AGENT_ASKS or conduct, with an argument that is <name> once made an agent name
# (agent_name's lower case, dashes and cut) as it is, as review-<arg> or as conduct-<arg>, or --backlog
# with backlog set (the backlog conductor); for a conductor, also any swarm.sh next or merge, which
# start conductors in their own process (conduct_ready). Reads NO_AGENT_PS; a command line may hold a
# token, so none is ever printed.
# With wait set, true instead while a `swarm.sh wait` naming <name> runs (prompt_lines' api-error check).
resend_busy() {
  awk -v n="$1" -v bl="${2:-}" -v wait="${3:-}" -v max="${AGENT_NAME_MAX}" -v asks=" ${NO_AGENT_ASKS} conduct " '
    function nm(x) { x = tolower(x); gsub(/[^a-z0-9_-]/, "-", x); if (x !~ /^[a-z]/) x = "s" x; return substr(x, 1, max) }
    {
    m = split($0, w, " ")
    for (i = 1; i < m; i++) {
      if (w[i] !~ /(^|\/)swarm\.sh$/) continue
      # wait: a swarm.sh wait naming <name>. A flag or a timeout is no name: nm makes --lead s--lead.
      if (wait != "") {
        if (w[i + 1] != "wait") continue
        for (j = i + 2; j <= m; j++) if (w[j] !~ /^(-|[0-9]+$)/ && nm(w[j]) == n) { f = 1; exit }
        continue
      }
      if (n ~ /^conduct-/ && (w[i + 1] == "next" || w[i + 1] == "merge")) { f = 1; exit }
      if (!index(asks, " " w[i + 1] " ")) continue
      for (j = i + 2; j <= m; j++)
        if (nm(w[j]) == n || nm("review-" w[j]) == n || nm("conduct-" w[j]) == n || (bl != "" && w[j] == "--backlog")) { f = 1; exit }
    } } END { exit !f }' <<< "${NO_AGENT_PS}"
}

# resend_pass — submit a brief left unsent in an idle agent's input box, once per delivery. For each
# agent this project opened that the poll's herdr list (lead_agents) shows idle, it takes the newest
# events.tsv line that delivered it a prompt: story, escalate, step-up or tell for <slug> (not a note,
# which goes to the inbox, its wake prompt one line that is never a collapsed paste), review-agent for
# review-<slug>, conduct for conduct-<epic>, restart for <slug>, agent for an agent started by name, each mapped as
# agent_name maps it. Its outcome is ok, or deliver_prompt's failure after herdr sent (or may have
# sent) the prompt (a brief never taken up ends its command so); a tell that failed before sending
# delivered nothing and is passed over, while a start that did skips its agent (it may have opened the
# pane and recorded the session that turn_since reads). A line not yet in LEAD_RESENT gets one pane
# read. Each herdr call has RESEND_HERDR_WAIT seconds (within), and no read starts past
# LEAD_READ_DEADLINE, RESEND_PASS_WAIT seconds after lead_wake set it (the rest wait for the next poll),
# so a hung herdr cannot hold the poll. Each read's text, or its failure, goes in LEAD_READS for
# prompt_lines, which reads no pane twice in a poll. When
# the box holds a collapsed paste (panes.py's unsent_brief) and no turn started since the prompt went
# out (turn_since: for a start, which opens its own session, any turn in it; for a tell, one later than
# RESEND_SLACK before the line), it sends the pane Enter and logs `resend <agent>`. A turn that started
# and ended in those seconds before a tell reads as the tell taken up: the log cannot tell them apart,
# so that tell is left alone, never submitted on a guess. The line goes in LEAD_RESENT once the pane is
# read and needs nothing, or once the Enter went; before the Enter it goes in marked pending, which is
# not done, and with no pending line written there is no Enter: an unreadable pane, a paste with no
# session log to say whether a turn ran (sent nothing), or an Enter herdr failed to send (logged as the
# resend's outcome), is tried again next poll. An agent that a swarm.sh command is delivering to as the
# poll runs (resend_busy over one ps read) is skipped, checked again with a fresh ps just before an
# Enter (which is also skipped, for the next poll, when events.tsv has grown since rows read it), and
# while an upgrade runs (upgrade_holder) the pass reads nothing: its new line is not written yet, and
# an Enter could submit the brief deliver_prompt is sending. Never a tell or deliver_prompt: a second
# tell:findings line would count a review round twice. The first read after an Enter (the delivery's
# line marked resent, not yet rechecked) that still finds the paste in the box and no turn since writes
# the agent's .unsent marker (unsent_marker), for a builder, a review agent or a conductor; the read is
# done once, for an idle agent, and needs nothing more. An .unsent marker goes when herdr no longer
# lists its agent in its pane, lists it working, blocked or done, or a read finds its box clear or a
# turn since the brief; an
# idle marked agent's pane is read each poll, as one read with any delivery of its own. Prints nothing;
# outside herdr, or with no list, it does nothing.
resend_pass() {
  local rows pane name at cmd k stem role mode marked text since rc backlog line size deadline="${LEAD_READ_DEADLINE:-$((SECONDS + RESEND_PASS_WAIT))}"
  [[ -n "${LEAD_AGENTS_OK}" ]] || return 0
  # No idle agent in the list and no .unsent marker, no work: return before any process starts, as most polls do.
  [[ "${LEAD_AGENTS}" == *idle* && -s "${EVENTS_LOG}" ]] || compgen -G "${PROJECT_DIR}/.swarm/briefs/*.unsent" >/dev/null || return 0
  backlog="$(conductor_name backlog)"
  # events.tsv's size as rows reads it: a line added before an Enter may be a newer delivery.
  size=$(( $(wc -c < "${EVENTS_LOG}" 2>/dev/null || echo 0) ))
  rows="$(SWARM_PANES="$(own_panes)" SWARM_BACKLOG="${backlog}" SWARM_NAME_MAX="${AGENT_NAME_MAX}" SWARM_BRIEFS="${PROJECT_DIR}/.swarm/briefs" SWARM_LIB="${SWARM_HOME}/bin/lib" python3 -I -c '
import glob, json, os, re, sys
sys.path.insert(0, os.environ["SWARM_LIB"]); from events_outcome import outcome
e = os.environ
own = set(e["SWARM_PANES"].split())
# agent_name: lower case, any other byte a dash, s before a name that does not start with a letter, the cut.
def name(x):
    x = re.sub(rb"[^a-z0-9_-]", b"-", x.encode().lower()).decode()
    return (x if re.match("[a-z]", x) else "s" + x)[:int(e["SWARM_NAME_MAX"])]
# The brief stem and role an .unsent marker takes for a start: none for an agent started by name.
def stem(c, t):
    if c == "agent": return "-", "-"
    s, r = (("review-" + t, "review") if c == "review-agent" else ("conduct-" + t.lstrip("-"), "conductor") if c == "conduct" else (t, "builder"))
    return (s, r) if re.fullmatch("[a-z0-9-]+", s) else ("-", "-")
# A tell takes the role of the last start line of its agent, else of the name it was told by.
def told(n, t):
    if n == e["SWARM_BACKLOG"]: return "conduct-backlog", "conductor"
    r = "conductor" if t.startswith("conduct-") else "review" if t.startswith("review-") else "builder"
    return (t, r) if re.fullmatch("[a-z0-9-]+", t) else ("-", "-")
# herdr lists an agent with no status too: that one is still listed.
listed = {(a["name"], a["pane_id"]): a.get("agent_status") or "-" for a in json.loads(sys.stdin.read())["result"]["agents"]
          if a.get("name") and a.get("pane_id") in own}
idle = {n: p for (n, p), s in listed.items() if s == "idle"}
# Each .unsent marker: kept for an idle agent, whose pane is read below; gone once its agent took a turn
# (working, blocked or done) or herdr no longer lists it in its pane.
marked = {}
for path in glob.glob(os.path.join(glob.escape(e["SWARM_BRIEFS"]), "*.unsent")):
    try:
        f = open(path, encoding="utf-8").readline().split()
    except OSError:
        continue
    if len(f) < 2:
        continue
    s = listed.get((f[0], f[1]), "gone")
    if s == "idle":
        marked[f[0]] = os.path.basename(path)[:-len(".unsent")]
    elif s in ("gone", "working", "blocked", "done"):
        try:
            os.remove(path)
        except OSError:
            pass
newest, alike, started = {}, {}, {}
try:
    for l in open(sys.argv[1], encoding="utf-8", errors="replace"):
        f = l.rstrip("\n").split("\t")
        if len(f) != 5:
            continue
        c, t = f[1], f[2]
        if c in ("story", "escalate", "step-up", "step-up:resume", "restart", "agent", "tell") or (c.startswith("tell:") and c != "tell:note"): n = name(t)
        elif c == "review-agent": n = name("review-" + t)
        elif c == "conduct": n = e["SWARM_BACKLOG"] if t in ("--backlog", "backlog") else name("conduct-" + t)
        else: continue
        if n not in idle:
            continue
        if c.startswith("tell"):
            sr = started.get(n) or told(n, t)
        else:
            sr = started[n] = stem(c, t)
        # ok (an escalate line reads ok (<trigger>: ...)), or a deliver_prompt failure once herdr may have sent it.
        o = outcome(f)
        if o == "ok" or o.startswith("ok (") or any(w in o for w in ("herdr sent it the brief", "may or may not have the brief", "could not be read")):
            k = (n, f[0], c)
            alike[k] = alike.get(k, 0) + 1
            newest[n] = (f[0], c, alike[k]) + sr
        elif not c.startswith("tell"):
            # A start that failed before sending may still have opened the pane and recorded its session
            # (record_agent comes before deliver_prompt): whatever is in the box is not an older brief.
            newest[n] = None
except OSError:
    pass
try:
    seen = set(open(sys.argv[2], encoding="utf-8").read().splitlines())
except OSError:
    seen = set()
# mode: new, a line not yet checked; after, the first read after its Enter; - for a marked agent alone.
for n in sorted(set(idle) & (set(n for n, v in newest.items() if v) | set(marked))):
    t, c, k, g, r = newest.get(n) or ("-",) * 5
    key = "\t".join((n, t, c, str(k)))
    mode = "-" if not newest.get(n) else "new" if key not in seen else "after" if key + "\tresent" in seen and key + "\trechecked" not in seen else "-"
    if mode != "-" or n in marked:
        print("\t".join((idle[n], n, t, c, str(k), g, r, mode, marked.get(n, "-"))))' "${EVENTS_LOG}" "${LEAD_RESENT}" <<< "${LEAD_AGENTS}" 2>/dev/null)" || return 0
  [[ -n "${rows}" ]] || return 0
  # An upgrade restarts agents in its own process and logs them only at its end, as no_agent_lines skips them.
  [[ ! -f "${UPGRADE_PID}" ]] || [[ -z "$(upgrade_holder)" ]] || return 0
  # With no process list, a delivery under way cannot be ruled out, so nothing is read.
  NO_AGENT_PS="$(ps -A -ww -o command= 2>/dev/null)" || return 0
  mkdir -p "${LEAD_DIR}" 2>/dev/null || return 0
  while IFS=$'\t' read -r pane name at cmd k stem role mode marked; do
    [[ -n "${pane}" ]] || continue
    (( SECONDS < deadline )) || break
    ! resend_busy "${name}" "$([[ "${name}" != "${backlog}" ]] || echo 1)" || continue
    # pane_text's read, with its failure kept: an empty or failed read is no clear box.
    text="$(within "${RESEND_HERDR_WAIT}" herdr agent read "${pane}" --source recent-unwrapped </dev/null 2>/dev/null)" && [[ -n "${text}" ]] \
      || { [[ -z "${LEAD_READS}" ]] || : > "${LEAD_READS}/${pane}.fail"; continue; }
    # prompt_lines reads the pane from here, not from herdr again.
    [[ -z "${LEAD_READS}" ]] || printf '%s' "${text}" > "${LEAD_READS}/${pane}"
    since="${at}"; [[ "${cmd}" == tell* ]] || since=-
    # 10: a paste in the box and no turn since the prompt went out; 11: a clear box; 13: a paste, but a turn
    # since. Anything else (12, a paste with no session log to say whether a turn ran, or python's own error
    # exit) is tried again next poll.
    rc=0; printf '%s' "${text}" | SWARM_LIB="${SWARM_HOME}/bin/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["SWARM_LIB"]); from panes import unsent_brief, turn_since
if not unsent_brief(sys.stdin.read()):
    sys.exit(11)
t = turn_since(*sys.argv[1:6])
sys.exit(12 if t is None else 13 if t else 10)' \
      "${AGENTS_LOG}" "${name}" "${CLAUDE_PROJECTS}" "${since}" "${RESEND_SLACK}" 2>/dev/null || rc=$?
    # A clear box, or a turn since the brief went out, takes the agent's .unsent marker down.
    [[ ( ${rc} -ne 11 && ${rc} -ne 13 ) || "${marked}" == - ]] || rm -f "${PROJECT_DIR}/.swarm/briefs/${marked}.unsent"
    line="${name}"$'\t'"${at}"$'\t'"${cmd}"$'\t'"${k}"
    if [[ ${rc} -eq 10 && "${mode}" != - ]]; then
      # A delivery that began after the first ps read would take this Enter, or be read as the brief left
      # unsent: read ps again.
      NO_AGENT_PS="$(ps -A -ww -o command= 2>/dev/null)" || continue
      ! resend_busy "${name}" "$([[ "${name}" != "${backlog}" ]] || echo 1)" || continue
      # A delivery that began and ended while the pane was read left a line rows has not seen.
      [[ $(( $(wc -c < "${EVENTS_LOG}" 2>/dev/null || echo 0) )) -eq ${size} ]] || continue
    fi
    case "${mode}" in
      after)
        # The read after the Enter: the paste still there, with no turn since, is a brief it did not send.
        case "${rc}" in
          10) [[ "${stem}" == - ]] || unsent_marker "${stem}" "${name}" "${pane}" "${role}" || continue ;;
          11|13) ;;
          *) continue ;;
        esac
        printf '%s\trechecked\n' "${line}" >> "${LEAD_RESENT}" 2>/dev/null || true
        continue ;;
      new) ;;
      *) continue ;;
    esac
    [[ ${rc} -ne 13 ]] || rc=11
    [[ ${rc} -eq 10 || ${rc} -eq 11 ]] || continue
    if [[ ${rc} -eq 10 ]]; then
      # Pending first, which counts as not done: a run stopped before the Enter, or an Enter that failed,
      # is tried again next poll, which reads the box again. A file it cannot write gets no Enter.
      printf '%s\tpending\n' "${line}" >> "${LEAD_RESENT}" 2>/dev/null || continue
      # The text read above is no longer the pane's once Enter may have gone: prompt_lines leaves it.
      [[ -z "${LEAD_READS}" ]] || : > "${LEAD_READS}/${pane}.sent"
      if ! within "${RESEND_HERDR_WAIT}" herdr pane send-keys "${pane}" Enter </dev/null >/dev/null 2>&1; then
        record_event resend "${name}" "herdr could not send Enter to ${pane}"
        size=$(( $(wc -c < "${EVENTS_LOG}" 2>/dev/null || echo 0) ))   # past its own line, as below
        continue
      fi
      record_event resend "${name}"
      size=$(( $(wc -c < "${EVENTS_LOG}" 2>/dev/null || echo 0) ))   # past its own line
      printf '%s\tresent\n' "${line}" >> "${LEAD_RESENT}" 2>/dev/null || true
    fi
    printf '%s\n' "${line}" >> "${LEAD_RESENT}" 2>/dev/null || true
  done <<< "${rows}"
}

# unsent_marker <stem> <agent> <pane> <role> — write .swarm/briefs/<stem>.unsent, the marker of a brief
# resend_pass's Enter did not send, in step_up_marker's format: its first line <agent> <pane> <role>
# (builder, review or conductor), then `pid <n>`, the wait --lead that wrote it. <stem> is the brief's
# file stem: the slug, review-<slug> or conduct-<epic> (conduct-backlog for the backlog's conductor).
unsent_marker() {
  local f="${PROJECT_DIR}/.swarm/briefs/$1.unsent"
  mkdir -p "${f%/*}" && printf '%s %s %s\npid %s\n' "$2" "$3" "$4" "$$" > "${f}.tmp" && mv "${f}.tmp" "${f}"
}

# unsent_lines — `unsent brief: <stem>, exit: <exit>` per .unsent marker (unsent_marker). The exit starts
# the agent again, or for a builder whose story is not ready, keeps it. A ready story's builder has its
# pane closed with herdr, since swarm.sh close would count a failed build and clear the worktree restart
# needs, then no_agent_exit's exit (restart); any other builder (a story in review, its findings left in
# the box) is told a nudge once a wait on it returns (the form every nudge instruction gives), which
# herdr types after the paste and sends with it. A review agent gets
# swarm.sh close, then review-agent for each of its story's PRs; a conductor swarm.sh close, then conduct. Like no_agent_lines' marker lines, printed only with the poll's
# herdr list (LEAD_AGENTS_OK). wait --lead reads them after resend_pass, which writes and removes markers.
unsent_lines() {
  local m stem agent pane role slug u out
  [[ -n "${LEAD_AGENTS_OK}" ]] || return 0
  for m in "${PROJECT_DIR}/.swarm/briefs/"*.unsent; do
    [[ -f "${m}" ]] || continue
    { read -r agent pane role; } 2>/dev/null < "${m}" || continue
    stem="${m##*/}"; stem="${stem%.unsent}"
    case "${role}" in
      builder)
        if [[ ! -f "${BOARD}/stories/${stem}.md" ]]; then out="herdr pane close ${pane}"
        elif [[ "$(fm "${BOARD}/stories/${stem}.md" status)" == ready ]]; then out="herdr pane close ${pane} then $(no_agent_exit "${stem}")"
        else out="swarm.sh wait --idle ${stem} && swarm.sh tell ${stem} nudge <a file asking it to act on the brief in its input box>"; fi ;;
      review)
        slug="${stem#review-}"; out=""
        [[ ! -f "${BOARD}/stories/${slug}.md" ]] || for u in $(story_prs "${BOARD}/stories/${slug}.md"); do
          out+="${out:+, then }swarm.sh review-agent ${slug} ${u}"
        done
        out="swarm.sh close ${stem} then ${out:-swarm.sh review-agent ${slug} <PR URL>}" ;;
      conductor)
        # The backlog's conductor is closed by its agent name: conduct-backlog names no epic.
        if [[ "${stem}" == conduct-backlog ]]; then out="swarm.sh close ${agent} then swarm.sh conduct --backlog"
        else out="swarm.sh close ${stem} then swarm.sh conduct ${stem#conduct-}"; fi ;;
      *) continue ;;
    esac
    echo "unsent brief: ${stem}, exit: ${out}"
  done
}

# LEAD_QUIET: the kinds of wait --lead line (the text before a line's first ": ") that another command
# already shows (status, next), so a first read with no LEAD_SEEN saves them without printing them.
LEAD_QUIET="held: escalated: kept: merge: idle:"

# lead_quiet <line> — true when <line>'s kind is in LEAD_QUIET.
lead_quiet() { [[ " ${LEAD_QUIET} " == *" ${1%%: *}: "* ]]; }

# lead_wake [quiet] — read the lead's queue once, taking herdr's agent list once for it (lead_agents)
# and running a heads pass first when this run has none yet or LEAD_HEADS_EVERY seconds have passed
# since its last (lead_heads, open_story_prs, lead_bases), start a fix-main story's writer for each red base
# head none covers (main_red_fix), run resend_pass off that list, add the .unsent markers' lines
# (unsent_lines) after it, then prompt_lines', which share resend_pass's reads and budget, then, after
# handing on the queued tells whose check stopped (tell_queue_strays), the `tell undelivered:` or
# `tell goal failed:` line of each queued tell no check delivered (tell_undelivered), and save the
# queue as LEAD_SEEN. Print
# each item that was not in LEAD_SEEN before and log `lead-woken <slug>`
# for it, its kind in the outcome (`ok (no-agent)`); true when there was one. quiet saves the lines
# of a kind in LEAD_QUIET without printing them, and prints every other line: each is an alert.
lead_wake() {
  local now line new="" slug u
  lead_agents
  if [[ -z "${LEAD_HEADS_AT}" ]] || (( SECONDS - LEAD_HEADS_AT >= LEAD_HEADS_EVERY )); then
    LEAD_HEADS_AT=${SECONDS}; lead_heads
    # The open story PRs pr_lines reads each poll, on the heads pass's cadence: its gh reads come with the pass's.
    open_story_prs > "${LEAD_PRS}.new" && mv "${LEAD_PRS}.new" "${LEAD_PRS}"
    # Each base's head and its CI, for main_red_lines, over the repos open_story_prs has just resolved.
    lead_bases > /dev/null
  fi
  # A fix-main story writer for each red base head none covers, started detached here, never in lead_queue's $(...).
  main_red_fix
  now="$(lead_queue)"
  # One read budget and one read per pane for resend_pass and prompt_lines. The reads sit in
  # .swarm/lead/reads, emptied at each poll's start and end, never in TMPDIR. lead_lock stops an earlier
  # run's bash, but not a $(prompt_lines) it had started: that subshell runs to its end (up to the read
  # budget), writing into the reads directory and over LEAD_SEEN and LEAD_STUCK after the new run has, so
  # a stop it moves out of LEAD_SEEN can wake the lead a second time. Each poll empties the directory first.
  LEAD_READ_DEADLINE=$((SECONDS + RESEND_PASS_WAIT))
  LEAD_READS="${LEAD_DIR}/reads"; rm -rf "${LEAD_READS}"; mkdir -p "${LEAD_READS}" 2>/dev/null || LEAD_READS=""
  resend_pass >/dev/null 2>&1 || true
  # No marker, no subshell: most polls have none.
  u=""; ! compgen -G "${PROJECT_DIR}/.swarm/briefs/*.unsent" >/dev/null || u="$(unsent_lines)"
  now="${now}${now:+${u:+$'\n'}}${u}"
  # No pane of this project's that herdr shows blocked, idle or done (prompt_wanted), and no prompt: line
  # to keep or drop: no subshell, as on most polls while agents work.
  u=""; [[ -n "${LEAD_AGENTS_OK}" ]] && ! prompt_wanted && ! grep -q '^prompt: ' "${LEAD_SEEN}" 2>/dev/null \
    || u="$(prompt_lines)"
  now="${now}${now:+${u:+$'\n'}}${u}"
  [[ -z "${LEAD_READS}" ]] || rm -rf "${LEAD_READS}"
  LEAD_READS=""
  tell_queue_strays 2>/dev/null || true   # a queued tell whose check stopped goes to the lead, never sits unseen
  u=""; ! compgen -G "${TELL_QUEUE}/*.undelivered" >/dev/null || u="$(cat "${TELL_QUEUE}"/*.undelivered 2>/dev/null)" || true
  now="${now}${now:+${u:+$'\n'}}${u}"
  while IFS= read -r line; do
    [[ -z "${line}" ]] || grep -qxF "${line}" "${LEAD_SEEN}" 2>/dev/null \
      || { [[ -n "${1:-}" ]] && lead_quiet "${line}"; } || new+="${line}"$'\n'
  done <<< "${now}"
  printf '%s\n' "${now}" > "${LEAD_SEEN}.tmp" && mv "${LEAD_SEEN}.tmp" "${LEAD_SEEN}"
  [[ -n "${new}" ]] || return 1
  while IFS= read -r line; do
    echo "${line}"; slug="${line#*: }"; slug="${slug%%,*}"
    record_event lead-woken "${slug%% *}" "ok (${line%%: *})"
  done <<< "${new%$'\n'}"
}

# lead_holder — the pid in LEAD_PID when it is a live wait --lead, else nothing.
lead_holder() {
  local pid
  pid="$(cat "${LEAD_PID}" 2>/dev/null)" || return 0
  if [[ "${pid}" =~ ^[0-9]+$ ]] && ps -p "${pid}" -o command= 2>/dev/null | grep -q -- 'swarm.sh wait --lead'; then echo "${pid}"; fi
}

# pid_lock <pid-file> <line> <holder> — link a file holding <line> (this run's pid first) into
# <pid-file>, so it is never seen half written. Fails while <holder>, a function, prints a live
# holder, whose file stays. A dead holder's file is removed under <pid-file>.reclaim, made with perl's
# mkdir (uutils' mkdir lets two racers both through, as state_lock says), and only while it still
# holds what was read before its holder was found dead: another run may have reclaimed it and
# linked its own in between, and that one is never removed.
pid_lock() {
  local tmp="$1.$$" n=0 stale
  { mkdir -p "${1%/*}" && printf '%s\n' "$2" > "${tmp}"; } || die "cannot write ${tmp}"
  until ln "${tmp}" "$1" 2>/dev/null; do
    [[ -e "$1" ]] || { rm -f "${tmp}"; die "cannot write $1"; }
    stale="$(cat "$1" 2>/dev/null)" || stale=""
    [[ -z "$("$3")" ]] || { rm -f "${tmp}"; return 1; }
    if perl -e 'mkdir shift or exit 1' "$1.reclaim"; then
      [[ -z "${stale}" || "$(cat "$1" 2>/dev/null)" != "${stale}" ]] || rm -f "$1"
      rmdir "$1.reclaim"
    else
      ((++n < 50)) || { rm -f "${tmp}"; die "$1.reclaim stays; remove it if nothing holds $1"; }
      sleep 0.1
    fi
  done
  rm -f "${tmp}"
}

# lead_lock — make this run the one wait --lead (pid_lock): stop any live holder of LEAD_PID (an
# earlier run, whose output may go unread) and take it. The pid file goes on exit, only while it
# still names this run.
lead_lock() {
  local pid i
  until pid_lock "${LEAD_PID}" "$$" lead_holder; do
    pid="$(lead_holder)"
    [[ -n "${pid}" ]] || continue
    echo "swarm: wait --lead: stopping the earlier run (pid ${pid}); this one watches now" >&2
    kill "${pid}" 2>/dev/null || true
    for ((i = 0; i < 50; i++)); do [[ -n "$(lead_holder)" ]] || break; sleep 0.1; done
    [[ -z "$(lead_holder)" ]] || die "wait --lead: the earlier run (pid ${pid}) did not stop"
  done
  trap '[[ "$(cat "${LEAD_PID}" 2>/dev/null)" != "$$" ]] || rm -f "${LEAD_PID}"' EXIT
}

# wait_lead [timeout-ms] — wait --lead: one run at a time, the newest (lead_lock). It reads the lead's
# queue every LEAD_POLL seconds and returns 0 as soon as it holds an item that LEAD_SEEN does not
# (lead_wake). The PR heads behind its merge: lines, the open story PRs behind its unmerged: and conflict:
# lines, and the base heads behind its main-red: lines are read only in a heads pass (lead_heads,
# open_story_prs, lead_bases), on its first read and then at most once
# every LEAD_HEADS_EVERY seconds. The first read of a run reports what
# landed since the last run; with no LEAD_SEEN yet it notes the queue and reports only the alerts,
# every line whose kind is not in LEAD_QUIET. At the timeout (default an hour) it fails with nothing printed. It edits
# no board file but to retire a red base's unstarted fix-main stories once that base reads fixed (lead_bases,
# clear_red_main) and, through a detached run, to write a red base head's fix-main story (main_red_fix), and
# nudges no one but to submit an unsent brief (resend_pass).
wait_lead() {
  local timeout="${1:-3600000}" start left
  [[ "${timeout}" =~ ^[0-9]+$ ]] || die "wait --lead: the timeout is in milliseconds, not '${timeout}'"
  timeout=$((10#${timeout}))   # 090000 is not octal
  [[ "${LEAD_POLL}" =~ ^[1-9][0-9]*$ ]] || die "SWARM_LEAD_POLL is whole seconds, at least 1, not '${LEAD_POLL}'"
  [[ "${LEAD_HEADS_EVERY}" =~ ^[1-9][0-9]*$ ]] || die "SWARM_LEAD_HEADS_EVERY is whole seconds, at least 1, not '${LEAD_HEADS_EVERY}'"
  lead_lock
  start=${SECONDS}
  if [[ -f "${LEAD_SEEN}" ]]; then ! lead_wake || return 0; else ! lead_wake quiet || return 0; fi
  while (( (SECONDS - start) * 1000 < timeout )); do
    left=$(( (timeout + 999) / 1000 - (SECONDS - start) ))
    sleep $(( left < LEAD_POLL ? left : LEAD_POLL ))
    ! lead_wake || return 0
  done
  return 1
}

# UPGRADE_WAIT_MS: how long upgrade works in rounds before it names the agents still on an old version.
UPGRADE_WAIT_MS="${SWARM_UPGRADE_WAIT_MS:-7200000}"
# UPGRADE_GRACE_MS: how much longer it waits for a conductor it gave up on to go idle, to withdraw
# the request by prompt.
UPGRADE_GRACE_MS="${SWARM_UPGRADE_GRACE_MS:-300000}"
# UPGRADE_PID: the running upgrade's pid, scope (its epic, - for every agent) and log, one upgrade
# per project. UPGRADE_DIR: that run's own records, a file per agent name: epic- (upgrade_epic), hand-
# (its handover file), asked- (prompt or note), ready- (idle with its handover in, this round), done-
# (moved, or a conductor already on the version told to carry on), left- (left on its old version),
# kept- (already on the version, with a problem), busy- (busy when its restart came), rheld- (the
# review-agent hold that kept a builder back in its last round, upgrade_hold's), hint- (how to
# resume it, while a restart is under way); summary, the lines it prints at the end; and why, a failed
# restart's. UPGRADE_SAID: how upgrade_say sent its last text, prompt or note. UPGRADE_HERDR: herdr's
# agent list, read once per round (upgrade_herdr). UPGRADE_WANT and UPGRADE_NEW: the run's agents
# (upgrade_want) and version.
UPGRADE_PID="${PROJECT_DIR}/.swarm/upgrade.pid"
UPGRADE_DIR=""
UPGRADE_SAID=""
UPGRADE_HERDR=""
UPGRADE_WANT=""
UPGRADE_NEW=""
UPGRADE_SHELL=""   # the pid of the shell the run's traps belong to (upgrade_mine)

# upgrade_agents [<epic>|backlog] [--foreground] — after `claude plugin update`, move <epic>'s Claude
# agents (its conductor, builders and review agents; backlog's, the stories with no epic; with
# neither, every one this project started) to this swarm.sh's version, each restarted in its own pane
# with --resume, so it keeps its context. Unless --foreground (or as the detached worker,
# SWARM_UPGRADE_WORKER=1), it runs itself again detached (upgrade_detach) and prints that run's pid
# and log; while an upgrade runs here, it starts nothing
# and names that one, failing when that one's scope does not cover this one's. It works in rounds
# (upgrade_round) until no agent waits, or until UPGRADE_WAIT_MS has passed (upgrade_end), then prints
# one line per agent: `<name>: <old> -> <new>`, `<name>: left on <old>: <why>`, or already on this
# version, and last a tally (upgrade_tally), so a log that stops before it was cut off. A TERM or HUP
# names the agents it had not moved and tells each conductor it paused to carry on first
# (upgrade_stopped). A run that never read herdr's list fails, saying no agent was moved. Worktrees are never touched. Fails when any agent was left on its old version.
upgrade_agents() {
  local epic="" fg="" a new log end name pane role cur f rc=0
  [[ "${SWARM_UPGRADE_WORKER:-}" != 1 ]] || fg=1
  unset SWARM_UPGRADE_WORKER
  for a in "$@"; do
    case "${a}" in
      --foreground) fg=1 ;;
      *) [[ -z "${epic}" ]] || die "upgrade: one epic at a time: swarm.sh upgrade [<epic>|backlog] [--foreground]"; epic="${a}" ;;
    esac
  done
  [[ "${epic}" != --backlog ]] || epic=backlog
  [[ -z "${epic}" || "${epic}" == backlog || ( "${epic}" =~ ^[a-z0-9-]+$ && -f "${BOARD}/epics/${epic}.md" ) ]] \
    || die "upgrade: no epic ${BOARD}/epics/${epic}.md (backlog moves the stories with no epic)"
  require_herdr_version
  new="$(plugin_version < "${SWARM_HOME}/.claude-plugin/plugin.json")"
  log="${PROJECT_DIR}/.swarm/upgrade-${new}.log"
  upgrade_busy "${epic}" || rc=$?
  case "${rc}" in 0) return 0 ;; 2) return 1 ;; esac
  rc=0
  [[ -n "${fg}" ]] || { upgrade_detach "${log}" "${epic}"; return; }
  upgrade_lock "${log}" "${epic}" || { [[ $? -eq 1 ]] && return 0; return 1; }
  UPGRADE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/swarm-upgrade-run.XXXXXX")" || { upgrade_unlock; die "upgrade: cannot make a folder in ${TMPDIR:-/tmp}"; }
  UPGRADE_NEW="${new}"; UPGRADE_WANT="$(upgrade_want "${epic}")"
  # Both act only in this shell (upgrade_mine): a subshell bash has just forked, a pipeline's included,
  # can run a trap it inherited before it resets them, and must neither clean up nor report the run.
  # TERM only: the worker runs under nohup, which ignores HUP for good, and a --foreground run's
  # swarm.sh turns a HUP into a TERM to it.
  # Its own output on fds 7 and 8 too: a trap runs with the redirections of the command it cut into
  # (a 2>/dev/null, a > list), and upgrade_stopped writes the summary back here.
  exec 7>&1 8>&2
  UPGRADE_SHELL="$(exec sh -c 'echo "${PPID}"')"
  trap 'upgrade_mine || exit; rm -rf "${UPGRADE_DIR}"; upgrade_unlock' EXIT
  trap 'upgrade_mine || exit 143; upgrade_stopped 143' TERM
  echo "swarm.sh upgrade${epic:+ ${epic}} to ${new}: pid $$, started $(date '+%F %T')"
  end=$(($(now_ms) + UPGRADE_WAIT_MS))
  until upgrade_round "${UPGRADE_WANT}" "${new}" "${end}"; do
    if (($(now_ms) >= end)); then upgrade_end "${UPGRADE_WANT}" "${new}"; break; fi
    nap 5
  done
  trap - TERM
  while IFS=$'\t' read -r name pane role cur; do
    [[ -n "${name}" && "${cur}" == new ]] || continue
    [[ -e "${UPGRADE_DIR}/done-${name}" || -e "${UPGRADE_DIR}/left-${name}" || -e "${UPGRADE_DIR}/kept-${name}" ]] || echo "${name}: already on ${new}"
  done <<< "$(upgrade_list "${UPGRADE_WANT}" "${new}")"
  cat "${UPGRADE_DIR}/summary" 2>/dev/null || true
  for f in "${UPGRADE_DIR}"/left-*; do [[ ! -e "${f}" ]] || rc=1; break; done
  [[ -e "${UPGRADE_DIR}/list" ]] || rc=1   # herdr's list never read: nothing was moved
  upgrade_tally "done" "${rc}"
  return "${rc}"
}

# upgrade_mine — succeed in the shell that set the run's traps (UPGRADE_SHELL): bash 3.2 has no
# BASHPID, and BASH_SUBSHELL does not count a pipeline's subshells, so the shell's own pid is read as
# the parent of a process it execs.
upgrade_mine() { [[ "$(exec sh -c 'echo "${PPID}"')" == "${UPGRADE_SHELL}" ]]; }

# upgrade_tally <done|stopped> <exit> — the log's last line: how many agents this run moved to a new
# version (their `<old> -> <new>` lines) and how many it left on an old one.
upgrade_tally() {
  local f moved left=0
  moved="$(grep -c ' -> ' "${UPGRADE_DIR}/summary" 2>/dev/null)" || moved=0
  for f in "${UPGRADE_DIR}"/left-*; do [[ ! -e "${f}" ]] || left=$((left + 1)); done
  echo "upgrade $1: ${moved} moved, ${left} left (exit $2)"
}

# upgrade_stopped <exit> — on a TERM (143): each agent in the run still on its old version and not
# paused is left, with its resume hint when its restart was cut off (a hint- file names it even when
# herdr no longer lists it); then each
# conductor this run asked for a handover and has not moved is told which of its builders were
# restarted and to carry on as before, and its pause marker removed, so none stays paused with
# nobody to wake it. Then the summary and the tally, and it exits <exit>. A KILL or a reboot leaves
# them paused: the marker stops holding back tell's wake prompt once it is an hour old.
upgrade_stopped() {
  local f n name pane role cur about
  trap - TERM
  exec 1>&7 2>&8   # the run's own output, not that of the command the TERM cut into
  set +e   # a TERM can land where errexit holds (between rounds); a stop must run to its end regardless
  UPGRADE_HERDR=""
  while IFS=$'\t' read -r name pane role cur; do
    [[ -n "${name}" && "${cur}" == old && ! -e "${UPGRADE_DIR}/hand-${name}" ]] || continue
    upgrade_epic "${name}" "${role}" >/dev/null
    upgrade_left "${name}" "the upgrade was stopped$(upgrade_hint "${name}")"
  done <<< "$(upgrade_list "${UPGRADE_WANT}" "${UPGRADE_NEW}" </dev/null | upgrade_open)"
  for f in "${UPGRADE_DIR}"/hint-*; do
    n="${f##*/hint-}"
    [[ -e "${f}" && ! -e "${UPGRADE_DIR}/done-${n}" && ! -e "${UPGRADE_DIR}/left-${n}" && ! -e "${UPGRADE_DIR}/kept-${n}" && ! -e "${UPGRADE_DIR}/hand-${n}" ]] || continue
    upgrade_left "${n}" "the upgrade was stopped$(upgrade_hint "${n}")"
  done
  for f in "${UPGRADE_DIR}"/hand-*; do
    n="${f##*/hand-}"
    [[ -e "${f}" && ! -e "${UPGRADE_DIR}/done-${n}" && ! -e "${UPGRADE_DIR}/left-${n}" && ! -e "${UPGRADE_DIR}/kept-${n}" ]] || continue
    pane="$(agent_field "${n}" pane_id </dev/null)"
    about="$(upgrade_about "$(upgrade_epic "${n}" conduct)" "${UPGRADE_NEW}")"
    upgrade_say "${n}" "${pane}" "swarm.sh upgrade was stopped before it moved you. ${about} Ignore its request, and carry on as before, on the version you run." </dev/null \
      || echo "${n}: could not be told to carry on; tell it by hand" >> "${UPGRADE_DIR}/summary"
    rm -f "$(upgrade_paused "${n}")"
    upgrade_left "${n}" "the upgrade was stopped, told to carry on as before$(upgrade_hint "${n}")"
  done
  cat "${UPGRADE_DIR}/summary" 2>/dev/null || true
  upgrade_tally stopped "$1"
  exit "$1"
}

# upgrade_hint <name> — `; <how to resume it>` while <name>'s restart is under way or failed once its
# claude had exited (upgrade_one's hint- file), else nothing.
upgrade_hint() { [[ ! -s "${UPGRADE_DIR}/hint-$1" ]] || printf '; %s' "$(cat "${UPGRADE_DIR}/hint-$1")"; }

# upgrade_detach <log> [epic] — run upgrade again as its worker (SWARM_UPGRADE_WORKER=1, which main
# logs as the run's one event), detached: nohup, in a session and so a process group of its own
# (setsid), its output appended to <log>. Once the worker holds this project's upgrade (upgrade_lock),
# print its pid and log; a worker that exits first, as one that finds another upgrade running does,
# has its lines printed here and its exit code returned, so what is printed is the working run's.
upgrade_detach() {
  local pid from=0 rc i
  mkdir -p "${1%/*}" || die "upgrade: cannot make ${1%/*}"
  [[ ! -f "$1" ]] || from=$(($(wc -c < "$1")))
  SWARM_UPGRADE_WORKER=1 nohup python3 -I -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
    bash "${SWARM_HOME}/bin/swarm.sh" upgrade ${2:+"$2"} >> "$1" 2>&1 </dev/null &
  pid=$!
  for ((i = 0; i < 300; i++)); do
    [[ "$(upgrade_holder)" != *" pid ${pid}, "* ]] || { echo "swarm.sh upgrade runs detached until every agent is moved: pid ${pid}, log $1"; return 0; }
    if ! kill -0 "${pid}" 2>/dev/null; then
      rc=0; wait "${pid}" || rc=$?
      tail -c "+$((from + 1))" "$1"
      return "${rc}"
    fi
    sleep 0.1
  done
  die "upgrade: its worker (pid ${pid}) has not started in 30s; see $1"
}

# upgrade_holder — the scope (- for every agent), pid and log of the upgrade running in this project
# (UPGRADE_PID): `<scope> pid <pid>, log <log>`. Fails when none runs: the file is gone, or its pid
# is not a swarm.sh upgrade now (it exited, and the pid may have gone to another process).
upgrade_holder() {
  local pid scope log
  read -r pid scope log 2>/dev/null < "${UPGRADE_PID}" || return 1
  [[ "${pid}" =~ ^[0-9]+$ && "$(ps -p "${pid}" -o command= 2>/dev/null)" == *"swarm.sh upgrade"* ]] || return 1
  echo "${scope} pid ${pid}, log ${log}"
}

# upgrade_busy [epic] — say which upgrade runs in this project (upgrade_holder): exits 0 when it moves
# [epic]'s agents too, 2 when it does not, so [epic] was not moved; fails with 1 when none runs.
upgrade_busy() {
  local h s
  h="$(upgrade_holder)" || return 1
  s="${h%% *}"; h="${h#* }"
  if [[ "${s}" == - || "${s}" == "${1:--}" ]]; then echo "swarm.sh upgrade already runs here (${h}); this one started nothing"; return 0; fi
  echo "swarm.sh upgrade already runs here for ${s} (${h}): ${1:-the whole project} was not moved; run it again once the running one ends"
  return 2
}

# upgrade_lock <log> [epic] — take this project's upgrade (pid_lock): UPGRADE_PID gets this run's pid,
# scope and <log>. While another runs it names that one (upgrade_busy) and fails: 1 when that one
# covers [epic], 2 when not.
upgrade_lock() {
  local rc=0
  pid_lock "${UPGRADE_PID}" "$$ ${2:--} $1" upgrade_holder && return 0
  upgrade_busy "${2:-}" || rc=$?
  return $((rc == 2 ? 2 : 1))
}

# upgrade_unlock — let this project's upgrade go, if this run still holds it.
upgrade_unlock() {
  local pid
  read -r pid _ 2>/dev/null < "${UPGRADE_PID}" || return 0
  [[ "${pid}" != "$$" ]] || rm -f "${UPGRADE_PID}"
}

# upgrade_status — status's lines while an upgrade runs here: its scope, pid and log, and the agents
# in its scope not yet on the version it moves them to.
upgrade_status() {
  local h s v old
  h="$(upgrade_holder)" || return 0
  s="${h%% *}"; [[ "${s}" != - ]] || s=""
  v="${h##*/upgrade-}"; v="${v%.log}"   # the running upgrade's version, from its log's name
  old="$(upgrade_list "$(upgrade_want "${s}")" "${v}" | awk -F'\t' '$4 == "old" { printf " %s", $1 }')"
  printf '\nUpgrade%s running (%s)\n  still on an old version:%s\n' "${s:+ of ${s}}" "${h#* }" "${old:- none}"
}

# upgrade_round <want> <version> <end-ms> — one round of upgrade_agents, over the agents in <want>
# (upgrade_want) read afresh, herdr's list once (UPGRADE_HERDR): each conductor whose agents will move
# is asked for its handover (upgrade_ask); while one is idle with it written, the agents are read
# again, so a builder it started before it paused, or after a watch woke it, counts. Then each idle
# builder whose conductor is idle with its handover in, and whose Claude review agent is not busy
# (upgrade_hold, read after the builder's own state, so a gone one is left at once), is restarted
# (upgrade_restart, waiting one round at most, upgrade_round_end), one whose session is gone or
# unknown is left, a busy one waits; last, each conductor whose builders are all moved or left is
# moved (upgrade_conductor).
# Fails while any agent waits, and when herdr's list cannot be read, so that round counts as waiting
# rather than as one with nothing left to move. A conductor paused here that a good list no longer
# holds is left.
upgrade_round() {
  local list name pane role cur e h st rc f olds=" " held=" " waits="" fresh=""
  upgrade_reread "$1" "$2" || return 1
  list="$(upgrade_open < "${UPGRADE_DIR}/list")"
  while IFS=$'\t' read -r name pane role cur; do
    [[ -n "${name}" && "${role}" != conduct && "${cur}" == old ]] || continue
    olds+="$(upgrade_epic "${name}" "${role}") "
  done <<< "${list}"
  # Handovers first, so no conductor acts on a builder mid-restart; one already on this version is
  # paused too while its builders restart.
  while IFS=$'\t' read -r name pane role cur; do
    [[ -n "${name}" && "${role}" == conduct ]] || continue
    e="$(upgrade_epic "${name}" conduct)"
    [[ "${cur}" == old || "${olds}" == *" ${e} "* || -e "${UPGRADE_DIR}/hand-${name}" ]] || continue
    upgrade_ask "${name}" "${pane}" "${e}" "$2" </dev/null || waits=1
    [[ ! -e "${UPGRADE_DIR}/ready-${name}" ]] || fresh=1
  done <<< "${list}"
  if [[ -n "${fresh}" ]]; then
    upgrade_reread "$1" "$2" || return 1
    list="$(upgrade_open < "${UPGRADE_DIR}/list")"
  fi
  while IFS=$'\t' read -r name pane role cur; do
    [[ -n "${name}" && "${role}" != conduct && "${cur}" == old ]] || continue
    e="$(upgrade_epic "${name}" "${role}")"
    rm -f "${UPGRADE_DIR}/rheld-${name}"
    case "$(upgrade_hold "${e}" "${list}")" in
      left) upgrade_left "${name}" "$(upgrade_held_why "${e}" left)"; continue ;;
      wait) held+="${e} "; continue ;;
    esac
    st="$(upgrade_state "${name}" "${pane}")"
    # Its review agent holds it only once its own session is known to be there: a gone one is left now.
    if [[ "${st}" != gone ]]; then
      h="$(upgrade_hold "${e}" "${list}" "$(upgrade_reviewer "${name}" "${role}")")"
      if [[ "${h}" == "review "* ]]; then echo "${h}" > "${UPGRADE_DIR}/rheld-${name}"; held+="${e} "; continue; fi
    fi
    case "${st}" in
      idle) rc=0; upgrade_restart "${name}" "${pane}" "${role}" "$2" "$(upgrade_round_end "$3")" || rc=$?
            [[ ${rc} -ne 2 ]] || held+="${e} " ;;
      gone) upgrade_left "${name}" "its Claude session is gone, so it is not restarted" ;;
      *) held+="${e} " ;;   # busy, or unknown: a bad read of Claude Code's list, read again next round
    esac
  done <<< "${list}"
  while IFS=$'\t' read -r name pane role cur; do
    [[ -n "${name}" && "${role}" == conduct && -e "${UPGRADE_DIR}/ready-${name}" && ! -e "${UPGRADE_DIR}/left-${name}" ]] || continue
    if [[ "${held}" == *" $(upgrade_epic "${name}" conduct) "* ]]; then waits=1; continue; fi   # loose-match: ok space-padded, so a whole word
    upgrade_conductor "${name}" "${pane}" "${cur}" "$2" "$(upgrade_round_end "$3")" || waits=1
  done <<< "${list}"
  UPGRADE_HERDR=""
  [[ -z "${waits}" && "${held}" == " " ]]
}

# upgrade_reread <want> <version> — read herdr's list (upgrade_read_herdr, for the round) and save the
# run's agents (list); fails when herdr's list cannot be read. Not in $(...): the round keeps the read.
# An agent the last read held that still waited (on its old version, or paused for its handover) and
# this one does not is left, never forgotten; a paused conductor's pause marker goes, and its
# builders no longer wait on it (gone-).
upgrade_reread() {
  local prev name pane role cur d="${UPGRADE_DIR}"
  upgrade_read_herdr || return 1
  prev=""; [[ ! -f "${d}/list" ]] || prev="$(upgrade_open < "${d}/list")"
  upgrade_list "$1" "$2" > "${d}/list"
  while IFS=$'\t' read -r name pane role cur; do
    [[ -n "${name}" && ( "${cur}" == old || -e "${d}/hand-${name}" ) ]] || continue
    ! grep -q "^${name}"$'\t' "${d}/list" || continue   # loose-match: ok agent names are [a-z0-9_-], anchored by ^ and a tab
    if [[ -e "${d}/hand-${name}" ]]; then
      rm -f "$(upgrade_paused "${name}")"; : > "${d}/gone-${name}"
      upgrade_left "${name}" "it left herdr's agent list while paused for its handover"
    else upgrade_left "${name}" "it left herdr's agent list before it was moved"; fi
  done <<< "${prev}"
}

# upgrade_round_end <end-ms> — how long one restart may wait for its agent to go idle: a round (60
# seconds, scaled as nap is), never past <end-ms>; one still busy then waits for the next round.
upgrade_round_end() {
  local r
  r=$(($(now_ms) + $(awk -v s="$(scaled 60)" 'BEGIN { printf "%d", s * 1000 }')))
  echo $((r < $1 ? r : $1))
}

# upgrade_read_herdr — read herdr's agent list for the round (UPGRADE_HERDR); fails, keeping none,
# when herdr gives no list it can parse.
upgrade_read_herdr() {
  if UPGRADE_HERDR="$(herdr agent list 2>/dev/null)" && json 'len(d["result"]["agents"])' <<< "${UPGRADE_HERDR}" >/dev/null 2>&1; then return 0; fi
  UPGRADE_HERDR=""
  return 1
}

# upgrade_herdr — herdr's agent list: the round's copy (UPGRADE_HERDR) while a round runs, else read now.
upgrade_herdr() { if [[ -n "${UPGRADE_HERDR}" ]]; then printf '%s\n' "${UPGRADE_HERDR}"; else herdr agent list 2>/dev/null; fi; }

# upgrade_held_why <epic> <hold> — why a builder of <epic> was held, from its upgrade_hold: `review
# <name>`, its review agent stayed busy; else its conductor wrote its handover but stayed busy, or it
# wrote none.
upgrade_held_why() {
  local f
  [[ "$2" != "review "* ]] || { echo "its review agent ${2#review } stayed busy"; return; }
  f="$(cat "${UPGRADE_DIR}/hand-$(conductor_name "$1")" 2>/dev/null)" || f=""
  if [[ -n "${f}" && -s "${f}" ]]; then echo "its conductor wrote its handover but stayed busy"; else echo "its conductor wrote no handover"; fi
}

# upgrade_end <want> <version> — at the end of the wait: each conductor marked ready is read again (it
# may have gone busy since), each builder still waiting is left, then each conductor idle with its
# handover in is moved (upgrade_conductor); one whose handover is not, or that
# stayed busy after it, is told to carry on as before, by prompt once it is idle (UPGRADE_GRACE_MS
# more), since one that ended its turn reads no inbox, else by a note, and left. When herdr's list
# cannot be read then, the last round's (list) stands in, so no agent still waiting is missed.
upgrade_end() {
  local list name pane role cur e h
  if upgrade_reread "$1" "$2"; then list="$(upgrade_open < "${UPGRADE_DIR}/list")"
  elif [[ -e "${UPGRADE_DIR}/list" ]]; then
    echo "herdr's agent list could not be read at the end; the last round's names the agents" >> "${UPGRADE_DIR}/summary"
    list="$(upgrade_open < "${UPGRADE_DIR}/list")"
  else echo "herdr's agent list could not be read during the run, so no agent was moved" >> "${UPGRADE_DIR}/summary"; list=""; fi
  UPGRADE_HERDR=""   # each state read from here on asks herdr afresh: the end may wait minutes
  while IFS=$'\t' read -r name pane role cur; do
    [[ -n "${name}" && "${role}" == conduct && -e "${UPGRADE_DIR}/ready-${name}" ]] || continue
    [[ "$(upgrade_state "${name}" "${pane}" </dev/null)" == idle ]] || rm -f "${UPGRADE_DIR}/ready-${name}"
  done <<< "${list}"
  while IFS=$'\t' read -r name pane role cur; do
    [[ -n "${name}" && "${role}" != conduct && "${cur}" == old ]] || continue
    e="$(upgrade_epic "${name}" "${role}")"
    h="$(upgrade_hold "${e}" "${list}" "$(upgrade_reviewer "${name}" "${role}")")"
    [[ -n "${h}" ]] || h="$(cat "${UPGRADE_DIR}/rheld-${name}" 2>/dev/null)" || h=""   # held by it in the last round
    if [[ -z "${h}" ]]; then upgrade_left "${name}" "still busy at the end of the wait"
    else upgrade_left "${name}" "$(upgrade_held_why "${e}" "${h}")"; fi
  done <<< "${list}"
  while IFS=$'\t' read -r name pane role cur; do
    [[ -n "${name}" && "${role}" == conduct ]] || continue
    if [[ ! -e "${UPGRADE_DIR}/hand-${name}" ]]; then   # never asked: first seen now, or no round read herdr
      [[ "${cur}" != old ]] || upgrade_left "${name}" "not reached before the end of the wait, never asked for a handover"
      continue
    fi
    if [[ -e "${UPGRADE_DIR}/ready-${name}" ]]; then upgrade_conductor "${name}" "${pane}" "${cur}" "$2" 0 && continue; fi
    upgrade_idle "${name}" "${pane}" $(($(now_ms) + UPGRADE_GRACE_MS)) </dev/null || true
    upgrade_say "${name}" "${pane}" "swarm.sh upgrade gave up waiting for your handover: ignore its request, and carry on as before, on the version you run." </dev/null || true
    rm -f "$(upgrade_paused "${name}")"
    if [[ -s "$(cat "${UPGRADE_DIR}/hand-${name}")" ]]; then upgrade_left "${name}" "still busy after its handover at the end of the wait, told to carry on as before"
    else upgrade_left "${name}" "no handover by the end of the wait, told to carry on as before"; fi
  done <<< "${list}"
}

# upgrade_open — upgrade_list's lines on stdin, but those of the agents this run already moved or left.
upgrade_open() {
  local l
  while IFS= read -r l; do
    [[ -n "${l}" && ! -e "${UPGRADE_DIR}/done-${l%%$'\t'*}" && ! -e "${UPGRADE_DIR}/left-${l%%$'\t'*}" && ! -e "${UPGRADE_DIR}/kept-${l%%$'\t'*}" ]] || continue
    printf '%s\n' "${l}"
  done
}

# upgrade_moved <name> <line> / upgrade_left <name> <why> — this run is done with <name>: moved, or
# left on its old version for <why>; its line goes in the summary upgrade prints at the end. One
# already on this version (a conductor paused for its builders) is never left: it is kept, named
# with <why>, and fails nothing.
upgrade_moved() { : > "${UPGRADE_DIR}/done-$1"; echo "$2" >> "${UPGRADE_DIR}/summary"; }
upgrade_left() {
  if [[ "$(agent_version "$1")" == "${UPGRADE_NEW}" ]]; then
    : > "${UPGRADE_DIR}/kept-$1"; echo "$1: already on ${UPGRADE_NEW}: $2" >> "${UPGRADE_DIR}/summary"; return 0
  fi
  : > "${UPGRADE_DIR}/left-$1"; echo "$1: left on $(agent_version "$1"): $2" >> "${UPGRADE_DIR}/summary"
}

# upgrade_epic <name> <role> — the epic whose conductor <name> answers to, kept for the run: a
# conductor's own (conduct_epic), a builder's or review agent's story's (backlog: none), - for one
# with no story.
upgrade_epic() {
  local f="${UPGRADE_DIR}/epic-$1" s e=-
  [[ ! -s "${f}" ]] || { cat "${f}"; return; }
  if [[ "$2" == conduct ]]; then e="$(conduct_epic "$1")"
  else
    while IFS= read -r s; do
      [[ "$(agent_name "$(basename "${s}" .md)")" == "$1" || "$(agent_name "review-$(basename "${s}" .md)")" == "$1" ]] || continue
      e="$(fm "${s}" epic)"; e="${e:-backlog}"; break
    done < <(board stories)
  fi
  echo "${e}" > "${f}"
  echo "${e}"
}

# upgrade_hold <epic> <list> [reviewer] — whether a builder of <epic> waits: left when its conductor
# was left (or kept) with no handover, wait while the conductor is in <list> (upgrade_list, not yet
# moved) and not idle with its handover in this round (ready-); else, as when the conductor left
# herdr's list (gone-), so none is left to act on them, `review <reviewer>` while the builder's
# review agent (upgrade_reviewer), which reviews its PR, is busy (upgrade_review_busy), left or not;
# else nothing.
upgrade_hold() {
  local c
  if [[ "$1" != - ]]; then
    c="$(conductor_name "$1")"
    if [[ ! -e "${UPGRADE_DIR}/ready-${c}" && ! -e "${UPGRADE_DIR}/gone-${c}" ]]; then
      if [[ -e "${UPGRADE_DIR}/left-${c}" || -e "${UPGRADE_DIR}/kept-${c}" ]]; then echo left; return 0; fi
      if grep -q "^${c}"$'\t' <<< "$2"; then echo wait; return 0; fi   # loose-match: ok conductor names are [a-z0-9_-], anchored by ^ and a tab
    fi
  fi
  ! upgrade_review_busy "${3:-}" || echo "review $3"
}

# upgrade_reviewer <name> <role> — the agent name of the review agent of the story whose builder is
# <name> (agent_name of review-<slug>, exact), kept for the run; nothing for an agent in no builder
# role, or with no story.
upgrade_reviewer() {
  local f="${UPGRADE_DIR}/reviewer-$1" s r=""
  [[ " ${BUILDER_ROLES} " == *" $2 "* ]] || return 0
  [[ ! -e "${f}" ]] || { cat "${f}"; return; }
  while IFS= read -r s; do
    s="$(basename "${s}" .md)"
    [[ "$(agent_name "${s}")" == "$1" ]] || continue
    r="$(agent_name "review-${s}")"; break
  done < <(board stories)
  echo "${r}" > "${f}"
  echo "${r}"
}

# upgrade_review_busy <reviewer> — succeed while <reviewer> is in the run's last read of its agents
# (list, a Claude agent) on its old version, not moved since, and neither idle nor gone (upgrade_state).
# One left on its old version still holds: it is still reviewing its builder's PR. A codex review agent
# is in no list, so it holds nothing.
upgrade_review_busy() {
  local name pane role cur
  [[ -n "$1" && -f "${UPGRADE_DIR}/list" && ! -e "${UPGRADE_DIR}/done-$1" && ! -e "${UPGRADE_DIR}/kept-$1" ]] || return 1
  while IFS=$'\t' read -r name pane role cur; do
    [[ "${name}" == "$1" && "${cur}" == old ]] || continue
    case "$(upgrade_state "${name}" "${pane}" </dev/null)" in idle|gone) return 1 ;; *) return 0 ;; esac
  done < "${UPGRADE_DIR}/list"
  return 1
}

# upgrade_ask <conductor> <pane> <epic> <version> — where the conductor is with its handover. The
# first time, its env: names are checked (refused: it is left, asked for nothing), then it is asked
# (upgrade_request). One asked by note, in its inbox, that is idle with no handover is asked again by
# prompt. Ready while the file is written and it is idle, read again each round, since an ended turn
# reads idle while a background watch can still wake it; left at once when its session is gone.
# Fails while it waits.
upgrade_ask() {
  local d="${UPGRADE_DIR}" names day file n=1 st
  if [[ ! -e "${d}/hand-$1" ]]; then
    names="$(upgrade_env "$1" conduct "$3")" || { upgrade_left "$1" "asked for no handover: ${names}"; return 0; }
    day="$(date +%F)"; file="${PROJECT_DIR}/.swarm/handover-$3-${day}.md"
    while [[ -e "${file}" ]]; do n=$((n + 1)); file="${PROJECT_DIR}/.swarm/handover-$3-${day}-${n}.md"; done
    echo "${file}" > "${d}/hand-$1"
    upgrade_request "$1" "$2" "$4" || { rm -f "$(upgrade_paused "$1")"; upgrade_left "$1" "could not be asked for a handover"; return 0; }
  fi
  : > "$(upgrade_paused "$1")" || true
  st="$(upgrade_state "$1" "$2")"
  case "${st}" in
    gone) rm -f "$(upgrade_paused "$1")"; upgrade_left "$1" "its Claude session is gone, so it wrote no handover"; return 0 ;;
    idle) if [[ -s "$(cat "${d}/hand-$1")" ]]; then : > "${d}/ready-$1"; return 0; fi
          [[ "$(cat "${d}/asked-$1")" != note ]] || upgrade_request "$1" "$2" "$4" || true ;;
  esac
  rm -f "${d}/ready-$1"
  return 1
}

# upgrade_request <conductor> <pane> <version> — mark it paused (upgrade_paused), then ask it
# (upgrade_say) to write its handover to its file and end its turn; asked- keeps whether that went as
# a prompt or a note.
upgrade_request() {
  local rc=0
  { mkdir -p "${PROJECT_DIR}/.swarm/inbox" && : > "$(upgrade_paused "$1")"; } || return 1
  upgrade_say "$1" "$2" "swarm.sh upgrade is moving this epic's agents to swarm-dev $3, restarting each with --resume, so it keeps its context. Write a handover to $(cat "${UPGRADE_DIR}/hand-$1"): each open PR with its review round, what its builder still owes, and any findings you have not sent. Then end your turn: start nothing and run no wait or watch until upgrade tells you to carry on." || rc=$?
  echo "${UPGRADE_SAID}" > "${UPGRADE_DIR}/asked-$1"
  return "${rc}"
}

# upgrade_restart <name> <pane> <role> <version> <end-ms> [then] — restart <name> (upgrade_one) and
# tell it (upgrade_told) in a subshell, so a die stops that agent alone; its env: names first, before
# anything is sent. A die's message is why it is left, with upgrade_one's resume hint once its claude
# has exited (upgrade_hint). Exits 2, leaving nothing, when the agent was busy by <end-ms>.
upgrade_restart() {
  local why="${UPGRADE_DIR}/why" w
  rm -f "${why}" "${UPGRADE_DIR}/hint-$1" "${UPGRADE_DIR}/busy-$1"
  # shellcheck disable=SC2034 # DIE_FILE and DIE_LEVEL are die's, this subshell's own
  if ( DIE_FILE="${why}"; DIE_LEVEL="${BASH_SUBSHELL}"
       names="$(upgrade_env "$1" "$3" "$(upgrade_epic "$1" "$3")")" || die "$1: ${names}, left on $(agent_version "$1")"
       upgrade_one "$1" "$2" "${names}" "$4" "$5"
       upgrade_told "$1" "$2" "$4" "${6:-}" ) </dev/null; then return 0; fi
  if [[ -e "${UPGRADE_DIR}/busy-$1" ]]; then rm -f "${UPGRADE_DIR}/busy-$1"; return 2; fi
  w="$(cat "${why}" 2>/dev/null)" || w=""
  w="${w#"$1: "}"
  upgrade_left "$1" "$(sed -E 's/[,;] (left )?on [^ ]+$//' <<< "${w:-its restart failed}")$(upgrade_hint "$1")"
  return 1
}

# upgrade_conductor <conductor> <pane> <old|new> <version> <end-ms> — move a conductor whose handover
# is in, told its handover and which of its builders were restarted and which left: restarted
# (upgrade_restart), or, already on <version>, only told to carry on. One whose restart failed while
# its claude still runs (it ended its turn for upgrade) is told to carry on where it is; one whose
# claude exited got its resume hint from upgrade_one. Exits 2, still paused, when it was busy by
# <end-ms>.
upgrade_conductor() {
  local hand about rc=0
  hand="$(cat "${UPGRADE_DIR}/hand-$1")"
  about="$(upgrade_about "$(upgrade_epic "$1" conduct)" "$4")"
  if [[ "$3" == new ]]; then
    if upgrade_say "$1" "$2" "swarm.sh upgrade is done with your builders. ${about} Your handover is ${hand}. Carry on where you stopped." </dev/null; then
      upgrade_moved "$1" "$1: already on $4, told to carry on"
    else upgrade_left "$1" "could not be told to carry on; tell it by hand"; fi
  else
    rc=0; upgrade_restart "$1" "$2" conduct "$4" "$5" "Your handover is ${hand}. ${about} Carry on where you stopped." || rc=$?
    [[ ${rc} -ne 2 ]] || return 2
  fi
  if [[ ${rc} -eq 1 ]] && upgrade_flags "$2" >/dev/null </dev/null; then
    upgrade_say "$1" "$2" "swarm.sh upgrade could not restart you, so you stay on the version you run. ${about} Your handover is ${hand}. Carry on where you stopped." </dev/null \
      || echo "$1: could not be told to carry on; tell it by hand" >> "${UPGRADE_DIR}/summary"
  fi
  rm -f "$(upgrade_paused "$1")"   # once it has been told to carry on, whichever way
}

# upgrade_about <epic> <version> — the line that tells <epic>'s conductor which of its builders this
# run restarted and which it left.
upgrade_about() {
  local f n c moved="" left=""
  c="$(conductor_name "$1")"
  for f in "${UPGRADE_DIR}"/epic-*; do
    n="${f##*/epic-}"
    [[ -e "${f}" && "${n}" != "${c}" && "$(cat "${f}")" == "$1" ]] || continue
    [[ ! -e "${UPGRADE_DIR}/done-${n}" ]] || moved+=" ${n}"
    [[ ! -e "${UPGRADE_DIR}/left-${n}" ]] || left+=" ${n}"
  done
  echo "Builders restarted on swarm-dev $2:${moved:- none}. Left on their old version:${left:- none}."
}

# upgrade_want <epic>|backlog — the agent names upgrade moves, space-separated with a space each side:
# the conductor and, for each story of <epic> (backlog: with no epic), its builder and review agent.
# Empty with no argument: every agent.
upgrade_want() {
  local f e="$1" want
  [[ -n "$1" ]] || return 0
  [[ "${e}" != backlog ]] || e=""
  want=" $(conductor_name "$1") "
  while IFS= read -r f; do
    [[ "$(fm "${f}" epic)" == "${e}" ]] || continue
    f="$(basename "${f}" .md)"; want+="$(agent_name "${f}") $(agent_name "review-${f}") "
  done < <(board stories)
  echo "${want}"
}

# upgrade_list <want> <version> — each agent named in <want> (upgrade_want; empty: any) whose newest
# agents.tsv line is a Claude one, that herdr holds in a pane recorded here (one read, upgrade_herdr),
# and not this one, in start order: name, pane, role and old or new (already on <version>),
# tab-separated.
upgrade_list() {
  local name role kind pane panes n p
  panes="$(upgrade_herdr | SWARM_PANES="$(own_panes)" json '"\n".join("%s %s" % (a.get("name"), a.get("pane_id")) for a in d["result"]["agents"] if a.get("name") and a.get("pane_id") in e["SWARM_PANES"].split())' 2>/dev/null)" || panes=""
  while read -r name role kind; do
    [[ "${kind}" == claude && ( -z "$1" || "$1" == *" ${name} "* ) ]] || continue
    pane=""
    while read -r n p; do [[ "${n}" != "${name}" ]] || { pane="${p}"; break; }; done <<< "${panes}"
    [[ -n "${pane}" && "${pane}" != "${HERDR_PANE_ID:-}" ]] || continue
    printf '%s\t%s\t%s\t%s\n' "${name}" "${pane}" "${role}" "$(if [[ "$(agent_version "${name}")" == "$2" ]]; then echo new; else echo old; fi)"
  done < <(awk -F'\t' 'NF == 7 { r[$3] = $2; k[$3] = $4; if (!($3 in o)) o[$3] = n++ }
    END { for (x in r) print o[x], x, r[x], k[x] }' "${AGENTS_LOG}" 2>/dev/null | sort -n | cut -d' ' -f2-)
}

# upgrade_say <conductor> <pane> <text> — send a conductor <text>: a prompt when it is idle
# (upgrade_state), else a note in its inbox, which it reads after its wait; UPGRADE_SAID says which.
upgrade_say() {
  local f rc=0
  f="$(mktemp "${TMPDIR:-/tmp}/swarm-upgrade.XXXXXX")" || return 1
  printf '%s\n' "$3" > "${f}"
  if [[ "$(upgrade_state "$1" "$2")" == idle ]]; then UPGRADE_SAID=prompt; (deliver_prompt "$1" "${f}" "$2") >&2 || rc=$?
  else UPGRADE_SAID=note; (tell_agent "$1" note "${f}") >/dev/null || rc=$?; fi
  rm -f "${f}"
  return "${rc}"
}

# agent_version <name> — the version the agent holding <name> started on (record_agent, upgrade_told),
# or unknown when none is recorded.
agent_version() {
  local v
  v="$(cat "${VERSIONS_DIR}/$1" 2>/dev/null)" || v=""
  echo "${v:-unknown}"
}

# upgrade_told <name> <pane> <version> [then] — tell a restarted agent this version's swarm.sh path,
# which its brief names under the old root, that the restart stopped its background commands, then
# [then] (a conductor's handover and its builders), else that it goes on as before. Only then is it
# on <version>: its old and new version go in the summary (upgrade_moved) and the new is recorded.
upgrade_told() {
  local f then="If you were waiting on the conductor, end your turn; otherwise carry on where you stopped." rc=0
  [[ -z "${4:-}" ]] || then="$4"
  f="$(mktemp "${TMPDIR:-/tmp}/swarm-upgrade.XXXXXX")" || die "$1: restarted on $3, but could not tell it the new swarm.sh path"
  printf '%s\n' "swarm.sh upgrade restarted you on swarm-dev $3. Its swarm.sh is ${SWARM_HOME}/bin/swarm.sh: use that path wherever your brief names another. The restart stopped any background command, subagent or monitor you had running (a wait-pr, a codex-review, a watch): start again any you still need. ${then}" > "${f}"
  (deliver_prompt "$1" "${f}" "$2") || rc=$?
  rm -f "${f}"
  [[ ${rc} -eq 0 ]] || die "$1: restarted on $3, but was not told the new swarm.sh path"
  upgrade_moved "$1" "$1: $(agent_version "$1") -> $3"
  { mkdir -p "${VERSIONS_DIR}" && echo "$3" > "${VERSIONS_DIR}/$1"; } || true
}

# upgrade_env <name> <role> [epic] — the env: names clean_env gives <name> again: a conductor's epic's
# (epic_env, empty for the backlog's), a builder's story's (story_env), none for any other agent.
upgrade_env() {
  local f
  if [[ "$2" == conduct ]]; then
    if [[ "$3" == backlog ]]; then epic_env ""; else epic_env "$3"; fi
    return
  fi
  [[ " ${BUILDER_ROLES} " == *" $2 "* ]] || return 0
  while IFS= read -r f; do
    [[ "$(agent_name "$(basename "${f}" .md)")" != "$1" ]] || { story_env "${f}"; return; }
  done < <(board stories)
}

# upgrade_paused <conductor> — the file that says upgrade asked <conductor> for a handover and has not
# yet told it to carry on. While it is under an hour old it holds back tell's wake prompt (note_wake),
# so a note does not send the paused conductor back to its waits; upgrade_ask keeps it fresh.
upgrade_paused() { echo "$(conductor_inbox "$1").upgrade"; }

# UPGRADE_HINT: what upgrade_one's EXIT trap prints once the agent's claude has exited, set then.
UPGRADE_HINT=""

# upgrade_one <name> <pane> <env-names> <version> <end-ms> — once <name> is idle (upgrade_idle, by
# <end-ms>), write this version's resume command (resume_file), send ctrl+c twice at once (claude
# exits only on a second within a moment) until claude has left its pane, then start it there again,
# through clean_env with this version's bin first on PATH and <env-names> and agent_env's names
# (agent_env_names): --resume of herdr's session for the pane,
# with the flags its claude ran with (herdr pane process-info). Any failure once claude has exited
# keeps the pane and says how to resume the session by hand, in its folder. Run in a subshell: a die
# stops only this agent.
upgrade_one() {
  local name="$1" pane="$2" old session a out cwd why rc flags=() resume=() try names
  old="$(agent_version "${name}")"
  names="$(agent_env_names)"; names="${names}${names:+ }$3"   # as start_agent gives every agent
  upgrade_idle "${name}" "${pane}" "$5" && rc=0 || rc=$?
  [[ ${rc} -ne 2 ]] || die "${name}: its Claude session is gone, so it is not restarted; left on ${old}"
  if [[ ${rc} -ne 0 ]]; then
    [[ -z "${UPGRADE_DIR}" ]] || : > "${UPGRADE_DIR}/busy-${name}"
    die "${name}: still busy at the end of the wait, left on ${old}"
  fi
  session="$(session_for_pane "${pane}")"
  [[ -n "${session}" ]] || die "${name}: herdr gives no session for it, so it cannot be resumed; left on ${old}"
  out="$(upgrade_flags "${pane}")" && rc=0 || rc=$?
  [[ ${rc} -ne 3 ]] || die "${name}: a flag of its claude holds a control character, which herdr refuses in a resume command; left on ${old}"
  [[ ${rc} -ne 4 ]] || die "${name}: herdr pane process-info could not be read, so it is left as it is, on ${old}"
  [[ ${rc} -eq 0 ]] || die "${name}: no claude in pane ${pane} (herdr pane process-info), left on ${old}"
  cwd="${out%%$'\n'*}"; out="${out#"${cwd}"}"; out="${out#$'\n'}"
  if [[ -n "${out}" ]]; then while IFS= read -r a; do flags+=("${a}"); done <<< "${out}"; fi
  resume=(python3 -I "${RESUME_DIR}/${session}.py" claude --resume "${session}" ${flags[@]+"${flags[@]}"})
  why="$(resume_refusal "${resume[@]}")" && die "${name}: herdr would refuse its resume command (${why}), left on ${old}"
  resume_file "${name}" "${session}" "${names}" "${resume[@]}"
  a="$(upgrade_path)"
  # Before the first ctrl+c, so a claude that exits late, or a read that fails, still says how to resume it.
  UPGRADE_HINT="${name}: not started again; if pane ${pane} shows a shell, claude --resume ${session}, run in ${cwd}, brings the session back"
  # In a file too, there until the restart succeeds: a TERM to upgrade runs no EXIT trap here.
  [[ -z "${UPGRADE_DIR}" ]] || echo "${UPGRADE_HINT#*: }" > "${UPGRADE_DIR}/hint-${name}"
  trap 'echo "swarm: ${UPGRADE_HINT}" >&2' EXIT
  for try in 1 2 3; do
    herdr pane send-keys "${pane}" ctrl+c ctrl+c >/dev/null 2>&1 || true
    nap 1
    upgrade_flags "${pane}" >/dev/null && rc=0 || rc=$?
    [[ ${rc} -ne 1 ]] || break   # no claude there now: it exited
    [[ ${rc} -ne 4 ]] || die "${name}: herdr pane process-info could not be read after the ctrl+c, so whether claude exited is not known"
    [[ ${try} -lt 3 ]] || die "${name}: claude did not exit on ctrl+c, left on ${old}"
  done
  local -x SWARM_RESUME="${RESUME_DIR}/${session}.argv"
  PATH="${a}" clean_env "${pane}" "${name}" "${names}" keep   # the agent's PATH; herdr below still runs from the lead's
  out="$(herdr agent start "${name}" --kind claude --pane "${pane}" --timeout 60000 -- --resume "${session}" ${flags[@]+"${flags[@]}"} 2>&1)" \
    || die "${name}: herdr could not start it again (${out})"
  trap - EXIT
  [[ -z "${UPGRADE_DIR}" ]] || rm -f "${UPGRADE_DIR}/hint-${name}"
  # As start_agent does, so a herdr restart before the agent's first hook report resumes it with its
  # flags; the hooks report the same command on every prompt, so a refusal here only warns.
  rc="$(python3 -I -c 'import time; print(time.time_ns())')" || rc=""
  [[ -n "${rc}" ]] && herdr pane report-agent "${pane}" --source swarm --agent claude --state idle --seq "${rc}" \
      --agent-session-id "${session}" -- "${resume[@]}" >/dev/null 2>&1 \
    || echo "swarm: ${name}: herdr did not take its resume command; its next prompt's hook reports it" >&2
}

# upgrade_flags <pane> — claude_flags over herdr pane process-info for <pane>; exits 4 when herdr's
# answer cannot be read, as claude_flags does for one it cannot parse.
upgrade_flags() {
  local info
  info="$(herdr pane process-info --pane "$1" 2>/dev/null </dev/null)" || return 4
  claude_flags <<< "${info}"
}

# upgrade_state <name> <pane> — idle, busy, or gone or unknown for a session that will not come back
# on its own: Claude Code's own state for the session herdr has in <pane> now (upgrade_herdr; the one
# upgrade_one resumes; a /clear moves it from the one agents.tsv recorded), else read_state's, over
# agents.tsv's session (herdr 0.9.5 lists none); a turn stopped on
# an API error is idle, as tell reads it (api_stopped), as is one whose last assistant entry ended its
# turn though background shells keep Claude Code saying busy (turn_over, on that same session's log);
# one waiting on a prompt, or on a tool call's result, is busy.
upgrade_state() {
  local s sid
  sid="$(upgrade_herdr </dev/null | json "next(((a.get('agent_session') or {}).get('value','') for a in d['result']['agents'] if a.get('pane_id')=='$2'),'')" 2>/dev/null)" || sid=""
  if [[ -z "${sid}" ]]; then s="$(read_state "$1" </dev/null)"
  else
    s="$(claude_agents </dev/null | python3 -I -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    print("unknown"); sys.exit()
e = next((x for x in d if isinstance(x, dict) and x.get("sessionId") == sys.argv[1]), None) if isinstance(d, list) else None
print("unknown" if not isinstance(d, list) else "gone" if e is None else e.get("status") or "unknown")' "${sid}")" || s=unknown
  fi
  case "${s}" in
    idle|herdr:idle|herdr:done) echo idle ;;
    gone|unknown|herdr:unknown) echo "${s#herdr:}" ;;
    busy|herdr:working) if api_stopped "$1" "$2" </dev/null || turn_over "${sid:-$(recorded_session "$1")}"; then echo idle; else echo busy; fi ;;
    *) echo busy ;;
  esac
}

# turn_over <session> — succeed when <session>'s log ends on an assistant message that ended its turn
# (log_turn_over.py); fails with no session or log.
turn_over() { [[ -n "$1" ]] && python3 "${SWARM_HOME}/bin/lib/log_turn_over.py" "${CLAUDE_PROJECTS}" "$1"; }

# upgrade_idle <name> <pane> <end-ms> — succeed once <name> is idle (upgrade_state; herdr's wait is
# only the wake-up, as for settle); a busy one is waited on at least once, and fails when it is
# still busy at <end-ms>; exits 2 at once when its session is gone or unknown.
upgrade_idle() {
  local left st
  while :; do
    st="$(upgrade_state "$1" "$2")"
    case "${st}" in idle) return 0 ;; gone) return 2 ;; esac   # busy or unknown: wait on
    left=$(($3 - $(now_ms))); ((left > 0)) || left=1
    herdr agent wait "$2" --until idle --until "done" --timeout "${left}" </dev/null >/dev/null 2>&1 || true
    nap 10   # herdr may say idle at once while Claude Code still says busy
    [[ "$(upgrade_state "$1" "$2")" != idle ]] || return 0
    (($(now_ms) < $3)) || return 1
  done
}

# claude_flags — from herdr pane process-info on stdin, the folder of the pane's claude (argv[0]
# claude, or an npm install's node running its claude link or @anthropic-ai/claude-code/cli.js as
# argv[1]) on the first line, then its arguments but its --session-id or --resume and their value,
# one a line; fails when no claude runs there, exits 3 when an argument or the folder holds a
# control character, which a line cannot carry and herdr refuses anyway, and 4 on input it cannot read.
claude_flags() {
  python3 -I -c '
import json, os, sys
try:
    procs = json.load(sys.stdin)["result"]["process_info"].get("foreground_processes") or []
except (ValueError, KeyError, TypeError, AttributeError):
    sys.exit(4)
for p in procs:
    a = p.get("argv") or []
    if a and os.path.basename(a[0]) == "claude": rest = a[1:]
    elif len(a) > 1 and (os.path.basename(a[1]) == "claude" or a[1].endswith("/@anthropic-ai/claude-code/cli.js")): rest = a[2:]
    else: continue
    out, skip = [p.get("cwd") or "its folder"], False
    for x in rest:
        if skip: skip = False
        elif x in ("--session-id", "--resume"): skip = True
        else: out.append(x)
    if any(c < " " or c == "\x7f" for x in out for c in x): sys.exit(3)
    print("\n".join(out)); sys.exit(0)
sys.exit(1)'
}

# upgrade_path — PATH with this version's bin first and every other plugin root's bin (a folder with
# swarm.sh beside a .claude-plugin/plugin.json: an older version's) gone.
upgrade_path() {
  local d dirs out="${SWARM_HOME}/bin"
  IFS=: read -r -a dirs <<< "${PATH}"
  for d in ${dirs[@]+"${dirs[@]}"}; do [[ -z "${d}" || ( -x "${d}/swarm.sh" && -f "${d}/../.claude-plugin/plugin.json" ) ]] || out+=":${d}"; done
  echo "${out}"
}

# wait_command [--stall] [--idle] | --until-report <name> [timeout-ms] | --lead [timeout-ms] — the wait
# command: a conductor's wait, with no timeout under --until-report, any other agent's, or the lead's
# (wait_lead). --idle, on an agent that is not a conductor or review agent, exits WAIT_NOT_IDLE when the
# wait ends 0 on anything but idle or done (auth, waiting, gone, stepped up: or stepping up:), so
# `wait --idle <slug> && tell <slug> nudge <file>` tells only an agent whose turn is over.
wait_command() {
  local stall until idle n out rc
  [[ "${1:-}" != --lead ]] || { wait_lead "${2:-}"; return; }
  require_herdr; stall=""; until=""; idle=""
  case "${1:-}" in --until-report) until=1; shift ;; esac
  while :; do case "${1:-}" in --stall) stall=--stall; shift ;; --idle) idle=1; shift ;; *) break ;; esac; done
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
  elif [[ -z "${idle}" ]]; then wait_agent "${n}" "${2:-3600000}" "${stall}"
  else
    rc=0; out="$(wait_agent "${n}" "${2:-3600000}" "${stall}")" || rc=$?
    [[ -z "${out}" ]] || printf '%s\n' "${out}"
    [[ ${rc} -eq 0 ]] || return "${rc}"
    [[ "${out##*$'\n'}" =~ ^(idle|done)$ ]] || return "${WAIT_NOT_IDLE}"
  fi
}
