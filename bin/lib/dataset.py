import collections, datetime, functools, json, os, re, subprocess, sys
from report import *
agents, events, findings, board, projects, archive, out = sys.argv[1:8]

EASY_MAX_LINES = 100   # was_easy: a diff under this many lines
WAS_EASY_RULE = 1      # which definition of was_easy a line used; bump it when the definition changes
ESCALATE = re.compile(r"ok \((?:attempt (\d+)|([a-z0-9-]+): ([\w.-]+) -> ([\w.-]+))\)")

def git(cwd, *args):
    r = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""

def planned(slug):
    # The story as planned: its file at the newest commit that added it (the board PR), and that day.
    c = git(board, "log", "--diff-filter=A", "-1", "--format=%H %cs", "--", f"stories/{slug}.md").split()
    return (git(board, "show", f"{c[0]}:./stories/{slug}.md"), c[1]) if c else ("", "")

def front(text):
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    return dict(re.findall(r"^([a-z_]+): *(.*?) *$", m.group(1), re.M)) if m else {}

def items(v):
    # A front-matter list, [a, b (x, y)]: split on the commas outside parentheses.
    v = (v or "").strip()
    return [s.strip() for s in re.split(r",(?![^()]*\))", v[1:-1]) if s.strip()] if v[:1] == "[" and v[-1:] == "]" else []

def leads():
    # agents.tsv's role-lead lines as (day, model, session log).
    rows = (l.rstrip("\n").split("\t") for l in open(agents, errors="ignore"))
    return [(f[0], f[4], session_log(projects, f[6], archive)) for f in rows if len(f) == 7 and f[1] == "lead"]

def planner(epic, day, cache={}):
    # The model of the last lead agent started by the day the story was added whose session log scopes
    # the epic (plan-epic's brief names docs/epics/<epic>.md); None when none does (a small epic the lead
    # planned alone, or a log that is gone). The log is only searched, never copied.
    if not epic or not day:
        return None
    if (epic, day) not in cache:
        named = re.compile(rf"epics/{re.escape(epic)}\.md\b")
        cache[(epic, day)] = next((m for d, m, p in reversed(LEADS) if d <= day
                                   and any(named.search(l) for l in log_lines(p) if p)), None)
    return cache[(epic, day)]

@functools.lru_cache(maxsize=None)
def merges(repo):
    # A repo's default branch's commits, newest first, as (sha, UTC time, message): where a merged PR
    # lands, and where a later fix names it.
    if not repo:
        return ()
    ref = "origin/HEAD" if git(repo, "rev-parse", "-q", "--verify", "origin/HEAD") else "HEAD"
    log = git(repo, "log", ref, "--first-parent", "--format=%H%x00%cI%x00%B%x01")
    return tuple(tuple(c.lstrip("\n").split("\0", 2)) for c in log.split("\x01") if c.strip())

def pr_diff(pr, slug, epic):
    # The PR's lines added and removed and its files, less the board's (the story's file, and its epic's,
    # which an epic's last story PR deletes), and its merge commit,
    # from gh, so any merge method (squash, merge or rebase) and any repo reads alike; (None, None, "")
    # when gh cannot say. ponytail: gh lists a PR's first 100 files; page the API if a story outgrows that.
    r = subprocess.run(["gh", "pr", "view", pr, "--json", "files,mergeCommit"], capture_output=True, text=True)
    try:
        d = json.loads(r.stdout)
        board_files = (f"stories/{slug}.md",) + ((f"epics/{epic}.md",) if epic else ())
        files = [f for f in d["files"] if not f["path"].endswith(board_files)]
        return sum(f["additions"] + f["deletions"] for f in files), len(files), (d.get("mergeCommit") or {}).get("oid", "")
    except (ValueError, TypeError, KeyError, AttributeError):
        return None, None, ""

def escalations(slug):
    found = []
    for line in open(events, errors="ignore") if os.path.exists(events) else ():
        f = line.rstrip("\n").split("\t")
        m = len(f) == 5 and f[1] == "escalate" and f[2] == slug and ESCALATE.fullmatch(f[4])
        if m:
            found.append({"at": f[0], "trigger": f"attempt {m[1]}" if m[1] else m[2],
                          "from": m[3], "to": m[4] or "fable"})
    return found

def minutes(start, end):
    # Whole minutes from one UTC time to a later one, as a string; "" when either does not parse, or the
    # end comes first (a retry on a reused slug that started after the merge), as outcomes_join's.
    try:
        t = lambda s: datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
        d = (t(end) - t(start)).total_seconds()
    except ValueError:
        return ""
    return str(round(d / 60)) if d >= 0 else ""

def merged_pr(slug):
    # The story's merged PR as (url, mergedAt) straight from gh, for a story whose builds hold none (a
    # retry whose session logs are gone has no PR of its own); ("", "") when gh cannot say.
    r = subprocess.run(["gh", "pr", "list", "--head", f"story/{slug}", "--state", "merged", "--json", "url,mergedAt",
                        "--limit", "1"], capture_output=True, text=True, cwd=REPOS.get(slug) or None)
    try:
        p = json.loads(r.stdout)[0]
        return p["url"], p["mergedAt"]
    except (ValueError, TypeError, KeyError, IndexError):
        return "", ""

