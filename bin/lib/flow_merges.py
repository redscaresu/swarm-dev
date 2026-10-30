# Merges, a flow section (flow_report.py gives its globals): the stories finished per local day, from
# events.tsv: a finish ok line, or reconcile's "ok (finished" once a PR merged, each slug once, on the
# day of its newest such line (a drop or a rescope writes neither). dash's speedometer counts the same
# lines its own way; dash --check compares the two. --epic does not narrow it.
# Then, after a blank line, the merges held for the user per local day by kind: each merge line whose
# outcome starts "held:", counted by its hold= field (dropped-lines, protected or money, merge_fail's), or
# under unmarked for an older line written before the field (or one naming a kind it does not know). A
# day with no held line has no row.
import collections, datetime, os
from events_outcome import fields, outcome

HOLD_KINDS = ("dropped-lines", "protected", "money")

last = {}
held = collections.defaultdict(collections.Counter)
for line in open(events, errors="ignore") if os.path.exists(events) else ():
    f = line.rstrip("\n").split("\t")
    if len(f) != 5:
        continue
    finished = (f[1] == "finish" and f[4] == "ok") or (f[1] == "reconcile" and f[4].startswith("ok (finished"))
    hold = f[1] == "merge" and outcome(f).startswith("held:")
    if not (finished or hold):
        continue
    try:
        t = datetime.datetime.fromisoformat(f[0].replace("Z", "+00:00")).timestamp()
    except ValueError:
        continue
    if finished:
        last[f[2]] = max(t, last.get(f[2], t))
    else:
        kind = fields(f).get("hold", "")
        held[datetime.date.fromtimestamp(t).isoformat()][kind if kind in HOLD_KINDS else "unmarked"] += 1

days = collections.Counter(datetime.date.fromtimestamp(t).isoformat() for t in last.values())
print("day\tfinished")
for day, n in sorted(days.items()):
    if since <= day <= until:
        print(f"{day}\t{n}")
print()
print("day\tdropped_lines\tprotected\tmoney\tunmarked")
for day, n in sorted(held.items()):
    if since <= day <= until:
        print("\t".join([day] + [str(n[k]) for k in HOLD_KINDS + ("unmarked",)]))
