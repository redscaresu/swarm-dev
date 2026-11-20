#!/usr/bin/env bash
# port_fields_test.sh — docs/port/fields.tsv names each board front-matter field the code reads, by file
# kind, with the functions that read it (read_by). Each row needs at least one read_by entry that is
# still a function in its file, under bin/, hooks/, cmd/ or internal/ (never a *_test.go), whose body
# names the field as a whole word: a bash `name() {`, a Python `def name(` (or `<file>:__main__`, the
# file's `if __name__ == "__main__":` block), or a Go `func Name(` or method. Full-line comments do not
# count. So a port that moves a reader must point read_by at the new function. The fixture cases pin
# that rule; the last case checks the real inventory against the code. Files are listed with find, not
# git, so it runs the same on a copy of the worktree without .git.
set -euo pipefail
# shellcheck source=tests/test_helpers.sh
source "$(dirname "${BASH_SOURCE[0]}")/test_helpers.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TSV=docs/port/fields.tsv
dir="$(mktemp -d)" || { echo "mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "${dir}"' EXIT
export HOME="${dir}/home"   # under its own root, as every test's is (sleep_scale_test.sh)

fails=0
check() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want '$2', got '$3'"; fails=$((fails + 1)); fi
}

# unread <root> — one line per row of <root>/docs/port/fields.tsv that no read_by entry still reads,
# naming the tsv, the field and its readers; one per malformed row; one when the tsv has no rows or
# cannot be read, or the check itself fails.
unread() {
  local d scan=()
  for d in bin hooks cmd internal; do [[ ! -d "$1/${d}" ]] || scan+=("${d}"); done
  (cd "$1" && { find ${scan[@]+"${scan[@]}"} -type d -name __pycache__ -prune -o -type f ! -name '*.pyc' ! -name '*_test.go' -print 2>/dev/null || true; } \
    | python3 -I -c '
import re, sys
tsv, files = sys.argv[1], set(sys.stdin.read().split())
def bodies(path, name):
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    except OSError:
        return []
    out = []
    for i, l in enumerate(lines):
        if path.endswith(".py"):
            if name == "__main__":
                hit = re.match(r"if __name__ == [\"\x27]__main__[\"\x27]:", l)
            else:
                hit = re.match(r"(\s*)def " + re.escape(name) + r"\(", l)
            if not hit:
                continue
            ind = len(l) - len(l.lstrip())
            j = i + 1
            while j < len(lines) and (not lines[j].strip() or len(lines[j]) - len(lines[j].lstrip()) > ind):
                j += 1
            out.append((lines[i:j], "#"))
        elif path.endswith(".go"):
            if re.match(r"func (\([^)]*\) *)?" + re.escape(name) + r"\(", l):
                if "{" in l and l.rstrip().endswith("}"):
                    out.append(([l], "//"))
                    continue
                j = i + 1
                while j < len(lines) and lines[j] != "}":
                    j += 1
                out.append((lines[i:j + 1], "//"))
        else:
            m = re.match(r"(\s*)" + re.escape(name) + r"\(\) *([{(])(.*)$", l)
            if not m:
                continue
            close = "}" if m.group(2) == "{" else ")"
            if m.group(3).rstrip().endswith(close):
                out.append(([l], "#"))
                continue
            j = i + 1
            while j < len(lines) and not re.match(re.escape(m.group(1) + close), lines[j]):
                j += 1
            out.append((lines[i:j + 1], "#"))
    return out
def reads(entry, field):
    path, _, name = entry.rpartition(":")
    if path not in files and "./" + path not in files:
        return False
    word = re.compile(r"(?<![A-Za-z0-9_-])" + re.escape(field) + r"(?![A-Za-z0-9_-])")
    return any(word.search(l) for body, c in bodies(path, name) for l in body if not l.strip().startswith(c))
try:
    lines = open(tsv, encoding="utf-8").read().split("\n")
except (OSError, UnicodeDecodeError) as e:
    sys.exit("docs/port/fields.tsv: cannot read it (%s)" % e.__class__.__name__)
rows = 0
for n, line in enumerate(lines, 1):
    line = line.rstrip("\n")
    if not line or line.startswith("#"):
        continue
    rows += 1
    f = line.split("\t")
    if len(f) != 3 or not f[0] or not f[1] or not f[2].split() or any(":" not in e for e in f[2].split()):
        print("docs/port/fields.tsv:%d: want <kind><TAB><field><TAB><file>:<function> ..., got %r" % (n, line))
        continue
    if not any(reads(e, f[1]) for e in f[2].split()):
        print("docs/port/fields.tsv: %s field %s: no read_by entry is a function whose body names it (%s); point read_by at the function that reads it now" % (f[0], f[1], f[2]))
if rows == 0:
    print("docs/port/fields.tsv: no rows")
' "${TSV}" 2>&1 || echo "docs/port/fields.tsv: the check failed (exit $?)")
}

# fixture <name> — a stand-in project with one reader of the field color in each language, and a
# *_test.go and a __pycache__ file that name it; the caller writes its fields.tsv.
fixture() {
  local p="${dir}/$1"
  mkdir -p "${p}/bin/lib/__pycache__" "${p}/internal/x" "${p}/docs/port"
  # shellcheck disable=SC2016 # the $1 is the fixture's shell, written as text
  printf 'color_of() {\n  fm "$1" color\n}\nshade_of() { get_fm "$1" color; }\nold_reader() {\n  # reads color\n  fm "$1" hue\n}\n' > "${p}/bin/lib/a.sh"
  printf 'def color_of(fm):\n    return fm.get("color")\n\nif __name__ == "__main__":\n    print(front()["color"])\n' > "${p}/bin/lib/p.py"
  printf 'color' > "${p}/bin/lib/__pycache__/p.cpython-39.pyc"
  printf 'package x\n\nfunc OnlyReader() string { return "hue" }\n\nfunc ColorOf(f string) string {\n\treturn fm(f, "color")\n}\n\nfunc (b *Board) Shade(f string) string {\n\treturn b.fm(f, "color")\n}\n' > "${p}/internal/x/x.go"
  printf 'package x\n\nfunc TestColor(t *testing.T) { _ = "color" }\n' > "${p}/internal/x/x_test.go"
  echo "${p}"
}
row() { printf '# header\nstory\tcolor\t%s\n' "$2" > "$1/docs/port/fields.tsv"; }

p="$(fixture green)"
row "${p}" "bin/lib/a.sh:color_of"
check "a bash reader that names the field passes" "" "$(unread "${p}")"
row "${p}" "bin/lib/a.sh:shade_of"
check "a one-line bash reader passes" "" "$(unread "${p}")"
row "${p}" "internal/x/x.go:ColorOf"
check "a Go func that names the field, in place of the bash reader, passes" "" "$(unread "${p}")"
row "${p}" "internal/x/x.go:Shade"
check "a Go method that names the field passes" "" "$(unread "${p}")"
row "${p}" "bin/lib/p.py:color_of bin/lib/p.py:__main__"
check "a Python def and a __main__ block pass" "" "$(unread "${p}")"
row "${p}" "bin/lib/gone.sh:color_of bin/lib/a.sh:color_of"
check "one live reader is enough" "" "$(unread "${p}")"

want="docs/port/fields.tsv: story field color: no read_by entry is a function whose body names it"
row "${p}" "bin/lib/a.sh:colour_of"
check "a renamed reader fails, naming the tsv and the field" "${want}" "$(unread "${p}" | cut -d'(' -f1 | sed 's/ $//')"
row "${p}" "bin/lib/a.sh:old_reader"
check "a reader that names the field only in a comment fails" "${want}" "$(unread "${p}" | cut -d'(' -f1 | sed 's/ $//')"
row "${p}" "internal/x/x_test.go:TestColor"
check "a *_test.go is not a reader" "${want}" "$(unread "${p}" | cut -d'(' -f1 | sed 's/ $//')"
row "${p}" "internal/x/x.go:Shades"
check "a Go name that only starts like a reader fails" "${want}" "$(unread "${p}" | cut -d'(' -f1 | sed 's/ $//')"
printf 'story\tcolor\n' > "${p}/docs/port/fields.tsv"
check "a row with no read_by fails" "1" "$(unread "${p}" | grep -c '^docs/port/fields.tsv:1: want' || true)"
printf '# only a header\n' > "${p}/docs/port/fields.tsv"
check "a tsv with no rows fails" "docs/port/fields.tsv: no rows" "$(unread "${p}")"
row "${p}" "internal/x/x.go:OnlyReader"
check "a one-line Go func ends at its own brace" "${want}" "$(unread "${p}" | cut -d'(' -f1 | sed 's/ $//')"
rm "${p}/docs/port/fields.tsv"
check "a missing tsv fails" "docs/port/fields.tsv: cannot read it" "$(unread "${p}" | head -1 | cut -d'(' -f1 | sed 's/ $//')"

check "every field in ${TSV} still has a reader" "" "$(unread "${ROOT}")"

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
