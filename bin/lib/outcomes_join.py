import collections, datetime, os, re, subprocess, sys
from report import *
from events_outcome import outcome
meta = {f[0]: f[1:] for f in (l.split("\t") for l in os.environ["SWARM_META"].splitlines()) if len(f) == 6}

NO_PR = ("", "", "", "", "", "", "", "")
RECURRING_MIN_PRS = 3   # the rule of three: a kind fixed on this many distinct PRs recurs
RECURRING_DAYS = 30     # within this many days

def parsed(prs):
    # The (url, state, mergedAt, createdAt, main_merges, checks, commits, closedAt) of each PR in the
    # meta column; a stub may leave out the last six. checks is its head's status rollup entries as
    # start/end/conclusion joined by ";", a time gh does not give empty (start/end in a cached record
    # from before conclusions), commits its commits' committedDate joined by ";".
    return [tuple((p.split(" ") + [""] * 7)[:8]) for p in prs.split(",") if " " in p]

def pr_of(prs, pulls):
    # The parsed PR of a build, or NO_PR: see outcomes_report. pulls is the first python's column: "-"
    # for no log.
    prs = parsed(prs)
    if pulls == "-":
        return prs[0] if len(prs) == 1 else NO_PR
    keyed = {pr_key(p[0]): p for p in prs}
    return next((keyed[pr_key(u)] for u in reversed(pulls.split()) if pr_key(u) in keyed), NO_PR)

def secs(t):
    # A UTC time in epoch seconds; None when it is empty or does not parse.
    try:
        return datetime.datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None

def minutes(start, end):
    # Whole minutes from one UTC time to a later one; empty when either is empty or does not parse, or
    # end comes first (a retry started after the PR it took over was created).
    a, b = secs(start), secs(end)
    return str(round((b - a) / 60)) if None not in (a, b) and b >= a else ""

# The phases of a build's start-to-merge minutes, highest first: where two cover the same minute, the
# higher takes it, and a minute none covers is building.
PRECEDENCE = ("fixing", "ci", "review_wait", "merge_wait")

def fixed_at(t, commits, ends):
    # Where fixing findings told at t ends: the first after it of the PR's next commit (one that merges
    # the base in is no fix, and gh leaves it out), the next check start, review event, tell:findings
    # or the merge (ends).
    return min([x for x in commits if x > t] + [e for e in ends if e > t])

def time_in_state(start, merged, pr, times):
    # The PHASES' minutes from start to merged, as strings that sum to minutes(start, merged); all empty
    # when a time is missing. CI runs over each check's start to end; review wait from the PR's creation
    # to its first review event after it (handed to the merger) or the merge; merge wait from that to the
    # merge; fixing from each tell:findings between the PR's creation and the merge (fixed_at), so a tell
    # on an earlier PR of the slug is not this one's.
    # ponytail: gh gives the latest run of each check on the PR's head alone, so other CI counts as the
    # phase under it; read every head's runs (as ci_health does) if that hides too much.
    s, c, m = secs(start), secs(pr[3]), secs(merged)
    if None in (s, c, m) or m < s:
        return [""] * len(PHASES)
    runs = [tuple(map(secs, r.split("/")[:2])) for r in pr[5].split(";") if r.count("/") in (1, 2)]
    # A run cancelled while queued starts at gh's zero time (year 1): no CI.
    runs = [r for r in runs if None not in r and 0 < r[0] <= r[1]]
    commits = [x for x in map(secs, pr[6].split(";")) if x is not None]
    events = sorted((secs(w), k) for k, _, w in (t.partition("=") for t in times) if secs(w) is not None)
    handed = min((t for t, k in events if k == "review" and t >= c), default=m)
    ends = [a for a, _ in runs] + [t for t, _ in events] + [m]
    spans = {"ci": runs, "review_wait": [(c, handed)], "merge_wait": [(handed, m)],
             "fixing": [(t, fixed_at(t, commits, ends)) for t, k in events if k == "tell:findings" and c <= t < m]}
    # Each piece between two cuts goes to one phase; rounding where it starts and ends (from start)
    # keeps the sum the rounded whole.
    cuts = sorted({s, m} | {min(max(x, s), m) for v in spans.values() for span in v for x in span})
    got = collections.Counter()
    for a, b in zip(cuts, cuts[1:]):
        mid = (a + b) / 2
        phase = next((p for p in PRECEDENCE if any(x <= mid < y for x, y in spans[p])), "building")
        got[phase] += round((b - s) / 60) - round((a - s) / 60)
    return [str(got[p]) for p in PHASES]

