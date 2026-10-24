import datetime, functools, glob, gzip, json, os, re, subprocess, sys, time, zlib
import gh_cache
# ponytail: list prices per million tokens as of 2026-09 (input, cache write, cache read, output);
# cache writes assume the 1-hour cache at 2x input. Update when prices change.
PRICES = {"fable": (10, 20, 0.25, 20), "opus": (4, 8, 0.20, 20), "sonnet": (2, 4, 0.20, 10), "haiku": (1, 2, 0.10, 5)}

# The phases outcomes splits a build's start-to-merge minutes into, in the order its columns print
# (<phase>_min); flow's time_in_state reads them by these names.
PHASES = ("building", "ci", "review_wait", "fixing", "merge_wait")

def pr_key(pr):
    m = re.search(r"github\.com/([^/\s]+/[^/\s]+)/pull/(\d+)", pr) or re.fullmatch(r"\s*([^/\s#]+/[^/\s#]+)#(\d+)\s*", pr)
    return f"{m.group(1).lower()}#{m.group(2)}" if m else pr.strip().rstrip("/")

# run_key(target) — a conduct or report event's target as a conductor run's key: <epic>, or --backlog
# (a report logs backlog), with .l<k> for lane k's conductor (conductor_lanes).
def run_key(target):
    m = re.fullmatch(r"(.+)(\.l\d+)", target)
    base, lane = (m.group(1), m.group(2)) if m else (target, "")
    return ("--backlog" if base in ("backlog", "--backlog") else base) + lane

# run_names(key) — the agent names a run key's conductor had, as bash conductor_name makes them: for
# lane k, cut so -l<k> fits; the backlog's per-project SWARM_BACKLOG_CONDUCTOR, or conduct-backlog in
# older logs.
def run_names(key):
    m = re.fullmatch(r"(.+)\.l(\d+)", key)
    base, s = (m.group(1), f"-l{m.group(2)}") if m else (key, "")
    if base != "--backlog":
        return [agent_name("conduct-" + base)[:32 - len(s)] + s]
    b = os.environ.get("SWARM_BACKLOG_CONDUCTOR", "")
    return ([] if s else ["conduct-backlog"]) + ([b[:-7][:25 - len(s)] + b[-7:] + s] if b else [])

# run_report(events_dir, key) — the report file a run key's conductor writes.
def run_report(events_dir, key):
    return os.path.join(events_dir, "conduct-" + re.sub(r"^--backlog", "backlog", key) + ".report.md")

# A step-up's escalate line: ok (<trigger>: <from> -> <to>).
STEP_UP = re.compile(r"ok \(([a-z0-9-]+): (\S+) -> (\S+)\)")

def escalate_build(result, model):
    # An escalate line that started an escalate build, on <model> (the escalate role's): build_story's
    # ok (attempt N), or a step-up to <model>. A step-up to a lower rung started none.
    m = STEP_UP.fullmatch(result)
    return re.fullmatch(r"ok \(attempt \d+\)", result) is not None or (m is not None and m.group(3) == model)

def agent_name(n):
    # bash agent_name: the name agents.tsv keeps for a slug (lowercase, [a-z0-9_-], a letter first, 32 at most).
    n = re.sub(r"[^a-z0-9_-]", "-", n.lower())
    return (n if re.match(r"[a-z]", n) else "s" + n)[:32]

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

def finding_rows(path, outcomes=("fixed", "declined"), width=6):
    # Read first, so a report that does not pass SWARM_FINDING_REVIEWERS fails rather than drops every row.
    reviewers = os.environ["SWARM_FINDING_REVIEWERS"].split() + ["unknown"]
    if not os.path.exists(path):
        return []
    rows = (l.rstrip("\n").split("\t")[:8] for l in open(path, encoding="utf-8", errors="replace", newline="\n"))
    rows = ((f + ["fixed", "unknown"][len(f) - 4:] + ["", ""])[:width] for f in rows if len(f) >= 4)
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

