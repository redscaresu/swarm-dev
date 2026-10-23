# Idle slots, a flow section (flow_report.py gives its globals): one TSV row per epic, then `all`; with
# --epic, that epic's row alone. idle_min: the minutes in the window when at least one of its stories
# was ready with no build, clashed with no running build, and its conductor ran; no_conductor_min: the
# same minutes while no conductor of its epic ran; most_ready: the most of its stories ready with no
# build at once, clashing or not. `all` takes the union of the epics' minutes, and the stories with no
# epic (the backlog conductor's). A story goes ready at an ok unblock, `reconcile ... ok (reopened)`,
# reset or reset:held event, or a close that sent it back: any close but the one that ended a build
# after its review or kept event (the builder's close leaves the story in review; a later close, the
# drop, sends it back). Its first wait runs from its first build's start less its ready_wait_min
# (outcomes' column) to that start; each later wait from the last such event since the build before
# to the next build's start; a story whose own build runs is not waiting. One on the board now that
# next would build (buildable_story: `status: ready`, a kind in SWARM_AGENT_KINDS or none, no epic or an
# active one; and not held), under what swarm.sh wrote to .swarm/board-state as touches_rows.front
# reads it, with no build since it went ready waits from then to the window's end; there the board's
# last commit to its status line on its default branch also readies it, dated by the merge as
# outcomes' board_log reads it, and a build with no start (no session log yet) on that day or later
# counts as built since, unless a close readied it. Builds keep agents.tsv's order: each runs from
# its started (with none, 00:00 local on its agents.tsv day, and no earlier than its slug's build
# before it ended, as throughput's) to its first ok close after that which no earlier build of its
# slug took, before the slug's next build with a known start, else to that start, else to the
# window's end. Two stories clash as touches_rows.py reads touches (the same file:symbol in the same
# repo, or either naming the bare file, with SWARM_REPOS_DIR as build.sh's REPOS_DIR), unless one
# depends on the other (a stacked start), each story read as story_text reads it, so a build before
# --since counts too. A
# conductor runs from an ok `conduct` event to its next one, an ok close of its agent, a report event
# for it or its report file's time, as outcomes' held reads it; the backlog's agent is conduct-backlog
# or SWARM_BACKLOG_CONDUCTOR (conductor_name backlog).
# ponytail: a build with no close runs to the window's end; read its session log's last entry, as throughput does, if that misleads.
# ponytail: a story readied, never built and gone from the board (or set blocked) is not counted; read the board's history if those matter.
import collections, datetime, functools, glob, os, subprocess, sys, time
import touches_rows
from report import agent_name
from touches_rows import deps as front_deps, entries, front, front_text, overlap
project_dir = os.path.dirname(os.path.dirname(findings))
board, repos_dir = os.environ.get("SWARM_BOARD", ""), os.environ.get("SWARM_REPOS_DIR", "")
board_state = os.path.join(os.path.dirname(events), "board-state")
touches_rows.state = os.path.join(board_state, "stories")   # front's overlay for a story

warned = []

def git(*args, quiet=False):
    # Its output, or "" when it fails; the first failure that is not quiet warns on stderr, as what it
    # read (a merged story's touches, a ready time) is then left out.
    got = subprocess.run(["git", "-C", board, *args], capture_output=True, encoding="utf-8", errors="replace")
    if got.returncode and not quiet and not warned:
        warned.append(args)
        why = (got.stderr.strip().splitlines() or [f"exit {got.returncode}"])[0]
        print(f"warning: idle_slots: git {args[0]} in {board} failed ({why}): what it reads is left out", file=sys.stderr)
    return got.stdout if got.returncode == 0 else ""

@functools.lru_cache(maxsize=None)
def board_ref():
    # The board's default branch (origin/HEAD, else HEAD); None with no commit yet.
    git("rev-parse", "--git-dir")   # warns when the board is no git repo
    return next((r for r in ("origin/HEAD", "HEAD") if git("rev-parse", "-q", "--verify", r, quiet=True)), None)

def board_log(*args):
    # outcomes_join's board_log: git log on the board's default branch, a commit dated by the merge
    # that brought it.
    ref = board_ref()
    return git("log", ref, "--first-parent", "--diff-merges=first-parent", "--no-renames", *args) if ref else ""

def buildable(fm):
    # board.sh's buildable_story: ready, an agent's kind (or none), no epic or an active one.
    if fm.get("status") != "ready" or fm.get("kind", "") not in [""] + os.environ.get("SWARM_AGENT_KINDS", "").split():
        return False
    f = os.path.join(board, "epics", fm.get("epic", "") + ".md")
    if not fm.get("epic"):
        return True
    touches_rows.state = os.path.join(board_state, "epics")
    try:
        return os.path.isfile(f) and front(f).get("status") == "active"
    finally:
        touches_rows.state = os.path.join(board_state, "stories")

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
readies, reviews = collections.defaultdict(list), collections.defaultdict(list)   # by agent_name: ready events; review or kept
for line in open(events, errors="ignore") if os.path.exists(events) else ():
    e = line.rstrip("\n").split("\t")
    t = secs(e[0]) if len(e) == 5 and (e[4] == "ok" or e[4].startswith("ok (")) else None
    if t is None:
        continue
    if e[1] in ("unblock", "reset", "reset:held") or e[1] == "reconcile" and e[4] == "ok (reopened)":
        readies[agent_name(e[2])].append(t)
    elif e[1] in ("review", "kept"):
        reviews[agent_name(e[2])].append(t)
    elif e[1] == "conduct":
        conducts[e[2]].append(t)
    elif e[1].split(":")[0] == "close":
        closes[agent_name(e[2])].append(t)
    elif e[1] == "report" and secs(e[4][len("ok ("):-1]) is not None:
        reports["--backlog" if e[2] == "backlog" else e[2]].append(secs(e[4][len("ok ("):-1]))

