import datetime, glob, gzip, json, os, re, zlib
# ponytail: list prices per million tokens as of 2026-09 (input, cache write, cache read, output);
# cache writes assume the 1-hour cache at 2x input. Update when prices change.
PRICES = {"fable": (10, 20, 0.25, 20), "opus": (4, 8, 0.20, 20), "sonnet": (2, 4, 0.20, 10), "haiku": (1, 2, 0.10, 5)}

def pr_key(pr):
    m = re.search(r"github\.com/([^/\s]+/[^/\s]+)/pull/(\d+)", pr) or re.fullmatch(r"\s*([^/\s#]+/[^/\s#]+)#(\d+)\s*", pr)
    return f"{m.group(1).lower()}#{m.group(2)}" if m else pr.strip().rstrip("/")

def session_log(projects, session, archive=""):
    if session in ("", "-"):
        return ""
    # Escaped, so a project or config dir named with [, ], * or ? is a path, not a pattern.
    paths = glob.glob(os.path.join(glob.escape(projects), "*", glob.escape(session) + ".jsonl"))
    if not paths and archive:
        paths = glob.glob(os.path.join(glob.escape(archive), f"*-{glob.escape(session)}.jsonl.gz"))
    return paths[0] if paths else ""

def log_lines(path):
    try:
        with gzip.open(path, "rt", errors="ignore") if path.endswith(".gz") else open(path, errors="ignore") as f:
            yield from f
    except (OSError, EOFError, zlib.error):   # truncated, not gzip, or gone since the glob
        return

def finding_rows(path, outcomes=("fixed", "declined")):
    # Read first, so a report that does not pass SWARM_FINDING_REVIEWERS fails rather than drops every row.
    reviewers = os.environ["SWARM_FINDING_REVIEWERS"].split() + ["unknown"]
    if not os.path.exists(path):
        return []
    rows = (l.rstrip("\n").split("\t")[:6] for l in open(path, encoding="utf-8", errors="replace", newline="\n"))
    rows = (f + ["fixed", "unknown"][len(f) - 4:] for f in rows if len(f) >= 4)
    return [f for f in rows if f[4] in outcomes and f[5] in reviewers]

def fixed_rows(path):
    return [f[:4] for f in finding_rows(path, ("fixed", "escaped"))]

def session_usage(path, seen):
    tok, usd, models = [0, 0, 0, 0], 0.0, set()
    for line in log_lines(path):
        try:
            m = json.loads(line).get("message") or {}
        except (ValueError, AttributeError):
            continue
        u, mid = m.get("usage"), m.get("id")
        if not u or not mid or mid in seen:
            continue
        seen.add(mid)
        t = [u.get("input_tokens", 0), u.get("cache_creation_input_tokens", 0), u.get("cache_read_input_tokens", 0), u.get("output_tokens", 0)]
        model = m.get("model", "?")
        models.add(model)
        tok = [x + y for x, y in zip(tok, t)]
        price = next((v for k, v in PRICES.items() if k in model), None)
        if price:
            usd += sum(x * p for x, p in zip(t, price)) / 1e6
    return tok, usd, models

REWORK_DAYS = 7   # a fix this soon after a merge is rework of it

def rework_of(pr, merged_at, commits, escaped):
    # True when a later PR fixed the merged pr within REWORK_DAYS of merged_at (UTC, as gh writes it):
    # a commit after it (commits: (UTC time, message) on the default branch, the pr's own merge left
    # out) names it as #N, owner/repo#N or its pull URL, or an escaped finding ((local day, pr) pairs) points at it.
    try:
        t = lambda s: datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
        start = t(merged_at)
    except ValueError:
        return False
    end, (repo, _, n) = start + datetime.timedelta(days=REWORK_DAYS), pr_key(pr).rpartition("#")
    # A bare #N is the repo's own PR; a URL or owner/repo#N must name this repo.
    r = re.escape(repo)
    names = re.compile(rf"(?<![\w/])#{n}(?!\d)|(?<![\w.-])(github\.com/{r}/pull/|{r}#){n}(?!\d)", re.I)
    for when, msg in commits:
        try:
            if start < t(when) <= end and names.search(msg):
                return True
        except ValueError:
            continue
    return any(pr_key(p) == pr_key(pr) and 0 <= (datetime.date.fromisoformat(d) - start.date()).days <= REWORK_DAYS
               for d, p in escaped if re.fullmatch(r"\d{4}-\d\d-\d\d", d))
