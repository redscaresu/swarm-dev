#!/usr/bin/env bash
# conduct_backlog_test.sh — two projects under one herdr each run `conduct --backlog`. herdr names span
# projects, so each backlog conductor is named for its project's dir and a hash of its path; next, wait,
# close, status and dash in each project find its own and not the other's, even for two dirs of one name,
# and a name held by another project's agent is refused naming where it runs, before the report goes. herdr, gh and claude are stubs on PATH; herdr's state is shared by both projects.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
# No trust file here, so require_trusted lets the fixture agents start whatever ~/.claude.json says.
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects"
# The claude stub goes first on PATH, so no run here reaches the real claude.
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }
hasnt() { if grep -qF -- "$1" <<< "$2"; then echo "has '$1'"; else echo no; fi; }
item() { # <board> <path> <front-matter line>...
  local path="$1/$2" title; shift 2
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

# herdr: one for both projects. Each new pane is w:<n> with the tab's --cwd; an agent's cwd is its pane's.
mkdir -p "${ROOT}/bin"
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
next() { n=$(($(cat "$H/n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/n"; }
case "$1 $2" in
  "workspace list")   echo '{"result":{"workspaces":[]}}' ;;
  "workspace create") echo '{"result":{"workspace":{"workspace_id":"w"},"tab":{"tab_id":"t0"}}}' ;;
  "tab create")       next; echo "t$n $(echo "$*" | sed 's/.*--label \([^ ]*\).*/\1/')" >> "$H/tabs"
                      echo "w:$n $(echo "$*" | sed 's/.*--cwd \([^ ]*\).*/\1/')" >> "$H/cwds"
                      echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "tab list")         awk 'BEGIN { printf "{\"result\":{\"tabs\":[" }
                           { printf "%s{\"tab_id\":\"%s\",\"label\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                           END { print "]}}" }' "$H/tabs" 2>/dev/null || echo '{"result":{"tabs":[]}}' ;;
  "agent prompt")     echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent wait")       echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent start")      p="$(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/')"
                      echo "$3 $p $(awk -v p="$p" '$1 == p { print $2 }' "$H/cwds")" >> "$H/agents" ;;
  "agent list")       awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                           { printf "%s{\"name\":\"%s\",\"agent_status\":\"idle\",\"pane_id\":\"%s\",\"cwd\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2, $3 }
                           END { print "]}}" }' "$H/agents" 2>/dev/null || echo '{"result":{"agents":[]}}' ;;
  "pane list")        awk 'BEGIN { printf "{\"result\":{\"panes\":[" }
                           { printf "%s{\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $2 }
                           END { print "]}}" }' "$H/agents" 2>/dev/null || echo '{"result":{"panes":[]}}' ;;
  "pane close"|"tab close") p=$3; [ "$1" = tab ] && p="w:${3#t}"
                      [ -e "$H/agents" ] && awk -v p="$p" '$2 != p' "$H/agents" > "$H/agents.tmp" && mv "$H/agents.tmp" "$H/agents" ;;
esac
EOF
printf '#!/bin/sh\necho "[]"\n' > "${ROOT}/bin/gh"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/gh"

# Two projects whose dirs share a name (work/api and oss/api), each with a ready story outside any epic.
A_DIR=work/api; B_DIR=oss/api
for p in "${A_DIR}" "${B_DIR}"; do
  mkdir -p "${ROOT}/${p}/.claude/swarm"; : > "${ROOT}/${p}/.claude/swarm/config"
  git -C "${ROOT}/${p}" init -q
  item "${ROOT}/${p}/docs" "stories/${p%%/*}1.md" "status: ready" "kind: code"
  : > "${ROOT}/${p}/docs/stories/README.md"   # dash's mark of a board
done
run() { local p="$1"; shift; (cd "${ROOT}/${p}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" 2>&1); }
# started <n> — the name of the <n>th backlog conductor herdr started.
started() { sed -n 's/^agent start \(conduct-backlog-[^ ]*-[0-9a-f]\{6\}\) .*/\1/p' "${ROOT}/herdr.log" | sed -n "$1p"; }
fits() { if [[ "$1" =~ ^conduct-backlog-api-[0-9a-f]{6}$ ]]; then echo yes; else echo "no, got: $1"; fi; }

