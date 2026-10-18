# Model fit, a flow section (flow_report.py gives its globals): cost against effectiveness, one TSV row
# per model and effort crossed with a story class (kind, risk, size and area), over the stories whose
# first build is dated in the window (with --epic, that epic's). A story counts under the model and
# effort of its first build, so an escalation to Fable stays under the model it started on; its cost,
# attempts and findings are those of all its builds. size buckets its estimate_lines and area is the
# top-level directory most of its touches name, both read through story_text (flow_sections), so a
# merged story keeps its class. Rework is report.py's rework_of over every merged PR of the rows'
# repos, from gh; when gh fails, only escaped findings mark rework, and a line says so. A cell under
# MIN_STORIES stories prints its count alone. After a blank line, a subagent row per model and effort
# of the builds whose subagents cost more than zero: their cost and its share of build cost (own and theirs).
import collections, datetime, json, os, re, subprocess
from report import *
from touches_rows import entries as touches_entries
MIN_STORIES = 5
AREAS = ("bin", "commands", "docs", "tests")
GH_SECONDS = 30
GH_LIMIT = 1000
project_dir = os.path.dirname(os.path.dirname(findings))
GITHUB = re.compile(r"https://github\.com/([^/]+/[^/]+)/pull/\d+")

def num(x):
    try:
        return float(x)
    except ValueError:
        return 0.0

def size(lines):
    try:
        n = int(lines)
    except ValueError:
        return "none"
    return "<=100" if n <= 100 else "<=300" if n <= 300 else ">300"

def area(touches):
    # The most named top-level area, the first named on a tie; other for a file outside AREAS, none for no
    # touches. The files are touches_rows.py's, so a bare name after a file (g in `bin/x.sh:f, g`) is
    # a function unless the project has a file by that name (Makefile). The project is the findings
    # log's (<project>/.swarm/<log>); a file in another repo is read under no repos_dir, as a function.
    # Each file counts once, however many of its functions follow it.
    tops = [f.split("/") for f in dict.fromkeys(f for _, f, _ in touches_entries({"touches": touches}, project_dir, ""))]
    tops = [f"{p[0]}/" if len(p) > 1 and p[0] in AREAS else "other" for p in tops]
    return collections.Counter(tops).most_common(1)[0][0] if tops else "none"

def minutes(start, end):
    try:
        t = lambda s: datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
        return (t(end) - t(start)) / 60
    except ValueError:
        return None

def merged_range(first_day, last_merge):
    # gh's merged: qualifier for the PRs that can be counted or fix one that is: from REWORK_DAYS before
    # --since (without it, from first_day, the earliest counted build's) to REWORK_DAYS after --until or
    # last_merge, the latest counted merge day, whichever is later, as a story built in the window can
    # merge after it (without --until, open-ended).
    days = datetime.timedelta(days=REWORK_DAYS)
    lo = datetime.date.fromisoformat(since) - days if since != "0000-00-00" else datetime.date.fromisoformat(first_day)
    hi = datetime.date.fromisoformat(max(until, last_merge)) + days if until != "9999-12-30" else None
    return f"merged:{lo}..{hi}" if hi else f"merged:>={lo}"

def merged_prs(urls, search):
    # pr_key -> (mergedAt, title and body, paths changed) for every merged PR of the repos the urls are
    # in that gh's search (merged_range) finds, or None when gh fails. A list that comes back GH_LIMIT
    # long prints that rework may be undercounted. files is read for rework_of's release PRs.
    # ponytail: the last GH_LIMIT merged PRs per repo; page with gh api if a repo outgrows that within the window.
    out = {}
    for repo in sorted({m.group(1) for u in urls for m in [GITHUB.match(u)] if m}):
        try:
            got = subprocess.run(["gh", "pr", "list", "-R", repo, "--state", "merged", "--limit", str(GH_LIMIT),
                                  "--json", "url,mergedAt,title,body,files", "--search", search], capture_output=True, text=True, timeout=GH_SECONDS)
            prs = json.loads(got.stdout) if got.returncode == 0 else None
        except (subprocess.TimeoutExpired, ValueError, OSError):   # OSError: no gh on PATH
            prs = None
        if not isinstance(prs, list):
            return None
        if len(prs) >= GH_LIMIT:
            print(f"rework: gh listed {GH_LIMIT} merged PRs of {repo}, its limit, so rework may be undercounted.")
        out.update({pr_key(p["url"]): (p.get("mergedAt") or "", f"{p.get('title') or ''}\n{p.get('body') or ''}",
                                       sorted(f.get("path", "") for f in p.get("files") or [])) for p in prs})
    return out

