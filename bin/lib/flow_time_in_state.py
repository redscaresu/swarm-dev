# Time in state, a flow section (flow_report.py gives its globals): one TSV row per epic, then `all`;
# with --epic, that epic's row alone. The five phases sum over the outcomes rows whose phase minutes
# are known (a merged PR): each PR counts once, by its build that started first, as a retried PR
# repeats its phases on every build, and in the window when that build is dated in it: never by a
# retry's partial minutes. held sums over each story's first build (attempts 1) dated in the window,
# merged or not. A row gives its PRs, the hours in all six states, and each state as
# <state>:<hours>h/<share of those hours>%, largest first (a tie in outcomes' column order, held last).
from report import PHASES, pr_key
STATES = PHASES + ("held",)

def hours(minutes):
    return f"{minutes / 60:.1f}".removesuffix(".0")

first = {}
for r in rows:
    if r["pr"] and r["building_min"]:
        k = pr_key(r["pr"])
        if k not in first or r["started"] < first[k]["started"]:
            first[k] = r
window = [r for r in first.values() if since <= r["date"] <= until]
waited = [r for r in rows if r.get("held_min") and since <= r["date"] <= until]
groups = {}
for r in window:
    if r["epic"]:
        groups.setdefault(r["epic"], ([], []))[0].append(r)
for r in waited:
    if r["epic"]:
        groups.setdefault(r["epic"], ([], []))[1].append(r)
print("epic\tprs\thours\tlargest_first")
for g, (rs, ws) in [(epic, groups.get(epic, ([], [])))] if epic else sorted(groups.items()) + [("all", (window, waited))]:
    sums = {p: sum(int(r[p + "_min"]) for r in rs) for p in PHASES}
    sums["held"] = sum(int(r["held_min"]) for r in ws)
    whole = sum(sums.values())
    print("\t".join([g, str(len(rs)), hours(whole),
                     " ".join(f"{p}:{hours(sums[p])}h/{100 * sums[p] / whole if whole else 0:.0f}%"
                              for p in sorted(STATES, key=lambda p: -sums[p]))]))
