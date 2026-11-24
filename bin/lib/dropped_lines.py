import difflib, re, subprocess, sys
from collections import Counter

# dropped_lines.py <repo-dir> <base> <head> [--own <path>] [--merged <sha>:<squash>]... [<merge sha>...] — the base lines a PR's
# own merge commits dropped (#693), from local git alone. It walks `git rev-list --first-parent --merges
# <base>..<head>`, oldest first, and with merge SHAs given scans only those (full SHAs, matched
# exactly). Each merge must have two parents, one an ancestor of <base> (the base side) and one not
# (the PR side); the order of the two does not matter. A merge with neither parent on <base> whose
# second parent is a --merged <sha>:<squash> (the caller's word that <sha> is on the branch of a PR merged
# into <base> as commit <squash>, full SHAs matched exactly; one per such PR, as stacked PRs share commits)
# is a stacked build's merge of its parent's branch once that parent merged. Its second parent is its base
# side, and each <squash> must be on <base>, else it is unchecked. A line of the merge's F counts as the
# base's when the F of one of its <squash>es, or the F of a commit of
# `git merge-base --all` of the first parent and <base> (the base commits the build itself holds), has it:
# main squash-merges, so the branch's own commits never reach <base>, and the build can hold commits of
# <base> that the branch lacks (it started on another parent's branch, cut from a newer <base>, or
# merged <base> itself). How many copies a merge keeps is still read from the merge's own two parents
# and their merge base, and every rule below holds as for a merge of the base, the base's own reads
# (gone, owing) included. So a line the parent added that this merge dropped prints only once `git
# merge-base <base> <head>` has it, which is once the build has merged <base> since the parent's squash:
# until then the PR's merge into <base> cannot delete it, as a clean merge keeps <base>'s copy and a
# conflict needs a merge of <base>, which is scanned as any other. The first parent's part of a conflict
# is read too, as it can hold the base's lines. Where a line dropped there has copies the build's own
# commits added (the first parent's copies beyond the most its merge base with the second parent, or a
# base commit it holds, has), a count cannot tell whose copy went, and the merge is unchecked.
# Otherwise it scans
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
# A line the PR's own commits edited is no drop either (own_edits): a printed L of EXTENDED_WORDS or more
# words that no head line extends does not print when one of the PR's own commits (`git log --no-merges
# <base>..<head>`, so never a merge of the base) changed a line X of F to X' in one hunk, X being the line
# of those the hunk removed that is most like X', and the head's F holds L with that same edit made at the
# same place (rebased), from the spare lines the extended check draws on. L must be X with only the part
# the edit changed changed: it starts and ends as X does around that part. Where X is L, the head line is
# X' itself, and the merge base of the merge's parents must have no copy of L, as when the PR reworded a
# line that the base also has by a squash of the same change (#1169): a copy that merge base has is one
# the count above already lets the PR remove. Where X is not L, the hunk of the base side's change to F
# (`git diff` of F at that merge base and at the base side, base_edits) that added L must have removed X,
# X being the line of those that hunk removed most like L, so the base changed X into L, and that merge
# base must hold more copies of X than the two sides together, so the copy the PR edited is the one the
# base changed, and the head line is the base's L with the PR's edit in it, as when both sides added a
# word to one list (#1042). A resolution that kept X' alone and lost the base's edit still prints, as do a
# line the base added beside an X it kept or in place of an X it removed elsewhere, a line dropped by a
# merge alone, which no commit of the PR's own changed, one the PR's commits deleted outright, and one
# edited twice over. Either way the PR side of the merge must hold more copies of X', beyond those that
# merge base holds, than edits that made X' have already stood for, so no later commit of the PR's own
# undid the edit before the merge, in one step or more. Each copy of X the PR's commits edited stands for
# one dropped line, however many lines the hunk made of it, and an edit a later commit of its own made the
# other way stands for none. The edit is read under the commit's own name for F, which must be the head's,
# and a hunk of either change with more than OWN_HUNK_LINES removed or added lines edits nothing.
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
# With --own <path>, the PR's own story file (merge.sh's dropped_lines), no line of that file prints when
# <head> has no file at <path>: a story PR deletes its own story file, so a line the base added to it
# after the branch was cut (a board PR setting a field) is gone with the file, not dropped. A head that
# keeps the file counts its lines as any other file's.

