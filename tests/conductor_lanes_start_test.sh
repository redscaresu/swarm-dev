#!/usr/bin/env bash
# conductor_lanes_start_test.sh — the swarm starts and watches every lane's conductor: a board merge
# that readies backlog stories in two lanes starts both lane conductors, next names the conduct step of
# a lane with ready stories and no conductor while another lane's works, a reported lane is collected
# whatever its session's state while a sibling lane works, and with conductor_lanes = 1 the steps are as
# before. gh, herdr and claude are
# stubs on PATH.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects"
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}"
fails=0
check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# herdr: each new pane is w:<n>; agent start adds "<name> <pane>" to agents, which agent list reads
# (a third column, when a case writes one, is its status), and fails while listfail exists, or once
# herdr.log counts more agent list calls than listfail-after holds; agent read prints screen.<pane>.
mkdir -p "${ROOT}/bin"
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;
  "workspace list")   echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  "tab create")       n=$(($(cat "$H/n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/n"
                      echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "tab list")         echo '{"result":{"tabs":[]}}' ;;
  "agent prompt")     echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent start")      echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')" >> "$H/agents" ;;
  "agent read")       cat "$H/screen.$3" 2>/dev/null ;;
  "agent list")       [ ! -e "$H/listfail" ] || exit 1
                      [ ! -e "$H/listfail-after" ] || [ "$(grep -c '^agent list' "$H/herdr.log")" -le "$(cat "$H/listfail-after")" ] || exit 1
                      awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                           { printf "%s{\"name\":\"%s\",\"agent_status\":\"%s\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, ($3 == "" ? "working" : $3), $2 }
                           END { print "]}}" }' "$H/agents" 2>/dev/null || echo '{"result":{"agents":[]}}' ;;
esac
EOF
# gh: what merge --board asks of a green board PR #7 in o/r, from ${FX}: its head, state and files;
# pr merge marks it merged at origin's tip (${FX}/oid). Every check, status and run is green.
FX="${ROOT}/fx"; H1=1111111111111111111111111111111111111111; URL=https://github.com/o/r/pull/7
printf '#!/usr/bin/env bash\nFX="%s"\n' "${FX}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'EOF'
green() { printf '{"name":"%s","status":"completed","conclusion":"success","html_url":"https://github.com/o/r/runs/1","path":".github/workflows/ci.yml","head_sha":"%s"}' "$1" "$2"; }
case "$1 $2" in
  "pr view")   printf '{"state":"%s","headRefOid":"%s","baseRefName":"main","mergeCommit":%s,"changedFiles":%s,"body":null,"commits":[{}]}\n' \
                 "$(cat "${FX}/state")" "$(cat "${FX}/head")" "$(cat "${FX}/mergecommit")" "$(cat "${FX}/nfiles")" ;;
  "pr merge")  echo MERGED > "${FX}/state"; printf '{"oid":"%s"}' "$(cat "${FX}/oid")" > "${FX}/mergecommit" ;;
  "repo view") case "$*" in *nameWithOwner*) echo '{"nameWithOwner":"o/r"}' ;;
                 *) echo '{"squashMergeAllowed":true,"mergeCommitAllowed":true,"rebaseMergeAllowed":true}' ;; esac ;;
  "pr diff")   : ;;
  "pr list")   echo '[]' ;;
  api*)
    for a in "$@"; do path="${a}"; done
    sha="${path#*/commits/}"; sha="${sha%%/*}"
    case "${path}" in
      *"mergeQueue(branch"*) echo '{"data":{"repository":{"mergeQueue":null}}}' ;;
      */check-runs*) echo "{\"total_count\":1,\"check_runs\":[$(green test "${sha}")]}" ;;
      */commits/*/status*) echo '{"total_count":0,"statuses":[]}' ;;
      */actions/runs*) sha="${path#*head_sha=}"; echo "{\"total_count\":1,\"workflow_runs\":[$(green ci "${sha%%&*}")]}" ;;
      */pulls/*/files*) case " $* " in *" --slurp "*) echo "[$(cat "${FX}/files")]" ;; *) cat "${FX}/files" ;; esac ;;
      */rules/branches/*) echo '[]' ;;
      */branches/*) echo "gh: Branch not protected (HTTP 404)" >&2; exit 1 ;;
      */contents/.github/workflows\?*) echo '[{"name":"ci.yml","path":".github/workflows/ci.yml","type":"file"}]' ;;
      */contents/*) printf 'name: ci\non:\n  push:\n    branches: [main]\n' ;;
      */commits/*) echo '{"files":[{"filename":"bin/x"}]}' ;;
      *) echo "stub: no fixture for ${path}" >&2; exit 1 ;;
    esac ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
EOF
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh"

# The project, its board in the repo, with a bare origin; up is another clone, where a board PR's
# merge lands.
g() { git -c user.name=t -c user.email=t@t "$@"; }
g init -q --bare --initial-branch=main "${ROOT}/origin.git"; g clone -q "${ROOT}/origin.git" "${ROOT}/proj" 2>/dev/null
p="${ROOT}/proj"; mkdir -p "${p}/docs/stories" "${p}/docs/epics" "${p}/.claude/swarm"; touch "${p}/docs/stories/.keep"
g -C "${p}" add -A; g -C "${p}" commit -qm init; g -C "${p}" push -q origin HEAD:main 2>/dev/null; g -C "${p}" branch -q -u origin/main
g clone -q "${ROOT}/origin.git" "${ROOT}/up" 2>/dev/null
config() { printf '%s\n' "merge = agent" "lead_epics = on" "$@" > "${p}/.claude/swarm/config"; }
put() { # <path> <front-matter line>... — a board file in up, staged
  mkdir -p "$(dirname "${ROOT}/up/$1")"; { echo ---; printf '%s\n' "${@:2}"; echo ---; } > "${ROOT}/up/$1"; g -C "${ROOT}/up" add -f "$1"
}
# land — commit up's staged board files to origin, as board PR #7's merge, and point gh's PR at them.
land() {
  g -C "${ROOT}/up" commit -q -m land; g -C "${ROOT}/up" push -q origin HEAD:main 2>/dev/null
  rm -rf "${FX}"; mkdir -p "${FX}"; echo OPEN > "${FX}/state"; echo "${H1}" > "${FX}/head"; echo null > "${FX}/mergecommit"
  g -C "${ROOT}/up" rev-parse HEAD > "${FX}/oid"
  g -C "${ROOT}/up" diff --name-only HEAD~1 HEAD | python3 -c 'import json, sys; print(json.dumps([{"filename": l.strip(), "status": "added"} for l in sys.stdin]))' > "${FX}/files"
  g -C "${ROOT}/up" diff --name-only HEAD~1 HEAD | wc -l | tr -d ' ' > "${FX}/nfiles"
}
swarm() { (cd "${p}" && env -u SWARM_PROJECT -u SWARM_AGENT HERDR_ENV=1 HERDR_PANE_ID=w:lead HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" \
  SWARM_MERGE_POLL=0 SWARM_MERGE_READ_WAIT=0 SWARM_MERGE_CI_GRACE=0 SWARM_MERGE_CI_SECONDS=5 bash "${SWARM}" "$@" 2>&1); }
step() { swarm next | sed -n 1p; }
# collected <conductor> — the lead collected it: an ok close in events.tsv, as swarm.sh close logs one.
collected() { printf '%s\tclose\t%s\t-\tok\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "${p}/.swarm/events.tsv"; }
# hook — the lead's stop hook in the project: nothing when it allows the stop, else its block decision.
hook() { (cd "${p}" && echo "{\"cwd\":\"${p}\"}" | env -u SWARM_PROJECT -u SWARM_AGENT HERDR_ENV=1 HERDR_BIN_PATH="${ROOT}/bin/herdr" PATH="${ROOT}/bin:${PATH}" \
  bash "$(dirname "${SWARM}")/../hooks/lead-stop.sh" 2>/dev/null); }
# lane_of <slug> <n> — the lane a slug with no lane: line hashes to.
lane_of() { local c; c="$(printf '%s' "$1" | cksum)"; echo $(( ${c%% *} % $2 + 1 )); }
# a story slug in each of two lanes
for s in s1 s2 s3 s4 s5 s6 s7 s8; do
  if [[ "$(lane_of "${s}" 2)" == 1 ]]; then in1="${in1:-${s}}"; else in2="${in2:-${s}}"; fi
done
check "the fixture has a slug in each of two lanes" "yes" "$([[ -n "${in1:-}" && -n "${in2:-}" ]] && echo yes || echo no)"

# --- conductor_lanes = 2: a board PR readies a backlog story in each lane; its merge starts both lanes' conductors.
config "conductor_lanes = 2"
put "docs/stories/${in1}.md" "status: ready" "kind: code"; put "docs/stories/${in2}.md" "status: ready" "kind: code"; land
out="$(swarm merge --board "${URL}" || echo "exit $?")"
l1="$(swarm _conductor backlog 1)"; l2="$(swarm _conductor backlog 2)"
check "a board merge that readies a backlog story in each lane: it merged" "yes" "$(grep -q "^merged: ${URL}" <<< "${out}" && echo yes || echo "no, got: ${out}")"
check "a board merge that readies a backlog story in each lane: starts lane 1's and lane 2's conductors" "yes|yes" \
  "$(grep -q "^agent start ${l1} " "${ROOT}/herdr.log" && echo yes || echo no)|$(grep -q "^agent start ${l2} " "${ROOT}/herdr.log" && echo yes || echo no)"
check "a board merge that readies a backlog story in each lane: says it started each with conduct --backlog --lane" "yes|yes" \
  "$(grep -qF "started: ${l1} (swarm.sh conduct --backlog --lane 1)" <<< "${out}" && echo yes || echo no)|$(grep -qF "started: ${l2} (swarm.sh conduct --backlog --lane 2)" <<< "${out}" && echo yes || echo no)"
check "a board merge that readies a backlog story in each lane: starts no lane-less conductor" "no" \
  "$(grep -q "^agent start $(swarm _conductor backlog) " "${ROOT}/herdr.log" && echo yes || echo no)"

# --- next while one lane's conductor runs: the other lane's conduct step.
check "next with both lanes running waits on one" "wait ${l1}" "$(step)"
# Outside herdr next sees no running conductor, yet each lane's runs: it waits on one, never a lane-less step.
check "next outside herdr with both lanes running waits on lane 1" "wait ${l1}" \
  "$(cd "${p}" && env -u SWARM_PROJECT -u SWARM_AGENT -u HERDR_ENV PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" _step 2>&1 | sed -n 1p)"

lane2="$(grep "^${l2} " "${ROOT}/agents")"; grep -v "^${l2} " "${ROOT}/agents" > "${ROOT}/agents.1"; mv "${ROOT}/agents.1" "${ROOT}/agents"
check "next with lane 1 running prints lane 2's conduct step" "conduct --backlog --lane 2" "$(step)"
check "_step, which the lead's stop hook reads, prints the same" "conduct --backlog --lane 2" "$(swarm _step | sed -n 1p)"
# The step keeps what the wait on lane 1 would say: start wait --until-report on it in the background, and the also: lead lines.
printf -- '---\nstatus: ready\nkind: lead\n---\n' > "${p}/docs/stories/lead1.md"
printf -- '---\nstatus: blocked\nkind: code\ndepends_on: [lead1]\n---\n' > "${p}/docs/stories/blk1.md"
out="$(swarm next)"
check "next with lane 1 running: lane 2's why says to start wait --until-report on lane 1 in the background" "yes" \
  "$(grep -qF "the conductor ${l1} is still working: start swarm.sh wait --until-report ${l1} in the background" <<< "${out}" && echo yes || echo "no, got: ${out}")"
check "next with lane 1 running: lane 2's step keeps the also: lead line" "yes" "$(grep -qx "also: lead lead1 blocks blk1" <<< "${out}" && echo yes || echo "no, got: ${out}")"
rm -f "${p}/docs/stories/lead1.md" "${p}/docs/stories/blk1.md"
# herdr's list fails after next saw lane 1 (a transient): the wait on lane 1 stays, never a step the lead would stop on.
: > "${ROOT}/herdr.log"; echo 1 > "${ROOT}/listfail-after"
check "next with lane 1 running, then herdr's list failing, keeps the wait on lane 1" "wait ${l1}" "$(swarm _step | sed -n 1p)"
rm -f "${ROOT}/listfail-after"
# An active epic e with a story in each lane and no conductor, its files sorted after the backlog's: epic e's
# lane 1 is the step (an active epic first, as the lane-less arms put it), its lane 2 and the backlog's lane 2 on also: lines.
for s in z1 z2 z3 z4 z5 z6 z7 z8; do
  if [[ "$(lane_of "${s}" 2)" == 1 ]]; then ze1="${ze1:-${s}}"; else ze2="${ze2:-${s}}"; fi
done
check "the fixture has an epic slug in each of two lanes" "yes" "$([[ -n "${ze1:-}" && -n "${ze2:-}" ]] && echo yes || echo no)"
mkdir -p "${p}/docs/epics"; printf -- '---\nstatus: active\n---\n' > "${p}/docs/epics/e.md"
for s in "${ze1}" "${ze2}"; do printf -- '---\nstatus: ready\nkind: code\nepic: e\n---\n' > "${p}/docs/stories/${s}.md"; done
out="$(swarm next)"
check "next with epic e's lanes both empty, its stories after the backlog's: epic e's lane 1 is the step" "conduct e --lane 1" "$(sed -n 1p <<< "${out}")"
check "next with epic e's lanes both empty: its lane 2 and the backlog's lane 2 on also: lines" "yes|yes" \
  "$(grep -qx "also: conduct e --lane 2" <<< "${out}" && echo yes || echo no)|$(grep -qx "also: conduct --backlog --lane 2" <<< "${out}" && echo yes || echo "no, got: ${out}")"
rm -f "${p}/docs/epics/e.md" "${p}/docs/stories/${ze1}.md" "${p}/docs/stories/${ze2}.md"

# --- collect: a lane that has reported is collected while another lane of the backlog works, whatever its
# session's state (gone here: Claude Code lists none under its id), as a lane-less conductor with a report is.
echo "${lane2}" >> "${ROOT}/agents"
touch "${p}/.swarm/conduct-backlog.l1.report.md"
check "next with lane 1 reported, its session gone, while lane 2 works collects lane 1" "collect ${l1}" "$(step)"
touch "${p}/.swarm/conduct-backlog.l2.report.md"
check "next with every lane reported collects lane 1" "collect ${l1}" "$(step)"
# Collected, their reports newer than every story: a new conductor would stop as the last did.
lane1="$(grep "^${l1} " "${ROOT}/agents")"; : > "${ROOT}/agents"; collected "${l1}"; collected "${l2}"
out="$(swarm next)"
check "next with both lanes collected and nothing changed: lane 1's step, its why the stop" "conduct --backlog --lane 1|yes" \
  "$(sed -n 1p <<< "${out}")|$(grep -qF "no backlog conductor of lane 1 started: no story or epic changed after" <<< "${out}" && echo yes || echo "no, got: ${out}")"
echo "${lane1}" > "${ROOT}/agents"; rm -f "${p}/.swarm/conduct-backlog.l1.report.md"
check "next with lane 1 working and lane 2 stopped waits on lane 1" "wait ${l1}" "$(step)"
check "next outside herdr with lane 1 working and lane 2 stopped waits on lane 1, never lane 2's stop" "wait ${l1}" \
  "$(cd "${p}" && env -u SWARM_PROJECT -u SWARM_AGENT -u HERDR_ENV PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" _step 2>&1 | sed -n 1p)"
rm -f "${p}/.swarm/conduct-backlog.l1.report.md" "${p}/.swarm/conduct-backlog.l2.report.md"

# --- A reported lane is collected while another lane works with its session idle too, and whatever order
# herdr lists them in: lane 1 working and listed first, lane 2 reported and idle, busy, or waiting on a
# prompt, so no wait on the slower lane hides it.
echo "${lane2}" >> "${ROOT}/agents"; touch "${p}/.swarm/conduct-backlog.l1.report.md"
printf 't\tconduct\t%s\tclaude\t-\t-\tsess-l1\n' "${l1}" >> "${p}/.swarm/agents.tsv"
echo '[{"sessionId":"sess-l1","status":"idle"}]' > "${ROOT}/claude.json"
check "next with lane 1 reported and idle while lane 2 works collects lane 1" "collect ${l1}" "$(CLAUDE_STUB_AGENTS="${ROOT}/claude.json" step)"
rm -f "${p}/.swarm/conduct-backlog.l1.report.md"
# Whatever order herdr lists them in: lane 1 working and listed first, lane 2 reported and idle.
touch "${p}/.swarm/conduct-backlog.l2.report.md"
printf 't\tconduct\t%s\tclaude\t-\t-\tsess-l2\n' "${l2}" >> "${p}/.swarm/agents.tsv"
echo '[{"sessionId":"sess-l2","status":"idle"}]' > "${ROOT}/claude.json"
check "next with lane 1 working and listed first while lane 2 is reported and idle collects lane 2" "collect ${l2}" "$(CLAUDE_STUB_AGENTS="${ROOT}/claude.json" step)"
echo '[{"sessionId":"sess-l2","status":"busy"}]' > "${ROOT}/claude.json"
check "next with lane 1 working and listed first while lane 2 is reported but still busy collects lane 2" "collect ${l2}" "$(CLAUDE_STUB_AGENTS="${ROOT}/claude.json" step)"
echo '[{"sessionId":"sess-l2","status":"waiting","waitingFor":"a permission prompt"}]' > "${ROOT}/claude.json"
check "next with lane 1 working and listed first while lane 2 is reported but waiting on a prompt collects lane 2" "collect ${l2}" "$(CLAUDE_STUB_AGENTS="${ROOT}/claude.json" step)"
rm -f "${p}/.swarm/conduct-backlog.l2.report.md"

# --- Any working conductor stopped on an API error: no lane is named, as conduct_ready starts none.
grep -v "^${l2} " "${ROOT}/agents" > "${ROOT}/agents.1"; mv "${ROOT}/agents.1" "${ROOT}/agents"
echo "conduct-e-l1 w:99 idle" >> "${ROOT}/agents"; echo "w:99 conduct-e-l1" > "${p}/.swarm/state/e"
printf '%s\n' '⏺ API Error: Connection dropped (ECONNRESET)' > "${ROOT}/screen.w:99"
# _step: next's queued: lines would look up the stub's epic e-l1, which has no file.
check "next with another conductor stopped on an API error names no lane start" "wait ${l1}" "$(swarm _step | sed -n 1p)"
rm -f "${ROOT}/screen.w:99" "${p}/.swarm/state/e"; echo "${lane1}" > "${ROOT}/agents"

# --- A lane-3 conductor that outlived conductor_lanes = 3 holds the stories that fold onto lane 1: no lane starts beside it.
l3="$(swarm _conductor backlog 3)"; echo "${l3} w:98" >> "${ROOT}/agents"; echo "w:98 ${l3}" > "${p}/.swarm/state/l3"; : > "${ROOT}/agents.l1"
grep -v "^${l1} " "${ROOT}/agents" > "${ROOT}/agents.1"; mv "${ROOT}/agents.1" "${ROOT}/agents"
check "next with lane 3's conductor left from conductor_lanes = 3 offers no lane start" "wait ${l3}" "$(step)"
rm -f "${p}/.swarm/state/l3"; : > "${ROOT}/agents"

# --- Lanes held back with no conductor at work: the step's why says why, and the lead's stop hook lets it stop.
sed -i.bak 's/^status: ready/status: blocked/' "${p}/docs/stories/${in2}.md"
touch "${p}/.swarm/conduct-backlog.l1.report.md"; sleep 1; touch "${p}/docs/stories/${in1}.md"
out="$(swarm next)"
check "next with lane 1 gone and its report uncollected: its why says so, never a start" "conduct --backlog --lane 1|yes" \
  "$(sed -n 1p <<< "${out}")|$(grep -qF "no conductor started: ${l1} is gone, and nobody collected" <<< "${out}" && echo yes || echo "no, got: ${out}")"
check "the lead's stop hook lets the lead stop on that step" "" "$(hook)"
collected "${l1}"; echo "not started: ${in1} (build died)" > "${p}/.swarm/conduct-backlog.l1.report.md"; mkdir -p "${ROOT}/proj-wt/${in1}"
sleep 1; touch "${p}/docs/stories/${in1}.md"; collected "${l1}"
out="$(swarm next)"
check "next with lane 1's report naming a dead build: its why carries the lane" "yes" \
  "$(grep -qF "no backlog conductor of lane 1 started: ${p}/.swarm/conduct-backlog.l1.report.md lists ${in1} under not started:" <<< "${out}" && echo yes || echo "no, got: ${out}")"
check "the lead's stop hook lets the lead stop on the dead build" "" "$(hook)"
rm -rf "${ROOT}/proj-wt/${in1}"; echo "done" > "${p}/.swarm/conduct-backlog.l1.report.md"; touch -t 202001010000 "${p}/docs/stories/${in1}.md"
mkdir -p "${p}/.swarm/board-state/stories"; sleep 1; printf 'status: ready\n' > "${p}/.swarm/board-state/stories/${in1}"; collected "${l1}"
out="$(swarm next)"
check "next with lane 1's story readied by its state file alone: lane 1 may start" "conduct --backlog --lane 1|no" \
  "$(sed -n 1p <<< "${out}")|$(grep -q "^no .* started:" <<< "${out}" && echo yes || echo no)"
check "the lead's stop hook keeps the lead going on that step" "yes" "$([[ -n "$(hook)" ]] && echo yes || echo no)"
mv "${p}/docs/stories/${in2}.md.bak" "${p}/docs/stories/${in2}.md"; rm -f "${p}/.swarm/conduct-backlog.l1.report.md" "${p}/.swarm/board-state/stories/${in1}"

# --- herdr cannot list its agents: no lane start, the step's why says so (conduct_ready starts none then).
touch "${ROOT}/listfail"; out="$(swarm _step)"; rm -f "${ROOT}/listfail"
check "next while herdr cannot list its agents names no lane start" "yes" \
  "$(grep -qx "no conductor started: herdr cannot list its agents, so which conductors run is not known" <<< "${out}" && echo yes || echo "no, got: ${out}")"
# That step names an active epic's lane before the backlog's, as the main loop does, even with the epic's files sorted after.
printf -- '---\nstatus: active\n---\n' > "${p}/docs/epics/e.md"
for s in "${ze1}" "${ze2}"; do printf -- '---\nstatus: ready\nkind: code\nepic: e\n---\n' > "${p}/docs/stories/${s}.md"; done
zfirst="$(printf '%s\n' "${ze1}" "${ze2}" | sort | sed -n 1p)"
touch "${ROOT}/listfail"; out="$(swarm _step)"; rm -f "${ROOT}/listfail"
check "next while herdr cannot list its agents names epic e's lane first, its stories after the backlog's" "conduct e --lane $(lane_of "${zfirst}" 2)" "$(sed -n 1p <<< "${out}")"
rm -f "${p}/docs/epics/e.md" "${p}/docs/stories/${ze1}.md" "${p}/docs/stories/${ze2}.md"

# --- conductor_lanes = 1: the steps as before.
config; : > "${ROOT}/agents"; : > "${ROOT}/herdr.log"
check "with conductor_lanes = 1 and no conductor, next names the backlog story" "story $(printf '%s\n' "${in1}" "${in2}" | sort | sed -n 1p)" "$(step)"
printf -- '---\nstatus: active\n---\n' > "${p}/docs/epics/e.md"; printf -- '---\nstatus: ready\nkind: code\nepic: e\n---\n' > "${p}/docs/stories/ex.md"
check "with conductor_lanes = 1, next names conduct <epic> with no --lane" "conduct e" "$(step)"
rm -f "${p}/docs/epics/e.md" "${p}/docs/stories/ex.md"
put docs/stories/s9.md "status: ready" "kind: code"; land
out="$(swarm merge --board "${URL}" || echo "exit $?")"
b="$(swarm _conductor backlog)"
check "with conductor_lanes = 1, a board merge starts the one backlog conductor" "yes|no" \
  "$(grep -qF "started: ${b} (swarm.sh conduct --backlog)" <<< "${out}" && echo yes || echo "no, got: ${out}")|$(grep -q "^agent start ${b}-l" "${ROOT}/herdr.log" && echo yes || echo no)"
check "with conductor_lanes = 1 and the backlog conductor running, next waits on it" "wait ${b}" "$(step)"
# Lane 1's conductor from conductor_lanes = 2 still runs: upgrade refuses, as conduct refuses a start beside it.
echo "${lane1}" >> "${ROOT}/agents"
out="$(swarm upgrade || echo "exit $?")"
check "with a lane conductor from conductor_lanes = 2 running, upgrade refuses, naming it" "yes|yes" \
  "$(grep -qF "upgrade: ${l1} runs under another conductor_lanes than 1; let it report and close it" <<< "${out}" && echo yes || echo "no, got: ${out}")|$(grep -q "^exit [1-9]" <<< "${out}" && echo yes || echo no)"

# --- commands/swarm.md's collect arm names a lane conductor's report, which next's collect <conductor>-l<k> step has the lead read.
collect="$(sed -n '/collect <agent>/,/^   - /p' "$(dirname "${SWARM}")/../commands/swarm.md")"
check "commands/swarm.md's collect arm names the lane report paths" "yes|yes" \
  "$(grep -qF '.swarm/conduct-<epic>.l<k>.report.md' <<< "${collect}" && echo yes || echo no)|$(grep -qF '.swarm/conduct-backlog.l<k>.report.md' <<< "${collect}" && echo yes || echo no)"

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
