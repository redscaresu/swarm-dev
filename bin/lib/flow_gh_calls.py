# gh calls, a flow section (flow_report.py gives its globals): bin/gh-shim's log, .swarm/gh-calls.tsv
# beside events.tsv, its lines whose local day is in the window, counted per local hour and budget
# (graphql or rest, 5000 calls an hour each), once by role and once by subcommand. A caller's role is
# its agents.tsv one (the last line naming it); swarm.sh's own calls (`swarm.sh <command>`) and a
# caller agents.tsv does not name stay as they are. Each block lists every hour's `all` row and its
# rows, most calls first, with their share of the 5000. --epic does not narrow it.
import collections, datetime, os

BUDGET = 5000

role_of = {}
for line in open(agents, errors="ignore") if os.path.exists(agents) else ():
    f = line.rstrip("\n").split("\t")
    if len(f) >= 3:
        role_of[f[2]] = f[1]

by = {"role": collections.Counter(), "subcommand": collections.Counter()}
log = os.path.join(os.path.dirname(events), "gh-calls.tsv")
for line in open(log, errors="ignore") if os.path.exists(log) else ():
    f = line.rstrip("\n").split("\t")
    if len(f) != 5:
        continue
    try:
        t = datetime.datetime.fromisoformat(f[0].replace("Z", "+00:00")).astimezone()
    except ValueError:
        continue
    if not since <= t.date().isoformat() <= until:
        continue
    hour = t.strftime("%Y-%m-%d %H:00")
    for key, name in (("role", role_of.get(f[1], f[1])), ("subcommand", f[2])):
        by[key][(hour, f[3], "all")] += 1
        by[key][(hour, f[3], name)] += 1

for i, (key, counts) in enumerate(by.items()):
    print(("\n" if i else "") + f"hour\tapi\t{key}\tcalls\tshare")
    for (hour, api, name), n in sorted(counts.items(), key=lambda kv: (-kv[1], kv[0][:2], kv[0][2] != "all", kv[0][2])):
        print(f"{hour}\t{api}\t{name}\t{n}\t{100 * n / BUDGET:.1f}%")
