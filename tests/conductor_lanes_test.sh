#!/usr/bin/env bash
# conductor_lanes_test.sh — conductor_lanes: an epic or the backlog with several conductors, each owning
# its own stories. The config key and its refusals, unblock --startable --lane, a story's lane kept from
# its build's start, lane conductor names, conduct --lane's brief, a lane-less note reaching every lane,
# and conductor_lanes = 1 changing nothing. herdr, gh and claude are stubs on PATH.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
# No trust file here, so require_trusted lets the fixture agents start whatever ~/.claude.json says.
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects" SWARM_NOTE_WAKE_SECS=1
# The claude stub goes first on PATH, so no run here reaches the real claude.
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }
item() { # <board> <path> <front-matter line>...
  local path="$1/$2" title; shift 2
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

# herdr: logs every call; each new pane is w:<n>, each tab t<n>; agent start and list track agents.
# gh: [] for every call but pr list, which finds no PR: a blocked story stacks only on a parent with an open PR.
mkdir -p "${ROOT}/bin"
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
next() { n=$(($(cat "$H/n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/n"; }
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;
  "workspace list")   echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  "tab create")       next; echo "t$n $(echo "$*" | sed 's/.*--label \([^ ]*\).*/\1/')" >> "$H/tabs"
                      echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "tab list")         awk 'BEGIN { printf "{\"result\":{\"tabs\":[" }
                           { printf "%s{\"tab_id\":\"%s\",\"label\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                           END { print "]}}" }' "$H/tabs" 2>/dev/null || echo '{"result":{"tabs":[]}}' ;;
  "agent prompt")     echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent start")      echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')" >> "$H/agents" ;;
  "agent list")       awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                           { printf "%s{\"name\":\"%s\",\"agent_status\":\"working\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                           END { print "]}}" }' "$H/agents" 2>/dev/null || echo '{"result":{"agents":[]}}' ;;
  "pane close"|"tab close") p=$3; [ "$1" = tab ] && p="w:${3#t}"
                      [ -e "$H/agents" ] && awk -v p="$p" '$2 != p' "$H/agents" > "$H/agents.tmp" && mv "$H/agents.tmp" "$H/agents" ;;
esac
EOF
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\ncase "$1 $2" in "pr list") ;; *) echo "[]" ;; esac\n' > "${ROOT}/bin/gh"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh"

