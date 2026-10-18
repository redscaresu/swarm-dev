#!/usr/bin/env bash
# queue_test.sh — a story PR green and mergeable for queue_minutes with no review agent on its head:
# `watch` returns `queued: ...`, and `next` prints the same line under a working conductor's wait.
# With a review agent on that head (.swarm/reviews/<slug>.head), or short of queue_minutes, neither
# does. gh, herdr and claude are stubs on PATH.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
mkdir -p "${ROOT}/bin"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${ROOT}/bin/claude"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# gh answers from fixture files: the PR list, and each head's check runs from runs-<sha>.json.
printf '#!/bin/sh\nF="%s"\n' "${ROOT}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'EOF'
q=""; for a in "$@"; do [ "$p" = -q ] && q="$a"; p="$a"; done
case "$1 $2" in
  "repo view") echo o/svc; exit 0 ;;
  "pr list")   jq -r "$q" "$F/prlist.json"; exit 0 ;;
esac
case "$2" in
  repos/o/svc/commits/*/check-runs) sha="${2#repos/o/svc/commits/}"; jq -r "$q" "$F/runs-${sha%/check-runs}.json" ;;
  *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
# herdr lists a working conductor for e1, in a pane this project recorded.
printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"agents\":[{\"name\":\"conduct-e1\",\"agent_status\":\"working\",\"pane_id\":\"w:7\"}]}}'" > "${ROOT}/bin/herdr"
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr" "${ROOT}/bin/claude"

p="${ROOT}/proj"
mkdir -p "${p}/.claude/swarm" "${p}/docs/epics" "${p}/docs/stories" "${p}/.swarm/briefs" "${p}/.swarm/state"
: > "${p}/.claude/swarm/config"
git -C "${p}" init -q && git -C "${p}" remote add origin https://github.com/o/svc
printf -- '---\nstatus: active\n---\n' > "${p}/docs/epics/e1.md"
printf -- '---\nstatus: ready\nkind: code\nepic: e1\n---\n' > "${p}/docs/stories/s1.md"
touch "${p}/.swarm/briefs/conduct-e1.md"; echo "w:7 conduct-e1" > "${p}/.swarm/state/tab"
echo '[{"number": 3, "headRefName": "story/s1", "headRefOid": "h1", "mergeable": "MERGEABLE", "updatedAt": "2026-01-01T00:00:00Z"}]' > "${ROOT}/prlist.json"

# green <minutes> — h1's checks all passed, the last <minutes> ago; watch has already reported them
# finished, so only a queued line can wake it.
green() {
  local at; at="$(python3 -c 'import sys, time; print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 60 * int(sys.argv[1]))))' "$1")"
  echo "{\"check_runs\":[{\"status\":\"completed\",\"conclusion\":\"success\",\"completed_at\":\"2020-01-01T00:00:00Z\"},{\"status\":\"completed\",\"conclusion\":\"skipped\",\"completed_at\":\"${at}\"}]}" > "${ROOT}/runs-h1.json"
  echo "done h1" > "${p}/.swarm/state/watch-seen"
}
# watchrun — what watch --epic e1 printed, or "(still watching)" if it has not returned in 10 seconds.
watchrun() {
  local pid
  (cd "${p}" && exec env -u HERDR_ENV -u SWARM_PROJECT PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" watch --epic e1 > "${ROOT}/watch.out" 2>&1) &
  pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do kill -0 "${pid}" 2>/dev/null || break; sleep 0.5; done
  if kill -0 "${pid}" 2>/dev/null; then pkill -P "${pid}" 2>/dev/null || true; kill "${pid}" 2>/dev/null || true; wait "${pid}" 2>/dev/null || true; echo "(still watching)"; return; fi
  cat "${ROOT}/watch.out"
}
# nextq — next's queued lines (none: "(none)"), after checking it still waits on the conductor.
nextq() {
  local out
  out="$(cd "${p}" && env -u SWARM_PROJECT HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" next)"
  [[ "${out%%$'\n'*}" == "wait conduct-e1" ]] || { echo "next did not wait: ${out}"; return; }
  grep '^queued: ' <<< "${out}" || echo "(none)"
}

green 31
check "watch reports a PR green and mergeable for 31 minutes with no review agent" "queued: #3 green 31m with no review" "$(watchrun)"
check "watch reports a queued head once" "(still watching)" "$(watchrun)"
check "next prints the queued line under the conductor's wait" "queued: #3 green 31m with no review" "$(nextq)"

mkdir -p "${p}/.swarm/reviews"; echo h1 > "${p}/.swarm/reviews/s1.head"
green 31
check "with a review agent on that head, watch does not report it" "(still watching)" "$(watchrun)"
check "with a review agent on that head, next prints no queued line" "(none)" "$(nextq)"
echo h0 > "${p}/.swarm/reviews/s1.head"
check "a review agent on an earlier head does not count" "queued: #3 green 31m with no review" "$(nextq)"
rm "${p}/.swarm/reviews/s1.head"

green 29
check "at 29 minutes, watch does not report it" "(still watching)" "$(watchrun)"
check "at 29 minutes, next prints no queued line" "(none)" "$(nextq)"

echo "queue_minutes = 20" > "${p}/.claude/swarm/config"
check "queue_minutes sets the threshold" "queued: #3 green 29m with no review" "$(nextq)"
: > "${p}/.claude/swarm/config"

green 31
echo '[{"number": 3, "headRefName": "story/s1", "headRefOid": "h1", "mergeable": "CONFLICTING", "updatedAt": "2026-01-01T00:00:00Z"}]' > "${ROOT}/prlist.json"
check "a PR that is not mergeable is not queued" "(none)" "$(nextq)"
echo '[{"number": 3, "headRefName": "story/s1", "headRefOid": "h1", "mergeable": "MERGEABLE", "updatedAt": "2026-01-01T00:00:00Z"}]' > "${ROOT}/prlist.json"
sed -i.bak 's/"skipped"/"failure"/' "${ROOT}/runs-h1.json"
check "a PR with a failed check is not queued" "(none)" "$(nextq)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
