# shellcheck shell=bash

# dash [--watch [seconds]] [--ladder] [--tree] — a read-only dashboard: a header and a summary
# line, what needs you, what runs now, each active epic's progress with its live agents and open PRs, and the recent
# events. --ladder adds the model per role; --tree shows the agents by herdr workspace and tab in
# place of the epics. It never writes the board, state or logs, and never opens or closes a pane.
# --watch rebuilds it every N seconds (default 2) and repaints in place; q quits, t and l toggle the
# tree and the ladder. Colour only on a terminal with NO_COLOR unset, or as DASH_COLOR says when set.
# Each --project <dir> (repeatable) draws that project's frame in turn (dash_frame) in place of this
# project's, so it runs from any directory; every dir is checked before anything is drawn.
dash() {
  local every="" tty=0 i d b c
  DASH_LADDER=0; DASH_TREE=0; DASH_DIRS=(); DASH_LEAD_ANY=off; DASH_ENV_W="${DASH_W:-}"; DASH_ENV_H="${DASH_H:-}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --watch)
        every=2
        if [[ -n "${2:-}" && "$2" != --* ]]; then every="$2"; shift; fi
        [[ "${every}" =~ ^[1-9][0-9]*$ ]] || die "dash --watch: seconds must be a positive whole number, not '${every}'" ;;
      --ladder) DASH_LADDER=1 ;;
      --tree) DASH_TREE=1 ;;
      --project) [[ -n "${2:-}" ]] || die "dash --project: name a project directory"
                 DASH_DIRS+=("$2"); shift ;;
      *) die "usage: swarm.sh dash [--watch [seconds]] [--ladder] [--tree] [--project <dir>]..." ;;
    esac
    shift
  done
  # init's marker; checked after the arguments and before any drawing, so --watch never draws an empty board either.
  if [[ ${#DASH_DIRS[@]} -eq 0 ]]; then
    # shellcheck disable=SC2153 # assigned in another file
    [[ -f "${BOARD}/stories/README.md" ]] || die "dash: no board at ${BOARD}; run swarm.sh init from the project's root"
  fi
  for ((i = 0; i < ${#DASH_DIRS[@]}; i++)); do
    d="$(cd "${DASH_DIRS[i]}" 2>/dev/null && pwd -P)" || d=""
    [[ -n "${d}" && -f "${d}/.claude/swarm/config" ]] \
      || die "dash --project ${DASH_DIRS[i]}: not a swarm project (no .claude/swarm/config)"
    c="$(SWARM_PROJECT="${d}" "${SWARM_HOME}/bin/swarm.sh" config)" || c=""
    b="$(sed -n 's/^board_dir = \(.*\)    (.*)$/\1/p' <<< "${c}")"
    [[ -n "${b}" && -f "${b}/stories/README.md" ]] || die "dash --project ${DASH_DIRS[i]}: no board at ${b}; run swarm.sh init there"
    [[ "${c}" != *$'\nlead = session '* ]] || DASH_LEAD_ANY=session
    DASH_DIRS[i]="${d}"
  done
  [[ ! -t 1 ]] || tty=1
  # Several projects share the height only in a watch on a terminal, or when DASH_H says so: a
  # one-shot dash, or one into a file or a pager, is never cut.
  DASH_SHARE=0
  if [[ ( ${tty} == 1 && -n "${every}" ) || -n "${DASH_ENV_H}" ]]; then DASH_SHARE=1; fi
  if [[ -z "${DASH_COLOR:-}" ]]; then
    DASH_COLOR=0
    [[ ${tty} == 0 || -n "${NO_COLOR+x}" ]] || DASH_COLOR=1
  fi
  dash_size
  if [[ -z "${every}" ]]; then
    [[ ${#DASH_DIRS[@]} -gt 0 ]] || dash_slow
    dash_frame; return
  fi
  dash_watch "${every}" "${tty}"
}

# dash_size — the terminal's columns and lines into DASH_W and DASH_H. Measured here, never in the
# render's $(...), where there is no terminal (tput answers 80 there): stty on /dev/tty, then tput
# on a terminal, then COLUMNS and LINES, then 100 columns and an unknown height (0). DASH_W and DASH_H
# set in dash's environment (a parent dash's share for one project, dash_frame) win.
dash_size() {
  local s="" c="" r=""
  s="$( { stty size </dev/tty; } 2>/dev/null)" || s=""
  r="${s% *}"; c="${s#* }"
  if [[ ! "${c}" =~ ^[1-9][0-9]*$ ]]; then
    c=""; r=""
    if [[ -t 1 ]]; then c="$(tput cols 2>/dev/null)" || c=""; r="$(tput lines 2>/dev/null)" || r=""; fi
  fi
  [[ "${c}" =~ ^[1-9][0-9]*$ ]] || c="${COLUMNS:-}"
  [[ "${c}" =~ ^[1-9][0-9]*$ ]] || c=100
  [[ "${r}" =~ ^[1-9][0-9]*$ ]] || r="${LINES:-}"
  [[ "${r}" =~ ^[1-9][0-9]*$ ]] || r=0
  [[ ! "${DASH_ENV_W}" =~ ^[1-9][0-9]*$ ]] || c="${DASH_ENV_W}"
  [[ ! "${DASH_ENV_H}" =~ ^[0-9]+$ ]] || r="${DASH_ENV_H}"
  DASH_W="${c}"; DASH_H="${r}"
}

# bin/lib/dash_legend.py — legend_lines(w, keys, wide, lead): the legend under dash's frame, packed onto as
# few lines as w columns allow, with a watch's keys at the end under 140 columns (wide puts them in
# the status bar). With lead = session most ! rows are the lead's queue, so the legend says so.

# dash_legend — the legend dash_frame draws once under several projects: legend_lines, then from 140
# columns the keys on a line of their own; dim when DASH_COLOR is 1.
dash_legend() {
  SWARM_LIB="${SWARM_HOME}/bin/lib" python3 -I -c '
import os, sys
sys.path.insert(0, os.environ["SWARM_LIB"]); from dash_legend import *
w, keys, lead, color = max(int(sys.argv[1]), 40), sys.argv[2] == "1", sys.argv[3] == "session", sys.argv[4] == "1"
rows = legend_lines(w, keys, w >= 140, lead) + (["   " + KEYWORDS + ("" if keys else " (with --watch)")] if w >= 140 else [])
rows = [r if len(r) <= w else r[:w - 1] + "…" for r in rows]
print("\n".join(f"\033[2m{r}\033[0m" if color else r for r in rows))' "${DASH_W}" "${DASH_KEYS:-0}" "${DASH_LEAD_ANY}" "${DASH_COLOR}"
}

# dash_frame — one frame: this project's (after dash_slow), or with --project each project's in turn,
# each drawn by this script run again on it (SWARM_PROJECT) with this colour, width, tree and ladder
# and no legend, then the legend once (dash_legend). With DASH_SHARE the height, less the legend's,
# is shared out between them; with too little room for a line each the legend goes. A project whose
# frame fails shows its error line in its place, the others are still drawn, and it returns 1. What
# the others print to stderr follows the frames, so it never pushes a header down.
dash_frame() {
  if [[ ${#DASH_DIRS[@]} -eq 0 ]]; then dash_render; return; fi
  local d out frames="" legend rows=0 h=0 failed=0 n=${#DASH_DIRS[@]} err errs=""
  err="$(mktemp "${TMPDIR:-/tmp}/swarm-dash.XXXXXX")" || die "dash: mktemp failed"
  legend="$(dash_legend)"
  if [[ ${DASH_SHARE} == 1 && ${DASH_H} -gt 0 ]]; then
    rows=$((DASH_H - $(wc -l <<< "${legend}")))
    [[ ${rows} -ge ${n} ]] || { legend=""; rows=${DASH_H}; }
    h=$((rows / n))
    # A known height is never shared down to 0, which would mean no limit.
    [[ ${h} -gt 0 ]] || h=1
  fi
  set -- dash
  [[ ${DASH_LADDER} == 0 ]] || set -- "$@" --ladder
  [[ ${DASH_TREE} == 0 ]] || set -- "$@" --tree
  for d in "${DASH_DIRS[@]}"; do
    if ! out="$(SWARM_PROJECT="${d}" DASH_COLOR="${DASH_COLOR}" DASH_W="${DASH_W}" DASH_H="${h}" DASH_LEGEND=0 \
        "${SWARM_HOME}/bin/swarm.sh" "$@" 2> "${err}")"; then
      out="$(tail -n 1 "${err}")"; out="$(basename "${d}")  could not draw: ${out#swarm: }"; failed=1
    elif [[ -s "${err}" ]]; then
      errs+="$(cat "${err}")"$'\n'
    fi
    frames+="${out}"$'\n'
  done
  rm -f "${err}"
  # More projects than lines: the 1-line shares still add up to no more than the height.
  if [[ ${h} -gt 0 ]]; then frames="$(sed -n "1,${rows}p" <<< "${frames%$'\n'}")"$'\n'; fi
  printf '%s%s' "${frames}" "${legend:+${legend}$'\n'}"
  printf '%s' "${errs}" >&2
  return "${failed}"
}

# dash_base_ref [dir] — in the repo at [dir] (default PROJECT_DIR), origin's default branch as last
# fetched (origin/HEAD; dash never fetches), else HEAD.
dash_base_ref() {
  if git -C "${1:-${PROJECT_DIR}}" rev-parse -q --verify origin/HEAD >/dev/null 2>&1; then echo origin/HEAD; else echo HEAD; fi
}

# dash_slow — the fields too slow for every frame, cached for a minute in a file under $TMPDIR (never
# under .swarm), so a one-shot dash reuses it too: today's estimated cost (the total line of
# cost_report), each open board item's PR checks, merge state, last update and whether it is open, one gh pr view per
# PR with a 5-second limit (a PR gh cannot answer in time is left out, and shows as its URL), each
# open story's open story/<slug> PR in that story's own repo (a builder's PR, which its story lists
# only from review on): one gh pr list of url and head per repo, named from its origin, then one gh pr
# view per PR that matches, each with the same limit; and how many stories of each epic finished
# (dash_finished).
dash_slow() {
  local cache f r urls pairs day
  # Today, or SWARM_DASH_NOW's day (dash_render's fixed clock).
  day="$(date +%F)"
  [[ -z "${SWARM_DASH_NOW:-}" ]] || day="$(python3 -c 'import datetime, sys; print(datetime.date.fromtimestamp(float(sys.argv[1])))' "${SWARM_DASH_NOW}")"
  # -3: the cache gained open-PR head lines; a name of its own, so an older swarm.sh's cache is never read.
  cache="${TMPDIR:-/tmp}/swarm-dash-3-$(printf '%s' "${PROJECT_DIR}" | cksum | cut -d' ' -f1)"
  if [[ -z "$(find "${cache}" -mmin -1 2>/dev/null)" ]]; then
    urls="$( { board stories; board epics; } | while IFS= read -r f; do
        [[ "$(fm "${f}" status)" == "done" ]] || fm "${f}" prs; done | grep -o 'https://github.com/[^] ,"]*/pull/[0-9]*' | sort -u || true)"
    # Each open story's repo and slug, so a story/<slug> branch counts only in the story's own repo.
    pairs="$(board stories | while IFS= read -r f; do
        [[ "$(get_fm "${f}" status)" == "done" ]] || { r="$(repo_dir "$(get_fm "${f}" repo)")" && printf '%s\t%s\n' "${r}" "$(basename "${f}" .md)"; }
      done || true)"
    {
      printf 'cost\t%s\n' "$( (cost_report "${day}") 2>/dev/null | sed -n 's/^| \*\*total\*\* |.* \([0-9][0-9.]*\) |$/\1/p' || true)"
      dash_finished
      # shellcheck disable=SC2086 # one URL per word
      if command -v gh >/dev/null 2>&1 && [[ -n "${urls}${pairs}" ]]; then SWARM_PAIRS="${pairs}" python3 "${SWARM_HOME}/bin/lib/dash_slow.py" ${urls}
      fi
    } > "${cache}.$$" 2>/dev/null && mv -f "${cache}.$$" "${cache}"
  fi
  DASH_COST="$(awk -F'\t' '$1 == "cost" { print $2 }' "${cache}" 2>/dev/null || true)"
  DASH_FINISHED="$(awk -F'\t' '$1 == "finished" { print $2 "\t" $3 }' "${cache}" 2>/dev/null || true)"
  DASH_PRSTATE="$(grep '^https://' "${cache}" 2>/dev/null || true)"
  DASH_HEADS="$(awk -F'\t' '$1 == "head" { print $2 "\t" $3 }' "${cache}" 2>/dev/null || true)"
}

# dash_finished — "finished<TAB>epic<TAB>count" per epic, from the board's own repo (none when the
# board is not in git). A finished story's file is deleted, so these are the story files deleted on
# the first-parent history of that repo's base branch and HEAD: one git log, names only, commits split
# on NUL (no diff text, so diff.noprefix or color settings cannot change it), each deleted file read
# from the parent's tree by one git cat-file --batch, its keys from the front matter only. A slug is
# counted once, and not at all while its file is on the board here (an unpulled checkout, or a slug
# added again): it is open. It counts when any of its deletions closed the story: the deleting commit
# names story/<slug> (its own PR's merge), or is the story's own work (it also changes a file that is
# not the board's own (its stories/, epics/, Board.base and README.md) nor a repo-root *.md, and its
# subject names no board/, close/ or epic/ branch: a squash-merged story PR, whose work may sit beside
# the board, as docs/operations.md does), the swarm finished it (finish, or reconcile "finished", in events.tsv), or
# the deleted file's last status was done or review (reconcile finishes only items in review) or it
# listed prs. A re-scope (a board/ PR, or a commit that edits only the board and root notes such as
# STATUS.md) has none of these, so it counts as nothing.
dash_finished() {
  local prefix
  prefix="$(git -C "${BOARD}" rev-parse --show-prefix 2>/dev/null)" || return 0
  python3 "${SWARM_HOME}/bin/lib/dash_finished.py" "${BOARD}" "${prefix}" "$(dash_base_ref "${BOARD}")" "${EVENTS_LOG}" 2>/dev/null || true
}

# dash_watch <seconds> <tty> — rebuild the frame every <seconds>, and repaint only when it changed;
# when only the clock moved, just the header line is rewritten. On a terminal it draws on the
# alternate screen with the cursor hidden, re-measures every frame, reads q (quit), r (redraw), t
# (the tree) and l (the ladder) without blocking, and redraws within a second of a resize (bash
# 3.2's read -t is not cut short by SIGWINCH, so it waits in one-second steps). Off a terminal it
# prints each changed frame, plain.
dash_watch() {
  local every="$1" tty="$2" tpl="" frame last="" key i winch=0 inst="" ver="" path="" now=""
  # The installed copy this runs from, if it is one: its scope and project, to re-read each frame. A
  # dev checkout matches no entry, so it never jumps to the installed copy.
  IFS=$'\t' read -r inst path ver <<< "$(dash_installed)"
  if [[ ${tty} == 1 ]]; then
    trap 'printf "\033[?25h\033[?1049l"' EXIT
    printf '\033[?1049h\033[?25l'
  fi
  trap 'exit 0' INT TERM HUP
  trap 'winch=1' WINCH
  while :; do
    if [[ -n "${inst}" ]]; then
      IFS=$'\t' read -r _ path now <<< "$(dash_installed "${inst}")"
      [[ -z "${now}" || "${now}" == "${ver}" ]] || dash_reexec "${path}/bin/swarm.sh" "${every}" "${tty}"
    fi
    [[ ${tty} == 0 ]] || dash_size
    # The cache file decides whether this asks gh again; each project's own dash runs it for itself.
    [[ ${#DASH_DIRS[@]} -gt 0 ]] || dash_slow
    # A failed render shows its error in the frame and the loop carries on: a watch must not die quietly.
    if ! tpl="$(DASH_CLOCK=HH:MM:SS DASH_KEYS="${tty}" dash_frame 2>&1)"; then
      # Keep the error line on screen: cut the rest to one line short of the terminal's height.
      [[ ${tty} == 0 || ${DASH_H} -lt 2 ]] || tpl="$(head -n $((DASH_H - 1)) <<< "${tpl}")"
      tpl+=$'\n'"(dash: this render failed; retrying in ${every}s)"
    fi
    frame="${tpl//HH:MM:SS/$(date +%H:%M:%S)}"
    if [[ ${tty} == 0 ]]; then
      [[ "${tpl}" == "${last}" ]] || printf '%s\n\n' "${frame}"
    elif [[ "${tpl}" != "${last}" || ${#DASH_DIRS[@]} -gt 1 ]]; then
      # Several projects have a clock each, so a frame that only ticked is repainted whole, in place.
      printf '\033[H%s\033[K\033[J' "${frame//$'\n'/$'\033[K\n'}"
    else
      printf '\033[H%s\033[K' "${frame%%$'\n'*}"
    fi
    last="${tpl}"; winch=0
    for ((i = 0; i < every; i++)); do
      if [[ ${tty} == 1 ]]; then
        key=""; read -rsn1 -t 1 key </dev/tty || true
        case "${key}" in
          q|Q) exit 0 ;;
          r|R) last=""; break ;;
          t|T) DASH_TREE=$((1 - DASH_TREE)); last=""; break ;;
          l|L) DASH_LADDER=$((1 - DASH_LADDER)); last=""; break ;;
        esac
      else
        sleep 1
      fi
      [[ ${winch} == 0 ]] || { last=""; break; }
    done
  done
}

# dash_installed [<install>] — this plugin's entry in installed_plugins.json as its install
# (scope:projectPath, as project installs share a scope), installPath and version, tab-separated: that
# install's entry, or with none the entry installed at SWARM_HOME (paths resolved). Installs at the
# same version share an installPath, so this project's own install wins, then one with no project.
# Prints nothing when the file is missing or unreadable or has no such entry.
dash_installed() {
  python3 "${SWARM_HOME}/bin/lib/dash_installed.py" "${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/plugins/installed_plugins.json" "${PLUGIN}" \
    "${SWARM_HOME}" "${PROJECT_DIR}" "${1:-}" 2>/dev/null || true
}

# dash_reexec <script> <seconds> <tty> — exec the newly installed <script> as `dash --watch <seconds>`
# on this project (the cwd may be gone), with the tree and ladder as they stand now and every --project. exec keeps the
# PID and skips the EXIT trap, so a terminal is restored first, in case the new script dies before
# it enters the alternate screen again. A script that is not an executable file is ignored.
dash_reexec() {
  [[ -f "$1" && -x "$1" ]] || return 0
  local script="$1" d
  [[ $3 == 0 ]] || printf '\033[?25h\033[?1049l'
  set -- dash --watch "$2"
  [[ ${DASH_LADDER} == 0 ]] || set -- "$@" --ladder
  [[ ${DASH_TREE} == 0 ]] || set -- "$@" --tree
  for d in ${DASH_DIRS[@]+"${DASH_DIRS[@]}"}; do set -- "$@" --project "${d}"; done
  SWARM_PROJECT="${PROJECT_DIR}" exec "${script}" "$@"
}

# dash_fields <file> — a board item's status, prs, epic, kind, title (its first "# " heading), who
# its step waits on and its first **You:** line's text, tab-separated, in one fork. Who is `held` for a held story (held_for: too), `escalated` for an escalated story
# (escalated_from: set; is_escalated's other tests are dash's), which is the lead's whatever it says,
# else `you` for a **You:** step (it starts a line, after any list marker, or a sentence: prose that
# names the convention, "has no **You:** step", is no step), else empty. The text is what follows the
# first step's **You:**, tabs as spaces. The keys are read from the front matter only (a leading ---, up to the next; CRLF
# tolerated), by fm's rule: a key's first line wins, an empty value too. dash_finished's front()
# reads them the same way.
dash_fields() {
  awk '{ sub(/\r$/, "") }
    NR == 1 && $0 == "---" { n = 1; next }
    n == 1 && $0 == "---" { n = 2; next }
    n == 1 && !hs && sub(/^status: */, "") { hs = 1; s = $0; next }
    n == 1 && !hp && sub(/^prs: */, "") { hp = 1; p = $0; next }
    n == 1 && !he && sub(/^epic: */, "") { he = 1; e = $0; next }
    n == 1 && !hk && sub(/^kind: */, "") { hk = 1; k = $0; next }
    n == 1 && !hx && sub(/^escalated_from: */, "") { hx = 1; x = $0; next }
    n == 1 && !hh && sub(/^held_for: */, "") { hh = 1; h = $0; next }
    n != 1 && !y && match($0, /(^[[:space:]]*([-*] )?|[.!?] )\*\*You:\*\*/) {
      y = 1; yt = substr($0, RSTART + RLENGTH); gsub(/\t/, " ", yt); sub(/^ +/, "", yt); sub(/ +$/, "", yt) }
    n != 1 && !ht && sub(/^# /, "") { ht = 1; t = $0 }
    END { printf "%s\t%s\t%s\t%s\t%s\t%s\t%s", s, p, e, k, t, (x != "" ? (h != "" ? "held" : "escalated") : (y ? "you" : "")), yt }' "$1"
}

# dash_render — gather what the dashboard shows (read-only), then lay it out in python at DASH_W x
# DASH_H. herdr is asked whenever it is on PATH, inside a herdr pane or not: dash only reads. Claude
# Code's list of sessions is read once a frame (DASH_SESSIONS); with no claude, every recorded
# session is unknown.
dash_render() {
  local agents="" panes="" workspaces="" sessions="" board="" policies="" merges="" drift="" commits="" waits="" f d r x
  if command -v herdr >/dev/null 2>&1; then
    # The lists status reads; the workspace list only labels the tree, so a failed one costs no agent.
    { agents="$(herdr agent list 2>/dev/null)" && panes="$(herdr pane list 2>/dev/null)"; } || agents=""
    [[ -z "${agents}" ]] || workspaces="$(herdr workspace list 2>/dev/null)" || workspaces=""
  fi
  [[ -z "${agents}" ]] || sessions="$(claude_agents)" || sessions=""
  # One line per item: dir, slug, status, prs, its agent name, (an epic) its conductor's, epic, kind, title, you, its **You:** text.
  for d in hld epics stories; do
    while IFS= read -r f; do
      r="$(basename "${f}" .md)"; x="$(dash_fields "${f}")"
      board+="${d}"$'\t'"${r}"$'\t'"${x%%$'\t'*}"$'\t'"$(cut -f2 <<< "${x}")"$'\t'"$(agent_name "${r}")"$'\t'"$(agent_name "conduct-${r}")"$'\t'"$(cut -f3- <<< "${x}")"$'\n'
    done < <(board "${d}")
  done
  # Each active epic with no stories whose depends_on still holds its planning up, as next reads it.
  while IFS= read -r f; do
    if x="$(epic_holding_deps "${f}")" && [[ -n "${x}" ]]; then waits+="$(basename "${f}" .md)"$'\t'"${x}"$'\n'; fi
  done < <(board epics)
  # The last worktree commit or edit of each working builder's story (stall.py's story_for), for the stall rule.
  while IFS= read -r r; do
    [[ -z "${r}" ]] || commits+="${r}"$'\t'"$(story_work_time "${r}")"$'\n'
  done < <(awk -F'\t' '$1 == "stories" { print $2 "\t" $5 "\t" $3 }' <<< "${board}" \
    | SWARM_OWN="$(own_panes)" DASH_AGENTS="${agents}" \
      DASH_SESSIONS="${sessions}" DASH_AGENTS_LOG="${AGENTS_LOG}" SWARM_LIB="${SWARM_HOME}/bin/lib" python3 -I -c '
import json, os, sys
sys.path.insert(0, os.environ["SWARM_LIB"]); from stall import *; from panes import *
E = os.environ
rows = [l.rstrip("\n").split("\t") for l in sys.stdin]
own = set(E["SWARM_OWN"].split())
try:
    agents = json.loads(E["DASH_AGENTS"])["result"]["agents"]
except (ValueError, KeyError, TypeError):
    agents = []
for a in agents:
    n = a.get("name") if isinstance(a, dict) else None
    if n and a.get("pane_id") in own and agent_state(a, n, session_state(E["DASH_AGENTS_LOG"], n, E["DASH_SESSIONS"]))[0] == "working":
        print(story_for(n, rows) or "")' 2>/dev/null || true)
  # ponytail: a few forks per board item each redraw; read the front matter in python if boards grow past ~150 items.
  for r in $(roles); do policies+="${r} $(policy "${r}")"$'\n'; done
  if [[ ${PROJECT_IS_GIT} == 1 ]]; then
    merges="$(git -C "${PROJECT_DIR}" log --first-parent --merges -n 40 --format='%cI%x09%an%x09%s' "$(dash_base_ref)" 2>/dev/null || true)"
    # The board files edited and not committed in the main checkout, a rename by its new name, each
    # relative to the board; no optional locks, so status writes no index.
    # -z: paths as they are, never quoted; a rename or copy (R or C in either column) is followed by
    # its old path, skipped.
    x="$(git -C "${BOARD}" rev-parse --show-prefix 2>/dev/null || true)"
    drift="$(GIT_OPTIONAL_LOCKS=0 git -C "${PROJECT_DIR}" status --porcelain -z --untracked-files=all -- "${BOARD}" 2>/dev/null \
      | while IFS= read -r -d '' f; do
          if [[ "${f:0:2}" == *[RC]* ]]; then IFS= read -r -d '' _ || true; fi
          f="${f:3}"; printf '%s\n' "${f#"${x}"}"
        done || true)"
  fi
  # sed, not head: head exits after a line, and where SIGPIPE is ignored (CI) next_step's second echo
  # prints "Broken pipe" into the frame, now and then, so --watch sees a changed frame.
  # shellcheck disable=SC2154 # assigned in another file
  DASH_PROJECT="${PROJECT_DIR}" DASH_VERSION="$(plugin_version < "${SWARM_HOME}/.claude-plugin/plugin.json")" \
  DASH_MERGE="${CFG_merge}" DASH_LEAD="${CFG_lead}" DASH_NEXT="$(next_step | sed -n 1p)" DASH_BOARD="${board}" DASH_POLICY="${policies}" \
  DASH_WAITING="$(waiting_on_user)" DASH_EPIC_WAITS="${waits}" DASH_MERGES="${merges}" DASH_DRIFT="${drift}" \
  DASH_AGENTS="${agents}" DASH_PANES="${panes}" DASH_WORKSPACES="${workspaces}" DASH_STATE="${STATE_DIR}" DASH_BOARD_DIR="${BOARD}" \
  SWARM_OWN="$(own_panes)" DASH_COLS="${DASH_W:-100}" DASH_LINES="${DASH_H:-0}" \
  DASH_COLOR="${DASH_COLOR:-0}" DASH_FIT="${DASH_ENV_H:+1}" DASH_PRSTATE="${DASH_PRSTATE:-}" DASH_HEADS="${DASH_HEADS:-}" DASH_COST="${DASH_COST:-}" \
  DASH_FINISHED="${DASH_FINISHED:-}" DASH_TREE="${DASH_TREE:-0}" DASH_LADDER="${DASH_LADDER:-0}" \
  DASH_COMMITS="${commits}" DASH_STALL_MIN="${CFG_stall_minutes}" DASH_SESSIONS="${sessions}" \
  DASH_AGENTS_LOG="${AGENTS_LOG}" DASH_PROJECTS="${CLAUDE_PROJECTS}" DASH_FINDINGS="${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}" DASH_EVENTS="${EVENTS_LOG}" \
  DASH_BUILDERS="${BUILDER_ROLES}" DASH_ESCALATE_AFTER="${CFG_escalate_after}" DASH_CODEX_MIN="${CFG_codex_minutes}" SWARM_FINDING_REVIEWERS="${FINDING_REVIEWERS}" python3 "${SWARM_HOME}/bin/lib/dash_render.py"
}
