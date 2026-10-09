#!/usr/bin/env bash
# next_test.sh — `swarm.sh next` against small throwaway boards, one per case.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
fails=0

# item <path> <front-matter line>... — write a board file under docs/.
item() {
  local path="docs/$1" title; shift
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

# expect <name> <first line of `next`> <setup...> — build a board with the setup, check next.
expect() {
  local name="$1" want="$2" dir got; shift 2
  dir="$(mktemp -d)"
  (
    cd "${dir}" && git init -q && mkdir -p docs/stories docs/epics docs/hld
    echo "# Stories" > docs/stories/README.md   # READMEs are never items
    for step in "$@"; do eval "${step}"; done
  )
  # The whole output, then its first line: `| head -1` can close the pipe while next is still
  # printing a gate's list, and the broken pipe fails the run under pipefail.
  got="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next)"; got="${got%%$'\n'*}"
  if [[ "${got}" == "${want}" ]]; then
    echo "ok   ${name}"
  else
    echo "FAIL ${name}: want '${want}', got '${got}'"; fails=$((fails + 1))
  fi
  rm -rf "${dir}" "${dir}-wt"
}

expect "empty board" "done"
expect "draft HLD" "hld 2026-01-01-x" \
  "item hld/2026-01-01-x.md 'status: draft'"
expect "agreed HLD, no epics" "plan-hld 2026-01-01-x" \
  "item hld/2026-01-01-x.md 'status: agreed'"
expect "agreed HLD, epics listed and done" "done" \
  "item hld/2026-01-01-x.md 'status: agreed'" \
  "printf '\n## Epics\n\n- e1 — done (#1)\n' >> docs/hld/2026-01-01-x.md"
expect "superseded HLD" "done" \
  "item hld/2026-01-01-x.md 'status: superseded'"
expect "active epic, no stories" "plan-epic e1" \
  "item epics/e1.md 'status: active'"
expect "active epic before a one-off" "conduct e1" \
  "item epics/e1.md 'status: active'" \
  "item stories/a-one-off.md 'status: ready' 'kind: code'" \
  "item stories/b.md 'status: ready' 'kind: code' 'epic: e1'"
expect "one-off story" "story a" \
  "item stories/a.md 'status: ready'"
expect "blocked code story is a gate, not done" "gate" \
  "item epics/e1.md 'status: active'" \
  "item stories/a.md 'status: blocked' 'kind: code' 'epic: e1' 'blocked_by: [b]'"
# shellcheck disable=SC2016 # the setup is eval'd inside the fixture, so $PWD is the fixture's
expect "started one-off resumes" "resume a" \
  "item stories/a.md 'status: ready'" \
  'mkdir -p "../$(basename "$PWD")-wt/a"'
expect "blocked story is not built" "gate" \
  "item epics/e1.md 'status: active'" \
  "item stories/a.md 'status: blocked' 'kind: lead' 'epic: e1'"
expect "unknown kind is a gate, not built" "gate" \
  "item stories/a.md 'status: ready' 'kind: Lead'"
expect "old operator kind is a gate, not built" "gate" \
  "item stories/a.md 'status: ready' 'kind: operator'"
expect "lead story is a gate" "gate" \
  "item stories/a.md 'status: ready' 'kind: lead'"
expect "ready story in a later epic waits" "gate" \
  "item epics/e1.md 'status: later'" \
  "item stories/a.md 'status: ready' 'kind: code' 'epic: e1'"
expect "only later stories left is a gate, not done" "gate" \
  "item stories/a.md 'status: later' 'kind: code'"
expect "only later epics left is a gate" "gate" \
  "item epics/e1.md 'status: later'"
expect "stories before planning" "conduct e2" \
  "item hld/2026-01-01-x.md 'status: draft'" \
  "item epics/e1.md 'status: active'" \
  "item epics/e2.md 'status: active'" \
  "item stories/a.md 'status: ready' 'epic: e2'"

# With a conductor in herdr: `wait` until it has written its report, then `collect`. A stub herdr
# lists the agent; being idle must not count as finished. A long epic's agent name is cut at 32
# characters, and its report is still found under the full epic name.
expect_conductor() { # <name> <want> <write the report?> [epic]
  local name="$1" want="$2" epic="${4:-e1}" dir got agent
  dir="$(mktemp -d)"
  # An older brief whose epic shares the cut name, as a finished long epic leaves behind.
  (cd "${dir}" && git init -q && mkdir -p docs/stories bin .swarm/briefs && touch -t 202001010000 ".swarm/briefs/conduct-${epic}-old.md" && touch ".swarm/briefs/conduct-${epic}.md")
  agent="$(cd "${dir}" && bash "${SWARM}" _name "conduct-${epic}")"; want="${want//AGENT/${agent}}"
  printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"agents\":[{\"name\":\"${agent}\",\"agent_status\":\"idle\"}]}}'" > "${dir}/bin/herdr"
  chmod +x "${dir}/bin/herdr"
  [[ "$3" == yes ]] && echo report > "${dir}/.swarm/conduct-${epic}.report.md"
  got="$(cd "${dir}" && HERDR_ENV=1 PATH="${dir}/bin:${PATH}" bash "${SWARM}" next)"; got="${got%%$'\n'*}"
  if [[ "${got}" == "${want}" ]]; then echo "ok   ${name}"; else
    echo "FAIL ${name}: want '${want}', got '${got}'"; fails=$((fails + 1)); fi
  rm -rf "${dir}"
}
expect_conductor "idle conductor without a report is still waited on" "wait conduct-e1" no
expect_conductor "conductor with a report is collected" "collect conduct-e1" yes
expect_conductor "a long epic's conductor is collected by its report" "collect AGENT" yes aws-layer3-claim-sweep-reap

# `wait` on a conductor: idle without a report is not settled. It returns once the report lands.
dir="$(mktemp -d)"
(cd "${dir}" && git init -q && mkdir -p docs/stories bin .swarm/briefs && touch .swarm/briefs/conduct-e1.md)
printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"agent\":{\"agent_status\":\"idle\"}}}'" > "${dir}/bin/herdr"
chmod +x "${dir}/bin/herdr"
(sleep 2; echo report > "${dir}/.swarm/conduct-e1.report.md") &
got="$(cd "${dir}" && HERDR_ENV=1 SWARM_CONDUCTOR_POLL=1 PATH="${dir}/bin:${PATH}" bash "${SWARM}" wait conduct-e1 20000)"
reported=no; [[ -f "${dir}/.swarm/conduct-e1.report.md" ]] && reported=yes
wait
if [[ "${got}" == idle && "${reported}" == yes ]]; then
  echo "ok   wait on an idle conductor holds until its report"; else
  echo "FAIL wait on an idle conductor holds until its report: got '${got}', report there on return: ${reported}"; fails=$((fails + 1)); fi
rm -f "${dir}/.swarm/conduct-e1.report.md"

# A conductor that never reports does not hang `wait`: the timeout bounds the whole wait.
start=${SECONDS}
got="$(cd "${dir}" && HERDR_ENV=1 PATH="${dir}/bin:${PATH}" bash "${SWARM}" wait conduct-e1 2000)"
if [[ "${got}" == idle && $((SECONDS - start)) -le 10 ]]; then
  echo "ok   wait on a conductor that never reports ends at its timeout"; else
  echo "FAIL wait on a conductor that never reports ends at its timeout: got '${got}' after $((SECONDS - start))s"; fails=$((fails + 1)); fi

# A conductor idle on an API error is stuck: wait returns after wait_agent's nudges, well inside
# the timeout, instead of polling and nudging again.
cat > "${dir}/bin/herdr" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "agent read") echo '⏺ API Error: overloaded' ;;
  *) echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
