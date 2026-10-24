#!/usr/bin/env bash
# close_exact_tab_test.sh — close takes only the tab or pane .swarm/state records under the exact name
# it is given. Two names that share their first 32 characters (where herdr's agent names stop) never
# close each other's tab or pane, and a name with no exact record is refused, naming what shares its
# cut, with nothing closed. herdr is a stub on PATH: it lists the tabs in ${ROOT}/tabs ("<id> <label>"),
# the agents in ${ROOT}/agents ("<name> <pane>", idle) and the panes in ${ROOT}/panes ("<pane> <tab>"),
# and records each tab close in ${ROOT}/tabs-closed and each pane close in ${ROOT}/panes-closed. gh is
# a stub too: pr list gives no PRs. The project has an empty bare origin.
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
git init -q --bare "${ROOT}/origin.git" && git -C "${P}" remote add origin "${ROOT}/origin.git"
cat > "${ROOT}/bin/gh" <<'STUB'
#!/bin/sh
case "$1 $2" in "pr list") echo "[]" ;; esac
STUB
chmod +x "${ROOT}/bin/gh"
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
  : > "${ROOT}/tabs-closed"; : > "${ROOT}/panes-closed"; : > "${P}/.swarm/events.tsv"
  while [[ $# -gt 0 ]]; do printf '%b\n' "$2" > "${P}/.swarm/state/$1"; shift 2; done
}

fails=0
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }

# refused <name> <found> — close <name> as a refusal reads: its exit, what it closed, a refusal
# naming <found> as sharing its cut, any not closed: line, and main's log line for it (ok or the refusal).
refused() {
  local rc=0; close "$1" || rc=$?
  echo "${rc}|$(closed)|$(grep -cF "swarm: close: nothing in .swarm/state is recorded as $1, and $2 share its first 32 characters" "${ROOT}/close.out")|$(grep -c '^not closed:' "${ROOT}/close.out")|$(grep -cF $'\tclose\t'"$1"$'\tw:me\tok' "${P}/.swarm/events.tsv")|$(grep -cF $'\tclose\t'"$1"$'\tw:me\tclose: no pane was closed for '"$1" "${P}/.swarm/events.tsv")"
}
REFUSED="1|||1|0|0|1"

# Two plan tabs for long HLD names: both labels cut to the same 32 characters.
H=plan-2026-10-24-a-long-dated-hld; T1="${H}-one"; T2="${H}-two"
is "${T1} and ${T2} share their agent name" "${H}|${H}" "$(name "${T1}")|$(name "${T2}")"
printf '%s\n' "w:t1 ${T1}" "w:t2 ${T2}" "w:t3 e1" "w:t4 e2" "w:t5 e3" > "${ROOT}/tabs"
printf '%s\n' "critic w:p1" "skeptic w:p2" > "${ROOT}/agents"
printf '%s\n' "w:p1 w:t1" "w:p2 w:t2" "w:p3 w:t5" > "${ROOT}/panes"
fixture "${T1}" "w:p1 critic" "${T2}" "w:p2 skeptic"
rc=0; close "${T2}" || rc=$?
is "close ${T2} closes its own tab and leaves ${T1}'s tab and record" "0|w:t2||w:p1 critic" \
  "${rc}|$(closed)|$(cat "${P}/.swarm/state/${T1}" 2>/dev/null)"

# herdr lists an agent under the cut both share, in T1's pane: it is never taken for T2's.
printf '%s\n' "${H} w:p1" "skeptic w:p2" > "${ROOT}/agents"
fixture "${T1}" "w:p1 critic" "${T2}" "w:p2 skeptic"
rc=0; close "${T2}" || rc=$?
is "close ${T2}, herdr listing ${H} in ${T1}'s pane, leaves that pane and ${T1}'s record" "0|w:t2||w:p1 critic" \
  "${rc}|$(closed)|$(cat "${P}/.swarm/state/${T1}" 2>/dev/null)"
printf '%s\n' "critic w:p1" "skeptic w:p2" > "${ROOT}/agents"

# T2's own tab record wins over a pane line elsewhere that shares the cut.
fixture "${T1}" "w:p1 critic" "${T2}" "w:p2 skeptic" e3 "w:p3 ${H}-x"
rc=0; close "${T2}" || rc=$?
is "close ${T2}, a pane line ${H}-x in tab e3 sharing its cut, still closes its own tab" "0|w:t2||w:p1 critic|w:p3 ${H}-x" \
  "${rc}|$(closed)|$(cat "${P}/.swarm/state/${T1}" 2>/dev/null)|$(cat "${P}/.swarm/state/e3" 2>/dev/null)"

fixture "${T1}" "w:p1 critic" "${T2}" "w:p2 skeptic"
is "close ${H}, the cut both share, fails, closes nothing, names both tabs, and main logs the refusal" "${REFUSED}" \
  "$(refused "${H}" "tab ${T1}, tab ${T2}")"
# The cut start_agent and herdr print is no record's name, even with one record to match it.
fixture "${T1}" "w:p1 critic"
is "close ${H}, with ${T1} the one record sharing it, is refused too" "${REFUSED}" "$(refused "${H}" "tab ${T1}")"

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
is "close ${A}, with no record of its own, fails, closes nothing, names ${B}, and main logs the refusal" "${REFUSED}" \
  "$(refused "${A}" "${B} (pane w:p21 in tab e2)")"

