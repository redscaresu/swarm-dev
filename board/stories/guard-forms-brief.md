---
kind: code
status: blocked
epic: board-pr-and-briefs
depends_on: [conduct-brief-hands-off, owner-merge-handoff]
needs: [conduct-brief-hands-off (conductor-hands-off): conduct_brief as it rewrites it, owner-merge-handoff (review-loop): review_brief as it rewrites it, the brief of an agent that now merges]
touches: [bin/lib/build.sh:guard_rule (new), bin/lib/build.sh:merge_rule, bin/lib/build.sh:review_brief, bin/lib/build.sh:conduct_brief, tests/guard_forms_test.sh (new)]
estimate_lines: 120
easy: false
---

# Briefs show the command forms the guard accepts and forms that need no approval

Uses conductor-hands-off's conduct-brief-hands-off (the conductor brief) and review-loop's owner-merge-handoff (the review brief) as they leave them. Add guard_rule (bin/lib/build.sh, new): `cd <dir> || exit 1 &&` (never `cd <dir>;`), `swarm.sh merge` alone in its Bash call, merge text written only through the Write tool or a quoted heredoc (a merge written into a file that is then run is a raw merge, hooks/merge-guard.sh:43-44), and wait with swarm.sh wait or wait-pr, never a loop of your own. It also shows a delete that Claude Code runs without a permission prompt, in place of the `rm -rf "$SP/$m"` a builder was prompted on (moved here from fixes-027's small-fixes-027): find the form auto mode allows and say in the PR how you checked. Print guard_rule from merge_rule (:16-20, so the builder brief gets it with no story_brief edit), review_brief and conduct_brief. The guard and tests/merge_guard_test.sh do not change.

**Done when:**
- tests/guard_forms_test.sh (new) renders the builder, review and conductor briefs and finds guard_rule's forms in each; it fails when guard_rule is dropped from any one.
- The same test feeds each Bash example in guard_rule to hooks/merge-guard.sh as a Bash tool call and sees it allowed, and checks separately that the Write tool and quoted-heredoc guidance is stated (it is not a Bash call).
- The same test pins the no-prompt delete form; the PR says how that form was shown to run without a prompt.
- git diff shows hooks/merge-guard.sh and tests/merge_guard_test.sh unchanged.
