#!/usr/bin/env bash
# outcome_scan_test.sh — no reader under bin/ reads events.tsv's outcome column raw. The column may end
# in a key=value tail (append_event), so an exact compare of it ($5 == "ok", e[4] == "ok"), a slice of
# it (substr($5, ...), e[4][3:]) or an end-anchored match on it ($5 ~ /x$/, match($5, /x$/),
# re.search(r"x$", e[4])) turns false once a writer adds fields. The forms that break the same way are
# flagged too: fullmatch, endswith, a key lookup (.get, seen[$5], $h{$F[4]}) and membership (in), on
# the column itself or wrapped in .strip() or .lower(). A reader goes through the helper instead:
# outcome($5) (EVENT_OUTCOME_AWK in bin/lib/agents.sh) or events_outcome.outcome(row)
# (bin/lib/events_outcome.py, which the scan skips).
# It scans bin/swarm.sh, bin/lib/*.sh and bin/lib/*.py: the awk and perl programs in the shell by line,
# the Python (the .py files, and python3 heredocs and -c strings in the shell) by its syntax tree.
# Heredoc text that is no Python, awk or perl program is data (a brief), and is skipped; a heredoc that
# never ends fails. A Python row rebuilt as f[:4] + [outcome(f)] (or + [o], o bound from outcome()),
# and a name bound from one (or from a list of only such rows), holds the outcome without its tail, so
# its [4] is not raw. A row is a name or an item of one (rows[-1], b["f"]) or x.split(...); a name bound
# to its raw [4] is raw itself (o = f[4]; c, o = f[1], f[4]; the fifth name of an unpacked row). An awk
# variable set from $5 is not followed. A read of another file's fifth column (findings.tsv,
# test-runs.tsv, agents.tsv) ends its line with `# outcome-scan: ok <reason>`, the reason naming the
# file it reads.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# outcome_scan <file>... — one `file:line: shape: text` line per raw read of the outcome column.
outcome_scan() {
  python3 - "$@" <<'EOF'
import ast, re, sys
OK = re.compile(r"#\s*outcome-scan:\s*ok\s+\S")
COL = r"(?:\\?\$5(?!\d)|\$F\[4\])"   # awk's fifth field (\$5 in a "..." program), perl's -a fifth
CMP = r"(?:==|!=|\beq\b|\bne\b)"
ANCHORED = r"""(?:/(?:[^/\\]|\\.)*?\\?\$/|\\?"(?:[^"\\]|\\.)*?\\?\$\\?")"""   # /x$/ or "x$"
SHELL = [(re.compile(COL + r"\s*" + CMP + "|" + CMP + r"\s*" + COL), "exact compare"),
         (re.compile(r"substr\s*\(\s*" + COL), "slice"),
         (re.compile(COL + r"\s*!?=?~\s*" + ANCHORED), "end-anchored match"),
         (re.compile(r"\bmatch\s*\(\s*" + COL + r"\s*,\s*" + ANCHORED), "end-anchored match"),
         (re.compile(COL + r"\s+in\b"), "membership"),
         (re.compile(r"\w\[\s*" + COL + r"\s*\]|\{\s*\$F\[4\]\s*\}"), "dict lookup")]
HEREDOC = re.compile(r"""(?<!<)<<-?[ \t]*\\?(["']?)([A-Za-z_]\w*)\1""")   # not <<<, a here-string
PY_C = re.compile(r"""\bpython3\b[^|;&]*?\s-c\s*(['"])""")
SQ_QUOTE = re.compile(r"""'(?:\\'|"'")'""")   # '\'' and '"'"': a ' in a '...' program
EXPANSION = re.compile(r"\$(?:\{[^}]*\}|\([^)]*\)|\w+|[@*#?!$-])")
OUT = []

def marked(line):   # ends in the opt-out, as a comment: no quote before its # is left open
    return any(line.count('"', 0, m.start()) % 2 == 0 and line.count("'", 0, m.start()) % 2 == 0
               for m in OK.finditer(line))

def report(path, lines, n, shape):
    if not marked(lines[n - 1]):
        OUT.append(f"{path}:{n}: {shape}: {lines[n - 1].strip()}")

def four(node):
    s = node.slice
    s = getattr(s, "value", s) if type(s).__name__ == "Index" else s   # Python 3.8's ast
    return isinstance(s, ast.Constant) and s.value == 4

def calls(node, *names):   # a call of one of <names>, as a function or a method
    return isinstance(node, ast.Call) and getattr(node.func, "id", getattr(node.func, "attr", "")) in names

def anchored(node):   # a string pattern that ends in $ or \Z
    return isinstance(node, ast.Constant) and isinstance(node.value, str) and node.value.endswith(("$", "\\Z"))

def rebuilt(node):   # x[:4] + [<one item>]
    return isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add) and isinstance(node.left, ast.Subscript) \
        and isinstance(node.left.slice, ast.Slice) and node.left.slice.lower is None \
        and isinstance(node.left.slice.upper, ast.Constant) and node.left.slice.upper.value == 4 \
        and isinstance(node.right, ast.List) and len(node.right.elts) == 1

