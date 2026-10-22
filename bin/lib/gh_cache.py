# Finished GitHub records, which never change, so flow reads each from gh once: one JSON file per
# record under SWARM_GH_CACHE (<project>/.swarm/gh-cache; empty caches nothing), in a folder per repo.
# With SWARM_GH_FRESH set (flow --no-cache) nothing is read from it, and what gh answers is written
# over it. A record that is not finished (an open PR, a run in progress) is never written, so it is
# read fresh every time. A write is a temp file renamed over the old one, so a parallel flow never
# reads half a file; one that cannot be read or parsed is fetched again.
import datetime, json, os, re, tempfile

def path(repo, name):
    return os.path.join(os.environ.get("SWARM_GH_CACHE", ""), repo.lower().replace("/", "--"), name + ".json")

def get(repo, name):
    # The cached record, or None when there is none, no cache, a fresh run, or it does not read or parse.
    if not os.environ.get("SWARM_GH_CACHE") or os.environ.get("SWARM_GH_FRESH"):
        return None
    try:
        with open(path(repo, name), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None

def put(repo, name, value):
    # Best effort: flow never fails on a write it does only to save a gh call.
    if not os.environ.get("SWARM_GH_CACHE"):
        return
    p = path(repo, name)
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p), suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(value, f)
        os.replace(tmp, p)
    except OSError:
        pass

def cached(repo, name, fetch, done, keep=lambda v: v):
    # name's record: the cached one when done says it is finished (a damaged one is not), else
    # fetch()'s answer, cached (what keep keeps of it) once done says it is finished.
    got = get(repo, name)
    if got is not None and done(got):
        return got
    got = fetch()
    if got is not None and done(got):
        got = keep(got)
        put(repo, name, got)
    return got

def closed(pr):
    return isinstance(pr, dict) and pr.get("state") == "closed"

def merged(pr):
    return closed(pr) and bool(pr.get("merged_at"))

def pull(repo, n, gh):
    # gh api repos/<repo>/pulls/<n>, cached once the PR is merged (a closed one can be reopened, so it
    # is read again each time), what flow reads of it alone.
    return cached(repo, f"pulls/{n}", lambda: gh("api", f"repos/{repo}/pulls/{n}"), merged,
                  lambda p: {"state": p["state"], "merged_at": p["merged_at"], "updated_at": p.get("updated_at"),
                             **{k: {"ref": (p.get(k) or {}).get("ref")} for k in ("head", "base")}})

def as_of(n, pr):
    # The key of PR n's records as pr (pull's) stands: a reopened PR, or a push to it, moves its updated_at.
    return f"{n}-{pr.get('updated_at') or ''}" if isinstance(pr, dict) else str(n)

def commits(repo, n, pr, gh):
    # PR n's commits, its pages slurped, cached while pr (pull's) is closed, each its sha and message alone.
    return cached(repo, f"commits/{as_of(n, pr)}", lambda: gh("api", "--paginate", "--slurp", f"repos/{repo}/pulls/{n}/commits?per_page=100"),
                  lambda pages: closed(pr) and isinstance(pages, list),
                  lambda pages: [[{"sha": c.get("sha"), "commit": {"message": (c.get("commit") or {}).get("message")}}
                                  for c in page if isinstance(c, dict)] for page in pages if isinstance(page, list)])

DAY = re.compile(r"\d{4}-\d\d-\d\d")

class Listing:
    # An incremental listing's cache (a repo's merged PRs, its runs), one file: its records (items, by
    # key), the first day they hold whole (from) and the newest day listed (next). A file that does
    # not read, starts after start, or holds a record valid rejects starts afresh (fresh) from start.
    def __init__(self, repo, name, start, valid):
        got = get(repo, name)
        self.fresh = not (isinstance(got, dict) and isinstance(got.get("items"), dict)
                          and all(isinstance(got.get(k), str) and DAY.fullmatch(got[k]) for k in ("from", "next"))
                          and got["from"] <= start and all(map(valid, got["items"].values())))
        self.repo, self.name = repo, name
        self.state = {"from": start, "next": start, "items": {}} if self.fresh else got
        self.items = self.state["items"]

    def since(self, back):
        # The day to list from: back days before next (for records listed late, or changed since),
        # never before from.
        day = datetime.date.fromisoformat(self.state["next"]) - datetime.timedelta(days=back)
        return max(day.isoformat(), self.state["from"])

    def save(self, next_day, day=None, keep_days=None):
        # Writes the items, the next listing to start from next_day; with keep_days, items whose day
        # (day(item)) is older than that many days are dropped, and from moves up past them.
        if keep_days:
            cut = (datetime.datetime.now(datetime.timezone.utc).date() - datetime.timedelta(days=keep_days)).isoformat()
            self.state["items"] = self.items = {k: v for k, v in self.items.items() if day(v) >= cut}
            self.state["from"] = max(self.state["from"], cut)
        self.state["next"] = max(next_day, self.state["from"])
        put(self.repo, self.name, self.state)
