#!/usr/bin/env bash
# fallback_reviewer_test.sh — codex-review on a codex usage limit: it always logs a codex-limit
# incident; with fallback_reviewer set it starts fallback-<story> (role review-fallback, on that
# model, with no file tools), waits what is left of codex's time for its findings file and prints
# it in codex's place, then closes the agent; with the key empty no agent starts and the output is
# codex's own, as before. A fallback that cannot start, writes nothing in time or is interrupted is
# closed, and codex-review says codex was skipped. Also the builder brief's codex rule, which names the
# PR body's "reviewed by fallback" line. codex, herdr and claude are stubs on PATH: herdr's agent
# writes its findings file as its brief arrives, then goes idle, unless ${ROOT}/silent exists.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
# No .claude.json here, so require_trusted lets the agent start. A wait checks the session often.
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/projects" SWARM_STALL_POLL_MS=200 \
  SWARM_CONDUCTOR_POLL=1 CLAUDE_STUB_AGENTS="${ROOT}/claude.json"
BIN="${ROOT}/stub-bin"; mkdir -p "${BIN}" "${ROOT}/done"; echo '[]' > "${ROOT}/claude.json"; : > "${ROOT}/agents"
cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${BIN}/claude"
fails=0

check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }
logged() { if grep -q -- "$1" "${ROOT}/herdr.log" 2>/dev/null; then echo yes; else echo no; fi; }

# codex's own line, curly apostrophe and all.
LIMIT_MSG="ERROR: You’ve hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro) or try again at 7:53 AM."
codex_says() { printf '#!/bin/sh\n'; printf 'echo "%s" >&2\n' "${@:2}"; printf 'exit %s\n' "$1"; } # <exit> <line>...
codex_says 1 "${LIMIT_MSG}" > "${BIN}/codex"
# herdr: logs every call. Tab t:<n> holds pane w:<n>. agent start records "<name> <pane> <session>"
# (failing with startfail, taking 20 s with slowstart); a tab create with panefail opens none; agent prompt writes the findings file the brief names and marks the agent
# done, unless silent (it stays busy) or idle (it goes idle with no file; with late, it writes the
# file 3 s later, as a background call of its own would), and with promptfail leaves the agent idle, so the brief is never taken up; a
# pane or tab close drops its agent. agent list and wait report it idle once done.
cat > "${BIN}/herdr" <<EOF
#!/bin/sh
H="${ROOT}"
EOF
cat >> "${BIN}/herdr" <<'EOF'
echo "$*" >> "$H/herdr.log"
drop() { awk -v p="$1" '$2 != p' "$H/agents" > "$H/agents.tmp" && mv "$H/agents.tmp" "$H/agents"; }
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;   # start_agent's require_herdr_version
  "tab create")   [ -e "$H/panefail" ] && exit 1
                  n=$(($(cat "$H/n" 2>/dev/null || echo 0) + 1)); echo "$n" > "$H/n"
                  echo "t:$n $(echo "$*" | sed 's/.*--label \([^ ]*\).*/\1/')" >> "$H/tabs"
                  echo "{\"result\":{\"root_pane\":{\"pane_id\":\"w:$n\"}}}" ;;
  "tab list")     awk 'BEGIN { printf "{\"result\":{\"tabs\":[" }
                    { printf "%s{\"tab_id\":\"%s\",\"label\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2 }
                    END { print "]}}" }' "$H/tabs" ;;
  "tab close")    drop "w:${3#t:}" ;;
  "pane close")   drop "$3" ;;
  "agent start")  [ -e "$H/startfail" ] && { echo '{"error":{"code":"start_failed"}}' >&2; exit 1; }
                  [ -e "$H/slowstart" ] && sleep 20
                  rm -f "$H/done/$3"   # a new agent is busy until its brief is done
                  echo "$3 $(echo "$*" | sed 's/.*--pane \([^ ]*\).*/\1/') $(echo "$*" | sed -n 's/.*--session-id \([^ ]*\).*/\1/p')" >> "$H/agents"
                  "$H/sessions" ;;
  "agent prompt") [ -e "$H/promptfail" ] && { echo '{"result":{"agent":{"agent_status":"idle"}}}'; exit 0; }
                  [ -e "$H/idle" ] && touch "$H/done/$(awk -v p="$3" '$2 == p { print $1 }' "$H/agents")" && "$H/sessions"
                  if [ -e "$H/late" ]; then
                    f=$(echo "$4" | grep -o '/[^ ]*/\.swarm/reviews/fallback/[a-z0-9-]*\.md' | head -1)
                    (sleep 3; printf '%s\n' '- [P2] LATE FINDING — y.sh:1' > "$f") > /dev/null 2>&1 &
                  fi
                  if [ ! -e "$H/silent" ] && [ ! -e "$H/idle" ]; then
                    f=$(echo "$4" | grep -o '/[^ ]*/\.swarm/reviews/fallback/[a-z0-9-]*\.md' | head -1)
                    printf '%s\n' '- [P1] STUB FINDING — x.sh:3' '  drops the error' > "$f"
                    touch "$H/done/$(awk -v p="$3" '$2 == p { print $1 }' "$H/agents")"; "$H/sessions"
                  fi
                  echo '{"result":{"agent":{"agent_status":"working"}}}' ;;
  "agent wait")   echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
  "agent list")   awk -v d="$H/done" 'BEGIN { printf "{\"result\":{\"agents\":[" }
                    { s = system("test -e " d "/" $1) == 0 ? "idle" : "working"
                      printf "%s{\"name\":\"%s\",\"agent_status\":\"%s\",\"pane_id\":\"%s\"}", (NR > 1 ? "," : ""), $1, s, $2 }
                    END { print "]}}" }' "$H/agents" ;;
