# dash_age.py — a working agent's minutes since its last sign of life, as dash shows them (STALL_PY's
# stall_age over dash's signs). dash.sh's stall pre-pass (stalled_panes) and dash_render.py's agent rows
# both use it, so the panes dash reads for a test run are the agents its rows would show stalled.
import json, os, re
from report import STEP_UP, session_log
from stall import *
from events_outcome import outcome
from panes import agent_state, pane_records, session_state

STARTS = ("agent", "conduct", "story")
URL = re.compile(r"https://github\.com/([^/\s]+)/([^/\s]+)/pull/(\d+)")

def pr_states(lines):
    # url -> gh's JSON for it, from DASH_PRSTATE's "<url>\t<json>" lines; a line that is not JSON is skipped.
    prs = {}
    for l in lines:
        url, _, j = l.partition("\t")
        try:
            prs[url] = json.loads(j)
        except ValueError:
            pass
    return prs

class Signs:
    # A frame's signs of life: events.tsv read once (last_seen's targets; started: target -> its newest
    # start, an agent, conduct or story line or a step-up's escalate; ran: pane -> the newest sign of life
    # it ran, sign_time's), the worktree commits (DASH_COMMITS, slug -> time) and the PRs (pr_states).
    def __init__(self, events, commits, prs, projects, now):
        self.seen, self.started, self.ran = last_seen(events), {}, {}
        self.commit_of, self.prs, self.projects, self.now = commits, prs, projects, now
        try:
            rows = [l.rstrip("\n").split("\t") for l in open(events, encoding="utf-8", errors="replace")]
        except OSError:
            rows = []
        for f in (f for f in rows if len(f) == 5):
            t = sign_time(f)
            if t is not None and t > self.ran.get(f[3], 0):
                self.ran[f[3]] = t
            o = outcome(f)
            t = epoch(f[0]) if (f[1] in STARTS and o == "ok") or (f[1] == "escalate" and STEP_UP.fullmatch(o)) else None
            if t is not None and t > self.started.get(f[2], 0):
                self.started[f[2]] = t

    def since(self, slug, epic, base):
        # When the agent's newest start ran: its story's, its epic's (a conductor's), else its own name's.
        return self.started.get(slug) or self.started.get(epic) or self.started.get(base)

    def age(self, who, session, story_prs):
        # (minutes or None, what it lacks) for a working agent. who: (slug, epic, base, pane). Any agent
        # with a Claude session counts its session log, written on every turn and tool call; a story's
        # builder its worktree's commits and its PRs' updates; any other its own events.tsv lines.
        slug, epic, base, pane = who
        log = session_log(self.projects, session) if session else ""
        try:
            logged = os.path.getmtime(log) if log else None
        except OSError:   # removed since the glob: no sign
            logged = None
        if slug:
            signs = [self.commit_of.get(slug, ""), logged] + [(self.prs.get(m.group(0)) or {}).get("updatedAt") for m in URL.finditer(story_prs)]
            return stall_age(self.seen, slug, base, signs, self.now), "no commit, edit, session-log write or PR update"
        since = self.since(slug, epic, base)
        return stall_age(self.seen, epic, base, ([since, self.ran.get(pane)] if since else []) + [logged], self.now), "no swarm action"

def stalled_panes(E, now):
    # dash.sh's pre-pass, ahead of the render: "<pane>\t<name>" for each of this project's agents
    # (pane_records over its own live panes, as the rows read them, herdr's name or else the record's)
    # that is working and whose age has reached stall_minutes.
    # Working is agent_state over the session's state; shown_state's pane read is left out, so an agent
    # the rows show on its usage limit is listed too. Nothing that cannot be read lists anything.
    try:
        agents = {a.get("pane_id"): a for a in json.loads(E["DASH_AGENTS"])["result"]["agents"]}
        live = {p["pane_id"] for p in json.loads(E["DASH_PANES"])["result"]["panes"]}
    except (ValueError, KeyError, TypeError, AttributeError):
        return []
    # The board as dash_fields lays it out: dir, slug, status, prs, agent name, conductor name, ...
    board = [(l.split("\t") + [""] * 6)[:6] for l in E.get("DASH_BOARD", "").splitlines() if l.strip()]
    story_rows = [(b[1], b[4], b[2]) for b in board if b[0] == "stories"]
    story_prs = {b[1]: b[3] for b in board if b[0] == "stories"}
    epic_of = {b[5]: b[1] for b in board if b[0] == "epics"}
    by_session, by_name = {}, {}
    try:
        for l in open(E["DASH_AGENTS_LOG"], encoding="utf-8", errors="replace"):
            f = l.rstrip("\n").split("\t")
            if len(f) == 7:
                by_name[f[2]] = by_session[f[6]] = f
    except OSError:
        pass
    commits = dict(l.split("\t", 1) for l in E.get("DASH_COMMITS", "").splitlines() if "\t" in l)
    signs = Signs(E["DASH_EVENTS"], commits, pr_states(E.get("DASH_PRSTATE", "").splitlines()), E["DASH_PROJECTS"], now)
    out = []
    for _, pane, recorded in pane_records(E["DASH_STATE"], set(E.get("SWARM_OWN", "").split()) & live):
        try:   # an odd agent record lists nothing, as the rows show it unreadable
            a = agents.get(pane)
            name = (a or {}).get("name") or recorded
            base = re.sub(r"-done\d*$", "", name)
            if a is None or agent_state(a, name, session_state(E["DASH_AGENTS_LOG"], name, E["DASH_SESSIONS"]))[0] != "working":
                continue
            rec = by_session.get((a.get("agent_session") or {}).get("value", "")) or by_name.get(base)
            slug = story_for(name, story_rows)
            age = signs.age((slug, epic_of.get(base), base, pane), rec[6] if rec else "", story_prs.get(slug, ""))[0]
        except Exception:
            continue
        if age is not None and age >= int(E["DASH_STALL_MIN"]):
            out.append(f"{pane}\t{name}")
    return out
