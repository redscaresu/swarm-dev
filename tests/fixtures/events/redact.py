#!/usr/bin/env python3
"""redact.py <events.tsv> <cut> — print a redacted sample of an events.tsv: how v0.29.1-sample.tsv was made.
redact.py --check <file> — print each token of <file> outside the classes below; exit 1 on any.

The sample comes from the rows before <cut> (an ISO-Z time, compared as text): every row whose outcome
holds `=`, the first row of each (command, first word of outcome) pair, and every row of the three
shortest whole story lifecycles (the rows whose target is the slug or its PR, among them a story, a merge
and a close row). It stops when that comes to more than MAX_ROWS rows.

The redaction is an allowlist (rules.md: never a denylist). It keeps the time, column 2 (the command),
numbers, punctuation and words found in the plugin's own source (bin/, hooks/, scripts/), and swaps every
other token, by class, for a stand-in that the same token always gets:
  slug     zz + a-z. In column 3 (the target), every slug-shaped word but RESERVED, whatever its
           spelling. Elsewhere, a word that is no source word, and a target that is hyphenated or no
           source word. <word>-<target>, an agent's name such as conduct-<epic>, keeps its source word.
  pane id  w<a-z>:p<a-z>; ids that share a workspace still do.
  URL      https://github.com/o/r plus its path past owner/repo, with stand-in numbers; a #<PR> the same.
  path     /p/<a-z>, for an absolute or ~/ path of two parts or more.
  hex      a commit sha: a zero-padded hex count of its length.
A one-word target that is also a source word (main, codex) is swapped in column 3 only, so its joins to
an outcome break; slugs and agent names keep theirs.
"""
import os
import re
import sys

MAX_ROWS = 400
LIFECYCLES = 3
SOURCE_DIRS = ("bin", "hooks", "scripts")
REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
# Targets the readers compare as text: `conduct --backlog`, and report's `backlog`.
RESERVED = {"backlog"}

TOKEN = re.compile(r"""
    (?P<url>https?://[^\s<>"'`()\[\]]*[^\s<>"'`()\[\].,;:!?])
  | (?P<time>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)
  | (?P<pane>(?<![\w-])w(?:[0-9A-Z]*|[a-z]+):(?:p[0-9A-Z]+|p[a-z]+|me|0)(?![\w-]))
  | (?P<path>(?:(?<![\w.~/-])|~)/[\w.@%+~-]+(?:/[\w.@%+~-]*)+)
  | (?P<hex>(?<![\w-])(?=[0-9a-f]*[a-f])(?=[0-9a-f]*[0-9])[0-9a-f]{7,40}(?![\w-]))
  | (?P<ref>(?<![\w&])\#[0-9]+(?!\w))
  | (?P<num>[0-9]+(?:[.:][0-9]+)*(?:(?:(?:ms|[dhms])[0-9]+)*(?:ms|[dhms])(?![A-Za-z]))?)
  | (?P<word>[^\W\d]\w*(?:[-.]\w+)*)
  | (?P<other>.)
""", re.VERBOSE | re.DOTALL)
SLUG = re.compile(r"[a-z][a-z0-9]*(?:-[a-z0-9]+)*")
VERSION = re.compile(r"v[0-9]+(?:\.[0-9]+)*")
ISO = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z")
URL_HEAD = re.compile(r"https?://[^/]+(?:/[^/]+){0,2}")
STANDIN = {
    "slug": re.compile(r"zz[a-z]+"),
    "pane": re.compile(r"w[a-z]+:p[a-z]+"),
    "path": re.compile(r"/p/[a-z]+"),
    "hex": re.compile(r"000[0-9a-f]+"),
}
GITHUB = "https://github.com/o/r"


def letters(n):
    """n as bijective base 26 in a-z: 1 is a, 26 z, 27 aa."""
    s = ""
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(ord("a") + r) + s
    return s


def vocabulary(root):
    """Every word token in the plugin's source files."""
    words = set()
    for d in SOURCE_DIRS:
        for dirpath, dirs, files in os.walk(os.path.join(root, d)):
            dirs[:] = sorted(x for x in dirs if not x.startswith(".") and x != "__pycache__")
            for f in files:
                if f.startswith(".") or f.endswith(".pyc"):
                    continue
                with open(os.path.join(dirpath, f), encoding="utf-8", errors="replace") as fh:
                    words.update(m.group() for m in TOKEN.finditer(fh.read()) if m.lastgroup == "word")
    return words


def splits(word):
    """Each (head, tail) of a hyphenated word, shortest head first."""
    return [(word[:m.start()], word[m.end():]) for m in re.finditer("-", word)]


