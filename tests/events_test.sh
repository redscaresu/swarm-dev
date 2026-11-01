#!/usr/bin/env bash
# events_test.sh — .swarm/events.tsv, the audit log: every command that changes state appends one
# well-formed line (reconcile and unblock one per item), failures included, with no message
# contents, and an unwritable .swarm never fails the command. gh and herdr are stubs on PATH.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
LIB="${SWARM%/swarm.sh}/lib"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
P="${ROOT}/proj"; LOG="${P}/.swarm/events.tsv"
trap 'chmod -R u+w "${ROOT}" 2>/dev/null; rm -rf "${ROOT}"' EXIT
# agents.sh's EVENT_SEP and EVENT_OUTCOME_AWK, read by sourcing it, as swarm.sh does.
from_agents() { PROJECT_DIR="${ROOT}/src" bash -c 'source "$1/agents.sh"; printf %s "${!2}"' _ "${LIB}" "$1"; }
SEP="$(from_agents EVENT_SEP)"; EVENT_AWK="$(from_agents EVENT_OUTCOME_AWK)"
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
# lines, each five tab-separated fields: ISO UTC time, command, target, actor, outcome. A pane-closed
# line (close_pane's, one per pane the command closed) is the pane's, not the command's: left out
# here, and checked on its own below.
appends() {
  local name="$1" n="$2" cmd="$3" target="$4" outcome="$5" was new; shift 5
  was="$(lines)"; run "$@" || true
  new="$(tail -n +"$((was + 1))" "${LOG}" 2>/dev/null | awk -F'\t' '$2 != "pane-closed"' || true)"
  check "${name}: ${n} line(s)" test "$(grep -c . <<< "${new}" || true)" -eq "${n}"
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
was_close="$(lines)"
appends "close" 1 close s1 ok close s1
check "close s1, its pane w:1 recorded, also writes one pane-closed line for it" \
  test "$(tail -n +"$((was_close + 1))" "${LOG}" | awk -F'\t' '$2 == "pane-closed" { print $3 "|" $5 }' | no_version)" = "s1|ok ~~ pane=w:1 slug=s1"
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
# --because's value is one word with its spaces, so the target is still <kind> <pr>.
appends "log-finding --declined --because" 1 log-finding:declined "k ${U}/9" ok log-finding --declined nit --because "the builder's reason, in words" --reviewer codex k "${U}/9" t
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
# The prompt's sleep carries this run's pid, so the pgrep below never sees a second copy of this test running beside it (live_logs_test.sh runs one).
printf '#!/bin/sh\ncase "$1 $2" in "agent prompt") exec sleep 37.%s ;; "agent wait") exec sleep 38 ;; esac\nexec "%s" "$@"\n' "$$" "${ROOT}/bin/herdr" > "${ROOT}/slow/herdr"
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
check "a TERM is logged as interrupted" bash -c "tail -n +$((was + 1)) '${LOG}' | grep -qE \$'^[^\t]*\ttell:findings\ts1\tw:me\tinterrupted( ~~ .*)?\$'"
check "a TERM leaves no temp file" test -z "$(ls "${ROOT}/sigtmp")"
sleep 1; check "a TERM leaves nothing of the command running" bash -c "! pgrep -f 'sleep 37[.]$$\$' >/dev/null"
read -r code took <<< "$(term_pid wait s1)"
check "a TERM to the pid stops a long wait at once, with exit 143" test "${code}" -eq 143 -a "${took}" -le 2

# The read-only commands, written out here: READ_ONLY_COMMANDS must be exactly this, so a command
# that changes state (story, say) cannot be declared read-only without this test changing too.
RO_EXPECTED="base cost config dash dataset dropped-lines flow features findings grants review-yield lessons next outcomes policy status where swarms wait wait-pr watch _base _brief _name _conductor _board-rel _role _pane _target _trusted _mtime _step-up _step _review-red-scan _tell-queue-check _fix-main"
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
  args=(); [[ "${arm}" == tidy ]] && args=(--yes); [[ "${arm}" == intervene ]] && args=(lead-hand other x)
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
check "a nudging wait appends only nudge lines" test "$(grep -cvE $'^[^\t]*\tnudge\ts1\tw:me\tok( ~~ .*)?$' <<< "${new}")" -eq 0

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
logged() { # <command> <target> <outcome> — events.tsv has this line, with an ISO UTC time and the actor;
  # the outcome compared without its key=value tail (EVENT_OUTCOME_AWK's outcome())
  # shellcheck disable=SC2016 # an awk program
  awk -F'\t' -v c="$1" -v t="$2" -v o="$3" "${EVENT_AWK}"'$1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ \
    && NF == 5 && $2 == c && $3 == t && $4 == "w:me" && outcome($5) == o { f = 1 } END { exit !f }' "${LOG}"
}
item stories/x1.md 'status: ready' 'kind: code' 'attempts: 2'
item stories/y1.md 'status: ready' 'kind: code'
run story x1 || true
check "an escalate build's start logs escalate x1, ok (attempt 3)" logged escalate x1 "ok (attempt 3)"
check "and the build itself, story x1 ok" logged story x1 ok
run story y1 || true
check "a code build's start logs no escalate line" bash -c "grep -qE \$'\tstory\ty1\tw:me\tok( ~~ .*)?\$' '${LOG}' && ! grep -q \$'\tescalate\ty1\t' '${LOG}'"
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

# --- The outcome column's key=value tail: append_event writes it after EVENT_SEP, and events_outcome.py
# (outcome, fields) and EVENT_OUTCOME_AWK's outcome() read it. Each case is a row and its exact reading.
P="${ROOT}/tail"; LOG="${P}/.swarm/events.tsv"; ERR="${ROOT}/tail.err"
ev() { PROJECT_DIR="${P}" HERDR_PANE_ID=w:me bash -c 'source "$1/agents.sh"; shift; append_event "$@"' _ "${LIB}" "$@" 2>> "${ERR}"; }
same() { # <got> <want>
  [[ "$1" == "$2" ]] || { diff <(printf '%s\n' "$2") <(printf '%s\n' "$1") || true; return 1; }
}
check "EVENT_SEP is events_outcome.SEP" same "${SEP}" \
  "$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import events_outcome; print(events_outcome.SEP, end="")' "${LIB}")"
ev x t 'ok (round 2)' round=2 verdict=pass
check "append_event with fields writes one row of 5 fields" awk -F'\t' 'NF != 5 { bad = 1 } END { exit bad || NR != 1 }' "${LOG}"
check "its column 5 is the outcome, EVENT_SEP, then the fields" same "$(cut -f5 "${LOG}")" "ok (round 2)${SEP}round=2 verdict=pass"
ev x t "die: no story${SEP}"
check "an outcome ending in EVENT_SEP is written without it" same "$(sed -n 2p "${LOG}" | cut -f5)" "die: no story"
ev x t "a${SEP}b" k=v
ev x t "a${SEP}b"
ev x t "a ~~ ~~ b${SEP}${SEP}c" n=1 m=two
ev x t ok Round=2 'v=a b' good=1 empty=
check "an invalid pair is left out, the line still written with the valid ones" same "$(sed -n 6p "${LOG}" | cut -f5)" "ok${SEP}good=1"
ev x t ok Bad=1
check "a call whose every pair is invalid writes the outcome alone" same "$(sed -n 7p "${LOG}" | cut -f5)" ok
ev x t 'die: foo ~~' round=2
check "an outcome ending in EVENT_SEP short of its last space loses it, so the tail starts at its own" \
  same "$(sed -n 8p "${LOG}" | cut -f5)" "die: foo${SEP}round=2"
ev x t 'die: foo ~~'
check "each invalid pair is named on stderr" same "$(cut -d: -f2 "${ERR}")" "$(printf ' left out %s\n' Round=2 'v=a b' empty= Bad=1)"
# Rows written before the tail: untailed, an outcome holding =, herdr's JSON.
{ printf '2026-10-01T00:00:00Z\tx\tt\tw:me\t%s\n' 'ok (round 2)' 'failed: key=value x=1' '{"result":{"agent":{"agent_status":"working","note":"a=b c"}}}'
  printf '2026-10-01T00:00:00Z\tx\tt\tw:me\t%s\n' "base-merged abc from def${SEP}round=3 why=x=y"; } >> "${LOG}"
read_py() { python3 -c 'import json, sys
sys.path.insert(0, sys.argv[1])
from events_outcome import fields, outcome
for line in open(sys.argv[2]):
    row = line.rstrip("\n").split("\t")
    print(outcome(row) + "\t" + json.dumps(fields(row), sort_keys=True))' "${LIB}" "${LOG}"; }
check "outcome() and fields() read each row exactly" same "$(read_py)" "$(cat <<'WANT'
ok (round 2)	{"round": "2", "verdict": "pass"}
die: no story	{}
a b	{"k": "v"}
a b	{}
a b  c	{"m": "two", "n": "1"}
ok	{"good": "1"}
ok	{}
die: foo	{"round": "2"}
die: foo	{}
ok (round 2)	{}
failed: key=value x=1	{}
{"result":{"agent":{"agent_status":"working","note":"a=b c"}}}	{}
base-merged abc from def	{"round": "3", "why": "x=y"}
WANT
)"
# shellcheck disable=SC2016 # an awk program
check "the awk outcome() returns the Python outcome() for each row" same \
  "$(awk -F'\t' "${EVENT_AWK}"'{ print outcome($5) }' "${LOG}")" "$(read_py | cut -f1)"

# --- version cases: every append_event line ends its tail in version=, the plugin's version from
# ${SWARM_HOME}/.claude-plugin/plugin.json read once per process, after the caller's fields; a plugin.json
# that cannot be read gives no version= and the command still succeeds.
HOME_SRC="${SWARM%/bin/swarm.sh}"
V="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "${HOME_SRC}/.claude-plugin/plugin.json")"
VH="${ROOT}/vhome"; mkdir -p "${VH}/.claude-plugin"; echo '{"version": "1.2.3"}' > "${VH}/.claude-plugin/plugin.json"
P="${ROOT}/version"; LOG="${P}/.swarm/events.tsv"
# evv <args...> — append_event in one process with SWARM_HOME at VH, with swarm.sh's own plugin_version;
# between the two appends plugin.json changes, which the second must not read.
evv() { PROJECT_DIR="${P}" SWARM_HOME="${VH}" HERDR_PANE_ID=w:me bash -c 'eval "$(grep "^plugin_version()" "$1")"; source "$2/agents.sh"; shift 2
  append_event "$@"; echo "{\"version\": \"9.9.9\"}" > "${SWARM_HOME}/.claude-plugin/plugin.json"; append_event "$@"' _ "${SWARM}" "${LIB}" "$@" 2>> "${ERR}"; }
evv x t 'ok (round 2)' round=2
check "version cases: append_event with a field writes that field, then version=, after the outcome; version= is read once per process" \
  same "$(cut -f5 "${LOG}")" "$(printf 'ok (round 2)%sround=2 version=1.2.3\n' "${SEP}" "${SEP}")"
check "version cases: outcome() is unchanged" same "$(read_py | cut -f1 | sort -u)/$(awk -F'\t' "${EVENT_AWK}"'{ print outcome($5) }' "${LOG}" | sort -u)" "ok (round 2)/ok (round 2)"
mkdir -p "${P}/.claude/swarm"; : > "${P}/.claude/swarm/config"; git init -q "${P}"
# intervene <swarm.sh> — log an intervention with that swarm.sh, printing its exit status and its line's outcome column
intervene() { local rc=0; (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me bash "$1" intervene lead-hand other "a line" >/dev/null 2>&1) || rc=$?; echo "${rc} $(tail -1 "${LOG}" | cut -f5)"; }
check "version cases: a logged command's line has version= equal to plugin.json's" \
  same "$(intervene "${SWARM}")" "0 lead-hand: a line${SEP}cause=other version=${V}"
# A copy of the plugin whose plugin.json is a directory, which no read can parse.
mkdir -p "${ROOT}/badhome/.claude-plugin/plugin.json"; cp -R "${HOME_SRC}/bin" "${ROOT}/badhome/bin"
check "version cases: with plugin.json unreadable the line has no version= and the command still succeeds" \
  same "$(intervene "${ROOT}/badhome/bin/swarm.sh")" "0 lead-hand: a line${SEP}cause=other"

# --- decline-only cases: a review --head that passes a findings round whose builder pushed nothing (the
# head is still the one .swarm/reviews/<slug>.head says the round started on) writes decline-only <slug>
# ok (round N), N the started round, then review-finished, then its own ok line, each with round=N and
# verdict=decline-only; any other --head pass writes review-finished and its ok line with verdict=pass and
# round= review_round's. A project of its own, whose gh prints the head H for every PR (review_heads) and
# lists no other open PR.
P="${ROOT}/decline"; LOG="${P}/.swarm/events.tsv"; DB="${ROOT}/declinebin"
H=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; OTHER=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
mkdir -p "${P}/.claude/swarm" "${P}/.swarm/reviews" "${DB}"; : > "${P}/.claude/swarm/config"; git init -q "${P}"
# shellcheck disable=SC2016 # the stub's own shell expands $1 and $2
printf '%s\n' '#!/bin/sh' 'case "$1 $2" in' "  'pr list') echo '[]' ;;" "  'pr view') echo '{\"headRefOid\":\"${H}\"}' ;;" '  *) exit 1 ;;' 'esac' > "${DB}/gh"
chmod +x "${DB}/gh"
run() { (cd "${P}" && HERDR_ENV=1 HERDR_PANE_ID=w:me PATH="${DB}:${ROOT}/bin:${PATH}" bash "${SWARM}" "$@" >/dev/null 2>&1); }
# decline <slug> <head file: a sha, or dir for one that cannot be read> <command>... — a fresh ready story
# whose events.tsv lines are those commands, each ok, and whose head file is as given
decline() {
  local slug="$1" head="$2" c; shift 2
  item "stories/${slug}.md" 'status: ready' 'kind: code'
  for c in "$@"; do printf '2026-10-01T00:00:00Z\t%s\t%s\tw:1\tok\n' "${c}" "${slug}" >> "${LOG}"; done
  if [[ "${head}" == dir ]]; then mkdir -p "${P}/.swarm/reviews/${slug}.head"; else echo "${head}" > "${P}/.swarm/reviews/${slug}.head"; fi
}
# reviewed <slug> <review args...> — run review <slug> <args>, and print the command, target and outcome
# of each line it appended
reviewed() {
  local slug="$1" was; shift
  was="$(lines)"; run review "${slug}" "$@" || true
  tail -n +"$((was + 1))" "${LOG}" | cut -f2,3,5
}
# ln <command> <slug> <outcome> <round> <verdict> — one line as reviewed prints it, version= the plugin's
ln() { printf '%s\t%s\t%s%sround=%s verdict=%s version=%s\n' "$1" "$2" "$3" "${SEP}" "$4" "$5" "${V}"; }
# passed <slug> <round> — a --head pass's two lines
passed() { ln review-finished "$1" ok "$2" pass; ln review "$1" "ok (${U}/7)" "$2" pass; }
# declined <slug> — a decline-only end of round 1's three lines
declined() { ln decline-only "$1" 'ok (round 1)' 1 decline-only; ln review-finished "$1" ok 1 decline-only; ln review "$1" "ok (${U}/7)" 1 decline-only; }
decline d1 "${H}" review-agent tell:findings
check "decline-only cases: a pass on the head the findings round started on writes decline-only, review-finished, then the review, each verdict=decline-only round=1" \
  same "$(reviewed d1 --head "${H}" "${U}/7")" "$(declined d1)"
decline d2 "${OTHER}" review-agent tell:findings
check "decline-only cases: none when the head file holds another sha" \
  same "$(reviewed d2 --head "${H}" "${U}/7")" "$(passed d2 2)"
decline d3 "${H}" review-agent tell:findings review-agent:next
check "decline-only cases: none when a review-agent:next came after the tell" \
  same "$(reviewed d3 --head "${H}" "${U}/7")" "$(passed d3 2)"
decline d4 "${H}" tell:findings review-agent
check "decline-only cases: none when no findings tell came after the review start" \
  same "$(reviewed d4 --head "${H}" "${U}/7")" "$(passed d4 2)"
decline d5 "${H}" review-agent tell:findings
check "decline-only cases: none for a review without --head, nor a review-finished line" \
  same "$(reviewed d5 "${U}/7")" "$(ln review d5 "ok (${U}/7)" 2 pass)"
# A head file that cannot be read fails decline_only_round: the review's own line is still written.
decline d6 dir review-agent tell:findings
check "decline-only cases: a failed decline_only_round still writes the review's ok line" \
  same "$(reviewed d6 --head "${H}" "${U}/7")" "$(passed d6 2)"
# The round's findings file names the head the findings were on: a wording recheck that passed moved
# the head file past it, so its head is no decline-only; one at the same head still is.
decline d7 "${H}" review-agent tell:findings
printf 'head: %s\n\n## Findings\n\n- doc.md:3 says foo\n' "${OTHER}" > "${P}/.swarm/reviews/d7.round.md"
check "decline-only cases: none when the round's findings file names another head (a wording recheck passed)" \
  same "$(reviewed d7 --head "${H}" "${U}/7")" "$(passed d7 2)"
decline d8 "${H}" review-agent tell:findings
printf 'head: %s\n\n## Findings\n\n- doc.md:3 says foo\n' "${H}" > "${P}/.swarm/reviews/d8.round.md"
check "decline-only cases: written when the round's findings file names the same head" \
  same "$(reviewed d8 --head "${H}" "${U}/7")" "$(declined d8)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
