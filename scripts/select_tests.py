# select_tests.py — scripts/select-tests.sh's logic: the tests/*_test.sh files to run for a branch.
#
# select_tests.py prints, one per line, the test files that cover the paths the branch changed
# against its merge base with origin/main (committed, uncommitted and untracked; a rename by both
# paths), from scripts/test-map.tsv. It fails toward more: a path no row matches, a `named` row that
# finds no test, a `self` test that is gone or a git command that fails selects every
# tests/*_test.sh, which scripts/test.sh logs as `all`, and says why on stderr; an empty selection
# says so on stderr too. stdout is the list alone. A `reach` row (bin/) selects by function: for each
# function and arm --functions gives, its callers in a static call graph of bin's shell up to the
# dispatch arms (a function's code that names another calls it; code that runs swarm.sh calls the arm
# its command names), and the tests that name a function on that chain or a reached arm's command, or
# a hook or script that runs that arm, and the tests that name the changed file. It selects every test for --functions' full, a caller at a
# file's top level, the catch-all arm, a call by a name built at run time ("cmd_${x}", eval), a test
# that runs swarm.sh and names no arm's command, or a function no test reaches.
# select_tests.py --check-map reads paths from stdin (`git ls-files`) and names each one under bin/,
# scripts/, commands/, hooks/ or docs/ that no row matches; it exits 1 when there is one.
# select_tests.py --functions prints, one per line, the bin/ functions those changes reach: each
# changed line of bin/swarm.sh or bin/lib/*.sh, at the merge base and now, as <file>:<function>, or
# <file>:arm <cmd> in an arm of bin/swarm.sh's dispatch case; for a changed bin/lib/*.py, each
# function whose body names it or a .py that imports it. It prints `full` alone, and says why on
# stderr, for a line in no function (top level, a setting), a function it cannot parse, a .py no
# function names or a hook, script or test runs, or a git command that fails. It prints nothing, and
# says so on stderr, when no change reaches those files.
# The default mode and --check-map read the map and tests/ of the git checkout the current directory
# is in, and exit 2 on a map that does not parse or lists a test file that is not there; --functions
# reads no map.
import glob
import io
import os
import re
import subprocess
import sys
import tokenize

MAP = "scripts/test-map.tsv"
TESTS = "tests/*_test.sh"
BASE = "origin/main"
KEYWORDS = ("named", "self", "all", "none", "reach")
ALONE = ("all", "none")
KNOWN = ", ".join(KEYWORDS)
MAPPED_DIRS = ("bin/", "scripts/", "commands/", "hooks/", "docs/")
# The selector's own test: its fixture names real paths it does not test, so it counts as naming none.
NOT_NAMERS = ("tests/select_tests_test.sh",)
# A basename is named when no word character, '-' or '.' runs on before it, nor a word character or
# '-' after it: swarm.md is not plan-swarm.md, test.sh is not select_test.sh.
BEFORE, AFTER = r"(?<![\w.-])", r"(?![\w-])"
FULL = "full"
SHELL_FILES = ("bin/swarm.sh", "bin/lib/*.sh")
PY_FILES = "bin/lib/*.py"
# Run a bin/lib .py outside the bin/ functions --functions names, so one they name gives full.
OTHER_RUNNERS = ("hooks/*", "scripts/*", "bin/gh-shim/*", "tests/*")
DISPATCH = ("bin/swarm.sh", "dispatch")
DEF = re.compile(r"([A-Za-z_][\w-]*)\(\)\s*([{(])")
CASE = re.compile(r"\s*case .* in$")
ARM = re.compile(r"\s*([^\s#()][^)]*)\)")
HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", re.MULTILINE)


class MapError(Exception):
    pass


# glob_re(pattern) — the pattern as a regex over a whole path: ** spans directories, * and ? do not.
def glob_re(pattern):
    out = ""
    for part in re.split(r"(\*\*|\*|\?)", pattern):
        out += {"**": ".*", "*": "[^/]*", "?": "[^/]"}.get(part, re.escape(part))
    return re.compile(out + r"\Z")


