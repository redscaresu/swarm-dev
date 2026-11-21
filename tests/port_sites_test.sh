#!/usr/bin/env bash
# port_sites_test.sh — docs/port/sites.tsv lists every inline Python site that imports a bin/lib helper,
# so the helper epics know which sites they rewrite. A site is a python3 run whose code sits in a file
# under bin/ or hooks/ that is not a .py file, as `-c '...'`, `-c "..."` or a `python3 - <<` heredoc,
# and that imports a module named like a bin/lib/*.py file (`from X import` or `import X`), however
# sys.path is set. The test finds every site by that rule and fails on a (file, function, module) with
# no row, or with more sites than its row's n, naming the row to add. A row with fewer sites, or none,
# passes: a helper port removes sites, and readers-exit checks that none is left. It also fails on a
# bin/lib import in such a file that sits in no site it can read (code in a variable, say), and on a
# row it cannot read. Files are listed by a walk of the folders, not git, so it runs the same on a copy without .git.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# scan <root> — one line per problem: a missing or short row, an import outside a readable site, a bad row.
scan() {
  python3 -I - "$1" <<'PY'
import ast, os, re, sys

root = sys.argv[1]
files = sorted(os.path.relpath(os.path.join(d, f), root)
               for top in ("bin", "hooks") for d, sub, names in os.walk(os.path.join(root, top))
               if "__pycache__" not in d.split(os.sep) for f in names if not f.endswith((".py", ".pyc")))
LIST = "docs/port/sites.tsv"
EPICS = ("helpers-shared", "helpers-panes")
modules = {f[:-3] for f in os.listdir(os.path.join(root, "bin/lib")) if f.endswith(".py")}

# A python3 word that is a command, then its flags, then -c and a quoted body or - and a heredoc.
RUN = re.compile(r"(?<![\w./-])python3((?:[ \t]+-[A-Za-z]+)*)[ \t]+(-c[ \t]+|-(?=[ \t]))")
HEREDOC = re.compile(r"<<-?[ \t]*(['\"]?)(\w+)\1")
DEF = re.compile(r"^([ \t]*)(?:function[ \t]+)?([A-Za-z_][\w:-]*)[ \t]*\(\)[ \t]*\{(.*)$")


def quoted(text, i):
    """The body of the quoted word at text[i], and the index past it, or None."""
    q = text[i:i + 1]
    if q == "'":
        j = text.find("'", i + 1)
        return (text[i + 1:j], j + 1) if j > 0 else None
    if q == '"':
        j = i + 1
        while j < len(text) and text[j] != '"':
            j += 2 if text[j] == "\\" else 1
        return (text[i + 1:j], j + 1) if j < len(text) else None
    return None


def heredoc(text, i):
    """The body of the first heredoc on the line holding text[i], or None."""
    eol = text.find("\n", i)
    m = HEREDOC.search(text, i, len(text) if eol < 0 else eol)
    if not m or eol < 0:
        return None
    end = re.compile(r"(?m)^[ \t]*" + re.escape(m.group(2)) + r"$").search(text, eol + 1)
    return (text[eol + 1:end.start()], end.end()) if end else None


def loose(text):
    """The bin/lib modules text names after `from` or `import`, wherever they sit: for bash text, and
    for a body Python cannot parse."""
    got = []
    for m in re.finditer(r"\bfrom[ \t]+([\w.]+)[ \t]+import\b|\bimport[ \t]+([\w., \t]+)", text):
        got += [m.group(1)] if m.group(1) else [p.split()[0] for p in m.group(2).split(",") if p.split()]
    return [g.split(".")[0] for g in got if g.split(".")[0] in modules]


def imports(body):
    """Each bin/lib module the body imports itself. Python's own parser finds an import anywhere, even in
    `if x: import report`."""
    try:
        tree = ast.parse(body)
    except (SyntaxError, ValueError):
        return loose(body)
    got = [a.name for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names]
    got += [n.module for n in ast.walk(tree) if isinstance(n, ast.ImportFrom) and n.module and not n.level]
    return [g.split(".")[0] for g in got if g.split(".")[0] in modules]


def functions(text, skip):
    """For each line, the name of the innermost bash function it sits in, or (top)."""
    names, stack = [], []
    for n, line in enumerate(text.split("\n"), 1):
        names.append(stack[-1][1] if stack else "(top)")
        if n in skip:
            continue
        m = DEF.match(line)
        if m:
            names[-1] = m.group(2)
            if not re.search(r"\}[ \t;]*(#.*)?$", m.group(3)):
                stack.append((m.group(1), m.group(2)))
            continue
        if stack and line.rstrip() == stack[-1][0] + "}":
            stack.pop()
    return names


def lines_of(text, a, b):
    return set(range(text.count("\n", 0, a) + 1, text.count("\n", 0, b) + 2))


found, problems = {}, []
for rel in files:
    try:
        text = open(os.path.join(root, rel), encoding="utf-8").read()
    except (UnicodeDecodeError, OSError):
        continue
    sites, skip, rest, at = [], set(), [], 0
    for m in HEREDOC.finditer(text):
        got = heredoc(text, m.start())
        if got:
            skip |= lines_of(text, text.find("\n", m.start()) + 1, got[1] - 1)
    for m in RUN.finditer(text):
        if m.start() < at:
            continue
        got = quoted(text, m.end()) if m.group(2).startswith("-c") else heredoc(text, m.end())
        if got:
            sites.append((m.start(), got[0]))
            skip |= lines_of(text, text.find("\n", m.start()) + 1, got[1])
            rest.append(text[at:m.start()])
            at = got[1]
    rest.append(text[at:])
    where = functions(text, skip)
    for start, body in sites:
        fn = where[text.count("\n", 0, start)]
        for mod in dict.fromkeys(imports(body)):
            found.setdefault((rel, fn, mod), 0)
            found[(rel, fn, mod)] += 1
    outside = sorted(set(loose("\n".join(rest))))
    if outside:
        problems.append(f"{rel}: imports {', '.join(outside)} from bin/lib outside a python3 -c or python3 - << site this test can read; write it as one, so {LIST} can list it")

rows = {}
try:
    lines = open(os.path.join(root, LIST), encoding="utf-8").read().split("\n")
except OSError:
    lines = []
    problems.append(f"{LIST} is missing")
for n, line in enumerate(lines, 1):
    if not line or line.startswith("#"):
        continue
    cells = line.split("\t")
    # A row's module need not still be a bin/lib file: a helper port deletes it, and its rows may stay.
    if len(cells) != 5 or not cells[3].isdigit() or int(cells[3]) < 1 or cells[4] not in EPICS or not cells[2].isidentifier():
        problems.append(f"{LIST}:{n}: not a row of file, function, module, a count of 1 or more and one of {', '.join(EPICS)}: {line!r}")
        continue
    rows[tuple(cells[:3])] = int(cells[3])

for (rel, fn, mod), n in sorted(found.items()):
    have = rows.get((rel, fn, mod))
    row = f"{rel}\t{fn}\t{mod}\t{n}\t<epic>"
    if have is None:
        problems.append(f"{rel} {fn}: {n} site(s) import {mod}, and {LIST} has no row for it; add the row {row!r}")
    elif n > have:
        problems.append(f"{rel} {fn}: {n} sites import {mod}, more than the {have} {LIST} lists; set n in its row to {n}")
print("\n".join(problems))
PY
}

