# CI health, a flow section (flow_report.py gives its globals): one TSV row for the project over the
# PRs of the outcomes rows dated in the window (with --epic, that epic's; without --since, the 30
# days up to --until or today, as each PR costs 3 or more gh calls). gh's REST API (not GraphQL, whose
# hourly limit a swarm spends first) gives each PR's branch and commits and its branch's workflow
# runs; a run counts when its head is one of the PR's commits. Then per repo, the CI time of these PRs and of the window's length before it (ci_time); dash_slow.py reads it too.
# Last, the test files that failed on a head before it went green (flaky_tests).
import datetime, functools, os, re, statistics, subprocess, urllib.parse
from report import *
from gh_cache import Listing, as_of, cached, closed, commits, forget, pull
RED = {"failure", "timed_out", "startup_failure"}   # never cancelled or skipped
GH_SECONDS = 10
FLAKY_CALLS = 100   # flaky_tests' gh invocations at most (listings, earlier attempts, logs); not REST requests: a
                    # listing pages up to 10, a log download is several, and gh() tries a 5xx up to 3 times
LOG_SECONDS = 60   # gh run view --log-failed downloads the attempt's whole log
RELIST_DAYS = 3   # window_runs lists again the runs of the newest cached day and this many before it
RUN_DAYS = 90     # and keeps the runs created in the last this many days
# scripts/test.sh's own lines for a test file that failed (FAIL <file> <n>s, FAIL <file>: its job ended
# without a result, TIMEOUT <file> after <n>s), whole and right after gh run view --log-failed's
# "<job>\t<step>\t<timestamp> " prefix, so a test's own output that quotes, indents or diffs one does not count
FAILED = re.compile(r"^[^\t\n]*\t[^\t\n]*\t\ufeff?\d{4}-\d\d-\d\dT[\d:.]+Z "
                    r"(?:FAIL (tests/\S+?)(?: \d+s|: its job ended without a result)|TIMEOUT (tests/\S+) after \d+s)\s*$", re.M)
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
    pr = pull(repo, n, gh)
    branch = (pr.get("head") or {}).get("ref") if isinstance(pr, dict) else None
    if not isinstance(branch, str) or not branch:
        return drop(url, None if pr is None else f"gh api repos/{repo}/pulls/{n}: no branch")
    pages = commits(repo, n, pr, gh)
    shas = [c.get("sha") for page in pages if isinstance(page, list) for c in page if isinstance(c, dict)] if isinstance(pages, list) else []
    if not shas:
        return drop(url, None if pages is None else f"gh api repos/{repo}/pulls/{n}/commits: no commits")
    # Its runs on its commits, cached once the PR is closed, gh lists some and none of them is still
    # running (none listed may be runs not registered yet, or cut by --limit).
    # ponytail: a rerun of a closed PR's run after that is not seen, nor in window_runs a rerun of a run
    # created over RELIST_DAYS before the newest cached day (a rerun keeps its run's created_at);
    # flow --no-cache reads both.
    mine = lambda runs: [r for r in runs if isinstance(r, dict) and r.get("headSha") in shas]
    runs = cached(repo, f"runs/{as_of(n, pr)}", lambda: gh("run", "list", "-R", repo, "--branch", branch, "--limit", "200", "--json", RUN_FIELDS),
                  lambda runs: closed(pr) and isinstance(runs, list) and mine(runs) != [] and all(r.get("status") == "completed" for r in mine(runs)),
                  mine)
    forget(repo, "runs", n, pr)
    if not isinstance(runs, list):
        return drop(url)
    return shas[-1], [r for r in mine(runs) if r.get("status") == "completed"]

@functools.lru_cache(maxsize=None)
def pr_runs(url):
    # head_runs, with their conclusions (attempts), or None when gh cannot read them; read once per PR.
    got = head_runs(url)
    if got is None:
        return None
    runs = attempts(GITHUB.match(url).group(1), got[1])
    return drop(url) if runs is None else runs

