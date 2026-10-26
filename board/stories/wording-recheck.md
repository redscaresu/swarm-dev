---
kind: code
status: blocked
epic: review-loop
depends_on: [next-review-round]
needs: [next-review-round: --next's head checks and .head writer in bin/lib/build.sh:review_agent]
touches: [bin/lib/build.sh:review_agent, bin/swarm.sh:review-agent dispatch arm, bin/swarm.sh:main event target, bin/swarm.sh:usage header, docs/reference.md:Commands review-agent row, tests/review_agent_test.sh:recheck cases]
estimate_lines: 190
easy: false
---

# review-agent --recheck: a wording-only fix passes on its diff alone

Uses next-review-round's --next checks and .head writer in bin/lib/build.sh:review_agent. New mode `swarm.sh review-agent --recheck <slug> <PR URL> <old head> <file:line>...`, from review-<slug>'s pane, is the wording recheck path. It passes only when the PR's new head is green (ci_gate head) and `git diff <old head>..<new head>` changes only hunks covering the named file:line points, with no other file and no other line. On a pass it writes .head and a findings file for the new head (head: line, a ## Findings section saying the wording recheck passed). It logs `review-agent:recheck <slug> ok`, which counts no round. Otherwise it exits non-zero, saying why and that a full round (--next) is due, and writes nothing. Document it in the usage and docs/reference.md.

**Done when:**
- tests/review_agent_test.sh: a green new head whose diff changes only the named lines passes, writes the findings file and .head for the new head, and the next --next prints the same round as before.
- A diff that also changes an unnamed line, or another file, is refused and names --next.
- A head that is not green is refused; each refusal leaves .swarm/reviews unchanged.
- Breaking the hunk check (accepting any diff) turns the unnamed-line case red (falsified once, noted in the PR).
