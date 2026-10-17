# CI health, a flow section (flow_report.py gives its globals): one TSV row for the project over the
# PRs of the outcomes rows dated in the window (with --epic, that epic's). gh gives each PR's commits
# and its branch's workflow runs; a run counts when its head is one of the PR's commits.
import datetime, json, re, statistics, subprocess
from report import *
RED = {"failure", "timed_out", "startup_failure"}

def gh(*args):
    # Its JSON, or None when gh fails or answers something else.
    got = subprocess.run(["gh", *args], capture_output=True, text=True)
    try:
        return json.loads(got.stdout) if got.returncode == 0 else None
    except ValueError:
        return None

def secs(t):
    return datetime.datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp()

def pr_runs(url):
    # The PR's completed runs, or None when gh cannot read them.
    pr = gh("pr", "view", url, "--json", "headRefName,commits")
    if pr is None:
        return None
    runs = gh("run", "list", "-R", re.search(r"github\.com/([^/]+/[^/]+)/pull/", url).group(1), "--branch", pr["headRefName"],
              "--limit", "200", "--json", "headSha,workflowName,status,conclusion,attempt,createdAt,updatedAt")
    shas = {c["oid"] for c in pr["commits"]}
    return None if runs is None else [r for r in runs if r["headSha"] in shas and r["status"] == "completed"]

def health(urls):
    heads, red, flakes = {}, 0, 0   # heads: sha -> [first created, last updated]
    for url in urls:
        runs = pr_runs(url)
        if runs is None:
            return None
        seen = {}   # (sha, workflow) -> True after a red attempt, until a green one
        for r in sorted(runs, key=lambda r: r["createdAt"]):
            span = heads.setdefault(r["headSha"], [secs(r["createdAt"]), 0])
            span[1] = max(span[1], secs(r["updatedAt"]))
            # gh lists a rerun's last attempt alone. ponytail: its earlier attempts count as red, as a
            # rerun follows a red one; read /attempts/<n> if a rerun of a green run ever shows up.
            for c in ["failure"] * (r["attempt"] - 1) + [r["conclusion"]]:
                key = (r["headSha"], r["workflowName"])
                if c == "success":
                    flakes += seen.pop(key, False)
                elif c in RED:
                    seen[key] = True
                    red += 1
    mins = [(e - s) / 60 for s, e in heads.values()]
    return [str(len(urls)), str(len(heads)), f"{statistics.median(mins):.1f}" if mins else "",
            f"{red / len(urls):.2f}" if urls else "", str(flakes)]

prs = {pr_key(r["pr"]): r["pr"] for r in rows
       if r["pr"].startswith("https://") and since <= r["date"] <= until and (not epic or r["epic"] == epic)}
got = health(sorted(prs.values()))
if got is None:
    print("ci health: gh failed")
else:
    print("prs\theads\tci_min_median\tred_runs_per_pr\tflakes")
    print("\t".join(got))
