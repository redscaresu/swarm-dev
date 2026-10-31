#!/usr/bin/env bash
# intervene_test.sh — `swarm.sh intervene <kind> <cause> "<one line>"`: an unknown kind or cause or an
# empty line fails and logs nothing, a valid one adds one events.tsv incident line with its cause= field,
# and the old form `intervene <kind> "<one line>"` logs cause=none with a warning. Then flow's incidents section and
# dash's interventions light agree on the 7-day count over a fixture events.tsv, and commands/swarm.md
# tells the lead to log both kinds.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

# herdr, gh, stty and tput that fail, and the claude stub, so dash reads only the fixture.
STUB_BIN="${ROOT}/bin"; mkdir -p "${STUB_BIN}" "${ROOT}/tmp"
cp "${REPO}/tests/claude_stub.sh" "${STUB_BIN}/claude"
for c in herdr gh stty tput; do printf '#!/bin/sh\nexit 1\n' > "${STUB_BIN}/${c}"; chmod +x "${STUB_BIN}/${c}"; done
echo '[]' > "${ROOT}/claude.json"
export PATH="${STUB_BIN}:${PATH}" CLAUDE_STUB_AGENTS="${ROOT}/claude.json" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TMPDIR="${ROOT}/tmp" TZ=UTC
unset COLUMNS LINES

P="${ROOT}/p"; mkdir -p "${P}/.swarm" "${P}/docs/stories"; git -C "${P}" init -q; touch "${P}/docs/stories/README.md"
EV="${P}/.swarm/events.tsv"
sw() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${REPO}/bin/swarm.sh" "$@"); }
lines() { if [[ -f "${EV}" ]]; then wc -l < "${EV}" | tr -d ' '; else echo 0; fi; }
# The kinds, read from swarm.sh's INTERVENE_KINDS, so this test counts what intervene and dash do.
KINDS="$(sed -n 's/^INTERVENE_KINDS="\(.*\)"$/\1/p' "${REPO}/bin/swarm.sh")"
check "swarm.sh names the two kinds" "${KINDS}" "lead-hand user-caught"
CAUSES="$(sed -n 's/^INTERVENE_CAUSES="\(.*\)"$/\1/p' "${REPO}/bin/swarm.sh")"
check "swarm.sh names the causes" "$(wc -w <<< "${CAUSES}" | tr -d ' ')" 20
# outcome() and fields() of events.tsv's last line, read by bin/lib/events_outcome.py.
last_line() { python3 -c 'import csv, sys; sys.path.insert(0, sys.argv[1]); import events_outcome as e; row = list(csv.reader(open(sys.argv[2]), delimiter="\t"))[-1]; print(e.outcome(row)); print(" ".join("%s=%s" % kv for kv in sorted(e.fields(row).items())))' "${REPO}/bin/lib" "${EV}"; }

check "with no intervention dash shows no interventions light" "$(COLUMNS=200 sw dash 2>&1 | grep -c intervention)" 0
rc=0; sw intervene lead-typo flaky-test "typed into a pane" >/dev/null 2>&1 || rc=$?
check "intervene with an unknown kind fails" "${rc}" 1
check "intervene with an unknown kind logs nothing" "$(lines)" 0
rc=0; out="$(sw intervene lead-hand flaky-tests "a test failed twice" 2>&1)" || rc=$?
check "intervene with an unknown cause fails and logs nothing" "${rc} $(lines)" "1 0"
check "its error lists every cause" "$(grep -cF -- "${CAUSES}" <<< "${out}")" 1
rc=0; sw intervene user-caught other "  " >/dev/null 2>&1 || rc=$?
check "intervene with an empty line fails and logs nothing" "${rc} $(lines)" "1 0"
rc=0; sw intervene user-caught flaky-test >/dev/null 2>&1 || rc=$?
check "intervene with a cause and no line fails and logs nothing" "${rc} $(lines)" "1 0"
sw intervene lead-hand flaky-test "typed into a stalled conductor's pane" >/dev/null
check "a valid intervene adds one events.tsv line" "$(lines)" 1
check "the line is an incident, target -" "$(cut -f2,3 "${EV}")" $'incident\t-'
check "its outcome() is <kind>: <line> and its fields() cause=<cause>" "$(last_line)" \
  "lead-hand: typed into a stalled conductor's pane"$'\n'"cause=flaky-test"
