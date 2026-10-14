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
# prompt` logs what it was sent and reports the agent working.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
(cd "${dir}" && git init -q && mkdir -p docs/stories bin .swarm/state && echo "w:1 s1" > .swarm/state/t)
cat > "${dir}/bin/herdr" <<EOF
#!/bin/sh
case "\$1 \$2" in
  "agent list") echo "{\"result\":{\"agents\":[{\"name\":\"s1\",\"agent_status\":\"\${TELL_STATUS}\",\"pane_id\":\"\${TELL_PANE:-w:1}\"}]}}" ;;
  "agent prompt") printf '%s\n' "\$4" >> "${dir}/sent"; echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
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
  (cd "${dir}" && HERDR_ENV=1 TMPDIR="${dir}/tmp" TELL_STATUS="${st}" CLAUDE_STUB_AGENTS="${CLAUDE_STUB_AGENTS:-${dir}/claude.json}" PATH="${dir}/bin:${PATH}" bash "${SWARM}" tell s1 "$@" 2>&1; echo "exit $?")
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
rm -rf "${dir}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
