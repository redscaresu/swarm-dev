import datetime, json, os, re, signal, subprocess, sys, time
FIELDS = "statusCheckRollup,mergeStateStatus,updatedAt,state"
# The ci line runs flow's ci_health over two weeks of PRs, 3 gh calls each, so at most every 6 hours:
# a week's median barely moves in that time. A refresh that fails is tried again after CI_RETRY.
# ponytail: every PR is read again each time; keep a closed PR's ci_time if the calls ever crowd
# gh's rate limit.
CI_SECONDS, CI_RETRY = 6 * 3600, 600
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

def ci_line(flow, repo):
    # dash's ci line from flow's ci_health output: repo's ci time row, as `ci 11m (slowest: test 9m)
    # ▼2m vs last week`, the change from the minutes it shows; "" with no PRs, None with no table or
    # when gh could read none of them.
    lines = flow.splitlines()
    head = next((i for i, l in enumerate(lines) if l.startswith("repo\tprs\tci_min_median\t")), None)
    if head is None:
        return None
    row = next((l.split("\t") for l in lines[head + 1:] if l.split("\t")[0].lower() == repo.lower()), None)
    if not row or not row[2]:
        return None if any(l.startswith("ci time: gh could not read") for l in lines) else ""
    now = round(float(row[2]))
    line = f"ci {now}m (slowest: {row[3]} {float(row[4]):.0f}m)"
    if row[6]:
        d = now - round(float(row[6]))
        line += f" {'▼' if d < 0 else '▲' if d > 0 else '±'}{abs(d)}m vs last week"
    return line

if sys.argv[1:2] == ["--ci"]:
    # A detached refresh: <project> <owner/repo> <cache>. It runs `swarm.sh flow --since <6 days ago>`'s
    # ci_health alone in the project, and writes the cache only when flow printed its ci time table.
    project, repo, cache = sys.argv[2:5]
    since = (datetime.date.today() - datetime.timedelta(days=6)).isoformat()
    env = {k: v for k, v in os.environ.items() if k != "HERDR_ENV"}
    env.update(SWARM_PROJECT=project, SWARM_FLOW_SECTIONS="ci_health")
    swarm = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "swarm.sh")
    flow = subprocess.run(["bash", swarm, "flow", "--since", since], cwd=project, env=env, capture_output=True, text=True).stdout
    line = ci_line(flow, repo)
    if line is not None:
        with open(f"{cache}.{os.getpid()}", "w") as f:
            f.write(line)
        os.replace(f"{cache}.{os.getpid()}", cache)
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
# The project's ci line from its cache (SWARM_CI_CACHE), which a detached copy of this script writes
# again once it is over CI_SECONDS old. <cache>.run marks a refresh started, so one dash starts it and
# a failed one is tried again after CI_RETRY. A cache it cannot read or write leaves the line out.
cache, project = os.environ.get("SWARM_CI_CACHE"), os.environ.get("SWARM_CI_PROJECT", ".")
m = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$", origin_of(project))
if cache and m:
    try:
        now = time.time()
        if not os.path.exists(cache) or now - os.path.getmtime(cache) > CI_SECONDS:
            if not os.path.exists(cache + ".run") or now - os.path.getmtime(cache + ".run") > CI_RETRY:
                open(cache + ".run", "w").close()
                subprocess.Popen([sys.executable, os.path.abspath(__file__), "--ci", project, m.group(1), cache],
                                 stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        if os.path.exists(cache):
            with open(cache) as f:
                print("ci\t" + f.read().strip())
    except OSError:
        pass
