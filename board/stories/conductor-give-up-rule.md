---
kind: code
status: blocked
blocked_by: [close-counts-a-failed-build, fable-failure-goes-to-you]
epic: fable-on-call
depends_on: [close-counts-a-failed-build, fable-failure-goes-to-you]
touches: [bin/swarm.sh:give_up_rule (new), bin/swarm.sh:conduct_story_mode, bin/swarm.sh:conduct_epic_mode, commands/swarm.md (story arm), tests/epic_test.sh (conductor brief checks), README.md (§ When /swarm stops for you), docs/method.md (§ Building)]
---

# Conductors and /swarm give up on a builder with close, retry in the same run, and list a Fable consent dialog for you

A give_up_rule heredoc beside auth_rule (:1659), used by conduct_story_mode (:1669) and conduct_epic_mode (:1689): give up on a builder when `wait --stall` returns stalled, when it is idle with no PR (epic mode: no pushed branch) after wait's nudges, or when review has not converged in the rounds you allow; run `swarm.sh close <slug>`, which counts the attempt and clears its worktree, branch and PR; start it again in a later wave with `swarm.sh story <slug>` (swarm.sh picks Fable for the third build; never choose a model). A story that comes back kind: lead is listed for the user as any lead story is. A builder whose wait prints `waiting: dialog open` is on Fable's usage-credits consent: list it for the user, never close or tell it, wait on it again; it is not an attempt. Review-then-close stays the order (conduct_merge_rule :1445). commands/swarm.md's `story <slug>` arm gets the same rule for the lead's one-offs. README § When /swarm stops for you: a row for `waiting: dialog open` (answer it in the builder's pane; dismissing it runs the build on Opus). docs/method.md § Building: one paragraph on giving up and the dialog.

**Done when:**
- tests/epic_test.sh conductor-brief checks (:92-93, :179-192): the story-mode and epic-mode briefs both contain the give-up `swarm.sh close <slug>`, `waiting: dialog open` and that a dialog is not closed or counted; each check fails with give_up_rule's call removed from that mode.
- commands/swarm.md's story arm names the give-up close and `dialog open`; README has the dialog row.
- humanizer ran over the changed README/docs prose and the PR description, and the PR says so; shellcheck bin/swarm.sh tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From review (binding; overrides the scope above where they differ):**
- Runs on macOS's bash 3.2: no mapfile, no associative arrays (AGENTS.md).

**From the user (2026-10-15; binding, overrides the scope above where they differ):** "You should decide the escalation not me." On `waiting: dialog open` the conductor accepts Fable's usage-credits consent itself with `herdr pane send-keys` in the builder's pane, logs `dialog <slug>` (a `swarm.sh` event), and waits on the builder again. It never closes the builder or tells it anything, and the dialog is not an attempt. It does not list the dialog for the user, and README gets no dialog row. README § Cost and safety says instead that a conductor accepts Fable's consent, so a third build may spend Fable usage credits. commands/swarm.md gets an `escalated <slug>` arm: read the attempts' PRs and findings; re-scope the story and `swarm.sh reset <slug>`, or drop it through a board PR, with at most one reset per story; then tell the user what was chosen and why. The epic-test checks look for `send-keys` and `dialog <slug>` in place of the listing. This story depends on fable-failure-goes-to-you, because both edit commands/swarm.md and the arm names that story's `escalated` step.

**From the user (2026-10-15; binding): escalation is logged with its time.** The `dialog <slug>` line is written through `swarm.sh` with log_event's timestamp, with result `accepted` or `dismissed`. commands/swarm.md's `escalated` arm ends with `swarm.sh reset <slug> <reason>` or `swarm.sh drop <slug> <reason>`, so the lead's choice and its reason are in events.tsv with the time. Both commands come from fable-failure-goes-to-you.
