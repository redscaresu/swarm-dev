#!/usr/bin/env bash
# lint_test.sh — scripts/lint's vacuous-test check on a fixture test file that feeds a hook JSON in
# each shape the tests use (a ${2:-default}, a heredoc, a printf format, a word quoted in pieces, an
# optional field, a list's items, a fragment a later command or the same printf completes, a list of
# numbers, a variable, a printf in a $(...), a printf repeated into sed, a JSON heredoc whose string
# holds what is not JSON, a printf '%s' of one word): it passes the file as written, and flags each feeding line, by file and line,
# once that line's JSON is broken (a value cut off and piped straight in or kept in a variable too, and
# a list's items piped with no brackets); #515's stray \} as well, and in a printf format. A line that says "# vacuous-test: ok" is let through. make check runs it over LINT_FILES.
# The fixture holds only JSON that parses, so this file passes the lint too; sed breaks the copies.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINT="${REPO}/scripts/lint"
tmp="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${tmp}"' EXIT
export CLAUDE_CONFIG_DIR="${tmp}/claude-config"   # under its own root, so parallel runs share no ~/.claude
fails=0

check() { # <name> <test...>
  local name="$1"; shift
  if "$@"; then echo "ok   ${name}"; else echo "FAIL ${name}"; fails=$((fails + 1)); fi
}

# lint <file> — the lint on one file: its output in out, its exit code in rc.
lint() { rc=0; out="$(python3 "${LINT}" "$1")" || rc=$?; }

# flags <file> <line> — the lint failed, naming <file>:<line> as invalid JSON.
flags() { [ "${rc}" = 1 ] && grep -q "^$1:$2: vacuous-test: invalid JSON" <<< "${out}"; }

good="${tmp}/good_test.sh"
cat > "${good}" <<'FIXTURE'
#!/usr/bin/env bash
run() { # <cwd> [<input>]
  local input="${2:-{\"hook_event_name\":\"Stop\",\"cwd\":\"$1\"}}"
  printf '%s' "${input}" | "${HOOK}"
}
cat > "${tmp}/in.json" <<JSON
{"hook_event_name": "Stop", "cwd": "${project}"}
JSON
printf '{"cwd":"%s","stop_hook_active":%s}' "${dir}" false | "${HOOK}"
echo '{"result":{"agents":[{"name":"'"${name}"'"}]}}' | "${HOOK}"
echo "[{\"sessionId\":\"s1\",\"status\":\"$1\"${2:+,\"waitingFor\":\"$2\"}}]" > "${tmp}/claude.json"
printf '[%s]' '{"a":1},{"b":2}' | "${HOOK}"
{ printf '{"total_count":1,"check_runs":['; printf '%s' "${runs}"; printf ']}'; } | "${HOOK}"
echo '[1,2]' | "${HOOK}"
printf '%s%s' '{"a":' '1}' | "${HOOK}"
input='[ {"a":1} ]'
echo '[{"a":1},{"b":2}]' | "${HOOK}"
input="$(printf '{"hook_event_name":"Stop","cwd":"%s"}' "${dir}")"
printf '[%s]' "$(printf '{"n":%s},' 1 2 | sed 's/,$//')" | "${HOOK}"
cat <<'JSON' | "${HOOK}"
{"message": "{\"a\":}"}
JSON
echo '[ 1, 2 ]' | "${HOOK}"
printf '%s\n' '{"cwd":"x"}' | "${HOOK}"
FIXTURE

lint "${good}"
check "a test file whose hook inputs all parse passes, in every shape" [ "${rc}|${out}" = "0|" ]

# break_line <line> <sed expression> <name> — a copy of the fixture with <line> broken by the
# expression (a trailing comma, which no JSON parser takes, or a cut), linted; it must be flagged at
# <line>.
break_line() {
  local f="${tmp}/bad${1}_test.sh"
  sed "$1$2" "${good}" > "${f}"
  lint "${f}"
  check "a broken $3 is flagged at its line" flags "${f}" "$1"
}
break_line 3 's/\\"}}"/\\",}}"/' "\${2:-default} hook input"
break_line 7 's/"}$/",}/' "heredoc body"
break_line 9 "s/%s}'/%s,}'/" "printf format"
break_line 10 "s/\"}]}}'/\",}]}}'/" "word quoted in pieces"
break_line 11 's/}}]"/},}]"/' "word with an optional field"
break_line 12 "s/2}'/2,}'/" "list's items"
break_line 14 's/2]/2,]/' "list that starts with a number"
break_line 14 "s/,2]'/,'/" "value cut off and piped straight to the hook"
break_line 16 's/1} ]/1,} ]/' "list with a space after its ["
break_line 16 "s/} ]'/'/" "value cut off in a variable"
break_line 17 "s/'\\[{/'{/; s/}]'/}'/" "list piped with no brackets"
break_line 18 's/"%s"}/"%s",}/' "printf in a \$(...)"
break_line 9 "s/%s}'/%s\\\\}'/" "printf format with a stray \\}"
break_line 18 "s/\"%s\"}'/'/" "printf in a \$(...) cut off in a variable"
break_line 23 's/ 2 ]/ 2, ]/' "list of numbers spaced in its [ ]"
break_line 24 's/"x"}/"x",/' "printf '%s' word cut off"

bad515="${tmp}/bad515_test.sh"
sed '3s/\\"}}"/\\"\\}}"/' "${good}" > "${bad515}"
lint "${bad515}"
check "#515's stray \\} in a hook input's default is flagged" flags "${bad515}" 3

sed '3s/$/ # vacuous-test: ok, bad JSON on purpose/' "${bad515}" > "${tmp}/marked_test.sh"
lint "${tmp}/marked_test.sh"
check "a line that says vacuous-test: ok is let through" [ "${rc}|${out}" = "0|" ]

rc=0; out="$(make -s -C "${REPO}" check LINT_FILES="${bad515}" 2>&1)" || rc=$?
check "make check runs the lint over LINT_FILES, and fails on a finding" grep -q "^${bad515}:3: vacuous-test" <<< "${out}"
rc=0; make -s -C "${REPO}" check LINT_FILES="${good}" > /dev/null 2>&1 || rc=$?
check "and passes when there is none" [ "${rc}" = 0 ]

[ "${fails}" -eq 0 ] || { echo "${fails} check(s) failed"; exit 1; }
