import re, subprocess, sys
from collections import Counter

# dropped_lines.py <repo-dir> <base> <head> [--merged <sha>]... [<merge sha>...] — the base lines a PR's
# own merge commits dropped (#693), from local git alone. It walks `git rev-list --first-parent --merges
# <base>..<head>`, oldest first, and with merge SHAs given scans only those (full SHAs, matched
# exactly). Each merge must have two parents, one an ancestor of <base> (the base side) and one not
# (the PR side); the order of the two does not matter. A merge with neither parent on <base> whose
# second parent is a --merged SHA (the caller's word that it is on the branch of a PR merged into
# <base>, full SHAs matched exactly) is a stacked build's merge of its parent's branch once that parent
# merged: its second parent is its base side, the parent's branch standing for the base, and every rule
# below holds as for a merge of the base, the base's own reads (gone, owing) included. So a line the
# parent added that this merge dropped prints only once `git merge-base <base> <head>` has it, which is
# once the build has merged <base> since the parent's squash: until then the PR's merge into <base>
# cannot delete it, as a clean merge keeps <base>'s copy and a conflict needs a merge of <base>, which
# is scanned as any other. Its first parent
# can hold commits of <base> that branch lacks, as when the build started on another parent's branch, cut
# from a newer <base>, or merged <base> itself; a line of theirs the merge dropped is not in the second
# parent's F, so the scan above cannot see it. Each such commit (a `git merge-base --all` of the first
# parent and <base> that is not on the second parent) gets a scan of its own with the sides swapped: the
# first parent is the base side, and only the copies of a line that commit's F holds too count as its
# copies, so the first parent's own lines, a `}` of its own among them, never count as the base's. A
# count cannot tell copies apart here either: where the first parent holds a copy of its own beside that
# commit's and the merge kept one of the two, nothing prints, as for a line each side of a merge of the
# base added once (owed). A dropped line of that commit with no such copy prints. The copies the PR's own
# commits had removed before the merge (owing, below) are there also the ones that commit's F has beyond
# the first parent's, so a build that removed one copy of a line itself owes only the copy the merge
# dropped. A line both scans find prints once, as the head is short of it once. Otherwise it scans
# nothing: an octopus is not remerged this way, and a merge with neither parent on <base> and no
# --merged second parent (a stacked build's merge of a parent branch whose PR has not merged) is
# unchecked, not clean. Of each merge's `git show --remerge-diff`, a removed line L of
# file F prints when L is in the base side's F and the merge's F has fewer copies of L than a merge
# of the two sides keeps (owed): the base side's copies, plus the PR side's, less the merge base's
# (`git merge-base` of the two parents). A line the merge base's F lacks and both sides added, as when
# one change reached the base by a squash merge and the PR side by its own commit, is owed the larger
# side's copies instead, so one copy kept of a line each side added once is no drop. Where the merge
# base has L, a new copy on each side can be two separate additions (a `}`, a `fi`), so the sum
# stands. It prints L once per copy the merge's F is short of, so a copy the resolution moved,
# removed in one place and added back in another, is no second report. So a copy the base added
# (beyond the PR side's, for a line new to F), or one both sides had, that the resolution dropped
# prints, and a copy the PR's own commits removed does not, whatever other copies of L the file
# holds. A line the base itself no longer has is no drop: when <base>'s F, or the F of `git merge-base
# <base> <head>`, has no copy of L, L does not print, so a merge a stacked build's parent made, still in
# the build's history once the parent's squash merge is on <base>, stops counting a line that squash took
# off. Those two commits' F is read as the other sides' is, and one with no such file under any name git
# finds still counts L. A line the PR's head holds again is no drop either: once every merge is read,
# L of F prints only while <head>'s F, read under the head's own name for it, holds fewer copies of L
# than a merge that printed L owes it. A merge owes the larger of two counts. One is the copies its F
# kept plus the ones it printed, which keeps a drop the PR's own copies hide: a head with as many copies
# as the base, one of them the PR's, still lacks the base's. The other is the copies the F of
# `git merge-base <base> <head>` holds, less those the PR's own commits had removed before the merge
# (the ones its parents' merge base has beyond the PR side's), which keeps a drop that a copy the base
# added since hides. The two are never summed: a stacked build's parent's own copies reach the base by
# its squash merge, and a sum would owe them twice. The merge that owes the most counts, and L prints
# once per copy the head is short of that. The lines kept are the newest merges', since a commit that
# puts a line back comes after the merge that dropped it, and they print in merge order, oldest first.
# So a later commit that restores the line clears it, and one that restores one of two dropped copies
# leaves one. A count cannot tell copies apart: a copy the PR adds after the merge for its own sake
# counts as one put back, and so does one the base adds after it where the PR side holds a copy the
# base does not. Where that merge base has no such file under any name git finds, every L prints.
# A line the PR's head extends is no drop either (extended): after that, a printed L of EXTENDED_WORDS
# or more words does not print when the head's F holds a line that is L with words added or only its
# spacing changed, and no line printed before it claimed that copy, as when the PR inserted a section
# into a table row the base also changed. That head line holds every word of L in the same order (words
# split on whitespace), and L's words are more than EXTENDED_SHARE of its own, so a longer line that only
# happens to hold L's words (`[ -n "$x" ] || exit 1` for a dropped `exit 1`) does not clear L. Only the
# head's copies of a line beyond the most <base>'s F or the F of `git merge-base <base> <head>` holds can
# stand for L, and none of a text any merge printed, so a base line the resolution kept, or a dropped
# line's own copies, never clears another. Where either commit has no such file under any name git
# finds, its copies are unknown, and no head line stands for L. Two base lines extended into one head
# line still print one, and a line whose words were changed, taken out or reordered still prints.
# Each side's F is read
# under that side's own name for it: a file renamed on one side is found through `git diff -M`
# against the merge. Inside a conflict section a line's side is the section's (the first parent's
# part, then the second's, followed across the diff's hunks), never its text found elsewhere in the
# base file, so a PR-side line in a conflict never counts as a base line; a base-side line whose file
# the base side does not have under any name git finds is unchecked. Conflict markers, the merge
# base's part of a section and whitespace-only lines never print. It prints `<merge sha7> <file>:
# <text>` per dropped line, control characters taken off and the text cut to TEXT_CHARS (it reaches
# events.tsv, state files and panes, as ci_data's lines do), and exits 1; with nothing dropped, it
# prints nothing and exits 0. When it cannot check, it prints one line on stdout saying why and exits
# 2, before printing any dropped line.

