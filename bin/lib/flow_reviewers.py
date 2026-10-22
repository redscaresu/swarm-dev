# Reviewers, a flow section (flow_report.py gives its globals): findings raised, fixed and declined per
# reviewer and kind, and the reworked PRs among those it raised them on, then the split critic's yield
# per split, review rounds per PR, and with --epic the PRs counted.
import collections, os, re, subprocess
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
# A split is dated by its first row, the critic's as the board PR opens (an escaped gap's when the
# critic found nothing), and every escaped gap counts against it whatever its own day.
splits = {}
for day, kind, pr, _, outcome, reviewer in finding_rows(findings, ("fixed", "declined", "escaped")):
    if reviewer == "split-critic" or kind == "split-gap" and outcome == "escaped":
        s = splits.setdefault(pr_key(pr), {"pr": pr, "day": day, "n": collections.Counter()})
        s["day"] = min(s["day"], day)
        s["n"][outcome] += 1

def split_epic(pr):
    # The epic a split's board PR split: board-pr names its branch board/scope-<epic>. "" when gh cannot say.
    repo, _, n = pr_key(pr).partition("#")
    try:
        got = subprocess.run(["gh", "pr", "view", n, "-R", repo, "--json", "headRefName", "--jq", ".headRefName"],
                             capture_output=True, text=True, timeout=GH_SECONDS)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    head = got.stdout.strip() if got.returncode == 0 else ""
    return head[len("board/scope-"):] if head.startswith("board/scope-") else ""

def parent_of(slug):
    # A child epic's parent: from its front matter on the board, or "" once it is gone.
    try:
        text = open(os.path.join(os.environ.get("SWARM_BOARD", ""), "epics", slug + ".md"), errors="ignore").read()
    except OSError:
        return ""
    m = re.search(r"(?m)^parent:\s*[\"']?([a-z0-9-]+)", text.split("\n---", 1)[0] if text.startswith("---") else "")
    return m.group(1) if m else ""

# With --epic, the splits of that epic or of its parent.
wanted = {epic, parent_of(epic)} - {""} if epic else set()
shown = [s for s in splits.values() if since <= s["day"] <= until and (not epic or split_epic(s["pr"]) in wanted)]
if shown:
    print("\nsplit\tcritic_fixed\tcritic_declined\tescaped_split_gaps")
    for s in sorted(shown, key=lambda s: s["pr"]):
        print(f"{s['pr']}\t{s['n']['fixed']}\t{s['n']['declined']}\t{s['n']['escaped']}")
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
