#!/usr/bin/env bash
# port_tests_list_test.sh — docs/port/tests.tsv lists every tests/*_test.sh that reaches inside the code.
# The rule (the list's header says it in words) finds a test's reach from its text, comment lines left out:
#   lib           a source or . of a bin/lib/*.sh
#   py            a bin/lib/*.py named, or a module of that name imported
#   text          a reader (grep, sed, awk, cat, head, tail, wc, perl, diff, cmp, cut, a python3 -c or -
#                 program, open() or a < redirect) whose arguments take a path into bin/ or hooks/, bin/
#                 or hooks/ itself, a name the test sets to one, or a "$(dirname <such a name>)"/... path;
#                 a python3 -c or - program that opens the sys.argv word that is such a path; a for loop
#                 over such paths; git ls-files over bin or hooks; os.walk in a file that names "bin" or
#                 "hooks". hooks/hooks.json, the plugin's config, a path past .., bin/lib or a .py given
#                 to a python3 program it does not open (its sys.path or its module), and a path inside a
#                 longer quoted string (a pattern or a message) are no reach.
#   python3-stub  a file written, copied or linked to a path ending in /python3
# A test also takes each kind of a helper under tests/ (not a *_test.sh) that it names by file name, so
# the 16 tests that source tests/merge_fixture.sh are lib. The rule runs first on samples of its own, so a
# pattern that stops matching fails here rather than passing every test by.
# It fails, naming the file and its reach, on a test with no row; on a row whose mark is neither
# rewrite-from-outside nor becomes-a-Go-test; on a text row (its reach says text, or the rule finds text
# in its test) whose go_check, and any row whose epic, is
# empty or a placeholder; and on a row without five tab-separated fields. A row whose file the rule does
# not find, or that does not exist, passes: the list is the record. It lists files with os.walk, not git,
# so it runs the same on a copy of the worktree without .git.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${ROOT}"' EXIT
export CLAUDE_CONFIG_DIR="${ROOT}/claude-config"   # under its own root, as every test file
python3 -I - "${REPO}" <<'PY'
import os
import re
import sys

ROOT = sys.argv[1]
LIST = "docs/port/tests.tsv"
KINDS = ("lib", "py", "text", "python3-stub")
MARKS = ("rewrite-from-outside", "becomes-a-Go-test")
PLACEHOLDERS = ("", "none", "none yet", "tbd", "?", "-")
COLUMNS = ("file", "reach", "mark", "go_check", "epic")


def lib_names(ext):
    """The bin/lib/*<ext> files' names, without the extension, sorted."""
    lib = os.path.join(ROOT, "bin", "lib")
    return sorted(f[: -len(ext)] for f in os.listdir(lib) if f.endswith(ext))