# load_map(root) — the map's rows in order: (line number, [glob regex], [targets]). Each row is
# <glob>[ <glob>...]<TAB><target>[ <target>...]; # starts a comment.
def load_map(root):
    rows = []
    with open(os.path.join(root, MAP), encoding="utf-8") as f:
        for n, line in enumerate(f, 1):
            line = line.split("#", 1)[0].rstrip()
            if not line:
                continue
            globs, sep, targets = line.partition("\t")
            globs, targets = globs.split(), targets.split()
            if not sep or not globs or not targets:
                raise MapError(f"{MAP}:{n}: not <glob><TAB><targets>")
            for t in targets:
                if t not in KEYWORDS and not glob_re(TESTS).match(t):
                    raise MapError(f"{MAP}:{n}: {t} is neither a test file nor one of {KNOWN}")
                if t not in KEYWORDS and not os.path.isfile(os.path.join(root, t)):
                    raise MapError(f"{MAP}:{n}: {t} does not exist")
            if len(targets) > 1 and any(t in ALONE for t in targets):
                raise MapError(f"{MAP}:{n}: all and none stand alone")
            rows.append((n, [glob_re(g) for g in globs], targets))
    return rows


# row_for(rows, path) — the first row with a glob that matches the path, or None.
def row_for(rows, path):
    for row in rows:
        if any(g.match(path) for g in row[1]):
            return row
    return None


def all_tests(root):
    return sorted(os.path.relpath(p, root) for p in glob.glob(os.path.join(root, TESTS)))


# naming(root, tests, path) — the tests whose text names the path's basename, read now, so a test
# added since the map was written is found; NOT_NAMERS never count.
def naming(root, tests, path):
    word = re.compile(BEFORE + re.escape(os.path.basename(path)) + AFTER)
    out = []
    for t in tests:
        if t in NOT_NAMERS:
            continue
        with open(os.path.join(root, t), encoding="utf-8", errors="replace") as f:
            if word.search(f.read()):
                out.append(t)
    return out


# select(root, rows, paths, base) — (the tests to run, None) or (None, why) for every test. The paths a
# `reach` row select the tests that name them, and go to reaching() together, after the rest.
def select(root, rows, paths, base):
    tests, picked, reach = all_tests(root), set(), []
    for path in paths:
        row = row_for(rows, path)
        if row is None:
            return None, f"{path}: no row in {MAP} matches it"
        n, _, targets = row
        if targets == ["all"]:
            return None, f"{path}: {MAP}:{n} maps it to all"
        for t in targets:
            if t == "named":
                found = naming(root, tests, path)
                if not found:
                    return None, f"{path}: no test names {os.path.basename(path)}"
                picked.update(found)
            elif t == "self":
                if path not in tests:
                    return None, f"{path}: the test is gone"
                picked.add(path)
            elif t == "reach":
                reach.append(path)
                picked.update(naming(root, tests, path))   # a test that reads the file as text
            elif t != "none":
                picked.add(t)
    if reach:
        found, why = reaching(root, base, reach)
        if why:
            return None, why
        picked |= found
    return sorted(picked), None


def git(root, *args):
    return subprocess.run(("git", "-C", root) + args, check=True, capture_output=True, text=True).stdout


def merge_base(root):
    return git(root, "merge-base", "HEAD", BASE).strip()


# changed(root, base) — every path that differs from the merge base in the working tree, both sides
# of a rename, and every untracked path git does not ignore.
def changed(root, base):
    paths = git(root, "diff", "-z", "--name-only", "--no-renames", base).split("\0")
    paths += git(root, "ls-files", "-z", "--others", "--exclude-standard").split("\0")
    return sorted({p for p in paths if p})


# code_of(line) — a shell line without its comment, which starts at a # that begins a word outside
# quotes.
def code_of(line):
    quote, k = None, 0
    while k < len(line):
        ch = line[k]
        if ch == "\\" and quote != "'":
            k += 1
        elif quote:
            quote = None if ch == quote else quote
        elif ch in "'\"":
            quote = ch
        elif ch == "#" and (k == 0 or line[k - 1].isspace()):
            return line[:k]
        k += 1
    return line


