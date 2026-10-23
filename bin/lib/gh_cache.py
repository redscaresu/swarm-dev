# Finished GitHub records, which never change, so flow reads each from gh once: one JSON file per
# record under SWARM_GH_CACHE (<project>/.swarm/gh-cache; empty caches nothing), in a folder per repo.
# With SWARM_GH_FRESH set (flow --no-cache) nothing is read from it, and what gh answers is written
# over it. A record that is not finished (an open PR, a run in progress) is never written, so it is
# read fresh every time. A write is a temp file renamed over the old one, so a parallel flow never
# reads half a file; one that cannot be read or parsed is fetched again.
import datetime, glob, json, os, re, tempfile

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
    p, tmp = path(repo, name), None
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p), suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(value, f)
        os.replace(tmp, p)
    except (OSError, TypeError, ValueError):   # a value json cannot write too
        if tmp:
            try:
                os.remove(tmp)
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

def forget(repo, kind, n, pr):
    # Deletes PR n's kind records kept under another updated_at than pr's (pull's): a reopened PR, or
    # one --no-cache read again, is only read under its newest key.
    if not os.environ.get("SWARM_GH_CACHE") or not isinstance(pr, dict):
        return
    keep = path(repo, f"{kind}/{as_of(n, pr)}")
    for p in glob.glob(os.path.join(glob.escape(os.path.dirname(keep)), f"{n}-*.json")):
        try:
            if p != keep:
                os.remove(p)
        except OSError:
            pass

def commits(repo, n, pr, gh):
    # PR n's commits, its pages slurped, cached while pr (pull's) is closed, each its sha and message alone.
    got = cached(repo, f"commits/{as_of(n, pr)}", lambda: gh("api", "--paginate", "--slurp", f"repos/{repo}/pulls/{n}/commits?per_page=100"),
                 lambda pages: closed(pr) and isinstance(pages, list),
                 lambda pages: [[{"sha": c.get("sha"), "commit": {"message": (c.get("commit") or {}).get("message")}}
                                 for c in page if isinstance(c, dict)] for page in pages if isinstance(page, list)])
    forget(repo, "commits", n, pr)
    return got

DAY = re.compile(r"\d{4}-\d\d-\d\d")

def is_hole(h):
    return isinstance(h, list) and len(h) == 2 and all(isinstance(d, str) and DAY.fullmatch(d) for d in h) and h[0] <= h[1]

class Listing:
    # An incremental listing's cache (a repo's merged PRs, its runs), one file: its records (items, by
    # key), the first day they hold whole (from), the newest day listed (next), and the days a listing
    # cut at GitHub's limit left out (hole, while there is one). A file that does not read, starts
    # after start, or holds a record valid rejects starts afresh (fresh) from start.
    def __init__(self, repo, name, start, valid):
        got = get(repo, name)
        self.fresh = not (isinstance(got, dict) and isinstance(got.get("items"), dict)
                          and all(isinstance(got.get(k), str) and DAY.fullmatch(got[k]) for k in ("from", "next"))
                          and got["from"] <= start and all(map(valid, got["items"].values()))
                          and (got.get("hole") is None or is_hole(got["hole"])))
        self.repo, self.name, self.start = repo, name, start
        self.state = {"from": start, "next": start, "items": {}} if self.fresh else got
        self.items = self.state["items"]
        self.read = json.dumps(self.state, sort_keys=True)   # as read, so a save that changes nothing writes nothing

    def since(self, back):
        # The day to list from: back days before next (for records listed late, or changed since),
        # never before from; or start, when the window starts after next, and the cache then holds
        # from start (the days between are never listed).
        if self.start > self.state["next"]:
            self.state["from"] = self.start
        day = datetime.date.fromisoformat(self.state["next"]) - datetime.timedelta(days=back)
        return max(day.isoformat(), self.state["from"])

    def hole_in(self, end):
        # The hole, to be listed again, when the window (start to end) reaches it; None when there is
        # none or it does not.
        h = self.state.get("hole")
        return h if h and h[0] <= (end or "9999-12-31") and h[1] >= self.start else None

    def left_out(self, lo, hi):
        # Keeps lo to hi (days) as the hole, with any hole already kept: listed again on each run that reaches it.
        h = self.state.get("hole") or [lo, hi]
        self.state["hole"] = [min(lo, h[0]), max(hi, h[1])]

    def save(self, next_day, day=None, keep_days=None):
        # Writes the items, the next listing to start from next_day, unless nothing changed; with
        # keep_days, items whose day (day(item)) is older than that many days, and older than start,
        # are dropped, and from moves up past them.
        if keep_days:
            cut = (datetime.datetime.now(datetime.timezone.utc).date() - datetime.timedelta(days=keep_days)).isoformat()
            cut = min(cut, self.start)
            self.state["items"] = self.items = {k: v for k, v in self.items.items() if day(v) >= cut}
            self.state["from"] = max(self.state["from"], cut)
            if self.state.get("hole") and self.state["hole"][1] < cut:
                del self.state["hole"]
        self.state["next"] = max(next_day, self.state["from"])
        if json.dumps(self.state, sort_keys=True) != self.read:
            put(self.repo, self.name, self.state)