# The project: a git repo with a bare origin, so story can make a worktree from origin/main.
g() { git -c user.name=t -c user.email=t@t "$@"; }
g init -q --bare --initial-branch=main "${ROOT}/proj.git"; g clone -q "${ROOT}/proj.git" "${ROOT}/proj" 2>/dev/null
p="${ROOT}/proj"; b="${p}/docs"
mkdir -p "${p}/.claude/swarm"; : > "${p}/.claude/swarm/config"
g -C "${p}" add -A; g -C "${p}" commit -qm init; g -C "${p}" push -q origin HEAD:main 2>/dev/null
run() { (cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
lanes() { echo "conductor_lanes = $1" > "${p}/.claude/swarm/config"; }
# lane_of <slug> <n> — the lane the story says a slug with no lane: line hashes to.
lane_of() { local c; c="$(printf '%s' "$1" | cksum)"; echo $(( ${c%% *} % $2 + 1 )); }
# startable <args> — unblock --startable's slugs, sorted, one line.
startable() { run unblock --startable "$@" | sed -n 's/^startable: \([^ ]*\).*/\1/p' | sort | paste -sd' ' -; }

# --- The config key: a whole number of 1 or more.
got=""
for bad in 0 -1 x 1.5 ""; do
  lanes "${bad}"
  out="$(run config conductor_lanes || echo "exit $?")"
  got+="$(grep -q "conductor_lanes must be" <<< "${out}" && grep -q "exit 1" <<< "${out}" && echo y || echo "n(${bad})")"
done
check "conductor_lanes of 0, -1, x, 1.5 or nothing is refused, naming the key" "yyyyy" "${got}"
: > "${p}/.claude/swarm/config"
check "conductor_lanes defaults to 1" "1" "$(run config conductor_lanes)"

# --- Ready backlog stories, one pinned by its front matter, and one in an epic.
slugs="a1 b2 c3 d4 e5 f6 g7 h8 i9 j10 k11 l12"
for s in ${slugs}; do item "${b}" "stories/${s}.md" "status: ready" "kind: code"; done
pin=pinned; [[ "$(lane_of "${pin}" 3)" != 3 ]] || pin=pinned2   # a slug that would not hash to lane 3
item "${b}" "stories/${pin}.md" "status: ready" "kind: code" "lane: 3"
item "${b}" epics/e.md "status: active"
item "${b}" stories/inep.md "status: ready" "kind: code" "epic: e"
# shellcheck disable=SC2086 # slugs, split on purpose
all="$(printf '%s\n' ${slugs} "${pin}" | sort | paste -sd' ' -)"

# --- conductor_lanes = 1: nothing changes.
check "with conductor_lanes = 1, unblock --startable --backlog prints every ready backlog story" "${all}" "$(startable --backlog)"
check "with conductor_lanes = 1, unblock --startable --lane 1 or --lane 2 prints every ready backlog story, as without it" "${all}|${all}" \
  "$(startable --backlog --lane 1)|$(startable --backlog --lane 2)"
# A start with one lane takes no lane-start lock: one held does not stop it, and it writes no lane.
mkdir -p "${p}/.swarm/lane-start.lock"
run story --strict a1 >/dev/null 2>&1 || true
check "with conductor_lanes = 1, a story --strict start runs while lane-start.lock is held, and writes no lane" "yes|" \
  "$([[ -d "${ROOT}/proj-wt/a1" ]] && echo yes || echo no)|$(grep '^lane:' "${p}/.swarm/board-state/stories/a1" 2>/dev/null || true)"
rmdir "${p}/.swarm/lane-start.lock"
g -C "${p}" worktree remove --force "${ROOT}/proj-wt/a1" 2>/dev/null; g -C "${p}" branch -qD story/a1 2>/dev/null || true
check "with conductor_lanes = 1, conductor names are today's" "conduct-e|yes" \
  "$(run _conductor e)|$([[ "$(run _conductor backlog)" =~ ^conduct-backlog-proj-[0-9a-f]{6}$ ]] && echo yes || echo "no, got: $(run _conductor backlog)")"

# --- conductor_lanes = 3: each lane prints its own stories, and the lanes together each story once.
lanes 3
want2="$(for s in ${slugs}; do [[ "$(lane_of "${s}" 3)" != 2 ]] || echo "${s}"; done | sort | paste -sd' ' -)"
check "some backlog story hashes to lane 2 (the fixture is useful)" "yes" "$([[ -n "${want2}" ]] && echo yes || echo no)"
check "unblock --startable --backlog --lane 2 prints exactly the ready backlog stories in lane 2" "${want2}" "$(startable --backlog --lane 2)"
check "the three lanes together print each ready backlog story once" "${all}" \
  "$(for k in 1 2 3; do run unblock --startable --backlog --lane "${k}" | sed -n 's/^startable: \([^ ]*\).*/\1/p'; done | sort | paste -sd' ' -)"
check "a story with lane: 3 in its front matter is in lane 3 alone" "yes|no" \
  "$(has "${pin}" "$(startable --backlog --lane 3)")|$(grep -qw "${pin}" <<< "$(startable --backlog --lane 1) $(startable --backlog --lane 2)" && echo yes || echo no)"
check "unblock --startable <epic> --lane takes the epic's stories in that lane" "inep" \
  "$(startable e --lane "$(lane_of inep 3)")"
check "--lane 0 and x are refused, and --lane 4 of 3 folds onto lane 1" "yes|yes|$(startable --backlog --lane 1)" \
  "$(has "--lane takes a whole number of 1 or more" "$(run unblock --startable --backlog --lane 0 || true)")|$(has "--lane takes a whole number of 1 or more" "$(run unblock --startable --backlog --lane x || true)")|$(startable --backlog --lane 4)"

# --- A story whose build started in lane 2 stays there when conductor_lanes becomes 2.
mv=""; for s in ${slugs}; do [[ "$(lane_of "${s}" 3)" == 2 && "$(lane_of "${s}" 2)" == 1 ]] && { mv="${s}"; break; }; done
check "some story is in lane 2 of 3 and would hash to lane 1 of 2 (the fixture is useful)" "yes" "$([[ -n "${mv}" ]] && echo yes || echo no)"
run story "${mv}" >"${ROOT}/story.out" || { echo "story failed:"; cat "${ROOT}/story.out"; }
check "story writes its lane to the board state when its build starts" "lane: 2" \
  "$(grep '^lane:' "${p}/.swarm/board-state/stories/${mv}" 2>&1)"
check "a lane start keeps its lock and reservations out of .swarm/state, the tab records' directory" "no|yes" \
  "$(compgen -G "${p}/.swarm/state/lane-start*" >/dev/null && echo yes || echo no)|$([[ -d "${p}/.swarm/lane-start" ]] && echo yes || echo no)"
lanes 2
# Its build died: the worktree and branch go, so it is startable again.
g -C "${p}" worktree remove --force "${ROOT}/proj-wt/${mv}" 2>/dev/null; g -C "${p}" branch -qD "story/${mv}" 2>/dev/null || true
check "with conductor_lanes = 2, the story started in lane 2 is in lane 2, not lane 1" "yes|no" \
  "$(has "${mv}" "$(startable --backlog --lane 2)")|$(grep -qw "${mv}" <<< "$(startable --backlog --lane 1)" && echo yes || echo no)"
check "with conductor_lanes = 2, the lane: 3 story folds onto lane 1, so it is not stranded" "yes" \
  "$(has "${pin}" "$(startable --backlog --lane 1)")"
# Built while folded, the pinned story keeps lane: 3 as written: back at 3 lanes it is lane 3's again.
run story "${pin}" >/dev/null 2>&1 || true
check "story keeps a pinned lane: 3 as written when conductor_lanes is 2" "" \
  "$(grep '^lane: [^3]' "${p}/.swarm/board-state/stories/${pin}" 2>/dev/null || true)"
lanes 3
g -C "${p}" worktree remove --force "${ROOT}/proj-wt/${pin}" 2>/dev/null; g -C "${p}" branch -qD "story/${pin}" 2>/dev/null || true
check "back at conductor_lanes = 3, the pinned story built at 2 is in lane 3" "yes" "$(has "${pin}" "$(startable --backlog --lane 3)")"

# --- Two backlog stories in lanes 1 and 2 touch one function: while lane 1's builds, lane 2 holds its.
item "${b}" stories/cx.md "status: ready" "kind: code" "lane: 1" "touches: [bin/x.sh:f]"
item "${b}" stories/cy.md "status: ready" "kind: code" "lane: 2" "touches: [bin/x.sh:f]"
item "${b}" stories/cz.md "status: ready" "kind: code" "lane: 2" "touches: [bin/z.sh:g]"
mkdir -p "${ROOT}/proj-wt/cx"
out="$(run unblock --startable --backlog --lane 2)"
check "unblock --startable --lane 2 holds a story that clashes with lane 1's running build, and only that one" "yes|yes" \
  "$(has "startable: cy (held: clashes with cx in lane 1 on bin/x.sh:f)" "${out}")|$(has "startable: cz" "$(grep -v held <<< "${out}")")"
out="$(run story --strict cy || true)"
check "story --strict refuses lane 2's story while lane 1's clashing build runs, and makes no worktree" "yes|no" \
  "$(has "cy: clashes with cx in lane 1 on bin/x.sh:f" "${out}")|$([[ -d "${ROOT}/proj-wt/cy" ]] && echo yes || echo no)"
# Another lane's start holds the lane-start lock: this start waits on it, then stops with no worktree.
mkdir -p "${p}/.swarm/lane-start.lock"
out="$(run story --strict cz || true)"
check "while another lane's start holds the lane-start lock, story waits, then stops saying to retry, never to remove it, with no worktree" "yes|no|no" \
  "$(has "retry in a moment" "${out}")|$(grep -q 'remove' <<< "${out}" && echo yes || echo no)|$([[ -d "${ROOT}/proj-wt/cz" ]] && echo yes || echo no)"
rmdir "${p}/.swarm/lane-start.lock"
# A refused start leaves nothing behind: no lane written for a story with none of its own.
nl=""; for s in cq1 cq2 cq3 cq4 cq5; do [[ "$(lane_of "${s}" 3)" == 1 ]] || { nl="${s}"; break; }; done
item "${b}" "stories/${nl}.md" "status: ready" "kind: code" "touches: [bin/x.sh:f]"
run story --strict "${nl}" >/dev/null 2>&1 || true
check "a story --strict refused for a cross-lane clash writes no lane and no reservation" "|no" \
  "$(grep '^lane:' "${p}/.swarm/board-state/stories/${nl}" 2>/dev/null || true)|$([[ -e "${p}/.swarm/lane-start/${nl}" ]] && echo yes || echo no)"
# A closed-unmerged story keeps that note beside the clash, so it is never started.
item "${b}" stories/cw.md "status: ready" "kind: code" "lane: 2" "touches: [bin/x.sh:f]" "prs: https://github.com/o/r/pull/7"
printf '2026-10-24T10:00:00Z\treconcile\tcw\t-\tok (reopened)\n' >> "${p}/.swarm/events.tsv"
check "a clash note goes before a closed-unmerged note, never in its place" "yes" \
  "$(has "startable: cw (held: clashes with cx in lane 1 on bin/x.sh:f; its PR https://github.com/o/r/pull/7 was closed unmerged)" "$(run unblock --startable --backlog --lane 2)")"
rm "${b}/stories/${nl}.md" "${b}/stories/cw.md"
rmdir "${ROOT}/proj-wt/cx"
check "once lane 1's build is gone, lane 2's story is startable again" "no" "$(grep -q 'cy (held' <<< "$(run unblock --startable --backlog --lane 2)" && echo yes || echo no)"
rm "${b}/stories/cx.md" "${b}/stories/cy.md" "${b}/stories/cz.md"

# --- watch --lane: only its lane's PRs, so one lane's watch never takes another lane's report.
item "${b}" stories/wa.md "status: review" "kind: code" "lane: 1"
item "${b}" stories/wb.md "status: review" "kind: code" "lane: 2"
cat > "${ROOT}/bin/gh" <<'EOF'
#!/bin/sh
case "$*" in
  "repo view"*) echo o/r ;;
  "api --paginate repos/o/r/pulls"*) printf '2 bbbbbbbbbb story/wb 5\n1 aaaaaaaaaa story/wa 5\n' ;;
  "api repos/o/r/pulls/"*) echo MERGEABLE ;;
  *check-runs*) echo "1 0" ;;
  *) echo "[]" ;;
