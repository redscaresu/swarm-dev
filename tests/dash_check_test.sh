#!/usr/bin/env bash
# dash_check_test.sh — `dash --check` on the two-project fixture (tests/fixtures/dash/two_projects.sh),
# with an active epic added to bravo that waits on its depends_on. For each field --check compares,
# this test runs the command that owns it and checks the frame shows the same, and --check exits 0.
# It still agrees with lead = off, when an agent spends while the frame draws, and with a waiting
# epic's conductor working. Then each of dash-three-defects' fixes reverted in a copy of bin/ (the
# working count, the failed workspace list, the calling pane's cost, the waiting epic), a status that
# lists one more working agent, a next that fails, a merge row gone while an answer row names its
# story, and flow's cost unreadable, each make --check exit 1 naming the field; a frame dash cannot
# draw is a frame line for each project. --check refuses --watch, and tells two projects with one
# basename apart.
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

# shellcheck source=fixtures/dash/two_projects.sh disable=SC1091 # CI lints without -x; shellcheck -x lints it
source "${HERE}/fixtures/dash/two_projects.sh" "${ROOT}"
A="${FIXTURE_A}"; B="${FIXTURE_B}"
item "${B}" epics/bravo-mobile.md "Bravo mobile" "status: active" "depends_on: [bravo-ui, bravo-docs]"
sw() { SWARM_PROJECT="$1" "${FIXTURE_SWARM}" "${@:2}"; }
# box <title> <frame>: the lines inside that box.
box() { awk -v t="$1" '/^╭─ / { on = index($0, "╭─ " t " ") == 1; next } /^╰/ { on = 0 } on' <<< "$2"; }

# 1. Each field against the command that owns it, in each project's own frame.
for p in alpha bravo; do
  d="${ROOT}/${p}"
  rm -f "${TMPDIR}"/swarm-dash-*
  f="$(DASH_W=100 sw "${d}" dash)"
  st="$(HERDR_ENV=1 sw "${d}" status)"
  n="$(grep -c '^  [^ ]*  *working  \[' <<< "${st}" || true)"
  check "${p}: agents working is the ${n} status lists" has " ${n} agents working" "${f}"
  check "${p}: the running gauge is the ${n} status lists" grep -qE "running [^0-9]* ${n} of peak" <<< "${f}"
  c="$(sw "${d}" flow --since 2026-10-10 | sed -n 's/^| \*\*total\*\* |.* \([0-9][0-9.]*\) |$/\1/p')"
  check "${p}: the cost is flow's \$${c}" has "\$${c} today" "${f}"
  q="$(box "lead's queue" "${f}")"
  for x in $(sw "${d}" flow | sed -n '/^## lead_queue$/,/^## /p' | awk -F'\t' 'NR > 2 && NF == 5 && $5 != "-" { gsub(",", " ", $5); print $5 }'); do
    check "${p}: lead_queue's open ${x} is in the lead's queue" grep -qE " ${x#*:}( |$)" <<< "${q}"
  done
  y="$(box "needs you" "${f}")"$'\n'"${q}"
  while read -r x; do
    check "${p}: status's merge of ${x} has a merge row" grep -qE "! merge .* ${x} *│" <<< "${y}"
  done < <(sed -n 's/^  awaiting your merge[^:]*: \([^ ]*\).*/\1/p' <<< "${st}")
  n="$(sed -n '/^Waiting on you$/,/^$/p' <<< "${st}" | grep -c '^  [^ :]*: [^ ]*$' || true)"
  m="$(box "needs you" "${f}" | sed -n 's/.*+\([0-9]\) more.*/\1/p')"
  check "${p}: status's ${n} stories for you or the lead are the run rows and +N more" \
    test "$(($(grep -c '! run [^ ]* story ' <<< "${y}") + ${m:-0}))" = "${n}"
  while read -r x; do
    check "${p}: status's ${x} waiting on a prompt has an answer row" has "! answer ${x} " "${y}"
  done < <(sed -n 's/^  \([^ ]*\)  *WAITING .*/\1/p' <<< "${st}")
  check "${p}: the header's next is next's" has "  next $(sw "${d}" next | sed -n 1p)  " "$(sed -n 1p <<< "${f}")"
  # flow's merges section over the 7 days to 2026-10-10: the stories finished each day.
  read -r t w <<< "$(sw "${d}" flow --since 2026-10-04 --until 2026-10-10 | sed -n '/^## merges$/,/^## /p' \
    | awk -F'\t' 'NR > 2 && NF == 2 { w += $2; if ($1 == "2026-10-10") t = $2 } END { printf "%d %.1f\n", t, w / 7 }')"
  check "${p}: merges today are flow's ${t}" has "  today ${t}  7-day avg ${w}" "${f}"
  check "${p}: the 7-day rate is flow's ${w}" has "${w} merged/day over 7 days" "$(sed -n 2p <<< "${f}")"
