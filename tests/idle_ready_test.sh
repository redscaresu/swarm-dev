#!/usr/bin/env bash
# idle_ready_test.sh — next's idle ready line (touches_rows.py --idle): a ready story an agent builds,
# with no build started, ready past queue_minutes and clashing by part with no running build, gets
# `idle: <story> is ready with no build, exit: ...`, naming its running conductor's note, else
# swarm.sh story --strict; and commands/swarm.md quotes the line the check prints.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0
OLD=202001010000                               # touch -t: long past queue_minutes
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# board — a fresh project in CASE: story a, ready, touching x.sh:f run, its file dated OLD.
board() {
  CASE="$(mktemp -d "${ROOT}/case.XXXXXX")"
  mkdir -p "${CASE}/docs/stories" "${CASE}/docs/epics" "${CASE}/.swarm/board-state/stories" "${CASE}/repos"
  story a "status: ready" "touches: [x.sh:f run]"
}

# story <slug> <front-matter line>... — write a story file dated OLD.
story() {
  local f="${CASE}/docs/stories/$1.md"; shift
  { echo "---"; echo "kind: code"; printf '%s\n' "$@"; printf -- '---\n\n# story\n'; } > "${f}"
  touch -t "${OLD}" "${f}"
}

# event <command> <target> [time] — an ok events.tsv line, dated 2020 unless a time is given.
event() { printf '%s\t%s\t%s\t-\tok\n' "${3:-2020-01-01T00:00:00Z}" "$1" "$2" >> "${CASE}/.swarm/events.tsv"; }

idle() {
  SWARM_AGENT_KINDS="code docs chore" SWARM_QUEUE_MINUTES=30 python3 "${REPO}/bin/lib/touches_rows.py" \
    "${CASE}/docs/stories" --idle "${CASE}" "${CASE}/repos" "${CASE}/.swarm/board-state/stories"
}
LINE="idle: a is ready with no build, exit: swarm.sh story --strict a"

board
check "a ready story with no build past queue_minutes gives the line" "${LINE}" "$(idle)"

board; story b "status: review" "touches: [x.sh:f check]"
check "a ready story clashing by part with a story in review gives no line" "" "$(idle)"
board; story b "status: review" "touches: [x.sh:f check]"; story a "status: ready" "depends_on: [b]" "touches: [x.sh:f run]"
check "a story stacked on the clashing story in review leaves the line" "${LINE}" "$(idle)"
board; story b "status: review" "touches: [x.sh:g]"
check "a story in review on another part of the file leaves the line" "${LINE}" "$(idle)"
board; story b "status: ready" "touches: [x.sh:f check]"; mkdir -p "${CASE}-wt/b"
check "a ready story clashing with a ready one whose build started gives no line" "" "$(idle)"
board; story b "status: blocked" "held_by: a review" "touches: [x.sh:f check]"; mkdir -p "${CASE}-wt/b"
check "a ready story clashing with a held stacked story whose worktree exists gives no line" "" "$(idle)"
board; story b "status: ready" "touches: [x.sh:f check]"; touch "${CASE}/docs/stories/b.md"   # b: under queue_minutes
check "a clashing ready story whose build has not started leaves the line" "${LINE}" "$(idle)"

board; touch "${CASE}/docs/stories/a.md"
check "a story readied under queue_minutes ago gives no line" "" "$(idle)"
board; event unblock a "${NOW}"
check "a story unblocked under queue_minutes ago gives no line" "" "$(idle)"

board; mkdir -p "${CASE}-wt/a"
check "a story whose worktree exists (its build started) gives no line" "" "$(idle)"
board; git -C "${CASE}" init -q && git -C "${CASE}" -c user.name=t -c user.email=t -c commit.gpgsign=false commit -q --allow-empty -m init \
  && git -C "${CASE}" branch story/a
check "a story whose story/<slug> branch is left (build_exists) gives no line" "" "$(idle)"
board; event story a "${NOW}"
check "a story with a story event since it went ready gives no line" "" "$(idle)"

board; story a "status: ready" "epic: e" "touches: [x.sh:f run]"
printf -- '---\nstatus: draft\n---\n\n# e\n' > "${CASE}/docs/epics/e.md"
check "a story of an epic not yet active gives no line" "" "$(idle)"
printf -- '---\nstatus: active\n---\n\n# e\n' > "${CASE}/docs/epics/e.md"
check "a story of an active epic with no conductor running names swarm.sh story --strict" "${LINE}" "$(idle)"
event conduct e
check "a story of an active epic whose conductor runs names a note to it" \
  "idle: a is ready with no build, exit: swarm.sh tell conduct-e note <file>" "$(idle)"
event close conduct-e
check "a conductor closed since its start is not running" "${LINE}" "$(idle)"

event report e "2021-01-01T00:00:00Z"; event conduct e "2021-01-01T00:00:00Z"
check "a report and a restart in the same second leave the restarted conductor running" \
  "idle: a is ready with no build, exit: swarm.sh tell conduct-e note <file>" "$(idle)"

board; event conduct --backlog
check "a story with no epic names a note to the running backlog conductor" \
  "idle: a is ready with no build, exit: swarm.sh tell conduct-backlog note <file>" "$(idle)"

# swarm.md's next idle list quotes the line --idle prints, with <story> for the slug: compared with
# the line itself, as printed with no conductor running, not with LINE above.
board
# shellcheck disable=SC2016 # backticks are the Markdown's, never expanded
# `|| true`: with no such quote, grep's exit 1 under pipefail would end the script with no FAIL line.
quoted="$(grep -o '`idle: <story> is ready with no build[^`]*`' "${REPO}/commands/swarm.md" | head -1 | tr -d '`' || true)"
if [[ -z "${quoted}" ]]; then echo "FAIL commands/swarm.md quotes the line touches_rows.py prints: no \`idle: <story> is ready with no build ...\` quote in it"; fails=$((fails + 1))
else check "commands/swarm.md quotes the line touches_rows.py prints" "$(idle)" "${quoted//<story>/a}"; fi

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