def previous():
    # The lines the last run wrote, by slug: a story whose merged PR cannot be read this time keeps its own.
    try:
        rows = [json.loads(l) for l in open(out, encoding="utf-8")]
    except (OSError, ValueError):
        return {}
    return {d["slug"]: d for d in rows if isinstance(d, dict) and d.get("slug") and d.get("merged_at")}

def num(v, cast):
    try:
        return cast(v)
    except (TypeError, ValueError):
        return None

LEADS = leads()
REPOS = dict(l.split("\t", 1) for l in os.environ["SWARM_REPOS"].splitlines() if "\t" in l)
NO_REPO = set(os.environ["SWARM_NO_REPO"].split())
PREVIOUS = previous()
ESCAPED = [(f[0], f[2]) for f in finding_rows(findings, ("escaped",))]
lines = os.environ["SWARM_ROWS"].splitlines()
builds = collections.defaultdict(list)
for line in lines[1:]:
    b = dict(zip(lines[0].split("\t"), line.split("\t")))
    builds[b["slug"]].append(b)

# A story gh could not read (kind is known, so outcomes asked, but story_merged is empty): an expired
# token, offline or a rate limit would read every story as unmerged, so nothing is overwritten. A story
# whose repo is not here (NO_REPO: repo_dir failed, so gh never ran) is skipped and counted instead.
unread = sorted(s for s, bs in builds.items() if s not in NO_REPO and any(b["kind"] and not b["story_merged"] for b in bs))
if NO_REPO & set(builds):
    skipped = sorted(NO_REPO & set(builds))
    print(f"skipped {len(skipped)} {'story' if len(skipped) == 1 else 'stories'} whose repo is not here: {', '.join(skipped)}", file=sys.stderr)
stories = []
for slug, bs in builds.items():
    if slug in NO_REPO:
        continue
    done = [b for b in bs if b.get("merged_at")]
    if done:
        pr, merged_at = done[-1]["pr"], done[-1]["merged_at"]
    elif any(b["story_merged"] == "true" for b in bs):
        pr, merged_at = merged_pr(slug)
        if not pr:
            kept = PREVIOUS.get(slug)
            print(f"{slug}: merged, but gh gave no merged PR; " + ("kept its previous line" if kept else "left out"), file=sys.stderr)
            if kept:
                stories.append((kept["merged_at"], kept))
            continue
    else:
        continue   # not finished: no PR of it merged
    text, added = planned(slug)
    fm = front(text)
    epic = fm.get("epic") or bs[-1]["epic"] or None
    diff_lines, diff_files, own = pr_diff(pr, slug, epic)
    if diff_lines is None:
        unread.append(slug)
    rework = rework_of(pr, merged_at, [c[1:] for c in merges(REPOS.get(slug, "")) if c[0] != own], ESCAPED)
    rounds = sum(num(b["tells_findings"], int) or 0 for b in bs)
    costs = [num(b["cost_usd"], float) for b in bs if b["cost_usd"]]
    starts = sorted(b["started"] for b in bs if b["started"])
    attempts = max(num(b["attempts"], int) or 0 for b in bs)
    was_easy = None if diff_lines is None else attempts == 1 and rounds <= 1 and not rework and diff_lines < EASY_MAX_LINES
    stories.append((merged_at, {
        "slug": slug, "epic": epic, "pr": pr, "merged_at": merged_at,
        "inputs": {"text": text, "kind": (fm.get("kind") or "code") if text else None, "risk": fm.get("risk") or None,
                   "touches": items(fm.get("touches")), "depends_on": items(fm.get("depends_on")),
                   "estimate_lines": num(fm.get("estimate_lines"), int),
                   "easy": {"true": True, "false": False}.get(fm.get("easy")),
                   "planner_model": planner(epic, added)},
        "results": {"diff_lines": diff_lines, "diff_files": diff_files, "attempts": attempts,
                    "findings_rounds": rounds, "findings_fixed": sum(num(b["findings_fixed"], int) or 0 for b in bs),
                    "rework": rework, "cost_usd": round(sum(costs), 2) if costs else None,
                    "minutes": num(minutes(starts[0], merged_at), int) if starts else None,
                    "models": list(dict.fromkeys(b["model"] for b in bs if b["model"])),
                    "escalations": escalations(slug)},
        "was_easy": was_easy, "was_easy_rule": WAS_EASY_RULE}))

if unread:
    sys.exit(f"gh could not read the PRs of {', '.join(unread)}; {out} is left as it was: check gh auth status and run it again")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out + ".tmp", "w") as f:
    for _, s in sorted(stories, key=lambda s: s[0]):
        f.write(json.dumps(s) + "\n")
os.replace(out + ".tmp", out)
print(f"wrote {len(stories)} finished stories to {out}")
