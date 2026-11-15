# Run times, a flow section (flow_report.py gives its globals): .swarm/run-times.tsv beside events.tsv,
# one row per status, next or dash run (bin/swarm.sh's timed): its start (UTC), command, seconds and
# 1-minute load average. Over the rows whose local day is in the window, TSV command runs median_s
# p90_s over_60s: per command, in name order, its runs, the median and p90 (nearest rank) seconds and
# the share of runs over 60 s. Then, after a blank line, a by-load block, TSV command load runs
# median_s: per command and 1-minute load band (<10, 10-20, 20+, and - for a load of - or one that is
# not a number), in command-name order then band order, its runs and median seconds. A band edge
# goes to the band above it (a load of 10 is 10-20). Torn rows (no newline, a time that does not
# parse, seconds that are not digits, or a command other than those three) are skipped.
# With no log it prints one line saying so, and with no row in the window another. --epic does not
# narrow it.
import datetime, os, re, statistics

SLOW_S = 60
COMMANDS = ("dash", "next", "status")
SECONDS = re.compile(r"[0-9]+(\.[0-9]+)?")
LOAD_LOW = 10    # a 1-minute load under this is the <10 band
LOAD_HIGH = 20   # from LOAD_LOW up to under this is 10-20; this and over is 20+
NO_LOAD = "-"
BANDS = (f"<{LOAD_LOW}", f"{LOAD_LOW}-{LOAD_HIGH}", f"{LOAD_HIGH}+", NO_LOAD)


def band(load):
    """The load band of a row's load field: one of BANDS, NO_LOAD for - or a load that is not a number."""
    if not SECONDS.fullmatch(load):
        return NO_LOAD
    x = float(load)
    return BANDS[0] if x < LOAD_LOW else BANDS[1] if x < LOAD_HIGH else BANDS[2]


log = os.path.join(os.path.dirname(events), "run-times.tsv")
lines = [l[:-1].split("\t") for l in open(log, errors="ignore") if l.endswith("\n")] if os.path.exists(log) else []
runs = {}
by_load = {}
for f in lines:
    if len(f) != 4 or f[1] not in COMMANDS or not SECONDS.fullmatch(f[2]):
        continue
    try:
        day = datetime.datetime.fromisoformat(f[0].replace("Z", "+00:00")).astimezone().date().isoformat()
    except ValueError:
        continue
    secs = float(f[2])
    if since <= day <= until:
        runs.setdefault(f[1], []).append(secs)
        by_load.setdefault((f[1], BANDS.index(band(f[3]))), []).append(secs)

if not os.path.exists(log):
    print(f"no run times logged: no {log} yet (status, next and dash write it)")
elif not runs:
    print(f"no run times logged in the window ({since} to {until})")
else:
    print("command\truns\tmedian_s\tp90_s\tover_60s")
    for cmd, s in sorted(runs.items()):
        s.sort()
        p90 = s[-(-9 * len(s) // 10) - 1]
        over = sum(x > SLOW_S for x in s) / len(s)
        print(f"{cmd}\t{len(s)}\t{statistics.median(s):.2f}\t{p90:.2f}\t{100 * over:.0f}%")
    print()
    print("command\tload\truns\tmedian_s")
    for (cmd, b), s in sorted(by_load.items()):
        print(f"{cmd}\t{BANDS[b]}\t{len(s)}\t{statistics.median(s):.2f}")
