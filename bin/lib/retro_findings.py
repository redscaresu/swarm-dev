# retro's findings section: the findings declined as out-of-scope or deferred since the window's day
# that are still open (their newest row is that decline) and that no story carries. retro_report
# writes them to findings_open with `out_of_scope_findings <day>` (bin/lib/reports.sh), which holds
# the rules; this prints that file's lines as they come, newest first, one per finding:
# `<reason> <date> <kind> <pr>: <text>`. An empty file prints one line saying none were found since
# the tag. Run by retro_report.py, with findings_open and tag among its globals.
with open(findings_open, encoding="utf-8", errors="replace") as f:  # noqa: F821 # retro_report.py's context
    lines = [line.rstrip("\n") for line in f if line.strip()]
if not lines:
    print(f"no out-of-scope or deferred findings open since {tag}")  # noqa: F821 # retro_report.py's context
for line in lines:
    print(line.replace("\t", " ", 1))
