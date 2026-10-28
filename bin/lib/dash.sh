# shellcheck shell=bash

# dash [--watch [seconds]] [--ladder] [--tree] — a read-only dashboard: a header and a summary
# line, what needs you, what runs now, each active epic's progress with its live agents and open PRs, and the recent
# events. --ladder adds the model per role; --tree shows the agents by herdr workspace and tab in
# place of the epics. It never writes the board or state, and never opens or closes a pane. The one
# log it writes is its row in .swarm/run-times.tsv (swarm.sh's timed; a watch's after its first frame).
# --watch rebuilds it every N seconds (default 2) and repaints in place; q quits, t and l toggle the
# tree and the ladder. Colour only on a terminal with NO_COLOR unset, or as DASH_COLOR says when set.
# Each --project <dir> (repeatable) draws that project's frame in turn (dash_frame) in place of this
# project's, so it runs from any directory; every dir is checked before anything is drawn.
# --check draws nothing: it checks each project's figures against their commands (dash_check).
# Each frame's reads that can block share one report deadline (dash_deadline): a read past it is cut
# or skipped, the frame is drawn from what the others gave, and a last line names each one.
dash() {
  local every="" tty=0 check=0 i d b c
  DASH_LADDER=0; DASH_TREE=0; DASH_DIRS=(); DASH_LEAD_ANY=off; DASH_ENV_W="${DASH_W:-}"; DASH_ENV_H="${DASH_H:-}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --watch)
        every=2
        if [[ -n "${2:-}" && "$2" != --* ]]; then every="$2"; shift; fi
        [[ "${every}" =~ ^[1-9][0-9]*$ ]] || die "dash --watch: seconds must be a positive whole number, not '${every}'" ;;
      --ladder) DASH_LADDER=1 ;;
      --tree) DASH_TREE=1 ;;
      --check) check=1 ;;
      --project) [[ -n "${2:-}" ]] || die "dash --project: name a project directory"
                 DASH_DIRS+=("$2"); shift ;;
      *) die "usage: swarm.sh dash [--watch [seconds]] [--ladder] [--tree] [--check] [--project <dir>]..." ;;
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
  if [[ ${check} == 1 ]]; then
    [[ -z "${every}" && ${DASH_LADDER} == 0 && ${DASH_TREE} == 0 ]] || die "dash --check draws nothing: --watch, --tree and --ladder do not go with it"
    dash_check; return
  fi
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
    dash_deadline
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

# dash_deadline — start one frame's report deadline (report_start): REPORT_SECONDS (merge.sh:
# SWARM_REPORT_SECONDS when it is whole seconds above 0, else 30). From here on every herdr, claude and
# gh call in this process goes through report_read, named by its subcommand: those reads sit deep in
# helpers dash shares with next and status (next_lines, test_running), and dash only reads, so no write
# or agent start is cut. The deadline and the skip file go to the python dash runs too (SWARM_REPORT_END
# and SWARM_REPORT_SKIP_FILE, as status sets them): panes.py's pane_text, dash_render.py's read of an
# agent's pane for a usage-limit dialog, takes at most the time left and records `herdr agent read` when
# cut. With --project each project's frame runs this for itself, so each has a deadline of its own.
# dash --check never calls it: its frame reads in full (dash_check_frame).
dash_deadline() {
  report_start || die "dash: could not start the report deadline"
  export SWARM_REPORT_END="${REPORT_END}" SWARM_REPORT_SKIP_FILE="${REPORT_SKIP_FILE}"
  # </dev/null, as status_reads (merge.sh) has: a read inside a while-read loop must not eat the loop's input.
  herdr() { report_read "herdr ${*:1:2}" herdr "$@" </dev/null; }
  # shellcheck disable=SC2329 # claude_agents (agents.sh) calls it
  claude() { report_read "claude ${1:-}" claude "$@" </dev/null; }
  # shellcheck disable=SC2329 # for any gh call a helper dash shares with status makes; dash_slow's own are python's
  gh() { if [[ "${1:-}" == api ]]; then report_read "gh api" gh "$@" </dev/null; else report_read "gh ${*:1:2}" gh "$@" </dev/null; fi; }
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
# each drawn by this script run again on it (SWARM_PROJECT) with this colour, width, tree and ladder,
# a deadline of its own (dash_deadline) and no legend, then the legend once (dash_legend). With
# DASH_SHARE the height, less the legend's, is shared out between them; with too little room for a
# line each the legend goes. A project whose frame fails shows its error line in its place, the
# others are still drawn, and it returns 1. What the others print to stderr follows the frames, so it
# never pushes a header down.
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
# view per PR that matches, each with the same limit; how many stories of each epic finished
# (dash_finished); and the project's ci line (its origin repo's row of flow's ci time, from a cache of
# its own, in a 0700 directory of this user's, that a detached dash_slow.py refreshes every 6 hours).
# dash_slow.py's reads run under the report deadline (report_read, as gh PR states), with at most half
# of it (DASH_GH_SHARE): they come first in the frame, and a slow GitHub with many PRs must leave
# dash_render's herdr reads their own time. It stops each gh call a second short of that end
# (DASH_READ_END), so no gh outlives the frame in a session of its own, and exits 142, report_read's
# cut. A run cut there keeps what it printed (python -u, in case report_read's KILL comes first) over
# the last cache's lines it did not reach (dash_cache_merge), so a PR state, a story's head or the ci
# line, a local 6-hour cache, stands until a later run reads it again; a PR no run has answered shows
# as its URL, as a PR gh cannot answer in 5 seconds does.
DASH_GH_SHARE=2
dash_slow() {
  local cache f r urls pairs day key rc=0 gh_end
  day="$(dash_day)"
  # -3: the cache gained open-PR head lines; a name of its own, so an older swarm.sh's cache is never read.
  key="$(printf '%s' "${PROJECT_DIR}" | cksum | cut -d' ' -f1)"
  cache="${TMPDIR:-/tmp}/swarm-dash-3-${key}"
  # DASH_FRESH (dash_check) asks again whatever the cache's age.
  if [[ -n "${DASH_FRESH:-}" || -z "$(find "${cache}" -mmin -1 2>/dev/null)" ]]; then
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
      # Test mode (SWARM_SLEEP_SCALE set) starts no ci refresh unless SWARM_NO_CI_REFRESH is set, if
      # only to empty: a detached refresh outlives the test and runs flow, and gh, on its project.
      if gh_installed; then
        # The gh reads' end: the deadline, or half of REPORT_SECONDS from now when that comes first.
        gh_end="$(perl -MTime::HiRes=time -e 'my ($end, $s) = @ARGV; my $h = time + $s; printf "%.3f", $h < $end ? $h : $end' -- "${REPORT_END}" "$((REPORT_SECONDS / DASH_GH_SHARE))")"
        SWARM_NO_CI_REFRESH="${SWARM_NO_CI_REFRESH-${SWARM_SLEEP_SCALE:+1}}" SWARM_CI_CACHE="${TMPDIR:-/tmp}/swarm-dash-ci-$(id -u)/${key}" SWARM_CI_PROJECT="${PROJECT_DIR}" SWARM_PAIRS="${pairs}" DASH_READ_END="${gh_end}" \
          report_read "gh PR states" python3 -u "${SWARM_HOME}/bin/lib/dash_slow.py" ${urls}
      fi
    } > "${cache}.$$" 2>/dev/null || rc=$?
    # A full run replaces the cache; one cut at the deadline (142) is merged over it; any other failure
    # leaves it as it was.
    if [[ ${rc} == 0 ]]; then mv -f "${cache}.$$" "${cache}"
    elif [[ ${rc} == 142 ]]; then dash_cache_merge "${cache}" "${cache}.$$"
    else rm -f "${cache}.$$"; fi
  fi
  DASH_COST="$(awk -F'\t' '$1 == "cost" { print $2 }' "${cache}" 2>/dev/null || true)"
  DASH_FINISHED="$(awk -F'\t' '$1 == "finished" { print $2 "\t" $3 }' "${cache}" 2>/dev/null || true)"
  DASH_PRSTATE="$(grep '^https://' "${cache}" 2>/dev/null || true)"
  DASH_HEADS="$(awk -F'\t' '$1 == "head" { print $2 "\t" $3 }' "${cache}" 2>/dev/null || true)"
  DASH_CI="$(awk -F'\t' '$1 == "ci" { print $2 }' "${cache}" 2>/dev/null || true)"
}

