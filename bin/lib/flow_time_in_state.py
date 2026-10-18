# Time in state, a flow section (flow_report.py gives its globals): one TSV row per epic, then `all`,
# over the outcomes rows dated in the window whose phase minutes are known (a merged PR); with --epic,
# that epic's row alone. Each PR counts once, by its build that started first (the most minutes), as a
# retried PR repeats its phases on every build. A row gives its PRs, their start-to-merge minutes and
# the five phases' sums as <phase>:<minutes>, largest first (a tie in outcomes' column order).
from report import PHASES, pr_key

def total(r):
    return sum(int(r[p + "_min"]) for p in PHASES)

first = {}
for r in rows:
    if since <= r["date"] <= until and r["pr"] and r["building_min"]:
        k = pr_key(r["pr"])
        if k not in first or total(r) > total(first[k]):
            first[k] = r
groups = {}
for r in first.values():
    if r["epic"]:
        groups.setdefault(r["epic"], []).append(r)
print("epic\tprs\tstart_to_merge_min\tlargest_first")
for g, rs in [(epic, groups.get(epic, []))] if epic else sorted(groups.items()) + [("all", list(first.values()))]:
    sums = {p: sum(int(r[p + "_min"]) for r in rs) for p in PHASES}
    print("\t".join([g, str(len(rs)), str(sum(sums.values())),
                     " ".join(f"{p}:{sums[p]}" for p in sorted(PHASES, key=lambda p: -sums[p]))]))