done
# The epics: next plans bravo-docs, so bravo-mobile, active with no stories, waits on its depends_on.
fb="$(DASH_W=100 sw "${B}" dash)"
check "bravo: next plans bravo-docs, not the waiting bravo-mobile" has "plan-epic bravo-docs" "$(HERDR_ENV=1 sw "${B}" status)"
check "bravo: the frame names bravo-mobile waiting on bravo-ui, bravo-docs" grep -qE '⏸ bravo-mobile .* waits on bravo-ui, bravo-docs' <<< "${fb}"

out="$(cd / && "${FIXTURE_SWARM}" dash --check --project "${A}" --project "${B}")" && rc=0 || rc=$?
check "dash --check exits 0 on the fixture (exit ${rc})" test "${rc}" -eq 0
check "dash --check says each project agrees" test "$(grep -c 'every dash figure agrees' <<< "${out}")" -eq 2
# A waiting epic whose name dash cuts to the width, a story with two PRs gh cannot answer (a merge
# row each, by its URL), and an agent waiting on a prompt with no reason given. A held PR that a story
# and its epic both list, shown once, and a merge row long enough to wrap.
sed 's/,"waitingFor":"input"//' "${CLAUDE_STUB_AGENTS}" > "${ROOT}/claude2.json" && cat "${ROOT}/claude2.json" > "${CLAUDE_STUB_AGENTS}"
item "${B}" epics/bravo-an-epic-name-too-long-for-the-epics-column.md "Long" "status: active" "depends_on: [bravo-ui]"
item "${B}" stories/b-new.md "New" "status: review" "kind: code" "prs: [https://github.com/o/bravo/pull/98, https://github.com/o/bravo/pull/99]"
item "${B}" epics/bravo-held.md "Held" "status: review" "costs: money" "prs: https://github.com/o/bravo/pull/97"
item "${B}" stories/b-held.md "Held" "status: review" "kind: code" "epic: bravo-held" "costs: money" "prs: https://github.com/o/bravo/pull/97"
item "${B}" stories/b-a-story-slug-long-enough-that-its-merge-row-wraps-at-one-hundred.md "Long" "status: review" "kind: code" \
  "prs: https://github.com/o/bravo/pull/96"
fb="$(DASH_W=100 sw "${B}" dash)"
check "bravo: dash shows the held PR once" test "$(grep -c 'pull/97' <<< "${fb}")" -eq 1
check "bravo: the long merge row wraps" grep -qE '^│   https://github.com/o/bravo/pull/96 ' <<< "${fb}"
check "bravo: dash cuts the long epic's name" grep -qE '⏸ bravo-an-epic-name-too-long[^ ]*… ' <<< "${fb}"
check "bravo: dash shows b-new's merge by its URL" has "merge b-new: https://github.com/o/bravo/pull/99" "${fb}"
check "bravo: dash shows b-fix's prompt with no reason" has "answer b-fix: " "${fb}"
out="$(sw "${B}" dash --check)" && rc=0 || rc=$?
check "with a cut epic name, PRs by URL, held or wrapped, and no prompt reason, dash --check exits 0 (exit ${rc}: ${out})" test "${rc}" -eq 0

