# shellcheck shell=bash

# fm <file> <key> — <key>'s value in the item's state file (state_value), else the first line for
# <key> anywhere in <file>, or nothing.
fm() { state_value "$1" "$2" || sed -n "s/^$2: *//p" "$1" | head -1; }

# BOARD_STATE_DIR: where swarm.sh keeps the SET_FM_KEYS it writes for the board's items, a root of its
# own: STATE_DIR's files are tab records named after epic and story slugs.
BOARD_STATE_DIR="${PROJECT_DIR}/.swarm/board-state"

# state_path <item-file> [key] — set STATE_PATH to the file under BOARD_STATE_DIR (stories/<slug> or
# epics/<slug>) that holds the SET_FM_KEYS swarm.sh wrote for a story or epic on the board, or to
# nothing for any other file, one that is gone, or a [key] not in SET_FM_KEYS. It sets a variable,
# not output, so fm reads it without a subshell.
state_path() {
  state_name "$@"
  [[ -f "$1" ]] || STATE_PATH=""
}

# state_name <item-file> [key] — state_path, for an item file that may be gone.
state_name() {
  local d="${1%/*}" n="${1##*/}"
  STATE_PATH=""
  [[ -z "${2:-}" || " ${SET_FM_KEYS} " == *" $2 "* ]] || return 0
  [[ ( "${d}" == "${BOARD}/stories" || "${d}" == "${BOARD}/epics" ) && "${n}" == *.md ]] || return 0
  STATE_PATH="${BOARD_STATE_DIR}/${d##*/}/${n%.md}"
}

# state_drop <item-file> — delete the item's state file and its lock (state_name), so a later item
# with its slug starts with no state.
state_drop() {
  state_name "$1"
  [[ -z "${STATE_PATH}" ]] || rm -rf "${STATE_PATH}" "${STATE_PATH}.lock"
}

# state_value <item-file> <key> — print <key>'s value from the item's state file (state_path; nothing
# when the line is empty, which clears the key) and succeed; fail when the state file has no line for
# it, or the item file's front matter no longer has the value its <key>@base: line recorded (a later
# edit to the file wins over what swarm.sh wrote before it). Dies when the state file is there but
# cannot be read: the committed value could be stale (a story in review read as ready).
state_value() {
  state_path "$1" "$2"
  [[ -f "${STATE_PATH}" ]] || return 1
  [[ -r "${STATE_PATH}" ]] || die "board state: cannot read ${STATE_PATH}; make it readable, or remove it to read $1 as committed"
  awk -v k="$2" 'function val(l, n) { l = substr(l, n + 1); sub(/^ +/, "", l); return l }
    FILENAME == ARGV[1] { if (!h && index($0, k ":") == 1) { v = val($0, length(k) + 1); h = 1 }
      if (!hb && index($0, k "@base:") == 1) { b = val($0, length(k) + 6); hb = 1 }
      next }
    /^---$/ && ++n == 2 { exit }
    n == 1 && index($0, k ":") == 1 { t = val($0, length(k) + 1); exit }
    END { if (!h || (hb && t != b)) exit 1; if (v != "") print v }' "${STATE_PATH}" "$1"
}

