#!/usr/bin/env bash
# conductor_close_test.sh — swarm.sh close conduct-<epic> refuses, closing nothing and saying why, while
# the conductor is working (under a name herdr holds cut too) or its state cannot be read, while its
# epic's Finish PR (board/finish-<epic>) is open, or when gh cannot list that PR; an idle conductor with
# no Finish PR open closes as before. A swarm.sh merge --board of
# that Finish PR closes the conductor once the merge has exited, the conductor reads idle and the lead
# has tried collect's close (for a long epic, under its full name); with no such close tried, or with
# herdr's agent list unparseable, it is left open, with a line saying why.
# herdr, gh and claude are stubs on PATH: herdr lists the agents in <dir>/h/agents ("<name> <pane>
# <status> [tab]" lines, tab t1 unless given: e's; t2 is the long epic's) and logs each call to
# <dir>/h/calls, and a pane or tab close drops its agents; the first
# half's gh answers pr list from ${ROOT}/finish.json, and fails while ${ROOT}/ghfail exists. The second
# half runs on merge_fixture.sh's project, whose gh answers pr list --head board/finish-e from
# ${FX}/prlist.finish-e.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
TESTS="$(dirname "${SWARM}")/../tests"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
# stop_waiter <project> [name] — kill <name>'s (conduct-e's) close_when_idle waiter by its pid file, so none outlives the test.
stop_waiter() { local pid; pid="$(cat "$1/.swarm/closing/${2:-conduct-e}.pid" 2>/dev/null)" || return 0; [[ ! "${pid}" =~ ^[0-9]+$ ]] || kill "${pid}" 2>/dev/null || true; }
trap 'stop_waiter "${ROOT}/m/proj"; stop_waiter "${ROOT}/m/proj" conduct-a-very-long-epic-slug-fo; rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
# The waiter looks every 0.2 s here, not every 5.
export SWARM_CLOSE_IDLE_POLL=0.2

# herdr_stub <dir> — the herdr stub in <dir>/bin, its files in <dir>/h.
herdr_stub() {
  mkdir -p "$1/bin" "$1/h"; : > "$1/h/calls"; : > "$1/h/agents"
  printf '#!/bin/sh\nH="%s"\n' "$1/h" > "$1/bin/herdr"
  cat >> "$1/bin/herdr" <<'STUB'
echo "$*" >> "$H/calls"
case "$1 $2" in
  "--version ") echo "herdr 0.9.5" ;;
  "agent list") [ ! -e "$H/garbage" ] || { echo '{"result":{}}'; exit 0; }
                awk 'BEGIN { printf "{\"result\":{\"agents\":[" }
                     { printf "%s{\"name\":\"%s\",\"pane_id\":\"%s\",\"agent_status\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2, $3 }
                     END { print "]}}" }' "$H/agents" ;;
  "pane list") awk 'BEGIN { printf "{\"result\":{\"panes\":[" }
                    { printf "%s{\"pane_id\":\"%s\",\"tab_id\":\"%s\"}", (NR > 1 ? "," : ""), $2, (NF > 3 ? $4 : "t1") }
                    END { print "]}}" }' "$H/agents" ;;
  "tab list") echo '{"result":{"tabs":[{"tab_id":"t1","label":"e"},{"tab_id":"t2","label":"a-very-long-epic-slug-for-cut-names"}]}}' ;;
  "workspace list") echo '{"result":{"workspaces":[]}}' ;;
  "tab close") awk -v t="$3" '(NF > 3 ? $4 : "t1") != t' "$H/agents" > "$H/agents.tmp" && mv "$H/agents.tmp" "$H/agents" ;;
  "pane close") awk -v p="$3" '$2 != p' "$H/agents" > "$H/agents.tmp" && mv "$H/agents.tmp" "$H/agents" ;;
esac
STUB
  chmod +x "$1/bin/herdr"
  cp "${TESTS}/claude_stub.sh" "$1/bin/claude"; chmod +x "$1/bin/claude"
}
# lay <dir> <project> <status> — conduct-e alone in pane w:c with herdr status <status>, recorded in
# e's tab record as start_agent records a conductor, and herdr's call log cleared.
lay() { echo "conduct-e w:c $3" > "$1/h/agents"; mkdir -p "$2/.swarm/state"; echo "w:c conductor" > "$2/.swarm/state/e"; : > "$1/h/calls"; }
# closes <dir> — the herdr calls that closed a pane or a tab, one per line.
closes() { grep -e '^pane close' -e '^tab close' "$1/h/calls" 2>/dev/null || true; }

