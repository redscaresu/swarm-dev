# Review loops, a flow section (flow_report.py gives its globals): per story PR, each review round's
# builder model, minutes, findings fixed and declined and step-up, then how its loop ended, then totals
# for tuning the stop and escalation rules. Built from events.tsv, findings.tsv and agents.tsv, with no
# gh call. Each build of a story (a story start, or an escalate build) is its own loop.
import collections, datetime, os, re, statistics
from events_outcome import outcome
from report import *
from events_outcome import outcome

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
       for e in handed(when(f[0]), f[1], f[2], outcome(f))]
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
    # (minutes then unknown). A decline-only line (review --head passed a findings round whose builder
    # pushed nothing) closes a round still open (review_rounds counted its findings where this reader
    # does not: a tell that failed after herdr sent it, or a recheck refused with a full round due),
    # makes the review or merge after it close no new round, and ends the loop decline-only unless a
    # later round closes; the round it names (ok (round N)) is review_rounds' count since the story
    # line, so rounds it counted that this reader did not see, less those of the loops before this one
    # since that line (a restarted builder's), are the loop's too, with no minutes. A step-up goes on the round open or last
    # closed, or before the first, and the rounds after it run on its model; a findings step-up resumed after one that failed partway
    # goes on the round that failure closed. Each loop: its rounds, step-ups before them, whether the
    # lead holds it, whether a merge line ended it, how its last round closed, its model at the end, its
    # PR, when it started and whether a review-agent, tell:findings or escalate line of it is in the
    # window. A build starts at an ok story line, an ok agent line (a builder a conductor started) or an
    # escalate build's ok (attempt N), whose story line follows: one start. Each start and each step-up
    # takes the builder's next agents.tsv model. A merge line ends its loop: the lines after it count
    # for none until the next start.
    models, nxt, prs = started[agent_name(slug)], [0], row_prs[slug]
    def take(model):
        nxt[0] += 1
        return models[nxt[0] - 1] if nxt[0] <= len(models) else model
    def done(lp, cur):
        # Its PR: its review line's, else the outcomes row of its builder's latest agents.tsv line (rows
        # line up with those lines; a loop before any start line is the first build's).
        i = max(nxt[0] - 1, 0)
        return dict(lp, rounds=lp["rounds"] + ([cur] if cur else []), pr=lp["pr"] or (prs[i] if i < len(prs) else "") or None)
    out_, model, paired, ended = [], models[0] if models else "?", False, False
    shown_ = lambda lp, cur: lp["rounds"] or cur or lp["pre"] or lp["held"] or lp["merged"]
    new = lambda t: {"rounds": [], "pre": [], "held": False, "merged": False, "last": None, "model": model,
                     "pr": None, "in": False, "t0": t, "c": collections.Counter(), "base": 0}
    lp, cur = new(lines[0][0]), None
    counted = [0]   # rounds closed since the last ok story line, where review_rounds starts its count
    for t, cmd, out in lines:
        s = step_up(cmd, out)
        inwin = cmd in loop_cmds[:3] and since <= t.astimezone().date().isoformat() <= until
        if cmd in ("story", "agent") and out == "ok" or cmd == "escalate" and re.fullmatch(r"ok \(attempt \d+\)", out):
            if not (cmd == "story" and paired):
                if shown_(lp, cur):
                    out_.append(done(lp, cur))
                counted[0] += 1 if cur else 0   # done keeps a round still open as one of the loop's
                lp, cur, ended = new(t), None, False
                model = lp["model"] = take(model)
            if cmd == "story":
                counted[0] = 0
            lp["base"] = counted[0]
            lp["in"] = lp["in"] or inwin
            paired = cmd == "escalate"
            continue
        paired = False
        if ended:
            continue
        lp["in"] = lp["in"] or inwin
        if cmd == "review-agent" and out == "ok":
            cur = dict(cur or {"model": model, "end": None, "step": []}, start=t)
        elif cmd == "tell:findings" and out == "ok" or s and s[0].startswith("findings") and (cur or lp["last"] != "partway") \
                or cmd in ("review", "merge") and out.startswith("ok") and (cur or lp["last"] in (None, "tell", "partway")):
            cur = cur or {"model": model, "start": None, "end": None, "step": []}
            cur["end"] = t
            lp["rounds"].append(cur)
            counted[0] += 1
            cur, lp["last"] = None, cmd if cmd in ("review", "merge") else "partway" if s and s[3] == "failed" else "tell"
        elif cmd == "decline-only" and out.startswith("ok"):
            if cur:   # its findings went by a line this reader does not close on: the decline-only line ends the round
                cur["end"] = t
                lp["rounds"].append(cur)
                cur, counted[0] = None, counted[0] + 1
            m = re.fullmatch(r"ok \(round (\d+)\)", out)
            want = (int(m.group(1)) if m else 0) - lp["base"] - len(lp["rounds"])
            lp["rounds"] += [{"model": model, "start": None, "end": None, "step": []} for _ in range(want)]
            counted[0] += max(want, 0)
            lp["last"] = "decline-only"
        lp["held"] = lp["held"] or cmd == "escalated" and out.startswith("ok")
        lp["pr"] = review_url(cmd, out) or lp["pr"]
        if s:
            (cur or (lp["rounds"][-1] if lp["rounds"] else {"step": lp["pre"]}))["step"].append(s)
            if s[3] == "ok":
                take(model)
                model = lp["model"] = s[2]
        if cmd == "merge" and out == "ok":
            lp["merged"] = ended = True
    return out_ + ([done(lp, cur)] if shown_(lp, cur) else [])

