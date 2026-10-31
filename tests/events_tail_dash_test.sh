#!/usr/bin/env bash
# events_tail_dash_test.sh — dash's and stall's events.tsv readers read the outcome through
# events_outcome.outcome(), so a key=value tail on column 5 changes nothing they print. Two stand-in
# projects hold the fixture plus a few synthetic rows (events_tail_helpers.sh), one with ` ~~ k=v` on
# every row. Over both, same_output compares stall.py's last_seen, dash_age.py's Signs (started, and
# ran by sign_time), dash_finished.py's lines, and what `swarm.sh dash` (dash_render.py) draws from
# them: the recent box, the running-now box, the speedometer and its interventions light, the
# escalated marks on two escalate agents' rows, a conductor's row under a name herdr cut, and an
# escalated lead story's reset hint. Each must be non-empty untailed, and the checks after them pin
# what it shows. The whole frame is not compared
# here: lifecycle.sh's no_agent_events still reads the raw column.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWARM="${HERE}/../bin/swarm.sh"
LIB="$(cd "${HERE}/../bin/lib" && pwd)"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
# shellcheck source=tests/events_tail_helpers.sh
. "${HERE}/events_tail_helpers.sh"
fails=0

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}
lacks() { ! grep -qE -- "$1" <<< "$2"; }

# The claude stub goes first on PATH, so no run here reaches the real claude; stty and tput fail, so
# the width is COLUMNS. herdr lists two working escalate agents; gh answers nothing.
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "${HERE}/claude_stub.sh" "${STUB_BIN}/claude"
for c in stty tput gh; do printf '#!/bin/sh\nexit 1\n' > "${STUB_BIN}/${c}"; done
cat > "${STUB_BIN}/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"zzak","agent_status":"working","pane_id":"w1:p1"},{"name":"zzesc","agent_status":"working","pane_id":"w1:p2"},{"name":"conduct-zzconductedepicwithalong","agent_status":"idle","pane_id":"w1:p3"}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w1:p1"},{"pane_id":"w1:p2"},{"pane_id":"w1:p3"}]}}' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "${STUB_BIN}"/*
echo '[]' > "${ROOT}/claude.json"
unset LINES
export PATH="${STUB_BIN}:${PATH}" CLAUDE_STUB_AGENTS="${ROOT}/claude.json" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TMPDIR="${ROOT}/tmp"
mkdir -p "${TMPDIR}" "${CLAUDE_PROJECTS_DIR}"

# The fixture has a step-up to fable (zzak), finish and reconcile lines and interventions, but no ok
# escalate build by attempt, no ok reset and no ok conduct of an epic off the board: synthetic rows
# add them, after the fixture's newest. That epic's conductor has a name herdr cut to 32 characters, so
# only its conduct line ties it to the epic, and to the report that marks it reported. Two tell lines
# on zzrep differ only in a tail the second has in both projects: recent shows them as one ×2 row.
# They are zzrep's only lines, and zznotok's only line is a tell that failed, so last_seen has zzrep
# and not zznotok through sign_time's tell test alone.
EVENTS="${ROOT}/events.tsv"
cp "${EVENTS_FIXTURE}" "${EVENTS}"
{
  printf '2026-10-29T01:30:00Z\tescalate\tzzesc\twa:pa\tok (attempt 3)\n'
  printf '2026-10-29T01:31:00Z\treset\tzzlead\twa:pa\tok\n'
  printf '2026-10-29T01:32:00Z\tconduct\tzzconductedepicwithalongname\twa:pa\tok\n'
  printf '2026-10-29T01:33:00Z\ttell\tzzrep\twa:pa\tok\n2026-10-29T01:34:00Z\ttell\tzzrep\twa:pa\tok ~~ n=2\n'
  printf '2026-10-29T01:35:00Z\ttell\tzznotok\twa:pa\tzznotok is still working\n'
} >> "${EVENTS}"
PLAIN="${ROOT}/plain/proj"; TAILED="${ROOT}/tailed/proj"
item() { # <project> <path under docs> <front-matter line>...
  local path="$1/docs/$2" title; shift 2
  title="$(basename "${path}" .md)"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}
