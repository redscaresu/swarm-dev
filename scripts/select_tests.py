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
# Both read the map and tests/ of the git checkout the current directory is in, and exit 2 on a map
# that does not parse or lists a test file that is not there.
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


# changed(root) — every path that differs from the merge base with origin/main in the working tree,
# both sides of a rename, and every untracked path git does not ignore.
def changed(root):
    base = git(root, "merge-base", "HEAD", BASE).strip()
    paths = git(root, "diff", "-z", "--name-only", "--no-renames", base).split("\0")
    paths += git(root, "ls-files", "-z", "--others", "--exclude-standard").split("\0")
    return sorted({p for p in paths if p})


def check_map(rows, paths):
    return [p for p in paths if p.startswith(MAPPED_DIRS) and row_for(rows, p) is None]


def main(argv):
    try:
        root = subprocess.run(("git", "rev-parse", "--show-toplevel"), check=True, capture_output=True, text=True).stdout.strip()
        rows = load_map(root)
    except (subprocess.CalledProcessError, OSError, MapError) as e:
        why = e.stderr.strip() if isinstance(e, subprocess.CalledProcessError) else e
        print(f"select-tests: {why}", file=sys.stderr)
        return 2
    if argv[1:] == ["--check-map"]:
        missing = check_map(rows, [line.rstrip("\n") for line in sys.stdin if line.strip()])
        for p in missing:
            print(f"select-tests: {p}: no row in {MAP} matches it")
        return 1 if missing else 0
    if argv[1:]:
        print("usage: select_tests.py [--check-map]", file=sys.stderr)
        return 2
    try:
        picked, why = select(root, rows, changed(root))
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