# With lead = off, an escalated lead story is in flow's lead_queue but dash draws no row for it, as
# it draws none for status.
sed 's/^lead = session$/lead = off/' "${A}/.claude/swarm/config" > "${ROOT}/alpha-config" && cat "${ROOT}/alpha-config" > "${A}/.claude/swarm/config"
check "alpha is lead = off" grep -qx 'lead = off' "${A}/.claude/swarm/config"
item "${A}" stories/a-esc.md "Escalated" "status: ready" "kind: lead" "escalated_from: code"
printf '%s\tescalated\ta-esc\tw1:p1\tok\n' "$(at 30)" >> "${A}/.swarm/events.tsv"
check "alpha, lead = off: flow's lead_queue holds escalated:a-esc open" grep -q 'escalated:a-esc' <<< "$(sw "${A}" flow)"
fa="$(DASH_W=100 sw "${A}" dash)"
# shellcheck disable=SC2016 # the script's own $1 and $2
check "alpha, lead = off: no needs-you or lead's-queue row for a-esc" bash -c '! grep -q a-esc <<< "$1"' _ "$(box "needs you" "${fa}"; box "lead's queue" "${fa}")"
out="$(sw "${A}" dash --check)" && rc=0 || rc=$?
check "alpha, lead = off: dash --check exits 0 (exit ${rc}: ${out})" test "${rc}" -eq 0

# An agent spends while the frame draws: the herdr stub logs a new turn for a-building each time dash
# or status asks for the agent list, after dash has read its cost. flow's cost before the frame and
# after it differ, and dash's lies between them.
mkdir -p "${ROOT}/spend"
cat > "${ROOT}/spend/herdr" <<STUB
#!/bin/sh
[ "\$1 \$2" != "agent list" ] || printf '{"type":"assistant","timestamp":"%s","message":{"id":"spend-%s","model":"claude-opus-5-5","usage":{"input_tokens":100000,"output_tokens":10000},"content":[]}}\n' \
  "$(at 1)" "\$\$" >> "${ROOT}/projects/alpha/sa-2.jsonl"
exec "${ROOT}/bin/herdr" "\$@"
STUB
chmod +x "${ROOT}/spend/herdr"
cost() { sw "$1" flow --since 2026-10-10 | sed -n 's/^| \*\*total\*\* |.* \([0-9][0-9.]*\) |$/\1/p'; }
c0="$(cost "${A}")"
out="$(PATH="${ROOT}/spend:${PATH}" sw "${A}" dash --check)" && rc=0 || rc=$?
check "with spend while the frame draws, dash --check exits 0 (exit ${rc}: ${out})" test "${rc}" -eq 0
c1="$(cost "${A}")"
check "with spend while the frame draws, the cost moved" test "${c1}" != "${c0}"

# From a pane whose own session cost today, the frame still shows the project's own cost, as flow
# with no calling session does.
session elsewhere lead-1 1 claude-opus-5-5 3000000 400000 Bash
mkdir -p "${ROOT}/priced"
cat > "${ROOT}/priced/herdr" <<STUB
#!/bin/sh
[ "\$1 \$2" = "agent list" ] || exec "${ROOT}/bin/herdr" "\$@"
"${ROOT}/bin/herdr" "\$@" | sed 's/"agents":\[/"agents":[{"name":"lead","agent_status":"working","pane_id":"w9:p9","agent_session":{"value":"lead-1"}},/'
STUB
mkdir -p "${ROOT}/noworkspace"
cat > "${ROOT}/noworkspace/herdr" <<STUB
#!/bin/sh
[ "\$1 \$2" != "workspace list" ] || exit 1
exec "${ROOT}/bin/herdr" "\$@"
STUB
chmod +x "${ROOT}/priced/herdr" "${ROOT}/noworkspace/herdr"
priced() { PATH="${ROOT}/priced:${PATH}" HERDR_ENV=1 HERDR_PANE_ID=w9:p9 "$@"; }
out="$(priced sw "${A}" dash --check)" && rc=0 || rc=$?
check "from a priced pane, dash --check still exits 0 (exit ${rc})" test "${rc}" -eq 0

