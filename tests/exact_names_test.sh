#!/usr/bin/env bash
# exact_names_test.sh — dash and flow's idle_slots read an agent by its exact name, never by herdr's
# cut of it (agent_name: 32 characters). 1. dash: a conductor whose conduct-<epic> runs past 32
# characters is listed by herdr under the cut; once its epic file has left the board, its epic comes
# from its own record (an ok conduct event or its brief), so its report shows it as reported. With no
# record, or two conductors under the cut (two epics' records, or one and an epic on the board whose
# conductor name is the cut itself), it is not reported, even when the cut without conduct- names a
# third epic with a report: the cut is no epic. 2. flow: two stories whose slugs share their
# first 32 characters, each readied and built at its own time, give idle_slots minutes to each one's
# epic, not to one merged key. Both parts fail with the old guesses (the cut without conduct-, and
# idle_slots' agent_name keys).
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWARM="${HERE}/../bin/swarm.sh"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}

# 1. dash, on the fixture's bravo project. The conductor's epic has no file on the board; herdr lists
# its agent idle under the cut, in pane w2:p9 of a tab recorded for it.
# shellcheck source=fixtures/dash/two_projects.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
source "${HERE}/fixtures/dash/two_projects.sh" "${ROOT}"
B="${FIXTURE_B}"
epic="an-epic-whose-conductor-name-runs-past-the-cut"; cut="conduct-${epic}"; cut="${cut:0:32}"
other="${epic}-too"   # a second long epic whose conductor shares the cut
printf 'w2:p9 conductor\n' > "${B}/.swarm/state/${epic}"
: > "${B}/.swarm/conduct-${epic}.report.md"
mkdir -p "${ROOT}/bin2"
cat > "${ROOT}/bin2/herdr" <<STUB
#!/bin/sh
case "\$1 \$2" in
  "agent list") "${ROOT}/bin/herdr" "\$@" | sed 's/"agents":\[/"agents":[{"name":"${cut}","agent_status":"idle","pane_id":"w2:p9"},/' ;;
  "pane list") "${ROOT}/bin/herdr" "\$@" | sed 's/"panes":\[/"panes":[{"pane_id":"w2:p9"},/' ;;
  *) exec "${ROOT}/bin/herdr" "\$@" ;;
esac
STUB
chmod +x "${ROOT}/bin2/herdr"
events="$(cat "${B}/.swarm/events.tsv")"
# conductor_row: "shown" when bravo's frame names the conductor (dash cuts the name to its column, so
# by its first 29 characters), then " reported" when a row of it says so.
conductor_row() {
  local frame
  rm -rf "${TMPDIR}"/swarm-dash-*
  frame="$(cd "${B}" && PATH="${ROOT}/bin2:${PATH}" DASH_W=160 "${FIXTURE_SWARM}" dash | grep -F "${cut:0:29}")" || true
  [[ -z "${frame}" ]] || printf shown
  ! grep -q ' reported ' <<< "${frame}" || printf ' reported'
}
conducted() { # <epic>... — bravo's events.tsv, with an ok conduct line for each
  { echo "${events}"; for e in "$@"; do printf '%s\tconduct\t%s\tw2:p0\tok\n' "$(at 60)" "${e}"; done; } > "${B}/.swarm/events.tsv"
}
conducted "${epic}"
check "a cut conductor whose epic file is gone takes its epic from its conduct event: reported" "$(conductor_row)" "shown reported"
conducted
mkdir -p "${B}/.swarm/briefs"; : > "${B}/.swarm/briefs/conduct-${epic}.md"
check "a cut conductor whose epic file is gone takes its epic from its brief: reported" "$(conductor_row)" "shown reported"
rm "${B}/.swarm/briefs/conduct-${epic}.md"
# The cut without conduct- is a third epic's name, and that epic wrote a report.
: > "${B}/.swarm/conduct-${cut#conduct-}.report.md"
check "a cut conductor with no record of its epic is not reported, though the cut names an epic with a report" "$(conductor_row)" shown
conducted "${epic}" "${other}"
check "a cut two epics' conduct events share gives no epic: not reported" "$(conductor_row)" shown
# The third epic is on the board, so its conductor's name is the cut too: two conductors under it.
conducted "${epic}"; item "${B}" "epics/${cut#conduct-}.md" "Third" "status: active"
check "a cut a board epic's conductor shares with the recorded one gives no epic: not reported" "$(conductor_row)" shown

# 2. flow's idle_slots. ea's story waits 09:00-10:00, eb's 11:00-13:00; neither epic's conductor
# runs. agents.tsv keeps the cut for both; their session logs name each full slug.
I="${ROOT}/idle"; mkdir -p "${I}/.swarm" "${I}/docs/stories" "${I}/docs/epics" "${ROOT}/flow-bin" "${ROOT}/flow-projects/p"; git -C "${I}" init -q
printf '#!/bin/sh\nexit 0\n' > "${ROOT}/flow-bin/gh"; chmod +x "${ROOT}/flow-bin/gh"
shared="two-stories-whose-slugs-share-th"   # 32 characters
one="${shared}e-first-32-characters"; two="${shared}is-start-but-not-the-rest"
for x in "ea:${one}:10:00" "eb:${two}:13:00"; do
  IFS=: read -r e s hh mm <<< "${x}"
  printf -- '---\nstatus: active\n---\n' > "${I}/docs/epics/${e}.md"
  printf -- '---\nkind: code\nstatus: ready\nepic: %s\ntouches: [src/%s.sh]\n---\n' "${e}" "${e}" > "${I}/docs/stories/${s}.md"
  printf '{"cwd":"%s/idle-wt/%s","timestamp":"2026-10-01T%s:%s:00Z"}\n' "${ROOT}" "${s}" "${hh}" "${mm}" > "${ROOT}/flow-projects/p/s-${e}.jsonl"
  printf '2026-10-01\tcode\t%s\tclaude\topus\thigh\ts-%s\n' "${shared}" "${e}" >> "${I}/.swarm/agents.tsv"
done
printf '%s\n' $'2026-10-01T09:00:00Z\tunblock\t'"${one}"$'\tw:1\tok' $'2026-10-01T11:00:00Z\tunblock\t'"${two}"$'\tw:1\tok' > "${I}/.swarm/events.tsv"
idle() { (cd "${I}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FLOW_SECTIONS=idle_slots CLAUDE_PROJECTS_DIR="${ROOT}/flow-projects" PATH="${ROOT}/flow-bin:${PATH}" \
  bash "${SWARM}" flow "$@" 2>&1 | grep -v -e '^## idle_slots$' -e '^sed: '); }   # sed warns on a byte that is not UTF-8
check "idle_slots: two slugs that share their first 32 characters give each its own epic's minutes" \
  "$(idle --until 2026-10-01)" $'epic\tidle_min\tno_conductor_min\tmost_ready\nea\t0\t60\t1\neb\t0\t120\t1\nall\t0\t180\t1'

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
