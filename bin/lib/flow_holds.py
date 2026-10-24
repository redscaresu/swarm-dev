# Holds, a flow section (flow_report.py gives its globals): one TSV row per hold of a ready story
# (`swarm.sh hold <slug> <why>`, an events.tsv hold line, outcome `ok (<why>)`): story, epic (outcomes'
# rows, else its story file on the board or, once deleted, in the board's git history, else -), reason
# (the first hold's), and held_min from that first hold line to the story's next build start (an ok
# `story` line). A hold that ends with no build shows how instead: dropped, reset or closed (the
# slug's next ok drop, reset or close line), or removed (the board commit that deleted its story
# file); open while none of these followed. Later hold lines before its end are the same hold; one
# after it starts a new one. A hold counts in the window when its first line's local day is in it;
# --epic keeps that epic's. Then, after a blank line, the held minutes of the built holds per reason
# class, fixed at the hold's own time: other when the reason is the conductor brief's give-up, closed
# this wave or not held:; else clash when it names a PR (#<n> or a /pull/ URL) or, as a whole
# hyphenated token, a story an ok story line in events.tsv started before the hold; else other.
# ponytail: a one-word slug never counts as named (it would match ordinary words); name its PR if that matters.
import datetime, functools, os, re, subprocess, sys
from touches_rows import front_text

PR = re.compile(r"#\d+|/pull/\d+")
SLUG = re.compile(r"(?<![\w./-])[a-z0-9]+(?:-[a-z0-9]+)+(?![\w/-])")
OTHER = re.compile(r"not held|give[- ]?up|gave up|closed (?:in )?this wave", re.I)
ENDS = {"drop": "dropped", "reset": "reset", "close": "closed"}
board = os.environ.get("SWARM_BOARD", "")

def when(t):
    try:
        return datetime.datetime.fromisoformat(t.replace("Z", "+00:00"))
    except ValueError:
        return None

def git(*a):
    r = subprocess.run(["git", "-C", board, *a], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""

@functools.lru_cache(maxsize=None)
def deleted(slug):
    # The board commit that deleted the story's file, and its time; ("", None) while the file is there or none did.
    if os.path.isfile(os.path.join(board, "stories", slug + ".md")):
        return "", None
    c, _, t = git("log", "--diff-filter=D", "-1", "--format=%H %cI", "--", f"./stories/{slug}.md").strip().partition(" ")
    return c, when(t) if t else None

def epic_of(slug):
    f = os.path.join(board, "stories", slug + ".md")
    e = next((r["epic"] for r in rows if r["slug"] == slug and r["epic"]), "")
    if not e and os.path.isfile(f):
        e = front_text(open(f, encoding="utf-8", errors="replace").read()).get("epic", "")
    elif not e and deleted(slug)[0]:
        e = front_text(git("show", f"{deleted(slug)[0]}^:./stories/{slug}.md")).get("epic", "")
    return e.strip() or "-"

def reason_class(reason, started):
    if OTHER.search(reason):
        return "other"
    return "clash" if PR.search(reason) or started & set(SLUG.findall(reason)) else "other"

started, held, holds = set(), {}, []   # held: slug -> its open hold [slug, start, reason, class, end, how]
for line in open(events, errors="ignore") if os.path.exists(events) else ():
    f = line.rstrip("\n").split("\t")
    cmd = f[1].partition(":")[0] if len(f) == 5 else ""
    if not cmd or (t := when(f[0])) is None:
        continue
    if cmd == "hold" and f[4].startswith("ok (") and f[4].endswith(")") and f[2] not in held:
        held[f[2]] = [f[2], t, f[4][4:-1], reason_class(f[4][4:-1], started - {f[2]}), None, None]
        holds.append(held[f[2]])
    elif cmd == "story" and f[4] == "ok":
        started.add(f[2])
        if f[2] in held:
            held.pop(f[2])[4] = t
    elif cmd in ENDS and f[4].startswith("ok") and f[2] in held:
        held.pop(f[2])[4:] = [t, ENDS[cmd]]
for h in held.values():
    gone = deleted(h[0])[1]
    if gone and gone >= h[1]:
        h[4:] = [gone, "removed"]

totals, shown = {"clash": 0, "other": 0}, []
for slug, start, reason, cls, end, how in holds:
    e = epic_of(slug)
    if since <= start.astimezone().date().isoformat() <= until and (not epic or e == epic):
        mins = round((end - start).total_seconds() / 60) if end and not how else None
        totals[cls] += mins or 0
        shown.append(f"{slug}\t{e}\t{reason}\t{how or ('open' if mins is None else mins)}")
if not shown:
    print(f"no hold{f' of epic {epic}' if epic else ''} in the window")
    sys.exit()   # ends this section alone (flow_report.py)
print("story\tepic\treason\theld_min", *shown, "", "class\theld_min", sep="\n")
for k, n in totals.items():
    print(f"{k}\t{n}")
