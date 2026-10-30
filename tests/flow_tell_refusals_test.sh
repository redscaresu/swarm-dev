#!/usr/bin/env bash
# flow_tell_refusals_test.sh — `swarm.sh flow`'s tell_refusals section. A fixture events.tsv on
# 2026-10-01: b1, which has an agents.tsv line, is refused gone and unknown (state=), refused before
# a state was read (no state=), and sent, queued and replaced; ghost and zz have none: ghost is
# refused `could not reach` twice with state=none, zz once on an old row with no state=. LONG, a
# slug past agent_name's 32-character cut, has an agents.tsv line under its cut name, so its refusal
# is an agent's. A refusal to a target named ok, whose outcome starts `ok is`, is still a refusal. A
# review-agent line that could not reach anyone is no tell, and tells on 2026-09-30 and 2026-10-02
# are outside a one-day window. A findings tell herdr sent but did not see taken up counts as
# delivered, on its own fixture. TZ is UTC. Then end to end: a real swarm.sh tell, herdr and claude
# stubbed as in tell_blocked_test.sh, refused for b1 on a status herdr gives (herdr:half_asleep) and
# twice for ghost, which herdr does not list (none), shows under those states.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
export TZ=UTC

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWARM="${HERE}/../bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export HOME="${ROOT}/home" CLAUDE_CONFIG_DIR="${ROOT}/claude-config" CLAUDE_PROJECTS_DIR="${ROOT}/claude-config/projects"
export CLAUDE_STUB_AGENTS="${ROOT}/claude.json"
mkdir -p "${HOME}" "${ROOT}/bin" "${CLAUDE_PROJECTS_DIR}"
echo '[]' > "${CLAUDE_STUB_AGENTS}"
cp "${HERE}/claude_stub.sh" "${ROOT}/bin/claude"
P="${ROOT}/proj"
mkdir -p "${P}/.claude/swarm" "${P}/docs/epics" "${P}/docs/stories" "${P}/.swarm/state"
: > "${P}/.claude/swarm/config"
git -C "${P}" init -q
printf '2026-10-01\tcode\tb1\tclaude\topus\thigh\t-\n' > "${P}/.swarm/agents.tsv"   # - : herdr answers for it
LONG=a-story-slug-well-past-the-agent-name-cut   # agent_name cuts it to a-story-slug-well-past-the-agent
printf '2026-10-01\tcode\ta-story-slug-well-past-the-agent\tclaude\topus\thigh\t-\n' >> "${P}/.swarm/agents.tsv"

ev() { printf '%s\t%s\t%s\t-\t%s\n' "$@" >> "${P}/.swarm/events.tsv"; }
ev 2026-09-30T23:00:00Z tell:nudge ghost "could not reach ghost: no agent this project started holds the name ~~ state=none"
ev 2026-10-01T09:00:00Z tell:nudge b1 "could not reach b1: its Claude session has ended (gone); this refusal is final ~~ state=gone"
ev 2026-10-01T09:01:00Z tell:resume b1 "b1: Claude Code gives no state for its session (unknown) ~~ state=unknown"
ev 2026-10-01T09:02:00Z tell:nudge b1 "tell: b1 was not told: herdr could not list its agents; tell it again"
ev 2026-10-01T09:03:00Z tell:findings b1 ok
ev 2026-10-01T09:04:00Z tell:findings b1 "queued: b1 (busy); delivered when its turn ends, so do not tell it again"
ev 2026-10-01T09:05:00Z tell:findings b1 "replaced: b1's findings tell, by a newer one sent or queued meanwhile; not sent"
ev 2026-10-01T09:05:30Z tell:nudge "${LONG}" "a-story-slug-well-past-the-agent is waiting on a prompt ~~ state=herdr:blocked"
ev 2026-10-01T09:06:00Z tell:note ghost "could not reach ghost: no agent this project started holds the name ~~ state=none"
ev 2026-10-01T09:07:00Z tell ghost "could not reach ghost: no agent this project started holds the name ~~ state=none"
ev 2026-10-01T09:07:30Z tell:nudge ok "ok is waiting on dialog open, and its pane shows a prompt or dialog ~~ state=waiting:dialog_open"
ev 2026-10-01T09:08:00Z tell:nudge zz "could not reach zz (status 'odd'): is its pane still open?"
ev 2026-10-01T09:09:00Z review-agent zz "could not reach zz: no agent this project started holds the name ~~ state=none"
ev 2026-10-02T00:00:00Z tell:nudge zz "could not reach zz (status 'odd'): is its pane still open?"

