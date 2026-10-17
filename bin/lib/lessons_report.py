import collections, datetime, glob, os, re, subprocess, sys
from report import *
project, log, brief, min_prs, recent_days, max_bytes, flag, memory, swarm_brief = sys.argv[1:10]
min_prs, recent_days, max_bytes = int(min_prs), int(recent_days), int(max_bytes)
cutoff = (datetime.date.today() - datetime.timedelta(days=recent_days)).isoformat()

def adopted(kind):
    # The day the kind's current rule landed on the default branch, from git; "" when it cannot be told.
    # The tag is searched as written in the brief, and the newest commit that changed its count is taken:
    # the rule is present now, so that commit is its latest addition (a rule pruned and re-added is new).
    tag, path = tags.get(kind, ("", ""))
    if not tag or not path:
        return ""
    got = subprocess.run(["git", "-C", project, "log", "--format=%cs", "-S", tag, "origin/HEAD", "--",
                          f":(top){path}"], capture_output=True, text=True)
    return got.stdout.split()[0] if got.returncode == 0 and got.stdout.strip() else ""

def read_brief(brief=brief):
    # The brief on the default branch, where adopted rules land. git paths are from the repo root,
    # so the project's own prefix is added for a project in a subdirectory of its repo.
    prefix = subprocess.run(["git", "-C", project, "rev-parse", "--show-prefix"], capture_output=True, text=True)
    path = prefix.stdout.strip() + os.path.relpath(brief, project)
    got = subprocess.run(["git", "-C", project, "show", f"origin/HEAD:{path}"], capture_output=True)
    if got.returncode == 0:
        return got.stdout.decode("utf-8", errors="replace"), "", path
    if not os.path.exists(brief):
        return "", "", ""
    note = f"note: no {os.path.relpath(brief, project)} on origin/HEAD, so it was read from the working tree (any branch)"
    return open(brief, encoding="utf-8", errors="replace").read(), note, ""

prs, recent, dated = collections.defaultdict(set), collections.defaultdict(set), collections.defaultdict(list)
last, example = {}, {}
for parts in fixed_rows(log):  # a declined finding is no lesson
    try:
        when = datetime.date.fromisoformat(parts[0]) if re.fullmatch(r"\d{4}-\d{2}-\d{2}", parts[0]) else None
    except ValueError:
        when = None
    if when is None or when > datetime.date.today():
        continue  # a malformed, impossible or future row must not count, least of all as recent
    _, kind, pr, finding = parts
    day = when.isoformat()
    prs[kind].add(pr_key(pr)); last[kind] = max(last.get(kind, ""), day); example[kind] = finding
    dated[kind].append((day, pr_key(pr)))
    if day >= cutoff:
        recent[kind].add(pr_key(pr))  # only PRs inside the window count toward a candidate
brief_text, note, brief_path = read_brief()
# The brief is pasted into every prompt, so a rule it still tags rules its kind too. Each kind keeps
# its tag as written and the file it is in, for its adoption date.
cap_text, cap_note, cap_path = (brief_text, "", brief_path) if swarm_brief == brief else read_brief(swarm_brief)
tags = {}
for text, path in ((cap_text, cap_path), (brief_text, brief_path)):  # lessons_file wins a kind in both
    tags.update({m.group(1): (m.group(0), path) for m in re.finditer(r"<!--\s*lesson:\s*([a-z0-9-]+)\s*-->", text)})
ruled = set(tags)
out = []
for kind in sorted(prs, key=lambda k: -len(prs[k])):
    n_recent = len(recent[kind])
    if flag == "--all":
        out.append(f"{kind}\t{len(prs[kind])} PR(s)\t{n_recent} in the last {recent_days} days\t{'ruled' if kind in ruled else ''}")
    elif n_recent >= min_prs and kind not in ruled:
        out.append(f"candidate {kind}: fixed in {n_recent} PRs in the last {recent_days} days, last {last[kind]}; e.g. {example[kind]}")
    elif kind in ruled:
        since = adopted(kind)
        after = {pr for day, pr in dated[kind] if since and day > since}
        if len(after) >= min_prs:
            out.append(f"recurring {kind}: fixed in {len(after)} PRs since its brief rule landed on {since}; "
                       "the rule is not working: turn it into a step agents must do, or drop it")
for path in sorted(glob.glob(os.path.join(memory, "*.md"))):
    # Only the frontmatter is read, and only a tagged memory is named: the rest of memory stays private.
    try:
        head = re.match(r"---\n(.*?)\n---", open(path, encoding="utf-8", errors="replace").read(), re.S)
    except OSError:
        continue  # an unreadable entry must not cost the rest of the report
    tag = head and re.search(r"^\s*lesson:\s*([a-z0-9]+(?:-[a-z0-9]+)*)\s*$", head.group(1), re.M)
    if tag and tag.group(1) not in ruled and flag != "--all" and not any(l.startswith(f"candidate {tag.group(1)}:") for l in out):
        out.append(f"candidate {tag.group(1)}: from the lead's memory {path}; draft the rule from it")
# The cap measures what every prompt carries: the brief, plus lessons_file's tagged lines when it is
# another file (project_rules pastes those too).
pasted = "" if swarm_brief == brief else "\n".join(re.findall(r"^.*<!--\s*lesson:\s*[a-z0-9-]+\s*-->.*$", brief_text, re.M))
size = len((cap_text + pasted).encode("utf-8", errors="surrogateescape"))
if size > max_bytes:
    where = (f"origin/HEAD:{cap_path}" if cap_path else swarm_brief) + (" plus lessons_file's rules" if pasted else "")
    out.append(f"long brief: {where} is {size} bytes, over {max_bytes}; merge or retire rules")
notes = list(dict.fromkeys(n for n in (note, cap_note) if n))
print("\n".join((out or ["no lessons: nothing has recurred in enough PRs yet"]) + notes))
