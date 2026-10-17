import collections, datetime, os, re, subprocess, sys
from report import *
meta = {f[0]: f[1:] for f in (l.split("\t") for l in os.environ["SWARM_META"].splitlines()) if len(f) == 6}

NO_PR = ("", "", "", "", "")
RECURRING_MIN_PRS = 3   # the rule of three: a kind fixed on this many distinct PRs recurs
RECURRING_DAYS = 30     # within this many days

def parsed(prs):
    # The (url, state, mergedAt, createdAt, main_merges) of each PR in the meta column; a stub may
    # leave out the last three.
    return [tuple((p.split(" ") + [""] * 4)[:5]) for p in prs.split(",") if " " in p]

def pr_of(prs, pulls):
    # The parsed PR of a build, or NO_PR: see outcomes_report. pulls is the first python's column: "-"
    # for no log.
    prs = parsed(prs)
    if pulls == "-":
        return prs[0] if len(prs) == 1 else NO_PR
    keyed = {pr_key(p[0]): p for p in prs}
    return next((keyed[pr_key(u)] for u in reversed(pulls.split()) if pr_key(u) in keyed), NO_PR)

def minutes(start, end):
    # Whole minutes from one UTC time to a later one; empty when either is empty or does not parse, or
    # end comes first (a retry started after the PR it took over was created).
    try:
        t = lambda s: datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
        d = t(end) - t(start)
    except ValueError:
        return ""
    return str(round(d / 60)) if d >= 0 else ""

rows = []
for line in os.environ["SWARM_ROWS"].splitlines():
    f = line.split("\t")
    kind, risk, prs, story_epic, asked = meta.get(f[1], ("", "", "", "", ""))
    rows.append((f, kind, risk, story_epic, asked, prs) + tuple(pr_of(prs, f[12])))
# Each finding goes to the latest build on its PR that started on or before the finding (both are
# local dates), so a PR two builds share counts each finding once.
found = [collections.Counter() for _ in rows]
for day, _, pr, _, outcome, reviewer in finding_rows(sys.argv[1]):
    on = [i for i, r in enumerate(rows) if r[6] and pr_key(r[6]) == pr_key(pr) and r[0][0] <= day]
    if on:
        found[on[-1]][(outcome, reviewer)] += 1

def by(c, outcome):
    return " ".join(f"{who}:{n}" for (o, who), n in sorted(c.items()) if o == outcome)

# Columns are only ever appended, never inserted or reordered: review-yield and flow read them by name,
# and a saved report or a script that cuts by position still lines up with a new one.
print("date\tslug\tkind\trisk\trole\tmodel\teffort\tcost_usd\ttokens\ttells_findings\ttells_nudge\ttells_resume\tcloses\tfindings_fixed\tpr\tpr_state\tattempts"
      "\tstarted\ttokens_input\ttokens_cache_write\ttokens_cache_read\ttokens_output\tclose_cause"
      "\tescalate_at\tdialog_at\tdialog\tescalated_at\treset_at\tdrop_at"
      "\tepic\tmerged_at\tstory_merged\tfindings_declined\tfindings_fixed_by\tfindings_declined_by"
      "\tpr_created_at\tstart_to_pr_min\tpr_to_merge_min\tmain_merges")
for (f, kind, risk, story_epic, asked, prs, pr, state, merged, created, main_merges), c in zip(rows, found):
    day, slug, role, model, effort, cost, tokens, tf, tn, tr, closes, attempts = f[:12]
    # Unknown (empty) unless gh answered for a story it could read: then true when any PR of its head merged.
    story_merged = ("true" if any(p[1] == "MERGED" for p in parsed(prs)) else "false") if asked else ""
    fixed, declined = (sum(n for (o, _), n in c.items() if o == k) for k in ("fixed", "declined"))
    merged = merged if asked and state == "MERGED" else ""
    print("\t".join([day, slug, kind, risk, role, model, effort, cost, tokens, tf, tn, tr, closes,
                     str(fixed), pr, state, attempts] + f[13:]
                     + [story_epic, merged, story_merged, str(declined), by(c, "fixed"), by(c, "declined"),
                        created, minutes(f[13], created), minutes(created, merged), main_merges]))

def check_story(kind):
    # The newest story with `checks: <kind>` that a merge deleted from the board (where story_text
    # finds a merged story), as (slug, day it was deleted); None when git has none.
    got = subprocess.run(["git", "-C", sys.argv[2], "log", "--diff-filter=D", "--format=%cs", "--name-only",
                          "-G", f"^checks: *{kind} *$", "--", "stories/"], capture_output=True, text=True)
    lines = got.stdout.split() if got.returncode == 0 else []
    return (os.path.splitext(os.path.basename(lines[1]))[0], lines[0]) if len(lines) > 1 else None

def day(d, days=0):
    return (d + datetime.timedelta(days=days)).isoformat()

# After a blank line, every kind fixed (or escaped) on RECURRING_MIN_PRS or more PRs in the last
# RECURRING_DAYS days, most PRs first; once its check story merged, its PRs in the RECURRING_DAYS
# before that day and in the RECURRING_DAYS from it. flow and review-yield skip these lines: they
# are not a row's width.
fixed = [f for f in fixed_rows(sys.argv[1]) if re.fullmatch(r"\d{4}-\d{2}-\d{2}", f[0])]
def prs(kind, start, end):
    return len({pr_key(pr) for d, k, pr, _ in fixed if k == kind and start <= d < end})
today = datetime.date.today()
recent = {k: prs(k, day(today, -RECURRING_DAYS), day(today, 1)) for k in {f[1] for f in fixed}}
flagged = sorted((k for k, n in recent.items() if n >= RECURRING_MIN_PRS), key=lambda k: (-recent[k], k))
if flagged:
    print("\nrecurring\tprs_30d\tcheck\tcheck_merged\tbefore_30d\tsince_30d")
for kind in flagged:
    check, merged = (re.fullmatch(r"[a-z0-9-]+", kind) and check_story(kind)) or ("", "")
    counts = ["", ""]
    if merged:
        m = datetime.date.fromisoformat(merged)
        counts = [str(prs(kind, day(m, -RECURRING_DAYS), merged)), str(prs(kind, merged, day(m, RECURRING_DAYS)))]
    print("\t".join([kind, str(recent[kind]), check, merged] + counts))
