#!/usr/bin/env bash
# features_test.sh — `swarm.sh features` against a fixture features.tsv (SWARM_FEATURES) and logs:
# an event: feature used within 30 days shows its count; one whose only use is older, and one with
# no metric, show delete?; an unlogged: one with a metric does not, and role:, agent: and reviewer:
# uses count from agents.tsv and findings.tsv; an interrupted events line is no use. Landing: one
# landed 5 days ago, a #PR whose commit (git log of the features file's repo) is 5 days old, and an
# epic still on the board are never stale; a #PR merged long ago, an epic gone from the board, and an
# impossible date (with a warning) are judged by their uses. Then docs/features.tsv itself: every row
# has a metric, a uses entry and a baseline (a value, or unavailable:), and every role: is one policy accepts.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"; mkdir -p "${P}/.swarm" "${P}/docs/epics"; git -C "${P}" init -q
echo '# Some epic' > "${P}/docs/epics/some-epic.md"
now="$(date -u +%Y-%m-%d)"; old=2020-01-01
fresh="$(python3 -c 'import datetime; print(datetime.date.today() - datetime.timedelta(days=5))')"
# The features file's repo: #2 merged in 2020, #7 five days ago.
F="${dir}/plugin"; mkdir -p "${F}"; git -C "${F}" init -q
for c in "${old} Old feature (#2)" "${fresh} New feature (#7)"; do
  GIT_COMMITTER_DATE="${c%% *}T12:00:00" git -C "${F}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false \
    commit -q --allow-empty -m "${c#* }"
done
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
  $'gone-epic\told-epic\tflow: stacked\t0 (flow)\tevent:stacked' \
  $'bad-date\t2026-02-30\tflow: stacked\t0 (flow)\tevent:stacked' > "${F}/features.tsv"
printf '%s\n' "${now}T10:00:00Z"$'\tstory\ta\tw:1\tok' "${now}T11:00:00Z"$'\tstory\tb\tw:1\tok' \
  "${old}T10:00:00Z"$'\tdrop\ta\tw:1\tok (gone)' "${now}T12:00:00Z"$'\ttidy\t-\tw:1\tinterrupted' > "${P}/.swarm/events.tsv"
printf '%s\n' "${now}"$'\tcode\ta\tclaude\topus\thigh\t-' "${now}"$'\tconduct\tconduct-e\tclaude\topus\thigh\t-' > "${P}/.swarm/agents.tsv"
printf '%s\n' "${now}"$'\tnit\to/r#1\tt\tdeclined\tcodex' > "${P}/.swarm/findings.tsv"

run() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FEATURES="${F}/features.tsv" bash "${SWARM}" features "$@"); }
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
  $'gone-epic\t0\tflow: stacked\t0 (flow)\tdelete?' \
  $'bad-date\t0\tflow: stacked\t0 (flow)\tdelete?')"
check "an impossible landed date is warned about, once, on stderr" "$(run 2>&1 >/dev/null)" \
  "swarm.sh features: bad-date: landed '2026-02-30' is not a date, a #PR git log knows, or an epic; judged by its uses"
check "--since counts the older use, and the verdict still reads the last 30 days" \
  "$(run --since "${old}" 2>/dev/null | grep '^stale')" $'stale\t1\tflow: stacked\t0 (flow)\tdelete?'
check "a bad flag prints the usage" "$(run --since 2>&1 || true)" "swarm: usage: swarm.sh features [--since YYYY-MM-DD]"

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
    [[ "${u}" != role:* ]] || env -u HERDR_ENV bash "${SWARM}" policy "${u#role:}" >/dev/null 2>&1 || bad+="${feature}: ${u} unknown to policy; "
  done
done < <(tail -n +2 "$(dirname "${SWARM}")/../docs/features.tsv")
check "docs/features.tsv: a landed date or epic, a metric, uses and a baseline on every row, and roles policy accepts" "${bad}" ""
check "docs/features.tsv has its rows" "$(( $(wc -l < "$(dirname "${SWARM}")/../docs/features.tsv") > 40 ))" 1

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
