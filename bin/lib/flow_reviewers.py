# Reviewers, a flow section (flow_report.py gives its globals): findings raised, fixed and declined per
# reviewer and kind, and the reworked PRs among those it raised them on, then the split critic's yield
# per split, review rounds per PR, and with --epic the PRs counted.
import collections
from report import *
rows = [r for r in rows if r["pr"] and (not epic or r["epic"] == epic)]
urls = {pr_key(r["pr"]): r["pr"] for r in reversed(rows)}   # the first URL each PR was written as
# None is the all of a reviewer or kind, apart from a finding whose kind is the word all.
c, counted, on = collections.defaultdict(collections.Counter), set(), collections.defaultdict(set)
for day, kind, pr, _, outcome, reviewer in finding_rows(findings):
    if since <= day <= until and (not epic or pr_key(pr) in urls):
        counted.add(pr_key(pr))
        for key in ((reviewer, kind), (reviewer, None), (None, kind), (None, None)):
            c[key][outcome] += 1
            on[key].add(pr_key(pr))
# outcomes' rework: a PR a later fix reworked. on[] already keeps the window's findings.
reworked = {pr_key(r["pr"]) for r in rows if r.get("rework") == "1"}

def line(who, kind):
    fixed, declined = c[(who, kind)]["fixed"], c[(who, kind)]["declined"]
    raised = fixed + declined
    rate = f"{int(100 * declined / raised + 0.5)}%" if raised else "-"
    return "\t".join(["all" if x is None else x for x in (who, kind)]
                     + [str(raised), str(fixed), str(declined), rate, str(len(on[(who, kind)] & reworked))])

def kinds(who):
    return sorted((k for w, k in list(c) if w == who and k is not None), key=lambda k: (-c[(who, k)]["declined"], k))

print("reviewer\tkind\traised\tfixed\tdeclined\tdecline_rate\trework")
for who in sorted({w for w, _ in c if w is not None}):
    print("\n".join(line(who, k) for k in [None] + kinds(who)))
print("\n".join(line(None, k) for k in kinds(None) + [None]))
# Per split (a large epic's board PR): the split critic's fixed and declined findings beside the
# split-gaps it missed, which a child's plan or a build found later (escaped rows of kind split-gap).
splits = {}
for day, kind, pr, _, outcome, reviewer in finding_rows(findings, ("fixed", "declined", "escaped")):
    if since <= day <= until and (not epic or pr_key(pr) in urls) and (reviewer == "split-critic" or kind == "split-gap" and outcome == "escaped"):
        splits.setdefault(pr_key(pr), [pr, collections.Counter()])[1][outcome] += 1
if splits:
    print("\nsplit\tcritic_fixed\tcritic_declined\tescaped_split_gaps")
    for pr, n in sorted(splits.values(), key=lambda v: v[0]):
        print(f"{pr}\t{n['fixed']}\t{n['declined']}\t{n['escaped']}")
rounds = collections.Counter()
for r in rows:
    if since <= r["date"] <= until:
        rounds[pr_key(r["pr"])] += int(r["tells_findings"])
total = sum(rounds.values())
per = f"{round(total / len(rounds), 1):g}" if rounds else "0"
print(f"\nprs\trounds\trounds_per_pr\tmax_rounds\n{len(rounds)}\t{total}\t{per}\t{max(rounds.values(), default=0)}")
if epic:
    print("\n" + "\n".join(["pr"] + sorted(urls[k] for k in counted | set(rounds))))
if rework_unknown(rows, since):
    print("\nrework: outcomes could not list every merged PR with gh (it failed or hit its limit), so some rework is unknown and counts as none.")
