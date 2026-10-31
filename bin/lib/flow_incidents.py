# Incidents, a flow section (flow_report.py gives its globals): events.tsv's incident lines (outcome
# `<kind>: <detail>`) counted per local day and kind, whatever the kind: `swarm.sh intervene`'s lead-hand and
# user-caught among them, whose sum over the last 7 days is dash's interventions light. --epic does not narrow it: an
# incident's target is an agent name, which may be cut short of its slug. Then, after a blank line,
# the agent stops (api-error and auto-denied) per epic and kind: the agent's epic is the one outcomes'
# rows give its story (a builder, or review-<slug>), or for conduct-<epic> its `conduct <epic>` start
# (or its epic in the rows), under its own name or the ones retire_agent renames it to, `-` when none
# does; --epic keeps that epic's rows. Then, each after a blank line and over every epic: the incidents per kind
# and cause (its cause= field, which `swarm.sh intervene` writes; `-` for a line with none); one row per stalled
# incident with its bg, test and sign fields as written (`-` when absent: not measured, never 0); and one line
# for Goal 3's bar: the stalled incidents with any of the three at 1, and the lead-hand and user-caught lines
# with cause=false-stall.
import collections, datetime, os
from events_outcome import fields
from report import agent_name

STOPS = ("api-error", "auto-denied")
STALL_INPUTS = ("bg", "test", "sign")
INTERVENE_KINDS = ("lead-hand", "user-caught")   # bin/swarm.sh's INTERVENE_KINDS

epic_of = {}

def own(name, e):
    # <name>'s agent name and retire_agent's renames of it: cut to 27, then -done; or to 26, then -done2..9.
    n = agent_name(name)
    for x in [n, n[:27] + "-done"] + [f"{n[:26]}-done{i}" for i in range(2, 10)]:
        epic_of[x] = e

for r in rows:
    if r["epic"]:
        for n in (r["slug"], "review-" + r["slug"], "conduct-" + r["epic"]):
            own(n, r["epic"])

counts, stops, causes = collections.Counter(), collections.Counter(), collections.Counter()
stalls, stalled_input_1, false_stall = [], 0, 0
for line in open(events, errors="ignore") if os.path.exists(events) else ():
    f = line.rstrip("\n").split("\t")
    if len(f) == 5 and f[1] == "conduct" and f[4] == "ok" and f[2] != "--backlog":
        own("conduct-" + f[2], f[2])
    if len(f) != 5 or f[1] != "incident":
        continue
    try:
        day = datetime.datetime.fromisoformat(f[0].replace("Z", "+00:00")).astimezone().date().isoformat()
    except ValueError:
        continue
    if since <= day <= until:
        kind = f[4].partition(":")[0].strip()
        counts[(day, kind)] += 1
        if kind in STOPS:
            stops[(epic_of.get(f[2], "-"), kind)] += 1
        kv = fields(f)
        cause = kv.get("cause", "-")
        causes[(kind, cause)] += 1
        if kind == "stalled":
            inputs = [kv.get(k, "-") for k in STALL_INPUTS]
            stalls.append((f[0], f[2], *inputs))
            stalled_input_1 += "1" in inputs
        if kind in INTERVENE_KINDS and cause == "false-stall":
            false_stall += 1

print("day\tkind\tincidents")
for (day, kind), n in sorted(counts.items()):
    print(f"{day}\t{kind}\t{n}")
print("\nepic\tkind\tstops")
for (e, kind), n in sorted(stops.items()):
    if not epic or e == epic:
        print(f"{e}\t{kind}\t{n}")
print("\nkind\tcause\tincidents")
for (kind, cause), n in sorted(causes.items()):
    print(f"{kind}\t{cause}\t{n}")
print("\ntime\tagent\t" + "\t".join(STALL_INPUTS))
for row in stalls:
    print("\t".join(row))
print(f"\nfalse stalls: {stalled_input_1 + false_stall} ({stalled_input_1} stalled with an input at 1, "
      f"{false_stall} lead-hand or user-caught with cause=false-stall)")
