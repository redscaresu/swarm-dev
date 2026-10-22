# CI health, a flow section (flow_report.py gives its globals): one TSV row for the project over the
# PRs of the outcomes rows dated in the window (with --epic, that epic's; without --since, the 30
# days up to --until or today, as each PR costs 3 or more gh calls). gh's REST API (not GraphQL, whose
# hourly limit a swarm spends first) gives each PR's branch and commits and its branch's workflow
# runs; a run counts when its head is one of the PR's commits. Then the test files that failed in a
# rerun that went green, in those PRs' repos (flaky_tests). Then per repo, the CI time of these PRs and of the window's length before it (ci_time); dash_slow.py reads it too.
import datetime, functools, os, re, statistics
from report import *
RED = {"failure", "timed_out", "startup_failure"}   # never cancelled or skipped
GH_SECONDS = 10
LOG_SECONDS = 60   # gh run view --log-failed downloads the attempt's whole log
FAILED = re.compile(r"\b(?:FAIL|TIMEOUT) (tests/[^\s:]+)")   # scripts/test.sh's line for a test file that failed
RUN_FIELDS = "databaseId,headSha,workflowName,event,status,conclusion,attempt,createdAt,startedAt,updatedAt"
GITHUB = re.compile(r"https://github\.com/([^/]+/[^/]+)/pull/(\d+)")
WHY = {}   # a PR gh could not read: the error that dropped it
gh = functools.partial(gh, seconds=GH_SECONDS)

def drop(url, why=None):
    # None, noting why gh could not read url's PR: why, or the gh call that just failed.
    WHY[url] = CONTROL.sub("", why or ERROR[0])
    return None

def secs(t):
    # A time in epoch seconds; None when it does not parse.
    try:
        return datetime.datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp()
    except (ValueError, AttributeError):
        return None

@functools.lru_cache(maxsize=None)
def head_runs(url):
    # The PR's newest commit (the last of its commits) and its completed runs on its own commits, or
    # None when gh cannot read them or answers without a branch or commits; read once per PR.
    repo, n = GITHUB.match(url).groups()
    pr = gh("api", f"repos/{repo}/pulls/{n}")
    branch = (pr.get("head") or {}).get("ref") if isinstance(pr, dict) else None
    if not isinstance(branch, str) or not branch:
        return drop(url, None if pr is None else f"gh api repos/{repo}/pulls/{n}: no branch")
    pages = gh("api", "--paginate", "--slurp", f"repos/{repo}/pulls/{n}/commits?per_page=100")
    shas = [c.get("sha") for page in pages if isinstance(page, list) for c in page if isinstance(c, dict)] if isinstance(pages, list) else []
    if not shas:
        return drop(url, None if pages is None else f"gh api repos/{repo}/pulls/{n}/commits: no commits")
    runs = gh("run", "list", "-R", repo, "--branch", branch, "--limit", "200", "--json", RUN_FIELDS)
    if not isinstance(runs, list):
        return drop(url)
    return shas[-1], [r for r in runs if isinstance(r, dict) and r.get("headSha") in shas and r.get("status") == "completed"]

@functools.lru_cache(maxsize=None)
def pr_runs(url):
    # head_runs, with their conclusions (attempts), or None when gh cannot read them; read once per PR.
    got = head_runs(url)
    if got is None:
        return None
    runs = attempts(GITHUB.match(url).group(1), got[1])
    return drop(url) if runs is None else runs

def reruns(repo, day):
    # The repo's runs created on day whose last attempt, not their first, went green, with their
    # conclusions (attempts); None when gh cannot read them. gh lists at most 1000 runs a query.
    runs = gh("run", "list", "-R", repo, "--created", day, "--status", "success", "--limit", "1000", "--json", RUN_FIELDS)
    if not isinstance(runs, list):
        return None
    return attempts(repo, [r for r in runs if isinstance(r, dict) and r.get("conclusion") == "success"
                           and isinstance(r.get("attempt"), int) and r["attempt"] > 1])

def attempts(repo, runs):
    # The runs, each with its conclusions first attempt first (gh run list gives a rerun's last
    # attempt alone, so the earlier ones come from /attempts/<n>), or None when gh cannot read them.
    for r in runs:
        earlier = []
        for n in range(1, r["attempt"]):
            earlier.append(gh("api", f"repos/{repo}/actions/runs/{r['databaseId']}/attempts/{n}"))
            if earlier[-1] is None:
                return None
        r["conclusions"] = [a.get("conclusion") if isinstance(a, dict) else None for a in earlier] + [r["conclusion"]]
    return runs

def tally(r, seen):
    # A run's red attempts and flakes; seen holds the (sha, workflow, event) keys red until a green one.
    key, red, flakes = (r["headSha"], r["workflowName"], r["event"]), 0, 0
    for c in r["conclusions"]:
        if c == "success" and key in seen:
            seen.discard(key)
            flakes += 1
        elif c in RED:
            seen.add(key)
            red += 1
    return red, flakes