SH_NAMES, PY_NAMES = lib_names(".sh"), lib_names(".py")
SH, PY = ("|".join(map(re.escape, n)) or "(?!)" for n in (SH_NAMES, PY_NAMES))
SOURCES = re.compile(r"""(?:^|[\s;&|({'"])(?:source|\.)\s+["']?(?:\$|[\w./-])[^;&|]*?(?:lib/|/)(?:%s|\$\{?\w+\}?)\.sh\b""" % SH)
NAMES_PY = re.compile(r"""(?<![\w.-])(?:%s)\.py\b|\bfrom\s+(?:%s)\s+import\b|(?:^|[;:'"]|\s)\s*import\s+(?:\w+\s*,\s*)*(?:%s)\b""" % (PY, PY, PY))
STUB = re.compile(r"""(?:>>?|\bcp\b[^|;&]*|\bln\b[^|;&]*)\s*["']?[^"'\s]*/python3["']?(?:\s|$|[;&)])""")
CODE = r"""bin/swarm\.sh|bin/lib\b|bin/gh-shim|(?<!\.git/)hooks/(?!hooks\.json)[\w*.-]+"""
CODE_DIR = r"""(?<=/)(?:bin|hooks)(?=["']?(?:\s|$|\)))"""   # the whole directory, as a reader's argument only
LS_FILES = re.compile(r"""\bls-files\s+(?:bin|hooks)\b""")
WALK = re.compile(r"""\bos\.walk\(""")
DIRWORD = re.compile(r"""["'](?:bin|hooks)["']""")   # vacuous-test: ok, a regex, not JSON
LOOP = r"""\bfor\s+\w+\s+in\s+[^;]*?[}"')]/%s"""
AT = r"""(?:^\s*|[|;&({`]\s*|\$\(\s*|["']\s+|\b(?:if|then|do|else|while|until|xargs|exec|eval|!)\s+)"""
PROGRAM = r"""python3\s+(?:-I\s+)?(?:-c|-)"""
READ = re.compile(r"""(?:%s(?:grep|sed|awk|cat|head|tail|wc|perl|diff|cmp|cut|%s)(?=\s)|\bopen\(|\.read_text\(|(?<![<\d])<\s*(?![<(]))""" % (AT, PROGRAM))
TAIL = r"""[\w./*@\[\]{}%#-]*["']?(?=\s|$|[);|&])"""
CD_PWD = re.compile(r"""\$\((?:cd\s+(?:"(?:[^"$]|\$\{[^}]*\}|\$\(dirname\s+"[^"]*"\))*"|[^\s)]+)\s*&&\s*pwd(?:\s+-P)?|dirname\s+(?:"[^"]*"|[^\s)]+))\)""")
DIRNAME = re.compile(r"""\$\(dirname\s+("[^"]*"|[^\s)]+)\)"?(/[\w./*-]*)""")
PY_PROGRAM = re.compile(r"""python3\s+(?:-I\s+)?(?:-c\s+'([^']*)'([^\n]*)|-\s+([^\n<]*)<<-?\s*'?(?:\w+)'?\n(.*?)\n\w+\n)""", re.S)
ASSIGN = re.compile(r"""^\s*(?:local\s+|export\s+|readonly\s+)?(\w+)=(.*)$""")


def code_lines(text):
    """The text's lines with continuations joined and comment lines left out."""
    return [l for l in text.replace("\\\n", " ").splitlines() if not l.lstrip().startswith("#")]


def blank_quotes(line):
    """The line with each single-quoted string emptied but a plain path ('bin/swarm.sh'): an awk or sed
    program, a pattern or a python -c body is no argument. A ' inside double quotes is a plain
    character."""
    out, stack, i = [], [], 0
    while i < len(line):
        c, top = line[i], stack[-1] if stack else ""
        if c == "'" and top != '"':
            j = line.find("'", i + 1)
            if j < 0:
                break
            out.append(line[i:j + 1] if re.fullmatch(r"[\w./*-]+", line[i + 1:j]) else "''")
            i = j + 1
            continue
        if line.startswith("$(", i):
            stack.append("(")
            out.append("$(")
            i += 2
            continue
        if c == "\\":
            out.append(line[i:i + 2])
            i += 2
            continue
        if c == '"':
            stack.pop() if top == '"' else stack.append('"')
        elif c == "(" and top != '"':
            stack.append("(")
        elif c == ")" and top == "(":
            stack.pop()
        out.append(c)
        i += 1
    return "".join(out)


def first_word(text):
    """The shell word text starts with: up to a blank, ;, & or | outside quotes and parentheses, an
    array's ( ... ) whole."""
    depth, quote, i = 0, "", 0
    while i < len(text):
        c = text[i]
        if quote:
            if c == quote:
                quote = ""
            elif quote == '"' and text.startswith("$(", i):
                depth, i = depth + 1, i + 1
        elif c in "\"'":
            quote = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0 and text[:1] == "(":
                return text[: i + 1]
            if depth < 0:
                break
        elif depth == 0 and c in " \t;&|":
            break
        i += 1
    return text[:i]


def code_tok(names, dirs=False):
    """A pattern for a path into the code or one of names; with dirs, bin or hooks itself too."""
    return "(?:" + "|".join([CODE] + [CODE_DIR] * dirs + [r"\$\{?%s\b" % re.escape(n) for n in sorted(names)]) + ")"


