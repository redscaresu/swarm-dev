# retro's incidents section: the times a person stepped in since the window's day, in full, then the
# other incidents counted. First, every lead-hand and user-caught line (the incident lines `swarm.sh
# intervene` writes: target -, outcome `<kind>: <text>`, the field cause=<cause>), oldest first, as TSV
# `day kind cause text`. Then, after a blank line, the other kinds flow_incidents.py counts: every other
# incident line by its kind (the outcome before its first colon) and cause= field (`-` for a line with
# none), and each stalled step-up (an ok escalate line `ok (stalled: <from> -> <to>)`) as kind
# `stalled step-up`, cause -. Each kind and cause is one TSV row `kind cause incidents first last`,
# with its count and its first and last day. Days are local, as flow_incidents takes them, and a line
# dated before the window's day is left out. A part with nothing in it prints a line saying so in place of its header, and
# a missing events.tsv prints one line saying that instead. flow_incidents.py counts these kinds and prints no text.
# Run by retro_report.py, with day (the window's first day) and events (events.tsv's path) among its globals.
import datetime, os
from events_outcome import fields, outcome
from report import STEP_UP

INTERVENE_KINDS = ("lead-hand", "user-caught")   # bin/swarm.sh's INTERVENE_KINDS
STALLED_STEP_UP = "stalled step-up"

since, path = day, events  # noqa: F821 # retro_report.py's context


def local_time(stamp):
    try:
        return datetime.datetime.fromisoformat(stamp.replace("Z", "+00:00")).astimezone()
    except ValueError:
        return None


if not os.path.exists(path):
    print(f"no incidents: {path} does not exist")
    raise SystemExit(0)

stepped_in, others = [], {}
with open(path, errors="ignore") as log:
    for line in log:
        f = line.rstrip("\n").split("\t")
        if len(f) != 5 or f[1] not in ("incident", "escalate"):
            continue
        step_up = STEP_UP.fullmatch(outcome(f)) if f[1] == "escalate" else None
        if f[1] == "escalate" and not (step_up and step_up[1] == "stalled"):
            continue
        at = local_time(f[0])
        if at is None or at.date().isoformat() < since:
            continue
        when = at.date().isoformat()
        kind, _, text = outcome(f).partition(":")
        kind, cause = (STALLED_STEP_UP, "-") if step_up else (kind.strip(), fields(f).get("cause", "-"))
        if kind in INTERVENE_KINDS:
            stepped_in.append((at, when, kind, cause, text.strip()))
            continue
        n, first, last = others.get((kind, cause), (0, when, when))
        others[(kind, cause)] = (n + 1, min(first, when), max(last, when))

if stepped_in:
    print("day\tkind\tcause\ttext")
    for _, when, kind, cause, text in sorted(stepped_in, key=lambda r: r[0]):
        print(f"{when}\t{kind}\t{cause}\t{text}")
else:
    print(f"no lead-hand or user-caught lines since {since}")
print()
if others:
    print("kind\tcause\tincidents\tfirst\tlast")
    for (kind, cause), (n, first, last) in sorted(others.items()):
        print(f"{kind}\t{cause}\t{n}\t{first}\t{last}")
else:
    print(f"no other incidents since {since}")
