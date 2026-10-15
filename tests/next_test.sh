#!/usr/bin/env bash
# next_test.sh — `swarm.sh next` against small throwaway boards, one per case.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
fails=0
# The claude stub goes first on PATH, so no run here reaches the real claude.
STUB_BIN="$(mktemp -d)"; trap 'rm -rf "${STUB_BIN}"' EXIT
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}"

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
  dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
  [ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
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
expect "epic waits on an open dependency" "plan-epic b" \
  "item epics/a.md 'status: active' 'depends_on: [b]'" \
  "item epics/b.md 'status: active'"
expect "epic planned once its dependency is deleted" "plan-epic a" \
  "item epics/a.md 'status: active' 'depends_on: [b]'"
expect "epic planned once its dependency is done" "plan-epic a" \
  "item epics/a.md 'status: active' 'depends_on: [b]'" \
  "item epics/b.md 'status: done'"
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
# The same one-off with a real worktree, its builder open in a pane this project recorded: a counted
# close clears the worktree, so the next step builds it afresh. herdr and gh are stubs.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
origin="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
(
  cd "${dir}" && git init -q && git init -q --bare "${origin}" && git remote add origin "${origin}"
  git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init && git push -q origin HEAD
  mkdir -p docs/stories bin .swarm/state && item stories/a.md 'status: ready' 'kind: code'
  git worktree add -q -b story/a "../$(basename "${dir}")-wt/a" && echo "w:1 a" > .swarm/state/a
  # shellcheck disable=SC2016 # the stubs' own shell expands these
  printf '%s\n' '#!/bin/sh' 'case "$1 $2" in' \
    "  \"agent list\") echo '{\"result\":{\"agents\":[{\"name\":\"a\",\"agent_status\":\"idle\",\"pane_id\":\"w:1\"}]}}' ;;" \
    "  \"tab list\") echo '{\"result\":{\"tabs\":[]}}' ;;" 'esac' > bin/herdr
  printf '%s\n' '#!/bin/sh' "[ \"\$1 \$2\" = 'pr list' ] && echo '[]'" 'exit 0' > bin/gh
  chmod +x bin/herdr bin/gh
)
nxt() { local got; got="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next)"; echo "${got%%$'\n'*}"; }
before="$(nxt)"
(cd "${dir}" && HERDR_ENV=1 PATH="${dir}/bin:${PATH}" bash "${SWARM}" close a >/dev/null 2>&1) || true
for pair in "before:resume a:${before}" "after:story a:$(nxt)"; do
  IFS=: read -r when want got <<< "${pair}"
  if [[ "${got}" == "${want}" ]]; then echo "ok   a started one-off is '${want}' ${when} the counted close"; else
    echo "FAIL a started one-off is '${want}' ${when} the counted close: got '${got}'"; fails=$((fails + 1)); fi
done
rm -rf "${dir}" "${dir}-wt" "${origin}"
expect "blocked story is not built" "gate" \
  "item epics/e1.md 'status: active'" \
  "item stories/a.md 'status: blocked' 'kind: lead' 'epic: e1'"
expect "unknown kind is a gate, not built" "gate" \
  "item stories/a.md 'status: ready' 'kind: Lead'"
expect "old operator kind is a gate, not built" "gate" \
  "item stories/a.md 'status: ready' 'kind: operator'"
expect "lead story is a gate" "gate" \
  "item stories/a.md 'status: ready' 'kind: lead'"
# A story whose Fable build failed is the lead's to decide, so next names it instead of the gate.
expect "an escalated story is the lead's to decide, ahead of gate" "escalated b" \
  "item stories/a.md 'status: ready' 'kind: lead'" \
  "item stories/b.md 'status: ready' 'kind: lead' 'attempts: 3' 'escalated_from: code'"
# `close <slug> impossible` hands a story on with an **Impossible.** block: the lead's, like a failed
# Fable build, so escalated, never a gate; next's reason says its builder called it impossible.
IMPOSSIBLE_BLOCK="printf '%s\n' '<!-- swarm.sh escalated: swarm.sh reset removes this block -->' '**Impossible.** The builder replied' '<!-- /swarm.sh escalated -->' >> docs/stories/b.md"
expect "an impossible story is the lead's to decide, escalated, not a gate" "escalated b" \
  "item stories/b.md 'status: ready' 'kind: lead' 'attempts: 1' 'escalated_from: code'" "${IMPOSSIBLE_BLOCK}"
# shellcheck disable=SC2016 # the setup is eval'd inside the fixture
expect "once the lead drops it, next no longer names it" "gate" \
  "item stories/a.md 'status: ready' 'kind: lead'" \
  "item stories/b.md 'status: ready' 'kind: lead' 'attempts: 3' 'escalated_from: code'" \
  'bash "${SWARM}" drop b "two Fable builds failed" >/dev/null'
# The escalated story is the lead's, so status's Waiting on you lists the plain lead story, not it.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p docs/stories && item stories/a.md 'status: ready' 'kind: lead' \
  && item stories/b.md 'status: ready' 'kind: lead' 'attempts: 3' 'escalated_from: code')