out_a="$(run "${A_DIR}" conduct --backlog || echo "exit $?")"
out_b="$(run "${B_DIR}" conduct --backlog || echo "exit $?")"
A="$(started 1)"; B="$(started 2)"
check "two projects whose dirs share a name both start a backlog conductor, each with its own name" "yes|yes|yes|no|no" \
  "$(fits "${A}")|$(fits "${B}")|$([[ "${A}" != "${B}" ]] && echo yes || echo no)|$(hasnt "exit" "${out_a}")|$(hasnt "exit" "${out_b}")"
brief_a="${ROOT}/${A_DIR}/.swarm/briefs/conduct-backlog.md"; brief_b="${ROOT}/${B_DIR}/.swarm/briefs/conduct-backlog.md"
check "each gets its own brief, under its own project" "yes|yes" \
  "$([[ -f "${brief_a}" ]] && echo yes || echo no)|$([[ -f "${brief_b}" ]] && echo yes || echo no)"
check "each brief reports to its own project's report" "yes|no|yes|no" \
  "$(has "${ROOT}/${A_DIR}/.swarm/conduct-backlog.report.md" "$(cat "${brief_a}")")|$(hasnt "${ROOT}/${B_DIR}/" "$(cat "${brief_a}")")|$(has "${ROOT}/${B_DIR}/.swarm/conduct-backlog.report.md" "$(cat "${brief_b}")")|$(hasnt "${ROOT}/${A_DIR}/" "$(cat "${brief_b}")")"

# next: each waits on its own; once A has reported, A collects and B still waits.
check "next in each project waits on its own backlog conductor" "wait ${A}|wait ${B}" \
  "$(run "${A_DIR}" next | head -1)|$(run "${B_DIR}" next | head -1)"
echo reported > "${ROOT}/${A_DIR}/.swarm/conduct-backlog.report.md"
check "A's report is A's alone: A collects, B still waits" "collect ${A}|wait ${B}" \
  "$(run "${A_DIR}" next | head -1)|$(run "${B_DIR}" next | head -1)"

rm "${brief_a}"
check "with its brief gone, A's reported conductor is still collected" "collect ${A}" "$(run "${A_DIR}" next | head -1)"

# dash: A's conductor, its session idle, has reported (its report is found by its name).
sess="$(grep -F "${A}" "${ROOT}/${A_DIR}/.swarm/agents.tsv" | grep -oE '[0-9a-f]{8}-[0-9a-f-]{27}' | head -1)"
echo "[{\"sessionId\":\"${sess}\",\"status\":\"idle\"}]" > "${ROOT}/claude.json"
check "dash in A shows its backlog conductor as reported" "yes" \
  "$(has "reported" "$(CLAUDE_STUB_AGENTS="${ROOT}/claude.json" run "${A_DIR}" dash | grep -F "${A}" || true)")"

# wait: A's conductor has reported, so the wait returns; the other project's name is never waited on.
w_a="$(run "${A_DIR}" wait "${A}" 2000 || echo "exit $?")"
w_x="$(run "${A_DIR}" wait "${B}" 2000 || echo "exit $?")"
check "wait in A returns on A's conductor, and refuses B's" "no|no|yes|yes" \
  "$(hasnt "exit" "${w_a}")|$(hasnt "no agent this project started" "${w_a}")|$(has "exit 1" "${w_x}")|$(has "no agent this project started holds this name" "${w_x}")"

# status --all: each lists its own backlog conductor and not the other's.
st_a="$(run "${A_DIR}" status --all)"; st_b="$(run "${B_DIR}" status --all)"
check "status in each project lists only its own backlog conductor" "yes|no|yes|no" \
  "$(has "${A}" "${st_a}")|$(hasnt "${B}" "${st_a}")|$(has "${B}" "${st_b}")|$(hasnt "${A}" "${st_b}")"

# close: A's close of B's name closes nothing; A's own closes A's alone.
run "${A_DIR}" close "${B}" >/dev/null 2>&1 || true
check "close in A leaves B's conductor" "yes" "$(has "${B} " "$(cat "${ROOT}/agents")")"
run "${A_DIR}" close "${A}" >/dev/null 2>&1 || true
check "close in A closes A's conductor and keeps B's" "no|yes" \
  "$(hasnt "${A} " "$(cat "${ROOT}/agents")")|$(has "${B} " "$(cat "${ROOT}/agents")")"

