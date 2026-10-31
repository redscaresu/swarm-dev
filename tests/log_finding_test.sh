#!/usr/bin/env bash
# log_finding_test.sh — `swarm.sh log-finding`: the row it appends (kind, PR, text, outcome, reviewer,
# a declined row's reason, the round and a declined row's --because), and every argument it refuses. Moved here from lessons_test.sh when
# lessons went; outcomes' recurring block is in recurring_kinds_test.sh.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

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
# A declined row carries its reason as a 7th field; a missing or unknown reason is refused, naming the four.
check "--declined nit appends a 7-field row ending declined, codex, nit" "7|declined	codex	nit" \
  "$(sw log-finding --declined nit --reviewer codex k o/r#94 t >/dev/null; tail -1 "${F}" | awk -F'\t' '{print NF}')|$(tail -1 "${F}" | cut -f5-)"
check "a fixed row stays at 6 fields" "6" "$(sw log-finding --reviewer codex k o/r#94 t >/dev/null; tail -1 "${F}" | awk -F'\t' '{print NF}')"
# --round <n> is an 8th field, after the reason (empty on a fixed row); a row without it still reads,
# as round unknown.
check "--round 2 on a fixed row appends 8 fields: an empty reason, then 2" "8|fixed	codex		2" \
  "$(sw log-finding --reviewer codex --round 2 k o/r#94 t >/dev/null; tail -1 "${F}" | awk -F'\t' '{print NF}')|$(tail -1 "${F}" | cut -f5-)"
check "--round 1 after --declined nit keeps the reason in field 7" "declined	codex	nit	1" \
  "$(sw log-finding --round 1 --declined nit --reviewer codex k o/r#94 t >/dev/null; tail -1 "${F}" | cut -f5-)"
check "a row without --round and one with it both read, the first as round unknown" "('fixed', '')|('fixed', '2')" \
  "$(SWARM_FINDING_REVIEWERS=codex python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from report import finding_rows
print("|".join(str((f[4], f[7])) for f in finding_rows(sys.argv[2], width=8) if f[2] == "o/r#94" and f[4] == "fixed"))' \
    "$(dirname "${SWARM}")/lib" "${F}")"
for r in "" x -1 1.5 1000; do
  check "--round '${r}' is refused" "refused" "$(refused --round "${r}" k o/r#94 t)"
done
check "the refusal says what a round is" "yes" "$(has "--round needs the review round" "$(sw log-finding --round x k o/r#94 t || true)")"
check "--declined deferred --round 3 keeps deferred in field 7 and 3 in field 8" "deferred|3" \
  "$(sw log-finding --declined deferred --reviewer codex --round 3 k o/r#94 t >/dev/null; tail -1 "${F}" | awk -F'\t' '{print $7 "|" $8}')"
# --because "<the builder's reason>" is a 9th field on a declined row, after an empty round when there
# is none; without --declined it is refused.
check "--because on a declined row with --round appends 9 fields, the 9th its text" "9|covered by the retry test" \
  "$(sw log-finding --declined nit --because 'covered by the retry test' --reviewer codex --round 2 k o/r#94 t >/dev/null; tail -1 "${F}" | awk -F'\t' '{print NF "|" $9}')"
check "--because with --declined and no --round keeps the 9th field the 9th, after an empty round" "9|nit||the builder says so" \
  "$(sw log-finding --because 'the builder says so' --declined nit k o/r#94 t >/dev/null; tail -1 "${F}" | awk -F'\t' '{print NF "|" $7 "|" $8 "|" $9}')"
check "--because without --declined is refused" "refused" "$(refused --because 'a reason' --reviewer codex k o/r#94 t)"
check "--because with --filed is refused" "refused" "$(refused --filed --because 'a reason' k o/r#94 t)"
check "the refusal says --because needs --declined" "yes" "$(has "it needs --declined" "$(sw log-finding --because x k o/r#94 t || true)")"
check "a blank --because is refused" "refused" "$(refused --declined nit --because '  ' k o/r#94 t)"
# Tabs and newlines in --because are flattened and it is cut at 200, so the row stays 9 parseable fields.
long="$(printf 'b%.0s' {1..250})"
sw log-finding --declined wrong --because "$(printf 'one\ttwo\nthree\r')${long}" --round 1 k o/r#94 t >/dev/null
check "a --because with tabs, newlines and 250 more characters stores 9 fields, flattened and cut at 200" \
  "9|$(printf 'one two three %s' "${long:0:186}")" "$(tail -1 "${F}" | awk -F'\t' '{print NF "|" $9}')"
# A 9-field row reads exactly as its 8-field twin: finding_rows and out_of_scope_findings stop at 8.
check "finding_rows reads a 9-field row as its 8-field twin" "True|('fixed', 'declined')" \
  "$(SWARM_FINDING_REVIEWERS=codex python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from report import finding_rows
a = sys.argv[2].split("\t"); b = a + ["the builder says so"]
open(sys.argv[3] + "/8.tsv", "w").write("\t".join(a) + "\n"); open(sys.argv[3] + "/9.tsv", "w").write("\t".join(b) + "\n")
r8, r9 = (finding_rows(sys.argv[3] + p, width=w) for p, w in (("/8.tsv", 8), ("/9.tsv", 8)))
print(str(len(a) == 8 and r8 == r9 and len(r8) == 1 and finding_rows(sys.argv[3] + "/8.tsv") == finding_rows(sys.argv[3] + "/9.tsv")) + "|" + str(("fixed", r9[0][4])))' \
    "$(dirname "${SWARM}")/lib" "$(date +%F)"$'\tk\to/r#96\tt\tdeclined\tcodex\tnit\t2' "${dir}")"
# oosf <dir> — out_of_scope_findings for a project at <dir>, with an empty board.
oosf() {
  # shellcheck disable=SC1090,SC1091 # the library, from the repo under test
  PROJECT_DIR="$1" BOARD="$1/board" bash -c '. "$1/reports.sh"; out_of_scope_findings' _ "$(dirname "${SWARM}")/lib"
}
for w in 8 9; do
  mkdir -p "${dir}/p${w}/.swarm" "${dir}/p${w}/board/stories"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "$(date +%F)" k o/r#97 "an edge case" declined codex out-of-scope 2 > "${dir}/p${w}/.swarm/findings.tsv"
  [[ "${w}" == 8 ]] || printf '\tthe builder says so' >> "${dir}/p${w}/.swarm/findings.tsv"
  echo >> "${dir}/p${w}/.swarm/findings.tsv"
done
check "out_of_scope_findings reads a 9-field row as its 8-field twin" "out-of-scope	$(date +%F) k o/r#97: an edge case|same" \
  "$(oosf "${dir}/p9")|$([[ "$(oosf "${dir}/p9")" == "$(oosf "${dir}/p8")" ]] && echo same || echo differ)"
REASONS="--declined needs a reason, one of: out-of-scope nit wrong deferred"
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