def conclusions(repo, r, read=gh):
    # Run r's conclusions, first attempt first (gh lists a rerun's last attempt alone, so the earlier
    # ones come from /attempts/<n>), or None when gh cannot read one, read through read.
    earlier = []
    for n in range(1, r["attempt"]):   # an earlier attempt has ended, so its conclusion is cached
        earlier.append(cached(repo, f"attempts/{r['databaseId']}-{n}", lambda: read("api", f"repos/{repo}/actions/runs/{r['databaseId']}/attempts/{n}"),
                              lambda a: isinstance(a, dict) and a.get("conclusion") is not None, lambda a: {"conclusion": a["conclusion"]}))
        if earlier[-1] is None:
            return None
    return [a.get("conclusion") if isinstance(a, dict) else None for a in earlier] + [r["conclusion"]]

def attempts(repo, runs):
    # The runs, each with its conclusions, or None when gh cannot read one.
    for r in runs:
        r["conclusions"] = conclusions(repo, r)
        if r["conclusions"] is None:
            return None
    return runs

def tally(r, seen):
    # A run's red attempts and its flakes, each the (run, attempt number) of the red attempts a green
    # one followed; seen holds those per (sha, workflow, event) until a green one.
    key, red, flakes = (r["headSha"], r["workflowName"], r["event"]), 0, []
    for n, c in enumerate(r["conclusions"], 1):
        if c == "success" and key in seen:
            flakes.append(seen.pop(key))
        elif c in RED:
            seen.setdefault(key, []).append((r, n))
            red += 1
    return red, flakes

class Stop(Exception):
    pass   # flaky_tests spent FLAKY_CALLS, or gh's hourly rate limit is spent: why

FLAKY_SPENT = [0]   # flaky_tests' gh invocations so far

def capped(*args, **kw):
    # gh, for flaky_tests: at most FLAKY_CALLS invocations, and none once gh's hourly rate limit is spent
    # (Stop says which, the call that hit the limit included).
    if not LIMIT[0] and FLAKY_SPENT[0] < FLAKY_CALLS:
        FLAKY_SPENT[0] += 1
        got = gh(*args, **kw)
        if not LIMIT[0]:
            return got
    raise Stop(f"gh's rate limit ({CONTROL.sub('', LIMIT[0])})" if LIMIT[0] else f"its cap of {FLAKY_CALLS} gh invocations")

def origin():
    # The project's origin repo on github.com (owner/name, lowercased), in a list; [] for none.
    url = subprocess.run(["git", "-C", os.path.dirname(os.path.dirname(os.path.abspath(agents))), "remote", "get-url", "origin"],
                         capture_output=True, text=True).stdout.strip()
    got = re.match(r"(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)([^/]+/[^/]+?)(?:\.git)?/?$", url)
    return [got.group(1).lower()] if got else []