TEXT_CHARS = 300   # the most of a dropped line's text it prints (merge.sh's FIX_MAIN_LINE_CHARS)
GIT_SECONDS = 120  # the longest one git call may run
EXTENDED_WORDS = 3  # the fewest words a printed line needs for a longer head line to clear it: a `}` or
                    # an `exit 1` is in many lines a PR writes for itself (`} else {`, `|| exit 1`)
EXTENDED_SHARE = 0.5  # a printed line's words must be more than this share of the words of a head line
                      # that clears it, so that line is the printed one with words added
OWN_HUNK_LINES = 50  # the most removed, or added, lines a hunk of the PR's own commits may have for its
                     # edits to clear a printed line: each added line is weighed against every removed
                     # one, so a rewrite of a whole file would cost its square
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
    """(PR side, base side, the base side's section, the commits whose files say what the base holds, the base
    commits the PR side holds) of merge m, or stop saying why it cannot be checked. The last is empty but for
    a merge of a merged parent's branch, whose PR side's conflict sections are then read too (scan)."""
    rc, out, err = git("rev-list", "--parents", "-n", "1", "--end-of-options", m)
    if rc != 0:
        stop("cannot read the parents of merge %s: %s" % (m[:7], err))
    parents = out.decode().split()[1:]
    if len(parents) != 2:
        stop("merge %s has %d parents: an octopus merge is not remerged, so it is not checked" % (m[:7], len(parents)))
    on = [p for p in parents if ancestor(p, base)]
    if not on and parents[1] in MERGED:   # a merge of a merged parent PR's branch, its squash on the base
        squashes = MERGED[parents[1]]
        for squash in squashes:
            if not ancestor(squash, base):
                stop("merge %s is unchecked: %s, the squash of its second parent's PR, is not on %s"
                     % (m[:7], squash[:7], base))
        rc, out, err = git("merge-base", "--all", parents[0], base)
        if rc not in (0, 1):
            stop("cannot find the commits of %s that merge %s's first parent holds: %s" % (base, m[:7], err))
        held = out.decode().split()
        return parents[0], parents[1], SECOND, squashes + held, held
    if not on:
        stop("merge %s is unchecked: neither parent is on %s, so it is not a merge of %s"
             " (a stacked build's merge of its parent branch?)" % (m[:7], base, base))
    if len(on) == 2:
        stop("merge %s is unchecked: both parents are on %s, so neither is the PR's side" % (m[:7], base))
    pr, side, ours = (parents[1], parents[0], FIRST) if on[0] == parents[0] else (parents[0], parents[1], SECOND)
    return pr, side, ours, [side], []

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