esac
EOF
# sessions: Claude Code's list, one entry per agent started, busy until done/<name> exists.
cat > "${ROOT}/sessions" <<EOF
#!/bin/sh
awk -v d="${ROOT}/done" 'BEGIN { printf "[" }
  { s = system("test -e " d "/" \$1) == 0 ? "idle" : "busy"
    printf "%s{\"sessionId\":\"%s\",\"status\":\"%s\"}", (NR > 1 ? "," : ""), \$3, s }
  END { print "]" }' "${ROOT}/agents" > "${ROOT}/claude.json"
EOF
chmod +x "${BIN}/codex" "${BIN}/herdr" "${ROOT}/sessions"

# A git project with stories s1 and two whose fallback names, cut at 32 characters, are one.
p="${ROOT}/proj"; LONG=abcdefghijklmnopqrstuvw
mkdir -p "${p}/.claude/swarm" "${p}/docs/stories"
git -c init.defaultBranch=main init -q "${p}"
for s in s1 "${LONG}-one" "${LONG}-two"; do
  printf '%s\n' --- "status: ready" "kind: code" "touches: [x.sh]" --- "" "# ${s}" "" "**Done when:**" "- it holds" > "${p}/docs/stories/${s}.md"
done
# review [config line] — codex-review main for $STORY (s1) with that config, codex's time $SECS
# (60 s), a fallback's least time $MIN (1 s; "default" for the shipped one, which an empty override
# keeps) and HERDR_ENV=1 unless
# NOHERDR is set, in the background: sets out, rc and took. A run past 30 s is KILLed, failing the
# checks instead of hanging the test.
review() {
  local t0=${SECONDS} pid i herdr=(HERDR_ENV=1) min=(SWARM_FALLBACK_MIN_SECONDS="${MIN:-1}")
  [[ -z "${NOHERDR:-}" ]] || herdr=(-u HERDR_ENV)
  [[ "${MIN:-}" != default ]] || min=(SWARM_FALLBACK_MIN_SECONDS=)
  printf '%s\n' "$@" > "${p}/.claude/swarm/config"; : > "${ROOT}/herdr.log"
  (cd "${p}" && exec env -u SWARM_PROJECT "${herdr[@]}" "${min[@]}" HERDR_WORKSPACE_ID=w \
    SWARM_STORY="${STORY:-s1}" SWARM_CODEX_SECONDS="${SECS:-60}" PATH="${BIN}:${PATH}" bash "${SWARM}" codex-review main > "${ROOT}/out" 2>&1) &
  pid=$!
  for ((i = 0; i < 150; i++)); do kill -0 "${pid}" 2>/dev/null || break; sleep 0.2; done
  kill -0 "${pid}" 2>/dev/null && kill -KILL "${pid}"
  rc=0; wait "${pid}" || rc=$?
  took=$((SECONDS - t0)); out="$(cat "${ROOT}/out")"
}
incidents() { awk -F'\t' '$2 == "incident" { print $3 "|" $5 }' "${p}/.swarm/events.tsv"; }
closed() { if grep -qE '^(pane|tab) close' "${ROOT}/herdr.log"; then echo yes; else echo no; fi; }
live() { awk '{ print $1 }' "${ROOT}/agents" | tr '\n' ' '; }

