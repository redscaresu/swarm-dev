# flow's sections: every flow_<name>.py beside this file, in name order (or only the names given after
# the context), each under a `## <name>` line and after a blank line. A section is a script run with
# the context as its globals: since and until (0000-00-00 and 9999-12-30 when not given), epic ("" when
# not given), the log paths agents, events and findings, features (docs/features.tsv), roles (the
# builder roles), projects (Claude's projects dir), archive (close's session copies), lead (the
# calling pane's session, or "") and own (the lead's own Claude Code directory); rows, outcomes' rows
# as dicts by column name, unfiltered; deps, each windowed slug's depends_on. A section that needs gh
# calls it itself. So a new section is a new file, and this one never changes. A section that raises
# prints `error: <name>: <message>` under its heading, the others still run, and flow exits 1; so does
# one that calls sys.exit with a failing code (sys.exit() or sys.exit(0) only ends that section).
import glob, os, runpy, sys, traceback
KEYS = "since until epic agents events findings features roles projects archive lead own".split()
ctx = dict(zip(KEYS, sys.argv[1:len(KEYS) + 1]))
table = [l.split("\t") for l in os.environ.get("SWARM_ROWS", "").splitlines()]
ctx["rows"] = [dict(zip(table[0], f)) for f in table[1:] if len(f) == len(table[0])] if table else []
ctx["deps"] = {s: d.split() for s, _, d in (l.partition("\t") for l in os.environ.get("SWARM_DEPS", "").splitlines())}
here = os.path.dirname(os.path.abspath(__file__))
names = sys.argv[len(KEYS) + 1:] or [os.path.basename(p)[len("flow_"):-len(".py")]
                                     for p in sorted(glob.glob(os.path.join(glob.escape(here), "flow_*.py")))]
failed = False
for i, name in enumerate(n for n in names if n != "report"):
    print(("\n" if i else "") + f"## {name}", flush=True)
    try:
        runpy.run_path(os.path.join(here, f"flow_{name}.py"), init_globals=dict(ctx), run_name="__main__")
    except SystemExit as e:
        if e.code not in (None, 0):
            print(f"error: {name}: exit {e.code}")
            failed = True
    except Exception as e:
        print(f"error: {name}: {e}")
        traceback.print_exc()
        failed = True
    sys.stdout.flush()
sys.exit(1 if failed else 0)
