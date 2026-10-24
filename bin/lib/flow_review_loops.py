# Review loops, a flow section (flow_report.py gives its globals): per story PR, each review round's
# builder model, minutes, findings fixed and declined and step-up, then how its loop ended, then totals
# for tuning the stop and escalation rules. Built from events.tsv, findings.tsv and agents.tsv, with no
# gh call. Each build of a story (a story start, or an escalate build) is its own loop.
import collections, datetime, os, re, statistics
from report import *

def when(t):
    try:
        return datetime.datetime.strptime(t, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    except ValueError:
        return None

def review_url(cmd, out):
    m = re.fullmatch(r"ok \((\S+/pull/\d+)\)", out) if cmd == "review" else None
    return m.group(1) if m else None

epic_of = {r["slug"]: r["epic"] for r in rows}
slug_of = {pr_key(r["pr"]): r["slug"] for r in rows if r["pr"]}   # every build's PR
merged = {pr_key(r["pr"]) for r in rows if r["pr"] and (r.get("pr_state") == "MERGED" or r.get("merged_at"))}
row_prs = collections.defaultdict(list)   # each slug's builds' PRs, one per builder agents.tsv line
for r in rows:
    row_prs[r["slug"]].append(r["pr"])

def handed(t, cmd, target, out):
    # A review line once per PR it hands over, as its story's (an epic's review names its stories' PRs).
    urls = re.findall(r"[^\s()]+/pull/\d+", out) if cmd == "review" and out.startswith("ok (") else []
    return [(t, cmd, slug_of.get(pr_key(u), target), f"ok ({u})") for u in urls] or [(t, cmd, target, out)]

evs = [e for f in (l.rstrip("\n").split("\t") for l in log_lines(events)) if len(f) >= 5 and when(f[0])
       for e in handed(when(f[0]), f[1], f[2], f[4])]
slug_of.update((pr_key(review_url(cmd, out)), target) for _, cmd, target, out in evs if review_url(cmd, out))
# Each builder's models, one agents.tsv line in a builder role per build start or step-up rung, in order,
# read as outcomes reads them (7 fields), so they line up with its rows.
started = collections.defaultdict(list)
for f in (l.rstrip("\n").split("\t") for l in log_lines(agents)):
    if len(f) == 7 and f[1] in roles.split():
        started[f[2]].append(f[4])

def step_up(cmd, out):
    # A step-up line as (trigger, from, to, ok): an escalate ok (<trigger>: <from> -> <to>), or a step-up
    # that failed partway, after its builder was closed (step-up's or step-up --resume's "builder is
    # closed, but", or a tell or close whose step-up failed partway, a tell's on findings); None for any
    # other line, a step-up refused before it changed anything among them.
    m = STEP_UP.fullmatch(out) if cmd == "escalate" else None
    if m:
        return m.group(1), m.group(2), m.group(3), "ok"
    if "step-up failed partway" in out:
        return "findings" if cmd == "tell:findings" else "?", "?", "?", "failed"
    m = re.search(r"'s (\S+) builder is closed, but (?:the (\S+) builder)?", out)
    return ("?", m.group(1), m.group(2) or "?", "failed") if m else None

def loops(slug, lines):
    # A slug's loops, one per build, in log order. A review-agent start opens a round (a restarted one
    # moves its start); a findings tell, a findings step-up (which takes the tell's place), or the
    # review or merge after the last tell closes it, opening it first when no review agent started it
    # (minutes then unknown). A step-up goes on the round open or last closed, or before the first, and
    # the rounds after it run on its model; a findings step-up resumed after one that failed partway
    # goes on the round that failure closed. Each loop: its rounds, step-ups before them, whether the
    # lead holds it, whether a merge line ended it, how its last round closed, its model at the end, its
    # PR, when it started and whether a review-agent, tell:findings or escalate line of it is in the window. An escalate build logs its
    # escalate line, then its story line: one start. Each start and each step-up takes the builder's
    # next agents.tsv model.
    models, nxt, prs = started[agent_name(slug)], [0], row_prs[slug]
    def take(model):
        nxt[0] += 1
        return models[nxt[0] - 1] if nxt[0] <= len(models) else model
    def done(lp, cur):
        # Its PR: its review line's, else the outcomes row of its builder's latest agents.tsv line (rows
        # line up with those lines; a loop before any start line is the first build's).
        i = max(nxt[0] - 1, 0)
        return dict(lp, rounds=lp["rounds"] + ([cur] if cur else []), pr=lp["pr"] or (prs[i] if i < len(prs) else "") or None)
    out_, model, paired = [], models[0] if models else "?", False
    new = lambda t: {"rounds": [], "pre": [], "held": False, "merged": False, "last": None, "model": model,
                     "pr": None, "in": False, "t0": t, "c": collections.Counter()}
    lp, cur = new(lines[0][0]), None
    for t, cmd, out in lines:
        s = step_up(cmd, out)
        inwin = cmd in loop_cmds[:3] and since <= t.astimezone().date().isoformat() <= until
        if cmd == "story" and out == "ok" or cmd == "escalate" and re.fullmatch(r"ok \(attempt \d+\)", out):
            if not (cmd == "story" and paired):
                if lp["rounds"] or cur or lp["pre"] or lp["held"]:
                    out_.append(done(lp, cur))
                lp, cur = new(t), None
                model = lp["model"] = take(model)
            lp["in"] = lp["in"] or inwin
            paired = cmd == "escalate"
            continue
        paired = False
        lp["in"] = lp["in"] or inwin
        if cmd == "review-agent" and out == "ok":
            cur = dict(cur or {"model": model, "end": None, "step": []}, start=t)
        elif cmd == "tell:findings" and out == "ok" or s and s[0].startswith("findings") and (cur or lp["last"] != "partway") \
                or cmd in ("review", "merge") and out.startswith("ok") and (cur or lp["last"] in (None, "tell", "partway")):
            cur = cur or {"model": model, "start": None, "end": None, "step": []}
            cur["end"] = t
            lp["rounds"].append(cur)
            cur, lp["last"] = None, cmd if cmd in ("review", "merge") else "partway" if s and s[3] == "failed" else "tell"
        lp["held"] = lp["held"] or cmd == "escalated" and out.startswith("ok")
        lp["pr"] = review_url(cmd, out) or lp["pr"]
        if s:
            (cur or (lp["rounds"][-1] if lp["rounds"] else {"step": lp["pre"]}))["step"].append(s)
            if s[3] == "ok":
                take(model)
                model = lp["model"] = s[2]
        if cmd == "merge" and out == "ok":
            lp["merged"] = True
            break
    return out_ + [done(lp, cur)]

loop_cmds = ("review-agent", "tell:findings", "escalate", "escalated", "review", "merge", "story")
by_slug = collections.defaultdict(list)
for t, cmd, target, out in evs:
    slug = slug_of.get(pr_key(target)) if "/pull/" in target else target
    if slug and (cmd in loop_cmds or step_up(cmd, out)):
        by_slug[slug].append((t, cmd, out))
built = {s: loops(s, lines) for s, lines in by_slug.items()}
# Each finding with a round (log-finding --round) goes to one build: the latest on its PR that started on
# or before the day it was logged (both local dates), as outcomes gives findings to builds.
on_pr = collections.defaultdict(list)
for lp in sorted((lp for b in built.values() for lp in b if lp["pr"]), key=lambda lp: lp["t0"]):
    on_pr[pr_key(lp["pr"])].append(lp)
for day, _, pr, _, outcome, _, _, n in finding_rows(findings, width=8):
    took = [lp for lp in on_pr[pr_key(pr)] if lp["t0"].astimezone().date().isoformat() <= day]
    if n.isdigit() and int(n) > 0 and took:
        took[-1]["c"][(int(n), outcome)] += 1
shown = {s: [lp for lp in b if lp["in"]] for s, b in sorted(built.items()) if not epic or epic_of.get(s) == epic}
shown = {s: b for s, b in shown.items() if b}
if not shown:
    print("no review loop in the window" + (f" for epic {epic}" if epic else ""))
    raise SystemExit
ladder = os.environ.get("SWARM_LADDER", "").replace(",", " ").split()
top = ladder[-1] if ladder else None
per_pr, fixed_in, round3_min, failed = [], collections.Counter(), 0, 0
stepped = collections.Counter()   # the stepped-up builds, and their fixes and rounds up to and after the first step-up
print("story\tpr\tround\tmodel\tminutes\tfixed\tdeclined\tstep_up")
ends = []
for slug, builds in shown.items():
    for lp in builds:
        pr, c, rounds = lp["pr"] or "-", lp["c"], lp["rounds"]
        n = max([len(rounds)] + [r for r, _ in c])
        rounds += [{"model": lp["model"], "start": None, "end": None, "step": []} for _ in range(n - len(rounds))]
        failed += sum(s[3] == "failed" for s in lp["pre"])
        if not n:   # no round: its step-ups alone, on a row with no round, and no end state
            steps = [f"{t}: {a} -> {b} {ok} before review" for t, a, b, ok in lp["pre"]]
            if steps:
                print(f"{slug}\t{pr}\t-\t{lp['model']}\t-\t0\t0\t{', '.join(steps)}")
            continue
        up = 0 if any(s[3] == "ok" for s in lp["pre"]) else None
        for i, r in enumerate(rounds, 1):
            mins = int((r["end"] - r["start"]).total_seconds() / 60 + 0.5) if r["start"] and r["end"] else None
            round3_min += (mins or 0) if i >= 3 else 0
            fixed_in["round1" if i == 1 else "round2" if i == 2 else "round3_on"] += c[(i, "fixed")]
            fixed_in["top_rung"] += c[(i, "fixed")] if r["model"] == top else 0
            failed += sum(s[3] == "failed" for s in r["step"])
            up = i if up is None and any(s[3] == "ok" for s in r["step"]) else up
            steps = [f"{t}: {a} -> {b} {ok} before review" for t, a, b, ok in lp["pre"] if i == 1]
            steps += [f"{t}: {a} -> {b} {ok}" for t, a, b, ok in r["step"]]
            print(f"{slug}\t{pr}\t{i}\t{r['model']}\t{'-' if mins is None else mins}\t{c[(i, 'fixed')]}\t{c[(i, 'declined')]}\t{', '.join(steps) or '-'}")
        if up is not None:
            stepped.update(builds=1, rounds_before=up, rounds_after=n - up,
                           fixed_before=sum(c[(i, "fixed")] for i in range(1, up + 1)),
                           fixed_after=sum(c[(i, "fixed")] for i in range(up + 1, n + 1)))
        end = "held-for-lead" if lp["held"] else "open" if not (lp["merged"] or pr_key(pr) in merged) \
            else "merged-after-fixes" if c[(n, "fixed")] else "pass"
        ends.append(f"{slug}\t{pr}\t{n}\t{end}")
        per_pr.append(n)
print("\nstory\tpr\trounds\tend\n" + "\n".join(ends))
s = sorted(per_pr)
total = sum(fixed_in[k] for k in ("round1", "round2", "round3_on"))
share = lambda k: f"{int(100 * fixed_in[k] / total + 0.5)}%" if total else "-"
rate = lambda f, r: f"{round(f / r, 1):g}" if r else "-"
print("\nprs\trounds_median\trounds_p90\tmin_round3_on\tfixes\tround1\tround2\tround3_on\ttop_rung\tstepped_up\tfixes_per_round_before\tfixes_per_round_after\tfailed_step_ups")
print("\t".join([str(len(s)), f"{statistics.median(s):g}" if s else "-", str(s[-(-9 * len(s) // 10) - 1]) if s else "-", str(round3_min), str(total),
                 share("round1"), share("round2"), share("round3_on"), share("top_rung") if top else "-",
                 str(stepped["builds"]), rate(stepped["fixed_before"], stepped["rounds_before"]),
                 rate(stepped["fixed_after"], stepped["rounds_after"]), str(failed)]))