def is_code_path(word, tok):
    """A word naming a place in the code: it ends in a code path or name (one cut back to the root, as
    ${SWARM%/bin/swarm.sh}, does not count), with no .. after it and no command run but cd && pwd or
    dirname."""
    word = re.sub(r"""\$\{\w+%%?/bin\b[^}]*\}""", "ROOT", word)
    last = None
    for last in re.finditer(tok, word):
        pass
    return last is not None and ".." not in word[last.end():] and "$(" not in CD_PWD.sub("", word)


def code_names(lines):
    """The names a test sets to a path into the code, or to a path built on such a name."""
    found = set()
    while True:
        tok = code_tok(found)
        new = set(found)
        for l in lines:
            m = ASSIGN.match(blank_quotes(l))
            if m and is_code_path(first_word(m.group(2)), tok):
                new.add(m.group(1))
        if new == found:
            return found
        found = new


def takes_code(line, read, start, i, tok):
    """Whether the reader's argument at i is a path into the code, not a word inside a longer quoted
    string, nor bin/lib or a .py given to a python3 program (its sys.path or its module)."""
    t = re.compile(tok + TAIL).match(line, i)
    if not t or line[i - 1] not in " \t\"'/,(=":
        return False
    if line.count('"', start, i) % 2:
        q = line.rindex('"', start, i)
        if re.search(r"\s", line[q + 1:i]) or not t.group(0).endswith('"'):
            return False
    return not (re.search(PROGRAM + r"$", read.rstrip()) and re.search(r"(?:bin/lib/?|\.py)$", t.group(0).strip("\"'")))


def reads_code(line, tok):
    """A reader whose arguments, before a pipe, a list, a redirect out, a command substitution or a
    command it runs (bash, sh, env, exec, timeout, python3), take a path into the code."""
    for m in READ.finditer(line):
        depth, i = 0, m.end()
        while i < len(line):
            c = line[i]
            if line.startswith("$(", i):
                d = DIRNAME.match(line, i)
                if d and re.search(tok, d.group(1)) and ".." not in d.group(2):
                    return True   # "$(dirname "${SWARM}")"/lib/x.sh: a path built in the code's directory
                break
            if line.startswith("<<", i) or c in "|;&`>":
                break
            if line[i - 1] in " \t" and re.match(r"(?:bash|sh|env|exec|timeout|python3)\s", line[i:]):
                break
            depth += (c == "(") - (c == ")")
            if depth < 0:
                break
            if takes_code(line, m.group(0), m.end(), i, tok):
                return True
            i += 1
    return False


def words(text):
    """The shell words of text, each with its quotes."""
    out, text = [], text.strip()
    while text:
        w = first_word(text) or text[0]
        out.append(w)
        text = text[len(w):].strip()
    return out


def opens_code(text, tok):
    """Whether a python3 -c or - program in text opens a file whose path, as its sys.argv word, is in the
    code: open(sys.argv[N]), or open() in a program that walks sys.argv[1:]."""
    for m in PY_PROGRAM.finditer(text):
        program = m.group(1) if m.group(1) is not None else m.group(4)
        args = words(m.group(2) if m.group(1) is not None else m.group(3))
        n = {int(k) for k in re.findall(r"open\(\s*sys\.argv\[(\d+)\]", program)}
        if "open(" in program and "sys.argv[1:]" in program:
            n |= set(range(1, len(args) + 1))
        if any(0 < k <= len(args) and is_code_path(args[k - 1], tok) for k in n):
            return True
    return False