waiting="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" status | sed -n '/^Waiting on you$/,/^$/p')"
if grep -qx '  lead: a' <<< "${waiting}" && ! grep -q 'b$' <<< "${waiting}"; then echo "ok   status lists a plain lead story under Waiting on you, never an escalated one"
else echo "FAIL status lists a plain lead story under Waiting on you, never an escalated one: got '${waiting}'"; fails=$((fails + 1)); fi
rm -rf "${dir}"
# An impossible story is never under Waiting on you, and next says why it is the lead's.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p docs/stories && item stories/b.md 'status: ready' 'kind: lead' 'attempts: 1' 'escalated_from: code' \
  && eval "${IMPOSSIBLE_BLOCK}")
waiting="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" status | sed -n '/^Waiting on you$/,/^$/p')"
why="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next | sed -n 2p)"
if ! grep -q 'b$' <<< "${waiting}" && [[ "${why}" == "b's builder called its Done when impossible: re-scope it and run swarm.sh reset b <reason>, or swarm.sh drop b <reason>, then tell the user why" ]]; then
  echo "ok   an impossible story is not under Waiting on you, and next says its builder called it impossible"
else echo "FAIL an impossible story is not under Waiting on you, and next says its builder called it impossible: got '${waiting}' and '${why}'"; fails=$((fails + 1)); fi
rm -rf "${dir}"
# Before its one reset, next offers reset or drop; after it (an ok reset line in events.tsv), only drop.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p docs/stories .swarm && item stories/b.md 'status: ready' 'kind: lead' 'attempts: 3' 'escalated_from: code')
why1="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next | sed -n 2p)"
printf '2026-10-15T01:00:00Z\treset\tb\tw:me\tok (re-scoped)\n' > "${dir}/.swarm/events.tsv"
why2="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next | sed -n 2p)"
# An impossible story after its one reset is offered only drop too.
(cd "${dir}" && eval "${IMPOSSIBLE_BLOCK}")
why3="$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" next | sed -n 2p)"
if [[ "${why1}" == *"swarm.sh reset b <reason>"* && "${why2}" == *"after its one reset (2026-10-15T01:00:00Z)"* \
      && "${why2}" == *"swarm.sh drop b <reason>"* && "${why2}" != *"swarm.sh reset"* \
      && "${why3}" == *"impossible after its one reset (2026-10-15T01:00:00Z)"* && "${why3}" == *"swarm.sh drop b <reason>"* && "${why3}" != *"swarm.sh reset"* ]]; then
  echo "ok   next offers reset before a story's one reset, and only drop after it, impossible or not"
else echo "FAIL next offers reset before a story's one reset, and only drop after it, impossible or not: got '${why1}', '${why2}', '${why3}'"; fails=$((fails + 1)); fi
rm -rf "${dir}"
# With goal on, /swarm's story arm names the cause on its give-up closes, reads the current build's
# transcript, and leaves a cleared-on-error story alone until it decides.
# shellcheck disable=SC2016 # the backticks are literal Markdown
arm="$(sed -n '/^   - `story <slug>`:/,/^   - `plan-epic <epic>`:/p' "$(dirname "${SWARM}")/../commands/swarm.md")"
got=""
# shellcheck disable=SC2016 # the backticks are literal Markdown
for w in '`swarm.sh close <slug>' 'stalled` for a stall' '`swarm.sh close <slug> met` when review has not converged' \
         "whose name (field 3) is the builder's agent name" 'do not start it again until you have decided' \
         'an `s` in front unless it starts with a' '- None of the above fits (no reply, no refusal, no stall' \
         'That counts nothing, so do not start it again: decide' 'the restart above is only for a stall or a review that has not converged' \
         '- `met`:' '- `impossible`:' '- `stalled`:' '- `bound`:' '- `paused`:' '- `cleared-on-error`:'; do
  grep -qF -- "${w}" <<< "${arm}" || got+=" missing '${w}'"; done
# shellcheck disable=SC2016 # the backticks are literal Markdown
grep -qF 'with `failed`' <<< "${arm}" && got+=" has an invented failed entry"
if [[ -z "${got}" ]]; then echo "ok   commands/swarm.md's story arm closes with a cause under goal, reads the current build, and holds a cleared-on-error story"
else echo "FAIL commands/swarm.md's story arm:${got}"; fails=$((fails + 1)); fi
# /swarm acts on `escalated <slug>` itself: its arm resets or drops the story and tells the user why.
# shellcheck disable=SC2016 # the backticks are literal Markdown
arm="$(sed -n '/^   - `escalated <slug>`:/,/^   - `gate`:/p' "$(dirname "${SWARM}")/../commands/swarm.md")"
got=""; for w in 'swarm.sh reset <slug> <reason>' 'swarm.sh drop <slug> <reason>' 'not a stop' 'tell the user' \
         'swarm.sh reset <slug> <reason> && git pull --ff-only' 'Waiting on you' '(its block starts **Impossible.**)'; do grep -qF -- "${w}" <<< "${arm}" || got+=" missing '${w}'"; done