TEXT_CHARS = 300   # the most of a dropped line's text it prints (merge.sh's FIX_MAIN_LINE_CHARS)
GIT_SECONDS = 120  # the longest one git call may run
EXTENDED_WORDS = 3  # the fewest words a printed line needs for a longer head line to clear it: a `}` or
                    # an `exit 1` is in many lines a PR writes for itself (`} else {`, `|| exit 1`)
EXTENDED_SHARE = 0.5  # a printed line's words must be more than this share of the words of a head line
                      # that clears it, so that line is the printed one with words added
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
    """the scans of merge m, each (PR side, base side, the base side's section, only), or stop saying why it
    cannot be checked; only is None, or the commit of base whose copies of a line alone count as the base
    side's: one scan per merge, and for a merge of a merged parent PR's branch one more per commit of base
    its first parent holds and its second lacks"""
    rc, out, err = git("rev-list", "--parents", "-n", "1", "--end-of-options", m)
    if rc != 0:
        stop("cannot read the parents of merge %s: %s" % (m[:7], err))
    parents = out.decode().split()[1:]
    if len(parents) != 2:
        stop("merge %s has %d parents: an octopus merge is not remerged, so it is not checked" % (m[:7], len(parents)))
    on = [p for p in parents if ancestor(p, base)]
    if not on and parents[1] in MERGED:   # a merge of a merged parent PR's branch, which stands for the base
        rc, out, err = git("merge-base", "--all", parents[0], base)
        if rc not in (0, 1):
            stop("cannot find the commits of %s that merge %s's first parent holds: %s" % (base, m[:7], err))
        ahead = [b for b in out.decode().split() if not ancestor(b, parents[1])]
        return [(parents[0], parents[1], SECOND, None)] + [(parents[1], parents[0], FIRST, b) for b in ahead]
    if not on:
        stop("merge %s is unchecked: neither parent is on %s, so it is not a merge of %s"
             " (a stacked build's merge of its parent branch?)" % (m[:7], base, base))
    if len(on) == 2:
        stop("merge %s is unchecked: both parents are on %s, so neither is the PR's side" % (m[:7], base))
    return [(parents[1], parents[0], FIRST, None) if on[0] == parents[0] else (parents[0], parents[1], SECOND, None)]

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
    """(file, its name in the merge or None, section, text) for each line the remerge diff removes, markers
    left out; the file is the remerged one's name"""
    path, after, header, old, new, section, size = None, None, False, 0, 0, OUTSIDE, 0
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
                yield path, after, section, text
            continue
        if line.startswith(b"diff --git "):
            path, after, header, section = None, None, True, OUTSIDE
        elif header and line.startswith((b"--- ", b"+++ ")):
            name = unquote(line[4:].rstrip(b"\t"))
            if line.startswith(b"--- "):
                path = name[2:] if name.startswith(b"a/") else None
            else:
                after = name[2:] if name.startswith(b"b/") else None
        elif header or path is not None:
            m = HUNK.match(line)
            if m:
                header = False
                old = int(m.group(1)) if m.group(1) is not None else 1
                new = int(m.group(2)) if m.group(2) is not None else 1