# owners(path, text) — per line of a bin shell file, its labels: the function the line is in;
# `arm <cmd>` per command of the dispatch arm it is in (bin/swarm.sh's dispatch); none for a blank
# line outside any function, which runs nothing; else FULL. A comment block that runs straight into a
# function is that function's. A function whose end it cannot find before the next one starts makes
# FULL of every line from there on.
def owners(path, text):
    lines, out, doc, i = text.split("\n"), [], [], 0
    while i < len(lines):
        m, line = DEF.match(lines[i]), lines[i].strip()
        if not m:
            out.append((FULL,) if line else ())
            doc = doc + [i] if line.startswith("#") else []
            i += 1
            continue
        name, closer = m.group(1), ")" if m.group(2) == "(" else "}"
        end = i if code_of(line).rstrip().endswith(closer) else \
            next((j for j in range(i + 1, len(lines)) if lines[j].startswith(closer) or DEF.match(lines[j])), None)
        if end is None or (end > i and DEF.match(lines[end])):
            return out + [(FULL,)] * (len(lines) - i)
        for j in doc:
            out[j] = (name,)
        body = lines[i:end + 1]
        out += arms(body, name) if (path, name) == DISPATCH else [(name,)] * len(body)
        doc, i = [], end + 1
    return out


# arms(body, name) — owners' entries for the dispatch function's body: a line in an arm of its case
# (a comment just above an arm included) is the arm's commands; any other line is the function's.
def arms(body, name):
    out = [(name,)] * len(body)
    start = next((k for k, line in enumerate(body) if CASE.match(line)), None)
    if start is None:
        return out
    indent, arm, doc = indent_of(body[start]) + 2, None, []
    for k in range(start + 1, len(body)):
        line = body[k]
        if line.strip() and indent_of(line) < indent:   # esac
            break
        m = ARM.match(line) if indent_of(line) == indent else None
        if m:
            arm = tuple("arm " + c for c in m.group(1).split("|"))
            for j in doc:
                out[j] = arm
            doc = []
        elif indent_of(line) == indent and line.strip().startswith("#"):
            doc.append(k)
            continue
        if arm:
            out[k] = arm
    return out


def indent_of(line):
    return len(line) - len(line.lstrip(" "))


def matches(path, patterns):
    return any(glob_re(g).match(path) for g in patterns)


def read(root, path):
    try:
        with open(os.path.join(root, path), encoding="utf-8", errors="replace") as f:
            return f.read()
    except FileNotFoundError:
        return None


# at_base(root, base, path) — the file's text at the merge base, or None when it was not there.
def at_base(root, base, path):
    if not git(root, "ls-tree", base, "--", path).strip():
        return None
    return git(root, "show", f"{base}:{path}")


# shell_changes(root, base, path) — (the labels a bin shell file's changed lines give, None), or
# (None, why) for full. A file new since the base gives its functions: its top level runs only where
# a changed line sources it, and that line gives full (bin/swarm.sh's top level) or its function.
def shell_changes(root, base, path):
    old, new = at_base(root, base, path), read(root, path)
    if old is None:
        return {f"{path}:{c}" for labels in owners(path, new or "") for c in labels if c != FULL}, None
    diff = git(root, "diff", "-U0", "--no-ext-diff", "--no-renames", base, "--", path)
    sides = [(old, "at the base", []), (new or "", "now", [])]
    for m in HUNK.finditer(diff):
        for (_, _, nums), start, count in zip(sides, m.group(1, 3), m.group(2, 4)):
            nums += range(int(start), int(start) + (1 if count is None else int(count)))
    if not sides[0][2] and not sides[1][2]:
        return None, f"{path}: git shows no changed line in it (a mode change)"
    got = set()
    for text, when, nums in sides:
        lines = owners(path, text)
        for n in nums:
            labels = lines[n - 1]
            if FULL in labels:
                return None, f"{path}:{n} {when} is in no function"
            got.update(f"{path}:{c}" for c in labels)
    return got, None


# names_py(text, path) — whether text names a .py's file or imports it as a module, in a statement
# that starts a line or follows a ;.
def names_py(text, path):
    name = os.path.basename(path)
    module = re.escape(name[:-len(".py")])
    return bool(re.search(BEFORE + re.escape(name) + AFTER, text)
                or re.search(rf"(^|;)\s*(from|import)\s.*(?<![\w.]){module}(?!\w)", text, re.MULTILINE))


