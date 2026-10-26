#!/usr/bin/env bash
# lead_handler_test.sh — every kind of line wait --lead prints has an arm in /swarm-dev:swarm's wait --lead
# handler (commands/swarm.md). For each kind on KINDS it builds a board that makes lead_queue print that
# kind, reads the queue once (`swarm.sh wait --lead 0`), and checks the line came out and that the handler
# names it as a backticked `<kind>: ` line. A kind on GAPS is a known gap, printed but not yet handled.
# gh is a stub answering a green head; herdr a stub listing no agent.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HOME_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWARM="${HOME_DIR}/bin/swarm.sh"
KINDS="held escalated merge kept no-agent"
GAPS="kept"   # kept-handler-arm adds its arm and takes it off this list
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; B="${P}/docs/stories"
H=1111111111111111111111111111111111111111; URL=https://github.com/na-owner/na-repo/pull/41
mkdir -p "${P}/.claude/swarm" "${B}" "${P}/.swarm/state" "${ROOT}/bin"
git -C "${P}" init -q

printf '#!/bin/sh\nH="%s"\n' "${H}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
case "$*" in
  "pr view"*) read -r _ || true; echo "${H}" ;;
  *check-runs*) echo '{"total_count":1,"check_runs":[{"name":"test","status":"completed","conclusion":"success","html_url":"u"}]}' ;;
  *status*) echo '{"total_count":0,"statuses":[]}' ;;
  *) exit 1 ;;
esac
STUB
cat > "${ROOT}/bin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[]}}' ;;
  *) echo '{"result":{}}' ;;
esac
STUB
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr"

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
story() { { echo ---; printf '%s\n' "${@:2}"; echo ---; echo; echo "# $1"; } > "${B}/$1.md"; }
ev() { printf '%s\t%s\t%s\t-\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "${3:-ok}" >> "${P}/.swarm/events.tsv"; }

# board <kind> — a board on which lead_queue prints a line of <kind>, and nothing else.
board() {
  rm -rf "${B:?}"/*.md "${P}/.swarm/events.tsv" "${P}/.swarm/lead" "${ROOT}/proj-wt"
  mkdir -p "${P}/.swarm/lead"; : > "${P}/.swarm/lead/seen"
  echo "merge = human" > "${P}/.claude/swarm/config"
  case "$1" in
    held) story s "kind: lead" "status: ready" "escalated_from: code" "held_for: paused" ;;
    escalated) story s "kind: lead" "status: ready" "escalated_from: code" ;;
    merge) story s "kind: code" "status: review" "prs: ${URL}" ;;
    kept) story s "kind: code" "status: review" "prs: ${URL}" "kept: 2026-10-25 close stalled (not reviewed)" ;;
    no-agent) story s "kind: code" "status: ready"; ev story s; mkdir -p "${ROOT}/proj-wt/s"; ev close s ;;
    *) echo "FAIL no board for kind ${1}: add one"; fails=$((fails + 1)) ;;
  esac
}

# The handler: the paragraph of commands/swarm.md that starts wait --lead beside the conductor's wait.
handler="$(awk '/also run `swarm.sh wait --lead`/ { s = 1 } s && /^[[:space:]]*$/ { exit } s' "${HOME_DIR}/commands/swarm.md")"
check "the wait --lead handler is found in commands/swarm.md" test -n "${handler}"

for kind in ${KINDS}; do
  board "${kind}"
  out="$(cd "${P}" && env -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" HERDR_ENV=1 bash "${SWARM}" wait --lead 0 2>&1)" || true
  check "wait --lead prints a ${kind}: line" grep -q "^${kind}: s" <<< "${out}"
  while IFS= read -r line; do
    [[ -n "${line}" && " ${KINDS} " != *" ${line%%: *} "* ]] || continue
    echo "FAIL wait --lead printed '${line%%: *}', a kind not on KINDS: add it, and an arm for it"; fails=$((fails + 1))
  done <<< "${out}"
  if [[ " ${GAPS} " == *" ${kind} "* ]]; then
    echo "gap  ${kind}: has no arm yet (GAPS)"
  else
    # shellcheck disable=SC2016 # the backtick is the Markdown's own
    check "the wait --lead handler has an arm for ${kind}: lines" grep -qF '`'"${kind}"': ' <<< "${handler}"
  fi
done

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
