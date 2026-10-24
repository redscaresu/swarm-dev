# Test runs, a flow section (flow_report.py gives its globals): scripts/test.sh's log, .swarm/test-runs.tsv
# beside events.tsv, its end lines (the ones with an exit status) of full-suite runs (TESTS all) whose
# start's local day is in the window. TSV at_once runs median_s p90_s median_load: the runs by how
# many test.sh runs went at once as each started (itself and the others), 1, 2, 3-4 and 5+, each
# with its median and p90 (nearest rank) seconds and median 1-minute load at the start (- with no run);
# then, after a blank line, TSV start seconds branch at_once status: the 5 slowest, slowest first. A
# line instead when there is no log or no full run in the window. --epic does not narrow it.
import datetime, os, statistics

BUCKETS = (("1", 1, 1), ("2", 2, 2), ("3-4", 3, 4), ("5+", 5, float("inf")))
SLOWEST = 5

def num(s):
    try:
        return float(s)
    except ValueError:
        return None

runs = []
log = os.path.join(os.path.dirname(events), "test-runs.tsv")
for line in open(log, errors="ignore") if os.path.exists(log) else ():
    f = line.rstrip("\n").split("\t")
    if len(f) != 10 or f[9] == "" or f[4] != "all" or not f[2].isdigit() or not f[8].isdigit():
        continue   # a start line, a filtered run, or a torn one
    try:
        day = datetime.datetime.fromisoformat(f[0].replace("Z", "+00:00")).astimezone().date().isoformat()
    except ValueError:
        continue
    if since <= day <= until:
        runs.append({"start": f[0], "seconds": int(f[2]), "branch": f[5], "load": num(f[6]),
                     "at_once": int(f[8]) + 1, "status": f[9]})

if not os.path.exists(log):
    print(f"no test runs logged: no {log} yet (scripts/test.sh writes it on each run)")
elif not runs:
    print(f"no full test runs logged in the window ({since} to {until})")
else:
    print("at_once\truns\tmedian_s\tp90_s\tmedian_load")
    for name, lo, hi in BUCKETS:
        b = [r for r in runs if lo <= r["at_once"] <= hi]
        s = sorted(r["seconds"] for r in b)
        loads = [r["load"] for r in b if r["load"] is not None]
        print("\t".join([name, str(len(b)), f"{statistics.median(s):g}" if s else "-",
                         str(s[-(-9 * len(s) // 10) - 1]) if s else "-",
                         f"{statistics.median(loads):.2f}" if loads else "-"]))
    print("\nstart\tseconds\tbranch\tat_once\tstatus")
    for r in sorted(runs, key=lambda r: -r["seconds"])[:SLOWEST]:
        print(f"{r['start']}\t{r['seconds']}\t{r['branch']}\t{r['at_once']}\t{r['status']}")
