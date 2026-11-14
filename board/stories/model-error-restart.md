---
kind: code
status: ready
depends_on: []
touches: [bin/lib/agents.sh:pane_stop model-error kind, bin/lib/agents.sh:wait api error branch, tests/api_model_error_test.sh (new), docs/reference-building.md:API errors paragraph (§ Building)]
estimate_lines: 140
easy: false
---

# A model error stops the retries at once and names the fresh-session restart

On 2026-11-14 the builder of codex-unavailable-fallback (#899) stopped on `API Error (anthropic.claude-fable-5-2): 400 Invocation of model ID ... with on-demand throughput isn't supported`. Bedrock was refusing that model ID. `wait` treats every `API Error:` stop the same way (bin/lib/agents.sh:1289, :1839-1930): it tells the agent to carry on up to three times, then prints `stuck: api error`. A resume in the same session sends the same model ID again, so those retries cannot help. The lead then restarted the builder by hand in a fresh pane, which picked up the fixed settings.

Tell a model error from a passing one. In pane_stop, an `API Error` line whose status is 400 or 404 and whose text names the model (`model ID`, `model identifier`, `inference profile`, `model_not_found`) is a new kind, `model-error`, beside `api-error`. On it, `wait` sends no resume. It prints `stuck: model error (<the line, cut to 200 characters>)` at once and returns the same exit code as `stuck: api error`, so every caller still handles it. 5xx, 429 and other `API Error` lines keep today's three resumes.

Log it as an `incident` with `model-error`, so flow's incidents section counts it.

The lead's handling of `stuck: model error` is the restart rule it already has for an API-error stop, which starts the agent in a fresh session. Add one sentence to docs/reference-building.md's API-errors paragraph saying a model error skips the resumes, and why: the same session would send the same model ID.

**Done when:**
- tests/api_model_error_test.sh: a pane fixture ending on the #899 line (400, "Invocation of model ID ... inference profile") makes wait print `stuck: model error` with no tell sent (the tell stub records none)
- A fixture ending on `API Error (...): 400 The provided model identifier is invalid` does the same
- A fixture ending on `API Error: 529 Overloaded` and one ending on a 503 still get the resumes and end on `stuck: api error`, as today
- An `incident` line with `model-error` is in events.tsv for the first two cases
- The first case goes red with the model-error kind removed, shown on a worktree copy and quoted in the PR (AGENTS.md mutation rule)
- scripts/select-tests.sh --run passes
