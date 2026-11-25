#!/usr/bin/env bash
# port_copies_test.sh — docs/port/copies.tsv names what still imports each of the five Python modules
# that keep a copy beside their Go (clock, events_outcome, report, touches_rows, gh_cache), so a copy
# goes with its last importer and not before. The counting rule, one row per module, importer and kind:
#   py      a bin/lib/*.py file whose code imports the module (`import X` or `from X import`, as Python's
#           parser finds it, so an import inside a function counts). The importer is the file.
#   site    a python3 -c '...', -c "..." or python3 - << heredoc in a file under bin/ or hooks/ that is not
#           a .py file, whose code imports the module. The importer is <file>:<function>, the bash
#           function holding the site, or (top) outside any.
#   script  a python3 command on a line of such a file, outside a heredoc and not a comment, that runs
#           bin/lib/<module>.py by its path. The importer is <file>:<function>.
#   test    a tests/*.sh with a python3 -c or - << site whose code imports the module, or a python3 line
#           that runs bin/lib/<module>.py by its path, as script reads it. The importer is the file. This
#           file and tests/port_sites_test.sh are left out: their sites are scanner fixtures that import
#           the stand-in modules of trees of their own. A .py file a test writes is not read, and a test
#           that only copies or reads a module's file (lint_test.sh copies clock.py) is not counted.
# A site or script line in a comment, or inside another heredoc's body (text written to a file, such as
# outcome_scan_test.sh's fixtures for its scanner), is not counted: nothing runs it there.
# A module's own file is no importer of it; what a module imports in turn is that module's own py row.
# It fails, naming the module and the importer, on an importer with no row, on a row whose importer no
# longer imports its module, on each row of a module whose bin/lib/<module>.py is gone, and on a module
# file with no row left. It fails on a row it cannot read too. Files are listed by a walk of the
# folders, not git, so it runs the same on a copy without .git.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# scan <root> — one line per problem with <root>'s docs/port/copies.tsv, in the order of the header's checks.
scan() {
  python3 -I - "$1" <<'PY'
import ast, os, re, sys

root = sys.argv[1]
LIST = "docs/port/copies.tsv"
MODULES = ("clock", "events_outcome", "report", "touches_rows", "gh_cache")
KINDS = ("py", "site", "script", "test")
FIXTURES = ("tests/port_copies_test.sh", "tests/port_sites_test.sh")

# A python3 word that is a command, then its flags, then -c and a quoted body or - and a heredoc. The
# words may sit on lines joined by a backslash.
SP = r"(?:[ \t]|\\\n)+"
RUN = re.compile(r"(?<![\w./-])python3((?:" + SP + r"-[A-Za-z]+)*)" + SP + r"(-c" + SP + r"|-(?=[ \t]|\\\n))")
HEREDOC = re.compile(r"<<-?[ \t]*(['\"]?)(\w+)\1")
DEF = re.compile(r"^([ \t]*)(?:function[ \t]+)?([A-Za-z_][\w:-]*)[ \t]*\(\)[ \t]*\{(.*)$")
SCRIPT = re.compile(r"(?<![\w./-])python3\b.*/(" + "|".join(MODULES) + r")\.py\b")


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
    """The body of the first heredoc on the line holding text[i], and the index past its end, or None."""
    eol = text.find("\n", i)
    m = HEREDOC.search(text, i, len(text) if eol < 0 else eol)
    if not m or eol < 0:
        return None
    end = re.compile(r"(?m)^[ \t]*" + re.escape(m.group(2)) + r"$").search(text, eol + 1)
    return (text[eol + 1:end.start()], end.end()) if end else None


def imports(code):
    """The five modules the code imports, as Python's parser finds them; for code it cannot parse, the
    names after `from` or `import`."""
    try:
        tree = ast.parse(code)
        got = [a.name for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names]
        got += [n.module for n in ast.walk(tree) if isinstance(n, ast.ImportFrom) and n.module and not n.level]
    except (SyntaxError, ValueError):
        got = []
        for m in re.finditer(r"\bfrom[ \t]+([\w.]+)[ \t]+import\b|\bimport[ \t]+([\w., \t]+)", code):
            got += [m.group(1)] if m.group(1) else [p.split()[0] for p in m.group(2).split(",") if p.split()]
    return {g.split(".")[0] for g in got} & set(MODULES)


def line_of(text, i):
    return text.count("\n", 0, i) + 1


def sites(text):
    """(line of the python3 word, the modules its code imports) for each site, and the heredoc body lines."""
    body_lines, got, at = set(), [], 0
    for m in HEREDOC.finditer(text):
        h = heredoc(text, m.start())
        if h:
            body_lines |= set(range(line_of(text, m.start()) + 1, line_of(text, h[1])))
    for m in RUN.finditer(text):
        start = text.rfind("\n", 0, m.start()) + 1
        # A site in a comment, or in another heredoc's body (text a test writes for a scanner), runs nothing.
        if m.start() < at or text[start:m.start()].lstrip().startswith("#") or line_of(text, m.start()) in body_lines:
            continue
        h = quoted(text, m.end()) if m.group(2).startswith("-c") else heredoc(text, m.end())
        if h:
            got.append((line_of(text, m.start()), imports(h[0])))
            at = h[1]
    return got, body_lines


def functions(lines, skip):
    """For each line number, the name of the innermost bash function it sits in, or (top)."""
    names, stack = {}, []
    for n, line in enumerate(lines, 1):
        names[n] = stack[-1][1] if stack else "(top)"
        if n in skip:
            continue
        m = DEF.match(line)
        if m:
            names[n] = m.group(2)
            if not re.search(r"\}[ \t;]*(#.*)?$", m.group(3)):
                stack.append((m.group(1), m.group(2)))
        elif stack and line.rstrip() == stack[-1][0] + "}":
            stack.pop()
    return names


def runs(lines, body_lines):
    """(line number, module) for each line, outside a heredoc body and not a comment, where python3 runs
    bin/lib/<module>.py by its path."""
    for n, line in enumerate(lines, 1):
        m = SCRIPT.search(line)
        if m and n not in body_lines and not line.lstrip().startswith("#"):
            yield n, m.group(1)


def read(rel):
    try:
        return open(os.path.join(root, rel), encoding="utf-8").read()
    except (UnicodeDecodeError, OSError):
        return None


found, problems = set(), []
lib = os.path.join(root, "bin", "lib")
for f in sorted(os.listdir(lib)) if os.path.isdir(lib) else []:
    rel, text = "bin/lib/" + f, read("bin/lib/" + f)
    if not f.endswith(".py") or text is None:
        continue
    try:
        ast.parse(text)
    except (SyntaxError, ValueError):
        problems.append(f"{rel}: Python cannot parse it, so its imports cannot be read")
        continue
    found |= {(mod, rel, "py") for mod in imports(text) if mod != f[:-3]}

bash_files = sorted(os.path.relpath(os.path.join(d, f), root)
                    for top in ("bin", "hooks") for d, sub, names in os.walk(os.path.join(root, top))
                    if "__pycache__" not in d.split(os.sep) for f in names if not f.endswith((".py", ".pyc")))
for rel in bash_files:
    text = read(rel)
    if text is None:
        continue
    got, body_lines = sites(text)
    lines = text.split("\n")
    where = functions(lines, body_lines)
    found |= {(mod, f"{rel}:{where[n]}", "site") for n, mods in got for mod in mods}
    found |= {(mod, f"{rel}:{where[n]}", "script") for n, mod in runs(lines, body_lines)}

tests = os.path.join(root, "tests")
for f in sorted(os.listdir(tests)) if os.path.isdir(tests) else []:
    rel = "tests/" + f
    text = read(rel) if f.endswith(".sh") and rel not in FIXTURES else None
    if text is not None:
        got, body_lines = sites(text)
        found |= {(mod, rel, "test") for _, mods in got for mod in mods}
        found |= {(mod, rel, "test") for _, mod in runs(text.split("\n"), body_lines)}

rows = {}
for n, line in enumerate((read(LIST) or "").split("\n"), 1):
    if not line or line.startswith("#"):
        continue
    cells = tuple(line.split("\t"))
    if len(cells) != 3 or cells[0] not in MODULES or cells[2] not in KINDS or not cells[1]:
        problems.append(f"{LIST}:{n}: not a row of one of {', '.join(MODULES)}, an importer and one of {', '.join(KINDS)}: {line!r}")
    elif cells in rows:
        problems.append(f"{LIST}:{n}: {cells[1]} ({cells[2]}) is listed for {cells[0]} twice, first on line {rows[cells]}")
    else:
        rows[cells] = n
if read(LIST) is None:
    problems.append(f"{LIST} is missing")

for mod, imp, kind in sorted(found - set(rows)):
    problems.append(f"{imp} imports {mod} ({kind}), and {LIST} has no row for it; add the row {mod + chr(9) + imp + chr(9) + kind!r}")
for (mod, imp, kind), n in sorted(rows.items(), key=lambda r: r[1]):
    if (mod, imp, kind) not in found:
        problems.append(f"{LIST}:{n}: {imp} no longer imports {mod} ({kind}); delete the row")
for (mod, imp, kind), n in sorted(rows.items(), key=lambda r: r[1]):
    if not os.path.isfile(os.path.join(lib, mod + ".py")):
        problems.append(f"{LIST}:{n}: bin/lib/{mod}.py is gone, but its row for {imp} ({kind}) remains; port that importer before the copy goes")
for mod in MODULES:
    if os.path.isfile(os.path.join(lib, mod + ".py")) and not any(r[0] == mod for r in rows):
        problems.append(f"bin/lib/{mod}.py has no row in {LIST}, so nothing is left importing it; delete the copy, or add the row of what still imports it")
print("\n".join(problems))
PY
}

