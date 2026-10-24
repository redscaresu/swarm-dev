#!/usr/bin/env bash
# close_exact_tab_test.sh — close takes only what .swarm/state records under the exact name it is
# given: its pane line, its tab records, and for a conductor its exact epic's tab records. Two names
# that share their first 32 characters (where herdr's agent names stop) never close each other's tab
# or pane. herdr's agent list stands in only for a name shorter than that; with nothing recorded under
# a longer name, a live agent herdr lists under its cut is refused, and nothing is closed, counted,
# cleared or kept. herdr is a stub on PATH: it lists the tabs in ${ROOT}/tabs ("<id> <label>"), the
# agents in ${ROOT}/agents ("<name> <pane> [status]", idle by default; from its second agent list on,
# with ${ROOT}/agents-later's after them) and the panes in ${ROOT}/panes ("<pane> <tab>"), and records
# each tab close in ${ROOT}/tabs-closed and each pane close in ${ROOT}/panes-closed. gh is a stub too:
# pr list gives ${ROOT}/prs.json, or no PRs, and pr close records each URL in ${ROOT}/prs-closed. The
# project has an empty bare origin.
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
cat > "${ROOT}/bin/gh" <<STUB
#!/bin/sh
case "\$1 \$2" in
  "pr list") cat "${ROOT}/prs.json" 2>/dev/null || echo "[]" ;;
  "pr close") echo "\$3" >> "${ROOT}/prs-closed" ;;
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
  "agent list") n=$(($(cat "$H/agent-lists" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/agent-lists"
                { cat "$H/agents"; [ "$n" -lt 2 ] || cat "$H/agents-later" 2>/dev/null; } | awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                     { printf "%s{\"name\":\"%s\",\"agent_status\":\"%s\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, (NF > 2 ? $3 : "idle"), $2 }
                     END { print "]}}" }' ;;
  "pane list") awk 'BEGIN { printf "{\"result\":{\"panes\":[" }
                    { printf "%s{\"pane_id\":\"%s\",\"tab_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                    END { print "]}}" }' "$H/panes" ;;
  "pane close") echo "$3" >> "$H/panes-closed" ;;