def window_runs(repo, created, lines):
    # The repo's completed runs created in the window (created, gh's syntax: >=<day> or <day>..<day>),
    # by gh run list's names, with a run's last conclusion, and whether that is all of them; a line in
    # lines when gh cannot list them all, or cannot list them, which returns None. Completed runs are
    # cached (gh_cache's Listing, RUN_DAYS of them), so with nothing cached the window is listed, and
    # after that only from RELIST_DAYS before the newest cached day (a run rerun since then is read
    # again; a rerun keeps its run's created day, so one created before that is not), or from the
    # oldest day with a run still running; the window is served from the cache. A listing cut at
    # GitHub's 1000 (the newest) is listed again up to the oldest day it reached, until whole, or a
    # line says what was left out. Raises Stop.
    start, _, end = created.removeprefix(">=").partition("..")
    have = Listing(repo, "runs", start, cached_run)
    lo = start if have.fresh else have.since(RELIST_DAYS)
    hi, whole, held, finished, last = end, True, [], False, have.state["next"]
    # A run still running holds its day for the next listing; one queued or waiting for over a day (a
    # runner that never came) does not.
    stale = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
    try:
        while not end or lo <= end:   # none to list when the cache holds every day up to end
            ask = created if have.fresh and hi == end else f"{lo}..{hi}" if hi else f">={lo}"
            got = list_runs(repo, ask, lines)
            if got is None:
                return None, False
            got, total = got
            for r in got:   # a run listed again while a rerun of it runs is no longer done
                if r.get("status") != "completed":
                    have.items.pop(str(r.get("id")), None)
            have.items.update({str(r["id"]): dict(databaseId=r["id"], headSha=r.get("head_sha"), workflowName=r.get("name"), event=r.get("event"),
                                                  conclusion=r.get("conclusion"), attempt=r["run_attempt"], createdAt=r["created_at"]) for r in got
                               if r.get("status") == "completed" and isinstance(r.get("id"), int) and isinstance(r.get("run_attempt"), int)})
            held += [r["created_at"][:10] for r in got if r.get("status") != "completed"
                     and not (r.get("status") in ("queued", "waiting", "requested", "pending") and r["created_at"] < stale)]
            if len(got) >= total:
                finished = True
                break
            oldest = min(r["created_at"][:10] for r in got) if got else lo
            if oldest <= lo or (hi and oldest >= hi):   # a day of over 1000 runs, or no way on
                lines.append(f"flaky tests: gh listed {len(got)} of the {total} runs of {repo} created {ask}, the newest; the rest are left out")
                whole, finished = False, True
                break
            hi = oldest
        finished = True
    finally:   # what was listed is kept, a Stop too; a listing left part way (a hole) moves next on by nothing
        served = [r for r in have.items.values() if start <= r["createdAt"][:10] <= (end or "9999-12-31")]
        newest = min(held) if held else max([r["createdAt"][:10] for r in have.items.values()] + [last])
        have.save(newest if finished else min(newest, last), lambda r: r["createdAt"][:10], RUN_DAYS)
    return served, whole

def list_runs(repo, ask, lines):
    # One paginated listing of the runs created ask (gh's syntax): (its runs, how many GitHub has), or
    # None and a line in lines when gh cannot list them. Raises Stop.
    pages = capped("api", "--paginate", "--slurp", f"repos/{repo}/actions/runs?created={urllib.parse.quote(ask)}&per_page=100",
                   seconds=LOG_SECONDS)
    pages = [p for p in pages if isinstance(p, dict)] if isinstance(pages, list) else None
    if pages is None:
        lines.append(f"flaky tests: left out the runs of {repo} created {ask}: {CONTROL.sub('', ERROR[0])}")
        return None
    got = [r for p in pages for r in p.get("workflow_runs") or [] if isinstance(r, dict) and isinstance(r.get("created_at"), str)]
    return got, max([p["total_count"] for p in pages if isinstance(p.get("total_count"), int)] + [len(got)])

def cached_run(r):
    # Whether a cached run has what window_runs gives each run; a cache with one that has not is rebuilt.
    return isinstance(r, dict) and {"headSha", "workflowName", "event", "conclusion"} <= r.keys() and isinstance(r.get("createdAt"), str) \
        and isinstance(r.get("databaseId"), int) and isinstance(r.get("attempt"), int)

def suspects(runs):
    # runs ({(repo, run id): run}) by (repo, sha, workflow, event), each group oldest first; the groups
    # that may hold a flake (a rerun, or a red run beside a green one), newest first.
    groups = {}
    for (repo, _), r in runs.items():
        groups.setdefault((repo, r["headSha"], r["workflowName"], r["event"]), []).append(r)
    maybe = [(key[0], sorted(g, key=lambda r: r["createdAt"])) for key, g in groups.items()
             if any(r["attempt"] > 1 for r in g) or ("success" in {r["conclusion"] for r in g} and RED & {r["conclusion"] for r in g})]
    return sorted(maybe, key=lambda g: g[1][-1]["createdAt"], reverse=True)