# dash_day [days before] — today as YYYY-MM-DD, or SWARM_DASH_NOW's day (dash_render's fixed clock),
# or the day that many calendar days before it.
dash_day() {
  if [[ -z "${SWARM_DASH_NOW:-}${1:-}" ]]; then date +%F; return; fi
  python3 -c 'import datetime, sys, time; print(datetime.date.fromtimestamp(float(sys.argv[1] or time.time())) - datetime.timedelta(days=int(sys.argv[2])))' \
    "${SWARM_DASH_NOW:-}" "${1:-0}"
}

# dash_check — dash --check: each figure in this project's frame (drawn afresh, plain, at 100
# columns so the gauges show) against the command that owns it; with --project, each project in
# turn, by this script run again on it. agents working and the running gauge against the agents
# `status` lists as working; the cost against flow's cost section since today with no calling
# session (dash leaves it out), read just before and just after the frame, so spend in between
# agrees; every item flow's lead_queue holds open, named in needs you or the lead's queue (an
# escalated or held story only with lead = session, the only time dash draws it; a no-agent item only
# when status read herdr's agent list); the PRs, the
# stories only you or the lead can run (+N more counted) and the agents waiting on a prompt that
# status lists, in needs you and the lead's queue; next against `next`; the epics waiting on their
# depends_on against epic_holding_deps, the rule next plans by (next prints one step, so it cannot
# list them); merges today and the 7-day rate against flow's merges section. flow's sections run
# here, in this process, and ask gh nothing. Prints each mismatch as `<project>: <field>: dash shows
# <x>, <owner> says <y>` (a project by its basename, or by its path when two --project dirs share
# one) and returns 1 on any; a frame dash cannot draw is one line, `<project>: frame: ...`.
dash_check() {
  local d n failed=0
  if [[ ${#DASH_DIRS[@]} -gt 0 ]]; then
    for d in "${DASH_DIRS[@]}"; do
      n="$(basename "${d}")"
      [[ "$(printf '%s\n' "${DASH_DIRS[@]}" | sed 's#.*/##' | grep -cxF -- "${n}")" == 1 ]] || n="${d}"
      DASH_CHECK_NAME="${n}" SWARM_PROJECT="${d}" "${SWARM_HOME}/bin/swarm.sh" dash --check || failed=1
    done
    return "${failed}"
  fi
  local sw="${SWARM_HOME}/bin/swarm.sh" herdr="" day lo hi frame st need boxes drawn got want x f v err
  DASH_CHECK_P="${DASH_CHECK_NAME:-$(basename "${PROJECT_DIR}")}"; DASH_CHECK_BAD=0; DASH_CHECK_NOSTATUS=""
  ! command -v herdr >/dev/null 2>&1 || herdr=1
  day="$(dash_day)"
  lo="$(dash_flow_cost "${day}")"
  err="$(mktemp "${TMPDIR:-/tmp}/swarm-dash.XXXXXX")" || die "dash --check: mktemp failed"
  if ! frame="$(dash_check_frame 2> "${err}")"; then
    echo "${DASH_CHECK_P}: frame: dash could not draw it: $(tail -n 1 "${err}")"
    rm -f "${err}"; return 1
  fi
  rm -f "${err}"
  # status asks herdr only inside a pane; dash whenever herdr is on PATH. Read next to the frame, as
  # agents change state.
  # A status that fails is said once, and the fields it owns are not compared with nothing.
  # Both read in full, as the frame does (DASH_CHECK_SECONDS): a read cut at 30 s would differ for the cut, not the code.
  st="$(HERDR_ENV="${herdr}" SWARM_PROJECT="${PROJECT_DIR}" SWARM_REPORT_SECONDS="${DASH_CHECK_SECONDS}" "${sw}" status)" || { dash_unread "agents and Waiting on you" status; DASH_CHECK_NOSTATUS=1; }
  hi="$(dash_flow_cost "${day}")"

  want="$(grep -c '^  [^ ]*  *working  \[' <<< "${st}" || true)"
  dash_agree "agents working" "$(dash_first '.* \([0-9][0-9]*\) agents working.*' "${frame}")" status "${want}"
  got="$(dash_first '.*running [^0-9]*\([0-9][0-9]*\) of peak.*' "${frame}")"
  # dash leaves the gauge out only with no agent or pane list from herdr (none, or none it can read),
  # and then status has none either: its Agents line says their states are not available.
  if [[ -n "${got}" || ( "${st}" != *$'\nAgents: '*"so their states are not available"* && "${st}" != "Agents: "*"so their states are not available"* && "${st}" != *"(herdr gave no agent list)"* ) ]]; then
    dash_agree running "${got}" status "${want}"
  fi

  got="$(dash_first '.*\$\([0-9][0-9.]*\) today.*' "${frame}")"
  want="${lo}"; [[ "${hi}" == "${lo}" ]] || want="${lo} to ${hi}"
  [[ -n "${lo}" && -n "${hi}" ]] || want="nothing: its cost could not be read"
  # What the agents spent between the two reads moves flow's cost on: anything from one to the other agrees.
  if [[ -n "${got}" && -n "${lo}" && -n "${hi}" ]] && awk -v g="${got:-x}" -v lo="${lo:-x}" -v hi="${hi:-x}" \
      'BEGIN { exit !(g != "x" && lo != "x" && hi != "x" && g + 0 >= lo + 0 && g + 0 <= hi + 0) }'; then got="${want}"; fi
  dash_agree cost "${got}" "flow --since ${day}" "${want}"

  # A section that fails is reported, never read as an empty one.
  x="$(flow_sections 0000-00-00 9999-12-30 "" "" "" lead_queue 2>/dev/null)" || dash_unread "lead's queue" "flow's lead_queue"
  # Both of its tables: the queue's (5 fields) and the no-agent items' (6), each a day's row with its
  # open items last. A no-agent item only when status read herdr's agent list: dash draws no-agent rows
  # from that list, so without one it has none to show.
  v=""; [[ -z "${st}" || "${st}" == "Agents: not inside herdr"* || "${st}" == *"(herdr gave no agent list)"* ]] || v=1
  # shellcheck disable=SC2154 # assigned in another file
  want="$(awk -F'\t' -v lead="${CFG_lead}" -v herdr="${v}" '$1 ~ /^[0-9]/ && (NF == 5 || NF == 6) && $NF != "-" {
      n = split($NF, a, ","); for (i = 1; i <= n; i++) if ((lead == "session" || a[i] !~ /^(escalated|held):/) && (herdr || NF == 5)) print a[i] }' <<< "${x}" | dash_words)"
  need="$(dash_box "needs you" "${frame}")"
  boxes="${need}"$'\n'"$(dash_box "lead's queue" "${frame}")"
  # The PRs the merge rows show, as <repo>#<n>: by that ref, or by URL when gh did not answer. A held PR
  # that a story and its epic both list is shown once, under the first.
  x="$(grep '^│ [^ ]* merge ' <<< "${boxes}" || true)"
  drawn="$( { sed -n 's/^│ [^ ]* merge \([^ ]*#[0-9][0-9]*\) .*/\1/p' <<< "${x}"; dash_prs <<< "${x}"; } | dash_words)"
  got=""
  for x in ${want}; do
    # Each kind has its own row: merge, review for a kept story, no agent on story for a no-agent item,
    # the wait --lead line as it is for a failed step-up (its exit names the slug) and for a no-review
    # item, or no agent on story for one whose builder was gone too (that poll prints its no-agent: line
    # instead), or decide for an escalated or held story, which dash draws
    # as a merge row once it is in review. A merge item counts by its slug or by any PR status lists for it.
    case "${x%%:*}" in
      merge) v=merge ;; kept) v="review kept story" ;; no-agent) v="no agent on story" ;;
      step-up-failed) v="step-up failed:" ;; no-review) v="(no agent on story|no-review:)" ;;
      *) v="(merge|decide escalated story)" ;;
    esac
    if dash_names "${x#*:}" "$(grep -E "^│ [^ ]* ${v} " <<< "${boxes}" || true)"; then got+=" ${x}"; continue; fi   # loose-match: ok v is a regex: a row's verb or an alternation
    [[ "${x%%:*}" == merge ]] || continue
    for f in $(awk -v s="${x#*:}" '/^  awaiting your merge/ { sub(/^[^:]*: /, ""); sub(/^epic /, ""); if ($1 == s) print }' <<< "${st}" | dash_prs); do
      if [[ " ${drawn} " == *" ${f} "* ]]; then got+=" ${x}"; break; fi
    done
  done
  dash_agree "lead's queue" "${got# }" "flow's lead_queue" "${want}"

  dash_agree "PRs waiting for a merge" "${drawn}" status "$(grep '^  awaiting your merge' <<< "${st}" | dash_prs | dash_words)"
  # A `<kind>: <slug>` line under Waiting on you is a story only you or the lead can run: a run row
  # each, but for the ones behind needs you's +N more.
  n="$(grep -c '^│ [^ ]* run [^ ]* story ' <<< "${boxes}" || true)"
  got="$(dash_first '.* +\([0-9][0-9]*\) more.*' "${need}")"
  want="$(sed -n '/^Waiting on you$/,/^$/p' <<< "${st}" | grep -c '^  [^ :]*: [^ ]*$' || true)"
  dash_agree "stories only you or the lead can run" "$((n + ${got:-0}))" status "${want}"
  dash_agree "agents waiting on a prompt" "$(sed -n 's/^│ [^ ]* answer \([^ :]*\)[: ].*/\1/p' <<< "${boxes}" | dash_words)" \
    status "$(sed -n 's/^  \([^ ]*\)  *WAITING .*/\1/p' <<< "${st}" | dash_words)"

  # _step: next's step without the conductors next starts; --dash: its no-agent lines read as dash reads them.
  want="$(SWARM_PROJECT="${PROJECT_DIR}" SWARM_REPORT_SECONDS="${DASH_CHECK_SECONDS}" "${sw}" _step --dash 2>/dev/null | sed -n 1p || true)"
  got="$(dash_first '.*  next \(.*[^ ]\)  *[0-9][0-9:]*$' "$(sed -n 1p <<< "${frame}")")"
  dash_agree next "$(dash_cut "${got}" "${want}")" next "${want}"

  want="$(while IFS= read -r f; do
      if x="$(epic_holding_deps "${f}")" && [[ -n "${x}" ]]; then echo "$(basename "${f}" .md): ${x// /, }"; fi
    done < <(board epics) | sort)"
  # The epics box's epic rows only (its agent rows are indented), whatever their symbol: a waiting epic
  # is ⏸ unless an agent, a look or a PR under it gives it another.
  # An epic whose open stories are all after: ones says `after: <slugs> waits on the lead`, which is no
  # depends_on wait (epic_holding_deps leaves it out).
  got="$(dash_box epics "${frame}" rows | { grep -v ' after: .* waits on the lead *$' || true; } | sed -n 's/^│ [^ ][^ ]* \([^ ]*\) .* waits on \(.*[^ ]\) *$/\1: \2/p' | while IFS= read -r x; do
      while IFS= read -r f; do x="$(dash_cut "${x}" "${f}")"; done <<< "${want}"; echo "${x}"
    done | sort | paste -sd';' -)"
  dash_agree "epics waiting on depends_on" "${got}" next "$(paste -sd';' - <<< "${want}")"

  if x="$(flow_sections "$(dash_day 6)" "${day}" "" "" "" merges 2>/dev/null)"; then
    x="$(awk -F'\t' -v d="${day}" 'NR > 2 && NF == 2 { w += $2; if ($1 == d) t = $2 } END { printf "%d %.1f\n", t, w / 7 }' <<< "${x}")"
    dash_agree "merges today" "$(dash_first '.*  today \([0-9][0-9]*\)  7-day avg.*' "${frame}")" "flow's merges" "${x% *}"
    dash_agree "7-day rate" "$(dash_first '^\([0-9][0-9.]*\) merged/day over 7 days.*' "${frame}")" "flow's merges" "${x#* }"
  else
    dash_unread "merges today and the 7-day rate" "flow's merges"
  fi

  [[ ${DASH_CHECK_BAD} == 1 ]] || echo "${DASH_CHECK_P}: every dash figure agrees with the command that owns it"
  return "${DASH_CHECK_BAD}"
}