# board <dir> — the item files in <board>/<dir>/, never the README.
board() {
  local f
  for f in "${BOARD}/$1"/*.md; do
    [[ -e "${f}" && "$(basename "${f}")" != README.md ]] && echo "${f}"
  done
  return 0
}

# epic_has_stories <epic> [<slug>] — true when any story names <epic>. With <slug>, true when any
# story but <slug> does, not counting a kind: lead story with after: (it waits on the epic, so the
# epic goes without it): story_brief's test for the epic's last story.
epic_has_stories() {
  local s
  while IFS= read -r s; do
    [[ "$(fm "${s}" epic)" == "$1" ]] || continue
    [[ -n "${2:-}" ]] || return 0
    [[ "$(basename "${s}" .md)" == "$2" ]] && continue
    [[ "$(get_fm "${s}" kind)" == lead && -n "$(get_fm "${s}" after)" ]] && continue
    return 0
  done < <(board stories)
  return 1
}

# next_step — what the chain does next, read from the board alone, so a run can stop anywhere and
# pick up again. Prints "<action> <arg>" on the first line and why on the second. In order:
#   collect <agent>   a conductor has written its report: read it, then close its tab
#   wait <agent>      a conductor exists and has not reported (idle between its own steps counts);
#                     why starts `auth:` when its login expired (wait then prints auth at once)
#   conduct <epic>    an active epic has a story an agent can build
#   resume <slug>     a one-off already started (its worktree exists): wait for it, then review
#   story <slug>      a ready story outside any epic
#   plan-epic <epic>  an active epic has no stories yet and nothing it depends on holds it up
#                     (plannable_epic), a child epic of a split one included; while a conductor
#                     works, this comes before its wait
#   plan-hld <hld>    an agreed HLD has no epics listed under ## Epics
#   escalated <slug>  a story whose Fable build failed, whose builder called its Done when
#                     impossible, or that close held (paused, cleared-on-error; held_for:), all kind:
#                     lead with escalated_from:: the lead re-scopes it or lifts the hold and runs
#                     reset, or drops it
#   release           origin/<base> has commits since the tag of plugin.json's version that change a
#                     file outside the board (release_due): the lead cuts a release
#   gate              only the user can move the board: lead stories, blocked
#                     stories, later stories and epics, draft epics, and PRs awaiting the user's merge
#   done              nothing open; start the next epic with /epic <title>
next_step() {
  local f slug epic kind story_epic src buildable="" waiting="" when held n tag base
  if [[ "${HERDR_ENV:-}" == 1 ]]; then
    # Any status: idle is not finished. Only the conductor's report file says it is done.
    # A retired conductor (renamed <name>-done, -done2 ...) has finished: never wait on it.
    # herdr lists every project's agents: only one in a pane this project opened counts.
    slug=$(herdr agent list 2>/dev/null | SWARM_PANES="$(own_panes)" json "next((a['name'] for a in d['result']['agents'] if a.get('name','').startswith('conduct-') and not a['name'].rstrip('0123456789').endswith('-done') and a.get('pane_id') in e.get('SWARM_PANES','').split()),'')" 2>/dev/null || true)
    if [[ -n "${slug}" ]]; then
      if [[ -f "$(conductor_report "${slug}")" ]]; then
        echo "collect ${slug}"; echo "the conductor ${slug} has finished and written its report"
      elif [[ "$(session_state "${slug}")" == idle ]] && login_expired "${slug}"; then
        # As in wait, only an idle session is auth: wait returns it at once, and /swarm-dev:swarm stops there
        # for the user's /login.
        echo "wait ${slug}"; echo "auth: the conductor ${slug} stopped on an expired login; run /login, then /swarm-dev:swarm tells it to resume"
      elif epic="$(plannable_epic)" && [[ -n "${epic}" ]]; then
        echo "plan-epic ${epic}"
        echo "the active epic ${epic} has no stories yet, and the conductor ${slug} is still working: start swarm.sh wait --until-report ${slug} in the background, then plan ${epic}"
      else
        echo "wait ${slug}"; echo "the conductor ${slug} is still working (it has not written its report)"
      fi
      return
    fi
  fi
  # Stories an agent can build: ready, and of a kind an agent builds. "<epic> <slug>" per line.
  while IFS= read -r f; do
    [[ "$(fm "${f}" status)" == ready ]] || continue
    kind=$(fm "${f}" kind)
    agent_kind "${kind}" || continue
    buildable+="$(fm "${f}" epic) $(basename "${f}" .md)"$'\n'
  done < <(board stories)
  # A one-off keeps status: ready until its PR merges, so an existing worktree means it has started.
  while read -r story_epic slug; do
    [[ -n "${story_epic}" && -z "${slug}" ]] || continue
    src="$(repo_dir "$(fm "${BOARD}/stories/${story_epic}.md" repo)")" || continue
    [[ -d "$(worktree_for "${src}" "${story_epic}")" ]] || continue
    echo "resume ${story_epic}"; echo "${story_epic} has already started: wait for its agent, then review its PR"; return
  done <<< "${buildable}"
  # An active epic's stories first: finish what is started before anything new.
  while read -r story_epic slug; do
    [[ -n "${slug}" && "$(fm "${BOARD}/epics/${story_epic}.md" status 2>/dev/null)" == active ]] || continue
    echo "conduct ${story_epic}"; echo "${slug} is ready in the active epic ${story_epic}"; return
  done <<< "${buildable}"
  while read -r story_epic slug; do
    # A one-off: `read` puts the lone slug in story_epic.
    [[ -n "${story_epic}" && -z "${slug}" ]] || continue
    echo "story ${story_epic}"; echo "${story_epic} is ready and belongs to no epic"; return
  done <<< "${buildable}"
  epic="$(plannable_epic)"
  if [[ -n "${epic}" ]]; then echo "plan-epic ${epic}"; echo "the active epic ${epic} has no stories yet"; return; fi
  while IFS= read -r f; do
    slug=$(basename "${f}" .md)
    case "$(fm "${f}" status)" in
      agreed)
        if [[ $(awk '/^## Epics/{e=1;next} /^## /{e=0} e && /^[-*] /{n++} END{print n+0}' "${f}") -eq 0 ]]; then
          echo "plan-hld ${slug}"; echo "the agreed HLD ${slug} has no epics yet"; return
        fi ;;
    esac
  done < <(board hld)
  while IFS= read -r f; do
    is_escalated "${f}" || continue
    slug=$(basename "${f}" .md); when="$(reset_at "${slug}")"; held="$(get_fm "${f}" held_for)"
    echo "escalated ${slug}"
    if [[ -n "${held}" ]]; then
      echo "${slug} is held (${held}): its builder stopped on its goal, which counts nothing; lift the hold with swarm.sh reset ${slug} <reason> to build it again, or swarm.sh drop ${slug} <reason>, then tell the user why"
    elif [[ -n "${when}" ]] && impossible_block "${f}"; then
      echo "${slug}'s builder called its Done when impossible after its one reset (${when}): drop it with swarm.sh drop ${slug} <reason>, then tell the user why"
    elif impossible_block "${f}"; then
      echo "${slug}'s builder called its Done when impossible: re-scope it and run swarm.sh reset ${slug} <reason>, or swarm.sh drop ${slug} <reason>, then tell the user why"
    elif [[ -n "${when}" ]]; then
      echo "${slug} failed on Fable again after its one reset (${when}): drop it with swarm.sh drop ${slug} <reason>, then tell the user why"
    else
      echo "${slug} failed on Fable: re-scope it and run swarm.sh reset ${slug} <reason>, or swarm.sh drop ${slug} <reason>, then tell the user why"
    fi
    return
  done < <(board stories)
  read -r n tag base <<< "$(release_due)"
  if [[ -n "${n}" ]]; then
    echo "release"; echo "origin/${base} has ${n} commit(s) since ${tag} that change files outside the board: cut a release"; return
  fi
  waiting="$(waiting_on_user)"
  if [[ -n "${waiting}" ]]; then
    echo "gate"; echo "only you can move the board now:"; printf '%s\n' "${waiting}"; return
  fi
  echo "done"; echo "nothing is open; start the next epic with /epic <title>"
}

# plannable_epic — the first active epic with no stories whose depends_on holds nothing up
# (epic_holding_deps), or nothing. A split epic (status: split) is never planned: its child epics are.
plannable_epic() {
  local f held
  while IFS= read -r f; do
    held="$(epic_holding_deps "${f}")" || continue
    [[ -z "${held}" ]] || continue
    basename "${f}" .md; return
  done < <(board epics)
}

# epic_holding_deps <epic file> — fails unless it is an active epic with no stories (the epics
# planning waits for); else prints its depends_on slugs that still hold its planning up (dep_holds),
# space-separated, none when it can be planned. Its deps are read only once it has no stories.
epic_holding_deps() {
  local b held=""
  [[ "$(fm "$1" status)" == active ]] && ! epic_has_stories "$(basename "$1" .md)" || return 1
  for b in $(story_deps "$1"); do if dep_holds "${b}"; then held+=" ${b}"; fi; done
  printf '%s' "${held# }"
}

# dep_holds <slug> — true while an epic's depends_on slug holds up its planning: an open story, or an
# open epic with no stories or with one not yet in review. Stories are scoped against the code the
# dependency builds, and code in review is code that exists.
dep_holds() {
  local f n=0
  open_item "${BOARD}/stories/$1.md" && return 0
  open_item "${BOARD}/epics/$1.md" || return 1
  while IFS= read -r f; do
    [[ "$(fm "${f}" epic)" == "$1" ]] || continue
    case "$(fm "${f}" status)" in review) n=1 ;; done) ;; *) return 0 ;; esac
  done < <(board stories)
  [[ ${n} -eq 0 ]]
}

# release_due — "<commits> v<version> <base>" when the local origin/HEAD names <base>, origin/<base>
# has .claude-plugin/plugin.json, the tag v<its version> exists here and is on origin/<base>, and
# commits since it change a file outside the board (when the board is in the repo); else nothing.
# Local refs only: reconcile has just pulled.
release_due() {
  local base version ex="" n
  base="$(git -C "${PROJECT_DIR}" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" || return 0
  base="${base#origin/}"
  version="$(git -C "${PROJECT_DIR}" show "origin/${base}:.claude-plugin/plugin.json" 2>/dev/null | plugin_version 2>/dev/null)" || return 0
  git -C "${PROJECT_DIR}" merge-base --is-ancestor "refs/tags/v${version}" "origin/${base}" 2>/dev/null || return 0
  [[ ${BOARD_IN_REPO} != 1 ]] || ex=":(exclude)${BOARD#"${PROJECT_DIR}"/}"
  n="$(git -C "${PROJECT_DIR}" rev-list --count "v${version}..origin/${base}" -- . ${ex:+"${ex}"})" || return 0
  [[ ${n} -eq 0 ]] || echo "${n} v${version} ${base}"
}

# is_escalated <story-file> — true for a story lead_block handed on: ready, kind: lead, with
# escalated_from:. It is the lead's to decide (next's escalated step), never the user's, impossible
# ones (impossible_block) included.
is_escalated() { [[ "$(fm "$1" status)" == ready && "$(fm "$1" kind)" == lead && -n "$(get_fm "$1" escalated_from)" ]]; }

# costs_money <item-file> — true when a story's costs: (costs_value) is money, or a value nothing here
# knows: merging its PR can spend money, so with merge = agent only the user merges it. costs: is a
# story's key; an epic's is ignored.
costs_money() {
  [[ "$1" == "${BOARD}/stories/"* ]] || return 1
  case "$(costs_value "$1")" in ""|none) return 1 ;; esac
}

# costs_value <story-file> — its costs: from the front matter, with the indented or "- " lines of a
# block list under it (blank and comment lines skipped), lowercased, with each line's # comment,
# quotes, brackets, commas, dashes and spaces gone (costs: [Money] and costs: then "  - money" are
# money): money, none, empty, or a value nothing here knows (unreadable for a file it cannot read),
# which costs_money holds (fails closed).
costs_value() {
  local v
  v="$(awk '/^---$/ && ++n == 2 { exit }
    n != 1 { next }
    on && /^[[:space:]]*(#.*)?$/ { next }
    on && /^([[:space:]]|-)/ { sub(/#.*/, ""); v = v $0; next }
    { on = 0 }
    !seen && index($0, "costs:") == 1 { seen = on = 1; v = substr($0, 7); sub(/#.*/, "", v) }
    END { print v }' "$1")" || { echo unreadable; return 0; }
  v="${v//[][[:space:]\"\',-]/}"
  tr '[:upper:]' '[:lower:]' <<< "${v}"
}

# pr_held <pr-url> — why the PR waits for the user's merge, or nothing: money_walk over the stories
# whose prs: lists it (pr_stories), or, when a story cannot be read, that (fails closed).
pr_held() {
  local s
  s="$(pr_stories "$1")" || { echo "$1 (a story on the board cannot be read, so whether it costs money is unknown)"; return 0; }
  money_walk "${s}"
}

# pr_stories <pr-url> — the slugs of the stories whose prs: (get_fm: their state file over their
# front matter; split on spaces and commas) lists the PR in any spelling: owner and repo in any case,
# the number with leading zeros. Fails when a story or its state file cannot be read.
pr_stories() {
  local f v rows=""
  while IFS= read -r f; do
    v="$(get_fm "${f}" prs)" || return 1
    rows+="$(basename "${f}" .md) ${v}"$'\n'
  done < <(board stories)
  awk -v k="$1" 'function canon(u) { u = tolower(u); gsub(/[][,"\047]/, "", u); sub(/\/pull\/0+/, "/pull/", u); return u }
    BEGIN { k = canon(k) }
    { for (j = 2; j <= NF; j++) { m = split($j, u, ","); for (i = 1; i <= m; i++) if (canon(u[i]) == k) { print $1; next } } }' <<< "${rows}"
}

# money_walk <slugs> — why their PRs wait for the user's merge, or nothing: the first of these stories,
# or of the open stories they depend on at any depth (a stacked PR carries its parents' commits), whose
# costs: holds its merge (costs_money). <slugs> is one string, split on spaces and newlines.
money_walk() {
  local todo=" ${1//$'\n'/ }" seen=" " s p f
  while [[ -n "${todo// /}" ]]; do
    todo="${todo# }"; s="${todo%% *}"; todo="${todo#"${s}"}"
    f="${BOARD}/stories/${s}.md"
    [[ -n "${s}" && "${seen}" != *" ${s} "* && -f "${f}" ]] || continue
    seen+="${s} "
    if costs_money "${f}"; then
      if [[ "$(costs_value "${f}")" == money ]]; then echo "${s} costs money"
      else echo "${s} has costs: $(costs_value "${f}"), not money or none"; fi
      return 0
    fi
    for p in $(open_parents "${f}"); do todo+=" ${p}"; done
  done
}

# costs_tag <item-file> — " (costs money)" when a PR the item lists waits for the user's merge (pr_held).
costs_tag() {
  local u
  for u in $(fm "$1" prs); do
    [[ -z "$(pr_held "${u}")" ]] || { printf ' (costs money)'; return 0; }
  done
}

# impossible_block <story-file> — true when the story's lead block (escalated_file) is impossible_story's.
impossible_block() { grep -q '^\*\*Impossible\.\*\*' "$(escalated_file "$(basename "$1" .md)")" 2>/dev/null; }

# waiting_on_user — one line per board item only the user can move: lead stories (not an escalated
# one, which is the lead's), blocked and later items, draft epics, and PRs awaiting the user's merge. Shared by
# next_step's gate, status and dash.
waiting_on_user() {
  local f kind slug waiting=""
  while IFS= read -r f; do
    kind=$(fm "${f}" kind); slug=$(basename "${f}" .md)
    case "$(fm "${f}" status)" in
      ready) agent_kind "${kind}" || is_escalated "${f}" || waiting+="  ${kind}: ${slug}"$'\n' ;;
      blocked) waiting+="  blocked: ${slug} ($(blocked_why "${f}"))"$'\n' ;;
      later) waiting+="  later story: ${slug}"$'\n' ;;
      review) waiting+="  awaiting your merge$(costs_tag "${f}"): ${slug} $(fm "${f}" prs)"$'\n' ;;
    esac
  done < <(board stories)
  while IFS= read -r f; do
    case "$(fm "${f}" status)" in
      later) waiting+="  later epic: $(basename "${f}" .md)"$'\n' ;;
      draft) waiting+="  draft epic: $(basename "${f}" .md), run /epic $(basename "${f}" .md)"$'\n' ;;
      review) waiting+="  awaiting your merge$(costs_tag "${f}"): epic $(basename "${f}" .md) $(fm "${f}" prs)"$'\n' ;;
    esac
  done < <(board epics)
  printf '%s' "${waiting%$'\n'}"
}

