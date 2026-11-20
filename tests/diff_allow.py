#!/usr/bin/env python3
"""diff_allow.py — tests/diff_run.sh's allow lists: parse the entry files under scripts/allow/, apply
their hunks to the old tree's streams and compare the result with the new tree's.

  python3 tests/diff_allow.py check <allow-dir> [--stage N] [--only <slug>]
  python3 tests/diff_allow.py compare <allow-dir> <work> [--stage N] [--only <slug>] [--draft]
          [--red <fixture>]... -- <fixture>...
  python3 tests/diff_allow.py compare <allow-dir> <work> --base [--story <slug>]... [--draft]
          [--red <fixture>]... -- <fixture>...

check parses the entries a run would read (with neither option, every entry on disk) and checks the
directory's layout: README.md and stage-<n>/ directories only, each holding <slug>.md files only.
compare reads <work>/<fixture>.a/out/ and <work>/<fixture>.b/out/, diff_run.sh's streams for each
fixture that ran, applies the entries' hunks to a's, and prints DIFF <fixture> <stream> and a diff
for each stream that still differs (with --draft, the hunks that would cover it), ALLOW-FAIL for a
hunk that does not apply, and same <fixture> for a fixture that is not red (--red names those diff_run
already found red). --base applies the entries of the --story slugs alone, from every stage, and a
slug with no entry is no error: a story that changes no output has none. The files stream is split: files is its list of written and deleted paths, and
file:<path> the content of one written file. scripts/allow/README.md gives the entry format.

Exit 0 when nothing differs and every hunk on a fixture that ran applied, 1 when something differs or
a hunk did not apply, 2 on a malformed entry, a bad layout or a bad argument.
"""
import argparse
import difflib
import os
import re
import subprocess
import sys

ORDER = ("stdout", "stderr", "exit", "files")
STREAM_RE = re.compile(rb"^(stdout|stderr|exit|files|file:\S.*|calls:[a-z0-9_-]+)$")
FIXTURE_RE = re.compile(rb"^[A-Za-z0-9_]+$")
SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
STAGE_RE = re.compile(r"^stage-([1-9][0-9]*)$")
PR_RE = re.compile(r"^[1-9][0-9]*$")
KINDS = ("fix", "stage")
KEYS = ("story", "pr", "kind")
NO_NL = b"\\ No newline at end of file"
FILE_HDR = re.compile(rb"^==> (.*) \((\d+) bytes\) <==\n$")
LINK_HDR = re.compile(rb"^==> (.*) -> (.*) <==\n$")


class Bad(Exception):
    """A malformed entry, a bad layout or a bad argument: exit 2."""


class Hunk:
    def __init__(self, fixture, stream, where):
        self.fixture, self.stream, self.where = fixture, stream, where
        self.old, self.new, self.at_start = [], [], False


class Entry:
    def __init__(self, path, stage, meta, hunks):
        self.path, self.stage, self.hunks = path, stage, hunks
        self.slug, self.pr, self.kind = meta["story"], int(meta["pr"]), meta["kind"]
        self.applied = self.skipped = self.failed = 0


def split(data):
    """data's lines, each with its newline; a last line with none keeps none."""
    parts = data.split(b"\n")
    lines = [p + b"\n" for p in parts[:-1]]
    if parts[-1]:
        lines.append(parts[-1])
    return lines


