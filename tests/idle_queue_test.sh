#!/usr/bin/env bash
# idle_queue_test.sh — next's idle: line reaches wait --lead, status and dash (idle_now). A blocked story
# whose dependency, still to build, shares no touches part with it gives the same idle: line in
# `swarm.sh wait --lead 0` (once: the next poll is quiet), in `swarm.sh status` and in dash. Once the
# dependency's PR merges and reconcile and unblock run, the line is gone from all three, and the story
# that merge readied, with no build, shows in status's next and in dash's idle gauge.
# gh is a stub answering the dependency's PR as merged; herdr a stub listing no agent; claude the
# shared stub.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWARM="${HOME_DIR}/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TMPDIR="${ROOT}/tmp"
P="${ROOT}/proj"; B="${P}/docs/stories"; URL=https://github.com/na-owner/na-repo/pull/7
LINE="idle: s waits on d but shares no touches part with it and needs nothing from it"
mkdir -p "${P}/.claude/swarm" "${B}" "${P}/.swarm/lead" "${ROOT}/bin" "${ROOT}/projects" "${TMPDIR}"
git -C "${P}" init -q
echo "merge = human" > "${P}/.claude/swarm/config"
: > "${B}/README.md"   # dash draws only a board init made
: > "${P}/.swarm/lead/seen"   # a lead that has read its queue before: wait --lead prints what is new
cp "${HOME_DIR}/tests/claude_stub.sh" "${ROOT}/bin/claude"

cat > "${ROOT}/bin/gh" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "pr view") echo '{"state":"MERGED"}' ;;
  *) exit 1 ;;
esac
STUB
cat > "${ROOT}/bin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[]}}' ;;
  "pane list") echo '{"result":{"panes":[]}}' ;;
  *) echo '{"result":{}}' ;;
esac
STUB
chmod +x "${ROOT}/bin/claude" "${ROOT}/bin/gh" "${ROOT}/bin/herdr"

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
story() { { echo ---; printf '%s\n' "${@:2}"; echo ---; echo; echo "# $1"; } > "${B}/$1.md"; }
run() { (cd "${P}" || exit 1; env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" HERDR_ENV=1 COLUMNS=120 bash "${SWARM}" "$@" 2>&1) || true; }
# count <text> <out> — how many lines of <out> hold <text>.
count() { grep -cF -- "$1" <<< "$2" || true; }

# s waits on d, which it shares no file with; d is still to build.
story s "kind: code" "status: blocked" "depends_on: [d]" "touches: [a.sh]"
story d "kind: code" "status: ready" "touches: [b.sh]"

out="$(run wait --lead 0)"
check "wait --lead prints the idle: line" grep -qxF "${LINE}" <<< "${out}"
check "wait --lead prints it once" test "$(count "${LINE}" "${out}")" = 1
out="$(run wait --lead 0)"
check "the next poll does not print it again" test "$(count "${LINE}" "${out}")" = 0
out="$(run status)"
check "status prints the idle: line under next" grep -qxF "  ${LINE}" <<< "${out}"
out="$(run dash)"
check "dash shows the idle: line" grep -qF "${LINE}" <<< "${out}"

# d's PR merges: reconcile takes it off the board, and unblock readies s, which has no build.
story d "kind: code" "status: review" "prs: ${URL}" "touches: [b.sh]"
run reconcile > /dev/null
run unblock > /dev/null
check "reconcile took d off the board" test ! -e "${B}/d.md"
out="$(run wait --lead 0)"
check "wait --lead no longer prints the idle: line" test "$(count "idle: " "${out}")" = 0
out="$(run status)"
check "status no longer prints the idle: line" test "$(count "idle: " "${out}")" = 0
check "status's next names s, readied by the merge" grep -qx "  story s" <<< "${out}"
out="$(run dash)"
check "dash no longer shows the idle: line" test "$(count "${LINE}" "${out}")" = 0
check "dash counts s as buildable, not started" grep -qF "idle: 1 buildable not started" <<< "${out}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