# open_item <file> — true while a board item is still open: its file exists and is not status: done,
# and, for an epic /plan-epic split into child epics (status: split), one of them is still on the board.
open_item() {
  [[ -f "$1" ]] || return 1
  case "$(fm "$1" status)" in
    done) return 1 ;;
    split) has_child_epics "$(basename "$1" .md)" ;;
  esac
}

# has_child_epics <epic> — true while an epic on the board, not status: done, names <epic> as the
# parent: in its front matter (a trailing # comment and trailing whitespace gone).
has_child_epics() {
  local f v
  while IFS= read -r f; do
    v="$(get_fm "${f}" parent)"; v="${v%%#*}"; v="${v%"${v##*[![:space:]]}"}"
    [[ "${v}" == "$1" && "$(fm "${f}" status)" != "done" ]] && return 0
  done < <(board epics)
  return 1
}

# story_deps <story> — the depends_on slugs in its front matter, space-separated, YAML brackets,
# quotes, a trailing # comment and trailing whitespace (a CR too) gone.
story_deps() {
  local v
  v="$(get_fm "$1" depends_on)"; v="${v%%#*}"; v="${v%"${v##*[![:space:]]}"}"
  v="${v#\[}"; v="${v%\]}"; v="${v//,/ }"; v="${v//\"/}"
  printf '%s' "${v//\'/}"
}

# open_deps <slugs> — the slugs (story_deps') still open: a story or epic on the board and not done,
# or not a plain slug (a hand step such as "operator:planted-leak-proof" is cleared by hand, never by
# a merge).
open_deps() {
  local b open=""
  for b in $1; do
    if open_item "${BOARD}/stories/${b}.md" || open_item "${BOARD}/epics/${b}.md" || [[ ! "${b}" =~ ^[a-z0-9-]+$ ]]; then
      open+=" ${b}"
    fi
  done
  printf '%s' "${open# }"
}

# blocked_why <story> — why a blocked story waits: its open depends_on slugs, or that none are left.
blocked_why() {
  local deps open
  deps="$(story_deps "$1")"; open="$(open_deps "${deps}")"
  if [[ -n "${open}" ]]; then echo "by ${open}"
  elif [[ -n "${deps// /}" ]]; then echo "its depends_on is finished: swarm.sh unblock readies it"
  else echo "by hand: no depends_on"
  fi
}

# build_exists <repo-dir> <slug> — true while a story's build is there: its worktree, or story/<slug>.
build_exists() { [[ -e "$(worktree_for "$1" "$2")" ]] || git -C "$1" show-ref -q --verify "refs/heads/story/$2"; }

# story_base <story> — the base its repo's stories start from and merge into (base_for), or <base>
# when that cannot be told.
story_base() {
  local src b
  if src="$(repo_dir "$(fm "$1" repo)")" && b="$(base_for "${src}" 2>/dev/null)"; then echo "${b}"; else echo "<base>"; fi
}

# open_parents <story> — its depends_on slugs that are stories still on the board and not done: the
# parents a stacked story starts on, and waits for before review.
open_parents() {
  local p out=""
  for p in $(story_deps "$1"); do
    if [[ "${p}" =~ ^[a-z0-9-]+$ ]] && open_item "${BOARD}/stories/${p}.md"; then out+=" ${p}"; fi
  done
  printf '%s' "${out# }"
}

# open_pr <repo-dir> <slug> — the URL of the open PR on story/<slug> in the repo's origin; fails when
# there is none or gh cannot tell.
open_pr() {
  local url pr
  url="$(git -C "$1" remote get-url origin 2>/dev/null)" || return 1
  pr="$(gh pr list -R "${url}" --head "story/$2" --state open --json url --jq '.[0].url // empty' </dev/null 2>/dev/null)" || return 1
  [[ -n "${pr}" ]] && echo "${pr}"
}

# unblock — a finished story is deleted or marked done, so a blocked story whose every depends_on
# slug is finished, and names no hand step, is ready. So is one stacked_on its open ones; one that
# only an old build keeps from it is printed as not stacked. A child review held keeps its worktree
# and held_by:, and its line says to merge the base in and review it again; with its worktree gone
# it is readied plainly, without held_by: or the prs: line the hold kept, to be built fresh. An old
# blocked_by line stays; nothing reads it. Prints each story it flips.
unblock() {
  local story slug deps open on why src rc drop
  while IFS= read -r story; do
    [[ "$(fm "${story}" status)" == blocked ]] || continue
    drop=()
    slug="$(basename "${story}" .md)"
    deps=$(story_deps "${story}")
    [[ -n "${deps// /}" ]] || continue   # blocked for a reason no merge clears
    open="$(open_deps "${deps}")"; why=""
    if [[ -n "${open}" ]]; then
      rc=0; on="$(stacked_on "${story}" "${open}")" || rc=$?
      [[ ${rc} -ne 2 ]] || echo "not stacked: ${slug} (its worktree or story/${slug} is already there, so it cannot start on ${open}; remove them, or let it wait until they merge)"
      [[ ${rc} -eq 0 ]] || continue
      why="stacked on ${on}"
    elif [[ -n "$(get_fm "${story}" held_by)" ]]; then
      if src="$(repo_dir "$(fm "${story}" repo)")" && [[ -d "$(worktree_for "${src}" "${slug}")" ]]; then
        why="held: merge origin/$(story_base "${story}"), review again"
      else
        drop=(held_by "" prs "")
      fi
    fi
    state_set "${story}" ${drop[@]+"${drop[@]}"} status ready
    record_event unblock "${slug}"
    echo "ready: ${slug}${why:+ (${why})}"
  done < <(board stories)
}

# delete_item <slug> — delete a story or epic's file where it is, and its state file (state_drop), so
# a later item with the slug starts with none: reconcile's, after its pull.
delete_item() { local f; f="$(item_file "$1")"; state_drop "${f}"; rm "${f}"; echo "deleted: ${f}"; }

# finish <slug> — take a merged story or epic off the board: delete its file (remove_item).
finish_item() { remove_item finish "$1"; }

# remove_item <verb> <slug> [<reason>] — finish's and drop's delete. A board outside the repo is
# edited in place; one in it through the board PR <verb>-<slug> (board_pr), never the main checkout,
# and a second run pushes to that PR. It prints the PR and the merge --board that lands it. A file
# that is not on origin's base (an unmerged board PR adds it) is refused, and a run that fails clears
# away the worktree and branch it started (unstart), so the next run starts clean.
remove_item() {
  local verb="$1" slug="$2" why="${3:-}" f rel name wt new="" body url title
  f="$(item_file "${slug}")"
  [[ ${BOARD_IN_REPO} == 1 ]] || { delete_item "${slug}"; return; }
  rel="${f#"${PROJECT_DIR}"/}"; name="${verb}-${slug}"
  wt="$(worktree_for "${PROJECT_DIR}" "_board-${name}")"
  if [[ ! -d "${wt}" ]]; then
    wt="$(board_pr start "${name}")" || die "${verb}: cannot start the board PR ${name}"
    new=1
    [[ -f "${wt}/${rel}" ]] || { unstart "${name}"; die "${verb}: ${rel} is not on origin/$(base_for "${PROJECT_DIR}") (is it in a board PR that has not merged?), so no board PR can delete it; merge that first"; }
  fi
  # An earlier run's worktree has the file deleted already; its PR is open, so a failure leaves it.
  [[ ! -e "${wt}/${rel}" ]] || git -C "${wt}" rm -q -- "${rel}" \
    || { [[ -z "${new}" ]] || unstart "${name}"; die "${verb}: git rm ${rel} failed in ${wt}"; }
  case "${verb}" in finish) title="Finish ${slug}" ;; *) title="Drop ${slug}: ${why}" ;; esac
  body="$(mktemp "${TMPDIR:-/tmp}/swarm-${verb}.XXXXXX")" || { [[ -z "${new}" ]] || unstart "${name}"; die "${verb}: mktemp failed"; }
  echo "Takes ${slug} off the board (\`swarm.sh ${verb} ${slug}${why:+ ${why}}\`)." > "${body}"
  url="$(board_pr open "${name}" "${title}" "${body}")" \
    || { rm -f "${body}"; [[ -z "${new}" ]] || unstart "${name}"; die "${verb}: cannot open the board PR ${name}"; }
  rm -f "${body}"
  echo "deleted: ${rel} in the board PR ${url}"
  echo "land it: swarm.sh merge --board ${url}"
}