# py_code(text) — a .py's text with its comments and docstrings (a string that is a statement of its
# own) blanked, so a .py that only mentions another does not count as running it; the text as it is
# when it does not tokenize.
def py_code(text):
    lines = text.split("\n")
    try:
        tokens = list(tokenize.generate_tokens(io.StringIO(text).readline))
    except (tokenize.TokenError, SyntaxError):
        return text
    starts = (tokenize.NEWLINE, tokenize.NL, tokenize.INDENT, tokenize.DEDENT, tokenize.COMMENT)
    for k, t in enumerate(tokens):
        lone = t.type == tokenize.STRING and (k == 0 or tokens[k - 1].type in starts) \
            and k + 1 < len(tokens) and tokens[k + 1].type in (tokenize.NEWLINE, tokenize.ENDMARKER, tokenize.COMMENT)
        if t.type != tokenize.COMMENT and not lone:
            continue
        (r0, c0), (r1, c1) = t.start, t.end
        for r in range(r0, r1 + 1):
            line = lines[r - 1]
            a, b = (c0 if r == r0 else 0), (c1 if r == r1 else len(line))
            lines[r - 1] = line[:a] + " " * (b - a) + line[b:]
    return "\n".join(lines)


# runners(root, path) — (the functions whose code, comments aside, names a bin/lib .py, or one whose
# code, comments and docstrings aside, imports or names it in turn, None), or (None, why) for full: one of those a hook, script or test
# runs, or one no function and no other .py names.
def runners(root, path):
    pys = {p: py_code(read(root, p)) for p in in_tree(root, (PY_FILES,))}
    shells = {}
    for sh in in_tree(root, SHELL_FILES):
        text = read(root, sh)
        shells[sh] = list(zip(text.split("\n"), owners(sh, text)))
    others = {p: read(root, p) for p in in_tree(root, OTHER_RUNNERS) if p not in NOT_NAMERS}
    got = set()
    for x in py_reach(pys, path):
        named = set()
        for sh, lines in shells.items():
            for n, (line, labels) in enumerate(lines, 1):
                if names_py(code_of(line), x):
                    if FULL in labels:
                        return None, f"{x}: {sh}:{n} runs it outside any function"
                    named.update(f"{sh}:{c}" for c in labels)
        outside = [p for p, text in others.items() if names_py(text, x)]
        if outside:
            return None, f"{x}: {outside[0]} runs it"
        if not named and not any(names_py(t, x) for y, t in pys.items() if y != x):
            return None, f"{x}: no function names it" + ("" if x == path else f", and it reaches {path}")
        got |= named
    return got, None


# py_reach(pys, path) — the .py and every bin/lib .py that imports or names it, in turn, sorted.
def py_reach(pys, path):
    reach, todo = {path}, [path]
    while todo:
        x = todo.pop()
        for y in sorted(pys):
            if y not in reach and names_py(pys[y], x):
                reach.add(y)
                todo.append(y)
    return sorted(reach)


# in_tree(root, patterns) — the working tree's files that match the globs, sorted.
def in_tree(root, patterns):
    paths = set()
    for g in patterns:
        paths.update(os.path.relpath(p, root) for p in glob.glob(os.path.join(glob.escape(root), g)) if os.path.isfile(p))
    return sorted(paths)


# changed_functions(root, base, paths) — (the sorted labels the changed bin files give, None), or
# (None, why) for full.
def changed_functions(root, base, paths):
    got = set()
    for path in paths:
        if matches(path, SHELL_FILES):
            labels, why = shell_changes(root, base, path)
        elif matches(path, (PY_FILES,)):
            labels, why = runners(root, path)
        else:
            continue
        if why:
            return None, why
        got |= labels
    return sorted(got), None


