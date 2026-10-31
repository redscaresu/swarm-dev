# Lead queue, a flow section (flow_report.py gives its globals): how long items wait on the lead, from
# events.tsv's ok lines. An item enters on a held line (held_story), an escalated line or an impossible
# close, a kept line (keep_build: a give-up's PR in review, not reviewed, which wait --lead wakes the
# lead for whatever merge is), or a review (handed over to merge; with merge = agent only a story whose
# costs: is not none, read as costs_value reads it, from the board, its last version in the board's git
# history or HEAD's, and money when none of them has it; never an epic), and leaves on its slug's next
# finish, reset, reset:held, drop or reconcile (finished once every PR merged, or reopened when one
# closed unmerged); a merge line is one PR's, so it does not end the wait. A kept line ends whatever
# item waits for its slug and opens a kept one, except for a child held by an open parent (blocked with
# held_by: on the board now), which status and wait --lead list as blocked, never kept: its kept line
# opens and ends nothing (only the current build's kept line can be one: the slug's last, after its last
# story line). Such a child may be unblocked since: unblock frees only a blocked story, and a
# kept story in review is never blocked, so an unblock line on a kept item, or its story blocked at the
# end, shows it was such a child, and the item is dropped, never counted. A kept item also leaves on a
# review (which then enters it as merge), a held or escalated line or an impossible close, each at its
# own time. keep_build logs its kept line inside a close, so the slug's next close line, whatever its
# outcome, is that keeping close's own. A later close (close --drop, which sends the story back to
# ready) logs ok even when it drops nothing, so the wait ends at the last such close only once something
# shows it dropped the build: a new build (story), a leaving line other than a finish or reconcile, or
# the story no longer kept at the end. A finish or reconcile ends the wait at its own time: a merged PR
# (finish, reconcile finished) or a reopen (reconcile reopens only an item still in review) shows the
# close dropped nothing.
# Waits stop at local midnight after --until (or now): an item that left later is open there. One with
# no leaving line is open only while its story or epic is on the board in review (a kept one only with
# kept: set), held or escalated (read with board-state as fm reads it); any other is dropped, its end
# unknown. Per local day it entered: items, the median and maximum minutes waited, and open, the
# kind:slug of each item open. --epic does not narrow it. Last, after a blank line and any no-agent
# table below: items, median_min, p90_min (nearest rank) and max_min over every item of this table in
# the window (never a no-agent item), - in each column with none.
import datetime, functools, os, re, statistics, subprocess, time

ENTER = {"held": "held", "escalated": "escalated", "close:impossible": "escalated", "kept": "kept", "review": "merge"}
LEAVE = {"finish", "reset", "reset:held", "drop", "reconcile"}

project = os.path.dirname(os.path.dirname(os.path.abspath(events)))
cfg = {}
try:
    for line in open(os.path.join(project, ".claude/swarm/config"), errors="ignore"):
        m = re.fullmatch(r"\s*([a-z_]+)\s*=\s*(.*?)\s*", line.split("#", 1)[0].rstrip("\n"))
        if m:
            cfg[m.group(1)] = m.group(2)
except OSError:
    pass
board = os.path.join(project, os.path.expanduser(cfg.get("board_dir", "docs")))

def front(text):
    return text.split("\n---", 1)[0] if text.startswith("---") else ""

def item(slug):
    # The live board file of a story or epic and its board-state file, or None.
    for d in ("stories", "epics"):
        f = os.path.join(board, d, slug + ".md")
        if os.path.isfile(f):
            return f, os.path.join(project, ".swarm/board-state", d, slug)
    return None

def fm(f, state, key):
    # As board.sh's fm: board-state's value unless the file's own changed from its key@base.
    m = re.search(rf"^{key}: *(.*)$", front(open(f, errors="ignore").read()), re.M)
    own = m.group(1).rstrip("\r") if m else ""
    try:
        s = open(state, errors="ignore").read()
    except OSError:
        return own
    v, base = (re.search(rf"^{k}: *(.*)$", s, re.M) for k in (key, re.escape(key + "@base")))
    return v.group(1) if v and (not base or base.group(1) == own) else own

def still_waiting(slug, what):
    found = item(slug)
    if not found:
        return False
    status, kind, held, esc, kept = (fm(*found, k) for k in ("status", "kind", "held_for", "escalated_from", "kept"))
    if what == "kept":
        return status == "review" and bool(kept)
    return status == "review" or bool(held) or (status == "ready" and kind == "lead" and bool(esc))

