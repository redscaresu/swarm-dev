# CI health, a flow section (flow_report.py gives its globals): one TSV row for the project over the
# PRs of the outcomes rows dated in the window (with --epic, that epic's). gh gives each PR's commits
# and its branch's workflow runs; a run counts when its head is one of the PR's commits.
import datetime, json, re, statistics, subprocess
from report import *
RED = {"failure", "timed_out"}   # never cancelled or skipped
GITHUB = re.compile(r"https://github\.com/([^/]+/[^/]+)/pull/\d+")

def gh(*args):
    # Its JSON, or None when gh fails or answers something else.
    got = subprocess.run(["gh", *args], capture_output=True, text=True)
    try:
        return json.loads(got.stdout) if got.returncode == 0 else None
    except ValueError:
        return None

def secs(t):
    # A time in epoch seconds; None when it does not parse.
    try:
        return datetime.datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp()
    except (ValueError, AttributeError):
        return None

def pr_runs(url):
    # The PR's completed runs, each with its conclusions first attempt first (gh run list gives a
    # rerun's last attempt alone, so the earlier ones come from /attempts/<n>), or None when gh cannot
    # read them.
    repo = GITHUB.match(url).group(1)
    pr = gh("pr", "view", url, "--json", "headRefName,commits")
    runs = pr and gh("run", "list", "-R", repo, "--branch", pr["headRefName"], "--limit", "200", "--json",
                     "databaseId,headSha,workflowName,event,status,conclusion,attempt,createdAt,updatedAt")
    if runs is None:
        return None
    shas = {c["oid"] for c in pr["commits"]}
    runs = [r for r in runs if r["headSha"] in shas and r["status"] == "completed"]
    for r in runs:
        earlier = [gh("api", f"repos/{repo}/actions/runs/{r['databaseId']}/attempts/{n}") for n in range(1, r["attempt"])]
        if None in earlier:
            return None
        r["conclusions"] = [a["conclusion"] for a in earlier] + [r["conclusion"]]
    return runs

def health(urls):
    heads, red, flakes = {}, 0, 0   # heads: sha -> the (created, updated) of its runs whose times parse
    for url in urls:
        runs = pr_runs(url)
        if runs is None:
            return None
        seen = set()   # (sha, workflow, event) after a red attempt, until a green one
        for r in sorted(runs, key=lambda r: r["createdAt"]):
            span = (secs(r["createdAt"]), secs(r["updatedAt"]))
            heads.setdefault(r["headSha"], []).extend([span] if None not in span else [])
            key = (r["headSha"], r["workflowName"], r["event"])
            for c in r["conclusions"]:
                if c == "success" and key in seen:
                    seen.discard(key)
                    flakes += 1
                elif c in RED:
                    seen.add(key)
                    red += 1
    mins = [(max(e for _, e in t) - min(s for s, _ in t)) / 60 for t in heads.values() if t]
    return [str(len(urls)), str(len(heads)), f"{statistics.median(mins):.1f}" if mins else "",
            f"{red / len(urls):.2f}" if urls else "", str(flakes)]

# A PR URL off github.com (Enterprise, or written by hand) is left out: gh run list needs its repo.
prs = {pr_key(r["pr"]): r["pr"] for r in rows
       if GITHUB.match(r["pr"]) and since <= r["date"] <= until and (not epic or r["epic"] == epic)}
got = health(sorted(prs.values()))
if got is None:
    print("ci health: gh failed")
else:
    print("prs\theads\tci_min_median\tred_runs_per_pr\tflakes")
    print("\t".join(got))
