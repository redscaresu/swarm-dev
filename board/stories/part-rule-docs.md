---
kind: docs
status: blocked
epic: clash-by-part
depends_on: [part-overlap]
needs: [part-overlap: the part rule in bin/lib/touches_rows.py:overlap, which these texts describe]
touches: [bin/lib/build.sh:clash_rule, AGENTS.md:rules that are not negotiable, docs/method.md:building, docs/reference.md:clash rule]
estimate_lines: 60
easy: true
---

# The conductor brief and the docs state the part rule

Needs part-overlap's rule in bin/lib/touches_rows.py:overlap. State it where the old rule is written: the conductor brief's clash_rule (bin/lib/build.sh:1119-1135), AGENTS.md's clash line (:105-106), docs/method.md § Building (:22) and the clash rule in docs/reference.md. The rule: two stories clash only when their touches name the same file and the same first word of a part, or both name the bare file. Within an epic the clash check is conductor prose, so clash_rule is the only code text that changes. Run the humanizer over the changed prose.

AGENTS.md order (epic constraint): if test-speed's story that edits AGENTS.md "Before you open a PR" is open when this builds, merge after it, so the two AGENTS.md edits do not conflict.

**Done when:**
- clash_rule, AGENTS.md, docs/method.md and docs/reference.md each state the part rule, and none still says a bare file clashes with any part of it (a test on clash_rule's text pins the new wording).
- doc_check passes, and `make test` passes.