# unstart <name> — undo a board_pr start whose PR never opened: its worktree, board/<name> here, and
# board/<name> on origin if open pushed it before gh failed. Best effort: it runs on the way to a die.
unstart() {
  local wt b="board/$1"; wt="$(worktree_for "${PROJECT_DIR}" "_board-$1")"
  git -C "${PROJECT_DIR}" worktree remove --force "${wt}" >/dev/null 2>&1 || true
  git -C "${PROJECT_DIR}" branch -q -D "${b}" >/dev/null 2>&1 || true
  if git -C "${PROJECT_DIR}" ls-remote --exit-code origin "refs/heads/${b}" >/dev/null 2>&1; then
    git -C "${PROJECT_DIR}" push -q origin --delete "${b}" >/dev/null 2>&1 || true
  fi
}

# reset_at <slug> — when the slug was reset (its first ok reset line in events.tsv), or nothing. A story
# is reset at most once.
reset_at() { awk -F'\t' -v s="$1" '$2 == "reset" && $3 == s && index($5, "ok") == 1 { print $1; exit }' "${EVENTS_LOG}" 2>/dev/null || true; }

# reset <slug> <reason> — put a story the lead re-scoped back in the build queue: drop attempts:,
# put kind back from escalated_from: (no kind: line for NO_KIND_LINE) while the story still says
# kind: lead, so a kind the lead re-scoped stays, drop escalated_from:, and delete escalate_story's
# block (escalated_file). A held story (held_for:, held_story) keeps attempts: and loses held_for:, and its reset is not
# counted as the one. A story with
# neither attempts: nor escalated_from: is refused, and so is a second reset (an ok reset line for the
# slug in events.tsv): at most one per story. main logs the reason as the outcome.
reset_story() {
  local slug="$1" f from when put kind held
  [[ -n "${slug}" ]] || die "reset: <slug> is missing: swarm.sh reset <slug> <reason>"
  [[ -n "${2//[[:space:]]/}" ]] || die "reset: <reason> is missing: swarm.sh reset ${slug} <reason>"
  [[ "${slug}" =~ ^[a-z0-9-]+$ ]] || die "reset: bad slug '${slug}'"
  f="${BOARD}/stories/${slug}.md"
  [[ -f "${f}" ]] || die "reset: no story ${f}"
  from="$(get_fm "${f}" escalated_from)"
  [[ -n "${from}$(get_fm "${f}" attempts)" ]] || die "reset: ${slug} has neither attempts: nor escalated_from:, so there is nothing to reset"
  held="$(get_fm "${f}" held_for)"
  when="$(reset_at "${slug}")"
  [[ -n "${held}" || -z "${when}" ]] || die "reset: ${slug} was reset already, at ${when} (events.tsv); a story is reset at most once, so drop it: swarm.sh drop ${slug} <reason>"
  put="${from}"; [[ "${from}" != "${NO_KIND_LINE}" ]] || put=""
  [[ -z "${from}" || "$(get_fm "${f}" kind)" != lead ]] || set_fm "${f}" kind "${put}"
  set_fm "${f}" escalated_from
  set_fm "${f}" held_for
  [[ -n "${held}" ]] || set_fm "${f}" attempts
  rm -f "$(escalated_file "${slug}")"
  kind="$(get_fm "${f}" kind)"
  if [[ -n "${held}" ]]; then echo "reset: ${slug} (kind: ${kind:-none, so code}; the ${held} hold is lifted, attempts: as it was)"; return; fi
  echo "reset: ${slug} (kind: ${kind:-none, so code}; no attempts:)"
}

