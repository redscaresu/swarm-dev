#!/usr/bin/env bash
# name_cut_test.sh — herdr lists an agent by its name cut at 32 characters (agent_name), and close
# maps a cut back to a full name only through cut_record: the one name the records hold under it (tab
# records' pane names, briefs, stories). Names that share their first 32 characters share the cut,
# so the checks have two: closing one never closes the other's pane, a tab close names a story from
# the cut only when it is the one name there (live_agents), and closing a conductor by a cut two
# epics' briefs share takes neither epic and is refused while herdr lists it live (close_epic). Those
# checks fail with cut_record swapped for a prefix match, which takes the first name under the cut.
# The rest pin what an exact match leaves open: own_pane never maps a long name to a pane by herdr's
# cut, and the one name under a cut counts only as a story's in a tab close or a conductor's in
# close_epic. herdr is a stub on PATH: it lists the tabs in ${ROOT}/tabs ("<id> <label>"), the agents
# in ${ROOT}/agents ("<name> <pane> [status]", idle by default) and the panes in ${ROOT}/panes ("<pane>
# <tab>"), and records each tab close in ${ROOT}/tabs-closed and each pane close in
# ${ROOT}/panes-closed. gh is a stub too: pr list gives the heads of ${ROOT}/prs.json's open PRs, or
# none. The project has an empty bare origin.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

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
cat > "${ROOT}/bin/gh" <<STUB
#!/bin/sh
case "\$1 \$2" in
  "pr list") python3 -c 'import json, sys; [print(p["headRefName"]) for p in json.load(open(sys.argv[1])) if p["state"] == "OPEN"]' "${ROOT}/prs.json" 2>/dev/null || true ;;