esac
EOF
check "watch --backlog --lane 1 reports lane 1's PR, passing lane 2's listed first" "o/r #1 story/wa checks finished on aaaaaaa" "$(run watch --backlog --lane 1)"
check "then watch --backlog --lane 2 still reports lane 2's PR" "o/r #2 story/wb checks finished on bbbbbbb" "$(run watch --backlog --lane 2)"
check "watch --lane with no --epic or --backlog is refused" "yes" "$(has "--lane goes after --epic <slug> or --backlog" "$(run watch --lane 1 || true)")"
# Lowered to 2 lanes, lane 3's surviving conductor watches its folded lane, lane 1.
lanes 2; rm -f "${p}/.swarm/state/watch-seen"
# Under perl's alarm: a watch with no PR in its scope would wait forever.
check "with conductor_lanes = 2, watch --backlog --lane 3 folds onto lane 1 and reports its PR" "o/r #1 story/wa checks finished on aaaaaaa" \
  "$(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" perl -e 'alarm 60; exec @ARGV' bash "${SWARM}" watch --backlog --lane 3 2>&1)"
lanes 3
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\ncase "$1 $2" in "pr list") ;; *) echo "[]" ;; esac\n' > "${ROOT}/bin/gh"
rm "${b}/stories/wa.md" "${b}/stories/wb.md"

