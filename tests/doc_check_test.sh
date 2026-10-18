#!/usr/bin/env bash
# doc_check_test.sh — the docs name only what swarm.sh has. In README.md, docs/*.md, commands/*.md,
# skills/ and templates/ (AGENTS.md is the lead's, so it is not read), every `swarm.sh <command>` in
# code must be one of dispatch's arms (or version and update, which run before it), every key in a
# setting table (header `| Key |`) or after `swarm.sh config` one of CONFIG_KEYS, and every repo path
# in code or a markdown link must exist; a docs/ path may instead be one templates/docs gives a board.
# A removed command that prints a pointer is still an arm, so it passes. tests/doc_check_known.txt
# lists the stale references found when this landed (file, tab, text); they pass until fixed, and an
# entry no longer found fails, so the list only shrinks.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KNOWN="${REPO}/tests/doc_check_known.txt"

# doc_check <docs root> — one `file<TAB>text` line per stale reference in the docs under <docs root>,
# checked against ${REPO}'s bin/swarm.sh and tree.
doc_check() {
  python3 - "${REPO}" "$1" <<'EOF'
import glob, os, re, sys
repo, root = sys.argv[1], sys.argv[2]
src = open(os.path.join(repo, "bin/swarm.sh")).read()
body = src.split("\ndispatch() {", 1)[1].split("\n  esac", 1)[0]
early = src.split('\ncase "${1:-}" in', 1)[1].split("\nesac", 1)[0]
commands = {a for arms in re.findall(r"^    ([a-z_|-]+)\)", body, re.M) for a in arms.split("|")}
commands |= set(re.findall(r"^  ([a-z_-]+)\)", early, re.M))
keys = set(re.search(r'^CONFIG_KEYS="([^"]+)"', src, re.M).group(1).split())
ROOTS = r"(?:bin|commands|docs|hooks|scripts|skills|templates|tests|\.claude-plugin|\.github)/"

def exists(path):
    if glob.glob(os.path.join(repo, path)):
        return True
    return path.startswith("docs/") and bool(glob.glob(os.path.join(repo, "templates", path)))

def check_code(code, out):
    for c in re.findall(r"(?<![\w.-])swarm\.sh[ \t]+([a-z][\w-]*)", code):
        if c not in commands:
            out.append("swarm.sh " + c)
    for k in re.findall(r"(?<![\w.-])swarm\.sh[ \t]+config[ \t]+([a-z][\w-]*)", code):
        if k not in keys | {"project"}:
            out.append("config key " + k)
    for m in re.finditer(r"(?<![\w.~/$-])(?:\./)?(" + ROOTS + r"[\w./*-]*)", code):
        path = m.group(1).rstrip(".,:;")
        if code[m.end():m.end() + 1] in ("<", "{"):
            path = path[:path.rfind("/") + 1]   # a placeholder follows: its directory must exist
        if not exists(path):
            out.append("path " + path)

def check_md(rel, text, out):
    fence = in_table = False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            fence = not fence
            continue
        if fence:
            check_code(line, out)
            continue
        for span in re.findall(r"`([^`]+)`", line):
            check_code(span, out)
        if re.match(r"\|\s*Key\s*\|", line):
            in_table = True
        elif not line.startswith("|"):
            in_table = False
        elif in_table and (k := re.match(r"\|\s*`?([a-z][\w-]*)`?\s*\|", line)) and k.group(1) not in keys:
            out.append("config key " + k.group(1))
        for link in re.findall(r"\]\(([^)\s]+)\)", line):
            target = link.split("#", 1)[0]
            if not target or "://" in link or link.startswith("mailto:") or "<" in target:
                continue
            if not os.path.exists(os.path.normpath(os.path.join(root, os.path.dirname(rel), target))):
                out.append("link " + link)

files = ["README.md"] + [os.path.relpath(f, root) for g in ("docs/*.md", "commands/*.md")
                          for f in sorted(glob.glob(os.path.join(root, g)))]
for d in ("skills", "templates"):
    for dirpath, _, names in sorted(os.walk(os.path.join(root, d))):
        files += sorted(os.path.relpath(os.path.join(dirpath, n), root) for n in names)
for rel in files:
    path = os.path.join(root, rel)
    if not os.path.isfile(path):
        continue
    text, out = open(path).read(), []
    if rel.endswith(".md"):
        check_md(rel, text, out)
    else:
        check_code(text, out)
    for o in dict.fromkeys(out):
        print(rel + "\t" + o)
EOF
}

