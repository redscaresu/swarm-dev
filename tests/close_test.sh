#!/usr/bin/env bash
# close_test.sh — close shuts every tab that carries the agent's label, one id per herdr call, even
# when two tabs share it, and archives the agent's session log once; closing the open builder of a
# ready story counts a failed build, and close takes a cause. herdr and gh are stubs on PATH: herdr records each tab close and
# lists the agents in ${ROOT}/agents ("<name> <pane> [status]" lines, idle by default, a name of - for
# none; agent list fails while ${ROOT}/agentfail exists) and the panes in ${ROOT}/panes ("<pane> <tab>"
# lines; pane list fails while ${ROOT}/panefail exists, tab list while ${ROOT}/tablistfail does, tab
# close while ${ROOT}/tabclosefail does and pane close while ${ROOT}/paneclosefail does); gh answers pr list from ${ROOT}/prs.json, with
# --state open the heads of its open PRs that name one, as close_heads' --jq asks, and pr view <url>
# from ${ROOT}/pr-states ("<url> <state>" lines).
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
P="${ROOT}/proj"; CLOSED="${ROOT}/closed"
mkdir -p "${P}/.swarm/state" "${P}/docs/stories" "${ROOT}/bin"
git -C "${P}" init -q
: > "${CLOSED}"
: > "${ROOT}/agents"; : > "${ROOT}/panes"
printf '#!/bin/sh\nA="%s"; CLOSED="%s"; H="%s"\n' "${ROOT}/agents" "${CLOSED}" "${ROOT}" | tee "${ROOT}/bin/gh" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'STUB'
case "$1 $2" in
  "tab list") [ -e "$H/tablistfail" ] && exit 1
              echo '{"result":{"tabs":[{"tab_id":"w:t1","label":"scope-x"},{"tab_id":"w:t2","label":"scope-x"},{"tab_id":"w:t3","label":"other"},{"tab_id":"w:t4","label":"_epic"},{"tab_id":"w:t5","label":"epic"},{"tab_id":"w:t6","label":"epic-x"},{"tab_id":"w:t7","label":"ce"},{"tab_id":"w:t8","label":"ce-2"},{"tab_id":"w:t10","label":"ce-foo"},{"tab_id":"w:t12","label":"sp"},{"tab_id":"w:t13","label":"rb"}]}}' ;;
  "tab close") [ -e "$H/tabclosefail" ] && exit 1
               printf '<%s>\n' "$3" >> "${CLOSED}" ;;
  "agent list") [ -e "$H/agentfail" ] && exit 1
                awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                     { printf "%s{%s\"agent_status\":\"%s\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), ($1 == "-" ? "" : "\"name\":\"" $1 "\","), (NF > 2 ? $3 : "idle"), $2 }
                     END { print "]}}" }' "$A" ;;
  "agent rename") awk -v p="$3" -v n="$4" '$2 == p { $1 = n } { print }' "$A" > "$A.tmp" && mv "$A.tmp" "$A" ;;
  "pane list") [ -e "$H/panefail" ] && exit 1
               awk 'BEGIN { printf "{\"result\":{\"panes\":[" }
                    { printf "%s{\"pane_id\":\"%s\",\"tab_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                    END { print "]}}" }' "$H/panes" ;;
  "pane close") [ -e "$H/paneclosefail" ] && exit 1
                echo "$3" >> "$H/panes-closed" ;;
esac
STUB
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "$H/gh.log"
[ -e "$H/ghfail" ] && exit 1
case "$1 $2 $*" in
  "pr list "*"--state open"*) python3 -c 'import json, sys; [print(p["headRefName"]) for p in json.load(open(sys.argv[1])) if p["state"] == "OPEN" and p.get("headRefName")]' "$H/prs.json" ;;
  "pr list "*) cat "$H/prs.json" ;;
  "pr view "*) awk -v u="$3" '$1 == u { printf "{\"state\":\"%s\"}\n", $2 }' "$H/pr-states" ;;
esac
exit 0
STUB
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh"
# Claude Code's list from a stub (claude_stub.sh: [] until CLAUDE_STUB_AGENTS names a file), so no
# close here reads a real claude's.
cp "$(dirname "${SWARM}")/../tests/claude_stub.sh" "${ROOT}/bin/claude"; chmod +x "${ROOT}/bin/claude"
echo "w:p1 lead-x" > "${P}/.swarm/state/scope-x"; echo "lead-x w:p1" > "${ROOT}/agents"
# scope-x has a Claude session (an older line for the same name came first), and so does lead-x, the
# agent in its tab; codex-y has none.
mkdir -p "${CLAUDE_CONFIG_DIR}/projects/p"
printf '{"type":"user","cwd":"/x"}\n' > "${CLAUDE_CONFIG_DIR}/projects/p/sx.jsonl"
printf '{"type":"user","cwd":"/l"}\n' > "${CLAUDE_CONFIG_DIR}/projects/p/lx.jsonl"
printf '%s\n' $'2026-10-01\tplan\tscope-x\tclaude\topus\thigh\told' $'2026-10-02\tplan\tscope-x\tclaude\topus\thigh\tsx' \
  $'2026-10-02\tlead\tlead-x\tclaude\topus\thigh\tlx' $'2026-10-02\tcodex\tcodex-y\tcodex\tdefault\thigh\t-' > "${P}/.swarm/agents.tsv"
