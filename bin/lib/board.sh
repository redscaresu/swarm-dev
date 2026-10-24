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

# state_drop <item-file> — delete the item's state file and its lock (state_name), and a story's
# escalated block (escalated_file), so a later item with its slug starts with no state.
state_drop() {
  state_name "$1"
  [[ -z "${STATE_PATH}" ]] || rm -rf "${STATE_PATH}" "${STATE_PATH}.lock"
  [[ "${STATE_PATH}" != "${BOARD_STATE_DIR}/stories/"* ]] || rm -f "$(escalated_file "${STATE_PATH##*/}")"
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

# board <dir> — the item files in <board>/<dir>/, never the README. A reader that stops early (a loop
# that found its item) ends it quietly: with SIGPIPE ignored, as under a python parent, echo would
# print a write error, and dash would draw it in the frame.
board() {
  local f
  for f in "${BOARD}/$1"/*.md; do
    [[ -e "${f}" && "$(basename "${f}")" != README.md ]] || continue
    echo "${f}" 2>/dev/null || return 0
  done
  return 0
}

# waits_on_epic <kind> <after> <epic> — the after: rule on a story's front-matter values: kind lead,
# and after: (slug_list) names its own epic, alone or in a list. Such a story waits on the epic, so it
# does not count in it (the epic goes, and reads as done, without it); it stays on the board and is
# listed with the lead's stories. An after: that does not name its own epic is ignored. after_story
# reads a story file with it, dash_finished and epic_deleted_here a deleted one.
waits_on_epic() {
  local a list
  [[ -n "$3" && "$1" == lead ]] || return 1
  read -r -a list <<< "$(slug_list "$2")" || true
  for a in ${list[@]+"${list[@]}"}; do [[ "${a}" != "$3" ]] || return 0; done
  return 1
}

# after_story <story-file> — true for a story waits_on_epic holds for (kind and after: state-aware).
after_story() { waits_on_epic "$(get_fm "$1" kind)" "$(get_fm "$1" after)" "$(fm "$1" epic)"; }

# epic_stories <epic> — the story files that count in <epic>, any status: those naming it, but an
# after_story. Every test of an epic's stories reads them here, taken whole first (a loop that returns
# while reading it would close the pipe on it: a Broken pipe where SIGPIPE is ignored).
epic_stories() {
  local s
  while IFS= read -r s; do
    [[ "$(fm "${s}" epic)" == "$1" ]] && ! after_story "${s}" && echo "${s}"
  done < <(board stories)
  return 0
}

# epic_has_stories <epic> [<slug>] — true when a story counts in <epic> (epic_stories). With <slug>,
# one but <slug>: story_brief's test for the epic's last story.
epic_has_stories() {
  local s list
  list="$(epic_stories "$1")"
  while IFS= read -r s; do
    [[ -z "${s}" || "$(basename "${s}" .md)" == "${2:-}" ]] || return 0
  done <<< "${list}"
  return 1
}

# epic_planned <epic> — true once code stories were planned for <epic>: one counts in it on the board
# (epic_stories, done ones too), one of them finished and left the board (dash_finished, from its
# repo's history) or was deleted and not committed yet (epic_deleted_here, as finish does on a board
# outside the repo), or the board has no history to read (not in git, or no commit yet), which never
# reads as unplanned.
epic_planned() {
  [[ -n "$(epic_stories "$1")" ]] && return 0
  git -C "${BOARD}" rev-parse -q --verify HEAD >/dev/null 2>&1 || return 0
  dash_finished | awk -F'\t' -v e="$1" '$2 == e && $3 > 0 { f = 1 } END { exit !f }' && return 0
  epic_deleted_here "$1"
}

# epic_deleted_here <epic> — true when a story file that counted in <epic> (its committed front matter:
# epic, and not waits_on_epic) is deleted from the board but the deletion is not committed.
epic_deleted_here() {
  local p text gone
  gone="$(git -C "${BOARD}" diff --name-only --diff-filter=D HEAD -- stories/ 2>/dev/null)" || return 1
  while IFS= read -r p; do
    [[ "${p}" == *.md ]] || continue
    text="$(git -C "${BOARD}" show "HEAD:${p}" 2>/dev/null)" || continue
    [[ "$(get_fm - epic <<< "${text}")" == "$1" ]] || continue
    waits_on_epic "$(get_fm - kind <<< "${text}")" "$(get_fm - after <<< "${text}")" "$1" || return 0
  done <<< "${gone}"
  return 1
}

# epic_after_only <epic-file> — true when the epic is active, its open stories are all after_story
# ones, it has an after_story on the board (open or done: epic_has_after), and code stories were
# planned for it (epic_planned): it counts as done (open_item), so what depends on it goes ahead,
# and it is not planned again. A draft or later epic,
# or one whose only story ever was an after: one, never does.
epic_after_only() {
  local s slug list
  [[ "$(fm "$1" status)" == active ]] || return 1
  slug="$(basename "$1" .md)"
  list="$(epic_stories "${slug}")"
  while IFS= read -r s; do
    [[ -z "${s}" || "$(fm "${s}" status)" == "done" ]] || return 1
  done <<< "${list}"
  epic_has_after "${slug}" && epic_planned "${slug}"
}

# epic_has_after <epic> — true when an after_story of <epic> is on the board, any status. The stories
# are taken whole first, as epic_stories says.
epic_has_after() {
  local s list
  list="$(board stories)"
  while IFS= read -r s; do
    [[ -n "${s}" && "$(fm "${s}" epic)" == "$1" ]] && after_story "${s}" && return 0
  done <<< "${list}"
  return 1
}

# next_step — what the chain does next, read from the board alone, so a run can stop anywhere and
# pick up again. Prints "<action> <arg>" on the first line and why on the second. In order:
#   fix-main <slug>   merge found a base red on a commit it merged, no commit has shown it fixed
#                     since (main-green), and the one-off fix-main-<sha> it wrote is ready with no
#                     build (main_red, the newest such of any repo and base): start it before
#                     anything else, a conductor's wait included
#   collect <agent>   a conductor has written its report: read it, then close its tab
#   wait <agent>      a conductor exists and has not reported (idle between its own steps counts);
#                     why starts `auth:` when its login expired (wait then prints auth at once);
#                     otherwise an `also: lead <slug> blocks <slugs>` line follows (blocking_leads);
#                     next_report puts every working conductor's `queued:` lines before them
#   conduct <epic>    an active epic has a story an agent can build
#   resume <slug>     a one-off already started (its worktree exists): wait for it, then review
#   story <slug>      a ready story outside any epic
#   plan-epic <epic>  an active epic has no stories yet and nothing it depends on holds it up
#                     (plannable_epic), a child epic of a split one included; while a conductor
#                     works, this (then unblocked_epic's, below) comes before its wait
#   plan-hld <hld>    an agreed HLD with no planned: (hld_planned), no epic carrying its hld:
#                     (hld_epics), and no plan board PR's worktree
#                     (<repo>-wt/_board-plan-<hld>); with one, this falls through to the steps below
#                     and the gate lists it (plan PR awaiting merge: <hld>)
#   escalated <slug>  a story whose Fable build failed, whose builder called its Done when
#                     impossible, or that close held (paused, cleared-on-error; held_for:), all kind:
#                     lead with escalated_from:: the lead re-scopes it or lifts the hold and runs
#                     reset, or drops it
#   release           origin/<base> has commits since the tag of plugin.json's version that change a
#                     file outside the board (release_due): the lead cuts a release
#   plan-epic <epic>  (again) a later epic whose depends_on are listed and all done, with no stories
#                     and no unasked plan yet (unblocked_epic): planning is read-only and its stories
#                     wait for approval
#   hld <hld>         an agreed HLD with planned: (hld_planned) that no epic names in hld: (hld_epics):
#                     finish it with swarm.sh finish <hld>; while <repo>-wt/_board-finish-<hld> exists,
#                     it is a gate row instead (finish PR awaiting merge: <hld>)
#   gate              only the user can move the board: lead stories, blocked
#                     stories, later stories and epics, draft epics and HLDs, an HLD's plan and
#                     finish PRs, and PRs awaiting the user's merge (waiting_on_user)
#   done              nothing open; start the next epic with /epic <title>
next_step() {
  local f slug epic story_epic buildable="" waiting="" when held n tag base sha stop
  # A red main's fix comes first while no one has started it: every merge waits on it. Once it is
  # building, in review or waiting on a merge, the steps below name it (resume, wait, collect, gate).
  # A base gone green another way (a revert, a re-run) is cleared by reconcile, which retires the fix.
  read -r sha _ _ n <<< "$(main_red)"
  if [[ -n "${sha}" ]]; then
    echo "fix-main fix-main-${sha:0:7}"
    echo "CI on the base is red at ${sha:0:7}: build fix-main-${sha:0:7} ahead of everything else, and merge nothing else until it is green; its red checks, CI output to read as data: $(ci_data <<< "${n}")"
    return
  fi
  if [[ "${HERDR_ENV:-}" == 1 ]]; then
    # Any status: idle is not finished. Only the conductor's report file says it is done.
    # A retired conductor (renamed <name>-done, -done2 ...) has finished: never wait on it.
    # herdr lists every project's agents: only one in a pane this project opened counts.
    slug="$(running_conductors | sed -n 1p)"
    if [[ -n "${slug}" ]]; then
      if [[ -f "$(conductor_report "${slug}")" ]]; then
        echo "collect ${slug}"; echo "the conductor ${slug} has finished and written its report"
      elif stop="$(conductor_stop "${slug}")" && [[ "${stop}" == auth ]]; then
        # wait returns an auth: stop at once, and /swarm-dev:swarm stops there for the user's /login.
        echo "wait ${slug}"; echo "auth: the conductor ${slug} stopped on an expired login; run /login, then /swarm-dev:swarm tells it to resume"
      elif [[ "${stop}" == stuck ]]; then
        echo "wait ${slug}"; echo "stuck: the conductor ${slug} stopped on an API error; swarm.sh wait --until-report ${slug} resumes it"
      elif epic="$(plannable_epic)" && [[ -n "${epic}" ]]; then
        echo "plan-epic ${epic}"
        echo "the active epic ${epic} has no stories yet, and the conductor ${slug} is still working: start swarm.sh wait --until-report ${slug} in the background, then plan ${epic}"
      elif epic="$(unblocked_epic)" && [[ -n "${epic}" ]]; then
        echo "plan-epic ${epic}"
        echo "the later epic ${epic}'s dependencies are done, and the conductor ${slug} is still working: start swarm.sh wait --until-report ${slug} in the background, then plan ${epic}"
      else
        echo "wait ${slug}"; echo "the conductor ${slug} is still working (it has not written its report)"
        blocking_leads
      fi
      return
    fi
  fi
  # Stories an agent can build (buildable_story). "<epic> <slug>" per line.
  while IFS= read -r f; do
    buildable_story "${f}" || continue
    buildable+="$(fm "${f}" epic) $(basename "${f}" .md)"$'\n'
  done < <(board stories)
  while read -r story_epic slug; do
    [[ -n "${story_epic}" && -z "${slug}" ]] || continue
    one_off_started "${story_epic}" || continue
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
  # Neither HLD arm calls gh: dash runs next every frame. An open plan PR (its worktree) lets the
  # steps below go on, and is a gate row (waiting_on_user).
  while IFS= read -r f; do
    slug=$(basename "${f}" .md)
    [[ "$(hld_due "${f}")" == plan ]] || continue
    ! hld_pr_open "${slug}" plan || continue
    echo "plan-hld ${slug}"; echo "the agreed HLD ${slug} has not been planned into epics yet: run /plan-hld ${slug}"; return
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
  epic="$(unblocked_epic)"
  if [[ -n "${epic}" ]]; then
    echo "plan-epic ${epic}"; echo "the later epic ${epic}'s dependencies are done; planning is read-only, and its stories wait for approval"; return
  fi
  # A planned HLD with no epic left is finished; while its finish PR is open, it is a gate row.
  while IFS= read -r f; do
    slug=$(basename "${f}" .md)
    [[ "$(hld_due "${f}")" == finish ]] || continue
    ! hld_pr_open "${slug}" finish || continue
    echo "hld ${slug}"; echo "the planned HLD ${slug} has no epics left on the board: run swarm.sh finish ${slug}"; return
  done < <(board hld)
  waiting="$(waiting_on_user)"
  if [[ -n "${waiting}" ]]; then
    echo "gate"; echo "only you can move the board now:"; printf '%s\n' "${waiting}"; return
  fi
  echo "done"; echo "nothing is open; start the next epic with /epic <title>"
}

# running_conductors — this project's conductors in herdr, a name a line, in herdr's order: conduct-*
# agents not retired (renamed <name>-done, -done2 ...), in panes this project opened (herdr lists every
# project's agents).
running_conductors() {
  herdr agent list 2>/dev/null | SWARM_PANES="$(own_panes)" json "'\n'.join(a['name'] for a in d['result']['agents'] if a.get('name','').startswith('conduct-') and not a['name'].rstrip('0123456789').endswith('-done') and a.get('pane_id') in e.get('SWARM_PANES','').split())" 2>/dev/null || true
}

# conductor_stop <conductor> — auth when it stopped on an expired login (as in wait, only an idle
# session, or a busy one stopped on an API error, is auth), stuck when it stopped on an API error, else
# nothing.
conductor_stop() {
  local pane
  pane="$(agent_field "$1" pane_id)"
  if { [[ "$(session_state "$1")" == idle ]] || api_stopped "$1" "${pane}"; } && login_expired "$1"; then echo auth
  elif api_stopped "$1" "${pane}"; then echo stuck; fi
}

# conductors_queued — queued_lines for each working conductor (running_conductors with no report yet),
# each line ending in (<conductor>): the conductor the lead sends it to.
conductors_queued() {
  local c
  [[ "${HERDR_ENV:-}" == 1 ]] || return 0
  while IFS= read -r c; do
    [[ -n "${c}" && ! -f "$(conductor_report "${c}")" ]] || continue
    queued_lines "${c}" | sed "s/\$/ (${c})/"
  done <<< "$(running_conductors)"
}

# queued_lines <conductor> — queued_prs's lines for the PRs the conductor's watch covers (its epic's,
# or the backlog's), once per repo (watch_repos warn: one that cannot be resolved is warned of and
# skipped). Nothing when the scope cannot be read (watch_scope dies): next goes on.
queued_lines() {
  local e scope r
  e="$(conduct_epic "$1")"
  if [[ "${e}" == backlog ]]; then scope=(--backlog); else scope=(--epic "${e}"); fi
  (
    watch_scope "${scope[@]}"; watch_repos warn
    # Guarded: bash 3.2's set -u calls an empty array unbound, and no repo may have resolved.
    for r in ${WATCH_REPOS[@]+"${WATCH_REPOS[@]}"}; do queued_prs "${r}" "${WATCH_HEADS}"; done
  ) || true
}

# buildable_story <story file> — true for a story next_step builds: ready, of a kind an agent
# builds (agent_kind), with no epic or in an active one. dash counts the same ones.
buildable_story() {
  local epic
  [[ "$(fm "$1" status)" == ready ]] && agent_kind "$(fm "$1" kind)" || return 1
  epic="$(fm "$1" epic)"
  [[ -z "${epic}" || "$(fm "${BOARD}/epics/${epic}.md" status 2>/dev/null)" == active ]]
}

# one_off_started <slug> — true once a one-off's build has begun: it keeps status: ready until its PR
# merges, so an existing worktree means it has started (next_step's resume).
one_off_started() {
  local src
  src="$(repo_dir "$(fm "${BOARD}/stories/$1.md" repo)")" && [[ -d "$(worktree_for "${src}" "$1")" ]]
}

# idle_lines <step> — what next prints after its step <step>: capacity no step uses. An idle: line
# per blocked story whose depends_on story shares no file in touches with it (touches_rows.py
# --idle). And when the step leaves the builders idle (gate, done, escalated, release: no planning
# step, no conductor at work), no story is buildable (buildable_story) and there is an out-of-scope
# finding to offer (out_of_scope_findings), idle: "<project>" (quoted: a slug never starts with a
# quote, and a space stays in the name) with up to IDLE_CANDIDATES of them to file as a one-off.
# Later stories are the user's (waiting_on_user), never offered here.
IDLE_CANDIDATES=5
idle_lines() {
  local f found
  # Advisory: a failed check warns, and never fails next.
  SWARM_AGENT_KINDS="${AGENT_KINDS}" python3 "${SWARM_HOME}/bin/lib/touches_rows.py" "${BOARD}/stories" --idle "${PROJECT_DIR}" "${REPOS_DIR}" "${BOARD_STATE_DIR}/stories" \
    || echo "warning: the idle-dependency check failed (touches_rows.py --idle); next's step above stands" >&2
  case "$1" in gate|done|escalated|release) ;; *) return 0 ;; esac
  while IFS= read -r f; do
    if buildable_story "${f}"; then return 0; fi
  done < <(board stories)
  # sed, not head: head can exit before the writers finish, and the broken pipe fails under pipefail.
  found="$(out_of_scope_findings | sed -n "1,${IDLE_CANDIDATES}p")"
  [[ -n "${found}" ]] || return 0
  echo "idle: \"$(basename "${PROJECT_DIR}")\""
  printf '%s\n' "${found}" | sed 's/^/  out-of-scope finding: /'
}

# next_report — swarm.sh next: next_step's step (with conduct_ready's lines on a wait, then
# conductors_queued's, after its why), then idle_lines' for it. Both are worked out first
# and written in one go with SIGPIPE ignored and a write error dropped, so a reader that stops after
# the step (`next | head -1`, `| grep -q`) leaves next exiting 0 with no warning. next_step runs in
# this shell into a temp file, never in a $(...), which turns errexit off: a failure in it stops next.
next_report() {
  local tmp step idle queued rest started
  tmp="$(mktemp)" || die "next: cannot make a temp file"
  # shellcheck disable=SC2064 # the path is fixed now
  trap "rm -f '${tmp}'" EXIT
  next_step > "${tmp}"
  step="$(< "${tmp}")"
  # Every working conductor's queued: lines go after the why, here alone: dash and status read
  # next_step every frame, and these cost gh calls.
  queued="$(conductors_queued)"
  # Ready work no conductor holds gets one now, named after the wait's why (conduct_ready). A failure
  # keeps what it printed: its started: lines name conductors that run.
  if [[ "${step}" == "wait "* ]]; then
    started="$(conduct_ready)" || started+="${started:+$'\n'}warning: starting conductors for ready work failed (exit $?)"
    queued="${started}${started:+${queued:+$'\n'}}${queued}"
  fi
  if [[ -n "${queued}" ]]; then
    rest="$(sed -n '3,$p' <<< "${step}")"
    step="$(sed -n 1,2p <<< "${step}")"$'\n'"${queued}${rest:+$'\n'"${rest}"}"
  fi
  idle="$(idle_lines "${step%%[ $'\n']*}")"
  trap '' PIPE
  printf '%s\n' "${step}" ${idle:+"${idle}"} 2>/dev/null || true
}

# blocking_leads — "also: lead <slug> blocks <slugs>" for each ready story of a kind no agent builds
# (kind: lead, or a legacy or unknown kind: agent_kind fails) that a blocked
# story's depends_on names: the lead's own work that holds an agent's story up while a conductor works.
# An escalated story is left out (wait --lead hands it to the escalated step), and so is one with
# after: (it waits for its epic to finish, as epic_has_stories says). Only a blocked story an agent
# builds counts, and neither story may sit in an epic the user holds (epic_held).
blocking_leads() {
  local f b slug blocks
  while IFS= read -r f; do
    [[ "$(fm "${f}" status)" == ready && -z "$(get_fm "${f}" after)" ]] || continue
    if agent_kind "$(fm "${f}" kind)"; then continue; fi
    if is_escalated "${f}" || epic_held "${f}"; then continue; fi
    slug=$(basename "${f}" .md); blocks=""
    while IFS= read -r b; do
      [[ "$(fm "${b}" status)" == blocked && " $(story_deps "${b}") " == *" ${slug} "* ]] || continue
      agent_kind "$(fm "${b}" kind)" || continue
      if epic_held "${b}"; then continue; fi
      blocks+=" $(basename "${b}" .md)"
    done < <(board stories)
    if [[ -n "${blocks}" ]]; then echo "also: lead ${slug} blocks${blocks}"; fi
  done < <(board stories)
}

# epic_held <story-file> — true when the story's epic is later or draft: the user has not started it.
epic_held() {
  local e
  e="$(fm "$1" epic)"; [[ -n "${e}" ]] || return 1
  case "$(fm "${BOARD}/epics/${e}.md" status 2>/dev/null)" in later|draft) return 0 ;; esac
  return 1
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

# unblocked_epic — the first later epic, in board order, whose depends_on lists something and is all
# done or gone (open_deps), with no unasked_plan: (plan_unasked), no parent: and no stories, or
# nothing: once planned unasked it is never offered again, and the gate says what to do with it
# (waiting_on_user). An active epic is plannable_epic's. A later epic with no depends_on waits on nothing but
# the user, and a split later epic's later children wait for the user to start them, so both stay
# the user's. Board files only, no gh: dash runs it every frame.
unblocked_epic() {
  local f slug deps
  while IFS= read -r f; do
    [[ "$(fm "${f}" status)" == later && -z "$(fm "${f}" unasked_plan)" && -z "$(fm_list "${f}" parent)" ]] || continue
    deps="$(story_deps "${f}")"
    [[ -n "${deps// /}" && -z "$(open_deps "${deps}")" ]] || continue
    slug="$(basename "${f}" .md)"
    epic_has_stories "${slug}" && continue
    echo "${slug}"; return
  done < <(board epics)
}


# plan_unasked [--declined] <epic> — swarm.sh plan-unasked: the lead records, before it starts the
# /plan-epic next offered unasked, that the later epic has had its plan (unasked_plan: <date>, in board
# state), so next offers it no more and the gate says what to do with it; with --declined, that the
# user declined it (unasked_plan: declined <date>), which the gate says instead.
plan_unasked() {
  local v="" e="" a f usage="swarm.sh plan-unasked [--declined] <epic>"
  for a in "$@"; do
    case "${a}" in
      --declined) v="declined " ;;
      *) [[ -z "${e}" ]] || die "plan-unasked: one epic only: ${usage}"; e="${a}" ;;
    esac
  done
  f="${BOARD}/epics/${e}.md"
  [[ "${e}" =~ ^[a-z0-9-]+$ && -f "${f}" ]] || die "plan-unasked: no epic ${f}: ${usage}"
  [[ "$(fm "${f}" status)" == later ]] || die "plan-unasked: ${e} is not a later epic"
  set_fm "${f}" unasked_plan "${v}$(date +%F)"
  echo "plan-unasked: ${e}, ${v:-planned unasked }on $(date +%F)"
}


# epic_holding_deps <epic file> — fails unless it is an active epic with no stories (epic_has_stories;
# an after: story is none) that does not count as done (epic_after_only): the epics planning waits
# for; else prints its depends_on slugs that still hold its planning up (dep_holds),
# space-separated, none when it can be planned. Its deps are read only once it has no stories. A child
# epic's own parent: never holds it: the split parent is open for as long as the child is.
epic_holding_deps() {
  local b held="" parent
  [[ "$(fm "$1" status)" == active ]] && ! epic_has_stories "$(basename "$1" .md)" && ! epic_after_only "$1" || return 1
  parent="$(fm_list "$1" parent)"
  for b in $(story_deps "$1"); do
    [[ "${b}" != "${parent}" ]] && dep_holds "${b}" && held+=" ${b}"
  done
  printf '%s' "${held# }"
}

# dep_holds <slug> — true while an epic's depends_on slug holds up its planning: an open story, or an
# open epic with no stories or with one not yet in review. Stories are scoped against the code the
# dependency builds, and code in review is code that exists. Its stories are epic_stories.
dep_holds() {
  local f n=0 list
  open_item "${BOARD}/stories/$1.md" && return 0
  open_item "${BOARD}/epics/$1.md" || return 1
  list="$(epic_stories "$1")"
  while IFS= read -r f; do
    [[ -n "${f}" ]] || continue
    case "$(fm "${f}" status)" in review) n=1 ;; done) ;; *) return 0 ;; esac
  done <<< "${list}"
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

# GRANTS: the values an HLD's grants: may hold.
GRANTS="epics stories merge release"

# hld_grants <hld file> — the grants in its front matter's grants: (get_fm, as a slug_list), one per
# line; none for an absent line. Any other value, a [ with no ] on its line, or a YAML block list
# (after blank or comment lines too), dies with the file and line, as a bad config does.
hld_grants() {
  local g list n
  n="$(awk '/^---$/ && ++c == 2 { exit }
    c == 1 && !g && index($0, "grants:") == 1 { g = NR; v = substr($0, 8); sub(/#.*/, "", v)
      if (index(v, "[") && !index(v, "]")) { print g; exit }
      if (v ~ /[^[:space:]]/) exit
      next }
    g && /^[[:space:]]*(#.*)?$/ { next }
    g { if (/^[[:space:]]*-/) print g; exit }' "$1")"
  [[ -z "${n}" ]] || die "$1:${n}: grants must be a one-line [..] list"
  read -r -a list <<< "$(slug_list "$(get_fm "$1" grants)")" || true
  for g in ${list[@]+"${list[@]}"}; do
    [[ " ${GRANTS} " == *" ${g} "* ]] && { echo "${g}"; continue; }
    n="$(awk '/^---$/ && ++c == 2 { exit } c == 1 && index($0, "grants:") == 1 { print NR; exit }' "$1")"
    die "$1:${n}: grants must be epics, stories, merge or release"
  done
}

# item_hld <story or epic file> [epics dir] — the agreed HLD file in ${BOARD}/hld over it: a story's
# epic:, then each epic's parent:, up to the first epic with hld:, read in [epics dir] (${BOARD}/epics).
# A seen list ends a parent: cycle. Prints nothing (fails closed) on a missing epic, a missing HLD
# file, a draft or superseded HLD, a story with no epic, or a cycle.
item_hld() {
  local f="$1" e="${2:-${BOARD}/epics}" seen=" " next h
  [[ "${f%/*}" != */stories ]] || { next="$(slug_list "$(get_fm "${f}" epic)")"; f="${e}/${next}.md"; }
  while [[ "${next:-}" =~ ^[a-z0-9-]*$ && -f "${f}" && "${seen}" != *" ${f} "* ]]; do
    seen+="${f} "
    h="$(slug_list "$(get_fm "${f}" hld)")"
    if [[ -n "${h}" ]]; then
      [[ "${h}" =~ ^[A-Za-z0-9._-]+$ ]] || return 0
      h="${BOARD}/hld/${h}.md"
      [[ ! -f "${h}" || "$(get_fm "${h}" status)" != agreed ]] || echo "${h}"
      return 0
    fi
    next="$(slug_list "$(get_fm "${f}" parent)")"; f="${e}/${next}.md"
  done
}

# hld_epics <hld name> [-1] — the board's epic files whose front-matter hld: (get_fm, slug_list) is
# <hld name> exactly, with no .md, as item_hld reads it; with -1, only the first, for a test of presence.
hld_epics() {
  local f
  while IFS= read -r f; do
    [[ "$(slug_list "$(get_fm "${f}" hld)")" == "$1" ]] || continue
    echo "${f}"
    [[ "${2:-}" != -1 ]] || return 0
  done < <(board epics)
  return 0
}

# hld_planned <hld file> — true when its front matter's planned: (get_fm) holds a value once quotes,
# brackets and a trailing comment are gone (slug_list), which /plan-hld's board PR sets. Links under
# ## Epics decide nothing: one added by hand must not make it look planned.
hld_planned() { local v; v="$(fm_list "$1" planned)"; [[ -n "${v//[[:space:]]/}" ]]; }

# hld_due <hld file> — for an agreed HLD that no epic names (hld_epics): plan with no planned:
# (hld_planned), finish with it. Else nothing: an epic carrying its hld: means it was decomposed (an
# HLD planned through /epic before planned: existed too), and is not planned again.
hld_due() {
  [[ "$(get_fm "$1" status)" == agreed && -z "$(hld_epics "$(basename "$1" .md)" -1)" ]] || return 0
  if hld_planned "$1"; then echo finish; else echo plan; fi
}

# hld_pr_open <hld name> <plan|finish> — true while the HLD's plan or finish board PR's worktree
# (<repo>-wt/_board-<plan|finish>-<hld>) exists: a local directory test, no gh.
hld_pr_open() { [[ -e "$(worktree_for "${PROJECT_DIR}" "_board-$2-$1")" ]]; }

# one_hld — the HLD named on every line of stdin (item_hld's answers, an empty line for an item under
# none), or nothing when there is none, an empty line, or two.
one_hld() { local u; u="$(sort -u)"; [[ -z "${u}" || "${u}" == *$'\n'* ]] || echo "${u}"; }

# hld_body <hld file> — the HLD less its front matter's planned: lines and the lines under its
# ## Epics heading (to the next # or ## heading, or EOF): what the board PR that plans it leaves as it was.
hld_body() {
  awk '/^---$/ && n < 2 { n++ } n == 1 && index($0, "planned:") == 1 { next }
    n == 2 && /^##? / { e = ($0 == "## Epics"); print; next } !e' "$1"
}

# hld_plain <hld file> — true when nothing in the HLD's body hides from hld_body where a # or ## heading
# is: no code fence or HTML comment, no # or ## heading indented, quoted, followed by a tab or empty,
# and no setext heading (a line of = or - under a line of text).
hld_plain() {
  awk '/^---$/ && n < 2 { n++; next } n < 2 { next }
    /^ ? ? ?(```|~~~)/ || /<!--/ { bad = 1 }
    /^[ \t>]*##?([ \t]|$)/ && !/^##? / { bad = 1 }
    /^ ? ? ?(=+|-+)[ \t]*$/ && p ~ /[^ \t]/ { bad = 1 }
    { p = $0 } END { exit bad }' "$1"
}

# planned_lines <hld file> — its front matter's planned: lines, as they are.
planned_lines() { awk '/^---$/ && ++n == 2 { exit } n == 1 && index($0, "planned:") == 1' "$1"; }

# plan_head <hld file> <head copy> — true when <head copy> only plans <hld file>: one planned: line at
# most, the same as the board's when the board has one, nothing hld_plain refuses, and no change
# outside ## Epics (hld_body).
plan_head() {
  local b h
  b="$(planned_lines "$1")"; h="$(planned_lines "$2")"
  [[ "${h}" != *$'\n'* && ( -z "${b}" || "${b}" == "${h}" ) ]] || return 1
  hld_plain "$2" || return 1
  cmp -s <(hld_body "$1") <(hld_body "$2")
}

# plan_hld <files> <prefix> — the agreed HLD in ${BOARD}/hld that a board PR plans into epics, or a
# failure. <files> are the PR's, one per line, each under the board's <prefix>: one hld/<H>.md and at
# least one epics/*.md, and the HLD agreed and plain (hld_plain). It reads no gh; pr_hld then checks
# the head (each file there, the HLD's copy plan_head's) and reads each epic through item_hld, so
# one_hld still has to agree on H. The HLD's grants are the board's, so a PR cannot grant itself.
plan_hld() {
  local p h="" e=0 f
  while IFS= read -r p; do
    [[ "${p}" == "$2"* ]] || return 1   # loose-match: ok <prefix> is empty or ends in /
    p="${p#"$2"}"
    if [[ -z "${h}" && "${p}" =~ ^hld/([A-Za-z0-9._-]+)\.md$ ]]; then h="${BASH_REMATCH[1]}"
    elif [[ "${p}" =~ ^epics/[^/]+\.md$ ]]; then e=$((e + 1))
    else return 1; fi
  done <<< "$1"
  f="${BOARD}/hld/${h}.md"
  [[ -n "${h}" && ${e} -gt 0 && -f "${f}" && "$(get_fm "${f}" status)" == agreed ]] || return 1
  hld_plain "${f}" || return 1
  echo "${f}"
}

# pr_hld <pr-url> — the one agreed HLD over a PR (one_hld), or nothing: over the stories whose prs:
# lists it (pr_stories) and, for a PR in the project's repo, over the epics/*.md and stories/*.md it
# touches, each as the board has it (a file the PR deletes too) and as the PR's head has it, read in a
# copy of the board's epics with the head's over them; the HLDs always the board's. A PR that touches
# .claude/swarm/ (in any repo), or the board's hld/, is under none: only the user changes those. The
# one exception is the board PR that plans an HLD, under that HLD (plan_hld). A PR no story lists that
# touches any file but the board's epics and stories is under none too.
pr_hld() (
  local s url repo n own="" info="" head="" pre p q view="" err plan=""
  url="$(tr '[:upper:]' '[:lower:]' <<< "$1")"
  trap 'rm -rf "${view}"' EXIT
  s="$(pr_stories "${url}")" || die "grants: a story on the board cannot be read"
  # The board's path in the repo, with a trailing /; empty for a board at the repo's root.
  pre="${BOARD#"${PROJECT_DIR}"}"; pre="${pre#/}"; pre="${pre:+${pre}/}"
  # A URL pr_stories reads but this does not, or a board repo whose origin cannot be read, is under
  # none: the PR's files could not be checked.
  [[ "${url}" =~ ^https://github\.com/([a-z0-9._-]+/[a-z0-9._-]+)/pull/0*([0-9]+)$ ]] || return 0
  repo="${BASH_REMATCH[1]}"; n="${BASH_REMATCH[2]}"
  if [[ ${BOARD_IN_REPO} == 1 ]]; then
    p="$(git -C "${PROJECT_DIR}" remote get-url origin 2>/dev/null)" || return 0
    own="$(gh repo view "${p}" --json nameWithOwner 2>/dev/null | json "d['nameWithOwner'].lower()" 2>/dev/null)" || return 0
  fi
  # No story lists it and the board is not in its repo: nothing on the board is under it.
  [[ -n "${s}" || "${repo}" == "${own}" ]] || return 0
  info="$(gh pr view "${n}" --repo "${repo}" --json headRefOid,changedFiles | json "d['headRefOid'] + ' ' + str(d['changedFiles'])")" \
    || die "grants: gh cannot read ${url}"
  head="${info% *}"
  info="$(ci_gate files "${repo}" "${n}" "${info#* }")" || die "grants: cannot list every file ${url} changes: ${info}"
  [[ $'\n'"${info}" != *$'\n.claude/swarm/'* ]] || return 0
  if [[ "${repo}" != "${own}" ]]; then head=""   # the board is not in its repo, so none of its files is a board file
  # A PR that touches the board's hld/ is under none, but for the board PR that plans an HLD, whose
  # head can be read.
  elif [[ $'\n'"${info}" == *$'\n'"${pre}hld/"* ]]; then   # loose-match: ok a whole line's prefix, the board's hld/
    plan="$(plan_hld "${info}" "${pre}")" || return 0
    [[ -n "${head}" ]] || return 0
  fi
  view="$(mktemp -d)"; mkdir "${view}/epics" "${view}/stories" "${view}/hld"
  cp "${BOARD}/epics/"*.md "${view}/epics/" 2>/dev/null || true
  err="${view}/err"
  while [[ -n "${head}" ]] && IFS= read -r p; do
    [[ "${p}" == "${pre}"* ]] || continue   # loose-match: ok pre is empty or ends in /
    p="${p#"${pre}"}"
    [[ "${p}" =~ ^(epics|stories|hld)/[^/]+\.md$ ]] || continue
    # Quoted, so a # or ? in a name is read as itself; a 404 is then a file the head does not have.
    q="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "${pre}${p}")"
    if gh api -H "Accept: application/vnd.github.raw" "repos/${repo}/contents/${q}?ref=${head}" > "${view}/${p}" 2> "${err}"; then continue; fi
    grep -q 'HTTP 404' "${err}" || die "grants: gh cannot read ${pre}${p} at ${url}'s head: $(tail -1 "${err}")"
    [[ -z "${plan}" ]] || return 0   # the plan PR deletes its HLD or an epic: under none
    rm -f "${view}/${p}"
  done <<< "${info}"
  [[ -z "${plan}" ]] || plan_head "${plan}" "${view}/hld/${plan##*/}" || return 0
  {
    for p in ${s}; do printf '%s\n' "$(item_hld "${BOARD}/stories/${p}.md")"; done
    while [[ -n "${head}" ]] && IFS= read -r p; do
      [[ "${p}" != "${pre}hld/"* ]] || { echo "${plan}"; continue; }   # loose-match: ok the one HLD plan_hld passed
      [[ "${p}" == "${pre}"* && "${p#"${pre}"}" =~ ^(epics|stories)/[^/]+\.md$ ]] || { [[ -n "${s}" ]] || echo; continue; }   # loose-match: ok pre is empty or ends in /
      p="${p#"${pre}"}"
      [[ ! -f "${BOARD}/${p}" ]] || printf '%s\n' "$(item_hld "${BOARD}/${p}")"
      [[ ! -f "${view}/${p}" ]] || printf '%s\n' "$(item_hld "${view}/${p}" "${view}/epics")"
      [[ -f "${BOARD}/${p}" || -f "${view}/${p}" ]] || echo   # in neither: under none
    done <<< "${info}"
  } | one_hld
)

# grants <story | epic | PR URL> — swarm.sh grants: the agreed HLD over it (item_hld, or pr_hld for a
# PR) and its grants (hld_grants), one per line, or none. A name that is no story or epic but an HLD
# in ${BOARD}/hld is that HLD: an agreed one prints itself and its grants, any other none.
grants() {
  local h g
  [[ $# -eq 1 ]] || die "usage: swarm.sh grants <story | epic | PR URL>"
  if [[ "$1" == https://* ]]; then h="$(pr_hld "$1")" || exit 1
  # Keep this slug check and the story/epic lookups in step with item_file's.
  elif [[ "$1" =~ ^[a-z0-9-]+$ && ! -f "${BOARD}/stories/$1.md" && ! -f "${BOARD}/epics/$1.md" && -f "${BOARD}/hld/$1.md" ]]; then
    h="${BOARD}/hld/$1.md"   # a story or epic of the name wins; only then the HLD itself
    [[ "$(get_fm "${h}" status)" == agreed ]] || h=""
  else g="$(item_file "$1")" || exit 1; h="$(item_hld "${g}")"; fi
  [[ -n "${h}" ]] || { echo none; return 0; }
  g="$(hld_grants "${h}")" || exit 1
  printf '%s\n%s\n' "${h}" "${g:-none}"
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
# next_step's gate, status and dash. An HLD's open plan or finish PR (hld_pr_open) is one too.
waiting_on_user() {
  local f kind slug when waiting=""
  while IFS= read -r f; do
    kind=$(fm "${f}" kind); slug=$(basename "${f}" .md)
    case "$(fm "${f}" status)" in
      ready) agent_kind "${kind}" || is_escalated "${f}" || waiting+="  ${kind}: ${slug}"$'\n' ;;
      blocked) waiting+="  blocked: ${slug} ($(blocked_why "${f}"))"$'\n' ;;
      later) waiting+="  later story: ${slug}"$'\n' ;;
      # A story a close kept (its PR not reviewed) is not one to merge yet.
      review) if [[ -n "$(get_fm "${f}" kept)" ]]; then waiting+="  kept: ${slug} $(fm "${f}" prs) (not reviewed)"$'\n'
              else waiting+="  awaiting your merge$(costs_tag "${f}"): ${slug} $(fm "${f}" prs)"$'\n'; fi ;;
    esac
  done < <(board stories)
  while IFS= read -r f; do
    case "$(fm "${f}" status)" in
      later) when="$(fm "${f}" unasked_plan)"; slug=$(basename "${f}" .md)
        case "${when}" in
          declined*) when=" (its unasked plan was ${when})" ;;
          ?*) if epic_has_stories "${slug}"; then when=" (planned unasked on ${when}; set it active to start it)"
              else when=" (planned unasked on ${when}, no stories yet; run /plan-epic ${slug} again if that plan stopped)"; fi ;;
        esac
        waiting+="  later epic: ${slug}${when}"$'\n' ;;
      draft) waiting+="  draft epic: $(basename "${f}" .md), run /epic $(basename "${f}" .md)"$'\n' ;;
      review) waiting+="  awaiting your merge$(costs_tag "${f}"): epic $(basename "${f}" .md) $(fm "${f}" prs)"$'\n' ;;
    esac
  done < <(board epics)
  while IFS= read -r f; do
    slug=$(basename "${f}" .md)
    # The directory test first: hld_due reads every epic, and dash runs this several times a frame.
    if [[ "$(fm "${f}" status)" == draft ]]; then waiting+="  draft hld: ${slug}, run /hld ${slug}"$'\n'
    elif hld_pr_open "${slug}" plan && [[ "$(hld_due "${f}")" == plan ]]; then waiting+="  plan PR awaiting merge: ${slug}"$'\n'
    elif hld_pr_open "${slug}" finish && [[ "$(hld_due "${f}")" == finish ]]; then waiting+="  finish PR awaiting merge: ${slug}"$'\n'
    fi
  done < <(board hld)
  printf '%s' "${waiting%$'\n'}"
}

# open_item <file> [seen] — true while a board item is still open: its file exists and is not status:
# done, for an epic /plan-epic split into child epics (status: split), one of them is still open
# (has_child_epics; [seen] is the split epics already walked, so a parent: cycle ends), and it is not
# an active epic whose only open stories are after: lead stories (epic_after_only).
open_item() {
  [[ -f "$1" ]] || return 1
  case "$(fm "$1" status)" in
    done) return 1 ;;
    split) has_child_epics "$(basename "$1" .md)" "${2:-}"; return ;;
  esac
  [[ "$1" != "${BOARD}/epics/"* ]] || ! epic_after_only "$1"
}

# has_child_epics <epic> [seen] — true while an open epic on the board (open_item) names <epic> as the
# parent: in its front matter (fm_list). An epic is never its own child, and one in [seen] (space-
# separated slugs) is skipped, so epics that name each other as parent: count as having none.
has_child_epics() {
  local f slug seen="${2:-} $1"
  while IFS= read -r f; do
    slug="$(basename "${f}" .md)"
    [[ " ${seen} " != *" ${slug} "* && "$(fm_list "${f}" parent)" == "$1" ]] && open_item "${f}" "${seen}" && return 0
  done < <(board epics)
  return 1
}

# story_deps <story> — the depends_on slugs in its front matter (fm_list).
story_deps() { fm_list "$1" depends_on; }

# fm_list <file> <key> — <key>'s slugs in its front matter (slug_list).
fm_list() { slug_list "$(get_fm "$1" "$2")"; }

# slug_list <value> — a front-matter value's slugs, space-separated, YAML brackets, quotes, a
# trailing # comment and trailing whitespace (a CR too) gone.
slug_list() {
  local v="$1"
  v="${v%%#*}"; v="${v%"${v##*[![:space:]]}"}"
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

# unblock_startable <epic>|--backlog — unblock, then a startable: line per story of that epic (--backlog:
# with no epic) that next would build (board_ready: ready, its build not started), whether or not this
# unblock readied it: unblock never prints a story a board PR added already ready. It reads the board as
# reconcile last left it and never pulls: pulling is reconcile's. An epic whose file is gone has
# finished, so after unblock (its last merge may ready another epic's stories) nothing is startable. A
# line ends (stacked on <parents>) while depends_on has open stories, as story stacks it, and (its PR
# <url> was closed unmerged) when the story's last event is reconcile's reopen, for the lead.
unblock_startable() {
  local want="$1" slug e f open why
  unblock
  if [[ "${want}" == --backlog ]]; then want=-
  else [[ -f "${BOARD}/epics/${want}.md" ]] || return 0; fi
  while read -r slug e; do
    [[ "${e}" == "${want}" ]] || continue
    f="${BOARD}/stories/${slug}.md"; why=""
    open="$(open_deps "$(story_deps "${f}")")"
    [[ -z "${open}" ]] || why="stacked on ${open}"
    if [[ "$(last_event "${slug}")" == $'reconcile	ok (reopened)' ]]; then
      why="its PR$(fm "${f}" prs | sed 's/^./ &/') was closed unmerged"
    fi
    echo "startable: ${slug}${why:+ (${why})}"
  done < <(board_ready)
}

# last_event <slug> — the command and outcome of the last events.tsv line for <slug>, tab-separated.
last_event() { awk -F'\t' -v s="$1" '$3 == s { last = $2 "\t" $5 } END { print last }' "${EVENTS_LOG}" 2>/dev/null || true; }

# delete_item <file> — delete a story or epic's file where it is, and its state file (state_drop), so
# a later item with the slug starts with none: reconcile's, on a board outside the repo.
delete_item() { state_drop "$1"; rm "$1"; echo "deleted: $1"; }

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
  [[ ${BOARD_IN_REPO} == 1 ]] || { delete_item "${f}"; return; }
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
# too, which review and unblock write, held_by, which review writes on a stacked story it holds, and
# an epic's unasked_plan, which plan-unasked writes.
# They live in BOARD_STATE_DIR, never in a tracked file.
SET_FM_KEYS="attempts kind escalated_from held_for held_by kept status prs unasked_plan"

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

# state_lock <dir> — take the lock <dir>: mkdir(2) makes it or fails, so one writer holds it (macOS has
# no flock). It calls mkdir(2) through perl: uutils mkdir (ubuntu 26.04) lets two racing callers both
# succeed. It tries every 0.1s, and dies naming it after STATE_LOCK_WAIT seconds.
# ponytail: a writer killed holding the lock leaves it; the next write dies, saying to remove it.
state_lock() {
  local i n=$(( ${SWARM_LOCK_WAIT:-${STATE_LOCK_WAIT}} * 10 ))
  for ((i = 0; i < n; i++)); do
    if perl -e 'mkdir shift or exit 1' "$1"; then return 0; fi
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
  review_state "${f}" "" "$@"; held="${REVIEW_HELD}"
  if [[ -n "${held}" ]]; then
    # A parent that costs money waits on the user's merge (money_walk), maybe for days.
    [[ -z "$(money_walk "${held}")" ]] || held+=" (costs money)"
    die "held: $(basename "${f}" .md) waits for ${held} to merge; once it has, act on the Stacked line swarm.sh status prints for it, then review it again"
  fi
  echo "review: $(basename "${f}" .md) $*"
}

# review_state <file> <kept> <pr-url>... — mark_review's state: the item in review with prs:
# <pr-url>..., or, for a story whose depends_on parents are still open, blocked with held_by: <parents>
# and that prs: line, with REVIEW_HELD set to <parents> (else empty); either way with kept: <kept>,
# which review passes empty (a reviewed item is not a kept one) and close's keep_build fills.
# Called directly, never in $(...), so a state_set that dies does it at the command's own level,
# where main logs why.
REVIEW_HELD=""
review_state() {
  local f="$1" kept="$2"; shift 2
  REVIEW_HELD=""
  [[ "${f}" != "${BOARD}/stories/"* ]] || REVIEW_HELD="$(open_parents "${f}")"
  if [[ -n "${REVIEW_HELD}" ]]; then
    state_set "${f}" status blocked prs "$*" held_by "${REVIEW_HELD}" kept "${kept}"
  else
    state_set "${f}" status review prs "$*" held_by "" kept "${kept}"
  fi
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
# cannot be read: said on stderr, naming it. A pull that fails (pull_board_repo) changes nothing and
# dies, naming why. A merged item whose tracked file is still on a board in the repo is never deleted
# there, so the main checkout keeps no edit: after a pull, or with no upstream to pull from, it is
# marked done; while an unread PR holds the pull, it stays in review for the reconcile that pulls. On a board in the repo, each item a commit took off the board
# loses its state, however that commit was pulled (drop_gone_state). A red main whose base is green
# now is cleared, and its unstarted fix retired (green_mains).
reconcile_board() {
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
        builder="$(builder_state "${slug}")"; CLOSE_PANE_KEPT=""
        [[ "${builder}" != open ]] || close_agent "${slug}" </dev/null   # stdin is this loop's list
        # A builder whose pane could not be closed (close_pane) may still be working in the worktree.
        if [[ -n "${CLOSE_PANE_KEPT}" ]]; then
          echo "build kept: ${slug}'s builder pane is still open, so its worktree and story/${slug} stay; clear them once it is closed"
        else
          clear_build "${slug}" "the PR of ${slug} merged" "[]" </dev/null
        fi
        [[ "${builder}" != unknown ]] \
          || echo "build cleared: ${slug}'s builder may still be open (herdr cannot list its agents); close its pane with swarm.sh close ${slug}"
      fi
      merged+=("${slug}"); merged_files+=("${f}")
    fi
  done < <(board stories; board epics)
  # A pull is due after an item merged when there is an upstream, and otherwise when the checkout is
  # behind it (a PR merged with no review item: a board PR, a one-off). It is held after an unread PR:
  # if that merged, the pull would take its file before its build is cleared.
  local due=1
  if [[ ${#merged[@]} -gt 0 ]]; then has_upstream || due=0; else behind_upstream || due=0; fi
  if [[ ${due} == 1 && -n "${unread}" ]]; then
    echo "reconcile: not pulling ${PROJECT_DIR}: gh cannot read ${unread}; fix that, then run reconcile again" >&2
    due=0
  fi
  if [[ ${due} == 1 ]]; then
    pull_board_repo || die "reconcile: cannot pull ${PROJECT_DIR}: ${PULL_WHY}, then run reconcile again"
  fi
  local i
  for ((i = 0; i < ${#merged[@]}; i++)); do
    slug="${merged[i]}"; f="${merged_files[i]}"
    if [[ -f "${f}" && "$(fm "${f}" status)" != "done" && ${BOARD_IN_REPO} == 1 ]] \
      && git -C "${PROJECT_DIR}" ls-files --error-unmatch -- "${f}" >/dev/null 2>&1; then
      # Its tracked file is still here: with a pull held, its PR may have deleted it on the base.
      if [[ ${due} == 0 ]] && has_upstream; then
        echo "merged: ${slug}, not pulled yet; it stays in review until reconcile pulls ${PROJECT_DIR}"
        continue
      fi
      # Its PR left it on the board: done in its state, so the main checkout stays clean.
      set_status "${f}" "done"; record_event reconcile "${slug}" "ok (finished)"
      echo "merged: ${slug}, marked done; its file stays on the board until swarm.sh finish ${slug} takes it off"; continue
    fi
    if [[ -f "${f}" && "$(fm "${f}" status)" != "done" ]]; then
      delete_item "${f}"; record_event reconcile "${slug}" "ok (finished)"; continue
    fi
    # Its PR took it off the board or marked it done: its state goes too, or a later item with the
    # slug would read it.
    state_drop "${f}"
    record_event reconcile "${slug}" "ok (finished by its PR)"; echo "merged: ${slug}"
  done
  # Clearing a red main never fails reconcile: in the background, as merge runs reconcile, so set -e
  # holds inside it, a failed step or a die there is said and reconcile goes on.
  ( set -e; green_mains ) &
  wait $! || echo "clearing a red main failed (exit $?); reconcile goes on"
  [[ ${BOARD_IN_REPO} == 0 ]] || drop_gone_state
}

# RECONCILE_LOCK_WAIT: seconds a reconcile waits for another to finish (SWARM_RECONCILE_WAIT).
RECONCILE_LOCK_WAIT=300

# reconcile — reconcile_board, one at a time per project: merges through a merge queue run side by
# side, and two pulls of one checkout at once would collide. The lock is held by a subshell whose
# EXIT trap removes it, so a die inside still frees it; the subshell is the logged level when its
# caller was, so that die is still the command's outcome.
reconcile() {
  local lock="${PROJECT_DIR}/.swarm/reconcile.lock" level="${DIE_LEVEL}"
  mkdir -p "${PROJECT_DIR}/.swarm" || die "reconcile: cannot create ${PROJECT_DIR}/.swarm"
  SWARM_LOCK_WAIT="${SWARM_RECONCILE_WAIT:-${RECONCILE_LOCK_WAIT}}" state_lock "${lock}"
  # shellcheck disable=SC2064 # the path is fixed now
  ( [[ $((BASH_SUBSHELL - 1)) != "${level}" ]] || DIE_LEVEL="${BASH_SUBSHELL}"
    trap "rmdir '${lock}' 2>/dev/null || true" EXIT   # a failed rmdir must not fail a finished reconcile
    reconcile_board )
}

# drop_gone_state — state_drop each story and epic, by its board-state or escalated file, whose file a
# commit deleted (its PR or a board PR, pulled by reconcile or by hand): it is in neither HEAD nor the
# main checkout, and was in a commit before. A later item with its slug then starts with no state. A
# file missing only from the main checkout, or never committed, keeps its state. A board directory
# that is not there (git removes it with its last file) counts as holding no item.
drop_gone_state() {
  local s n d rel=""
  # The board's path from the root with a trailing /, or empty when the board is the root.
  [[ "${BOARD}" == "${PROJECT_DIR}" ]] || rel="${BOARD#"${PROJECT_DIR}"/}/"
  for s in "${BOARD_STATE_DIR}"/stories/* "${BOARD_STATE_DIR}"/epics/* "${PROJECT_DIR}"/.swarm/escalated/*; do
    n="${s##*/}"; d="${s%/*}"; d="${d##*/}"; [[ "${d}" != escalated ]] || d=stories
    [[ -f "${s}" && "${n}" =~ ^[a-z0-9-]+$ && ! -e "${BOARD}/${d}/${n}.md" ]] || continue
    ! git -C "${PROJECT_DIR}" cat-file -e "HEAD:${rel}${d}/${n}.md" 2>/dev/null || continue
    [[ -n "$(git -C "${PROJECT_DIR}" log -1 --format=%h HEAD -- "${rel}${d}/${n}.md")" ]] || continue
    state_drop "${BOARD}/${d}/${n}.md"
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