def owed(base, side, root):
    """the copies of a line a merge of the two sides keeps, from each side's count and the merge base's: the
    sum less the merge base's, or the larger side's for a line new to the file that both sides added"""
    if root == 0 and base > 0 and side > 0:   # one change on both sides, such as a squash and its own commit
        return max(base, side)
    return base + side - root   # with L in the merge base, a new copy on each side can be two additions

def scan(m, pr, base_side, ours, only):
    """(head key, copies the head owes, copies it holds, the head file's spare lines, `<sha7> <file>: <text>`)
    per base line merge m's resolution dropped (owing); with only, a commit, the base side's copies of a line
    are those only's file holds too (sides)"""
    rc, out, err = git("show", "--remerge-diff", "--format=", "--no-color", "--no-ext-diff", "--no-textconv",
                       "--src-prefix=a/", "--dst-prefix=b/", "--end-of-options", m)
    if rc != 0:
        stop("git show --remerge-diff failed on merge %s: %s" % (m[:7], err))
    rc, mb, err = git("merge-base", pr, base_side)
    if rc not in (0, 1):
        stop("cannot find the merge base of merge %s's parents: %s" % (m[:7], err))
    mb = mb.decode().strip() if rc == 0 else None   # 1: no common ancestor, so every line is new
    files, renames, spares, found = {}, {}, {}, []

    def read(rev, path):
        """each line of path at rev and its count; None where rev has no such path, a stop when git cannot read it"""
        if (rev, path) not in files:
            rc, blob, err = git("cat-file", "blob", rev.encode() + b":" + path)
            if rc != 0:
                gone, listed, _ = git("--literal-pathspecs", "ls-tree", "--name-only", "-z", rev, "--", path)
                if gone != 0 or listed:
                    stop("cannot read %s at %s for merge %s: %s" % (clean(path), rev[:7], m[:7], err))
            files[rev, path] = Counter(blob.split(b"\n")) if rc == 0 else None
        return files[rev, path]

    def renamed(rev):
        """each path in m's tree that rev holds under another name (git diff -M), mapped to that name"""
        if rev not in renames:
            rc, out, err = git("diff", "-M", "--name-status", "-z", "--no-ext-diff", rev, m, "--")
            if rc != 0:
                stop("cannot read the renames between %s and merge %s: %s" % (rev[:7], m[:7], err))
            f, renames[rev], i = out.split(b"\0"), {}, 0
            while i + 1 < len(f) and f[i]:
                if f[i][:1] in (b"R", b"C"):
                    renames[rev][f[i + 2]] = f[i + 1]
                    i += 3
                else:
                    i += 2
        return renames[rev]

    def named(rev, path, after):
        """(rev's own name for the file, its lines): after (its name in m) or what rev renamed to after,
        else path; (None, None) where rev has none of them"""
        name = after or path
        got = read(rev, name)
        if got is None and after is not None and after in renamed(rev):
            name = renamed(rev)[after]
            got = read(rev, name)
        return (name, got) if got is not None else (None, None)

    def copies(rev, path, after):
        """the file's lines at rev, read under rev's own name for it (named); None where rev has none of
        them, and no lines where there is no rev"""
        return Counter() if rev is None else named(rev, path, after)[1]

    def gone(path, after, text):
        """whether the base itself no longer has text in this file: at <base> or at the PR's merge base
        with it (LATER), the file, read under that commit's own name for it, has no copy; a commit with
        no such file under any name git finds still counts the line"""
        for rev in LATER:
            got = copies(rev, path, after)
            if got is not None and not got[text]:
                return True
        return False

    def spare(path, after):
        """the head's copies of each line of the file beyond the most that <base> or the merge base of <base>
        and <head> (LATER) holds, each file read under that commit's own name for it (named); none where one
        of them has no such file, as its copies are then unknown"""
        if (path, after) not in spares:
            later, base = [copies(rev, path, after) for rev in LATER], Counter()
            for got in later:
                base |= got or Counter()
            known = all(got is not None for got in later)
            spares[path, after] = (named(HEAD, path, after)[1] or Counter()) - base if known else Counter()
        return spares[path, after]

    def owing(path, text, printed):
        """(the head's file and text, the copies of text the head owes merge m, the copies it holds, the head
        file's spare lines): the larger of the merge's copies plus the ones it printed, and those the merge
        base of <base> and <head> holds less the ones the PR side had removed; no bound where that merge base
        has no such file"""
        after, kept, cut = counts[path, text]
        name, now = named(HEAD, path, after)
        since = copies(MERGE_BASE, path, after) if MERGE_BASE else None
        need = max(kept + printed, since[text] - cut) if since is not None else float("inf")
        key = (name, text) if name is not None else (None, path, text)
        return key, need, (now or Counter())[text], spare(path, after)

    short = {}   # (file, text): the copies of text the merge's file is short of, less those printed
    counts = {}  # (file, text): its name in the merge, the merge's copies of text, those removed before the merge
    for path, after, section, text in removed(out):
        if not text.strip() or section not in (OUTSIDE, ours):
            continue
        base = copies(base_side, path, after)
        if base is None:
            if section == ours:   # the base's part of a conflict, so the base side has this file
                stop("merge %s is unchecked: %s, in a conflict, is not on its base side under that name or"
                     " a rename git finds" % (m[:7], clean(path)))
            continue
        whole = Counter()   # with only, its file's copies of each line
        if only is not None:   # a stacked merge's first parent: its lines are the base's as far as only has them
            whole = copies(only, path, after) or Counter()
            base = base & whole
        side, root = copies(pr, path, after) or Counter(), copies(mb, path, after) or Counter()
        kept = (read(m, after) or Counter()) if after is not None else Counter()
        if (path, text) not in short:
            short[path, text] = (owed(base[text], side[text], root[text]) - kept[text]
                                 if base[text] and not gone(path, after, text) else 0)
            # removed before the merge: by the PR side, or with only, by the first parent since only
            counts[path, text] = after, kept[text], max(0, root[text] - side[text], whole[text] - base[text])
        if short[path, text] > 0:   # a copy the resolution moved is removed here and added back elsewhere
            short[path, text] -= 1
            found.append((path, text, "%s %s: %s" % (m[:7], clean(path), clean(text)[:TEXT_CHARS])))
    printed = Counter((path, text) for path, text, _ in found)
    return [owing(path, text, printed[path, text]) + (line,) for path, text, line in found]

