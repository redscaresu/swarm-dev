# Time in state, a flow section (flow_report.py gives its globals): one TSV row per epic, then `all`;
# with --epic, that epic's row alone. The five phases sum over the outcomes rows whose phase minutes
# are known (a merged PR): each PR counts once, by its build that started first, as a retried PR
# repeats its phases on every build, and in the window when that build is dated in it: never by a
# retry's partial minutes. held is over the same PRs: each of their stories' held_min (on its earliest
# build, as a step-up rung keeps attempts 1 and its own held_min) once, so the six states share one population. A row gives its PRs, the hours in
# all six states, and each state as <state>:<hours>h/<share of those hours>%, largest first (a tie in
# outcomes' column order, held last). Then ready_wait's median and p90 (nearest rank) in minutes, over
# the stories whose first build (the slug's earliest started, as a step-up rung keeps attempts 1 and its
# own ready_wait_min) is dated in the window and has a ready_wait_min, merged or not (empty with none);
# an epic with those alone still gets a row. Then green_to_review's median and p90 (nearest rank) in
# minutes, over the row's merged PRs (the ones the phases count) that have a green_to_review_min
# (empty with none).
import statistics
from report import PHASES, pr_key
STATES = PHASES + ("held",)

def hours(minutes):
    return f"{minutes / 60:.1f}".removesuffix(".0")

def median_p90(mins):
    s = sorted(mins)
    return [f"{statistics.median(s):g}", str(s[-(-9 * len(s) // 10) - 1])] if s else ["", ""]

first = {}
for r in rows:
    if r["pr"] and r["building_min"]:
        k = pr_key(r["pr"])
        if k not in first or r["started"] < first[k]["started"]:
            first[k] = r
window = [r for r in first.values() if since <= r["date"] <= until]
earliest = {}
for r in rows:
    if r["started"] and (r["slug"] not in earliest or r["started"] < earliest[r["slug"]]["started"]):
        earliest[r["slug"]] = r
held = {s: int(r["held_min"]) for s, r in earliest.items() if r.get("held_min")}
waits = [r for r in earliest.values() if r.get("ready_wait_min") and since <= r["date"] <= until]
groups = {r["epic"]: [] for r in waits if r["epic"]}
for r in window:
    if r["epic"]:
        groups.setdefault(r["epic"], []).append(r)
print("epic\tprs\thours\tlargest_first\tready_wait_median\tready_wait_p90\tgreen_to_review_median\tgreen_to_review_p90")
for g, rs in [(epic, groups.get(epic, []))] if epic else sorted(groups.items()) + [("all", window)]:
    # `rs is window` on the all row alone, so an epic named all keeps its own waits.
    wait = median_p90(int(r["ready_wait_min"]) for r in waits if rs is window or r["epic"] == g)
    sums = {p: sum(int(r[p + "_min"]) for r in rs) for p in PHASES}
    sums["held"] = sum(held.get(slug, 0) for slug in {r["slug"] for r in rs})
    whole = sum(sums.values())
    print("\t".join([g, str(len(rs)), hours(whole),
                     " ".join(f"{p}:{hours(sums[p])}h/{100 * sums[p] / whole if whole else 0:.0f}%"
                              for p in sorted(STATES, key=lambda p: -sums[p]))] + wait
                    + median_p90(int(r["green_to_review_min"]) for r in rs if r.get("green_to_review_min"))))