# Runs swarm.sh: its path, closed by a quote or followed by a space ("${SWARM_HOME}/bin/swarm.sh",
# bash bin/swarm.sh go), its name alone in quotes (a .py's "swarm.sh"), or its name as a command word
# (swarm.sh go, through PATH); prose names it otherwise.
SWARM_PATH = r"(?:[/\"']swarm\.sh[\"']|/swarm\.sh(?=[ \t])|(?m:(?:^|[;&|(]|\$\(|\b(?:then|do|else|exec)\s)[ \t]*)swarm\.sh(?=[ \t]))"
# A command word: at a line's start, or after ; & | ( ) ! $( or a keyword that starts a command, or a
# { that does not open an expansion.
CMD_AT = r"(?:^|[;&|()!]|(?<!\$)\{|\b(?:then|do|else|if|while|until)\s)\s*"
BUILT = r"[\"']?((?:[\w-]|\$\{[^}]*\}|\$\w+)+)[\"']?"
CMD_WORD = re.compile(CMD_AT + BUILT)
# A variable set to a name, and one run as a command ("$fn"), which calls what it holds: a literal
# name, quoted or not, which call_graph counts as a call by the line that sets it, or a built one.
ASSIGNED = re.compile(r"(?<![\w$-])(\w+)=" + BUILT)
RUN_VAR = re.compile(CMD_AT + r"\"?\$\{?(\w+)\}?\"?(?=[\s;)]|\Z)", re.MULTILINE)
EVAL = re.compile(CMD_AT + r"eval" + AFTER)
EXPANSION = re.compile(r"(\$\{[^}]*\}|\$\w+)")
CALL = re.compile(CMD_AT + r"\"?([\w-]+)")
# A name the path to swarm.sh is put in, and a function that runs one with "$@".
HANDLE = re.compile(r"(\w+)\s*=[^\n]*" + SWARM_PATH)
FORWARDER = r"([\w-]+)\(\)\s*[{(][^\n]*(?:NAMES)[^\n]*\"\$@\""
# A case pattern that opens a line: the words in it are matched, not called.
CASE_PATTERN = re.compile(r"^\s*\(?[^\s()|;]+(?:\s*\|\s*[^\s()|;]+)*\)(?=\s|\Z)")
# A test runs swarm.sh: its path or a name for it as a command word, after any of VAR=x, env -u X, bash,
# exec or timeout N; not an assignment's value, nor an argument (a reader's sed -n ... "${SWARM}").
RUN_PREFIX = r"(?:(?:\w+=\S*|env(?:\s+-u\s+\S+)*|bash|sh|exec|timeout\s+\S+)\s+)*\"?"
# Run swarm.sh outside bin/: a test that names one runs the commands it names.
WRAPPERS = ("hooks/*", "scripts/*")
CATCH_ALL = "arm *"


# words_re(words) — a regex for any of the words, named as naming() names a file; one that never matches for none.
def words_re(words, after=AFTER):
    if not words:
        return re.compile(r"(?!)")
    return re.compile(BEFORE + "(?:" + "|".join(re.escape(w) for w in sorted(words, key=len, reverse=True)) + ")" + after)


# shell_code(text) — per line of a shell file, the code that names what it calls: comments, quoted text
# and heredoc bodies blanked, but a $( ) inside double quotes (with its $( and )) or an unquoted heredoc
# kept, and a trap's or a -c's quoted text kept whole. A << inside (( )) is a shift, not a heredoc.
def shell_code(text):
    buf, stack, docs, i, n = [], [], [], 0, len(text)   # stack: '"' per double quote, a paren count per $( in one
    while i < n:
        ch, quoted = text[i], bool(stack) and stack[-1] == '"'
        if ch == "\n" and docs and not quoted:
            buf.append(ch)
            for delim, raw, tabs in docs:
                i = heredoc(text, i + 1, delim, raw, tabs, buf)
            docs = []
            continue
        if ch == "\\":
            buf.append(blank(text[i:i + 2]) if quoted else text[i:i + 2])
            i += 2
            continue
        if quoted:
            sub = text.startswith("$(", i)
            if ch == '"':
                stack.pop()
            elif sub:
                stack.append(1)
            buf.append("$(" if sub else blank(ch))
            i += 2 if sub else 1
            continue
        whole = re.search(r"(?:\btrap|\s-c)\s+\Z", text[text.rfind("\n", 0, i) + 1:i])
        m = re.compile(r"'[^']*'?|\"(?:[^\"\\]|\\.)*\"?" if whole else r"'[^']*'?|#[^\n]*").match(text, i)
        if m and (m.group(0)[0] != "#" or i == 0 or text[i - 1].isspace() or text[i - 1] in ";|&("):
            buf.append(m.group(0) if whole else blank(m.group(0)))
            i = m.end()
            continue
        doc = re.compile(r"<<(-?)[ \t]*(['\"]?)([\w-]+)\2").match(text, i)
        before = text[text.rfind("\n", 0, i) + 1:i]
        if doc and not text.startswith("<<<", i) and before.count("((") <= before.count("))"):
            docs.append((doc.group(3), bool(doc.group(2)), bool(doc.group(1))))
        if ch == '"':
            stack.append('"')
            ch = " "
        elif stack and ch in "()":
            stack[-1] += 1 if ch == "(" else -1
            if not stack[-1]:
                stack.pop()
        buf.append(ch)
        i += 1
    return "".join(buf).split("\n")


