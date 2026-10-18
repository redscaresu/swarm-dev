import collections, datetime, glob, itertools, json, os, re, subprocess, time
E = os.environ
from report import *
from panes import *
from stall import *
W = max(int(E.get("DASH_COLS") or 100), 40)
H = int(E.get("DASH_LINES") or 0)
# Now, and so today and the header's clock: SWARM_DASH_NOW (epoch seconds) fixes them, so a test's
# "today" holds across midnight and a golden frame is the same on every run.
NOW = float(E.get("SWARM_DASH_NOW") or time.time())
TODAY = datetime.date.fromtimestamp(NOW)
NARROW = W < 100   # stacked: the role and model columns and the recent actor column go
WIDE = W >= 140   # two columns: needs you and the epics on the left, recent as a log on the right
RW = W * 2 // 5 if WIDE else 0
LW = W - RW - 1 if WIDE else W
COLOR = E.get("DASH_COLOR") == "1"
KEYS = E.get("DASH_KEYS") == "1"
FIT = KEYS or E.get("DASH_FIT") == "1"   # cut to H: a watched frame, or a height given to dash (a share of --project's)
STYLE = {"h": "1;36", "ok": "32", "warn": "33", "bad": "1;31", "dim": "2", "b": "1", "grey": "90"}
# One status vocabulary: the symbol carries the meaning in plain text, the colour on a terminal.
SYM = {"working": ("●", "ok"), "ready": ("○", "h"), "review": ("◐", "warn"), "done": ("✓", "ok"), "failed": ("✗", "bad"),
       "blocked": ("⏸", "grey"), "look": ("!", "bad"), "unknown": ("?", "")}
# A colour per model (256-colour ANSI), the same wherever it shows: its name in that colour, and from
# 140 columns a label on that colour.
MODEL_COLOR = {"fable": 213, "opus": 208, "sonnet": 75, "haiku": 114, "codex": 250}
for m, c in MODEL_COLOR.items():
    STYLE[m], STYLE[m + "-label"] = f"38;5;{c}", f"38;5;16;48;5;{c}"

def model_style(model, label=False):
    k = next((m for m in MODEL_COLOR if m in model.lower()), None)
    return (k + "-label" if label else k) if k else "dim"

from dash_legend import *
out = []

def paint(t, s):
    return f"\033[{STYLE[s]}m{t}\033[0m" if COLOR and s and t else t

def sym(k):
    return SYM[k][0] + " ", SYM[k][1]

def cut(t, n):
    return t if len(t) <= n else t[:max(n - 1, 0)] + "…"

def fit(segs, n):
    # Truncate, never wrap: plain lengths are measured before any colour is added.
    res, left = [], n
    for t, s in segs:
        if left <= 0:
            break
        t = cut(t, left)
        res.append(paint(t, s)); left -= len(t)
    return "".join(res) + " " * left

def wrap(segs, n, indent=2):
    # Word-wrap styled segments into lines of at most n, the later lines indented; only a single
    # word longer than a line is cut (by fit).
    lines, cur, used = [], [], 0
    for t, s in segs:
        for w in re.findall(r"\s*\S+\s*|\s+", t):
            if cur and used + len(w.rstrip()) > n:
                lines.append(cur[:-1] + [(cur[-1][0].rstrip(), cur[-1][1])])
                cur, used, w = [(" " * indent, "")], indent, w.lstrip()
            cur.append((w, s)); used += len(w)
    return lines + [cur] if cur else lines

def box(title, rows, w, style="h"):
    res = ["╭─ " + paint(title, style) + " " + "─" * max(w - len(title) - 5, 0) + "╮"]
    for r in rows or [[("(none)", "dim")]]:
        res.append("│ " + fit([(r, "")] if isinstance(r, str) else r, w - 4) + " │")
    return res + ["╰" + "─" * (w - 2) + "╯"]

def read_tsv(path, n):
    try:
        return [f for f in (l.rstrip("\n").split("\t") for l in open(path, encoding="utf-8", errors="replace")) if len(f) == n]
    except OSError:
        return []

def lines(key):
    return [l for l in E.get(key, "").splitlines() if l.strip()]

# The board: dir, slug, status, prs, agent name, conductor name, epic, kind, title, you, its **You:** text (dash_fields').
board = [(l.split("\t") + [""] * 11)[:11] for l in lines("DASH_BOARD")]
stories = [b for b in board if b[0] == "stories"]
story_rows = [(b[1], b[4], b[2]) for b in stories]
story_by_slug = {b[1]: b for b in stories}
epics = collections.OrderedDict((b[1], b) for b in board if b[0] == "epics")
epic_of = {b[5]: b[1] for b in epics.values()}
# An active epic with no stories -> the depends_on slugs that hold its planning up (dash_render's DASH_EPIC_WAITS).
waits = dict(l.split("\t", 1) for l in lines("DASH_EPIC_WAITS") if "\t" in l)
finished = collections.Counter()
for l in lines("DASH_FINISHED"):
    e, _, n = l.partition("\t")
    finished[e] += int(n) if n.isdigit() else 0

PRS = {}
for l in lines("DASH_PRSTATE"):
    url, _, j = l.partition("\t")
    try:
        PRS[url] = json.loads(j)
    except ValueError:
        pass
URL = re.compile(r"https://github\.com/([^/\s]+)/([^/\s]+)/pull/(\d+)")
# A builder's open PR on story/<slug> (dash_slow's), for a story whose file lists none yet.
HEADS = dict(l.split("\t", 1) for l in lines("DASH_HEADS") if "\t" in l)
FAILED = ("FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE")

def pr_state(url):
    # (vocabulary key, words) for a PR's checks and merge state; None when gh gave nothing.
    s = PRS.get(url)
    if not isinstance(s, dict):
        return None
    roll = s.get("statusCheckRollup") or []
    bad = any((c.get("conclusion") or c.get("state") or "").upper() in FAILED for c in roll)
    running = any((c.get("status") or "COMPLETED").upper() != "COMPLETED" or (c.get("state") or "").upper() in ("PENDING", "EXPECTED") for c in roll)
    k, words = ("failed", "failing") if bad else ("review", "CI running") if running else ("done", "green") if roll else ("review", "no checks")
    behind = {"BEHIND": " · behind", "DIRTY": " · conflicts"}.get((s.get("mergeStateStatus") or "").upper(), "")
    return k, words + behind

def is_open(url):
    # A PR gh did not say is merged or closed counts as open.
    return (PRS.get(url) or {}).get("state", "OPEN").upper() not in ("MERGED", "CLOSED")

def builder_prs(slug):
    # A story's PRs, and its builder's open story/<slug> PR (HEADS) while none it lists is open: a
    # retry's PR beside the closed one an earlier attempt left on the story.
    listed = (story_by_slug.get(slug) or [""] * 4)[3]
    if any(is_open(m.group(0)) for m in URL.finditer(listed)) or not HEADS.get(slug or ""):
        return listed
    return f"{listed} {HEADS[slug]}".strip()