# gh over REST for flow's sections: one flow run shares ERROR and LIMIT, so once one section spends
# the hourly limit, the later ones make no calls either.
CONTROL = re.compile(r"[\x00-\x1f\x7f-\x9f]")   # gh's errors and a fork's job names are not ours to print raw
ERROR = [""]   # the last gh call that failed, and why
PASSES = re.compile(r"connection reset|unexpected EOF|i/o timeout|TLS handshake timeout|HTTP 5\d\d", re.I)   # tried again
SPENT = re.compile(r"API rate limit (already )?exceeded")   # the hourly limit: no more calls this run
LIMIT = [""]   # gh's error once the hourly limit is spent

FETCH_SECONDS = 60

@functools.lru_cache(maxsize=None)
def batch_ssh(root):
    # The user's GIT_SSH_COMMAND or core.sshCommand, with -o BatchMode=yes after it.
    return (os.environ.get("GIT_SSH_COMMAND") or subprocess.run(["git", "-C", root, "config", "core.sshCommand"],
            capture_output=True, text=True).stdout.strip() or "ssh") + " -o BatchMode=yes"

def quiet_git(root, *args, seconds=FETCH_SECONDS):
    # git <args> in root that never prompts, even when a partial clone fetches on demand: no stdin, no
    # terminal prompt, and ssh in batch mode, stopped after seconds (exit 124, "over <seconds> s").
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_SSH_COMMAND=batch_ssh(root))
    try:
        return subprocess.run(["git", "-C", root, *args], stdin=subprocess.DEVNULL, capture_output=True, text=True,
                              timeout=seconds, env=env)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(args, 124, "", f"over {seconds} s")

def git_fetch(root, *args):
    # git fetch -q <args> in root, never prompting (quiet_git). "" once it fetched, else why not.
    got = quiet_git(root, "fetch", "-q", *args)
    said = [l.strip() for l in got.stderr.splitlines() if l.strip()]
    return "" if got.returncode == 0 else said[-1] if said else f"exit {got.returncode}"

def gh(*args, seconds=GH_SECONDS, parse=json.loads):
    # Its JSON (or what parse makes of its output, a byte that is not UTF-8 read as U+FFFD; JSON's own
    # such byte fails, gh's error's never), or None when gh fails, takes over seconds or answers something else; ERROR[0] says
    # which call and why. A reset connection or a 5xx is tried again, 1 s then 2 s later (times
    # SWARM_SLEEP_SCALE); any other error is not (a secondary rate limit asks for a minute or more),
    # and once the hourly rate limit is spent, every later call fails at once with that error.
    call = "gh " + " ".join(args[:args.index("--json")] if "--json" in args else args)
    if LIMIT[0]:
        ERROR[0] = f"{call}: not tried: {LIMIT[0]}"
        return None
    for wait in (1, 2, 0):
        try:
            got = subprocess.run(["gh", *args], capture_output=True, timeout=seconds)
            if got.returncode == 0:
                ERROR[0] = f"{call}: an answer it could not read"   # when its caller finds no list or object
                out = got.stdout.decode("utf-8", "strict" if parse is json.loads else "replace")
                return parse(out.replace("\r\n", "\n").replace("\r", "\n"))   # text mode's newlines
            said = [l.strip() for l in got.stderr.decode("utf-8", "replace").splitlines() if l.strip()]
            ERROR[0] = f"{call}: {said[-1]}" if said else f"{call}: exit {got.returncode}"
            LIMIT[0] = said[-1] if said and SPENT.search(said[-1]) else ""
        except subprocess.TimeoutExpired:
            ERROR[0] = f"{call}: over {seconds} s"
            return None
        except ValueError:
            ERROR[0] = f"{call}: an answer that is not JSON"
            return None
        if not wait or not PASSES.search(ERROR[0]):
            return None
        time.sleep(wait * float(os.environ.get("SWARM_SLEEP_SCALE") or 1))

