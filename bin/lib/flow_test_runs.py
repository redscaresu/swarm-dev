# Test runs, a flow section (flow_report.py gives its globals): scripts/test.sh's log, .swarm/test-runs.tsv
# beside events.tsv, its end lines (the ones with an exit status) whose start's local day is in the
# window, less the interrupted ones (a status of 128 or more) and torn ones. Each end line pairs with
# its run's start line (the same start and PID). A run's at_once is the larger of its start's and
# end's other runs, plus itself; its load is its start line's (the end's when the start line is
# missing). Over the full-suite runs (filter all), the baseline: TSV at_once runs median_s p90_s
# median_load, the runs by at_once, 1, 2, 3-4 and 5+, each with its median and p90 (nearest rank)
# seconds and median load (- with no run); then, after a blank line, TSV start seconds branch at_once
# status: the 5 slowest, slowest first. After a blank line, TSV builder_runs median_s p90_s: the
# builders' runs (branch story/*) of every filter, all included and shards not, with their median and
# p90 seconds (- with none). With no log (a project with no scripts/test.sh) it prints nothing; with
# no full run in the window, a line in place of the baseline. --epic does not narrow it.
import datetime, os, statistics

BUCKETS = (("1", 1, 1), ("2", 2, 2), ("3-4", 3, 4), ("5+", 5, float("inf")))
SLOWEST = 5

def num(s):
    try:
        return float(s)
    except ValueError:
        return None

log = os.path.join(os.path.dirname(events), "test-runs.tsv")
# A line with no newline is torn: test.sh ends each line it writes with one.
lines = [l[:-1].split("\t") for l in open(log, errors="ignore") if l.endswith("\n")] if os.path.exists(log) else []
lines = [f for f in lines if len(f) == 11 and f[8].isdigit()]
starts = {(f[0], f[10]): f for f in lines if f[9] == ""}
runs, builders = [], []
for f in lines:
    if not f[2].isdigit() or not f[9].isdigit() or int(f[9]) >= 128 or not f[10].isdigit():
        continue   # a start line, an interrupted run, or a torn one
    try:
        day = datetime.datetime.fromisoformat(f[0].replace("Z", "+00:00")).astimezone().date().isoformat()
    except ValueError:
        continue
    if not since <= day <= until:
        continue
    if f[5].startswith("story/") and " shard " not in f[4]:
        builders.append(int(f[2]))
    if f[4] == "all":
        st = starts.get((f[0], f[10]), f)
        runs.append({"start": f[0], "seconds": int(f[2]), "branch": f[5], "load": num(st[6]),
                     "at_once": max(int(st[8]), int(f[8])) + 1, "status": f[9]})

def median_p90(s):
    """The median and p90 (nearest rank) of sorted seconds s, as text, - with none."""
    return [f"{statistics.median(s):g}" if s else "-", str(s[-(-9 * len(s) // 10) - 1]) if s else "-"]

if lines and not runs:
    print(f"no full test runs logged in the window ({since} to {until})")
elif runs:
    print("at_once\truns\tmedian_s\tp90_s\tmedian_load")
    for name, lo, hi in BUCKETS:
        b = [r for r in runs if lo <= r["at_once"] <= hi]
        loads = [r["load"] for r in b if r["load"] is not None]
        print("\t".join([name, str(len(b))] + median_p90(sorted(r["seconds"] for r in b))
                        + [f"{statistics.median(loads):.2f}" if loads else "-"]))
    print("\nstart\tseconds\tbranch\tat_once\tstatus")
    for r in sorted(runs, key=lambda r: -r["seconds"])[:SLOWEST]:
        print(f"{r['start']}\t{r['seconds']}\t{r['branch']}\t{r['at_once']}\t{r['status']}")
if lines:
    print("\nbuilder_runs\tmedian_s\tp90_s")
    print("\t".join([str(len(builders))] + median_p90(sorted(builders))))
