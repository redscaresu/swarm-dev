---
status: active
hld: 2026-10-28-swarm-dev-0-30-and-0-31
stage: v0.30.0
depends_on: [delivery-liveness, lead-woken, reference-split]
---

# telemetry-readers

HLD Goal 6, first half (v0.30.0): one outcome helper per language, every reader of events.tsv on it, proven equivalent over a committed fixture with and without a key=value tail on every row; and the writer contract (append_event's optional fields, the separator, the escape) with no caller passing fields yet. Split from v1's telemetry-fields at its skeptic's and the lead's word.

**Done when:**
- stage: v0.30.0
- Contract: append_event (agents.sh:857-861) takes optional key=value fields after the outcome and writes them after a separator the story picks; it strips that separator from the free-text outcome first, so the tail parses whatever the text held; keys match [a-z_]+, values hold no space or tab. Tested against a committed fixture tests/fixtures/events/v029-sample.tsv (a redacted sample of the v0.29.0 log that keeps its 37 outcomes containing `=`, the herdr JSON ones included) and against a die message that ends in the separator. The live .swarm/events.tsv is gitignored (.gitignore:2) and is read by no test (contradiction 29).
- Python helper bin/lib/events_outcome.py (outcome(row) -> text, fields(row) -> dict) imported by every bin/lib reader of events.tsv: ci_gate.py, dash_age.py, dash_finished.py, dash_render.py, dash_slow.py, dataset.py, flow_features.py, flow_gh_calls.py, flow_holds.py, flow_idle_slots.py, flow_incidents.py, flow_lead_queue.py, flow_merge_ins.py, flow_merges.py, flow_report.py, flow_review_loops.py, flow_run_times.py, flow_test_runs.py, flow_throughput.py, flow_time_in_state.py, herdr_events.py, outcomes_join.py (its events reads at 149, 211, 218-222; its cost keys untouched), outcomes_rows.py, panes.py, stall_py.py, stall.py, touches_rows.py.
- One awk function or prefilter every $5 site in the shell uses: agents.sh (4 sites: login_incident 1638-1640, findings_told 2461 among them), build.sh (6: review_rounds 667-671 among them), lifecycle.sh (13: 1203, 1265, 1470, 2745, 3090-3162 with no_review_events and :3103's exact `ok (reopened)`), merge.sh (2: base_merged 716 among them), reports.sh (1); tests/events_test.sh:237's exact `$5 == o` compares the stripped outcome and keeps its NF == 5, ISO-Z and prefix pins.
- Equivalence test tests/events_tail_test.sh (new): over the fixture, then over the same fixture with a tail `k=v` appended to every row, it runs every flow section flow_report.py lists, outcomes, dash --check's figures, wait --lead's lead_queue (in a fixture project), review_round, findings_told, login_incident, base_merged and no_review_events, and diffs the two outputs: identical. A reader left on an exact $5 or e[4] comparison fails it (proven by breaking one in a worktree copy, as AGENTS.md's mutation rule says).
- A scanner in tests/ (the loose_match_test.sh pattern) fails when any bin/lib file outside the helper compares $5 or e[4] exactly with a literal or slices it, so a sibling epic's new reader goes red until it uses the helper (skeptic: new exact matches turn false once version= is on every row).
- dash --project over a project whose files predate the fields renders the same (tests/dash_projects_test.sh, the file's real name: contradiction in v1's areas).

**Out of scope:**
Any writer passing fields (telemetry-writers); new flow sections; the hooks' writers (telemetry-writers' lead-merged story); the retro reader (retro-report).

**Constraints:**
- stage: v0.30.0. depends_on delivery-liveness and lead-woken for touches: login_incident's skip list and no_review_line's event reads land first, then the sweep covers them. Not for a patch (contradiction 21).
- Parallel with merge-safety: no shared part (merge_pr's dropped-lines step and epic_unticketed read no $5).
- rung-cost-block (ladder-cost, ready) touches outcomes_join.py:step-up outcome join: this epic's part is `outcomes_join.py:events reads`; the story depends_on rung-cost-block while it is on the board.
- review-rounds-end and telemetry-writers depend on this epic; its helper story is top-level code, so scripts/select-tests.sh runs the full suite for that PR.
- The fixture is redacted by the lead or a builder from the main checkout's log by a script in the PR that keeps column shape and outcome text classes only: no pane ids, no URLs, no slugs beyond a-z stand-ins; a builder never reads session logs (#696).
- bash 3.2; no new sixth column; readers that match `ok (round N)`, `base-merged`, `incident <kind>:` keep their prefixes (the helper strips only the tail).

**Areas:** bin/lib/agents.sh:append_event (fields, separator, escape), bin/lib/events_outcome.py (new helper), bin/lib/*.py events readers (the 27 files listed), bin/lib/outcomes_join.py:events reads, bin/lib/agents.sh:awk outcome sites (login_incident, findings_told), bin/lib/build.sh:review_rounds (awk), bin/lib/lifecycle.sh:awk outcome sites (no_review_events and the 12 others), bin/lib/merge.sh:base_merged, bin/lib/reports.sh:awk outcome site, tests/fixtures/events/v029-sample.tsv (new), tests/events_test.sh:helper cases, tests/events_tail_test.sh (new), tests/outcome_scan_test.sh (new scanner), tests/dash_projects_test.sh, docs/reference.md:Logs and outcomes (the field tail)

**Your part:**
- None. The hooks and the fields are telemetry-writers'.