def conductor_runs(key):
    # The (start, end) of each run of the epic's conductor (key --backlog for the backlog's).
    if key == "--backlog":
        ends = [t for n in {"conduct-backlog", os.environ.get("SWARM_BACKLOG_CONDUCTOR", "")} - {""} for t in closes[n]]
    else:
        ends = list(closes[agent_name("conduct-" + key)])
    report = os.path.join(os.path.dirname(events), f"conduct-{'backlog' if key == '--backlog' else key}.report.md")
    ends += reports[key] + ([os.path.getmtime(report)] if os.path.exists(report) else [])
    starts = sorted(conducts[key])
    return [(s, min([t for t in ends + starts[i + 1:] if t > s] + [hi])) for i, s in enumerate(starts)]

by_slug = collections.defaultdict(list)   # slug -> its rows, in agents.tsv order
for r in rows:
    by_slug[r["slug"]].append(r)
builds, starts, loose = [], collections.defaultdict(list), collections.defaultdict(list)   # (slug, start, end); slug -> starts; days of builds with none
for slug, rs in by_slug.items():
    known, taken, ended = [secs(r["started"]) for r in rs], set(), None
    for i, r in enumerate(rs):
        b0 = known[i] if known[i] is not None else secs(r["date"] + "T00:00:00")
        if b0 is None:
            continue
        if known[i] is None:
            b0 = max(b0, ended) if ended is not None else b0
            loose[slug].append(r["date"])
        upto = next((k for k in known[i + 1:] if k is not None), hi)
        c = min((t for t in closes[agent_name(slug)] if b0 <= t < upto and t not in taken), default=None)
        taken.add(c)
        ended = c if c is not None else upto
        builds.append((slug, b0, ended))
        starts[slug].append(b0)

def sent_back(slug, c):
    # Whether the close at c sent the story back to ready: not the first close after a review or kept
    # event since the build before it started, which leaves the story in review.
    n = agent_name(slug)
    since = [r for r in reviews[n] if max((b for b in starts[slug] if b <= c), default=float("-inf")) <= r <= c]
    return not since or any(max(since) < x < c for x in closes[n])

def readied(slug):
    n = agent_name(slug)
    return readies[n] + [c for c in closes[n] if sent_back(slug, c)]

epic_of, earliest = {}, {}   # slug -> its epic; slug -> (its first build's start, that build's ready_wait_min)
for r in rows:
    t = secs(r["started"])
    epic_of[r["slug"]] = r["epic"]
    if t is not None and (r["slug"] not in earliest or t < earliest[r["slug"]][0]):
        earliest[r["slug"]] = (t, r["ready_wait_min"])
ready = [(slug, t - 60 * int(w), t) for slug, (t, w) in earliest.items() if w]
for slug, bs in starts.items():
    bs = sorted(bs)
    for prev, b0 in zip(bs, bs[1:]):
        t = max((x for x in readied(slug) if prev < x <= b0), default=None)
        if t is not None:
            ready.append((slug, t, b0))
for f in sorted(glob.glob(os.path.join(glob.escape(board), "stories", "*.md"))) if board else ():
    slug = os.path.basename(f)[:-3]
    fm = {} if slug == "README" else front(f)
    if not buildable(fm) or fm.get("held_by"):
        continue
    commit = board_log("-1", "-s", "--format=%ct", "-G^status:", "--", f"stories/{slug}.md").strip()
    t = max(readied(slug) + ([float(commit)] if commit else []), default=None)
    # A close that sent it back ended every build before it, and a build after it starts no earlier;
    # else a build with no start on its day or later is since.
    day = "~" if t is None or t in closes[agent_name(slug)] else datetime.date.fromtimestamp(t).isoformat()
    if t is not None and not any(b >= t for b in starts[slug]) and not any(d >= day for d in loose[slug]):
        epic_of.setdefault(slug, fm.get("epic", ""))
        ready.append((slug, t, hi))
files, needs = {}, {}   # slug -> its touches' entries; slug -> its depends_on

def known(s):
    if s not in files:
        fm = story(s)
        files[s], needs[s] = entries(fm, project_dir, repos_dir), front_deps(fm)
    return files[s]

@functools.lru_cache(maxsize=None)
def clashes(a, b):
    return a != b and any(overlap(x, y) for x in known(a) for y in known(b)) and a not in needs[b] and b not in needs[a]

runs = {k: conductor_runs(k) for k in {epic_of[s] or "--backlog" for s, _, _ in ready}}
points = sorted({min(max(t, lo), hi) for _, s, e in ready + builds for t in (s, e)}
                | {min(max(t, lo), hi) for rs in runs.values() for s, e in rs for t in (s, e)})
idle, none, most = collections.Counter(), collections.Counter(), collections.Counter()
for a, b in zip(points, points[1:]):
    mid = (a + b) / 2
    running = [s for s, b0, b1 in builds if b0 <= mid < b1]
    waiting = [s for s, r0, r1 in ready if r0 <= mid < r1 and s not in running]   # reopened while its build runs
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