loop_cmds = ("review-agent", "tell:findings", "escalate", "escalated", "review", "merge", "story", "agent", "decline-only")
by_slug = collections.defaultdict(list)
# An agent line names the agent (agents.tsv's name, cut at 32): its story's slug where one is known.
slug_by_name = {agent_name(t): t for _, c, t, _ in evs if c in ("story", "review-agent", "tell:findings")}
for t, cmd, target, out in evs:
    slug = slug_of.get(pr_key(target)) if "/pull/" in target else slug_by_name.get(target, target) if cmd == "agent" else target
    if slug and (cmd in loop_cmds or step_up(cmd, out)):
        by_slug[slug].append((t, cmd, out))
built = {s: loops(s, lines) for s, lines in by_slug.items()}
# Rounds count per PR (the n-th review of a PR is its round n, as log-finding --round numbers them): each
# build on a PR starts after the rounds of the builds on it before. A finding with a round goes to the
# build whose rounds hold it, the last on its PR taking any later round; one with no round, or on a PR no
# build has, is left out.
on_pr = collections.defaultdict(list)
for lp in sorted((lp for b in built.values() for lp in b if lp["pr"]), key=lambda lp: lp["t0"]):
    lp["off"] = sum(len(o["rounds"]) for o in on_pr[pr_key(lp["pr"])])
    on_pr[pr_key(lp["pr"])].append(lp)
for _, _, pr, _, verdict, _, _, n in finding_rows(findings, width=8):
    took = [lp for lp in on_pr[pr_key(pr)] if n.isdigit() and lp["off"] < int(n)]
    if took:
        took[-1]["c"][(int(n), verdict)] += 1
shown = {s: [lp for lp in b if lp["in"]] for s, b in sorted(built.items()) if not epic or epic_of.get(s) == epic}
shown = {s: b for s, b in shown.items() if b}
if not shown:
    print("no review loop in the window" + (f" for epic {epic}" if epic else ""))
    raise SystemExit
ladder = os.environ.get("SWARM_LADDER", "").replace(",", " ").split()
top = ladder[-1] if ladder else None
pr_rounds, fixed_in, round3_min, failed = {}, collections.Counter(), 0, 0   # each PR's rounds, by its last build shown
stepped = collections.Counter()   # the stepped-up builds, and their fixes and rounds up to and after the first step-up
print("story\tpr\tround\tmodel\tminutes\tfixed\tdeclined\tstep_up")
ends = []
for slug, builds in shown.items():
    for lp in builds:
        pr, c, rounds, off = lp["pr"] or "-", lp["c"], lp["rounds"], lp.get("off", 0)
        n = max([off + len(rounds)] + [r for r, _ in c])   # the PR's last round in this build
        rounds += [{"model": lp["model"], "start": None, "end": None, "step": []} for _ in range(n - off - len(rounds))]
        failed += sum(s[3] == "failed" for s in lp["pre"])
        if not rounds:   # no round: its step-ups alone, on a row with no round, and no end state
            steps = [f"{t}: {a} -> {b} {ok} before review" for t, a, b, ok in lp["pre"]]
            if steps:
                print(f"{slug}\t{pr}\t-\t{lp['model']}\t-\t0\t0\t{', '.join(steps)}")
            continue
        up = off if any(s[3] == "ok" for s in lp["pre"]) else None
        for i, r in enumerate(rounds, off + 1):
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
            stepped.update(builds=1, rounds_before=up - off, rounds_after=n - up,
                           fixed_before=sum(c[(i, "fixed")] for i in range(off + 1, up + 1)),
                           fixed_after=sum(c[(i, "fixed")] for i in range(up + 1, n + 1)))
        end = "held-for-lead" if lp["held"] else "open" if not (lp["merged"] or pr_key(pr) in merged) \
            else "decline-only" if lp["last"] == "decline-only" else "merged-after-fixes" if c[(n, "fixed")] else "pass"
        ends.append(f"{slug}\t{pr}\t{n}\t{end}")
        if pr != "-":
            pr_rounds[pr_key(pr)] = max(pr_rounds.get(pr_key(pr), 0), n)
print("\nstory\tpr\trounds\tend\n" + "\n".join(ends))
s = sorted(pr_rounds.values())
total = sum(fixed_in[k] for k in ("round1", "round2", "round3_on"))
share = lambda k: f"{int(100 * fixed_in[k] / total + 0.5)}%" if total else "-"
rate = lambda f, r: f"{round(f / r, 1):g}" if r else "-"
print("\nprs\trounds_median\trounds_p90\tmin_round3_on\tfixes\tround1\tround2\tround3_on\ttop_rung\tstepped_up\tfixes_per_round_before\tfixes_per_round_after\tfailed_step_ups")
print("\t".join([str(len(s)), f"{statistics.median(s):g}" if s else "-", str(s[-(-9 * len(s) // 10) - 1]) if s else "-", str(round3_min), str(total),
                 share("round1"), share("round2"), share("round3_on"), share("top_rung") if top else "-",
                 str(stepped["builds"]), rate(stepped["fixed_before"], stepped["rounds_before"]),
                 rate(stepped["fixed_after"], stepped["rounds_after"]), str(failed)]))