# A file in .swarm/state that is no tab record (a brief) is never taken for one, cut or not.
: > "${ROOT}/agents"
fixture e1 "w:p10 conductor" "${S}-brief.md" "# The brief for ${S}-z\n\nRead the story first."
rc=0; close "${S}-z" || rc=$?
is "close ${S}-z, a brief ${S}-brief.md beside the records, is not refused and closes nothing" "0|||0" \
  "${rc}|$(closed)|$(grep -c 'nothing in .swarm/state is recorded' "${ROOT}/close.out")"

# Only the pane is refused: a story's board work goes on. A merged story's close, as reconcile runs it,
# exits 0, closes no pane, says why and is logged ok; a stalled --drop close of a ready one counts its
# attempt and clears its build. herdr's cut name is B's, so A's build reads as open (failed_build).
printf '%s\n' "$(name "${A}") w:p21" > "${ROOT}/agents"
story() { printf -- '---\nstatus: %s\nkind: code\n---\n\n# %s\n' "$2" "$1" > "${P}/docs/stories/$1.md"; rm -rf "${P}/.swarm/board-state"; }
story_close() {
  local rc=0; close "$@" || rc=$?
  echo "${rc}|$(closed)|$(grep -cF "swarm: close: nothing in .swarm/state is recorded as $1, and ${B} (pane w:p21 in tab e2) share" "${ROOT}/close.out")|$(grep -cF $'\tclose' "${P}/.swarm/events.tsv" | tr -d ' ')|$(grep -c $'\tok' "${P}/.swarm/events.tsv")"
}
story "${A}" review; fixture e1 "w:p10 conductor" e2 "w:p20 conductor\nw:p21 ${B}"; mkdir -p "${P}/.swarm/zdotdir/${S}"
is "close ${A}, its story merged and its record gone, closes no pane, says why, and goes on (exit 0, logged ok)" "0|||1|1|1" \
  "$(story_close "${A}")"
is "and leaves the ZDOTDIR of ${S}, the cut name ${B} holds" "kept" "$([[ -d "${P}/.swarm/zdotdir/${S}" ]] && echo kept || echo gone)"
story "${A}" ready; fixture e1 "w:p10 conductor" e2 "w:p20 conductor\nw:p21 ${B}"
is "close ${A} stalled --drop, its story ready and its record gone, closes no pane and counts its attempt" "0|||1|1|1|1" \
  "$(story_close "${A}" stalled --drop)|$(grep -c '^attempts: 1$' "${P}/.swarm/board-state/stories/${A}" 2>/dev/null)"
rm -f "${P}/docs/stories/${A}.md"

# A long builder whose record line has no name (an older record) is found by herdr's cut of its name;
# two herdr agents under that cut, on unnamed lines, are refused rather than one picked.
L=a-long-builder-slug-running-past-32-characters; LN="$(name "${L}")"
printf '%s\n' "w:t6 e5" >> "${ROOT}/tabs"; printf '%s\n' "w:p40 w:t6" "w:p41 w:t6" > "${ROOT}/panes"
printf '%s\n' "${LN} w:p40" > "${ROOT}/agents"; fixture e5 "w:p40\nw:p41"
rc=0; close "${L}" || rc=$?
is "close ${L}, its record line unnamed, closes the pane herdr lists as ${LN}" "0||w:p40" "${rc}|$(closed)"
printf '%s\n' "${LN} w:p40" "${LN} w:p41" > "${ROOT}/agents"; fixture e5 "w:p40\nw:p41"
rc=0; close "${L}" || rc=$?
is "close ${L}, herdr listing ${LN} on both unnamed panes, fails and closes neither" "1|||1" \
  "${rc}|$(closed)|$(grep -cF "herdr lists more than one agent as ${LN}" "${ROOT}/close.out")"

# A long epic's conductor with no brief left (conduct_epic gives the cut): its epic's tab is found
# from the one record whose conductor name is its own, and closes.
E=aws-layer3-claim-sweep-reaper-long-epic; C="$(name "conduct-${E}")"
printf '%s\n' "w:t7 ${E}" >> "${ROOT}/tabs"; printf '%s\n' "w:p50 w:t7" "w:p51 w:t7" > "${ROOT}/panes"
printf '%s\n' "${C} w:p50" "s9 w:p51" > "${ROOT}/agents"; fixture "${E}" "w:p50 conductor\nw:p51 s9"
rc=0; close "${C}" || rc=$?
is "close ${C}, no brief left, closes its epic ${E}'s tab" "0|w:t7|" "${rc}|$(closed)"

# A record mid-rewrite (record_drop's .tmp) is no tab of its own.
printf '%s\n' "critic w:p1" "skeptic w:p2" > "${ROOT}/agents"
fixture "${T1}" "w:p1 critic" "${T1}.tmp" "w:p1 critic" "${T2}" "w:p2 skeptic"
is "close ${H}, ${T1}.tmp beside ${T1}, names ${T1} and ${T2} only" "${REFUSED}" "$(refused "${H}" "tab ${T1}, tab ${T2}")"

if [[ ${fails} -ne 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