# A head is green once every check run on it concluded one of these.
GREEN = ("SUCCESS", "NEUTRAL", "SKIPPED")

def run_end(run):
    # When a status rollup entry (start, end, conclusion) ended: its completedAt, else its startedAt,
    # which for a commit status is the time it was set (gh exports its createdAt as startedAt, and it
    # has no completedAt); None with neither, or gh's year-1 zero time.
    t = secs(run[1])
    if t is None:
        t = secs(run[0])
    return t if t is not None and t > 0 else None

def green_at(checks):
    # When the PR's head went green (secs): the end (run_end) of the last entry in its status rollup,
    # once every entry concluded GREEN; None with no entry, or one that failed, is still running or has
    # no conclusion (a cached record from before conclusions were read is unknown, never green), or a
    # green one with no end: the data does not say when the head went green, so no other entry's end
    # stands in. gh gives the latest head's entries alone, so an earlier head that failed is no green,
    # and a later one counts from its own.
    runs = [r.split("/") for r in checks.split(";") if r]
    if not runs or any(len(r) != 3 or r[2] not in GREEN for r in runs):
        return None
    ends = [run_end(r) for r in runs]
    return max(ends) if None not in ends else None

def green_to_review(slug, pr):
    # green_to_review_min: whole minutes from the later of the PR's green (green_at) and its creation
    # (a head can go green before its PR opens, and no review of it starts before then; a round before
    # then is an earlier PR's of the slug) to the first review round its slug started at or after
    # that, and before the PR closed (round_starts); empty with no green or no such round.
    green, created, closed = green_at(pr[5]), secs(pr[3]), secs(pr[7])
    if green is None:
        return ""
    since = green if created is None else max(green, created)
    start = min((t for t in round_starts[slug] if t >= since and (closed is None or t <= closed)), default=None)
    return "" if start is None else str(round((start - since) / 60))

# outcomes_rows' columns: up to pulls, then the ones printed as they are (started, the four tokens_*,
# close_cause and the six escalation steps), then the subagent ones (cost, cost by model, tokens), then
# its slug's review and tell:findings times (kind=time, space-separated), read here and not printed.
AS_IS = 13                 # where started, the first printed as it is, sits
AS_IS_N, SUBAGENT_N = 12, 3
SUBAGENT = AS_IS + AS_IS_N
TIMES = SUBAGENT + SUBAGENT_N
rows = []
for line in os.environ["SWARM_ROWS"].splitlines():
    f = line.split("\t")
    if len(f) != TIMES + 1:
        # A damaged log (a tab in a cwd) or the two files out of step: skip the row, never the report.
        print(f"outcomes: skipped a row of {len(f)} columns, not {TIMES + 1}: {line[:80]!r}", file=sys.stderr)
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
def open_at(slug, t):
    # The URLs of the slug's PRs open at t: created by then, and not closed (or merged) by then.
    return [p[0] for p in parsed(meta.get(slug, ("", "", ""))[2])
            if secs(p[3]) is not None and secs(p[3]) <= t and not (secs(p[7]) is not None and secs(p[7]) <= t)]

# A review (`swarm.sh review <slug or epic> <PRs>`) logs the PRs it names in its outcome, ok (<PRs>): its
# time goes to the builds on each PR it names. One logged before reviews named their PRs (a bare ok)
# goes to its slug's PR when the slug had exactly one open then, and to none otherwise.
named_reviews = collections.defaultdict(list)
for line in open(sys.argv[3], errors="ignore") if os.path.exists(sys.argv[3]) else ():
    e = line.rstrip("\n").split("\t")
    if len(e) == 5:
        e[4] = outcome(e)   # without its key=value tail (a review's round= and verdict=)
    t = secs(e[0]) if len(e) == 5 and e[1] == "review" and (e[4] == "ok" or e[4].startswith("ok (")) else None
    if t is None:
        continue
    urls = re.findall(r"https://github\.com/[^/\s]+/[^/\s]+/pull/\d+", e[4])
    if e[4] == "ok":
        urls = open_at(e[2], t)
        urls = urls if len(urls) == 1 else []
    for u in urls:
        named_reviews[pr_key(u)].append(f"review={e[0]}")

