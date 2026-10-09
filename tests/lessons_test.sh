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

# A declined kind is never proposed again.
for pr in u/4 u/5 u/6; do sw finding denylist "${pr}" "a scrub that lists what to remove" >/dev/null; done
check "denylist is now a candidate" "yes" "$(has "candidate denylist" "$(sw lessons)")"
printf 'No. <!-- lesson-declined: denylist -->\n' >> "${dir}/.claude/swarm/brief.md"
check "a declined kind is not proposed again" "no" "$(grep -q "candidate denylist" <<< "$(sw lessons)" && echo yes || echo no)"

# A kind last fixed long ago is not news: no candidate.
for pr in u/20 u/21 u/22; do printf '2020-01-01\told-kind\t%s\tlong ago\n' "${pr}" >> "${dir}/.swarm/findings.tsv"; done
check "a kind not fixed recently is not a candidate" "no" "$(grep -q "candidate old-kind" <<< "$(sw lessons)" && echo yes || echo no)"

# One PR written three ways counts once.
for pr in https://github.com/O/R/pull/12 https://github.com/o/r/pull/12/files o/r#12; do sw finding same-pr "${pr}" "x" >/dev/null; done
check "one PR written three ways counts once" "yes" "$(has "same-pr	1 PR(s)" "$(sw lessons --all)")"

# Unquoted text is kept whole, and a carriage return cannot split a row.
sw finding unquoted u/30 several words of text >/dev/null
check "unquoted text is kept whole" "several words of text" "$(tail -1 "${dir}/.swarm/findings.tsv" | cut -f4)"
sw finding cr-test "$(printf 'u/31\r')" "$(printf 'a\rb')" >/dev/null
check "a carriage return is flattened" "4" "$(tail -1 "${dir}/.swarm/findings.tsv" | awk -F'\t' '{print NF}')"
check "an unknown flag is refused" "yes" "$(has "usage: swarm.sh lessons" "$(sw lessons -a || true)")"

# A brief over the cap is flagged.
head -c 5000 /dev/zero | tr '\0' 'x' >> "${dir}/.claude/swarm/brief.md"
check "a long brief is flagged" "yes" "$(has "long brief" "$(sw lessons)")"

# Tabs and newlines in a finding cannot break the log's columns.
sw finding tab-test u/7 "$(printf 'a\tb\nc')" >/dev/null
check "a finding's tabs and newlines are flattened" "4" "$(tail -1 "${dir}/.swarm/findings.tsv" | awk -F'\t' '{print NF}')"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