# dash_flow_cost <day> — the total of flow's cost section since that day, with no calling session.
dash_flow_cost() {
  { flow_sections "$1" 9999-12-30 "" "" "" cost 2>/dev/null || true; } | sed -n 's/^| \*\*total\*\* |.* \([0-9][0-9.]*\) |$/\1/p'
}

# dash_cache_merge <cache> <new> — <new>'s lines, then <cache>'s lines whose key <new> lacks, into
# <cache>; <new> is removed. A line's key is its first field (cost, ci, a PR's URL), or its first two
# for a head or finished line (the slug, the epic). With no <cache> yet, <new>'s lines stand alone.
dash_cache_merge() {
  awk -F'\t' '{ k = ($1 == "head" || $1 == "finished") ? $1 FS $2 : $1 }
    FNR == NR { seen[k] = 1; print; next } !(k in seen)' "$2" "$1" > "$2.m" 2>/dev/null || true
  mv -f "$2.m" "$1"; rm -f "$2"
}

# DASH_CHECK_SECONDS: the report deadline of dash --check's frame, a day, which stands for none: it
# reads in full, like the commands it is checked against, so no figure differs for a read cut short.
DASH_CHECK_SECONDS=86400

# dash_check_frame — this project's frame for dash_check: the slow fields asked again, plain, at 100
# columns, with the epics and not the tree, every read in full (DASH_CHECK_SECONDS).
dash_check_frame() {
  # shellcheck disable=SC2034 # read by dash_slow, dash_render and report_start
  local DASH_FRESH=1 DASH_W=100 DASH_H=0 DASH_ENV_H="" DASH_COLOR=0 DASH_TREE=0 REPORT_SECONDS="${DASH_CHECK_SECONDS}"
  report_start || die "dash --check: could not start the report deadline"
  dash_slow; DASH_LEGEND=0 dash_render
}