def board_log(*args):
    # git log over the board's stories on its default branch, where merges land (HEAD when there is no
    # origin/HEAD, as dash_base_ref), so a story branch's own commits are no merge; "" when git fails.
    # --first-parent dates a commit by the merge, and --no-renames keeps a story deleted beside a
    # similar new one a deletion.
    board = sys.argv[2]
    has_origin = subprocess.run(["git", "-C", board, "rev-parse", "-q", "--verify", "origin/HEAD"], capture_output=True)
    got = subprocess.run(["git", "-C", board, "log", "origin/HEAD" if has_origin.returncode == 0 else "HEAD",
                          "--first-parent", "--diff-merges=first-parent", "--no-renames", *args, "--", "stories/"],
                         capture_output=True, text=True)
    return got.stdout if got.returncode == 0 else ""

def board_commits(*args):
    # The board's commits that add or delete a story file, newest first, as (the format's text, [the
    # story paths]). Each commit prints as "\x01<format>\0" and then its paths (from the repo root, any
    # characters), each ending "\0".
    commits = [c.split("\0") for c in board_log("-z", "--name-only", *args).split("\x01")[1:]]
    return [(c[0], [p.lstrip("\n") for p in c[1:] if p.strip("\n")]) for c in commits]

# held: the minutes a story's first build waited ready under the conductor run it started in: from the
# later of the run's start and the story's ready time to the build's start. The story was ready at its
# last ok unblock event or board commit that set its `status: ready` (a story added ready, or readied
# by hand) before the build, unless a board commit set it `status: blocked` after that; with none,
# held is unknown (empty). A conductor of its epic (the backlog conductor, `conduct --backlog`, for a
# story with no epic) runs from an ok `conduct` event until the next one, an ok close of its agent,
# or its report, whichever comes first: the report's file time while it is there
# (.swarm/conduct-<epic>.report.md), or the time the next conduct logged for it (a report event) as
# it removed the file. A build that started after its run ended, or with no run, held 0. Retiring a
# conductor is the next conduct's first step, and tidy closes only retired panes, so neither ends a
# run sooner. An epic's conductor is conduct-<epic>; the backlog's is the per-project
# SWARM_BACKLOG_CONDUCTOR (conductor_name), or conduct-backlog in older logs.
# ponytail: a retry's own wait in ready is not counted; time it from the close before it if retries wait long.
ready_at, blocked_at = collections.defaultdict(list), collections.defaultdict(list)
conducting, closed, reported = collections.defaultdict(list), collections.defaultdict(list), collections.defaultdict(list)
# round_starts: each slug's review round starts: its review-agent lines, a review agent's start,
# whose outcome main logs as a bare ok (today the conductor starts an agent so for every round, and
# the agent waits for green itself, so a start can come before the head is green), and review-agent
# --next's review-agent:next lines, a round run in the same session, the only ones main gives
# `ok (round <n>)`. A review-agent line that carried `(round <n>)` would count the same, though none
# does today. green_to_review reads only those at or after the head's green, so a start before it
# never counts.
round_starts = collections.defaultdict(list)
# Explicit prefixes and no colour, whatever the user's diff.noprefix, diff.dstPrefix or color.ui.
for commit in board_log("-p", "-U0", "--no-color", "--src-prefix=a/", "--dst-prefix=b/", "-G^status:", "--format=%x01%ct").split("\x01")[1:]:
    lines, path = commit.split("\n"), ""
    for l in lines[1:]:
        if l.startswith("+++ "):
            path = l[len("+++ b/"):] if l.startswith("+++ b/") else ""
        elif path and (m := re.fullmatch(r"\+status:\s*(ready|blocked)\s*", l)):
            (ready_at if m.group(1) == "ready" else blocked_at)[os.path.splitext(os.path.basename(path))[0]].append(float(lines[0]))
