---
kind: code
status: blocked
epic: go-layers
depends_on: [go-layer-walk, go-clock]
needs: go-layer-walk (the walk's records in internal/layers/walk_test.go); go-clock (internal/clock, the one package the rule exempts)
touches: [internal/layers/time_test.go, internal/layers/testdata/time/]
estimate_lines: 140
---

# Fail a Go package other than the clock that reads the time

Uses the walk's records in internal/layers/walk_test.go from go-layer-walk, which it does not edit, and internal/clock from go-clock. This is tests.tsv:83's go_check for tests/lint_test.sh: no package but the clock reads the time, as scripts/lint's python-clock rule does for bin/lib/*.py. The python-clock rule stays until bash-retired. The rule, for every class but the clock, adapters and wiring included: a selector on time must be on time's allowed names, so a name not listed fails, called or only passed, under any import name. Allowed: the types (Duration, Location, Month, ParseError, Time, Weekday), the constants (the units, the layouts, the months and the days), Date, FixedZone, Local, Parse, ParseDuration, ParseInLocation, Unix, UnixMicro, UnixMilli and UTC. So Now, Since, Until, Sleep, After, AfterFunc, Tick, NewTicker, NewTimer and any name Go adds later fail, and LoadLocation fails too, as it reads the zone files. A dot import of time fails here in every class, adapters included; go-layer-walk fails it only outside them. A context deadline (context.WithTimeout) is not a read: it runs on the real clock, as clock.py leaves time.time() to deadlines. The test logs internal/clock as the one package that may read the time. Fixtures follow go-layer-walk's limits. Break: allow time.Sleep; the fixture test must go red.

**Done when:**
- For fixture trees under internal/layers/testdata/time/ the test asserts the exact findings by file:line: each of the ten banned names called and passed as a value, an aliased time, a dot import of time in an adapter, and time.Now in wiring. A clean file using Duration, Unix and Date passes. On the real tree it passes, with internal/clock's own reads allowed, and fails when internal/clock is missing. A throwaway tmp/ branch PR with a time.Now() in a rules package turns go-checks red, and is closed unmerged. The story PR links it. tests/port_swarm_names_test.sh and tests/port_locks_test.sh pass.
- scripts/select-tests.sh --run passes
