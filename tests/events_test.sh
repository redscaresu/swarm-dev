#!/usr/bin/env bash
# events_test.sh — .swarm/events.tsv, the audit log: every command that changes state appends one
# well-formed line (reconcile and unblock one per item), failures included, with no message
# contents, and an unwritable .swarm never fails the command. gh and herdr are stubs on PATH.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
P="${ROOT}/proj"; LOG="${P}/.swarm/events.tsv"
trap 'chmod -R u+w "${ROOT}" 2>/dev/null; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
# The claude stub goes first on PATH, so no run here reaches the real claude.
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}"
fails=0
U="https://github.com/o/r/pull"

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}

item() { # <path under docs> <front-matter line>... — a fresh item: its file, and no state file
  local path="${P}/docs/$1" title; rm -f "${P}/.swarm/board-state/${1%.md}"; shift
  title="$(basename "${path}" .md)"
  mkdir -p "$(dirname "${path}")"
  { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"
}

mkdir -p "${P}/.swarm/state" "${P}/docs/stories" "${P}/docs/epics" "${ROOT}/bin"
git -C "${P}" init -q
cat > "${ROOT}/bin/gh" <<'STUB'
#!/bin/sh
[ "$1 $2" = "pr list" ] && { echo 0; exit 0; }   # no story has a PR
case "$3" in */pull/1) echo '{"state":"MERGED"}' ;; */pull/2) echo '{"state":"CLOSED"}' ;; *) exit 1 ;; esac
STUB
cat > "${ROOT}/bin/herdr" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;   # start_agent's require_herdr_version
  "agent list") echo '{"result":{"agents":[{"name":"s1","agent_status":"idle","pane_id":"w:1"}]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w:1"}]}}' ;;
  "agent prompt") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "tab list") echo '{"result":{"tabs":[]}}' ;;
esac
STUB
mkdir -p "${ROOT}/nobin" "${ROOT}/slow"
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/nobin/herdr"; cp "${ROOT}/nobin/herdr" "${ROOT}/nobin/gh"
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr" "${ROOT}/nobin/herdr" "${ROOT}/nobin/gh"
echo "w:1 s1" > "${P}/.swarm/state/t1"