class Redactor:
    def __init__(self, vocab, targets):
        self.vocab = vocab
        self.targets = targets
        self.tables = {}

    def standin(self, kind, key, make):
        table = self.tables.setdefault(kind, {})
        if key not in table:
            table[key] = make(len(table) + 1)
        return table[key]

    def slug(self, word):
        return self.standin("slug", word, lambda n: "zz" + letters(n))

    def word(self, word, target):
        if VERSION.fullmatch(word):
            return word
        if SLUG.fullmatch(word):
            if target and word in RESERVED:
                return word
            for head, tail in splits(word):
                if tail in self.targets and head in self.vocab:
                    return head + "-" + self.slug(tail)
            if target or word in self.targets or word not in self.vocab:
                return self.slug(word)
            return word
        if word in self.vocab:
            return word
        if "." in word:
            return ".".join(self.field(part, target) for part in word.split("."))
        return self.slug(word)

    def url(self, url):
        rest = url[URL_HEAD.match(url).end():]
        return GITHUB + "/".join(self.field(seg, numbers=True) for seg in rest.split("/"))

    def sha(self, sha):
        return self.standin("hex", sha, lambda n: format(n, "x").rjust(len(sha), "0"))

    def pane(self, pane):
        ws = self.standin("ws", pane.split(":")[0], letters)
        return f"w{ws}:p{self.standin('pane', pane, letters)}"

    def field(self, text, target=False, numbers=False):
        out = []
        for m in TOKEN.finditer(text):
            kind, tok = m.lastgroup, m.group()
            if kind == "url":
                tok = self.url(tok)
            elif kind == "pane":
                tok = self.pane(tok)
            elif kind == "path":
                tok = self.standin("path", tok, lambda n: "/p/" + letters(n))
            elif kind == "hex":
                tok = self.sha(tok)
            elif kind == "num" and numbers:
                tok = self.standin("number", tok, str)
            elif kind == "ref":
                tok = "#" + self.standin("number", tok[1:], str)
            elif kind == "word":
                tok = self.word(tok, target)
            out.append(tok)
        return "".join(out)

    def row(self, f):
        return "\t".join([f[0], f[1], self.field(f[2], target=True), self.field(f[3]), self.field(f[4])])


def lifecycles(rows):
    """The row indexes of each whole story lifecycle, shortest first."""
    own, by_url = {}, {}
    for i, f in enumerate(rows):
        parts = f[2].split(" ")
        own.setdefault(parts[0], []).append(i)
        for p in parts:
            if p.startswith("http"):
                by_url.setdefault(p, []).append(i)
    lives = []
    for slug, idx in own.items():
        if not SLUG.fullmatch(slug):
            continue
        urls = {m.group() for i in idx for m in TOKEN.finditer(rows[i][4]) if m.lastgroup == "url"}
        life = sorted(set(idx).union(*(by_url.get(u, []) for u in urls if "/pull/" in u)))
        if {"story", "merge", "close"} <= {rows[i][1] for i in life}:
            lives.append((len(life), slug, life))
    return [life for _, _, life in sorted(lives)]


def sample(rows):
    keep, pairs = set(), set()
    for i, f in enumerate(rows):
        pair = (f[1], (f[4].split() or [""])[0])
        if "=" in f[4] or pair not in pairs:
            keep.add(i)
        pairs.add(pair)
    for life in lifecycles(rows)[:LIFECYCLES]:
        keep.update(life)
    return sorted(keep)


def redact(path, cut, vocab):
    with open(path, encoding="utf-8", errors="replace") as fh:
        rows = [f for f in (line.rstrip("\n").split("\t") for line in fh) if len(f) == 5 and f[0] < cut]
    keep = sample(rows)
    if len(keep) > MAX_ROWS:
        sys.exit(f"redact.py: the sample has {len(keep)} rows, more than {MAX_ROWS}")
    targets = {m.group() for f in rows for m in TOKEN.finditer(f[2])
               if m.lastgroup == "word" and SLUG.fullmatch(m.group()) and m.group() not in RESERVED
               and ("-" in m.group() or m.group() not in vocab)}
    r = Redactor(vocab, targets)
    return [r.row(rows[i]) for i in keep]


def word_ok(word, target, vocab):
    if VERSION.fullmatch(word) or STANDIN["slug"].fullmatch(word):
        return True
    if SLUG.fullmatch(word):
        if any(head in vocab and STANDIN["slug"].fullmatch(tail) for head, tail in splits(word)):
            return True
        return word in RESERVED if target else word in vocab
    if word in vocab:
        return True
    return "." in word and all(not bad_tokens(part, target, vocab) for part in word.split("."))


def bad_tokens(text, target, vocab, numbers=False):
    """The tokens of a field that fall outside the classes."""
    bad = []
    for m in TOKEN.finditer(text):
        kind, tok = m.lastgroup, m.group()
        if kind == "url":
            rest = tok[len(GITHUB):]
            ok = tok.startswith(GITHUB) and (not rest or rest[0] == "/") \
                and not any(bad_tokens(seg, False, vocab, True) for seg in rest.split("/"))
        elif kind in STANDIN:
            ok = bool(STANDIN[kind].fullmatch(tok))
        elif kind == "word":
            ok = word_ok(tok, target, vocab)
        else:
            ok = True
        if not ok:
            bad.append(tok)
    return bad


def check(path, vocab):
    bad = 0
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            f = line.rstrip("\n").split("\t")
            if len(f) != 5 or not ISO.fullmatch(f[0]):
                print(f"{path}:{n}: not 5 tab fields with an ISO-Z time")
                bad += 1
                continue
            toks = [p for p in f[1].split(":") if p not in vocab]
            toks += bad_tokens(f[2], True, vocab) + bad_tokens(f[3], False, vocab) + bad_tokens(f[4], False, vocab)
            for tok in toks:
                print(f"{path}:{n}: {tok}")
            bad += len(toks)
    return bad


def main(argv):
    if len(argv) == 3 and argv[1] == "--check":
        return 1 if check(argv[2], vocabulary(REPO)) else 0
    if len(argv) != 3 or not ISO.fullmatch(argv[2]):
        sys.stderr.write(__doc__.split("\n\n")[0] + "\n")
        return 2
    for row in redact(argv[1], argv[2], vocabulary(REPO)):
        print(row)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
