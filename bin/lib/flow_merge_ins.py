# Merge-ins, a flow section (flow_report.py gives its globals): why the PRs epic_totals counts under
# main_merged (merged PRs of the outcomes rows dated in the window, or --epic's, whose main_merges is
# above 0) merged their base in. gh's REST API lists each PR's commits; a merge-in is one whose headline merges the
# base in, by outcomes' main_merges rule. git re-merges its two parents with merge-tree in the project's
# repo: conflict when they conflict, behind when they merge clean and the base had commits the branch
# lacked, neither when it had none. unread counts the merge-ins of a PR gh could not read, and those
# whose commit is not in the repo. TSV cause merge_ins prs, then, after a blank line, file conflicts:
# the three files conflicts hit most.
import collections, json, os, re, subprocess
from report import pr_key

GH_SECONDS = 30
CAUSES = ("conflict", "behind", "neither", "unread")
root = os.path.dirname(os.path.dirname(events))   # events is <project>/.swarm/events.tsv

def git(*args):
    return subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)

def base_merge(headline, base):
    # outcomes' jq base_merge: `Merge origin/main into x`, `Merge branch 'main' into x`, `Merge
    # remote-tracking branch 'origin/main' into x`.
    if not headline.startswith("Merge "):
        return False
    name = headline[len("Merge "):].removeprefix("remote-tracking ").removeprefix("branch ").split(" ")[0]
    return name.removeprefix("'").removesuffix("'").removeprefix("origin/") == base

def cause(oid):
    # (cause, conflicted files) of one merge-in: its first parent is the branch, its second the base.
    parents = git("rev-parse", f"{oid}^1", f"{oid}^2")
    if parents.returncode:
        return "unread", []
    ours, base = parents.stdout.split()
    merged = git("merge-tree", "--write-tree", "--name-only", "--no-messages", "-z", ours, base)
    if merged.returncode == 1:
        return "conflict", sorted(set(f for f in merged.stdout.split("\0")[1:] if f))
    if merged.returncode:
        return "unread", []
    return ("neither" if git("merge-base", "--is-ancestor", base, ours).returncode == 0 else "behind"), []

def gh(path):
    # gh api's JSON for path, or None when gh fails. REST, not GraphQL, whose hourly budget runs out first.
    try:
        got = subprocess.run(["gh", "api", "--paginate", "--slurp", path], capture_output=True, text=True, timeout=GH_SECONDS)
        return json.loads(got.stdout) if got.returncode == 0 else None
    except (subprocess.TimeoutExpired, ValueError, OSError):   # OSError: no gh on PATH
        return None

def merge_ins(url):
    # The oids of a PR's merge-ins, or None when gh fails.
    m = re.search(r"github\.com/([^/]+/[^/]+)/pull/(\d+)", url)
    if not m:
        return None
    pr, pages = gh(f"repos/{m.group(1)}/pulls/{m.group(2)}"), gh(f"repos/{m.group(1)}/pulls/{m.group(2)}/commits?per_page=100")
    try:
        base = pr[0]["base"]["ref"]
        return [c["sha"] for page in pages for c in page if base_merge(c["commit"]["message"].split("\n")[0], base)]
    except (TypeError, KeyError, IndexError, AttributeError):
        return None

prs = {pr_key(r["pr"]): r for r in rows if r["pr"] and since <= r["date"] <= until and (not epic or r["epic"] == epic)
       and (r["pr_state"] == "MERGED" or r["merged_at"]) and r["main_merges"].isdigit() and int(r["main_merges"]) > 0}
counts, by_cause, files = collections.Counter(), collections.defaultdict(set), collections.Counter()
for key, r in sorted(prs.items()):
    oids = merge_ins(r["pr"])
    for c, conflicted in [cause(o) for o in oids] if oids is not None else [("unread", [])] * int(r["main_merges"]):
        counts[c] += 1
        by_cause[c].add(key)
        files.update(conflicted)
print("cause\tmerge_ins\tprs")
for c in CAUSES:
    print(f"{c}\t{counts[c]}\t{len(by_cause[c])}")
print("\nfile\tconflicts")
for f, n in sorted(files.items(), key=lambda x: (-x[1], x[0]))[:3]:
    print(f"{f}\t{n}")