close() { (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" close "$@" >"${ROOT}/close.out" 2>&1) || true; }

close scope-x

fails=0
check() { local name="$1"; shift; if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi; }
check "both tabs with the label are closed, one id per call" test "$(sort "${CLOSED}" | tr '\n' ' ')" = "<w:t1> <w:t2> "
check "another label's tab is left open" bash -c "! grep -qx '<w:t3>' '${CLOSED}'"
check "the tab record is removed" test ! -e "${P}/.swarm/state/scope-x"
archives() { find "${P}/.swarm/sessions" -type f 2>/dev/null | wc -l | tr -d ' '; }
check "close archives the agent's newest session, gzip'd" \
  test "$(gunzip -c "${P}/.swarm/sessions/"*-scope-x-sx.jsonl.gz 2>/dev/null)" = '{"type":"user","cwd":"/x"}'
check "closing its tab archives the agent left in it too" \
  test "$(gunzip -c "${P}/.swarm/sessions/"*-lead-x-lx.jsonl.gz 2>/dev/null)" = '{"type":"user","cwd":"/l"}'
check "the two archives are the only files there" test "$(archives)" = 2
check "the archives are readable by their owner only" test "$(find "${P}/.swarm/sessions" -name "*.jsonl.gz" -perm 600 | wc -l | tr -d ' ')" = 2
# Dated earlier, so a second copy would get a new name rather than overwrite this one.
mv "${P}/.swarm/sessions/"*-scope-x-sx.jsonl.gz "${P}/.swarm/sessions/2026-01-01-scope-x-sx.jsonl.gz"
close scope-x
check "closing it again, another day, archives nothing more" test "$(archives)" = 2
close codex-y
: > "${ROOT}/agents"
check "an agent with no session archives nothing" test "$(archives)" = 2

# /epic's co-author and reviewer share the tab commands/epic.md names. Closing both closes that tab
# and never the tab of an epic slugged epic-x, which a tab label starting epic- would glob.
EL="$(sed -n 's/.*swarm\.sh agent \([^ ]*\) epic-<slug> .*/\1/p' "$(dirname "${SWARM}")/../commands/epic.md")"
printf 'w:p30 epic-e\nw:p31 epic-review-e\n' > "${P}/.swarm/state/${EL}"
echo "w:p32 conduct-epic-x" > "${P}/.swarm/state/epic-x"
: > "${CLOSED}"; close epic-e; close epic-review-e
check "closing /epic's co-author and reviewer (tab ${EL}) leaves an epic-x epic's tab open" \
  test "$(tr -d '\n' < "${CLOSED}")|$(cat "${P}/.swarm/state/epic-x" 2>/dev/null)" = "<w:t4>|w:p32 conduct-epic-x"
rm -f "${P}/.swarm/state/epic-x"

# --- A close that ends a failed build: the story is ready, of an agent's kind, its builder is open
# under its name and none of its PRs merged. attempts: goes up by one, and the worktree, local and
# origin story/<slug> go, and with --drop the open PR too. Any other close counts and clears nothing.
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
GIT=(git -c user.name=t -c user.email=t@t)
"${GIT[@]}" init -q --bare "${ROOT}/origin.git"
git -C "${P}" remote add origin "${ROOT}/origin.git"
"${GIT[@]}" -C "${P}" commit -q --allow-empty -m init && git -C "${P}" push -q origin HEAD:refs/heads/main
# item <slug> <front-matter line>... — a fresh story: its file, and no state file.
item() { { echo ---; printf '%s\n' "${@:2}"; echo ---; echo; echo "# $1"; } > "${P}/docs/stories/$1.md"; rm -f "${P}/.swarm/board-state/stories/$1"; }
# fmv <slug> <key> — <key> as swarm.sh reads it: board.sh's own get_fm.
# shellcheck source=/dev/null
fmv() { (export BOARD="${P}/docs" PROJECT_DIR="${P}"; . "${SWARM%/*}/lib/board.sh"; get_fm "${BOARD}/stories/$1.md" "$2"); }
# put <slug> <key: value>... — lines in the story's state file, as swarm.sh writes them.
put() { mkdir -p "${P}/.swarm/board-state/stories"; printf '%s\n' "${@:2}" >> "${P}/.swarm/board-state/stories/$1"; }
started() { # <slug> [pane] — its worktree on story/<slug>, pushed, and an untracked file; with a pane, its builder open there
  local wt="${ROOT}/proj-wt/$1"
  "${GIT[@]}" -C "${P}" worktree add -q -b "story/$1" "${wt}"
  "${GIT[@]}" -C "${wt}" commit -q --allow-empty -m "$1" && git -C "${wt}" push -q origin "story/$1"
  touch "${wt}/untracked"
  [[ -z "${2:-}" ]] || { echo "$2 $1" > "${P}/.swarm/state/$1"; echo "$1 $2" >> "${ROOT}/agents"; }
}
left() { # <slug> — which of its worktree, local story/<slug> and origin's are still there
  local o=""
  [[ ! -d "${ROOT}/proj-wt/$1" ]] || o+=" worktree"
  ! git -C "${P}" show-ref -q --verify "refs/heads/story/$1" || o+=" branch"
  ! git -C "${ROOT}/origin.git" show-ref -q --verify "refs/heads/story/$1" || o+=" origin"
  echo "${o# }"
}
attempts() { fmv "$1" attempts 2>/dev/null || true; }
U="https://github.com/o/proj/pull"
echo "[{\"number\":1,\"state\":\"OPEN\",\"url\":\"${U}/1\",\"headRefOid\":\"feed1\"},{\"number\":2,\"state\":\"CLOSED\",\"url\":\"${U}/2\"}]" > "${ROOT}/prs.json"
# A bare close of a builder whose PR is open closes the builder alone and puts the story in review
# with the PR and a kept: line, logged as kept (never review): no PR closed, the branch and worktree
# kept, nothing counted. gh gives no head here, so its checks are not read.
st() { (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" status 2>&1) || true; }
item o1 "status: ready" "kind: code"; started o1 w:p1
close o1
is "close o1, its PR open: its pane closes, no PR is closed, attempts: unset, its build kept, the PR named" \
  "closed|0||worktree branch origin|1" \
  "$([[ -e "${P}/.swarm/state/o1" ]] && echo open || echo closed)|$(grep -c '^pr close' "${ROOT}/gh.log")|$(attempts o1)|$(left o1)|$(grep -c "^kept (checks not read, not reviewed): o1 is in review with its PR ${U}/1, .*swarm.sh close o1 --drop" "${ROOT}/close.out")"
is "and o1 is in review with prs: its PR and a dated kept: line, logged as kept, not review" "review|${U}/1|yes|1|0" \
  "$(fmv o1 status)|$(fmv o1 prs)|$([[ "$(fmv o1 kept)" == "$(date +%F) close (checks not read, not reviewed)" ]] && echo yes)|$(no_version < "${P}/.swarm/events.tsv" | grep -c $'\tkept\to1\tw:me\tok ('"${U}"'/1; checks not read, not reviewed)$')|$(grep -c $'\treview\to1\t' "${P}/.swarm/events.tsv")"
out="$(st)"
is "status lists o1 as kept, not reviewed, and never as awaiting your merge" "1|0" \
  "$(grep -cx "  kept: o1 ${U}/1 (not reviewed)" <<< "${out}")|$(grep -c "awaiting your merge.*: o1 " <<< "${out}")"
# Its builder closed, the build kept: close o1 --drop still finds the open PR, and clears it all away.
close o1 --drop
is "close o1 --drop after the bare close closes its PR, counts the attempt, clears its build, and o1 is ready again with no prs:" "1|1||ready|" \
  "$(grep -c "^pr close ${U}/1 --comment .*attempt 1 at o1" "${ROOT}/gh.log")|$(attempts o1)|$(left o1)|$(fmv o1 status)|$(fmv o1 prs)"
# With a cause, the kept line's --drop names it. Once the kept PR merges, reconcile finishes the story.
# A review that passed on the PR's head leaves only the checks to say.
item o2 "status: ready" "kind: code"; started o2 w:p17
mkdir -p "${P}/.swarm/reviews"; printf 'head: feed1\n\n## Findings\n\nnone\n' > "${P}/.swarm/reviews/o2.md"
close o2 stalled
is "close o2 stalled keeps the PR, says only that its checks were not read, and names the cause in its --drop" "1|1|review" \
  "$(grep -c "^kept (checks not read): o2 is in review" "${ROOT}/close.out")|$(grep -c "swarm.sh close o2 stalled --drop closes the PR" "${ROOT}/close.out")|$(fmv o2 status)"
# Once it is reviewed, review clears kept:, and status offers it to merge.
(cd "${P}" && bash "${SWARM}" review o2 "${U}/1" >/dev/null 2>&1) || true; out="$(st)"
is "review o2 clears kept:, and status lists o2 as awaiting your merge" "|1|0" \
  "$(fmv o2 kept)|$(grep -c "awaiting your merge: o2 ${U}/1" <<< "${out}")|$(grep -c "kept: o2" <<< "${out}")"
echo "${U}/1 MERGED" > "${ROOT}/pr-states"
(cd "${P}" && PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" reconcile >"${ROOT}/close.out" 2>&1) || true
o2st=gone; [[ ! -f "${P}/docs/stories/o2.md" ]] || o2st="$(fmv o2 status)"; [[ "${o2st}" != "done" ]] || o2st=gone
is "when o2's kept PR merges, reconcile finishes o2 and clears its build" "gone|" "${o2st}|$(left o2)"
: > "${ROOT}/pr-states"
# A stacked child whose parent is open is held by a bare close, as review holds it; --drop still
# clears it, the hold and prs: line with it.
item hp2 "status: review" "kind: code"; item hc2 "status: ready" "kind: code" "depends_on: [hp2]"; started hc2 w:p23
close hc2
is "close hc2, its parent open: held with its PR, the kept line naming --drop" "blocked|hp2|${U}/1|1|worktree branch origin" \
  "$(fmv hc2 status)|$(fmv hc2 held_by)|$(fmv hc2 prs)|$(grep -c "held: it waits for hp2 to merge, .*swarm.sh close hc2 --drop" "${ROOT}/close.out")|$(left hc2)"
: > "${ROOT}/gh.log"; close hc2 --drop
is "close hc2 --drop closes its PR, counts the attempt and clears its build, hold and prs:" "1|1|||" \
  "$(grep -c "^pr close ${U}/1 --comment .*attempt 1 at hc2" "${ROOT}/gh.log")|$(attempts hc2)|$(left hc2)|$(fmv hc2 held_by)|$(fmv hc2 prs)"
rm -f "${P}/docs/stories/hp2.md"
# A parent that costs money is said on the held line, as review says it.
item hp3 "status: review" "kind: code" "costs: money"; item hc3 "status: ready" "kind: code" "depends_on: [hp3]"; started hc3 w:p25
close hc3
is "close hc3, its parent costing money: the held line says so" "1" "$(grep -c "held: it waits for hp3 (costs money) to merge" "${ROOT}/close.out")"
rm -f "${P}/docs/stories/hp3.md"
# A --drop of a story in review whose count cannot be written leaves it in review with its PR.
item rv "status: ready" "kind: code" "attempts: x"; started rv w:p24; close rv; close rv --drop
is "close rv --drop with a bad attempts: leaves rv in review with its PR and build" "review|${U}/1|worktree branch origin|1" \
  "$(fmv rv status)|$(fmv rv prs)|$(left rv)|$(grep -c "attempts must be a non-negative whole number, not 'x'" "${ROOT}/close.out")"
# paused, cleared-on-error and impossible would hand the story on and close the PR: refused while it
# is open, before anything closes.
item o3 "status: ready" "kind: code" "attempts: 1"; started o3 w:p18
rc=0; (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" close o3 paused >"${ROOT}/close.out" 2>&1) || rc=$?
is "close o3 paused with its PR open is refused, naming --drop; its pane, build and story stay" "1|1|open|worktree branch origin|code|ready" \
  "${rc}|$(grep -c 'run swarm.sh close o3 paused --drop for that' "${ROOT}/close.out")|$([[ -e "${P}/.swarm/state/o3" ]] && echo open || echo closed)|$(left o3)|$(fmv o3 kind)|$(fmv o3 status)"
is "and main logs the refusal, not close:paused ok" "0|1" \
  "$(no_version < "${P}/.swarm/events.tsv" | grep -c $'\tclose:paused\to3\tw:me\tok$')|$(grep -c $'\tclose:paused\to3\tw:me\tclose: o3\'s PR ' "${P}/.swarm/events.tsv")"
# A pane that cannot be closed keeps the story as it was, and says so.
touch "${ROOT}/paneclosefail"; close o3; rm "${ROOT}/paneclosefail"
is "with its pane not closing, close o3 prints not closed: and leaves o3 ready, with no prs: or kept:" "1|ready||" \
  "$(grep -c "^not closed: o3's pane is still open" "${ROOT}/close.out")|$(fmv o3 status)|$(fmv o3 prs)|$(fmv o3 kept)"
# The kept state is written before the builder closes: a state_set that dies (its lock held) leaves the
# builder's pane open and the story as it was, and main logs why, not a bare exit status.
item o6 "status: ready" "kind: code"; started o6 w:p26; mkdir -p "${P}/.swarm/board-state/stories/o6.lock"
rc=0; (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me SWARM_LOCK_WAIT=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" close o6 >"${ROOT}/close.out" 2>&1) || rc=$?
rmdir "${P}/.swarm/board-state/stories/o6.lock"
is "close o6 with its state locked fails, its pane open and o6 ready, and main logs the lock" "1|open|ready|1" \
  "${rc}|$([[ -e "${P}/.swarm/state/o6" ]] && echo open || echo closed)|$(fmv o6 status)|$(grep -c $'\tclose\to6\tw:me\tboard state: .*o6 is locked' "${P}/.swarm/events.tsv")"
# --drop with no local branch still names origin's head, read before it is deleted.
item o4 "status: ready" "kind: code"; started o4 w:p21
osha="$(git -C "${ROOT}/origin.git" rev-parse story/o4)"
git -C "${ROOT}/proj-wt/o4" checkout -q --detach && git -C "${P}" branch -q -D story/o4
close o4 --drop
is "close o4 --drop with no local branch prints origin's story/o4 with its head" "1|0" \
  "$(grep -c "^dropped: story/o4 on origin, head ${osha}$" "${ROOT}/close.out")|$(grep -c "^dropped: story/o4 in " "${ROOT}/close.out")"
# impossible while a PR merged is refused, --drop or not, naming the merge.
echo "[{\"number\":3,\"state\":\"MERGED\",\"url\":\"${U}/3\"}]" > "${ROOT}/prs.json"
item o5 "status: ready" "kind: code"; started o5 w:p22
rc=0; (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" close o5 impossible --drop >"${ROOT}/close.out" 2>&1) || rc=$?
is "close o5 impossible --drop with a merged PR is refused, naming the merge; its build stays" "1|1|worktree branch origin" \
  "${rc}|$(grep -c 'a PR on story/o5 merged or is merging' "${ROOT}/close.out")|$(left o5)"
echo "[{\"number\":1,\"state\":\"OPEN\",\"url\":\"${U}/1\",\"headRefOid\":\"feed1\"},{\"number\":2,\"state\":\"CLOSED\",\"url\":\"${U}/2\"}]" > "${ROOT}/prs.json"
: > "${ROOT}/gh.log"
item s1 "status: ready" "kind: code"; started s1 w:p1
sha="$(git -C "${P}" rev-parse story/s1)"
close s1 --drop
is "close s1 --drop prints the PR it closed with its head, and the branch it deleted with its head" "1|1" \
  "$(grep -c "^dropped: ${U}/1, closed unmerged, head feed1 " "${ROOT}/close.out")|$(grep -c "^dropped: story/s1 in ${P}, head ${sha}$" "${ROOT}/close.out")"
is "closing a ready story's open builder writes attempts: 1" "1" "$(attempts s1)"
is "and removes its worktree, local story/s1 and origin's" "" "$(left s1)"
is "and closes its open PR, and only that one, with a comment naming the attempt" "1|0|yes" \
  "$(grep -c "^pr close ${U}/1 --comment .*attempt 1 at s1" "${ROOT}/gh.log")|$(grep -c "^pr close ${U}/2" "${ROOT}/gh.log")|$(grep -q "^pr list -R ${ROOT}/origin.git --head story/s1 --state all --json number,state,url,autoMergeRequest,headRefOid$" "${ROOT}/gh.log" && echo yes)"
close s1
is "closing it again leaves 1" "1" "$(attempts s1)"
echo '[]' > "${ROOT}/prs.json"
mkdir -p "${P}/.claude/swarm"
# Its pane is alone in its tab, so the tab closes with it and the tab record goes.
item k1 "status: ready" "kind: code"; started k1 w:p2
close k1
is "closing a builder closes its pane and never renames it k1-done" "closed|k1 w:p2" \
  "$([[ -e "${P}/.swarm/state/k1" ]] || echo closed)|$(grep ' w:p2$' "${ROOT}/agents")"
# A worktree whose directory was deleted by hand is still registered: it is pruned, so the branch goes.
item w1 "status: ready" "kind: code"; started w1 w:p11; rm -rf "${ROOT}/proj-wt/w1"
close w1
is "a worktree deleted by hand is pruned, so its local and origin branches go too" "1|" "$(attempts w1)|$(left w1)"
# attempts: is read from the front matter alone, never from a body line that starts the same way.
item b1 "status: ready" "kind: code"; echo "attempts: 3" >> "${P}/docs/stories/b1.md"; started b1 w:p12
close b1
is "a body line 'attempts: 3' is not the count: the first failure writes attempts: 1" "1|yes" \
  "$(attempts b1)|$(grep -qx 'attempts: 3' "${P}/docs/stories/b1.md" && echo yes)"
item r1 "status: review" "kind: code"; started r1 w:p3
item rd "status: review" "kind: code"; started rd w:p16; close rd --drop
is "close rd --drop on a story in review drops nothing and says so" "worktree branch origin|1" \
  "$(left rd)|$(grep -c '^not dropped: rd has no build this close can drop' "${ROOT}/close.out")"
item m1 "status: ready" "kind: code"; started m1 w:p4
item g1 "status: ready" "kind: code"; started g1 w:p5
item n1 "status: ready" "kind: code"; started n1
item h1 "status: ready" "kind: code"; started h1; echo "w:p6 h1" > "${P}/.swarm/state/h1"   # its pane closed by hand
item q1 "status: ready" "kind: code"; started q1 w:p13
started d1 w:p7
started conduct-x w:p8; started hld-x w:p9; started plan-x w:p10
close r1; close d1; close n1; close h1; for s in conduct-x hld-x plan-x; do close "${s}"; done
echo "[{\"number\":3,\"state\":\"MERGED\",\"url\":\"${U}/3\"},{\"number\":4,\"state\":\"OPEN\",\"url\":\"${U}/4\"}]" > "${ROOT}/prs.json"
close m1
# Merged but queued: still open, with auto-merge set.
echo "[{\"number\":5,\"state\":\"OPEN\",\"url\":\"${U}/5\",\"autoMergeRequest\":{\"mergeMethod\":\"SQUASH\"}}]" > "${ROOT}/prs.json"
close q1
rm "${ROOT}/prs.json"; touch "${ROOT}/ghfail"
close g1
rm "${ROOT}/ghfail"
is "a gh call that fails is said on stderr" "1" "$(grep -c "g1: could not list the PRs on story/g1" "${ROOT}/close.out")"
item x2 "status: ready" "kind: code" "repo: nosuch"; started x2 w:p15
close x2
is "a repo that cannot be found counts nothing, and stderr names it" "|1" "$(attempts x2)|$(grep -c "x2: no repo at ${ROOT}/nosuch" "${ROOT}/close.out")"
# A slug over 32 characters: herdr knows its builder by the cut agent name; its pane record, in an
# epic's tab beside another pane, keeps the full slug, as start_agent writes it.
L=a-story-whose-slug-runs-well-past-thirty-two-characters
LN="$(cd "${P}" && bash "${SWARM}" _name "${L}")"
item "${L}" "status: ready" "kind: code" "epic: e1"; started "${L}" w:p20
awk -v l="${L}" -v n="${LN}" '$1 == l { $1 = n } { print }' "${ROOT}/agents" > "${ROOT}/agents.tmp" && mv "${ROOT}/agents.tmp" "${ROOT}/agents"
rm "${P}/.swarm/state/${L}"; printf 'w:p19 conductor\nw:p20 %s\n' "${L}" > "${P}/.swarm/state/e1"
echo '[]' > "${ROOT}/prs.json"; : > "${ROOT}/panes-closed"
close "${L}"
is "a slug over 32 characters (agent ${#LN} long) is counted once, cleared, and its pane closed" "1||w:p20|w:p19 conductor" \
  "$(attempts "${L}")|$(left "${L}")|$(cat "${ROOT}/panes-closed")|$(cat "${P}/.swarm/state/e1")"
close "${L}"
is "and closing it again leaves 1" "1" "$(attempts "${L}")"
for s in r1:"a story in review" d1:"a deleted story" m1:"a story whose PR merged" q1:"a story whose open PR has auto-merge set" \
         g1:"a story whose gh call fails" \
         n1:"a ready story with no builder open" h1:"a ready story whose builder's pane was closed by hand" \
         conduct-x:"conduct-x" hld-x:"hld-x" plan-x:"plan-x"; do
  is "closing ${s#*:} writes nothing and removes no worktree or branch" "|worktree branch origin" "$(attempts "${s%%:*}")|$(left "${s%%:*}")"
done
is "no story file is written for a name with none" "" "$(cd "${P}/docs/stories" && ls d1.md conduct-x.md hld-x.md plan-x.md 2>/dev/null)"
is "no PR is closed but s1's" "1" "$(grep -c '^pr close' "${ROOT}/gh.log")"

# --- A counted close of an escalate build (the role on the newest agents.tsv line for the story's
# agent) makes the story the lead's: kind: lead, escalated_from: its kind, still ready, and a
# block in .swarm/state naming the lead's choices and the attempts' PRs. reset puts the story back as it was.
sw() { (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
built() { printf '2026-10-15\t%s\t%s\tclaude\topus\thigh\tsess-%s\n' "$2" "$1" "$1" >> "${P}/.swarm/agents.tsv"; }   # <slug> <role>
state() { echo "$(fmv "$1" kind)|$(fmv "$1" escalated_from)|$(fmv "$1" attempts)|$(fmv "$1" status)"; }
block() { cat "${P}/.swarm/escalated/$1" 2>/dev/null || true; }
echo "[{\"number\":7,\"state\":\"CLOSED\",\"url\":\"${U}/7\"},{\"number\":8,\"state\":\"OPEN\",\"url\":\"${U}/8\"}]" > "${ROOT}/prs.json"
item e1 "status: ready" "kind: code"; cp "${P}/docs/stories/e1.md" "${ROOT}/e1.orig"
for i in 1 2; do started e1 "w:p3${i}"; built e1 code; close e1 --drop; done
is "a counted close of a code build at attempts: 1 leaves kind: code" "code||2|ready" "$(state e1)"
started e1 w:p33; built e1 escalate; close e1 --drop
is "a counted close of an escalate build at attempts: 2: kind: lead, escalated_from: code, attempts: 3, still ready" \
  "lead|code|3|ready" "$(state e1)"
b="$(block e1)"
is "its block names the lead's choices, reset and drop, at most one reset, and both PRs gh listed" "yes|yes|yes|yes|yes" \
  "$(grep -qF 'swarm.sh reset e1 <reason>' <<< "${b}" && echo yes)|$(grep -qF 'swarm.sh drop e1 <reason>' <<< "${b}" && echo yes)|$(grep -qF 'At most one reset per story' <<< "${b}" && echo yes)|$(grep -qx -- "- ${U}/7" <<< "${b}" && echo yes)|$(grep -qx -- "- ${U}/8" <<< "${b}" && echo yes)"
is "the escalated story has no **You:** step" "0" "$(grep -c '\*\*You:\*\*' "${P}/docs/stories/e1.md")"
is "the escalation is logged with the attempts and the PR count" "1" \
  "$(no_version < "${P}/.swarm/events.tsv" | grep -c $'\tescalated\te1\tw:me\tok (attempts 3, 2 PRs)$')"
sw reset e1 re-scoped to the parser alone >/dev/null
is "reset returns the story to what it was before its first counted close" "" "$(diff "${ROOT}/e1.orig" "${P}/docs/stories/e1.md")"
is "after reset, the story is built as code" "code" "$(sw _role e1)"
is "reset is logged with its reason" "1" "$(no_version < "${P}/.swarm/events.tsv" | grep -c $'\treset\te1\tw:me\tok (re-scoped to the parser alone)$')"
item e1 "status: ready" "kind: lead" "attempts: 3" "escalated_from: code"; rc=0; out="$(sw reset e1 again)" || rc=$?
is "a second reset of e1 fails, naming the first, and leaves it kind: lead" "1|yes|lead" \
  "${rc}|$(grep -qF 'reset: e1 was reset already, at ' <<< "${out}" && echo yes)|$(fmv e1 kind)"
item e1 "status: ready" "kind: code" "attempts: 2"; built e1 escalate; started e1 w:p39; close e1 --drop; b="$(block e1)"
is "escalated again after its reset, e1's block offers only drop" "yes|0|yes" \
  "$(grep -qF 'It was reset once already' <<< "${b}" && echo yes)|$(grep -c 'swarm.sh reset e1' <<< "${b}")|$(grep -qF 'swarm.sh drop e1 <reason>' <<< "${b}" && echo yes)"
item n2 "status: ready" "kind: code"; rc=0; out="$(sw reset n2 why)" || rc=$?
is "reset of a story with neither attempts: nor escalated_from: fails, naming it" "1|yes" \
  "${rc}|$(grep -qF 'reset: n2 has neither attempts: nor escalated_from:' <<< "${out}" && echo yes)"
# The role decides, not the count: a code build at attempts: 2 (an older escalate line before it) stays code.
item c2 "status: ready" "kind: code" "attempts: 2"; built c2 escalate; built c2 code; started c2 w:p34; close c2 --drop
is "a code build closed at attempts: 2 writes attempts: 3 and no kind: lead or block" "code||3|ready|" "$(state c2)|$(block c2)"
# A chore round-trips, and so does a story with no kind: line (escalated_from: code (default)).
item ch "status: ready" "kind: chore"; cp "${P}/docs/stories/ch.md" "${ROOT}/ch.orig"
put ch "attempts: 2"; built ch escalate; started ch w:p35; close ch --drop
is "a chore escalates from chore" "lead|chore|3|ready" "$(state ch)"
sw reset ch why >/dev/null
is "and reset returns it as it was" "" "$(diff "${ROOT}/ch.orig" "${P}/docs/stories/ch.md")"
item nk "status: ready"; cp "${P}/docs/stories/nk.md" "${ROOT}/nk.orig"
put nk "attempts: 2"; built nk escalate; started nk w:p36; close nk --drop
is "a story with no kind: line escalates from code (default)" "lead|code (default)|3|ready" "$(state nk)"
sw reset nk why >/dev/null
is "and reset returns it byte for byte, with no kind: line" "" "$(diff "${ROOT}/nk.orig" "${P}/docs/stories/nk.md")"
# The lead re-scoped the kind in the file itself (the board outside the repo), which still says
# code (kind: lead is in the state file): reset keeps it.
item rk "status: ready" "kind: code" "attempts: 2"; built rk escalate; started rk w:p40; close rk --drop
awk '{ sub(/^kind: code$/, "kind: docs") } 1' "${P}/docs/stories/rk.md" > "${ROOT}/rk.tmp" && mv "${ROOT}/rk.tmp" "${P}/docs/stories/rk.md"
sw reset rk why >/dev/null
is "a kind the lead set itself survives reset; escalated_from: and attempts: go" "docs|||ready" "$(state rk)"
item vf "status: ready" "kind: lead" "escalated_from: verify" "attempts: 3"; sw reset vf why >/dev/null
is "escalated_from: verify resets to kind: verify" "verify|||ready" "$(state vf)"
# With no PR on the branch it says so; with gh failing the close counts nothing, so nothing escalates.
echo '[]' > "${ROOT}/prs.json"
item np "status: ready" "kind: code" "attempts: 2"; built np escalate; started np w:p37; close np
is "with no PR on story/np, the block says none was found" "lead|yes" "$(fmv np kind)|$(grep -qx 'No PR was found on story/np.' <<< "$(block np)" && echo yes)"
touch "${ROOT}/ghfail"
item gf "status: ready" "kind: code" "attempts: 2"; built gf escalate; started gf w:p38; close gf
rm "${ROOT}/ghfail"
is "with gh failing the close counts nothing: no attempt, no kind: lead, no block" "code||2|ready|" "$(state gf)|$(block gf)"

# --- close <name> <cause>: met, stalled and bound count as above; impossible, paused and
# cleared-on-error count nothing and still clear the build away, and impossible hands the story to the
# lead. An unknown cause is refused before anything closes; with goal on, so is a missing one while the
# name's story is ready.
cs() { (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" close "$@" 2>&1); }
CAUSES="met, impossible, stalled, bound, paused or cleared-on-error"
echo "[{\"number\":9,\"state\":\"OPEN\",\"url\":\"${U}/9\"}]" > "${ROOT}/prs.json"
item i1 "status: ready" "kind: code" "attempts: 1"; started i1 w:p41; cs i1 impossible --drop >/dev/null
is "close i1 impossible, its builder open: kind: lead, escalated_from: code, attempts: 1, still ready" "lead|code|1|ready" "$(state i1)"
b="$(block i1)"
# shellcheck disable=SC2016 # the backticks are the block's
is "its block is the lead's, with no **You:** step: re-scope Done when and reset, or drop; no epic branch step, and the PR" "0|yes|yes|no|yes" \
  "$(grep -c '\*\*You:\*\*' <<< "${b}")|$(grep -qF -- '- Re-scope its **Done when**' <<< "${b}" && echo yes)|$(grep -qF -- '- Or drop it: run `swarm.sh drop i1 <reason>`' <<< "${b}" && echo yes)|$(grep -qF 'epic/<epic>' <<< "${b}" && echo yes || echo no)|$(grep -qx -- "- ${U}/9" <<< "${b}" && echo yes)"
is "and its build is cleared away" "" "$(left i1)"
# impossible hands a ready story an agent builds to the lead, and clears its worktree and branches so
# a reset builds it again, even when the close finds no build to count: with no builder open, gh
# failing. Then it closes no PR, and the block says the PRs were not listed. Any other story (a
# verify story too, a kind no agent builds), and a name with no story file, is refused before
# anything closes.
unlisted() { grep -qxF "swarm.sh did not list the PRs on story/$1, so look at them before you reset it: \`gh pr list --head story/$1 --state all\` in its repo." <<< "$(block "$1")" && echo yes; }
closed_prs="$(grep -c '^pr close' "${ROOT}/gh.log")"
# A bare close impossible that could not list the PRs is refused: deleting story/<slug> on origin
# would close a PR still open there.
item i5 "status: ready" "kind: code" "attempts: 1"; started i5
rc=0; out="$(cs i5 impossible)" || rc=$?
is "close i5 impossible with no builder open is refused, naming --drop, and keeps its build and story" "1|1|worktree branch origin|code" \
  "${rc}|$(grep -c 'swarm.sh close i5 impossible --drop clears its build anyway; nothing was closed' <<< "${out}")|$(left i5)|$(fmv i5 kind)"
echo '[]' > "${ROOT}/prs.json"
item i2 "status: ready" "kind: code" "attempts: 1"; started i2
rc=0; cs i2 impossible --drop >/dev/null || rc=$?
is "close i2 impossible --drop with no builder open hands it on and clears its build; the block says its PRs were not listed" \
  "0|lead|code|1|ready|yes|" "${rc}|$(state i2)|$(unlisted i2)|$(left i2)"
item i3 "status: ready" "kind: code" "attempts: 1"; started i3 w:p57; touch "${ROOT}/ghfail"
rc=0; out="$(cs i3 impossible --drop)" || rc=$?; rm "${ROOT}/ghfail"
is "with gh failing, close i3 impossible --drop closes its pane, hands it on and clears its build; stderr says gh failed" \
  "0|closed|lead|code|1|ready|yes|yes|" \
  "${rc}|$([[ -e "${P}/.swarm/state/i3" ]] && echo open || echo closed)|$(state i3)|$(grep -qF 'i3: could not list the PRs on story/i3' <<< "${out}" && echo yes)|$(unlisted i3)|$(left i3)"
item v1 "status: ready" "kind: verify" "attempts: 1"; echo "w:p14 v1" > "${P}/.swarm/state/v1"
rc=0; cs v1 impossible >/dev/null || rc=$?
is "close v1 impossible on a ready verify story is refused, as for any kind no agent builds: exit 1, the story as it was" \
  "1|verify||1|ready|0||" "${rc}|$(state v1)|$(grep -c '^- Re-scope its \*\*Done when\*\*' <<< "$(block v1)")|$(unlisted v1)|$(left v1)"
is "and none of them closes a PR, since none was listed" "${closed_prs}" "$(grep -c '^pr close' "${ROOT}/gh.log")"
echo '[]' > "${ROOT}/prs.json"; item i4 "status: ready" "kind: code"; started i4 w:p61; cs i4 impossible >/dev/null
is "when gh lists no PR on story/i4, the block says none was found" "lead|yes" "$(fmv i4 kind)|$(grep -qx 'No PR was found on story/i4.' <<< "$(block i4)" && echo yes)"
echo "[{\"number\":9,\"state\":\"OPEN\",\"url\":\"${U}/9\"}]" > "${ROOT}/prs.json"
item ir "status: review" "kind: code"; started ir w:p58
item il "status: ready" "kind: lead"; started il w:p59
started ix w:p60   # no story file
got=""
for s in ir il ix; do
  rc=0; out="$(cs "${s}" impossible)" || rc=$?
  got+="${rc}|$(grep -qF "close: ${s} cannot be closed impossible, because" <<< "${out}" && echo named || echo unnamed)|$(grep -qsx "w:p[0-9]* ${s}" "${P}/.swarm/state/${s}" && echo open || echo closed) "
done
is "close impossible on a story in review, a lead story or a name with no story file is refused, naming it; its pane stays" \
  "1|named|open 1|named|open 1|named|open " "${got}"
is "and the stories are as they were: ir in review, il kind: lead with no escalated_from: or block" "review|lead||" \
  "$(fmv ir status)|$(fmv il kind)|$(fmv il escalated_from)|$(block il)"
n=42
for c in met stalled bound paused cleared-on-error; do
  item "c-${c}" "status: ready" "kind: code" "attempts: 1"; started "c-${c}" "w:p${n}"; n=$((n + 1)); cs "c-${c}" "${c}" --drop >/dev/null
done
is "met, stalled and bound raise attempts: by one; paused and cleared-on-error leave it" "2|2|2|1|1" \
  "$(attempts c-met)|$(attempts c-stalled)|$(attempts c-bound)|$(attempts c-paused)|$(attempts c-cleared-on-error)"
is "each clears its build away" "||||" "$(left c-met)|$(left c-stalled)|$(left c-bound)|$(left c-paused)|$(left c-cleared-on-error)"
is "an uncounted close closes the open PR with a comment naming its cause, not an attempt" "1" \
  "$(grep -c "^pr close ${U}/9 --comment swarm.sh close: the build of c-paused stopped (paused), which is not an attempt" "${ROOT}/gh.log")"
# paused and cleared-on-error hold the story for the lead when they end a build: kind: lead,
# escalated_from:, held_for: <cause>, and a block naming reset and drop, with no **You:** step. With no
# builder open there is no build to end, and the story file is left as it was.
# shellcheck disable=SC2016 # the backticks are the block's
for c in paused cleared-on-error; do
  b="$(block "c-${c}")"
  is "close c-${c} ${c}, its builder open: kind: lead, escalated_from: code, attempts: 1, held_for: ${c}; the block names reset and drop, no **You:**" \
    "lead|code|1|ready|${c}|0|yes|yes" \
    "$(state "c-${c}")|$(fmv "c-${c}" held_for)|$(grep -c '\*\*You:\*\*' <<< "${b}")|$(grep -qF -- "- Lift the hold: run \`swarm.sh reset c-${c} <reason>\`" <<< "${b}" && echo yes)|$(grep -qF -- "- Or drop it: run \`swarm.sh drop c-${c} <reason>\`" <<< "${b}" && echo yes)"
  item "h-${c}" "status: ready" "kind: code" "attempts: 1"; started "h-${c}"; cp "${P}/docs/stories/h-${c}.md" "${ROOT}/h.md"
  out="$(cs "h-${c}" "${c}")"
  is "close h-${c} ${c} with no builder open leaves the story file unchanged, and says it is not held" "same|1" \
    "$(cmp -s "${ROOT}/h.md" "${P}/docs/stories/h-${c}.md" && echo same)|$(grep -c "^not held: h-${c} (${c}) .*list it for the lead and do not start it again$" <<< "${out}")"
  item "hg-${c}" "status: ready" "kind: code" "attempts: 1"; started "hg-${c}" w:p77; cp "${P}/docs/stories/hg-${c}.md" "${ROOT}/h.md"
  touch "${ROOT}/ghfail"; out="$(cs "hg-${c}" "${c}")"; rm "${ROOT}/ghfail"
  is "close hg-${c} ${c} with gh failing (a merging PR cannot be ruled out) leaves the story file and its build alone, and says it is not held" \
    "same|worktree branch origin|1" "$(cmp -s "${ROOT}/h.md" "${P}/docs/stories/hg-${c}.md" && echo same)|$(left "hg-${c}")|$(grep -c "^not held: hg-${c} " <<< "${out}")"
  started "conduct-h${c}" w:p79; out="$(cs "conduct-h${c}" "${c}")"
  is "close conduct-h${c} ${c}, a name with no story file and its pane open: no read error, no held or not held line" "0" \
    "$(grep -c "No such file\|can't read\|held" <<< "${out}")"
done
# Lifting a hold is not the story's one reset: paused, reset, paused again and reset again each
# succeed with attempts: 1 kept, a failed build then counts from there, and the reset-once rule for
# the rest is unchanged (a real reset still works once, and a second is refused).
rs() { (cd "${P}" && bash "${SWARM}" reset "$@" 2>&1); }
item hr "status: ready" "kind: code" "attempts: 1"; got=""
for i in 1 2; do
  started hr "w:p7${i}"; cs hr paused --drop >/dev/null; got+="$(state hr)/$(fmv hr held_for)/"
  rc=0; rs hr lifted >/dev/null || rc=$?; got+="${rc}|$(state hr)|$(fmv hr held_for)|$(block hr) "
done
is "hr paused, reset, paused, reset: each reset succeeds, attempts: stays 1, kind: code again with no hold or block" \
  "lead|code|1|ready/paused/0|code||1|ready|| lead|code|1|ready/paused/0|code||1|ready|| " "${got}"
started hr w:p73; cs hr met --drop >/dev/null
is "a failed build after the lifted holds counts from there: attempts: 2" "2" "$(attempts hr)"
rc=0; rs hr re-scoped >/dev/null || rc=$?
started hr w:p74; cs hr met --drop >/dev/null; rc2=0; out="$(rs hr again)" || rc2=$?
is "the holds did not use hr's one reset: the first real reset succeeds and a second is refused" "0|1|yes" \
  "${rc}|${rc2}|$(grep -qF 'reset: hr was reset already' <<< "${out}" && echo yes)"
item u1 "status: ready" "kind: code" "attempts: 1"; started u1 w:p50
rc=0; out="$(cs u1 maybe)" || rc=$?
is "close u1 maybe fails naming the six causes, not the word; the pane stays and nothing is counted" "1|yes|0|yes|1" \
  "${rc}|$(grep -qF "${CAUSES}" <<< "${out}" && echo yes)|$(grep -c maybe <<< "${out}")|$(grep -qx 'w:p50 u1' "${P}/.swarm/state/u1" && echo yes)|$(attempts u1)"
is "events.tsv logs it as command close, target u1, with no 'maybe' in the line" "1|0" \
  "$(grep -c $'\tclose\tu1\tw:me\tclose: the cause must be ' "${P}/.swarm/events.tsv")|$(grep -c maybe "${P}/.swarm/events.tsv")"
echo "goal = 5" > "${P}/.claude/swarm/config"
item g5 "status: ready" "kind: code" "attempts: 1"; started g5 w:p51
rc=0; out="$(cs g5)" || rc=$?
is "with goal = 5, close g5 on a ready story fails naming the causes, and closes nothing" "1|yes|yes|1|worktree branch origin" \
  "${rc}|$(grep -qF "${CAUSES}" <<< "${out}" && echo yes)|$(grep -qx 'w:p51 g5' "${P}/.swarm/state/g5" && echo yes)|$(attempts g5)|$(left g5)"
item gr "status: review" "kind: code"; started gr w:p52; started gd w:p53   # gd has no story file
started conduct-g w:p54; started hld-g w:p55; started plan-g w:p56; got=""
for s in gr gd conduct-g hld-g plan-g; do
  rc=0; cs "${s}" >/dev/null || rc=$?; got+="${rc}$([[ -e "${P}/.swarm/state/${s}" ]] && echo open || echo closed) "
done
is "with goal = 5 and no cause, a story in review, a name with no story file, conduct-, hld- and plan- close" \
  "0closed 0closed 0closed 0closed 0closed " "${got}"
: > "${P}/.claude/swarm/config"
rc=0; cs g5 --drop >/dev/null || rc=$?
is "with goal off, close g5 --drop with no cause closes and counts as today" "0|2|" "${rc}|$(attempts g5)|$(left g5)"

# --- A tab close never takes a live agent: one working or waiting (its session's state, or herdr's
# with no session), one whose state cannot be read, or one whose story has an open PR (or whose PRs gh
# could not list). close conduct-<epic> keeps each tab that holds one, naming
# it, and closes the conductor's own pane alone; with --all it closes every tab, and with no live agent
# left it closes every tab as before. Tab ce is the conductor's (herdr's tabs w:t7 and w:t8 are ce, ce-2).
# conductor_fixture <cb1 status> <cb2 status> <ce's second line> — conductor w:p90 in ce, cb1 w:p91 in
# ce-2, and cb2 w:p92 in ce when its line is given.
printf '[{"sessionId":"sess-cb2","status":"busy"}]' > "${ROOT}/claude-agents.json"; export CLAUDE_STUB_AGENTS="${ROOT}/claude-agents.json"
# count <pattern> <file> — the lines of <file> matching <pattern>, 0 when <file> is gone.
count() { local n; n="$(grep -c -- "$1" "$2" 2>/dev/null)" || true; echo "${n:-0}"; }
conductor_fixture() {
  item cb1 "status: review" "kind: code" "epic: ce"
  printf 'w:p90 conductor\n%s' "${3:+$3$'\n'}" > "${P}/.swarm/state/ce"; echo "w:p91 cb1" > "${P}/.swarm/state/ce-2"
  printf '%s\n' "conduct-ce w:p90" "cb1 w:p91 $1" "cb2 w:p92 $2" > "${ROOT}/agents"
  printf '%s\n' "w:p90 w:t7" "w:p91 w:t8" ${3:+"w:p92 w:t7"} > "${ROOT}/panes"
  : > "${CLOSED}"; : > "${ROOT}/panes-closed"
}
open_pr='[{"number":10,"state":"OPEN","url":"'"${U}"'/10","headRefName":"story/cb1"}]'
echo "${open_pr}" > "${ROOT}/prs.json"; conductor_fixture idle idle
out="$(cs conduct-ce)"
is "close conduct-ce, cb1's PR open in tab ce-2: only the conductor's tab closes, and cb1 is printed as kept" \
  "<w:t7>||w:p91 cb1|1" \
  "$(tr -d '\n' < "${CLOSED}")|$(cat "${ROOT}/panes-closed")|$(cat "${P}/.swarm/state/ce-2" 2>/dev/null)|$(grep -c '^kept cb1 (PR open) in tab ce-2' <<< "${out}")"
conductor_fixture idle idle; cs conduct-ce --all >/dev/null
is "close conduct-ce --all closes both tabs" "<w:t7><w:t8>|" "$(tr -d '\n' < "${CLOSED}")|$(ls "${P}/.swarm/state/ce" "${P}/.swarm/state/ce-2" 2>/dev/null)"
echo '[{"number":10,"state":"MERGED","url":"'"${U}"'/10"}]' > "${ROOT}/prs.json"; conductor_fixture idle idle "w:p92 cb2"
cs conduct-ce >/dev/null
is "with every builder merged and idle, close conduct-ce closes every tab as before" "<w:t7><w:t8>|" "$(tr -d '\n' < "${CLOSED}")|$(cat "${ROOT}/panes-closed")"
built cb2 code; conductor_fixture idle idle "w:p92 cb2"; out="$(cs conduct-ce)"
is "cb2 working beside the conductor in ce (its session busy, herdr idle): ce is kept, the conductor's pane closes alone, cb2 is printed as kept, ce-2 closes" \
  "<w:t8>|w:p90|w:p92 cb2|1" \
  "$(tr -d '\n' < "${CLOSED}")|$(cat "${ROOT}/panes-closed")|$(cat "${P}/.swarm/state/ce")|$(grep -c '^kept cb2 (working) in tab ce' <<< "${out}")"
conductor_fixture idle idle; touch "${ROOT}/ghfail"; out="$(cs conduct-ce)"; rm "${ROOT}/ghfail"
is "with gh failing, cb1 is kept, since its PR may be open" "<w:t7>|1" \
  "$(tr -d '\n' < "${CLOSED}")|$(grep -c '^kept cb1 (gh could not list its PRs) in tab ce-2' <<< "${out}")"
conductor_fixture idle idle "w:p92 cb2"; out="$(CLAUDE_STUB_AGENTS="${ROOT}/nosuch" cs conduct-ce)"
is "with Claude Code's list unreadable, cb2 is kept, since it may be working" "<w:t8>|w:p90|1" \
  "$(tr -d '\n' < "${CLOSED}")|$(cat "${ROOT}/panes-closed")|$(grep -c '^kept cb2 (its state could not be read) in tab ce' <<< "${out}")"
conductor_fixture working idle; out="$(cs conduct-ce)"
is "cb1 working by herdr's word (no session recorded) is kept" "<w:t7>|1" \
  "$(tr -d '\n' < "${CLOSED}")|$(grep -c '^kept cb1 (working) in tab ce-2' <<< "${out}")"
conductor_fixture unknown idle; out="$(cs conduct-ce)"
is "cb1 with no session and herdr's status unknown is kept" "<w:t7>|1" \
  "$(tr -d '\n' < "${CLOSED}")|$(grep -c '^kept cb1 (its state could not be read) in tab ce-2' <<< "${out}")"
# herdr's panes decide, not the records: cb4, working, was moved into ce by hand (its record still
# says tab cb4), and cb5 is in ce in no record at all, so its state cannot be read.
conductor_fixture idle idle; echo "w:p94 cb4" > "${P}/.swarm/state/cb4"; echo "cb4 w:p94 working" >> "${ROOT}/agents"; echo "w:p94 w:t7" >> "${ROOT}/panes"
out="$(cs conduct-ce)"
moved="$([[ -e "${P}/.swarm/state/cb4" ]] && echo copied || echo moved)|$(cat "${P}/.swarm/state/"* 2>/dev/null | grep -c '^w:p94 ' || true)"
rm -f "${P}/.swarm/state/cb4"
is "a working builder moved into the conductor's tab by hand keeps the tab" "<w:t8>|w:p90|1" \
  "$(tr -d '\n' < "${CLOSED}")|$(cat "${ROOT}/panes-closed")|$(grep -c '^kept cb4 (working) in tab ce' <<< "${out}")"
is "cb4's line is moved from its old record (tab cb4) to ce's, not copied: one record has it" "moved|1" "${moved}"
# The kept cb4 joins ce's record, so once the conductor's pane, the last one recorded there, closes,
# the tab is still recorded, and --all still closes it.
rec="$(cat "${P}/.swarm/state/ce" 2>/dev/null || true)"; cs conduct-ce --all >/dev/null
is "the kept cb4 joins ce's record, so close conduct-ce --all still closes ce" "w:p94 cb4|<w:t8><w:t7>" "${rec}|$(tr -d '\n' < "${CLOSED}")"
conductor_fixture idle idle; echo "cb5 w:p95 working" >> "${ROOT}/agents"; echo "w:p95 w:t7" >> "${ROOT}/panes"; out="$(cs conduct-ce)"
is "an agent in no tab record, working by herdr's word, is kept, named by herdr" "<w:t8>|1" \
  "$(tr -d '\n' < "${CLOSED}")|$(grep -c '^kept cb5 (working) in tab ce' <<< "${out}")"
is "cb5, with no agents.tsv line here, is not this project's: ce's record never gains it" "0" "$(count 'w:p95' "${P}/.swarm/state/ce")"
is "and close says cb5 stays unrecorded, never that --all closes it" "1|0" \
  "$(grep -c '^kept cb5 (working) in tab ce: no tab record of this project has it, so it stays unrecorded$' <<< "${out}")|$(grep -c '^kept cb5 .*--all closes it too' <<< "${out}")"
# An agent with no name is herdr's to answer for: idle it keeps nothing, working it is kept by its pane.
echo '[]' > "${ROOT}/prs.json"; conductor_fixture idle idle; echo "- w:p97" >> "${ROOT}/agents"; echo "w:p97 w:t7" >> "${ROOT}/panes"; out="$(cs conduct-ce)"
is "an idle agent with no name in ce keeps nothing, and nothing says None" "<w:t7><w:t8>|0" "$(tr -d '\n' < "${CLOSED}")|$(grep -c None <<< "${out}")"
conductor_fixture idle idle; echo "- w:p97 working" >> "${ROOT}/agents"; echo "w:p97 w:t7" >> "${ROOT}/panes"; out="$(cs conduct-ce)"
is "a working agent with no name in ce is kept, named by its pane, and never recorded" "<w:t8>|1|0|0" \
  "$(tr -d '\n' < "${CLOSED}")|$(grep -c '^kept w:p97 (working) in tab ce' <<< "${out}")|$(grep -c None <<< "${out}")|$(count 'w:p97' "${P}/.swarm/state/ce")"
# A story whose repo has no origin has no PR to keep it; a repo that is missing says so, not gh.
git init -q "${ROOT}/noorigin"; echo "${open_pr}" > "${ROOT}/prs.json"
conductor_fixture idle idle; item cb1 "status: review" "kind: code" "epic: ce" "repo: noorigin"; out="$(cs conduct-ce)"
is "cb1's repo has no origin: both tabs close and nothing is kept" "<w:t7><w:t8>|0" "$(tr -d '\n' < "${CLOSED}")|$(grep -c '^kept' <<< "${out}")"
conductor_fixture idle idle; item cb1 "status: review" "kind: code" "epic: ce" "repo: nosuch"; out="$(cs conduct-ce)"
is "cb1's repo is missing: both tabs close, and stderr names the cause, not gh" "<w:t7><w:t8>|1|0" \
  "$(tr -d '\n' < "${CLOSED}")|$(grep -c "cb1: no repo at ${ROOT}/nosuch, so no PR of its was looked for" <<< "${out}")|$(grep -c 'gh could not' <<< "${out}")"
# herdr lists its panes but none in ce-2: the record stands in, so cb1 (PR open) is kept.
conductor_fixture idle idle; echo "w:p90 w:t7" > "${ROOT}/panes"; out="$(cs conduct-ce)"
is "herdr lists no pane in ce-2: its record stands in, so cb1 (PR open) is kept" "<w:t7>|1" \
  "$(tr -d '\n' < "${CLOSED}")|$(grep -c '^kept cb1 (PR open) in tab ce-2' <<< "${out}")"
# A survivor moved out to a new tab (herdr pane move --new-tab) no longer holds its old tab open,
# where cb6, idle with no story, is left.
echo "${open_pr}" > "${ROOT}/prs.json"; conductor_fixture idle idle; echo "cb6 w:p96" >> "${ROOT}/agents"
printf '%s\n' "w:p90 w:t7" "w:p91 w:t9" "w:p96 w:t8" > "${ROOT}/panes"; out="$(cs conduct-ce)"
is "cb1, its PR open, moved out of ce-2 to a new tab: both tabs close and nothing is kept" "<w:t7><w:t8>|0" \
  "$(tr -d '\n' < "${CLOSED}")|$(grep -c '^kept' <<< "${out}")"
# With herdr's pane list failing, the tab records stand in: cb1, recorded in ce-2, is kept.
conductor_fixture idle idle; touch "${ROOT}/panefail"; out="$(cs conduct-ce)"; rm "${ROOT}/panefail"
is "with herdr's pane list failing, the record's cb1 (PR open) is kept" "<w:t7>|1" \
  "$(tr -d '\n' < "${CLOSED}")|$(grep -c '^kept cb1 (PR open) in tab ce-2' <<< "${out}")"
# A builder's close that closes its tab (its last pane) never takes an overflow tab's live builder.
echo "${open_pr}" > "${ROOT}/prs.json"; conductor_fixture idle idle; echo "w:p93 cb3" > "${P}/.swarm/state/ce"; echo "cb3 w:p93" >> "${ROOT}/agents"
printf '%s\n' "w:p93 w:t7" "w:p91 w:t8" > "${ROOT}/panes"
cs cb3 >/dev/null
is "closing cb3, the last pane of tab ce, leaves ce-2 and its builder with an open PR" "<w:t7>|w:p91 cb1" \
  "$(tr -d '\n' < "${CLOSED}")|$(cat "${P}/.swarm/state/ce-2" 2>/dev/null)"
# A long slug's builder in no record is known to herdr by its first 32 characters: its story is found
# from that name, so its open PR keeps ce-2, and with an agents.tsv line it is this project's, recorded
# under its full slug. Claude Code's list is read once for the whole close.
LS=cb-a-story-whose-slug-runs-well-past-thirty-two; LSN="$(cd "${P}" && bash "${SWARM}" _name "${LS}")"
echo '[{"number":10,"state":"OPEN","url":"'"${U}"'/10","headRefName":"story/cb1"},{"number":11,"state":"OPEN","url":"'"${U}"'/11","headRefName":"story/'"${LS}"'"}]' > "${ROOT}/prs.json"
conductor_fixture idle idle; item "${LS}" "status: review" "kind: code" "epic: ce"; built "${LSN}" code
echo "${LSN} w:p98" >> "${ROOT}/agents"; echo "w:p98 w:t8" >> "${ROOT}/panes"; : > "${ROOT}/claude.log"
printf '[{"sessionId":"sess-cb2","status":"busy"},{"sessionId":"sess-%s","status":"idle"}]' "${LSN}" > "${ROOT}/claude-agents.json"
out="$(CLAUDE_STUB_LOG="${ROOT}/claude.log" cs conduct-ce)"
is "${LS} (agent ${LSN}, ${#LSN} long) in no record: its story is found, its PR keeps ce-2, and ce-2 records its full slug" "1|1" \
  "$(grep -c "^kept ${LS} (PR open) in tab ce-2" <<< "${out}")|$(count "^w:p98 ${LS}$" "${P}/.swarm/state/ce-2")"
is "Claude Code's agent list is read once for the whole close" "1" "$(grep -c '^agents --json$' "${ROOT}/claude.log")"
rm -f "${P}/docs/stories/${LS}.md"
# A 32-character name no story's agent has is kept, since its story cannot be found; it is not recorded.
X=zz-a-name-that-is-thirty-two-chr; echo '[]' > "${ROOT}/prs.json"; conductor_fixture idle idle
echo "${X} w:p99" >> "${ROOT}/agents"; echo "w:p99 w:t8" >> "${ROOT}/panes"; out="$(cs conduct-ce)"
is "an idle agent named ${X} (${#X} characters, no story's) keeps ce-2, its story not found, and is not recorded" "<w:t7>|1|0" \
  "$(tr -d '\n' < "${CLOSED}")|$(grep -c "^kept ${X} (its story could not be found) in tab ce-2" <<< "${out}")|$(count 'w:p99' "${P}/.swarm/state/ce-2")"
# With herdr's agent list failing, the conductor's pane comes from its record line, and closes alone
# while ce and ce-2 are kept; with no record naming it either, close says so and fails.
conductor_fixture idle idle "w:p92 cb2"; touch "${ROOT}/agentfail"; rc=0; out="$(cs conduct-ce)" || rc=$?; rm "${ROOT}/agentfail"
is "with herdr's agent list failing, close conduct-ce closes its recorded pane alone and keeps both tabs" "0|w:p90||2" \
  "${rc}|$(cat "${ROOT}/panes-closed")|$(tr -d '\n' < "${CLOSED}")|$(grep -c '^kept cb[12] (herdr gave no agent list, so its state is unknown)' <<< "${out}")"
conductor_fixture idle idle "w:p92 cb2"; echo "w:p92 cb2" > "${P}/.swarm/state/ce"
touch "${ROOT}/agentfail"; rc=0; out="$(cs conduct-ce)" || rc=$?; rm "${ROOT}/agentfail"
is "with herdr's agent list failing and no record naming the conductor, close conduct-ce says its pane is still open and fails" "1|1|" \
  "${rc}|$(grep -c "no tab record names conduct-ce's pane, so it could not be found and is still open" <<< "${out}")|$(cat "${ROOT}/panes-closed")"
# The conductor's pane is its record's conductor line, whatever herdr calls the agent in it: its
# Claude exited to a shell (no agent named conduct-ce), or herdr lists it with no name, working.
echo '[]' > "${ROOT}/prs.json"; conductor_fixture idle working "w:p92 cb2"
awk '$1 != "conduct-ce"' "${ROOT}/agents" > "${ROOT}/agents.tmp" && mv "${ROOT}/agents.tmp" "${ROOT}/agents"; out="$(cs conduct-ce)"
is "conduct-ce's Claude gone from its pane: the record's pane closes alone, ce kept for cb2, ce-2 closes" "w:p90|<w:t8>|1" \
  "$(cat "${ROOT}/panes-closed")|$(tr -d '\n' < "${CLOSED}")|$(grep -c '^kept cb2 (working) in tab ce' <<< "${out}")"
conductor_fixture idle idle
awk '$1 != "conduct-ce"' "${ROOT}/agents" > "${ROOT}/agents.tmp" && mv "${ROOT}/agents.tmp" "${ROOT}/agents"; echo "- w:p90 working" >> "${ROOT}/agents"; out="$(cs conduct-ce)"
is "conduct-ce's pane listed with no name, working: it is the conductor, never kept, so both tabs close" "<w:t7><w:t8>|0" \
  "$(tr -d '\n' < "${CLOSED}")|$(grep -c '^kept' <<< "${out}")"
# A conductor line a gone pane left (w:p89, which herdr no longer lists) is passed over for the live one.
conductor_fixture idle idle "w:p92 cb2"; printf '%s\n' "w:p89 conductor" "w:p90 conductor" "w:p92 cb2" > "${P}/.swarm/state/ce"; out="$(cs conduct-ce)"
is "two conductor lines in ce, w:p89's pane gone: the live w:p90 closes alone, never w:p89" "w:p90|<w:t8>" "$(cat "${ROOT}/panes-closed")|$(tr -d '\n' < "${CLOSED}")"
# Tabs are listed before any is kept: keeping cb1, moved by hand from ce-2 into ce, moves its line
# out of ce-2's record, which then goes, and ce-2 (where cb6, idle with no story, is left) is still
# checked and closed by its herdr id.
conductor_fixture working idle; echo "cb6 w:p96" >> "${ROOT}/agents"; printf '%s\n' "w:p90 w:t7" "w:p91 w:t7" "w:p96 w:t8" > "${ROOT}/panes"
out="$(cs conduct-ce)"
is "cb1 moved into ce keeps ce; ce-2, its record gone with cb1's line, is still closed; ce records cb1" "<w:t8>|w:p90|1|w:p91 cb1" \
  "$(tr -d '\n' < "${CLOSED}")|$(cat "${ROOT}/panes-closed")|$(grep -c '^kept cb1 (working) in tab ce:' <<< "${out}")|$(cat "${P}/.swarm/state/ce" 2>/dev/null || true)"
# own_panes is read whole: sxa's pane w:p80 is recorded with no name, first of 20001 lines, and a
# grep -q fed by a pipe would stop at it and, under pipefail, fail on own_panes' SIGPIPE.
{ echo "w:p80"; seq 1 20000 | sed 's/^/w:q/'; } > "${P}/.swarm/state/aaa-big"
echo "sxa w:p80" > "${ROOT}/agents"; echo "w:p80 w:t3" > "${ROOT}/panes"; : > "${CLOSED}"; : > "${ROOT}/panes-closed"
cs sxa >/dev/null; rm -f "${P}/.swarm/state/aaa-big"
is "close sxa, its pane first of 20001 recorded panes: herdr's pane for it is found, and closes" "w:p80" "$(cat "${ROOT}/panes-closed")"
# Every name the close functions assign by read or for is local, so none leaks into a caller's own
# (close_agent's why, through shut_agent and close_tabs).
leaks="$(python3 -I - "$(dirname "${SWARM}")/lib/lifecycle.sh" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
for fn in ("close_panes", "own_pane", "close_pane", "record_kept", "close_heads", "close_stories", "live_agents", "close_tabs", "close_tab", "tab_ids"):
    body = re.search(r"^%s\(\) \{\n(.*?)^\}" % fn, src, re.S | re.M).group(1)
    body = re.sub(r"^\s*#.*$", "", body, flags=re.M)
    declared = {w.split("=")[0] for m in re.findall(r"\blocal ([^;\n]*)", body) for w in m.split()}
    assigned = set(re.findall(r"(?:^|[;&|]|\bdo|\bthen)\s*for ([a-z_][a-z0-9_]*) in\b", body, re.M))
    for m in re.findall(r"\bread ([^<;\n]*)", body):
        words = m.split()
        assigned |= {w for i, w in enumerate(words) if not w.startswith("-") and not (i and words[i - 1] == "-u") and w != "_"}
    for v in sorted(assigned - declared):
        print(f"{fn}: {v}")
PY
)"
is "the close functions declare every name they read or loop over as local" "" "${leaks}"
# Epics ce and ce-foo: with ce's conductor pane gone, ce-foo's live conductor is never taken for it.
echo '[]' > "${ROOT}/prs.json"; conductor_fixture idle idle; echo "w:p70 conductor" > "${P}/.swarm/state/ce-foo"
awk '$1 != "conduct-ce"' "${ROOT}/agents" > "${ROOT}/agents.tmp" && mv "${ROOT}/agents.tmp" "${ROOT}/agents"; echo "conduct-ce-foo w:p70 working" >> "${ROOT}/agents"
printf '%s\n' "w:p91 w:t8" "w:p70 w:t10" > "${ROOT}/panes"; cs conduct-ce >/dev/null
is "with ce's conductor pane gone, close conduct-ce leaves epic ce-foo's live conductor, its pane and its tab" "0|0|w:p70 conductor" \
  "$(count 'w:p70' "${ROOT}/panes-closed")|$(grep -c '<w:t10>' "${CLOSED}" || true)|$(cat "${P}/.swarm/state/ce-foo" 2>/dev/null || true)"
rm -f "${P}/.swarm/state/ce-foo"
# A state not known to be idle keeps the pane (herdr's starting, with no session); herdr's done is
# finished, as tell reads it.
got=""
for st in starting 'done'; do
  conductor_fixture "${st}" idle; out="$(cs conduct-ce)"
  got+="$(tr -d '\n' < "${CLOSED}")|$(grep -c "^kept cb1" <<< "${out}" || true) "
done
is "cb1 starting (herdr's word, no session) keeps ce-2; cb1 done lets it close" "<w:t7>|1 <w:t7><w:t8>|0 " "${got}"
# cb1's recorded session gone from Claude Code's list (exited, or a new session): herdr's status
# answers, so working keeps ce-2 and idle lets it close.
built cb1 code; got=""
for st in working idle; do
  conductor_fixture "${st}" idle; out="$(cs conduct-ce)"
  got+="$(tr -d '\n' < "${CLOSED}")|$(grep -c '^kept cb1' <<< "${out}" || true) "
done
is "cb1's session gone: herdr's working keeps ce-2, its idle closes it" "<w:t7>|1 <w:t7><w:t8>|0 " "${got}"
# Closing one builder's last pane closes that record's own tab only: overflow ce-2 and epic ce-foo's
# tab, both idle, stay open.
conductor_fixture idle idle; echo "w:p93 cb3" > "${P}/.swarm/state/ce"; echo "cb3 w:p93" >> "${ROOT}/agents"
echo "w:p70 conductor" > "${P}/.swarm/state/ce-foo"; echo "conduct-ce-foo w:p70" >> "${ROOT}/agents"
printf '%s\n' "w:p93 w:t7" "w:p91 w:t8" "w:p70 w:t10" > "${ROOT}/panes"; cs cb3 >/dev/null
is "closing cb3, the last pane of tab ce, closes ce alone; idle ce-2 and ce-foo stay open and recorded" "<w:t7>|w:p91 cb1|w:p70 conductor" \
  "$(tr -d '\n' < "${CLOSED}")|$(cat "${P}/.swarm/state/ce-2" 2>/dev/null || true)|$(cat "${P}/.swarm/state/ce-foo" 2>/dev/null || true)"
rm -f "${P}/.swarm/state/ce-foo"
# herdr's tab list failing keeps each tab, says so, and the close carries on to the conductor's pane.
conductor_fixture idle idle "w:p92 cb2"; touch "${ROOT}/tablistfail"; rc=0; out="$(cs conduct-ce)" || rc=$?; rm "${ROOT}/tablistfail"
is "with herdr's tab list failing, close conduct-ce keeps ce and ce-2, says so, and closes the conductor's pane alone" "0||w:p90|2" \
  "${rc}|$(tr -d '\n' < "${CLOSED}")|$(cat "${ROOT}/panes-closed")|$(grep -c "^kept tab ce[-2]*: herdr could not list its workspace's tabs" <<< "${out}")"
# herdr's pane close failing: the conductor's pane is said to be open, its record keeps it, and close fails.
conductor_fixture idle idle "w:p92 cb2"; touch "${ROOT}/paneclosefail"; rc=0; out="$(cs conduct-ce)" || rc=$?; rm "${ROOT}/paneclosefail"
is "with herdr's pane close failing, close conduct-ce says the pane is still open, keeps its record line, and fails" "1|1|1|0" \
  "${rc}|$(grep -c 'could not close pane conduct-ce (w:p90)' <<< "${out}")|$(count '^w:p90 conductor$' "${P}/.swarm/state/ce")|$(grep -c '^closed pane conduct-ce' <<< "${out}")"
# An epic whose only pane left beside the conductor is a retired builder (cb1-done, retire_agent's
# rename, no agents.tsv line): herdr's done, or any word for a retired name, is finished, so every tab
# closes.
echo '[]' > "${ROOT}/prs.json"; got=""
for st in 'done' unknown; do
  conductor_fixture idle idle; echo "w:p91 cb1-done" > "${P}/.swarm/state/ce-2"
  awk -v s="${st}" '$1 == "cb1" { $1 = "cb1-done"; $3 = s } { print }' "${ROOT}/agents" > "${ROOT}/agents.tmp" && mv "${ROOT}/agents.tmp" "${ROOT}/agents"
  out="$(cs conduct-ce)"; got+="$(tr -d '\n' < "${CLOSED}")|$(grep -c '^kept' <<< "${out}" || true) "
done
is "the retired cb1-done (herdr's done, then unknown) is finished: close conduct-ce closes every tab" "<w:t7><w:t8>|0 <w:t7><w:t8>|0 " "${got}"
# The sweep takes a label's own record and its numbered overflow only: epic ce-foo's idle conductor
# and its tab are never close conduct-ce's.
conductor_fixture idle idle; echo "w:p70 conductor" > "${P}/.swarm/state/ce-foo"; echo "conduct-ce-foo w:p70" >> "${ROOT}/agents"; echo "w:p70 w:t10" >> "${ROOT}/panes"
cs conduct-ce >/dev/null
is "close conduct-ce leaves epic ce-foo's idle conductor, its tab and its record" "<w:t7><w:t8>|0|w:p70 conductor" \
  "$(tr -d '\n' < "${CLOSED}")|$(count 'w:p70' "${ROOT}/panes-closed")|$(cat "${P}/.swarm/state/ce-foo" 2>/dev/null || true)"
rm -f "${P}/.swarm/state/ce-foo"
# A record's last pane whose label herdr has no tab for (tab cz): the pane closes by itself, and only
# then does the record go.
: > "${CLOSED}"; : > "${ROOT}/panes-closed"; echo "w:p93 cb3" > "${P}/.swarm/state/cz"; echo "cb3 w:p93" > "${ROOT}/agents"; echo "w:p93 w:t11" > "${ROOT}/panes"
out="$(cs cb3)"
is "closing cb3, the last pane of cz, which herdr has no tab for, closes its pane and then drops the record" "w:p93|gone|1|0" \
  "$(cat "${ROOT}/panes-closed")|$([[ -e "${P}/.swarm/state/cz" ]] && echo kept || echo gone)|$(grep -c '^closed pane cb3$' <<< "${out}")|$(grep -c '^closed cz$' <<< "${out}" || true)"
# With herdr's tab list failing, closing a record's last pane keeps the pane and the record, says so,
# and succeeds, so a caller (reconcile's loop) carries on.
: > "${CLOSED}"; : > "${ROOT}/panes-closed"; echo "w:p93 cb3" > "${P}/.swarm/state/ce"; echo "cb3 w:p93" > "${ROOT}/agents"; echo "w:p93 w:t7" > "${ROOT}/panes"
touch "${ROOT}/tablistfail"; rc=0; out="$(cs cb3)" || rc=$?; rm "${ROOT}/tablistfail"
is "with herdr's tab list failing, closing cb3, ce's last pane, keeps the pane and its record, says so, and exits 0" "0||w:p93 cb3|1" \
  "${rc}|$(cat "${ROOT}/panes-closed")|$(cat "${P}/.swarm/state/ce" 2>/dev/null || true)|$(grep -c "^kept pane cb3 (w:p93) in tab ce: herdr could not list" <<< "${out}")"
# A recorded pane herdr has no agent in yet (cb2's, its claude still starting) keeps its tab, and the
# conductor's pane closes alone; a pane no record has and no agent is in holds nothing to keep.
echo '[]' > "${ROOT}/prs.json"; got=""
for extra in recorded unrecorded; do
  conductor_fixture idle idle "w:p92 cb2"
  awk '$1 != "cb2"' "${ROOT}/agents" > "${ROOT}/agents.tmp" && mv "${ROOT}/agents.tmp" "${ROOT}/agents"
  [[ "${extra}" == recorded ]] || { echo "w:p90 conductor" > "${P}/.swarm/state/ce"; }
  out="$(cs conduct-ce)"
  got+="$(tr -d '\n' < "${CLOSED}")|$(cat "${ROOT}/panes-closed")|$(grep -c '^kept cb2 (starting: no agent in it yet) in tab ce' <<< "${out}" || true) "
done
is "cb2's pane recorded with no agent in it yet keeps ce (the conductor's pane closes alone); unrecorded, it keeps nothing" \
  "<w:t8>|w:p90|1 <w:t7><w:t8>||0 " "${got}"
# reconcile goes on past a merged story whose builder's pane herdr could not close: rm1's and rm2's
# panes both fail to close, and both stories are still finished, each saying its pane stays open.
printf '%s\n' "${U}/21 MERGED" "${U}/22 MERGED" > "${ROOT}/pr-states"
item rm1 "status: review" "kind: code" "prs: ${U}/21"; item rm2 "status: review" "kind: code" "prs: ${U}/22"; started rm1; started rm2
printf '%s\n' "w:p51 rm1" "w:p52 rm2" > "${P}/.swarm/state/rmt"; printf '%s\n' "rm1 w:p51" "rm2 w:p52" > "${ROOT}/agents"; : > "${ROOT}/panes"
touch "${ROOT}/paneclosefail"; rc=0; out="$(sw reconcile)" || rc=$?; rm "${ROOT}/paneclosefail"
is "reconcile with rm1's and rm2's panes failing to close finishes both (their files deleted), saying each pane stays open, and exits 0" "0|1|1|1|1" \
  "${rc}|$(grep -c 'deleted: .*/stories/rm1.md$' <<< "${out}")|$(grep -c 'deleted: .*/stories/rm2.md$' <<< "${out}")|$(grep -c 'could not close pane rm1 (w:p51)' <<< "${out}")|$(grep -c 'could not close pane rm2 (w:p52)' <<< "${out}")"
is "and keeps rm1's and rm2's builds, since their builders may still be working there, saying so" "worktree branch origin|worktree branch origin|1|1" \
  "$(left rm1)|$(left rm2)|$(grep -c "^build kept: rm1's builder pane is still open" <<< "${out}")|$(grep -c "^build kept: rm2's builder pane is still open" <<< "${out}")"
rm -f "${P}/.swarm/state/rmt"
# A failed build's close whose pane herdr could not close counts and clears nothing: its builder may
# still be working in the worktree.
echo '[]' > "${ROOT}/prs.json"; item pf "status: ready" "kind: code"; started pf w:p88; mkdir -p "${P}/.swarm/zdotdir/pf"
touch "${ROOT}/paneclosefail"; out="$(cs pf)"; rm "${ROOT}/paneclosefail"
is "close pf, its pane failing to close: no attempt counted, its build and its ZDOTDIR left, and it says so" "|worktree branch origin|kept|1" \
  "$(attempts pf)|$(left pf)|$([[ -d "${P}/.swarm/zdotdir/pf" ]] && echo kept || echo gone)|$(grep -c "^not closed: pf's pane is still open, so nothing was counted or cleared" <<< "${out}")"
# herdr's tab close failing keeps each tab's record, says so, and the close carries on to the
# conductor's own pane.
echo '[]' > "${ROOT}/prs.json"; conductor_fixture idle idle; touch "${ROOT}/tabclosefail"; rc=0; out="$(cs conduct-ce)" || rc=$?; rm "${ROOT}/tabclosefail"
is "with herdr's tab close failing, close conduct-ce keeps ce-2's record, says it could not close it, exits 0" "0|w:p91 cb1|1|0" \
  "${rc}|$(cat "${P}/.swarm/state/ce-2" 2>/dev/null || true)|$(grep -c 'could not close tab ce-2 (w:t8)' <<< "${out}")|$(grep -c '^closed ce-2$' <<< "${out}" || true)"
# A live builder whose slug ends in -done (mark-tasks-done, started under that name, so agents.tsv has
# its line) is not retired: starting, it keeps its tab.
conductor_fixture idle idle; built mark-tasks-done code; echo "w:p91 mark-tasks-done" > "${P}/.swarm/state/ce-2"
awk '$1 == "cb1" { $1 = "mark-tasks-done"; $3 = "starting" } { print }' "${ROOT}/agents" > "${ROOT}/agents.tmp" && mv "${ROOT}/agents.tmp" "${ROOT}/agents"
out="$(cs conduct-ce)"
is "mark-tasks-done, a live builder starting, keeps ce-2; its -done is its slug's, not a retirement" "<w:t7>|1" \
  "$(tr -d '\n' < "${CLOSED}")|$(grep -c '^kept mark-tasks-done (state starting) in tab ce-2' <<< "${out}" || true)"
# Two tabs share the label scope-x (herdr's w:t1 and w:t2): sxb, working, is in w:t2 and in no record,
# so both tabs are checked and neither closes.
echo "w:p80 sxa" > "${P}/.swarm/state/scope-x"; printf '%s\n' "sxa w:p80" "sxb w:p81 working" > "${ROOT}/agents"
printf '%s\n' "w:p80 w:t1" "w:p81 w:t2" > "${ROOT}/panes"; : > "${CLOSED}"; out="$(cs scope-x)"
is "two tabs labelled scope-x: sxb working in the second keeps them, and awk reads both ids" "|1|0" \
  "$(tr -d '\n' < "${CLOSED}")|$(grep -c '^kept sxb (working) in tab scope-x' <<< "${out}")|$(grep -c 'newline' <<< "${out}")"
rm -f "${P}/.swarm/state/scope-x"
# The same close (reconcile's path) with herdr's agent list failing keeps ce, where cb1 was moved in
# by hand, its state unknown, and carries on: cb3's pane closes alone, and it exits 0, never dies.
conductor_fixture idle idle; echo "w:p93 cb3" > "${P}/.swarm/state/ce"; echo "cb3 w:p93" >> "${ROOT}/agents"
printf '%s\n' "w:p93 w:t7" "w:p91 w:t7" > "${ROOT}/panes"; touch "${ROOT}/agentfail"; rc=0; out="$(cs cb3)" || rc=$?; rm "${ROOT}/agentfail"
is "with herdr's agent list failing, closing cb3 exits 0, keeps ce for cb1, its state unknown, and closes cb3's pane alone" "0||w:p93|1" \
  "${rc}|$(tr -d '\n' < "${CLOSED}")|$(cat "${ROOT}/panes-closed")|$(grep -c '^kept cb1 (herdr gave no agent list, so its state is unknown) in tab ce:' <<< "${out}")"

# --- A tab close never takes the pane running the command (HERDR_PANE_ID), however idle its agent: a
# review agent idles in its story's tab while its own swarm.sh tell or merge steps the build up or reconciles.
# from_pane <pane|-> <arg>... — swarm.sh run from <pane>, or with HERDR_PANE_ID unset for -.
from_pane() {
  local p="$1"; shift
  [[ "${p}" != - ]] || p=""
  (cd "${P}" && env -u HERDR_PANE_ID ${p:+HERDR_PANE_ID="${p}"} HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1)
}
# Backlog story sp, its builder due a step-up, shares its tab (w:t12) with review-sp, idle. The
# builder's record line has no name, so close finds its pane through herdr and sweeps sp's tab
# (close_tabs). This file's herdr starts no agent, so the step-up stops once the old builder is
# closed (escalate_ladder_test.sh starts the next rung); the close is what is checked.
sp_fixture() {
  printf '%s\n' "w:p101" "w:p102 review-sp" > "${P}/.swarm/state/sp"
  printf '%s\n' "sp w:p101" "review-sp w:p102" > "${ROOT}/agents"; printf '%s\n' "w:p101 w:t12" "w:p102 w:t12" > "${ROOT}/panes"
  : > "${CLOSED}"; : > "${ROOT}/panes-closed"
}
item sp "status: ready" "kind: code"; started sp; built sp code
echo '[{"number":12,"state":"OPEN","url":"'"${U}"'/12","headRefName":"story/sp"}]' > "${ROOT}/prs.json"
echo "escalate_ladder = sonnet,opus,fable" > "${P}/.claude/swarm/config"
sp_fixture; out="$(from_pane w:p102 step-up sp findings-3)" || true
is "step-up sp from review-sp's idle pane closes sp's builder, and keeps review-sp, its tab and its record line, saying why" \
  "w:p101||w:p102 review-sp|1" \
  "$(cat "${ROOT}/panes-closed")|$(tr -d '\n' < "${CLOSED}")|$(cat "${P}/.swarm/state/sp" 2>/dev/null)|$(grep -c '^kept review-sp (the pane running this command) in tab sp:' <<< "${out}")"
sp_fixture; from_pane - step-up sp findings-3 >/dev/null || true
is "with HERDR_PANE_ID unset, the same step-up's sweep closes sp's tab, review-sp with it" "<w:t12>|gone" \
  "$(tr -d '\n' < "${CLOSED}")|$([[ -e "${P}/.swarm/state/sp" ]] && echo kept || echo gone)"
: > "${P}/.claude/swarm/config"
# reconcile, run from a merged story's idle review pane, closes its builder and keeps that pane. Backlog
# story rb's builder, in a record line with no name, sweeps rb's tab (w:t13). Epic story re's builder
# is the last line of ce-2's record, so its close takes that tab, where review-re was moved by hand
# (its line still in ce's record).
item rb "status: review" "kind: code" "prs: ${U}/31"; started rb; echo "${U}/31 MERGED" > "${ROOT}/pr-states"
printf '%s\n' "w:p103" "w:p104 review-rb" > "${P}/.swarm/state/rb"
printf '%s\n' "rb w:p103" "review-rb w:p104" > "${ROOT}/agents"; printf '%s\n' "w:p103 w:t13" "w:p104 w:t13" > "${ROOT}/panes"
: > "${CLOSED}"; : > "${ROOT}/panes-closed"; out="$(from_pane w:p104 reconcile)" || true
is "reconcile from review-rb's idle pane closes backlog story rb's builder, and keeps review-rb and its tab" "w:p103||w:p104 review-rb|1" \
  "$(cat "${ROOT}/panes-closed")|$(tr -d '\n' < "${CLOSED}")|$(cat "${P}/.swarm/state/rb" 2>/dev/null)|$(grep -c '^kept review-rb (the pane running this command) in tab rb:' <<< "${out}")"
item re "status: review" "kind: code" "epic: ce" "prs: ${U}/32"; started re; echo "${U}/32 MERGED" > "${ROOT}/pr-states"
printf '%s\n' "w:p90 conductor" "w:p106 review-re" > "${P}/.swarm/state/ce"; echo "w:p105 re" > "${P}/.swarm/state/ce-2"
printf '%s\n' "conduct-ce w:p90" "re w:p105" "review-re w:p106" > "${ROOT}/agents"; printf '%s\n' "w:p90 w:t7" "w:p105 w:t8" "w:p106 w:t8" > "${ROOT}/panes"
: > "${CLOSED}"; : > "${ROOT}/panes-closed"; out="$(from_pane w:p106 reconcile)" || true
is "reconcile from review-re's idle pane closes epic story re's builder, and keeps review-re and tab ce-2, recorded there now" "w:p105||w:p106 review-re|1" \
  "$(cat "${ROOT}/panes-closed")|$(tr -d '\n' < "${CLOSED}")|$(cat "${P}/.swarm/state/ce-2" 2>/dev/null)|$(grep -c '^kept review-re (the pane running this command) in tab ce-2:' <<< "${out}")"

# --- pane-closed: close_pane logs one line per pane it closes, its target the agent's name, with
# pane= and agent_fields' slug= and role=. review-x shares x's tab with its builder, so its pane closes
# alone; review-y is the last pane of tab other (w:t3), so its pane closes with that tab.
# pane_closed_lines <name> — <outcome> of each pane-closed line on <name>, without version=
pane_closed_lines() { awk -F'\t' -v n="$1" '$2 == "pane-closed" && $3 == n { print $5 }' "${P}/.swarm/events.tsv" | no_version; }
item x "status: review" "kind: code"; built review-x review; built review-y review
printf '%s\n' "w:p70 x" "w:p71 review-x" > "${P}/.swarm/state/x"; echo "w:p72 review-y" > "${P}/.swarm/state/other"
printf '%s\n' "x w:p70" "review-x w:p71" "review-y w:p72" > "${ROOT}/agents"; printf '%s\n' "w:p70 w:t9" "w:p71 w:t9" "w:p72 w:t3" > "${ROOT}/panes"
: > "${CLOSED}"; : > "${ROOT}/panes-closed"; cs review-x >/dev/null || true
is "close review-x closes its pane alone and logs one pane-closed line, slug=x role=review pane=w:p71" \
  "w:p71|ok ~~ pane=w:p71 slug=x role=review" "$(cat "${ROOT}/panes-closed")|$(pane_closed_lines review-x)"
cs review-y >/dev/null || true
is "close review-y closes its tab, its last pane, and logs one pane-closed line for that pane" \
  "<w:t3>|ok ~~ pane=w:p72 slug=y role=review" "$(tr -d '\n' < "${CLOSED}")|$(pane_closed_lines review-y)"
echo "w:p73 review-z" >> "${P}/.swarm/state/x"; echo "review-z w:p73" >> "${ROOT}/agents"
touch "${ROOT}/paneclosefail"; cs review-z >/dev/null || true; rm -f "${ROOT}/paneclosefail"
is "a pane herdr could not close logs no pane-closed line, and its record keeps it" "|w:p73 review-z" \
  "$(pane_closed_lines review-z)|$(grep -x 'w:p73 review-z' "${P}/.swarm/state/x")"
rm -f "${P}/.swarm/state/x" "${P}/.swarm/state/other"

if [[ ${fails} -ne 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