# --- Lane conductor names: distinct and at most 32 characters, epic and backlog alike.
lanes 3
long=a-very-long-epic-slug-that-runs-past-the-cut
names="$(for k in 1 2 3; do run _conductor e "${k}"; run _conductor "${long}" "${k}"; run _conductor backlog "${k}"; done)"
check "lane conductor names are distinct" "9" "$(sort -u <<< "${names}" | wc -l | tr -d ' ')"
check "lane conductor names are at most 32 characters" "" "$(awk 'length($0) > 32' <<< "${names}")"
check "a lane conductor's name is conduct-<epic>-l<k>, cut so -l<k> stays" "conduct-e-l2|yes" \
  "$(run _conductor e 2)|$([[ "$(run _conductor "${long}" 3)" == *-l3 ]] && echo yes || echo no)"
bn="$(run _conductor backlog)"
check "the backlog's lane name is its conductor_name with -l<k>" "yes" \
  "$([[ "$(run _conductor backlog 2)" =~ ^conduct-backlog-proj-${bn##*-}-l2$ ]] && echo yes || echo "no, got: $(run _conductor backlog 2)")"

# --- conduct: --lane required, and the lane's brief, report and inbox are its own.
check "with conductor_lanes = 3, conduct --backlog without --lane is refused" "yes" \
  "$(has "start each lane's conductor with swarm.sh conduct --backlog --lane <k>" "$(run conduct --backlog || true)")"
