import re, subprocess, sys
from collections import Counter

# dropped_lines.py <repo-dir> <base> <head> [<merge sha>...] — the base lines a PR's own merge commits
# dropped (#693), from local git alone. It walks `git rev-list --first-parent --merges <base>..<head>`,
# oldest first, and with merge SHAs given scans only those (full SHAs, matched exactly). Each merge
# must have two parents, one an ancestor of <base> (the base side) and one not (the PR side); the order
# of the two does not matter. Otherwise it scans nothing: an octopus is not remerged this way, and a
# merge with neither parent on <base> (a stacked build's merge of its parent branch) is unchecked, not
# clean. Of each merge's `git show --remerge-diff`, a removed line L of file F prints when L is in the
# base side's F and the PR side's F has at least as many copies of L as the merge base's F (`git
# merge-base` of the two parents), so L is new on the base side or still on the PR side: a base line the
# resolution dropped that the PR's own commits had not removed. Copies are counted, not just found, so a
# line the PR removed while it keeps another copy (a block's closing `}`) is the PR's removal. Inside
# a conflict section a line's side is the section's (the first parent's part, then the second's, followed
# across the diff's hunks), never its text found elsewhere in the base file, so a PR-side line in a conflict never counts as a base
# line. Conflict markers, the merge base's part of a section and whitespace-only lines never print. It
# prints `<merge sha7> <file>: <text>` per dropped line, control characters taken off and the text cut
# to TEXT_CHARS (it reaches events.tsv, state files and panes, as ci_data's lines do), and exits 1; with
# nothing dropped, it prints nothing and exits 0. When it cannot check, it prints one line on stdout
# saying why and exits 2, before printing any dropped line.

TEXT_CHARS = 300   # the most of a dropped line's text it prints (merge.sh's FIX_MAIN_LINE_CHARS)
GIT_SECONDS = 120  # the longest one git call may run
OUTSIDE, FIRST, SECOND, ANCESTOR = 0, 1, 2, 3   # where a line of the remerged file sits
HUNK = re.compile(rb"^@@ -\d+(?:,(\d+))? \+\d+(?:,(\d+))? @@")
MARKER = re.compile(rb"^(?:<{7,}|\|{7,}|>{7,})(?: |$)|^={7,}$")
CONTROL = re.compile(r"[\x00-\x1f\x7f]")
ESCAPES = {ord("a"): 7, ord("b"): 8, ord("f"): 12, ord("n"): 10, ord("r"): 13, ord("t"): 9, ord("v"): 11}

def clean(b):
    return CONTROL.sub("", b.decode("utf-8", "replace") if isinstance(b, bytes) else b)

def say(line):
    sys.stdout.buffer.write((line + "\n").encode("utf-8", "replace"))

def stop(why):
    say(clean(why))
    sys.exit(2)

def git(*args):
    """git -C REPO <args>: (exit code, stdout bytes, its stderr's first line); -1 when it could not run"""
    cmd = ["git", "-C", REPO, "-c", "core.quotePath=false", "-c", "merge.conflictStyle=merge"] + list(args)
    try:
        p = subprocess.run(cmd, capture_output=True, timeout=GIT_SECONDS)
    except (OSError, subprocess.SubprocessError) as e:
        return -1, b"", str(e)
    return p.returncode, p.stdout, clean((p.stderr.strip().splitlines() or [b""])[0])

def ancestor(rev, of):
    rc, _, err = git("merge-base", "--is-ancestor", rev, of)
    if rc not in (0, 1):
        stop("cannot tell whether %s is on %s: %s" % (rev[:7], of, err))
    return rc == 0

def sides(m, base):
    """(PR side, base side, the base side's section) of merge m, or stop saying why it cannot be checked"""
    rc, out, err = git("rev-list", "--parents", "-n", "1", "--end-of-options", m)
    if rc != 0:
        stop("cannot read the parents of merge %s: %s" % (m[:7], err))
    parents = out.decode().split()[1:]
    if len(parents) != 2:
        stop("merge %s has %d parents: an octopus merge is not remerged, so it is not checked" % (m[:7], len(parents)))
    on = [p for p in parents if ancestor(p, base)]
    if not on:
        stop("merge %s is unchecked: neither parent is on %s, so it is not a merge of %s"
             " (a stacked build's merge of its parent branch?)" % (m[:7], base, base))
    if len(on) == 2:
        stop("merge %s is unchecked: both parents are on %s, so neither is the PR's side" % (m[:7], base))
    return (parents[1], parents[0], FIRST) if on[0] == parents[0] else (parents[0], parents[1], SECOND)

