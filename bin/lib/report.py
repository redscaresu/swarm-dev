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

def turns(path, seen):
    # Each turn of a session's log once, as (its record, model, (input, cache write, cache read, output)
    # tokens, est. USD), skipping (and adding to seen) message ids already counted. A damaged line (a
    # usage that is no object, a token that is no number, a model that is no string) is skipped.
    for line in log_lines(path):
        try:
            d = json.loads(line)
            m = d.get("message") or {}
            u, mid, model = m.get("usage"), m.get("id"), m.get("model", "?")
            if not u or not mid or mid in seen:
                continue
            t = [u.get("input_tokens", 0), u.get("cache_creation_input_tokens", 0), u.get("cache_read_input_tokens", 0), u.get("output_tokens", 0)]
            if not isinstance(model, str) or not all(isinstance(x, (int, float)) for x in t):
                continue
            price = next((v for k, v in PRICES.items() if k in model), None)
        except (ValueError, AttributeError, TypeError):
            continue
        seen.add(mid)
        yield d, model, t, sum(x * p for x, p in zip(t, price)) / 1e6 if price else 0.0

def session_usage(path, seen):
    tok, usd, models = [0, 0, 0, 0], 0.0, set()
    for _, model, t, cost in turns(path, seen):
        models.add(model)
        tok = [x + y for x, y in zip(tok, t)]
        usd += cost
    return tok, usd, models

REWORK_DAYS = 7

def utc(t):
    # A UTC time as gh and events.tsv write it, as an aware datetime; None when empty or it does not parse.
    try:
        return datetime.datetime.fromisoformat(t.replace("Z", "+00:00"))
    except ValueError:
        return None

def rework_of(prs, escaped):
    # The PRs (as pr_key) a later fix reworked: a merged PR that a later merged PR names (a pull URL, or
    # #N of its own repo, in its title or body) merged within REWORK_DAYS after it, or that a
    # log-finding --reviewer escaped row points at within REWORK_DAYS of its merge's local day (findings
    # are dated in local time). prs is (url, merged_at, names), names the refs joined by "+" ("" for
    # none); escaped is (day, pr).
    merged = {pr_key(u): utc(m) for u, m, _ in prs if utc(m)}
    out = set()
    for url, m, names in prs:
        repo = pr_key(url).partition("#")[0]
        for n in names.split("+") if utc(m) and names else ():
            k = repo + n if n.startswith("#") else pr_key(n)
            if k in merged and datetime.timedelta(0) < utc(m) - merged[k] <= datetime.timedelta(days=REWORK_DAYS):
                out.add(k)
    for day, pr in escaped:
        k = pr_key(pr)
        try:
            d = datetime.date.fromisoformat(day)
        except ValueError:
            continue
        if k in merged and 0 <= (d - merged[k].astimezone().date()).days <= REWORK_DAYS:
            out.add(k)
    return out
