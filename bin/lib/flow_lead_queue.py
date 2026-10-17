# Lead queue, a flow section (flow_report.py gives its globals): how long items waited in the lead's
# queue (lead_queue in lifecycle.sh), one TSV row per local day items entered it. From events.tsv's ok
# lines: a story enters it held on held (a close that really held it), escalated on escalated or
# close:impossible, and awaiting merge on review (with merge = agent, only a story whose costs: is not
# none); it leaves on its next reset, reset:held, drop, merge, reconcile or finish. An item with no end
# still waits while the board shows it so (held_for:, escalated, or in review) and is listed under open
# as <kind>: <slug>, counted up to now or to local midnight after --until; else it is left out.
# The section ignores --epic.
import datetime, os, re, statistics, subprocess, time
ENTER = {"held": "held", "close:impossible": "escalated", "escalated": "escalated", "review": "merge"}
LEAVE = {"reset", "reset:held", "drop", "merge", "reconcile", "finish"}
project = os.path.dirname(os.path.dirname(os.path.abspath(events)))   # events is <project>/.swarm/events.tsv
try:
    config = open(os.path.join(project, ".claude/swarm/config"), errors="ignore").read()
except OSError:
    config = ""
setting = lambda k, d: (re.findall(rf"^\s*{k}\s*=\s*([^#\s]+)", config, re.M) or [d])[-1]
board = os.path.join(project, setting("board_dir", "docs"))   # an absolute board_dir stays as it is

def secs(t):
    try:
        return datetime.datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None

def front(kind, slug):
    # The item's front matter as a dict, from the board file or, once deleted, its last version in git.
    path = f"{kind}/{slug}.md"
    try:
        text = open(os.path.join(board, path), errors="ignore").read()
    except OSError:
        git = lambda *a: subprocess.run(["git", "-C", board, *a], capture_output=True, text=True).stdout
        c = git("log", "--diff-filter=D", "-1", "--format=%H", "--", path).strip()
        text = git("show", f"{c}^:./{path}") if c else ""
    head = text.split("\n---", 1)[0] if text.startswith("---") else ""
    fm, key = {}, None
    for line in head.splitlines()[1:]:
        line = re.sub(r"\s+#.*", "", line)
        if re.match(r"[A-Za-z_]+:", line):
            key, _, v = line.partition(":")
            fm[key] = v.strip()
        elif key and line.strip():   # a costs: list on the lines after it
            fm[key] += " " + line.strip()
    return fm

def costs_money(slug):
    return front("stories", slug).get("costs", "") not in ("", "none")

def still_waiting(kind, slug):
    fm = front("stories", slug)
    if kind == "held":
        return bool(fm.get("held_for"))
    if kind == "escalated":
        return fm.get("status") == "ready" and fm.get("kind") == "lead" and bool(fm.get("escalated_from"))
    return "review" in (fm.get("status"), front("epics", slug).get("status"))

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
        d = days.setdefault(day, ([], []))
        d[0].append(((end or stop) - start) / 60)
        if end is None:
            d[1].append(f"{kind}: {slug}")

print("day\titems\tmedian_min\tmax_min\topen")
for day, (mins, open_) in sorted(days.items()):
    print("\t".join([day, str(len(mins)), str(round(statistics.median(mins))), str(round(max(mins))), ", ".join(open_)]))