def pr_ref(m):
    return f"{m.group(2)}#{m.group(3)}"

# Agents: this project's panes (its tab records). A working agent shows how long since its last sign
# of life (STALL_PY's stall_age); past stall_minutes it is stalled, and needs you. A story's builder
# counts its worktree's commits and PR updates; an agent with no story (a conductor or planner)
# its own events.tsv lines: by target, and once it has a start line, by the pane that ran them.
commit_of = dict(l.split("\t", 1) for l in E.get("DASH_COMMITS", "").splitlines() if "\t" in l)
seen = last_seen(E["DASH_EVENTS"])
STARTS = ("agent", "conduct", "story")
started = {}   # target -> when its newest start (agent, conduct or story) in events.tsv ran
ran = {}       # pane -> when the newest sign of life it ran (STALL_PY's sign_time) was written
for f in read_tsv(E["DASH_EVENTS"], 5):
    t = sign_time(f)
    if t is not None and t > ran.get(f[3], 0):
        ran[f[3]] = t
    t = epoch(f[0]) if f[1] in STARTS and f[4] == "ok" else None
    if t is not None and t > started.get(f[2], 0):
        started[f[2]] = t
# Escalation: today's ok escalate builds, and each slug's newest one (its attempt and when).
ESCALATION = ("escalate", "dialog", "escalated", "reset", "reset:held", "drop")
escalations, escalated_at, was_reset = 0, {}, set()   # was_reset: slugs with an ok reset (reset_at's rule)
for f in read_tsv(E["DASH_EVENTS"], 5):
    if f[1] == "reset" and f[4].startswith("ok"):
        was_reset.add(f[2])
    t = epoch(f[0]) if f[1] == "escalate" else None
    m = re.match(r"ok \(attempt (\d+)\)", f[4])
    if t is None or not f[4].startswith("ok"):
        continue
    escalations += datetime.date.fromtimestamp(t) == TODAY
    if m and t > escalated_at.get(f[2], (0,))[0]:
        escalated_at[f[2]] = (t, m.group(1))
recs, stalled = [], []
try:
    agents = {a.get("pane_id"): a for a in json.loads(E["DASH_AGENTS"])["result"]["agents"]}
    live = {p["pane_id"] for p in json.loads(E["DASH_PANES"])["result"]["panes"]}
except (ValueError, KeyError, TypeError):
    agents = None
try:   # labels only: without them the tree names each workspace by its id
    ws_label = {w["workspace_id"]: w.get("label") or w["workspace_id"] for w in json.loads(E["DASH_WORKSPACES"])["result"]["workspaces"]}
except (ValueError, KeyError, TypeError):
    ws_label = {}

def reported(base):
    # A conductor that wrote its report, which the lead has not collected yet.
    epic = epic_of.get(base) or ("backlog" if base == E.get("DASH_BACKLOG") else base[len("conduct-"):] if base.startswith("conduct-") else "")
    return bool(epic) and os.path.exists(os.path.join(E["DASH_PROJECT"], ".swarm", f"conduct-{epic}.report.md"))

def epic_for(base, slug, tab):
    if base in epic_of:
        return epic_of[base]
    if slug:
        return story_by_slug[slug][6] or None
    if tab in epics:
        return tab
    return (story_by_slug.get(tab) or [""] * 10)[6] or None

def scan_tail(entries):
    # Newest first: (the newest entry's timestamp, the newest tool it ran, the newest reply's text).
    t = tool = reply = None
    for l in reversed(entries):
        try:
            d = json.loads(l)
        except ValueError:
            continue
        if not isinstance(d, dict):
            continue
        t = t or d.get("timestamp")
        msg = d.get("message") if d.get("type") == "assistant" else None
        content = msg.get("content") if isinstance(msg, dict) else None
        for c in reversed(content) if isinstance(content, list) else []:
            if isinstance(c, dict) and c.get("type") == "tool_use" and tool is None:
                tool = str(c.get("name") or "")
            if isinstance(c, dict) and c.get("type") == "text" and reply is None:
                reply = str(c.get("text") or "")
        if t and tool is not None and reply is not None:
            break
    return t, tool, reply

def tail_of(rec, reply_wanted):
    # An agent's last activity from its session log (agents.tsv's session), read from its last 64 KB
    # so every frame can afford it, and from 4 times as much while that misses the newest timestamp,
    # tool or (when reply_wanted: only an idle one-off builder's IMPOSSIBLE check needs it) reply, as a
    # big Write entry cut there does: (the newest entry's timestamp, the newest tool it ran, whether
    # its newest reply starts IMPOSSIBLE:). (None, "", False) with no log.
    # ponytail: at most the last 4 MB per frame; a tool or reply older than that is not found.
    path = session_log(E["DASH_PROJECTS"], rec[6]) if rec else ""
    size = 65536
    try:
        with open(path, "rb") as f:
            end = f.seek(0, 2)
            while True:
                f.seek(max(end - size, 0))
                t, tool, reply = scan_tail(f.read().decode("utf-8", "replace").splitlines())
                if (t and tool is not None and (reply is not None or not reply_wanted)) or size >= min(end, 1 << 22):
                    break
                size *= 4
    except OSError:
        return None, "", False
    return t, tool or "", (reply or "").lstrip().startswith("IMPOSSIBLE:")

