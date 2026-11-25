# shellcheck shell=bash
# diff_fixtures_resend.sh — tests/diff_run.sh's fixtures for resend_pass (bin/lib/lifecycle.sh), the
# wait --lead pass that submits a brief left unsent in an idle agent's box. Each runs one
# `swarm.sh wait --lead 0` poll in a project whose pane state lists its agents, with a herdr stub
# that answers the agent list, each pane read and each key press, and the real bin/lib/panes.py. So
# the rows the pass picks, the markers it removes, the panes it reads and the Enter it sends are
# compared between two trees: a base whose pass runs its inline Python program, and a head that runs
# the binary's _resend-rows entry. diff_run.sh sources this file, and every other
# tests/diff_fixtures_*.sh, by a glob; its header says what a fixture sets.
# shellcheck disable=SC2034 # diff_run.sh reads the FX_ settings

# RESEND_SESSION: the session id agents.tsv gives every agent, its log empty (no turn since the brief).
RESEND_SESSION=11111111-2222-3333-4444-555555555555
# RESEND_PASTE: a box that holds a collapsed paste, which panes.py's unsent_brief reads as a brief unsent.
RESEND_PASTE='╭───╮\n│ Claude Code │\n╰───╯\n\n────\n❯ [Pasted text #1 +40 lines]\n────\n'
# RESEND_CLEAR: a box with nothing in it.
RESEND_CLEAR='╭───╮\n│ Claude Code │\n╰───╯\n\n────\n❯ \n────\n'

# resend_project — an empty project with herdr's pane state, agents.tsv and its claude-projects folder,
# and the command: one wait --lead poll from the lead's pane (w:lead), through resend_poll. A fixture
# adds agents with resend_agent and lines with resend_event, then writes the stub with resend_stub.
# The tree's binary is built here, where a git checkout builds it, so the poll's own pass does not
# spend its read deadline (RESEND_PASS_WAIT) on the build.
resend_project() {
  P="${ROOT}/proj"
  mkdir -p "${P}/.claude/swarm" "${P}/docs/stories" "${P}/.swarm/state" "${P}/.swarm/lead" "${P}/.swarm/briefs" \
    "${ROOT}/claude-config/projects/proj" "${ROOT}/panes"
  git -C "${P}" init -q
  : > "${P}/.claude/swarm/config"; : > "${P}/.swarm/lead/seen"; : > "${P}/.swarm/state/tab"; : > "${P}/.swarm/events.tsv"
  : > "${ROOT}/claude-config/projects/proj/${RESEND_SESSION}.jsonl"
  RESEND_LIST=""
  # Two minutes ago, as an ISO stamp: after the session began, so no turn in it is since the line.
  RESEND_AT="$(python3 -I -c 'import time; print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 120)))')"
  # The backlog conductor's name holds a hash of the project's path, which differs between two runs:
  # resend_poll writes it as <backlog> in what the poll printed and wrote.
  RESEND_BACKLOG="conduct-backlog-proj-$(printf '%06x' $(( $(printf '%s' "$(cd "${P}" && pwd -P)" | cksum | cut -d' ' -f1) % 16777216 )))"
  bash -c 'source "$1/bin/lib/binary.sh" && binary_path "$1"' _ "${TREE}" > /dev/null 2>&1 || true
  resend_poll_script
  FX_CWD="${P}"; FX_HERDR="${ROOT}/herdr-stub"
  FX_ENV=("CLAUDE_PROJECTS_DIR=${ROOT}/claude-config/projects" HERDR_ENV=1 HERDR_PANE_ID=w:lead)
  FX_CMD=(bash "${ROOT}/poll.sh" "${TREE}/bin/swarm.sh" "${RESEND_BACKLOG}")
  FX_CALLS=("herdr agent list")
}

# resend_poll_script — write ${ROOT}/poll.sh <swarm.sh> <backlog name>: run `<swarm.sh> wait --lead 0`
# in the cwd and exit as it did, with its stdout, stderr and each file it left under .swarm/ passed
# through the same mask: the backlog name becomes <backlog>. It deletes .swarm/lead/events-at, whose
# events.tsv inode differs between two runs, and writes the epoch second that ends each line of
# .swarm/lead/stuck as <epoch>.
resend_poll_script() {
  cat > "${ROOT}/poll.sh" <<'POLL'
#!/usr/bin/env bash
mask() { B="$1" perl -pe 's/\Q$ENV{B}\E/<backlog>/g'; }
out="$(mktemp)"; err="$(mktemp)"; rc=0
bash "$1" wait --lead 0 > "${out}" 2> "${err}" || rc=$?
rm -f .swarm/lead/events-at
[[ ! -f .swarm/lead/stuck ]] || perl -pi -e 's/\t\d+$/\t<epoch>/' .swarm/lead/stuck
find .swarm -type f -exec env B="$2" perl -pi -e 's/\Q$ENV{B}\E/<backlog>/g' {} +
mask "$2" < "${out}"; mask "$2" < "${err}" >&2
rm -f "${out}" "${err}"
exit "${rc}"
POLL
}

# resend_agent <name> <pane> <status> <box> — an agent this project opened in <pane>, as herdr lists it
# with <status> (- for none: herdr lists it with no status), whose pane read gives <box> (printf text).
resend_agent() {
  printf '%s %s\n' "$2" "$1" >> "${P}/.swarm/state/tab"
  printf '2026-10-26\tcode\t%s\tclaude\topus\thigh\t%s\n' "$1" "${RESEND_SESSION}" >> "${P}/.swarm/agents.tsv"
  # shellcheck disable=SC2059 # <box> is printf text
  printf "$4" > "${ROOT}/panes/${2#w:}.txt"
  local s=""; [[ "$3" == - ]] || s=",\"agent_status\":\"$3\""
  RESEND_LIST="${RESEND_LIST:+${RESEND_LIST},}{\"name\":\"$1\",\"pane_id\":\"$2\"${s}}"
}