# dash_agree <field> <dash's value> <owner> <owner's value> — prints a mismatch and marks the check
# failed; a field status owns is skipped once status could not be read (DASH_CHECK_NOSTATUS).
dash_agree() {
  [[ "$2" != "$4" ]] || return 0
  [[ "$3" != status || -z "${DASH_CHECK_NOSTATUS}" ]] || return 0
  echo "${DASH_CHECK_P}: $1: dash shows ${2:-nothing}, $3 says ${4:-nothing}"
  DASH_CHECK_BAD=1
}

# dash_unread <field> <owner> — the owner could not be read: prints that and marks the check failed.
dash_unread() {
  echo "${DASH_CHECK_P}: $1: $2 could not be read"
  DASH_CHECK_BAD=1
}

# dash_first <sed regex with a group> <text> — the group in the first line that matches, or nothing.
dash_first() { sed -n "\\#$1#{s##\\1#p;q;}" <<< "$2"; }

# dash_cut <dash's> <owner's> — the owner's value when dash's is it cut to the width (each … standing
# for what was cut, the rest matched as plain text), else dash's.
dash_cut() {
  local shown="$1" rest="$2" piece
  if [[ "${shown}" != *…* ]]; then printf '%s' "$1"; return; fi
  piece="${shown%%…*}"; shown="${shown#*…}"
  if [[ "${rest}" != "${piece}"* ]]; then printf '%s' "$1"; return; fi   # loose-match: ok the first piece of a cut line starts the full one
  rest="${rest#"${piece}"}"
  while [[ "${shown}" == *…* ]]; do
    piece="${shown%%…*}"; shown="${shown#*…}"
    if [[ "${rest}" != *"${piece}"* ]]; then printf '%s' "$1"; return; fi   # loose-match: ok a piece of a cut line may sit anywhere in the full one
    rest="${rest#*"${piece}"}"
  done
  if [[ "${rest}" == *"${shown}" ]]; then printf '%s' "$2"; else printf '%s' "$1"; fi   # loose-match: ok the last piece of a cut line ends the full one
}

# dash_names <word> <text> — true when a line of <text> has <word> as a whole word (words split at
# spaces, parentheses and colons), compared as plain text.
dash_names() { awk -v s="$1" '{ n = split($0, w, /[ ():]+/); for (i = 1; i <= n; i++) if (w[i] == s) f = 1 } END { exit !f }' <<< "$2"; }

# dash_words — stdin's lines, sorted and each once (a story's merge row per PR), on one line.
dash_words() { sort -u | paste -sd' ' -; }

# dash_prs — the GitHub PR URLs in stdin, each as <repo>#<n> (dash's ref), one a line.
dash_prs() { { grep -o 'https://github.com/[^/ ]*/[^/ ]*/pull/[0-9]*' || true; } | sed 's#.*/\([^/]*\)/pull/#\1\##'; }

# dash_box <title> <frame> [rows] — the rows inside the frame's box of that title, the right border
# gone, each wrapped row (its later lines indented) joined back onto one line; with rows, every line
# as it is (the epics box indents its agent rows).
dash_box() {
  awk -v t="$1" -v rows="${3:-}" '/^╭─ / { on = index($0, "╭─ " t " ") == 1; next } /^╰/ { on = 0 } !on { next }
    { sub(/ *│$/, "") } /^│   / && n && !rows { sub(/^│ */, ""); r[n] = r[n] " " $0; next } { r[++n] = $0 }
    END { for (i = 1; i <= n; i++) print r[i] }' <<< "$2"
}