# 2. A fix reverted, or a status that disagrees: --check exits 1 naming the field.
# mutant <name> <file under bin/> <sed script>: a copy of the plugin whose file has the edit, its
# swarm.sh in M; fails when the edit changes nothing.
mutant() {
  local h="${ROOT}/m-$1"
  mkdir -p "${h}/.claude-plugin"
  cp -R "${HERE}/../bin" "${h}/bin"; cp "${ROOT}/home/.claude-plugin/plugin.json" "${h}/.claude-plugin/"
  sed "$3" "${h}/bin/$2" > "${h}/edit"
  ! cmp -s "${h}/edit" "${h}/bin/$2" || return 1
  cat "${h}/edit" > "${h}/bin/$2"
  M="${h}/bin/swarm.sh"
}
# names <project dir> <field> <command...>: the command exits 1 and names the field in that project.
names() {
  local p; p="$(basename "$1")"; shift
  local field="$1"; shift
  out="$("$@")" && rc=0 || rc=$?
  if [[ ${rc} -eq 1 ]] && has "${p}: ${field}: dash shows" "${out}"; then return 0; fi
  echo "  exit ${rc}: ${out}"; return 1
}
M=""
check "mutant: the working count leaves out stalled agents" \
  mutant working lib/dash_render.py 's/sum(r\["state"\] in ("working", "stalled") for r in recs)/sum(r["state"] == "working" for r in recs)/'
check "with stalled agents left out, --check names agents working" names "${B}" "agents working" env SWARM_PROJECT="${B}" "${M}" dash --check
check "mutant: a failed workspace list loses the agents" mutant workspace lib/dash.sh 's/|| workspaces=""$/|| agents=""/'
check "with no workspace list, --check names agents working" names "${A}" "agents working" \
  env PATH="${ROOT}/noworkspace:${PATH}" SWARM_PROJECT="${A}" "${M}" dash --check
# shellcheck disable=SC2016 # the sed scripts name bash's own $1 and ${...}
check "mutant: dash's cost counts the calling pane's session" \
  mutant cost lib/reports.sh 's/flow_sections "$1" 9999-12-30 "" "" "" cost/flow_sections "$1" 9999-12-30 "" "" "$(session_for_pane "${HERDR_PANE_ID:-}")" cost/'
check "from a priced pane, --check names the cost" names "${A}" cost priced env SWARM_PROJECT="${A}" "${M}" dash --check
check "mutant: a waiting epic goes under no open story" mutant waits lib/dash_render.py 's/ and s not in waits and not any/ and not any/'
check "with the waiting epic quiet, --check names the epics waiting" names "${B}" "epics waiting on depends_on" \
  env SWARM_PROJECT="${B}" "${M}" dash --check
# shellcheck disable=SC2016
check "mutant: status lists one more working agent" \
  mutant status swarm.sh 's/^    status) status_report "${1:-}" ;;$/    status) status_report "${1:-}"; echo "  ghost  working  [x w9:p9]" ;;/'
check "with that status, --check names agents working" names "${A}" "agents working" env SWARM_PROJECT="${A}" "${M}" dash --check
check "mutant: next fails" mutant next swarm.sh 's/^    next)   next_step ;;$/    next)   exit 3 ;;/'
out="$(env SWARM_PROJECT="${A}" "${M}" dash --check)" && rc=0 || rc=$?
# shellcheck disable=SC2016 # the script's own $1 and $2
check "with next failing, --check exits 1 naming next (exit ${rc}: ${out})" \
  bash -c '[[ $1 == 1 ]] && grep -q "^alpha: next: dash shows conduct alpha-core, next says nothing$" <<< "$2"' _ "${rc}" "${out}"

check "mutant: a merge row with checks is never drawn" mutant mergerow lib/dash_render.py 's/add(rows, bang + \[(f"merge {pr_ref(u)} (",/add([], bang + [(f"merge {pr_ref(u)} (",/'
check "with b-fix's merge row gone but its answer row kept, --check names the lead's queue" names "${B}" "lead's queue" \
  env SWARM_PROJECT="${B}" "${M}" dash --check
check "mutant: dash_render raises" mutant raise lib/dash_render.py '1s/^/raise RuntimeError("boom"); /'
out="$(cd / && "${M}" dash --check --project "${A}" --project "${B}")" && rc=0 || rc=$?
framed() { [[ ${rc} == 1 ]] && grep -qx "alpha: frame: dash could not draw it: RuntimeError: boom" <<< "${out}" \
  && grep -qx "bravo: frame: dash could not draw it: RuntimeError: boom" <<< "${out}"; }
check "when dash cannot draw, --check exits 1 with a frame line for each project" framed
check "mutant: flow's cost section raises" mutant nocost lib/flow_cost.py '1s/^/raise RuntimeError("no cost") /'
check "when flow's cost cannot be read, --check names the cost" names "${A}" cost env SWARM_PROJECT="${A}" "${M}" dash --check
check "when flow's cost cannot be read, --check says so" has "says nothing: its cost could not be read" "${out}"

