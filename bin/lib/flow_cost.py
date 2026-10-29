# Cost, a flow section (flow_report.py gives its globals): tokens and estimated cost per role, in the window.
# The split-critic agent (/plan-epic's check on a large epic's split) is a critic with a row of its own.
# Then the per-rung block: each step-up in the window with its story's tokens per rung and how its build
# ended, and per rung the builds that reached it.
import collections, datetime, os
from report import *
log, agents, named, built = agents, [], set(), collections.defaultdict(list)   # built: builder lines by agent name
if os.path.exists(log):
    for line in open(log):
        f = line.rstrip("\n").split("\t")
        if len(f) == 7:
            named.add(f[6])
            if since <= f[0] <= until:
                agents.append({"role": "split-critic" if f[1:3] == ["critic", "split-critic"] else f[1], "kind": f[3], "session": f[6]})
            if f[1] in roles.split():
                built[f[2]].append(f)

def started(path):
    # The first timestamp's local day, as since and agents.tsv's dates are, or "".
    for line in log_lines(path) if path else ():
        try:
            ts = json.loads(line).get("timestamp")
            return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().date().isoformat()
        except (ValueError, AttributeError, TypeError):
            continue
    return ""

def in_window(path):
    # A lead session counts by its first timestamp's local day; one with none (or no log) only without --since.
    day = started(path)
    return since <= day <= until if day else since == "0000-00-00"

if lead and lead not in named and in_window(session_log(projects, lead, archive)):   # a conductor's own pane is already its agents.tsv row
    agents.append({"role": "lead", "kind": "claude", "session": lead})
    named.add(lead)

# The lead's own sessions: Claude Code keeps them under the project's path, all but letters and digits turned into -.
for path in sorted(glob.glob(os.path.join(glob.escape(own), "*.jsonl"))):
    session = os.path.basename(path)[:-len(".jsonl")]
    if session not in named and in_window(path):
        agents.append({"role": "lead", "kind": "claude", "session": session, "path": path})
table, seen, priced = {}, set(), {}   # priced: each session's (tokens, est. $) as the role table counted it
for a in agents:
    r = table.setdefault(a["role"], {"agents": 0, "models": set(), "tok": [0, 0, 0, 0], "usd": 0.0, "unpriced": 0})
    r["agents"] += 1
    path = a.get("path") or session_log(projects, a["session"], archive)
    if a["kind"] != "claude" or not path:
        r["unpriced"] += 1
        continue
    tok, usd, models = session_usage(path, seen)
    priced[a["session"]] = (sum(tok), usd)
    r["models"] |= models
    r["tok"] = [x + y for x, y in zip(r["tok"], tok)]
    r["usd"] += usd
def n(x):
    return f"{x/1e6:.1f}M" if x >= 1e6 else f"{x/1e3:.0f}k"
print("| role | agents | model | input | cache write | cache read | output | est. $ |")
print("|---|---|---|---|---|---|---|---|")
tot = [0, 0, 0, 0]; usd = 0.0
for role, r in sorted(table.items(), key=lambda kv: -kv[1]["usd"]):
    tot = [x + y for x, y in zip(tot, r["tok"])]; usd += r["usd"]
    note = f" ({r['unpriced']} not in the logs)" if r["unpriced"] else ""
    print(f"| {role} | {r['agents']}{note} | {', '.join(sorted(r['models'])) or '-'} | " + " | ".join(n(x) for x in r["tok"]) + f" | {r['usd']:.2f} |")
print(f"| **total** | {sum(r['agents'] for r in table.values())} | | " + " | ".join(n(x) for x in tot) + f" | {usd:.2f} |")
print("\nList prices; on a subscription this is plan usage, not a bill. Codex agents are not priced.")
if epic:
    print(f"Every agent in the window, not only epic {epic}'s.")

# The per-rung block. A step-up is an ok escalate line `ok (<trigger>: <from> -> <to>)` whose local day is
# in the window. Its tokens per rung are its story's builder sessions (agents.tsv lines with the story's
# agent name), summed by model and priced as above. How the build ended comes from outcomes' rows for the
# story, so a PR merged on GitHub or by another run counts with no merge line of this run: merged, lead
# (an ok held, escalated or close:impossible line for the story after the step-up and before its next
# attempt started), failed (a later attempt, or its last rung closed with no PR open) or open (no row yet,
# or still building). Sessions logged after the window's end are left out of the tokens.
RANK = ("haiku", "sonnet", "opus", "fable")
by_rank = lambda m: (RANK.index(m) if m in RANK else len(RANK), m)
LEAD = ("held", "escalated", "close:impossible")
ups, to_lead, every = [], collections.defaultdict(list), collections.defaultdict(list)   # every: step-up times by (slug, trigger, from)
for line in open(events, errors="ignore") if os.path.exists(events) else ():
    e = line.rstrip("\n").split("\t")
    if len(e) != 5 or not e[4].startswith("ok") or not merge_time(e[0]):
        continue
    if e[1] in LEAD:
        to_lead[e[2]].append(e[0])
    m = STEP_UP.fullmatch(e[4]) if e[1] == "escalate" else None
    if m:
        every[(e[2],) + m.groups()[:2]].append(e[0])
    if m and since <= local_day(merge_time(e[0])).isoformat() <= until:
        ups.append((e[0], e[2]) + m.groups())

