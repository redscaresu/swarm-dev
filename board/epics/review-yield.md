---
status: active
hld: 2026-10-28-swarm-dev-0-30-and-0-31
stage: v0.31.0
depends_on: []
---

# Reviews spend their rounds on findings that get fixed: we can see which reviewer and which kinds are declined, and the noisy ones are cut

**Brought into v0.31.0 (user, 2026-10-31)**, under the 0.30/0.31 HLD's v0.31.0 additions. Earlier: **Parked (user, 2026-10-25):** set `later` so planning the 0.28 HLD comes first. Its remaining stories are all lead stories, parked with it, each with a note saying where it goes.

**Done when:**
- Every logged finding records which reviewer raised it (codex, code-review, conductor, lead, or unknown for old lines): `swarm.sh log-finding` takes it, the briefs and conduct rules pass it, and old lines without it still read.
- ~~`swarm.sh review-yield`~~: not built. `swarm.sh flow`'s `reviewers` and `review_loops` sections give the same per-reviewer and per-kind figures (narrowed with the user, 2026-11-15).
- The tuning change and its after reading move to review-yield-tuning (narrowed with the user, 2026-11-15).
- The swarm-dev board's existing findings (about 60% declined: 207 declined vs 140 fixed on 2026-10-15; 364 vs 211, 63%, at the baseline cut on 2026-10-16) are summarised in that lead story as the baseline, by kind.
- Demoting the four kinds (duplicate-code, missing-case, efficiency, hot-path-cost), the after reading and the 4+ round bar move to review-yield-tuning, which switches `demote_kinds` on once a release carries demote-kinds-key (narrowed with the user, 2026-11-15). The codex-time-limit and codex-bump-not-a-finding stories are not built.

**Out of scope:** removing codex or /code-review outright. Changing what counts as a finding kind.

**Constraints:** bash 3.2, shellcheck, every tests/*_test.sh. findings.tsv stays readable by `lessons`, `outcomes` and `decisions` (append a column, never reorder). New flags default to today's behaviour. Stories touching codex review prompts depend on flow-speedups' codex-time-limit and lead-loop's codex-bump-not-a-finding. Bump plugin.json in a release story.

**Checks before every stage:** every PR passes shellcheck bin/swarm.sh tests/*.sh, every tests/*_test.sh and `claude plugin validate .`; shows each new check failing with its code removed; and ran humanizer over changed README/docs prose and its description, saying so.

**Your part:** none; the user approved the stories on 2026-10-15.
