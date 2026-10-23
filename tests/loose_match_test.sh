#!/usr/bin/env bash
# loose_match_test.sh — no loose text match in the shell under bin/ and hooks/. A loose match is a
# grep whose pattern interpolates a shell variable without -F, -x or -w; a [[ ... == *"$var"* ]]
# substring test; or an awk ~ (or !~) whose right side is not a /regex/ literal. Each one has matched
# what it should not: a regex built from an unescaped URL, a check name with a parenthesis, a slug
# ending in -done. A line that is correct says so with a trailing `# loose-match: ok <reason>`.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# loose_match <file>... — one `file:line: shape: text` line per loose match in <file>s.
loose_match() {
  python3 - "$@" <<'EOF'
import re, sys
OK = re.compile(r"#\s*loose-match:\s*ok\s+\S")
GREP = re.compile(r"(?:^|[\s|;&({!`])e?grep\s+")   # fgrep is grep -F
WORD = re.compile(r"""(?:\$'(?:[^'\\]|\\.)*'|'[^']*'|"(?:[^"\\]|\\.)*"|\\.|[^\s|;&()<>'"\\])+""")
ARG = set("efmABCdD")   # short options that take the next word
LONG_ARG = {"--regexp", "--file", "--max-count", "--context", "--after-context", "--before-context",
            "--label", "--binary-files", "--devices", "--directories", "--include", "--exclude",
            "--exclude-dir", "--exclude-from", "--group-separator"}
VAR = re.compile(r"\$[{(\w@*#?]")
GLOB_TEST = re.compile(r"\s(?:==|!=|=)\s+")   # [[ ... == <glob> ]], [[ ... = <glob> ]]
PADDED = re.compile(r"""\*" (?:[^"\\]|\\.)* "\*""")   # *" ${n} "*: whole words of a space-separated list
SEPARATED = re.compile(r""""(?:[^"\\]|\\.)*[/:]"\*""")   # "${dir}/"*: a prefix that ends at a / or :
AWK_RE = re.compile(r"""(?<![=!~"'])!?~\s*(?:"(?:[^"\\]|\\.)*"\s*)*(?=[A-Za-z_$(])""")

def interpolates(word):
    # $'...', '...' and \$ expand nothing; a ' inside "..." is a plain character.
    for q in re.findall(r"""\$'(?:[^'\\]|\\.)*'|'[^']*'|"(?:[^"\\]|\\.)*"|\\.|[^'"\\]+""", word):
        if not q.startswith(("'", "\\", "$'")) and VAR.search(re.sub(r"\\.", "", q)):
            return True
    return False

# shell_scan <line> <quote> — (where a # comment starts or None, the quote still open at the end),
# reading <line> from inside <quote> ("", "'" or '"'). '\'' closes, escapes and reopens: no change.
def shell_scan(line, quote=""):
    i = 0
    while i < len(line):
        c = line[i]
        if quote == "'":
            quote = "" if c == "'" else quote
        elif c == "\\":
            i += 1
        elif quote == '"':
            quote = "" if c == '"' else quote
        elif c in "'\"":
            quote = c
        elif c == "#" and (i == 0 or line[i - 1].isspace()):
            return i, quote
        i += 1
    return None, quote

def grep_loose(rest):
    words, fixed, patterns, from_file = WORD.findall(rest), False, [], False
    i = 0
    while i < len(words):
        w = words[i]
        if w == "--":
            i += 1; break
        if not w.startswith("-") or w == "-":
            break
        if w.startswith("--"):
            name, eq, val = w.partition("=")
            fixed |= name in ("--fixed-strings", "--line-regexp", "--word-regexp")
            if name in LONG_ARG and not eq and i + 1 < len(words): i += 1; val = words[i]
            if name == "--regexp": patterns.append(val)
            from_file |= name == "--file"
        else:
            k = next((j for j, c in enumerate(w[1:]) if c in ARG), None)
            fixed |= bool(set(w[1:] if k is None else w[1:k + 1]) & set("Fxw"))   # not in an attached argument
            if k is not None:
                arg = w[k + 2:] or (words[i + 1] if i + 1 < len(words) else "")
                if not w[k + 2:]: i += 1
                if w[k + 1] == "e": patterns.append(arg)
                from_file |= w[k + 1] == "f"
        i += 1
    if not patterns and not from_file and i < len(words):
        patterns.append(words[i])
    return not fixed and any(interpolates(p) for p in patterns)

def glob_loose(line):
    for m in GLOB_TEST.finditer(line):
        w = WORD.match(line, m.end())
        w = w.group(0) if w else ""
        if (w.startswith("*") or w.endswith("*")) and interpolates(w) and not PADDED.fullmatch(w) and not SEPARATED.fullmatch(w):
            return True
    return False

# logical_lines <path> — (first line number, text) per command: a line ending in \ joins the next,
# unless the \ is in a comment, which bash never continues.
def logical_lines(path):
    start, buf = None, ""
    for n, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
        line = line.rstrip("\n")
        start, buf = start or n, buf + line
        if line.endswith("\\") and not line.endswith("\\\\") and shell_scan(line)[0] is None:
            buf = buf[:-1] + " "; continue
        yield start, buf
        start, buf = None, ""
    if buf: yield start, buf

for path in sys.argv[1:]:
    awk_quote = ""   # the quote an awk program spans lines in
    for n, line in logical_lines(path):
        code, shapes = line.lstrip(), []
        hash_at, _ = shell_scan(line, awk_quote)
        live = line if hash_at is None else line[:hash_at]
        awk_part = live if awk_quote else None
        if not awk_quote and (m := re.search(r"(?:^|[\s|;&({!`])awk\s", live)):
            awk_part = live[m.end():]
        if awk_part is not None:
            awk_quote = shell_scan(awk_part, awk_quote)[1]
            if AWK_RE.search(awk_part): shapes.append("awk ~ built from a variable")
        if code.startswith("#") or OK.search(line):
            continue
        if any(grep_loose(live[m.end():]) for m in GREP.finditer(live)):
            shapes.append("grep pattern from a variable without -F, -x or -w")
        if glob_loose(live):
            shapes.append("glob test on a variable")
        for s in shapes:
            print(f"{path}:{n}: {s}: {code}")
EOF
}

