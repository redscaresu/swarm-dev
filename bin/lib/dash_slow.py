import json, os, signal, subprocess, sys
FIELDS = "statusCheckRollup,mergeStateStatus,updatedAt,state"
def gh(args):
    p = subprocess.Popen(["gh"] + args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, start_new_session=True)
    try:
        out, _ = p.communicate(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid, signal.SIGKILL); p.communicate()
        return None
    return out if p.returncode == 0 else None
for url in sys.argv[1:]:
    out = gh(["pr", "view", url, "--json", FIELDS])
    if out is not None:
        print(url + "\t" + out.replace("\n", "").replace("\t", ""))
slugs = {}
for l in os.environ["SWARM_PAIRS"].splitlines():
    repo, _, slug = l.partition("\t")
    slugs.setdefault(repo, set()).add(slug)
for repo, mine in slugs.items():
    # The repo named from its origin, as nudge_reason names it, so an upstream remote never answers.
    origin = subprocess.run(["git", "-C", repo, "remote", "get-url", "origin"], capture_output=True, text=True).stdout.strip()
    # ponytail: only the newest 200 open PRs per repo are read, so a builder's older PR in a repo with
    # more shows as no PR yet; query each unmatched story/<slug> head if a repo ever has that many.
    try:
        prs = json.loads(gh(["pr", "list", "-R", origin, "--state", "open", "--limit", "200", "--json", "url,headRefName"]) or "[]") if origin else []
    except ValueError:
        continue
    for pr in prs if isinstance(prs, list) else []:
        head = str(pr.get("headRefName")) if isinstance(pr, dict) else ""
        if head.startswith("story/") and head[len("story/"):] in mine:
            print("head\t" + head[len("story/"):] + "\t" + pr["url"])
            # A PR a board item lists was viewed above.
            out = gh(["pr", "view", pr["url"], "--json", FIELDS]) if pr.get("url") not in sys.argv[1:] else None
            if out is not None:
                print(pr["url"] + "\t" + out.replace("\n", "").replace("\t", ""))