# drop <slug> <reason> — the lead drops an escalated story (is_escalated): take it off the board as
# finish does (in a board PR, on a board in the repo), so next stops naming it once that lands. Any
# other story is refused. main logs the reason as the outcome.
drop_story() {
  local f="${BOARD}/stories/$1.md"
  [[ -n "$1" ]] || die "drop: <slug> is missing: swarm.sh drop <slug> <reason>"
  [[ -n "${2//[[:space:]]/}" ]] || die "drop: <reason> is missing: swarm.sh drop $1 <reason>"
  [[ "$1" =~ ^[a-z0-9-]+$ ]] || die "drop: bad slug '$1'"
  [[ -f "${f}" ]] || die "drop: no story ${f}"
  is_escalated "${f}" || die "drop: $1 is not an escalated story (ready, kind: lead, with escalated_from:), so it is not dropped"
  remove_item drop "$1" "$2"
  echo "dropped: $1"
}

# dialog <slug> <accepted|dismissed> — a conductor answered an escalate builder's Fable usage-credits
# consent (wait printed `waiting: dialog open`). It changes nothing: main logs `dialog <slug>` with
# `ok (<result>)` as the outcome, so each escalation step is in events.tsv with its time.
dialog_answered() {
  [[ "$1" =~ ^[a-z0-9-]+$ ]] || die "dialog: bad slug '$1': swarm.sh dialog <slug> <accepted|dismissed>"
  [[ -f "${BOARD}/stories/$1.md" ]] || die "dialog: no story ${BOARD}/stories/$1.md"
  [[ "$2" == accepted || "$2" == dismissed ]] || die "dialog: the result must be accepted or dismissed, not '$2'"
  echo "logged: dialog $1 $2"
}