KINDS = ("clean", "told", "alias", "mixed", "rows", "rowlists", "anchored")

class Scan(ast.NodeVisitor):
    # Visits in source order, so what a name holds counts from where it is bound: clean, rows whose [4]
    # has no tail; told, a value from outcome(); alias, a raw [4] itself (o = f[4]); mixed, a list given
    # a row that is not clean, which no clean row added later makes clean; rows, one row from a split;
    # rowlists, a list of those; anchored, a re.compile() of a pattern that ends in $ or \Z.
    def __init__(self, path, lines, at):
        self.path, self.lines, self.at = path, lines, at
        self.names = {k: set() for k in KINDS}

    def has(self, kind, node):
        return isinstance(node, ast.Name) and node.id in self.names[kind]

    def raw(self, node):   # a raw [4]: of a row not known to be clean, an alias, or one in .strip() or .lower()
        if isinstance(node, ast.Name):
            return self.has("alias", node)
        if calls(node, "strip", "lstrip", "rstrip", "lower", "upper", "casefold") and not node.args:
            return isinstance(node.func, ast.Attribute) and self.raw(node.func.value)
        if not (isinstance(node, ast.Subscript) and four(node)):
            return False
        root = node.value   # a row: a name, an item of one (rows[-1], b["f"]) or x.split(...)
        while isinstance(root, ast.Subscript): root = root.value
        return (isinstance(root, ast.Name) or calls(root, "split")) and not self.stripped(node.value)

    def outcome(self, node):   # calls outcome(), or reads a name bound from it
        return any(self.told_value(n) for n in ast.walk(node))

    def told_value(self, node):   # is outcome(...) itself, or a name bound from it
        return calls(node, "outcome") or self.has("told", node)

    def in_comp(self, node, test):   # <test> of a comprehension's item, its targets bound as it binds them
        got = []
        def inside():
            for g in node.generators: self.bind(g.target, g.iter, True)
            got.append(test(node.elt))
        self.scoped(inside)
        return got[0]

    def stripped(self, node):   # holds clean rows only, by its shape: a clean name used as a key is not enough
        if isinstance(node, ast.Name):
            return self.has("clean", node)
        if isinstance(node, ast.Subscript):   # an item or a slice of clean rows
            return self.stripped(node.value)
        if rebuilt(node):
            return self.told_value(node.right.elts[0])
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
            return self.stripped(node.left) and self.stripped(node.right)
        if isinstance(node, ast.IfExp):   # f[:4] + [outcome(f)] if len(f) == 5 else f: a short row has no [4]
            return self.stripped(node.body)
        if isinstance(node, (ast.List, ast.Set)):
            return bool(node.elts) and all(self.stripped(e) for e in node.elts)
        if isinstance(node, ast.Tuple):   # a record such as (time, row)
            return any(self.stripped(e) for e in node.elts)
        if calls(node, "enumerate", "reversed", "sorted", "list", "tuple", "iter") and node.args:
            return self.stripped(node.args[0])
        if isinstance(node, (ast.ListComp, ast.SetComp, ast.GeneratorExp)):
            return self.in_comp(node, self.stripped)
        return False

    def split_row(self, node):   # one raw row: x.split(...) or a name bound from one
        return calls(node, "split") or self.has("rows", node)

    def split_rows(self, node):   # a list of raw rows: a name bound from one, or a comprehension of them
        if isinstance(node, (ast.ListComp, ast.GeneratorExp)):
            return self.in_comp(node, self.split_row)
        return self.has("rowlists", node)

    # bind <target> <value> [each] — the names in <target> now hold <value>, or each of its items.
    def bind(self, target, value, each=False):
        if isinstance(target, (ast.Tuple, ast.List)) and not each and isinstance(value, (ast.Tuple, ast.List)) \
                and len(value.elts) == len(target.elts):
            for t, v in zip(target.elts, value.elts): self.bind(t, v)   # c, o = f[1], f[4]
            return
        name = isinstance(target, ast.Name)
        on = {"clean": self.stripped(value), "told": not each and self.outcome(value),
              "alias": not each and name and self.raw(value), "mixed": False,
              "rows": self.split_rows(value) if each else self.split_row(value),
              "rowlists": not each and self.split_rows(value),
              "anchored": not each and calls(value, "compile") and bool(value.args) and anchored(value.args[0])}
        for n in ast.walk(target):
            if isinstance(n, ast.Name):
                for k in KINDS: (self.names[k].add if on[k] else self.names[k].discard)(n.id)
        if not name and len(getattr(target, "elts", ())) >= 5 and isinstance(target.elts[4], ast.Name) \
                and not any(isinstance(e, ast.Starred) for e in target.elts[:5]) and on["rows"]:
            self.names["alias"].add(target.elts[4].id)   # a row unpacked: its fifth name is the raw outcome
            self.names["rows"].discard(target.elts[4].id)

    def flag(self, node, shape):
        report(self.path, self.lines, self.at + node.lineno, shape)

    def visit_For(self, node):
        self.visit(node.iter); self.bind(node.target, node.iter, True)
        for s in node.body + node.orelse: self.visit(s)
    visit_AsyncFor = visit_For

    def visit_Assign(self, node):
        self.visit(node.value)
        for t in node.targets: self.bind(t, node.value)

    def visit_AnnAssign(self, node):
        if node.value: self.visit(node.value); self.bind(node.target, node.value)

    def visit_AugAssign(self, node):
        self.visit(node.value)
        if isinstance(node.target, ast.Name): self.added(node.target.id, [node.value])

    def added(self, name, values):   # <name>, a list, was given <values>: clean while each row was
        if any(self.stripped(v) for v in values) and name not in self.names["mixed"]:
            self.names["clean"].add(name)
        elif not any(self.stripped(v) for v in values):
            self.names["clean"].discard(name); self.names["mixed"].add(name)

    def visit_NamedExpr(self, node):
        self.visit(node.value); self.bind(node.target, node.value)

    def scoped(self, visit):   # what a comprehension or function binds is its own: the names outside keep theirs
        held = {k: set(v) for k, v in self.names.items()}
        visit()
        self.names = held

    def visit_comp(self, node):
        def inside():
            for g in node.generators:
                self.visit(g.iter); self.bind(g.target, g.iter, True)
                for i in g.ifs: self.visit(i)
            for f in ("elt", "key", "value"):
                if hasattr(node, f): self.visit(getattr(node, f))
        self.scoped(inside)
    visit_ListComp = visit_SetComp = visit_GeneratorExp = visit_DictComp = visit_comp

    def visit_FunctionDef(self, node):
        self.scoped(lambda: self.generic_visit(node))
    visit_AsyncFunctionDef = visit_Lambda = visit_FunctionDef

    def visit_arguments(self, node):   # its defaults read the names outside; a parameter is a row of unknown origin
        for d in node.defaults + node.kw_defaults:
            if d: self.visit(d)
        for a in node.posonlyargs + node.args + node.kwonlyargs + [node.vararg, node.kwarg]:
            if a: self.bind(ast.Name(a.arg), ast.Constant(None))

    def visit_Compare(self, node):
        lefts = [node.left] + node.comparators[:-1]
        for op, left, right in zip(node.ops, lefts, node.comparators):
            if isinstance(op, (ast.Eq, ast.NotEq)) and (self.raw(left) or self.raw(right)):
                self.flag(node, "exact compare")
            elif isinstance(op, (ast.In, ast.NotIn)) and self.raw(left):
                self.flag(node, "membership")
        self.generic_visit(node)

    def visit_Subscript(self, node):
        if isinstance(node.slice, ast.Slice) and self.raw(node.value):
            self.flag(node, "slice")
        self.generic_visit(node)

    def visit_Call(self, node):
        f, args = node.func, node.args + [k.value for k in node.keywords]
        if calls(node, "fullmatch") and any(self.raw(a) for a in args):
            self.flag(node, "fullmatch")
        elif calls(node, "search", "match") and any(self.raw(a) for a in args) and (
                node.args and anchored(node.args[0])
                or isinstance(f, ast.Attribute) and self.has("anchored", f.value)):
            self.flag(node, "end-anchored match")
        elif calls(node, "endswith") and isinstance(f, ast.Attribute) and self.raw(f.value):
            self.flag(node, "endswith")
        elif calls(node, "get") and node.args and self.raw(node.args[0]):
            self.flag(node, "dict lookup")
        elif calls(node, "append", "add", "extend", "insert") and isinstance(f, ast.Attribute) \
                and isinstance(f.value, ast.Name):
            self.added(f.value.id, node.args)
        self.generic_visit(node)

