# retro's sections: every retro_<name>.py beside this file, in name order, each under a `## <name>`
# line and after a blank line. A section is a script run with the context as its globals: tag (the
# window's tag), day (its commit's day, YYYY-MM-DD), project and board (the project and board dirs),
# events and findings (the events.tsv and findings.tsv paths), memory (the lead's memory folder) and
# findings_open (a file holding out_of_scope_findings' lines for the window's day). A section makes no
# gh call: retro is read-only and asks gh nothing. So a new section is a new file, and this one never
# changes. A section that raises prints `error: <name>: <message>` under its heading, the others
# still run, and retro exits 1; so does one that calls sys.exit with a failing code (sys.exit() or
# sys.exit(0) only ends that section). bin/lib comes first on sys.path (SWARM_LIB, under python3 -I),
# so a section imports bin/lib's report.py, never a file of that name in the project. The environment
# holds SWARM_FINDING_REVIEWERS, so report.py's finding readers can read findings.tsv.
import glob, os, runpy, sys, traceback
sys.path.insert(0, os.environ["SWARM_LIB"])
KEYS = "tag day project board events findings memory findings_open".split()
ctx = dict(zip(KEYS, sys.argv[1:len(KEYS) + 1]))
here = os.path.dirname(os.path.abspath(__file__))
names = [os.path.basename(p)[len("retro_"):-len(".py")] for p in sorted(glob.glob(os.path.join(glob.escape(here), "retro_*.py")))]
failed = False
for i, name in enumerate(n for n in names if n != "report"):
    print(("\n" if i else "") + f"## {name}", flush=True)
    try:
        runpy.run_path(os.path.join(here, f"retro_{name}.py"), init_globals=dict(ctx), run_name="__main__")
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