fails=0
is() { if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi; }
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo no; fi; }

# --- The close guard, on a project of its own whose board is in its repo, with an origin.
herdr_stub "${ROOT}"
P="${ROOT}/proj"; mkdir -p "${P}/docs/stories" "${P}/docs/epics"
git -C "${P}" init -q; git -C "${P}" remote add origin https://github.com/o/r.git
printf '#!/bin/sh\nH="%s"\n' "${ROOT}" > "${ROOT}/bin/gh"
cat >> "${ROOT}/bin/gh" <<'STUB'
echo "$*" >> "$H/gh.log"
[ ! -e "$H/ghfail" ] || { echo "gh: HTTP 502" >&2; exit 1; }
case "$1 $2" in
  "pr list") cat "$H/finish.json" ;;
  *) echo "stub: unexpected gh $*" >&2; exit 1 ;;
esac
STUB
chmod +x "${ROOT}/bin/gh"
FIN=https://github.com/o/r/pull/9
# finish <state> — conduct-e's Finish PR, as gh pr list gives it, in <state>; none for no PR.
finish() {
  if [[ "$1" == none ]]; then echo '[]' > "${ROOT}/finish.json"
  else printf '[{"url":"%s","state":"%s","headRefName":"board/finish-e"}]\n' "${FIN}" "$1" > "${ROOT}/finish.json"; fi
}
# close — swarm.sh close conduct-e from the lead's pane; sets rc and out.
close() { rc=0; out="$(cd "${P}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_PANE_ID=w:lead PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" close conduct-e 2>&1)" || rc=$?; }

finish none; lay "${ROOT}" "${P}" working; close
is "a working conduct-e: the close fails, closes no pane and says it is working" "1||yes" \
  "${rc}|$(closes "${ROOT}")|$(has "close: conduct-e is working, so nothing was closed" "${out}")"

finish OPEN; lay "${ROOT}" "${P}" idle; close
is "an idle conduct-e whose Finish PR is open: the close fails, closes nothing and names the PR" "1||yes|yes" \
  "${rc}|$(closes "${ROOT}")|$(has "close: conduct-e has its Finish PR ${FIN} open" "${out}")|$(has "--head board/finish-e" "$(cat "${ROOT}/gh.log")")"
finish MERGED; close
is "once that Finish PR has merged, the close closes conduct-e's tab" "0|tab close t1|" \
  "${rc}|$(closes "${ROOT}")|$(cat "${P}/.swarm/state/e" 2>/dev/null)"

finish OPEN; touch "${ROOT}/ghfail"; lay "${ROOT}" "${P}" idle; close; rm -f "${ROOT}/ghfail"
is "with gh failing to list the Finish PR, the close fails, closes nothing and says the PR could not be read" "1||yes" \
  "${rc}|$(closes "${ROOT}")|$(has "close: conduct-e could not have its Finish PR read" "${out}")"

# conduct-e with a Claude session recorded: a list Claude Code fails to give leaves its state unknown,
# and the close fails closed; a list that no longer has the session reads herdr's status, here working.
mkdir -p "${P}/.swarm"; printf '2026-11-01T00:00:00Z\tconduct\tconduct-e\tclaude\tm\te\tsid-1\n' > "${P}/.swarm/agents.tsv"
finish none; lay "${ROOT}" "${P}" idle; export CLAUDE_STUB_AGENTS="${ROOT}/no-such-list"; close
is "conduct-e's session state unreadable: the close fails, closes nothing and says its state could not be read" "1||yes" \
  "${rc}|$(closes "${ROOT}")|$(has "close: conduct-e could not have its state read" "${out}")"
echo '[]' > "${ROOT}/sessions.json"; export CLAUDE_STUB_AGENTS="${ROOT}/sessions.json"; lay "${ROOT}" "${P}" working; close
is "conduct-e's session gone from Claude Code's list, herdr working: the close fails and says it is working" "1||yes" \
  "${rc}|$(closes "${ROOT}")|$(has "close: conduct-e is working" "${out}")"
unset CLAUDE_STUB_AGENTS; rm -f "${P}/.swarm/agents.tsv" "${ROOT}/sessions.json"

