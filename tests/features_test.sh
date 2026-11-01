#!/usr/bin/env bash
# features_test.sh — `swarm.sh flow`'s features section against a fixture features.tsv (SWARM_FEATURES) and logs:
# an event: feature used within 30 days shows its count; one whose only use is older, and one with
# no metric, show delete?; an unlogged: one with a metric does not, and role:, agent: and reviewer:
# uses count from agents.tsv and findings.tsv; an interrupted events line is no use, and an event
# counts by its local day. Landing, read in the features file's own repo: one landed 5 days ago, a #PR
# whose commit subject is 5 days old, an epic on its board, and one deleted from it 5 days ago are
# never stale; a #PR merged in 2020 (a later body naming it does not count), an epic deleted in
# 2020, one it never had, and an impossible date (with a warning) are judged by their uses. Then docs/features.tsv itself: every row
# has a metric, a uses entry and a baseline (a value, or unavailable:), and every role: is one policy accepts.
# Then the section check over a fixture and docs/features.tsv: a metric naming `flow <section>` names a
# flow_<section>.py that exists, a row landed by an epic of the 0.30 and 0.31 HLD names a column that section
# prints, the two rows read by hand are exempt by name and fail without it, and Goal 6's events have rows.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
P="${dir}/repo"; mkdir -p "${P}/.swarm" "${P}/docs" "${dir}/bin"; git -C "${P}" init -q
# gh answers nothing, as for a repo with no GitHub remote.
printf '#!/bin/sh\nexit 1\n' > "${dir}/bin/gh"; chmod +x "${dir}/bin/gh"
now="$(date -u +%Y-%m-%d)"; old=2020-01-01
fresh="$(python3 -c 'import datetime; print(datetime.date.today() - datetime.timedelta(days=5))')"
# The features file's repo, where its PRs and epics are (its board is board/): #2 merged in 2020, a
# later commit names (#2) only in its body, #7 merged five days ago; epic some-epic is on its board,
# old-gone-epic left it in 2020 and new-gone-epic five days ago. The reported project's board has none.
F="${dir}/plugin"; mkdir -p "${F}/docs" "${F}/board/epics" "${F}/.claude/swarm"; git -C "${F}" init -q
echo 'board_dir = board' > "${F}/.claude/swarm/config"
fc() { GIT_COMMITTER_DATE="$1T12:00:00" git -C "${F}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q --allow-empty "${@:2}"; }
touch "${F}/board/epics/old-gone-epic.md" "${F}/board/epics/new-gone-epic.md"; git -C "${F}" add -A
fc "${old}" -m "Old feature (#2)"
git -C "${F}" rm -q board/epics/old-gone-epic.md; fc "${old}" -m "old-gone-epic is done"
fc "${fresh}" -m "A later fix" -m "It follows up on (#2)"
fc "${fresh}" -m "New feature (#7)"
git -C "${F}" rm -q board/epics/new-gone-epic.md; fc "${fresh}" -m "new-gone-epic is done"
mkdir -p "${F}/board/epics"; echo "# Some epic" > "${F}/board/epics/some-epic.md"
printf '%s\n' $'feature\tlanded\tmetric\tbaseline\tuses' \
  "used"$'\t'"${old}"$'\tflow: stacked\t0 (flow)\tevent:story' \
  "stale"$'\t'"${old}"$'\tflow: stacked\t0 (flow)\tevent:drop' \
  "unmeasured"$'\t'"${old}"$'\t\t0 (flow)\tevent:story' \
  "read-only"$'\t'"${old}"$'\tflow: builds\t0 (flow)\tunlogged: read-only' \
  "others"$'\t'"${old}"$'\tcost: total\t0 (cost)\trole:code agent:conduct-e reviewer:codex' \
  "fresh"$'\t'"${fresh}"$'\tflow: stacked\t0 (flow)\tevent:drop' \
  $'pending\tsome-epic\tflow: stacked\t0 (flow)\tevent:stacked' \
  "refused"$'\t'"${old}"$'\tflow: stacked\t0 (flow)\tevent:tidy' \
  $'old-pr\t#2\tflow: stacked\t0 (flow)\tevent:stacked' \
  $'new-pr\t#7\tflow: stacked\t0 (flow)\tevent:stacked' \
  $'old-gone\told-gone-epic\tflow: stacked\t0 (flow)\tevent:stacked' \
  $'new-gone\tnew-gone-epic\tflow: stacked\t0 (flow)\tevent:stacked' \
  $'never\tno-such-epic\tflow: stacked\t0 (flow)\tevent:stacked' \
  $'bad-date\t2026-02-30\tflow: stacked\t0 (flow)\tevent:stacked' > "${F}/docs/features.tsv"
printf '%s\n' "${now}T10:00:00Z"$'\tstory\ta\tw:1\tok' "${now}T11:00:00Z"$'\tstory\tb\tw:1\tok' \
  "${old}T10:00:00Z"$'\tdrop\ta\tw:1\tok (gone)' "${now}T12:00:00Z"$'\ttidy\t-\tw:1\tinterrupted' > "${P}/.swarm/events.tsv"
printf '%s\n' "${now}"$'\tcode\ta\tclaude\topus\thigh\t-' "${now}"$'\tconduct\tconduct-e\tclaude\topus\thigh\t-' > "${P}/.swarm/agents.tsv"
printf '%s\n' "${now}"$'\tnit\to/r#1\tt\tdeclined\tcodex' > "${P}/.swarm/findings.tsv"

# flow's features section, without its `## features` line; flow's stderr as it is.
run() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FEATURES="${SWARM_FEATURES:-${F}/docs/features.tsv}" PATH="${dir}/bin:${PATH}" \
  bash "${SWARM}" flow "$@") | sed -n '/^## features$/,/^## /p' | sed -e 1d -e '/^## /d' -e '/^$/d'; }
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
check "uses in 30 days, delete? for a stale or unmeasured feature, unlogged judged on its metric alone, none for one landed (a date or a #PR) in 30 days or an epic still on the board, and a refused event is no use" "$(run 2>/dev/null)" "$(printf '%s\n' \
  $'feature\tuses\tmetric\tbaseline\tverdict' \
  $'used\t2\tflow: stacked\t0 (flow)\t' \
  $'stale\t0\tflow: stacked\t0 (flow)\tdelete?' \
  $'unmeasured\t2\t\t0 (flow)\tdelete?' \
  $'read-only\t-\tflow: builds\t0 (flow)\t' \
  $'others\t3\tcost: total\t0 (cost)\t' \
  $'fresh\t0\tflow: stacked\t0 (flow)\t' \
  $'pending\t0\tflow: stacked\t0 (flow)\t' \
  $'refused\t0\tflow: stacked\t0 (flow)\tdelete?' \
  $'old-pr\t0\tflow: stacked\t0 (flow)\tdelete?' \
  $'new-pr\t0\tflow: stacked\t0 (flow)\t' \
  $'old-gone\t0\tflow: stacked\t0 (flow)\tdelete?' \
  $'new-gone\t0\tflow: stacked\t0 (flow)\t' \
  $'never\t0\tflow: stacked\t0 (flow)\tdelete?' \
  $'bad-date\t0\tflow: stacked\t0 (flow)\tdelete?')"