# resend_event <command> <target> [outcome] — an events.tsv line at RESEND_AT, ok unless given.
resend_event() { printf '%s\t%s\t%s\tw:lead\t%s\n' "${RESEND_AT}" "$1" "$2" "${3:-ok}" >> "${P}/.swarm/events.tsv"; }

# resend_marker <stem> <name> <pane> — an .unsent marker for <stem>, as unsent_marker writes it.
resend_marker() { printf '%s %s builder\npid 1\n' "$2" "$3" > "${P}/.swarm/briefs/$1.unsent"; }

# resend_stub [read-exit] — the herdr stub: the agent list resend_agent built, each pane's box for a
# read (or no text and exit <read-exit> for every read), and an empty result for anything else.
resend_stub() {
  { printf '#!/bin/sh\nR=%q; LIST=%q; READ=%q\n' "${ROOT}/panes" "{\"result\":{\"agents\":[${RESEND_LIST}]}}" "${1:-0}"
    cat <<'STUB'
case "$1 $2" in
  "agent list") printf '%s\n' "${LIST}" ;;
  "agent read") [ "${READ}" = 0 ] || exit "${READ}"; cat "${R}/${3#w:}.txt" ;;
  *) echo '{"result":{}}' ;;
esac
STUB
  } > "${ROOT}/herdr-stub"
  chmod +x "${ROOT}/herdr-stub"
}

# An idle builder with a new story delivery, its brief still a paste in its box and no turn since: the
# pass reads its pane once, sends Enter and logs the resend.
fx_resend_delivery() {
  resend_project
  resend_agent rsa w:p1 idle "${RESEND_PASTE}"
  resend_event story rsa
  resend_stub
  FX_CALLS+=("herdr agent read w:p1" "herdr pane send-keys w:p1")
}

# An idle builder whose story line is marked resent but not rechecked (after mode): the read after its
# Enter still finds the paste and no turn since, so the pass writes its .unsent marker.
fx_resend_after() {
  resend_project
  resend_agent rsb w:p1 idle "${RESEND_PASTE}"
  resend_event story rsb
  # As the poll that sent the Enter left it: pending, resent, then the line itself, and no rechecked.
  printf 'rsb\t%s\tstory\t1\t%s\n' "${RESEND_AT}" pending "${RESEND_AT}" resent > "${P}/.swarm/lead/resend"
  printf 'rsb\t%s\tstory\t1\n' "${RESEND_AT}" >> "${P}/.swarm/lead/resend"
  resend_stub
  FX_CALLS+=("herdr agent read w:p1")
}

# .unsent markers and no delivery: an idle agent's is kept and its pane read (the paste still there),
# a gone agent's (herdr lists no such agent in its pane) and a working agent's are removed unread.
fx_resend_markers() {
  resend_project
  resend_agent rsi w:p1 idle "${RESEND_PASTE}"
  resend_agent rsw w:p2 working "${RESEND_PASTE}"
  printf 'w:p3 rsg\n' >> "${P}/.swarm/state/tab"
  resend_marker rsi rsi w:p1; resend_marker rsw rsw w:p2; resend_marker rsg rsg w:p3
  resend_stub
  FX_CALLS+=("herdr agent read w:p1")
}

# A findings tell to an idle builder after its start: the tell is the newest delivery, its paste still
# in the box and no turn since, so the pass sends Enter. A note to it, and a tell that failed before
# sending, are passed over.
fx_resend_tell() {
  resend_project
  resend_agent rst w:p1 idle "${RESEND_PASTE}"
  resend_event story rst
  resend_event tell:findings rst
  resend_event tell:note rst
  resend_event tell:nudge rst "failed: no such pane"
  resend_stub
  FX_CALLS+=("herdr agent read w:p1" "herdr pane send-keys w:p1")
}

# The backlog conductor, started by conduct --backlog and idle with its brief a paste in its box.
# resend_busy skips a conductor while any swarm.sh next or merge runs on the machine, so ps here leaves
# those lines out: another swarm's merge on the same machine would skip it in one tree's run alone.
fx_resend_backlog() {
  resend_project
  mkdir -p "${ROOT}/bin"
  printf '#!/usr/bin/env bash\nset -o pipefail\n%q "$@" | awk %q\n' "$(command -v ps)" '!/\/swarm\.sh (next|merge)( |$)/' > "${ROOT}/bin/ps"
  chmod +x "${ROOT}/bin/ps"
  FX_ENV+=("PATH=${ROOT}/bin:${PATH}")
  resend_agent "${RESEND_BACKLOG}" w:p1 idle "${RESEND_PASTE}"
  resend_event conduct --backlog
  resend_stub
  FX_CALLS+=("herdr agent read w:p1" "herdr pane send-keys w:p1")
}

# herdr fails every pane read: an idle builder with a new delivery and an idle marked agent each get
# one read, and nothing is sent, recorded or removed.
fx_resend_read_fails() {
  resend_project
  resend_agent rsf w:p1 idle "${RESEND_PASTE}"
  resend_agent rsm w:p2 idle "${RESEND_PASTE}"
  resend_event story rsf
  resend_marker rsm rsm w:p2
  resend_stub 1
  FX_CALLS+=("herdr agent read w:p1" "herdr agent read w:p2")
}