# An epic slug long enough that herdr holds its conductor's name cut at 32 characters, closed by the
# full name, as close takes it: still read as working.
LONG=a-very-long-epic-slug-for-cut-names; CUT="conduct-${LONG}"; CUT="${CUT:0:32}"
finish none; lay "${ROOT}" "${P}" idle; echo "${CUT} w:c working" > "${ROOT}/h/agents"
mkdir -p "${P}/.swarm/briefs"; echo brief > "${P}/.swarm/briefs/conduct-${LONG}.md"; echo "w:c conductor" > "${P}/.swarm/state/${LONG}"
rc=0; out="$(cd "${P}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_PANE_ID=w:lead PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" close "conduct-${LONG}" 2>&1)" || rc=$?
is "a working conductor whose name herdr holds cut, closed by its full name: the close fails, closes nothing and says it is working" "1||yes" \
  "${rc}|$(closes "${ROOT}")|$(has "close: conduct-${LONG} is working, so nothing was closed" "${out}")"
rm -rf "${P}/.swarm/briefs" "${P}/.swarm/state/${LONG}"

finish none; lay "${ROOT}" "${P}" idle; export CLAUDE_STUB_LOG="${ROOT}/claude.log"; : > "${CLAUDE_STUB_LOG}"; close; unset CLAUDE_STUB_LOG
is "an idle conduct-e with no Finish PR closes, as before, reading Claude Code's agent list once for the guard and the close" "0|tab close t1||1" \
  "${rc}|$(closes "${ROOT}")|$(cat "${P}/.swarm/state/e" 2>/dev/null)|$(grep -c '^agents --json$' "${ROOT}/claude.log")"

