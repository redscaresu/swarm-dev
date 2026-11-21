#!/usr/bin/env bash
# board_state_readers_test.sh — status, wait --lead and the touches check read a story's status from its
# state file in .swarm/board-state first: a story whose file says ready and whose state file says review,
# with a PR, waits on your merge in status, and story --strict on another story touching the same file
# refuses naming it; with no state file both behave as before (status names it ready, and story gets
# past the touches check to its next step, which fails here: the project has no origin). kind,
# escalated_from and held_for come from it too (wait --lead's queue shows an escalated and a held story).
# herdr is a stub on PATH that lists no agents and fails anything else.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
fails=0
P="${ROOT}/proj"; ST="${P}/.swarm/board-state/stories"
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TMPDIR="${ROOT}/tmp"
mkdir -p "${P}/.claude/swarm" "${P}/board/stories" "${P}/board/epics" "${ST}" "${TMPDIR}" "${ROOT}/bin"
# The claude stub goes first on PATH, so no run here reaches the real claude.
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${ROOT}/bin/claude"
cat > "${ROOT}/bin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in "agent list") echo '{"result":{"agents":[]}}' ;; *) exit 1 ;; esac
STUB
chmod +x "${ROOT}/bin/herdr"

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo no; fi; }
item() { { echo ---; printf '%s\n' "${@:3}"; echo ---; echo; echo "# $2"; } > "${P}/board/$1/$2.md"; }
run() { # <HERDR_ENV> <swarm.sh args...>
  local h="$1"; shift
  (cd "${P}" && env -u SWARM_PROJECT HERDR_ENV="${h}" PATH="${ROOT}/bin:${PATH}" COLUMNS=100 bash "${SWARM}" "$@" 2>&1) || true
}
status() { run "" status; }
lead() { mkdir -p "${P}/.swarm/lead"; : > "${P}/.swarm/lead/seen"; run "" wait --lead 0; }   # a lead that has read its queue: it prints what is new
strict() { run 1 story --strict b; }

printf 'board_dir = board\n' > "${P}/.claude/swarm/config"; echo '# stories' > "${P}/board/stories/README.md"
item epics e1 "status: active"; item epics e2 "status: active"
item stories a "status: ready" "kind: code" "epic: e1" "touches: [bin/x.sh]"
item stories b "status: ready" "kind: code" "epic: e2" "touches: [bin/x.sh]"
item stories c "status: ready" "kind: code"; item stories d "status: ready" "kind: code"
git -C "${P}" init -q -b main

REFUSAL="b: a (epic e1) is open and touches bin/x.sh; start b after it merges"
MERGE="awaiting your merge: a https://github.com/o/r/pull/7"
out="$(status)"; refused="$(strict)"
check "with no state file, status names a ready and story --strict b gets past the touches check" "yes|no|no|yes" \
  "$(has "a is ready in the active epic e1" "${out}")|$(has "${MERGE}" "${out}")|$(has "${REFUSAL}" "${refused}")|$(
  has "cannot tell origin's default branch" "${refused}")"

printf 'status: review\nstatus@base: ready\nprs: https://github.com/o/r/pull/7\nprs@base:\n' > "${ST}/a"
printf 'kind: lead\nkind@base: code\nescalated_from: code\nescalated_from@base:\n' > "${ST}/c"
cp "${ST}/c" "${ST}/d"; printf 'held_for: paused\nheld_for@base:\n' >> "${ST}/d"
out="$(status)"; refused="$(strict)"
check "a's state file says review and lists a PR: status has it wait on your merge, and story --strict b refuses naming a" "yes|yes" \
  "$(has "${MERGE}" "${out}")|$(has "${REFUSAL}" "${refused}")"
out="$(lead)"
check "c's state file escalates it (kind: lead, escalated_from:): the lead's queue shows it" "yes" "$(has "escalated: c" "${out}")"
check "d's state file holds it (held_for:): the lead's queue shows it held" "yes" "$(has "held: d (paused)" "${out}")"

# A later commit to a's file moves status off the state file's base: the file wins again.
item stories a "status: blocked" "kind: code" "epic: e1" "touches: [bin/x.sh]"
out="$(run "" status --all)"
check "a's file changed status after the state was written: status reads the file" "no|yes" \
  "$(has "${MERGE}" "${out}")|$(has "blocked: a" "${out}")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