run conduct --backlog --lane 2 >/dev/null
l2="$(run _conductor backlog 2)"
brief="$(cat "${p}/.swarm/briefs/conduct-backlog.l2.md" 2>&1 || true)"
check "conduct --backlog --lane 2 starts the lane's conductor" "yes" "$(has "agent start ${l2} " "$(cat "${ROOT}/herdr.log")")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "the lane brief runs unblock --startable --backlog --lane 2, keeps to its lane, and has its own report and inbox" "yes|yes|yes|yes|yes" \
  "$(has 'swarm.sh unblock --startable --backlog --lane 2' "${brief}")|$(has "You are lane 2 of 3 conductors" "${brief}")|$(has "Never start, tell, close, review or
merge another lane's story or PR" "${brief}")|$(has ".swarm/conduct-backlog.l2.report.md" "${brief}")|$(has ".swarm/inbox/${l2}.md" "${brief}")"
# shellcheck disable=SC2016 # the backticks are the brief's
check "the lane brief watches its lane, folds a lane above 3, holds a cross-lane clash and scopes the Stacked rule" "yes|yes|yes|yes" \
  "$(has 'swarm.sh watch --backlog --lane 2` in the background' "${brief}")|$(has '(lane - 1) mod 3 + 1' "${brief}")|$(has 'whose note starts `(held: clashes with <other> in lane <j>`' "${brief}")|$(has 'Yours is a story with no `epic:` in your lane' "${brief}")"
check "conduct --backlog --lane 2 logs its start as --backlog.l2" "1" \
  "$(awk -F'\t' '$2 == "conduct" && $3 == "--backlog.l2" && $5 == "ok"' "${p}/.swarm/events.tsv" | wc -l | tr -d ' ')"

# --- A note to the lane-less name reaches every lane's inbox.
run conduct --backlog --lane 1 >/dev/null
l1="$(run _conductor backlog 1)"
echo "hello lanes" > "${ROOT}/note"
run tell "${bn}" note "${ROOT}/note" >/dev/null || true
check "a note to the lane-less backlog conductor goes to each running lane's inbox" "yes|yes" \
  "$(has "hello lanes" "$(cat "${p}/.swarm/inbox/${l1}.md" 2>&1)")|$(has "hello lanes" "$(cat "${p}/.swarm/inbox/${l2}.md" 2>&1)")"

# --- Epics foo and foo-l1: foo's lane 1 conductor would take foo-l1's conductor's name, so it is refused.
item "${b}" epics/foo.md "status: active"; item "${b}" epics/foo-l1.md "status: active"
check "conduct foo --lane 1 is refused while an epic foo-l1 holds the name conduct-foo-l1" "yes|no" \
  "$(has "the epic foo-l1's conductor's name" "$(run conduct foo --lane 1 || true)")|$(grep -q '^agent start conduct-foo-l1 ' "${ROOT}/herdr.log" && echo yes || echo no)"

# --- An epic's lane brief watches with --epic <epic> --lane <k>.
item "${b}" epics/w.md "status: active"
run conduct w --lane 2 >/dev/null
# shellcheck disable=SC2016 # the backticks are the brief's
check "an epic lane's brief watches with --epic w --lane 2, everywhere it names watch" "yes|no" \
  "$(has 'Watch with `swarm.sh watch --epic w --lane 2`' "$(cat "${p}/.swarm/briefs/conduct-w.l2.md" 2>&1)")|$(grep -q 'swarm.sh watch w ' "${p}/.swarm/briefs/conduct-w.l2.md" 2>/dev/null && echo yes || echo no)"

# --- An epic slug long enough that the lane-less name and its lane brief's slug cut alike: a note to
# the lane-less name is still lane-less, so it reaches lane 2's inbox.
long26=abcdefghijklmnopqrstuvwxyz
item "${b}" "epics/${long26}.md" "status: active"
run conduct "${long26}" --lane 2 >/dev/null
echo "for the long epic" > "${ROOT}/note3"
run tell "$(run _conductor "${long26}")" note "${ROOT}/note3" >/dev/null || true
check "a note to a long epic's lane-less name reaches its lane 2 conductor's inbox" "yes" \
  "$(has "for the long epic" "$(cat "${p}/.swarm/inbox/$(run _conductor "${long26}" 2).md" 2>&1)")"

# --- A lane's run ends only when nothing of its lane can still need it, and the last lane ends the epic,
# in either merge mode; the backlog's lanes have no epic to end.
w2="$(cat "${p}/.swarm/briefs/conduct-w.l2.md" 2>&1)"
printf 'conductor_lanes = 3\nmerge = agent\n' > "${p}/.claude/swarm/config"
run conduct w --lane 3 >/dev/null
w3="$(cat "${p}/.swarm/briefs/conduct-w.l3.md" 2>&1)"
lanes 3
# shellcheck disable=SC2016 # the backticks are the brief's
check "a lane brief waits on a blocked story, reports its lane done while others run, and ends the epic as the last lane, with merge = human and = agent" "yes|yes|yes|yes|yes|yes|yes" \
  "$(has 'waiting: <slug> (blocked on <parents>)' "${w2}")|$(has 'lane 2 done; <names> still run' "${w2}")|$(has "you are the epic's last lane" "${w2}")|$(has 'swarm.sh review <epic> <every PR URL still waiting>' "${w2}")|$(has "you are the epic's last lane" "${w3}")|$(has 'swarm.sh finish <epic>` only' "${w3}")|$(has "over every lane's PRs" "${w3}")"
check "the backlog's lane brief reports its lane done while others run, and has no epic to end" "yes|no" \
  "$(has 'lane 2 done; <names> still run' "${brief}")|$(grep -q "last lane" <<< "${brief}" && echo yes || echo no)"

# --- unblock --startable --lane: the lane's blocked stories with an open parent wait, and the other lanes
# that have not reported are named; the lane that sees none is the last.
item "${b}" stories/wp.md "status: ready" "kind: code" "epic: w" "lane: 1"
item "${b}" stories/wc.md "status: blocked" "kind: code" "epic: w" "lane: 2" "depends_on: [wp]"
item "${b}" stories/wd.md "status: blocked" "kind: code" "epic: w" "lane: 3" "depends_on: [wp]"
item "${b}" stories/wn.md "status: blocked" "kind: code" "epic: w" "lane: 2"
out="$(run unblock --startable w --lane 2)"
check "unblock --startable w --lane 2 prints waiting: for its story blocked on an open parent, not for one blocked with no depends_on, and names the other lane that has not reported" "yes|no|other lanes running: conduct-w-l3" \
  "$(has 'waiting: wc (blocked on wp)' "${out}")|$(grep -q 'waiting: wn' <<< "${out}" && echo yes || echo no)|$(grep '^other lanes running:' <<< "${out}")"
check "unblock --startable w --lane 1, with no conductor of lane 1, names lanes 2 and 3" "other lanes running: conduct-w-l2 conduct-w-l3" \
  "$(run unblock --startable w --lane 1 | grep '^other lanes running:')"
touch "${p}/.swarm/conduct-w.l3.report.md"
check "once lane 3 has reported, lane 2 sees no other lane running: it is the last" "other lanes running: none" \
  "$(run unblock --startable w --lane 2 | grep '^other lanes running:')"
rm "${p}/.swarm/conduct-w.l3.report.md"
check "with conductor_lanes = 1, unblock --startable prints no waiting: or other lanes line" "" \
  "$(lanes 1; run unblock --startable w | grep -E '^(waiting|other lanes running):'; lanes 3)"
# --- The final check, --done: a lane with a story to wait on is not done, and is not marked.
out="$(run unblock --startable w --lane 2 --done)"
check "unblock --startable w --lane 2 --done with a waiting story says not done, names lane 3, and marks nothing" "yes|other lanes running: conduct-w-l3|no" \
  "$(has 'not done: lane 2 still has a story to start or to wait on' "${out}")|$(grep '^other lanes running:' <<< "${out}")|$([[ -e "${p}/.swarm/lane-done/w.l2" ]] && echo yes || echo no)"

# --- The parent merges (its file goes): unblock readies wc and wd, and notes lane 3's conductor of wd, not
# the lane 2 conductor that ran it of its own wc.
rm "${b}/stories/wp.md"
SWARM_AGENT=conduct-w-l2 run unblock --startable w --lane 2 >/dev/null
check "unblock run by lane 2 notes lane 3's conductor of the story it readied in lane 3, and not lane 2 of its own" "yes|no" \
  "$(has 'unblock readied wd, a story of your lane' "$(cat "${p}/.swarm/inbox/conduct-w-l3.md" 2>&1)")|$(grep -q 'readied wc' "${p}/.swarm/inbox/conduct-w-l2.md" 2>/dev/null && echo yes || echo no)"

# --- The election: with nothing left in lanes 2 and 3, the first --done sees the other, the second sees none;
# a lane with a new story unmarks itself on its next unblock, and the other lane sees it running again.
rm "${b}/stories/wc.md" "${b}/stories/wd.md" "${b}/stories/wn.md"
check "lane 2's --done with nothing left marks it done and still names lane 3" "other lanes running: conduct-w-l3|yes" \
  "$(run unblock --startable w --lane 2 --done | grep '^other lanes running:')|$([[ -e "${p}/.swarm/lane-done/w.l2" ]] && echo yes || echo no)"
check "then lane 3's --done sees no other lane: it is the last" "other lanes running: none" \
  "$(run unblock --startable w --lane 3 --done | grep '^other lanes running:')"
item "${b}" stories/wz.md "status: ready" "kind: code" "epic: w" "lane: 2"
check "a lane woken to a new story unmarks itself on its next unblock without --done, and lane 3 sees it running" "startable: wz|no|other lanes running: conduct-w-l2" \
  "$(run unblock --startable w --lane 2 | grep '^startable:')|$([[ -e "${p}/.swarm/lane-done/w.l2" ]] && echo yes || echo no)|$(run unblock --startable w --lane 3 --done | grep '^other lanes running:')"
check "--done with a startable story of its own is refused as not done" "yes" \
  "$(has 'not done: lane 2' "$(run unblock --startable w --lane 2 --done)")"
rm "${b}/stories/wz.md" "${p}/.swarm/lane-done/w.l3"

# --- What --done counts as the lane's: not a story the lead has (closed unmerged, or left ready by a not held:
# close, which the lane's hold follows), not a wait on a lead story or another epic's, but a wait on this
# epic's agent-built story.
item "${b}" stories/wu.md "status: ready" "kind: code" "epic: w" "lane: 2"
printf '2026-10-25T10:00:00Z\treconcile\twu\t-\tok (reopened)\n' >> "${p}/.swarm/events.tsv"
item "${b}" stories/wv.md "status: ready" "kind: code" "epic: w" "lane: 2"
printf '2026-10-25T10:01:00Z\tclose:paused\twv\tw:1\tok\n2026-10-25T10:02:00Z\thold\twv\tw:1\tok (not held)\n' >> "${p}/.swarm/events.tsv"
out="$(run unblock --startable w --lane 2 --done)"
check "--done with only a closed-unmerged story and a not-held one left ready: prints them, is done, and marks the lane" "yes|yes|no|yes" \
  "$(has 'startable: wu (its PR' "${out}")|$(has 'startable: wv' "${out}")|$(grep -q '^not done' <<< "${out}" && echo yes || echo no)|$([[ -e "${p}/.swarm/lane-done/w.l2" ]] && echo yes || echo no)"
item "${b}" stories/wl.md "status: ready" "kind: lead" "epic: w"
item "${b}" stories/wm.md "status: blocked" "kind: code" "epic: w" "lane: 2" "depends_on: [wl]"
item "${b}" epics/x.md "status: active"; item "${b}" stories/xq.md "status: ready" "kind: code" "epic: x"
item "${b}" stories/wo.md "status: blocked" "kind: code" "epic: w" "lane: 2" "depends_on: [xq]"
item "${b}" stories/wq.md "status: ready" "kind: code" "epic: w" "lane: 1"
item "${b}" stories/wj.md "status: blocked" "kind: lead" "epic: w" "lane: 2" "depends_on: [wq]"
out="$(run unblock --startable w --lane 2 --done)"
check "a wait on a lead story or on another epic's story, or a lead story's own wait, is the lead's: said so, and the lane is done" "yes|yes|yes|no" \
  "$(has "waiting: wm (blocked on wl; the lead's: list it in your report)" "${out}")|$(has "waiting: wo (blocked on xq; the lead's" "${out}")|$(has "waiting: wj (blocked on wq; the lead's" "${out}")|$(grep -q '^not done' <<< "${out}" && echo yes || echo no)"
item "${b}" stories/wr.md "status: blocked" "kind: code" "epic: w" "lane: 2" "depends_on: [wq]"
out="$(run unblock --startable w --lane 2 --done)"
check "a wait on this epic's agent-built story is the lane's: not done" "yes|yes" \
  "$(has 'waiting: wr (blocked on wq)' "${out}")|$(has 'not done: lane 2' "${out}")"
rm "${b}"/stories/{wu,wv,wl,wm,wo,wj,wq,wr,xq}.md "${b}/epics/x.md"; rm -f "${p}/.swarm/lane-done/w.l2"
# A story that failed twice is the lead's with escalation off (the give-up rule), and the lane's build on
# Fable with it on.
item "${b}" stories/wt.md "status: ready" "kind: code" "epic: w" "lane: 2"
mkdir -p "${p}/.swarm/board-state/stories"; printf 'attempts: 2\n' > "${p}/.swarm/board-state/stories/wt"
printf 'conductor_lanes = 3\nescalate_after = 0\n' > "${p}/.claude/swarm/config"
out="$(run unblock --startable w --lane 2 --done)"
check "--done with a story that failed twice and escalate_after = 0: it is the lead's, and the lane is done" "yes|no|yes" \
  "$(has 'startable: wt' "${out}")|$(grep -q '^not done' <<< "${out}" && echo yes || echo no)|$([[ -e "${p}/.swarm/lane-done/w.l2" ]] && echo yes || echo no)"
lanes 3
check "with escalate_after on, the same story is the lane's next build: not done" "yes" "$(has 'not done: lane 2' "$(run unblock --startable w --lane 2 --done)")"
# A child blocked on that parent waits on a merge no lane will make with escalation off: the lead's; with it
# on, the parent is a lane's build, so the wait is the child's lane's.
item "${b}" stories/wt2.md "status: blocked" "kind: code" "epic: w" "lane: 2" "depends_on: [wt]"
printf 'conductor_lanes = 3\nescalate_after = 0\n' > "${p}/.claude/swarm/config"
out="$(run unblock --startable w --lane 2 --done)"
check "a wait on a parent that failed twice with escalate_after = 0 is the lead's: said so, and the lane is done" "yes|no" \
  "$(has "waiting: wt2 (blocked on wt; the lead's: list it in your report)" "${out}")|$(grep -q '^not done' <<< "${out}" && echo yes || echo no)"
lanes 3
check "with escalate_after on, the same wait is the lane's: not done" "yes|yes" \
  "$(out="$(run unblock --startable w --lane 2 --done)"; has 'waiting: wt2 (blocked on wt)' "${out}")|$(has 'not done: lane 2' "$(run unblock --startable w --lane 2 --done)")"
rm "${b}/stories/wt.md" "${b}/stories/wt2.md" "${p}/.swarm/board-state/stories/wt"; rm -f "${p}/.swarm/lane-done/w.l2"

# --- The done marker is the lane's own: under conductor_lanes = 2, --lane 3 folds to lane 1 for its stories
# and marks w.l3, never w.l1.
lanes 2
check "after conductor_lanes drops to 2, lane 3's unblock leaves itself out of the other lanes, not the folded lane 1's conductor" "other lanes running: conduct-w-l2" \
  "$(run unblock --startable w --lane 3 | grep '^other lanes running:')"
run unblock --startable w --lane 3 --done >/dev/null
check "after conductor_lanes drops to 2, lane 3's --done marks w.l3, not the folded w.l1" "yes|no" \
  "$([[ -e "${p}/.swarm/lane-done/w.l3" ]] && echo yes || echo no)|$([[ -e "${p}/.swarm/lane-done/w.l1" ]] && echo yes || echo no)"
lanes 3; rm -f "${p}/.swarm/lane-done/w.l3"

# --- With the epic's file gone (its last story's PR took it), a lane's --done still answers.
mv "${b}/epics/w.md" "${ROOT}/w.md.away"
check "with epic w's file gone, unblock --startable w --lane 2 --done still names the other lanes" "other lanes running: conduct-w-l3" \
  "$(run unblock --startable w --lane 2 --done | grep '^other lanes running:')"
mv "${ROOT}/w.md.away" "${b}/epics/w.md"; rm -f "${p}/.swarm/lane-done/w.l2"

# --- A touches read that fails holds the start, saying it cannot tell, and story --strict refuses it.
mkdir "${b}/stories/broken.md"
item "${b}" stories/wk.md "status: ready" "kind: code" "epic: w" "lane: 2" "touches: [bin/k.sh]"
out="$(run unblock --startable w --lane 2)"
check "when the touches cannot be read, a lane's startable line is held saying it cannot tell, and --strict refuses the start" "yes|yes|no" \
  "$(has "startable: wk (held: cannot read the board's touches" "${out}")|$(has "cannot read the board's touches" "$(run story --strict wk || true)")|$([[ -d "${ROOT}/proj-wt/wk" ]] && echo yes || echo no)"
check "a story held because the touches cannot be read is the lead's: --done is done" "no|yes" \
  "$(run unblock --startable w --lane 2 --done | grep -q '^not done' && echo yes || echo no)|$([[ -e "${p}/.swarm/lane-done/w.l2" ]] && echo yes || echo no)"
rmdir "${b}/stories/broken.md"; rm "${b}/stories/wk.md"; rm -f "${p}/.swarm/lane-done/w.l2"

# --- A build cleared by a close ends a clash too: the other lanes hear, as after a merge.
item "${b}" stories/wa1.md "status: ready" "kind: code" "epic: w" "lane: 1" "touches: [bin/a.sh]"
run story wa1 >/dev/null 2>&1 || true
SWARM_AGENT=conduct-w-l2 run close wa1 impossible --drop >/dev/null 2>&1 || true
check "a close that clears lane 1's build notes lane 3 that the build is gone, not lane 2, which closed it" "yes|no" \
  "$(has "wa1's build is gone (merged or cleared)" "$(cat "${p}/.swarm/inbox/conduct-w-l3.md" 2>&1)")|$(grep -q "wa1's build is gone" "${p}/.swarm/inbox/conduct-w-l2.md" 2>/dev/null && echo yes || echo no)"

# --- Lanes outliving a drop to conductor_lanes = 1 still hear: a story readied by lane 2 is noted to lane 3.
lanes 1
item "${b}" stories/wx.md "status: ready" "kind: code" "epic: w"
item "${b}" stories/wy.md "status: blocked" "kind: code" "epic: w" "depends_on: [wx]"
rm "${b}/stories/wx.md"
SWARM_AGENT=conduct-w-l2 run unblock --startable w --lane 2 >/dev/null
check "with conductor_lanes back at 1, unblock run by lane 2 still notes lane 3 of the story it readied" "yes" \
  "$(has 'unblock readied wy, a story of your lane' "$(cat "${p}/.swarm/inbox/conduct-w-l3.md" 2>&1)")"
lanes 3; rm "${b}/stories/wy.md"

# --- Closing a lane conductor, even with --all, closes its own pane alone while another lane of its epic
# runs: never the epic's tab with another lane's builder in it. The last lane's close takes the epic's tab.
item "${b}" stories/ws.md "status: ready" "kind: code" "epic: w"
run story ws >/dev/null 2>&1 || true
run close conduct-w-l2 --all >/dev/null 2>&1 || true
check "close conduct-w-l2 --all closes its own pane and leaves the builder in the epic's tab" "no|yes" \
  "$(awk '$1 == "conduct-w-l2"' "${ROOT}/agents" | grep -q . && echo yes || echo no)|$(awk '$1 == "ws"' "${ROOT}/agents" | grep -q . && echo yes || echo no)"
run close conduct-w-l3 --all >/dev/null 2>&1 || true
check "close conduct-w-l3 --all, the last lane of w, closes the epic's tab and the builder in it too" "no|no" \
  "$(awk '$1 == "conduct-w-l3"' "${ROOT}/agents" | grep -q . && echo yes || echo no)|$(awk '$1 == "ws"' "${ROOT}/agents" | grep -q . && echo yes || echo no)"

# --- The last lane's close of a long epic whose file is gone, and whose lane-less name cuts at 32: the epic
# comes from the lane's own brief, so the epic's tab still goes with its builder.
l26="$(run _conductor "${long26}" 2)"
item "${b}" stories/lw.md "status: ready" "kind: code" "epic: ${long26}"
run story lw >/dev/null 2>&1 || true
rm "${b}/epics/${long26}.md"
run close "${l26}" --all >/dev/null 2>&1 || true
check "the last lane's close of a long epic whose file is gone still closes the epic's tab and its builder" "no|no" \
  "$(awk -v n="${l26}" '$1 == n' "${ROOT}/agents" | grep -q . && echo yes || echo no)|$(awk '$1 == "lw"' "${ROOT}/agents" | grep -q . && echo yes || echo no)"

# --- A lane-less conductor of e from conductor_lanes = 1 still runs: no lane of e starts beside it.
lanes 1
run conduct e >/dev/null
lanes 3
check "with e's lane-less conductor running, conduct e --lane 1 is refused naming it" "yes|no" \
  "$(has "conduct-e runs for e under another conductor_lanes" "$(run conduct e --lane 1 || true)")|$(grep -q '^agent start conduct-e-l1 ' "${ROOT}/herdr.log" && echo yes || echo no)"

# --- foo's lane 2 (conduct-foo-l2) runs: a lane-less conduct of an epic foo-l2 would take its name.
run conduct foo --lane 2 >/dev/null
item "${b}" epics/foo-l2.md "status: active"
lanes 1
check "with foo's lane 2 running, conduct foo-l2 is refused naming it, and starts nothing" "yes|1" \
  "$(has "conduct-foo-l2 is the name of foo's running conductor" "$(run conduct foo-l2 || true)")|$(grep -c '^agent start conduct-foo-l2 ' "${ROOT}/herdr.log")"

# --- Lowered to 2 lanes, lane 3's conductor starts a fix-main story: its lane is folded onto lane 1.
lanes 2
item "${b}" stories/fix-main-abc1234.md "status: ready" "kind: code"
SWARM_AGENT="$(run _conductor backlog 3)" run story fix-main-abc1234 >/dev/null 2>&1 || true
check "a fix-main story started by lane 3's conductor after conductor_lanes became 2 is written as lane 1" "lane: 1" \
  "$(grep '^lane:' "${p}/.swarm/board-state/stories/fix-main-abc1234" 2>&1)"

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
