#!/usr/bin/env bash
# dash_defects_test.sh — the three wrong numbers seen on 2026-10-17, on the two-project fixture
# (tests/fixtures/dash/two_projects.sh): each frame's working-agents count matches `swarm.sh status`
# (with herdr's workspace list failing too), each frame shows its own project's cost when dash runs
# from a pane whose session is priced, and an active epic whose depends_on holds it up is named as
# waiting on it, never under "no open story".
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
fails=0
check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}
has() { grep -qF -- "$1" <<< "$2"; }
lacks() { ! grep -qF -- "$1" <<< "$2"; }

# shellcheck source=fixtures/dash/two_projects.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
source "${HERE}/fixtures/dash/two_projects.sh" "${ROOT}"
A="${FIXTURE_A}"; B="${FIXTURE_B}"
# frames: both projects' frames, with no cache, so each run reads its cost again.
frames() { rm -f "${TMPDIR}"/swarm-dash-*; (cd "${A}" && DASH_W=100 "${FIXTURE_SWARM}" dash --project "${A}" --project "${B}"); }
# frame_of <name> <output>: the lines from <name>'s header line up to the next project's.
frame_of() { awk -v n="$1" '/^(alpha|bravo)  swarm-dev / { on = index($0, n "  ") == 1 } on' <<< "$2"; }
# working <frame>: its "N agents working" count.
working() { sed -n 's/.* \([0-9][0-9]*\) agents working.*/\1/p' <<< "$1" | head -1; }
# cost <frame>: its "$N today".
cost() { sed -n 's/.*\$\([0-9.]*\) today.*/\1/p' <<< "$1" | head -1; }
# status_working <dir>: the agents `swarm.sh status` lists as working in that project.
status_working() { HERDR_ENV=1 SWARM_PROJECT="$1" "${FIXTURE_SWARM}" status | grep -c '^  [^ ]*  *working  \[' || true; }

# 1. The working count is the one status gives, a stalled agent too (bravo's b-page).
out="$(frames)"
for p in alpha bravo; do
  n="$(status_working "${ROOT}/${p}")"
  check "${p}: status lists working agents (${n})" test "${n}" -gt 0
  check "${p}: dash counts the ${n} agents status lists as working" test "$(working "$(frame_of "${p}" "${out}")")" = "${n}"
done
# herdr's workspace list fails: the count still matches status, which never reads it.
mkdir -p "${ROOT}/bin2"
cat > "${ROOT}/bin2/herdr" <<STUB
#!/bin/sh
[ "\$1 \$2" != "workspace list" ] || exit 1
exec "${ROOT}/bin/herdr" "\$@"
STUB
chmod +x "${ROOT}/bin2/herdr"
out="$(PATH="${ROOT}/bin2:${PATH}" frames)"
check "with no workspace list, alpha still counts its 2 working agents" test "$(working "$(frame_of alpha "${out}")")" = 2
check "with no workspace list, the agents are not unavailable" lacks "agents unavailable" "${out}"

# 2. Run from a pane whose own session cost today: each frame keeps its own project's cost.
out="$(frames)"
ca="$(cost "$(frame_of alpha "${out}")")"; cb="$(cost "$(frame_of bravo "${out}")")"
check "the two projects' costs differ (${ca}, ${cb})" test -n "${ca}" -a -n "${cb}" -a "${ca}" != "${cb}"
session elsewhere lead-1 1 claude-opus-5-5 3000000 400000 Bash
cat > "${ROOT}/bin2/herdr" <<STUB
#!/bin/sh
[ "\$1 \$2" = "agent list" ] || exec "${ROOT}/bin/herdr" "\$@"
"${ROOT}/bin/herdr" "\$@" | sed 's/"agents":\[/"agents":[{"name":"lead","agent_status":"working","pane_id":"w9:p9","agent_session":{"value":"lead-1"}},/'
STUB
out="$(PATH="${ROOT}/bin2:${PATH}" HERDR_ENV=1 HERDR_PANE_ID=w9:p9 frames)"
check "from a priced pane, alpha's frame shows alpha's own cost (\$${ca})" has "\$${ca} today" "$(frame_of alpha "${out}")"
check "from a priced pane, bravo's frame shows bravo's own cost (\$${cb})" has "\$${cb} today" "$(frame_of bravo "${out}")"

# 3. An active epic with no stories, on bravo-ui (open stories) and bravo-docs (none, so it holds too).
item "${B}" epics/bravo-mobile.md "Bravo mobile" "status: active" "depends_on: [bravo-ui, bravo-docs]"
fb="$(frame_of bravo "$(frames)")"
check "the waiting epic's row names its depends_on" grep -qE '⏸ bravo-mobile .* waits on bravo-ui, bravo-docs' <<< "${fb}"
check "the waiting epic is not under 'no open story'" bash -c "! grep 'no open story' <<< \"\$1\" | grep -q bravo-mobile" _ "${fb}"
check "the quiet epic with no depends_on is still under 'no open story'" has "1 active epic with no open story: bravo-docs" "${fb}"
# An epic whose stories are all done is never planned, so it waits on nothing, as next reads it.
item "${B}" epics/bravo-old.md "Bravo old" "status: active" "depends_on: [bravo-ui]"
item "${B}" stories/b-old.md "Old work" "status: done" "kind: code" "epic: bravo-old"
fb="$(frame_of bravo "$(frames)")"
check "an epic whose stories are all done does not wait on its depends_on" lacks "waits on bravo-ui" "$(grep bravo-old <<< "${fb}")"
check "an epic whose stories are all done is under 'no open story'" grep -qE 'no open story: .*bravo-old' <<< "${fb}"
# The waiting epic's conductor is shown (reported): its row still names what it waits on.
printf 'w2:p9 conductor\n' > "${B}/.swarm/state/bravo-mobile"
: > "${B}/.swarm/conduct-bravo-mobile.report.md"
cat > "${ROOT}/bin2/herdr" <<STUB
#!/bin/sh
case "\$1 \$2" in
  "agent list") "${ROOT}/bin/herdr" "\$@" | sed 's/"agents":\[/"agents":[{"name":"conduct-bravo-mobile","agent_status":"idle","pane_id":"w2:p9"},/' ;;
  "pane list") "${ROOT}/bin/herdr" "\$@" | sed 's/"panes":\[/"panes":[{"pane_id":"w2:p9"},/' ;;
  *) exec "${ROOT}/bin/herdr" "\$@" ;;
esac
STUB
fb="$(frame_of bravo "$(PATH="${ROOT}/bin2:${PATH}" frames)")"
check "the waiting epic's conductor is shown under it" bash -c "grep -A1 '⏸ bravo-mobile ' <<< \"\$1\" | grep -q '✓ conduct-bravo-mobile .*reported'" _ "${fb}"
check "with its conductor shown, the waiting epic's row names its depends_on" grep -qE '⏸ bravo-mobile .* waits on bravo-ui, bravo-docs' <<< "${fb}"

if [ "${fails}" -gt 0 ]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