# The name-held refusal: an agent of a project elsewhere holds A's name. A's uncollected report and
# its brief are left as they were.
echo "${A} w:99 ${ROOT}/elsewhere" >> "${ROOT}/agents"
echo kept > "${brief_a}"
out="$(run "${A_DIR}" conduct --backlog || echo "exit $?")"
check "a name held by another project's agent is refused, naming that project's dir" "yes|yes|yes" \
  "$(has "exit 1" "${out}")|$(has "an agent this project did not start" "${out}")|$(has "it runs in ${ROOT}/elsewhere" "${out}")"
check "a refused conduct --backlog keeps the uncollected report and the brief" "reported|kept" \
  "$(cat "${ROOT}/${A_DIR}/.swarm/conduct-backlog.report.md" 2>/dev/null || echo gone)|$(cat "${brief_a}")"

# An epic whose conductor would take A's backlog conductor's name is refused, starting nothing; an
# epic merely slugged backlog-<x> is not.
item "${ROOT}/${A_DIR}/docs" "epics/${A#conduct-}.md" "status: active"
n="$(grep -c '^agent start' "${ROOT}/herdr.log")"
out="$(run "${A_DIR}" conduct "${A#conduct-}" || echo "exit $?")"
check "conduct <the backlog conductor's name, as an epic> is refused, and starts nothing" "yes|yes|${n}" \
  "$(has "exit 1" "${out}")|$(has "would take the backlog conductor's name" "${out}")|$(grep -c '^agent start' "${ROOT}/herdr.log")"
item "${ROOT}/${A_DIR}/docs" epics/backlog-grooming.md "status: active"
out="$(run "${A_DIR}" conduct backlog-grooming || echo "exit $?")"
check "conduct backlog-grooming, an epic of that slug, starts its conductor" "no|yes" \
  "$(hasnt "exit" "${out}")|$(has "agent start conduct-backlog-grooming " "$(cat "${ROOT}/herdr.log")")"

# A dir named like a retired agent (work-done) still gives a live conductor's name: next waits on it.
mkdir -p "${ROOT}/work-done/.claude/swarm"; : > "${ROOT}/work-done/.claude/swarm/config"
git -C "${ROOT}/work-done" init -q
item "${ROOT}/work-done/docs" stories/w1.md "status: ready" "kind: code"
run work-done conduct --backlog >/dev/null || true
C="$(started 3)"
check "a project dir ending -done gets a name that is not a retired one, and next waits on it" "no|wait ${C}" \
  "$([[ "${C}" =~ -done[0-9]*$ ]] && echo yes || echo no)|$(run work-done next | head -1)"

# A dir name of multibyte characters still leaves room for the hash.
mkdir -p "${ROOT}/ünï-cödé-ünï/.claude/swarm"; : > "${ROOT}/ünï-cödé-ünï/.claude/swarm/config"
git -C "${ROOT}/ünï-cödé-ünï" init -q
item "${ROOT}/ünï-cödé-ünï/docs" stories/u1.md "status: ready" "kind: code"
run "ünï-cödé-ünï" conduct --backlog >/dev/null || true
D="$(sed -n 's/^agent start \(conduct-backlog-[^ ]*\) .*/\1/p' "${ROOT}/herdr.log" | tail -1)"
check "a multibyte dir name keeps the hash in the name" "yes" \
  "$([[ "${D}" =~ ^conduct-backlog-[a-z0-9_-]{1,9}-[0-9a-f]{6}$ ]] && echo yes || echo "no, got: ${D}")"

# Once the holder elsewhere is gone, A starts again, and its new run removes the old report.
awk '$2 != "w:99"' "${ROOT}/agents" > "${ROOT}/agents.tmp" && mv "${ROOT}/agents.tmp" "${ROOT}/agents"
out="$(run "${A_DIR}" conduct --backlog || echo "exit $?")"
check "a new conduct --backlog removes the report its earlier run left" "no|gone" \
  "$(hasnt "exit" "${out}")|$(cat "${ROOT}/${A_DIR}/.swarm/conduct-backlog.report.md" 2>/dev/null || echo gone)"

[[ "${fails}" -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
