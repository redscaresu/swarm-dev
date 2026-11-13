"""recurring — the kinds of finding fixed (or escaped) on many distinct PRs in a window of days, and the
check story that merged for each. outcomes_join prints its recurring block from here. It makes no gh
call: it reads findings.tsv and the board's git log alone."""
import collections, datetime, os, re, subprocess
from report import fixed_rows, pr_key

def board_log(board, *args):
    # git log over the board's stories on its default branch, where merges land (HEAD when there is no
    # origin/HEAD, as dash_base_ref), so a story branch's own commits are no merge; "" when git fails.
    # --first-parent dates a commit by the merge, and --no-renames keeps a story deleted beside a
    # similar new one a deletion.
    has_origin = subprocess.run(["git", "-C", board, "rev-parse", "-q", "--verify", "origin/HEAD"], capture_output=True)
    got = subprocess.run(["git", "-C", board, "log", "origin/HEAD" if has_origin.returncode == 0 else "HEAD",
                          "--first-parent", "--diff-merges=first-parent", "--no-renames", *args, "--", "stories/"],
                         capture_output=True, text=True)
    return got.stdout if got.returncode == 0 else ""

def board_commits(board, *args):
    # The board's commits that add or delete a story file, newest first, as (the format's text, [the
    # story paths]). Each commit prints as "\x01<format>\0" and then its paths (from the repo root, any
    # characters), each ending "\0".
    commits = [c.split("\0") for c in board_log(board, "-z", "--name-only", *args).split("\x01")[1:]]
    return [(c[0], [p.lstrip("\n") for p in c[1:] if p.strip("\n")]) for c in commits]

def check_story(board, kind):
    # The newest story with `checks: <kind>` that a merge deleted from the board (where story_text
    # finds a merged story), as (slug, day it was deleted); None when git has none, or the kind is not
    # a slug (it goes into git's -G pattern). Without --pickaxe-all, -G lists only the files whose
    # removed lines name the kind, so a story deleted beside it is never taken for it.
    if not re.fullmatch(r"[a-z0-9-]+", kind):
        return None
    commits = board_commits(board, "--diff-filter=D", "--format=%x01%cs", "-G", f"^checks: *{kind} *$")
    if not commits or not commits[0][1]:
        return None
    deleted, paths = commits[0]
    return os.path.splitext(os.path.basename(paths[0]))[0], datetime.date.fromisoformat(deleted)

def finding_day(s, today):
    # A finding's local day, or None when it is malformed, impossible (2026-02-30) or after today.
    try:
        d = datetime.date.fromisoformat(s) if re.fullmatch(r"\d{4}-\d{2}-\d{2}", s) else None
    except ValueError:
        return None
    return d if d and d <= today else None

def dated_fixes(findings, today):
    # findings.tsv's fixed and escaped rows as (day, kind, PR key), leaving out a row whose day
    # finding_day refuses.
    fixes = [(finding_day(f[0], today), f[1], pr_key(f[2])) for f in fixed_rows(findings)]
    return [f for f in fixes if f[0]]

def prs_between(fixes, kind, since, until):
    # The distinct PRs the kind was fixed on from day since up to, not including, day until.
    return len({pr for d, k, pr in fixes if k == kind and since <= d < until})

def recurring(fixes, since, until, min_prs):
    # Every kind fixed on min_prs or more distinct PRs from day since up to, not including, day until,
    # as (kind, PRs), most PRs first. One pass over the fixes; prs_between is for one kind.
    prs = collections.defaultdict(set)
    for day, kind, pr in fixes:
        if since <= day < until:
            prs[kind].add(pr)
    return sorted(((k, len(v)) for k, v in prs.items() if len(v) >= min_prs), key=lambda kn: (-kn[1], kn[0]))

def block(fixes, board, today, days, min_prs):
    # outcomes' recurring block, as lines: a header, then every kind fixed on min_prs or more PRs in the
    # last <days> days (today among them), most PRs first; once its check story merged, its PRs in the
    # <days> before that day and in the <days> from it, the second as <n>/<covered>d while fewer days
    # than that have passed. [] when no kind recurs.
    window = datetime.timedelta(days=days)
    until = today + datetime.timedelta(days=1)
    kinds = recurring(fixes, until - window, until, min_prs)
    lines = ["\t".join(["recurring", f"prs_{days}d", "check", "check_merged", f"before_{days}d", f"since_{days}d"])] if kinds else []
    for kind, n in kinds:
        check_slug, check_day = check_story(board, kind) or ("", None)
        counts = ["", ""]
        if check_day:
            since, covered = str(prs_between(fixes, kind, check_day, check_day + window)), max(0, (today - check_day).days + 1)
            counts = [str(prs_between(fixes, kind, check_day - window, check_day)),
                      since if covered >= days else f"{since}/{covered}d"]
        lines.append("\t".join([kind, str(n), check_slug, check_day.isoformat() if check_day else ""] + counts))
    return lines