def blocked_now(slug, held_by=False):
    found = item(slug)
    return bool(found) and fm(*found, "status") == "blocked" and (not held_by or bool(fm(*found, "held_by")))

def git(*a):
    r = subprocess.run(["git", "-C", board, *a], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None

@functools.lru_cache(maxsize=None)
def story_text(slug):
    # The story's text, or None when neither the board nor its git history has it.
    f = os.path.join(board, "stories", slug + ".md")
    if os.path.isfile(f):
        return open(f, errors="ignore").read()
    c = (git("log", "--diff-filter=D", "-1", "--format=%H", "--", f"./stories/{slug}.md") or "").strip()
    return git("show", f"{c}^:./stories/{slug}.md" if c else f"HEAD:./stories/{slug}.md")

def is_epic(slug):
    f = f"./epics/{slug}.md"
    return os.path.isfile(os.path.join(board, f)) or bool((git("log", "-1", "--format=%H", "--", f) or "").strip())

def costs_money(slug):
    # As board.sh's costs_value and costs_money: a block list's lines joined, lowercased, comments,
    # quotes, brackets, commas, dashes and spaces gone; anything but empty or none is money, and so is a
    # story that cannot be read (fails closed). An epic's costs: is ignored.
    text = story_text(slug)
    if text is None:
        return not is_epic(slug)
    v, on = None, False
    for line in front(text).splitlines():
        if on and re.fullmatch(r"\s*(#.*)?", line):
            continue
        if on and re.match(r"[\s-]", line):
            v += line.split("#", 1)[0]
            continue
        on = False
        if v is None and line.startswith("costs:"):
            v, on = line[6:].split("#", 1)[0], True
    return re.sub(r"[][\s\"',-]", "", v or "").lower() not in ("", "none")

stop = min(time.time(), (datetime.datetime.fromisoformat(until) + datetime.timedelta(days=1)).timestamp())
# keeping: slugs whose keeping close is still to come; dropped: a kept item's slug, and when the last
# close since may have dropped its build.
waiting, done, keeping, dropped = {}, [], set(), {}

def leave(slug, end):
    kind, start = waiting.pop(slug)
    dropped.pop(slug, None)
    done.append((start, end, f"{kind}:{slug}"))

rows = [f for f in (l.rstrip("\n").split("\t") for l in open(events, errors="ignore")) if len(f) == 5] if os.path.exists(events) else []
# The current build's kept line: a slug's last ok kept line after its last ok story line (a build's start).
# Only it can be the kept line of a child held now; an earlier one is an earlier build's.
last = {}
for n, f in enumerate(rows):
    if f[1] in ("kept", "story") and f[4].startswith("ok"):
        last[(f[1], f[2])] = n
for n, f in enumerate(rows):
    cmd, slug = f[1], f[2]
    if slug in keeping and cmd.split(":")[0] == "close":
        keeping.discard(slug)
        continue
    if not f[4].startswith("ok"):
        continue
    try:
        at = datetime.datetime.fromisoformat(f[0].replace("Z", "+00:00")).timestamp()
    except ValueError:
        continue
    kept = slug in waiting and waiting[slug][0] == "kept"
    if cmd == "kept":
        keeping.add(slug)
        if n == last[("kept", slug)] and n > last.get(("story", slug), -1) and blocked_now(slug, held_by=True):
            continue
        if slug in waiting:
            leave(slug, at)
        waiting[slug] = ("kept", at)
        continue
    if kept and cmd == "unblock":
        waiting.pop(slug)
        dropped.pop(slug, None)
        continue
    if kept and cmd.split(":")[0] == "close" and cmd != "close:impossible":
        dropped[slug] = at   # the last close: one that drops nothing (gh down) may come before it
        continue
    if kept and slug in dropped and cmd == "story":
        leave(slug, dropped[slug])
    elif slug in waiting and (cmd in LEAVE or (kept and cmd in ENTER)):
        leave(slug, dropped[slug] if cmd in LEAVE and slug in dropped and cmd not in ("finish", "reconcile") else at)
    if cmd in ENTER and slug not in waiting:
        if cmd != "review" or cfg.get("merge") != "agent" or costs_money(slug):
            waiting[slug] = (ENTER[cmd], at)
for slug, (kind, start) in waiting.items():
    if still_waiting(slug, kind):
        done.append((start, None, f"{kind}:{slug}"))
    elif slug in dropped and not blocked_now(slug):
        done.append((start, dropped[slug], f"{kind}:{slug}"))

days = {}
for start, end, name in done:
    day = datetime.datetime.fromtimestamp(start).date().isoformat()
    if since <= day <= until:
        days.setdefault(day, []).append(((min(end or stop, stop) - start) / 60, name if not end or end > stop else None))

print("day\titems\tmedian_min\tmax_min\topen")
for day, items in sorted(days.items()):
    mins = [m for m, _ in items]
    still = ",".join(sorted(s for _, s in items if s)) or "-"
    print(f"{day}\t{len(items)}\t{statistics.median(mins):.0f}\t{max(mins):.0f}\t{still}")

# No-agent items: a started story no agent works on, a failed step-up and a review agent that never
# started, named no-agent, step-up-failed and no-review after wait --lead's no-agent:, step-up failed:
# and no-review: lines. A failed review-agent start wakes the lead as ok (no-review) while its builder
# is listed, and as ok (no-agent) when the builder is gone too: that poll prints the no-agent: line. An
# item's clock starts at the events that explain the missing agent, as no_agent_events reads them, and
# runs to its lead-woken line, whose outcome names the kind; a wake with nothing waiting measures
# nothing. Each ok close of the builder or review agent starts it afresh (the newest close, as the poll
# times its row; an earlier close may be a handover to review long before any alert was due), and so do
# a review or kept line while an item waits, a step-up:failed line, and a review agent's failed start
# unless a no-review item already waits. A no-agent line or another failed start keeps the time it
# finds. A failed start while the builder is running starts the clock only when nothing waits (its pane
# may have gone with no close) and never opens the item, as the poll stays quiet while herdr lists the
# builder; a failed step-up or _step-up line enters nothing either (refused before it closed anything,
# or followed by step-up:failed). The wait ends unmeasured on a sign of a live agent (an ok start of the
# builder or review agent, an ok tell, a hold, or an ok upgrade naming the story's epic, backlog for
# none, or - for all, except for a failed step-up, whose marker the poll reports whatever an upgrade
# restarts) and on a reconcile that reopened the story (its PR closed unmerged), which keeps it out
# until its next ok start, as no_agent_events leaves it to unblock --startable. An item not woken is
# open only once a no-agent, step-up:failed or failed start line came since its newest close (that close
# may have cleared the build, and a plain close is how every build ends), and only while its story is
# ready, of a kind an agent builds, not held and with an ok builder start on record (a first start that
# failed leaves no build to alert on): a review story's alert depends on its PRs' costs and merge =
# agent, which only the poll reads, so it counts once woken and is never open. Per local day it entered:
# items, the median and maximum minutes to the wake (- when no item entered that day), and open; and per
# local day of the wake, woken_while_working: no-agent wakes whose slug had a builder started (an ok
# start other than review-agent) with no close or step-up:failed line since (step-up logs that line once
# it has closed the builder). A builder whose pane died with no close line looks the same in events.tsv,
# so a nonzero count is either an alert while the builder worked or a real one for a pane that went with
# no close; the story's events and herdr's record tell which. Printed under the table above only when
# the window has an item or a wake.
STARTS = set(os.environ.get("SWARM_NO_AGENT_STARTS", "").split())
NAME_MAX = int(os.environ.get("SWARM_AGENT_NAME_MAX") or 32)
AGENT_KINDS = os.environ.get("SWARM_AGENT_KINDS", "").split()
WOKEN = {"ok (no-agent)": "no-agent", "ok (step-up failed)": "step-up-failed", "ok (no-review)": "no-review"}

def agent_name(s):
    # As swarm.sh's agent_name: the name a close or herdr line gives <s>'s agent, cut to its limit.
    n = re.sub(r"[^a-z0-9_-]", "-", s.lower())
    return (n if re.match("[a-z]", n) else "s" + n)[:NAME_MAX]

def alert_waiting(slug):
    f = os.path.join(board, "stories", slug + ".md")
    if not os.path.isfile(f):
        return False
    state = os.path.join(project, ".swarm/board-state/stories", slug)
    status, k, held = (fm(f, state, x) for x in ("status", "kind", "held_for"))
    return status == "ready" and not held and (not k or k in AGENT_KINDS)

# Each agent name a line may give, to its story and whether it is the review agent's; a story's own slug
# first, so a story named review-<x> is never taken for x's review agent.
slugs = {f[2] for f in rows if f[1] in ("lead-woken", "no-agent", "step-up:failed", "review-agent")}
if os.path.isdir(os.path.join(board, "stories")):
    slugs |= {n[:-3] for n in os.listdir(os.path.join(board, "stories")) if n.endswith(".md")}
own = {s: (s, False) for s in slugs}
for s in sorted(slugs):
    for n, rev in ((agent_name(s), False), ("review-" + s, True), (agent_name("review-" + s), True)):
        own.setdefault(n, (s, rev))
# pending: slug -> (when it entered, its kind once a no-agent, step-up:failed or failed start line came).
pending, builder, built, reopened, alerts, working = {}, {}, set(), set(), [], []
def story_epic(slug):
    f = os.path.join(board, "stories", slug + ".md")
    return fm(f, os.path.join(project, ".swarm/board-state/stories", slug), "epic") if os.path.isfile(f) else ""

for f in rows:
    if f[1] == "upgrade" and f[4].startswith("ok"):
        for slug in [s for s in pending if pending[s][1] != "step-up-failed" and f[2] in ("-", story_epic(s) or "backlog")]:
            del pending[slug]
        continue
    if f[2] not in own:
        continue
    try:
        at = datetime.datetime.fromisoformat(f[0].replace("Z", "+00:00")).timestamp()
    except ValueError:
        continue
    (slug, rev), cmd, ok = own[f[2]], f[1], f[4].startswith("ok")
    base = cmd.split(":")[0]
    if cmd == "lead-woken":
        kind = WOKEN.get(f[4])
        if kind == "no-agent" and builder.get(slug):
            working.append(at)
        if kind and slug in pending:
            alerts.append((pending.pop(slug)[0], at, f"{kind}:{slug}"))
    elif base in ("step-up", "_step-up") and not ok and cmd != "step-up:failed":
        continue
    elif cmd == "reconcile" and f[4] == "ok (reopened)":
        pending.pop(slug, None)
        reopened.add(slug)
    elif cmd in ("no-agent", "step-up:failed") or (base in STARTS and not ok):
        if cmd == "step-up:failed":
            builder[slug] = False
        if slug in reopened:
            continue
        if cmd not in ("no-agent", "step-up:failed") and builder.get(slug):
            pending.setdefault(slug, (at, None))
            continue
        kind = "step-up-failed" if cmd == "step-up:failed" else "no-review" if rev or cmd == "review-agent" else "no-agent"
        start, was = pending.get(slug, (at, None))
        if kind != "no-agent" and was != kind:
            start, was = at, kind
        pending[slug] = (start, was or kind)
    elif base in STARTS:
        pending.pop(slug, None)
        reopened.discard(slug)
        if not rev and cmd != "review-agent":
            builder[slug] = True
            built.add(slug)
    elif base == "close" and ok:
        if slug not in reopened:
            pending[slug] = (at, None)
        if not rev:
            builder[slug] = False
    elif cmd in ("review", "kept") and ok and slug in pending:
        pending[slug] = (at, None)
    elif (base == "tell" and ok) or cmd == "hold":
        pending.pop(slug, None)
for slug, (start, kind) in pending.items():
    if kind and slug in built and alert_waiting(slug):
        alerts.append((start, None, f"{kind}:{slug}"))

nd = {}
for start, end, name in alerts:
    day = datetime.datetime.fromtimestamp(start).date().isoformat()
    if since <= day <= until:
        nd.setdefault(day, ([], []))[0].append(((min(end or stop, stop) - start) / 60, name if not end or end > stop else None))
for at in working:
    day = datetime.datetime.fromtimestamp(at).date().isoformat()
    if since <= day <= until:
        nd.setdefault(day, ([], []))[1].append(at)
if nd:
    print("no_agent_day\titems\tmedian_min\tmax_min\twoken_while_working\topen")
for day, (items, woke) in sorted(nd.items()):
    mins = [m for m, _ in items]
    still = ",".join(sorted(s for _, s in items if s)) or "-"
    med, top = (f"{statistics.median(mins):.0f}", f"{max(mins):.0f}") if mins else ("-", "-")
    print(f"{day}\t{len(items)}\t{med}\t{top}\t{len(woke)}\t{still}")

waits = sorted(m for items in days.values() for m, _ in items)
p90 = waits[-(-9 * len(waits) // 10) - 1] if waits else None
print("\nitems\tmedian_min\tp90_min\tmax_min")
print("\t".join([str(len(waits)), f"{statistics.median(waits):.0f}", f"{p90:.0f}", f"{waits[-1]:.0f}"] if waits else ["-"] * 4))