def scan_python(path, lines, code, at=0):
    try:
        tree = ast.parse(code)
    except SyntaxError as e:
        OUT.append(f"{path}:{at + (e.lineno or 1)}: Python that does not parse: {e.msg}")
        return
    Scan(path, lines, at).visit(tree)

# python_c <text> <quote> — the -c program in <text> up to its closing <quote>, as python3 gets it,
# with each shell expansion in a "..." program read as a name; None when it does not close there.
def python_c(text, q):
    out, i = [], 0
    while i < len(text):
        if q == "'" and (m := SQ_QUOTE.match(text, i)):
            out.append("'"); i = m.end(); continue
        if q == '"' and text[i] == "\\" and text[i + 1:i + 2] in ('"', "\\", "$", "`"):
            out.append(text[i + 1]); i += 2; continue
        if q == '"' and (m := EXPANSION.match(text, i)):
            out.append("_shell_"); i = m.end(); continue
        if text[i] == q:
            return "".join(out)
        out.append(text[i]); i += 1
    return None

def scan_shell(path, lines):
    i, cmd = 0, ""   # cmd: the command so far, its lines joined where one ends in a \
    while i < len(lines):
        line, n = lines[i], i + 1
        i += 1
        if line.lstrip().startswith("#"):
            continue
        cmd = (cmd if cmd.endswith("\\") else "") + line
        for rx, shape in SHELL:
            if rx.search(line):
                report(path, lines, n, shape)
        for m in PY_C.finditer(cmd):
            if m.end() <= len(cmd) - len(line):
                continue   # its -c is on a line before, which scanned it
            j, text = i, cmd[m.end():]
            while (code := python_c(text, m.group(1))) is None and j < len(lines):
                text += "\n" + lines[j]; j += 1
            if code is not None:
                scan_python(path, lines, code, n - 1)
        for h in HEREDOC.finditer(line):
            before = line[:h.start()]
            if before.count("((") > before.count("))") or before.count('"') % 2 or before.count("'") % 2:
                continue   # a shift in $(( )), or << in a string
            d, body = h.group(2), i
            while i < len(lines) and lines[i].strip() != d: i += 1
            if i == len(lines):
                OUT.append(f"{path}:{n}: heredoc {d} never ends, so the rest of the file goes unread")
            if re.search(r"\bpython3\b", cmd):
                scan_python(path, lines, "\n".join(lines[body:i]), body)
            elif re.search(r"\b(?:awk|perl)\b", cmd):   # a program on stdin: awk -f -, perl -
                for k in range(body, i):
                    for rx, shape in SHELL:
                        if rx.search(lines[k]): report(path, lines, k + 1, shape)
            i += 1

