#!/usr/bin/env bash
# after_key_test.sh — a kind: lead story with after: <epic> does not hold its epic open: an epic whose
# only story is one counts as done in next, dash and status, and the story is still listed as a lead
# story. With the after: line removed, the epic is open in all three.
# A throwaway board: the active epic alpha, whose only story is the lead story check, and the active
# epic beta, which depends_on alpha. herdr and gh are stubbed to fail.
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
lacks() { ! grep -qF -- "$1" <<< "$2"; }

item() { # <path under docs> <front-matter line>...
  local path="${P}/docs/$1" title; shift
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

run() { # <command> — swarm.sh <command> in the project, outside herdr
  (cd "${P}" && rm -f "${TMPDIR}"/swarm-dash-* && env -u HERDR_ENV -u SWARM_PROJECT bash "${SWARM}" "$1" 2>&1) || true
}

mkdir -p "${P}/docs/stories" && git -C "${P}" init -q
echo "# Stories" > "${P}/docs/stories/README.md"   # dash reads a board only with it
item epics/alpha.md 'status: active'
item epics/beta.md 'status: active' 'depends_on: [alpha]'

# With after: alpha counts as done, so beta can be planned.
item stories/check.md 'status: ready' 'kind: lead' 'epic: alpha' 'after: alpha'
out="$(run next)"
check "next: an after: lead story leaves its epic done, so the epic after it is planned" test "${out%%$'\n'*}" = "plan-epic beta"
out="$(run status)"
check "status: an after: lead story leaves its epic done" has "plan-epic beta" "${out}"
check "status: the after: story is listed as a lead story" has "lead: check" "${out}"
out="$(run dash)"
check "dash: an epic with only an after: lead story has no open story" has "with no open story: alpha, beta" "${out}"
check "dash: the epic shows no ready story" lacks "1 ready" "${out}"
check "dash: the epic after it waits on nothing" lacks "waits on alpha" "${out}"
check "dash: the after: story is still listed for the lead" has "run lead story check" "${out}"
# A done story kept beside it does not hold alpha open either.
item stories/built.md 'status: done' 'kind: code' 'epic: alpha'
out="$(run next)"
check "next: a done story beside the after: story leaves its epic done" test "${out%%$'\n'*}" = "plan-epic beta"
rm "${P}/docs/stories/built.md"

# With beta gone, nothing is left but the lead's: next stops at the gate and lists check, and alpha,
# which has a story, is not planned again.
mv "${P}/docs/epics/beta.md" "${ROOT}/beta.md"
out="$(run next)"
check "next: the after: story is listed as a lead story" has "lead: check" "${out}"
check "next: the after: story's epic is not planned again" test "${out%%$'\n'*}" = "gate"
mv "${ROOT}/beta.md" "${P}/docs/epics/beta.md"

# Without after: the lead story holds alpha open, so beta waits and next stops at the gate.
item stories/check.md 'status: ready' 'kind: lead' 'epic: alpha'
out="$(run next)"
check "next: without after: the lead story holds its epic open" test "${out%%$'\n'*}" = "gate"
check "next: the gate lists it as a lead story" has "lead: check" "${out}"
out="$(run status)"
check "status: without after: the epic is open" lacks "plan-epic beta" "${out}"
check "status: without after: the story is listed as a lead story" has "lead: check" "${out}"
out="$(run dash)"
check "dash: without after: the epic has an open story" lacks "no open story: alpha" "${out}"
check "dash: without after: the epic shows its ready story" has "1 ready" "${out}"
check "dash: without after: the epic after it waits on it" has "waits on alpha" "${out}"

if [[ ${fails} -eq 0 ]]; then echo "all passed"; else echo "${fails} failed"; exit 1; fi