# --- merge --board of conduct-e's Finish PR, on merge_fixture.sh's project, in a subshell, since its
# helpers share these names. It runs from conduct-e's own pane while conduct-e works: the merge closes
# nothing while it runs; once it has exited and conduct-e reads idle, with its report written and the
# lead's collect close tried (refused, as the Finish PR was open), its waiter closes conduct-e. With no
# collect tried, the waiter leaves it open past its limit and says why. In the background, so set -e
# holds inside it; it exits with its count of failed checks.
merge_fails=0
( set -e
  ROOT="${ROOT}/m"; mkdir -p "${ROOT}"
  # shellcheck source=tests/merge_fixture.sh
  . "${TESTS}/merge_fixture.sh"
  herdr_stub "${ROOT}"
  # working <status> — conduct-e's herdr status.
  working() { perl -pi -e "s/^conduct-e w:c \\S+\$/conduct-e w:c $1/" "${ROOT}/h/agents"; }
  # waiter — wait up to 30 s for conduct-e's waiter to end (it removes its pid file): ended, or stopped.
  waiter() {
    local i; for ((i = 0; i < 300; i++)); do [[ -e "${P}/.swarm/closing/conduct-e.pid" ]] || { echo ended; return 0; }; sleep 0.1; done
    stop_waiter "${P}"; echo "stopped: still running after 30 s"
  }
  # polled — wait up to 30 s for two herdr agent lists since the call log was cleared: the waiter's
  # first poll since then has read conduct-e and decided. yes, or no.
  polled() {
    local i; for ((i = 0; i < 300; i++)); do [[ "$(grep -cx 'agent list' "${ROOT}/h/calls" 2>/dev/null)" -lt 2 ]] || { echo yes; return 0; }; sleep 0.1; done
    echo no
  }
  # board_finish — fresh, conduct-e working in w:c with its report written, and URL its epic's Finish PR (open).
  board_finish() {
    fresh; rm -f "${S}" "${P}"/.swarm/state/*; lay "${ROOT}" "${P}" working
    echo board/finish-e > "${FX}/headref"; echo '{"files":[{"filename":"docs/stories/s.md"}]}' > "${FX}/commit.${M}"
    printf '[{"url":"%s","state":"OPEN","headRefName":"board/finish-e"}]\n' "${URL}" > "${FX}/prlist.finish-e"
    mkdir -p "${P}/.swarm"; echo "merged: everything" > "${P}/.swarm/conduct-e.report.md"
  }
  collect() { rc=0; (cd "${P}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_PANE_ID=w:lead PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" close conduct-e > "${ROOT}/out" 2>&1) || rc=$?; }

  board_finish; working idle; collect; working working
  is "the lead's collect close while the Finish PR is open is refused" "1|" "${rc}|$(closes "${ROOT}")"
  : > "${ROOT}/h/calls"; merge HERDR_ENV=1 HERDR_PANE_ID=w:c --board "${URL}"
  ran="$(closes "${ROOT}")"; : > "${ROOT}/h/calls"; seen="$(polled)"
  is "merge --board of conduct-e's Finish PR from its pane, conduct-e working: it merges, says conduct-e closes later, and closes nothing, during the merge or after" \
    "0|yes|yes|||conduct-e w:c working" \
    "${rc}|$(grep -q '^merged: ' "${ROOT}/out" && echo yes)|${seen}|${ran}|$(closes "${ROOT}")|$(cat "${ROOT}/h/agents")"
  working idle
  is "once the merge has exited and conduct-e reads idle, its waiter closes it and logs it" \
    "ended|tab close t1|close-when-idle conduct-e closed (pane w:c)" \
    "$(waiter)|$(closes "${ROOT}")|$(events | grep '^close-when-idle ' || true)"

  board_finish; working idle; : > "${ROOT}/h/calls"
  merge HERDR_ENV=1 HERDR_PANE_ID=w:c SWARM_CLOSE_IDLE_SECONDS=1 --board "${URL}"
  is "with no collect close tried, conduct-e idle is left open past the waiter's limit, and a line says its report was not collected" \
    "0|ended||conduct-e w:c idle|close-when-idle conduct-e left open: its report was still not collected 1s after the merge that landed its Finish PR exited; collect it, and its close closes it" \
    "${rc}|$(waiter)|$(closes "${ROOT}")|$(cat "${ROOT}/h/agents")|$(events | grep '^close-when-idle ' || true)"

  # herdr's agent list answers but does not parse as one, from just after the merge (which needs the list
  # to find conduct-e's pane): conduct-e, collected and in truth idle, reads as unknown, never as gone,
  # so it is left open, with a line naming its state.
  board_finish; working idle; collect; working working; : > "${ROOT}/h/calls"
  merge HERDR_ENV=1 HERDR_PANE_ID=w:lead SWARM_CLOSE_IDLE_SECONDS=5 --board "${URL}"; touch "${ROOT}/h/garbage"; working idle
  is "with herdr's agent list unparseable, the waiter closes nothing and says conduct-e's state is unknown" \
    "0|ended||close-when-idle conduct-e left open: it was still unknown 5s after the merge that landed its Finish PR exited; close it with swarm.sh close conduct-e once it is done" \
    "${rc}|$(waiter)|$(closes "${ROOT}")|$(events | grep '^close-when-idle ' || true)"
  rm -f "${ROOT}/h/garbage"

  # A long epic: herdr holds its conductor cut at 32 characters, and the lead's collect close names it
  # in full, as close takes it. Its Finish PR's merge still closes it once it is idle.
  L=a-very-long-epic-slug-for-cut-names; C="conduct-${L}"; C="${C:0:32}"
  fresh; rm -f "${S}" "${P}"/.swarm/state/*; echo "${C} w:c idle t2" > "${ROOT}/h/agents"; echo "w:c conductor" > "${P}/.swarm/state/${L}"
  mkdir -p "${P}/.swarm/briefs"; echo brief > "${P}/.swarm/briefs/conduct-${L}.md"; echo "merged: everything" > "${P}/.swarm/conduct-${L}.report.md"
  echo "board/finish-${L}" > "${FX}/headref"; echo '{"files":[{"filename":"docs/stories/s.md"}]}' > "${FX}/commit.${M}"
  printf '[{"url":"%s","state":"OPEN","headRefName":"board/finish-%s"}]\n' "${URL}" "${L}" > "${FX}/prlist.finish-${L}"
  rc=0; (cd "${P}" && env -u SWARM_PROJECT HERDR_ENV=1 HERDR_PANE_ID=w:lead PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" close "conduct-${L}" > "${ROOT}/out" 2>&1) || rc=$?
  first="${rc}"; : > "${ROOT}/h/calls"; merge HERDR_ENV=1 HERDR_PANE_ID=w:lead --board "${URL}"
  long_waiter() {
    local i; for ((i = 0; i < 300; i++)); do [[ -e "${P}/.swarm/closing/${C}.pid" ]] || { echo ended; return 0; }; sleep 0.1; done
    stop_waiter "${P}" "${C}"; echo "stopped: still running after 30 s"
  }
  is "a long epic's conductor, its collect close refused under its full name: once its Finish PR's merge has exited, its waiter closes it" \
    "1|0|ended|tab close t2|close-when-idle ${C} closed (pane w:c)" \
    "${first}|${rc}|$(long_waiter)|$(closes "${ROOT}")|$(events | grep '^close-when-idle ' || true)"
  exit "${fails}"
) &
wait $! || merge_fails=$?
# shellcheck disable=SC2031 # the subshell counts its own fails, and exits with them
fails=$((fails + merge_fails))

echo
if [[ ${fails} -eq 0 ]]; then echo "all conductor close tests passed"; else echo "${fails} conductor close test(s) failed"; exit 1; fi
