#!/usr/bin/env bash
# loose_match_test.sh — no loose text match in the shell under bin/ and hooks/. A loose match is a
# grep whose pattern interpolates a shell variable without -F, -x or -w; a [[ ... == <glob> ]] whose
# glob is built from a variable; an awk ~ (or !~) whose right side is a variable, or a /regex/
# with a shell variable spliced in; or a [[ ... =~ <regex> ]] whose regex expands a variable outside
# quotes. Each one has matched what it should not: a regex built from an unescaped URL, a check name
# with a parenthesis, a slug ending in -done. A line that is correct says so with a trailing `# loose-match: ok <reason>`.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# loose_match <file>... — one `file:line: shape: text` line per loose match in <file>s.
loose_match() {
  python3 - "$@" <<'EOF'
import re, sys
OK = re.compile(r"#\s*loose-match:\s*ok\s+\S")
GREP = re.compile(r"(?:^|[\s|;&({!`])e?grep\s+")   # fgrep is grep -F
WORD = re.compile(r"""(?:\$'(?:[^'\\]|\\.)*'|'[^']*'|"(?:[^"\\]|\\.)*"|\\.|[^\s|;&()<>'"\\])+""")
QUOTED = re.compile(r"""\$'(?:[^'\\]|\\.)*'|'[^']*'|"(?:[^"\\]|\\.)*"|\$\{[^}]*\}|\\.""")
ARG = set("efmABCdD")   # short options that take the next word
LONG_ARG = {"--regexp", "--file", "--max-count", "--context", "--after-context", "--before-context",
            "--label", "--binary-files", "--devices", "--directories", "--include", "--exclude",
            "--exclude-dir", "--exclude-from", "--group-separator"}
VAR = re.compile(r"\$[{(\w@*#?]")
GLOB_TEST = re.compile(r"\s(?:==|!=|=)\s+")   # [[ ... == <glob> ]], [[ ... = <glob> ]]
PADDED = re.compile(r"""\*" (?:[^"\\]|\\.)* "\*""")   # *" ${n} "*: whole words of a space-separated list
SEPARATED = re.compile(r""""(?:[^"\\]|\\.)*[/:]"\*""")   # "${dir}/"*: a prefix that ends at a / or :
HEREDOC = re.compile(r"""<<-?[ \t]*\\?(["']?)([A-Za-z_]\w*)\1""")
AWK = re.compile(r"(?:^|[\s|;&({!`])awk\s")
SHELL_VAR = re.compile(r"\$(?:\{[^}]*\}|\([^)]*\)|\w+|[@*#?!$-])")
AWK_RE = re.compile(r"""(?<![=!~])!?~\s*(?:(?:""|//)\s*)*(?=[A-Za-z_$(@])""")   # ~ p, ~ $2, ~ "^" p
REGEX_BEFORE = set("~(,{;!&|}") | {""}   # what a /regex/ literal follows in awk, not a division
REGEX_TEST = re.compile(r"\s=~\s+")   # [[ ... =~ <regex> ]]
REGEX_WORD = re.compile(r"""(?:\$'(?:[^'\\]|\\.)*'|'[^']*'|"(?:[^"\\]|\\.)*"|\$\{[^}]*\}|\\.|[^\s'"\\])+""")   # ( and | too
STRINGS = re.compile(r"""\$'(?:[^'\\]|\\.)*'|'[^']*'|"(?:[^"\\]|\\.)*"|\\.""")

def interpolates(word):
    # $'...', '...' and \$ expand nothing; a ' inside "..." is a plain character.
    for q in re.findall(r"""\$'(?:[^'\\]|\\.)*'|'[^']*'|"(?:[^"\\]|\\.)*"|\\.|[^'"\\]+""", word):
        if not q.startswith(("'", "\\", "$'")) and VAR.search(re.sub(r"\\.", "", q)):
            return True
    return False

# shell_scan <line> <stack> — (where a # comment starts or None, what is still open at the end, the
# heredoc delimiters the line opens). What is open is a tuple of ' " ( { for quotes, $( or ( and ${,
# starting from <stack>. A $( or ${ opens a context of its own, so a quote in it does not close the
# one outside. '\'' closes, escapes and reopens.
def shell_scan(line, stack=()):
    st, docs, i = list(stack), [], 0
    while i < len(line):
        c, top = line[i], (st[-1] if st else "")
        if top == "'":
            if c == "'": st.pop()
        elif c == "\\":
            i += 1
        elif c == "$" and line[i + 1:i + 2] in ("(", "{"):
            i += 1; st.append(line[i])
        elif top == '"':
            if c == '"': st.pop()
        elif c == "<" and not line.startswith("<<<", i) and (m := HEREDOC.match(line, i)):
            docs.append(m.group(2)); i = m.end(); continue
        elif c in "'\"(":
            st.append(c)
        elif (c, top) in ((")", "("), ("}", "{")):
            st.pop()
        elif c == "#" and top != "{" and (i == 0 or line[i - 1].isspace()):
            return i, tuple(st), docs
        i += 1
    return None, tuple(st), docs

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

# glob_loose <line> — a [[ ... == <word> ]] whose <word> is built from a variable and has a * outside
# its quotes, anywhere: *"${x}"*, "${p}"*, "${p}"*"${q}".
def glob_loose(line):
    for m in GLOB_TEST.finditer(line):
        w = WORD.match(line, m.end())
        w = w.group(0) if w else ""
        if "*" in QUOTED.sub("", w) and interpolates(w) and not PADDED.fullmatch(w) and not SEPARATED.fullmatch(w):
            return True
    return False

# regex_loose <line> — a [[ ... =~ <regex> ]] whose <regex> expands a variable outside quotes: ^${slug}-,
# ${re}. Bash matches a quoted part, ^"${slug}"-, as plain text.
def regex_loose(line):
    for m in REGEX_TEST.finditer(line):
        w = REGEX_WORD.match(line, m.end())
        if w and VAR.search(STRINGS.sub("", w.group(0))):
            return True
    return False

def skip_blanks(s, i):
    while i < len(s) and s[i] in " \t": i += 1
    return i

# program_rest <text> <quote> — (the awk program in <text> up to its closing <quote>, whether it closed).
def program_rest(s, q):
    out, i = [], 0
    while i < len(s):
        if q == "'" and s.startswith("'\\''", i):
            out.append("'"); i += 4; continue
        if q == '"' and s[i] == "\\":
            out.append(s[i:i + 2]); i += 2; continue
        if s[i] == q:
            return "".join(out), True
        out.append(s[i]); i += 1
    return "".join(out), False

# awk_program <words after awk> — (its program's quote, the program on this line, whether it closed),
# or None for a program from -f or not quoted. -F, -v and their values are not the program.
def awk_program(rest):
    i = skip_blanks(rest, 0)
    while rest.startswith("-", i):
        w = WORD.match(rest, i).group(0)
        i = skip_blanks(rest, i + len(w))
        if w == "--": break
        if w.startswith("-f"): return None
        if w in ("-F", "-v") and (v := WORD.match(rest, i)): i = skip_blanks(rest, v.end())
    q = rest[i:i + 1]
    return (q, *program_rest(rest[i + 1:], q)) if q in ("'", '"') else None

# unshell <program> — a "..." awk program as awk reads it: \$ and \" unescaped, each shell expansion
# marked @V@.
def unshell(text):
    out, i = [], 0
    while i < len(text):
        if text[i] == "\\" and text[i + 1:i + 2] in ('$', '"', '\\', '`'):
            out.append(text[i + 1]); i += 2; continue
        if text[i] == "$" and (m := SHELL_VAR.match(text, i)):
            out.append("@V@"); i = m.end(); continue
        out.append(text[i]); i += 1
    return "".join(out)

# awk_loose <program> — (whether a match in it is built from a variable, its # comment): a ~ whose
# right side is a variable, or a shell variable in a /regex/ or in a string after ~. Strings and regex
# literals are read as awk reads them, so a ~ or # in one is not code.
def awk_loose(text):
    out, loose, prev, i = [], False, "", 0
    while i < len(text):
        c = text[i]
        if c == "#":
            return loose or bool(AWK_RE.search("".join(out))), text[i:]
        if c == '"' or (c == "/" and prev in REGEX_BEFORE):
            j = i + 1
            while j < len(text) and text[j] != c:
                if text[j] == "\\":
                    j += 1
                elif c == "/" and text[j] == "[":   # a bracket expression may hold a /
                    k = j + 1 + (text[j + 1:j + 2] == "^"); k += text[k:k + 1] == "]"
                    j = text.find("]", k) if text.find("]", k) >= 0 else len(text)
                j += 1
            loose |= "@V@" in text[i:j + 1] and (c == "/" or prev == "~")
            out.append(c + c); prev = c; i = j + 1; continue
        out.append(c)
        if not c.isspace(): prev = c
        i += 1
    return loose or bool(AWK_RE.search("".join(out))), ""

# logical_lines <path> — (first line number, text, what is open at its start) per command: a line
# ending in \ joins the next, unless the \ is in a comment or a '...' string, which bash never
# continues. Quotes carry from line to line; a heredoc's body is data and is skipped.
def logical_lines(path):
    lines, stack, i = open(path, encoding="utf-8", errors="replace").read().split("\n"), (), 0
    while i < len(lines):
        start, start_stack, buf, docs = i + 1, stack, "", []
        while True:
            line = lines[i]; i += 1
            hash_at, stack, d = shell_scan(line, stack)
            docs += d
            if line.endswith("\\") and not line.endswith("\\\\") and hash_at is None \
                    and stack[-1:] != ("'",) and i < len(lines):
                buf += line[:-1] + " "; continue
            buf += line; break
        yield start, buf, start_stack
        for d in docs:
            while i < len(lines) and lines[i].strip() != d: i += 1
            i += 1

for path in sys.argv[1:]:
    awk_q = ""   # the quote of an awk program still open from the line before
    for n, line, stack in logical_lines(path):
        hash_at, _, _ = shell_scan(line, stack)
        live = line if hash_at is None else line[:hash_at]
        # The opt-out counts only in a comment: the shell's, or awk's in a program.
        note, shapes, prog, q = line[hash_at:] if hash_at is not None else "", [], None, awk_q
        if awk_q:
            prog, closed = program_rest(line, awk_q)
            awk_q = "" if closed else awk_q
        elif (m := AWK.search(live)) and (got := awk_program(live[m.end():])):
            q, prog, closed = got
            awk_q = "" if closed else q
        if prog is not None:
            loose, comment = awk_loose(unshell(prog) if q == '"' else prog)
            note = note or comment
            if loose: shapes.append("awk ~ built from a variable")
        if OK.search(note):
            continue
        if any(grep_loose(live[m.end():]) for m in GREP.finditer(live)):
            shapes.append("grep pattern from a variable without -F, -x or -w")
        if glob_loose(live):
            shapes.append("glob test on a variable")
        if regex_loose(live):
            shapes.append("=~ regex from a variable outside quotes")
        for s in shapes:
            print(f"{path}:{n}: {s}: {line.lstrip()}")
EOF
}

