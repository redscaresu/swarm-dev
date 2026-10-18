import datetime, functools, glob, gzip, json, os, re, subprocess, sys, zlib
# ponytail: list prices per million tokens as of 2026-09 (input, cache write, cache read, output);
# cache writes assume the 1-hour cache at 2x input. Update when prices change.
PRICES = {"fable": (10, 20, 0.25, 20), "opus": (4, 8, 0.20, 20), "sonnet": (2, 4, 0.20, 10), "haiku": (1, 2, 0.10, 5)}

# The phases outcomes splits a build's start-to-merge minutes into, in the order its columns print
# (<phase>_min); flow's time_in_state reads them by these names.
PHASES = ("building", "ci", "review_wait", "fixing", "merge_wait")

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
RELEASE_FILES = [".claude-plugin/plugin.json"]   # a release PR changes these alone, and fixes nothing
# A clause that names an earlier PR without fixing it: a stacked child's parent, a main merge note.
NOT_A_FIX = re.compile(r"\b(?:merge after|depends on|stacked on|merged origin/main)\b", re.I)
# A fix verb (fix, fixes, fixed, fixing, and hotfix, bugfix or quickfix with or without a hyphen), rework
# of, or regression from, in or of.
FIX = re.compile(r"\b(?:(?:(?:hot|bug|quick)-?)?fix(?:es|ed|ing)?|rework of|regression (?:from|in|of))\b", re.I)
NEGATED = re.compile(r"(?:\b(?:not|never|no longer)|n't)\s+(?:\w+\s+)?$", re.I)   # doesn't fix, not yet fixing
FIX_REACH = 40   # characters from the end of a fix verb to the PR it fixes
CLAUSE = re.compile(r"(?<=[.!?])\s+|;|\n")   # a sentence end before a space, a semicolon or a line break

@functools.lru_cache(maxsize=None)
def pr_ref(repo, n, bare):
    # The pattern for PR n of repo in a PR's text, compiled once: its URL, owner/repo#N, and with bare a bare #N.
    bare = r"|(?<![\w/#])#" if bare else ""
    return re.compile(rf"(?:github\.com/{re.escape(repo)}/pull/|(?<![\w./-]){re.escape(repo)}#{bare}){n}(?!\d)", re.I)

def fixes_pr(text, key, by):
    # Whether the title and body of the PR whose pr_key is by say it fixes the PR whose pr_key is key: in
    # a clause that is not NOT_A_FIX, its URL, owner/repo#N, or a bare #N when both are in one repo, whose
    # governing fix verb (the nearest FIX ending within FIX_REACH characters before it) has no negation
    # directly before it. "Fixes #1 and doesn't fix #4" fixes #1 and not #4.
    repo, _, n = key.partition("#")
    ref = pr_ref(repo, n, by.partition("#")[0] == repo)
    for c in CLAUSE.split(text) if n else ():
        if NOT_A_FIX.search(c):
            continue
        for m in ref.finditer(c):
            verb = [v for v in FIX.finditer(c, 0, m.start()) if m.start() - v.end() <= FIX_REACH][-1:]
            if verb and not NEGATED.search(c, 0, verb[0].start()):
                return True
    return False

