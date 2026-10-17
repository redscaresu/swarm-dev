# Reviewers, a flow section (flow_report.py gives its globals): findings raised, fixed and declined per
# reviewer and kind, then review rounds per PR, and with --epic the PRs counted.
import collections
from report import *
rows = [r for r in rows if r["pr"] and (not epic or r["epic"] == epic)]
urls = {pr_key(r["pr"]): r["pr"] for r in reversed(rows)}   # the first URL each PR was written as
# None is the all of a reviewer or kind, apart from a finding whose kind is the word all.
c, counted = collections.defaultdict(collections.Counter), set()
for day, kind, pr, _, outcome, reviewer in finding_rows(findings):
    if since <= day <= until and (not epic or pr_key(pr) in urls):
        counted.add(pr_key(pr))
        for key in ((reviewer, kind), (reviewer, None), (None, kind), (None, None)):
            c[key][outcome] += 1

def line(who, kind):
    fixed, declined = c[(who, kind)]["fixed"], c[(who, kind)]["declined"]
    raised = fixed + declined
    rate = f"{int(100 * declined / raised + 0.5)}%" if raised else "-"
    return "\t".join(["all" if x is None else x for x in (who, kind)] + [str(raised), str(fixed), str(declined), rate])

def kinds(who):
    return sorted((k for w, k in list(c) if w == who and k is not None), key=lambda k: (-c[(who, k)]["declined"], k))

print("reviewer\tkind\traised\tfixed\tdeclined\tdecline_rate")
for who in sorted({w for w, _ in c if w is not None}):
    print("\n".join(line(who, k) for k in [None] + kinds(who)))
print("\n".join(line(None, k) for k in kinds(None) + [None]))
rounds = collections.Counter()
for r in rows:
    if since <= r["date"] <= until:
        rounds[pr_key(r["pr"])] += int(r["tells_findings"])
total = sum(rounds.values())
per = f"{round(total / len(rounds), 1):g}" if rounds else "0"
print(f"\nprs\trounds\trounds_per_pr\tmax_rounds\n{len(rounds)}\t{total}\t{per}\t{max(rounds.values(), default=0)}")
if epic:
    print("\n" + "\n".join(["pr"] + sorted(urls[k] for k in counted | set(rounds))))
