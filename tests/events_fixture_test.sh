#!/usr/bin/env bash
# events_fixture_test.sh — tests/fixtures/events/v0.29.1-sample.tsv, the redacted events.tsv sample the
# readers' tail tests run over, and what makes and uses it. The fixture: every row has 5 tab fields
# and an ISO-Z time, exactly 37 outcomes hold `=` (v0.29.1's cut; v0.29.0's held 34), 400 rows at most,
# every token in redact.py's allowlist classes (redact.py --check), and no /Users path, herdr pane id,
# target slug or URL off https://github.com/o/r (leaks, which reads it without redact.py). Each such
# row planted in a copy turns it red. redact.py over a synthetic log: one stand-in per slug across
# rows and columns, a URL and its #<PR> on o/r, a path on /p, a target slug that is also a source word
# replaced, and the same bytes from a second run. events_tail_helpers.sh: events_project's copies, and
# same_output, which fails on a column-5 read of a tailed copy or an empty first output and passes on
# columns 1-4. The Go words: a word that only a non-test .go file under cmd/ or internal/ uses passes
# --check, and one that only a _test.go or testdata/ file there uses is refused; each check finds its
# word at run time, names it, and fails when there is none. No test reads the live .swarm/events.tsv.
# When a change to bin/, hooks/, scripts/ or the Go source drops the last use of a word the fixture
# holds, --check names it: swap it in the fixture for a zz stand-in.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REDACT="${HERE}/fixtures/events/redact.py"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
[ -d "${tmp}" ] || { echo "mktemp -d failed" >&2; exit 1; }
ROOT="$(cd "${tmp}" && pwd -P)"
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"
# shellcheck source=tests/events_tail_helpers.sh
. "${HERE}/events_tail_helpers.sh"
FX="${EVENTS_FIXTURE}"
fails=0

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}
fails_quietly() { ! "$@" 2>/dev/null; }
# shape <file> — every row has 5 tab fields and an ISO-Z time, and there is a row.
shape() {
  awk -F'\t' 'NF != 5 || $1 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ { bad = 1 }
    END { exit bad || NR == 0 }' "$1"
}
# leaks <file> — each token of <file> that names a real place, pane or story: a /Users/ path, a herdr
# pane id (w<digits and capitals>:p…, w:me, w:0), a URL off https://github.com/o/r, and in column 3 a
# slug-shaped word that is no stand-in (zz<a-z>, <word>-zz<a-z> or backlog).
leaks() {
  grep -oE '/Users/[^[:space:]]*' "$1" || true
  grep -oE '(^|[^[:alnum:]_-])w[0-9A-Z]*:(p[0-9A-Z]+|me|0)([^[:alnum:]_-]|$)' "$1" || true
  grep -oE '[[:alpha:]]+://[^[:space:]]*' "$1" | grep -vE '^https://github\.com/o/r(/|$)' || true
  awk -F'\t' '{ gsub(/[a-z]+:\/\/[^ ]*/, "", $3); n = split($3, w, /[ \/]/); for (i = 1; i <= n; i++) print w[i] }' "$1" \
    | grep -E '^[a-z][a-z0-9]*(-[a-z0-9]+)*$' | grep -vE '^(backlog|([a-z0-9-]+-)?zz[a-z]+)$' || true
}
no_leaks() { [[ -z "$(leaks "$1")" ]]; }
# allowlisted <file> — redact.py --check passes <file> and prints nothing.
allowlisted() { [[ -z "$(python3 "${REDACT}" --check "$1")" ]]; }
# planted <name> <row> — a copy of the fixture with <row> appended.
planted() { cp "${FX}" "${ROOT}/$1.tsv" && printf '%s\n' "$2" >> "${ROOT}/$1.tsv"; }
# flags <file> <token> — redact.py --check fails on <file> and names <token>.
flags() { local out rc=0; out="$(python3 "${REDACT}" --check "$1")" || rc=$?; [[ ${rc} -eq 1 && "${out}" == *": $2"* ]]; }
# red_both <file> <token> — both redact.py --check and leaks name <token> in <file>.
red_both() { flags "$1" "$2" && [[ "$(leaks "$1")" == *"$2"* ]]; }