if [[ -z "${got}" ]]; then echo "ok   commands/swarm.md's escalated arm resets then pulls, or drops, is not a stop, tells the user, and shows Waiting on you while it waits"
else echo "FAIL commands/swarm.md's escalated arm:${got}"; fails=$((fails + 1)); fi
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
  dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
  [ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
  # An older brief whose epic shares the cut name, as a finished long epic leaves behind.
  (cd "${dir}" && git init -q && mkdir -p docs/stories bin .swarm/briefs && touch -t 202001010000 ".swarm/briefs/conduct-${epic}-old.md" && touch ".swarm/briefs/conduct-${epic}.md")
  agent="$(cd "${dir}" && bash "${SWARM}" _name "conduct-${epic}")"; want="${want//AGENT/${agent}}"
  mkdir -p "${dir}/.swarm/state"; echo "w:7 ${agent}" > "${dir}/.swarm/state/tab"   # its pane, as next_pane records it
  # Started in this project: in a pane it recorded (herdr lists every project's agents).
  printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"agents\":[{\"name\":\"${agent}\",\"agent_status\":\"idle\",\"pane_id\":\"w:7\"}]}}'" > "${dir}/bin/herdr"
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

# The stub lists this project's conductor (and its retired name) in panes the state records, as
# next_pane does: wait addresses an agent by this project's pane, never by a bare name. herdr says
# `done` for both and is never asked for a Claude conductor's state: that is its session's, recorded
# in agents.tsv (sess-c1) and read from the claude stub's fixture.
# shellcheck disable=SC2016 # the stub's $1/$2/$3 are its own arguments, written literally
stub() { # [api-error]
  {
    echo '#!/bin/sh'
    echo 'case "$1 $2" in'
    echo "  \"agent prompt\") echo \"\$*\" >> '${dir}/prompts' ;;"
    echo 'esac'
    echo 'case "$1 $2" in'
    echo "  \"agent list\") echo '{\"result\":{\"agents\":[{\"name\":\"conduct-e1\",\"agent_status\":\"done\",\"pane_id\":\"w:1\"},{\"name\":\"conduct-e1-done\",\"agent_status\":\"done\",\"pane_id\":\"w:2\"}]}}' ;;"
    if [ -n "${1:-}" ]; then echo "  \"agent read\") echo '⏺ API Error: overloaded' ;;"; fi
    echo '  "agent wait"|"agent prompt") case "$3" in w:1|w:2) ;; *) echo "{\"error\":\"not this project'"'"'s pane: $3\"}"; exit 1 ;; esac ;;'
    echo 'esac'
    echo 'case "$1 $2" in "agent list"|"agent read") ;; *)'
    echo "  echo '{\"result\":{\"agent\":{\"agent_status\":\"done\"}}}' ;;"
    echo 'esac'
  } > "${dir}/bin/herdr"
  chmod +x "${dir}/bin/herdr"
}
session() { # <status> [waitingFor] — the conductor's session, as `claude agents --json` lists it
  echo "[{\"sessionId\":\"sess-c1\",\"status\":\"$1\"${2:+,\"waitingFor\":\"$2\"}}]" > "${dir}/claude.json"
}
waitc() { (cd "${dir}" && HERDR_ENV=1 CLAUDE_STUB_AGENTS="${dir}/claude.json" CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" bash "${SWARM}" wait "$@"); }
# `wait` on a conductor: idle without a report is not settled. It returns once the report lands.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p docs/stories bin .swarm/briefs .swarm/state && touch .swarm/briefs/conduct-e1.md && printf 'w:1 conduct-e1\nw:2 conduct-e1-done\n' > .swarm/state/e1)
printf '2026-10-13\tconduct\tconduct-e1\tclaude\topus\thigh\tsess-c1\n' > "${dir}/.swarm/agents.tsv"
stub; session idle
(sleep 2; echo report > "${dir}/.swarm/conduct-e1.report.md") &
got="$(SWARM_CONDUCTOR_POLL=1 waitc conduct-e1 20000)"
reported=no; [[ -f "${dir}/.swarm/conduct-e1.report.md" ]] && reported=yes
wait
if [[ "${got}" == idle && "${reported}" == yes ]]; then
  echo "ok   wait on a conductor whose session is idle holds until its report"; else
  echo "FAIL wait on a conductor whose session is idle holds until its report: got '${got}', report there on return: ${reported}"; fails=$((fails + 1)); fi
rm -f "${dir}/.swarm/conduct-e1.report.md"

# A conductor waiting on a prompt has settled: wait returns at once and says what it waits on.
session waiting "permission prompt"; start=${SECONDS}
got="$(SWARM_CONDUCTOR_POLL=5 waitc conduct-e1 20000)"
if [[ "${got}" == "waiting: permission prompt" && $((SECONDS - start)) -lt 5 ]]; then
  echo "ok   wait on a conductor waiting on a prompt returns at once, naming it"; else
  echo "FAIL wait on a conductor waiting on a prompt returns at once, naming it: got '${got}' after $((SECONDS - start))s"; fails=$((fails + 1)); fi

# A conductor whose session has no entry has exited: wait returns gone at once.
echo '[]' > "${dir}/claude.json"; start=${SECONDS}
got="$(SWARM_CONDUCTOR_POLL=5 waitc conduct-e1 20000)"
if [[ "${got}" == gone && $((SECONDS - start)) -lt 5 ]]; then
  echo "ok   wait on a conductor whose session is gone returns at once"; else
  echo "FAIL wait on a conductor whose session is gone returns at once: got '${got}' after $((SECONDS - start))s"; fails=$((fails + 1)); fi
session idle

# A conductor whose transcript ends on an expired login will not report until the user's /login:
# wait returns auth at once, naming it. The fixture is a real transcript's shape, ids replaced.
fixture="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/login-expired.jsonl"
mkdir -p "${dir}/projects/p"; cp "${fixture}" "${dir}/projects/p/sess-c1.jsonl"; start=${SECONDS}
got="$(SWARM_CONDUCTOR_POLL=5 waitc conduct-e1 20000 2>"${dir}/wait.err")"
if [[ "${got}" == auth && $((SECONDS - start)) -lt 5 ]] && grep -q "conduct-e1: its login expired" "${dir}/wait.err"; then
  echo "ok   wait on a conductor whose login expired returns auth at once, naming it"; else
  echo "FAIL wait on a conductor whose login expired returns auth at once, naming it: got '${got}' after $((SECONDS - start))s, stderr: $(cat "${dir}/wait.err")"; fails=$((fails + 1)); fi
# next says so too: its step stays `wait` (which returns auth at once), its why names auth and /login.
nextc() { (cd "${dir}" && HERDR_ENV=1 CLAUDE_STUB_AGENTS="${dir}/claude.json" CLAUDE_PROJECTS_DIR="${dir}/projects" PATH="${dir}/bin:${PATH}" bash "${SWARM}" next); }
got="$(nextc)"
if [[ "${got}" == "wait conduct-e1"$'\n'"auth: the conductor conduct-e1 stopped on an expired login; run /login"* ]]; then
  echo "ok   next names auth and /login for a conductor whose login expired"; else
  echo "FAIL next names auth and /login for a conductor whose login expired: got '${got}'"; fails=$((fails + 1)); fi
# Only an idle session is auth, as in wait: with the session gone there is nothing to resume.
echo '[]' > "${dir}/claude.json"
got="$(nextc)"
if [[ "${got}" == "wait conduct-e1"$'\n'"the conductor conduct-e1 is still working"* ]]; then
  echo "ok   next does not say auth for a conductor whose session is gone"; else
  echo "FAIL next does not say auth for a conductor whose session is gone: got '${got}'"; fails=$((fails + 1)); fi
session idle
# After an ordinary turn (the same transcript without the auth entry) it is waited on, as below.
grep -v authentication_failed "${fixture}" > "${dir}/projects/p/sess-c1.jsonl"
got="$(nextc)"
if [[ "${got}" == "wait conduct-e1"$'\n'"the conductor conduct-e1 is still working"* ]]; then
  echo "ok   next does not say auth once the conductor's last turn is an ordinary one"; else
  echo "FAIL next does not say auth once the conductor's last turn is an ordinary one: got '${got}'"; fails=$((fails + 1)); fi

# A conductor that never reports does not hang `wait`: the timeout bounds the whole wait.
start=${SECONDS}
got="$(waitc conduct-e1 2000)"
if [[ "${got}" == idle && $((SECONDS - start)) -le 10 ]]; then
  echo "ok   wait on a conductor that never reports ends at its timeout"; else
  echo "FAIL wait on a conductor that never reports ends at its timeout: got '${got}' after $((SECONDS - start))s"; fails=$((fails + 1)); fi

# A conductor has no story, so it is never nudged, even with an API error on its pane: idle with no
# report, wait polls on until the timeout.
stub api-error; rm -f "${dir}/prompts"
start=${SECONDS}
got="$(SWARM_CONDUCTOR_POLL=1 waitc conduct-e1 4000 2>/dev/null)"
if [[ "${got}" == idle && $((SECONDS - start)) -ge 4 && ! -e "${dir}/prompts" ]]; then
  echo "ok   an idle conductor with no report is not nudged, and wait returns at the timeout"; else
  echo "FAIL an idle conductor with no report is not nudged, and wait returns at the timeout: got '${got}' after $((SECONDS - start))s, prompts: $(cat "${dir}/prompts" 2>/dev/null)"; fails=$((fails + 1)); fi

# A conductor of the same name started by another project is refused, never waited on.
printf 'w:9 other\n' > "${dir}/.swarm/state/e1"; stub
got="$(waitc conduct-e1 3000 2>&1; echo "exit $?")"
if [[ "${got}" == *"no agent this project started"* && "${got}" == *"exit 1" ]]; then
  echo "ok   wait refuses another project's conductor of the same name"; else
  echo "FAIL wait refuses another project's conductor of the same name: got '${got}'"; fails=$((fails + 1)); fi
printf 'w:1 conduct-e1\nw:2 conduct-e1-done\n' > "${dir}/.swarm/state/e1"

# A retired conductor (renamed <name>-done) is not waited on for a report. agents.tsv has no line
# for that name, so herdr answers for it.
start=${SECONDS}
got="$(SWARM_CONDUCTOR_POLL=5 waitc conduct-e1-done 20000)"
if [[ "${got}" == "done" && $((SECONDS - start)) -lt 5 ]]; then
  echo "ok   wait on a retired conductor returns at once"; else
  echo "FAIL wait on a retired conductor returns at once: got '${got}' after $((SECONDS - start))s"; fails=$((fails + 1)); fi
rm -rf "${dir}"

# A retired conductor (keep_panes renames it <name>-done) is finished: next must not wait on it.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p docs/stories bin)
printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"agents\":[{\"name\":\"conduct-e1-done\",\"agent_status\":\"idle\"}]}}'" > "${dir}/bin/herdr"
chmod +x "${dir}/bin/herdr"
got="$(cd "${dir}" && HERDR_ENV=1 PATH="${dir}/bin:${PATH}" bash "${SWARM}" next)"; got="${got%%$'\n'*}"
if [[ "${got}" == "done" ]]; then echo "ok   a retired conductor is not waited on"; else
  echo "FAIL a retired conductor is not waited on: want 'done', got '${got}'"; fails=$((fails + 1)); fi
rm -rf "${dir}"

# Another project's conductor runs in a pane this project never opened: next must not wait on it,
# even when this project once had a conductor of the same name in a pane of its own.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p docs/stories bin .swarm/state && echo "w:1 conduct-x" > .swarm/state/tab)
printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"agents\":[{\"name\":\"conduct-x\",\"agent_status\":\"working\",\"pane_id\":\"w:9\"}]}}'" > "${dir}/bin/herdr"
chmod +x "${dir}/bin/herdr"
got="$(cd "${dir}" && HERDR_ENV=1 PATH="${dir}/bin:${PATH}" bash "${SWARM}" next)"; got="${got%%$'\n'*}"
if [[ "${got}" == "done" ]]; then echo "ok   another project's conductor is not waited on"; else
  echo "FAIL another project's conductor is not waited on: want 'done', got '${got}'"; fails=$((fails + 1)); fi
rm -rf "${dir}"

# A long conductor's agent name is cut at 32 characters; close must still find its full tab label.
long="conduct-aws-layer3-claim-sweep-reap"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p .swarm/state && touch ".swarm/state/${long}" ".swarm/state/${long}-2" .swarm/state/short)
short_name="$(cd "${dir}" && bash "${SWARM}" _name "${long}")"
for pair in "${short_name}:${long}" "${long}:${long}" "short:short" "unknown:unknown"; do
  got="$(cd "${dir}" && bash "${SWARM}" _label "${pair%%:*}")"
  if [[ "${got}" == "${pair#*:}" ]]; then echo "ok   tab label for ${pair%%:*}"; else
    echo "FAIL tab label for ${pair%%:*}: want '${pair#*:}', got '${got}'"; fails=$((fails + 1)); fi
done
rm -rf "${dir}"

# `tell <slug> <kind> <file>` sends an idle builder the file and exits 0, leaving no temp file behind.
# A Claude builder's state is its session's (agents.tsv's newest line for s1, then the claude stub's
# fixture), never herdr's: it refuses one busy, waiting (naming on what), gone or unknown instead of
# typing into it. The stub's `agent list` reports s1 as $TELL_STATUS in pane $TELL_PANE; `agent
# prompt` appends what it was sent to ${dir}/sent as one record ending in a `--` line, and reports
# the agent working. With $TELL_GOAL set (a goal test), a prompt that is not a /goal makes sess-s1
# busy, as its turn starts, or $TELL_AFTER: idle (herdr said working, the session has not started)
# or waiting (on a permission prompt); a /goal's record also holds `state: <sess-s1's status>`
# as the stub saw it, and the stub appends to sess-s1's log a goal_status set entry for it, written
# now (new), an hour ago (old), or none, showing the goal on the pane instead (pane).
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p docs/stories bin .swarm/state projects/p && printf 'w:1 s1\nw:2 conduct-e\n' > .swarm/state/t)
cat > "${dir}/bin/herdr" <<EOF
#!/bin/sh
case "\$1 \$2" in
  "agent list") echo "{\"result\":{\"agents\":[{\"name\":\"s1\",\"agent_status\":\"\${TELL_STATUS}\",\"pane_id\":\"\${TELL_PANE:-w:1}\"},{\"name\":\"conduct-e\",\"agent_status\":\"working\",\"pane_id\":\"w:2\"}]}}" ;;
  "agent prompt") st=\$(sed -n 's/.*"sess-s1","status":"\([a-z]*\)".*/\1/p' "${dir}/claude.json")
    case "\$4" in
      "/goal "*) printf '%s\nstate: %s\n--\n' "\$4" "\$st" >> "${dir}/sent"
        [ "\${TELL_GOAL}" = pane ] && printf 'Goal set: %s\n' "\${4#/goal }" > "${dir}/screen"
        if [ "\${TELL_GOAL}" = new ] || [ "\${TELL_GOAL}" = old ]; then
          python3 -c 'import datetime, json, sys
t = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(hours=sys.argv[1] == "old")
print(json.dumps({"type": "attachment", "timestamp": t.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
                  "attachment": {"type": "goal_status", "met": False, "sentinel": True, "condition": sys.argv[2]}}))' \
            "\${TELL_GOAL}" "\${4#/goal }" >> "${dir}/projects/p/sess-s1.jsonl"
        fi ;;
      *) printf '%s\n--\n' "\$4" >> "${dir}/sent"
        after="\${TELL_AFTER:-busy}\""; [ "\${TELL_AFTER}" = waiting ] && after='waiting","waitingFor":"permission prompt"'
        [ -z "\${TELL_GOAL}" ] || sed -i.bak "s/\"sess-s1\",\"status\":\"[a-z]*\"/\"sess-s1\",\"status\":\"\$after/" "${dir}/claude.json" ;;
    esac
    echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent read") cat "${dir}/screen" 2>/dev/null ;;
esac
EOF
chmod +x "${dir}/bin/herdr"
printf -- '- a finding\n' > "${dir}/findings.md"
mkdir -p "${dir}/tmp"
tsv() { printf '2026-10-13\tcode\ts1\t%s\topus\thigh\t%s\n' "$1" "$2" >> "${dir}/.swarm/agents.tsv"; }
tsession() { # <status> [waitingFor] — sess-s1's entry; `none` lists no entry for it
  if [[ "$1" == none ]]; then echo '[]'; else echo "[{\"sessionId\":\"sess-s1\",\"status\":\"$1\"${2:+,\"waitingFor\":\"$2\"}},{\"sessionId\":\"sess-old\",\"status\":\"${OLD:-idle}\"}]"; fi > "${dir}/claude.json"
}
# tellout <herdr status> <tell args...> — run tell; print its output, then "exit N".
tellout() {
  local st="$1"; shift; rm -f "${dir}/sent"
  (cd "${dir}" && HERDR_ENV=1 TMPDIR="${dir}/tmp" TELL_STATUS="${st}" TELL_GOAL="${TELL_GOAL:-}" TELL_AFTER="${TELL_AFTER:-}" CLAUDE_STUB_AGENTS="${CLAUDE_STUB_AGENTS:-${dir}/claude.json}" \
    CLAUDE_PROJECTS_DIR="${dir}/projects" SWARM_PROMPT_TIMEOUT_MS="${PTO:-2000}" PATH="${dir}/bin:${PATH}" bash "${SWARM}" tell s1 "$@" 2>&1; echo "exit $?")
}
refused() { # <name> <want in the message> <herdr status> <tell args...>
  local name="$1" want="$2" out; shift 2
  out="$(tellout "$@")"
  if [[ "${out}" == *"${want}"* && "${out}" == *"exit 1" && ! -f "${dir}/sent" ]]; then echo "ok   ${name}"; else
    echo "FAIL ${name}: got '${out}', sent: $(cat "${dir}/sent" 2>/dev/null)"; fails=$((fails + 1)); fi
}
told() { # <name> <herdr status> <tell args...>
  local name="$1" out sent left; shift
  out="$(tellout "$@")"; sent="$(cat "${dir}/sent" 2>/dev/null || true)"; left="$(ls "${dir}/tmp")"
  if [[ "${out}" == *"exit 0" && "${sent}" == "From the conductor:"* && "${sent}" == *"- a finding"* && -z "${left}" ]]; then echo "ok   ${name}"; else
    echo "FAIL ${name}: got '${out}', sent '${sent}', left '${left}'"; fails=$((fails + 1)); fi
}
tsv claude sess-s1
tsession idle; told "tell sends an idle session the findings while herdr says working, and leaves no temp file" working findings findings.md
tsession busy; refused "tell refuses a busy session while herdr says done: still working" "still working" "done" findings findings.md
tsession waiting "permission prompt"; refused "tell refuses a waiting session, naming what it waits for" "waiting on permission prompt" idle findings findings.md
tsession none; refused "tell refuses a session that is gone" "gone" idle findings findings.md
tsession compacting; refused "tell refuses a session in a state it does not know (unknown)" "(unknown)" idle findings findings.md
tsession idle
CLAUDE_STUB_AGENTS="${dir}/no-such-file" refused "tell refuses when Claude Code cannot list its sessions (unknown)" "(unknown)" idle findings findings.md
for k in nudge resume; do told "tell takes the kind ${k}" idle "${k}" findings.md; done
# goal = N: once the findings are taken up, a findings tell sends a fresh /goal mid-turn (sess-s1 busy)
# and finds it set in sess-s1's log after the tell began; a nudge or resume tell, or goal off, sends one record.
# The events log holds one ok tell:findings line, and when the goal step fails, its failure after it.
records() { grep -c '^--$' "${dir}/sent" 2>/dev/null || true; }
reply() { local f; f="$(awk '/^reply_sentence\(\)/,/^}$/' "${SWARM}")"; (eval "${f}"; reply_sentence "$1"); }
goalcase() { # <name> <0: told with a goal, 1: refused naming s1> <want in the /goal or the refusal> <tell args...>
  # A refusal leaves $NREC records (2: the /goal was sent) and says the findings must not be sent again.
  local name="$1" rc="$2" want="$3" out goal ev; shift 3
  : > "${dir}/projects/p/sess-s1.jsonl"; rm -f "${dir}/screen" "${dir}/.swarm/events.tsv"; tsession idle
  out="$(tellout idle "$@")"; ev="$(cut -f2,3,5 "${dir}/.swarm/events.tsv" | tr '\t\n' ' |')"; goal="$(sed -n '/^\/goal /,/^--$/p' "${dir}/sent" 2>/dev/null)"
  if [[ ${rc} == 0 && "${out}" == *"exit 0" && "$(records)" == 2 && "$(head -1 "${dir}/sent")" == "From the conductor:" \
        && "${goal}" == *"the conductor's review findings, sent to you just before this goal, are addressed (each fixed, or declined with a reason in your reply) and you have replied"*"${want}"*"or stop after 4 more turns"* && "${goal}" == *"state: busy"* \
        && -z "$(ls "${dir}/tmp")" && "${ev}" == "tell:findings s1 ok|" ]] \
     || [[ ${rc} == 1 && "${out}" == *"s1: ${want}"*"do not send them again"*"exit 1" && "$(records)" == "${NREC:-2}" \
           && "${ev}" == "tell:findings s1 ok|tell:findings s1 s1: ${want}"* ]]; then echo "ok   ${name}"; else
    echo "FAIL ${name}: got '${out}', events '${ev}', sent '$(cat "${dir}/sent" 2>/dev/null)'"; fails=$((fails + 1)); fi
}
onerecord() { # <name> <tell args...> — the tell sends one record, no goal
  local name="$1"; shift
  tsession idle; : "$(TELL_GOAL=new tellout idle "$@")"   # in $(), so a failing tell does not trip set -e
  if [[ "$(records)" == 1 ]]; then echo "ok   ${name}"; else
    echo "FAIL ${name}: sent '$(cat "${dir}/sent" 2>/dev/null)'"; fails=$((fails + 1)); fi
}
mkdir -p "${dir}/.claude/swarm"; echo "goal = 4" > "${dir}/.claude/swarm/config"
TELL_GOAL=new goalcase "goal on: a findings tell sends the findings, then mid-turn a /goal with the story reply, and finds it set" 0 "$(reply story)" findings findings.md
TELL_GOAL=old goalcase "goal on: only a set entry older than the tell fails the tell, naming s1" 1 "the findings were delivered, but its session log shows no goal set" findings findings.md
TELL_GOAL=pane goalcase "goal on: a goal on the pane with no new entry fails the tell, naming s1" 1 "the findings were delivered, but its session log shows no goal set" findings findings.md
# The /goal goes only into a turn that has started, never into a dialog: nothing is typed otherwise.
t0=${SECONDS}
TELL_GOAL=new TELL_AFTER=waiting NREC=1 PTO=10000 goalcase "goal on: a session waiting on a prompt once the findings are taken up gets no /goal; the tell fails naming s1 and the prompt" \
  1 "the findings were delivered, but its builder is waiting on permission prompt, so no /goal was sent" findings findings.md
