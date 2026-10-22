import datetime, json, os, re, subprocess, sys
from report import *
from touches_rows import deps, entries, front_text
board, agents, events, findings, projects, archive, out = sys.argv[1:8]
EASY_MAX_LINES = 100   # was_easy rule 1: a diff under this many lines
project_dir = os.path.dirname(os.path.dirname(findings))

def git(repo, *args):
    got = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    return got.stdout if got.returncode == 0 else ""

def default_ref(repo):
    return "origin/HEAD" if git(repo, "rev-parse", "-q", "--verify", "origin/HEAD") else "HEAD"

fetched = set()
def fetch(repo):
    # git fetch origin, once a run per repo, never prompting (report.git_fetch). A fetch that fails or
    # hangs leaves the history as it was, and says so on stderr.
    top = os.path.realpath(git(repo, "rev-parse", "--show-toplevel").strip() or repo)
    if top in fetched:
        return
    fetched.add(top)
    if git_fetch(top, "origin"):
        print(f"dataset: git fetch origin failed in {top}, so its origin/HEAD may be stale", file=sys.stderr)

def planned(slug):
    # The story as the board PR merged it: the oldest commit on the board's default branch (first
    # parent, so a merged PR counts as its merge, and fetched first) that added the file; the board's
    # current text when git has no such commit.
    fetch(board)
    added = git(board, "log", default_ref(board), "--first-parent", "--diff-merges=first-parent", "--diff-filter=A",
                "--no-patch", "--format=%H", "--", f"stories/{slug}.md").split()
    if added:
        return git(board, "show", f"{added[-1]}:./stories/{slug}.md")
    path = os.path.join(board, "stories", f"{slug}.md")
    return open(path, encoding="utf-8", errors="replace").read() if os.path.exists(path) else ""

def planner_model(epic):
    # The model of the last agents.tsv lead whose session log names the epic's scope output
    # (.swarm/<epic>/lead.json, which plan-epic's brief gives it); only the model is kept.
    model = None
    for line in open(agents, errors="ignore") if epic else ():
        f = line.rstrip("\n").split("\t")
        if len(f) == 7 and f[1] == "lead":
            path = session_log(projects, f[6], archive)
            if path and any(f".swarm/{epic}/lead.json" in l for l in log_lines(path)):
                model = f[4]
    return model

def diff_of(repo, slug, epic, pr, merge_sha, heads):
    # (lines, files) of the PR on the default branch, fetched first: from gh's merge commit, a rebase
    # (the subjects of its last commits are the PR's commit headlines, heads, in order; gh cuts a long
    # headline and ends it with …) against the commit before them, a merge or a squash against its
    # first parent. When the merge commit is not on the branch, the commit whose subject is a squash's
    # `... (#N)` or a `Merge pull request #N`. The board's own files it changes (the story and its epic)
    # are not counted. (None, None) when git cannot find the commit or diff it (a shallow clone).
    fetch(repo)
    n = pr_key(pr).rpartition("#")[2]
    log = [(c.split("\x00") + ["", ""])[:3] for c in git(repo, "log", default_ref(repo), "--first-parent", "--format=%H%x00%s%x00%P").splitlines()]
    hit = [c for c in log if merge_sha and c[0] == merge_sha] or \
          [c for c in log if c[1].endswith(f"(#{n})") or c[1].startswith(f"Merge pull request #{n} ")]
    if not hit:
        return None, None
    sha, _, parents = hit[0]
    # Each commit's first line, as gh's headline is: %s would join a subject that runs over two lines.
    mine = [m.lstrip("\n").partition("\n")[0] for m in git(repo, "log", "--first-parent", f"-{len(heads)}", "--format=%B%x00", sha).split("\x00")[:-1]][::-1] if sha == merge_sha else []
    mine = [m.replace("\t", " ") for m in mine]
    rebased = len(heads) > 1 and len(parents.split()) == 1 and len(mine) == len(heads) and all(
        m == h or h.endswith("…") and m.startswith(h[:-1]) for m, h in zip(mine, heads))
    rel = os.path.relpath(os.path.realpath(board), os.path.realpath(git(repo, "rev-parse", "--show-toplevel").strip() or repo))
    own = {os.path.normpath(os.path.join(rel, p)) for p in [f"stories/{slug}.md"] + ([f"epics/{epic}.md"] if epic else [])}
    got = subprocess.run(["git", "-C", repo, "diff", "--numstat", "--no-renames", f"{sha}~{len(heads)}" if rebased else f"{sha}^", sha],
                         capture_output=True, text=True)
    if got.returncode != 0:
        return None, None
    stat = [l.split("\t") for l in got.stdout.splitlines()]
    stat = [s for s in stat if len(s) == 3 and os.path.normpath(s[2]) not in own]
    return sum(int(a) + int(d) for a, d, _ in stat if a.isdigit() and d.isdigit()), len(stat)

def escalations(slug):
    # Each ok escalate line of the slug: `ok (attempt N)`, or step-up's `ok (<trigger>: <from> -> <to>)`.
    got = []
    for line in open(events, errors="ignore") if os.path.exists(events) else ():
        f = line.rstrip("\n").split("\t")
        m = len(f) == 5 and f[1] == "escalate" and f[2] in (slug, agent_name(slug)) and re.fullmatch(r"ok \((.*)\)", f[4])
        if m:
            step = re.fullmatch(r"([^:]+): (\S+) -> (\S+)", m[1])
            got.append({"at": f[0], "trigger": step[1], "from": step[2], "to": step[3]} if step
                       else {"at": f[0], "trigger": m[1], "from": None, "to": None})
    return got