def failed_files(repo, r, n):
    # Attempt n of run r's URL, and the test files its failed steps' log names (FAILED), or None when gh
    # cannot read the log. Raises Stop.
    # A red attempt has ended: its FAILED lines are cached ({"fail": lines}), never the whole log, and
    # never an empty answer (a log GitHub has not archived yet), which is read again next time.
    log = cached(repo, f"logs/{r['databaseId']}-{n}", lambda: capped("run", "view", str(r["databaseId"]), "-R", repo, "--attempt", str(n),
                                                                     "--log-failed", seconds=LOG_SECONDS, parse=str),
                 lambda log: isinstance(log, dict) and isinstance(log.get("fail"), str) or isinstance(log, str) and log.strip() != "",
                 lambda log: {"fail": "\n".join(m.group(0).rstrip() for m in FAILED.finditer(log))})
    log = log["fail"] if isinstance(log, dict) else log
    return (f"https://github.com/{repo}/actions/runs/{r['databaseId']}/attempts/{n}",
            None if log is None else {CONTROL.sub("", m.group(1) or m.group(2)) for m in FAILED.finditer(log)})

def group_files(repo, group, lines, out):
    # Adds to out the flaky runs of one suspects group (tally's, as health counts them: a red attempt a
    # green one on the same head, workflow and event followed, in that run or a later one), each as
    # (run, {test file: attempt URL}, [a True per log read]), filled in as each log is read, so a Stop
    # keeps what was read. A run whose attempts gh cannot read is left out, and a line in lines names
    # it, as it does each log gh cannot read. Raises Stop.
    for r in group:
        if "conclusions" not in r:
            r["conclusions"] = conclusions(repo, r, capped)
            lines.extend([f"flaky tests: left out https://github.com/{repo}/actions/runs/{r['databaseId']}: {CONTROL.sub('', ERROR[0])}"]
                         if r["conclusions"] is None else [])
    seen, red = {}, {}   # red: run id -> (run, its red attempts a green one followed)
    for r in [r for r in group if r["conclusions"] is not None]:
        for flake in tally(r, seen)[1]:
            for fr, n in flake:
                red.setdefault(fr["databaseId"], (fr, []))[1].append(n)
    for r, ns in red.values():
        named, read = {}, []
        out.append((r, named, read))
        for n in ns:
            link, got = failed_files(repo, r, n)
            lines.extend([f"flaky tests: could not read {link}: {CONTROL.sub('', ERROR[0])}"] if got is None else [])
            read.extend([True] if got is not None else [])
            named.update({f: link for f in got or () if f not in named})

def flaky_tests(urls, created):
    # Per test file on a FAIL or TIMEOUT line of a flaky run's red attempts (gh run view --log-failed),
    # worst first: its flaky runs (a run once per file), the day the last one was created and its
    # attempt; and lines for what was read and what was not. The runs are those created in the window
    # (created) in the repos of the window's PRs and the project's origin (so main's and the lead's
    # PRs' too), or with --epic its PRs' own runs, a run once; at most FLAKY_CALLS gh invocations,
    # stopping at gh's rate limit with what it read so far.
    lines, runs, groups, flaky, done, unlisted, whole = [], {}, [], [], 0, [], True   # runs: (repo, run id) -> run
    read = [u for u in urls if pr_runs(u) is not None]
    known = {r["databaseId"]: r["conclusions"] for u in read for r in pr_runs(u)}   # what health read already
    try:
        if epic:
            runs = {(GITHUB.match(u).group(1), r["databaseId"]): r for u in read for r in pr_runs(u)}
            whole = len(read) == len(urls)   # a PR gh could not read: its runs unknown
        else:
            unlisted = sorted({GITHUB.match(u).group(1).lower() for u in urls} | set(origin()))   # a PR health could not read too
            while unlisted:
                repo = unlisted[0]
                got, every = window_runs(repo, created, lines)
                whole = whole and every
                runs.update({(repo, r["databaseId"]): r for r in got or []})
                unlisted.pop(0)
            for r in runs.values():
                if len(known.get(r["databaseId"]) or ()) == r["attempt"]:
                    r["conclusions"] = known[r["databaseId"]]
        groups = suspects(runs)
        for repo, group in groups:
            group_files(repo, group, lines, flaky)
            done += 1
    except Stop as why:
        whole, groups = False, groups or suspects(runs)   # a Stop while listing: the groups of the repos listed
        said = [f"the runs of {', '.join(unlisted)} not listed"] if unlisted else []
        said += [f"{sum(len(g) for _, g in groups[done:])} of {sum(len(g) for _, g in groups)} runs that may be flaky not read in full"] if groups or not said else []
        lines.append(f"flaky tests: stopped at {why}: {'; '.join(said)}")
    whole = whole and all(r.get("conclusions") is not None for _, g in groups for r in g)   # no run's attempts left unread
    return flaky_rows(flaky), lines + summary_lines(runs, flaky, whole)