def merge_time(t):
    # gh's mergedAt as an aware time, or None when it is empty, malformed or has no offset.
    try:
        d = datetime.datetime.fromisoformat(t.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None
    return d if d.tzinfo else None

def local_day(t):
    # An aware time's local calendar day: log-finding dates findings in local time, so rework counts days so.
    return t.astimezone().date()

def rework_settled():
    # The local day before which a merge has had all its REWORK_DAYS for a fix to come, as YYYY-MM-DD.
    return (datetime.date.today() - datetime.timedelta(days=REWORK_DAYS)).isoformat()

def rework_of(merged, findings, judged=None):
    # The pr_keys of the merged PRs (of judged alone, when given) a later PR fixed within REWORK_DAYS of
    # their merge day (local days, for both kinds of fix): a PR merged after it, on that day or up to that
    # many days later, that fixes_pr says fixes it (a release PR never does), or a log-finding --reviewer
    # escaped row (fixed_rows' day, kind, pr, text, outcome order; outcome escaped) pointing at it, dated
    # that many days after its merge day or fewer. merged maps each merged PR's pr_key to (mergedAt as gh
    # gives it, title and body, and the paths it changed, or None when unknown). A mergedAt that does not
    # parse leaves its PR out, counted on stderr.
    when = {k: merge_time(v[0]) for k, v in merged.items() if v[0]}
    bad = [k for k, t in when.items() if t is None]
    if bad:
        print(f"rework: skipped {len(bad)} merged PRs whose mergedAt does not parse, as {bad[0]}", file=sys.stderr)
    when = {k: t for k, t in when.items() if t}
    fixers = [(j, u) for j, u in when.items() if merged[j][2] != RELEASE_FILES]
    judge = {k: t for k, t in when.items() if judged is None or k in judged}
    out = {k for k, t in judge.items()
           if any(j != k and t < u and (local_day(u) - local_day(t)).days <= REWORK_DAYS and fixes_pr(merged[j][1], k, j)
                  for j, u in fixers)}
    for f in findings:
        k = pr_key(f[2])
        if len(f) > 4 and f[4] == "escaped" and k in judge:
            try:
                d = (datetime.date.fromisoformat(f[0]) - local_day(judge[k])).days
            except ValueError:
                continue
            if 0 <= d <= REWORK_DAYS:
                out.add(k)
    return out

GH_SECONDS = 30
GH_LIMIT = 1000
GITHUB = re.compile(r"https://github\.com/([^/]+/[^/]+)/pull/\d+")

def merged_prs(urls, search):
    # (pr_key -> (mergedAt, title and body, paths changed) for every merged PR of the repos the urls are
    # in that gh's search finds, and repo -> the oldest mergedAt of each list that came back GH_LIMIT long,
    # before which a fix may be missing), or None when gh fails. files is read for rework_of's release PRs.
    # ponytail: the last GH_LIMIT merged PRs per repo; page with gh api if a repo outgrows that within the window.
    out, oldest = {}, {}
    for repo in sorted({m.group(1) for u in urls for m in [GITHUB.match(u)] if m}):
        try:
            got = subprocess.run(["gh", "pr", "list", "-R", repo, "--state", "merged", "--limit", str(GH_LIMIT),
                                  "--json", "url,mergedAt,title,body,files", "--search", search], capture_output=True, text=True, timeout=GH_SECONDS)
            prs = json.loads(got.stdout) if got.returncode == 0 else None
        except (subprocess.TimeoutExpired, ValueError, OSError):   # OSError: no gh on PATH
            prs = None
        if not isinstance(prs, list):
            return None
        if len(prs) >= GH_LIMIT:
            oldest[repo.lower()] = min((t for t in (merge_time(p.get("mergedAt") or "") for p in prs) if t), default=None)
            print(f"rework: gh listed {GH_LIMIT} merged PRs of {repo}, its limit, so rework is unknown for its PRs merged before"
                  f" {oldest[repo.lower()]}.", file=sys.stderr)
        out.update({pr_key(p["url"]): (p.get("mergedAt") or "", f"{p.get('title') or ''}\n{p.get('body') or ''}",
                                       sorted(f.get("path", "") for f in p.get("files") or [])) for p in prs})
    return out, oldest

def rework_from(since):
    # The first local merge day outcomes judges rework for, given flow's or its own --since: REWORK_DAYS
    # before it, so a fix in the window still counts. None for no --since (0000-00-00 or empty) or a bad one.
    try:
        return datetime.date.fromisoformat(since) - datetime.timedelta(days=REWORK_DAYS)
    except (ValueError, OverflowError):
        return None

def rework_unknown(rows, since):
    # Whether outcomes could not judge rework for some PR it should have (gh failed, or its list hit
    # GH_LIMIT): the latest build on a PR merged from rework_from(since) to before rework_settled() has
    # an empty rework cell.
    last = {pr_key(r["pr"]): r for r in rows if r.get("pr")}
    lo = rework_from(since)
    days = [(local_day(t), r) for r in last.values() for t in [merge_time(r.get("merged_at", ""))] if t]
    return any((not lo or d >= lo) and d.isoformat() < rework_settled() and r.get("rework") == "" for d, r in days)