def blank(s):
    return re.sub(r"[^\n]", " ", s)


# heredoc(text, i, delim, raw, tabs, buf) — a heredoc body from i to its delimiter's line, onto buf: blank,
# but each $( ) in it kept when its delimiter is unquoted; the position of the newline that ends it.
def heredoc(text, i, delim, raw, tabs, buf):
    while i < len(text):
        end = text.find("\n", i)
        end = len(text) if end < 0 else end
        line = text[i:end]
        if (line.lstrip("\t") if tabs else line) == delim:
            buf.append(blank(line))
            return end
        kept = blank(line)
        for m in re.finditer(r"\$\(([^()]*(?:\([^()]*\)[^()]*)*)\)", "" if raw else line):
            kept = kept[:m.start(1)] + m.group(1) + kept[m.end(1):]
        buf.append(kept + ("\n" if end < len(text) else ""))
        i = end + 1
    return len(text)


# built_call(line, run_vars) — the regexes of the function names a line calls by a name it builds at
# run time: a whole command word glued from a name and an expansion ("cmd_${x}"), or such a value set
# to a variable in run_vars; not a case pattern (which a ) ends, where no $( opened it); or eval, which may call any.
def built_call(line, run_vars):
    out = [re.compile(r".*")] if EVAL.search(line) else []
    words = [(m, m.group(1)) for m in CMD_WORD.finditer(line)]
    words += [(m, m.group(2)) for m in ASSIGNED.finditer(line) if m.group(1) in run_vars]
    for m, w in words:
        after = line[m.end():m.end() + 1]
        if after == ")" and not line[:m.start(1)].rstrip('"').endswith("$("):
            continue
        if after not in ("", ")") and not after.isspace() and after not in ";&|":
            continue
        if "$" in w and re.search(r"[\w-]", EXPANSION.sub("", w)):
            out.append(re.compile("".join(r"[\w-]*" if p.startswith("$") else re.escape(p) for p in EXPANSION.split(w))))
    return out


# swarm_runs(text, arms, arm_re) — the commands a unit's text runs swarm.sh with: each arm's command
# that follows its quoted path, or a name for it (HANDLE, FORWARDER) not in `prose`. One followed by an
# expansion ("$@"), but in a FORWARDER, runs each arm the text names, every arm when it names none.
def swarm_runs(text, arms, arm_re):
    if not re.search(SWARM_PATH, text):
        return set()
    names = {m.group(1) for m in HANDLE.finditer(text)}
    ran = "|".join([SWARM_PATH] + [r"(?<![\w-])" + re.escape(n) + r"(?![\w-])" for n in names])
    names |= {m.group(1) for m in re.finditer(FORWARDER.replace("NAMES", ran), text)}
    names = "|".join(map(re.escape, names or ["(?!)"]))
    handle = r"(?:" + SWARM_PATH + r"[\"']?|(?<![\w`${-])\$?\{?(?:" + names + r")\}?(?![\w-]))"
    got, unsure = set(), False
    for m in re.finditer(handle + r"[\"']?,?[ \t]+[\"']?(\$\S*|[\w-]+)", text):
        if m.group(1) in arms:
            got.add(m.group(1))
        elif m.group(1).startswith("$"):
            unsure = unsure or not re.match(r"[\w-]+\(\)", text[text.rfind("\n", 0, m.start()) + 1:])
    return got | (set(arm_re.findall(text)) or set(arms) if unsure else set())