def missing(found):
    """the entries of found, (head key, copies owed, copies held, spare lines, line) per printed copy, that the
    head has not put back: per key, as many as the head holds fewer copies than the most any merge owes, the
    newest merges' entries kept, in merge order (oldest first)"""
    owe = {}
    for key, need, _, _, _ in found:
        owe[key] = max(owe.get(key, need), need)
    short = {key: owe[key] - held for key, _, held, _, _ in found}
    left = []
    for entry in reversed(found):
        if short[entry[0]] > 0:
            short[entry[0]] -= 1
            left.append(entry)
    return left[::-1]

def extends(text, head):
    """whether head is text with words added or its spacing changed: head's words (split on whitespace) hold
    every word of text in the same order, and text's are more than EXTENDED_SHARE of them"""
    wanted, words = text.split(), head.split()
    if len(wanted) <= EXTENDED_SHARE * len(words):
        return False
    rest = iter(words)
    return all(word in rest for word in wanted)

def extended(left, found):
    """the lines of left (missing's entries) that no line the head added extends: in print order, an entry of
    EXTENDED_WORDS or more words takes the first spare head line of its file, not yet taken, that extends it,
    and does not print; a text any entry of found has never stands for another"""
    pools = {}   # head file: its spare lines' copies not yet taken
    for key, _, _, spare, _ in found:
        pools.setdefault(key[:-1], Counter(spare))
    for key, _, _, _, _ in found:
        pools[key[:-1]].pop(key[-1], None)
    lines = []
    for key, _, _, _, line in left:
        pool, text = pools[key[:-1]], key[-1]
        enough = len(text.split()) >= EXTENDED_WORDS
        head = next((h for h in pool if pool[h] > 0 and extends(text, h)), None) if enough else None
        if head is None:
            lines.append(line)
        else:
            pool[head] -= 1
    return lines

