# Epic totals, a flow section (flow_report.py gives its globals): one TSV row per epic, then `all`, over
# the outcomes rows dated in the window; with --epic, that epic's row alone. cost_usd and start_to_pr_min
# sum its builds; pr_to_merge_min and main_merged count each PR once (by pr_key), as a retried PR repeats
# them on every build. main_merged_share is the share of its merged PRs whose main_merges is above 0, out
# of those gh could read, so an open or abandoned PR does not count; it is set beside leaner-faster-swarm's
# baseline, which counted merged story PRs.
from report import pr_key
BASELINE = "55%"

def num(x):
    try:
        return float(x)
    except ValueError:
        return None

def totals(rs):
    cost = sum(num(r["cost_usd"]) or 0 for r in rs)
    start = sum(num(r["start_to_pr_min"]) or 0 for r in rs)
    prs = {pr_key(r["pr"]): r for r in rs if r["pr"]}.values()
    merge = sum(num(r["pr_to_merge_min"]) or 0 for r in prs)
    known = [num(r["main_merges"]) for r in prs
             if (r["pr_state"] == "MERGED" or r["merged_at"]) and num(r["main_merges"]) is not None]
    merged = sum(1 for n in known if n > 0)
    share = f"{100 * merged / len(known):.0f}%" if known else ""
    return [str(len(rs)), f"{cost:.2f}", f"{start:.0f}", f"{merge:.0f}", str(len(known)), str(merged), share]

window = [r for r in rows if since <= r["date"] <= until]
groups = {}
for r in window:
    if r["epic"]:
        groups.setdefault(r["epic"], []).append(r)
print("epic\tbuilds\tcost_usd\tstart_to_pr_min\tpr_to_merge_min\tmerged_prs\tmain_merged\tmain_merged_share")
for g, rs in [(epic, groups.get(epic, []))] if epic else sorted(groups.items()) + [("all", window)]:
    print("\t".join([g] + totals(rs)))
print(f"\nmain_merged_share against leaner-faster-swarm's baseline: {BASELINE} of story PRs needed main merged in.")
