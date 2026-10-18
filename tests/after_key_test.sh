#!/usr/bin/env bash
# after_key_test.sh — a kind: lead story whose after: names its own epic does not count in it: an epic
# that had code stories planned, with only such a story open, counts as done in next, dash and
# status, and the story is still listed as a lead story. With the after: line removed, the epic is
# open in all three. An epic whose only story ever was an after: one is planned, never done.
# A throwaway board in git: the active epic alpha, whose stories are the lead story check and a code
# story, and the active epic beta, which depends_on alpha. herdr and gh are stubbed to fail.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
fails=0
P="${ROOT}/proj"
# The claude stub goes first on PATH, so no run here reaches the real claude.
mkdir -p "${ROOT}/stub-bin" "${ROOT}/tmp"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${ROOT}/stub-bin/claude"
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/stub-bin/herdr"
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/stub-bin/gh"
chmod +x "${ROOT}/stub-bin/herdr" "${ROOT}/stub-bin/gh"
export PATH="${ROOT}/stub-bin:${PATH}" TMPDIR="${ROOT}/tmp" CLAUDE_PROJECTS_DIR="${ROOT}/projects"
unset COLUMNS LINES

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}
has() { grep -qF -- "$1" <<< "$2"; }

item() { # <path under docs> <front-matter line>...
  local path="${P}/docs/$1" title; shift
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

run() { # <command> — swarm.sh <command> in the project, outside herdr
  (cd "${P}" && rm -f "${TMPDIR}"/swarm-dash-* && env -u HERDR_ENV -u SWARM_PROJECT bash "${SWARM}" "$1" 2>&1) || true
}
commit() { # <subject> — commit the whole board
  git -C "${P}" add -A && git -C "${P}" -c user.name=t -c user.email=t@example.com commit -qm "$1"
}
# first <output> — its first line: next's step.
first() { printf '%s\n' "${1%%$'\n'*}"; }
# step <status output> — the step under status's Next heading.
step() { sed -n '/^Next$/{n;s/^  //;p;}' <<< "$1"; }
# rows <dash frame> — its lines with box borders, the status symbol and progress bars cut, spaces
# squeezed. epic_line <dash frame> <epic> — the row of that epic; quiet <dash frame> — the line of the
# active epics with no open story.
rows() { sed 's/^[^a-z0-9]*//; s/ *│$//; s/█//g; s/░//g; s/  */ /g' <<< "$1"; }
epic_line() { rows "$1" | awk -v e="$2" '$1 == e' || true; }
quiet() { rows "$1" | grep -F "with no open story" || true; }

mkdir -p "${P}/docs/stories" && git -C "${P}" init -q
echo "# Stories" > "${P}/docs/stories/README.md"   # dash reads a board only with it
item epics/alpha.md 'status: active'
item epics/beta.md 'status: active' 'depends_on: [alpha]'

# alpha's code story is done and its after: story waits: alpha counts as done, so beta can be planned.
item stories/built.md 'status: done' 'kind: code' 'epic: alpha'
out="$(run next)"
check "next: with no after: story, a done code story alone still holds the epic after it" test "$(first "${out}")" = "done"
item stories/check.md 'status: ready' 'kind: lead' 'epic: alpha' 'after: alpha'
out="$(run next)"
check "next: an after: lead story leaves its epic done, so the epic after it is planned" test "$(first "${out}")" = "plan-epic beta"
out="$(run status)"
check "status: an after: lead story leaves its epic done" test "$(step "${out}")" = "plan-epic beta"
check "status: the after: story is listed as a lead story" has "lead: check" "${out}"
out="$(run dash)"
check "dash: the done epic's row names its after: story" test "$(epic_line "${out}" alpha)" = "alpha 1/1 after: check waits on the lead"
check "dash: the epic after it is with the epics with no open story" test "$(quiet "${out}")" = "1 active epic with no open story: beta"
check "dash: the after: story is still listed for the lead" has "run lead story check" "${out}"

# after: is read as a slug list: brackets, quotes, a comment, trailing spaces and a CR name alpha.
for v in '[alpha]' '"alpha"' 'alpha  # once the code is in' 'alpha   ' $'alpha\r'; do
  item stories/check.md 'status: ready' 'kind: lead' 'epic: alpha' "after: ${v}"
  out="$(run next)"
  check "next: after: ${v%$'\r'}$([[ "${v}" == *$'\r' ]] && echo ' (CRLF)') names its epic" test "$(first "${out}")" = "plan-epic beta"
done
item stories/check.md 'status: ready' 'kind: lead' 'epic: alpha' 'after: alpha'

# built merged and left the board; an earlier after: story of alpha finished too. History says alpha
# was planned, so it is still done, and dash counts only built as finished.
item stories/old-check.md 'status: review' 'kind: lead' 'epic: alpha' 'after: alpha'
commit "board"
git -C "${P}" rm -q docs/stories/built.md && commit "Merge pull request #1 from o/story/built"
git -C "${P}" rm -q docs/stories/old-check.md && commit "Merge pull request #2 from o/story/old-check"
out="$(run next)"
check "next: an epic whose code story finished and left the board is done" test "$(first "${out}")" = "plan-epic beta"
out="$(run dash)"
check "dash: a finished after: story is not counted in its epic" test "$(epic_line "${out}" alpha)" = "alpha 1/1 after: check waits on the lead"

# With beta gone, nothing is left but the lead's: next stops at the gate and lists check, and alpha,
# done, is not planned again.
mv "${P}/docs/epics/beta.md" "${ROOT}/beta.md"
out="$(run next)"
check "next: the after: story is listed as a lead story" has "lead: check" "${out}"
check "next: the after: story's done epic is not planned again" test "$(first "${out}")" = "gate"
mv "${ROOT}/beta.md" "${P}/docs/epics/beta.md"

# A draft or later epic is not planned, so an after: story never makes it done: beta waits.
for st in draft later; do
  item epics/alpha.md "status: ${st}"
  out="$(run next)"
  check "next: a ${st} epic with only an after: story holds the epic after it" test "$(first "${out}")" = "gate"
  check "next: a ${st} epic with only an after: story is still waiting on you" has "${st} epic: alpha" "${out}"
done
item epics/alpha.md 'status: active'

# An after: that names anything but the story's own epic is ignored: the story holds alpha open.
for v in beta tbd; do
  item stories/check.md 'status: ready' 'kind: lead' 'epic: alpha' "after: ${v}"
  out="$(run next)"
  check "next: after: ${v} (not its epic) holds its epic open" test "$(first "${out}")" = "gate"
done
out="$(run dash)"
check "dash: after: tbd (not its epic) shows the epic's ready story" test "$(epic_line "${out}" alpha)" = "alpha 1/2 1 ready"

# kind is read state-aware, as next reads it: a board-state kind: lead over the file's kind: code
# makes it an after: story, in next and in dash alike.
item stories/check.md 'status: ready' 'kind: code' 'epic: alpha' 'after: alpha'
mkdir -p "${P}/.swarm/board-state/stories" && echo 'kind: lead' > "${P}/.swarm/board-state/stories/check"
out="$(run next)"
check "next: a board-state kind: lead makes it an after: story" test "$(first "${out}")" = "plan-epic beta"
out="$(run dash)"
check "dash: a board-state kind: lead makes it an after: story" test "$(epic_line "${out}" alpha)" = "alpha 1/1 after: check waits on the lead"
rm -r "${P}/.swarm/board-state"

# Without after: the lead story holds alpha open, so beta waits and next stops at the gate.
item stories/check.md 'status: ready' 'kind: lead' 'epic: alpha'
out="$(run next)"
check "next: without after: the lead story holds its epic open" test "$(first "${out}")" = "gate"
check "next: the gate lists it as a lead story" has "lead: check" "${out}"
out="$(run status)"
check "status: without after: the epic is open" test "$(step "${out}")" = "gate"
check "status: without after: the story is listed as a lead story" has "lead: check" "${out}"
out="$(run dash)"
check "dash: without after: the epic shows its ready story" test "$(epic_line "${out}" alpha)" = "alpha 1/2 1 ready"
check "dash: without after: the epic after it waits on it" test "$(epic_line "${out}" beta)" = "beta – waits on alpha"

# A check story written before /plan-epic: gamma's only story ever is an after: one. gamma is planned,
# not done: delta waits, and unblock leaves a story that depends on gamma blocked.
rm "${P}"/docs/epics/*.md "${P}"/docs/stories/check.md
item epics/gamma.md 'status: active'
item epics/delta.md 'status: active' 'depends_on: [gamma]'
item stories/gcheck.md 'status: ready' 'kind: lead' 'epic: gamma' 'after: gamma'
item stories/waiter.md 'status: blocked' 'kind: code' 'depends_on: [gamma]'
out="$(run next)"
check "next: an epic whose only story is an after: one is planned" test "$(first "${out}")" = "plan-epic gamma"
out="$(run status)"
check "status: an epic whose only story is an after: one is planned" test "$(step "${out}")" = "plan-epic gamma"
out="$(run dash)"
check "dash: the epic after an epic with only an after: story waits on it" test "$(epic_line "${out}" delta)" = "delta – waits on gamma"
out="$(run unblock)"
check "unblock: a story that depends on an epic with only an after: story stays blocked" test "$(grep -c waiter <<< "${out}")" -eq 0
# Once gamma's code is planned and done, it is done: unblock readies the story.
item stories/gcode.md 'status: done' 'kind: code' 'epic: gamma'
out="$(run unblock)"
check "unblock: a story that depends on a done epic with an after: story is readied" has "waiter" "${out}"

if [[ ${fails} -eq 0 ]]; then echo "all passed"; else echo "${fails} failed"; exit 1; fi