for line in open(sys.argv[3], errors="ignore") if os.path.exists(sys.argv[3]) else ():
    e = line.rstrip("\n").split("\t")
    if len(e) == 5:
        e[4] = outcome(e)   # without its key=value tail (a review-agent line's round=)
    t = secs(e[0]) if len(e) == 5 and (e[4] == "ok" or e[4].startswith("ok (")) else None
    if t is None:
        continue
    if e[1] == "unblock":
        ready_at[e[2]].append(t)
    elif e[1] == "conduct":
        conducting[e[2]].append(t)
    elif e[1] == "report" and secs(e[4][len("ok ("):-1]) is not None:
        reported["--backlog" if e[2] == "backlog" else e[2]].append(secs(e[4][len("ok ("):-1]))
    elif e[1].split(":")[0] == "close":
        closed[agent_name(e[2])].append(t)
    elif e[1] in ("review-agent", "review-agent:next") and (e[4] == "ok" or re.fullmatch(r"ok \(round \d+\)", e[4])):
        round_starts[e[2]].append(t)

def run_ends(epic):
    # The times a conductor run of the epic ("" for the backlog's) could have ended: its agent's ok
    # closes and its reports' times.
    names = [agent_name("conduct-" + epic)] if epic else ["conduct-backlog", os.environ.get("SWARM_BACKLOG_CONDUCTOR", "")]
    report = os.path.join(os.path.dirname(sys.argv[3]), f"conduct-{epic or 'backlog'}.report.md")
    return ([t for n in names if n for t in closed[n]] + reported[epic or "--backlog"]
            + ([os.path.getmtime(report)] if os.path.exists(report) else []))

def ready_time(slug, s):
    # The story's ready time by s (secs), as held reads it; None when it has none.
    ready = max((t for t in ready_at[slug] if t <= s), default=None)
    return None if ready is None or any(ready < t <= s for t in blocked_at[slug]) else ready

def held(slug, epic, start):
    # Whole minutes, as a string; empty when start or the story's ready time is unknown.
    s = secs(start)
    ready = ready_time(slug, s) if s is not None else None
    if ready is None:
        return ""
    run = max((t for t in conducting[epic or "--backlog"] if t <= s), default=None)
    if run is None or any(run < t <= s for t in run_ends(epic)):
        return "0"
    return str(round((s - max(ready, run)) / 60))

# ready_wait: the minutes from a story's ready time (as held reads it, unclipped by any conductor run)
# to its first build's start; 0 when no ready signal came before the start (it was readied only after),
# empty when start or the ready time is unknown (a ready, then a block, before the start, as held).
def ready_wait(slug, start):
    s = secs(start)
    if s is None:
        return ""
    if not any(t <= s for t in ready_at[slug]):
        return "0" if ready_at[slug] else ""
    ready = ready_time(slug, s)
    return "" if ready is None else str(round((s - ready) / 60))

# Rework, computed here alone (flow's reviewers and model_fit read this column): rework_of over the merged
# PRs of these builds from rework_from(SWARM_REWORK_SINCE) on (flow's --since, else outcomes' own), with
# every PR of their repos merged from the first one's day to REWORK_DAYS after the last one's as a possible
# fix. gh's merged: dates are UTC, so the end has a day more for a local 7th day that is the next day in
# UTC. A mergedAt that does not parse is left out of the search, and rework_of counts it on stderr. A
# reworked PR counts once, on the latest build on it, as findings do; a 1 is written at once, a 0 only
# once its REWORK_DAYS have passed, as a fix may still come. Rework is unknown, and left empty, for a PR
# merged before the window, for all when gh fails, and for a PR merged before the oldest of a gh list at
# its limit, whose fix the list may have missed.
lo = rework_from(os.environ.get("SWARM_REWORK_SINCE", ""))
judged = {pr_key(r[6]): r[8] for r in rows if r[4] and r[6] and r[7] == "MERGED" and r[8]
          and not (lo and merge_time(r[8]) and local_day(merge_time(r[8])) < lo)}
days = sorted(t.date() for t in map(merge_time, judged.values()) if t)
got = merged_prs([r[6] for r in rows if pr_key(r[6]) in judged], days[0].isoformat(),
                 (days[-1] + datetime.timedelta(days=REWORK_DAYS + 1)).isoformat()) if days else ({}, {})
gh_failed = got is None
if gh_failed:
    print("rework: gh failed, so rework is left empty.", file=sys.stderr)
