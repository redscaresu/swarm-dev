#!/usr/bin/env bash
# lessons_test.sh — the outer loop: `swarm.sh finding` logs fixed findings by kind, and
# `swarm.sh lessons` names a kind fixed in 3+ distinct PRs that the brief has no rule for, a brief
# rule whose kind has gone quiet, and a brief that has grown too long.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)"
trap 'rm -rf "${dir}"' EXIT
git -C "${dir}" init -q
mkdir -p "${dir}/.claude/swarm"
: > "${dir}/.claude/swarm/config"
fails=0
sw() { (cd "${dir}" && env -u SWARM_PROJECT bash "${SWARM}" "$@" 2>&1); }
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }
check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

check "a kind must be kebab-case" "yes" "$(has "must be short kebab-case" "$(sw finding 'Vacuous Test' u/1 x || true)")"
check "nothing recorded yet" "yes" "$(has "no lessons" "$(sw lessons)")"

# vacuous-test in three distinct PRs (one PR twice); denylist in two.
for pr in u/1 u/1 u/2 u/3; do sw finding vacuous-test "${pr}" "a test that passes with its fix removed" >/dev/null; done
for pr in u/4 u/5; do sw finding denylist "${pr}" "a scrub that lists what to remove" >/dev/null; done
out="$(sw lessons)"
check "a kind in 3 distinct PRs is a candidate" "yes" "$(has "candidate vacuous-test: fixed in 3 PRs" "${out}")"
check "a kind in 2 PRs is not yet" "no" "$(grep -q "candidate denylist" <<< "${out}" && echo yes || echo no)"
check "--all lists every kind with its PR count" "yes|yes" \
  "$(has "vacuous-test	3 PR(s)" "$(sw lessons --all)")|$(has "denylist	2 PR(s)" "$(sw lessons --all)")"

# A rule in the brief, tagged with its kind, retires the candidate.
printf 'Prove each test can fail. <!-- lesson: vacuous-test -->\n' > "${dir}/.claude/swarm/brief.md"
check "a kind the brief already rules is no longer a candidate" "no" \
  "$(grep -q "candidate vacuous-test" <<< "$(sw lessons)" && echo yes || echo no)"

# A rule whose kind was last fixed long ago, or never, is stale.
printf '2020-01-01\told-kind\tu/9\tlong ago\n' >> "${dir}/.swarm/findings.tsv"
printf 'Old rule. <!-- lesson: old-kind -->\nNever seen. <!-- lesson: never-seen -->\n' >> "${dir}/.claude/swarm/brief.md"
out="$(sw lessons)"
check "a rule whose kind went quiet is stale" "yes|yes" "$(has "stale old-kind" "${out}")|$(has "stale never-seen" "${out}")"
check "a rule whose kind is still fixed is not stale" "no" "$(grep -q "stale vacuous-test" <<< "${out}" && echo yes || echo no)"

# A brief over the cap is flagged.
head -c 5000 /dev/zero | tr '\0' 'x' >> "${dir}/.claude/swarm/brief.md"
check "a long brief is flagged" "yes" "$(has "long brief" "$(sw lessons)")"

# Tabs and newlines in a finding cannot break the log's columns.
sw finding tab-test u/7 "$(printf 'a\tb\nc')" >/dev/null
check "a finding's tabs and newlines are flattened" "4" "$(tail -1 "${dir}/.swarm/findings.tsv" | awk -F'\t' '{print NF}')"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
