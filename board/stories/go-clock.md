---
kind: code
status: ready
epic: go-layers
depends_on: []
touches: [internal/clock/clock.go, internal/clock/clock_test.go, docs/port/swarm-names.tsv:SWARM_DASH_NOW row, docs/port/swarm-names.tsv:SWARM_SLEEP_SCALE row]
estimate_lines: 230
---

# Add the Go clock: now and today under SWARM_DASH_NOW, and sleeps under SWARM_SLEEP_SCALE

Adds internal/clock's code beside go-interfaces' doc.go, the one package that may read the time (HLD:339-340). clock.go has no package comment: doc.go holds it. It has what bin/lib/clock.py:9-21 has: Now is SWARM_DASH_NOW in epoch seconds, fraction kept, when set and not empty, else the real clock, and a non-number is an error. Today is Now's local day, and UTCNow is Now in UTC. It also adds Real, the real clock with the pin ignored, for deadlines and ages: the epic bans every other time read, wider than clock.py, which leaves time.time() to them (clock.py:4-5). Scale reads SWARM_SLEEP_SCALE with bin/swarm.sh:116-121's check and message, word for word: it must match ^[0-9]*\.?[0-9]+$ and be at least 0.001, and unset or empty means 1. Scaled and Nap copy agents.sh:1814-1819: the seconds times the scale, rounded to the millisecond as awk's %.3f does, at least 0.1 s. report.py:239 (no floor) and hooks/lead-stop.sh:22 (at least 1 s) keep their own rules until their ports. Go's ParseFloat differs from Python's float(): the test names the inputs that match (integers, decimals, exponents) and the ones that differ (spaces, underscores, hex, inf, nan). The byte comparison with clock.py is helpers-shared's job. CI runs on UTC, and Go reads TZ once per process, so t.Setenv("TZ") can be ignored: the test sets time.Local to a fixed zone, puts it back, and does not run that case in parallel. Add internal/clock/clock.go to the SWARM_DASH_NOW and SWARM_SLEEP_SCALE rows (docs/port/swarm-names.tsv:34,113). Break: drop the 0.1 s floor, read an empty SWARM_DASH_NOW as 0, or make Today use UTC; the test must go red.

**Done when:**
- With SWARM_DASH_NOW=1700000000 and time.Local set to UTC+14, Now is that instant, Today is 2023-11-15 and UTCNow's day is 2023-11-14. A pin of 1700000000.5 gives Now with its half second, and 1.7e9 gives 1700000000. With the pin set, Real falls between two real-clock reads. With SWARM_DASH_NOW empty, Now falls between two real-clock reads, and with "abc" it is an error. Scale accepts 0.01, 5 and .5, and is 1 when unset and when empty. It refuses 5., 1e-2, +1, inf, NaN, 0 and 0.0009, each with the message "SWARM_SLEEP_SCALE: '<v>' is not a number of at least 0.001". Unset, Scaled(30) is 30 s. At scale 0.01, Scaled(30) is 300 ms and Scaled(1) is 100 ms. At scale 0.1236, Scaled(1) is 124 ms. Nap(1) at 0.01 sleeps at least 100 ms and less than 1 s. tests/port_swarm_names_test.sh passes, with internal/clock/clock.go in both rows.
- scripts/select-tests.sh --run passes