# dash_finished — "finished<TAB>epic<TAB>count" per epic, from the board's own repo (none when the
# board is not in git). A finished story's file is deleted, so these are the story files deleted on
# the first-parent history of that repo's base branch and HEAD: one git log, names only, commits split
# on NUL (no diff text, so diff.noprefix or color settings cannot change it), each deleted file read
# from the parent's tree by one git cat-file --batch, its keys from the front matter only. A slug is
# counted once, and not at all while its file is on the board here (an unpulled checkout, or a slug
# added again): it is open. It counts when any of its deletions closed the story: the deleting commit
# names story/<slug> (its own PR's merge), or is the story's own work (it also changes a file that is
# not the board's own (its stories/, epics/, hld/, .obsidian/, Board.base and README.md) nor a repo-root *.md, and its
# subject names no board/, close/ or epic/ branch: a squash-merged story PR, whose work may sit beside
# the board, as docs/operations.md does), the swarm finished it (finish, or reconcile "finished", in events.tsv), or
# the deleted file's last status was done or review (reconcile finishes only items in review) or it
# listed prs. A re-scope (a board/ PR, or a commit that edits only the board and root notes such as
# STATUS.md) has none of these, so it counts as nothing. An after: story (waits_on_epic, on the deleted
# version's front matter) never counts in its epic.
dash_finished() {
  local prefix tag epic kind after
  prefix="$(git -C "${BOARD}" rev-parse --show-prefix 2>/dev/null)" || return 0
  { python3 "${SWARM_HOME}/bin/lib/dash_finished.py" "${BOARD}" "${prefix}" "$(dash_base_ref "${BOARD}")" "${EVENTS_LOG}" 2>/dev/null || true; } \
    | while IFS=$'\t' read -r tag epic kind after; do
        if [[ "${tag}" == story ]] && ! waits_on_epic "${kind}" "${after}" "${epic}"; then printf '%s\n' "${epic}"; fi
      done | sort | uniq -c | awk '{ print "finished\t" $2 "\t" $1 }'
}