def unquote(path):
    """a path as git's diff header writes it, its C-style quotes and escapes taken off"""
    if not path.startswith(b'"') or not path.endswith(b'"'):
        return path
    out, s, i = bytearray(), path[1:-1], 0
    while i < len(s):
        if s[i] == ord("\\") and i + 1 < len(s):
            nxt = s[i + 1]
            if s[i + 1:i + 4].isdigit():
                out.append(int(s[i + 1:i + 4], 8))
                i += 4
                continue
            out.append(ESCAPES.get(nxt, nxt))
            i += 2
            continue
        out.append(s[i])
        i += 1
    return bytes(out)

def removed(diff):
    """(file, section, text) for each line the remerge diff removes, conflict markers left out"""
    path, header, old, new, section, size = None, False, 0, 0, OUTSIDE, 0
    for line in diff.split(b"\n"):
        if old > 0 or new > 0:
            tag, text = line[:1], line[1:]
            if tag == b"\\":
                continue
            if tag == b"+":
                new -= 1
                continue
            old -= 1
            if tag != b"-":
                new -= 1
            marker = section != OUTSIDE and MARKER.match(text) is not None
            if section == OUTSIDE and re.match(rb"^<{7,}(?: |$)", text):
                section, size, marker = FIRST, len(text) - len(text.lstrip(b"<")), True
            elif section in (FIRST, ANCESTOR) and text == b"=" * size:
                section = SECOND
            elif section == FIRST and text[:size + 1] in (b"|" * size, b"|" * size + b" "):
                section = ANCESTOR
            elif section == SECOND and text[:size + 1] in (b">" * size, b">" * size + b" "):
                section = OUTSIDE
            if tag == b"-" and not marker and path is not None:
                yield path, section, text
            continue
        if line.startswith(b"diff --git "):
            path, header, section = None, True, OUTSIDE
        elif header and line.startswith(b"--- "):
            name = unquote(line[4:].rstrip(b"\t"))
            path = name[2:] if name.startswith(b"a/") else None
        elif header or path is not None:
            m = HUNK.match(line)
            if m:
                header = False
                old = int(m.group(1)) if m.group(1) is not None else 1
                new = int(m.group(2)) if m.group(2) is not None else 1

def scan(m, pr, base_side, ours):
    """the `<sha7> <file>: <text>` line of each base line merge m's resolution dropped"""
    rc, out, err = git("show", "--remerge-diff", "--format=", "--no-color", "--no-ext-diff", "--no-textconv",
                       "--src-prefix=a/", "--dst-prefix=b/", "--end-of-options", m)
    if rc != 0:
        stop("git show --remerge-diff failed on merge %s: %s" % (m[:7], err))
    rc, mb, err = git("merge-base", pr, base_side)
    if rc not in (0, 1):
        stop("cannot find the merge base of merge %s's parents: %s" % (m[:7], err))
    mb = mb.decode().strip() if rc == 0 else None   # 1: no common ancestor, so every line is new
    files, found = {}, []

    def lines(rev, path):
        """each line of path at rev and its count; none where rev has no such path, a stop when git cannot read it"""
        if rev is None:
            return Counter()
        if (rev, path) not in files:
            rc, blob, err = git("cat-file", "blob", rev.encode() + b":" + path)
            if rc != 0:
                gone, listed, _ = git("--literal-pathspecs", "ls-tree", "--name-only", "-z", rev, "--", path)
                if gone != 0 or listed:
                    stop("cannot read %s at %s for merge %s: %s" % (clean(path), rev[:7], m[:7], err))
            files[rev, path] = Counter(blob.split(b"\n")) if rc == 0 else Counter()
        return files[rev, path]

    for path, section, text in removed(out):
        if not text.strip() or section not in (OUTSIDE, ours):
            continue
        if lines(base_side, path)[text] and lines(pr, path)[text] >= lines(mb, path)[text]:
            found.append("%s %s: %s" % (m[:7], clean(path), clean(text)[:TEXT_CHARS]))
    return found

if len(sys.argv) < 4:
    stop("usage: dropped_lines.py <repo-dir> <base> <head> [<merge sha>...]")
REPO, BASE, HEAD = sys.argv[1:4]
wanted = {s.lower() for s in sys.argv[4:]}
rc, out, err = git("rev-list", "--first-parent", "--merges", "--reverse", "--end-of-options", BASE + ".." + HEAD, "--")
if rc != 0:
    stop("cannot list the merges in %s..%s: %s" % (BASE, HEAD, err))
merges = [m for m in out.decode().split() if not sys.argv[4:] or m in wanted]
checks = [(m,) + sides(m, BASE) for m in merges]   # every merge is checkable before any line prints
dropped = [line for c in checks for line in scan(*c)]   # every remerge read before any line prints
for line in dropped:
    say(line)
sys.exit(1 if dropped else 0)
