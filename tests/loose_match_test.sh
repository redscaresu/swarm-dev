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
GREP = re.compile(r"(?:^|[\s|;&({!`])grep\s+")
WORD = re.compile(r"""(?:\$'(?:[^'\\]|\\.)*'|'[^']*'|"(?:[^"\\]|\\.)*"|\\.|[^\s|;&()<>'"\\])+""")
ARG = set("efmABC")   # short options that take the next word
VAR = re.compile(r"\$[{(\w@*#?]")
SUBSTR = re.compile(r"[!=]=\s+(\*\S*\*)(?:\s|$)")
AWK_RE = re.compile(r"(?<![=!~\"'])!?~\s*(?=[\w$(\"])")

def interpolates(word):
    # $'...', '...' and \$ expand nothing; a ' inside "..." is a plain character.
    for q in re.findall(r"""\$'(?:[^'\\]|\\.)*'|'[^']*'|"(?:[^"\\]|\\.)*"|\\.|[^'"\\]+""", word):
        if not q.startswith(("'", "\\", "$'")) and VAR.search(re.sub(r"\\.", "", q)):
            return True
    return False

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
            fixed |= w in ("--fixed-strings", "--line-regexp", "--word-regexp")
            if w == "--regexp" and i + 1 < len(words): i += 1; patterns.append(words[i])
            elif w.startswith("--regexp="): patterns.append(w[len("--regexp="):])
            from_file |= w == "--file" or w.startswith("--file=")
            if w == "--file": i += 1
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

# logical_lines <path> — (first line number, text) per command, a line ending in \ joined to the next.
def logical_lines(path):
    start, buf = None, ""
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.rstrip("\n")
        start, buf = start or n, buf + line
        if line.endswith("\\") and not line.endswith("\\\\"):
            buf = buf[:-1] + " "; continue
        yield start, buf
        start, buf = None, ""
    if buf: yield start, buf

for path in sys.argv[1:]:
    in_awk = False
    for n, line in logical_lines(path):
        code, shapes = line.lstrip(), []
        awk_part = line if in_awk else None
        if not in_awk and (m := re.search(r"(?:^|[\s|;&({!`])awk\s", line)):
            awk_part = line[m.end():]
        if awk_part is not None:
            in_awk = (awk_part.count("'") % 2 == 1) != in_awk
            if AWK_RE.search(awk_part): shapes.append("awk ~ built from a variable")
        if code.startswith("#") or OK.search(line):
            continue
        if any(grep_loose(line[m.end():]) for m in GREP.finditer(line)):
            shapes.append("grep pattern from a variable without -F, -x or -w")
        if any(interpolates(w) for w in SUBSTR.findall(line)):
            shapes.append("substring test on a variable")
        for s in shapes:
            print(f"{path}:{n}: {s}: {code}")
EOF
}

fails=0
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
export CLAUDE_CONFIG_DIR="${tmp}/claude-config"   # under its own root, as every test file

files=("${REPO}/bin/swarm.sh" "${REPO}"/bin/lib/*.sh "${REPO}"/bin/gh-shim/gh "${REPO}"/hooks/*.sh)
if found="$(loose_match "${files[@]}")" && [[ -z "${found}" ]]; then
  echo "ok   no loose match in bin/ or hooks/"
else
  echo "FAIL a loose match in bin/ or hooks/ (use -F, -x or -w, or end the line with # loose-match: ok <reason>):"
  echo "${found//${REPO}\//}"; fails=$((fails + 1))
fi

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
EOF
got="$(loose_match "${tmp}/loose.sh" | sed 's/^[^:]*:\([0-9]*\): \([^:]*\):.*/\1 \2/')"
g='grep pattern from a variable without -F, -x or -w' a='awk ~ built from a variable'
want="$(printf '%s\n' "1 ${g}" '2 substring test on a variable' "3 ${a}" "4 ${g}" "5 ${g}" "7 ${a}" "9 ${g}" "10 ${g}" "11 ${g}" "12 ${g}")"
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

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
