import os, re, subprocess, sys
from events_outcome import outcome
board, prefix, ref, events = sys.argv[1:5]
def git(args, data=None):
    return subprocess.run(["git", "-c", "core.quotePath=false"] + args, cwd=board, input=data,
                          capture_output=True, check=True).stdout
KEY = re.compile(r"([A-Za-z_]+): *(.*)$")
def front(text):
    # The front matter's keys, as dash_fields reads a file's: only after a leading ---, up to the
    # next; a key's first line wins, an empty value too; CRLF tolerated. No state file: these are
    # deleted versions, and a slug's state file may be a later story's.
    keys, lines = {}, [l.rstrip("\r") for l in text.split("\n")]
    if lines[0] != "---":
        return keys
    for l in lines[1:]:
        if l == "---":
            break
        m = KEY.match(l)
        if m and m.group(1) not in keys:
            keys[m.group(1)] = m.group(2)
    return keys
finished_here = set()
try:
    for l in open(events, encoding="utf-8", errors="replace"):
        f = l.rstrip("\n").split("\t")
        if len(f) == 5 and ((f[1] == "finish" and outcome(f) == "ok") or (f[1] == "reconcile" and "finished" in outcome(f))):
            finished_here.add(f[2])
except OSError:
    pass
stories = prefix + "stories/"
BOOKKEEPING = re.compile(r"(^|[\s/])(board|close|epic)/")   # a board, close or epic branch, never a story's own work
BOARD_OWN = [prefix + f for f in ("stories/", "epics/", "hld/", "Board.base", "README.md", ".obsidian/")]   # the board's own files
def board_own(p):
    # As on_board_paths (merge.sh) has it: a directory by its prefix, a file exactly (Board.base, not Board.base.py).
    return any(p.startswith(o) if o.endswith("/") else p == o for o in BOARD_OWN)
tips = [ref] + (["HEAD"] if ref != "HEAD" else [])
log = git(["log", "--first-parent", "--diff-merges=first-parent", "--no-color", "--no-renames", "--name-status", "--format=%x00%H%x09%s"] + tips + ["--"])
todo = []   # (slug, cat-file spec, closed by its commit), newest first
for chunk in log.decode("utf-8", "replace").split("\0")[1:]:
    head, _, changes = chunk.partition("\n")
    commit, _, subject = head.partition("\t")
    paths = [c.partition("\t")[2] for c in changes.splitlines() if "\t" in c]
    work = not BOOKKEEPING.search(subject) and any(
        not board_own(p) and ("/" in p or not p.endswith(".md")) for p in paths)
    for c in changes.splitlines():
        st, _, path = c.partition("\t")
        if st != "D" or not path.startswith(stories) or not path.endswith(".md") or "/" in path[len(stories):]:
            continue
        slug = path[len(stories):-3]
        if slug != "README" and not os.path.exists(os.path.join(board, "stories", slug + ".md")):
            own = re.search(r"story/" + re.escape(slug) + r"(\s|$)", subject) or work or slug in finished_here
            todo.append((slug, f"{commit}^1:{path}", bool(own)))
out = git(["cat-file", "--batch"], "".join(t[1] + "\n" for t in todo).encode()) if todo else b""
done, pos = set(), 0
for slug, _, own in todo:
    nl = out.index(b"\n", pos)
    head, pos = out[pos:nl], nl + 1
    if head.endswith(b" missing"):
        continue
    size = int(head.rsplit(b" ", 1)[1])
    fm = front(out[pos:pos + size].decode("utf-8", "replace"))
    pos += size + 1
    if slug not in done and fm.get("epic") and (own or fm.get("status") in ("done", "review") or fm.get("prs")):
        done.add(slug)
        # One row per finished story, "-" for an empty value; dash_finished (dash.sh) leaves out an
        # after: story by board.sh's rule and counts the rest per epic.
        print("\t".join(["story", fm["epic"], fm.get("kind") or "-", fm.get("after") or "-"]))
