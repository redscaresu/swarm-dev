# Lead queue, a flow section (flow_report.py gives its globals): how long items wait on the lead, from
# events.tsv's ok lines. An item enters on a held line (held_story), an escalated line or an impossible
# close, or a review (handed over to merge), and leaves on its slug's next finish, reset, reset:held,
# drop, story (built again) or reconcile (finished once every PR merged, or reopened when one closed
# unmerged); a merge line is one PR's, so it does not end the wait. Per local day it entered: items, the median and maximum minutes waited, and
# open, the kind:slug of each item still waiting, which counts up to now. --epic does not narrow it.
# events.tsv does not say who merges, so with merge = agent a review counts too.
import datetime, os, statistics

ENTER = {"held": "held", "escalated": "escalated", "close:impossible": "escalated", "review": "merge"}
LEAVE = {"finish", "reset", "reset:held", "drop", "story", "reconcile"}

waiting, done = {}, []
for line in open(events, errors="ignore") if os.path.exists(events) else ():
    f = line.rstrip("\n").split("\t")
    if len(f) != 5 or not f[4].startswith("ok"):
        continue
    try:
        at = datetime.datetime.fromisoformat(f[0].replace("Z", "+00:00")).astimezone()
    except ValueError:
        continue
    cmd, slug = f[1], f[2]
    if cmd in ENTER:
        waiting.setdefault(slug, (ENTER[cmd], at))
    elif slug in waiting and cmd in LEAVE:
        kind, start = waiting.pop(slug)
        done.append((start, (at - start).total_seconds() / 60, None))

now = datetime.datetime.now().astimezone()
done += [(start, (now - start).total_seconds() / 60, f"{kind}:{slug}") for slug, (kind, start) in waiting.items()]
days = {}
for start, minutes, still in done:
    day = start.date().isoformat()
    if since <= day <= until:
        days.setdefault(day, []).append((minutes, still))

print("day\titems\tmedian_min\tmax_min\topen")
for day, items in sorted(days.items()):
    mins = [m for m, _ in items]
    still = ",".join(sorted(s for _, s in items if s)) or "-"
    print(f"{day}\t{len(items)}\t{statistics.median(mins):.0f}\t{max(mins):.0f}\t{still}")