def reach(text):
    """The kinds of reach the text of a test or helper shows."""
    lines = code_lines(text)
    quoted = [blank_quotes(l) for l in lines]
    tok = code_tok(code_names(lines), dirs=True)
    kinds = set()
    if any(SOURCES.search(l) for l in lines):
        kinds.add("lib")
    if any(NAMES_PY.search(l) for l in lines):
        kinds.add("py")
    if (any(reads_code(l, tok) or re.search(LOOP % tok, l) or LS_FILES.search(l) for l in quoted)
            or opens_code("\n".join(lines), tok)
            or (any(WALK.search(l) for l in lines) and any(DIRWORD.search(l) for l in lines))):
        kinds.add("text")
    if any(STUB.search(l) for l in lines):
        kinds.add("python3-stub")
    return kinds


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def found_tests():
    """{tests/<name>_test.sh: its kinds} for each test with a reach, a helper's kinds included."""
    tests, helpers = {}, {}
    for dirpath, dirs, files in os.walk(os.path.join(ROOT, "tests")):
        dirs[:] = [d for d in dirs if d != "__pycache__"]
        for f in files:
            path = os.path.join(dirpath, f)
            if dirpath == os.path.join(ROOT, "tests") and f.endswith("_test.sh"):
                tests["tests/" + f] = read(path)
            elif f.endswith((".sh", ".py")):
                helpers[f] = reach(read(path))
    out = {}
    for t, text in tests.items():
        kinds = reach(text)
        named = "\n".join(code_lines(text))
        for h, hk in helpers.items():
            if hk and re.search(r"(?<![\w.-])%s\b" % re.escape(h), named):
                kinds |= hk
        if kinds:
            out[t] = kinds
    return out


SH_SAMPLES = [   # (a line of a test, with %s for a bin/lib/*.sh name, the kinds the rule must find in it)
    ('bash -c \'source "$1/bin/lib/%s.sh"; get_fm x\' _ "${REPO}"', {"lib"}),
    ('. "${SWARM%%/*}/lib/%s.sh"', {"lib"}),
    ("cd \"${REPO}\" && source bin/lib/%s.sh", {"lib"}),
]
PY_SAMPLES = [   # the same, with %s for a bin/lib/*.py name
    ('python3 "${REPO}/bin/lib/%s.py" a', {"py"}),
    ("from %s import outcome", {"py"}),
    ("python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import json, %s' x", {"py"}),
]
SAMPLES = [   # (a line of a test, the kinds the rule must find in it), named from the files bin/lib has now
    *((t % SH_NAMES[0], k) for t, k in SH_SAMPLES[: len(SH_SAMPLES) * bool(SH_NAMES)]),
    *((t % PY_NAMES[0], k) for t, k in PY_SAMPLES[: len(PY_SAMPLES) * bool(PY_NAMES)]),
    ("cat 'bin/swarm.sh'", {"text"}),
    ('diff -rq -x __pycache__ "${REPO}/bin" "${dir}/plugin/bin"', {"text"}),
    ('SWARM="${REPO}/bin/swarm.sh"\nx="$(python3 -I - "$(dirname "${SWARM}")/lib/lifecycle.sh" <<\'PY\'\nsrc = open(sys.argv[1]).read()\nPY\n)"', {"text"}),
    ('SWARM="${REPO}/bin/swarm.sh"\nx="$(grep -c x "$(dirname "${SWARM}")"/lib/*.sh)"', {"text"}),
    ("python3 -c 'import sys; print(open(sys.argv[1]).read())' \"${REPO}/bin/lib/%s.py\"" % (PY_NAMES or ["x"])[0], {"py", "text"} if PY_NAMES else {"text"}),
    ("python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); print(open(sys.argv[2]).read())' \"${REPO}/bin/lib\" \"${ROOT}/ev\"", set()),
    ('SWARM="${REPO}/bin/swarm.sh"\nt="$(python3 -c \'import sys; print(open(sys.argv[1]).read())\' "$(dirname "${SWARM}")/../commands/swarm.md")"', set()),
    ('SWARM="${REPO}/bin/swarm.sh"\nperl -e \'alarm 5; exec @ARGV\' python3 -I "$(dirname "${SWARM}")/lib/x.py"', set()),
    ("src = open('bin/swarm.sh').read()", {"text"}),
    ('KINDS="$(sed -n \'s/^K="\\(.*\\)"$/\\1/p\' "${REPO}/bin/swarm.sh")"', {"text"}),
    ('SWARM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/swarm.sh"\nx="$(awk \'/^f\\(\\)/\' "${SWARM}")"', {"text"}),
    ('git -C "$1" ls-files bin hooks', {"text"}),
    ('for f in "$1"/bin/swarm.sh "$1"/bin/lib/*.sh; do echo "${f}"; done', {"text"}),
    ('src = open(os.path.join(repo, "bin/swarm.sh")).read()', {"text"}),
    ('printf \'#!/bin/sh\\nexit 1\\n\' > "${ROOT}/badpy/python3"', {"python3-stub"}),
    ('SWARM="${REPO}/bin/swarm.sh"\nout="$("${SWARM}" next | grep -c x)"', set()),
    ('grep -qxF \'x\' "${p}/.git/hooks/pre-commit"', set()),
    ('h = json.load(open("hooks/hooks.json"))', set()),
    ('grep -c "Its swarm.sh is ${REPO}/bin/swarm.sh: use that path" "${out}"', set()),
    ('# grep x "${REPO}/bin/swarm.sh" in a comment', set()),
    ('check "a red head, changing hooks/x.sh" "held: s changes hooks/x.sh"', set()),
]