def flaky_rows(flaky):
    # flaky_tests' rows from group_files' flaky runs: per test file, its runs, worst first.
    files = {}   # test file -> [(createdAt, attempt URL)], one per run
    for r, named, _ in flaky:
        for name, link in named.items():
            files.setdefault(name, []).append((r["createdAt"], link))
    rows = sorted(files.items(), key=lambda f: (len(f[1]), max(f[1])), reverse=True)
    return [[name, str(len(seen)), max(seen)[0][:10], max(seen)[1]] for name, seen in rows]

def summary_lines(runs, flaky, whole):
    # A line when none of the runs (each once) was flaky, read whole (no stop, every listing read); and
    # one counting the flaky runs whose logs were read and name no test file.
    logged = [named for _, named, was_read in flaky if was_read]
    unnamed = sum(1 for named in logged if not named)
    return ([f"flaky tests: none in the {len(runs)} runs read"] if whole and not flaky else []) + \
           ([f"flaky tests: {unnamed} of the {len(logged)} flaky runs whose failed logs were read have no FAIL or TIMEOUT tests/<file> line"] if unnamed else [])

def health(urls):
    # The row over the PRs gh could read, and the PRs it could not, which are left out.
    heads, red, flakes, read, unread = {}, 0, 0, 0, []   # heads: sha -> the (created, updated) of its runs whose times parse
    for url in urls:
        runs = pr_runs(url)
        if runs is None:
            unread.append(url)
            continue
        read += 1
        seen = {}   # (sha, workflow, event) -> its red attempts, until a green one
        for r in sorted(runs, key=lambda r: r["createdAt"]):
            span = (secs(r["createdAt"]), secs(r["updatedAt"]))
            heads.setdefault(r["headSha"], []).extend([span] if None not in span else [])
            r_red, r_flakes = tally(r, seen)
            red, flakes = red + r_red, flakes + len(r_flakes)
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
    repo = GITHUB.match(url).group(1)   # a completed run's jobs have ended, so they are cached
    got = cached(repo, f"jobs/{run['databaseId']}-{run['attempt']}",
                 lambda: gh("api", "--paginate", "--slurp", f"repos/{repo}/actions/runs/{run['databaseId']}/attempts/{run['attempt']}/jobs?per_page=100"),
                 lambda got: isinstance(got, list),
                 lambda got: [{"jobs": [{k: j.get(k) for k in ("name", "run_attempt", "started_at", "completed_at")}
                                        for j in page.get("jobs") or [] if isinstance(j, dict)]} for page in got if isinstance(page, dict)])
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
    # The flaky tests last, so their reads (which can spend gh's hourly limit) never starve the ci
    # time table dash's ci line reads. GitHub's created filter reads the window's dates as UTC days.
    if not os.environ.get("SWARM_CI_TIME_ONLY"):
        tests, lines = flaky_tests(now, f">={since}" if until == "9999-12-30" else f"{since}..{until}")
        print()
        print("\n".join((["test_file\tflaky_runs\tlast_seen\texample_run"] + ["\t".join(t) for t in tests] if tests else []) + lines))
