#!/usr/bin/env bash
# close_exact_tab_test.sh — close takes only the tab or pane .swarm/state records under the exact name
# it is given. Two names that share their first 32 characters (where herdr's agent names stop) never
# close each other's tab or pane, and a name with no exact record is refused, naming what shares its
# cut, with nothing closed. herdr is a stub on PATH: it lists the tabs in ${ROOT}/tabs ("<id> <label>"),
# the agents in ${ROOT}/agents ("<name> <pane>", idle) and the panes in ${ROOT}/panes ("<pane> <tab>"),
# and records each tab close in ${ROOT}/tabs-closed and each pane close in ${ROOT}/panes-closed.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"
mkdir -p "${P}/docs/stories" "${ROOT}/bin"
git -C "${P}" init -q
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'STUB'
case "$1 $2" in
  "tab list") awk 'BEGIN { printf "{\"result\":{\"tabs\":[" }
                   { printf "%s{\"tab_id\":\"%s\",\"label\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                   END { print "]}}" }' "$H/tabs" ;;
  "tab close") echo "$3" >> "$H/tabs-closed" ;;
  "agent list") awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                     { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                     END { print "]}}" }' "$H/agents" ;;
  "pane list") awk 'BEGIN { printf "{\"result\":{\"panes\":[" }
                    { printf "%s{\"pane_id\":\"%s\",\"tab_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                    END { print "]}}" }' "$H/panes" ;;
  "pane close") echo "$3" >> "$H/panes-closed" ;;
esac
STUB
chmod +x "${ROOT}/bin/herdr"
cp "$(dirname "${SWARM}")/../tests/claude_stub.sh" "${ROOT}/bin/claude"; chmod +x "${ROOT}/bin/claude"
close() { (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" close "$@" >"${ROOT}/close.out" 2>&1); }
name() { (cd "${P}" && bash "${SWARM}" _name "$1"); }
closed() { echo "$(paste -sd' ' - < "${ROOT}/tabs-closed")|$(paste -sd' ' - < "${ROOT}/panes-closed")"; }
# fixture <state-file> <lines>... — a fresh .swarm/state with each named record; nothing closed yet.
fixture() {
  rm -rf "${P}/.swarm/state"; mkdir -p "${P}/.swarm/state"
  : > "${ROOT}/tabs-closed"; : > "${ROOT}/panes-closed"
  while [[ $# -gt 0 ]]; do printf '%b\n' "$2" > "${P}/.swarm/state/$1"; shift 2; done
}

fails=0
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }

# Two plan tabs for long HLD names: both labels cut to the same 32 characters.
H=plan-2026-10-24-a-long-dated-hld; T1="${H}-one"; T2="${H}-two"
is "${T1} and ${T2} share their agent name" "${H}|${H}" "$(name "${T1}")|$(name "${T2}")"
printf '%s\n' "w:t1 ${T1}" "w:t2 ${T2}" "w:t3 e1" "w:t4 e2" > "${ROOT}/tabs"
printf '%s\n' "critic w:p1" "skeptic w:p2" > "${ROOT}/agents"
printf '%s\n' "w:p1 w:t1" "w:p2 w:t2" > "${ROOT}/panes"
fixture "${T1}" "w:p1 critic" "${T2}" "w:p2 skeptic"
rc=0; close "${T2}" || rc=$?
is "close ${T2} closes its own tab and leaves ${T1}'s tab and record" "0|w:t2||w:p1 critic" \
  "${rc}|$(closed)|$(cat "${P}/.swarm/state/${T1}" 2>/dev/null)"

fixture "${T1}" "w:p1 critic" "${T2}" "w:p2 skeptic"
close "${H}" || true
is "close ${H}, the cut both share, closes nothing and names both tabs" "||1|1" \
  "$(closed)|$(grep -c "no pane in .swarm/state is recorded as exactly ${H}, and tab ${T1}, tab ${T2} share its first 32 characters" "${ROOT}/close.out")|$(grep -c "^not closed: ${H}" "${ROOT}/close.out")"

# Two builders whose long slugs share their first 32 characters, in two epics' tabs; herdr knows
# only one of them by the cut name, as it holds that name now.
S=a-story-slug-that-runs-past-32-c; A="${S}-a"; B="${S}-b"
printf '%s\n' "$(name "${A}") w:p21" > "${ROOT}/agents"
printf '%s\n' "w:p10 w:t3" "w:p11 w:t3" "w:p20 w:t4" "w:p21 w:t4" > "${ROOT}/panes"
fixture e1 "w:p10 conductor\nw:p11 ${A}" e2 "w:p20 conductor\nw:p21 ${B}"
is "${A} and ${B} share their agent name" "${S}|${S}" "$(name "${A}")|$(name "${B}")"
# B's record comes second (e2), so a match on the cut name would find A's line first.
rc=0; close "${B}" || rc=$?
is "close ${B} closes its pane and leaves ${A}'s open and recorded" "0||w:p21|w:p10 conductor w:p11 ${A}" \
  "${rc}|$(closed)|$(paste -sd' ' - < "${P}/.swarm/state/e1")"

# Its pane line gone (closed by hand): no exact record is left, so close refuses rather than take
# the pane herdr gives for the cut name, which is the other builder's.
fixture e1 "w:p10 conductor" e2 "w:p20 conductor\nw:p21 ${B}"
close "${A}" || true
is "close ${A}, with no record of its own, closes nothing and names ${B}" "||1|1" \
  "$(closed)|$(grep -c "recorded as exactly ${A}, and ${B} (pane w:p21 in tab e2) share its first 32 characters" "${ROOT}/close.out")|$(grep -c "^not closed: ${A}" "${ROOT}/close.out")"

if [[ ${fails} -ne 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