rows="$(wc -l < "${FX}" | tr -d ' ')"
check "every fixture row has 5 tab fields and an ISO-Z time" shape "${FX}"
check "the fixture holds exactly 37 outcomes with = (v0.29.1's cut)" \
  test "$(awk -F'\t' '$5 ~ /=/' "${FX}" | wc -l | tr -d ' ')" = 37
check "the fixture has at most 400 rows" test "${rows}" -le 400
check "every token of every fixture row is in redact.py's allowlist classes" allowlisted "${FX}"
check "the fixture holds no /Users path, real pane id, real target slug or URL off o/r" no_leaks "${FX}"

T=$'2026-10-01T00:00:00Z\tstory\tzza\twa:pa'
planted slug "${T}"$'\tok (on quokka-ledger)'
planted users "${T}"$'\tstuck: /Users/someone/Work/widgets/.swarm/x.log'
planted url "${T}"$'\tok https://github.com/acme/widgets/pull/42'
planted pane $'2026-10-01T00:00:00Z\tstory\tzza\tw3E:p2\tok'
planted target $'2026-10-01T00:00:00Z\tstory\treconcile\twa:pa\tok'
check "a planted slug-like word outside the source vocabulary turns --check red" flags "${ROOT}/slug.tsv" quokka-ledger
check "a planted /Users path turns --check and leaks red" red_both "${ROOT}/users.tsv" /Users/someone
check "a planted github.com URL off o/r turns --check and leaks red" red_both "${ROOT}/url.tsv" https://github.com/acme
check "a planted real pane id turns --check and leaks red" red_both "${ROOT}/pane.tsv" w3E:p2
check "a planted real target slug, though a source word, turns --check and leaks red" red_both "${ROOT}/target.tsv" reconcile

# The Go words. The file lists are drawn here, not by redact.py's vocabulary(), and the words by its
# tokenizer. A candidate is letters only and no zz stand-in, so --check keeps or refuses it by the
# vocabulary alone.
REPO="$(cd "${HERE}/.." && pwd)"
# WORDS_PY <redact dir> <file>... — each word token of the files, one per line.
WORDS_PY='import sys; sys.path.insert(0, sys.argv[1]); from redact import TOKEN
for p in sys.argv[2:]:
    with open(p, encoding="utf-8", errors="replace") as fh:
        print("\n".join(m.group() for m in TOKEN.finditer(fh.read()) if m.lastgroup == "word"))'
# files_words <find args...> — the sorted word set of the files find selects from the repo root.
files_words() {
  (cd "${REPO}" || exit 1 && find "$@" -exec python3 -B -c "${WORDS_PY}" "${HERE}/fixtures/events" {} +) \
    | grep -v '^$' | LC_ALL=C sort -u
}
go_src="$(files_words cmd internal \( -name testdata -o -name '.*' \) -prune -o -type f -name '*.go' ! -name '*_test.go')"
go_test="$(files_words cmd internal -type f \( -name '*_test.go' -o -path '*/testdata/*' \))"
plugin="$(files_words bin hooks scripts \( -name '.*' -o -name __pycache__ \) -prune -o -type f ! -name '*.pyc')"
# first_plain <set> <minus>... — the first letters-only word of <set> that is no zz stand-in and in none of <minus>.
first_plain() {
  local set="$1" m; shift
  for m in "$@"; do set="$(LC_ALL=C comm -23 <(printf '%s\n' "${set}") <(printf '%s\n' "${m}"))"; done
  grep -E '^[A-Za-z]+$' <<< "${set}" | grep -vE '^zz[a-z]+$' | sed -n 1p || true
}
go_only="$(first_plain "${go_src}" "${plugin}")"
test_only="$(first_plain "${go_test}" "${plugin}" "${go_src}")"
planted go-word "${T}"$'\tok '"${go_only}"
planted test-word "${T}"$'\tok '"${test_only}"
go_word_kept() {
  [[ -n "${go_only}" ]] || { echo "  no letters-only word is in a non-test .go file under cmd/ or internal/ and in no file under bin/, hooks/ or scripts/"; return 1; }
  allowlisted "${ROOT}/go-word.tsv"
}
test_word_refused() {
  [[ -n "${test_only}" ]] || { echo "  no letters-only word is only in a _test.go or testdata/ file under cmd/ or internal/"; return 1; }
  flags "${ROOT}/test-word.tsv" "${test_only}"
}
check "a word only Go source uses (${go_only:-none found}) passes --check" go_word_kept
check "a word only Go tests or testdata use (${test_only:-none found}) turns --check red" test_word_refused

