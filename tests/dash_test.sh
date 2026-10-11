#!/usr/bin/env bash
# dash_test.sh — `swarm.sh dash` against a throwaway board, a fake agents.tsv, findings.tsv and
# events.tsv, and a stub herdr on PATH printing a fixed agent list.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" && [ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
fails=0
P="${ROOT}/proj"

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}
has() { grep -qF -- "$1" <<< "$2"; }
lacks() { ! grep -qF -- "$1" <<< "$2"; }

item() { # <path under docs> <front-matter line>...
  local path="${P}/docs/$1" title; shift
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

mkdir -p "${P}/.swarm/state" "${ROOT}/bin" "${ROOT}/nobin"
git -C "${P}" init -q
item hld/2026-01-01-x.md 'status: agreed'
item epics/e1.md 'status: active' 'hld: 2026-01-01-x'
item epics/e2.md 'status: later'
item stories/s-one.md 'status: review' 'epic: e1' 'prs: https://github.com/o/r/pull/7'
item stories/s-two.md 'status: blocked' 'epic: e1' 'blocked_by: [s-one]'
item stories/s-three.md 'status: ready' 'epic: e1'
item stories/ask.md 'status: ready' 'kind: lead'
printf 'w1:p1 conductor\nw1:p2 s-one\nw1:p3 s-gone\n' > "${P}/.swarm/state/e1"
printf '2026-10-01\tconduct\tconduct-e1\tclaude\topus\thigh\tsess-1\n2026-10-02\tcode\ts-one\tclaude\topus\thigh\tsess-2\n' > "${P}/.swarm/agents.tsv"
printf '2026-10-03\tvacuous-test\thttps://github.com/o/r/pull/7\ta test that could not fail\n' > "${P}/.swarm/findings.tsv"
printf '2026-10-04T10:00:00Z\treview\ts-one\tw1:p1\tok\n' > "${P}/.swarm/events.tsv"

# herdr: this project's conductor (working) and builder (blocked), an empty pane (w1:p3), and
# another project's agent (w9:p1), which must not be shown.
cat > "${ROOT}/bin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "agent list") echo '{"result":{"agents":[{"name":"conduct-e1","agent_status":"working","pane_id":"w1:p1","agent_session":{"value":"sess-1"}},{"name":"s-one","agent_status":"blocked","pane_id":"w1:p2"},{"name":"foreign","agent_status":"working","pane_id":"w9:p1"}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w1:p1"},{"pane_id":"w1:p2"},{"pane_id":"w1:p3"},{"pane_id":"w9:p1"}]}}' ;;
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"2026-01-01-x"},{"workspace_id":"w9","label":"other"}]}}' ;;
  *) exit 1 ;;
esac
STUB
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/nobin/herdr"
chmod +x "${ROOT}/bin/herdr" "${ROOT}/nobin/herdr"

snapshot() { (cd "${P}" && find docs .swarm -type f -print0 | sort -z | xargs -0 cksum; ls -laR docs .swarm) ; }
before="$(snapshot)"

out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
for panel in "swarm-dev " "pipeline" "agents" "ladder" "waiting on you" "recent"; do
  check "panel ${panel}" has "─ ${panel}" "${out}"
done
check "header names the project" has "project ${P}" "${out}"
check "header names the merge mode" has "merge   human" "${out}"
check "header names the next step" has "next    wait conduct-e1" "${out}"
check "pipeline counts HLDs" has "agreed 1" "${out}"
check "pipeline counts epics" has "active 1  later 1  review 0" "${out}"
check "pipeline counts stories" has "ready 2  blocked 1  review 1  later 0" "${out}"
check "agents are grouped by workspace" has "2026-01-01-x" "${out}"
check "agents are grouped by tab" has "└─ e1" "${out}"
check "the conductor shows role, model and status" grep -qE 'conduct-e1 +conduct +opus·high +\[working\]' <<< "${out}"
check "a blocked agent needs a look, with its PR" grep -qE '! s-one +code +opus·high +\[WAITING\] +https://github.com/o/r/pull/7' <<< "${out}"
check "an empty pane needs a look" grep -qE '! s-gone .*\[EMPTY\]' <<< "${out}"
check "another project's agent is not shown" lacks "foreign" "${out}"
check "the ladder maps role to model and effort" has "code-risky → opus · xhigh" "${out}"
check "the ladder names codex" has "codex      → codex · high" "${out}"
check "waiting on you lists a lead story" has "lead: ask" "${out}"
check "waiting on you lists a merge" has "awaiting your merge: s-one https://github.com/o/r/pull/7" "${out}"
check "recent lists the event, newest first" grep -qE 'review s-one +\[ok\]' <<< "$(grep -A1 -- '─ recent' <<< "${out}")"
check "recent lists a finding" has "a test that could not fail (#7)" "${out}"
check "recent lists an agent start" has "started conduct-e1 (opus high)" "${out}"
check "the status line has one line per group" grep -qE '^planning +survey: \[sonnet high\]  lead: \[opus xhigh\]' <<< "${out}"
check "a run off a terminal has no ANSI escapes" lacks $'\033' "${out}"
check "no line is wider than the default 100" python3 -c 'import sys; sys.exit(any(len(l) > 100 for l in sys.stdin.read().splitlines()))' <<< "${out}"

out="$(cd "${P}" || exit 1; HERDR_ENV=1 PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true)"
check "a failing herdr degrades: agents unavailable" has "agents unavailable" "${out}"
check "a failing herdr still prints the board" has "ready 2  blocked 1" "${out}"
out="$(cd "${P}" || exit 1; env -u HERDR_ENV bash "${SWARM}" dash 2>&1 || true)"
check "outside herdr: agents unavailable, board shown" grep -q "agents unavailable" <<< "${out}"

# --watch redraws until stopped, clearing the screen, and shows the cursor again on the way out.
(cd "${P}" && exec env -u HERDR_ENV bash "${SWARM}" dash --watch 1 > "${ROOT}/watch.out" 2>&1) &
pid=$!; sleep 3; kill -TERM "${pid}"; wait "${pid}" || true
w="$(cat "${ROOT}/watch.out")"
check "--watch redraws" test "$(grep -c -- '─ pipeline' <<< "${w}")" -ge 2
check "--watch clears the screen" has $'\033[H\033[2J' "${w}"
check "--watch restores the cursor on exit" test "${w: -6}" == $'\033[?25h'
check "--watch refuses a bad interval" bash -c "cd '${P}' && ! bash '${SWARM}' dash --watch 0 2>/dev/null"

check "dash changes nothing under the board or .swarm" test "$(snapshot)" == "${before}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