# --- Key empty: no agent, codex's output and exit as before, and the incident.
review
check "with fallback_reviewer empty, codex-review exits as codex did, with codex's output alone" "1|${LIMIT_MSG}" "${rc}|${out}"
check "with fallback_reviewer empty, no agent starts" "no" "$(logged '^agent start')"
check "with fallback_reviewer empty, the codex-limit incident is logged" "codex-s1|codex-limit: usage limit" "$(incidents)"

# --- fallback_reviewer = sonnet: the fallback agent starts on sonnet, its findings are printed, and
# it is closed.
review "fallback_reviewer = sonnet"
check "with fallback_reviewer = sonnet, codex-review exits 0" "0" "${rc}"
check "the fallback agent starts as fallback-s1 on sonnet" "yes" "$(logged '^agent start fallback-s1 .*--model sonnet ')"
check "the fallback agent has a tab of its own, fallback-s1" "yes" "$(logged '^tab create .*--label fallback-s1 ')"
check "the fallback agent has no Edit, Write or NotebookEdit tool, and cannot commit or push" "yes" \
  "$(logged '^agent start fallback-s1 .*--disallowedTools Bash(gh pr merge:\*) Edit Write NotebookEdit Bash(git commit:\*) Bash(git push:\*) --settings')"
check "agents.tsv records it with role review-fallback" "review-fallback" \
  "$(awk -F'\t' '$3 == "fallback-s1" { print $2 }' "${p}/.swarm/agents.tsv")"
check "its brief holds codex's story prompt" "yes" "$(has "Its Done when:" "$(cat "${p}/.swarm/briefs/fallback/s1.md")")"
check "its findings go to .swarm/reviews/fallback/s1.md" "yes" "$([[ -f "${p}/.swarm/reviews/fallback/s1.md" ]] && echo yes || echo no)"
check "the stub's findings appear in codex-review's stdout" "yes" "$(has "- [P1] STUB FINDING — x.sh:3" "${out}")"
check "stdout names the fallback for the PR body" "yes" "$(has "reviewed by fallback sonnet: codex usage limit" "${out}")"
check "the fallback agent is closed once its findings are read" "yes|" "$(closed)|$(live)"
check "with fallback_reviewer set, the codex-limit incident is logged too" "codex-s1|codex-limit: usage limit" "$(incidents | tail -1)"
check "one incident per run" "2" "$(incidents | wc -l | tr -d ' ')"
check "the incident's target is codex-<slug>, never the builder's own name" "codex-s1" "$(incidents | cut -d'|' -f1 | sort -u)"
review "fallback_reviewer = sonnet"
check "the next usage limit for the story starts its fallback again" "0|yes" "${rc}|$(logged '^agent start fallback-s1 ')"