check "an impossible landed date is warned about, once, on stderr" "$(run 2>&1 >/dev/null)" \
  "swarm.sh flow: features: bad-date: landed '2026-02-30' is not a date, a #PR git log knows, or an epic; judged by its uses"
check "--since counts the older use, and the verdict still reads the last 30 days" \
  "$(run --since "${old}" 2>/dev/null | grep '^stale')" $'stale\t1\tflow: stacked\t0 (flow)\tdelete?'
check "--until leaves out the uses after it: used's are today's, stale's is on --until's day" \
  "$(run --since "${old}" --until "${old}" 2>/dev/null | grep -E '^(used|stale)')" "$(printf '%s\n' $'used\t0\tflow: stacked\t0 (flow)\t' $'stale\t1\tflow: stacked\t0 (flow)\tdelete?')"
check "--until alone counts the 30 days up to it: stale's use on --until's day" \
  "$(run --until "${old}" 2>/dev/null | grep '^stale')" $'stale\t1\tflow: stacked\t0 (flow)\tdelete?'
# In UTC-7, an event at 03:00Z on the first day of the 30 is the day before locally, so outside them.
edge="$(TZ=America/Los_Angeles python3 -c 'import datetime; print(datetime.date.today() - datetime.timedelta(days=30))')"
printf '%s\n' "${edge}T03:00:00Z"$'\tedgecmd\t-\tw:1\tok' >> "${P}/.swarm/events.tsv"
printf '%s\n' "edge"$'\t'"${old}"$'\tflow: stacked\t0 (flow)\tevent:edgecmd' >> "${F}/docs/features.tsv"
check "an event counts by its local day: 03:00Z in UTC-7 falls before the last 30 days" \
  "$(TZ=America/Los_Angeles run 2>/dev/null | grep '^edge')" $'edge\t0\tflow: stacked\t0 (flow)\tdelete?'