if (( SECONDS - t0 < 5 )); then echo "ok   goal on: a waiting session fails the tell at once, not at the timeout"; else
  echo "FAIL goal on: a waiting session fails the tell at once, not at the timeout: took $((SECONDS - t0))s"; fails=$((fails + 1)); fi
TELL_GOAL=new TELL_AFTER=idle NREC=1 goalcase "goal on: a session still idle while herdr says working gets no /goal; the tell fails naming s1" \
  1 "the findings were delivered, but its session did not read busy" findings findings.md
for k in nudge resume; do onerecord "goal on: a ${k} tell sends no goal" "${k}" findings.md; done
# A second findings tell right after one that set its goal: the same condition's entry from the
# first tell is older than the second tell, so with no new entry the second fails.
tsession idle; first="$(TELL_GOAL=new tellout idle findings findings.md)"; tsession idle
out="$(TELL_GOAL=pane tellout idle findings findings.md)"
if [[ "${first}" == *"exit 0" && "${out}" == *"s1: the findings were delivered, but its session log shows no goal set"*"exit 1" ]]; then echo "ok   goal on: a repeated findings tell does not count the previous tell's goal"; else
  echo "FAIL goal on: a repeated findings tell does not count the previous tell's goal: got '${out}'"; fails=$((fails + 1)); fi