# call_graph(root) — bin's static call graph, as a dict. callers: per function name or `arm <cmd>`, the
# labels (owners') of the code lines that name it, comments left out. A unit that runs swarm.sh (a
# function's or an arm's lines, a bin/lib .py, a hook or a script) calls each arm whose command its
# text names, or every arm when it names none: a .py for the functions whose code names it or a .py
# that imports it. top: per function or arm, where a shell file's top level calls it, or the .py that
# runs it when a top level or no function runs that .py. dynamic: (regex,
# where) per call by a built name. arms: every arm's command. wrappers: per hook, script or bin/lib .py
# (and each .py that imports one), the arms it calls.
# gone: names to find callers of beyond the functions defined now (a deleted one, whose callers break).
def call_graph(root, gone=()):
    units, fns, g = {}, set(), {"callers": {}, "top": {}, "dynamic": [], "wrappers": {}}
    for sh in in_tree(root, SHELL_FILES):
        text = read(root, sh)
        run_vars = set(RUN_VAR.findall(text))
        for n, (line, code, labels) in enumerate(zip(text.split("\n"), shell_code(text), owners(sh, text)), 1):
            m = DEF.match(line)
            fns.update([m.group(1)] if m else [])
            if labels:
                units.setdefault(labels, []).append((f"{sh}:{n}", code_of(line), code, run_vars))
    g["arms"] = arms = sorted({c[4:] for labels in units for c in labels if c.startswith("arm ")} - {"*"})
    fn_re, arm_re = words_re(fns | set(gone), r"(?![\w.-])"), words_re(arms)   # a function is never named as board.sh is

    def arms_run(text):
        return {"arm " + a for a in swarm_runs(text, arms, arm_re)}

    for labels, lines in units.items():
        for c in labels if labels[0].startswith("arm ") else ():
            g["callers"].setdefault(c, set()).update(labels)   # one arm's commands reach each other
        ran = arms_run("\n".join(line for _, line, _, _ in lines)) if FULL not in labels else set()
        for where, line, code, run_vars in lines:
            if FULL in labels:
                named = {w for w in CALL.findall(code) if w in fns}
            else:
                named = set(fn_re.findall(CASE_PATTERN.sub("", code, count=1)))
            if code.strip() or line.lstrip()[:1] in "\"'":   # not a heredoc's or a long string's line
                g["dynamic"] += [(rx, where) for rx in built_call(line, run_vars)]
            named |= {m.group(2) for m in ASSIGNED.finditer(line) if m.group(1) in run_vars and m.group(2) in fns | set(gone)}
            for c in named | (arms_run(line) if FULL in labels else ran):
                if FULL in labels:
                    g["top"].setdefault(c, where)
                else:
                    g["callers"].setdefault(c, set()).update(labels)
    for w in in_tree(root, WRAPPERS):
        g["wrappers"][w] = arms_run(read(root, w))
    pys = {p: py_code(read(root, p)) for p in in_tree(root, (PY_FILES,))}
    for py in pys:
        ran = arms_run(read(root, py))
        reach = py_reach(pys, py) if ran else []
        by = {label: where for labels, lines in units.items() for where, line, _, _ in lines
              if any(names_py(line, x) for x in reach) for label in labels}
        for c in ran:
            if FULL in by or not by:
                g["top"].setdefault(c, f"{py}, " + (f"which {by[FULL]} runs" if by else "which no function runs"))
            g["callers"].setdefault(c, set()).update(by)
        for x in reach:   # a test that runs it, or a .py that imports it, runs these arms
            g["wrappers"][x] = g["wrappers"].get(x, set()) | ran
    return g


# chain_of(g, start) — (the function or arm and every caller of each, up to the dispatch arms, sorted,
# None), or (None, why) when one runs outside any function, is the catch-all arm, or may be called by a
# built name.
def chain_of(g, start):
    chain, todo = {start}, [start]
    while todo:
        x = todo.pop()
        if x == CATCH_ALL:
            return None, "the catch-all arm runs for any command"
        if x in g["top"]:
            return None, f"{x} runs outside any function, at {g['top'][x]}"
        for rx, where in g["dynamic"]:
            if not x.startswith("arm ") and rx.fullmatch(x):
                return None, f"{where} calls a function by a name it builds, which may be {x}"
        for c in sorted(g["callers"].get(x, ())):
            if c not in chain:
                chain.add(c)
                todo.append(c)
    return sorted(chain), None