def scan(m, pr, base_side, ours, holds, held):
    """(head key, copies the head owes, copies it holds, the head file's spare lines, `<sha7> <file>: <text>`,
    its origin) per base line merge m's resolution dropped (owing); holds and held are sides'. The origin is
    whether the merge base of m's parents lacks the line, a call that gives the lines it replaced in the base
    side's change (base_edits), and the lines of the PR side's file, of that merge base's and of the base
    side's, which the PR's own edits need (extended)"""
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
    counts = {}  # (file, text): its name in the merge, the merge's copies of text, those the PR side had removed
    mosts = {}   # (revs, file, its name in m): the most copies of each line its file holds at any of revs
    def most(revs, path, after):
        """the most copies of each line that the file holds at any of revs (copies), read once per file; None
        where none of them has the file"""
        if len(revs) == 1:
            return copies(revs[0], path, after)
        if (tuple(revs), path, after) not in mosts:
            got, top = [c for c in (copies(rev, path, after) for rev in revs) if c is not None], Counter()
            for c in got:
                top |= c   # a Counter union keeps each line's larger count
            mosts[tuple(revs), path, after] = top if got else None
        return mosts[tuple(revs), path, after]

    added = {}   # (file, its name in m): the base side's hunks of it; with a text too, base_edits' answer
    def base_edits(path, after, text):
        """the lines text replaced in the base side's change to the file: per hunk that added it, the line of
        those the hunk removed that is most like it (like, as own_edits pairs them), from `git diff` of the
        file at the merge base of m's parents and at the base side, each read under its own name for it
        (named); none where either has no such file, and none from a hunk past OWN_HUNK_LINES on either side"""
        if (path, after, text) in added:
            return added[path, after, text]
        if (path, after) not in added:
            got, a, b = [], named(mb, path, after)[0] if mb else None, named(base_side, path, after)[0]
            if a is not None and b is not None:
                rc, diff, err = git("diff", "-U0", "--inter-hunk-context=0", "--no-color", "--no-ext-diff",
                                    "--no-textconv", "--src-prefix=a/", "--dst-prefix=b/",
                                    mb.encode() + b":" + a, base_side.encode() + b":" + b)
                if rc != 0:
                    stop("cannot read the base side's change to %s for merge %s: %s" % (clean(path), m[:7], err))
                got = [(cut, put) for _, cut, put in hunks(diff)
                       if cut and put and len(cut) <= OWN_HUNK_LINES and len(put) <= OWN_HUNK_LINES]
            added[path, after] = got
        added[path, after, text] = frozenset(max(cut, key=lambda o: like(o, text))
                                             for cut, put in added[path, after] if text in put)
        return added[path, after, text]

    origins = {}   # (file, text): (whether the merge base of m's parents lacks text, a call that gives base_edits'
                   # lines for it, read only when an edit needs them, the PR side's lines, that merge base's, the
                   # base side's)
    sections = (OUTSIDE, ours, FIRST) if held else (OUTSIDE, ours)
    for path, after, section, text in removed(out):
        if not text.strip() or section not in sections or (OWN_GONE and OWN in (path, after)):
            continue
        base = most(holds, path, after)
        if base is None:
            if section == ours:   # the base's part of a conflict, so the base side has this file
                stop("merge %s is unchecked: %s, in a conflict, is not on its base side under that name or"
                     " a rename git finds" % (m[:7], clean(path)))
            continue
        side, root = copies(pr, path, after) or Counter(), copies(mb, path, after) or Counter()
        kept = (read(m, after) or Counter()) if after is not None else Counter()
        if (path, text) not in short:
            # the merge's own sides say how many copies a merge of them keeps
            two = (copies(base_side, path, after) or Counter()) if held else base
            short[path, text] = (owed(two[text], side[text], root[text]) - kept[text]
                                 if base[text] and not gone(path, after, text) else 0)
            counts[path, text] = after, kept[text], max(0, root[text] - side[text])
            if short[path, text] > 0:   # what the PR's own edits need to stand for it (extended)
                origins[path, text] = (not root[text], lambda p=path, a=after, t=text: base_edits(p, a, t), side,
                                       root, copies(base_side, path, after) or Counter())
            # In the PR side's own part of a conflict, a copy its own commits added (beyond the most its merge
            # base with the base side, or a base commit it holds, has) cannot be told from the base's.
            if short[path, text] > 0 and held and section == FIRST \
                    and side[text] > max(root[text], (most(held, path, after) or Counter())[text]):
                stop("merge %s is unchecked: %s: %s, dropped from its first parent's part of a conflict, has"
                     " copies the build's own commits added, so a count cannot tell whose copy it dropped"
                     % (m[:7], clean(path), clean(text)[:TEXT_CHARS]))
        if short[path, text] > 0:   # a copy the resolution moved is removed here and added back elsewhere
            short[path, text] -= 1
            found.append((path, text, "%s %s: %s" % (m[:7], clean(path), clean(text)[:TEXT_CHARS])))
    printed = Counter((path, text) for path, text, _ in found)
    return [owing(path, text, printed[path, text]) + (line, origins[path, text]) for path, text, line in found]

def missing(found):
    """the entries of found, (head key, copies owed, copies held, spare lines, line, origin) per printed copy,
    that the head has not put back: per key, as many as the head holds fewer copies than the most any merge owes, the
    newest merges' entries kept, in merge order (oldest first)"""
    owe = {}
    for key, need, _, _, _, _ in found:
        owe[key] = max(owe.get(key, need), need)
    short = {key: owe[key] - held for key, _, held, _, _, _ in found}
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

class Edits:
    """the edits the PR's own commits made in one file (own_edits): pairs counts each (old, new), less the times
    the commits made it the other way, so an edit a later commit reverted counts for nothing; cuts counts the
    copies of each old the hunks removed with a line paired to them, so one removed copy edited into two lines
    stands for one dropped line"""
    def __init__(self):
        self.pairs, self.cuts = Counter(), Counter()

