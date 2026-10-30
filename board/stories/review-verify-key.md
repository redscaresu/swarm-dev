---
kind: code
status: ready
epic: review-rounds-end
depends_on: []
touches: [bin/swarm.sh:CONFIG_KEYS and CFG_review_verify, bin/swarm.sh:load_config validation arm (review_verify), bin/lib/build.sh:review_brief (review_verify line), docs/reference-models.md:Settings (review_verify), docs/method.md:Configuring a project (settings table), docs/reference-building.md:Review before closing (review_verify), tests/config_test.sh:review_verify cases, tests/review_handoff_gaps_test.sh:review_verify cases]
estimate_lines: 70
easy: false
---

# review_verify = ci | full, default ci: the review brief says whether the review agent may run tests

Needs nothing from another story. A new key review_verify: CFG_review_verify=ci beside CFG_merge_admin (bin/swarm.sh:232), review_verify in CONFIG_KEYS (:237), and a validation arm like merge_admin's (:289-290) that refuses anything but ci or full, naming the key and value. review_brief (bin/lib/build.sh:1382-) carries one line from it: with ci, every round reads the diff and trusts CI, with no local test suite and no mutation run; with full, round 1 (the brief's round, $6) may run the project's selected tests for the changed files and check the builder's mutation proofs, and rounds 2 and later are ci, so a brief started on round 2 or later carries the ci line. Docs: docs/reference-models.md § Settings (:123-140), docs/method.md's settings table (§ Configuring a project, :93-140) and docs/reference-building.md § Review before closing. The key name passes tests/removed_test.sh:52, but write no bare word verify in bin/ prose and no 'verify story' or 'kind: verify' in docs (removed_test.sh:57). No board sets the key, so upgrade changes nothing. The CONFIG_KEYS edit is top-level code, so scripts/select-tests.sh runs the full suite. Humanizer over the changed docs.

**Done when:**
- tests/config_test.sh: with no review_verify line the loaded value is ci; `review_verify = full` loads as full; `review_verify = maybe` is refused with a message naming review_verify and maybe; proven red by dropping the validation arm in a worktree copy.
- tests/review_handoff_gaps_test.sh: review_brief on round 1 carries the ci line by default and with CFG_review_verify=ci; with CFG_review_verify=full, round 1's brief carries the full line and not the ci line, and a brief on round 2 carries the ci line.
- The full suite passes under scripts/select-tests.sh --run (a CONFIG_KEYS edit selects it), tests/removed_test.sh and tests/doc_check_test.sh among them.
- With review_verify = full, round 1's brief says later rounds are ci, and `swarm.sh review-agent --next` at round 2 under full mode carries the ci line (tested on review_next's output, not only review_brief).
