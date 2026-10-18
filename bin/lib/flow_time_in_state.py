# Time in state, a flow section (flow_report.py gives its globals): one TSV row per epic, then `all`,
# over the outcomes rows whose phase minutes are known (a merged PR); with --epic, that epic's row
# alone. Each PR counts once, by its build that started first, as a retried PR repeats its phases on
# every build, and in the window when that build is dated in it: never by a retry's partial minutes. A
# row gives its PRs, their start-to-merge minutes and the five phases' sums as <phase>:<minutes>,
# largest first (a tie in outcomes' column order).
from report import PHASES, pr_key

first = {}
for r in rows:
    if r["pr"] and r["building_min"]:
        k = pr_key(r["pr"])
        if k not in first or r["started"] < first[k]["started"]:
            first[k] = r
window = [r for r in first.values() if since <= r["date"] <= until]
groups = {}
for r in window:
    if r["epic"]:
        groups.setdefault(r["epic"], []).append(r)
print("epic\tprs\tstart_to_merge_min\tlargest_first")
for g, rs in [(epic, groups.get(epic, []))] if epic else sorted(groups.items()) + [("all", window)]:
    sums = {p: sum(int(r[p + "_min"]) for r in rs) for p in PHASES}
    print("\t".join([g, str(len(rs)), str(sum(sums.values())),
                     " ".join(f"{p}:{sums[p]}" for p in sorted(PHASES, key=lambda p: -sums[p]))]))