check "docs/port/copies.tsv names every importer of the five Python copies, and only those" "" "$(scan "${ROOT}")"

dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export CLAUDE_CONFIG_DIR="${dir}/claude-config"   # under its own root, as every test's: it runs no claude
HEAD_ROW='# module\timporter\tkind\n'

# A tree with one importer of each kind, a lazy import, a site continued over two lines, a commented-out
# site, a site in a heredoc that only writes a file and a test that runs a copy by its path, a row whose importer
# stopped importing, an importer with no row, and a module whose file is gone while its row stays.
t="${dir}/kinds"
mkdir -p "${t}/bin/lib" "${t}/hooks" "${t}/tests" "${t}/docs/port"
touch "${t}/bin/lib/clock.py" "${t}/bin/lib/report.py" "${t}/bin/lib/touches_rows.py" "${t}/bin/lib/gh_cache.py"
printf 'import clock\n\n\ndef late():\n    from report import pr_key\n' > "${t}/bin/lib/a.py"
# shellcheck disable=SC2016 # the fixture is bash source text, written as it is
printf '%s\n' \
  'one() {' \
  "  python3 -I -c 'import sys; from gh_cache import get' \"\$1\"" \
  "  python3 -I - <<'X'" \
  'import touches_rows' \
  '}' \
  'X' \
  '  python3 "${SWARM_HOME}/bin/lib/touches_rows.py" --idle' \
  "  python3 -I \\" "    -c 'import clock'" \
  "  # python3 -c 'import report'" \
  '}' > "${t}/hooks/x.sh"
