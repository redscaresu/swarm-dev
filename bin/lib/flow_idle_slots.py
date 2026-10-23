# Idle slots, a flow section (flow_report.py gives its globals): one TSV row per epic, then `all`; with
# --epic, that epic's row alone. idle_min: the minutes in the window when at least one of its stories
# was ready with no build, clashed with no running build, and its conductor ran; no_conductor_min: the
# same minutes while no conductor of its epic ran; most_ready: the most of its stories ready with no
# build at once, clashing or not. `all` takes the union of the epics' minutes, and the stories with no
# epic (the backlog conductor's). A story is ready from its first build's start less its
# ready_wait_min (outcomes' column) to that start. One on the board now as `status: ready` (not a lead
# story, not held), under what swarm.sh wrote to .swarm/board-state as touches_rows.front reads it,
# with no build since it went ready is ready from then (the later of its last ok unblock event and the
# board's last commit to its status line) to the window's end. A build runs
# from its started to its slug's first ok close after it, before the slug's next build, else to that
# next build, else to the window's end. Two stories clash as touches_rows.py reads touches (the same
# file:symbol in the same repo, or either naming the bare file), unless one depends on the other (a
# stacked start), each story read as story_text reads it, so a build before --since counts too. A
# conductor runs from an ok `conduct` event to its next one, an ok close of its agent, a report event
# for it or its report file's time, as outcomes' held reads it; the backlog's agent is any
# conduct-backlog* name, as the events log is the project's own.
# ponytail: a build with no close runs to the window's end; read its session log's last entry, as throughput does, if that misleads.
# ponytail: a story readied, never built and gone from the board (or set blocked) is not counted; read the board's history if those matter.
import collections, datetime, glob, os, subprocess, time
import touches_rows
from report import agent_name
from touches_rows import deps as front_deps, entries, front, front_text, overlap
project_dir = os.path.dirname(os.path.dirname(findings))
board = os.environ.get("SWARM_BOARD", "")
touches_rows.state = os.path.join(os.path.dirname(events), "board-state", "stories")   # front's overlay

def git(*args):
    got = subprocess.run(["git", "-C", board, *args], capture_output=True, text=True)
    return got.stdout if got.returncode == 0 else ""

def story(slug):
    # Its front matter, as story_text finds it: on the board, else as the commit that deleted it left it.
    f = os.path.join(board, "stories", slug + ".md")
    if os.path.isfile(f):
        return front(f)
    c = git("log", "--diff-filter=D", "-1", "--format=%H", "--", f"stories/{slug}.md").strip()
    return {k: v.strip() for k, v in front_text(git("show", f"{c}^:./stories/{slug}.md")).items()} if c else {}

def secs(t):
    # A time in epoch seconds (local when it names no zone); None when it does not parse.
    try:
        return datetime.datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None

lo = secs(since) or float("-inf")   # since's 0000-00-00 placeholder does not parse
hi = min((datetime.datetime.fromisoformat(until) + datetime.timedelta(days=1)).timestamp(), time.time())

conducts, closes, reports = collections.defaultdict(list), collections.defaultdict(list), collections.defaultdict(list)
unblocks = collections.defaultdict(list)
for line in open(events, errors="ignore") if os.path.exists(events) else ():
    e = line.rstrip("\n").split("\t")
    t = secs(e[0]) if len(e) == 5 and (e[4] == "ok" or e[4].startswith("ok (")) else None
    if t is None:
        continue
    if e[1] == "unblock":
        unblocks[e[2]].append(t)
    elif e[1] == "conduct":
        conducts[e[2]].append(t)
    elif e[1].split(":")[0] == "close":
        closes[agent_name(e[2])].append(t)
    elif e[1] == "report" and secs(e[4][len("ok ("):-1]) is not None:
        reports["--backlog" if e[2] == "backlog" else e[2]].append(secs(e[4][len("ok ("):-1]))