# dash_watch <seconds> <tty> — rebuild the frame every <seconds>, and repaint only when it changed;
# when only the clock moved, just the header line is rewritten. On a terminal it draws on the
# alternate screen with the cursor hidden, re-measures every frame, reads q (quit), r (redraw), t
# (the tree) and l (the ladder) without blocking, and redraws within a second of a resize (bash
# 3.2's read -t is not cut short by SIGWINCH, so it waits in one-second steps). Off a terminal it
# prints each changed frame, plain. Each frame has a deadline of its own (dash_deadline), so the first
# is drawn from what its reads gave by then.
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
    dash_deadline
    # The cache file decides whether this asks gh again; each project's own dash runs it for itself.
    [[ ${#DASH_DIRS[@]} -gt 0 ]] || dash_slow
    # A failed render shows its error in the frame and the loop carries on: a watch must not die quietly.
    if ! tpl="$(DASH_CLOCK=HH:MM:SS DASH_KEYS="${tty}" dash_frame 2>&1)"; then
      # Keep the error line on screen: cut the rest to one line short of the terminal's height.
      [[ ${tty} == 0 || ${DASH_H} -lt 2 ]] || tpl="$(head -n $((DASH_H - 1)) <<< "${tpl}")"
      tpl+=$'\n'"(dash: this render failed; retrying in ${every}s)"
      run_time_drop   # a watch whose first frame failed logs no row, as a run that fails logs none
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
    run_time_end   # the watch's row times its first frame only
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

# gh_installed — true when a gh other than bin/gh-shim's is on PATH: the shim is always there (swarm.sh
# puts it first), and with no real gh behind it every call it makes fails with 127.
gh_installed() {
  local d dirs
  IFS=: read -r -a dirs <<< "${PATH}"
  for d in ${dirs[@]+"${dirs[@]}"}; do [[ "${d%/}" == */gh-shim || ! -x "${d}/gh" || -d "${d}/gh" ]] || return 0; done
  return 1
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
# its step waits on, its first **You:** line's text, tab-separated, in one awk, then `after` for an
# after_story (state-aware, as next reads it), else empty. Who is `held` for a held story (held_for: too), `escalated` for an escalated story
# (escalated_from: set; is_escalated's other tests are dash's), which is the lead's whatever it says,
# else `you` for a **You:** step (it starts a line, after any list marker, or a sentence: prose that
# names the convention, "has no **You:** step", is no step), else empty. The text is what follows the
# first step's **You:**, tabs as spaces. The keys are read from the front matter only (a leading ---, up to the next; CRLF
# tolerated), by fm's rule: a key's first line wins, an empty value too. Then, as state_value reads
# them, the item's state file (state_path) wins for each of SET_FM_KEYS it has a line for, unless its
# <key>@base: line no longer matches the file's value. dash_finished's front() reads the front matter
# the same way; it reads deleted files only, so never a state file.
dash_fields() {
  state_path "$1"
  awk -v sf="${STATE_PATH}" -v keys=" ${SET_FM_KEYS} " 'function val(l, i) { l = substr(l, i + 1); sub(/^ +/, "", l); return l }
    { sub(/\r$/, "") }
    NR == 1 && $0 == "---" { n = 1; next }
    n == 1 && $0 == "---" { n = 2; next }
    n == 1 && (i = index($0, ":")) > 1 { if (!((k = substr($0, 1, i - 1)) in fv)) fv[k] = val($0, i); next }
    n != 1 && !y && match($0, /(^[[:space:]]*([-*] )?|[.!?] )\*\*You:\*\*/) {
      y = 1; yt = substr($0, RSTART + RLENGTH); gsub(/\t/, " ", yt); sub(/^ +/, "", yt); sub(/ +$/, "", yt) }
    n != 1 && !ht && sub(/^# /, "") { ht = 1; t = $0 }
    END { while (sf != "" && (getline l < sf) > 0) { sub(/\r$/, "", l)
        if ((i = index(l, ":")) > 1 && !((k = substr(l, 1, i - 1)) in sv)) sv[k] = val(l, i) }
      for (k in sv) if (index(keys, " " k " ") && (!((k "@base") in sv) || sv[k "@base"] == fv[k])) fv[k] = sv[k]
      x = fv["escalated_from"]
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s", fv["status"], fv["prs"], fv["epic"], fv["kind"], t,
        (x != "" ? (fv["held_for"] != "" ? "held" : "escalated") : (y ? "you" : "")), yt }' "$1"
  if after_story "$1"; then printf '\tafter'; else printf '\t'; fi
}

# dash_no_agent_at <no-agent lines> — "<slug>\t<time>" for each no-agent: line's story: the time of the
# event that explains its missing agent (no_agent_events' event: an ok close, a failed start or a
# no-agent line), which its row waits from.
dash_no_agent_at() {
  local slug name rname e rows=""
  while IFS= read -r slug; do
    [[ -n "${slug}" ]] || continue
    no_agent_name name "${slug}"; no_agent_name rname "review-${slug}"
    e="$(fm "${BOARD}/stories/${slug}.md" epic)"; rows+=" ${slug} ${name} ${rname} ${e:--}"
  done < <(sed -n 's/^no-agent: \([^,]*\), exit: .*/\1/p' <<< "$1")
  [[ -n "${rows}" ]] || return 0
  # shellcheck disable=SC2086 # rows: space-separated 4-tuples
  no_agent_events ${rows} | awk '$3 != "-" { print $1 "\t" $3 }'
}

# dash_no_agent <herdr agent list> [board] — set next_step's NO_AGENT_NOW (and NO_AGENT_SET) to the
# no-agent lines read from that list (no_agent_from), asked only while a story could have one (ready,
# or review under merge = agent); board is dash_render's rows, else the board is read. A story in review
# under merge = human whose HLD grants merge, which no_agent_lines gives a no-review: line, does not
# open that gate: with no other story that does, dash leaves its line out, and wait --lead shows it. Used by
# dash_render and by `_step --dash`, dash --check's next, which reads herdr's list as dash does,
# whenever herdr is on PATH, in a pane or not.
dash_no_agent() {
  local rows="${2:-}" f
  NO_AGENT_NOW=""
  # shellcheck disable=SC2034 # next_step (board.sh) reads it
  NO_AGENT_SET=1
  if [[ -z "${rows}" ]]; then
    while IFS= read -r f; do rows+="stories"$'\t'"x"$'\t'"$(fm "${f}" status)"$'\n'; done < <(board stories)
  fi
  # shellcheck disable=SC2154 # CFG_merge is assigned in another file
  awk -F'\t' -v m="${CFG_merge}" '$1 == "stories" && ($3 == "ready" || ($3 == "review" && m == "agent")) { f = 1; exit } END { exit !f }' <<< "${rows}" || return 0
  NO_AGENT_NOW="$(no_agent_from "$1")" || NO_AGENT_NOW=""
}

# dash_render — gather what the dashboard shows (read-only), then lay it out in python at DASH_W x
# DASH_H. herdr is asked whenever it is on PATH, inside a herdr pane or not: dash only reads. Claude
# Code's list of sessions is read once a frame (DASH_SESSIONS); with no claude, every recorded
# session is unknown. The reads cut or skipped (report_skipped: its own, dash_slow's, and the render's
# pane reads) are named on a line under the frame, which is laid out a line shorter to make room; a
# frame one line high has none to spare, and names none. The line is cut to DASH_W.
dash_render() {
  local agents="" panes="" workspaces="" sessions="" listed="" noagent="" noagent_at="" board="" granted="" hgrants=$'\n' policies="" merges="" drift="" commits="" waits="" afterdone="" buildable="" nx f d r x
  local testing="" p idle skipped="" more pass pending=0 out read_end lines="${DASH_H:-0}"
  # type -P: herdr on PATH, not dash_deadline's function of that name.
  if type -P herdr >/dev/null 2>&1; then
    # The lists status reads; the workspace list only labels the tree, so a failed one costs no agent.
    # listed keeps the agent list whatever the pane list does: no_agent_lines needs only that one.
    { agents="$(herdr agent list 2>/dev/null)" && listed="${agents}" && panes="$(herdr pane list 2>/dev/null)"; } || agents=""
    [[ -z "${agents}" ]] || workspaces="$(herdr workspace list 2>/dev/null)" || workspaces=""
  fi
  [[ -z "${agents}" ]] || sessions="$(claude_agents)" || sessions=""
  # One line per item: dir, slug, status, prs, its agent name, (an epic) its conductor's, epic, kind, title, you, its **You:** text, after (after_story).
  for d in hld epics stories; do
    while IFS= read -r f; do
      r="$(basename "${f}" .md)"; x="$(dash_fields "${f}")"
      board+="${d}"$'\t'"${r}"$'\t'"${x%%$'\t'*}"$'\t'"$(cut -f2 <<< "${x}")"$'\t'"$(agent_name "${r}")"$'\t'"$(agent_name "conduct-${r}")"$'\t'"$(cut -f3- <<< "${x}")"$'\n'
    done < <(board "${d}")
  done
  # With lead = session and merge = human, "<dir>\t<slug>" for each review item and each agreed HLD with
  # an open plan PR whose agreed HLD grants merge (item_hld, hld_grants): the lead merges those. From
  # board files alone, no gh, as dash runs every frame; a grants: line hld_grants refuses grants nothing.
  # hgrants: "<hld file>\t<1 or 0>" per HLD read, so items under one HLD read its grants once a frame.
  # shellcheck disable=SC2154 # assigned in another file
  if [[ "${CFG_lead}" == session && "${CFG_merge}" == human ]]; then
    while IFS=$'\t' read -r d r x; do
      if [[ "${d}" == hld ]]; then
        if [[ "${x}" == agreed ]] && hld_pr_open "${r}" plan; then f="${BOARD}/hld/${r}.md"; else continue; fi
      elif [[ "${x}" == review ]]; then f="$(item_hld "${BOARD}/${d}/${r}.md")"
      else continue; fi
      [[ -n "${f}" ]] || continue
      if [[ "${hgrants}" != *$'\n'"${f}"$'\t'* ]]; then   # loose-match: ok a whole hgrants line, a newline before the path and a tab after
        x="$(hld_grants "${f}" 2>/dev/null)" || x=""
        if [[ $'\n'"${x}"$'\n' == *$'\n'merge$'\n'* ]]; then x=1; else x=0; fi
        hgrants+="${f}"$'\t'"${x}"$'\n'
      fi
      if [[ "${hgrants}" == *$'\n'"${f}"$'\t'1$'\n'* ]]; then granted+="${d}"$'\t'"${r}"$'\n'; fi   # loose-match: ok a whole hgrants line, a newline before the path and a tab after
    done < <(cut -f1-3 <<< "${board}")
  fi
  # Each active epic with no stories whose depends_on still holds its planning up, as next reads it.
  while IFS= read -r f; do
    if x="$(epic_holding_deps "${f}")" && [[ -n "${x}" ]]; then waits+="$(basename "${f}" .md)"$'\t'"${x}"$'\n'; fi
    # An epic that counts as done with only after: stories open, as next reads it (epic_after_only).
    if epic_after_only "${f}"; then afterdone+="$(basename "${f}" .md)"$'\n'; fi
  done < <(board epics)
  # The stories next would start (buildable_story; a one-off not started), "<slug>\t<epic>": the idle gauge's.
  while IFS= read -r f; do
    buildable_story "${f}" || continue
    r="$(basename "${f}" .md)"; x="$(fm "${f}" epic)"
    if [[ -z "${x}" ]] && one_off_started "${r}"; then continue; fi
    buildable+="${r}"$'\t'"${x}"$'\n'
  done < <(board stories)
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
  # The lead's no-agent: lines (dash_no_agent), from this frame's herdr list, which next_step takes
  # too, so the Next row and the No agent rows agree. Read-only: it writes no events.tsv line.
  dash_no_agent "${listed}" "${board}"; noagent="${NO_AGENT_NOW}"
  [[ -z "${noagent}" ]] || noagent_at="$(dash_no_agent_at "${noagent}")"
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
  # The working agents past stall_minutes (dash_age's stalled_panes, the rows' own rule): a test suite
  # running under one's pane (test_running: herdr's process info, read here and never in the render,
  # and one ps read) is work, and the render shows it working (DASH_TESTING). An agent under
  # stall_minutes is never read; a read that fails leaves the agent stalled.
  # shellcheck disable=SC2154 # assigned in another file
  while IFS= read -r p; do
    [[ -z "${p}" ]] || ! test_running "${p}" < /dev/null || testing+=" ${p}"
  done < <(DASH_AGENTS="${agents}" DASH_PANES="${panes}" DASH_STATE="${STATE_DIR}" SWARM_OWN="$(own_panes)" DASH_BOARD="${board}" \
    DASH_COMMITS="${commits}" DASH_PRSTATE="${DASH_PRSTATE:-}" DASH_EVENTS="${EVENTS_LOG}" DASH_PROJECTS="${CLAUDE_PROJECTS}" \
    DASH_AGENTS_LOG="${AGENTS_LOG}" DASH_SESSIONS="${sessions}" DASH_STALL_MIN="${CFG_stall_minutes}" SWARM_LIB="${SWARM_HOME}/bin/lib" python3 -I -c '
import os, sys, time
sys.path.insert(0, os.environ["SWARM_LIB"]); from dash_age import stalled_panes
E = os.environ
print("\n".join(stalled_panes(E, float(E.get("SWARM_DASH_NOW") or time.time()))))' 2>/dev/null || true)
  # Taken whole, never through head: head exits after a line, and where SIGPIPE is ignored (CI) next's
  # second echo prints "Broken pipe" into the frame, now and then, so --watch sees a changed frame.
  nx="$(next_lines)" || true
  # next's idle: lines (idle_now), read each frame: board and state only, given the step next would
  # take, so the epic that step names gets no row.
  idle="$(idle_now "${nx%%$'\n'*}" 2>/dev/null)" || idle=""
  # The shell's reads are done; the render's own, each agent's pane for a usage-limit dialog (panes.py's
  # pane_text, under SWARM_REPORT_END), come inside the python below. The frame is laid out a line
  # shorter when a read was cut before the render (pending); when the render's own reads are the first
  # cut, it is drawn again a line shorter with no pane read at all (SWARM_REPORT_END=0: each is skipped
  # at once, so no pane is read twice in a frame), the states from herdr's list alone. A frame of one
  # line (DASH_H, a --project share) keeps its header, and names none: a two-line one gives its second
  # line to the names.
  [[ ! -s "${REPORT_SKIP_FILE:-/dev/null}" ]] || pending=1
  [[ ${pending} == 0 || ${lines} -le 1 ]] || lines=$((lines - 1))
  read_end="${SWARM_REPORT_END:-}"
  for pass in 1 2; do
  # An x after the frame keeps its trailing newlines through $( ); python's failure returns.
  # shellcheck disable=SC2154 # assigned in another file
  out="$(SWARM_REPORT_END="${read_end}" DASH_PROJECT="${PROJECT_DIR}" DASH_BACKLOG="$(conductor_name backlog)" DASH_VERSION="$(plugin_version < "${SWARM_HOME}/.claude-plugin/plugin.json")" \
  DASH_MERGE="${CFG_merge}" DASH_LEAD="${CFG_lead}" DASH_NEXT="${nx%%$'\n'*}" DASH_HELD="$(grep '^release-held: ' <<< "${nx}" || true)" DASH_IDLE="${idle}" DASH_BOARD="${board}" DASH_GRANTED="${granted}" DASH_POLICY="${policies}" \
  DASH_WAITING="$(waiting_on_user)" DASH_NO_AGENT="${noagent}" DASH_NO_AGENT_AT="${noagent_at}" DASH_EPIC_WAITS="${waits}" DASH_EPIC_DONE="${afterdone}" DASH_BUILDABLE="${buildable}" DASH_MERGES="${merges}" DASH_DRIFT="${drift}" \
  DASH_AGENTS="${agents}" DASH_PANES="${panes}" DASH_WORKSPACES="${workspaces}" DASH_STATE="${STATE_DIR}" DASH_BOARD_DIR="${BOARD}" \
  SWARM_OWN="$(own_panes)" DASH_COLS="${DASH_W:-100}" DASH_LINES="${lines}" \
  DASH_COLOR="${DASH_COLOR:-0}" DASH_FIT="${DASH_ENV_H:+1}" DASH_PRSTATE="${DASH_PRSTATE:-}" DASH_HEADS="${DASH_HEADS:-}" DASH_COST="${DASH_COST:-}" DASH_CI="${DASH_CI:-}" \
  DASH_FINISHED="${DASH_FINISHED:-}" DASH_TREE="${DASH_TREE:-0}" DASH_LADDER="${DASH_LADDER:-0}" \
  DASH_COMMITS="${commits}" DASH_STALL_MIN="${CFG_stall_minutes}" DASH_SESSIONS="${sessions}" DASH_TESTING="${testing}" \
  DASH_AGENTS_LOG="${AGENTS_LOG}" DASH_PROJECTS="${CLAUDE_PROJECTS}" DASH_FINDINGS="${PROJECT_DIR}/.swarm/${FINDINGS_LOG_NAME}" DASH_EVENTS="${EVENTS_LOG}" \
  DASH_BUILDERS="${BUILDER_ROLES}" DASH_INTERVENE_KINDS="${INTERVENE_KINDS}" DASH_ESCALATE_AFTER="${CFG_escalate_after}" DASH_CODEX_MIN="${CFG_codex_minutes}" SWARM_FINDING_REVIEWERS="${FINDING_REVIEWERS}" python3 "${SWARM_HOME}/bin/lib/dash_render.py" && echo x)" || return
  out="${out%x}"
  more="$(report_skipped)"; [[ -z "${more}" ]] || skipped="${more}"
  [[ ${pass} == 1 && ${pending} == 0 && -n "${skipped}" && ${lines} -gt 1 ]] || break
  lines=$((lines - 1)); pending=1; read_end=0
  done
  [[ ${DASH_H:-0} != 1 ]] || skipped=""
  # Cut to the width with …, as the legend is, so the line never wraps onto a second.
  if [[ ${#skipped} -gt ${DASH_W:-100} ]]; then skipped="${skipped:0:$((${DASH_W:-100} - 1))}…"; fi
  printf '%s' "${out}"
  [[ -z "${skipped}" ]] || echo "${skipped}"
}

# swarms — every swarm herdr runs on this machine, from its workspace, pane and agent lists, each
# read under REPORT_SECONDS (within): each workspace labelled `swarm-lead · <label>` as a project,
# headed by <label> and the lead's dir, then its workspaces, the lead's first, each with its agents'
# names (one herdr gives no name as `<pane> (no name)`). A pane's dir is its cwd taken up to the
# nearest folder with .claude/swarm/config, as lead_project finds the lead's project; one in a story
# worktree (<dir>-wt/<slug>, or a folder in it) is <dir>'s when <dir> has that config. The lead's dir
# is its first pane's. Another workspace is a project's when one of its panes' dirs is the lead's, or
# holds the lead's dir in its board (the last board_dir in its config: a board kept outside the
# repo, where the lead runs), or the project's lead-agents record (LEAD_AGENTS_RECORD) holds the
# workspace's id and label (its panes may all be in other repos' worktrees); and its label is
# `<part> · ...`, where <part> is the lead's <label>, the dir's name, or the dir's name and its own
# path_hash (project_label's forms). So never by a prefix of another project's label, nor by a dir
# name two projects share. A workspace no lead owns is left out, as is one an older swarm.sh labelled
# with no ` · `. Dies when herdr gives no workspace, pane or agent list in time, naming it, or one
# that is not JSON.
swarms() {
  local ws panes agents
  ws="$(swarms_read workspace)" || die "swarms: ${ws}"
  panes="$(swarms_read pane)" || die "swarms: ${panes}"
  agents="$(swarms_read agent)" || die "swarms: ${agents}"
  SWARM_WS="${ws}" SWARM_PANES="${panes}" SWARM_AGENTS="${agents}" SWARM_SEP="${WORKSPACE_SEP}" \
  SWARM_RECORD=".swarm/lead/${LEAD_AGENTS_RECORD}" python3 -I -c '
import functools, json, os, subprocess, sys
e = os.environ
sep = e["SWARM_SEP"]; lead = "swarm-lead" + sep
def items(name, key):
    try:
        return [x for x in json.loads(e[name])["result"][key] if isinstance(x, dict)]
    except (ValueError, KeyError, TypeError):
        sys.exit("swarm: swarms: herdr gave a %s list that is not JSON" % key[:-1])
def ws_of(x):
    return x.get("workspace_id") or (x.get("pane_id") or "").split(":")[0]
def config(d):
    return os.path.join(d, ".claude", "swarm", "config")
def up(d, found):
    while d not in ("", "/") and not found(d):
        d = os.path.dirname(d)
    return d if d not in ("", "/") else ""
@functools.lru_cache(maxsize=None)
def project(d):
    p = up(d, lambda p: os.path.isfile(config(p))) or up(d, lambda p: os.path.dirname(p).endswith("-wt")) or d
    main = os.path.dirname(p)[:-3]
    return main if os.path.dirname(p).endswith("-wt") and os.path.isfile(config(main)) else p
@functools.lru_cache(maxsize=None)
def board(d):
    b = ""
    try:
        with open(config(d)) as f:
            for k, _, v in (l.split("#", 1)[0].partition("=") for l in f):
                if k.strip() == "board_dir" and v.strip():
                    b = v.strip()
    except OSError:
        return ""
    if b == "~" or b.startswith("~/"):
        b = e.get("HOME", "") + b[1:]
    return b and os.path.realpath(os.path.join(d, b))
@functools.lru_cache(maxsize=None)
def path_hash(d):
    out = subprocess.run(["cksum"], input=d.encode(), stdout=subprocess.PIPE, check=True).stdout.split()
    return "%06x" % (int(out[0]) % 16777216)
def home(ld, d):
    b = board(d)
    return ld == d or bool(b) and (ld == b or ld.startswith(b + "/"))
def fits(part, own, d):
    base = os.path.basename(d)
    return part in (own, base) or part == base + "-" + path_hash(d)
workspaces = [w for w in items("SWARM_WS", "workspaces") if w.get("workspace_id")]
panes, agents = items("SWARM_PANES", "panes"), items("SWARM_AGENTS", "agents")
dirs, held = {}, {}
for p in panes:
    c = (p.get("cwd") or "").rstrip("/")
    if c:
        dirs.setdefault(ws_of(p), []).append(project(c))
for a in agents:
    if a.get("name") or a.get("pane_id"):
        held.setdefault(ws_of(a), []).append(a.get("name") or "%s (no name)" % a["pane_id"])
records = {}
for d in {d for ds in dirs.values() for d in ds}:
    try:
        with open(os.path.join(d, e["SWARM_RECORD"])) as f:
            for l in f:
                r = l.rstrip("\n").split("\t")
                if len(r) > 1:
                    records.setdefault(r[0], []).append((r[1], d))
    except OSError:
        pass
leads = [(w["workspace_id"], w["label"][len(lead):], (dirs.get(w["workspace_id"]) or [""])[0])
         for w in workspaces if (w.get("label") or "").startswith(lead)]
if not leads:
    print("no swarm runs here: herdr has no %s<project> workspace" % lead); sys.exit(0)
owned = {}
for w in workspaces:
    i, label = w["workspace_id"], w.get("label") or ""
    if label.startswith(lead) or sep not in label:
        continue
    part = label.split(sep, 1)[0]
    cands = dirs.get(i, []) + [d for l, d in records.get(i, []) if l == label]
    owner = next((li for d in cands for li, own, ld in leads if ld and fits(part, own, d) and home(ld, d)), None)
    if owner is not None:
        owned.setdefault(owner, []).append(w)
labels = {w["workspace_id"]: w.get("label") or "" for w in workspaces}
for i, own, d in leads:
    print("%s  %s" % (own, d or "(no pane)"))
    for w in [i] + [x["workspace_id"] for x in owned.get(i, [])]:
        print("  %s: %s" % (labels[w], ", ".join(held.get(w, [])) or "no agents"))'
}

# swarms_read <workspace|pane|agent> — herdr's <kind> list, cut at REPORT_SECONDS; prints why and
# fails when herdr gives none or the read was cut.
swarms_read() {
  local out rc=0
  out="$(within "${REPORT_SECONDS}" herdr "$1" list 2>/dev/null)" || rc=$?
  if (( rc == 142 )); then echo "herdr's $1 list was cut after ${REPORT_SECONDS} s"; return 1; fi
  (( rc == 0 )) || { echo "herdr gave no $1 list"; return 1; }
  printf '%s' "${out}"
}
