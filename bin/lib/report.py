import datetime, glob, gzip, json, os, re, zlib
# ponytail: list prices per million tokens as of 2026-09 (input, cache write, cache read, output);
# cache writes assume the 1-hour cache at 2x input. Update when prices change.
PRICES = {"fable": (10, 20, 0.25, 20), "opus": (4, 8, 0.20, 20), "sonnet": (2, 4, 0.20, 10), "haiku": (1, 2, 0.10, 5)}

def pr_key(pr):
    m = re.search(r"github\.com/([^/\s]+/[^/\s]+)/pull/(\d+)", pr) or re.fullmatch(r"\s*([^/\s#]+/[^/\s#]+)#(\d+)\s*", pr)
    return f"{m.group(1).lower()}#{m.group(2)}" if m else pr.strip().rstrip("/")

def agent_name(n):
    # bash agent_name: the name agents.tsv keeps for a slug (lowercase, [a-z0-9_-], a letter first, 32 at most).
    n = re.sub(r"[^a-z0-9_-]", "-", n.lower())
    return (n if re.match(r"[a-z]", n) else "s" + n)[:32]

REWORK_DAYS = 7   # a fix this soon after a merge is rework of it, not new work

def rework_of(pr, merged, later, escaped):
    # True when the PR, merged at UTC time merged, was fixed within REWORK_DAYS: a later commit (later:
    # (ISO time, message) pairs) names it as #N or by URL, or an escaped finding (findings.tsv rows, as
    # (day, kind, pr, ...)) points at it. dataset and rework share it, so both count the same fixes.
    m = re.fullmatch(r"([^#]+)#(\d+)", pr_key(pr))
    if not m or not merged:
        return False
    try:
        t0 = datetime.datetime.fromisoformat(merged.replace("Z", "+00:00"))
    except ValueError:
        return False
    o_r, n = re.escape(m[1]), m[2]
    names = re.compile(r"((?<![\w/])|(?<![\w./-])%s)#%s(?!\d)|github\.com/%s/pull/%s(?!\d)" % (o_r, n, o_r, n), re.I)
    for when, message in later:
        try:
            dt = datetime.datetime.fromisoformat(when.replace("Z", "+00:00")) - t0
        except ValueError:
            continue
        if datetime.timedelta(0) < dt <= datetime.timedelta(days=REWORK_DAYS) and names.search(message):
            return True
    for f in escaped:
        try:
            days = (datetime.date.fromisoformat(f[0]) - t0.date()).days
        except ValueError:
            continue
        if pr_key(f[2]) == pr_key(pr) and 0 <= days <= REWORK_DAYS:
            return True
    return False

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
