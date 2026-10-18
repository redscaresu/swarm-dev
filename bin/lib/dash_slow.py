import datetime, json, os, re, signal, subprocess, sys, time
FIELDS = "statusCheckRollup,mergeStateStatus,updatedAt,state"
# The ci line reads two weeks of PRs, 3 gh calls each, so at most every 6 hours: a week's median barely
# moves in that time. ponytail: every PR is read again each time; keep a closed PR's ci_time if the
# calls ever crowd gh's rate limit.
CI_SECONDS = 6 * 3600
def gh(args):
    p = subprocess.Popen(["gh"] + args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL); p.communicate()
        return None
    return out if p.returncode == 0 else None

def origin_of(repo):
    # The repo named from its origin, as nudge_reason names it, so an upstream remote never answers.
    return subprocess.run(["git", "-C", repo, "remote", "get-url", "origin"], capture_output=True, text=True).stdout.strip()

def ci_line(origin):
    # dash's ci line: flow ci_health's ci time over origin's PRs created in the last 7 days, against the
    # 7 days before (flow --since <6 days ago>), as `ci 11m (slowest: test 9m) ▼2m vs last week`.
    from flow_ci_health import ci_time, summary
    from report import local_day, merge_time
    today = datetime.date.today()
    prs = json.loads(gh(["pr", "list", "-R", origin, "--state", "all", "--search", f"created:>={today - datetime.timedelta(days=14)}",
                         "--limit", "1000", "--json", "url,createdAt"]))
    weeks = ([], [])
    for p in prs:
        age = (today - local_day(merge_time(p["createdAt"]))).days
        if 0 <= age < 14:
            weeks[age >= 7].append(p["url"])
    now, before = ([ci_time(u) for u in sorted(w)] for w in weeks)
    if None in now + before:
        return None
    now, before = summary([t for t in now if t]), summary([t for t in before if t])
    if not now:
        return ""
    line = f"ci {now[0]:.0f}m (slowest: {now[1]} {now[2]:.0f}m)"
    if before:
        d = now[0] - before[0]
        line += f" {'▼' if d < 0 else '▲' if d > 0 else '±'}{abs(d):.0f}m vs last week"
    return line

if sys.argv[1:2] == ["--ci"]:
    # A detached refresh: <origin> <cache>. Anything gh or the repo answers oddly leaves the cache as it was.
    try:
        line = ci_line(sys.argv[2])
        if line is not None:
            with open(sys.argv[3] + f".{os.getpid()}", "w") as f:
                f.write(line)
            os.replace(sys.argv[3] + f".{os.getpid()}", sys.argv[3])
    except Exception:
        pass
    sys.exit()
for url in sys.argv[1:]:
    out = gh(["pr", "view", url, "--json", FIELDS])
    if out is not None:
        print(url + "\t" + out.replace("\n", "").replace("\t", ""))
slugs = {}
for l in os.environ["SWARM_PAIRS"].splitlines():
    repo, _, slug = l.partition("\t")
    slugs.setdefault(repo, set()).add(slug)
for repo, mine in slugs.items():
    origin = origin_of(repo)
    # ponytail: only the newest 200 open PRs per repo are read, so a builder's older PR in a repo with
    # more shows as no PR yet; query each unmatched story/<slug> head if a repo ever has that many.
    try:
        prs = json.loads(gh(["pr", "list", "-R", origin, "--state", "open", "--limit", "200", "--json", "url,headRefName"]) or "[]") if origin else []
    except ValueError:
        continue
    for pr in prs if isinstance(prs, list) else []:
        head = str(pr.get("headRefName")) if isinstance(pr, dict) else ""
        if head.startswith("story/") and head[len("story/"):] in mine:
            print("head\t" + head[len("story/"):] + "\t" + pr["url"])
            # A PR a board item lists was viewed above.
            out = gh(["pr", "view", pr["url"], "--json", FIELDS]) if pr.get("url") not in sys.argv[1:] else None
            if out is not None:
                print(pr["url"] + "\t" + out.replace("\n", "").replace("\t", ""))
# The project's ci line from its cache (SWARM_CI_CACHE), which a detached copy of this script reads
# again when it is over CI_SECONDS old; its mtime is moved first, so one dash starts it.
cache, origin = os.environ.get("SWARM_CI_CACHE"), origin_of(os.environ.get("SWARM_CI_PROJECT", "."))
if cache and re.search(r"github\.com[:/]", origin):
    try:
        stale = time.time() - os.path.getmtime(cache) > CI_SECONDS
    except OSError:
        stale = True
    if stale:
        open(cache, "a").close()
        os.utime(cache)
        subprocess.Popen([sys.executable, os.path.abspath(__file__), "--ci", origin, cache], stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    with open(cache) as f:
        print("ci\t" + f.read().strip())