# shell_files <repo> — the shell files git tracks under <repo>'s bin/ and hooks/: *.sh, or a first
# line that is a sh or bash shebang.
shell_files() {
  local f
  git -C "$1" ls-files bin hooks | while IFS= read -r f; do
    case "${f}" in
      *.sh) echo "${f}" ;;
      *) if head -n 1 "$1/${f}" | grep -qE '^#!.*[/ ](ba)?sh([[:space:]]|$)'; then echo "${f}"; fi ;;
    esac
  done
}

fails=0
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
export CLAUDE_CONFIG_DIR="${tmp}/claude-config"   # under its own root, as every test file

scan=(); while IFS= read -r f; do scan+=("${f}"); done < <(shell_files "${REPO}")
if [[ ${#scan[@]} -eq 0 ]]; then
  echo "FAIL git lists no shell file under bin/ or hooks/"; fails=$((fails + 1))
elif ! found="$(cd "${REPO}" && loose_match "${scan[@]}")"; then
  echo "FAIL the loose-match scanner itself failed on bin/ or hooks/"; fails=$((fails + 1))
elif [[ -n "${found}" ]]; then
  echo "FAIL a loose match in bin/ or hooks/ (use -F, -x or -w, quote the variable in a =~ regex, or end the line with # loose-match: ok <reason>):"
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
new="$(ps -Ao pid=,ppid= | awk -v have=" ${out} " 'index(have, " " $2 " ") { print $1 }')"
echo "it's done"
n="$(awk -v k="it's" '$1 == k' "${f}")"
awk -v p="$1" '
  $1 ~ p { print }' "${f}"
grep "${slug}" list.txt; echo '# loose-match: ok this is data'
awk -v p="$1" "\$1 ~ p { print }" "${f}"
awk "\$1 ~ /${x}/" "${f}"
awk "/${x}/" "${f}"
awk -F'"' -v p="$1" '$2 ~ p' "${f}"
[[ "${s}" == "${p}"*"${q}" ]]
msg='multi
# '; grep "${d}" list.txt
awk -v p="$1" '{ s = "it'\''s" } $1 ~ p' "${f}"
[[ $x =~ ^${slug}- ]]
[[ $x =~ ${re} ]]
[[ -n "${v}" && "${v}" =~ ^(a|${b})$ ]]
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
awk '{ print "status ~ pending" }' "${f}"
awk -v p="$1" '
  $1 ~ p { print }   # loose-match: ok a fixture
' "${f}"
awk '$0 ~ /foo ~ bar/ { print }' "${f}"
msg='multi
line'; grep "${d}" list.txt   # loose-match: ok a fixture
cat <<NOTE
grep "${x}" is text in a heredoc, and it's not code
NOTE
[[ $x =~ ${re} ]]   # loose-match: ok a fixture
[[ "${x}" =~ ^"${slug}"-[0-9]+$ ]]
EOF
# shellcheck disable=SC2016 # the fixture's ${x} is for the scanner, not this shell
printf 'grep -q "${x}" list.txt\n# \xff\n' > "${tmp}/bytes.sh"
got="$(loose_match "${tmp}/loose.sh")" || got="the scanner failed"
# shellcheck disable=SC2001 # a sed over many lines
got="$(sed 's/^[^:]*:\([0-9]*\): \([^:]*\):.*/\1 \2/' <<< "${got}")"
g='grep pattern from a variable without -F, -x or -w' a='awk ~ built from a variable' b='glob test on a variable'
r='=~ regex from a variable outside quotes'
want="$(printf '%s\n' "1 ${g}" "2 ${b}" "3 ${a}" "4 ${g}" "5 ${g}" "7 ${a}" "9 ${g}" "10 ${g}" "11 ${g}" "12 ${g}" \
  "14 ${g}" "16 ${g}" "20 ${a}" "21 ${g}" "22 ${g}" "23 ${b}" "24 ${b}" "25 ${b}" "26 ${b}" "27 ${a}" "28 ${g}" "30 ${a}" "35 ${a}" "36 ${g}" \
  "37 ${a}" "38 ${a}" "39 ${a}" "40 ${a}" "41 ${b}" "43 ${g}" "44 ${a}" "45 ${r}" "46 ${r}" "47 ${r}")"
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

mkdir -p "${tmp}/repo/bin/lib" "${tmp}/repo/hooks"
printf '#!/usr/bin/env bash\n' > "${tmp}/repo/bin/new-tool"; printf '#!/bin/sh\n' > "${tmp}/repo/hooks/x"
printf '#!/usr/bin/env python3\n' > "${tmp}/repo/bin/lib/y.py"; : > "${tmp}/repo/bin/z.sh"
printf '{}\n' > "${tmp}/repo/hooks/h.json"; : > "${tmp}/repo/bin/untracked.sh"
git -C "${tmp}/repo" init -q && git -C "${tmp}/repo" add bin/new-tool hooks/x bin/lib/y.py bin/z.sh hooks/h.json
got="$(shell_files "${tmp}/repo")"
if [[ "${got}" == $'bin/new-tool\nbin/z.sh\nhooks/x' ]]; then
  echo "ok   the scan takes every tracked *.sh and sh or bash script under bin/ and hooks/"
else
  echo "FAIL the scan's file list: want bin/new-tool, bin/z.sh, hooks/x, got:"; echo "${got}"; fails=$((fails + 1))
fi

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