by_slug = collections.defaultdict(list)
for r in rows:
    by_slug[r["slug"]].append(r)
counted = {}
for slug, rs in by_slug.items():
    first = min(rs, key=lambda r: num(r["attempts"]))
    if since <= first["date"] <= until and (not epic or first["epic"] == epic):
        counted[slug] = (first, rs)

prs = {r["pr"] for _, rs in counted.values() for r in rs if r["pr"]}
last_merge = max((r["merged_at"][:10] for _, rs in counted.values() for r in rs if re.match(r"\d{4}-\d\d-\d\d", r["merged_at"])), default="")
merged = merged_prs(prs, merged_range(min(f["date"] for f, _ in counted.values()), last_merge)) if prs else {}
gh_failed = merged is None
merged = merged or {}
for _, rs in counted.values():
    for r in rs:
        if r["pr"] and r["merged_at"]:
            merged.setdefault(pr_key(r["pr"]), (r["merged_at"], "", None))
escapes = finding_rows(findings, ("escaped",))
rework = rework_of(merged, escapes)
escaped = collections.Counter(pr_key(f[2]) for f in escapes)

cells = collections.defaultdict(list)
for slug, (first, rs) in counted.items():
    lines, touches = stories.get(slug, ("", ""))
    cells[(first["model"], first["effort"], first["kind"] or "-", first["risk"] or "-", size(lines), area(touches))].append((first, rs))

def cell(entries):
    out = [str(len(entries))]
    if len(entries) < MIN_STORIES:
        return out + ["-"] * 7
    keys = {pr_key(r["pr"]) for _, rs in entries for r in rs if r["pr"]}
    done = [(first, rs) for first, rs in entries if any(r["story_merged"] == "true" for r in rs)]
    # story_merged is empty when outcomes could not ask gh, and a story with no merge and an open PR is
    # still in flight: either is left out of the rate.
    known = [rs for _, rs in entries if any(r["story_merged"] for r in rs)
             and (any(r["story_merged"] == "true" for r in rs) or not any(r["pr_state"] == "OPEN" for r in rs))]
    cost = sum(num(r["cost_usd"]) + num(r["subagent_cost_usd"]) for _, rs in entries for r in rs)
    # A story can have merged on a PR no build of it named, so with no merged_at: it adds no wait.
    ends = [(first["started"], min(r["merged_at"] for r in rs if r["merged_at"])) for first, rs in done if any(r["merged_at"] for r in rs)]
    waits = [m for start, end in ends if start for m in [minutes(start, end)] if m is not None]
    reworked = sum(1 for _, rs in entries if any(r["pr"] and pr_key(r["pr"]) in rework for r in rs))
    # As epic_totals: a build with no cost (no session log, a codex agent) is named, never counted as free.
    missing = sum(1 for _, rs in entries for r in rs if not r["cost_usd"])
    return out + [(f"{cost / len(done):.2f}" + (f" ({missing} not in the logs)" if missing else "")) if done else "-",
                  f"{100 * sum(1 for _, rs in done if len(rs) == 1) / len(known):.0f}%" if known else "-",
                  f"{sum(len(rs) for _, rs in entries) / len(entries):.1f}",
                  f"{sum(num(r['findings_fixed']) for _, rs in entries for r in rs) / len(keys):.1f}" if keys else "-",
                  str(reworked), str(sum(escaped[k] for k in keys)),
                  f"{sum(waits) / len(waits):.0f}" if waits else "-"]

print("model\teffort\tkind\trisk\tsize\tarea\tstories\tcost_per_merged_usd\tfirst_attempt_merge_rate\tmean_attempts"
      "\tfindings_per_pr\trework\tescaped\tstart_to_merge_min")
for key in sorted(cells):
    print("\t".join(list(key) + cell(cells[key])))

subs = collections.defaultdict(lambda: [0.0, 0.0])
for _, rs in counted.values():
    for r in rs:
        if num(r["subagent_cost_usd"]) > 0:   # outcomes writes 0.00 for every build with a session log
            s = subs[(r["model"], r["effort"])]
            s[0] += num(r["subagent_cost_usd"])
            s[1] += num(r["subagent_cost_usd"]) + num(r["cost_usd"])
print("\nsubagents\teffort\tsubagent_cost_usd\tbuild_cost_usd\tsubagent_share")
for (model, effort), (sub, total) in sorted(subs.items()):
    print("\t".join([model, effort, f"{sub:.2f}", f"{total:.2f}", f"{100 * sub / total:.0f}%" if total else "-"]))
print(f"\nA cell with fewer than {MIN_STORIES} stories prints its count alone: too few to judge.")
if gh_failed:
    print("rework: gh failed, so only escaped findings mark rework.")