USAGE = "usage: dropped_lines.py <repo-dir> <base> <head> [--merged <sha>]... [<merge sha>...]"
if len(sys.argv) < 4:
    stop(USAGE)
REPO, BASE, HEAD = sys.argv[1:4]
MERGED, wanted, rest = set(), set(), iter(sys.argv[4:])   # MERGED: second parents on a merged PR's branch
for arg in rest:
    if arg == "--merged":
        sha = next(rest, None)
        if sha is None:
            stop(USAGE)
        MERGED.add(sha.lower())
    else:
        wanted.add(arg.lower())
rc, out, err = git("rev-list", "--first-parent", "--merges", "--reverse", "--end-of-options", BASE + ".." + HEAD, "--")
if rc != 0:
    stop("cannot list the merges in %s..%s: %s" % (BASE, HEAD, err))
merges = [m for m in out.decode().split() if not wanted or m in wanted]
checks = [(m,) + s for m in merges for s in sides(m, BASE)]   # every merge is checkable before any line prints
MERGE_BASE = None   # git merge-base <base> <head>: None with no common ancestor
if checks:
    rc, out, err = git("merge-base", "--end-of-options", BASE, HEAD)
    if rc not in (0, 1):
        stop("cannot find the merge base of %s and %s: %s" % (BASE, HEAD, err))
    MERGE_BASE = out.decode().strip() or None
LATER = [BASE] + ([MERGE_BASE] if MERGE_BASE else [])   # where the base must still have a line (gone)
found = [f for c in checks for f in scan(*c)]   # every remerge read before any line prints
dropped = extended(missing(found), found)
for line in dropped:
    say(line)
sys.exit(1 if dropped else 0)
