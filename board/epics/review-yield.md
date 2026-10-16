---
status: active
---

# Reviews spend their rounds on findings that get fixed: we can see which reviewer and which kinds are declined, and the noisy ones are cut

**Done when:**
- Every logged finding records which reviewer raised it (codex, code-review, conductor, lead, or unknown for old lines): `swarm.sh log-finding` takes it, the briefs and conduct rules pass it, and old lines without it still read.
- `swarm.sh review-yield [--since YYYY-MM-DD]` prints, per reviewer and per finding kind: findings raised, fixed, declined, the decline rate, and review rounds per PR (from tell:findings lines); a stub findings/events fixture pins the numbers.
- After one epic's worth of data with reviewers recorded, the lead posts the report on this epic's lead story and makes the tuning change it shows (a prompt line that names the kinds a reviewer keeps raising and that get declined, or dropping /code-review for docs/chore/board-only PRs), each as its own PR with the before numbers; a later report shows the decline rate for the tuned reviewer or kind went down, or the lead says it did not and reverts.
- The swarm-dev board's existing findings (about 60% declined: 207 declined vs 140 fixed on 2026-10-15; 364 vs 211, 63%, at the baseline cut on 2026-10-16) are summarised in that lead story as the baseline, by kind.

**Out of scope:** removing codex or /code-review outright. Changing what counts as a finding kind.

**Constraints:** bash 3.2, shellcheck, every tests/*_test.sh. findings.tsv stays readable by `lessons`, `outcomes` and `decisions` (append a column, never reorder). New flags default to today's behaviour. Stories touching codex review prompts depend on flow-speedups' codex-time-limit and lead-loop's codex-bump-not-a-finding. Bump plugin.json in a release story.

**Checks before every stage:** every PR passes shellcheck bin/swarm.sh tests/*.sh, every tests/*_test.sh and `claude plugin validate .`; shows each new check failing with its code removed; and ran humanizer over changed README/docs prose and its description, saying so.

**Your part:** none; the user approved the stories on 2026-10-15.