tr_flow() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FLOW_SECTIONS=tell_refusals bash "${SWARM}" flow "$@" | grep -v '^## tell_refusals$'); }
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
out="$(tr_flow --since 2026-10-01 --until 2026-10-01)"
check "tells by pane (agents.tsv or not) and state: ok, queued: and replaced: are tells, not refusals; no state= is -" \
  "$(sed -n '1,/^$/p' <<< "${out}")" "$(printf '%s\n' $'pane\tstate\ttells\trefused' \
    $'agent\tall\t7\t4' $'agent\t-\t4\t1' $'agent\tgone\t1\t1' $'agent\therdr:blocked\t1\t1' $'agent\tunknown\t1\t1' \
    $'other\tall\t4\t4' $'other\t-\t1\t1' $'other\tnone\t2\t2' $'other\twaiting:dialog_open\t1\t1' '')"
check "a slug past agent_name's cut counts under agent, by its agents.tsv name" "$(grep $'^[a-z]*\therdr:blocked\t' <<< "${out}")" \
  $'agent\therdr:blocked\t1\t1'
check "a refusal to a target named ok is a refusal" "$(grep $'^[a-z]*\twaiting:dialog_open\t' <<< "${out}")" \
  $'other\twaiting:dialog_open\t1\t1'
check "could not reach per target, most first: ghost refused twice shows 2" "$(sed '1,/^$/d' <<< "${out}")" \
  "$(printf '%s\n' $'target\tcould_not_reach' $'ghost\t2' $'b1\t1' $'zz\t1')"
check "with no tell in the window, one line" "$(tr_flow --since 2026-10-03)" "no tell in the window"
check "the next day: its refusal alone" "$(tr_flow --since 2026-10-02 --until 2026-10-02 | sed '1,/^$/d')" \
  "$(printf '%s\n' $'target\tcould_not_reach' $'zz\t1')"
: > "${P}/.swarm/events.tsv"
ev 2026-10-01T09:03:00Z tell:findings b1 "b1: herdr sent it the brief once; the findings count as delivered, a findings round of its build, so do not send them again"
check "a findings tell herdr sent but did not see taken up is delivered, not refused" "$(tr_flow --since 2026-10-01 --until 2026-10-01 | sed -n 2p)" \
  $'agent\tall\t1\t0'
: > "${P}/.swarm/events.tsv"
ev 2026-10-01T09:03:00Z tell:findings b1 ok
check "a window with tells and no could not reach refusal says so" "$(tr_flow --since 2026-10-01 --until 2026-10-01)" \
  "$(printf '%s\n' $'pane\tstate\ttells\trefused' $'agent\tall\t1\t0' $'agent\t-\t1\t0' '' 'no could not reach refusal in the window')"

# End to end: herdr lists b1 alone, in pane w:9, with the status in ${ROOT}/status.
printf '#!/bin/sh\nF="%s"\n' "${ROOT}" > "${ROOT}/bin/herdr"
cat >> "${ROOT}/bin/herdr" <<'EOF'
case "$1 $2" in
  "agent list") printf '{"result":{"agents":[{"name":"b1","agent_status":"%s","pane_id":"w:9"}]}}\n' "$(cat "$F/status")" ;;
  "agent get") printf '{"result":{"agent":{"agent_status":"%s"}}}\n' "$(cat "$F/status")" ;;
  *) echo "herdr stub: unexpected call: $*" >&2; exit 1 ;;
esac
EOF
chmod +x "${ROOT}/bin/herdr" "${ROOT}/bin/claude"
echo "w:9 b1" > "${P}/.swarm/state/b1"
echo "half asleep" > "${ROOT}/status"
echo "carry on" > "${ROOT}/msg"
rm -f "${P}/.swarm/events.tsv"
tell() { (cd "${P}" && env -u SWARM_PROJECT -u HERDR_PANE_ID HERDR_ENV=1 PATH="${ROOT}/bin:${PATH}" bash "${SWARM}" tell "$1" nudge "${ROOT}/msg" 2>&1) || true; }
today="$(date -u +%Y-%m-%d)"
said="$(tell b1)$(tell ghost)$(tell ghost)"
grep -qF "could not reach b1 (status 'half asleep')" <<< "${said}" || { echo "FAIL the real tell to b1 was not refused as expected: ${said}"; exit 1; }
out="$(tr_flow --since "${today}")"
check "end to end: real refused tells show under the states they logged" "${out}" \
  "$(printf '%s\n' $'pane\tstate\ttells\trefused' $'agent\tall\t1\t1' $'agent\therdr:half_asleep\t1\t1' \
    $'other\tall\t2\t2' $'other\tnone\t2\t2' '' $'target\tcould_not_reach' $'ghost\t2' $'b1\t1')"

[[ ${fails} -eq 0 ]] || { echo "${out}"; echo "${fails} failed"; exit 1; }
echo "all passed"
