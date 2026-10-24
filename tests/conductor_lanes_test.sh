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
esac
EOF
printf '#!/bin/sh\necho "[]"\n' > "${ROOT}/bin/gh"
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
for bad in 0 -1 x 1.5 ""; do
  lanes "${bad}"
  check "conductor_lanes = '${bad}' is refused" "yes" "$(has "conductor_lanes" "$(run config conductor_lanes || true)")"
  out="$(run config conductor_lanes || echo "exit $?")"
  check "conductor_lanes = '${bad}' fails" "yes" "$(has "exit 1" "${out}")"
done
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
check "with conductor_lanes = 1, --lane is refused" "yes" "$(has "--lane needs conductor_lanes above 1" "$(run unblock --startable --backlog --lane 1 || true)")"
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
check "--lane 0, 4 and x are refused" "yes|yes|yes" \
  "$(has "--lane takes 1 to 3" "$(run unblock --startable --backlog --lane 0 || true)")|$(has "--lane takes 1 to 3" "$(run unblock --startable --backlog --lane 4 || true)")|$(has "--lane takes 1 to 3" "$(run unblock --startable --backlog --lane x || true)")"

# --- A story whose build started in lane 2 stays there when conductor_lanes becomes 2.
mv=""; for s in ${slugs}; do [[ "$(lane_of "${s}" 3)" == 2 && "$(lane_of "${s}" 2)" == 1 ]] && { mv="${s}"; break; }; done
check "some story is in lane 2 of 3 and would hash to lane 1 of 2 (the fixture is useful)" "yes" "$([[ -n "${mv}" ]] && echo yes || echo no)"
run story "${mv}" >"${ROOT}/story.out" || { echo "story failed:"; cat "${ROOT}/story.out"; }
check "story writes its lane to the board state when its build starts" "lane: 2" \
  "$(grep '^lane:' "${p}/.swarm/board-state/stories/${mv}" 2>&1)"
lanes 2
# Its build died: the worktree and branch go, so it is startable again.
g -C "${p}" worktree remove --force "${ROOT}/proj-wt/${mv}" 2>/dev/null; g -C "${p}" branch -qD "story/${mv}" 2>/dev/null || true
check "with conductor_lanes = 2, the story started in lane 2 is in lane 2, not lane 1" "yes|no" \
  "$(has "${mv}" "$(startable --backlog --lane 2)")|$(grep -qw "${mv}" <<< "$(startable --backlog --lane 1)" && echo yes || echo no)"
check "with conductor_lanes = 2, the lane: 3 story folds onto lane 1, so it is not stranded" "yes" \
  "$(has "${pin}" "$(startable --backlog --lane 1)")"

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

# --- A note to the lane-less name reaches every lane's inbox.
run conduct --backlog --lane 1 >/dev/null
l1="$(run _conductor backlog 1)"
echo "hello lanes" > "${ROOT}/note"
run tell "${bn}" note "${ROOT}/note" >/dev/null || true
check "a note to the lane-less backlog conductor goes to each running lane's inbox" "yes|yes" \
  "$(has "hello lanes" "$(cat "${p}/.swarm/inbox/${l1}.md" 2>&1)")|$(has "hello lanes" "$(cat "${p}/.swarm/inbox/${l2}.md" 2>&1)")"

# --- Epics foo and foo-l1: foo's lane 1 conductor (conduct-foo-l1) is still foo's lane 1, so a note to
# it lands in its own inbox rather than fanning out to foo-l1's lanes.
item "${b}" epics/foo.md "status: active"; item "${b}" epics/foo-l1.md "status: active"
run conduct foo --lane 1 >/dev/null
echo "for foo lane 1" > "${ROOT}/note2"
run tell conduct-foo-l1 note "${ROOT}/note2" >/dev/null || true
check "with an epic foo-l1 on the board, a note to foo's lane 1 conductor reaches its inbox" "yes" \
  "$(has "for foo lane 1" "$(cat "${p}/.swarm/inbox/conduct-foo-l1.md" 2>&1)")"

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