def check_rule():
    bad = []
    for text, want in SAMPLES:
        got = reach(text)
        if got != want:
            bad.append("FAIL the rule finds %s in %r, not %s: fix the rule in %s" % (
                sorted(got) or "no reach", text, sorted(want) or "no reach", "tests/port_tests_list_test.sh"))
    return bad


def rows():
    """(rows by file, failure lines) from the list."""
    out, bad = {}, []
    for n, line in enumerate(read(os.path.join(ROOT, LIST)).split("\n"), 1):
        if not line.strip() or line.startswith("#"):
            continue
        f = line.split("\t")
        if len(f) != len(COLUMNS):
            bad.append("FAIL %s:%d has %d tab-separated fields, not %d (%s): %s" % (LIST, n, len(f), len(COLUMNS), ", ".join(COLUMNS), line))
            continue
        if f[0] in out:
            bad.append("FAIL %s:%d is a second row for %s: keep one" % (LIST, n, f[0]))
        out[f[0]] = dict(zip(COLUMNS, f), line=n)
    return out, bad


def check_rows(listed, found):
    """Failure lines for each test with no row and each row that breaks a column's rule. A row is a text
    row when its reach says text, or the rule finds text in its test."""
    bad = []
    for t in sorted(found):
        if t not in listed:
            reach_s = ",".join(k for k in KINDS if k in found[t])
            go = "<what the Go check that keeps its rule asserts>" if "text" in found[t] else ""
            bad.append("FAIL %s reaches inside the code (%s) and has no row in %s: add the row "
                       "'%s<TAB>%s<TAB>rewrite-from-outside<TAB>%s<TAB><epic>' (its header says what each column holds)"
                       % (t, reach_s, LIST, t, reach_s, go))
    for t, r in sorted(listed.items()):
        where = "%s:%d (%s)" % (LIST, r["line"], t)
        if r["mark"] not in MARKS:
            bad.append("FAIL %s has mark %r: write %s or %s" % (where, r["mark"], MARKS[0], MARKS[1]))
        empty = [c for c in ("go_check", "epic") if r[c].strip().lower() in PLACEHOLDERS
                 and (c == "epic" or "text" in r["reach"].split(",") or "text" in found.get(t, ()))]
        for c in empty:
            kind = "text" if c == "go_check" else r["reach"]
            bad.append("FAIL %s has %s %r on a %s row: name %s" % (
                where, c, r[c], kind, "the Go check that keeps its rule, or retired-with: <epic>" if c == "go_check" else "the epic"))
    return bad


rule_bad = check_rule()
if rule_bad:
    print("\n".join(rule_bad))
    sys.exit(1)
print("ok   the rule finds each sample's reach, and none in the %d samples with no reach" % sum(not w for _, w in SAMPLES))
listed, bad = rows()
found = found_tests()
bad += check_rows(listed, found)
counts = ", ".join("%s %d" % (k, sum(k in v for v in found.values())) for k in KINDS)
if bad:
    print("\n".join(bad))
    sys.exit(1)
print("ok   each of the %d tests that reach inside the code (%s) has a row in %s" % (len(found), counts, LIST))
print("ok   every row's mark is one of the two, every text row names its go_check and every row its epic")
PY
