import collections, datetime, glob, json, os, sys
from report import *
log, events, since, projects, roles, archive = sys.argv[1:7]

def slug_of(path, name):
    # A builder runs in <repo>-wt/<slug>; any other cwd (or none logged) leaves the agents.tsv name.
    for line in log_lines(path) if path else ():
        try:
            cwd = json.loads(line).get("cwd")
        except (ValueError, AttributeError):
            continue
        if cwd:
            return os.path.basename(cwd.rstrip("/")) if os.path.dirname(cwd.rstrip("/")).endswith("-wt") else name
    return name

PULL = re.compile(r"https://github\.com/[^/\s\"\\]+/[^/\s\"\\]+/pull/\d+")
def pulls(path):
    # Each URL once, in the order of its last mention (pr_of wants only the last of the PRs of the slug), so
    # a log that names hundreds keeps the row small enough for SWARM_ROWS. A log that reads as nothing
    # (gone, or damaged from its start) is no log: "-".
    named, read = {}, False
    for line in log_lines(path) if path else ():
        read = True
        for u in PULL.findall(line):
            named.pop(u, None)
            named[u] = None
    return " ".join(named) if read else "-"

def started_of(path):
    # The first timestamp in the session log, to the second as events.tsv writes times (both UTC), or "".
    for line in log_lines(path) if path else ():
        try:
            ts = json.loads(line).get("timestamp")
        except (ValueError, AttributeError):
            continue
        if isinstance(ts, str) and re.fullmatch(r"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z", ts):
            return ts[:19] + "Z"
    return ""

def midnight(day):
    # 00:00 local time on an agents.tsv day (a local date), in epoch seconds: where a build with no
    # session log starts. None for a day that does not parse.
    try:
        return datetime.datetime.strptime(day, "%Y-%m-%d").timestamp()
    except ValueError:
        return None

def secs(t):
    # A UTC time as events.tsv and started write it, in epoch seconds; None when it does not parse.
    try:
        return datetime.datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None

def agent_name(n):
    # bash agent_name: the name agents.tsv keeps for a slug (lowercase, [a-z0-9_-], a letter first, 32 at most).
    n = re.sub(r"[^a-z0-9_-]", "-", n.lower())
    return (n if re.match(r"[a-z]", n) else "s" + n)[:32]

def usage(path):
    # A builder's own tokens and est. USD, and its subagents' est. USD per model (opus, haiku, ...). A
    # subagent turn is one with parent_tool_use_id set in the builder's log, or any turn in
    # subagents/*.jsonl in the folder named after its session beside the log: Claude Code writes either.
    tok, usd, sub, seen = [0, 0, 0, 0], 0.0, collections.Counter(), set()
    side = glob.glob(os.path.join(glob.escape(re.sub(r"\.jsonl(\.gz)?$", "", path)), "subagents", "*.jsonl"))
    for p in [path] + sorted(side):
        for d, model, t, cost in turns(p, seen):
            if p == path and not d.get("parent_tool_use_id"):
                tok, usd = [x + y for x, y in zip(tok, t)], usd + cost
            else:
                sub[next((k for k in PRICES if k in model), model)] += cost
    return tok, usd, sub

builds, tries = [], collections.Counter()
for line in open(log, errors="ignore"):
    f = line.rstrip("\n").split("\t")
    if len(f) != 7 or f[1] not in roles.split():
        continue
    path = session_log(projects, f[6], archive)
    slug = slug_of(path, f[2])
    tries[slug] += 1
    started = started_of(path)
    builds.append({"f": f, "path": path, "slug": slug, "n": tries[slug], "started": started,
                   "t": secs(started) if started else midnight(f[0]), "steer": collections.Counter(), "at": {}})

def of(target):
    # The builds an events.tsv target names: by slug or agents.tsv name, and a build whose slug is
    # unknown (no log, so it is the name) by the name agents.tsv keeps for the target, which cuts a slug
    # over 32 characters. A build whose log names another slug with the same 32 is not this one.
    cut = agent_name(target)
    return [b for b in builds if b["t"] is not None
            and (target in (b["slug"], b["f"][2]) or b["slug"] == b["f"][2] == cut)]