# runs_swarm(text) — whether a test's text runs swarm.sh (RUN_PREFIX). A name for it is one the text
# sets to its path, or any with SWARM in it, which a test can take from a file it sources.
def runs_swarm(text):
    names = "|".join([re.escape(m.group(1)) for m in HANDLE.finditer(text)] + [r"\w*SWARM\w*"])
    command = r"(?:[^\s=\"]*/)?swarm\.sh|\$\{?(?:" + names + r")\}?"
    return bool(re.search(CMD_AT + RUN_PREFIX + "(?:" + command + r")\"?(?=\s|\)|\Z)", text, re.MULTILINE))


# reaching(root, base, paths) — (the tests that reach what the changed bin paths change, None), or (None,
# why) for every test. A test reaches a changed function when it names a function on its chain, a
# reached arm's command, or a hook or script that runs that arm; a changed .py also selects the tests
# that name it or a .py that imports it. Every test: --functions' full, a chain chain_of refuses, a
# test that runs swarm.sh and names no arm's command, or a function no test reaches.
def reaching(root, base, paths):
    labels, why = changed_functions(root, base, paths)
    if why:
        return None, why
    g = call_graph(root, [label.split(":", 1)[1] for label in labels if ":arm " not in label])
    tests = {t: read(root, t) for t in all_tests(root) if t not in NOT_NAMERS}
    any_arm = words_re(g["arms"])
    for t, text in tests.items():
        if runs_swarm(text) and not any_arm.search(text):
            return None, f"{t} runs swarm.sh with no command word in it"
    picked = set()
    pys = {p: py_code(read(root, p)) for p in in_tree(root, (PY_FILES,))}
    for path in paths:
        if matches(path, (PY_FILES,)):
            for x in py_reach(pys, path):
                picked.update(naming(root, sorted(tests), x))
    for label in labels:
        chain, why = chain_of(g, label.split(":", 1)[1])
        if why:
            return None, f"{label}: {why}"
        arms = {c for c in chain if c.startswith("arm ")}
        said = words_re([c[4:] if c in arms else c for c in chain]
                        + [os.path.basename(w) for w, called in g["wrappers"].items() if called & arms])
        found = {t for t, text in tests.items() if said.search(text)}
        if not found:
            return None, f"{label}: no test reaches it"
        picked |= found
    return picked, None


def check_map(rows, paths):
    return [p for p in paths if p.startswith(MAPPED_DIRS) and row_for(rows, p) is None]


def main(argv):
    if argv[1:] not in ([], ["--check-map"], ["--functions"]):
        print("usage: select_tests.py [--check-map | --functions]", file=sys.stderr)
        return 2
    try:
        root = subprocess.run(("git", "rev-parse", "--show-toplevel"), check=True, capture_output=True, text=True).stdout.strip()
        rows = None if argv[1:] == ["--functions"] else load_map(root)
    except (subprocess.CalledProcessError, OSError, MapError) as e:
        why = e.stderr.strip() if isinstance(e, subprocess.CalledProcessError) else e
        print(f"select-tests: {why}", file=sys.stderr)
        return 2
    if argv[1:] == ["--check-map"]:
        missing = check_map(rows, [line.rstrip("\n") for line in sys.stdin if line.strip()])
        for p in missing:
            print(f"select-tests: {p}: no row in {MAP} matches it")
        return 1 if missing else 0
    if argv[1:] == ["--functions"]:
        try:
            base = merge_base(root)
            labels, why = changed_functions(root, base, changed(root, base))
        except subprocess.CalledProcessError as e:
            labels, why = None, f"git {e.cmd[3]} failed: {e.stderr.strip()}"
        if labels is None:
            print(f"select-tests: full: {why}", file=sys.stderr)
            labels = [FULL]
        elif not labels:
            print("select-tests: no bin/ function: no change reaches a function in bin/swarm.sh, bin/lib/*.sh or bin/lib/*.py",
                  file=sys.stderr)
        for label in labels:
            print(label)
        return 0
    try:
        base = merge_base(root)
        picked, why = select(root, rows, changed(root, base), base)
    except subprocess.CalledProcessError as e:
        picked, why = None, f"git {e.cmd[3]} failed: {e.stderr.strip()}"
    if picked is None:
        print(f"select-tests: every test: {why}", file=sys.stderr)
        picked = all_tests(root)
    elif not picked:
        print("select-tests: no test file covers this branch's changes", file=sys.stderr)
    for t in picked:
        print(t)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