esac
STUB
chmod +x "${ROOT}/bin/herdr"
cp "$(dirname "${SWARM}")/../tests/claude_stub.sh" "${ROOT}/bin/claude"; chmod +x "${ROOT}/bin/claude"
sw() { (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" >"${ROOT}/close.out" 2>&1); }
close() { sw close "$@"; }
name() { (cd "${P}" && bash "${SWARM}" _name "$1"); }
closed() { echo "$(paste -sd' ' - < "${ROOT}/tabs-closed")|$(paste -sd' ' - < "${ROOT}/panes-closed")"; }
# fixture <state-file> <lines>... — a fresh .swarm/state with each named record; nothing closed yet.
fixture() {
  rm -rf "${P}/.swarm/state"; mkdir -p "${P}/.swarm/state"
  : > "${ROOT}/tabs-closed"; : > "${ROOT}/panes-closed"; : > "${P}/.swarm/events.tsv"; rm -f "${ROOT}/agent-lists"
  while [[ $# -gt 0 ]]; do printf '%b\n' "$2" > "${P}/.swarm/state/$1"; shift 2; done
}
story() { printf -- '---\nstatus: %s\nkind: code\n---\n\n# %s\n' "$2" "$1" > "${P}/docs/stories/$1.md"; rm -rf "${P}/.swarm/board-state/stories/$1"; }
attempts() { grep -h '^attempts:' "${P}/.swarm/board-state/stories/$1" 2>/dev/null || true; }
open_pr() { echo '[{"number":7,"state":"OPEN","url":"https://github.com/o/p/pull/7","headRefOid":"abc"}]' > "${ROOT}/prs.json"; : > "${ROOT}/prs-closed"; }

fails=0
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }

# refused <name> [arg]... — close <name> as a refusal reads: its exit, what it closed, the refusal
# naming herdr's cut, any not closed: line, and main's log line for it (ok, or the refusal).
refused() {
  local rc=0; close "$@" || rc=$?
  echo "${rc}|$(closed)|$(grep -cF "swarm: close: nothing in .swarm/state is recorded as $1, and herdr lists $(name "$1"), its first 32 characters" "${ROOT}/close.out")|$(grep -c '^not closed:' "${ROOT}/close.out")|$(grep -c $'\tw:me\tok' "${P}/.swarm/events.tsv")|$(grep -cF $'\tw:me\tclose: no pane was closed for '"$1" "${P}/.swarm/events.tsv")"
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
printf '%s\n' "${H} w:p1" "skeptic w:p2" > "${ROOT}/agents"; fixture "${T1}" "w:p1 critic" "${T2}" "w:p2 skeptic"
rc=0; close "${T2}" || rc=$?
is "close ${T2}, herdr listing ${H} in ${T1}'s pane, leaves that pane and ${T1}'s record" "0|w:t2||w:p1 critic" \
  "${rc}|$(closed)|$(cat "${P}/.swarm/state/${T1}" 2>/dev/null)"
# T2's own tab record wins over a pane line elsewhere that shares the cut.
printf '%s\n' "critic w:p1" "skeptic w:p2" > "${ROOT}/agents"
fixture "${T1}" "w:p1 critic" "${T2}" "w:p2 skeptic" e3 "w:p3 ${H}-x"
rc=0; close "${T2}" || rc=$?
is "close ${T2}, a pane line ${H}-x in tab e3 sharing its cut, still closes its own tab" "0|w:t2||w:p1 critic|w:p3 ${H}-x" \
  "${rc}|$(closed)|$(cat "${P}/.swarm/state/${T1}" 2>/dev/null)|$(cat "${P}/.swarm/state/e3" 2>/dev/null)"
# The cut both share is no record's name: with nothing live under it, close takes nothing; with herdr
# listing it live, close is refused.
fixture "${T1}" "w:p1 critic" "${T2}" "w:p2 skeptic"
rc=0; close "${H}" || rc=$?
is "close ${H}, the cut both share, with nothing live under it, closes nothing" "0||" "${rc}|$(closed)"
printf '%s\n' "${H} w:p1" "skeptic w:p2" > "${ROOT}/agents"; fixture "${T1}" "w:p1 critic" "${T2}" "w:p2 skeptic"
is "close ${H}, herdr listing it live in ${T1}'s pane, is refused and closes nothing" "${REFUSED}" "$(refused "${H}")"

# Two builders whose long slugs share their first 32 characters, in two epics' tabs; herdr lists the
# cut on B's pane, as B holds that name now. A session log is recorded under the cut, B's.
S=a-story-slug-that-runs-past-32-c; A="${S}-a"; B="${S}-b"
is "${A} and ${B} share their agent name" "${S}|${S}" "$(name "${A}")|$(name "${B}")"
printf '%s\n' "${S} w:p21" > "${ROOT}/agents"
printf '%s\n' "w:p10 w:t3" "w:p11 w:t3" "w:p20 w:t4" "w:p21 w:t4" > "${ROOT}/panes"
mkdir -p "${CLAUDE_CONFIG_DIR}/projects/p"; echo '{"type":"user"}' > "${CLAUDE_CONFIG_DIR}/projects/p/sess-b.jsonl"
printf '2026-10-01\tcode-sonnet\t%s\tclaude\tsonnet\thigh\tsess-b\n' "${S}" > "${P}/.swarm/agents.tsv"
archived() { find "${P}/.swarm/sessions" -type f 2>/dev/null | wc -l | tr -d ' '; }
fixture e1 "w:p10 conductor\nw:p11 ${A}" e2 "w:p20 conductor\nw:p21 ${B}"
# A's record comes first (e1), so a match on the cut would find A's line closing B.
rc=0; close "${B}" || rc=$?
is "close ${B} closes its pane, leaves ${A}'s open and recorded, and archives no session under the cut" "0||w:p21|w:p10 conductor w:p11 ${A}|0" \
  "${rc}|$(closed)|$(paste -sd' ' - < "${P}/.swarm/state/e1")|$(archived)"
# A's pane line gone (closed by hand): nothing is recorded as A, and herdr's agent under the cut is
# live, maybe A's or B's, so nothing is closed, counted, cleared, kept or archived.
fixture e1 "w:p10 conductor" e2 "w:p20 conductor\nw:p21 ${B}"; mkdir -p "${P}/.swarm/zdotdir/${S}"
is "close ${A}, with no record of its own and herdr listing its cut live, is refused" "${REFUSED}" "$(refused "${A}")"
story "${A}" review; fixture e1 "w:p10 conductor" e2 "w:p20 conductor\nw:p21 ${B}"
is "close ${A}, its story merged, is refused the same way" "${REFUSED}" "$(refused "${A}")"
is "and archives no session (${B}'s, recorded under the cut) and keeps the cut's ZDOTDIR" "0|kept" \
  "$(archived)|$([[ -d "${P}/.swarm/zdotdir/${S}" ]] && echo kept || echo gone)"
story "${A}" ready; fixture e1 "w:p10 conductor" e2 "w:p20 conductor\nw:p21 ${B}"; open_pr
is "close ${A} stalled --drop, its story ready and its PR open, is refused: nothing counted, no PR closed" "${REFUSED}||" \
  "$(refused "${A}" stalled --drop)|$(attempts "${A}")|$(cat "${ROOT}/prs-closed")"
rm -f "${ROOT}/prs.json"

# The ladder on, A's builder idle with no PR: its close is refused and counts nothing, and a step-up
# of A is refused with nothing closed (its .step-up marker goes). With nothing live under the cut,
# A's pane simply gone, a step-up gets past the close.
GIT=(git -c user.name=t -c user.email=t@t -c commit.gpgsign=false)
"${GIT[@]}" -C "${P}" commit -q --allow-empty -m init
"${GIT[@]}" -C "${P}" worktree add -q -b "story/${A}" "${ROOT}/proj-wt/${A}"
mkdir -p "${P}/.claude/swarm"; echo "escalate_ladder = sonnet,opus" > "${P}/.claude/swarm/config"
story "${A}" ready; fixture e1 "w:p10 conductor" e2 "w:p20 conductor\nw:p21 ${B}"
printf '2026-10-01T09:00:00Z\tstory\t%s\tw:1\tok\n' "${A}" > "${P}/.swarm/events.tsv"
ladder() { echo "$(grep -c $'\tescalate\t' "${P}/.swarm/events.tsv")|$(attempts "${A}")|$([[ -e "${P}/.swarm/briefs/${A}.step-up" ]] && echo marker || echo gone)|$([[ -d "${ROOT}/proj-wt/${A}" ]] && echo worktree || echo cleared)"; }
rc=0; close "${A}" || rc=$?
is "close ${A}, the ladder on and its builder idle with no PR, is refused: nothing stepped up or counted, its worktree kept" \
  "1|0||gone|worktree" "${rc}|$(ladder)"
rc=0; sw step-up "${A}" stalled || rc=$?
is "step-up ${A} stalled, herdr listing its cut live, closes nothing: its marker goes, and nothing is stepped up" "1|0||gone|worktree|1" \
  "${rc}|$(ladder)|$(grep -c "step-up: ${A}'s builder pane was not closed (see above), so nothing was stepped up" "${ROOT}/close.out")"
: > "${ROOT}/agents"; story "${A}" ready; fixture e1 "w:p10 conductor" e2 "w:p20 conductor\nw:p21 ${B}"
rc=0; sw step-up "${A}" stalled || rc=$?
is "step-up ${A} stalled, its pane gone and nothing live under its cut, gets past the close" "0|marker" \
  "$(grep -c "builder pane was not closed\|builder pane could not be closed" "${ROOT}/close.out")|$([[ -e "${P}/.swarm/briefs/${A}.step-up" ]] && echo marker || echo gone)"
rm -rf "${P}/.claude/swarm/config" "${P}/.swarm/agents.tsv" "${P}/docs/stories/${A}.md" "${P}/.swarm/briefs"

# A long builder on an older record line with no name: herdr holds its name only cut, so with herdr
# listing the cut live there, close refuses rather than guess whose it is, for a story too: nothing
# counted, cleared or kept.
L=a-long-builder-slug-running-past-32-characters; LN="$(name "${L}")"
printf '%s\n' "w:t6 e5" >> "${ROOT}/tabs"; printf '%s\n' "w:p40 w:t6" "w:p41 w:t6" > "${ROOT}/panes"
printf '%s\n' "${LN} w:p40" > "${ROOT}/agents"; fixture e5 "w:p40\nw:p41"
is "close ${L}, its record line unnamed and herdr listing ${LN} on it, is refused" "${REFUSED}" "$(refused "${L}")"
printf '%s\n' "${LN} w:p40" "${LN} w:p41" > "${ROOT}/agents"; fixture e5 "w:p40\nw:p41"
is "close ${L}, herdr listing ${LN} on both unnamed panes, is refused" "${REFUSED}" "$(refused "${L}")"
story "${L}" ready; open_pr; fixture e5 "w:p40\nw:p41"
is "close ${L} stalled --drop, its story ready, is refused: nothing counted, no PR closed" "${REFUSED}||" \
  "$(refused "${L}" stalled --drop)|$(attempts "${L}")|$(cat "${ROOT}/prs-closed")"
story "${L}" ready; fixture e5 "w:p40\nw:p41"
is "close ${L}, its PR open, is refused and keeps nothing: the story stays ready" "${REFUSED}||" \
  "$(refused "${L}")|$(grep -h '^status: review' "${P}/.swarm/board-state/stories/${L}" 2>/dev/null || true)|$(grep -h '^kept:' "${P}/.swarm/board-state/stories/${L}" 2>/dev/null || true)"
rm -f "${ROOT}/prs.json" "${P}/docs/stories/${L}.md"
# <L2>-a live on an older unnamed line, <L2>-b's line gone, both stories: close <L2>-b never takes it.
L2=another-long-builder-slug-past-32; La="${L2}-a"; Lb="${L2}-b"
printf '%s\n' "w:t12 e6" >> "${ROOT}/tabs"; printf '%s\n' "w:p60 w:t12" > "${ROOT}/panes"
printf '%s\n' "$(name "${La}") w:p60" > "${ROOT}/agents"; fixture e6 "w:p60"; story "${La}" ready; story "${Lb}" ready
is "close ${Lb}, ${La} live on an unnamed line under the same cut, is refused and counts nothing" "${REFUSED}|" \
  "$(refused "${Lb}")|$(attempts "${Lb}")"
rm -f "${P}/docs/stories/${La}.md" "${P}/docs/stories/${Lb}.md"

# A story whose long slug starts with its epic's: the epic's tab label is no agent's name, so with
# its pane line gone and nothing live under its cut, its close is not refused.
E=aws-layer3-claim-sweep-reaper-long-epic; C="$(name "conduct-${E}")"
printf '%s\n' "w:t7 ${E}" "w:t8 aws-layer3-claim-sweep-reaper-fix" "w:t9 ${E}-2" >> "${ROOT}/tabs"
printf '%s\n' "w:p50 w:t7" "w:p51 w:t7" "w:p80 w:t8" "w:p52 w:t9" > "${ROOT}/panes"
printf '%s\n' "s9 w:p51" "fixer w:p80" > "${ROOT}/agents"; fixture "${E}" "w:p50 conductor\nw:p51 s9"
rc=0; close "${E}-builder" || rc=$?
is "close ${E}-builder, its pane line gone, is not refused for its epic's tab ${E} and closes nothing" "0||" "${rc}|$(closed)"

# A conductor's epic tabs: its brief's epic, or the full name's, never a match on the cut alone.
printf '%s\n' "${C} w:p50" "s9 w:p51" "fixer w:p80" "s8 w:p52" > "${ROOT}/agents"
mkdir -p "${P}/.swarm/briefs"; : > "${P}/.swarm/briefs/conduct-${E}.md"; fixture "${E}" "w:p50 conductor\nw:p51 s9"
rc=0; close "${C}" || rc=$?
is "close ${C}, its brief naming ${E}, closes ${E}'s tab" "0|w:t7|" "${rc}|$(closed)"
rm -f "${P}/.swarm/briefs/conduct-${E}.md"; fixture "${E}" "w:p50 conductor\nw:p51 s9"
rc=0; close "conduct-${E}" || rc=$?
is "close conduct-${E}, the full name with no brief, closes ${E}'s tab" "0|w:t7|" "${rc}|$(closed)"
fixture "${E}" "w:p50 conductor\nw:p51 s9" "${E}-2" "w:p52 s8"
is "close ${C}, no brief and herdr listing it live on ${E}'s conductor pane, is refused" "${REFUSED}" "$(refused "${C}")"
printf '%s\n' "fixer w:p80" > "${ROOT}/agents"; fixture aws-layer3-claim-sweep-reaper-fix "w:p80 fixer"
rc=0; close "${C}" || rc=$?
is "close ${C}, no brief or record of ${E}, leaves the story tab sharing its cut, and its record" "0|||w:p80 fixer" \
  "${rc}|$(closed)|$(cat "${P}/.swarm/state/aws-layer3-claim-sweep-reaper-fix")"
: > "${ROOT}/agents"; fixture e1 "w:p10 conductor"
rc=0; close conduct-e7 || rc=$?
is "close conduct-e7, its tabs and pane already gone, succeeds with nothing to do" "0||" "${rc}|$(closed)"
# Two briefs share a 32-character conductor name: the exact one, conduct-<name>.md, wins over the newer.
E24=aws-layer3-claim-sweep-r; C24="conduct-${E24}"
printf '%s\n' "w:t13 ${E24}" "w:t14 ${E24}-longer-epic" >> "${ROOT}/tabs"; printf '%s\n' "w:p90 w:t13" "w:p91 w:t14" > "${ROOT}/panes"
: > "${P}/.swarm/briefs/${C24}.md"; sleep 1; : > "${P}/.swarm/briefs/conduct-${E24}-longer-epic.md"
fixture "${E24}" "w:p90 conductor" "${E24}-longer-epic" "w:p91 conductor"
rc=0; close "${C24}" || rc=$?
is "close ${C24} (${#C24} characters), two briefs giving it, closes ${E24}'s tab, its exact brief's" "0|w:t13|" "${rc}|$(closed)"
rm -rf "${P}/.swarm/briefs"
# Long epics E1 and E2 share a conductor name; herdr lists it on E1's conductor pane.
E1=aws-layer3-claim-sweep-reaper-one; E2=aws-layer3-claim-sweep-reaper-two
printf '%s\n' "w:t10 ${E1}" "w:t11 ${E2}" >> "${ROOT}/tabs"; printf '%s\n' "w:p70 w:t10" "w:p71 w:t11" > "${ROOT}/panes"
printf '%s\n' "$(name "conduct-${E1}") w:p70" > "${ROOT}/agents"; fixture "${E1}" "w:p70 conductor" "${E2}" "w:p71 conductor"
rc=0; close "conduct-${E2}" || rc=$?
is "close conduct-${E2}, herdr listing the shared conductor name on ${E1}'s pane, closes ${E2}'s tab only" "0|w:t11|" "${rc}|$(closed)"

# herdr's lists are read when close closes, after the build is read: an agent that starts in the
# tab in between (listed from herdr's second agent list on) keeps it.
printf '%s\n' "w:t15 x1" >> "${ROOT}/tabs"; printf '%s\n' "w:p92 w:t15" "w:p93 w:t15" > "${ROOT}/panes"
printf '%s\n' "helper w:p92" > "${ROOT}/agents"; echo "worker w:p93 working" > "${ROOT}/agents-later"
story x1 ready; fixture x1 "w:p92 helper"
rc=0; close x1 || rc=$?
is "close x1, a worker starting in its tab after its build was read, keeps the tab" "0|||1" \
  "${rc}|$(closed)|$(grep -c '^kept worker (working) in tab x1' "${ROOT}/close.out")"
rm -f "${ROOT}/agents-later" "${P}/docs/stories/x1.md"

if [[ ${fails} -ne 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