printf '%s\n' "python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import events_outcome as e, report' \"\$LIB\"" \
  "cat > \"\$tmp/scanned.sh\" <<'FIXTURE'" "python3 -c 'import gh_cache'" 'FIXTURE' > "${t}/tests/t_test.sh"
# shellcheck disable=SC2016 # the fixture is bash source text, written as it is
printf '%s\n' 'out="$(python3 "${REPO}/bin/lib/touches_rows.py" --idle)"' > "${t}/tests/u_test.sh"
# shellcheck disable=SC2059 # the format is the fixture's rows
printf "${HEAD_ROW}clock\tbin/lib/a.py\tpy\nreport\tbin/lib/a.py\tpy\ngh_cache\thooks/x.sh:one\tsite\ntouches_rows\thooks/x.sh:one\tsite\ntouches_rows\thooks/x.sh:one\tscript\nevents_outcome\ttests/t_test.sh\ttest\nreport\tbin/lib/gone.py\tpy\nclock\thooks/x.sh:one\tsite\ntouches_rows\ttests/u_test.sh\ttest\n" > "${t}/docs/port/copies.tsv"
check "the scan finds each kind, and names the module and importer of each problem" \
  "tests/t_test.sh imports report (test), and docs/port/copies.tsv has no row for it; add the row 'report\ttests/t_test.sh\ttest'
docs/port/copies.tsv:8: bin/lib/gone.py no longer imports report (py); delete the row
docs/port/copies.tsv:7: bin/lib/events_outcome.py is gone, but its row for tests/t_test.sh (test) remains; port that importer before the copy goes" \
  "$(scan "${t}")"

# A module's file kept after its last importer and that importer's row are both gone.
t="${dir}/left"
mkdir -p "${t}/bin/lib" "${t}/docs/port"
touch "${t}/bin/lib/clock.py"
# shellcheck disable=SC2059 # the format is the header row
printf "${HEAD_ROW}" > "${t}/docs/port/copies.tsv"
check "a module file left with no importer and no row is named" \
  "bin/lib/clock.py has no row in docs/port/copies.tsv, so nothing is left importing it; delete the copy, or add the row of what still imports it" \
  "$(scan "${t}")"

[[ ${fails} -eq 0 ]] || exit 1
