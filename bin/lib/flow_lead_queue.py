# Lead queue, a flow section (flow_report.py gives its globals): how long items waited in the lead's
# queue (lead_queue in lifecycle.sh), one TSV row per local day items entered it. From events.tsv's ok
# lines: a story enters it held on held (a close that really held it), escalated on escalated or
# close:impossible, and awaiting merge on review (with merge = agent, only a story whose costs: is not
# none); it leaves on its next reset, reset:held, drop, merge, reconcile or finish. An item with no end
# still waits while the live board shows it so (held_for:, escalated, or in review), else it is left
# out. An item counts up to its end, now or local midnight after --until, whichever is first; one
# still waiting then is listed under open as <kind>: <slug>.
# The section ignores --epic.
import datetime, functools, os, re, statistics, subprocess, time
ENTER = {"held": "held", "close:impossible": "escalated", "escalated": "escalated", "review": "merge"}
LEAVE = {"reset", "reset:held", "drop", "merge", "reconcile", "finish"}
project = os.path.dirname(os.path.dirname(os.path.abspath(events)))   # events is <project>/.swarm/events.tsv
try:
    config = open(os.path.join(project, ".claude/swarm/config"), errors="ignore").read()
except OSError:
    config = ""

def setting(key, default):
    # Its last value, read as load_config reads it: the # comment gone, trimmed, a leading ~ expanded.
    got = [m.group(1) for line in config.splitlines()
           for m in [re.fullmatch(rf"\s*{key}\s*=\s*(.*?)\s*", line.split("#", 1)[0])] if m]
    v = got[-1] if got else default
    return os.path.expanduser(v) if v == "~" or v.startswith("~/") else v

board = os.path.join(project, setting("board_dir", "docs"))   # an absolute board_dir stays as it is

def secs(t):
    try:
        return datetime.datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None

@functools.lru_cache(maxsize=None)
def text(path, history=False):
    # A board file's text; with history, once deleted, its last version in git; else "".
    try:
        return open(os.path.join(board, path), errors="ignore").read()
    except OSError:
        if not history:
            return ""
    git = lambda *a: subprocess.run(["git", "-C", board, *a], capture_output=True, text=True).stdout
    c = git("log", "--diff-filter=D", "-1", "--format=%H", "--", path).strip()
    return git("show", f"{c}^:./{path}") if c else ""

def front(t):
    # Front matter lines, as get_fm reads them: the first `key:` line for each key.
    head = t.split("\n---", 1)[0].splitlines()[1:] if t.startswith("---") else []
    fm = {}
    for line in head:
        k, sep, v = line.partition(":")
        if sep and re.fullmatch(r"[A-Za-z_]+", k):
            fm.setdefault(k, v.strip())
    return head, fm

def costs_money(slug):
    # costs_value's reading: the costs: line and the indented or "- " lines under it (blank and comment
    # lines skipped), each # comment, quote, bracket, comma, dash and space gone, lowercased.
    v, on = None, False
    for line in front(text(f"stories/{slug}.md", history=True))[0]:
        if on and re.fullmatch(r"\s*(#.*)?", line):
            continue
        if on and re.match(r"[\s-]", line):
            v += line.split("#", 1)[0]
            continue
        on = False
        if v is None and line.startswith("costs:"):
            v, on = line[6:].split("#", 1)[0], True
    return re.sub(r"[][\s\"',-]", "", v or "").lower() not in ("", "none")

def still_waiting(kind, slug):
    # From the live board alone: a story deleted with no end line has left the queue.
    fm = front(text(f"stories/{slug}.md"))[1]
    if kind == "held":
        return bool(fm.get("held_for"))
    if kind == "escalated":
        return fm.get("status") == "ready" and fm.get("kind") == "lead" and bool(fm.get("escalated_from"))
    return "review" in (fm.get("status"), front(text(f"epics/{slug}.md"))[1].get("status"))

agent = setting("merge", "human") == "agent"
waiting, items = {}, []   # (slug, kind) -> when it entered; (entered, left or None, kind, slug)
for line in open(events, errors="ignore") if os.path.exists(events) else ():
    f = line.rstrip("\n").split("\t")
    t = secs(f[0]) if len(f) == 5 and f[4].startswith("ok") else None
    if t is None:
        continue
    if f[1] in ENTER and not (f[1] == "review" and agent and not costs_money(f[2])):
        waiting.setdefault((f[2], ENTER[f[1]]), t)
    elif f[1] in LEAVE:
        for slug, kind in [k for k in waiting if k[0] == f[2]]:
            items.append((waiting.pop((slug, kind)), t, kind, slug))
items += [(t, None, kind, slug) for (slug, kind), t in waiting.items() if still_waiting(kind, slug)]

# Local midnight after --until, as flow_throughput's cutoff.
stop = min(time.time(), (datetime.datetime.fromisoformat(until) + datetime.timedelta(days=1)).timestamp())
days = {}
for start, end, kind, slug in sorted(items, key=lambda i: i[0]):
    day = datetime.date.fromtimestamp(start).isoformat()
    if since <= day <= until:
        # One still waiting at the cutoff, or after it, counts to the cutoff and is open there.
        open_ = end is None or end > stop
        d = days.setdefault(day, ([], []))
        d[0].append(((stop if open_ else end) - start) / 60)
        if open_:
            d[1].append(f"{kind}: {slug}")

print("day\titems\tmedian_min\tmax_min\topen")
for day, (mins, opens) in sorted(days.items()):
    print("\t".join([day, str(len(mins)), str(round(statistics.median(mins))), str(round(max(mins))), ", ".join(opens)]))