# item_file <slug> — the story or epic file for <slug>.
item_file() {
  [[ "$1" =~ ^[a-z0-9-]+$ ]] || die "bad slug '$1'"
  if [[ -f "${BOARD}/stories/$1.md" ]]; then echo "${BOARD}/stories/$1.md"
  elif [[ -f "${BOARD}/epics/$1.md" ]]; then echo "${BOARD}/epics/$1.md"
  else die "no story or epic '$1' in ${BOARD}"; fi
}

# set_status <file> <status> [prs] — set the item's status, and its prs to [prs] or nothing, in one
# write (state_set).
set_status() { state_set "$1" status "$2" prs "${3:-}"; }

# SET_FM_KEYS: the front-matter keys swarm.sh writes (set_fm refuses any other): status and prs
# too, which review and unblock write, and held_by, which review writes on a stacked story it holds.
# They live in BOARD_STATE_DIR, never in a tracked file. reconcile puts an older swarm.sh's edit to
# them in a board file back as committed on an item whose PRs merged, and carries another board
# file's over its pull, so they never stop it.
SET_FM_KEYS="attempts kind escalated_from held_for held_by status prs"

# set_fm <file> <key> [value] — set <key> of a story or epic on the board to <value> (state_set);
# an empty <value> clears it. <key> must be one of SET_FM_KEYS.
set_fm() {
  [[ " ${SET_FM_KEYS} " == *" $2 "* ]] || die "set_fm: $2 is not in SET_FM_KEYS"
  state_set "$1" "$2" "${3:-}"
}

