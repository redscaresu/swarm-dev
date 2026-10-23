---
kind: code
status: ready
depends_on: []
touches: [bin/lib/report.py:gh, bin/lib/reports.sh:flow doc comment, tests/flow_test.sh]
easy: true
estimate_lines: 40
---

# flow reads a job log that isn't UTF-8 instead of reporting it as "not JSON"

The backlog conductor logged this out of scope on #370 (2026-10-23). report.py's gh() (line 199) with parse=str decodes output strictly, so a CI log with one non-UTF-8 byte is reported as "not JSON". Its FAIL lines are lost, and flow-flaky-tests miscounts that run. Decode logs with errors="replace". Only a JSON call reports a parse error, and it says "not JSON" only for JSON. Also fix the flow doc comment in reports.sh (around :282), which lists the flaky and ci time tables in the wrong order.

**Done when:**
- tests/flow_test.sh: a log fixture with a 0xff byte next to a `FAIL tests/a_test.sh` line still counts a_test.sh as flaky, and no "not JSON" line prints.
- The reports.sh comment lists the sections in the order flow prints them.
