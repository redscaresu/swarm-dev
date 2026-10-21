# Merges, a flow section (flow_report.py gives its globals): the stories finished per local day, from
# events.tsv: a finish ok line, or reconcile's "ok (finished" once a PR merged, each slug once, on the
# day of its newest such line (a drop or a rescope writes neither). dash's speedometer counts the same
# lines its own way; dash --check compares the two. --epic does not narrow it.
import collections, datetime, os

last = {}
for line in open(events, errors="ignore") if os.path.exists(events) else ():
    f = line.rstrip("\n").split("\t")
    if len(f) != 5 or not ((f[1] == "finish" and f[4] == "ok") or (f[1] == "reconcile" and f[4].startswith("ok (finished"))):
        continue
    try:
        t = datetime.datetime.fromisoformat(f[0].replace("Z", "+00:00")).timestamp()
    except ValueError:
        continue
    last[f[2]] = max(t, last.get(f[2], t))

days = collections.Counter(datetime.date.fromtimestamp(t).isoformat() for t in last.values())
print("day\tfinished")
for day, n in sorted(days.items()):
    if since <= day <= until:
        print(f"{day}\t{n}")