def parse_front(path, lines):
    """The front matter's story, pr and kind, and the index of the line after its closing ---."""
    if not lines or lines[0] != b"---":
        raise Bad(f"{path}:1: an entry starts with a --- line, then story:, pr: and kind:")
    meta, i = {}, 1
    while i < len(lines) and lines[i] != b"---":
        m = re.match(rb"^([a-z]+): *(.*?) *$", lines[i])
        key = m.group(1).decode() if m else ""
        if key not in KEYS:
            raise Bad(f"{path}:{i + 1}: a front matter line is story:, pr: or kind:, not {lines[i]!r}")
        if key in meta:
            raise Bad(f"{path}:{i + 1}: {key}: is given twice")
        meta[key] = m.group(2).decode("utf-8", "replace")
        i += 1
    if i >= len(lines):
        raise Bad(f"{path}: the front matter has no closing --- line")
    for key in KEYS:
        if key not in meta:
            raise Bad(f"{path}: the front matter has no {key}:")
    slug = os.path.basename(path)[:-len(".md")]
    if meta["story"] != slug:
        raise Bad(f"{path}: story: {meta['story']} is not the file's name, {slug}")
    if not PR_RE.match(meta["pr"]):
        raise Bad(f"{path}: pr: {meta['pr']} is not a PR number")
    if meta["kind"] not in KINDS:
        raise Bad(f"{path}: kind: {meta['kind']} is neither fix (a fix: true story) nor stage (a change the stage makes on purpose)")
    return meta, i + 1


def parse_heading(path, n, line):
    """The fixture and stream a ## line names."""
    words = line[3:].strip().split(b" ", 1)
    if not words[0] or not FIXTURE_RE.match(words[0]):
        raise Bad(f"{path}:{n}: a ## heading is ## <fixture> <stream>, not {line!r}")
    if len(words) < 2 or not words[1].strip():
        raise Bad(f"{path}:{n}: ## {words[0].decode()} names a whole fixture: name a stream and its lines")
    stream = words[1].strip()
    if not STREAM_RE.match(stream):
        raise Bad(f"{path}:{n}: {stream!r} is no stream: stdout, stderr, exit, files, file:<path> or calls:<step>")
    return words[0].decode(), stream.decode("utf-8", "surrogateescape")


def parse_fence(path, lines, i, hunk):
    """Fill hunk from the fence that opens at lines[i]; the index past its closing ```."""
    n0, i, prev, change = i + 1, i + 1, None, False
    body = []
    while i < len(lines) and lines[i] != b"```":
        body.append((i + 1, lines[i]))
        i += 1
    if i >= len(lines):
        raise Bad(f"{path}:{n0}: the fence opened here never closes")
    if not body:
        raise Bad(f"{path}:{n0}: the hunk for {hunk.fixture} {hunk.stream} has no lines")
    for n, line in body:
        if line == b"^":
            if prev is not None or hunk.at_start:
                raise Bad(f"{path}:{n}: ^ (the stream's start) comes first in a hunk, once")
            hunk.at_start = True
            continue
        if line == NO_NL:
            if prev is None or not prev[0][-1].endswith(b"\n"):
                raise Bad(f"{path}:{n}: '\\ No newline at end of file' follows a line, once")
            for lst in prev:
                lst[-1] = lst[-1][:-1]
            continue
        tag, text = (line[:1], line[1:]) if line else (b" ", b"")
        sides = {b" ": (hunk.old, hunk.new), b"-": (hunk.old,), b"+": (hunk.new,)}.get(tag, ())
        if any(lst and not lst[-1].endswith(b"\n") for lst in sides):
            raise Bad(f"{path}:{n}: a line with no newline is the last of its side")
        if tag == b" ":
            hunk.old.append(text + b"\n")
            hunk.new.append(text + b"\n")
            prev = (hunk.old, hunk.new)
        elif tag in (b"-", b"+"):
            lst = hunk.old if tag == b"-" else hunk.new
            lst.append(text + b"\n")
            prev, change = (lst,), True
        else:
            raise Bad(f"{path}:{n}: a hunk line starts with ' ', - or +, or is ^ or '\\ No newline at end of file', not {line!r}")
    if not change:
        raise Bad(f"{path}:{n0}: the hunk for {hunk.fixture} {hunk.stream} has no - or + line, so it changes nothing")
    if not hunk.old and not hunk.at_start:
        raise Bad(f"{path}:{n0}: an insertion names the line it follows (a ' ' line before its + lines), or ^ for the stream's start")
    return i + 1


