---
kind: code
status: blocked
blocked_by: [close-counts-a-failed-build]
epic: fable-on-call
depends_on: [close-counts-a-failed-build]
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
