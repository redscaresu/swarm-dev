#!/usr/bin/env bash
# dash_speedometer_test.sh — the speedometer: stories merged per day over 7 days and its two
# lights, and the board line.
# `swarm.sh dash` against a throwaway board, a fake agents.tsv, findings.tsv and events.tsv, a stub
# herdr on PATH printing a fixed agent list, and a stub gh. stty and tput are stubbed to fail, so the
# width comes from COLUMNS (or the default 100), except in the pty tests.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0
# The claude stub goes first on PATH, so no run here reaches the real claude.
STUB_BIN="${ROOT}/stub-bin"; mkdir -p "${STUB_BIN}"; cp "$(dirname "${BASH_SOURCE[0]}")/claude_stub.sh" "${STUB_BIN}/claude"
export PATH="${STUB_BIN}:${PATH}" CLAUDE_STUB_AGENTS="${ROOT}/claude.json"

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}
has() { grep -qF -- "$1" <<< "$2"; }

mkdir -p "${ROOT}/nobin" "${ROOT}/size"
unset COLUMNS LINES
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/size/stty"
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/size/tput"
chmod +x "${ROOT}/size/stty" "${ROOT}/size/tput"
export PATH="${ROOT}/size:${PATH}" CLAUDE_PROJECTS_DIR="${ROOT}/projects" TMPDIR="${ROOT}/tmp"
mkdir -p "${TMPDIR}"
# fresh — drop dash's one-minute cache of gh and cost, so the next run asks again.
fresh() { rm -rf "${TMPDIR}"/swarm-dash-*; }
# Claude Code's sessions: the conductor (sess-1) and s-three's builder (sess-today) are busy, and
# s-one's builder waits on a permission prompt.
printf '[{"sessionId":"sess-1","status":"busy"},{"sessionId":"sess-2","status":"waiting","waitingFor":"input"},{"sessionId":"sess-today","status":"busy"}]' > "${ROOT}/claude.json"

ago() { python3 -c 'import datetime, sys; print((datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(minutes=int(sys.argv[1]))).strftime("%Y-%m-%dT%H:%M:%SZ"))' "$1"; }

# herdr and gh that always fail: no project here has a herdr, and gh is never reached.
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/nobin/herdr"
printf '#!/bin/sh\nexit 1\n' > "${ROOT}/nobin/gh"
chmod +x "${ROOT}/nobin/herdr" "${ROOT}/nobin/gh"

# --- The speedometer, in a project of its own (SPD, lead = session): stories merged per day over 7
# days, the slugs events.tsv says were finished, and two lights.
SPD="${ROOT}/speed"; mkdir -p "${SPD}/.swarm" "${SPD}/.claude/swarm" "${SPD}/docs/stories"
git -C "${SPD}" init -q; touch "${SPD}/docs/stories/README.md"; echo "lead = session" > "${SPD}/.claude/swarm/config"
GSP=(git -C "${SPD}" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false)
sitem() { local path="${SPD}/docs/$1" title; title="$(basename "$1" .md)"; shift; { echo ---; printf '%s\n' "$@"; echo ---; echo; echo "# ${title}"; } > "${path}"; }
# 14 stories finished in the last 7 days (m1 by finish and again by reconcile), one reopened, one
# dropped, and one finished 8 days ago whose file was deleted only yesterday.
for i in $(seq 1 14); do printf '%s\treconcile\tm%s\tw5:p1\tok (finished%s)\n' "$(ago $((i * 600)))" "${i}" "$([ $((i % 2)) = 0 ] && echo ' by its PR')"; done > "${SPD}/.swarm/events.tsv"
printf '%s\tfinish\tm1\tw5:p1\tok\n%s\treconcile\tm-back\tw5:p1\tok (reopened)\n%s\tdrop\tm-drop\tw5:p1\tok\n%s\treconcile\tm-old\tw5:p1\tok (finished)\n' \
  "$(ago 30)" "$(ago 30)" "$(ago 30)" "$(ago $((8 * 1440)))" >> "${SPD}/.swarm/events.tsv"