def red_then_green(r):
    # The numbers of a run's red attempts before its last green one: none for a run never green.
    last = max((n for n, c in enumerate(r["conclusions"], 1) if c == "success"), default=0)
    return [n for n, c in enumerate(r["conclusions"][:last], 1) if c in RED]

def failed_files(repo, r, n):
    # Attempt n of run r's URL, and the test files its failed steps' log names (FAILED), or None when gh
    # cannot read the log.
    log = gh("run", "view", str(r["databaseId"]), "-R", repo, "--attempt", str(n), "--log-failed", seconds=LOG_SECONDS, parse=str)
    return (f"https://github.com/{repo}/actions/runs/{r['databaseId']}/attempts/{n}",
            None if log is None else {CONTROL.sub("", f) for f in FAILED.findall(log)})

def flaky_tests(urls, days):
    # Per test file on a FAIL or TIMEOUT line of the red attempts before a run's last green one (gh run
    # view --log-failed), worst first: its runs (each counted once per file), the day its last one was
    # created and that one's attempt; and a line each for a day's runs or a log gh could not read. The
    # runs are the reruns created on the days, in the repos of the PRs health read (main's and a lead
    # PR's too), or with --epic its PRs' own runs.
    files, unread, runs = {}, [], []   # files: test file -> [(createdAt, attempt URL)], one per run
    read = [u for u in urls if pr_runs(u) is not None]
    if epic:
        runs = [(GITHUB.match(u).group(1), pr_runs(u)) for u in read]
    for repo in [] if epic else sorted({GITHUB.match(u).group(1).lower() for u in read}):
        for day in days:
            got = reruns(repo, day)
            unread.extend([f"flaky tests: left out the runs of {repo} created {day}: {CONTROL.sub('', ERROR[0])}"] if got is None else [])
            runs.append((repo, got or []))
    for (repo, _), r in {(repo, r["databaseId"]): r for repo, rs in runs for r in rs}.items():   # a run once, whichever PRs share it
        named = set()
        for n in red_then_green(r):
            link, got = failed_files(repo, r, n)
            unread.extend([f"flaky tests: could not read {link}: {CONTROL.sub('', ERROR[0])}"] if got is None else [])
            for name in (got or set()) - named:
                files.setdefault(name, []).append((r["createdAt"], link))
                named.add(name)
    rows = sorted(files.items(), key=lambda f: (len(f[1]), max(f[1])), reverse=True)
    return [[name, str(len(seen)), max(seen)[0][:10], max(seen)[1]] for name, seen in rows], unread

def health(urls):
    # The row over the PRs gh could read, and the PRs it could not, which are left out.
    heads, red, flakes, read, unread = {}, 0, 0, 0, []   # heads: sha -> the (created, updated) of its runs whose times parse
    for url in urls:
        runs = pr_runs(url)
        if runs is None:
            unread.append(url)
            continue
        read += 1
        seen = set()   # (sha, workflow, event) after a red attempt, until a green one
        for r in sorted(runs, key=lambda r: r["createdAt"]):
            span = (secs(r["createdAt"]), secs(r["updatedAt"]))
            heads.setdefault(r["headSha"], []).extend([span] if None not in span else [])
            r_red, r_flakes = tally(r, seen)
            red, flakes = red + r_red, flakes + r_flakes
    mins = [(max(e for _, e in t) - min(s for s, _ in t)) / 60 for t in heads.values() if t]
    return [str(read), str(len(heads)), f"{statistics.median(mins):.1f}" if mins else "",
            f"{red / read:.2f}" if read else "", str(flakes)], unread

def ci_time(url):
    # The PR's CI time: the longest run on its newest head, its last commit (not the head of the run
    # created last: a rerun of an old head can come after it), timed over its last attempt, startedAt
    # to updatedAt, and that run's slowest job (one jobs listing of that same attempt, all its pages,
    # less the jobs a rerun of failed jobs carried over from an earlier one), as (minutes, job, job
    # minutes); () when it has no timed run or job, None when gh fails or answers without them.
    got = head_runs(url)
    if got is None:
        return None
    newest, runs = got
    timed = [(secs(r.get("startedAt")), secs(r.get("updatedAt")), r) for r in runs if r["headSha"] == newest]
    timed = [t for t in timed if None not in t[:2]]
    if not timed:
        return ()
    start, end, run = max(timed, key=lambda t: t[1] - t[0])
    got = gh("api", "--paginate", "--slurp", f"repos/{GITHUB.match(url).group(1)}/actions/runs/{run['databaseId']}/attempts/{run['attempt']}/jobs?per_page=100")
    if not isinstance(got, list):
        return drop(url)
    jobs = [(secs(j.get("completed_at")) - secs(j.get("started_at")), CONTROL.sub("", j["name"]))
            for page in got if isinstance(page, dict) for j in page.get("jobs") or []
            if isinstance(j, dict) and isinstance(j.get("name"), str) and j.get("run_attempt") == run["attempt"]
            and secs(j.get("started_at")) is not None and secs(j.get("completed_at")) is not None]
    if not jobs:
        return ()
    job_secs, job = max(jobs)
    return (end - start) / 60, job, job_secs / 60