merged_by, oldest = got or ({}, {})
for k, m in judged.items():
    merged_by.setdefault(k, (m, "", None))
cut = {k for k, m in judged.items() for t in [merge_time(m)]
       if t and oldest.get(k.partition("#")[0]) and t < oldest[k.partition("#")[0]]}
reworked = rework_of(merged_by, finding_rows(sys.argv[1], ("escaped",)), judged)
settled = rework_settled()
last = {pr_key(r[6]): i for i, r in enumerate(rows) if r[6]}

def by(c, outcome):
    return " ".join(f"{who}:{n}" for (o, who), n in sorted(c.items()) if o == outcome)

# Columns are only ever appended, never inserted or reordered: review-yield and flow read them by name,
# and a saved report or a script that cuts by position still lines up with a new one.
print("date\tslug\tkind\trisk\trole\tmodel\teffort\tcost_usd\ttokens\ttells_findings\ttells_nudge\ttells_resume\tcloses\tfindings_fixed\tpr\tpr_state\tattempts"
      "\tstarted\ttokens_input\ttokens_cache_write\ttokens_cache_read\ttokens_output\tclose_cause"
      "\tescalate_at\tdialog_at\tdialog\tescalated_at\treset_at\tdrop_at"
      "\tepic\tmerged_at\tstory_merged\tfindings_declined\tfindings_fixed_by\tfindings_declined_by"
      "\tpr_created_at\tstart_to_pr_min\tpr_to_merge_min\tmain_merges\tsubagent_cost_usd\tsubagent_cost_by_model\tsubagent_tokens"
      "\t" + "\t".join(p + "_min" for p in PHASES) + "\trework\theld_min\tready_wait_min\tgreen_to_review_min")
for i, ((f, kind, risk, story_epic, asked, prs, *the_pr), c) in enumerate(zip(rows, found)):
    pr, state, merged, created, main_merges = the_pr[:5]
    day, slug, role, model, effort, cost, tokens, tf, tn, tr, closes, attempts = f[:12]
    # Unknown (empty) unless gh answered for a story it could read: then true when any PR of its head merged.
    story_merged = ("true" if any(p[1] == "MERGED" for p in parsed(prs)) else "false") if asked else ""
    fixed, declined = (sum(n for (o, _), n in c.items() if o == k) for k in ("fixed", "declined"))
    merged = merged if asked and state == "MERGED" else ""
    # 1 when a later fix reworked its merged PR, 0 when none did once REWORK_DAYS passed; empty on an
    # unmerged PR, an earlier build on it, and where rework is unknown.
    merged_t, k = merge_time(merged), pr_key(pr)
    known = merged_t and last[k] == i and k in judged and k not in cut and not gh_failed
    rework = "1" if known and k in reworked else "0" if known and local_day(merged_t).isoformat() < settled else ""
    print("\t".join([day, slug, kind, risk, role, model, effort, cost, tokens, tf, tn, tr, closes,
                     str(fixed), pr, state, attempts] + f[AS_IS:SUBAGENT]
                     + [story_epic, merged, story_merged, str(declined), by(c, "fixed"), by(c, "declined"),
                        created, minutes(f[AS_IS], created), minutes(created, merged), main_merges] + f[SUBAGENT:TIMES]
                     + time_in_state(f[AS_IS], merged, the_pr, f[TIMES].split() + (named_reviews[pr_key(pr)] if pr else []))
                     + [rework] + ([held(slug, story_epic, f[AS_IS]), ready_wait(slug, f[AS_IS])] if attempts == "1" else ["", ""])
                     + [green_to_review(slug, the_pr)]))

def check_story(kind):
    # The newest story with `checks: <kind>` that a merge deleted from the board (where story_text
    # finds a merged story), as (slug, day it was deleted); None when git has none. Without
    # --pickaxe-all, -G lists only the files whose removed lines name the kind, so a story deleted
    # beside it is never taken for it.
    commits = board_commits("--diff-filter=D", "--format=%x01%cs", "-G", f"^checks: *{kind} *$")
    if not commits or not commits[0][1]:
        return None
    deleted, paths = commits[0]
    return os.path.splitext(os.path.basename(paths[0]))[0], datetime.date.fromisoformat(deleted)

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
