# Reviewers, a flow section (flow_report.py gives its globals): findings raised, fixed and declined per
# reviewer and kind, and the reworked PRs among those it raised them on, then the split critic's yield
# per split, review rounds per PR, the yield of each review round (log-finding --round) and the round
# each story's review stopped in, and with --epic the PRs counted.
import collections, glob, os, re, subprocess
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
# board-pr open records each split's board PR in .swarm/<epic>/split-pr (its day and URL), so a clean
# split shows too, and its epic is known here. A split with no record (its .swarm lost) is dated by its
# first row, and gh names its epic. Every escaped gap counts against its split whatever its own day.
splits = {}
for path in glob.glob(os.path.join(glob.escape(os.path.dirname(os.path.abspath(findings))), "*", "split-pr")):
    try:
        day, url = open(path, errors="ignore").read().split()[:2]
    except (OSError, ValueError):
        continue
    splits[pr_key(url)] = {"pr": url, "day": day, "epic": os.path.basename(os.path.dirname(path)), "n": collections.Counter()}
for day, kind, pr, _, outcome, reviewer in finding_rows(findings, ("fixed", "declined", "escaped")):
    if reviewer == "split-critic" or kind == "split-gap" and outcome == "escaped":
        s = splits.setdefault(pr_key(pr), {"pr": pr, "day": day, "epic": None, "n": collections.Counter()})
        s["day"] = s["day"] if s["epic"] is not None else min(s["day"], day)
        s["n"][outcome] += 1

def split_epic(pr):
    # The epic a split's board PR split: board-pr names its branch board/scope-<epic>. None when gh fails.
    repo, _, n = pr_key(pr).partition("#")
    def read():
        try:
            got = subprocess.run(["gh", "pr", "view", n, "-R", repo, "--json", "headRefName", "--jq", ".headRefName"],
                                 capture_output=True, text=True, timeout=GH_SECONDS)
        except (OSError, subprocess.TimeoutExpired):
            return None
        return None if got.returncode else got.stdout.strip()
    head = gh_cache.cached(repo, f"head/{n}", read, lambda h: isinstance(h, str)) if n else read()   # a PR's branch never changes
    return None if head is None else head[len("board/scope-"):] if head.startswith("board/scope-") else ""

def board_git(*a):
    try:
        r = subprocess.run(["git", "-C", os.environ.get("SWARM_BOARD", ""), *a], capture_output=True, text=True)
    except OSError:
        return None
    return r.stdout if r.returncode == 0 else None

def parent_of(slug):
    # A child epic's parent: from its front matter on the board, or, once it is gone (a child that
    # finished), from its last version in the board's git history; "" when neither has it.
    f = os.path.join(os.environ.get("SWARM_BOARD", ""), "epics", slug + ".md")
    if os.path.isfile(f):
        text = open(f, errors="ignore").read()
    else:
        c = (board_git("log", "--diff-filter=D", "-1", "--format=%H", "--", f"./epics/{slug}.md") or "").strip()
        text = (board_git("show", f"{c}^:./epics/{slug}.md") if c else None) or ""
    m = re.search(r"(?m)^parent:\s*[\"']?([a-z0-9-]+)", text.split("\n---", 1)[0] if text.startswith("---") else "")
    return m.group(1) if m else ""

# With --epic, the splits of that epic or of its parent.
wanted = {epic, parent_of(epic)} - {""} if epic and splits else set()
shown, unknown = [], 0
for s in splits.values():
    if since <= s["day"] <= until and epic:
        s["epic"] = s["epic"] if s["epic"] is not None else split_epic(s["pr"])
        unknown += s["epic"] is None
    if since <= s["day"] <= until and (not epic or s["epic"] in wanted):
        shown.append(s)
if shown:
    print("\nsplit\tcritic_fixed\tcritic_declined\tescaped_split_gaps")
    for s in sorted(shown, key=lambda s: s["pr"]):
        print(f"{s['pr']}\t{s['n']['fixed']}\t{s['n']['declined']}\t{s['n']['escaped']}")
