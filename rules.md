# swarm-dev's rules

Builders follow these rules before they write, and reviewers hold each PR to them.

- When many failures look alike, fix their shared upstream cause first.
  Why: patching each failure on its own leaves the cause in place to make the next one.
- A narrow sample is not a conclusion: widen a mutation test, or a claim about which round or run something happened in, before you rely on it.
  Why: the one case that passed says nothing about the cases nobody tried.
- A claim checked against a stand-in (a mock, a sibling API, a narrower sample) is unverified: check it against the thing itself.
  Why: the stand-in can agree while the real thing differs.
- An audit or test scoped to one file, when the defect class spans many, is a finding: scope it to every file, or close the class at the type.
  Why: a narrow audit reads as checked and hides the files it skipped, which is worse than no audit.
- A new code path must enforce every rule the existing paths enforce.
  Why: those rules are rarely written down where the new path can see them.
- A zero or empty value shown to a person must say what it means. Fix every value of that kind at once, not only the one you found.
  Why: a zero is fine in storage, but in a view it reads as "none happened" when the truth may be "not measured".
- A repair path that changes something must say what it did.
  Why: a fix that works silently looks like no fix, and someone fixes it again.
- Never inspect a credential with a denylist, such as a grep that redacts; print an allowlist of its fields instead.
  Why: a denylist leaks every field nobody thought to list.
- A fork's "no secret, so skip and pass" path never shares the fail-closed guard.
  Why: once they share code, a missing secret on the real repo passes as quietly as a fork's run does.
- Match on exact records, never on a heuristic such as a unique truncated prefix.
  Why: a prefix that is unique today matches the wrong record once the data grows.
- Prove each new or changed test can fail: break what it guards and watch it go red. A builder's brief says where to break it.
  Why: a test that still passes with its fix removed proves nothing.
- Describe test coverage by the contract it checks, not by its line count.
  Why: a count of test lines says nothing about which behaviour would go red.
- Add no CI work that brings an ongoing LLM cost unless something material changes.
  Why: that cost recurs on every run, whether or not the work still pays for itself.
- Never generate load (stress loops, parallel test repeats, load containers) on the machine the swarm runs on; a check that needs load runs on another machine. If load does run here, the cap in a builder's brief holds it: at most 4 CPUs in all, torn down as soon as the check ends.
  Why: all the swarm's agents share that machine, and load there slows or stalls every build.
- Never read `~/.claude/projects` or any session log, yours or another agent's, unless your brief orders that read; then read only the log it names.
  Why: a session log holds a whole conversation and anything printed in it, and the swarm's own tools already read what they need from it.