# unknown <found> <known> — the findings <known> does not allow. gone <found> <known> — the entries of
# <known> that are no longer found.
unknown() { comm -23 <(LC_ALL=C sort "$1") <(LC_ALL=C sort "$2"); }
gone() { comm -13 <(LC_ALL=C sort "$1") <(LC_ALL=C sort "$2"); }

fails=0
tmp="$(mktemp -d)"; trap 'rm -rf "${tmp}"' EXIT
doc_check "${REPO}" > "${tmp}/found"
new="$(unknown "${tmp}/found" "${KNOWN}")"
if [[ -n "${new}" ]]; then
  echo "FAIL the docs name something swarm.sh does not have (fix the doc; AGENTS.md is the lead's):"; echo "${new}"
  fails=$((fails + 1))
else echo "ok   every command, config key and path the docs name exists, or is in doc_check_known.txt"; fi
stale="$(gone "${tmp}/found" "${KNOWN}")"
if [[ -n "${stale}" ]]; then
  echo "FAIL doc_check_known.txt lists what the docs no longer say; remove it:"; echo "${stale}"
  fails=$((fails + 1))
else echo "ok   every doc_check_known.txt entry is still found"; fi
if [[ "$(cat "${KNOWN}")" != "$(LC_ALL=C sort "${KNOWN}")" ]]; then
  echo "FAIL doc_check_known.txt is not sorted"; fails=$((fails + 1))
else echo "ok   doc_check_known.txt is sorted"; fi

# Fixture docs: each kind of stale reference is caught, and the real ones are not.
mkdir -p "${tmp}/fixture/docs" "${tmp}/fixture/templates"
# A line ending in swarm.sh does not make the next line's first word a command.
printf 'note: swarm.sh\nreads this\n' > "${tmp}/fixture/templates/Board.base"
cat > "${tmp}/fixture/README.md" <<'EOF'
Run `swarm.sh nosuch`, `swarm.sh dash2`, `swarm.sh config merge2` or `swarm.sh dash`, then `swarm.sh cost` (removed, prints a pointer).
See [the method](docs/method.md) and [gone](docs/nosuch.md), `bin/lib/nosuch.sh`, `./bin/gone.sh` and `./bin/swarm.sh`.
`docs/epics/<slug>.md` lives on the board, as does `docs/stories/`; `docs/nosuch/<slug>.md` does not.
EOF
cat > "${tmp}/fixture/docs/method.md" <<'EOF'
| Key | Default | What it does |
|---|---|---|
| `merge` | `human` | ok |
| `nosuch_key` | `0` | stale |
| plain_key | 0 | stale, no backticks |
EOF
want=$'README.md\tswarm.sh nosuch\nREADME.md\tswarm.sh dash2\nREADME.md\tconfig key merge2\nREADME.md\tpath bin/lib/nosuch.sh\nREADME.md\tpath bin/gone.sh\nREADME.md\tlink docs/nosuch.md\nREADME.md\tpath docs/nosuch/\ndocs/method.md\tconfig key nosuch_key\ndocs/method.md\tconfig key plain_key'
doc_check "${tmp}/fixture" > "${tmp}/fixture.found"
got="$(cat "${tmp}/fixture.found")"
if [[ "${got}" == "${want}" ]]; then
  echo "ok   fixture docs: an unknown command, config key, link and path are each caught, and nothing else"
else
  echo "FAIL fixture docs: want:"; echo "${want}"; echo "got:"; echo "${got}"; fails=$((fails + 1))
fi

# A fixture known list, written as an entry is: one finding it allows and one the docs no longer say.
printf 'README.md\tswarm.sh nosuch\nREADME.md\tswarm.sh stale\n' > "${tmp}/fixture.known"
new="$(unknown "${tmp}/fixture.found" "${tmp}/fixture.known")"
if [[ "${new}" != *$'README.md\tswarm.sh nosuch'* && "${new}" == *$'README.md\tswarm.sh dash2'* ]]; then
  echo "ok   fixture known list: its entry is allowed and a finding not in it still fails"
else
  echo "FAIL fixture known list: allowed wrongly, the findings left were:"; echo "${new}"; fails=$((fails + 1))
fi
stale="$(gone "${tmp}/fixture.found" "${tmp}/fixture.known")"
if [[ "${stale}" == $'README.md\tswarm.sh stale' ]]; then
  echo "ok   fixture known list: an entry no longer found is reported gone"
else
  echo "FAIL fixture known list: want swarm.sh stale gone, got:"; echo "${stale}"; fails=$((fails + 1))
fi

[[ ${fails} -eq 0 ]] || { echo "${fails} failed"; exit 1; }
echo "all passed"