printf -- '---\nkind: code\nstatus: ready\nepic: e1\n---\n' > "${dir}/docs/stories/s1.md"; printf 'goal = 4\npr_per = epic\n' > "${dir}/.claude/swarm/config"
TELL_GOAL=new goalcase "goal on, pr_per = epic: the /goal holds the epic-mode reply" 0 "$(reply epic)" findings findings.md
rm -rf "${dir}/.claude" "${dir}/docs/stories/s1.md"
onerecord "goal off: a findings tell sends no goal" findings findings.md
refused "tell with no kind fails, listing the three" "findings, nudge or resume, not ''" idle
refused "the old form, tell <slug> <file>, fails on its kind" "findings, nudge or resume, not 'findings.md'" idle findings.md
refused "tell with an unknown kind fails, listing the three" "findings, nudge or resume, not 'review'" idle review findings.md
refused "tell with a kind and no file fails" "no such file ''" idle findings
TELL_PANE=w:77 refused "tell refuses another project's agent of the same name" "not one this project started" idle findings findings.md
# A reused name: the older line's session (sess-old) is retired; the newer line's (sess-s1) decides.
: > "${dir}/.swarm/agents.tsv"; tsv claude sess-old; tsv claude sess-s1
OLD=busy tsession idle; told "a reused name reads the newer line (older busy, newer idle): told" working findings findings.md
OLD=idle tsession busy; refused "a reused name reads the newer line (older idle, newer busy): refused" "still working" idle findings findings.md
# No session recorded ('-', as a codex agent has): herdr answers for it.
tsv codex -; tsession busy
told "tell sends an agent with no session that herdr reports as idle" idle findings findings.md
told "tell also sends one herdr reports as done" "done" findings findings.md
refused "tell refuses one herdr reports as working" "still working" working findings findings.md
refused "tell refuses one herdr reports as blocked on a prompt" "waiting on a prompt" blocked findings findings.md
# herdr giving no status (agent_field reads it as unknown): refused as unknown, never as another project's.
refused "tell refuses its own agent with no session and no herdr status as unknown" "herdr gives no state for it (unknown)" "" findings findings.md
# `tell conduct-e note <file>` appends the file to the conductor's inbox while its session is busy,
# sends no prompt, and logs tell:note; a second note appends after the first. A note to a builder,
# or to a conductor this project never started, is refused and writes no inbox.
inbox="${dir}/.swarm/inbox/conduct-e.md"
printf '2026-10-13\tconduct\tconduct-e\tclaude\topus\thigh\tsess-c\n' >> "${dir}/.swarm/agents.tsv"
echo '[{"sessionId":"sess-c","status":"busy"}]' > "${dir}/claude.json"
noteout() { rm -f "${dir}/sent"; (cd "${dir}" && HERDR_ENV=1 TMPDIR="${dir}/tmp" CLAUDE_STUB_AGENTS="${dir}/claude.json" PATH="${dir}/bin:${PATH}" bash "${SWARM}" tell "$@" 2>&1; echo "exit $?"); }
printf 'first note\n' > "${dir}/n1.md"; printf 'second note\n' > "${dir}/n2.md"
out="$(noteout conduct-e note n1.md)"
if [[ "${out}" == *"noted conduct-e"*"exit 0" && "$(cat "${inbox}" 2>/dev/null)" == *"first note"* && ! -f "${dir}/sent" \
      && "$(tail -1 "${dir}/.swarm/events.tsv" | cut -f2,3,5)" == $'tell:note\tconduct-e\tok' ]]; then echo "ok   tell note leaves a busy conductor the file in its inbox, prompts nothing, and logs tell:note ok"; else
  echo "FAIL tell note leaves a busy conductor the file in its inbox: got '${out}', inbox '$(cat "${inbox}" 2>/dev/null)', sent '$(cat "${dir}/sent" 2>/dev/null)', events '$(tail -1 "${dir}/.swarm/events.tsv")'"; fails=$((fails + 1)); fi