def rung_tokens(slug):
    # "<model> <tokens> $<est.>" per rung, lowest first; "<model> -" for a rung with no session in the logs.
    got = collections.defaultdict(list)
    for f in (f for f in built[agent_name(slug)] if f[0] <= until):
        path = session_log(projects, f[6], archive) if f[3] == "claude" else ""
        if f[6] in priced:
            got[f[4]].append(priced[f[6]])
        elif path:   # a session before the window, which the role table did not read
            tok, usd, _ = session_usage(path, set())
            got[f[4]].append((sum(tok), usd))
        else:
            got[f[4]] += []   # the rung is listed, with nothing priced
    return ", ".join(f"{m} " + (f"{n(sum(t for t, _ in got[m]))} ${sum(u for _, u in got[m]):.2f}" if got[m] else "-")
                     for m in sorted(got, key=by_rank))

def paired(mine, slug, trigger, frm, to):
    # {step-up line's time: its build's attempt}. outcomes closes the build a step-up replaced with close_cause
    # step-up:<trigger>, and the rung is its next row, on <to>, started the day the step-up was logged or
    # the day before (a rung starts before its step-up line, which can fall after midnight). Newest line
    # first, each takes the newest such row not taken, as outcomes pairs them in order. A line with none
    # has no row yet.
    was = [(r, rung.get("date")) for r, rung in zip(mine, mine[1:])
           if r.get("close_cause") == f"step-up:{trigger}" and r.get("model") == frm and rung.get("model") == to]
    got = {}
    for t in reversed(every[(slug, trigger, frm)]):
        days = {local_day(merge_time(t) - datetime.timedelta(days=d)).isoformat() for d in (0, 1)}
        i = next((i for i in range(len(was) - 1, -1, -1) if was[i][1] in days), None)
        if i is not None:
            got[t] = was.pop(i)[0].get("attempts")
    return got

def ended(at, slug, trigger, frm, to):
    # merged, lead, failed or open, as above, for the step-up of <slug> from <frm> to <to> logged at <at>.
    mine = [r for r in rows if r.get("slug") == slug]
    att = paired(mine, slug, trigger, frm, to).get(at)
    if att is None:
        return "open"
    build = [r for r in mine if r.get("attempts") == att]
    num = lambda a: int(a) if (a or "").isdigit() else 0
    later = any(num(r.get("attempts")) > num(att) for r in mine)
    # A later attempt means this one's close counted it failed, and clear_build closed its PRs.
    if not later and (any(r.get("pr_state") == "MERGED" for r in build) or any(r.get("story_merged") == "true" for r in mine)):
        return "merged"
    # A hold after the next attempt started (its session's first time, else its day) is that attempt's.
    nxt = min((r.get("started") or r.get("date", "") for r in mine if num(r.get("attempts")) > num(att)), default="")
    if any(at <= t and (not nxt or t < nxt) for t in to_lead[slug]):
        return "lead"
    last = build[-1]
    if later or (last.get("closes", "0") not in ("", "0") and not last.get("close_cause", "").startswith("step-up:")
                 and not any(r.get("pr_state") == "OPEN" for r in build)):
        return "failed"
    return "open"

print("\n### per rung\n")
if ups:
    print("| story | trigger | step-up | tokens per rung | outcome |")
    print("|---|---|---|---|---|")
    for at, slug, trigger, frm, to in sorted(ups):
        print(f"| {slug} | {trigger} | {frm} -> {to} | {rung_tokens(slug) or '-'} | {ended(at, slug, trigger, frm, to)} |")
else:
    print("none")
# Per rung, the builds in the window that reached it, and their share of all of them: outcomes' rows by
# story and attempt (a step-up's rung is the same attempt), a build in the window when any of its rows is,
# and a rung reached when a row on it started by the window's end.
builds, inside = collections.defaultdict(set), set()
for r in (r for r in rows if r.get("date", "") <= until):
    k = (r.get("slug"), r.get("attempts"))
    builds[k].add(r.get("model"))
    if since <= r.get("date", "") <= until:
        inside.add(k)
if inside:
    print("\n| rung | builds | share |\n|---|---|---|")
    for m in sorted(set().union(*(builds[k] for k in inside)), key=by_rank):
        k = sum(m in builds[b] for b in inside)
        print(f"| {m} | {k} | {round(100 * k / len(inside))}% |")