def conductor_runs(key):
    # The (start, end) of each run of the epic's conductor (key --backlog for the backlog's).
    if key == "--backlog":
        ends = [t for n, ts in closes.items() if n.startswith("conduct-backlog") for t in ts]
    else:
        ends = list(closes[agent_name("conduct-" + key)])
    report = os.path.join(os.path.dirname(events), f"conduct-{'backlog' if key == '--backlog' else key}.report.md")
    ends += reports[key] + ([os.path.getmtime(report)] if os.path.exists(report) else [])
    starts = sorted(conducts[key])
    return [(s, min([t for t in ends + starts[i + 1:] if t > s] + [hi])) for i, s in enumerate(starts)]

starts = collections.defaultdict(list)
for r in rows:
    t = secs(r["started"])
    if t is not None:
        starts[r["slug"]].append(t)
builds = []   # (slug, start, end)
for slug, ts in starts.items():
    ts = sorted(set(ts))
    for i, s in enumerate(ts):
        upto = ts[i + 1] if i + 1 < len(ts) else hi
        builds.append((slug, s, min([t for t in closes[agent_name(slug)] if s <= t < upto] + [upto])))
epic_of, earliest = {}, {}   # slug -> its epic; slug -> (its first build's start, that build's ready_wait_min)
for r in rows:
    t = secs(r["started"])
    epic_of[r["slug"]] = r["epic"]
    if t is not None and (r["slug"] not in earliest or t < earliest[r["slug"]][0]):
        earliest[r["slug"]] = (t, r["ready_wait_min"])
ready = [(slug, t - 60 * int(w), t) for slug, (t, w) in earliest.items() if w]
for f in sorted(glob.glob(os.path.join(glob.escape(board), "stories", "*.md"))) if board else ():
    slug = os.path.basename(f)[:-3]
    fm = {} if slug == "README" else front(f)
    if fm.get("status") != "ready" or fm.get("kind") == "lead" or fm.get("held_by"):
        continue
    commit = git("log", "-1", "--format=%ct", "-G^status:", "--", f"stories/{slug}.md").strip()
    t = max(unblocks[slug] + ([float(commit)] if commit else []), default=None)
    if t is not None and not any(b >= t for b in starts[slug]):
        epic_of.setdefault(slug, fm.get("epic", ""))
        ready.append((slug, t, hi))
files, needs = {}, {}   # slug -> its touches' entries; slug -> its depends_on

def known(s):
    if s not in files:
        fm = story(s)
        files[s], needs[s] = entries(fm, project_dir, ""), front_deps(fm)
    return files[s]

def clashes(a, b):
    return a != b and any(overlap(x, y) for x in known(a) for y in known(b)) and a not in needs[b] and b not in needs[a]

runs = {k: conductor_runs(k) for k in {epic_of[s] or "--backlog" for s, _, _ in ready}}
points = sorted({min(max(t, lo), hi) for _, s, e in ready + builds for t in (s, e)}
                | {min(max(t, lo), hi) for rs in runs.values() for s, e in rs for t in (s, e)})
idle, none, most = collections.Counter(), collections.Counter(), collections.Counter()
for a, b in zip(points, points[1:]):
    mid = (a + b) / 2
    waiting = [s for s, r0, r1 in ready if r0 <= mid < r1]
    running = [s for s, b0, b1 in builds if b0 <= mid < b1]
    # epic ("" for none) -> "idle" or "none": its stories share one conductor
    hit = {epic_of[s]: "idle" if any(r0 <= mid < r1 for r0, r1 in runs[epic_of[s] or "--backlog"]) else "none"
           for s in waiting if not any(clashes(s, o) for o in running)}
    for g, kind in hit.items():
        (idle if kind == "idle" else none)[g] += b - a
    # The project row apart, so an epic named all is still an epic.
    idle[None] += (b - a) * ("idle" in hit.values())
    none[None] += (b - a) * ("none" in hit.values())
    for g, n in collections.Counter(epic_of[s] for s in waiting).items():
        most[g] = max(most[g], n)
    most[None] = max(most[None], len(waiting))

print("epic\tidle_min\tno_conductor_min\tmost_ready")
groups = sorted({epic_of[s] for s, r0, r1 in ready if epic_of[s] and r0 < hi and r1 > lo})
for g in [epic] if epic else groups + [None]:
    print("\t".join([g or "all", str(round(idle[g] / 60)), str(round(none[g] / 60)), str(most[g])]))