def parse_entry(path, stage):
    with open(path, "rb") as f:
        lines = f.read().split(b"\n")
    if lines and lines[-1] == b"":
        lines.pop()
    meta, i = parse_front(path, lines)
    hunks, heading = [], None

    def close(heading):
        if heading and not heading[2]:
            raise Bad(f"{path}:{heading[0]}: ## {heading[1]} names a stream with no lines: give its exact lines in a ``` fence")

    while i < len(lines):
        line = lines[i]
        if line.startswith(b"```"):
            if heading is None:
                raise Bad(f"{path}:{i + 1}: a fence of lines comes under a ## <fixture> <stream> heading")
            if line not in (b"```", b"```diff"):
                raise Bad(f"{path}:{i + 1}: a hunk's fence opens with ``` or ```diff")
            fixture, stream = heading[3]
            hunk = Hunk(fixture, stream, i + 1)
            i = parse_fence(path, lines, i, hunk)
            hunks.append(hunk)
            heading[2] = True
            continue
        if line == b"##" or line.startswith(b"## "):
            close(heading)
            names = parse_heading(path, i + 1, line)
            heading = [i + 1, " ".join(names), False, names]
        i += 1
    close(heading)
    if not hunks:
        raise Bad(f"{path}: the entry has no hunks: name each difference by its fixture, stream and exact lines")
    return Entry(path, stage, meta, hunks)


def check_layout(allow_dir):
    """Every stage directory, by number, after checking that the layout holds nothing else."""
    if not os.path.isdir(allow_dir):
        return []
    stages = []
    for name in sorted(os.listdir(allow_dir)):
        p = os.path.join(allow_dir, name)
        m = STAGE_RE.match(name)
        if m and os.path.isdir(p):
            stages.append((int(m.group(1)), p))
        elif name != "README.md":
            raise Bad(f"{p}: {allow_dir} holds README.md and stage-<n>/ directories only")
    for _, d in stages:
        for name in sorted(os.listdir(d)):
            p = os.path.join(d, name)
            if not (name.endswith(".md") and SLUG_RE.match(name[:-3]) and os.path.isfile(p)):
                raise Bad(f"{p}: a stage directory holds <slug>.md entry files only")
    return sorted(stages)