# state_set <file> <key> <value> [<key> <value>]... — in one write to the item's state file
# (state_path), never <file>: each <key>: <value> line, and <key>@base: with <file>'s front-matter
# value now, which state_value compares. A value <file> already has needs no line, so its lines go and
# the file's reads again; so do the lines of any key whose base <file> no longer has. A state file
# left with no line goes. It holds the item's lock (state_lock) from its read to its write, so two
# writers to one item keep each other's keys. Dies naming the state file when any step fails.
state_set() {
  local f="$1" s pairs="" rc=0
  state_path "${f}"; s="${STATE_PATH}"
  [[ -n "${s}" ]] || die "set_fm: ${f} is not a story or epic in ${BOARD}"
  shift
  while [[ $# -gt 0 ]]; do pairs+="$1"$'\t'"${2:-}"$'\n'; shift 2 || shift; done
  # Checked first, or the lock's mkdir would fail as if it were held.
  { mkdir -p "${s%/*}" && [[ -w "${s%/*}" ]]; } || die "board state: cannot write ${s}: ${s%/*} cannot be made or written"
  state_lock "${s}.lock"
  state_write "${f}" "${s}" "${pairs}" || rc=1
  rmdir "${s}.lock" || die "board state: cannot remove ${s}.lock; remove it by hand"
  [[ ${rc} -eq 0 ]] || die "board state: cannot write ${s}"
}

# STATE_LOCK_WAIT: seconds state_lock waits for an item's lock (SWARM_LOCK_WAIT).
STATE_LOCK_WAIT=10

# state_lock <dir> — take the lock <dir>: mkdir makes it or fails, so one writer holds it (macOS has no
# flock). It tries every 0.1s, and dies naming it after STATE_LOCK_WAIT seconds.
# ponytail: a writer killed holding the lock leaves it; the next write dies, saying to remove it.
state_lock() {
  local i n=$(( ${SWARM_LOCK_WAIT:-${STATE_LOCK_WAIT}} * 10 ))
  for ((i = 0; i < n; i++)); do
    if mkdir "$1" 2>/dev/null; then return 0; fi
    sleep 0.1
  done
  die "board state: ${1%.lock} is locked (${1} is still there after ${SWARM_LOCK_WAIT:-${STATE_LOCK_WAIT}}s); if no swarm.sh is writing it, remove ${1} and run this again"
}

# state_write <file> <state-file> <pairs> — state_set's read and write, under its lock: <pairs> (lines
# of <key><tab><value>) over the state file, through a temp file of its own. Either step failing fails
# the write, with no temp file left.
state_write() {
  local in="$2" t
  [[ -f "$2" ]] || in=/dev/null
  t="$(mktemp "$2.XXXXXX")" || return 1
  if ! { SWARM_SET="$3" awk 'function val(l, n) { l = substr(l, n + 1); sub(/^ +/, "", l); return l }
    function put(k, v) { print k ":" (v == "" ? "" : " " v) }
    BEGIN { n = split(ENVIRON["SWARM_SET"], L, "\n")
      for (i = 1; i <= n; i++) if ((p = index(L[i], "\t")) > 0) { k = substr(L[i], 1, p - 1); set[k] = substr(L[i], p + 1); order[++o] = k } }
    FILENAME == ARGV[1] { if ($0 == "---") { m++; next }
      if (m == 1 && (p = index($0, ":")) > 1 && !((k = substr($0, 1, p - 1)) in fv)) fv[k] = val($0, p)
      next }
    (p = index($0, ":")) > 1 { k = substr($0, 1, p - 1)
      if (k ~ /@base$/) { k = substr(k, 1, length(k) - 5); if (!(k in b)) b[k] = val($0, p) }
      else if (!(k in sv)) { sv[k] = val($0, p); keep[++c] = k } }
    END { for (i = 1; i <= c; i++) { k = keep[i]
        if (k in set || (k in b && b[k] != fv[k])) continue
        put(k, sv[k]); if (k in b) put(k "@base", b[k]) }
      for (i = 1; i <= o; i++) { k = order[i]; if (set[k] != fv[k]) { put(k, set[k]); put(k "@base", fv[k]) } } }' "$1" "${in}" > "${t}" && mv "${t}" "$2"; }; then
    rm -f "${t}"; return 1
  fi
  [[ -s "$2" ]] || rm -f "$2"
}

# set_file_fm <file> <key> [value] — in <file>'s own front matter, set <key>'s line to <value>, adding
# it at the end when there is none, or drop it when <value> is empty: only to put back what an older
# swarm.sh wrote there, over a pull.
set_file_fm() {
  awk -v k="$2" -v v="${3:-}" '
    /^---$/ && ++n == 2 && !d && v != "" { print k ": " v }
    n == 1 && index($0, k ":") == 1 { if (!d && v != "") print k ": " v; d = 1; next }
    { print }' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
}

# get_fm <file> <key> — <key>'s value in the item's state file (state_value), else in <file>'s front
# matter alone (fm takes the first line for <key> anywhere, so a story's body could answer). <file>
# may be - for stdin, which is read as it is.
get_fm() {
  state_value "$1" "$2" || awk -v k="$2" '/^---$/ && ++n == 2 { exit }
    n == 1 && index($0, k ":") == 1 { v = substr($0, length(k) + 2); sub(/^ +/, "", v); print v; exit }' "$1"
}

# review <slug> <pr-url>... — the item's PRs are green and reviewed and wait on a human merge. A story
# whose depends_on parents are still open is held instead: back to blocked with held_by: <parents> and
# its prs: line, its builder, worktree and branch kept, so no merge reaches a child before its parents.
mark_review() {
  local f url held
  f="$(item_file "${1:?slug}")"; shift
  [[ $# -gt 0 ]] || die "review: name the PR URLs"
  for url in "$@"; do
    [[ "${url}" =~ ^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/pull/[0-9]+$ ]] || die "review: not a PR URL: ${url}"
  done
  [[ "${f}" != "${BOARD}/stories/"* ]] || held="$(open_parents "${f}")"
  if [[ -n "${held:-}" ]]; then
    state_set "${f}" status blocked prs "$*" held_by "${held}"
    # A parent that costs money waits on the user's merge (money_walk), maybe for days.
    [[ -z "$(money_walk "${held}")" ]] || held+=" (costs money)"
    die "held: $(basename "${f}" .md) waits for ${held} to merge; once it has, act on the Stacked line swarm.sh status prints for it, then review it again"
  fi
  state_set "${f}" status review prs "$*" held_by ""
  echo "review: $(basename "${f}" .md) $*"
}

# builder_state <slug> — open when this project's builder for <slug> is open in herdr, none when it is
# not, unknown when herdr cannot list its agents. Outside herdr (HERDR_ENV unset) it is none, and herdr
# is never called.
builder_state() {
  local agents
  [[ "${HERDR_ENV:-}" == 1 ]] || { echo none; return; }
  # One list, read as agent_field reads it: a pane this project opened, under the builder's name.
  agents="$(herdr agent list 2>/dev/null)" \
    && SWARM_NAME="$(agent_name "$1")" SWARM_PANES="$(own_panes)" json "'open' if any(a.get('name') == e['SWARM_NAME'] and a.get('pane_id') in e['SWARM_PANES'].split() for a in d['result']['agents']) else 'none'" <<< "${agents}" 2>/dev/null \
    || echo unknown
}

# reconcile — for each item in review: finish it once every PR it lists has merged; send it back to
# ready, saying which, if any closed without merging; otherwise leave it waiting. A story's build is
# cleared (clear_build) before the pull, while its file still names its repo: always once it merged,
# after closing its builder if one is open (still in review, so close counts nothing), and saying so
# when herdr cannot tell whether one is; after a
# closed PR only when no builder is open (one may be fixing it; so may one herdr cannot list), so the
# story can be built again. With no item merged, it still pulls the main checkout when that is behind
# its upstream (a PR merged with no review item), and dies as a failed pull below does; a failed fetch
# is noted on stderr and is not a failure. No pull is made, merged items or not, while a PR in review
# cannot be read: said on stderr, naming it.
reconcile() {
  local f slug url state closed waiting urls builder unread="" merged=() merged_files=()
  while IFS= read -r f; do
    [[ "$(fm "${f}" status)" == review ]] || continue
    slug="$(basename "${f}" .md)"
    read -r -a urls <<< "$(fm "${f}" prs)"
    if [[ ${#urls[@]} -eq 0 ]]; then echo "in review with no prs: line: ${slug}"; continue; fi
    closed=""; waiting=0
    for url in "${urls[@]}"; do
      if ! state="$(gh pr view "${url}" --json state | json "d['state']")"; then
        echo "cannot read ${url}; ${slug} stays in review"; waiting=1; unread+="${unread:+, }${url} (${slug})"; continue
      fi
      case "${state}" in
        MERGED) ;;
        CLOSED) closed+=" ${url}" ;;
        *) waiting=1 ;;
      esac
    done
    if [[ -n "${closed}" ]]; then
      if [[ "${f}" == "${BOARD}/stories/"* ]]; then
        case "$(builder_state "${slug}")" in
          none) clear_build "${slug}" "the PR of ${slug} closed unmerged" "[]" </dev/null ;;
          open) echo "build kept: ${slug}'s builder is still open, so its worktree and story/${slug} stay" ;;
          *) echo "build kept: ${slug}'s builder may be open (herdr cannot list its agents), so its worktree and story/${slug} stay" ;;
        esac
      fi
      set_status "${f}" ready
      record_event reconcile "${slug}" "ok (reopened)"
      echo "back to ready: ${slug} (closed without merging:${closed})"
    elif [[ ${waiting} -eq 0 ]]; then
      if [[ "${f}" == "${BOARD}/stories/"* ]]; then
        builder="$(builder_state "${slug}")"
        [[ "${builder}" != open ]] || close_agent "${slug}" </dev/null   # stdin is this loop's list
        clear_build "${slug}" "the PR of ${slug} merged" "[]" </dev/null
        [[ "${builder}" != unknown ]] \
          || echo "build cleared: ${slug}'s builder may still be open (herdr cannot list its agents); close its pane with swarm.sh close ${slug}"
      fi
      merged+=("${slug}"); merged_files+=("${f}")
    fi
  done < <(board stories; board epics)
  # A pull is due after an item merged when there is an upstream, and otherwise when the checkout is
  # behind it (a PR merged with no review item: a board PR, a one-off). It is held after an unread PR:
  # if that merged, the pull would take its file before its build is cleared.
  local due=1 held=0
  if [[ ${#merged[@]} -gt 0 ]]; then has_upstream || due=0; else behind_upstream || due=0; fi
  if [[ ${due} == 1 && -n "${unread}" ]]; then
    echo "reconcile: not pulling ${PROJECT_DIR}: gh cannot read ${unread}; fix that, then run reconcile again" >&2
    due=0; held=1
  fi
  if [[ ${#merged[@]} -eq 0 ]]; then
    [[ ${due} == 0 ]] || pull_board_repo \
      || die "reconcile: cannot pull ${PROJECT_DIR}: ${PULL_WHY}; pull it by hand, then run reconcile again"
    return 0
  fi
  local i k committed saved=()
  if [[ ${BOARD_IN_REPO} == 1 && ${held} == 0 ]]; then
    # The board is in the project repo, and a merged PR may itself have taken the item off it or
    # changed it. An older swarm.sh's edits in the file (each SET_FM_KEYS key, such as the review
    # status or a retry's attempts:) would block that pull, so put them back as committed first, and
    # the whole file as it was if the pull fails. A hand edit is left alone, and still stops the pull.
    for slug in "${merged[@]}"; do
      f="$(item_file "${slug}")"; saved+=("$(cat "${f}"; echo .)")   # the dot keeps trailing newlines
      if committed="$(git -C "${PROJECT_DIR}" show "HEAD:${f#"${PROJECT_DIR}"/}" 2>/dev/null)"; then
        for k in ${SET_FM_KEYS}; do set_file_fm "${f}" "${k}" "$(get_fm - "${k}" <<< "${committed}")"; done
      fi
    done
    if [[ ${due} == 1 ]] && ! pull_board_repo; then
      for i in "${!merged[@]}"; do printf '%s' "${saved[i]%.}" > "$(item_file "${merged[i]}")"; done
      die "reconcile: cannot pull ${PROJECT_DIR}: ${PULL_WHY}; pull it by hand, then run reconcile again"
    fi
  fi
  for i in "${!merged[@]}"; do
    slug="${merged[i]}"; f="${merged_files[i]}"
    if [[ -f "${f}" && "$(fm "${f}" status)" != "done" ]]; then
      delete_item "${slug}"; record_event reconcile "${slug}" "ok (finished)"; continue
    fi
    # Its PR took it off the board or marked it done: its state goes too, or a later item with the
    # slug would read it.
    state_drop "${f}"
    record_event reconcile "${slug}" "ok (finished by its PR)"; echo "merged: ${slug}"
  done
}

# has_upstream — true when the board is in the project repo and its main checkout has an upstream.
has_upstream() { [[ ${BOARD_IN_REPO} == 1 ]] && git -C "${PROJECT_DIR}" rev-parse -q --verify '@{upstream}' >/dev/null; }

# behind_upstream — true when the main checkout has an upstream and, once fetched, is behind it. A
# failed fetch is false, said on stderr.
behind_upstream() {
  has_upstream || return 1
  git -C "${PROJECT_DIR}" fetch -q \
    || { echo "reconcile: cannot fetch ${PROJECT_DIR}, so it may be behind its upstream" >&2; return 1; }
  [[ -n "$(git -C "${PROJECT_DIR}" rev-list -1 'HEAD..@{upstream}')" ]]
}

# costs_diff — the path of the first file in a unified diff (stdin) whose added or removed lines include
# a costs: line, or a block-list line under one: the key above it in the hunk (blank and comment lines
# skipped), or, past the context, the one git names after the hunk's @@ (the last line above it that
# starts with a letter).
costs_diff() {
  awk '/^diff / { f = ""; key = ""; next }
    /^--- / { if ($2 != "/dev/null") { f = $2; sub(/^a\//, "", f) }; next }
    /^\+\+\+ / { if ($2 != "/dev/null") { f = $2; sub(/^b\//, "", f) }; next }
    /^@@/ { key = $0; if (!sub(/^@@[^@]*@@ ?/, "", key)) key = ""; key = tolower(key); next }
    /^[ +-]/ { l = substr($0, 2)
      if (l ~ /^[[:space:]]*(#.*)?$/) next
      if (l ~ /^([[:space:]]|-)/) { c = 1 } else { c = 0; key = tolower(l) }
      if ($0 ~ /^[+-]/ && (tolower(l) ~ /^costs:/ || (c && key ~ /^costs:/))) { print f; exit } }'
}
