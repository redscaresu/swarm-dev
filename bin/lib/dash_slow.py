import datetime, fcntl, json, os, re, signal, stat, subprocess, sys, time
FIELDS = "statusCheckRollup,mergeStateStatus,updatedAt,state"
# The ci line runs flow's ci_health over two weeks of PRs, 4 gh calls each, so at most every 6 hours:
# a week's median barely moves in that time. A refresh that fails is tried again after CI_RETRY, and
# one still running after CI_TIMEOUT is stopped. ponytail: every PR is read again each time; keep a
# closed PR's ci_time if the calls ever crowd gh's rate limit.
CI_SECONDS, CI_RETRY, CI_TIMEOUT = 6 * 3600, 600, 1800
CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f]")   # flow_ci_health.py's: the cache is text to print, not escapes
def private(path, flags):
    # os.open that never follows a symlink, as an opener for open(): a second guard, after own_dir.
    return os.open(path, flags | os.O_NOFOLLOW, 0o600)

def own_dir(path):
    # path's directory, made 0700 if it is not there; PermissionError unless it is a directory (not a
    # link) this user owns that no one else can write to. The ci cache's names are easy to guess under
    # a TMPDIR other users may write to (/tmp), so no one else may plant, rewrite or lock a file in it.
    d = os.path.dirname(path)
    try:
        os.mkdir(d, 0o700)
    except FileExistsError:
        pass
    st = os.lstat(d)
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise PermissionError(d)
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
    # ▼2m vs last week`, the change from the minutes it shows; "" with no row for a quiet week, None
    # with no table (flow failed) or when gh could not read one of this window's PRs (offline, a login
    # expired, a hiccup): a failed refresh, tried again soon, that keeps the line there was.
    lines = flow.splitlines()
    head = next((i for i, l in enumerate(lines) if l.startswith("repo\tprs\tci_min_median\t")), None)
    if head is None or re.search(r"^ci time: gh could not read \d+ of \d+ PRs \([1-9]", flow, re.M):
        return None
    row = next((l.split("\t") for l in lines[head + 1:] if l.split("\t")[0].lower() == repo.lower()), None)
    if not row or not row[2]:
        return ""
    now = round(float(row[2]))
    line = f"ci {now}m (slowest: {row[3]} {float(row[4]):.0f}m)"
    if row[6]:
        d = now - round(float(row[6]))
        line += f" {'▼' if d < 0 else '▲' if d > 0 else '±'}{abs(d)}m vs last week"
    return line

def age(path):
    # Seconds since path changed, or None when it is not there.
    try:
        return time.time() - os.path.getmtime(path)
    except FileNotFoundError:
        return None

def ci_refresh(project, repo, cache):
    # Runs `swarm.sh flow --since <6 days ago>`'s ci time table alone in the project (its whole process
    # group stopped after CI_TIMEOUT) and writes the cache when flow printed it, else stamps
    # <cache>.failed. It holds start_refresh's lock on <cache>.run (an inherited descriptor) until it ends.
    line = None
    try:
        since = (datetime.date.today() - datetime.timedelta(days=6)).isoformat()
        env = {k: v for k, v in os.environ.items() if k != "HERDR_ENV"}
        env.update(SWARM_PROJECT=project, SWARM_FLOW_SECTIONS="ci_health", SWARM_CI_TIME_ONLY="1")
        swarm = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "swarm.sh")
        p = subprocess.Popen(["bash", swarm, "flow", "--since", since], cwd=project, env=env, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, encoding="utf-8", errors="replace", start_new_session=True)
        try:
            line = ci_line(p.communicate(timeout=CI_TIMEOUT)[0], repo)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL); p.communicate()
        if line is not None:
            with open(f"{cache}.{os.getpid()}", "x", encoding="utf-8", opener=private) as f:
                f.write(line)
            os.replace(f"{cache}.{os.getpid()}", cache)
    except Exception:
        line = None
    finally:
        if line is None:
            open(cache + ".failed", "w", opener=private).close()

if sys.argv[1:2] == ["--ci"]:
    ci_refresh(*sys.argv[2:5])
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
def start_refresh(project, repo, cache):
    # A detached ci_refresh, unless one failed within CI_RETRY or one runs: it holds an flock on
    # <cache>.run, taken here and passed to it, which the kernel drops when it ends however it ends.
    failed = age(cache + ".failed")
    if failed is not None and failed < CI_RETRY:
        return
    fd = private(cache + ".run", os.O_CREAT | os.O_WRONLY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        subprocess.Popen([sys.executable, os.path.abspath(__file__), "--ci", project, repo, cache], pass_fds=(fd,),
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except BlockingIOError:
        pass
    finally:
        os.close(fd)

# The project's ci line from its cache (SWARM_CI_CACHE), refreshed by a detached ci_refresh once it is
# over CI_SECONDS old (never with SWARM_NO_CI_REFRESH set, as in tests); past that age the line says
# how old it is. Anything that goes wrong here leaves the ci line out, never the rest of the cache.
try:
    cache, project = os.environ.get("SWARM_CI_CACHE"), os.environ.get("SWARM_CI_PROJECT", ".")
    m = re.search(r"github\.com[:/]([^/]+/[^/]+?)(?:\.git)?/?$", origin_of(project))
    if cache and m:
        own_dir(cache)
        old = age(cache)
        if (old is None or old > CI_SECONDS) and not os.environ.get("SWARM_NO_CI_REFRESH"):
            start_refresh(project, m.group(1), cache)
        if old is not None:
            with open(cache, encoding="utf-8", opener=private) as f:
                line = CONTROL.sub("", f.read()).strip()
            if line and old > CI_SECONDS:
                line += f" · {old // 3600:.0f}h old" if old < 2 * 86400 else f" · {old // 86400:.0f}d old"
            print("ci\t" + line)
except Exception:
    pass
