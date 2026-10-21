#!/usr/bin/env bash
# log_finding_test.sh — `swarm.sh log-finding`: the row it appends (kind, PR, text, outcome, reviewer,
# and a declined row's reason), and every argument it refuses. Moved here from lessons_test.sh when
# lessons went; outcomes' recurring block is in recurring_kinds_test.sh.
set -euo pipefail

SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${dir}" ] || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, so parallel runs share no ~/.claude
git -C "${dir}" init -q
mkdir -p "${dir}/.claude/swarm"
: > "${dir}/.claude/swarm/config"
fails=0
sw() { (cd "${dir}" && env -u SWARM_PROJECT bash "${SWARM}" "$@" 2>&1); }
has() { if grep -qF -- "$1" <<< "$2"; then echo yes; else echo "no, got: $2"; fi; }
check() { # <name> <want> <got>
  if [[ "$3" == "$2" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

check "a kind must be kebab-case" "yes" "$(has "must be short kebab-case" "$(sw log-finding 'Vacuous Test' o/r#1 x || true)")"

# A fixed finding is logged as fixed; a declined one with its outcome.
sw log-finding denylist o/r#4 "a scrub that lists what to remove" >/dev/null
check "a fixed finding is logged as fixed" "fixed" "$(grep -m1 denylist "${dir}/.swarm/findings.tsv" | cut -f5)"
for pr in o/r#90 o/r#91 o/r#92; do sw log-finding --declined out-of-scope edge-case "${pr}" "an edge case the story leaves out" >/dev/null; done
check "a declined finding is logged as declined" "edge-case	declined" "$(tail -1 "${dir}/.swarm/findings.tsv" | cut -f2,5)"

# The reviewer that raised a finding is its sixth field; the flags go before the kind, in either order.
F="${dir}/.swarm/findings.tsv"
# logged <log-finding args...> — fields 5 and 6 of the one row it appended, or why there is none.
logged() {
  local n; n="$(wc -l < "${F}")"
  if ! sw log-finding "$@" >/dev/null; then echo "exited non-zero"; return; fi
  if [[ "$(wc -l < "${F}")" -ne $((n + 1)) ]]; then echo "appended $(($(wc -l < "${F}") - n)) rows"; return; fi
  tail -1 "${F}" | cut -f5,6
}
# refused <log-finding args...> — "refused" when it exits non-zero and appends nothing.
refused() {
  local n; n="$(wc -l < "${F}")"
  if sw log-finding "$@" >/dev/null; then echo "exited 0"; elif [[ "$(wc -l < "${F}")" -ne "${n}" ]]; then echo "appended a row"; else echo refused; fi
}
check "--reviewer is logged after the outcome" "fixed	codex" "$(logged --reviewer codex rev-kind o/r#93 t)"
check "--declined before --reviewer" "declined	code-review" "$(logged --declined wrong --reviewer code-review rev-kind o/r#93 t)"
check "--reviewer before --declined" "declined	code-review" "$(logged --reviewer code-review --declined wrong rev-kind o/r#93 t)"
for who in skeptic critic split-critic; do
  check "--reviewer ${who} is logged in field 6" "fixed	${who}" "$(logged --reviewer "${who}" rev-kind o/r#93 t)"
done
# An escaped defect is no finding review raised: its outcome is escaped, and it is never declined.
check "--reviewer escaped is logged in field 6, with outcome escaped" "escaped	escaped" "$(logged --reviewer escaped rev-kind o/r#93 t)"
check "an escaped split-gap (a gap the split critic missed) is logged as kind split-gap, outcome escaped" "split-gap	escaped	escaped" \
  "$(logged --reviewer escaped split-gap o/r#95 t >/dev/null; tail -1 "${F}" | cut -f2,5,6)"
check "--declined with --reviewer escaped is refused" "refused" "$(refused --declined nit --reviewer escaped rev-kind o/r#93 t)"
check "--declined with no reason and --reviewer escaped says escaped is never declined" "refused|yes" \
  "$(refused --declined --reviewer escaped rev-kind o/r#93 t)|$(has "never declined" "$(sw log-finding --declined --reviewer escaped rev-kind o/r#93 t || true)")"
# A declined row carries its reason as a 7th field; a missing or unknown reason is refused, naming the three.
check "--declined nit appends a 7-field row ending declined, codex, nit" "7|declined	codex	nit" \
  "$(sw log-finding --declined nit --reviewer codex k o/r#94 t >/dev/null; tail -1 "${F}" | awk -F'\t' '{print NF}')|$(tail -1 "${F}" | cut -f5-)"
check "a fixed row stays at 6 fields" "6" "$(sw log-finding --reviewer codex k o/r#94 t >/dev/null; tail -1 "${F}" | awk -F'\t' '{print NF}')"
REASONS="--declined needs a reason, one of: out-of-scope nit wrong"
check "--declined with no reason is refused, naming the reasons" "refused|yes" \
  "$(refused --declined --reviewer codex k o/r#94 t)|$(has "${REASONS}" "$(sw log-finding --declined --reviewer codex k o/r#94 t || true)")"
check "--declined maybe is refused, naming the reasons" "refused|yes" \
  "$(refused --declined maybe k o/r#94 t)|$(has "${REASONS}" "$(sw log-finding --declined maybe k o/r#94 t || true)")"
check "no --reviewer is logged as unknown" "fixed	unknown" "$(logged rev-kind o/r#93 t)"
check "a reviewer not in the list is refused" "refused" "$(refused --reviewer bot rev-kind o/r#93 t)"
check "a bare trailing --reviewer is refused" "refused" "$(refused --reviewer)"
check "an empty --reviewer is refused" "refused" "$(refused --reviewer '' k o/r#1 t)"
check "unknown is not a --reviewer value" "refused" "$(refused --reviewer unknown k o/r#1 t)"
check "two reviewers in one value are refused" "refused" "$(refused --reviewer 'conductor lead' k o/r#1 t)"
check "the refusal lists the reviewers, not unknown" "yes" \
  "$(has "must be one of: codex fallback code-review ci conductor lead skeptic critic split-critic escaped" "$(sw log-finding --reviewer unknown k o/r#1 t || true)")"


# Unquoted text is kept whole, and a carriage return cannot split a row.
sw log-finding unquoted o/r#30 several words of text >/dev/null
check "unquoted text is kept whole" "several words of text" "$(tail -1 "${dir}/.swarm/findings.tsv" | cut -f4)"
sw log-finding cr-test o/r#31 "$(printf 'a\rb\r')" >/dev/null
check "a carriage return is flattened" "0" "$(grep -c $'\r' "${dir}/.swarm/findings.tsv" || true)"

# A PR must be a URL or owner/repo#N; shorthand that could double-count is refused.
check "a shorthand PR is refused" "yes" "$(has "must be a PR URL or owner/repo#N" "$(sw log-finding k '#12' x || true)")"

# A PR URL with junk after the number is refused, not counted as a different PR.
check "a malformed PR URL is refused" "yes" "$(has "must be a PR URL" "$(sw log-finding k https://github.com/o/r/pull/1x2 x || true)")"
check "a blank finding is refused with the usage" "yes" "$(has "usage: swarm.sh log-finding" "$(sw log-finding k o/r#1 '   ' || true)")"
check "a whitespace-only finding is refused" "yes" "$(has "usage: swarm.sh log-finding" "$(sw log-finding k o/r#1 "$(printf '\t\n')" || true)")"
check "an overlong kind is refused" "yes" "$(has "32 characters at most" "$(sw log-finding "$(printf 'a%.0s' {1..40})" o/r#1 x || true)")"

# Tabs and newlines in a finding cannot break the log's columns.
sw log-finding tab-test o/r#7 "$(printf 'a\tb\nc')" >/dev/null
check "a finding's tabs and newlines are flattened" "6" "$(tail -1 "${dir}/.swarm/findings.tsv" | awk -F'\t' '{print NF}')"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
