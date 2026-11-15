# Panes, a flow section (flow_report.py gives its globals): how long a review agent's pane stays open once
# its work is done, from events.tsv alone. A story's review agent hands over with `review --head`, which
# writes an ok review-finished line (target <slug>) and then an ok `review` line (outcome `ok (<PR
# URLs>)`), both from the agent's own pane. A review line counts when such a review-finished line of the
# same slug and pane came before it; one without (the lead's own `review`, with no --head) had no review
# pane, so it is skipped, and so is a pair from pane - (run outside herdr, where no review agent runs).
# The lead's own `review --head` from a herdr pane writes the same pair and is not told apart. Each (slug, pane) is one review pane, so a review agent restarted in a new pane
# while the old one stays open is a second row. Its start is that handover, or the story's merge when
# one follows before the pane closes (an ok or `merged elsewhere` merge line whose target is the slug, or
# a PR URL a review line named; it starts every open review pane of the slug). A later handover in the
# same pane before the close moves the start to it (the pane worked again); a merge stays the start
# once it is one, whatever merge line follows. It ends at the first close of that pane after the start:
# a pane-closed line with slug=<slug> role=review and pane=<its pane>, paired by those fields and never
# by its target, so a retired review-<cut>-done pane pairs too; or an ok `close review-<slug>` line from
# before LOGGED_FROM, which closes every open review pane of the slug (a later one has its pane-closed
# lines). TSV story from minutes pane: from is merge or handover, pane is closed, or open with the
# minutes so far. An open row whose handover line (its newest, even when a merge is the start) has no
# version= or one before LOGGED_FROM reads unlogged with minutes -: that swarm.sh logged no pane-closed
# line for the closes it made itself (reconcile's, after a merge), so the pane may have closed unseen; it
# is not measured and not counted.
# A row counts in the window when its start's local day is in it. Then, after a blank line, over_30:
# the rows whose minutes, as shown, are past 30, open ones too. --epic does not narrow it.
import datetime, os, re
from events_outcome import fields, outcome

OVER_MIN = 30
URLS = re.compile(r"https://\S+/pull/\d+")
LOGGED_FROM = (0, 30, 1)   # the first release whose swarm.sh logs a pane-closed line for each pane it closes


def when(t):
    try:
        return datetime.datetime.fromisoformat(t.replace("Z", "+00:00"))
    except ValueError:
        return None


def logged(version):
    try:
        return tuple(int(n) for n in version.split(".")[:3]) >= LOGGED_FROM
    except ValueError:
        return False


def close(key, t):
    done.append([key[0], *pending.pop(key), t])


# pending: (slug, pane) -> [from, start time, handover line's version]
finished, slug_of, pending, done = set(), {}, {}, []
for line in open(events, errors="ignore") if os.path.exists(events) else ():
    f = line.rstrip("\n").split("\t")
    if len(f) != 5 or (t := when(f[0])) is None:
        continue
    cmd, target, o, kv = f[1].partition(":")[0], f[2], outcome(f), fields(f)
    if f[1] == "review-finished" and o == "ok" and f[3] != "-":
        finished.add((target, f[3]))
    elif f[1] == "review" and o.startswith("ok (") and (target, f[3]) in finished:
        finished.discard((target, f[3]))
        slug_of.update((u, target) for u in URLS.findall(o))
        if pending.get((target, f[3]), ["handover"])[0] == "handover":
            pending[(target, f[3])] = ["handover", t, kv.get("version", "")]
    elif f[1] == "merge" and o in ("ok", "merged elsewhere"):
        for key in [k for k in pending if k[0] == slug_of.get(target, target) and pending[k][0] == "handover"]:
            pending[key] = ["merge", t, pending[key][2]]   # the handover's version: the pane worked under it
    elif f[1] == "pane-closed" and kv.get("role") == "review" and (kv.get("slug"), kv.get("pane")) in pending:
        close((kv["slug"], kv["pane"]), t)
    elif cmd == "close" and o == "ok" and target.startswith("review-") and not logged(kv.get("version", "")):
        for key in [k for k in pending if k[0] == target[len("review-"):]]:
            close(key, t)

now = datetime.datetime.now(datetime.timezone.utc)
over = 0
print("story\tfrom\tminutes\tpane")
for slug, kind, start, version, end in sorted(done + [[k[0], *v, None] for k, v in pending.items()], key=lambda r: r[2]):
    if not since <= start.astimezone().date().isoformat() <= until:
        continue
    if not end and not logged(version):
        print(f"{slug}\t{kind}\t-\tunlogged")
        continue
    mins = round(((end or now) - start).total_seconds() / 60)
    over += mins > OVER_MIN
    print(f"{slug}\t{kind}\t{mins}\t{'closed' if end else 'open'}")
print("\nover_30", over, sep="\n")