fails=0
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
export CLAUDE_CONFIG_DIR="${tmp}/claude-config"   # under its own root, as every test file

if ! found="$(cd "${REPO}" && loose_match bin/swarm.sh bin/lib/*.sh bin/gh-shim/gh hooks/*.sh)"; then
  echo "FAIL the loose-match scanner itself failed on bin/ or hooks/"; fails=$((fails + 1))
elif [[ -n "${found}" ]]; then
  echo "FAIL a loose match in bin/ or hooks/ (use -F, -x or -w, or end the line with # loose-match: ok <reason>):"
  echo "${found}"; fails=$((fails + 1))
else echo "ok   no loose match in bin/ or hooks/"; fi

cat > "${tmp}/loose.sh" <<'EOF'
grep -qE "^${name}"$'\t' "${list}"
[[ "${urls}" == *"${url}"* ]] && echo hit
awk -v p="$1" '$1 ~ p { print }' "${f}"
grep -F ok "${f}" | grep -q "${name}"
grep -q \
  "${name}" "${f}"
awk -v p="$1" \
  '$1 ~ p { print }' "${f}"
grep -e "${name}" -e done "${f}"
grep -e"${prefix}" "${f}"
grep --regexp="${name}" list.txt
grep "^'${slug}'$" "${f}"
# a comment is never continued \
grep -q "${name}" list.txt
echo hi   # nor a trailing one \
grep -q "${name}" list.txt
# the awk isn't here
awk '{ print "it'\''s" }' "${f}"
awk -v p="$1" '
  $1 ~ p { print }' "${f}"
grep --max-count 1 "${x}" list.txt
grep -d skip "${x}" list.txt
[[ "${a}" = *"${b}"* ]]
[[ "${s}" == *"${a} ${b}"* ]]
[[ "${s}" == "${p}"* ]]
[[ "${s}" == *"${x}" ]]
awk -v p="$1" '$1 ~ "^" p { print }' "${f}"
egrep "${x}" list.txt
awk -v p="$1" "
  \$1 ~ p { print }" "${f}"
EOF
cat > "${tmp}/tight.sh" <<'EOF'
grep -qxF -- "${name}" "${list}"
grep -q '^head moved:' "${f}"
[[ "${urls}" == *"${url}"* ]] && echo hit   # loose-match: ok a fixture
awk -v p="$1" '$1 == p { print }' "${f}"
awk '$1 ~ /^[0-9]+$/ { print }' "${f}"
grep -F ok "${f}" | grep -qF "${name}"
grep -qx \
  "${name}" "${f}"
grep -F -e "${name}" -e done "${f}"
grep -xe"${prefix}" "${f}"
grep -F --regexp="${name}" list.txt
grep -x "^'${slug}'$" "${f}"
grep --max-count "${n}" done "${f}"
grep -m "${n}" done "${f}"
grep -F "${x}" "${f}"   # not grep "${x}" here
[[ " ${list} " == *" ${n} "* ]]
[[ " ${seen} " != *" ${repo}#${n} "* ]]
[[ "${f}" == "${BOARD}/stories/"* ]]
[[ "${PATH}" == "${GH_SHIM}:"* ]]
[[ "${s}" == "${x}" ]]
awk '$1 ~ "^[0-9]+$" { print }' "${f}"
fgrep "${x}" list.txt
EOF
# shellcheck disable=SC2016 # the fixture's ${x} is for the scanner, not this shell
printf 'grep -q "${x}" list.txt\n# \xff\n' > "${tmp}/bytes.sh"
got="$(loose_match "${tmp}/loose.sh")" || got="the scanner failed"
# shellcheck disable=SC2001 # a sed over many lines
got="$(sed 's/^[^:]*:\([0-9]*\): \([^:]*\):.*/\1 \2/' <<< "${got}")"
g='grep pattern from a variable without -F, -x or -w' a='awk ~ built from a variable' b='glob test on a variable'
want="$(printf '%s\n' "1 ${g}" "2 ${b}" "3 ${a}" "4 ${g}" "5 ${g}" "7 ${a}" "9 ${g}" "10 ${g}" "11 ${g}" "12 ${g}" \
  "14 ${g}" "16 ${g}" "20 ${a}" "21 ${g}" "22 ${g}" "23 ${b}" "24 ${b}" "25 ${b}" "26 ${b}" "27 ${a}" "28 ${g}" "30 ${a}")"
if [[ "${got}" == "${want}" ]]; then
  echo "ok   a fixture with each loose shape fails"
else
  echo "FAIL a fixture with each loose shape: want"; echo "${want}"; echo "got"; echo "${got}"; fails=$((fails + 1))
fi
if got="$(loose_match "${tmp}/tight.sh")" && [[ -z "${got}" ]]; then
  echo "ok   the same fixture with -F, -x, == or the opt-out passes"
else
  echo "FAIL the tight fixture still reports:"; echo "${got}"; fails=$((fails + 1))
fi
if got="$(loose_match "${tmp}/bytes.sh")" && [[ "${got}" == *":1: ${g}:"* ]]; then
  echo "ok   a file with a byte that is not UTF-8 is still scanned"
else
  echo "FAIL the scanner failed on a byte that is not UTF-8"; fails=$((fails + 1))
fi

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
