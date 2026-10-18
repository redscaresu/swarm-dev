# Lead queue, a flow section (flow_report.py gives its globals): how long items wait on the lead, from
# events.tsv's ok lines. An item enters on a held line (held_story), an escalated line or an impossible
# close, or a review (handed over to merge; with merge = agent only a story whose costs: is not none,
# read as costs_value reads it, from the board, its last version in the board's git history or HEAD's,
# and money when none of them has it; never an epic), and leaves on its slug's next finish, reset,
# reset:held, drop or reconcile (finished once every PR merged, or reopened when one closed unmerged); a merge line is one PR's, so it does not
# end the wait. Waits stop at local midnight after --until (or now): an item that left later is open
# there. One with no leaving line is open only while its story or epic is on the board in review, held
# or escalated (read with board-state as fm reads it); any other is dropped, its end unknown. Per local
# day it entered: items, the median and maximum minutes waited, and open, the kind:slug of each item
# open. --epic does not narrow it.
import datetime, functools, os, re, statistics, subprocess, time

ENTER = {"held": "held", "escalated": "escalated", "close:impossible": "escalated", "review": "merge"}
LEAVE = {"finish", "reset", "reset:held", "drop", "reconcile"}

project = os.path.dirname(os.path.dirname(os.path.abspath(events)))
cfg = {}
try:
    for line in open(os.path.join(project, ".claude/swarm/config"), errors="ignore"):
        m = re.fullmatch(r"\s*([a-z_]+)\s*=\s*(.*?)\s*", line.split("#", 1)[0].rstrip("\n"))
        if m:
            cfg[m.group(1)] = m.group(2)
except OSError:
    pass
board = os.path.join(project, os.path.expanduser(cfg.get("board_dir", "docs")))

def front(text):
    return text.split("\n---", 1)[0] if text.startswith("---") else ""

def item(slug):
    # The live board file of a story or epic and its board-state file, or None.
    for d in ("stories", "epics"):
        f = os.path.join(board, d, slug + ".md")
        if os.path.isfile(f):
            return f, os.path.join(project, ".swarm/board-state", d, slug)
    return None

def fm(f, state, key):
    # As board.sh's fm: board-state's value unless the file's own changed from its key@base.
    m = re.search(rf"^{key}: *(.*)$", front(open(f, errors="ignore").read()), re.M)
    own = m.group(1).rstrip("\r") if m else ""
    try:
        s = open(state, errors="ignore").read()
    except OSError:
        return own
    v, base = (re.search(rf"^{k}: *(.*)$", s, re.M) for k in (key, re.escape(key + "@base")))
    return v.group(1) if v and (not base or base.group(1) == own) else own

def still_waiting(slug):
    found = item(slug)
    if not found:
        return False
    status, kind, held, esc = (fm(*found, k) for k in ("status", "kind", "held_for", "escalated_from"))
    return status == "review" or bool(held) or (status == "ready" and kind == "lead" and bool(esc))

def git(*a):
    r = subprocess.run(["git", "-C", board, *a], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None

@functools.lru_cache(maxsize=None)
def story_text(slug):
    # The story's text, or None when neither the board nor its git history has it.
    f = os.path.join(board, "stories", slug + ".md")
    if os.path.isfile(f):
        return open(f, errors="ignore").read()
    c = (git("log", "--diff-filter=D", "-1", "--format=%H", "--", f"./stories/{slug}.md") or "").strip()
    return git("show", f"{c}^:./stories/{slug}.md" if c else f"HEAD:./stories/{slug}.md")

def is_epic(slug):
    f = f"./epics/{slug}.md"
    return os.path.isfile(os.path.join(board, f)) or bool((git("log", "-1", "--format=%H", "--", f) or "").strip())

def costs_money(slug):
    # As board.sh's costs_value and costs_money: a block list's lines joined, lowercased, comments,
    # quotes, brackets, commas, dashes and spaces gone; anything but empty or none is money, and so is a
    # story that cannot be read (fails closed). An epic's costs: is ignored.
    text = story_text(slug)
    if text is None:
        return not is_epic(slug)
    v, on = None, False
    for line in front(text).splitlines():
        if on and re.fullmatch(r"\s*(#.*)?", line):
            continue
        if on and re.match(r"[\s-]", line):
            v += line.split("#", 1)[0]
            continue
        on = False
        if v is None and line.startswith("costs:"):
            v, on = line[6:].split("#", 1)[0], True
    return re.sub(r"[][\s\"',-]", "", v or "").lower() not in ("", "none")

stop = min(time.time(), (datetime.datetime.fromisoformat(until) + datetime.timedelta(days=1)).timestamp())
waiting, done = {}, []
for line in open(events, errors="ignore") if os.path.exists(events) else ():
    f = line.rstrip("\n").split("\t")
    if len(f) != 5 or not f[4].startswith("ok"):
        continue
    try:
        at = datetime.datetime.fromisoformat(f[0].replace("Z", "+00:00")).timestamp()
    except ValueError:
        continue
    cmd, slug = f[1], f[2]
    if cmd in ENTER and slug not in waiting:
        if cmd != "review" or cfg.get("merge") != "agent" or costs_money(slug):
            waiting[slug] = (ENTER[cmd], at)
    elif slug in waiting and cmd in LEAVE:
        kind, start = waiting.pop(slug)
        done.append((start, at, f"{kind}:{slug}"))
done += [(start, None, f"{kind}:{slug}") for slug, (kind, start) in waiting.items() if still_waiting(slug)]

days = {}
for start, end, name in done:
    day = datetime.datetime.fromtimestamp(start).date().isoformat()
    if since <= day <= until:
        days.setdefault(day, []).append(((min(end or stop, stop) - start) / 60, name if not end or end > stop else None))

print("day\titems\tmedian_min\tmax_min\topen")
for day, items in sorted(days.items()):
    mins = [m for m, _ in items]
    still = ",".join(sorted(s for _, s in items if s)) or "-"
    print(f"{day}\t{len(items)}\t{statistics.median(mins):.0f}\t{max(mins):.0f}\t{still}")
