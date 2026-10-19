# CI health, a flow section (flow_report.py gives its globals): one TSV row for the project over the
# PRs of the outcomes rows dated in the window (with --epic, that epic's; without --since, the 30
# days up to --until or today, as each PR costs 2 or more gh calls). gh gives each PR's commits and
# its branch's workflow runs; a run counts when its head is one of the PR's commits. Then per repo, the
# CI time of these PRs and of the window's length before it (ci_time); dash_slow.py reads it too.
import datetime, functools, json, re, statistics, subprocess
from report import *
RED = {"failure", "timed_out", "startup_failure"}   # never cancelled or skipped
GH_SECONDS = 10
GITHUB = re.compile(r"https://github\.com/([^/]+/[^/]+)/pull/\d+")
CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f]")   # a job name is a PR's (a fork's) to set: no escapes or line breaks

def gh(*args):
    # Its JSON, or None when gh fails, takes over GH_SECONDS or answers something else.
    try:
        got = subprocess.run(["gh", *args], capture_output=True, text=True, timeout=GH_SECONDS)
        return json.loads(got.stdout) if got.returncode == 0 else None
    except (subprocess.TimeoutExpired, ValueError):
        return None

def secs(t):
    # A time in epoch seconds; None when it does not parse.
    try:
        return datetime.datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp()
    except (ValueError, AttributeError):
        return None

@functools.lru_cache(maxsize=None)
def head_runs(url):
    # The PR's completed runs on its own commits, or None when gh cannot read them; read once per PR.
    repo = GITHUB.match(url).group(1)
    pr = gh("pr", "view", url, "--json", "headRefName,commits")
    runs = pr and gh("run", "list", "-R", repo, "--branch", pr["headRefName"], "--limit", "200", "--json",
                     "databaseId,headSha,workflowName,event,status,conclusion,attempt,createdAt,startedAt,updatedAt")
    if runs is None:
        return None
    shas = {c["oid"] for c in pr["commits"]}
    return [r for r in runs if r["headSha"] in shas and r["status"] == "completed"]

def pr_runs(url):
    # head_runs, each with its conclusions first attempt first (gh run list gives a rerun's last
    # attempt alone, so the earlier ones come from /attempts/<n>), or None when gh cannot read them.
    repo, runs = GITHUB.match(url).group(1), head_runs(url)
    if runs is None:
        return None
    for r in runs:
        earlier = [gh("api", f"repos/{repo}/actions/runs/{r['databaseId']}/attempts/{n}") for n in range(1, r["attempt"])]
        if None in earlier:
            return None
        r["conclusions"] = [a["conclusion"] for a in earlier] + [r["conclusion"]]
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

def health(urls):
    heads, red, flakes = {}, 0, 0   # heads: sha -> the (created, updated) of its runs whose times parse
    for url in urls:
        runs = pr_runs(url)
        if runs is None:
            return None
        seen = set()   # (sha, workflow, event) after a red attempt, until a green one
        for r in sorted(runs, key=lambda r: r["createdAt"]):
            span = (secs(r["createdAt"]), secs(r["updatedAt"]))
            heads.setdefault(r["headSha"], []).extend([span] if None not in span else [])
            r_red, r_flakes = tally(r, seen)
            red, flakes = red + r_red, flakes + r_flakes
    mins = [(max(e for _, e in t) - min(s for s, _ in t)) / 60 for t in heads.values() if t]
    return [str(len(urls)), str(len(heads)), f"{statistics.median(mins):.1f}" if mins else "",
            f"{red / len(urls):.2f}" if urls else "", str(flakes)]

def ci_time(url):
    # The PR's CI time: its newest head's longest run (its last attempt, startedAt to updatedAt) and
    # that run's slowest job (one jobs listing of that same attempt, all its pages: a run's own listing
    # keeps the jobs a rerun of failed jobs carried over), as (minutes, job, job minutes); () when it
    # has no timed run or job, None when gh fails.
    runs = head_runs(url)
    if runs is None:
        return None
    timed = [(secs(r["startedAt"]), secs(r["updatedAt"]), r) for r in runs]
    timed = [t for t in timed if None not in t[:2]]
    if not timed:
        return ()
    newest = max(timed, key=lambda t: t[2]["createdAt"])[2]["headSha"]
    start, end, run = max((t for t in timed if t[2]["headSha"] == newest), key=lambda t: t[1] - t[0])
    got = gh("api", "--paginate", "--slurp", f"repos/{GITHUB.match(url).group(1)}/actions/runs/{run['databaseId']}/attempts/{run['attempt']}/jobs?per_page=100")
    if got is None:
        return None
    jobs = [(secs(j.get("completed_at")) - secs(j.get("started_at")), CONTROL.sub("", j["name"])) for page in got for j in page["jobs"]
            if secs(j.get("started_at")) is not None and secs(j.get("completed_at")) is not None]
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
    # One TSV row per repo of the PRs in now or before: its PRs, median CI minutes, slowest job and its
    # median minutes in now, the same in before, and the change in CI minutes; and how many PRs gh
    # could not read, which are left out.
    times, unread = {}, 0
    for i, urls in enumerate((now, before)):
        for url in urls:
            t = ci_time(url)
            unread += t is None
            if t:
                times.setdefault(GITHUB.match(url).group(1), ([], []))[i].append(t)
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
    got = health(now)
    if got is None:
        print("ci health: gh failed")
    else:
        print("prs\theads\tci_min_median\tred_runs_per_pr\tflakes")
        print("\t".join(got))
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
    if unread:
        print(f"ci time: gh could not read {unread} of {len(now) + len(before)} PRs, left out")
