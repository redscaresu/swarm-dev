# Holds, a flow section (flow_report.py gives its globals): one TSV row per hold of a ready story
# (`swarm.sh hold <slug> <why>`, an events.tsv hold line, outcome `ok (<why>)`), from events.tsv alone:
# story, epic (outcomes' rows, else its board story file, else -), reason (the first hold's), and
# held_min from that first hold line to the story's next build start (an ok `story` line), or `open`
# while none followed. Later hold lines before that start are the same hold; one after it starts a
# new one. A hold counts in the window when its first line's local day is in it; --epic keeps that
# epic's. Then, after a blank line, the held minutes per reason class, closed holds only: clash when
# the reason names a story (another slug from the rows, the board or a story or hold line) or a PR (`PR`,
# `#<n>` or a /pull/ URL), else other.
import datetime, os, re
from touches_rows import front_text

PR = re.compile(r"\bPR\b|#\d+|/pull/\d+")
board = os.environ.get("SWARM_BOARD", "")

def when(t):
    try:
        return datetime.datetime.fromisoformat(t.replace("Z", "+00:00"))
    except ValueError:
        return None

def epic_of(slug):
    f = os.path.join(board, "stories", slug + ".md")
    e = next((r["epic"] for r in rows if r["slug"] == slug and r["epic"]), "")
    if not e and os.path.isfile(f):
        e = front_text(open(f, encoding="utf-8", errors="replace").read()).get("epic", "").strip()
    return e or "-"

slugs = {r["slug"] for r in rows}
if os.path.isdir(os.path.join(board, "stories")):
    slugs |= {n[:-3] for n in os.listdir(os.path.join(board, "stories")) if n.endswith(".md")}
held, holds = {}, []   # held: slug -> its open hold [slug, start, reason, end]
for line in open(events, errors="ignore") if os.path.exists(events) else ():
    f = line.rstrip("\n").split("\t")
    if len(f) != 5 or (t := when(f[0])) is None:
        continue
    if f[1] == "hold" and f[4].startswith("ok (") and f[4].endswith(")"):
        slugs.add(f[2])
        if f[2] not in held:
            held[f[2]] = [f[2], t, f[4][4:-1], None]
            holds.append(held[f[2]])
    elif f[1] == "story" and f[4] == "ok":
        slugs.add(f[2])
        if f[2] in held:
            held.pop(f[2])[3] = t

def clash(slug, reason):
    return PR.search(reason) or any(w in slugs - {slug} for w in re.findall(r"[a-z0-9][a-z0-9-]*", reason))

totals = {"clash": 0, "other": 0}
print("story\tepic\treason\theld_min")
for slug, start, reason, end in holds:
    e = epic_of(slug)
    if not since <= start.astimezone().date().isoformat() <= until or (epic and e != epic):
        continue
    mins = round((end - start).total_seconds() / 60) if end else None
    if mins is not None:
        totals["clash" if clash(slug, reason) else "other"] += mins
    print(f"{slug}\t{e}\t{reason}\t{'open' if mins is None else mins}")
print("\nclass\theld_min")
for k, n in totals.items():
    print(f"{k}\t{n}")