check "mutant: the running gauge is left out" mutant nogauge lib/dash_render.py 's/^    if agents is None:   # no agent list/    if True:   # no agent list/'
check "with herdr's agent list but no running gauge, --check names running" names "${A}" running env SWARM_PROJECT="${A}" "${M}" dash --check
check "mutant: flow's lead_queue section raises" mutant noqueue lib/flow_lead_queue.py '1s/^/raise RuntimeError("no queue") /'
out="$(env SWARM_PROJECT="${B}" "${M}" dash --check)" && rc=0 || rc=$?
unread() { [[ ${rc} == 1 ]] && grep -qx "$1" <<< "${out}"; }
check "when flow's lead_queue cannot be read, --check says so" unread "bravo: lead's queue: flow's lead_queue could not be read"
check "mutant: flow's merges section raises" mutant nomerges lib/flow_merges.py '1s/^/raise RuntimeError("no merges") /'
out="$(env SWARM_PROJECT="${A}" "${M}" dash --check)" && rc=0 || rc=$?
check "when flow's merges cannot be read, --check says so" unread "alpha: merges today and the 7-day rate: flow's merges could not be read"

# --check draws nothing, so it refuses the flags that change how a frame is drawn.
out="$(sw "${A}" dash --check --watch 30 2>&1)" && rc=0 || rc=$?
refused() { [[ ${rc} != 0 ]] && has "dash --check draws nothing" "${out}"; }
check "dash --check --watch 30 is refused" refused

# Two --project dirs with one basename: each is named by its path.
mkdir -p "${ROOT}/twin" && cp -R "${A}" "${ROOT}/twin/alpha"
out="$(cd / && "${FIXTURE_SWARM}" dash --check --project "${A}" --project "${ROOT}/twin/alpha")" || true
apart() { grep -q "^${A}: " <<< "${out}" && grep -q "^${ROOT}/twin/alpha: " <<< "${out}" && ! grep -q "^alpha: " <<< "${out}"; }
check "two projects named alpha are told apart by their paths" apart

# A waiting epic with a working conductor is drawn ● rather than ⏸, and still names what it waits on.
printf 'w2:p9 conductor\n' > "${B}/.swarm/state/bravo-mobile"
printf '2026-10-10\tconduct\tconduct-bravo-mobile\tclaude\topus\thigh\tsb-9\n' >> "${B}/.swarm/agents.tsv"
session bravo sb-9 1 claude-opus-5-5 1000 100 Bash
sed 's/\]$/,{"sessionId":"sb-9","status":"busy"}]/' "${CLAUDE_STUB_AGENTS}" > "${ROOT}/claude3.json" && cat "${ROOT}/claude3.json" > "${CLAUDE_STUB_AGENTS}"
mkdir -p "${ROOT}/conducting"
cat > "${ROOT}/conducting/herdr" <<STUB
#!/bin/sh
case "\$1 \$2" in
  "agent list") "${ROOT}/bin/herdr" "\$@" | sed 's/"agents":\[/"agents":[{"name":"conduct-bravo-mobile","agent_status":"working","pane_id":"w2:p9","agent_session":{"value":"sb-9"}},/' ;;
  "pane list") "${ROOT}/bin/herdr" "\$@" | sed 's/"panes":\[/"panes":[{"pane_id":"w2:p9"},/' ;;
  *) exec "${ROOT}/bin/herdr" "\$@" ;;
esac
STUB
chmod +x "${ROOT}/conducting/herdr"
check "bravo: the waiting epic with a working conductor is drawn ●" grep -qE '^│ ● bravo-mobile .* waits on bravo-ui, bravo-docs' \
  <<< "$(PATH="${ROOT}/conducting:${PATH}" DASH_W=100 sw "${B}" dash)"
out="$(PATH="${ROOT}/conducting:${PATH}" sw "${B}" dash --check)" && rc=0 || rc=$?
check "with the waiting epic's conductor working, dash --check exits 0 (exit ${rc}: ${out})" test "${rc}" -eq 0

if [ "${fails}" -gt 0 ]; then echo "${fails} failed"; exit 1; fi
echo "all passed"