sitem stories/m-old.md 'status: review'
"${GSP[@]}" add docs && "${GSP[@]}" commit -qm board
GIT_COMMITTER_DATE="$(ago 1440)" "${GSP[@]}" rm -q docs/stories/m-old.md && GIT_COMMITTER_DATE="$(ago 1440)" "${GSP[@]}" commit -qm "clean m-old"
# A held story whose builder was closed paused 3 hours ago, and a story in review: the lead's two items.
sitem stories/q-held.md 'status: ready' 'kind: lead' 'escalated_from: code' 'held_for: paused'
sitem stories/q-rev.md 'status: review' 'prs: https://github.com/o/q/pull/50'
"${GSP[@]}" add docs && "${GSP[@]}" commit -qm "held and review"
printf '%s\tclose:paused\tq-held\tw5:p1\tok\n' "$(ago 180)" >> "${SPD}/.swarm/events.tsv"
# Three identical lines in a row: one recent row, ×3.
for _ in 1 2 3; do printf '%s\ttell:nudge\tq-rev\tw5:p1\tok\n' "$(ago 5)" >> "${SPD}/.swarm/events.tsv"; done
# A fixed finding far longer than recent's column: its text is cut, never its (#PR).
printf '%s\tlong\thttps://github.com/o/q/pull/42\t%s\n' "$(date +%F)" "$(printf 'word %.0s' $(seq 1 40))" > "${SPD}/.swarm/findings.tsv"
spdash() { fresh; (cd "${SPD}" || exit 1; env -u HERDR_ENV COLUMNS=100 PATH="${ROOT}/nobin:${PATH}" bash "${SWARM}" dash 2>&1 || true); }
out="$(spdash)"; top="$(sed -n 2p <<< "${out}")"
check "speedometer: 14 stories finished in 7 days are 2.0 a day; a second finish, a reopen, a drop and one 8 days old do not change it" has "2.0 merged/day over 7 days" "${top}"
check "speedometer: a held story closed 3h ago and a review story light the first light, 2 items, oldest 3h" \
  grep -qE '! 2 waiting on you or the lead, oldest 3h0[01]m' <<< "${top}"
check "speedometer: with no escaped finding the second light is unlit" has "✓ 0 escaped in 7 days" "${top}"
recent="$(sed -n '/^╭─ recent/,/^╰/p' <<< "${out}")"
check "recent: three identical lines in a row are one row, ×3" test "$(grep -c 'tell:nudge q-rev' <<< "${recent}")" -eq 1
check "recent: the collapsed row says ×3" has "tell:nudge q-rev ×3" "${recent}"
check "recent: a findings row cut to width keeps its (#PR)" has "… (#42)" "${recent}"
# A story a close kept 5 hours ago, its file committed just now: it waits from its kept line, not the commit.
sitem stories/q-kept.md 'status: review' 'prs: https://github.com/o/q/pull/51' 'kept: 2026-10-26 close (not reviewed)'
"${GSP[@]}" add docs && "${GSP[@]}" commit -qm "kept"
printf '%s\tkept\tq-kept\tw5:p1\tok (https://github.com/o/q/pull/51; not reviewed)\n%s\tclose\tq-kept\tw5:p1\tok\n' "$(ago 300)" "$(ago 300)" >> "${SPD}/.swarm/events.tsv"
check "speedometer: a kept story waits from its kept line, 3 items, oldest 5h" \
  grep -qE '! 3 waiting on you or the lead, oldest 5h0[01]m' <<< "$(sed -n 2p <<< "$(spdash)")"
# One escaped finding 2 days old lights the second light; one 9 days old does not count.
printf '%s\tmissed\thttps://github.com/o/q/pull/3\tescaped %s\tescaped\tescaped\n' \
  "$(python3 -c 'import datetime; print(datetime.date.today() - datetime.timedelta(days=2))')" two \
  "$(python3 -c 'import datetime; print(datetime.date.today() - datetime.timedelta(days=9))')" nine >> "${SPD}/.swarm/findings.tsv"
check "speedometer: one escaped finding 2 days old lights the second light" has "! 1 escaped in 7 days" "$(sed -n 2p <<< "$(spdash)")"
# An uncommitted board file whose name has a space is named as it is, unquoted.
echo x > "${SPD}/docs/stories/notes 1.md"
check "the board line names a file with a space unquoted" has "board: 1 uncommitted edit in the main checkout: stories/notes 1.md" "$(spdash)"
rm "${SPD}/docs/stories/notes 1.md"
# A rename in the work tree only (Y = R, after git add -N): the new name once, never the old one.
echo n > "${SPD}/docs/stories/n-old.md"; "${GSP[@]}" add docs && "${GSP[@]}" commit -qm n-old
mv "${SPD}/docs/stories/n-old.md" "${SPD}/docs/stories/n-new.md"; "${GSP[@]}" add -N docs/stories/n-new.md
check "the board line names a work-tree rename by its new name alone" has "board: 1 uncommitted edit in the main checkout: stories/n-new.md" "$(spdash)"
"${GSP[@]}" rm -q --cached docs/stories/n-new.md; rm "${SPD}/docs/stories/n-new.md"; "${GSP[@]}" checkout -q -- docs/stories/n-old.md
"${GSP[@]}" rm -q docs/stories/n-old.md && "${GSP[@]}" commit -qm "n-old gone"
# Nothing built, so nothing finished: 0.0.
mv "${SPD}/.swarm/events.tsv" "${SPD}/.swarm/events.tsv.bak"
check "speedometer: with no events.tsv nothing was built, 0.0" has "0.0 merged/day" "$(sed -n 2p <<< "$(spdash)")"
mv "${SPD}/.swarm/events.tsv.bak" "${SPD}/.swarm/events.tsv"


[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
