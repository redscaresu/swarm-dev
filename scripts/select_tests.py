# select_tests.py — scripts/select-tests.sh's logic: the tests/*_test.sh files to run for a branch.
#
# select_tests.py prints, one per line, the test files that cover the paths the branch changed
# against its merge base with origin/main (committed, uncommitted and untracked; a rename by both
# paths), from scripts/test-map.tsv. It fails toward more: a path no row matches, a `named` row that
# finds no test, a `self` test that is gone or a git command that fails selects every
# tests/*_test.sh, which scripts/test.sh logs as `all`, and says why on stderr; an empty selection
# says so on stderr too. stdout is the list alone.
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
import os
import re
import subprocess
import sys

MAP = "scripts/test-map.tsv"
TESTS = "tests/*_test.sh"
BASE = "origin/main"
KEYWORDS = ("named", "self", "all", "none")
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
HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", re.M)


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


# select(root, rows, paths) — (the tests to run, None) or (None, why) for every test.
def select(root, rows, paths):
    tests, picked = all_tests(root), set()
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
            elif t != "none":
                picked.add(t)
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
                or re.search(rf"(^|;)\s*(from|import)\s.*(?<![\w.]){module}(?!\w)", text, re.M))


# runners(root, path) — (the functions whose code, comments aside, names a bin/lib .py, or one that
# imports or names it in turn, None), or (None, why) for full: one of those a hook, script or test
# runs, or one no function and no other .py names.
def runners(root, path):
    pys = {p: read(root, p) for p in in_tree(root, (PY_FILES,))}
    shells = {}
    for sh in in_tree(root, SHELL_FILES):
        text = read(root, sh)
        shells[sh] = list(zip(text.split("\n"), owners(sh, text)))
    others = {p: read(root, p) for p in in_tree(root, OTHER_RUNNERS) if p not in NOT_NAMERS}
    reach, todo, got = {path}, [path], set()
    while todo:
        x = todo.pop()
        for y in sorted(pys):
            if y not in reach and names_py(pys[y], x):
                reach.add(y)
                todo.append(y)
    for x in sorted(reach):
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
        picked, why = select(root, rows, changed(root, base))
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