# --- A fallback still working when codex's time runs out is stopped then, and closed. Its 10 s leave
# its start room to finish first.
touch "${ROOT}/silent"
SECS=10 review "fallback_reviewer = sonnet"
check "a silent fallback ends within codex's time, exiting as codex did and saying codex was skipped" "1|yes|yes" \
  "${rc}|$([[ ${took} -le 16 ]] && echo yes || echo "no, ${took}s")|$(has "codex skipped: usage limit (fallback-s1 wrote no findings in time" "${out}")"
check "a fallback that timed out is closed" "yes|" "$(closed)|$(live)"

# --- A fallback is waited on for its file, not its idle: one idle while a background call of its own
# still runs writes it later, and its findings come through.
touch "${ROOT}/idle" "${ROOT}/late"
review "fallback_reviewer = sonnet"
check "a fallback that goes idle and writes its findings later is waited for, and they come through" "0|yes|yes|" \
  "${rc}|$(has "- [P2] LATE FINDING — y.sh:1" "${out}")|$(closed)|$(live)"
rm "${ROOT}/late"
# One idle that never writes it ends at codex's time, closed.
SECS=8 review "fallback_reviewer = sonnet"
check "a fallback idle with no findings is waited on until codex's time, then closed, and codex was skipped" "1|yes|yes|yes|" \
  "${rc}|$([[ ${took} -ge 5 && ${took} -le 14 ]] && echo yes || echo "no, ${took}s")|$(has "codex skipped: usage limit (fallback-s1 wrote no findings in time" "${out}")|$(closed)|$(live)"
rm "${ROOT}/idle"

# --- An interrupt while the fallback reviews closes it at once.
printf '%s\n' "fallback_reviewer = sonnet" > "${p}/.claude/swarm/config"; : > "${ROOT}/herdr.log"
(cd "${p}" && exec env -u SWARM_PROJECT HERDR_ENV=1 HERDR_WORKSPACE_ID=w SWARM_STORY=s1 SWARM_CODEX_SECONDS=60 SWARM_FALLBACK_MIN_SECONDS=1 \
  PATH="${BIN}:${PATH}" bash "${SWARM}" codex-review main > "${ROOT}/out" 2>&1) &
pid=$!
for ((i = 0; i < 100; i++)); do [[ "$(logged '^agent prompt')" == yes ]] && break; sleep 0.1; done
sleep 1; t0=${SECONDS}
{ # stderr off, so the test prints no "Terminated" notice for the job
  kill -TERM "${pid}"
  for ((i = 0; i < 100; i++)); do kill -0 "${pid}" || break; sleep 0.1; done
  kill -0 "${pid}" && kill -KILL "${pid}"
  wait "${pid}" || true
} 2>/dev/null
check "an interrupted codex-review closes its fallback within 5 s" "yes|yes|" \
  "$([[ $((SECONDS - t0)) -le 5 ]] && echo yes || echo "no, $((SECONDS - t0))s")|$(closed)|$(live)"
check "events.tsv's codex-review line says it was interrupted" "interrupted" \
  "$(awk -F'\t' '$2 == "codex-review" { o = $5 } END { print o }' "${p}/.swarm/events.tsv")"
rm "${ROOT}/silent"

# --- A fallback that cannot start: codex was skipped, exiting as codex did, and no pane is left.
touch "${ROOT}/startfail"
review "fallback_reviewer = sonnet"
check "a fallback whose start fails says codex was skipped and why, exiting as codex did" "1|yes" \
  "${rc}|$(has "codex skipped: usage limit (fallback did not start: fallback-s1: herdr could not start the agent" "${out}")"
rm "${ROOT}/startfail"
touch "${ROOT}/promptfail"
review "fallback_reviewer = sonnet"
check "a fallback whose brief is never taken up says codex was skipped, and its pane is closed" "1|yes|yes|" \
  "${rc}|$(has "fallback did not start: fallback-s1: the brief was not taken up" "${out}")|$(closed)|$(live)"
rm "${ROOT}/promptfail"
touch "${ROOT}/panefail"
review "fallback_reviewer = sonnet"
check "a fallback whose pane does not open says why, exiting as codex did, and no agent starts" "1|yes|no" \
  "${rc}|$(has "codex skipped: usage limit (fallback did not start: herdr could not open a pane in tab fallback-s1)" "${out}")|$(logged '^agent start')"
rm "${ROOT}/panefail"
# A start that outlasts codex's time is stopped at it, and its pane closed. Its 6 s let the start
# open its pane before it stalls in agent start.
touch "${ROOT}/slowstart"
SECS=6 review "fallback_reviewer = sonnet"
check "a fallback start that outlasts codex's time is stopped within it, its pane closed, and codex was skipped" "1|yes|yes|yes|" \
  "${rc}|$([[ ${took} -le 11 ]] && echo yes || echo "no, ${took}s")|$(has "codex skipped: usage limit (fallback did not start: its start ran out of codex's time)" "${out}")|$(closed)|$(live)"
rm "${ROOT}/slowstart"
rm -rf "${p}/.swarm/briefs/fallback"; : > "${p}/.swarm/briefs/fallback"
review "fallback_reviewer = sonnet"
check "a fallback whose brief cannot be written says why, exiting as codex did, and no pane opens" "1|yes|no" \
  "${rc}|$(has "codex skipped: usage limit (fallback did not start: could not write its brief ${p}/.swarm/briefs/fallback/s1.md" "${out}")|$(logged '^tab create')"
rm "${p}/.swarm/briefs/fallback"
# Under FALLBACK_MIN_SECONDS (2 minutes) of codex's time left, no fallback is started.
MIN=default review "fallback_reviewer = sonnet"
check "with under 2 minutes of codex's time left, no fallback starts, and codex was skipped" "1|yes|no" \
  "${rc}|$(has "codex skipped: usage limit (no time left for a fallback)" "${out}")|$(logged '^tab create')"
# What codex used counts against it: one that hits its limit 2 s into 4 leaves under the 3 s a
# fallback needs.
{ printf '#!/bin/sh\nsleep 2\n'; codex_says 1 "${LIMIT_MSG}" | tail -n +2; } > "${BIN}/codex"
SECS=4 MIN=3 review "fallback_reviewer = sonnet"
check "codex's own time counts against a fallback's: 2 s used of 4 leaves under 3, so none starts" "1|yes|no" \
  "${rc}|$(has "codex skipped: usage limit (no time left for a fallback)" "${out}")|$(logged '^tab create')"
codex_says 1 "${LIMIT_MSG}" > "${BIN}/codex"
NOHERDR=1 review "fallback_reviewer = sonnet"
check "outside herdr the fallback does not start, and codex was skipped" "1|yes|no" \
  "${rc}|$(has "codex skipped: usage limit (fallback did not start: not in a herdr pane" "${out}")|$(logged '^agent start')"

# --- Two stories whose fallback names are cut to one: the second is refused while the first holds
# the name, and the first's findings are kept.
mkdir -p "${p}/.swarm/state" "${p}/.swarm/reviews/fallback"
echo "fallback-${LONG} w:99 sess-one" >> "${ROOT}/agents"; echo "w:99 fallback-${LONG}-one" > "${p}/.swarm/state/fallback"
echo "the first's findings" > "${p}/.swarm/reviews/fallback/${LONG}-one.md"
STORY="${LONG}-two" review "fallback_reviewer = sonnet"
check "a fallback whose cut name another story's fallback holds is refused, and codex was skipped" "1|yes|no" \
  "${rc}|$(has "fallback did not start: fallback-${LONG} is held by fallback-${LONG}-one" "${out}")|$(logged '^agent start')"
# Once the name is free, the second's findings go to a file of its own, beside the first's.
: > "${ROOT}/agents"; rm "${p}/.swarm/state/fallback"
STORY="${LONG}-two" review "fallback_reviewer = sonnet"
check "two stories whose names are cut to one keep their findings apart" "0|the first's findings|yes" \
  "${rc}|$(cat "${p}/.swarm/reviews/fallback/${LONG}-one.md")|$(has "STUB FINDING" "$(cat "${p}/.swarm/reviews/fallback/${LONG}-two.md" 2>&1)")"

# --- A fallback of the story's own that is still reviewing (another run's) is refused before any file
# is touched, and left running.
rm -f "${ROOT}/done/fallback-s1"; echo "fallback-s1 w:98 sess-busy" >> "${ROOT}/agents"; "${ROOT}/sessions"; echo "w:98 fallback-s1" > "${p}/.swarm/state/fallback"
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' 2026-10-18T00:00:00Z review-fallback fallback-s1 claude sonnet high sess-busy >> "${p}/.swarm/agents.tsv"
echo "the running review's findings" > "${p}/.swarm/reviews/fallback/s1.md"
review "fallback_reviewer = sonnet"
check "a fallback still reviewing is refused and kept, its findings file too, and codex was skipped" "1|yes|no|fallback-s1 |the running review's findings" \
  "${rc}|$(has "fallback did not start: fallback-s1: an agent with this name is still working" "${out}")|$(closed)|$(live)|$(cat "${p}/.swarm/reviews/fallback/s1.md")"
: > "${ROOT}/agents"; rm "${p}/.swarm/state/fallback"

# --- Closing a fallback closes its own tab alone, never another story's fallback tab, whose
# fallback is still reviewing.
echo "fallback-other w:77 sess-other" >> "${ROOT}/agents"; echo "t:77 fallback-other" >> "${ROOT}/tabs"
echo "w:77 fallback-other" > "${p}/.swarm/state/fallback-other"
review "fallback_reviewer = sonnet"
check "closing a fallback leaves another story's fallback tab and the fallback there running" "0|yes|no|fallback-other |yes" \
  "${rc}|$(logged '^tab close')|$(logged '^tab close t:77')|$(live)|$([[ -f "${p}/.swarm/state/fallback-other" ]] && echo yes || echo no)"
: > "${ROOT}/agents"; rm "${p}/.swarm/state/fallback-other"

# --- A codex that fails without its own limit message (a transcript that quotes one does not count)
# logs no incident and starts no fallback.
codex_says 1 "reviewing a diff about the usage limit" "+ERROR: You've hit your usage limit." "ERROR: stream disconnected" > "${BIN}/codex"
n="$(incidents | wc -l | tr -d ' ')"
review "fallback_reviewer = sonnet"
check "another failure exits as codex did, with no incident and no agent" "1|${n}|no" \
  "${rc}|$(incidents | wc -l | tr -d ' ')|$(logged '^agent start')"

# --- Its findings are logged with --reviewer fallback.
check "log-finding --reviewer fallback is accepted and recorded" "0|fallback" \
  "$(cd "${p}" && env -u SWARM_PROJECT -u HERDR_ENV bash "${SWARM}" log-finding --reviewer fallback drops-error https://github.com/o/r/pull/1 "x.sh drops the error" >/dev/null 2>&1; echo "$?")|$(cut -f6 "${p}/.swarm/findings.tsv" 2>/dev/null | tail -1)"

# --- The builder brief's codex rule names the PR body's line.
brief="$(cd "${p}" && env -u SWARM_PROJECT -u HERDR_ENV PATH="${BIN}:${PATH}" bash "${SWARM}" _brief s1 2>&1)"
check "the built brief's codex rule names 'reviewed by fallback' for the PR body" "yes" \
  "$(has 'the PR says "reviewed by fallback <model>: codex usage limit"' "${brief}")"
check "the built brief's codex rule says to wait for codex-review to exit and act on what it prints last" "yes" \
  "$(has 'Wait for codex-review to exit, and act on what it prints last' "${brief}")"

if [[ ${fails} -gt 0 ]]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