if agents is not None:
    by_session, by_name = {}, {}
    for f in read_tsv(E["DASH_AGENTS_LOG"], 7):
        by_name[f[2]] = by_session[f[6]] = f
    for label, pane, recorded in pane_records(E["DASH_STATE"], set(E.get("SWARM_OWN", "").split()) & live):
        r = {"ws": ws_label.get(pane.split(":")[0], pane.split(":")[0]), "tab": label, "name": recorded, "role": "?",
             "model": "?", "look": True, "slug": None, "epic": epic_for("", None, label)}
        try:
            a = agents.get(pane)
            name = (a or {}).get("name") or recorded
            base = re.sub(r"-done\d*$", "", name)
            rec = by_session.get(((a or {}).get("agent_session") or {}).get("value", "")) or by_name.get(base)
            s = session_state(E["DASH_AGENTS_LOG"], name, E["DASH_SESSIONS"])
            st, look = shown_state(a, name, s, E["DASH_AGENTS_LOG"], E["DASH_PROJECTS"])
            if st in ("idle", "done") and reported(base):
                st = "reported"
            slug = story_for(name, story_rows)
            why = s[1] if s and st == "WAITING" else ""
            words = {"EMPTY": "empty pane", "WAITING": f"waiting on {why or 'a prompt'}", "done": "idle", "auth": "auth: login expired",
                     "gone": "gone: session ended", "unknown": "unknown: no session state" if s else "unknown"}.get(st, st)
            since = started.get(slug) or started.get(epic_of.get(base)) or started.get(base)
            if st == "working":
                # Any agent with a Claude session: its session log, written on every turn and tool call.
                log = session_log(E["DASH_PROJECTS"], rec[6]) if rec else ""
                try:
                    logged = os.path.getmtime(log) if log else None
                except OSError:   # removed since the glob: no sign
                    logged = None
                if slug:
                    signs = [commit_of.get(slug, ""), logged] + [(PRS.get(m.group(0)) or {}).get("updatedAt") for m in URL.finditer(story_by_slug[slug][3])]
                    age, lack = stall_age(seen, slug, base, signs, NOW), "no commit, edit, session-log write or PR update"
                else:
                    age, lack = stall_age(seen, epic_of.get(base), base, ([since, ran.get(pane)] if since else []) + [logged], NOW), "no swarm action"
                if age is not None and age >= int(E["DASH_STALL_MIN"]):
                    st, look, words = "stalled", True, f"stalled {age}m"
                    stalled.append((name, age, lack))
                elif age is not None:
                    words = f"working {age}m"
            r.update(name=name, role=rec[1] if rec else "?", model=(f"{rec[4] if rec[3] == 'claude' else rec[3]}·{rec[5]}") if rec else "?",
                     look=look, why=why, slug=slug, epic=epic_for(base, slug, label), state=st, words=words, prs=builder_prs(slug),
                     open=bool(slug) and story_by_slug[slug][2] != "done",
                     since=since, day=rec[0] if rec else "", tail=tail_of(rec, bool(slug) and st in ("idle", "done") and epic_for(base, slug, label) not in epics),
                     escalated=escalated_at.get(slug or base) if rec and rec[1] == "escalate" else None)
        except Exception as err:  # one odd agent record must not cost the whole panel
            r.update(state="unreadable", words=f"unreadable: {type(err).__name__}", prs="", open=False)
        r["sym"] = "look" if r["look"] else {"working": "working", "reported": "done", "idle": "done", "done": "done", "retired": "done"}.get(r["state"], "unknown")
        recs.append(r)

# Shown: what needs a look, works, reported, or is tied to an open story; the rest is one +N idle.
shown = [r for r in recs if r["look"] or r["state"] in ("working", "reported") or r["open"]]
idle = len(recs) - len(shown)

# Running codex reviews (codex-review's markers): one row each, under the epic of its worktree's story
# (or of its epic-<epic> worktree), never in needs you or the lead's queue. A marker whose pid is dead
# or that is older than codex_minutes plus 1 shows nothing; dash only reads, so it leaves both.
def alive(pid):
    try:
        os.kill(pid, 0)
    except PermissionError:
        return True
    except OSError:
        return False
    return True