# The old form, until hooks/user-caught-reminder.sh names the new one: logged, with cause=none, and a
# warning that lists the causes.
rc=0; out="$(sw intervene user-caught "held stories found by asking" 2>&1 >/dev/null)" || rc=$?
check "the old two-argument form still logs one line" "${rc} $(lines)" "0 2"
check "its outcome() is <kind>: <line> and its fields() cause=none" "$(last_line)" \
  "user-caught: held stories found by asking"$'\n'"cause=none"
check "its warning lists every cause" "$(grep -c 'warning' <<< "${out}") $(grep -cF -- "${CAUSES}" <<< "${out}")" "1 1"
# An unwritable log: intervene fails, says so, and does not say logged:.
chmod a-w "${EV}" "${P}/.swarm"
rc=0; out="$(sw intervene user-caught other "found by asking" 2>&1)" || rc=$?
chmod u+w "${P}/.swarm" "${EV}"
check "intervene fails when it cannot write events.tsv, and logs nothing" "${rc} $(lines)" "1 2"
check "it says nothing was logged" "$(grep -c 'nothing was logged' <<< "${out}") $(grep -c '^logged:' <<< "${out}")" "1 0"

# The fixture: on top of those two, interventions 1, 3 and 6 days ago (two kinds), one 8 days ago that
# the 7 days leave out, and other incidents that are not interventions. One pinned now (dash's
# SWARM_DASH_NOW) dates them and flow's --since, so a run across midnight counts the same days.
NOW="$(date +%s)"
ago() { python3 -c 'import datetime, sys; print((datetime.datetime.fromtimestamp(int(sys.argv[1]), datetime.timezone.utc) - datetime.timedelta(days=int(sys.argv[2]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "${NOW}" "$1"; }
ev() { printf '%s\tincident\t-\tw:1\t%s\n' "$(ago "$1")" "$2" >> "${EV}"; }
ev 1 "user-caught: held stories found by asking"
ev 3 "user-caught: slow CI found by asking"
ev 6 "lead-hand: merged by hand"
ev 8 "lead-hand: too old"
ev 2 "wait-timeout: busy"
ev 2 "login: Login expired"
since="$(python3 -c 'import datetime, sys; print(datetime.date.fromtimestamp(int(sys.argv[1])) - datetime.timedelta(days=6))' "${NOW}")"
flow="$(sw flow --since "${since}" | sed -n '/^## incidents$/,/^$/p' | awk -F'\t' -v kinds=" ${KINDS} " 'index(kinds, " " $2 " ") { n += $3 } END { print n + 0 }' || true)"
dash="$(COLUMNS=200 SWARM_DASH_NOW="${NOW}" sw dash 2>&1 | sed -n 2p | grep -oE '[0-9]+ interventions? in 7 days' | cut -d' ' -f1 || true)"
check "flow counts 5 interventions in the last 7 days" "${flow}" 5
check "dash shows the same 7-day count as flow" "${dash}" "${flow}"
# Where it does not fit beside the speedometer (80 columns) it takes the next line; a cut frame drops
# the sparkline's line before it (80x18), and it goes too once the frame is shorter (80x17).
dsh() { SWARM_DASH_NOW="${NOW}" sw dash 2>&1; }
check "at 80 columns the lit light is the line under the speedometer" "$(DASH_W=80 dsh | sed -n 3p)" "! 5 interventions in 7 days"
out="$(DASH_KEYS=1 DASH_W=80 DASH_H=18 dsh)"
check "at 80x18 the sparkline's line gives way before the light's" "$(grep -c '14 days' <<< "${out}") $(grep -c 'interventions in 7 days' <<< "${out}")" "0 1"
out="$(DASH_KEYS=1 DASH_W=80 DASH_H=17 dsh)"
check "at 80x17 the light's line gives way too, and needs you still shows" "$(grep -c 'interventions in 7 days' <<< "${out}") $(grep -c 'nothing needs you' <<< "${out}") $(wc -l <<< "${out}" | tr -d ' ')" "0 1 17"

# commands/swarm.md tells the lead to log each kind with intervene, in the form with a cause.
for kind in ${KINDS}; do
  check "commands/swarm.md names ${kind} with a cause" "$(grep -c "swarm.sh intervene ${kind} <cause> \"" "${REPO}/commands/swarm.md")" 1
done
# and lists every cause it can pick from.
missing=""; for c in ${CAUSES}; do grep -qF -- "\`${c}\`" "${REPO}/commands/swarm.md" || missing+=" ${c}"; done
check "commands/swarm.md lists every cause" "${missing}" ""

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