def started(build):
    # When a build started, as outcomes has it: its session log's first time, or with none 00:00 local
    # on its agents.tsv day.
    if build["started"]:
        return build["started"]
    try:
        return datetime.datetime.strptime(build["date"], "%Y-%m-%d").astimezone().isoformat()
    except ValueError:
        return ""

def minutes(start, end):
    # Whole minutes from start to end; None when either does not parse or end comes first.
    s, e = merge_time(start), merge_time(end)
    return round((e - s).total_seconds() / 60) if s and e and e >= s else None

def was_easy(builds, rounds, rework, lines):
    # Rule 1: one build, at most one findings round, no rework and a diff under EASY_MAX_LINES lines.
    # False once any known part fails it; None (unknown) when the rest pass but rework or the diff is
    # unknown.
    if builds != 1 or rounds > 1 or rework or (lines is not None and lines >= EASY_MAX_LINES):
        return False
    return None if rework is None or lines is None else True

def num(s):
    try:
        return float(s)
    except ValueError:
        return 0.0

def touch(e):
    r, f, fn = e
    return (f"{r}: " if r else "") + f + (f":{fn}" if fn else "")

lines = os.environ["SWARM_ROWS"].splitlines()
head = lines[0].split("\t") if lines else []
rows = [dict(zip(head, l.split("\t"))) for l in lines[1:]]
# slug, repo, then each merged PR of story/<slug> as gh lists it: url, mergedAt, merge commit, and its
# commit headlines joined by \x01 (gh's @tsv writes a backslash as two).
prs = {}
for f in (l.split("\t") for l in os.environ.get("SWARM_PRS", "").splitlines()):
    if len(f) == 6 and f[3]:
        heads = [h.replace("\\\\", "\\") for h in f[5].split("\x01")] if f[5] else []
        prs.setdefault(f[0], (f[1], []))[1].append((f[2], f[3], f[4], heads))
stories = {}
for slug, (repo, ps) in prs.items():
    builds = [r for r in rows if r["slug"] == slug]
    pr, merged_at, merge_sha, heads = max(ps, key=lambda p: p[1])
    text = planned(slug)
    fm = {k: v.strip() for k, v in front_text(text).items()}
    lines_n, files_n = diff_of(repo, slug, fm.get("epic", ""), pr, merge_sha, heads) if repo else (None, None)
    rounds = sum(int(r["tells_findings"] or 0) for r in builds)
    # outcomes' rework column, which model_fit reads too: true when any of its PRs was reworked, false
    # when every merged PR of the story was judged and none was, else null (gh could not judge one, it
    # merged within REWORK_DAYS of today, or outcomes gives no build its PR).
    judged = {pr_key(r["pr"]): r["rework"] for r in builds if r.get("rework") in ("0", "1")}
    rework = True if "1" in judged.values() else False if all(pr_key(p[0]) in judged for p in ps) else None
    est = fm.get("estimate_lines", "")
    stories[slug] = {
        "slug": slug,
        "inputs": {"text": text, "kind": fm.get("kind"), "risk": fm.get("risk"),
                   "touches": [touch(e) for e in entries(fm, project_dir, "")], "depends_on": sorted(deps(fm) - {""}),
                   "estimate_lines": int(est) if est.isdigit() else None,
                   "easy": {"true": True, "false": False}.get(fm.get("easy")), "planner_model": planner_model(fm.get("epic"))},
        "results": {
            "pr": pr, "merged_at": merged_at, "diff_lines": lines_n, "diff_files": files_n,
            "attempts": len(builds), "findings_rounds": rounds,
            "substantive_findings": sum(int(r["findings_fixed"] or 0) for r in builds), "rework": rework,
            "cost_usd": round(sum(num(r["cost_usd"]) + num(r.get("subagent_cost_usd", "")) for r in builds), 2),
            "minutes": minutes(started(builds[0]), merged_at) if builds else None,
            "models": list(dict.fromkeys(r["model"] for r in builds)), "escalations": escalations(slug),
        },
        "was_easy": was_easy(len(builds), rounds, rework, lines_n),
        "was_easy_rule": 1,
    }
# A finished story stays finished: a story this run could not read (its repo gone, or its builds no
# longer in agents.tsv) keeps its line from the last run, so the file never shrinks.
kept = 0
for line in open(out, encoding="utf-8", errors="replace") if os.path.exists(out) else ():
    try:
        old = json.loads(line)
        slug = old["slug"] if isinstance(old, dict) else None
    except (ValueError, KeyError):
        continue
    if isinstance(slug, str) and slug not in stories:
        stories[slug], kept = old, kept + 1
tmp = out + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    for s in sorted(stories.values(), key=lambda s: str((s.get("results") or {}).get("merged_at"))):
        f.write(json.dumps(s, sort_keys=True) + "\n")
os.replace(tmp, out)
print(f"wrote {len(stories)} stories to {out}" + (f" ({kept} kept from the last run)" if kept else ""))
