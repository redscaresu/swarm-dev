#!/usr/bin/env bash
# events_tail_stall_test.sh — stall's and the finished-story count's events.tsv readers read the outcome
# through events_outcome.outcome(), so a key=value tail on column 5 changes nothing they print. Two
# stand-in projects hold the fixture plus a few synthetic rows (events_tail_helpers.sh), one with
# ` ~~ k=v` on every row. Over both, same_output compares stall.py's last_seen and finished.py's lines
# (board.sh's stories_finished, which next's epic_built reads). Each must be non-empty untailed, and
# the checks after them pin what it shows.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

export TMPDIR="${ROOT}/tmp"; mkdir -p "${TMPDIR}"

# The fixture has finish and reconcile lines; synthetic rows, after the fixture's newest, add two tell
# lines on zzrep that differ only in a tail the second has in both projects. They are zzrep's only
# lines, and zznotok's only line is a tell that failed, so last_seen has zzrep and not zznotok through
# sign_time's tell test alone.
EVENTS="${ROOT}/events.tsv"
cp "${EVENTS_FIXTURE}" "${EVENTS}"
{
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
  touch "${p}/docs/stories/README.md"
  item "${p}" epics/zzx.md 'status: active'
  # Stories that left the board in a bookkeeping commit: stories_finished counts each one events.tsv
  # finished (zzai's finish, zzd's and zzep's reconcile), not zzr, whose finish failed.
  for s in zzai zzd zzep zzr; do item "${p}" "stories/${s}.md" 'status: ready' 'epic: zzx'; done
  "${g[@]}" add docs && "${g[@]}" commit -qm board && "${g[@]}" rm -q docs/stories/zz{ai,d,ep,r}.md \
    && "${g[@]}" commit -qm "board: tidy" || return 1
}
if ! setup "${PLAIN}" || ! setup "${TAILED}" ' ~~ k=v'; then echo "FAIL could not set up the stand-in projects"; exit 1; fi

# The readers, each printing what it read, run in a project's directory.
last_seen() { python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from stall import last_seen
for k, t in sorted(last_seen(".swarm/events.tsv").items()): print(k, t)' "${LIB}"; }
finished() { python3 "${LIB}/finished.py" docs docs/ HEAD .swarm/events.tsv; }

check "stall.py's last_seen is the same with a tail" same_output "${PLAIN}" "${TAILED}" last_seen
check "finished.py's lines are the same with a tail" same_output "${PLAIN}" "${TAILED}" finished

# What each part shows untailed, so the comparisons above compare something.
out="$(cd "${PLAIN}" && finished)"
check "finished.py lists the three stories events.tsv finished, not zzr" test "$(sort <<< "${out}")" == "$(printf 'story\tzzx\t-\t-\nstory\tzzx\t-\t-\nstory\tzzx\t-\t-')"
out="$(cd "${PLAIN}" && last_seen)"
check "last_seen counts an ok tell line as a sign of life" grep -q '^zzrep ' <<< "${out}"
check "last_seen does not count a tell line that failed" lacks '^zznotok ' "${out}"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
