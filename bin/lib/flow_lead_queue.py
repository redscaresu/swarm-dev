# Lead queue, a flow section (flow_report.py gives its globals): how long items waited in the lead's
# queue (lead_queue in lifecycle.sh), one TSV row per local day items entered it. From events.tsv's ok
# lines: a story enters it held on close:paused or close:cleared-on-error, escalated on escalated or
# close:impossible, and awaiting merge on review; it leaves on its next reset, reset:held, drop, merge,
# reconcile or finish. An item still waiting counts up to now and is listed under open as <kind>: <slug>.
# The section ignores --epic.
# ponytail: every review counts, as events.tsv does not say whether merge = agent left it to the user.
import datetime, os, statistics, time
ENTER = {"close:paused": "held", "close:cleared-on-error": "held", "close:impossible": "escalated",
         "escalated": "escalated", "review": "merge"}
LEAVE = {"reset", "reset:held", "drop", "merge", "reconcile", "finish"}

def secs(t):
    try:
        return datetime.datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None

waiting, items = {}, []   # (slug, kind) -> when it entered; (entered, left or None, kind, slug)
for line in open(events, errors="ignore") if os.path.exists(events) else ():
    f = line.rstrip("\n").split("\t")
    t = secs(f[0]) if len(f) == 5 and f[4].startswith("ok") else None
    if t is None:
        continue
    if f[1] in ENTER:
        waiting.setdefault((f[2], ENTER[f[1]]), t)
    elif f[1] in LEAVE:
        for slug, kind in [k for k in waiting if k[0] == f[2]]:
            items.append((waiting.pop((slug, kind)), t, kind, slug))
items += [(t, None, kind, slug) for (slug, kind), t in waiting.items()]

now, days = time.time(), {}
for start, end, kind, slug in sorted(items):
    day = datetime.date.fromtimestamp(start).isoformat()
    if since <= day <= until:
        d = days.setdefault(day, ([], []))
        d[0].append(((end or now) - start) / 60)
        if end is None:
            d[1].append(f"{kind}: {slug}")

print("day\titems\tmedian_min\tmax_min\topen")
for day, (mins, open_) in sorted(days.items()):
    print("\t".join([day, str(len(mins)), str(round(statistics.median(mins))), str(round(max(mins))), ", ".join(open_)]))
