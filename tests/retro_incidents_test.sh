#!/usr/bin/env bash
# retro_incidents_test.sh — `swarm.sh retro`'s incidents section over a fixture project tagged v0.2.0
# on 2026-02-10. One lead-hand and one user-caught line logged with `swarm.sh intervene` print in
# full with their day, kind and cause, after a hand-written lead-hand line dated inside the window but
# appended after them (oldest first); a lead-hand and a login line dated before the window do not
# print. Then the other kinds: one wait-timeout row with count 1, two login lines as one row with
# their first and last day, a login line with a cause= field as a row of its own, and a stalled
# step-up as its own row, but not a findings-3 step-up or a reap line. A line's day is its local day:
# one logged at 20:00Z on the 9th prints as the 10th at UTC+9, and not at all at UTC. A project whose
# events.tsv holds no incident says so for each part, and one with no events.tsv says the file does
# not exist. A run makes no gh call.
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
check() { # <name> <got> <want>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

# gh records each call and fails; herdr fails. git reads no user config, so no signer is asked.
STUB_BIN="${ROOT}/bin"; GH_CALLS="${ROOT}/gh-calls"; mkdir -p "${STUB_BIN}" "${ROOT}/tmp" "${ROOT}/memory"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexit 1\n' "${GH_CALLS}" > "${STUB_BIN}/gh"
printf '#!/bin/sh\nexit 1\n' > "${STUB_BIN}/herdr"
chmod +x "${STUB_BIN}/gh" "${STUB_BIN}/herdr"
: > "${ROOT}/gitconfig"; : > "${GH_CALLS}"
export PATH="${STUB_BIN}:${PATH}" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TMPDIR="${ROOT}/tmp" TZ=UTC \
  GIT_CONFIG_GLOBAL="${ROOT}/gitconfig" GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS

# project <dir> — a swarm project whose v0.2.0 tag is committed on 2026-02-10.
project() {
  git init -q -b main "$1"
  mkdir -p "$1/.swarm" "$1/docs/stories"; touch "$1/docs/stories/README.md"
  git -C "$1" add -A
  GIT_COMMITTER_DATE="2026-02-10T10:00:00Z" git -C "$1" commit -q -m one
  git -C "$1" tag v0.2.0
}
sw() { local p="$1"; shift; (cd "${p}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${REPO}/bin/swarm.sh" "$@"); }
# incidents <dir> — the incidents section of retro since v0.2.0, from its heading to the next one.
incidents() { sw "$1" retro --since v0.2.0 --memory "${ROOT}/memory" | awk '/^## /{on = ($0 == "## incidents")} on'; }

P="${ROOT}/p"; project "${P}"
sw "${P}" intervene user-caught flaky-test "a test failed twice before anyone looked" >/dev/null
sw "${P}" intervene lead-hand stuck-builder "typed into a stalled conductor's pane: it had no output" >/dev/null
# Each intervene line's own day, as logged: the two may fall either side of midnight.
day1="$(sed -n 1p "${P}/.swarm/events.tsv" | cut -c1-10)"; day2="$(sed -n 2p "${P}/.swarm/events.tsv" | cut -c1-10)"
S=" ~~ "   # events_outcome.py's SEP
printf '%s\n' \
  $'2026-02-09T12:00:00Z\tincident\t-\t-\tlead-hand: before the window'"${S}"'cause=other' \
  $'2026-02-09T13:00:00Z\tincident\tconduct-e\t-\tlogin: expired before the window' \
  $'2026-02-11T08:00:00Z\tincident\t-\t-\tlead-hand: merged a stuck PR by hand'"${S}"'cause=review-rounds' \
  $'2026-02-12T09:00:00Z\tincident\tconduct-e\t-\twait-timeout: conduct-e for 60m'"${S}"'slug=e' \
  $'2026-02-12T10:00:00Z\tincident\tconduct-e\t-\tlogin: expired' \
  $'2026-02-14T10:00:00Z\tincident\tconduct-e\t-\tlogin: expired again' \
  $'2026-02-13T11:00:00Z\tincident\tconduct-f\t-\tlogin: expired'"${S}"'slug=f cause=sso' \
  $'2026-02-13T09:00:00Z\tescalate\ta\t-\tok (stalled: sonnet -> opus)' \
  $'2026-02-13T09:30:00Z\tescalate\tb\t-\tok (findings-3: sonnet -> opus)' \
  $'2026-02-13T10:00:00Z\treap\ttests/slow_test.sh\t-\tTIMEOUT after 600s' >> "${P}/.swarm/events.tsv"

out="$(incidents "${P}")"
check "every lead-hand and user-caught line since the tag prints in full with its day, kind and cause, oldest first" \
  "$(sed -n '2,/^$/p' <<< "${out}")" "day	kind	cause	text
2026-02-11	lead-hand	review-rounds	merged a stuck PR by hand
${day1}	user-caught	flaky-test	a test failed twice before anyone looked
${day2}	lead-hand	stuck-builder	typed into a stalled conductor's pane: it had no output"
check "the other kinds print one row per kind and cause, with its count and first and last day" \
  "$(sed -n '/^kind	/,$p' <<< "${out}")" "kind	cause	incidents	first	last
login	-	2	2026-02-12	2026-02-14
login	sso	1	2026-02-13	2026-02-13
stalled step-up	-	1	2026-02-13	2026-02-13
wait-timeout	-	1	2026-02-12	2026-02-12"

Q="${ROOT}/q"; project "${Q}"
printf '%s\n' $'2026-02-13T10:00:00Z\treap\ttests/slow_test.sh\t-\tTIMEOUT after 600s' > "${Q}/.swarm/events.tsv"
check "an events.tsv with no incident says so for each part" "$(incidents "${Q}")" "## incidents
no lead-hand or user-caught lines since 2026-02-10

no other incidents since 2026-02-10"

# JST-9 is UTC+9 as a POSIX zone, so it needs no tz database.
T="${ROOT}/t"; project "${T}"
printf '%s\n' $'2026-02-09T20:00:00Z\tincident\t-\t-\tuser-caught: late on the 9th by UTC'"${S}"'cause=other' > "${T}/.swarm/events.tsv"
check "a line's day is its local day: 20:00Z on the 9th is in the window at UTC+9 and before it at UTC" \
  "$(TZ=JST-9 incidents "${T}" | sed -n 2,3p) | $(incidents "${T}" | sed -n 2p)" "day	kind	cause	text
2026-02-10	user-caught	other	late on the 9th by UTC | no lead-hand or user-caught lines since 2026-02-10"

R="${ROOT}/r"; project "${R}"
check "a project with no events.tsv says the file does not exist" "$(incidents "${R}")" "## incidents
no incidents: ${R}/.swarm/events.tsv does not exist"

check "no retro run above made a gh call" "$(cat "${GH_CALLS}")" ""

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