check "with no feature list, the section says so" "$(SWARM_FEATURES="${dir}/none.tsv" run 2>/dev/null)" "no feature list at ${dir}/none.tsv"
# Without SWARM_FEATURES, the project's own docs/features.tsv, never the plugin's.
own() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT -u SWARM_FEATURES PATH="${dir}/bin:${PATH}" bash "${SWARM}" flow 2>/dev/null) \
  | sed -n '/^## features$/,/^## /p' | sed -e 1d -e '/^## /d' -e '/^$/d'; }
check "without SWARM_FEATURES or a project docs/features.tsv, one line and no plugin feature" \
  "$(own | sed 's|at .*/docs/features.tsv$|at <project>/docs/features.tsv|')" "no feature list at <project>/docs/features.tsv"
cp "${F}/docs/features.tsv" "${P}/docs/features.tsv"
check "without SWARM_FEATURES, the project's docs/features.tsv is read" "$(own | head -2)" \
  "$(printf '%s\n' $'feature\tuses\tmetric\tbaseline\tverdict' $'used\t2\tflow: stacked\t0 (flow)\t')"
rm "${P}/docs/features.tsv"

# docs/features.tsv: a metric, a uses entry and a baseline on every row; each role: one policy knows.
bad=""
while IFS=$'\t' read -r feature landed metric baseline uses; do
  [[ -n "${metric}" && -n "${uses}" && -n "${baseline}" ]] || bad+="${feature}: an empty field; "
  # A date or an epic, so the installed plugin, which is no git checkout, never has to look up a #PR.
  [[ "${landed}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ || "${landed}" =~ ^[a-z][a-z0-9_-]*$ ]] || bad+="${feature}: landed ${landed}; "
  [[ "${baseline}" != unavailable* || "${baseline}" == unavailable:* ]] || bad+="${feature}: baseline ${baseline}; "
  [[ "${uses}" == unlogged:* ]] && continue
  for u in ${uses}; do
    [[ "${u}" =~ ^(event|role|agent|reviewer):. ]] || bad+="${feature}: use ${u}; "
    [[ "${u}" != role:* ]] || (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT bash "${SWARM}" policy "${u#role:}" >/dev/null 2>&1) || bad+="${feature}: ${u} unknown to policy; "
  done
done < <(tail -n +2 "$(dirname "${SWARM}")/../docs/features.tsv")
check "docs/features.tsv: a landed date or epic, a metric, uses and a baseline on every row, and roles policy accepts" "${bad}" ""
check "docs/features.tsv has its rows" "$(( $(wc -l < "$(dirname "${SWARM}")/../docs/features.tsv") > 40 ))" 1

# The section check. A metric naming `flow <section>` (not `flow:`, and not a metric without flow) names a
# bin/lib/flow_<section>.py that exists. A row landed by an epic of the 0.30 and 0.31 HLD also names,
# after the colon, a column that section prints as a header (a tab-separated line of lowercase names)
# over the fixture logs below, which give each section the rows its headers need.
ROOT="$(cd "$(dirname "${SWARM}")/.." && pwd)"
# The HLD's § Epics, listed here: `swarm.sh finish` deletes the HLD once its epics are built, in a board-only
# PR that runs no tests, and its rows must still have their columns checked after that.
HLD="${ROOT}/board/hld/2026-10-28-swarm-dev-0-30-and-0-31.md"
HLD_EPICS=" delivery-liveness lead-woken merge-safety telemetry-readers telemetry-writers review-rounds-end reference-split machine-usable merge-mechanics flaky-tests deferred-700 board-loose-ends review-yield review-follows-head reliable-runs stalls-and-effort doc-hotspot status-speed "
if [[ -f "${HLD}" ]]; then
  check "HLD_EPICS is the HLD's § Epics, while the HLD is on the board" \
    " $(sed -n '/^## Epics$/,/^## /s|^- \[\([a-z0-9-]*\)\](\.\./epics/.*|\1|p' "${HLD}" | tr '\n' ' ')" "${HLD_EPICS}"
fi
# Read by hand at the release (lead decision 2026-10-30), so no one flow column holds them:
# - lead-woken incidents: lead-hand incidents per 100 merged story PRs takes incidents' lead-hand lines
#   over a count of merged story PRs that no section prints (epic_totals' merged_prs leaves some out).
# - reference split: conflict merge-ins touching a docs/reference*.md file reads each merge-in's
#   files, which merge_ins lists only for its top three files.
EXEMPT=$'lead-woken incidents\nreference split'
Q="${dir}/sections"; mkdir -p "${Q}/.swarm"; git -C "${Q}" init -q
printf '%s\n' $'2026-10-01\tcode\ts-a\tclaude\topus\thigh\tk1' > "${Q}/.swarm/agents.tsv"; : > "${Q}/.swarm/findings.tsv"
printf '%s\n' $'2026-10-01T07:00:00Z\tstory\ts-a\t-\tok' $'2026-10-01T07:10:00Z\treview-agent\ts-a\t-\tok' \
  $'2026-10-01T07:20:00Z\treview\ts-a\t-\tok (https://github.com/o/r/pull/1)' $'2026-10-01T07:21:00Z\tmerge\ts-a\t-\tok' \
  $'2026-10-01T09:00:00Z\ttell:nudge\tghost\t-\tcould not reach ghost: no agent this project started holds the name ~~ state=none' \
  $'2026-10-01T10:00:00Z\treview-agent\ts-b\t-\treview-agent: review-s-b did not start (its pane w1-3 is closed)' > "${Q}/.swarm/events.tsv"
headers() { # <section>... — `<section><TAB><word>` for each header word those sections print over the fixture,
  # run as flow runs them (flow_report.py), without the outcomes rows flow builds first, which no header needs.
  local q="${Q}/.swarm"
  { (cd "${Q}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FINDING_REVIEWERS=codex PATH="${dir}/bin:${PATH}" python3 "${ROOT}/bin/lib/flow_report.py" \
    0000-00-00 9999-12-30 "" "${q}/agents.tsv" "${q}/events.tsv" "${q}/findings.tsv" x code x x "" x "$@" 2>/dev/null) || true; } |
    awk -F'\t' '/^## /{s = substr($0, 4); next}
    NF > 1 {for (i = 1; i <= NF; i++) if ($i !~ /^[a-z][a-z0-9_]*$/) next; for (i = 1; i <= NF; i++) print s "\t" $i}'
}
# The whole word after `flow ` and after its colon, so a name that only starts like a real one fails.
SECTION_RE='^flow ([^: ]+)' COLUMN_RE='^flow [^: ]+: ([^ ,;]+)'
section_check() { # <features.tsv> [exempt feature names, one per line] — one line per row that fails
  local f="$1" exempt="${2-${EXEMPT}}" bad="" todo="" sections=() feature landed metric baseline uses section col
  while IFS=$'\t' read -r feature landed metric baseline uses; do
    [[ "${metric}" =~ ${SECTION_RE} ]] || continue
    section="${BASH_REMATCH[1]}"
    [[ -f "${ROOT}/bin/lib/flow_${section}.py" ]] || { bad+="${feature}: no bin/lib/flow_${section}.py"$'\n'; continue; }
    [[ "${HLD_EPICS}" == *" ${landed} "* ]] || continue
    ! grep -Fxq "${feature}" <<< "${exempt}" || continue
    col=""; [[ "${metric}" =~ ${COLUMN_RE} ]] && col="${BASH_REMATCH[1]}"
    [[ -n "${col}" ]] || { bad+="${feature}: flow ${section} names no column"$'\n'; continue; }
    todo+="${feature}"$'\t'"${section}"$'\t'"${col}"$'\n'; sections+=("${section}")
  done < <(tail -n +2 "${f}")
  if [[ -n "${todo}" ]]; then
    local seen; seen="$(headers "${sections[@]}")"
    while IFS=$'\t' read -r feature section col; do
      grep -Fxq "${section}"$'\t'"${col}" <<< "${seen}" || bad+="${feature}: flow ${section} prints no column ${col}"$'\n'
    done <<< "${todo%$'\n'}"
  fi
  printf '%s' "${bad}"
}
printf '%s\n' $'feature\tlanded\tmetric\tbaseline\tuses' $'no-section\tlead-woken\tflow no_such_section: x\t0\tevent:story' \
  $'no-column\tlead-woken\tflow lead_queue: no_such_column\t0\tevent:story' $'bare\tlead-woken\tflow lead_queue\t0\tevent:story' \
  $'old-gone\t2020-01-01\tflow no_such_section\t0\tevent:story' $'prefix\t2020-01-01\tflow lead_queue-v2: p90_min\t0\tevent:story' \
  $'col-prefix\tlead-woken\tflow lead_queue: p90_minX\t0\tevent:story' > "${dir}/bad.tsv"
check "a missing flow section fails on any row; a column the section does not print, or none, fails on a row of the HLD's epics; a name that only starts like a real one fails" \
  "$(section_check "${dir}/bad.tsv")" "$(printf '%s\n' 'no-section: no bin/lib/flow_no_such_section.py' \
  'bare: flow lead_queue names no column' 'old-gone: no bin/lib/flow_no_such_section.py' 'prefix: no bin/lib/flow_lead_queue-v2.py' \
  'no-column: flow lead_queue prints no column no_such_column' 'col-prefix: flow lead_queue prints no column p90_minX')"
printf '%s\n' $'feature\tlanded\tmetric\tbaseline\tuses' $'flow-bare\tlead-woken\tflow: builders_mean\t0\tevent:story' \
  $'no-flow\tlead-woken\toutcomes: story_merged share\t0\tevent:story' $'column\tlead-woken\tflow lead_queue: p90_min\t0\tevent:story' \
  $'not-hld\t2020-01-01\tflow lead_queue: no_such_column\t0\tevent:story' > "${dir}/good.tsv"
check "with the HLD deleted from the board, a row of its epics still has its column checked" \
  "$(HLD="${dir}/no-such-hld.md" section_check "${dir}/bad.tsv" | grep '^no-column')" 'no-column: flow lead_queue prints no column no_such_column'
check "flow: and a metric without flow pass; a column the section prints passes; outside the HLD's epics no column is read" \
  "$(section_check "${dir}/good.tsv")" ""
check "docs/features.tsv passes the section check" "$(section_check "${ROOT}/docs/features.tsv")" ""
check "without its exemption, lead-woken incidents fails" "$(section_check "${ROOT}/docs/features.tsv" 'reference split')" \
  "lead-woken incidents: flow incidents prints no column lead-hand"
check "without its exemption, reference split fails" "$(section_check "${ROOT}/docs/features.tsv" 'lead-woken incidents')" \
  "reference split: flow merge_ins prints no column conflict"
check "Goal 6's rows: a use of each new event" \
  "$(cut -f5 "${ROOT}/docs/features.tsv" | tr ' ' '\n' | grep -E '^event:(pr-opened|first-green|review-finished)$' | sort)" \
  "$(printf '%s\n' event:first-green event:pr-opened event:review-finished)"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
