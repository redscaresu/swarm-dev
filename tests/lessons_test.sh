#!/usr/bin/env bash
# lessons_test.sh — the outer loop: `swarm.sh finding` logs fixed findings by kind, and
# `swarm.sh lessons` names a kind fixed in 3+ distinct recent PRs that the brief has no rule (or
# decline) for, and a brief that has grown too long.
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

check "a kind must be kebab-case" "yes" "$(has "must be short kebab-case" "$(sw finding 'Vacuous Test' o/r#1 x || true)")"
check "nothing recorded yet" "yes" "$(has "no lessons" "$(sw lessons)")"

# vacuous-test in three distinct PRs (one PR twice); denylist in two.
for pr in o/r#1 o/r#1 o/r#2 o/r#3; do sw finding vacuous-test "${pr}" "a test that passes with its fix removed" >/dev/null; done
for pr in o/r#4 o/r#5; do sw finding denylist "${pr}" "a scrub that lists what to remove" >/dev/null; done
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
for pr in o/r#4 o/r#5 o/r#6; do sw finding denylist "${pr}" "a scrub that lists what to remove" >/dev/null; done
check "denylist is now a candidate" "yes" "$(has "candidate denylist" "$(sw lessons)")"
printf 'No. <!-- lesson-declined: denylist -->\n' >> "${dir}/.claude/swarm/brief.md"
check "a declined kind is not proposed again" "no" "$(grep -q "candidate denylist" <<< "$(sw lessons)" && echo yes || echo no)"

# A kind last fixed long ago is not news: no candidate.
for pr in o/r#20 o/r#21 o/r#22; do printf '2020-01-01\told-kind\t%s\tlong ago\n' "${pr}" >> "${dir}/.swarm/findings.tsv"; done
check "a kind not fixed recently is not a candidate" "no" "$(grep -q "candidate old-kind" <<< "$(sw lessons)" && echo yes || echo no)"

# One PR written three ways counts once.
for pr in https://github.com/O/R/pull/12 https://github.com/o/r/pull/12/files o/r#12; do sw finding same-pr "${pr}" "x" >/dev/null; done
check "one PR written three ways counts once" "yes" "$(has "same-pr	1 PR(s)" "$(sw lessons --all)")"

# Unquoted text is kept whole, and a carriage return cannot split a row.
sw finding unquoted o/r#30 several words of text >/dev/null
check "unquoted text is kept whole" "several words of text" "$(tail -1 "${dir}/.swarm/findings.tsv" | cut -f4)"
sw finding cr-test o/r#31 "$(printf 'a\rb\r')" >/dev/null
check "a carriage return is flattened" "4" "$(tail -1 "${dir}/.swarm/findings.tsv" | awk -F'\t' '{print NF}')"
check "an unknown flag is refused" "yes" "$(has "usage: swarm.sh lessons" "$(sw lessons -a || true)")"

# A PR must be a URL or owner/repo#N; shorthand that could double-count is refused.
check "a shorthand PR is refused" "yes" "$(has "must be a PR URL or owner/repo#N" "$(sw finding k '#12' x || true)")"

# Only PRs inside the window count: two old fixes plus one new one is not a candidate.
for pr in o/r#40 o/r#41; do printf '2020-01-01\tmixed\t%s\told\n' "${pr}" >> "${dir}/.swarm/findings.tsv"; done
sw finding mixed o/r#42 "new" >/dev/null
check "old PRs do not count toward the threshold" "no" "$(grep -q "candidate mixed" <<< "$(sw lessons)" && echo yes || echo no)"

# A stray non-UTF-8 byte in the log does not break lessons.
printf '%s\tbytes\to/r#50\tbad \xff byte\n' "$(date +%F)" >> "${dir}/.swarm/findings.tsv"
check "a non-UTF-8 byte does not break lessons" "yes" "$(has "bytes	1 PR(s)" "$(sw lessons --all)")"

# A brief over the cap is flagged.
head -c 5000 /dev/zero | tr '\0' 'x' >> "${dir}/.claude/swarm/brief.md"
check "a long brief is flagged" "yes" "$(has "long brief" "$(sw lessons)")"

# Tabs and newlines in a finding cannot break the log's columns.
sw finding tab-test o/r#7 "$(printf 'a\tb\nc')" >/dev/null
check "a finding's tabs and newlines are flattened" "4" "$(tail -1 "${dir}/.swarm/findings.tsv" | awk -F'\t' '{print NF}')"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