def hunks(diff):
    """(file, lines removed, lines added) per hunk of a -U0 diff, the file as its +++ line names it (None for
    a deletion); a context line, which a config's diff.interHunkContext can still put in, is neither"""
    path, header, old, new, cut, put = None, False, 0, 0, [], []
    for line in diff.split(b"\n"):
        if old > 0 or new > 0:
            tag = line[:1]
            if tag == b"-":
                cut.append(line[1:])
                old -= 1
            elif tag == b"+":
                put.append(line[1:])
                new -= 1
            elif tag != b"\\":
                old, new = old - 1, new - 1
            if old == 0 and new == 0:
                yield path, cut, put
            continue
        if line.startswith(b"diff --git "):
            path, header = None, True
        elif header and line.startswith(b"+++ "):
            name = unquote(line[4:].rstrip(b"\t"))
            path = name[2:] if name.startswith(b"b/") else None
        elif header or path is not None:
            m = HUNK.match(line)
            if m:
                header, cut, put = False, [], []
                old = int(m.group(1)) if m.group(1) is not None else 1
                new = int(m.group(2)) if m.group(2) is not None else 1
                if old == 0 and new == 0:
                    yield path, cut, put

def own_edits(paths):
    """{file: Edits}: each line new that a hunk of the PR's own commits (`git log --no-merges <base>..<head>`,
    its merges of the base left out) added, beside the line old of those the hunk removed that is most like it
    (difflib's ratio, the first of a tie), under the commit's name for the file, for the files in paths; a hunk
    past OWN_HUNK_LINES on either side is left out. So a line the hunk deleted outright beside one it edited
    pairs with nothing"""
    rc, out, err = git("--literal-pathspecs", "log", "--no-merges", "-p", "-M", "-U0", "--inter-hunk-context=0",
                       "--format=", "--no-color", "--no-ext-diff", "--no-textconv", "--src-prefix=a/",
                       "--dst-prefix=b/", "--end-of-options", BASE + ".." + HEAD, "--", *paths)
    if rc != 0:
        stop("cannot read the PR's own commits in %s..%s: %s" % (BASE, HEAD, err))
    edits = {}
    for path, cut, put in hunks(out):
        if path is None or not cut or not put or len(cut) > OWN_HUNK_LINES or len(put) > OWN_HUNK_LINES:
            continue
        made = edits.setdefault(path, Edits())
        pairs = [(max(cut, key=lambda o: like(o, n)), n) for n in put]
        made.pairs.update(pairs)
        for o, partners in Counter(o for o, _ in pairs).items():
            made.cuts[o] += min(cut.count(o), partners)
    for made in edits.values():
        each = dict(made.pairs)
        for (o, n), times in each.items():
            made.pairs[o, n] = times - each.get((n, o), 0) if o != n else 0
    return edits

def like(a, b):
    """how alike lines a and b are, from 0 to 1 (difflib's ratio)"""
    return difflib.SequenceMatcher(None, a, b, autojunk=False).ratio()

def common(a, b):
    """how many leading bytes a and b share"""
    n = 0
    while n < min(len(a), len(b)) and a[n] == b[n]:
        n += 1
    return n

def rebased(old, new, text):
    """what text becomes when the edit that turned old into new is made at the same place in it: old is
    lead + cut + tail and new lead + put + tail, lead and tail the most the two share at each end; text must
    be lead + mid + tail, so it is old with only the part the edit changed changed, and cut, at mid's start
    or its end, is swapped for put. Nothing where text does not start with lead and end with tail"""
    start = common(old, new)
    end = common(old[start:][::-1], new[start:][::-1])
    lead, cut, put, tail = old[:start], old[start:len(old) - end], new[start:len(new) - end], old[len(old) - end:]
    if len(lead) + len(tail) > len(text) or not text.startswith(lead) or not text.endswith(tail):
        return []
    mid, out = text[len(lead):len(text) - len(tail)], []
    if mid.startswith(cut):
        out.append(lead + put + mid[len(cut):] + tail)
    if mid.endswith(cut):
        out.append(lead + mid[:len(mid) - len(cut)] + put + tail)
    return out