esac
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
                     { printf "%s{\"name\":\"%s\",\"agent_status\":\"%s\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, (NF > 2 ? $3 : "idle"), $2 }
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
# fixture <tabs> <panes> <agents> [<state-file> <lines>]... — herdr's lists ("<a>;<b>" for two lines,
# "" for no agent) and a fresh .swarm/state, briefs, stories and events, with nothing closed and no
# PR open yet.
fixture() {
  tr ';' '\n' <<< "$1" > "${ROOT}/tabs"; tr ';' '\n' <<< "$2" > "${ROOT}/panes"
  if [[ -n "$3" ]]; then tr ';' '\n' <<< "$3" > "${ROOT}/agents"; else : > "${ROOT}/agents"; fi; shift 3
  rm -rf "${P}/.swarm/state" "${P}/.swarm/briefs" "${P}/docs/stories"; mkdir -p "${P}/.swarm/state" "${P}/.swarm/briefs" "${P}/docs/stories"
  : > "${ROOT}/tabs-closed"; : > "${ROOT}/panes-closed"; : > "${P}/.swarm/events.tsv"; echo '[]' > "${ROOT}/prs.json"
  while [[ $# -gt 0 ]]; do printf '%b\n' "$2" > "${P}/.swarm/state/$1"; shift 2; done
}
brief() { : > "${P}/.swarm/briefs/$1.md"; }
story() { printf -- '---\nstatus: review\nkind: code\n---\n\n# %s\n' "$1" > "${P}/docs/stories/$1.md"; }
open_pr() { echo '[{"number":7,"state":"OPEN","url":"https://github.com/o/p/pull/7","headRefName":"story/'"$1"'"}]' > "${ROOT}/prs.json"; }

fails=0
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }

# Two slugs that share their first 32 characters, S, the agent name herdr lists both under.
S=name-cut-two-slugs-sharing-32-ch; A="${S}-a"; B="${S}-b"
is "${A} and ${B} share their agent name ${S}" "${S}|${S}" "$(name "${A}")|$(name "${B}")"

# A's backlog tab (label A) holds a helper and, on an unnamed line (an older record), B's builder,
# which herdr lists under S. A's own pane line is gone, and both are stories, so the cut is A's and
# B's: close A takes neither that pane nor the tab, which keeps it.
fixture "w:t1 ${A}" "w:p10 w:t1;w:p11 w:t1" "helper w:p10;${S} w:p11" "${A}" "w:p10 helper\nw:p11"
story "${A}"; story "${B}"
rc=0; close "${A}" || rc=$?
is "close ${A}, herdr listing ${S} on an unnamed pane of its tab and both stories, closes neither the pane nor the tab" "0|||1" \
  "${rc}|$(closed)|$(grep -c "^kept ${S} (its story could not be found) in tab ${A}" "${ROOT}/close.out")"
# own_pane never takes a long name's pane by herdr's cut, even when A is the one name the records hold
# under it: B's builder, with no record of its own, may share it. Working on an unnamed line of A's
# tab, it keeps the tab; idle on an unnamed line of another tab, it keeps its pane.
fixture "w:t1 ${A};w:t2 other" "w:p10 w:t1;w:p11 w:t1;w:p21 w:t2" "helper w:p10;${S} w:p11 working;${S} w:p21" \
  "${A}" "w:p10 helper\nw:p11" other "w:p21"
brief "${A}"
rc=0; close "${A}" || rc=$?
is "close ${A}, the one name under ${S}, takes neither of herdr's ${S} panes, in its tab or another" "0|||1|w:p21" \
  "${rc}|$(closed)|$(grep -c "^kept ${S} (its story could not be found) in tab ${A}" "${ROOT}/close.out")|$(cat "${P}/.swarm/state/other" 2>/dev/null)"

# live_agents: epic e1's tab holds its conductor and, on a pane no record names, herdr's idle S. B's
# story has its PR open. With A and B both stories, or A a story and B only a brief (its story file
# gone at merge), S names no one story: the pane is kept and so is the tab.
kept_tab() {
  local rc=0; close conduct-e1 || rc=$?
  echo "${rc}|$(closed)|$(grep -c "^kept ${S} (its story could not be found) in tab e1" "${ROOT}/close.out")"
}
E1TAB=("w:t3 e1" "w:p30 w:t3;w:p31 w:t3" "conduct-e1 w:p30;${S} w:p31" e1 "w:p30 conductor")
fixture "${E1TAB[@]}"; story "${A}"; story "${B}"; open_pr "${B}"
is "close conduct-e1, ${A} and ${B} both stories, keeps ${S}'s pane and the tab: its story could not be found" "0||w:p30|1" "$(kept_tab)"
fixture "${E1TAB[@]}"; story "${A}"; brief "${B}"
is "close conduct-e1, ${A} a story and ${B} only a brief, keeps ${S}'s pane and the tab the same way" "0||w:p30|1" "$(kept_tab)"
# One name under the cut that is no story's says nothing of what its agent holds: an idle review
# agent known only by its brief is kept as for a story not found.
R="review-${A}"; RN="$(name "${R}")"
fixture "w:t3 e1" "w:p30 w:t3;w:p31 w:t3" "conduct-e1 w:p30;${RN} w:p31" e1 "w:p30 conductor"; brief "${R}"
rc=0; close conduct-e1 || rc=$?
is "close conduct-e1, ${RN} idle on an unrecorded pane and ${R} only a brief, keeps it and the tab" "0||w:p30|1" \
  "${rc}|$(closed)|$(grep -c "^kept ${RN} (its story could not be found) in tab e1" "${ROOT}/close.out")"

# close_epic: two long epics share a conductor name C, and each has its brief, so C is neither's.
# herdr lists C live on E2's conductor pane: close C is refused and closes nothing.
E1=name-cut-epic-whose-slug-runs-long-one; E2=name-cut-epic-whose-slug-runs-long-two; C="$(name "conduct-${E1}")"
is "conduct-${E1} and conduct-${E2} share the conductor name ${C}" "${C}" "$(name "conduct-${E2}")"
fixture "w:t5 ${E1};w:t6 ${E2}" "w:p50 w:t5;w:p60 w:t6" "${C} w:p60" "${E1}" "w:p50 conductor" "${E2}" "w:p60 conductor"
brief "conduct-${E1}"; brief "conduct-${E2}"
rc=0; close "${C}" || rc=$?
is "close ${C}, two briefs under it and herdr listing it live, is refused and closes nothing" "1|||1|1" \
  "${rc}|$(closed)|$(grep -cF "swarm: close: nothing in .swarm/state is recorded as ${C}, and herdr lists ${C}, its first 32 characters" "${ROOT}/close.out")|$(grep -cF $'\tw:me\tclose: no pane was closed for '"${C}" "${P}/.swarm/events.tsv")"

# The same two briefs, nothing live under C, and a third epic whose label is C without conduct-:
# close C takes no epic for the cut, so that epic's tab and record stay.
E3="${C#conduct-}"
fixture "w:t5 ${E1};w:t6 ${E2};w:t8 ${E3}" "w:p50 w:t5;w:p60 w:t6;w:p80 w:t8" "" "${E1}" "w:p50 conductor" "${E2}" "w:p60 conductor" "${E3}" "w:p80 conductor"
brief "conduct-${E1}"; brief "conduct-${E2}"
rc=0; close "${C}" || rc=$?
is "close ${C}, two briefs under it, leaves the tab of epic ${E3} and its record" "0|||w:p80 conductor" \
  "${rc}|$(closed)|$(cat "${P}/.swarm/state/${E3}" 2>/dev/null)"

# A story whose slug starts with conduct- is no conductor: closing its cut never takes the epic tab
# that the rest of its slug names, though it is the one name under the cut and has a brief.
K=conduct-name-cut-story-not-a-conductor; KN="$(name "${K}")"
fixture "w:t7 ${K#conduct-}" "w:p70 w:t7" "worker w:p70" "${K#conduct-}" "w:p70 worker"; story "${K}"; brief "${K}"
rc=0; close "${KN}" || rc=$?
is "close ${KN}, the cut of story ${K}, leaves the tab ${K#conduct-} and its record" "0|||w:p70 worker" \
  "${rc}|$(closed)|$(cat "${P}/.swarm/state/${K#conduct-}" 2>/dev/null)"

if [[ ${fails} -ne 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