check "every inline site that imports a bin/lib helper has its row in docs/port/sites.tsv" "" "$(scan "${ROOT}")"

# The scanner finds each kind of site: a -c site, a second site in one function, a site that takes its
# path from an argument, an import inside an if, and a heredoc site, with a list that has only a row
# whose module is gone.
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, as every test's: it runs no claude
mkdir -p "${dir}/bin/lib" "${dir}/hooks" "${dir}/docs/port"
touch "${dir}/bin/lib/report.py" "${dir}/bin/lib/gh_cache.py" "${dir}/bin/lib/panes.py"   # its own helpers: a port deletes the real ones
# A row whose module a port has deleted, and whose sites are gone with it, still reads.
printf '# file\tfunction\timports\tn\tepic\nbin/lib/gone.sh\tgone_site\tgone_helper\t1\thelpers-panes\n' > "${dir}/docs/port/sites.tsv"
# shellcheck disable=SC2016 # the fixture is bash source text, written as it is
printf '%s\n' \
  'one() {' \
  "  SWARM_LIB=\"\${SWARM_HOME}/bin/lib\" python3 -I -c 'import os, sys; sys.path.insert(0, os.environ[\"SWARM_LIB\"]); from report import *; print(1)'" \
  "  python3 -I -c '" \
  'import sys' \
  'sys.path.insert(0, sys.argv[1])' \
  'import gh_cache, json' \
  "' \"\$1\"" \
  "  python3 -I -c 'from report import session_log'" \
  '}' \
  'two() {' \
  "  python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1])
if True: import report' \"\$1\"" \
  "  python3 -I - \"\$1\" <<'PY'" \
  'from panes import *' \
  '}' \
  'PY' \
  '}' > "${dir}/bin/lib/fixture.sh"
check "the scanner names each site of a fixture: two -c sites in one function, an argument path, an import inside an if, a heredoc" \
  "bin/lib/fixture.sh one: 1 site(s) import gh_cache, and docs/port/sites.tsv has no row for it; add the row 'bin/lib/fixture.sh\tone\tgh_cache\t1\t<epic>'
bin/lib/fixture.sh one: 2 site(s) import report, and docs/port/sites.tsv has no row for it; add the row 'bin/lib/fixture.sh\tone\treport\t2\t<epic>'
bin/lib/fixture.sh two: 1 site(s) import panes, and docs/port/sites.tsv has no row for it; add the row 'bin/lib/fixture.sh\ttwo\tpanes\t1\t<epic>'
bin/lib/fixture.sh two: 1 site(s) import report, and docs/port/sites.tsv has no row for it; add the row 'bin/lib/fixture.sh\ttwo\treport\t1\t<epic>'" \
  "$(scan "${dir}")"

[[ ${fails} -eq 0 ]] || exit 1