def summary(times):
    # ci_time over PRs: the median minutes, and of the jobs that were a PR's slowest, the one with the
    # highest median minutes (by its own runs) and that median; None for no PRs.
    if not times:
        return None
    by_job = {}
    for _, job, mins in times:
        by_job.setdefault(job, []).append(mins)
    job, mins = max(((j, statistics.median(m)) for j, m in by_job.items()), key=lambda jm: jm[1])
    return statistics.median(t[0] for t in times), job, mins

def trend(now, before):
    # One TSV row per repo (lowercased, as pr_key has it) of the PRs in now or before: its PRs, median CI minutes, slowest job and its
    # median minutes in now, the same in before, and the change in CI minutes; and how many PRs of
    # each window gh could not read, which are left out, in a list each.
    times, unread = {}, ([], [])
    for i, urls in enumerate((now, before)):
        for url in urls:
            t = ci_time(url)
            unread[i].extend([url] if t is None else [])
            if t:
                times.setdefault(GITHUB.match(url).group(1).lower(), ([], []))[i].append(t)
    rows = []
    for repo, (a, b) in sorted(times.items()):
        sa, sb = summary(a), summary(b)
        cells = lambda s: [f"{s[0]:.1f}", s[1], f"{s[2]:.1f}"] if s else ["", "", ""]
        rows.append([repo, str(len(a))] + cells(sa) + [str(len(b))] + cells(sb)
                    + [f"{sa[0] - sb[0]:+.1f}" if sa and sb else ""])
    return rows, unread

def windowed(start, end):
    # The github.com PRs of the outcomes rows dated start to end (with --epic, its own). One off
    # github.com (Enterprise, or written by hand) is left out: gh run list needs its repo.
    return sorted({pr_key(r["pr"]): r["pr"] for r in rows if GITHUB.match(r["pr"]) and start <= r["date"] <= end
                   and (not epic or r["epic"] == epic)}.values())

if __name__ == "__main__":
    end = datetime.date.today() if until == "9999-12-30" else datetime.date.fromisoformat(until)
    if since == "0000-00-00":
        since = (end - datetime.timedelta(days=30)).isoformat()
        print(f"PRs from the last 30 days, {since} on; --since sets the start")
    now = windowed(since, until)
    # SWARM_CI_TIME_ONLY (dash's ci line, which reads the ci time table alone) skips this row and its
    # per-attempt calls.
    if not os.environ.get("SWARM_CI_TIME_ONLY"):
        got, unread = health(now)
        print("prs\theads\tci_min_median\tred_runs_per_pr\tflakes")
        print("\t".join(got))
        if unread:
            print(f"ci health: gh could not read {len(unread)} of {len(now)} PRs, left out")
            print("\n".join(f"ci health: left out {url}: {WHY[url]}" for url in unread))
        first, last = datetime.date.fromisoformat(since), min(end, datetime.date.today())
        days = [(first + datetime.timedelta(days=i)).isoformat() for i in range((last - first).days + 1)]
        tests, unread = flaky_tests(now, days)   # not rows: windowed reads the outcomes rows below
        if tests or unread:
            print()
            print("test_file\tflaky_runs\tlast_seen\texample_run")
            print("\n".join(["\t".join(t) for t in tests] + unread))
    # The window before: as many days, up to the day before since; a PR built in both windows counts
    # in this one alone, by its latest build. A PR gh cannot read is left out here, so the PRs that
    # answered still count (dash's ci line reads this table).
    start, day = datetime.date.fromisoformat(since), datetime.timedelta(days=1)
    keys = {pr_key(u) for u in now}
    before = [u for u in windowed((start - (end - start) - day).isoformat(), (start - day).isoformat()) if pr_key(u) not in keys]
    rows, unread = trend(now, before)
    print()
    print("repo\tprs\tci_min_median\tslowest_job\tslowest_job_min_median\tprev_prs\tprev_ci_min_median"
          "\tprev_slowest_job\tprev_slowest_job_min_median\tci_min_change")
    print("\n".join("\t".join(r) for r in rows))
    if unread[0] or unread[1]:
        print(f"ci time: gh could not read {len(unread[0]) + len(unread[1])} of {len(now) + len(before)} PRs ({len(unread[0])} of {len(now)} in this window), left out")
        print("\n".join(f"ci time: left out {url}: {WHY[url]}" for url in unread[0] + unread[1]))