def merge_order(allow_dir):
    """{entry path: n}, n the index of the commit on HEAD's first-parent history that added it, oldest
    first; {} when allow_dir's repo is no git checkout of its own. On main that is the order the PRs
    merged; an entry one commit brought with others (a merge of main into a branch) ties with them."""
    repo = os.path.realpath(os.path.dirname(os.path.dirname(allow_dir)))
    git = ["git", "-C", repo]
    try:
        top = subprocess.run(git + ["rev-parse", "--show-toplevel"], capture_output=True, check=True).stdout
        if os.path.realpath(top.decode().strip()) != repo:
            return {}
        out = subprocess.run(git + ["log", "-m", "--first-parent", "--reverse", "--diff-filter=A", "--name-only",
                                    "--format=%x01", "HEAD", "--", "scripts/allow/"], capture_output=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return {}
    order, n = {}, 0
    for line in out.decode("utf-8", "surrogateescape").split("\n"):
        if line == "\x01":
            n += 1
        elif line:
            order[os.path.join(repo, line)] = n
    return order


def load(allow_dir, stage, only, stories=None):
    """The entries of stage-1 through stage-<stage> (every stage when stage is None), in the order
    their PRs merged (merge_order), then by stage and PR number: one no commit added yet comes after
    those, and with no git every entry goes by stage and PR number. With only, that slug's entry alone;
    with stories (a list, for --base), the entries of those slugs alone, none when no slug has one.
    Every entry in range is parsed either way, so a malformed one is an error whichever applies."""
    entries, slugs, prs = [], {}, {}
    for n, d in check_layout(allow_dir):
        if stage is not None and n > stage:
            continue
        for name in sorted(os.listdir(d)):
            e = parse_entry(os.path.join(d, name), n)
            for seen, key in ((slugs, e.slug), (prs, e.pr)):
                if key in seen:
                    raise Bad(f"{e.path}: {key} is also {seen[key]}'s; one story has one entry, from one PR")
                seen[key] = e.path
            entries.append(e)
    order = merge_order(allow_dir)
    pos = {e.path: order.get(os.path.realpath(e.path)) for e in entries}
    entries.sort(key=lambda e: (pos[e.path] is None, pos[e.path] or 0, e.stage, e.pr))
    if only is not None:
        entries = [e for e in entries if e.slug == only]
        if not entries:
            raise Bad(f"--only {only}: no {only}.md in {allow_dir}/stage-*/" + ("" if stage is None else f" up to stage-{stage}"))
    if stories is not None:
        entries = [e for e in entries if e.slug in stories]
    return entries


def base_line(allow_dir, stories, entries):
    """--base's first line: which stories' entries apply, so an empty list reads as what it means."""
    if not stories:
        return f"allow: --base names no story, so no entry in {rel(allow_dir)} applies and every difference is red"
    have = {e.slug for e in entries}
    parts = [s + ("" if s in have else " (no entry)") for s in stories]
    return f"allow: --base applies the entries of {', '.join(parts)} alone; every other entry is left to --stage"


def parse_files(data):
    """diff_run.sh's files stream as its list of paths and a {path: [(kind, payload)]} of records,
    kind file (payload its content) or link (payload its target)."""
    pos, inv, records = 0, [], {}
    while pos < len(data) and not data.startswith(b"==> ", pos):
        end = data.find(b"\n", pos)
        end = len(data) if end < 0 else end + 1
        inv.append(data[pos:end])
        pos = end
    while pos < len(data):
        end = data.find(b"\n", pos) + 1
        header = data[pos:end] if end else data[pos:]
        m = FILE_HDR.match(header)
        if m:
            n = int(m.group(2))
            if data[end + n:end + n + 1] != b"\n":
                raise Bad(f"the files stream's record for {m.group(1)!r} does not end where its header says")
            records.setdefault(m.group(1), []).append((b"file", data[end:end + n]))
            pos = end + n + 1
            continue
        m = LINK_HDR.match(header)
        if not m:
            raise Bad(f"the files stream has a line that is no record header: {header!r}")
        records.setdefault(m.group(1), []).append((b"link", m.group(2)))
        pos = end
    return inv, records


def read_side(out):
    """The plain streams ({name: lines}), the files list and records of one side's out/ directory."""
    plain, inv, records = {}, [], {}
    for name in sorted(os.listdir(out)) if os.path.isdir(out) else []:
        with open(os.path.join(out, name), "rb") as f:
            data = f.read()
        if name == "files":
            inv, records = parse_files(data)
        else:
            plain[name] = split(data)
    return plain, inv, records


def apply(lines, hunk):
    """lines with hunk applied, or None and why it does not apply."""
    k = len(hunk.old)
    if hunk.at_start:
        spots = [0] if lines[:k] == hunk.old else []
    else:
        spots = [i for i in range(len(lines) - k + 1) if lines[i:i + k] == hunk.old]
    if len(spots) == 1:
        return lines[:spots[0]] + hunk.new + lines[spots[0] + k:], None
    if not spots:
        return None, "its - and ' ' lines are not in the stream as the entries before it leave it; --draft prints the difference"
    return None, f"its - and ' ' lines are in the stream {len(spots)} times; add a ' ' line before them, or ^"


def written_paths(inv):
    return {line[len(b"written "):].rstrip(b"\n") for line in inv if line.startswith(b"written ")}


class Side:
    """One fixture's a side, as the entries change it. The files list decides which paths are
    written, as each hunk applies: a path a files hunk adds is an empty file, one it removes goes with
    its content, and a file:<path> hunk changes the content of a path the list writes then."""

    def __init__(self, out):
        self.plain, inv, self.records = read_side(out)
        self.plain["files"] = inv

    def apply(self, hunk, b_streams):
        s = hunk.stream
        if s.startswith("file:"):
            path = s[len("file:"):].encode("utf-8", "surrogateescape")
            recs = self.records.get(path, [])
            if not recs:
                return "the files list does not write it here; its files hunk goes before it"
            if len(recs) > 1:
                return f"{len(recs)} files a mask made alike have this name, so no hunk can name one"
            if recs[0][0] == b"link":
                return "it is a symbolic link, which no hunk can change"
            got, why = apply(split(recs[0][1]), hunk)
            if got is not None:
                self.records[path] = [(b"file", b"".join(got))]
            return why
        if s not in self.plain and s not in b_streams:
            return "the run has no such stream"
        got, why = apply(self.plain.get(s, []), hunk)
        if got is not None:
            self.plain[s] = got
            if s == "files":
                written = written_paths(got)
                self.records = {p: r for p, r in self.records.items() if p in written}
                for p in written - set(self.records):
                    self.records[p] = [(b"file", b"")]
        return why


def emit(line=b""):
    sys.stdout.buffer.write(line + b"\n")


def show(lines):
    """lines as a diff or a hunk prints them: a line with no newline gets the marker after it."""
    for line in lines:
        if line.endswith(b"\n"):
            emit(line[:-1])
        else:
            emit(line)
            emit(NO_NL)


def unified(fx, stream, a, b):
    name = f"{fx}/{stream}".encode("utf-8", "surrogateescape")
    out = difflib.diff_bytes(difflib.unified_diff, a, b, b"a/" + name, b"b/" + name, lineterm=b"")
    for line in out:
        if line.startswith((b"---", b"+++", b"@@")):
            emit(line)
        else:
            show([line])


def draft(fx, stream, a, b):
    """Print the hunks that turn a into b, each applying, in order, to what the ones before it left:
    a block of - and ' ' lines found once in the text, widened by ' ' lines before it, or ^."""
    emit(b"## " + f"{fx} {stream}".encode("utf-8", "surrogateescape"))
    cur, off = list(a), 0
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if tag == "equal":
            continue
        p = i1 + off
        removed, added = cur[p:p + i2 - i1], b[j1:j2]
        ctx = 0 if removed else 1
        while ctx <= p:
            block = cur[p - ctx:p + len(removed)]
            if sum(1 for i in range(len(cur) - len(block) + 1) if cur[i:i + len(block)] == block) == 1:
                break
            ctx += 1
        at_start, ctx = (True, p) if ctx > p else (False, ctx)
        emit()
        emit(b"```diff")
        if at_start:
            emit(b"^")
        show([b" " + x for x in cur[p - ctx:p]] + [b"-" + x for x in removed] + [b"+" + x for x in added])
        emit(b"```")
        cur[p:p + len(removed)] = added
        off += len(added) - len(removed)
    emit()


def report(fx, stream, a, b, as_draft, note=None):
    emit(b"DIFF " + f"{fx} {stream}".encode("utf-8", "surrogateescape"))
    if note:
        emit(b"  " + note)
    elif a is None or b is None:
        emit(b"  a symbolic link, or files a mask made alike, on one side: no hunk can name it")
    elif as_draft:
        draft(fx, stream, a, b)
    else:
        unified(fx, stream, a, b)


def record_lines(recs):
    """A path's records as lines to diff, or None when no hunk could name them."""
    if len(recs) == 1 and recs[0][0] == b"file":
        return split(recs[0][1])
    return None


def compare_fixture(fx, work, entries, as_draft):
    """Apply every entry's hunks for fx to its a side, then report what differs from b. True when
    something differs or a hunk did not apply."""
    a = Side(os.path.join(work, f"{fx}.a", "out"))
    b_plain, b_inv, b_recs = read_side(os.path.join(work, f"{fx}.b", "out"))
    b_plain["files"] = b_inv
    red = False
    for e in entries:
        for h in e.hunks:
            if h.fixture != fx:
                continue
            why = a.apply(h, b_plain)
            if why is None:
                e.applied += 1
                continue
            e.failed += 1
            red = True
            emit(f"ALLOW-FAIL {fx} {h.stream}: {rel(e.path)}:{h.where} ({e.slug}) does not apply: {why}".encode("utf-8", "surrogateescape"))
    a_recs = a.records
    names = sorted(set(a.plain) | set(b_plain), key=lambda s: (s not in ORDER, ORDER.index(s) if s in ORDER else 0, s))
    for s in names:
        al, bl = a.plain.get(s, []), b_plain.get(s, [])
        if b"".join(al) != b"".join(bl):
            red = True
            report(fx, s, al, bl, as_draft)
        if s != "files":
            continue
        for p in sorted(set(a_recs) | set(b_recs)):
            ar, br = sorted(a_recs.get(p, [])), sorted(b_recs.get(p, []))
            if ar == br:
                continue
            red = True
            stream = "file:" + p.decode("utf-8", "surrogateescape")
            if not br:
                report(fx, stream, None, None, as_draft, b"b writes no such file: a files hunk that drops its written line drops its content too")
            elif not ar and record_lines(br) == []:
                report(fx, stream, None, None, as_draft, b"a writes no such file: a files hunk that adds its written line makes it, empty")
            else:
                report(fx, stream, record_lines(ar) if ar else [], record_lines(br), as_draft)
    return red


REL_ROOT = [None]


def rel(path):
    return os.path.relpath(path, REL_ROOT[0]) if REL_ROOT[0] else path


def summary(entries):
    for e in entries:
        line = f"allow {e.slug} (#{e.pr}, {e.kind}, stage-{e.stage}): {e.applied} of {len(e.hunks)} hunks applied"
        if e.skipped:
            line += f", {e.skipped} skipped as their fixture did not run"
        if e.failed:
            line += f", {e.failed} did not apply"
        emit(line.encode())


def main(argv):
    ap = argparse.ArgumentParser(prog="diff_allow.py")
    ap.add_argument("mode", choices=("check", "compare"))
    ap.add_argument("allow_dir")
    ap.add_argument("work", nargs="?")
    ap.add_argument("--stage", type=int)
    ap.add_argument("--only")
    ap.add_argument("--draft", action="store_true")
    ap.add_argument("--base", action="store_true")
    ap.add_argument("--story", action="append", default=[])
    ap.add_argument("--red", action="append", default=[])
    ap.add_argument("fixtures", nargs="*")
    args = ap.parse_args(argv)
    allow_dir = os.path.abspath(args.allow_dir)
    REL_ROOT[0] = os.path.dirname(os.path.dirname(allow_dir))
    try:
        if args.stage is not None and args.stage < 1:
            raise Bad("--stage takes a stage number above 0")
        if args.base and (args.stage is not None or args.only is not None):
            raise Bad("--base takes neither --stage nor --only: it applies the --story entries alone")
        if args.story and not args.base:
            raise Bad("--story goes with --base")
        for slug in args.story:
            if not SLUG_RE.match(slug):
                raise Bad(f"--story takes a story slug, not {slug!r}")
        stories = list(dict.fromkeys(args.story)) if args.base else None
        read = args.mode == "check" or args.stage is not None or args.only is not None or args.base
        entries = load(allow_dir, args.stage, args.only, stories) if read else []
        if args.mode == "check":
            for e in entries:
                emit(f"parsed {rel(e.path)} ({e.slug}, #{e.pr}, {e.kind}): {len(e.hunks)} hunks".encode())
            if not entries:
                emit(f"no entry file in {rel(allow_dir)}/stage-*/".encode())
            return 0
        if args.base:
            emit(base_line(allow_dir, stories, entries).encode())
        elif read and not entries:
            upto = "every stage" if args.stage is None else ("stage-1" if args.stage == 1 else f"stage-1 through stage-{args.stage}")
            emit(f"allow: no entry file in {rel(allow_dir)}, {upto}, so every difference is red".encode())
        ran = set(args.fixtures)
        for e in entries:
            e.skipped = sum(1 for h in e.hunks if h.fixture not in ran)
        status = 0
        for fx in args.fixtures:
            if compare_fixture(fx, args.work, entries, args.draft):
                status = 1
            elif fx not in args.red:
                emit(f"same {fx}".encode())
        summary(entries)
        return status
    except Bad as e:
        print(f"diff_allow: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
