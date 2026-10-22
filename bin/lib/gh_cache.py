# Finished GitHub records, which never change, so flow reads each from gh once: one JSON file per
# record under SWARM_GH_CACHE (<project>/.swarm/gh-cache; empty, as with flow --no-cache, caches
# nothing), in a folder per repo. A record that is not finished (an open PR, a run in progress) is
# never written, so it is read fresh every time. A write is a temp file renamed over the old one, so
# a parallel flow never reads half a file; one that cannot be read or parsed is fetched again.
import json, os, tempfile

def path(repo, name):
    return os.path.join(os.environ.get("SWARM_GH_CACHE", ""), repo.lower().replace("/", "--"), name + ".json")

def get(repo, name):
    # The cached record, or None when there is none, no cache, or it does not read or parse.
    if not os.environ.get("SWARM_GH_CACHE"):
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

def pull(repo, n, gh):
    # gh api repos/<repo>/pulls/<n>, cached once the PR is closed or merged, its state and branches alone.
    return cached(repo, f"pulls/{n}", lambda: gh("api", f"repos/{repo}/pulls/{n}"), closed,
                  lambda p: {"state": p["state"], **{k: {"ref": (p.get(k) or {}).get("ref")} for k in ("head", "base")}})

def commits(repo, n, pr, gh):
    # PR n's commits, its pages slurped, cached once pr (pull's) is closed, each its sha and message alone.
    return cached(repo, f"commits/{n}", lambda: gh("api", "--paginate", "--slurp", f"repos/{repo}/pulls/{n}/commits?per_page=100"),
                  lambda pages: closed(pr) and isinstance(pages, list),
                  lambda pages: [[{"sha": c.get("sha"), "commit": {"message": (c.get("commit") or {}).get("message")}}
                                  for c in page if isinstance(c, dict)] for page in pages if isinstance(page, list)])