for path in sys.argv[1:]:
    with open(path, encoding="utf-8", errors="replace") as fh:
        lines = fh.read().split("\n")
    if path.endswith(".py"):
        scan_python(path, lines, "\n".join(lines))
    else:
        scan_shell(path, lines)
print("\n".join(OUT), end="\n" if OUT else "")
EOF
}

# scan_files <repo> — what the scan reads under <repo>: bin/swarm.sh, bin/lib/*.sh and bin/lib/*.py,
# less the helper bin/lib/events_outcome.py.
scan_files() {
  local f
  for f in "$1"/bin/swarm.sh "$1"/bin/lib/*.sh "$1"/bin/lib/*.py; do
    [[ -f "${f}" && "${f}" != "$1/bin/lib/events_outcome.py" ]] && echo "${f#"$1"/}"
  done
  return 0
}

fails=0
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
export CLAUDE_CONFIG_DIR="${tmp}/claude-config"   # under its own root, as every test file

scan=(); while IFS= read -r f; do scan+=("${f}"); done < <(scan_files "${REPO}")
if [[ ${#scan[@]} -eq 0 ]]; then
  echo "FAIL no file to scan under bin/"; fails=$((fails + 1))
elif ! found="$(cd "${REPO}" && outcome_scan "${scan[@]}")"; then
  echo "FAIL the outcome scanner itself failed on bin/"; fails=$((fails + 1))
elif [[ -n "${found}" ]]; then
  echo "FAIL a raw read of events.tsv's outcome column in bin/ (read it through outcome(), or end the line with # outcome-scan: ok <the file it reads>):"
  echo "${found}"; fails=$((fails + 1))
else echo "ok   no raw read of the outcome column in bin/"; fi

# shellcheck disable=SC2016 # the fixtures' $5 and ${x} are for the scanner, not this shell
cat > "${tmp}/loose.sh" <<'FIXTURE'
awk -F'\t' '$2 == "story" && $5 == "ok" { n++ }' "${EVENTS_LOG}"
awk -F'\t' '"ok" != $5' "${f}"
awk -F'\t' '{ print substr($5, 8) }' "${f}"
awk -F'\t' '$5 ~ /x$/' "${f}"
awk -F'\t' '$5 !~ "done$"' "${f}"
perl -F'\t' -lane 'print if $F[4] eq "ok"' "${f}"
perl -F'\t' -lane 'print substr($F[4], 3)' "${f}"
perl -F'\t' -lane 'print if $F[4] =~ /ok$/' "${f}"
awk -F'\t' "\$5 == \"ok\"" "${f}"
python3 -c 'import sys; f = sys.argv[1].split("\t"); print(f[4] == "ok")' "${x}"
python3 - "${f}" <<'PY'
f = input().split("\t")
print(f[4].endswith("x"))
PY
python3 -c 'print("it'\''s", f[4] == "ok")'
python3 -c "print(f[4] == $1)"
python3 -I -c '
import sys
print(sys.argv[1].split("\t")[4], f[4] != "ok")' "${x}"
read -r x <<< "ok"
awk -F'\t' "\$5 ~ /x\$/" "${f}"
python3 - "${f}" \
  "${g}" <<'PY'
f = input().split("\t")
print(f[4] == "ok")
PY
python3 -I \
  -c 'import sys; f = sys.argv[1].split("\t"); print(f[4] == "ok")' "${x}"
awk -F'\t' -f - "${f}" <<'AWK'
$5 == "ok" { n++ }
AWK
awk -F'\t' '{ print substr ($5, 8) }' "${f}"
awk -F'\t' '$5 == "ok" { print "# outcome-scan: ok findings.tsv" }' "${f}"
awk -F'\t' "{ print substr(\$5, 8) }" "${f}"
awk -F'\t' "\"ok\" == \$5" "${f}"
python3 -c 'print(1)'; python3 -c 'import sys; f = sys.argv[1].split("\t"); print(f[4] == "ok")' "${x}"
n=$(( 1 << shift ))
awk -F'\t' '$5 == "ok"' "${f}"
echo "a << b"
awk -F'\t' '$5 != "ok"' "${f}"
awk -F'\t' 'match($5, /ok$/)' "${f}"
awk -F'\t' '($5 in seen) { n++ }' "${f}"
awk -F'\t' '{ seen[$5]++ }' "${f}"
perl -F'\t' -lane '$h{$F[4]}++' "${f}"
FIXTURE
cat > "${tmp}/loose.py" <<'FIXTURE'
import re, sys
f = sys.stdin.readline().split("\t")
a = f[4] == "ok"
b = f[4][3:]
c = re.fullmatch(r"ok \(\d+\)", f[4])
d = f[4].endswith(")")
e = {"ok": 1}.get(f[4])
g = f[4] in ("ok", "done")
def h(row):
    return row[4] != "ok"
f = f[:4] + ["ok"]
f = sys.stdin.readline().split("\t")
i = f[4] == "ok"
rows = [r[:4] + [r[4]] for r in []]
rows = []
j = [r for r in rows if r[4] == "ok"]
o = f[4]
k = o == "ok"
rows = [r[:4] + [r[4]] for r in [f]]
m = [r for r in rows if r[4] == "ok"]
o = outcome(f)
rows = [r[:4] + [r[4] if o else o] for r in [f]]
p = [r for r in rows if r[4] == "ok"]
q = [f for _, f in [(0, f[:4] + [o])]]
s = f[4] == "ok"
from re import fullmatch
u = fullmatch("ok", f[4])
v = re.fullmatch("ok", string=f[4])
w = sys.stdin.readline().split("\t")[4] == "ok"
evs = []
evs.append((0, f[:4] + [outcome(f)]))
evs.append((0, f))
evs.append((0, f[:4] + [outcome(f)]))
y = [e for _, e in evs if e[4] == "ok"]
evs = [(0, f[:4] + [outcome(f)])]
evs += [(0, f)]
z = [e for _, e in evs if e[4] == "ok"]
print("# outcome-scan: ok findings.tsv", f[4] == "ok")
f = sys.stdin.readline().split("\t")
def local(f):
    f = f[:4] + [outcome(f)]
    return f[4] == "ok"
aa = f[4] == "ok"
def done(ok=f[4] == "ok"):
    return ok
cmd, o = f[1], f[4]
ab = o == "ok"
t, cmd, slug, who, out = line.split("\t")
ac = out == "ok"
rows = [l.split("\t") for l in sys.stdin]
for _, c, s, w, out in rows:
    ad = out == "ok"
ae = re.search(r"done$", f[4])
af = re.match(r"ok \(\d+\)$", f[4])
PAT = re.compile(r"ok\Z")
ag = PAT.search(f[4])
ah = rows[-1][4] == "ok"
ai = b["f"][4] == "ok"
aj = f[4].strip() == "ok"
ak = f[4].lower() in ("ok",)
g = f[:4] + [outcome(f)]
by_story = {l.split("\t")[0]: l.split("\t") for l in sys.stdin}
e = by_story.get(g[0], [])
al = e[4] == "ok"
st = by_story[g[0]]
am = st[4] == "ok"
rows = [f[:4] + [outcome(f)], f]
an = [r for r in rows if r[4] == "ok"]
FIXTURE
cat > "${tmp}/tight.sh" <<'FIXTURE'
awk -F'\t' "${EVENT_OUTCOME_AWK}"'$2 == "story" && outcome($5) == "ok"' "${f}"
awk -F'\t' "${EVENT_OUTCOME_AWK}"'{ o = outcome($5) } o ~ /^ok/ && substr(o, 1, 2) == "ok"' "${f}"
awk -F'\t' '$5 ~ /^ok/ && index($5, "ok") == 1 { print $5, $15 == "x", $55 != 1 }' "${f}"
awk -F'\t' '$5 == "declined"' "${f}"   # outcome-scan: ok findings.tsv's outcome
# awk -F'\t' '$5 == "ok"' "${f}" in a comment
cat <<EOF
awk -F'\t' '\$5 == "fixed"' is text in a brief
EOF
python3 -c 'import sys; print(sys.argv[4] == "1")' a b c d
python3 - <<'PY'
import re, sys
from events_outcome import outcome
rows = [f[:4] + [outcome(f)] for f in (l.split("\t") for l in sys.stdin)]
for n, f in enumerate(rows):
    print(f[4] == "ok", f[4][3:], {}.get(f[4]))
evs = []
for line in sys.stdin:
    e = line.split("\t")
    evs.append((0, e[:4] + [outcome(e)]))
for t, e in evs:
    print(e[4] == "ok (reopened)", e[4][len("ok ("):-1])
f = line.split("\t")
f = f[:4] + [outcome(f)] if len(f) == 5 else f
print(f[4] == "ok", re.fullmatch("x", f[4]), f[4] in ("ok",))
g = line.split("\t")
print(g[4].startswith("ok"), "ok" in g[4], g[4] + "x", sys.argv[4] == "x")
print(g[4] == "all")   # outcome-scan: ok test-runs.tsv's filter
o = outcome(g)
evs.append((0, g[:4] + [o]))
for t, e in evs:
    print(e[4] == "ok")
o = g[4]
o = outcome(g)
print(o == "ok", o.endswith("x"))
PY
n=$(( 1 << 2 ))
echo "a << b"
python3 - <<'PY'
import re, sys
from events_outcome import outcome
g = sys.stdin.readline().split("\t")
print(re.match("ok", g[4]), re.search("^ok", g[4]), g[4].strip().startswith("ok"))
evs = [(0, g[:4] + [outcome(g)])]
for r in [e for _, e in evs]:
    print(r[4] == "ok", r[4].strip() == "ok")
PY
FIXTURE
got="$(outcome_scan "${tmp}/loose.sh" "${tmp}/loose.py")" || got="the scanner failed"
# shellcheck disable=SC2001 # a sed over many lines
got="$(sed 's/^[^:]*\/\([^/:]*\):\([0-9]*\): \([^:]*\):.*/\1:\2 \3/' <<< "${got}")"
x='exact compare'
want="$(printf '%s\n' "loose.sh:1 ${x}" "loose.sh:2 ${x}" "loose.sh:3 slice" "loose.sh:4 end-anchored match" \
  "loose.sh:5 end-anchored match" "loose.sh:6 ${x}" "loose.sh:7 slice" "loose.sh:8 end-anchored match" "loose.sh:9 ${x}" \
  "loose.sh:10 ${x}" "loose.sh:13 endswith" "loose.sh:15 ${x}" "loose.sh:16 ${x}" "loose.sh:19 ${x}" \
  "loose.sh:21 end-anchored match" "loose.sh:25 ${x}" "loose.sh:28 ${x}" "loose.sh:30 ${x}" \
  "loose.sh:32 slice" "loose.sh:33 ${x}" "loose.sh:34 slice" "loose.sh:35 ${x}" "loose.sh:36 ${x}" \
  "loose.sh:38 ${x}" "loose.sh:40 ${x}" "loose.sh:41 end-anchored match" "loose.sh:42 membership" \
  "loose.sh:43 dict lookup" "loose.sh:44 dict lookup" \
  "loose.py:3 ${x}" "loose.py:4 slice" "loose.py:5 fullmatch" "loose.py:6 endswith" "loose.py:7 dict lookup" \
  "loose.py:8 membership" "loose.py:10 ${x}" "loose.py:13 ${x}" "loose.py:16 ${x}" "loose.py:18 ${x}" "loose.py:20 ${x}" \
  "loose.py:23 ${x}" "loose.py:25 ${x}" "loose.py:27 fullmatch" "loose.py:28 fullmatch" "loose.py:29 ${x}" "loose.py:34 ${x}" \
  "loose.py:37 ${x}" "loose.py:38 ${x}" "loose.py:43 ${x}" "loose.py:44 ${x}" \
  "loose.py:47 ${x}" "loose.py:49 ${x}" "loose.py:52 ${x}" "loose.py:53 end-anchored match" \
  "loose.py:54 end-anchored match" "loose.py:56 end-anchored match" "loose.py:57 ${x}" "loose.py:58 ${x}" \
  "loose.py:59 ${x}" "loose.py:60 membership" "loose.py:64 ${x}" "loose.py:66 ${x}" "loose.py:68 ${x}")"
if [[ "${got}" == "${want}" ]]; then
  echo "ok   a fixture with each raw read fails, naming its file:line"
else
  echo "FAIL a fixture with each raw read: want"; echo "${want}"; echo "got"; echo "${got}"; fails=$((fails + 1))
fi
if got="$(outcome_scan "${tmp}/tight.sh")" && [[ -z "${got}" ]]; then
  echo "ok   outcome(), a prefix match, a rebuilt row, heredoc text and the opt-out pass"
else
  echo "FAIL the tight fixture still reports:"; echo "${got}"; fails=$((fails + 1))
fi
cat > "${tmp}/open.sh" <<'FIXTURE'
cat <<BRIEF
awk -F'\t' '$5 == "ok"' "${f}"
FIXTURE
if got="$(outcome_scan "${tmp}/open.sh")" && [[ "${got}" == *"open.sh:1: heredoc BRIEF never ends, so the rest of the file goes unread" ]]; then
  echo "ok   a heredoc that never ends fails rather than leaving the rest of the file unread"
else
  echo "FAIL a heredoc that never ends: got"; echo "${got}"; fails=$((fails + 1))
fi
printf 'f = (\n' > "${tmp}/broken.py"
if got="$(outcome_scan "${tmp}/broken.py")" && [[ "${got}" == *"broken.py:"*": Python that does not parse:"* ]]; then
  echo "ok   Python the scanner cannot parse fails rather than passing unread"
else
  echo "FAIL Python that does not parse: got"; echo "${got}"; fails=$((fails + 1))
fi

mkdir -p "${tmp}/repo/bin/lib"
: > "${tmp}/repo/bin/swarm.sh"; : > "${tmp}/repo/bin/lib/a.sh"; : > "${tmp}/repo/bin/lib/b.py"
: > "${tmp}/repo/bin/lib/events_outcome.py"; : > "${tmp}/repo/bin/c.sh"; : > "${tmp}/repo/bin/lib/d.txt"
got="$(scan_files "${tmp}/repo")"
if [[ "${got}" == $'bin/swarm.sh\nbin/lib/a.sh\nbin/lib/b.py' ]]; then
  echo "ok   the scan reads bin/swarm.sh and every bin/lib/*.sh and *.py but the helper"
else
  echo "FAIL the scan's file list: want bin/swarm.sh, bin/lib/a.sh, bin/lib/b.py, got:"; echo "${got}"; fails=$((fails + 1))
fi

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