STEPS = ("escalate", "dialog", "escalated", "reset", "drop")
oks, escalates = [], collections.defaultdict(list)
for line in open(events, errors="ignore") if os.path.exists(events) else ():
    f = line.rstrip("\n").split("\t")
    # Only an ok line counts: a refused or interrupted tell never reached the builder. Field 5 is read
    # for that and for the answer of a dialog alone: a reset or drop holds the reason the lead gave. A
    # line whose time does not parse goes to no build.
    t = secs(f[0]) if len(f) == 5 and (f[4] == "ok" or f[4].startswith("ok (")) else None
    if t is not None:
        oks.append((t, f))
        if f[1] == "escalate":
            escalates[f[2]].append(t)
cycle, seen = {}, collections.Counter()
for t, f in oks:
    # A tell is logged as tell:<kind>; a bare tell, from logs before kinds, sent findings.
    when, c, target = f[0], {"tell": "tell:findings"}.get(f[1], f[1]), f[2]
    if c in STEPS:
        # An escalate opens a cycle for the next escalate build of its target with none, in agents.tsv
        # order, and each step until the next reset, drop or escalate belongs to that build (by event
        # order, the last of a kind kept). build_story logs the escalate as its build starts, so a later
        # build with a session log takes the cycle instead when this is the escalate of its target
        # nearest its start (a tie to the earlier), and it started nearer than the first: a build whose
        # brief was never taken up logged no escalate, and must not take the cycle of its retry.
        if c == "escalate":
            mine, seen[target] = seen[target], seen[target] + 1
            near = lambda b: min(range(len(escalates[target])), key=lambda i: abs(b["t"] - escalates[target][i]))
            free = [b for b in of(target) if b["f"][1] == "escalate" and "escalate" not in b["at"]]
            own = [b for b in free[1:] if b["started"] and near(b) == mine]
            cycle[target] = min(free[:1] + own, key=lambda b: abs(b["t"] - t), default=None)
        b = cycle.pop(target, None) if c in ("reset", "drop") else cycle.get(target)
        if b:
            b["at"][c] = when
            if c == "dialog":
                m = re.fullmatch(r"ok \((accepted|dismissed)\)", f[4])
                b["at"]["answer"] = m.group(1) if m else ""
        continue
    if c.split(":")[0] not in ("tell", "close"):
        continue
    # A tell or close goes to the build of its target that started last at or before it.
    b = max((b for b in reversed(of(target)) if b["t"] <= t), key=lambda b: b["t"], default=None)
    if b and c.split(":")[0] == "close":
        # Counted whatever its cause (close:<cause>); close_cause is the cause of the last close (none: empty).
        b["steer"]["close"] += 1
        b["cause"] = c.partition(":")[2]
    elif b:
        b["steer"][c] += 1
for b in builds:
    day, role, _, _, model, effort, _ = b["f"]
    if day < since:
        continue
    cost = tokens = sub_cost = sub_models = ""
    tok = ["", "", "", ""]
    if b["path"]:
        t, usd, sub = usage(b["path"])
        cost, tokens, tok = f"{usd:.2f}", str(sum(t)), [str(x) for x in t]
        sub_cost, sub_models = f"{sum(sub.values()):.2f}", ",".join(f"{m}:{v:.2f}" for m, v in sorted(sub.items()))
    counts = [str(b["steer"][c]) for c in ("tell:findings", "tell:nudge", "tell:resume", "close")]
    steps = [b["at"].get(k, "") for k in ("escalate", "dialog", "answer", "escalated", "reset", "drop")]
    print("\t".join([day, b["slug"], role, model, effort, cost, tokens] + counts + [str(b["n"]), pulls(b["path"]), b["started"]]
                    + tok + [b.get("cause", "")] + steps + [sub_cost, sub_models]))
