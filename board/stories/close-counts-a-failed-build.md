---
kind: code
status: blocked
blocked_by: [wire-escalate-role]
epic: fable-on-call
depends_on: [wire-escalate-role]
touches: [bin/swarm.sh:set_fm (new, beside set_status), bin/swarm.sh:close_agent, bin/swarm.sh:a cleanup helper close_agent calls (new), bin/swarm.sh:usage header (close line), tests/close_test.sh, tests/epic_test.sh (new e2e block after the role block), tests/next_test.sh (resume block :63), tests/review_test.sh (reconcile block), docs/method.md (§ Model and effort), board/stories/README.md, templates/docs/stories/README.md, README.md (§ Cost and safety)]
risk: high
---

# close counts a failed build once in attempts: and clears its worktree, branch and PR, so the next story starts fresh

A front-matter writer beside set_status (:1981): set_fm <file> <key> [value] sets or adds the key, or removes it with no value; set_status is left alone. close_agent (:3114): archive_session (#93) stays first. A close counts when <board>/stories/<arg>.md exists, says status: ready, has an agent kind, has no merged PR on story/<slug>, and this close finds the builder open under the slug's name (its pane in a STATE_DIR record, or with keep_panes the herdr agent retire_agent renames). Decide before closing; after closing or retiring, a counted close raises attempts: by one, then in the story's repo (repo_dir of repo:) removes the worktree (worktree_for), deletes local story/<slug>, closes each open PR on it unmerged (gh pr close, with a comment naming the attempt) and deletes origin's story/<slug>. One `gh pr list --head story/<slug> --state all --json number,state,url` answers both the merged guard and the PRs to close. gh failing is said on stderr and never stops the close; with pr_per = epic there is no PR and only the branches go. reconcile, review, finish and every other close (conduct-*, hld-*, plan-*, a name with no story file) behave as today. Docs: § Model and effort (close counts a failed build; the third build is Fable); both stories READMEs gain attempts:, written by swarm.sh only; README Cost and safety: a story that failed twice is built once on Fable, escalate_after = 0 turns it off; the usage line for close.

**Done when:**
- tests/close_test.sh: closing a builder whose story is ready writes attempts: 1 with keep_panes false and with keep_panes true; closing it again leaves 1; a story in review, a deleted story, a story whose PR merged (gh stub), and closes of conduct-x, hld-x and plan-x write nothing and remove no worktree or branch.
- tests/epic_test.sh end to end against the herdr, claude and gh stubs and the bare svc remote: story, close, story, close, story on one ready code story records roles code, code, escalate in agents.tsv; every worktree add succeeds; after each close the worktree dir, local story/<slug> and origin's story/<slug> are gone and the gh stub logged `pr close` for the open PR.
- tests/next_test.sh: a one-off with a worktree is `resume` before the counted close and `story <slug>` after it.
- tests/review_test.sh: reconcile sending a review story back to ready writes no attempts: line.
- The PR shows each new check failing with the counting removed; humanizer ran over the changed README/docs prose and the PR description, and the PR says so; shellcheck bin/swarm.sh tests/*.sh, every tests/*_test.sh and `claude plugin validate .` pass.

**From review (binding; overrides the scope above where they differ):**
- Cleanup uses `git worktree remove --force` and `git branch -D`. The end-to-end test commits and pushes story/<slug> to the svc remote (and leaves an untracked file) before each close, so 'gone' and 'the next worktree add succeeds' can fail.
- When the merged-PR check's gh call fails: no count and no cleanup, reported on stderr; a close_test case with the gh stub failing writes nothing. A merged story is never counted.
- A close_test case: closing a ready story with no open builder and no retired builder (including a pane closed by hand) counts nothing.
- Put a gh stub on PATH at the top of tests/epic_test.sh; add the existing close blocks (epic_test.sh:111, :129) to touches and update their expectations.
- Runs on macOS's bash 3.2: no mapfile, no associative arrays (AGENTS.md).
