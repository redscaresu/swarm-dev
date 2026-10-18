import datetime, json, os, re, subprocess, sys
from report import *
board, agents, events, findings, projects, archive, out = sys.argv[1:8]
EASY_MAX_LINES = 100   # was_easy rule 1: a diff under this many lines

def git(repo, *args):
    got = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    return got.stdout if got.returncode == 0 else ""

def front(text):
    # A story's frontmatter as {key: value}, the values as written.
    m = re.match(r"---\n(.*?)\n---", text, re.S)
    return dict(re.findall(r"(?m)^([a-z_]+): *(.*?) *$", m[1])) if m else {}

def listed(v):
    return [x.strip().strip("\"'") for x in (v or "").strip("[]").split(",") if x.strip()]

def planned(slug):
    # The story as the board PR that added it wrote it (the oldest commit adding the file); the
    # board's current text when git has no add.
    added = git(board, "log", "--diff-filter=A", "--format=%H", "--", f"stories/{slug}.md").split()
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

def diff_of(repo, slug, pr):
    # (lines, files, later commits as (ISO time, message)) of the PR's commit on the default branch:
    # a squash `... (#N)` or a `Merge pull request #N ...`. The story file it deletes is not counted.
    n = pr_key(pr).rpartition("#")[2]
    ref = "origin/HEAD" if git(repo, "rev-parse", "-q", "--verify", "origin/HEAD") else "HEAD"
    log = git(repo, "log", ref, "--first-parent", "--format=%H%x00%cI%x00%s%x00%B%x01").split("\x01")
    for i, c in enumerate(log):
        sha, _, subject, _ = (c.lstrip("\n").split("\x00") + ["", "", ""])[:4]
        if subject.endswith(f"(#{n})") or subject.startswith(f"Merge pull request #{n} "):
            stat = [l.split("\t") for l in git(repo, "diff", "--numstat", f"{sha}^", sha).splitlines()]
            stat = [s for s in stat if len(s) == 3 and not s[2].endswith(f"stories/{slug}.md")]
            lines = sum(int(a) + int(d) for a, d, _ in stat if a.isdigit() and d.isdigit())
            later = [tuple(c.lstrip("\n").split("\x00")[1:4:2]) for c in log[:i] if "\x00" in c]
            return lines, len(stat), later
    return None, None, []

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

def minutes(start, end):
    try:
        t = lambda s: datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
        return round((t(end) - t(start)) / 60)
    except (ValueError, AttributeError):
        return None

def num(s):
    try:
        return float(s)
    except ValueError:
        return 0.0

lines = os.environ["SWARM_ROWS"].splitlines()
head = lines[0].split("\t") if lines else []
rows = [dict(zip(head, l.split("\t"))) for l in lines[1:]]
repos = dict(l.split("\t", 1) for l in os.environ.get("SWARM_REPOS", "").splitlines() if "\t" in l)
escaped = finding_rows(findings, ("escaped",))
stories = []
for slug in dict.fromkeys(r["slug"] for r in rows if r.get("story_merged") == "true"):
    builds = [r for r in rows if r["slug"] == slug]
    merged = [r for r in builds if r.get("merged_at")]
    if not merged:
        continue
    pr, merged_at = merged[-1]["pr"], merged[-1]["merged_at"]
    text = planned(slug)
    fm = front(text)
    lines_n, files_n, later = diff_of(repos[slug], slug, pr) if repos.get(slug) else (None, None, [])
    rounds = sum(int(r["tells_findings"] or 0) for r in builds)
    rework = rework_of(pr, merged_at, later, escaped)
    est = fm.get("estimate_lines", "")
    results = {
        "pr": pr, "merged_at": merged_at, "diff_lines": lines_n, "diff_files": files_n,
        "attempts": len(builds), "findings_rounds": rounds,
        "substantive_findings": sum(int(r["findings_fixed"] or 0) for r in builds), "rework": rework,
        "cost_usd": round(sum(num(r["cost_usd"]) + num(r.get("subagent_cost_usd", "")) for r in builds), 2),
        "minutes": minutes(builds[0]["started"], merged_at),
        "models": list(dict.fromkeys(r["model"] for r in builds)), "escalations": escalations(slug),
    }
    stories.append({
        "slug": slug,
        "inputs": {"text": text, "kind": fm.get("kind"), "risk": fm.get("risk"), "touches": listed(fm.get("touches")),
                   "depends_on": listed(fm.get("depends_on")), "estimate_lines": int(est) if est.isdigit() else None,
                   "easy": {"true": True, "false": False}.get(fm.get("easy")), "planner_model": planner_model(fm.get("epic"))},
        "results": results,
        "was_easy": len(builds) == 1 and rounds <= 1 and not rework and lines_n is not None and lines_n < EASY_MAX_LINES,
        "was_easy_rule": 1,
    })
tmp = out + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    for s in sorted(stories, key=lambda s: s["results"]["merged_at"]):
        f.write(json.dumps(s, sort_keys=True) + "\n")
os.replace(tmp, out)
print(f"wrote {len(stories)} stories to {out}")
