#!/usr/bin/env bash
# close_exact_tab_test.sh — close takes only the tab or pane .swarm/state records under the exact name
# it is given. Two names that share their first 32 characters (where herdr's agent names stop) never
# close each other's tab or pane, and a name with no exact record is refused, naming what shares its
# cut, with nothing closed. herdr is a stub on PATH: it lists the tabs in ${ROOT}/tabs ("<id> <label>"),
# the agents in ${ROOT}/agents ("<name> <pane>", idle) and the panes in ${ROOT}/panes ("<pane> <tab>"),
# and records each tab close in ${ROOT}/tabs-closed and each pane close in ${ROOT}/panes-closed. gh is
# a stub too: pr list gives ${ROOT}/prs.json, or no PRs, and pr close records each URL in
# ${ROOT}/prs-closed. The project has an empty bare origin.
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
sw() { (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" >"${ROOT}/close.out" 2>&1); }
close() { sw close "$@"; }
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

# Only the pane is refused: herdr's agent under the cut is B's (a named record), never A's, so a
# story's board work goes on as for a builder closed by hand. A merged story's close, as reconcile runs
# it, exits 0, closes no pane, says why once and is logged ok; a stalled --drop close of a ready one
# whose PR is open counts its attempt and closes that PR.
printf '%s\n' "$(name "${A}") w:p21" > "${ROOT}/agents"
story() { printf -- '---\nstatus: %s\nkind: code\n---\n\n# %s\n' "$2" "$1" > "${P}/docs/stories/$1.md"; rm -rf "${P}/.swarm/board-state/stories/$1"; }
attempts() { grep -h '^attempts:' "${P}/.swarm/board-state/stories/$1" 2>/dev/null || true; }
open_pr() { echo '[{"number":7,"state":"OPEN","url":"https://github.com/o/p/pull/7","headRefOid":"abc"}]' > "${ROOT}/prs.json"; : > "${ROOT}/prs-closed"; }
story_close() {
  local rc=0; close "$@" || rc=$?
  echo "${rc}|$(closed)|$(grep -cF "swarm: close: nothing in .swarm/state is recorded as $1, and ${B} (pane w:p21 in tab e2) share" "${ROOT}/close.out")|$(grep -cF $'\tclose' "${P}/.swarm/events.tsv" | tr -d ' ')|$(grep -c $'\tok' "${P}/.swarm/events.tsv")"
}
story "${A}" review; fixture e1 "w:p10 conductor" e2 "w:p20 conductor\nw:p21 ${B}"; mkdir -p "${P}/.swarm/zdotdir/${S}"
is "close ${A}, its story merged and its record gone, closes no pane, says why, and goes on (exit 0, logged ok)" "0|||1|1|1" \
  "$(story_close "${A}")"
is "and leaves the ZDOTDIR of ${S}, the cut name ${B} holds" "kept" "$([[ -d "${P}/.swarm/zdotdir/${S}" ]] && echo kept || echo gone)"
story "${A}" ready; fixture e1 "w:p10 conductor" e2 "w:p20 conductor\nw:p21 ${B}"; open_pr
is "close ${A} stalled --drop, its story ready, its record gone and its PR open, closes no pane, counts its attempt and closes the PR" \
  "0|||1|1|1|attempts: 1|https://github.com/o/p/pull/7" \
  "$(story_close "${A}" stalled --drop)|$(attempts "${A}")|$(cat "${ROOT}/prs-closed")"
rm -f "${ROOT}/prs.json"

# The ladder on, A's builder idle with no PR: its close says the refusal once, begins no step-up and
# counts nothing, as A's builder is no open one. A step-up of A itself closes nothing: its .step-up
# marker goes, and nothing is stepped up.
GIT=(git -c user.name=t -c user.email=t@t -c commit.gpgsign=false)
"${GIT[@]}" -C "${P}" commit -q --allow-empty -m init
"${GIT[@]}" -C "${P}" worktree add -q -b "story/${A}" "${ROOT}/proj-wt/${A}"
mkdir -p "${P}/.claude/swarm"; echo "escalate_ladder = sonnet,opus" > "${P}/.claude/swarm/config"
printf '2026-10-01\tcode-sonnet\t%s\tclaude\tsonnet\thigh\tsess-a\n' "${S}" > "${P}/.swarm/agents.tsv"
story "${A}" ready; fixture e1 "w:p10 conductor" e2 "w:p20 conductor\nw:p21 ${B}"
printf '2026-10-01T09:00:00Z\tstory\t%s\tw:1\tok\n' "${A}" > "${P}/.swarm/events.tsv"
ladder() { echo "$(grep -cF "recorded as ${A}, and ${B} (pane w:p21 in tab e2) share" "${ROOT}/close.out")|$(grep -c $'\tescalate\t' "${P}/.swarm/events.tsv")|$(attempts "${A}")|$([[ -e "${P}/.swarm/briefs/${A}.step-up" ]] && echo marker || echo gone)|$([[ -d "${ROOT}/proj-wt/${A}" ]] && echo worktree || echo cleared)"; }
rc=0; close "${A}" || rc=$?
is "close ${A}, the ladder on and its builder idle with no PR, says the refusal once, steps nothing up and counts nothing" \
  "0|1|0||gone|worktree" "${rc}|$(ladder)"
rc=0; sw step-up "${A}" stalled || rc=$?
is "step-up ${A} stalled, its record gone, closes nothing: its marker goes, and nothing is stepped up" "1|1|0||gone|worktree|1" \
  "${rc}|$(ladder)|$(grep -c "step-up: ${A}'s builder pane was not closed (see above), so nothing was stepped up" "${ROOT}/close.out")"
rm -f "${P}/.claude/swarm/config" "${P}/.swarm/agents.tsv" "${P}/docs/stories/${A}.md"

# A long builder whose record line has no name (an older record) is found by herdr's cut of its name,
# when nothing else has that cut. Two herdr agents under it on unnamed lines, or one when another
# story has the cut, are refused as a kept pane: nothing closed, counted, cleared or kept, and the
# close fails.
L=a-long-builder-slug-running-past-32-characters; LN="$(name "${L}")"
printf '%s\n' "w:t6 e5" >> "${ROOT}/tabs"; printf '%s\n' "w:p40 w:t6" "w:p41 w:t6" > "${ROOT}/panes"
printf '%s\n' "${LN} w:p40" > "${ROOT}/agents"; fixture e5 "w:p40\nw:p41"
rc=0; close "${L}" || rc=$?
is "close ${L}, its record line unnamed, closes the pane herdr lists as ${LN}" "0||w:p40" "${rc}|$(closed)"
printf '%s\n' "${LN} w:p40" "${LN} w:p41" > "${ROOT}/agents"; fixture e5 "w:p40\nw:p41"
rc=0; close "${L}" || rc=$?
is "close ${L}, herdr listing ${LN} on both unnamed panes, fails and closes neither" "1|||1" \
  "${rc}|$(closed)|$(grep -cF "herdr lists more than one agent as ${LN}" "${ROOT}/close.out")"
story "${L}" ready; open_pr; fixture e5 "w:p40\nw:p41"
rc=0; close "${L}" stalled --drop || rc=$?
is "close ${L} stalled --drop, its story ready and two herdr agents under its cut, fails: nothing counted or cleared, no PR closed" \
  "1|||||1" "${rc}|$(closed)|$(attempts "${L}")|$(cat "${ROOT}/prs-closed")|$(grep -c $'\tclose:stalled\t'"${L}"$'\tw:me\tclose: no pane was closed' "${P}/.swarm/events.tsv")"
story "${L}" ready; fixture e5 "w:p40\nw:p41"
rc=0; close "${L}" || rc=$?
is "close ${L}, its PR open and two herdr agents under its cut, fails and keeps nothing: the story stays ready" "1||||" \
  "${rc}|$(closed)|$(grep -h '^status: review' "${P}/.swarm/board-state/stories/${L}" 2>/dev/null || true)|$(grep -h '^kept:' "${P}/.swarm/board-state/stories/${L}" 2>/dev/null || true)"
rm -f "${ROOT}/prs.json" "${P}/docs/stories/${L}.md"
# <L2>-a live on an older unnamed line, <L2>-b's line gone, both stories: close <L2>-b never takes it.
L2=another-long-builder-slug-past-32; La="${L2}-a"; Lb="${L2}-b"
printf '%s\n' "w:t12 e6" >> "${ROOT}/tabs"; printf '%s\n' "w:p60 w:t12" > "${ROOT}/panes"
printf '%s\n' "$(name "${La}") w:p60" > "${ROOT}/agents"; fixture e6 "w:p60"; story "${La}" ready; story "${Lb}" ready
rc=0; close "${Lb}" || rc=$?
is "close ${Lb}, ${La} live on an unnamed line under the same cut, fails, closes nothing and names the story ${La}" "1||||1" \
  "${rc}|$(closed)|$(attempts "${Lb}")|$(grep -cF "share that cut, so the pane may be another's live agent" "${ROOT}/close.out")"
rm -f "${P}/docs/stories/${La}.md" "${P}/docs/stories/${Lb}.md"

# A conductor's epic tabs come from its brief, or with none from a record of exactly the epic its
# name gives; a match on the conductor name's cut alone is refused as a kept pane.
E=aws-layer3-claim-sweep-reaper-long-epic; C="$(name "conduct-${E}")"
printf '%s\n' "w:t7 ${E}" "w:t8 aws-layer3-claim-sweep-reaper-fix" "w:t9 ${E}-2" >> "${ROOT}/tabs"
printf '%s\n' "w:p50 w:t7" "w:p51 w:t7" "w:p80 w:t8" "w:p52 w:t9" > "${ROOT}/panes"
printf '%s\n' "${C} w:p50" "s9 w:p51" "fixer w:p80" "s8 w:p52" > "${ROOT}/agents"
mkdir -p "${P}/.swarm/briefs"; : > "${P}/.swarm/briefs/conduct-${E}.md"; fixture "${E}" "w:p50 conductor\nw:p51 s9"
rc=0; close "${C}" || rc=$?
is "close ${C}, its brief naming ${E}, closes ${E}'s tab" "0|w:t7|" "${rc}|$(closed)"
rm -f "${P}/.swarm/briefs/conduct-${E}.md"; fixture "${E}" "w:p50 conductor\nw:p51 s9" "${E}-2" "w:p52 s8"
rc=0; close "${C}" || rc=$?
is "close ${C}, no brief and ${E}'s tabs matching only its cut, fails, closes nothing and names ${E} once" "1|||1" \
  "${rc}|$(closed)|$(grep -cF "match the tab records of ${E}, so no pane was closed" "${ROOT}/close.out")"
fixture aws-layer3-claim-sweep-reaper-fix "w:p80 fixer"
rc=0; close "${C}" || rc=$?
is "close ${C}, no brief or record of ${E}, leaves the story tab sharing its cut, and its record" "1|||w:p80 fixer" \
  "${rc}|$(closed)|$(cat "${P}/.swarm/state/aws-layer3-claim-sweep-reaper-fix")"
fixture e1 "w:p10 conductor"
rc=0; close "${C}" || rc=$?
is "close ${C}, nothing recorded for it, fails and says so" "1|||1" "${rc}|$(closed)|$(grep -cF "no tab record in .swarm/state is its epic's or ${C}'s" "${ROOT}/close.out")"
# Long epics E1 and E2 share a conductor name; herdr lists it on E1's conductor pane.
E1=aws-layer3-claim-sweep-reaper-one; E2=aws-layer3-claim-sweep-reaper-two
printf '%s\n' "w:t10 ${E1}" "w:t11 ${E2}" >> "${ROOT}/tabs"; printf '%s\n' "w:p70 w:t10" "w:p71 w:t11" > "${ROOT}/panes"
printf '%s\n' "$(name "conduct-${E1}") w:p70" > "${ROOT}/agents"; fixture "${E1}" "w:p70 conductor" "${E2}" "w:p71 conductor"
rc=0; close "conduct-${E2}" || rc=$?
is "close conduct-${E2}, no brief and herdr listing the shared conductor name on ${E1}'s pane, fails and closes neither" "1|||1" \
  "${rc}|$(closed)|$(grep -cF "match the tab records of ${E1}, ${E2}, so no pane was closed" "${ROOT}/close.out")"

# A record mid-rewrite (record_drop's .tmp) is no tab of its own.
printf '%s\n' "critic w:p1" "skeptic w:p2" > "${ROOT}/agents"
fixture "${T1}" "w:p1 critic" "${T1}.tmp" "w:p1 critic" "${T2}" "w:p2 skeptic"
is "close ${H}, ${T1}.tmp beside ${T1}, names ${T1} and ${T2} only" "${REFUSED}" "$(refused "${H}" "tab ${T1}, tab ${T2}")"

if [[ ${fails} -ne 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
