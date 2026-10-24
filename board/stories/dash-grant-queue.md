---
kind: code
status: later
depends_on: []
touches: [bin/lib/dash_render.py:awaiting rows, tests/dash_test.sh]
estimate_lines: 40
easy: true
---

# dash shows a granted PR as the lead's, not the user's

Under `merge = human`, dash (bin/lib/dash_render.py, around :357) lists every waiting PR in the user's queue, but a PR whose HLD grants `merge` (and that has no `costs: money`) is now the lead's to land. Show those as the lead's.

**Done when:**
- A dash test: under `merge = human`, a PR whose HLD grants `merge` is not in the user's queue; a `costs: money` one still is.
- `make test` passes.
