---
kind: code
status: ready
epic: port-inventory
depends_on: []
touches: [docs/port/sites.tsv, tests/port_sites_test.sh]
estimate_lines: 170
---

# docs/port/sites.tsv lists every inline Python site that imports a helper, with its count and the one epic that rewrites it, and a test fails on one it lacks

Needs no other story.
- Write docs/port/sites.tsv (`#` header: file, function, imports, n, epic). A site is a python3 run whose code sits in any file under bin/ or hooks/ that is not a .py file (`-c '...'` or a `python3 - <<` heredoc) and imports a module that is a bin/lib/*.py file (`from X import` or `import X`), however sys.path is set. Scan the class, not a list of files: bin/gh-shim/gh is in scope. board.sh's site takes the path from an argument (bin/lib/board.sh:1700-1703, gh_cache).
- Name each site by file and enclosing function, never by line: merge.sh's site moved from :3274 to :3293 in v0.31.3. n is how many sites in that function import that module, so a second import of a listed module in a listed function shows.
- imports lists only the modules the site imports itself. dash.sh:747 imports dash_age, which imports panes, stall and report; the row names dash_age only.
- epic: helpers-shared for the four sites in board/epics/helpers-shared.md:13, helpers-dash for the three in dash.sh (helpers-dash.md:11), helpers-panes for the rest (helpers-panes.md:11). A site that imports modules of two epics goes to the later one in depends_on order: helpers-shared, helpers-panes, helpers-dash.
- Add tests/port_sites_test.sh. It finds every site by that rule and fails on a (file, function, module) with no row, or with more sites than its n, naming it. A row with fewer or no sites passes: helper ports remove sites, and readers-exit checks that none is left. Each failure line names docs/port/sites.tsv and the row to add. Source tests/test_helpers.sh first. List files with find (skip __pycache__, *.pyc), not git, so the test runs the same on a copy of the worktree without .git.
- tests/lib_path_test.sh checks the sites' -I guard with a six-module regex (:52). Leave it: that is a different rule.
- Prove it red on a copy without .git: a new -c site importing report in agents.sh, a second import of a listed module inside a listed function, a site that takes its path from an argument, a heredoc site, and a deleted row.
- The PR gives the count with its population (the survey found 25 sites over 134 python3 lines in bin/ and hooks/ at 7b480edf), per file and per epic.
- Humanizer over the header lines and the PR body.

**Done when:**
- sites.tsv has one row per (file, function, module) the rule finds at the base, each with its count, its direct imports and one epic. tests/port_sites_test.sh passes and goes red on each of the five seeded cases on a copy without .git.
- scripts/select-tests.sh --run passes