run() { (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" >/dev/null 2>&1); }
# outside <cmd...> — run <cmd> with P and LOG on a project that is not a git repo: its board is outside
# any repo, so finish and drop delete in place (pr_removes_story_test.sh has the board PR they open in one).
outside() { local p="${P}" l="${LOG}" rc=0; P="${ROOT}/nogit"; LOG="${P}/.swarm/events.tsv"; mkdir -p "${P}/docs/stories" "${P}/.swarm" "${P}/.claude/swarm"; : >> "${P}/.claude/swarm/config"; "$@" || rc=$?; P="${p}"; LOG="${l}"; return "${rc}"; }
lines() { if [[ -f "${LOG}" ]]; then wc -l < "${LOG}" | tr -d ' '; else echo 0; fi; }

# appends <name> <n> <command> <target> <outcome-prefix> <swarm args...> — run it; exactly <n> new
# lines, each five tab-separated fields: ISO UTC time, command, target, actor, outcome.
appends() {
  local name="$1" n="$2" cmd="$3" target="$4" outcome="$5" was new; shift 5
  was="$(lines)"; run "$@" || true
  new="$(tail -n +"$((was + 1))" "${LOG}" 2>/dev/null || true)"
  check "${name}: ${n} line(s)" test "$(( $(lines) - was ))" -eq "${n}"
  [[ ${n} -gt 0 ]] || return 0
  # shellcheck disable=SC2016 # an awk program
  check "${name}: well-formed" awk -F'\t' -v c="${cmd}" -v t="${target}" -v o="${outcome}" \
    'NF != 5 || $1 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ || $2 != c || (t != "*" && $3 != t) || $4 != "w:me" || index($5, o) != 1 { bad = 1 } END { exit bad }' <<< "${new}"
}

item stories/s1.md 'status: ready'
item stories/s2.md 'status: blocked' 'depends_on: [gone]'
item stories/s3.md 'status: blocked' 'depends_on: [gone]'
item stories/m1.md 'status: review' "prs: ${U}/1"
item stories/c1.md 'status: review' "prs: ${U}/2"
printf 'SECRET-CONTENT-123 in the findings\n' > "${P}/findings.md"

# A review logs the PRs it names, so outcomes can tell which an epic's review handed over.
appends "review logs the PRs it names" 1 review s1 "ok (${U}/9)" review s1 "${U}/9"
appends "a failed review" 1 review s1 "review: not a PR URL" review s1 "https://x"$'\t'"y"
# A tell's kind goes with its command (tell:<kind>), so its target stays the slug, which the stall rule reads.
appends "tell" 1 tell:findings s1 ok tell s1 findings findings.md
appends "a tell with no kind" 1 tell s1 "tell: the kind must be findings, nudge or resume" tell s1
# Only a real kind goes with the command: an unknown one, or the old form's file path, logs plain tell.
appends "a tell with an unknown kind" 1 tell s1 "tell: the kind must be findings, nudge or resume" tell s1 bogus findings.md
appends "the old form, tell <slug> <file>" 1 tell s1 "tell: the kind must be findings, nudge or resume" tell s1 /tmp/f.md
check "tell never logs the file's contents" bash -c "! grep -q SECRET-CONTENT '${LOG}'"
appends "close" 1 close s1 ok close s1
# A close's cause goes with its command too (close:<cause>), and the target stays the slug.
appends "close with a cause" 1 close:bound s1 ok close s1 bound
appends "tidy --yes" 1 tidy - ok tidy --yes
appends "tidy without --yes logs nothing" 0 - - - tidy
appends "unblock, one per story" 2 unblock '*' ok unblock
appends "reconcile, one per item" 2 reconcile '*' ok reconcile
check "reconcile says which it finished and which it reopened" bash -c "grep -q \$'reconcile\tm1\tw:me\tok (finished)' '${LOG}' && grep -q \$'reconcile\tc1\tw:me\tok (reopened)' '${LOG}'"
outside item stories/s1.md 'status: ready'
outside appends "finish" 1 finish s1 ok finish s1
appends "log-finding" 1 log-finding "vacuous-test ${U}/9" ok log-finding vacuous-test "${U}/9" "a line"
# The flags before the kind, in either order, leave the target <kind> <pr>; a decline goes with the command.
appends "log-finding --reviewer then --declined" 1 log-finding:declined "k ${U}/9" ok log-finding --reviewer codex --declined nit k "${U}/9" t
appends "log-finding --declined then --reviewer" 1 log-finding:declined "k ${U}/9" ok log-finding --declined wrong --reviewer lead k "${U}/9" t
appends "log-finding --declined out-of-scope --reviewer" 1 log-finding:declined "k ${U}/9" ok log-finding --declined out-of-scope --reviewer codex k "${U}/9" t
appends "log-finding --reviewer" 1 log-finding "k ${U}/9" ok log-finding --reviewer conductor k "${U}/9" t
appends "a failed story" 1 story nope "no story" story nope
appends "a failed conduct" 1 conduct nope "no epic" conduct nope
appends "a failed agent, logged by its agent name" 1 agent n1-x "no prompt file" agent t "N1 x" "${P}" code "${P}/missing.md"
appends "log-finding with no arguments" 1 log-finding - "usage" log-finding
# A die inside a nested $(...) (item_file, here) gives only its exit status: a caller could have
# tolerated it, so its message is never taken as the outcome.
appends "a die in a nested substitution gives failed (exit N)" 1 review nope "failed (exit 1)" review nope "${U}/9"
appends "an unknown command logs nothing" 0 - - - bogus
appends "--help logs nothing" 0 - - - --help
appends "-h logs nothing" 0 - - - -h

# DIE_FILE and DIE_LEVEL are main's own: ones set in the environment are never used.
(cd "${P}" || exit 1; DIE_FILE="${ROOT}/planted" DIE_LEVEL=0 SWARM_DIE_FILE="${ROOT}/planted" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" policy bogus >/dev/null 2>&1) || true
(cd "${P}" || exit 1; DIE_FILE="${ROOT}/planted" DIE_LEVEL=0 SWARM_DIE_FILE="${ROOT}/planted" PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" story nope >/dev/null 2>&1) || true
check "a DIE_FILE from the environment is never written" test ! -e "${ROOT}/planted"

# Signals, sent to swarm.sh's pid alone (no process group), must stop it at once. A logged command
# (tell, its stubbed prompt hanging) is logged as interrupted, leaves no temp file, and keeps the
# exit status 128+N. A read-only one (wait, its stubbed wait hanging) just stops.
# shellcheck disable=SC2016 # the stub's own shell expands these
printf '#!/bin/sh\ncase "$1 $2" in "agent prompt") exec sleep 37 ;; "agent wait") exec sleep 38 ;; esac\nexec "%s" "$@"\n' "${ROOT}/bin/herdr" > "${ROOT}/slow/herdr"
chmod +x "${ROOT}/slow/herdr"; mkdir -p "${ROOT}/sigtmp"; echo "w:1 s1" > "${P}/.swarm/state/t1"
# term_pid <swarm args...> — start it, TERM its pid once it is under way, and print "<exit> <seconds>".
term_pid() {
  local pid code=0 t0
  (cd "${P}" || exit 1; HERDR_ENV=1 HERDR_PANE_ID=w:me TMPDIR="${ROOT}/sigtmp" PATH="${ROOT}/slow:${ROOT}/bin:${PATH}" exec bash "${SWARM}" "$@" >/dev/null 2>&1) &
  pid=$!
  sleep 2; t0=${SECONDS}; kill -TERM "${pid}" || true
  { wait "${pid}"; } 2>/dev/null || code=$?
  echo "${code} $((SECONDS - t0))"
}
was="$(lines)"
read -r code took <<< "$(term_pid tell s1 findings findings.md)"
check "a TERM to the pid stops a logged command at once, with exit 143" test "${code}" -eq 143 -a "${took}" -le 2
check "a TERM is logged as interrupted" bash -c "tail -n +$((was + 1)) '${LOG}' | grep -q \$'^[^\t]*\ttell:findings\ts1\tw:me\tinterrupted\$'"
check "a TERM leaves no temp file" test -z "$(ls "${ROOT}/sigtmp")"
sleep 1; check "a TERM leaves nothing of the command running" bash -c "! pgrep -f 'sleep 3[7]' >/dev/null"
read -r code took <<< "$(term_pid wait s1)"
check "a TERM to the pid stops a long wait at once, with exit 143" test "${code}" -eq 143 -a "${took}" -le 2

# The read-only commands, written out here: READ_ONLY_COMMANDS must be exactly this, so a command
# that changes state (story, say) cannot be declared read-only without this test changing too.
RO_EXPECTED="base cost config dash dataset flow features findings grants review-yield lessons next outcomes policy status wait wait-pr watch _base _brief _name _conductor _role _pane _target _trusted _mtime _step-up _step"
ro_sorted() { tr ' ' '\n' | grep -v '^$' | sort | tr '\n' ' '; }
check "READ_ONLY_COMMANDS is exactly the expected read-only set" \
  test "$(sed -n 's/^READ_ONLY_COMMANDS="\(.*\)"$/\1/p' "${SWARM}" | ro_sorted)" == "$(ro_sorted <<< "${RO_EXPECTED}")"

# Every dispatch arm, read off the case statement, is read-only (logs nothing) or logged (one line),
# so a new command can never slip past the log. reconcile and unblock log per item (above); init
# refuses outside a git root before logging, so a refusal writes nothing (init_test.sh checks both).
# A bare project, no herdr: every arm stops at once.
Q="${ROOT}/bare"; mkdir -p "${Q}/.claude/swarm" "${Q}/docs/stories" "${Q}/docs/epics" "${Q}/docs/hld"; : > "${Q}/.claude/swarm/config"
ro=" ${RO_EXPECTED} "
arms="$(awk '/^dispatch\(\) \{/ { d = 1; next } d && /^  esac/ { exit } d && match($0, /^    [a-z_|-]+\)/) { a = substr($0, 5, RLENGTH - 5); gsub(/\|/, " ", a); print a }' "${SWARM}" | tr ' ' '\n')"
check "the case statement's arms were read" test "$(wc -l <<< "${arms}")" -gt 20
for arm in ${RO_EXPECTED}; do
  check "read-only ${arm} is a command" grep -qx -- "${arm}" <<< "${arms}"
done
for arm in ${arms}; do
  [[ "${arm}" == reconcile || "${arm}" == unblock || "${arm}" == init ]] && continue
  args=(); [[ "${arm}" == tidy ]] && args=(--yes); [[ "${arm}" == intervene ]] && args=(lead-hand x)
  # hold logs only for a ready story on the board.
  [[ "${arm}" == hold ]] && { printf -- '---\nstatus: ready\n---\n' > "${Q}/docs/stories/h.md"; args=(h x); }
  [[ "${arm}" == upgrade ]] && args=(--foreground)   # its starter only detaches the worker, which logs the run
  n=0; [[ "${ro}" == *" ${arm} "* ]] || n=1
  before="$(LOG="${Q}/.swarm/events.tsv" lines)"
  (cd "${Q}" || exit 1; env -u HERDR_ENV PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" "${arm}" ${args[@]+"${args[@]}"} </dev/null >/dev/null 2>&1) || true
  after="$(LOG="${Q}/.swarm/events.tsv" lines)"
  what="read-only, not logged"; [[ ${n} == 0 ]] || what="logged"
  check "arm ${arm}: ${what}" test "$((after - before))" -eq "${n}"
  rm -f "${Q}/docs/stories/h.md"   # hold's ready story, so no later arm sees it
done
appends "next logs nothing" 0 - - - next
appends "status logs nothing" 0 - - - status
appends "_role logs nothing" 0 - - - _role s1

# An unwritable .swarm (and log): the command still succeeds, and the log is unchanged.
unwritable() {
  item stories/s4.md 'status: ready'
  was="$(lines)"; chmod a-w "${LOG}" "${P}/.swarm"
  check "an unwritable .swarm never fails the command" run finish s4
  chmod u+w "${P}/.swarm" "${LOG}"
  check "an unwritable .swarm: the command did its work" test ! -f "${P}/docs/stories/s4.md"
  check "an unwritable .swarm: nothing logged" test "$(lines)" -eq "${was}"
}
outside unwritable

# wait is read-only, but a nudge is logged: s1's builder sits idle and story/s1 has no PR, so wait
# nudges it IDLE_NUDGES times and appends one `nudge s1` line each, and nothing else.
item stories/s1.md 'status: ready' 'kind: code'
echo "w:1 s1" > "${P}/.swarm/state/t1"
printf '2026-10-13\tcode\ts1\tclaude\topus\thigh\tsess-s1\n' >> "${P}/.swarm/agents.tsv"
appends "outcomes logs nothing" 0 - - - outcomes
echo '[{"sessionId":"sess-s1","status":"idle"}]' > "${ROOT}/claude.json"
git -C "${P}" remote add origin https://github.com/o/r
was="$(lines)"
(cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me SWARM_STALL_POLL_MS=200 CLAUDE_STUB_AGENTS="${ROOT}/claude.json" \
  PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" wait s1 >/dev/null 2>&1) || true
new="$(tail -n +"$((was + 1))" "${LOG}")"
check "a nudging wait appends a line per nudge" test "$(grep -c . <<< "${new}")" -eq 3
check "a nudging wait appends only nudge lines" test "$(grep -cv $'^[^\t]*\tnudge\ts1\tw:me\tok$' <<< "${new}")" -eq 0

# --- Each escalation step writes its own line with its UTC time, for the training data: escalate
# when build_story starts an escalate build, escalated when that build's close makes the story the
# lead's, then reset or drop with the lead's reason. A project of its own, with its own herdr and gh.
P="${ROOT}/esc"; LOG="${P}/.swarm/events.tsv"; EB="${ROOT}/escbin"
mkdir -p "${P}/.claude/swarm" "${EB}"; : > "${P}/.claude/swarm/config"
git init -q --bare "${ROOT}/esc.git"; git -C "${ROOT}/esc.git" symbolic-ref HEAD refs/heads/main; git init -q "${P}"; git -C "${P}" remote add origin "${ROOT}/esc.git"
git -C "${P}" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init && git -C "${P}" push -q origin HEAD:refs/heads/main
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${EB}/herdr"
cat >> "${EB}/herdr" <<'STUB'
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;   # start_agent's require_herdr_version
  "tab create") echo '{"result":{"root_pane":{"pane_id":"w:5"}}}' ;;
  "agent start") touch "$H/esc-started" ;;
  "agent list") if [ -e "$H/esc-started" ]; then echo '{"result":{"agents":[{"name":"x1","agent_status":"idle","pane_id":"w:5"}]}}'
                else echo '{"result":{"agents":[]}}'; fi ;;
  "agent prompt") echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "tab list") echo '{"result":{"tabs":[]}}' ;;
  "pane list") echo '{"result":{"panes":[{"pane_id":"w:5"}]}}' ;;
