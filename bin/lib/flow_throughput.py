# Throughput, a flow section (flow_report.py gives its globals): one TSV row per epic, then `all`.
import collections, datetime, json, os, subprocess
from report import *
log = agents

def secs(t):
    # A time in epoch seconds (local when it names no zone); None when it does not parse.
    try:
        return datetime.datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None

def last_entry(path):
    t = None
    for line in log_lines(path) if path else ():
        try:
            ts = json.loads(line).get("timestamp")
        except (ValueError, AttributeError):
            continue
        t = (secs(ts) if isinstance(ts, str) else None) or t
    return t

oks = []
for line in open(events, errors="ignore") if os.path.exists(events) else ():
    f = line.rstrip("\n").split("\t")
    t = secs(f[0]) if len(f) == 5 and f[4].startswith("ok") else None
    if t is not None:
        oks.append((t, f[1], f[2], datetime.date.fromtimestamp(t).isoformat()))
# A close after --until still ends its build (at the cutoff); every other event counts in the window
# only, by its local day, as builds are.
closes = [(t, x) for t, c, x, _ in oks if c.split(":")[0] == "close"]
evs = [(t, c, x) for t, c, x, day in oks if since <= day <= until]
agents = [l.rstrip("\n").split("\t") for l in open(log, errors="ignore")] if os.path.exists(log) else []
agents = [f for f in agents if len(f) == 7 and f[1] in roles.split()]
# Local midnight after --until, as agents.tsv dates and a log-less build's start are local.
stop = (datetime.datetime.fromisoformat(until) + datetime.timedelta(days=1)).timestamp()
# A build whose start does not parse (a damaged agents.tsv date and no session log) is left out.
built = [(r, a, t) for r, a in zip(rows, agents) for t in [secs(r["started"] or r["date"] + "T00:00:00")] if t is not None]
project, groups = [], collections.defaultdict(list)   # apart, so an epic named all is still an epic
ended, taken = {}, set()   # slug -> when its last build so far (agents.tsv order) ended; closes taken
for i, (r, a, start) in enumerate(built):
    # A log-less build starts at 00:00, so a retry could seem to start before the build it retries:
    # it starts no earlier than that one ended.
    if not r["started"] and ended.get(r["slug"]):
        start = max(start, ended[r["slug"]])
    # Its first close after its start that no earlier build of the slug took, and before the slug's
    # next build with a known start: a build never closed must not take its retry's. A log-less
    # retry bounds nothing, as its start is only known once this build's end is.
    upto = next((t for o, _, t in built[i + 1:] if o["slug"] == r["slug"] and o["started"]), float("inf"))
    names = (r["slug"], a[2])
    got = min(((t, k) for k, (t, x) in enumerate(closes) if x in names and start <= t < upto and k not in taken),
              default=None)
    if got:
        taken.add(got[1])
    end = got[0] if got else last_entry(session_log(projects, a[6], archive))
    ended[r["slug"]] = end or ended.get(r["slug"])
    if not since <= r["date"] <= until:
        continue
    b = {"slug": r["slug"], "pr": r["pr"], "start": start, "end": min(end, stop) if end else None}
    project.append(b)
    if r["epic"]:
        groups[r["epic"]].append(b)

def running(bs):
    spans = [(b["start"], b["end"]) for b in bs if b["end"] and b["end"] > b["start"]]
    if not spans:
        return "", ""
    now = top = 0
    for _, d in sorted([(s, 1) for s, _ in spans] + [(e, -1) for _, e in spans]):   # an end before a start at one time
        now += d
        top = max(top, now)
    span = max(e for _, e in spans) - min(s for s, _ in spans)
    return f"{sum(e - s for s, e in spans) / span:.2f}", str(top)

def chain(slugs):
    memo = {}
    def depth(s, seen):
        if s not in memo:
            memo[s] = 1 + max((depth(d, seen | {s}) for d in deps.get(s, []) if d in slugs and d not in seen), default=0)
        return memo[s]
    return max((depth(s, frozenset()) for s in slugs), default=0)

def created_at(url):
    # Its createdAt from gh, cached as it never changes, or "" when gh cannot read it.
    def read():
        got = subprocess.run(["gh", "pr", "view", url, "--json", "createdAt", "--jq", ".createdAt"], capture_output=True, text=True)
        return got.stdout.strip() if got.returncode == 0 else ""
    repo, _, n = pr_key(url).partition("#")
    return gh_cache.cached(repo, f"created/{n}", read, bool) if n else read()
created = {u: created_at(u) for u in {b["pr"] for b in (groups[epic] if epic else project)} if u.startswith("https://")}
def waits(bs):
    wait, proxy = [], []
    prs = list({pr_key(b["pr"]): b for b in bs if b["pr"]}.values())
    for b in prs:
        t0 = secs(created.get(b["pr"], ""))
        # A retry's PR takes the slug's events from its own createdAt on, so an older PR keeps only its own.
        t1 = min((t for t in (secs(created.get(o["pr"], "")) for o in prs if o["slug"] == b["slug"])
                  if t is not None and t0 is not None and t > t0), default=float("inf"))
        first = lambda cmds: min((t for t, c, x in evs if c in cmds and x == b["slug"] and t0 <= t < t1), default=None)
        t = first(("review-agent",)) if t0 is not None else None
        p = first(("tell:findings", "tell", "review")) if t0 is not None and t is None else None
        if t is not None:
            wait.append(t - t0)
        elif p is not None:
            proxy.append(p - t0)
    mean = lambda xs: str(round(sum(xs) / len(xs) / 60)) if xs else ""
    return mean(wait), mean(proxy)

print("epic\tbuilds\tbuilders_mean\tbuilders_max\tstories\tlongest_chain\tstories_per_chain"
      "\treview_wait_min\tproxy_review_wait_min\tstacked")
# With --epic, only its row.
for g, bs in [(epic, groups[epic])] if epic else sorted(groups.items()) + [(None, project)]:
    slugs = {b["slug"] for b in bs}
    n = chain(slugs)
    stacked = sum(1 for _, c, x in evs if c == "stacked" and (g is None or x in slugs))
    print("\t".join([g or "all", str(len(bs)), *running(bs), str(len(slugs)), str(n), f"{len(slugs) / n:.1f}" if n else "",
                     *waits(bs), str(stacked)]))