esac
EOF
start=${SECONDS}
got="$(cd "${dir}" && HERDR_ENV=1 SWARM_CONDUCTOR_POLL=5 PATH="${dir}/bin:${PATH}" bash "${SWARM}" wait conduct-e1 20000 2>/dev/null)"
if [[ "${got}" == idle && $((SECONDS - start)) -lt 5 ]]; then
  echo "ok   wait on a conductor stuck on an API error returns without polling"; else
  echo "FAIL wait on a conductor stuck on an API error returns without polling: got '${got}' after $((SECONDS - start))s"; fails=$((fails + 1)); fi

# A retired conductor (renamed <name>-done) is not waited on for a report.
printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"agent\":{\"agent_status\":\"idle\"}}}'" > "${dir}/bin/herdr"
start=${SECONDS}
got="$(cd "${dir}" && HERDR_ENV=1 SWARM_CONDUCTOR_POLL=5 PATH="${dir}/bin:${PATH}" bash "${SWARM}" wait conduct-e1-done 20000)"
if [[ "${got}" == idle && $((SECONDS - start)) -lt 5 ]]; then
  echo "ok   wait on a retired conductor returns at once"; else
  echo "FAIL wait on a retired conductor returns at once: got '${got}' after $((SECONDS - start))s"; fails=$((fails + 1)); fi
rm -rf "${dir}"

# A retired conductor (keep_panes renames it <name>-done) is finished: next must not wait on it.
dir="$(mktemp -d)"
(cd "${dir}" && git init -q && mkdir -p docs/stories bin)
printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"agents\":[{\"name\":\"conduct-e1-done\",\"agent_status\":\"idle\"}]}}'" > "${dir}/bin/herdr"
chmod +x "${dir}/bin/herdr"
got="$(cd "${dir}" && HERDR_ENV=1 PATH="${dir}/bin:${PATH}" bash "${SWARM}" next)"; got="${got%%$'\n'*}"
if [[ "${got}" == "done" ]]; then echo "ok   a retired conductor is not waited on"; else
  echo "FAIL a retired conductor is not waited on: want 'done', got '${got}'"; fails=$((fails + 1)); fi
rm -rf "${dir}"

# A long conductor's agent name is cut at 32 characters; close must still find its full tab label.
long="conduct-aws-layer3-claim-sweep-reap"
dir="$(mktemp -d)"
(cd "${dir}" && git init -q && mkdir -p .swarm/state && touch ".swarm/state/${long}" ".swarm/state/${long}-2" .swarm/state/short)
short_name="$(cd "${dir}" && bash "${SWARM}" _name "${long}")"
for pair in "${short_name}:${long}" "${long}:${long}" "short:short" "unknown:unknown"; do
  got="$(cd "${dir}" && bash "${SWARM}" _label "${pair%%:*}")"
  if [[ "${got}" == "${pair#*:}" ]]; then echo "ok   tab label for ${pair%%:*}"; else
    echo "FAIL tab label for ${pair%%:*}: want '${pair#*:}', got '${got}'"; fails=$((fails + 1)); fi
done
rm -rf "${dir}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
