#!/usr/bin/env bash
# features_test.sh — `swarm.sh features` against a fixture features.tsv (SWARM_FEATURES) and logs:
# an event: feature used within 30 days shows its count; one whose only use is older, and one with
# no metric, show delete?; an unlogged: one with a metric does not, and role:, agent: and reviewer:
# uses count from agents.tsv and findings.tsv. One landed 5 days ago, and one whose landed is an epic,
# are never stale; an interrupted events line is no use. Then docs/features.tsv itself: every row has a metric,
# a uses entry and a baseline (a value, or unavailable:), and every role: is one policy accepts.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
P="${dir}/repo"; mkdir -p "${P}/.swarm" "${P}/docs"; git -C "${P}" init -q
now="$(date -u +%Y-%m-%d)"; old=2020-01-01
fresh="$(python3 -c 'import datetime; print(datetime.date.today() - datetime.timedelta(days=5))')"
printf '%s\n' $'feature\tlanded\tmetric\tbaseline\tuses' \
  $'used\t#1\tflow: stacked\t0 (flow)\tevent:story' \
  $'stale\t#2\tflow: stacked\t0 (flow)\tevent:drop' \
  $'unmeasured\t#3\t\t0 (flow)\tevent:story' \
  $'read-only\t#4\tflow: builds\t0 (flow)\tunlogged: read-only' \
  $'others\t#5\tcost: total\t0 (cost)\trole:code agent:conduct-e reviewer:codex' \
  "fresh"$'\t'"${fresh}"$'\tflow: stacked\t0 (flow)\tevent:drop' \
  $'pending\tsome-epic\tflow: stacked\t0 (flow)\tevent:stacked' \
  $'refused\t#6\tflow: stacked\t0 (flow)\tevent:tidy' > "${dir}/features.tsv"
printf '%s\n' "${now}T10:00:00Z"$'\tstory\ta\tw:1\tok' "${now}T11:00:00Z"$'\tstory\tb\tw:1\tok' \
  "${old}T10:00:00Z"$'\tdrop\ta\tw:1\tok (gone)' "${now}T12:00:00Z"$'\ttidy\t-\tw:1\tinterrupted' > "${P}/.swarm/events.tsv"
printf '%s\n' "${now}"$'\tcode\ta\tclaude\topus\thigh\t-' "${now}"$'\tconduct\tconduct-e\tclaude\topus\thigh\t-' > "${P}/.swarm/agents.tsv"
printf '%s\n' "${now}"$'\tnit\to/r#1\tt\tdeclined\tcodex' > "${P}/.swarm/findings.tsv"

run() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FEATURES="${dir}/features.tsv" bash "${SWARM}" features "$@"); }
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
check "uses in 30 days, delete? for a stale or unmeasured feature, unlogged judged on its metric alone, none for one landed in 30 days or with an epic yet to finish, and a refused event is no use" "$(run)" "$(printf '%s\n' \
  $'feature\tuses\tmetric\tbaseline\tverdict' \
  $'used\t2\tflow: stacked\t0 (flow)\t' \
  $'stale\t0\tflow: stacked\t0 (flow)\tdelete?' \
  $'unmeasured\t2\t\t0 (flow)\tdelete?' \
  $'read-only\t-\tflow: builds\t0 (flow)\t' \
  $'others\t3\tcost: total\t0 (cost)\t' \
  $'fresh\t0\tflow: stacked\t0 (flow)\t' \
  $'pending\t0\tflow: stacked\t0 (flow)\t' \
  $'refused\t0\tflow: stacked\t0 (flow)\tdelete?')"
check "--since counts the older use, and the verdict still reads the last 30 days" \
  "$(run --since "${old}" | grep '^stale')" $'stale\t1\tflow: stacked\t0 (flow)\tdelete?'
check "a bad flag prints the usage" "$(run --since 2>&1 || true)" "swarm: usage: swarm.sh features [--since YYYY-MM-DD]"

# docs/features.tsv: a metric, a uses entry and a baseline on every row; each role: one policy knows.
bad=""
while IFS=$'\t' read -r feature _ metric baseline uses; do
  [[ -n "${metric}" && -n "${uses}" && -n "${baseline}" ]] || bad+="${feature}: an empty field; "
  [[ "${baseline}" != unavailable* || "${baseline}" == unavailable:* ]] || bad+="${feature}: baseline ${baseline}; "
  [[ "${uses}" == unlogged:* ]] && continue
  for u in ${uses}; do
    [[ "${u}" =~ ^(event|role|agent|reviewer):. ]] || bad+="${feature}: use ${u}; "
    [[ "${u}" != role:* ]] || env -u HERDR_ENV bash "${SWARM}" policy "${u#role:}" >/dev/null 2>&1 || bad+="${feature}: ${u} unknown to policy; "
  done
done < <(tail -n +2 "$(dirname "${SWARM}")/../docs/features.tsv")
check "docs/features.tsv: a metric, uses and a baseline on every row, and roles policy accepts" "${bad}" ""
check "docs/features.tsv has its rows" "$(( $(wc -l < "$(dirname "${SWARM}")/../docs/features.tsv") > 40 ))" 1

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