MERGED_DAYS = 120   # merged_prs keeps the PRs merged in the last this many days (or the window, if longer)

def merged_prs(urls, start, end):
    # (pr_key -> (mergedAt, title and body, paths changed) for every PR of the repos the urls are in
    # merged from start to end (YYYY-MM-DD, UTC, as gh's merged: search), and repo -> the oldest mergedAt
    # of each list that came back GH_LIMIT long, before which a fix may be missing), or None when gh
    # fails. files is read for rework_of's release PRs. A merged PR never changes, so each repo's are
    # cached (gh_cache's Listing), and gh searches only from a day before the newest cached one's day
    # (a PR GitHub's search lists late still comes). A list cut at GH_LIMIT (the newest) leaves the days
    # up to its oldest as the cache's hole, searched again first on each run whose window reaches it,
    # which says so again (and gives that cutoff) while it is cut.
    # ponytail: the last GH_LIMIT merged PRs per search; page with gh api if a repo outgrows that within the window.
    out, oldest = {}, {}
    for repo in sorted({m.group(1) for m in map(GITHUB.match, urls) if m}):
        have = gh_cache.Listing(repo, "merged", start, merged_pr)
        since, hole = have.since(1), have.hole_in(end)
        for lo, hi in ([hole] if hole else []) + ([[since, end]] if since <= end else []):   # none when the cache holds every day up to end
            prs = search_merged(repo, lo, hi)
            if prs is None:
                return None
            if [lo, hi] == hole:   # searched again: what it still leaves out is the hole now
                have.state.pop("hole")
            have.items.update({pr_key(p["url"]): [p.get("mergedAt") or "", f"{p.get('title') or ''}\n{p.get('body') or ''}",
                                                  sorted(f.get("path", "") for f in p.get("files") or [])] for p in prs})
            if len(prs) >= GH_LIMIT:
                cutoff = min((t for t in (merge_time(p.get("mergedAt") or "") for p in prs) if t), default=None)
                oldest[repo.lower()] = min(t for t in (oldest.get(repo.lower()), cutoff) if t) if cutoff else oldest.get(repo.lower())
                have.left_out(lo, max(lo, cutoff.astimezone(datetime.timezone.utc).date().isoformat()) if cutoff else hi)
        if repo.lower() in oldest:
            print(f"rework: gh listed {GH_LIMIT} merged PRs of {repo}, its limit, so rework is unknown for its PRs merged before"
                  f" {oldest[repo.lower()]}.", file=sys.stderr)
        have.save(max([v[0][:10] for v in have.items.values() if gh_cache.DAY.match(v[0])] + [have.state["next"]]),
                  lambda v: v[0][:10] if gh_cache.DAY.match(v[0]) else "9999-12-31", MERGED_DAYS)
        # A mergedAt that is no date stays in, for rework_of to count.
        out.update({k: tuple(v) for k, v in have.items.items() if not gh_cache.DAY.match(v[0]) or start <= v[0][:10] <= end})
    return out, oldest

def search_merged(repo, lo, hi):
    # gh's merged PRs of repo merged lo to hi (days, UTC), GH_LIMIT at most, or None when gh fails.
    try:
        got = subprocess.run(["gh", "pr", "list", "-R", repo, "--state", "merged", "--limit", str(GH_LIMIT), "--json", "url,mergedAt,title,body,files",
                              "--search", f"merged:{lo}..{hi}"], capture_output=True, text=True, timeout=GH_SECONDS)
        prs = json.loads(got.stdout) if got.returncode == 0 else None
    except (subprocess.TimeoutExpired, ValueError, OSError):   # OSError: no gh on PATH
        prs = None
    return prs if isinstance(prs, list) else None

def merged_pr(v):
    # Whether a cached merged PR has what merged_prs gives each; a cache with one that has not is rebuilt.
    return isinstance(v, list) and len(v) == 3 and all(isinstance(x, str) for x in v[:2]) and isinstance(v[2], list)

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
