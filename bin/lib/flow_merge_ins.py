# Merge-ins, a flow section (flow_report.py gives its globals): why the PRs epic_totals counts under
# main_merged (merged PRs of the outcomes rows dated in the window, or --epic's, whose main_merges is
# above 0; without --since, the 30 days up to --until or today, as each PR costs 2 gh calls) merged
# their base in. gh's REST API lists each PR's commits; a merge-in is one whose headline merges the base
# in, by outcomes' main_merges rule. git re-merges its two parents with merge-tree in its story's repo
# (SWARM_REPO_DIRS), fetching the PR's refs/pull/<n>/head from origin once when a merge-in is not there:
# conflict when they conflict, or when the commit's tree is not git's clean merge (a hand fix); behind
# when they merge clean and the base had commits the branch lacked; neither when it had none. unread
# counts the rest: a PR gh could not read, the merge-ins main_merges counted that gh does not list, a
# commit git cannot find, and a one-parent "merge" (a squash, a rebase); a `merge ins: left out <url>:
# <why>` line names each. TSV cause merge_ins prs, then, after a blank line, file conflicts: the three
# files conflicts hit most.
import collections, datetime, os, subprocess
from report import *

DAYS = 30
CAUSES = ("conflict", "behind", "neither", "unread")
project = os.path.dirname(os.path.dirname(events))   # events is <project>/.swarm/events.tsv
repos = {s: d.strip() for s, _, d in (l.partition("\t") for l in os.environ.get("SWARM_REPO_DIRS", "").splitlines())}

def git(root, *args):
    return subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)

def said(got):
    lines = [l.strip() for l in got.stderr.splitlines() if l.strip()]
    return lines[-1] if lines else f"exit {got.returncode}"

def base_merge(headline, base):
    # outcomes' jq base_merge: `Merge origin/main into x`, `Merge branch 'main' into x`, `Merge
    # remote-tracking branch 'origin/main' into x`.
    if not headline.startswith("Merge "):
        return False
    name = headline[len("Merge "):].removeprefix("remote-tracking ").removeprefix("branch ").split(" ")[0]
    return name.removeprefix("'").removesuffix("'").removeprefix("origin/") == base

def merge_ins(repo, n):
    # The oids of PR n's merge-ins, or None when gh fails (ERROR says why).
    pr = gh("api", f"repos/{repo}/pulls/{n}")
    if not isinstance(pr, dict) or not isinstance(pr.get("base"), dict):
        return None
    pages = gh("api", "--paginate", "--slurp", f"repos/{repo}/pulls/{n}/commits?per_page=100")
    try:
        return [c["sha"] for page in pages for c in page if base_merge(c["commit"]["message"].split("\n")[0], pr["base"].get("ref"))]
    except (TypeError, KeyError, AttributeError):
        return None

def missing(root, oid, n, fetched):
    # Why oid is not in root, fetching PR n's head from origin once first; None once it is there.
    if git(root, "cat-file", "-e", f"{oid}^{{commit}}").returncode == 0:
        return None
    if n not in fetched:
        got = git(root, "fetch", "-q", "--no-write-fetch-head", "origin", f"refs/pull/{n}/head")
        fetched[n] = "" if got.returncode == 0 else f": git fetch origin refs/pull/{n}/head: {said(got)}"
        if not fetched[n] and git(root, "cat-file", "-e", f"{oid}^{{commit}}").returncode == 0:
            return None
    return f"{oid[:12]}: not in {root}{fetched[n]}"

def cause(root, oid):
    # (cause, files, why unread) of one merge-in: its first parent is the branch, its second the base.
    got = git(root, "log", "-1", "--format=%T %P", oid)
    if got.returncode:
        return "unread", [], f"{oid[:12]}: git log: {said(got)}"
    tree, *parents = got.stdout.split()
    if len(parents) != 2:   # a headline that says merge on a commit that is not one (a squash, a rebase)
        return "unread", [], f"{oid[:12]}: {len(parents)} parent(s), not a merge of two"
    ours, base = parents
    merged = git(root, "merge-tree", "--write-tree", "--name-only", "--no-messages", "-z", ours, base)
    if merged.returncode == 1:
        return "conflict", sorted(set(f for f in merged.stdout.split("\0")[1:] if f)), ""
    if merged.returncode:
        return "unread", [], f"{oid[:12]}: git merge-tree: {said(merged)}"
    clean = merged.stdout.split("\0")[0].strip()
    if clean != tree:   # git merged it clean, and the builder changed the result before committing
        return "conflict", sorted(f for f in git(root, "diff", "--name-only", "-z", clean, tree).stdout.split("\0") if f), ""
    ancestor = git(root, "merge-base", "--is-ancestor", base, ours)
    if ancestor.returncode in (0, 1):
        return ("neither", "behind")[ancestor.returncode], [], ""
    return "unread", [], f"{oid[:12]}: git merge-base: {said(ancestor)}"

end = datetime.date.today() if until == "9999-12-30" else datetime.date.fromisoformat(until)
if since == "0000-00-00":
    since = (end - datetime.timedelta(days=DAYS)).isoformat()
    print(f"PRs from the last {DAYS} days, {since} on; --since sets the start")
prs = {pr_key(r["pr"]): r for r in rows if r["pr"] and since <= r["date"] <= until and (not epic or r["epic"] == epic)
       and (r["pr_state"] == "MERGED" or r["merged_at"]) and r["main_merges"].isdigit() and int(r["main_merges"]) > 0}
counts, by_cause, files, why = collections.Counter(), collections.defaultdict(set), collections.Counter(), []

def tally(key, url, c, n=1, conflicted=(), reason=""):
    counts[c] += n
    by_cause[c].add(key)
    files.update(conflicted)
    if reason:
        why.append(f"merge ins: left out {url}: {CONTROL.sub('', reason)}")

for key, r in sorted(prs.items()):
    url, want, root, n = r["pr"], int(r["main_merges"]), repos.get(r["slug"]) or project, key.rpartition("#")[2]
    m = GITHUB.match(url)
    if root.startswith("!"):
        tally(key, url, "unread", want, reason=f"its story's repo: {root[1:]}")
        continue
    oids = merge_ins(m.group(1), n) if m else None
    if oids is None:
        tally(key, url, "unread", want, reason=ERROR[0] if m else "not a github.com PR")
        continue
    if len(oids) < want:
        tally(key, url, "unread", want - len(oids), reason=f"gh lists {len(oids)} of the {want} merge-ins outcomes counted")
    fetched = {}
    for oid in oids:
        gone = missing(root, oid, n, fetched)
        c, conflicted, reason = ("unread", [], gone) if gone else cause(root, oid)
        tally(key, url, c, conflicted=conflicted, reason=reason)

print("cause\tmerge_ins\tprs")
for c in CAUSES:
    print(f"{c}\t{counts[c]}\t{len(by_cause[c])}")
print("\nfile\tconflicts" if files else "\nnone conflicted")
for f, k in sorted(files.items(), key=lambda x: (-x[1], x[0]))[:3]:
    print(f"{f}\t{k}")
if why:
    print("\n".join(why))
