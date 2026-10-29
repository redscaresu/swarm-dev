---
kind: code
status: ready
epic: merge-safety
depends_on: []
touches: [bin/lib/dropped_lines.py (new), tests/dropped_lines_test.sh (new)]
estimate_lines: 280
easy: false
---

# dropped_lines.py: the base lines a PR's own merge commits dropped, read with git show --remerge-diff

The detection half of #693, local git only (no gh, no network); nothing calls it until dropped-lines-command. New bin/lib/dropped_lines.py: `python3 dropped_lines.py <repo-dir> <base> <head> [<merge sha>...]`. It walks `git rev-list --first-parent --merges <base>..<head>`, and when merge SHAs are given it scans only those (the command passes the ones that are not web-flow verified). For each merge M: exactly two parents, else exit 2 naming M (an octopus is not remerged this way). The base side is found by ancestry, not position: the parent that is an ancestor of <base>, the other is the PR side; if neither or both are, exit 2 naming M. Run `git show --remerge-diff --format= M` and parse it per file (a `diff --git` header, then hunks; a `-` line inside a hunk is a removed line, so a removed line that starts with `--` is never read as a header). Print a removed line L of file F when L is in the base-side parent's F and either in the PR-side parent's F or absent from the merge base's F (`git merge-base` of the two parents): a base line the resolution dropped that the PR's own commits had not removed (HLD:425-431). Not printed: a line the PR's commits removed before the merge (in the merge base, not on the PR side); a PR-side line the resolution dropped (not on the base side); the conflict markers git writes (`<<<<<<< `, `=======`, `||||||| `, `>>>>>>> ` lines); whitespace-only lines; a removal by a non-merge commit, before or after (never scanned). The epic's own wording ('in the base-side parent, not in the PR-side parent') is corrected here: see contradictions. Output: one line per dropped line, `<merge sha7> <file>: <text>`, with control characters stripped and the text cut to a named constant, as ci_data does (merge.sh:1481), since the text reaches events.tsv, state files and panes. Exit 0 with nothing printed, 1 with lines, 2 with one line saying why it could not check. Review (2026-10-29): inside a conflict section, a removed line's side is taken from the section it sits in (between <<<<<<< and ======= is ours, between ======= and >>>>>>> is the base's), never by matching its text elsewhere in the base file, so a PR-side `fi` or `}` is not reported as a base line (rules.md: no loose match). A merge of a non-base branch (a stacked build merging its parent, whose parent then squash-merged) has neither parent on origin/<base>: it is reported as unchecked, not as a drop, and says so.

**Done when:**
- tests/dropped_lines_test.sh (new) builds real repos with real conflicting merges (no gh, no network). Two builder merges where the older one drops a line the base added: that line prints with its merge's short SHA and file, exit 1.
- A clean merge of the base, and a conflict resolved by keeping both sides: nothing printed, exit 0.
- The PR-side drop (the resolution keeps the base side and drops the PR's line): nothing printed.
- The PR's own removal before the merge, inside the conflict hunk (the merge base has L, the PR removed it, the base edited the next line): nothing printed. A removal by a PR commit after the merge: nothing printed.
- Conflict markers and a whitespace-only line the resolution dropped: nothing printed for them. A line both parents had that the resolution deleted: printed.
- A merge whose parents are in swapped order (made from the base side): the same dropped line is found.
- A merge not in the given SHA list is not scanned. An octopus merge exits 2 with its SHA.
- Copy-aside proofs: dropping the merge-base condition turns the PR's-own-removal case red; reading the base side by parent position turns the swapped case red.
- python3 -m py_compile bin/lib/*.py and scripts/select-tests.sh --run pass.
- A PR-side line removed inside a conflict section whose text also appears elsewhere in the base file is not reported.
- A merge of a stacked parent branch is reported as unchecked with its reason, not as dropped lines.
