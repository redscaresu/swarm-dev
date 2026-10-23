#!/usr/bin/env bash
# timeouts_test.sh — in bin/ and hooks/, a call that can wait forever names its bound. A command that
# runs `gh run download`, `gh run view ... --log`, `curl` or `herdr ... --wait` (a line ending in \ joins
# the next) must hold `timeout`, `within` (merge.sh's perl alarm), `--max-time` or `--timeout`, or end
# with `# no-timeout: <reason>`. A comment, whole-line or trailing, and text that does not start the
# command (a heredoc naming it in backticks), is not a call.
# shellcheck disable=SC2016,SC1003 # the fixtures are shell text, not expansions
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export HOME="${dir}/home"   # under its own root, so parallel runs share no ~

# untimed <file>... — one `file:line: text` per call with no bound and no opt-out.
untimed() {
  awk '
    function check(text, at) {
      if (text ~ /^[[:space:]]*#/) return
      code = text; sub(/[[:space:]]#.*$/, "", code)
      if (code !~ /(^|[[:space:];&|(=])(gh[[:space:]]+run[[:space:]]+download|gh[[:space:]]+run[[:space:]]+view.*--log|curl([[:space:]]|$)|herdr[^|;]*--wait)/) return
      if (code ~ /(^|[[:space:](])(timeout|within)[[:space:]]|--max-time|--timeout/) return
      if (text ~ /#[[:space:]]*no-timeout:[[:space:]]*[^[:space:]]/) return
      print at ": " text
    }
    FNR == 1 { joined = "" }
    {
      if (joined == "") start = FILENAME ":" FNR
      if ($0 ~ /\\$/) { joined = joined substr($0, 1, length($0) - 1); next }
      check(joined $0, start); joined = ""
    }' "$@"
}

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}
flagged() { # <line>... — how many of the lines untimed flags
  printf '%s\n' "$@" > "${dir}/f.sh"; untimed "${dir}/f.sh" | wc -l | tr -d ' '
}

check "a bare curl is flagged" 1 "$(flagged 'x="$(curl -fsSL "$URL")"')"
check "a bare gh run download is flagged" 1 "$(flagged '  gh run download "$id" --dir out')"
check "a bare gh run view --log-failed is flagged" 1 "$(flagged 'log="$(gh run view "$id" --log-failed)"')"
check "a bare herdr --wait is flagged" 1 "$(flagged 'herdr agent prompt a hi --wait --until idle')"
check "a bare call is flagged once, not once per line, when it continues" 1 "$(flagged 'gh run download "$id" \' '  --dir out')"
check "--max-time passes" 0 "$(flagged 'curl -fsSL --max-time 5 "$URL"')"
check "timeout passes" 0 "$(flagged 'timeout 30 gh run download "$id"')"
check "within passes" 0 "$(flagged 'within 30 gh run view "$id" --log-failed')"
check "--timeout on a continuation line passes" 0 "$(flagged 'herdr agent prompt a hi --wait \' '  --timeout 5000')"
check "the opt-out with a reason passes" 0 "$(flagged 'curl "$URL"  # no-timeout: the caller bounds it')"
check "the opt-out with no reason is flagged" 1 "$(flagged 'curl "$URL"  # no-timeout:')"
check "a comment line is not a call" 0 "$(flagged '# curl "$URL" has no bound')"
check "a comment naming --max-time does not bound the call" 1 "$(flagged 'curl "$URL"  # TODO: add --max-time 5')"
check "a trailing comment naming the call is not a call" 0 "$(flagged 'x=1  # curl is not run here')"
check "a command named in backticks in a heredoc is not a call" 0 "$(flagged 'run \`gh run download <id>\` to fetch it')"

files=()
while IFS= read -r f; do files+=("$f"); done < <(find "${REPO}/bin" "${REPO}/hooks" -type f | sort)
check "bin/ and hooks/ hold files to scan" yes "$( ((${#files[@]} > 0)) && echo yes || echo no)"
found="$(untimed "${files[@]}")" || { echo "FAIL the scan of bin/ and hooks/ failed"; fails=$((fails + 1)); }
check "every call in bin/ and hooks/ names its timeout" "" "${found}"

(( fails == 0 )) || exit 1
