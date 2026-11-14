# retro's recurring section: the finding kinds fixed (or escaped) on MIN_PRS or more distinct PRs from
# the window's day to today, after folding (recurring.py's FOLD: docs-misstate-code counts as docs),
# that have no check. A folded kind has a check when check_story finds a merged `checks:` story for any
# name in its group. One line per kind, most PRs first: `<kind>: <n> PRs, as <the names seen>`. With
# none, one line saying so. Run by retro_report.py, with day, findings and board among its globals.
import collections, datetime
from recurring import check_story, dated_fixes, fold, fold_group, recurring

MIN_PRS = 3

since = datetime.date.fromisoformat(day)  # noqa: F821 # retro_report.py's context
today = datetime.date.today()
fixes = [f for f in dated_fixes(findings, today) if f[0] >= since]  # noqa: F821
names = collections.defaultdict(set)
for _, kind, _ in fixes:
    names[fold(kind)].add(kind)
folded = [(d, fold(k), pr) for d, k, pr in fixes]
rows = [(k, n) for k, n in recurring(folded, since, today + datetime.timedelta(days=1), MIN_PRS)
        if not any(check_story(board, name) for name in fold_group(k))]  # noqa: F821
if not rows:
    print(f"no recurring kind without a check: none was fixed on {MIN_PRS} or more PRs since {day} and lacks a merged checks: story")  # noqa: F821
for kind, n in rows:
    print(f"{kind}: {n} PRs, as {', '.join(sorted(names[kind]))}")
