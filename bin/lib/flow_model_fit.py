# Model fit, a flow section (flow_report.py gives its globals): cost against effectiveness, one TSV row
# per model and effort crossed with a story class (kind, risk, size and area), over the stories whose
# first build is dated in the window (with --epic, that epic's). A story counts under the model and
# effort of its first build, so an escalation to Fable stays under the model it started on; its cost,
# attempts and findings are those of all its builds. size buckets its estimate_lines and area is the
# top-level directory most of its touches name, both read through story_text (flow_sections), so a
# merged story keeps its class. Rework is outcomes' rework column, which outcomes alone computes (report.py's
# rework_of over every merged PR of the rows' repos), so every flow section counts the same. A cell under
# MIN_STORIES stories prints its count alone. After a blank line, a subagent row per model and effort
# of the builds whose subagents cost more than zero: their cost and its share of build cost (own and theirs).
import collections, datetime, os
from report import *
from touches_rows import entries as touches_entries
MIN_STORIES = 5
project_dir = os.path.dirname(os.path.dirname(findings))

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
    # The top-level folder most of its files are in (bin/, src/, ...; root for a file at the project's
    # root), the first named on a tie; none for no touches. The files are touches_rows.py's, so a bare name after a file (g in `bin/x.sh:f, g`) is
    # a function unless the project has a file by that name (Makefile). The project is the findings
    # log's (<project>/.swarm/<log>); a file in another repo is read under no repos_dir, as a function.
    # Each file counts once, however many of its functions follow it.
    tops = [f.split("/") for f in dict.fromkeys(f for _, f, _ in touches_entries({"touches": touches}, project_dir, ""))]
    tops = [f"{p[0]}/" if len(p) > 1 else "root" for p in tops]
    return collections.Counter(tops).most_common(1)[0][0] if tops else "none"

def minutes(start, end):
    try:
        t = lambda s: datetime.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
        return (t(end) - t(start)) / 60
    except ValueError:
        return None

by_slug = collections.defaultdict(list)
for r in rows:
    by_slug[r["slug"]].append(r)
counted = {}
for slug, rs in by_slug.items():
    first = min(rs, key=lambda r: num(r["attempts"]))
    if since <= first["date"] <= until and (not epic or first["epic"] == epic):
        counted[slug] = (first, rs)

rework = {pr_key(r["pr"]) for r in rows if r.get("rework") == "1"}
escaped = collections.Counter(pr_key(f[2]) for f in finding_rows(findings, ("escaped",)))

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
if rework_unknown(rows, since):
    print("rework: outcomes could not list every merged PR with gh (it failed or hit its limit), so some rework is unknown and counts as none.")