def extended(left, found):
    """the lines of left (missing's entries) that no line the head added extends or holds as the PR's own
    edit: in print order, an entry of EXTENDED_WORDS or more words takes the first spare head line of its
    file, not yet taken, that extends it, else the first that is it with an edit of the PR's own commits made
    in it (own_edits, rebased), the edit taken too, and does not print; a text any entry of found has never
    stands for another"""
    pools = {}   # head file: its spare lines' copies not yet taken
    for key, _, _, spare, _, _ in found:
        pools.setdefault(key[:-1], Counter(spare))
    for key, _, _, _, _, _ in found:
        pools[key[:-1]].pop(key[-1], None)
    edits = None   # own_edits of the head files left, read once a line needs them
    spent = Counter()   # (head file, an edit's new line): the dropped lines edits that made it stood for

    def ours(name, made, pair, text, origin):
        """whether edit pair of the PR's own can stand for dropped line text, given its origin (scan): text is the
        line the edit changed, and the merge base of the merge's parents had no copy of it, as a copy it had is
        one the merge's count already lets the PR remove; or the base side's hunk that added text removed the
        line the edit changed, so the base changed that line into text, and the two sides removed one copy of it
        between them, as that merge base has more copies than the two sides together. Either way the merge's PR
        side holds more
        copies of the edit's new line, beyond those its merge base has, than edits that made it have stood for,
        so no later commit of the PR's own undid the edit before the merge"""
        if made.pairs[pair] <= 0 or made.cuts[pair[0]] <= 0 \
                or spent[name, pair[1]] >= origin[2][pair[1]] - origin[3][pair[1]]:
            return False
        side, root, base = origin[2:]
        if pair[0] == text:
            return origin[0]
        return root[pair[0]] > side[pair[0]] + base[pair[0]] and pair[0] in origin[1]()

    lines = []
    for key, _, _, _, line, origin in left:
        pool, text = pools[key[:-1]], key[-1]
        enough = len(text.split()) >= EXTENDED_WORDS
        head = next((h for h in pool if pool[h] > 0 and extends(text, h)), None) if enough else None
        if head is None and enough and key[0] is not None:
            if edits is None:
                edits = own_edits(sorted({k[0] for k, _, _, _, _, _ in left if k[0] is not None}))
            made = edits.get(key[0], Edits())
            edit, head = next(((pair, h) for pair in list(made.pairs) if ours(key[0], made, pair, text, origin)
                               for h in rebased(pair[0], pair[1], text) if pool[h] > 0), (None, None))
            if edit is not None:   # each copy the PR edited stands for one dropped line
                made.pairs[edit] -= 1
                made.cuts[edit[0]] -= 1
                spent[key[0], edit[1]] += 1
        if head is None:
            lines.append(line)
        else:
            pool[head] -= 1
    return lines

USAGE = "usage: dropped_lines.py <repo-dir> <base> <head> [--own <path>] [--merged <sha>:<squash>]... [<merge sha>...]"
if len(sys.argv) < 4:
    stop(USAGE)
REPO, BASE, HEAD = sys.argv[1:4]
MERGED, wanted, rest = {}, set(), iter(sys.argv[4:])   # MERGED: second parent on merged PRs' branches -> their squashes
OWN = None   # --own: the PR's own story file, as bytes, which removed() yields
for arg in rest:
    if arg == "--own":
        own = next(rest, None)
        if not own:
            stop(USAGE)
        OWN = own.encode()
    elif arg == "--merged":
        pair = (next(rest, None) or "").lower().split(":")
        if len(pair) != 2 or not all(pair):
            stop(USAGE)
        MERGED.setdefault(pair[0], []).append(pair[1])
    else:
        wanted.add(arg.lower())
rc, out, err = git("rev-list", "--first-parent", "--merges", "--reverse", "--end-of-options", BASE + ".." + HEAD, "--")
if rc != 0:
    stop("cannot list the merges in %s..%s: %s" % (BASE, HEAD, err))
merges = [m for m in out.decode().split() if not wanted or m in wanted]
OWN_GONE = False   # whether <head> has no file at OWN, so its lines do not print
if OWN is not None:
    rc, out, err = git("--literal-pathspecs", "ls-tree", "--name-only", "-z", "--end-of-options", HEAD, "--", OWN)
    if rc != 0:
        stop("cannot tell whether %s has %s: %s" % (HEAD[:7], clean(OWN), err))
    OWN_GONE = not out
checks = [(m,) + sides(m, BASE) for m in merges]   # every merge is checkable before any line prints
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
