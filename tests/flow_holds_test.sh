#!/usr/bin/env bash
# flow_holds_test.sh — `swarm.sh flow`'s holds section against a fixture events.tsv. a is held at 10:00
# for story b and built at 10:50: 50 minutes, a clash. c is held twice with different reasons before
# its 11:00 build: one hold, from the first, with the first's reason. d is held and never built: open.
# e is held for 5 minutes with a reason that names no story or PR: other. TZ is UTC.
set -euo pipefail
export TZ=UTC

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
P="${dir}/repo"
mkdir -p "${P}/.swarm" "${P}/docs/stories"
git -C "${P}" init -q
for s in a b c d; do printf -- '---\nkind: code\nstatus: ready\nepic: e1\n---\n' > "${P}/docs/stories/${s}.md"; done
ev() { printf '2026-10-01T%s:00Z\t%s\t%s\t-\t%s\n' "$1" "$2" "$3" "$4" >> "${P}/.swarm/events.tsv"; }
ev 10:00 hold a "ok (clashes with b on flow.sh)"
ev 10:10 hold c "ok (waits on PR #12)"
ev 10:20 hold c "ok (the lead asked)"
ev 10:30 hold d "ok (waits on #13)"
ev 10:40 story a "failed (exit 1)"
ev 10:50 story a ok
ev 11:00 story c ok
ev 12:00 hold e "ok (the lead asked)"
ev 12:05 story e ok

holds() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FLOW_SECTIONS=holds bash "${SWARM}" flow "$@" | grep -v '^## holds$'); }
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
out="$(holds)"
check "a hold runs from its line to the next ok build start, with its reason" "$(grep $'^a\t' <<< "${out}")" $'a\te1\tclashes with b on flow.sh\t50'
check "a story held and never built is open" "$(grep $'^d\t' <<< "${out}")" $'d\te1\twaits on #13\topen'
check "two holds of one story count once, from the first, with its reason" "$(grep $'^c\t' <<< "${out}")" $'c\te1\twaits on PR #12\t50'
check "a story with no board file or rows has epic -" "$(grep $'^e\t' <<< "${out}")" $'e\t-\tthe lead asked\t5'
check "held minutes per class: a story or PR named is clash, else other; open holds are not counted" \
  "$(sed -n '/^class/,$p' <<< "${out}")" $'class\theld_min\nclash\t100\nother\t5'
check "--epic keeps that epic's holds" "$(holds --epic e1 | cut -f1 | sed -n '2,4p' | tr '\n' ' ')" "a c d "
check "--since past the holds' day leaves them out" "$(holds --since 2026-10-02 | head -2)" $'story\tepic\treason\theld_min'

[[ ${fails} -eq 0 ]] || { echo "${out}"; echo "${fails} failed"; exit 1; }
echo "all passed"
