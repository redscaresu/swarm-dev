#!/usr/bin/env bash
# events_test.sh — .swarm/events.tsv, the audit log: every command that changes state appends one
# well-formed line (reconcile and unblock one per item), failures included, with no message
# contents, and an unwritable .swarm never fails the command. gh and herdr are stubs on PATH.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
ROOT="$(cd "$(mktemp -d)" && pwd -P)"
P="${ROOT}/proj"; LOG="${P}/.swarm/events.tsv"
trap 'chmod -R u+w "${ROOT}" 2>/dev/null; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
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
chmod +x "${ROOT}/bin/gh" "${ROOT}/bin/herdr"
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
appends "tell" 1 tell s1 ok tell s1 findings.md
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
appends "a failed agent" 1 agent n1 "no prompt file" agent t n1 "${P}" code "${P}/missing.md"
appends "next logs nothing" 0 - - - next
appends "status logs nothing" 0 - - - status

# An unwritable .swarm (and log): the command still succeeds, and the log is unchanged.
item stories/s4.md 'status: ready'
was="$(lines)"; chmod a-w "${LOG}" "${P}/.swarm"
check "an unwritable .swarm never fails the command" run finish s4
chmod u+w "${P}/.swarm" "${LOG}"
check "an unwritable .swarm: the command did its work" test ! -f "${P}/docs/stories/s4.md"
check "an unwritable .swarm: nothing logged" test "$(lines)" -eq "${was}"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
