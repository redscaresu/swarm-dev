#!/usr/bin/env bash
# flow_merges_test.sh — `swarm.sh flow`'s merges section against a fixture events.tsv. On 2026-10-01 s-a
# finishes, s-b's reconcile finishes it and s-c finishes twice (counted once, on its newer day); merge
# holds s-p for a protected path, s-m for a costs: line and s-d for dropped base lines, each line with its
# hold= field as merge_fail writes it; s-o's held line is older than the field and has none; s-r's
# refusal is no hold, and s-k's merge went through. On 2026-10-02 s-c finishes again and merge holds s-x
# for dropped base lines unchecked. TZ is UTC.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
P="${dir}/repo"
mkdir -p "${P}/.swarm" "${P}/docs/stories"
git -C "${P}" init -q
ev() { printf '%s\t%s\t%s\t-\t%s\n' "$1" "$2" "$3" "$4" >> "${P}/.swarm/events.tsv"; }
ev 2026-10-01T08:00:00Z finish s-a ok
ev 2026-10-01T08:10:00Z reconcile s-b "ok (finished s-b)"
ev 2026-10-01T08:20:00Z finish s-c ok
ev 2026-10-01T09:00:00Z merge s-p "held: s-p changes hooks/x.sh, which only the user merges; the user merges it ~~ hold=protected"
ev 2026-10-01T09:10:00Z merge s-m "held: s-m costs money; the user merges it ~~ hold=money"
ev 2026-10-01T09:20:00Z merge s-d "held: s-d (dropped base lines: 1, first f: x); the builder restores them ~~ hold=dropped-lines"
ev 2026-10-01T09:30:00Z merge s-o "held: s-o costs money; the user merges it"
ev 2026-10-01T09:40:00Z merge s-r "the head abc1234 is not green: test failed"
ev 2026-10-01T09:50:00Z merge s-k ok
ev 2026-10-02T10:00:00Z finish s-c ok
ev 2026-10-02T10:10:00Z merge s-x "held: s-x (dropped base lines unchecked: gh: HTTP 502); the user checks the merge ~~ hold=dropped-lines"

merges() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FLOW_SECTIONS=merges bash "${SWARM}" flow "$@" | grep -v '^## merges$'); }
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
out="$(merges)"
finished="$(sed -n '1,/^$/p' <<< "${out}" | sed '/^$/d')"
holds="$(sed -n '/^day\tdropped_lines/,$p' <<< "${out}")"
check "the day finished table: each slug once, on its newest finishing line's day; held lines change nothing" \
  "${finished}" $'day\tfinished\n2026-10-01\t2\n2026-10-02\t1'
check "after a blank line, held merge lines per day under their hold= kind; an old held line with no field under unmarked only" \
  "${holds}" $'day\tdropped_lines\tprotected\tmoney\tunmarked\n2026-10-01\t1\t1\t1\t1\n2026-10-02\t1\t0\t0\t0'
check "the two tables are parted by one blank line" "$(grep -c '^$' <<< "${out}")" 1
check "--since keeps the held rows of the window's days" "$(merges --since 2026-10-02 | sed -n '/^day\tdropped_lines/,$p')" \
  $'day\tdropped_lines\tprotected\tmoney\tunmarked\n2026-10-02\t1\t0\t0\t0'

[[ ${fails} -eq 0 ]] || { echo "${out}"; echo "${fails} failed"; exit 1; }
echo "all passed"
