# Running a repo's PR review bot

With `review_bot = auto`, the conductor runs the repo's PR review bot on each story PR once its
checks pass and `swarm.sh findings` is triaged, and before it hands the PR on (to `swarm.sh review`
or to its own merge). With `review_bot = off` (the default) it skips this.

**1. Find the bot.** Look at who reviewed the repo's recent PRs:

```bash
gh pr list --state all --limit 20 --json number \
  | jq -r '.[].number' \
  | xargs -I{} gh api "repos/{owner}/{repo}/pulls/{}/reviews" --jq '.[].user.login' | sort | uniq -c
```

| Reviewer login | Bot | Trigger comment |
|---|---|---|
| `chatgpt-codex-connector[bot]` | Codex | `@codex review` |
| `qodo-merge[bot]`, `pr-agent[bot]` or similar | Qodo / PR-Agent | `/review` |
| none of these | no bot | skip steps 2 to 4 and say so in the report |

**2. Trigger it** on the PR, with the comment from the table: `gh pr comment <pr> --body '@codex review'`.

**3. Wait for a review of the head commit.** A review of an older commit does not count. Poll
`gh api repos/{owner}/{repo}/pulls/<pr>/reviews` (and the PR's comments, for bots that comment
rather than review) until one arrives whose `commit_id` is the PR's head. Allow about 15 minutes;
if none comes, say so in the report and carry on without it.

**4. Triage every finding** before changing any code. Each one is either:

- **fix**: a real defect. Change the code, push, and go back to step 2 for the new head.
- **rebut**: a nit, out of scope, by design, or not worth its cost. Reply in the thread with the
  reason, and change nothing.

A rebutted finding counts as addressed. Reply to every inline thread
(`gh api repos/{owner}/{repo}/pulls/<pr>/comments/<id>/replies -f body=...`) and resolve it.
The bot does not answer a rebuttal on its own.

**Done when** one review of the current head raises nothing new that you would fix. Report how many
findings you fixed and how many you rebutted. Never change code only to quiet the bot.
