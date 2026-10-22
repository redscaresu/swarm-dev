# gh calls, a flow section (flow_report.py gives its globals): bin/gh-shim's log, .swarm/gh-calls.tsv
# beside events.tsv, its lines whose local day is in the window, counted per local hour and budget
# (graphql or rest, 5000 an hour each), once by role and once by subcommand. A row counts gh runs, not
# API requests: a run marked many (--paginate, --watch, run watch) spends many requests, and GraphQL
# counts points, so the share of 5000 is a floor. A caller's role is its agent's agents.tsv one (the
# last line naming it), an agent agents.tsv does not name as itself, and - for a call outside any
# agent; a subcommand swarm.sh ran says so (`via swarm.sh <command>`). Each hour's budget lists its
# `(all)` row (no agent, role or subcommand has parentheses), then its rows, most runs first. A share
# under 0.1% shows as <0.1%; a `none` run (one that calls no API, such as gh config) has no share. The log only grows, so it is read from its end and the
# reading stops two days before --since. --epic does not narrow it.
import collections, datetime, os

BUDGET = 5000
ALL = "(all)"
BLOCK = 1 << 16

def backwards(path):
    # The file's lines, last first, read in blocks from its end.
    with open(path, "rb") as f:
        f.seek(0, 2)
        pos, tail = f.tell(), b""
        while pos > 0:
            n = min(BLOCK, pos)
            pos -= n
            f.seek(pos)
            lines = (f.read(n) + tail).split(b"\n")
            tail = lines.pop(0)
            yield from reversed(lines)
        yield tail

def share(api, n):
    pct = 100 * n / BUDGET
    return "-" if api == "none" else "<0.1%" if pct < 0.05 else f"{pct:.1f}%"

role_of = {}
for line in open(agents, errors="ignore") if os.path.exists(agents) else ():
    f = line.rstrip("\n").split("\t")
    if len(f) >= 3:
        role_of[f[2]] = f[1]

# Lines are appended in time order, near enough: two days of slack covers local time and a slow append.
stop = "" if since == "0000-00-00" else (datetime.date.fromisoformat(since) - datetime.timedelta(days=2)).isoformat()
by = {"role": collections.Counter(), "subcommand": collections.Counter()}
many = {"role": collections.Counter(), "subcommand": collections.Counter()}
log = os.path.join(os.path.dirname(events), "gh-calls.tsv")
for raw in backwards(log) if os.path.exists(log) else ():
    f = raw.decode("utf-8", "ignore").split("\t")
    if len(f) != 7:
        continue
    try:
        t = datetime.datetime.fromisoformat(f[0].replace("Z", "+00:00")).astimezone()
    except ValueError:
        continue   # a torn or hand-edited line: skipped, never taken for the stop
    if f[0][:10] < stop:
        break
    if not since <= t.date().isoformat() <= until:
        continue
    hour, agent, via, sub, api, heavy = t.strftime("%Y-%m-%d %H:00"), f[1], f[2], f[3], f[4], f[5] != "-"
    for key, name in (("role", role_of.get(agent, agent)), ("subcommand", sub if via == "-" else f"{sub} via {via}")):
        for k in ((hour, api, ALL), (hour, api, name)):
            by[key][k] += 1
            many[key][k] += heavy

if not os.path.exists(log):
    print(f"no gh calls logged: no {log} yet (bin/gh-shim writes it once swarm.sh or an agent it started runs gh)")
elif not by["role"]:
    print(f"no gh calls logged in the window ({since} to {until})")
else:
    print("# gh runs, not API requests: a run with many > 0 (--paginate, --watch) spends several, and GraphQL counts points;"
          " role - is a call outside any agent, and share - a none run, which spends neither budget")
    for i, key in enumerate(by):
        print(("\n" if i else "") + f"hour\tapi\t{key}\truns\tmany\tshare")
        for (hour, api, name), n in sorted(by[key].items(), key=lambda kv: (kv[0][:2], kv[0][2] != ALL, -kv[1], kv[0][2])):
            print(f"{hour}\t{api}\t{name}\t{n}\t{many[key][(hour, api, name)]}\t{share(api, n)}")
