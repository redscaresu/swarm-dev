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
set -euo pipefail

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

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