setup() { # <project> [<tail>]
  local p="$1" g
  events_project "${p}" "${EVENTS}" "${2:-}" && g=(git -C "${p}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false) || return 1
  echo "lead = session" > "${p}/.claude/swarm/config"
  touch "${p}/docs/stories/README.md"
  item "${p}" epics/zzx.md 'status: active'
  item "${p}" stories/zzlead.md 'status: ready' 'kind: lead' 'escalated_from: fable'
  # Stories that left the board in a bookkeeping commit: dash_finished counts each one events.tsv
  # finished (zzai's finish, zzd's and zzep's reconcile), not zzr, whose finish failed.
  for s in zzai zzd zzep zzr; do item "${p}" "stories/${s}.md" 'status: ready' 'epic: zzx'; done
  "${g[@]}" add docs && "${g[@]}" commit -qm board && "${g[@]}" rm -q docs/stories/zz{ai,d,ep,r}.md \
    && "${g[@]}" commit -qm "board: tidy" || return 1
  mkdir -p "${p}/.swarm/state"
  printf 'w1:p1 zzak\nw1:p2 zzesc\n' > "${p}/.swarm/state/zzx"
  printf 'w1:p3 conduct-zzconductedepicwithalong\n' > "${p}/.swarm/state/zzconductedepicwithalongname"
  echo "# report" > "${p}/.swarm/conduct-zzconductedepicwithalongname.report.md"
  printf '2026-10-29\tescalate\tzzak\tclaude\tfable\txhigh\tsess-ak\n2026-10-29\tescalate\tzzesc\tclaude\tfable\txhigh\tsess-esc\n' > "${p}/.swarm/agents.tsv"
}
if ! setup "${PLAIN}" || ! setup "${TAILED}" ' ~~ k=v'; then echo "FAIL could not set up the stand-in projects"; exit 1; fi

# The readers, each printing what it read, run in a project's directory.
last_seen() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from stall import last_seen
for k, t in sorted(last_seen(".swarm/events.tsv").items()): print(k, t)' "${LIB}"; }
signs() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from dash_age import Signs
s = Signs(".swarm/events.tsv", {}, {}, "", 0)
for name, d in (("started", s.started), ("ran", s.ran)):
    for k, t in sorted(d.items()): print(name, k, t)' "${LIB}"; }
finished() { python3 "${LIB}/dash_finished.py" docs docs/ HEAD .swarm/events.tsv; }
# dash's frame at a fixed now, 2026-10-29 12:00 UTC (the fixture ends at 01:14, the synthetic rows at 01:35), drawn once for each
# project into the directory above it (a frame takes seconds), and the parts of it read from there.
# Each frame starts with no dash cache, and recent is compared on its newest 40 rows: the rows it gets
# are the height the frame leaves, which other parts set.
NOW="$(python3 -c 'import datetime; print(int(datetime.datetime(2026, 10, 29, 12, tzinfo=datetime.timezone.utc).timestamp()))')"
for p in "${PLAIN}" "${TAILED}"; do
  rm -rf "${TMPDIR}"/swarm-dash-*
  (cd "${p}" || exit 1; HERDR_ENV=1 SWARM_DASH_NOW="${NOW}" COLUMNS=120 LINES=200 bash "${SWARM}" dash > ../frame 2>/dev/null || true)
done
recent() { awk '/^╭─ recent/ { on = 1 } on && ++n <= 41 { print } on && /^╰/ { exit }' ../frame; }
running() { sed -n '/^╭─ running now/,/^╰/p' ../frame; }
speedometer() { grep -E '^[0-9.]+ merged/day|^! [0-9]+ interventions? in 7 days' ../frame; }
escalated() { grep -oE '(zzak|zzesc) .*(attempt [0-9]+|from [a-z]+) · [0-9:]+' ../frame; }
conductor() { grep -oE 'conduct-zzconducted[^ ]* .* w1:p3 in [^│]*[^ │]' ../frame; }
reset_hint() { grep -oE 'decide escalated story zzlead: [^│]*[^ │]' ../frame; }

check "stall.py's last_seen is the same with a tail" same_output "${PLAIN}" "${TAILED}" last_seen
check "dash_age.py's Signs (its starts and sign_time's panes) are the same with a tail" same_output "${PLAIN}" "${TAILED}" signs
check "dash_finished.py's lines are the same with a tail" same_output "${PLAIN}" "${TAILED}" finished
check "dash's recent box is the same with a tail" same_output "${PLAIN}" "${TAILED}" recent
check "dash's running-now box (Signs' starts) is the same with a tail" same_output "${PLAIN}" "${TAILED}" running
check "dash's speedometer is the same with a tail" same_output "${PLAIN}" "${TAILED}" speedometer
check "dash's escalated marks are the same with a tail" same_output "${PLAIN}" "${TAILED}" escalated
check "dash's row for a conductor under a cut name is the same with a tail" same_output "${PLAIN}" "${TAILED}" conductor
check "dash's reset hint for an escalated lead story is the same with a tail" same_output "${PLAIN}" "${TAILED}" reset_hint

# What each part shows untailed, so the comparisons above compare something.
out="$(cd "${PLAIN}" && finished)"
check "dash_finished.py lists the three stories events.tsv finished, not zzr" test "$(sort <<< "${out}")" == "$(printf 'story\tzzx\t-\t-\nstory\tzzx\t-\t-\nstory\tzzx\t-\t-')"
out="$(cd "${PLAIN}" && last_seen)"
check "last_seen counts an ok tell line as a sign of life" grep -q '^zzrep ' <<< "${out}"
check "last_seen does not count a tell line that failed" lacks '^zznotok ' "${out}"
out="$(cd "${PLAIN}" && signs)"
check "Signs counts zzak's step-up as its start" grep -q '^started zzak ' <<< "${out}"
out="$(cd "${PLAIN}" && speedometer)"
check "the speedometer counts the three finished stories" grep -q '^0\.4 merged/day' <<< "${out}"
check "the interventions light counts the fixture's lead-hand and user-caught lines" grep -qx '! 6 interventions in 7 days' <<< "${out}"
out="$(cd "${PLAIN}" && escalated)"
check "zzak's row shows the model it stepped up from" grep -q '^zzak .*from opus · ' <<< "${out}"
check "zzesc's row shows its attempt" grep -q '^zzesc .*attempt 3 · ' <<< "${out}"
check "an escalated lead story that was reset offers only drop" test "$(cd "${PLAIN}" && reset_hint)" == "decide escalated story zzlead: swarm.sh drop zzlead"
check "a conductor under a cut name is tied to its epic by its conduct line, and so reported" grep -qE 'reported +w1:p3 in - › zzconductedepicwithalongname' <<< "$(cd "${PLAIN}" && conductor)"
out="$(cd "${PLAIN}" && running)"
check "running now dates zzak from its step-up, not its agents.tsv day" grep -qE 'zzak +up 3d ' <<< "${out}"

# A recent line from a tailed row shows the outcome without the tail.
out="$(cd "${TAILED}" && recent)"
check "a tailed line in recent shows its outcome whole and no more" grep -qE '▲ escalate zzesc: ok \(attempt 3\) +wa:pa │$' <<< "${out}"
check "no recent line shows a tail" lacks '~~|k=v|n=2' "${out}"
check "recent folds lines that differ only in their tail into one row" grep -qE '· tell zzrep ×2 +wa:pa │$' <<< "${out}"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