esac
STUB
printf '%s\n' '#!/bin/sh' "[ \"\$1 \$2\" = 'pr list' ] && echo '[{\"number\":1,\"state\":\"CLOSED\",\"url\":\"${U}/1\"},{\"number\":2,\"state\":\"OPEN\",\"url\":\"${U}/2\"}]'" 'exit 0' > "${EB}/gh"
chmod +x "${EB}/herdr" "${EB}/gh"
run() { (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me HERDR_WORKSPACE_ID=w PATH="${EB}:${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" >/dev/null 2>&1); }
logged() { # <command> <target> <outcome> — events.tsv has this line, with an ISO UTC time and the actor
  # shellcheck disable=SC2016 # an awk program
  awk -F'\t' -v c="$1" -v t="$2" -v o="$3" '$1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ \
    && NF == 5 && $2 == c && $3 == t && $4 == "w:me" && $5 == o { f = 1 } END { exit !f }' "${LOG}"
}
item stories/x1.md 'status: ready' 'kind: code' 'attempts: 2'
item stories/y1.md 'status: ready' 'kind: code'
run story x1 || true
check "an escalate build's start logs escalate x1, ok (attempt 3)" logged escalate x1 "ok (attempt 3)"
check "and the build itself, story x1 ok" logged story x1 ok
run story y1 || true
check "a code build's start logs no escalate line" bash -c "grep -q \$'\tstory\ty1\tw:me\tok\$' '${LOG}' && ! grep -q \$'\tescalate\ty1\t' '${LOG}'"
run close x1 --drop || true
check "its failed close --drop logs escalated x1, ok (attempts 3, 2 PRs)" logged escalated x1 "ok (attempts 3, 2 PRs)"
appends "reset with no reason fails, naming it" 1 reset x1 "reset: <reason> is missing" reset x1
appends "drop with a blank reason fails, naming it" 1 drop x1 "drop: <reason> is missing" drop x1 " "
appends "reset logs the lead's reason" 1 reset x1 "ok (re-scoped to the parser alone)" reset x1 re-scoped to the parser alone
appends "drop of a story that is not escalated fails, naming it" 1 drop x1 "drop: x1 is not an escalated story" drop x1 why
appends "drop of a missing story fails, naming it" 1 drop nope "drop: no story ${P}/docs/stories/nope.md" drop nope why
outside item stories/z1.md 'status: ready' 'kind: lead' 'attempts: 3' 'escalated_from: code'
outside appends "drop logs the lead's reason" 1 drop z1 "ok (failed on Fable after a reset)" drop z1 "failed on Fable after a reset"
check "drop takes the story off the board" test ! -e "${ROOT}/nogit/docs/stories/z1.md"
# A conductor that answers a builder's Fable consent dialog logs it, with the result as the outcome.
appends "dialog logs the answer" 1 dialog y1 "ok (accepted)" dialog y1 accepted
check "dialog's outcome is exactly ok (accepted), so dash counts it ok" logged dialog y1 "ok (accepted)"
appends "dialog with no result fails, naming it" 1 dialog y1 "dialog: the result must be accepted or dismissed" dialog y1
appends "dialog of a missing story fails, naming it" 1 dialog nope "dialog: no story" dialog nope dismissed

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
