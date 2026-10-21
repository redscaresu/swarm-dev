# Incidents, a flow section (flow_report.py gives its globals): events.tsv's incident lines (outcome
# `<kind>: <detail>`) counted per local day and kind, whatever the kind: `swarm.sh intervene`'s lead-hand and
# user-caught among them, whose sum over the last 7 days is dash's interventions light. --epic does not narrow it: an
# incident's target is an agent name, which may be cut short of its slug.
import collections, datetime, os

counts = collections.Counter()
for line in open(events, errors="ignore") if os.path.exists(events) else ():
    f = line.rstrip("\n").split("\t")
    if len(f) != 5 or f[1] != "incident":
        continue
    try:
        day = datetime.datetime.fromisoformat(f[0].replace("Z", "+00:00")).astimezone().date().isoformat()
    except ValueError:
        continue
    if since <= day <= until:
        counts[(day, f[4].partition(":")[0].strip())] += 1

print("day\tkind\tincidents")
for (day, kind), n in sorted(counts.items()):
    print(f"{day}\t{kind}\t{n}")