# redact.py over a synthetic log: reconcile, a target in row 4, is a source word, which row 5's
# outcome keeps; the last row is past the cut, and its `=` would put it in the sample before it.
S="${ROOT}/synthetic"; mkdir -p "${S}"
printf '%s\n' $'2026-01-01T00:00:00Z\tstory\tquokka-ledger\tw7Q:p3\tok' \
  $'2026-01-01T00:00:01Z\tstacked\twombat-sails\tw7Q:p4\tok (on quokka-ledger)' \
  $'2026-01-01T00:00:02Z\tmerge\thttps://github.com/acme/widgets/pull/42\tw7Q:p3\tok #42 merged' \
  $'2026-01-01T00:00:03Z\tincident\treconcile\t-\tstuck: /Users/someone/Work/widgets/.swarm/x.log rc=1' \
  $'2026-01-01T00:00:04Z\tclose\tquokka-ledger\tw7Q:p3\tok reconcile' \
  $'2026-03-01T00:00:00Z\tstory\tlate-otter\t-\theld rc=2' > "${S}/events.tsv"
python3 "${REDACT}" "${S}/events.tsv" 2026-02-01T00:00:00Z > "${S}/a.tsv"
python3 "${REDACT}" "${S}/events.tsv" 2026-02-01T00:00:00Z > "${S}/b.tsv"
row() { sed -n "$1p" "${S}/a.tsv" | cut -f"$2"; }
check "redact.py gives a slug one stand-in in every row, as target and in an outcome" \
  test "$(row 1 3)|$(row 2 5)|$(row 5 3)|$(row 2 3)" = "zza|ok (on zza)|zza|zzb"
check "redact.py moves a URL to o/r, and its #<PR> to the same number" \
  test "$(row 3 3)|$(row 3 5)" = "https://github.com/o/r/pull/1|ok #1 merged"
check "redact.py swaps a path for /p" test "$(row 4 5)" = "stuck: /p/a rc=1"
check "redact.py swaps a target slug that is also a source word, which an outcome keeps" \
  test "$(row 4 3)|$(row 5 5)" = "zzc|ok reconcile"
check "redact.py gives pane ids stand-ins that keep their workspace" \
  test "$(row 1 4)|$(row 2 4)|$(row 3 4)|$(row 4 4)" = "wa:pa|wa:pb|wa:pa|-"
check "redact.py keeps the rows before the cut, times and commands as they were" \
  test "$(cut -f1,2 "${S}/a.tsv" | tr '\t\n' ' |')" = \
  "2026-01-01T00:00:00Z story|2026-01-01T00:00:01Z stacked|2026-01-01T00:00:02Z merge|2026-01-01T00:00:03Z incident|2026-01-01T00:00:04Z close|"
check "a second run of redact.py writes the same bytes" cmp -s "${S}/a.tsv" "${S}/b.tsv"

P="${ROOT}/plain/proj"; Q="${ROOT}/tailed/proj"
events_project "${P}" "${FX}"
events_project "${Q}" "${FX}" " k=v"
check "events_project copies the events file as it is, with no tail" cmp -s "${FX}" "${P}/.swarm/events.tsv"
check "events_project appends the tail to column 5 of every row" \
  test "$(awk -F'\t' 'NF == 5 && / k=v$/' "${Q}/.swarm/events.tsv" | wc -l | tr -d ' ')" = "${rows}"
check "same_output fails for a command printing column 5 of a project and its tailed copy" \
  fails_quietly same_output "${P}" "${Q}" cut -f5 .swarm/events.tsv
check "same_output passes for one printing columns 1-4" same_output "${P}" "${Q}" cut -f1-4 .swarm/events.tsv
check "same_output fails when the first output is empty" fails_quietly same_output "${P}" "${P}" true

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
