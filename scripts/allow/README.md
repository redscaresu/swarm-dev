# Allow lists

`tests/diff_run.sh` runs the same fixtures against two trees and compares what each run did.
An allow list names the differences that are meant to be there.
Every other difference is red.

Each stage of a release has its own list, in `scripts/allow/stage-<n>/`.
A list holds one file per story, `<slug>.md`, so two PRs never edit the same file.
`tests/diff_run.sh --stage <n>` reads `stage-1/` through `stage-<n>/`.
The user agrees each stage's list when the stage exits.

## An entry

An entry file starts with front matter, followed by one hunk per difference.

````markdown
---
story: example-story
pr: 1234
kind: stage
---

# next names the stage

Free text says what changed and why.

## next stdout

```diff
 ready: example-story
+stage: v0.32.0
```

## next calls:fg

```diff
 gh pr list --state open
-gh api repos/o/r/tags
+gh api repos/o/r/git/matching-refs/tags
```
````

- `story` is the story's slug, which is also the file's name.
- `pr` is the story's PR number.
- `kind` is `fix` for a `fix: true` story, or `stage` for a change the stage makes on purpose.

Each `## <fixture> <stream>` heading has one or more fenced hunks under it.
A fixture is a `fx_<name>` function in a `tests/diff_fixtures_*.sh` file, named without its `fx_`.
Every `##` heading in an entry is a hunk heading.

The streams are:

- `stdout`, `stderr` and `exit`: the command's.
- `files`: the list of files the run wrote and deleted, one `written <path>` or `deleted <path>` line each.
- `file:<path>`: one written file's content, with its path as `files` lists it.
- `calls:<step>`: the gh and herdr calls of one step, such as `calls:fg` for the foreground.
- A background step's `<step>` is its label, `[<argv>] <first call>`, as a `DIFF` line and `--draft` print it.

Paths and other run-specific values appear after the run's replacements and masks.
So a path reads `<root>/proj/...`, and a time stamp reads `<time>`.
The header of `tests/diff_run.sh` lists them all.

## A hunk

A hunk's lines work like a unified diff's, with no `@@` line:

- A line starting with `-` is removed.
- A line starting with `+` is added.
- A line starting with a space is context: it is in the stream before and after.
- `^` as the first line puts the hunk at the stream's start.
- `\ No newline at end of file` after a line means that line has no newline.
- An empty line counts as an empty context line, since editors strip a lone trailing space.

The `-` and context lines together must appear in the stream exactly once.
That block is replaced by the context and `+` lines.
An insertion has no `-` lines, so it names the line it follows as context, or starts with `^`.
Add a context line before the change when its lines appear more than once.

These are refused, and stop the run before any fixture runs:

- a hunk with no lines, or with no `-` or `+` line;
- a heading with no hunk under it, or one that names a fixture and no stream;
- an entry with no hunks;
- a file under `scripts/allow/` other than this README and `stage-<n>/<slug>.md` entries;
- two entries for one story or one PR.

So an entry cannot allow a whole command or file wholesale. It has to give the lines.

## How entries apply

The entries apply to the old tree's output, the first tree named, in the order their PRs merged.
That order comes from git: the commit on HEAD's first-parent history that added each entry file.
On `main` that is the order the PRs merged.
Entries that tie, because one commit added them all, go by stage and then by PR number.
An entry no commit has added yet, such as a branch's own, comes after the rest.
In a tree with no git, every entry goes by stage and then by PR number.
Each hunk applies to what the hunks before it left.
The result is then compared with the new tree's output.

- A difference no hunk covers is red (`DIFF <fixture> <stream>`).
- A hunk that does not apply on a fixture the run ran is red (`ALLOW-FAIL <fixture> <stream>`).
- A hunk for a fixture outside the run is skipped.

The run ends with one line per entry saying how many of its hunks applied.

With `--times <n>`, the entries apply to the two trees' first runs.
The run compares each repeat with its own tree's first run, with no entry applied, so a tree that differs from itself is always red.

The `files` list decides which files exist, as each hunk applies.
A `files` hunk that adds a `written <path>` line makes that file, empty until a `file:<path>` hunk gives it lines.
One that removes a `written <path>` line drops the file and its content.
So a new file's `files` hunk goes before its `file:<path>` hunk, as `--draft` prints them.
A `file:<path>` hunk for a path the list does not write at that point is red.
A symbolic link cannot be changed by a hunk.

## Writing an entry

1. Run the old tree against your branch with `--draft`:

   ```bash
   bash tests/diff_run.sh --stage <n> --draft <old-tree> <your-tree>
   ```

   It prints each difference no entry covers as `##` headings and hunks.
2. Put the ones your story makes on purpose in `scripts/allow/stage-<n>/<slug>.md`, under the front matter.
3. Run it again without `--draft`. It should exit 0.
4. Check the entry alone against your story's own merge commit and its parent:

   ```bash
   bash tests/diff_run.sh --only <slug> <parent-tree> <merge-tree>
   ```

`tests/diff_allow_test.sh` parses every entry file on disk, so a malformed one fails CI.

## On each PR

The `diff-run` CI job runs the PR's base against its head:

```bash
bash tests/diff_run.sh --base --branch story/<slug> <base-tree> <head-tree>
```

`--base` applies only the entries of the stories `--branch` names, from any stage.
A PR on branch `story/<slug>` names its own story, so only its own entry applies.
Every other entry, on the base or added by the PR, is left to `--stage`, and is never applied, so it is never red either.
A branch that is not `story/<slug>` names no story, and then every difference is red.
A merge queue's group holds several PRs, so the job passes one `--branch` per PR in the group, as `scripts/diff-run-branches.sh` reads them.