for path in sorted(glob.glob(os.path.join(E["DASH_STATE"], "codex-review.*"))):
    try:
        pid = int(path.rsplit(".", 1)[1])
        t, base, cwd = open(path).read().rstrip("\n").split("\t", 2)
        age = max(int(NOW - float(t)) // 60, 0)
    except (OSError, ValueError):
        continue
    if pid <= 0 or not alive(pid) or NOW - float(t) > (int(E["DASH_CODEX_MIN"]) + 1) * 60:
        continue
    wt = os.path.basename(cwd.rstrip("/"))
    # The name column is cut at name_w, so the base goes with the age, in the words.
    shown.append({"name": f"codex review {wt}", "role": "codex", "model": "codex", "words": f"running {age}m vs {base}",
                  "state": "codex", "sym": "working", "look": False, "open": False, "prs": "",
                  "epic": epic_for("", None, re.sub(r"^epic-", "", wt))})

# Needs you: only what you act on, each as a short action. With lead = session a lead session acts
# for you, so needs you keeps your steps (a story's **You:** line, an expired login, a draft epic) and
# the rest goes to the lead's queue (lq); with lead off, lq is needs you. Of the stories with a
# **You:** step only the first is listed, with +N more for the rest (more).
need, blocked, later, green, need_slugs, held_seen = [], 0, 0, 0, set(), set()
LEAD = E.get("DASH_LEAD") == "session"
queue = []
lq = queue if LEAD else need
bang = [sym("look")]
waiting = []   # (dir, slug) of the board item each row waits on, where it names one: the first light's age
yours, more = None, 0

def add(rows, row, item=None):
    rows.append(row)
    if item:
        waiting.append(item)

def story_title(slug):
    title = (story_by_slug.get(slug) or [""] * 10)[8]
    return f": {title[:1].lower()}{title[1:]}" if title and title != slug else ""

for l in lines("DASH_WAITING"):
    l = l.strip()
    if l.startswith("blocked:"):
        blocked += 1
        continue
    if l.startswith("later "):
        later += 1
        continue
    if l.startswith("draft epic: "):
        continue  # the board's draft epics have their own needs-you row below
    m = re.match(r"awaiting your merge( \(costs money\))?: (epic )?(\S+) ?(.*)$", l)
    if m:
        # With merge = agent, swarm.sh merge holds a costs: money story for the user, so no lead
        # session can merge it; with merge = human the lead may, when the user asks.
        rows = need if m.group(1) and E["DASH_MERGE"] == "agent" else lq
        what = ("epic " if m.group(2) else "") + m.group(3) + (" (costs money)" if m.group(1) else "")
        item = ("epics" if m.group(2) else "stories", m.group(3))
        urls = list(URL.finditer(m.group(4)))
        if m.group(1):
            # A held PR is listed once, under the first item naming it (a story and its epic both may).
            urls = [u for u in urls if u.group(0) not in held_seen]
            if not urls:
                continue
            held_seen.update(u.group(0) for u in urls)
        if not urls:
            add(rows, bang + [(f"merge {what}: no PR on its file", "")], item)
        for u in urls:
            st = pr_state(u.group(0))
            if st is None:
                add(rows, bang + [(f"merge {what}: ", ""), (u.group(0), "dim")], item)
                continue
            green += st[0] == "done"
            add(rows, bang + [(f"merge {pr_ref(u)} (", ""), (SYM[st[0]][0] + " " + st[1], SYM[st[0]][1]), (")  ", ""), (what, "dim")], item)
        continue
    m = re.match(r"(\S+): (\S+)$", l)
    if m:
        slug = m.group(2)
        need_slugs.add(slug)
        b = story_by_slug.get(slug) or [""] * 11
        row = bang + [(f"run {m.group(1)} story {slug}{story_title(slug)}", ""), ("  waits for: ", "dim")]
        if b[9] != "you":
            add(lq, row + [("the lead", "")], ("stories", slug))
        elif yours is None:
            yours = row + [("you" + (f": {b[10]}" if b[10] else ""), "")]
            add(need, yours, ("stories", slug))
        else:
            more += 1
            waiting.append(("stories", slug))
    else:
        lq.append(bang + [(l, "")])
if more:
    yours.append((f"  +{more} more", "dim"))
# An escalated lead story, impossible or failed on Fable, is the lead's (next's escalated step): waiting_on_user
# leaves it out, so only the lead's queue shows it. Once reset, drop is all that is left, except for a
# held story, whose hold reset always lifts (as next says).
if LEAD:
    for b in stories:
        if b[2] == "ready" and b[7] == "lead" and b[9] in ("escalated", "held"):
            add(queue, bang + [(f"decide escalated story {b[1]}{story_title(b[1])}: ", ""),
                               (("" if b[1] in was_reset and b[9] != "held" else f"swarm.sh reset {b[1]} or ") + f"swarm.sh drop {b[1]}", "dim")],
                ("stories", b[1]))
for r in recs:
    item = ("stories", r["slug"]) if r.get("slug") else None
    if r["state"] == "WAITING":
        why = f" (waiting on {r['why']})" if r.get("why") else ""
        add(lq, bang + [(f"answer {r['name']}{why}: ", ""), (f"herdr agent read {r['name']}", "dim")], item)
    elif r["state"] == "auth":
        add(need, bang + [(f"auth: run /login ({r['name']}'s login expired), then /swarm-dev:swarm tells it to resume", "")], item)
    elif r["state"] == "EMPTY":
        add(lq, bang + [(f"close the empty pane {r['name']}: ", ""), ("swarm.sh tidy", "dim")], item)
    elif r["state"] in ("gone", "unknown") and r["look"]:
        add(lq, bang + [(f"look at {r['name']}: " + ("session ended" if r["state"] == "gone" else "no session state"), "")], item)
lq += [bang + [(f"look at {n}: working {age} min with {lack}", "")] for n, age, lack in stalled]
for b in board:
    if b[0] == "epics" and b[2] == "draft":
        add(need, bang + [(f"agree draft epic {b[1]}: ", ""), (f"/epic {b[1]}", "dim")], ("epics", b[1]))

# Epics: one row per active epic (and any other epic an agent shown works for), its progress, then
# its live agents and open PRs beneath it.
def one_off(r):
    # An idle one-off builder (its story on no epic) says what it waits on, never a bare idle.
    if r.get("epic") in epics or not r.get("slug") or r["state"] not in ("idle", "done"):
        return r
    pr = next((m for m in URL.finditer(r["prs"]) if is_open(m.group(0))), None)
    ref = f"#{pr.group(3)} " if pr else ""
    wait = ("IMPOSSIBLE" if (r.get("tail") or (0, 0, False))[2] else "waits for the lead's merge" if story_by_slug[r["slug"]][2] == "review"
            else "waits for review" if pr else "no PR yet")
    return dict(r, words=ref + wait)

shown = [one_off(r) for r in shown]   # before any width is measured
groups = collections.OrderedDict((s, []) for s, b in epics.items() if b[2] == "active")
for r in shown:
    groups.setdefault(r["epic"] if r["epic"] in epics else "", []).append(r)
name_w = min(max((len(r["name"]) for r in shown), default=0), 30 if not NARROW else max(12, (W - 20) // 2))

def agent_cols(r):
    # Role and model, then the state (a working agent's with its age); from 140 columns the model is
    # a label in its colour, and a working agent shows how long since it started.
    row = []
    if WIDE:
        label = f" {r['model']} "
        row = [(f"{r['role']:<10} ", "dim"), (label, model_style(r["model"], True)), (" " * max(16 - len(label), 1), "")]
    elif not NARROW:
        row = [(f"{r['role']:<10} ", "dim"), (f"{r['model']:<12} ", model_style(r["model"]))]
    row.append((r["words"], SYM[r["sym"]][1] if r["sym"] != "done" else "dim"))
    if WIDE and r.get("state") == "working" and r.get("since"):
        m = max(int(NOW - r["since"]) // 60, 0)
        row.append((f"  {m}m" if m < 60 else f"  {m // 60}h{m % 60:02d}m", "dim"))
    if r.get("escalated"):
        t, n = r["escalated"]
        row.append((f"  attempt {n} · {datetime.datetime.fromtimestamp(t).strftime('%H:%M')}", "fable"))
    return row

def agent_row(r):
    return [("  ", ""), sym(r["sym"]), (f"{cut(r['name'], name_w):<{name_w}}  ", "")] + agent_cols(r)

if WIDE:
    # The left column takes what its widest agent card needs from recent's, down to a third of the
    # screen, so a card's state age never cuts the escalation time after it.
    grow = min(max((sum(len(t) for t, _ in agent_row(r)) + 4 for r in shown), default=0) - LW, RW - W // 3)
    if grow > 0:
        LW, RW = LW + grow, RW - grow

def epic_label(slug):
    return slug if epics[slug][2] == "active" else f"{slug} ({epics[slug][2]})"

def epic_rows(slug, members):
    if not slug:
        return [[("  ", ""), ("no epic", "dim")]] + [agent_row(r) for r in members]
    mine = [b for b in stories if b[6] == slug]
    done = finished[slug] + sum(b[2] == "done" for b in mine)
    left = collections.Counter(b[2] or "?" for b in mine if b[2] != "done")
    total = done + sum(left.values())
    prs = [(m, b[1]) for b in mine + [epics[slug]] if b[2] != "done" for m in URL.finditer(b[3])]
    states = [pr_state(m.group(0)) for m, _ in prs]
    k = ("look" if any(r["look"] for r in members) or any(s and s[0] == "failed" for s in states) or any(b[1] in need_slugs for b in mine)
         else "working" if any(r["state"] == "working" for r in members)
         else "review" if prs or left["review"] else "blocked" if slug in waits else "done" if not left else "ready" if left["ready"]
         else "blocked" if set(left) <= {"blocked", "later"} else "unknown")
    bar_w = 6 if NARROW else 12
    fill = round(bar_w * done / total) if total else 0
    order = ["review", "ready", "blocked", "later"]
    counts = " · ".join(f"{left[s]} {s}" for s in order + sorted(s for s in left if s not in order) if left[s])
    rows = [[sym(k), (f"{cut(epic_label(slug), epic_w):<{epic_w}}  ", "b"), ("█" * fill, "ok"), ("░" * (bar_w - fill), "dim"),
             (f" {done:>2}/{total:<2}  " if total else "   –   ", ""), (counts or (f"waits on {', '.join(waits[slug].split())}" if slug in waits else "" if total else "no stories on the board or in git"), "dim")]]
    rows += [agent_row(r) for r in members]
    for (m, owner), st in zip(prs, states):
        k = st[0] if st else "review"
        rows.append([("  ", ""), sym(k), (f"{cut(pr_ref(m), name_w):<{name_w}}  ", ""), (st[1] if st else "checks unknown", SYM[k][1]),
                     (f"  {owner}", "dim")])
    return rows

def rank(item):
    # Epics that need you, then working ones, then the rest; agents with no epic last.
    slug, members = item
    if not slug:
        return 3
    if any(r["look"] for r in members) or any(b[6] == slug and b[1] in need_slugs for b in stories):
        return 0
    return 1 if any(r["state"] == "working" for r in members) else 2

# An active epic with no open story and no agent shown is one line for them all, unless its
# depends_on holds it up (DASH_EPIC_WAITS): it keeps its own row, which names what it waits on.
quiet = [s for s, m in groups.items() if s and not m and s not in waits and not any(b[6] == s and b[2] != "done" for b in stories)]
groups = collections.OrderedDict((s, m) for s, m in groups.items() if s not in quiet)
epic_w = min(max((len(epic_label(s)) for s in groups if s), default=0), LW // 3)
epic_view = [row for item in sorted(groups.items(), key=rank) for row in epic_rows(*item)]
if quiet:
    epic_view.append([sym("done"), (f"{len(quiet)} active epic{'' if len(quiet) == 1 else 's'} with no open story: {', '.join(quiet)}", "dim")])
if agents is None:
    epic_view.append([("agents unavailable: herdr is not on PATH, or gave no list", "dim")])
if idle:
    epic_view.append([(f"+{idle} idle", "dim"), ("  (t shows the tree)" if KEYS else "  (--tree lists them)", "dim")])

# The tree (t, or --tree): every agent of this project's panes, by herdr workspace, then tab.
def tree_view():
    if agents is None:
        return [[("agents unavailable: herdr is not on PATH, or gave no list", "dim")]]
    tree = collections.OrderedDict()
    for r in recs:
        tree.setdefault(r["ws"], collections.OrderedDict()).setdefault(r["tab"], []).append(r)
    width = min(max((len(r["name"]) for r in recs), default=0), 30)
    rows = []
    for ws, tabs in tree.items():
        rows.append([(ws, "b")])
        for i, (tab, items) in enumerate(tabs.items()):
            last_tab = i == len(tabs) - 1
            rows.append([(" └─ " if last_tab else " ├─ ", "dim"), (tab, "h")])
            for j, r in enumerate(items):
                stem = ("    " if last_tab else " │  ") + ("└─ " if j == len(items) - 1 else "├─ ")
                row = [(stem, "dim"), sym(r["sym"]), (f"{cut(r['name'], width):<{width}}  ", "")] + agent_cols(one_off(r))
                rows.append(row + [(f"  {r['prs']}" if r["prs"] else "", "dim")])
    return rows or [[("no agents open in this project's panes", "dim")]]

# Recent: swarm actions (events.tsv), merges on the base branch and fixed findings, newest first.
# Findings are one row per PR and day, and at most a third of the rows, so they never crowd out the rest.
def when(s):
    # (sort time, relative time). A date alone (findings.tsv) sorts as the end of that local day,
    # after the day's timed events, and reads in calendar days: today, yesterday, Nd ago.
    try:
        if len(s) == 10:
            days = (TODAY - datetime.date.fromisoformat(s)).days
            return (datetime.datetime.fromisoformat(s + "T23:59:59").astimezone(),
                    "today" if days <= 0 else "yesterday" if days == 1 else f"{days}d ago")
        t = datetime.datetime.fromisoformat(s.replace("Z", "+00:00"))
        if t.tzinfo is None:
            t = t.astimezone()
        secs = max(int(NOW - t.timestamp()), 0)
        if secs < 86400:
            return t, "now" if secs < 60 else f"{secs // 60}m ago" if secs < 3600 else f"{secs // 3600}h ago"
        days = (TODAY - t.astimezone().date()).days   # a day or more: calendar days, as for a date
        return t, "yesterday" if days <= 1 else f"{days}d ago"
    except ValueError:
        return None, s

events = []   # (time, actor, text, icon key)
for l in lines("DASH_MERGES"):
    f = l.split("\t", 2)
    if len(f) == 3:
        m = re.match(r"Merge pull request #(\d+) from [^/\s]+/(\S+)", f[2])
        events.append((f[0], f[1], f"merged #{m.group(1)} {m.group(2)}" if m else f[2], "merge"))
found = collections.OrderedDict()
for f in fixed_rows(E["DASH_FINDINGS"]):
    m = re.search(r"(\d+)\D*$", f[2])
    found.setdefault((f[0], m.group(1) if m else f[2]), []).append(f)
for (day, pr), fs in found.items():
    text = fs[0][3] if len(fs) == 1 else f"{len(fs)} findings: " + "; ".join(x[3] for x in fs)
    events.append((day, fs[0][1] if len(fs) == 1 else "findings", f"{text} (#{pr})", "finding"))
# A fixed finding's log-finding line is left out: its findings.tsv row above shows it. A run of ok
# declined lines on one PR, with nothing but fixed ones between, is one row at the newest's time, and
# so is a run of lines with the same action, target and outcome, with ×N.
run = None   # [index in events, PR, count] of the declined run still open
same = None   # [index in events, line, count] of the run of the same line still open
for f in read_tsv(E["DASH_EVENTS"], 5):
    ok = f[4].startswith("ok")
    if f[1] == "log-finding" and ok:
        continue
    pr = pr_key((f[2].split() or [""])[-1])
    if f[1] == "log-finding:declined" and ok and run and run[1] == pr:
        run[2] += 1
        events[run[0]] = (f[0], f[3], f"{run[2]} findings declined on #{pr.rsplit('#', 1)[-1]}", "action")
        continue
    run = [len(events), pr, 1] if f[1] == "log-finding:declined" and ok else None
    text = f"{f[1]} {f[2]}" + ("" if f[4] == "ok" else f": {f[4]}")
    kind = "failed" if not ok else "start" if f[1] in STARTS else "escalation" if f[1] in ESCALATION else "action"
    if same and same[1] == f[1:3] + f[4:]:
        same[2] += 1
        events[same[0]] = (f[0], f[3], f"{text} ×{same[2]}", kind)
        continue
    same = [len(events), f[1:3] + f[4:], 1]
    events.append((f[0], f[3], text, kind))
ICON = {"merge": ("⇡", "ok"), "finding": ("✎", "warn"), "start": ("▶", "ok"), "action": ("·", "dim"), "failed": ("✗", "bad"),
        "escalation": ("▲", "fable")}
dated = sorted(((when(e[0]), e) for e in events if when(e[0])[0]), key=lambda x: x[0][0], reverse=True)

def stamp(raw, t):
    # The log's time column: HH:MM today, the date before; a dated finding of today is "today".
    t = t.astimezone()
    return t.strftime("%m-%d") if t.date() != TODAY else "today" if len(raw) == 10 else t.strftime("%H:%M")

def recent_box(w, n, clock=False):
    rec, findings = [], 0
    actor_w = 0 if w < 100 else 14
    tw = 5 if clock else 9
    for (t, ago), (raw, actor, text, kind) in dated:
        if len(rec) >= n:
            break
        if kind == "finding":
            findings += 1
            if findings > max(1, n // 3):
                continue
        room = max(w - 4 - tw - 2 - 2 - (actor_w + 2 if actor_w else 0), 0)
        # A finding's (#PR) is kept whole, its text cut instead, while the column has room for more than it.
        pr = re.search(r" \(#\d+\)$", text) if kind == "finding" else None
        text = cut(text[:pr.start()], room - len(pr.group(0))) + pr.group(0) if pr and room > len(pr.group(0)) and len(text) > room else cut(text, room)
        row = [(f"{stamp(raw, t) if clock else ago:>{tw}}  ", "dim"), (ICON[kind][0] + " ", ICON[kind][1]), (text.ljust(room), "")]
        if actor_w:
            row.append((f"  {cut(actor, actor_w):>{actor_w}}", "dim"))
        rec.append(row)
    return box("recent", rec, w)

def line_model(l):
    # A log line's model, or "" for none, a non-string, or "<synthetic>" (a failed turn's entry).
    try:
        m = (json.loads(l).get("message") or {}).get("model")
    except (ValueError, AttributeError):
        return ""
    return m if isinstance(m, str) and not m.startswith("<") else ""

def first_model(path):
    # The first real model in a session's log; reading stops there, so a --watch redraw stays
    # cheap. An unreadable log names none, as a missing one does.
    try:
        with open(path, errors="ignore") as f:
            m = next((m for m in map(line_model, f) if m), "")
    except OSError:
        return ""
    return next((k for k in MODEL_COLOR if k in m.lower()), m)

def ladder_box(w):
    # Per role: its policy model, then how many agents agents.tsv recorded and the models their
    # sessions ran on (a session with no log or no model counts but names none). The cell is the
    # longest row plus a gap, so no row runs into the next.
    ran = collections.defaultdict(lambda: [0, set()])
    for f in read_tsv(E["DASH_AGENTS_LOG"], 7):
        path = session_log(E["DASH_PROJECTS"], f[6])
        ran[f[1]][0] += 1
        ran[f[1]][1].add(first_model(path) if path else "")
    rows = []
    for p in (l.split() for l in lines("DASH_POLICY")):
        n, models = ran[p[0]]
        m = f"{p[2] if p[1] == 'claude' else p[1]} · {p[3]}"
        rows.append([(f"{p[0]:<11}→ ", ""), (m, model_style(m)), (f"  {n}", "dim")] + [(" " + x, model_style(x)) for x in sorted(models - {""})])
    cell = max((sum(len(t) for t, _ in r) for r in rows), default=0) + 2
    rows = [r + [(" " * (cell - sum(len(t) for t, _ in r)), "")] for r in rows]
    per = max(1, (w - 4) // cell)
    return box("ladder", [sum(rows[i:i + per], []) for i in range(0, len(rows), per)], w)

# Running now: each open agent with how long it has run (its events.tsv start, else its agents.tsv
# day from midnight), its last activity (its session log's newest entry and tool) and, for a builder,
# its PR and CI state; then each held story with its cause. Empty when nothing is open or held.
def held_cause(slug):
    try:
        text = open(os.path.join(E["DASH_BOARD_DIR"], "stories", slug + ".md"), encoding="utf-8", errors="replace").read()
    except OSError:
        return ""
    m = re.search(r"^held_for: *(.*?)\r?$", text.split("\n---", 1)[0], re.M)
    return m.group(1) if m else ""

def dur(s):
    m = max(int(s) // 60, 0)
    return f"{m}m" if m < 60 else f"{m // 60}h{m % 60:02d}m" if m < 1440 else f"{m // 1440}d"

def running_view():
    cells = []
    for r in recs:
        if r["state"] in ("EMPTY", "retired"):
            continue
        try:
            up = r.get("since") or datetime.datetime.strptime(r.get("day", ""), "%Y-%m-%d").timestamp()
        except ValueError:
            up = None
        t, tool, _ = r.get("tail") or (None, "", False)
        ago = when(t)[1] if isinstance(t, str) else ""
        act = f"{tool} {ago}" if tool and ago else ago or "no session log"
        pr = []
        for m in URL.finditer(r.get("prs") or "") if r.get("slug") else []:
            if not is_open(m.group(0)):
                continue
            st = pr_state(m.group(0))
            pr.append((f"#{m.group(3)} {st[1] if st else 'checks unknown'}  ", SYM[st[0] if st else "review"][1]))
        if r.get("slug") and not pr:
            pr = [("no PR yet", "dim")]
        cells.append([sym(r["sym"]), (cut(r["name"], 30), ""), (f"up {dur(NOW - up)}" if up else "up ?", "dim"), (act, "dim")] + pr)
    width = [max((len(c[i][0]) for c in cells if len(c) > i), default=0) for i in range(4)]
    rows = [[c[0]] + [(t.ljust(width[i] + 2) if i < 4 else t, s) for i, (t, s) in enumerate(c) if i] for c in cells]
    return rows + [[sym("blocked"), (f"held {b[1]}: {held_cause(b[1]) or '?'}", "")] for b in stories if b[9] == "held"]

# The speedometer: stories merged per day over 7 days, the distinct slugs events.tsv says were
# finished on the last 7 calendar days, today's among them, each on the day of its newest finish (finish, or reconcile's "finished" once a PR merged; a drop or a
# rescope writes neither), and two lights, each lit (!) when its count is above 0: the items waiting on you or the lead (every
# needs-you and lead's-queue row, and the stories behind +N more) with how long the oldest has
# waited, and the escaped defects logged in the last 7 days. A board item waits from its newest
# review, close:<cause> or escalated line in events.tsv, else from its file's last commit.
def waited_from(item):
    d, slug = item
    if slug in moved:
        return moved[slug]
    got = subprocess.run(["git", "-C", E["DASH_BOARD_DIR"], "log", "-1", "--format=%ct", "--", f"{d}/{slug}.md"], capture_output=True, text=True)
    return float(got.stdout) if got.returncode == 0 and got.stdout.strip().isdigit() else None

moved, done_at = {}, {}   # done_at: slug -> its newest finish, so it counts once, on that day
for f in read_tsv(E["DASH_EVENTS"], 5):
    t = epoch(f[0])
    # ponytail: an epic finished by its own PR counts too; tell them apart if epic PRs come back.
    if t is not None and ((f[1] == "finish" and f[4] == "ok") or (f[1] == "reconcile" and f[4].startswith("ok (finished"))):
        done_at[f[2]] = max(t, done_at.get(f[2], t))
    t = t if f[1] in ("review", "escalated") or f[1].startswith("close:") else None
    if t is not None and t > moved.get(f[2], 0):
        moved[f[2]] = t

def days_ago(day):
    try:
        return (TODAY - datetime.date.fromisoformat(day)).days
    except ValueError:
        return None

# Days ago -> the stories finished that day; the speedometer, the sparkline and the rate gauge all
# read the same last 7 of them.
per_day = collections.Counter((TODAY - datetime.date.fromtimestamp(t)).days for t in done_at.values())
last7 = sum(per_day[d] for d in range(7))
n_waiting = len(need) + len(queue) + more
since = [t for t in map(waited_from, dict.fromkeys(waiting)) if t is not None] if n_waiting else []
escaped = sum(days_ago(f[0]) in range(7) for f in finding_rows(E["DASH_FINDINGS"], ("escaped",)))
speed = [(f"{last7 / 7:.1f}", "b"), (" merged/day over 7 days", "")]
for n, words in ((n_waiting, f"waiting on {'you or the lead' if LEAD else 'you'}" + (f", oldest {dur(NOW - min(since))}" if since else "")),
                 (escaped, "escaped in 7 days")):
    speed += [(" · ", "dim"), (f"! {n} {words}", "bad") if n else (f"✓ 0 {words}", "dim")]

# Under the speedometer from 60 columns: the stories finished per day over 14 days (done_at's days) as
# a sparkline, oldest first, then today's count and the average of its last 7 days. From 100
# columns, two gauges (on the sparkline's line when both fit): the 7-day rate against the best 7 calendar days in events.tsv, and the agents
# working now (status's count, as the summary's) by kind against the most at once in the last 7 days.
SPARK = "▁▂▃▅▇"
G = 12   # a gauge's cells, as an epic's bar
PEAK_ROW_DAYS = 14   # busy_peak reads the agents.tsv rows started on the last 14 days, today's among them
RECENT_MIN = 3   # a frame with a height keeps this many rows of recent before the lines under the speedometer

def sparkline():
    days = [per_day[d] for d in range(13, -1, -1)]
    top = max(days) or 1
    bars = "".join(SPARK[-(-n * (len(SPARK) - 1) // top)] for n in days)   # 0 is the lowest, the busiest day the highest
    return [("14 days ", "dim"), (bars, "ok"), ("  today ", "dim"), (str(days[-1]), "b"), ("  7-day avg ", "dim"), (f"{last7 / 7:.1f}", "b")]

# Each working agent's kind: a cell character and a colour each, so plain text tells them apart too.
KINDS = (("builder", "█", "ok"), ("conductor", "▓", "h"), ("review", "▒", "warn"), ("other", "▪", "dim"))

def kind_of(role):
    return "conductor" if role == "conduct" else "review" if role == "review" else "builder" if role in E.get("DASH_BUILDERS", "").split() else "other"

def json_or_none(l):
    try:
        return json.loads(l)
    except ValueError:
        return None

def busy_peak():
    # The most agents at once on the last 7 calendar days (the speedometer's): each agents.tsv
    # session from its log's first timestamp to its last write, swept with ends first, so a hand-off
    # in the same second is no overlap; never fewer than work now.
    # ponytail: an idle stretch inside a session counts as busy, and only rows started in the last
    # PEAK_ROW_DAYS are read; log working spans if the peak reads high.
    spans, since = [], datetime.datetime.combine(TODAY - datetime.timedelta(days=6), datetime.time()).timestamp()
    for f in read_tsv(E["DASH_AGENTS_LOG"], 7):
        if days_ago(f[0]) not in range(PEAK_ROW_DAYS):
            continue
        path = session_log(E["DASH_PROJECTS"], f[6])
        try:
            end = os.path.getmtime(path)
            with open(path, encoding="utf-8", errors="replace") as fh:
                start = next((epoch(d.get("timestamp")) for d in map(json_or_none, itertools.islice(fh, 50)) if isinstance(d, dict) and d.get("timestamp")), None)
        except OSError:
            continue
        if start is not None and start < end and end >= since:
            spans += [(start, 1), (end, -1)]
    peak = n = 0
    for _, step in sorted(spans):
        n += step; peak = max(peak, n)
    return peak

def bar(parts, of):
    # parts: (count, char, style). The cells add up to the whole's rounded share of G, split by largest
    # remainder, so a full gauge has no gap; a count above 0 keeps at least one cell, taken from the
    # widest part, and the bar never exceeds G.
    q = [n * G / of if of else 0 for n, _, _ in parts]
    total = min(G, max(round(sum(q)), sum(n > 0 for n, _, _ in parts)))
    cells = [int(x) for x in q]
    for i in sorted(range(len(q)), key=lambda i: q[i] - cells[i], reverse=True)[:max(total - sum(cells), 0)]:
        cells[i] += 1
    for i, (n, _, _) in enumerate(parts):
        if n and not cells[i]:
            cells[cells.index(max(cells))] -= 1
            cells[i] = 1
    return [(ch * c, s) for c, (_, ch, s) in zip(cells, parts)] + [("·" * (G - sum(cells)), "dim")]

def gauges():
    best = max([last7] + [sum(per_day[d] for d in range(k, k + 7)) for k in range(max(per_day, default=0) + 1)])
    rate = [("rate ", "dim")] + bar([(last7, "█", "ok")], best) + [(f" {last7 / 7:.1f} of best {best / 7:.1f}/day", "")]
    if agents is None:   # no agent list from herdr: nothing is known to work, so no running gauge
        return rate
    working = collections.Counter(kind_of(r["role"]) for r in recs if r["state"] in ("working", "stalled"))   # status's count
    now = sum(working.values())
    peak = max(busy_peak(), now)
    return (rate + [(" · ", "dim"), ("running ", "dim")] + bar([(working[k], ch, s) for k, ch, s in KINDS], peak)
            + [(f" {now} of peak {peak} in 7 days", "")])

def idle_gauge():
    # Beside the running gauge: the stories next would start (DASH_BUILDABLE, dash_render's) with no
    # agent of their own in this project's panes (story_for's slug, a retired <slug>-done too) and no
    # conductor: the epic's, or for a one-off the backlog conductor (DASH_BACKLOG). Nothing when there are none, or
    # no agent list.
    if agents is None:
        return []
    mine = {r["slug"] for r in recs if r.get("slug")}
    conducted = {r["epic"] for r in recs if r.get("role") == "conduct" and r.get("epic")}
    backlog = any(r["name"] == E.get("DASH_BACKLOG") for r in recs)
    idle = 0
    for l in lines("DASH_BUILDABLE"):
        slug, _, epic = l.partition("\t")
        idle += not (slug in mine or (epic in conducted if epic else backlog))
    return [(f"idle: {idle} buildable not started", "warn")] if idle else []

SEP = (" · ", "dim")

def pack(groups, n):
    # Groups of styled segments onto as few lines of n as they fit, never splitting a group; each
    # group carries the separator it takes after another on the same line.
    rows = [[]]
    for sep, g in groups:
        if rows[-1] and sum(len(t) for t, _ in rows[-1] + [sep] + g) > n:
            rows.append([])
        rows[-1] += ([sep] if rows[-1] else []) + g
    return [fit(r, n) for r in rows if r]

# Layout. Header: one line, the clock at the right; then the speedometer, then the summary line
# (from 140 columns, the status bar at the bottom carries it, with the merge mode).
right = E.get("DASH_CLOCK") or datetime.datetime.fromtimestamp(NOW).strftime("%H:%M:%S")
head = [(os.path.basename(E["DASH_PROJECT"].rstrip("/")), "b"), (f"  swarm-dev {E['DASH_VERSION']}", "dim"),
        ("  merge ", "dim"), (E["DASH_MERGE"], ""), ("  next ", "dim"), (E["DASH_NEXT"], "warn")]
if WIDE:
    head = head[:2] + head[4:]
if sum(len(t) for t, _ in head) > W - len(right) - 1:
    head = head[:1] + head[4:]   # narrow: the version and merge mode go before next is cut
out.append(fit(head, W - len(right) - 1) + " " + paint(right, "dim"))
out.append(fit(speed, W))
under = pack([(SEP, g) for g in (sparkline() if W >= 60 else [], gauges() if W >= 100 else [], idle_gauge() if W >= 100 else []) if g], W)
n_active = sum(b[2] == "active" for b in epics.values())
n_working = sum(r["state"] in ("working", "stalled") for r in recs)   # status calls a stalled agent working too
summary = [(f"{n_active} epics active", ""), (" · ", "dim"), (f"{n_working} agents working", "ok" if n_working else ""), (" · ", "dim"),
           (f"{green} PRs green, waiting", "ok" if green else ""), (" · ", "dim"), (f"{len(stalled)} stalled", "bad" if stalled else "")]
if E.get("DASH_COST"):
    summary += [(" · ", "dim"), (f"${E['DASH_COST']} today", "")]
# Who is on call (the escalate role's model, off when escalate_after is 0) and today's escalations, a
# zero count too. It goes on the summary's line when it fits there, else on a line of its own.
esc = next((p for p in (l.split() for l in lines("DASH_POLICY")) if p[0] == "escalate" and len(p) > 3), None)
on_call = "off" if E.get("DASH_ESCALATE_AFTER") == "0" or not esc else f"{esc[2] if esc[1] == 'claude' else esc[1]}·{esc[3]}"
on_call = [("on call: ", "dim"), (on_call, model_style(on_call)), (" · ", "dim"),
           (f"{escalations} escalation{'' if escalations == 1 else 's'} today", "fable" if escalations else "")]
if not WIDE:
    out += pack([(SEP, summary), (SEP, on_call)], W)
drift = lines("DASH_DRIFT")
if drift:
    out.append(fit([(f"board: {len(drift)} uncommitted edit{'' if len(drift) == 1 else 's'} in the main checkout: {', '.join(drift)}", "warn")], W))

# The main column: needs you, the epics (or the tree), the blocked count. From 140 columns it is the
# left column, LW wide.
left = box("needs you", [l for r in need for l in wrap(r, LW - 4)], LW, "bad") if need else [fit([sym("done"), ("nothing needs you", "dim")], LW)]
if queue:
    left += box("lead's queue", [l for r in queue for l in wrap(r, LW - 4)], LW, "warn")
if E.get("DASH_TREE") == "1":
    left += box("agents by workspace and tab", tree_view(), LW)
elif epic_view:
    left += box("epics", epic_view, LW)
# Running now: from 140 columns under the epics; narrower, under the ladder and above recent, which
# gives up the height it takes, so a watched frame keeps the ladder.
running = running_view()
if WIDE and running:
    left += box("running now", running, LW)
if blocked or later:
    left.append(fit([sym("blocked"), (f"{blocked} blocked · {later} later  (swarm.sh status --all lists them)", "dim")], LW))

# The legend; from 140 columns the keys go to the status bar. DASH_LEGEND=0 (a --project frame,
# whose legend dash_frame draws once under them all) leaves the legend and the keys out.
LEGEND_ON = E.get("DASH_LEGEND") != "0"
foot = [fit([(cut(l, W), "dim")], W) for l in legend_lines(W, KEYS, WIDE, LEAD)] if LEGEND_ON else []
if WIDE:
    foot += pack([(SEP, [("merge ", "dim"), (E["DASH_MERGE"], "b"), (" · ", "dim")] + summary), (SEP, on_call)]
                 + ([(("   ", ""), [(KEYWORDS if KEYS else KEYWORDS + " (with --watch)", "dim")])] if LEGEND_ON else []), W)

# Recent fills the height left. Under 140 columns it, a shown ladder and running now are stacked
# under the main column; from 140 recent and the ladder are the right column, the ladder on top.
# A watched frame drops what does not fit, never the foot; a one-shot dash shows at least 5 rows.
ladder = E.get("DASH_LADDER") == "1"

def make_room(room, spare=H):
    # The lines under the speedometer (under) take recent's rows; a cut frame keeps RECENT_MIN of them
    # (or the ladder, when even those do not fit) and, from 140 columns, the whole left column (spare:
    # the rows under it) first, dropping the sparkline's line, then the gauges.
    while under and FIT and H and (room - len(under) < RECENT_MIN or spare < len(under)):
        under.pop(0)
    return room - len(under)

if WIDE:
    side = ladder_box(RW) if ladder else []
    room = make_room(H - len(out) - len(foot) - len(side) - 2, H - len(out) - len(foot) - len(left)) if H else max(8, len(left) - len(side) - 2)
    if not KEYS:
        room = max(5, room)
    if room > 0:
        side += recent_box(RW, room, clock=True)
    out += [(a if a is not None else " " * LW) + " " + (b or "") for a, b in itertools.zip_longest(left, side)]
else:
    out += left
    if ladder:
        out += ladder_box(W)
    if running:
        out += box("running now", running, W)
    room = make_room(H - len(out) - 2 - len(foot)) if H else 8
    if not KEYS:
        room = max(5, room)
    if room > 0:
        out += recent_box(W, room)
out[2:2] = under
if FIT and H:
    # A watched frame never scrolls the screen; the header line stays even when the foot does not fit.
    out = out[:max(H - len(foot), 1)]
out += foot
if FIT and H:
    out = out[:H]
print("\n".join(l.rstrip() for l in out))