out="$(noteout conduct-e note n2.md)"
if [[ "${out}" == *"exit 0" && "$(grep -v '^From the lead' "${inbox}" | grep .)" == $'first note\nsecond note' ]]; then echo "ok   a second note appends after the first"; else
  echo "FAIL a second note appends after the first: got '${out}', inbox '$(cat "${inbox}")'"; fails=$((fails + 1)); fi
rm -f "${inbox}"
for who in s1 conduct-zz; do
  out="$(noteout "${who}" note n1.md)"
  want="a note goes only to a conductor"; [[ ${who} == s1 ]] || want="could not reach conduct-zz"
  if [[ "${out}" == *"${want}"*"exit 1" && ! -e "${inbox%/*}/${who}.md" \
        && "$(tail -1 "${dir}/.swarm/events.tsv" | cut -f2,3,5)" != *ok ]]; then echo "ok   tell note refuses ${who}, writes no inbox and logs no ok"; else
    echo "FAIL tell note refuses ${who}: got '${out}', inbox '$(ls "${inbox%/*}" 2>/dev/null)'"; fails=$((fails + 1)); fi
done
out="$(noteout conduct-e bogus n1.md)"
if [[ "${out}" == *"findings, nudge or resume, not 'bogus' (or note, to a conductor)"*"exit 1" ]]; then echo "ok   an unknown kind's refusal lists note with findings, nudge and resume"; else
  echo "FAIL an unknown kind's refusal lists note with findings, nudge and resume: got '${out}'"; fails=$((fails + 1)); fi
rm -rf "${dir}"

# conduct on a later epic sets it active, says so, and status stops listing it as waiting on you; an
# active epic is left as it is, silently. An epic file that cannot be written stays later, conduct says
# so and still succeeds. herdr is a stub whose one answer has every field conduct reads.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p bin && item stories/s.md 'status: ready' 'kind: code' 'epic: e')
printf '#!/bin/sh\necho %s\n' "'{\"result\":{\"workspaces\":[{\"workspace_id\":\"w\",\"label\":\"e\"}],\"root_pane\":{\"pane_id\":\"w:1\"},\"agent\":{\"agent_status\":\"working\"},\"agents\":[],\"panes\":[]}}'" > "${dir}/bin/herdr"
chmod +x "${dir}/bin/herdr"
conduct() { (cd "${dir}" && HERDR_ENV=1 CLAUDE_CONFIG_DIR="${dir}/cc" PATH="${dir}/bin:${PATH}" bash "${SWARM}" conduct e 2>&1); }
for st in later active; do
  (cd "${dir}" && item epics/e.md "status: ${st}")
  out="$(conduct)"; rm -rf "${dir}/.swarm/state"
  said=no; grep -q '^epic e: status later -> active' <<< "${out}" && said=yes
  # The whole output, then grep: grep -q can close the pipe on status, which fails under pipefail.
  waits=no; grep -q 'later epic: e' <<< "$(cd "${dir}" && env -u HERDR_ENV bash "${SWARM}" status)" && waits=yes
  got="$(sed -n 's/^status: //p' "${dir}/docs/epics/e.md")|${said}|${waits}"
  want="active|no|no"; [[ ${st} == later ]] && want="active|yes|no"
  if [[ "${got}" == "${want}" ]]; then echo "ok   conduct on a ${st} epic leaves it active (active|said|waits on you: ${got})"; else
    echo "FAIL conduct on a ${st} epic: want '${want}', got '${got}': ${out}"; fails=$((fails + 1)); fi
done
(cd "${dir}" && item epics/e.md "status: later"); chmod a-w "${dir}/docs/epics"
out="$(conduct; echo "exit $?")"; rm -rf "${dir}/.swarm/state"; chmod u+w "${dir}/docs/epics"
got="$(sed -n 's/^status: //p' "${dir}/docs/epics/e.md")|$(ls "${dir}/docs/epics")"
if [[ "${got}" == "later|e.md" && "${out}" == *"epic e: could not write "*"/docs/epics/e.md, so it is still later"*"exit 0" ]]; then
  echo "ok   conduct on a later epic it cannot write leaves it later, says so, and exits 0"; else
  echo "FAIL conduct on a later epic it cannot write: got '${got}': ${out}"; fails=$((fails + 1)); fi
rm -rf "${dir}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
