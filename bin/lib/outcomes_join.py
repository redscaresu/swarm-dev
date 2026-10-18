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

# outcomes_rows' columns: up to pulls, then the ones printed as they are (started, the four tokens_*,
# close_cause and the six escalation steps), then the subagent ones (cost, cost by model, tokens) printed last.
AS_IS = 13                 # where started, the first printed as it is, sits
AS_IS_N, SUBAGENT_N = 12, 3
SUBAGENT = AS_IS + AS_IS_N
rows = []
for line in os.environ["SWARM_ROWS"].splitlines():
    f = line.split("\t")
    if len(f) != SUBAGENT + SUBAGENT_N:
        # A damaged log (a tab in a cwd) or the two files out of step: skip the row, never the report.
        print(f"outcomes: skipped a row of {len(f)} columns, not {SUBAGENT + SUBAGENT_N}: {line[:80]!r}", file=sys.stderr)
        continue
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
      "\tpr_created_at\tstart_to_pr_min\tpr_to_merge_min\tmain_merges\tsubagent_cost_usd\tsubagent_cost_by_model\tsubagent_tokens")
for (f, kind, risk, story_epic, asked, prs, pr, state, merged, created, main_merges), c in zip(rows, found):
    day, slug, role, model, effort, cost, tokens, tf, tn, tr, closes, attempts = f[:12]
    # Unknown (empty) unless gh answered for a story it could read: then true when any PR of its head merged.
    story_merged = ("true" if any(p[1] == "MERGED" for p in parsed(prs)) else "false") if asked else ""
    fixed, declined = (sum(n for (o, _), n in c.items() if o == k) for k in ("fixed", "declined"))
    merged = merged if asked and state == "MERGED" else ""
    print("\t".join([day, slug, kind, risk, role, model, effort, cost, tokens, tf, tn, tr, closes,
                     str(fixed), pr, state, attempts] + f[AS_IS:SUBAGENT]
                     + [story_epic, merged, story_merged, str(declined), by(c, "fixed"), by(c, "declined"),
                        created, minutes(f[AS_IS], created), minutes(created, merged), main_merges] + f[SUBAGENT:]))

def check_story(kind):
    # The newest story with `checks: <kind>` that a merge deleted from the board (where story_text
    # finds a merged story), as (slug, day it was deleted); None when git has none. Read on the
    # default branch, where merges land (HEAD when there is no origin/HEAD, as dash_base_ref), so a
    # story branch deleting its own file is no merge. --first-parent dates it by the merge commit, and
    # --no-renames keeps a story deleted beside a similar new one a deletion. Each commit prints as
    # "\x01<day>\0" and then its deleted paths (from the repo root, any characters), each ending "\0".
    # Without --pickaxe-all, -G lists only the files whose removed lines name the kind, so a story
    # deleted beside it is never taken for it.
    board = sys.argv[2]
    has_origin = subprocess.run(["git", "-C", board, "rev-parse", "-q", "--verify", "origin/HEAD"], capture_output=True)
    got = subprocess.run(["git", "-C", board, "log", "origin/HEAD" if has_origin.returncode == 0 else "HEAD",
                          "--first-parent", "--diff-merges=first-parent", "--no-renames", "--diff-filter=D", "-z",
                          "--name-only", "--format=%x01%cs", "-G", f"^checks: *{kind} *$", "--", "stories/"],
                         capture_output=True, text=True)
    commits = got.stdout.split("\x01")[1:] if got.returncode == 0 else []
    if not commits:
        return None
    deleted, path = commits[0].split("\0")[:2]
    return os.path.splitext(os.path.basename(path.lstrip("\n")))[0], datetime.date.fromisoformat(deleted)

TODAY, DAY = datetime.date.today(), datetime.timedelta(days=1)
WINDOW = datetime.timedelta(days=RECURRING_DAYS)

def finding_day(s):
    # A finding's local day, or None when it is malformed, impossible (2026-02-30) or in the future.
    try:
        d = datetime.date.fromisoformat(s) if re.fullmatch(r"\d{4}-\d{2}-\d{2}", s) else None
    except ValueError:
        return None
    return d if d and d <= TODAY else None

# After a blank line, every kind fixed (or escaped) on RECURRING_MIN_PRS or more PRs in the last
# RECURRING_DAYS days (today among them), most PRs first; once its check story merged, its PRs in the
# RECURRING_DAYS before that day and in the RECURRING_DAYS from it, the second as <n>/<days>d while
# fewer days than that have passed. flow and review-yield skip these lines: they are not a row's width.
dated_fixes = [(finding_day(f[0]), f[1], pr_key(f[2])) for f in fixed_rows(sys.argv[1])]
dated_fixes = [f for f in dated_fixes if f[0]]

def prs_between(kind, start, end):
    # The distinct PRs the kind was fixed on from day start up to, not including, day end.
    return len({pr for d, k, pr in dated_fixes if k == kind and start <= d < end})

# One pass over the log for every kind's recent PRs; prs_between is only for the few flagged kinds.
recent_prs = collections.defaultdict(set)
for fix_day, fix_kind, fix_pr in dated_fixes:
    if TODAY + DAY - WINDOW <= fix_day < TODAY + DAY:
        recent_prs[fix_kind].add(fix_pr)
recent = {k: len(v) for k, v in recent_prs.items()}
flagged = sorted((k for k, n in recent.items() if n >= RECURRING_MIN_PRS), key=lambda k: (-recent[k], k))
if flagged:
    print("\nrecurring\tprs_30d\tcheck\tcheck_merged\tbefore_30d\tsince_30d")
for flagged_kind in flagged:
    check_slug, check_day = (re.fullmatch(r"[a-z0-9-]+", flagged_kind) and check_story(flagged_kind)) or ("", None)
    counts = ["", ""]
    if check_day:
        since, covered = str(prs_between(flagged_kind, check_day, check_day + WINDOW)), max(0, (TODAY - check_day).days + 1)
        counts = [str(prs_between(flagged_kind, check_day - WINDOW, check_day)),
                  since if covered >= RECURRING_DAYS else f"{since}/{covered}d"]
    print("\t".join([flagged_kind, str(recent[flagged_kind]), check_slug, check_day.isoformat() if check_day else ""] + counts))
