---
kind: code
status: ready
epic: flow-speedups
touches: [bin/swarm.sh:start_conductor, tests/next_test.sh]
---

# swarm.sh conduct sets its epic to active

`swarm.sh conduct <epic>` starts a conductor but leaves the epic's `status:` as it was. On 2026-10-15 flow-speedups and dash-tells-the-truth ran under conductors while still `later`, so `status` and `next` listed them as "later epic, waiting on you" (fixed by hand in #145). start_conductor sets `status: active` in the main checkout's epic file with set_fm (an uncommitted board edit like unblock's) when it says `later`, and prints one line saying so. An epic in `review` is refused as today.

**Done when:**
- tests/next_test.sh: `conduct e` on an epic with `status: later` leaves `status: active` in the epic file, prints a line naming e, and `status` no longer lists e under waiting on you.
- An epic already `active` is unchanged and nothing extra is printed.
- The PR shows the check failing with the set_fm call removed; shellcheck and every tests/*_test.sh pass.
