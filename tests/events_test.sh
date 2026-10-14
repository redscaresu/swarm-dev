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

item() { # <path under docs> <front-matter line>...
  local path="${P}/docs/$1" title; shift
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
item stories/s2.md 'status: blocked' 'blocked_by: [gone]'
item stories/s3.md 'status: blocked' 'blocked_by: [gone]'
item stories/m1.md 'status: review' "prs: ${U}/1"
item stories/c1.md 'status: review' "prs: ${U}/2"
printf 'SECRET-CONTENT-123 in the findings\n' > "${P}/findings.md"

appends "review" 1 review s1 ok review s1 "${U}/9"
appends "a failed review" 1 review s1 "review: not a PR URL" review s1 "https://x"$'\t'"y"
# A tell's kind goes with its command (tell:<kind>), so its target stays the slug, which the stall rule reads.
appends "tell" 1 tell:findings s1 ok tell s1 findings findings.md
appends "a tell with no kind" 1 tell s1 "tell: the kind must be findings, nudge or resume" tell s1
# Only a real kind goes with the command: an unknown one, or the old form's file path, logs plain tell.
appends "a tell with an unknown kind" 1 tell s1 "tell: the kind must be findings, nudge or resume" tell s1 bogus findings.md
appends "the old form, tell <slug> <file>" 1 tell s1 "tell: the kind must be findings, nudge or resume" tell s1 /tmp/f.md
check "tell never logs the file's contents" bash -c "! grep -q SECRET-CONTENT '${LOG}'"
appends "close" 1 close s1 ok close s1
appends "tidy --yes" 1 tidy - ok tidy --yes
appends "tidy without --yes logs nothing" 0 - - - tidy
appends "unblock, one per story" 2 unblock '*' ok unblock
appends "reconcile, one per item" 2 reconcile '*' ok reconcile
check "reconcile says which it finished and which it reopened" bash -c "grep -q \$'reconcile\tm1\tw:me\tok (finished)' '${LOG}' && grep -q \$'reconcile\tc1\tw:me\tok (reopened)' '${LOG}'"
appends "finish" 1 finish s1 ok finish s1
appends "log-finding" 1 log-finding "vacuous-test ${U}/9" ok log-finding vacuous-test "${U}/9" "a line"
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
RO_EXPECTED="base cost config dash decisions findings lessons next outcomes policy status wait watch _base _label _name _pane _target _trusted"
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
  args=(); [[ "${arm}" == tidy ]] && args=(--yes)
  n=0; [[ "${ro}" == *" ${arm} "* ]] || n=1
  before="$(LOG="${Q}/.swarm/events.tsv" lines)"
  (cd "${Q}" || exit 1; env -u HERDR_ENV PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" "${arm}" ${args[@]+"${args[@]}"} </dev/null >/dev/null 2>&1) || true
  after="$(LOG="${Q}/.swarm/events.tsv" lines)"
  what="read-only, not logged"; [[ ${n} == 0 ]] || what="logged"
  check "arm ${arm}: ${what}" test "$((after - before))" -eq "${n}"
done
appends "next logs nothing" 0 - - - next
appends "status logs nothing" 0 - - - status

# An unwritable .swarm (and log): the command still succeeds, and the log is unchanged.
item stories/s4.md 'status: ready'
was="$(lines)"; chmod a-w "${LOG}" "${P}/.swarm"
check "an unwritable .swarm never fails the command" run finish s4
chmod u+w "${P}/.swarm" "${LOG}"
check "an unwritable .swarm: the command did its work" test ! -f "${P}/docs/stories/s4.md"
check "an unwritable .swarm: nothing logged" test "$(lines)" -eq "${was}"

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

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
