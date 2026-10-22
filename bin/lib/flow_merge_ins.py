# Merge-ins, a flow section (flow_report.py gives its globals): why the PRs epic_totals counts under
# main_merged (the outcomes rows dated in the window, or --epic's, one per PR by pr_key, the last; of
# those, the merged PRs whose main_merges is above 0) merged their base in. Without --since or --epic,
# the window is the 30 days up to --until or today, as each PR costs 2 gh calls. gh's REST API lists each
# PR's commits; a merge-in is one whose headline merges the base in, by outcomes' main_merges rule. git
# re-merges its two parents with merge-tree in its story's repo (SWARM_REPO_DIRS), fetching the PR's
# refs/pull/<n>/head once when a merge-in is not there and origin is the PR's repo (a `merge ins: fetched`
# line says so); every git call runs with no prompt and a time limit (report.quiet_git):
# conflict when they conflict, or when the commit's tree differs from git's clean merge on a path the
# PR changes against the base (a hand fix; a difference elsewhere is another merge strategy); behind
# when they merge clean and the base had commits the branch lacked; neither when it had none. unread
# counts the rest: a PR gh could not read, the merge-ins main_merges counted that gh does not list, a
# sha or commit git cannot read, a merge-in whose git log, merge-tree, diff or merge-base fails, and a
# one-parent "merge" (a squash, a rebase); a `merge ins: left out <url>: <why>` line names each. TSV
# cause merge_ins prs, then, after a blank line, file conflicts: the three files conflicts hit most; or
# none conflicted, or none read when it read no merge-in.
import collections, datetime, os, re
from report import *
from gh_cache import commits, pull

DAYS = 30
CAUSES = ("conflict", "behind", "neither", "unread")
SHA = re.compile(r"[0-9a-f]{40}")   # a fork's PR is not ours to pass to git as an option
project = os.path.dirname(os.path.dirname(events))   # events is <project>/.swarm/events.tsv
repos = {s: d.strip() for s, _, d in (l.partition("\t") for l in os.environ.get("SWARM_REPO_DIRS", "").splitlines())}

git = quiet_git
ORIGIN = re.compile(r"(?:https://|ssh://git@|git@)github\.com[/:]([^/]+/[^/]+?)(?:\.git)?/?")

def origin(root):
    # owner/repo of root's origin on github.com, lowercase; "" for any other origin.
    m = ORIGIN.fullmatch(git(root, "config", "--get", "remote.origin.url").stdout.strip())
    return m.group(1).lower() if m else ""

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

def names(got):
    # The paths a -z --name-only git call printed, or None when it failed (an empty list is no paths).
    return None if got.returncode else sorted(f for f in got.stdout.split("\0") if f)

def merge_ins(repo, n):
    # The shas of PR n's merge-ins and "", or None and why gh's answer cannot be read.
    pr = pull(repo, n, gh)
    if pr is None:
        return None, ERROR[0]
    base = pr.get("base") if isinstance(pr, dict) else None
    if not isinstance(base, dict) or not isinstance(base.get("ref"), str):
        return None, f"gh api repos/{repo}/pulls/{n}: an answer with no base branch"
    pages = commits(repo, n, pr, gh)
    try:
        return [c["sha"] for page in pages for c in page if base_merge(c["commit"]["message"].split("\n")[0], base["ref"])], ""
    except (TypeError, KeyError, AttributeError):
        return None, ERROR[0]

def missing(root, oid, n, fetched):
    # Why oid is not in root, fetching PR n's head from origin once first; None once it is there.
    if git(root, "cat-file", "-e", "--end-of-options", f"{oid}^{{commit}}").returncode == 0:
        return None
    if n not in fetched:
        failed = git_fetch(root, "--no-write-fetch-head", "origin", f"refs/pull/{n}/head")
        fetched[n] = failed and f": git fetch origin refs/pull/{n}/head: {failed}"
        if not failed:
            notes.append(f"merge ins: fetched refs/pull/{n}/head into {root}")
            if git(root, "cat-file", "-e", "--end-of-options", f"{oid}^{{commit}}").returncode == 0:
                return None
    return f"{oid[:12]}: not in {root}{fetched[n]}"