if unknown:
    print(f"\nsplit: gh could not name the epic of {unknown} split board PR(s) with no .swarm/<epic>/split-pr, so --epic may leave splits out.")
rounds = collections.Counter()
for r in rows:
    if since <= r["date"] <= until:
        rounds[pr_key(r["pr"])] += int(r["tells_findings"])
total = sum(rounds.values())
per = f"{round(total / len(rounds), 1):g}" if rounds else "0"
print(f"\nprs\trounds\trounds_per_pr\tmax_rounds\n{len(rounds)}\t{total}\t{per}\t{max(rounds.values(), default=0)}")
# By review round (log-finding --round): per round, each reviewer and then all, the findings fixed,
# declined in all and by reason, and the share fixed. Then per story PR (round 1 on; 0 is a plan or
# board PR) the round its review stopped in, and why: once the PR merged, pass when that round fixed
# nothing, else merged-after-fixes; unmerged before that, as its review may not have stopped. The stop
# is the review after its last round of findings sent to the builder (its tells_findings over every
# build, whatever its date, plus one), since a final pass that finds nothing logs no row; never below
# its last logged round. Printed only once a row in the window has a round; a row logged without one
# is round unknown.
REASONS = ("nit", "out-of-scope", "wrong", "deferred")
# A story PR is listed when the window has a row of it with a round; where it stopped is read from all
# its rows, whatever their date, so the window never moves it.
by_round, per_pr, seen = collections.defaultdict(collections.Counter), collections.defaultdict(collections.Counter), {}
for day, kind, pr, _, outcome, reviewer, reason, n in finding_rows(findings, width=8):
    if epic and pr_key(pr) not in urls:
        continue
    n = int(n) if n.isdigit() else None
    if n:
        per_pr[pr_key(pr)][n] += outcome == "fixed"
    if since <= day <= until:
        for who in (reviewer, None):
            by_round[(n, who)][outcome] += 1
            by_round[(n, who)][reason] += outcome == "declined"
        if n:
            seen.setdefault(pr_key(pr), pr)
if any(n is not None for n, _ in by_round):
    print("\nround\treviewer\tfixed\tdeclined\t" + "\t".join(REASONS) + "\tshare_fixed")
    for n, who in sorted(by_round, key=lambda k: (k[0] is None, k[0] or 0, k[1] is None, k[1] or "")):
        got = by_round[(n, who)]
        raised = got["fixed"] + got["declined"]
        print("\t".join(["unknown" if n is None else str(n), who or "all", str(got["fixed"]), str(got["declined"])]
                        + [str(got[r]) for r in REASONS] + [f"{int(100 * got['fixed'] / raised + 0.5)}%"]))
    slug_of, sent = {pr_key(r["pr"]): r["slug"] for r in rows}, collections.Counter()
    for r in rows:
        sent[pr_key(r["pr"])] += int(r["tells_findings"])
    merged = {pr_key(r["pr"]) for r in rows if r.get("pr_state") == "MERGED" or r.get("merged_at")}
    print("\nstory\tpr\tstopped_round\twhy")
    for k in sorted(seen, key=lambda k: (slug_of.get(k, "-"), k)):
        stop = max(sent[k] + 1, max(per_pr[k]))
        why = "unmerged" if k not in merged else "merged-after-fixes" if per_pr[k][stop] else "pass"
        print(f"{slug_of.get(k, '-')}\t{urls.get(k, seen[k])}\t{stop}\t{why}")
if epic:
    print("\n" + "\n".join(["pr"] + sorted(urls[k] for k in counted | set(rounds))))
if rework_unknown(rows, since):
    print("\nrework: outcomes could not list every merged PR with gh (it failed or hit its limit), so some rework is unknown and counts as none.")
