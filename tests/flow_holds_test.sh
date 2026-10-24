#!/usr/bin/env bash
# flow_holds_test.sh — `swarm.sh flow`'s holds section against a fixture events.tsv and board. s-a is
# held at 10:00 for s-b (building since 09:00) and built at 10:50: 50 minutes, a clash. s-c is held
# twice with different reasons before its 11:00 build: one hold, from the first, with the first's
# reason. s-d is held and never built: open. s-e has no story file: epic -. s-m's reason holds the
# word merge, a one-word story that started earlier, and s-n's names s-late, which starts after the
# hold: both other. s-i (not held:), s-j (give-up) and s-k (closed this wave) name PRs, and are other.
# s-h is dropped and s-g's file deleted by a board commit, neither built: dropped and removed, s-g's
# epic read from that commit's parent. TZ is UTC.
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
commit() { # <date> <message>
  GIT_AUTHOR_DATE="$1" GIT_COMMITTER_DATE="$1" git -C "${P}" -c user.name=t -c user.email=t@t.invalid commit -qm "$2"
}
for s in s-a s-c s-d s-g s-h s-i s-j s-k s-m s-n; do
  printf -- '---\nkind: code\nstatus: ready\nepic: e1\n---\n' > "${P}/docs/stories/${s}.md"
done
git -C "${P}" add docs && commit 2026-09-30T00:00:00Z board
git -C "${P}" rm -q docs/stories/s-g.md && commit 2026-10-01T14:30:00Z "drop s-g"
ev() { printf '2026-10-01T%s:00Z\t%s\t%s\t-\t%s\n' "$1" "$2" "$3" "$4" >> "${P}/.swarm/events.tsv"; }
ev 08:00 story merge ok
ev 09:00 story s-b ok
ev 10:00 hold s-a "ok (clashes with s-b on flow.sh)"
ev 10:10 hold s-c "ok (waits on PR #12)"
ev 10:20 hold s-c "ok (the lead asked)"
ev 10:30 hold s-d "ok (waits on #13)"
ev 10:40 story s-a "failed (exit 1)"
ev 10:50 story s-a ok
ev 11:00 story s-c ok
ev 12:00 hold s-e "ok (the lead asked)"
ev 12:05 story s-e ok
ev 12:10 hold s-m "ok (waits for the merge)"
ev 12:20 story s-m ok
ev 12:30 hold s-n "ok (shares a file with s-late)"
ev 12:35 story s-late ok
ev 12:40 story s-n ok
ev 13:00 hold s-i "ok (not held: a PR merged or merging, #20)"
ev 13:10 story s-i ok
ev 13:20 hold s-j "ok (the give-up rule: PR #21 failed twice)"
ev 13:30 story s-j ok
ev 13:40 hold s-k "ok (closed this wave after s-b's PR #22)"
ev 13:50 story s-k ok
ev 14:00 hold s-h "ok (the lead asked)"
ev 14:10 drop s-h "ok (no longer needed)"
ev 14:20 hold s-g "ok (the lead asked)"

holds() { (cd "${P}" && env -u HERDR_ENV -u SWARM_PROJECT SWARM_FLOW_SECTIONS=holds bash "${SWARM}" flow "$@" | grep -v '^## holds$'); }
row() { grep $'^'"$1"$'\t' <<< "${out}"; }
fails=0
check() { # <name> <output> <exact expected output>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1"; diff <(echo "$3") <(echo "$2") || true; fails=$((fails + 1)); fi
}
out="$(holds)"
check "a hold runs from its line to the next ok build start, with its reason" "$(row s-a)" $'s-a\te1\tclashes with s-b on flow.sh\t50'
check "a story held and never built is open" "$(row s-d)" $'s-d\te1\twaits on #13\topen'
check "two holds of one story count once, from the first, with its reason" "$(row s-c)" $'s-c\te1\twaits on PR #12\t50'
check "a story with no board file or rows has epic -" "$(row s-e)" $'s-e\t-\tthe lead asked\t5'
check "a hold dropped with no build shows dropped" "$(row s-h)" $'s-h\te1\tthe lead asked\tdropped'
check "a hold whose story file a board commit deleted shows removed, with the epic from history" "$(row s-g)" $'s-g\te1\tthe lead asked\tremoved'
check "held minutes per class: clash for a PR or a started story named; other for an ordinary word that is a slug, a story started after the hold, not held:, give-up and closed this wave" \
  "$(sed -n '/^class/,$p' <<< "${out}")" $'class\theld_min\nclash\t100\nother\t55'
check "--epic keeps that epic's holds, the whole table" "$(holds --epic e1 | awk -F'\t' 'NF { print $1 "\t" $NF; next } 1')" \
  "$(printf '%s\t%s\n' story held_min s-a 50 s-c 50 s-d open s-m 10 s-n 10 s-i 10 s-j 10 s-k 10 s-h dropped s-g removed '' '' class held_min clash 100 other 50 | sed 's/^\t$//')"
check "--since past the holds' day leaves them out, in one line" "$(holds --since 2026-10-02)" "no hold in the window"
check "--epic with no holds says so in one line" "$(holds --epic e9)" "no hold of epic e9 in the window"

[[ ${fails} -eq 0 ]] || { echo "${out}"; echo "${fails} failed"; exit 1; }
echo "all passed"
