#!/usr/bin/env bash
# outcome_scan_test.sh — no reader under bin/ reads events.tsv's outcome column raw. The column may end
# in a key=value tail (append_event), so an exact compare of it ($5 == "ok", e[4] == "ok"), a slice of
# it (substr($5, ...), e[4][3:]) or an end-anchored match on it ($5 ~ /x$/) turns false once a writer
# adds fields. The Python forms that break the same way are flagged too: fullmatch, endswith, a dict
# .get and membership (in). A reader goes through the helper instead: outcome($5) (EVENT_OUTCOME_AWK in
# bin/lib/agents.sh) or events_outcome.outcome(row) (bin/lib/events_outcome.py, which the scan skips).
# It scans bin/swarm.sh, bin/lib/*.sh and bin/lib/*.py: the awk and perl programs in the shell by line,
# the Python (the .py files, and python3 heredocs and -c strings in the shell) by its syntax tree.
# Heredoc text that is no Python, awk or perl program is data (a brief), and is skipped. A Python row
# rebuilt as f[:4] + [outcome(f)] (or + [o], o bound from outcome()), and a name bound from one (or
# from a list one was added to, and no other row), holds the outcome without its tail, so its [4] is
# not raw; a name bound to a raw [4] (o = f[4]) is raw itself. An awk variable set from $5 is not
# followed. A read of another file's fifth column (findings.tsv, test-runs.tsv) ends its line with
# `# outcome-scan: ok <reason>`, the reason naming the file it reads.
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
SHELL = [(re.compile(COL + r"\s*" + CMP + "|" + CMP + r"\s*" + COL), "exact compare"),
         (re.compile(r"substr\s*\(\s*" + COL), "slice"),
         (re.compile(COL + r"""\s*!?=?~\s*(?:/(?:[^/\\]|\\.)*?\\?\$/|\\?"(?:[^"\\]|\\.)*?\\?\$\\?")"""), "end-anchored match")]
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

class Scan(ast.NodeVisitor):
    # Visits in source order, so what a name holds counts from where it is bound: clean, a row whose
    # [4] has no tail; told, a value from outcome(); alias, a raw [4] itself (o = f[4]); mixed, a list
    # given a row that is not clean, which no clean row added later makes clean.
    def __init__(self, path, lines, at):
        self.path, self.lines, self.at = path, lines, at
        self.clean, self.told, self.alias, self.mixed = set(), set(), set(), set()

    def raw(self, node):   # <name>[4] of a name not known to be clean, x.split(...)[4], or an alias
        if isinstance(node, ast.Name):
            return node.id in self.alias
        return isinstance(node, ast.Subscript) and four(node) and (
            isinstance(node.value, ast.Name) and node.value.id not in self.clean
            or isinstance(node.value, ast.Call) and getattr(node.value.func, "attr", "") == "split")

    def outcome(self, node):   # calls outcome(), or reads a name bound from it
        return any(self.told_value(n) for n in ast.walk(node))

    def told_value(self, node):   # is outcome(...) itself, or a name bound from it
        return isinstance(node, ast.Call) and getattr(node.func, "id", getattr(node.func, "attr", "")) == "outcome" \
            or isinstance(node, ast.Name) and node.id in self.told

    def stripped(self, node):   # holds a row rebuilt as x[:4] + [outcome(x)] or + [o], or a clean name
        for n in ast.walk(node):
            if isinstance(n, ast.BinOp) and isinstance(n.op, ast.Add) and isinstance(n.left, ast.Subscript) \
                    and isinstance(n.left.slice, ast.Slice) and n.left.slice.lower is None \
                    and isinstance(n.left.slice.upper, ast.Constant) and n.left.slice.upper.value == 4 \
                    and isinstance(n.right, ast.List) and len(n.right.elts) == 1 and self.told_value(n.right.elts[0]):
                return True
            if isinstance(n, ast.Name) and n.id in self.clean:
                return True
        return False

    # bind <target> <value> [each] — the names in <target> now hold <value>, or each of its items.
    def bind(self, target, value, each=False):
        on = (self.stripped(value), not each and self.outcome(value),
              not each and isinstance(target, ast.Name) and self.raw(value))
        for n in ast.walk(target):
            if isinstance(n, ast.Name):
                self.mixed.discard(n.id)
                for names, add in zip((self.clean, self.told, self.alias), on):
                    (names.add if add else names.discard)(n.id)

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
        if any(self.stripped(v) for v in values) and name not in self.mixed:
            self.clean.add(name)
        elif not any(self.stripped(v) for v in values):
            self.clean.discard(name); self.mixed.add(name)

    def visit_NamedExpr(self, node):
        self.visit(node.value); self.bind(node.target, node.value)

    def scoped(self, visit):   # what a comprehension or function binds is its own: the names outside keep theirs
        held = [set(names) for names in (self.clean, self.told, self.alias, self.mixed)]
        visit()
        self.clean, self.told, self.alias, self.mixed = held

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
        f = node.func
        args = node.args + [k.value for k in node.keywords]
        if isinstance(f, ast.Name) and f.id == "fullmatch" and any(self.raw(a) for a in args):
            self.flag(node, "fullmatch")
        if isinstance(f, ast.Attribute):
            if f.attr == "endswith" and self.raw(f.value):
                self.flag(node, "endswith")
            elif f.attr == "fullmatch" and any(self.raw(a) for a in args):
                self.flag(node, "fullmatch")
            elif f.attr == "get" and node.args and self.raw(node.args[0]):
                self.flag(node, "dict lookup")
            elif f.attr in ("append", "add", "extend", "insert") and isinstance(f.value, ast.Name):
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
        for d in [h.group(2) for h in HEREDOC.finditer(line)]:
            body = i
            while i < len(lines) and lines[i].strip() != d: i += 1
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
print(g[4].startswith("ok"), "ok" in g[4], g[4] + "x", b["f"][4] == "x", sys.argv[4] == "x")
print(g[4] == "all")   # outcome-scan: ok test-runs.tsv's filter
o = outcome(g)
evs.append((0, g[:4] + [o]))
for t, e in evs:
    print(e[4] == "ok")
o = g[4]
o = outcome(g)
print(o == "ok", o.endswith("x"))
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
  "loose.py:3 ${x}" "loose.py:4 slice" "loose.py:5 fullmatch" "loose.py:6 endswith" "loose.py:7 dict lookup" \
  "loose.py:8 membership" "loose.py:10 ${x}" "loose.py:13 ${x}" "loose.py:16 ${x}" "loose.py:18 ${x}" "loose.py:20 ${x}" \
  "loose.py:23 ${x}" "loose.py:25 ${x}" "loose.py:27 fullmatch" "loose.py:28 fullmatch" "loose.py:29 ${x}" "loose.py:34 ${x}" \
  "loose.py:37 ${x}" "loose.py:38 ${x}" "loose.py:43 ${x}" "loose.py:44 ${x}")"
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
