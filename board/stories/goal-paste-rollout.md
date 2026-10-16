---
kind: lead
status: blocked
blocked_by: [goal-condition-fits-paste]
epic: goal-paste
depends_on: [goal-condition-fits-paste]
touches: []
---

# Install the fix and rebuild infrafactory's three held stories under goal

After goal-condition-fits-paste merges and its release is published, the lead runs `claude plugin update swarm-dev@swarm-dev` and runs `swarm.sh reset <slug> "goal-paste fixed"` in infrafactory for rehearsal-passthrough-args, -exit-code and -runner-stream. It then tells the rehearsal-passthrough conductor that they are ready again.

**Done when:**
- `swarm.sh version` prints the new patch version.
- Each of the three builders' session logs shows a `goal_status` entry with `sentinel:true` and no `cleared-on-error` close. Otherwise the lead files a story naming what happened.