def cause(root, oid):
    # (cause, files, why unread) of one merge-in: its first parent is the branch, its second the base.
    got = git(root, "log", "-1", "--format=%T %P", "--end-of-options", oid)
    if got.returncode:
        return "unread", [], f"{oid[:12]}: git log: {said(got)}"
    tree, *parents = got.stdout.split()
    if len(parents) != 2:   # a headline that says merge on a commit that is not one (a squash, a rebase)
        return "unread", [], f"{oid[:12]}: {len(parents)} parent(s), not a merge of two"
    ours, base = parents
    merged = git(root, "merge-tree", "--write-tree", "--name-only", "--no-messages", "-z", "--end-of-options", ours, base)
    if merged.returncode == 1:
        return "conflict", sorted(set(f for f in merged.stdout.split("\0")[1:] if f)), ""
    if merged.returncode:
        return "unread", [], f"{oid[:12]}: git merge-tree: {said(merged)}"
    clean = merged.stdout.split("\0")[0].strip()
    if clean != tree:
        # git merged it clean and the commit differs. On a path the PR changes against the base, the
        # builder changed the result before committing; elsewhere it is another strategy's clean merge.
        diff = ("diff", "--name-only", "--no-renames", "-z", "--end-of-options")
        fixed = None
        for side in (clean, base):   # the first failure stops it: a timed-out diff costs one limit
            got = git(root, *diff, side, tree)
            paths = names(got)
            if paths is None:
                return "unread", [], f"{oid[:12]}: git diff: {said(got)}"
            fixed = set(paths) if fixed is None else fixed & set(paths)
        if fixed:
            return "conflict", sorted(fixed), ""
    ancestor = git(root, "merge-base", "--is-ancestor", "--end-of-options", base, ours)
    if ancestor.returncode in (0, 1):
        return ("neither", "behind")[ancestor.returncode], [], ""
    return "unread", [], f"{oid[:12]}: git merge-base: {said(ancestor)}"

end = datetime.date.today() if until == "9999-12-30" else datetime.date.fromisoformat(until)
if since == "0000-00-00" and not epic:
    since = (end - datetime.timedelta(days=DAYS)).isoformat()
    print(f"PRs from the last {DAYS} days, {since} on; --since sets the start")
last = {pr_key(r["pr"]): r for r in rows if r["pr"] and since <= r["date"] <= until and (not epic or r["epic"] == epic)}
prs = {k: r for k, r in last.items() if (r["pr_state"] == "MERGED" or r["merged_at"]) and r["main_merges"].isdigit() and int(r["main_merges"]) > 0}
counts, by_cause, files, notes = collections.Counter(), collections.defaultdict(set), collections.Counter(), []

def tally(key, url, c, n=1, conflicted=(), reason=""):
    counts[c] += n
    by_cause[c].add(key)
    files.update(CONTROL.sub("", f) for f in conflicted)   # a fork names its files
    if reason:
        notes.append(f"merge ins: left out {url}: {CONTROL.sub('', reason)}")

for key, r in sorted(prs.items()):
    url, want, root, n = r["pr"], int(r["main_merges"]), repos.get(r["slug"]) or project, key.rpartition("#")[2]
    m = GITHUB.match(url)
    if root.startswith("!"):
        tally(key, url, "unread", want, reason=f"its story's repo: {root[1:]}")
        continue
    oids, failed = merge_ins(m.group(1), n) if m else (None, "not a github.com PR")
    if oids is None:
        tally(key, url, "unread", want, reason=failed)
        continue
    if len(oids) < want:
        tally(key, url, "unread", want - len(oids), reason=f"gh lists {len(oids)} of the {want} merge-ins outcomes counted")
    # A fork's or another repo's origin has no refs/pull/<n>/head of this PR: never fetch from it.
    fetched = {} if origin(root) == m.group(1).lower() else {n: f": its origin is not github.com/{m.group(1)}"}
    for oid in oids:
        if not isinstance(oid, str) or not SHA.fullmatch(oid):
            tally(key, url, "unread", reason=f"gh gives {str(oid)[:40]!r} as a merge-in's sha")
            continue
        gone = missing(root, oid, n, fetched)
        c, conflicted, reason = ("unread", [], gone) if gone else cause(root, oid)
        tally(key, url, c, conflicted=conflicted, reason=reason)

print("cause\tmerge_ins\tprs")
for c in CAUSES:
    print(f"{c}\t{counts[c]}\t{len(by_cause[c])}")
print("\nfile\tconflicts" if files else "\nnone conflicted" if counts["conflict"] + counts["behind"] + counts["neither"] else "\nnone read")
for f, k in sorted(files.items(), key=lambda x: (-x[1], x[0]))[:3]:
    print(f"{f}\t{k}")
if notes:
    print("\n".join(notes))
