#!/usr/bin/env bash
# board_state_readers_test.sh — dash and the touches check read a story's status from its state file
# in .swarm/board-state first: a story whose file says ready and whose state file says review shows
# in review in dash, and story --strict on another story touching the same file refuses naming it;
# with no state file both behave as before (story gets past the touches check to its next step, which
# fails here: the project has no origin). Only SET_FM_KEYS come from the state file. herdr is a stub
# on PATH that lists no agents and fails anything else.
set -euo pipefail

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
dash() { rm -f "${TMPDIR}"/swarm-dash-*; run "" dash; }
strict() { run 1 story --strict b; }

printf 'board_dir = board\n' > "${P}/.claude/swarm/config"; echo '# stories' > "${P}/board/stories/README.md"
item epics e1 "status: active"; item epics e2 "status: active"
item stories a "status: ready" "kind: code" "epic: e1" "touches: [bin/x.sh]"
item stories b "status: ready" "kind: code" "epic: e2" "touches: [bin/x.sh]"
git -C "${P}" init -q -b main

REFUSAL="b: a (epic e1) is open and touches bin/x.sh; start b after it merges"
out="$(dash)"; refused="$(strict)"
check "with no state file, dash shows a ready and story --strict b gets past the touches check" "yes|no|no|yes" \
  "$(has "○ e1  ░░░░░░░░░░░░  0/1   1 ready" "${out}")|$(has "1 review" "${out}")|$(has "${REFUSAL}" "${refused}")|$(
  has "cannot tell origin's default branch" "${refused}")"

printf 'status: review\nstatus@base: ready\n' > "${ST}/a"
out="$(dash)"; refused="$(strict)"
check "a's state file says review: dash shows it in review and story --strict b refuses naming a" "yes|yes" \
  "$(has "◐ e1  ░░░░░░░░░░░░  0/1   1 review" "${out}")|$(has "${REFUSAL}" "${refused}")"

# A later commit to a's file moves status off the state file's base: the file wins again.
item stories a "status: blocked" "kind: code" "epic: e1" "touches: [bin/x.sh]"
check "a's file changed status after the state was written: dash reads the file" "no" "$(has "1 review" "$(dash)")"

# A key outside SET_FM_KEYS in the state file is never read, as state_value never reads one.
printf 'epic: e2\n' > "${ST}/a"
check "an epic: line in a's state file leaves a in e1" "yes" "$(has "e1  ░░░░░░░░░░░░  0/1   1 blocked" "$(dash)")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
