package merge

import (
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"testing"

	"github.com/redscaresu/swarm-dev/internal/adapter/git"
	"github.com/redscaresu/swarm-dev/internal/iface"
)

// The dropped-lines check on real repos, each built as tests/dropped_lines_test.sh builds the same
// shape, with the lines and exit code that file expects of the Python.

// droppedBase0 is the shell test's BASE0: f's lines on main before a case changes them.
var droppedBase0 = []string{"one", "two", "three", "four", "five", "six", "seven", "eight", "-- nine", "ten", "=======", "}", "eleven"}

// droppedStory is the PR's own story file in the --own cases.
const droppedStory = "board/stories/s.md"

// droppedF is f with BASE0's line three replaced by three (the shell test's lines).
func droppedF(three ...string) string {
	return strings.Join(slices.Concat([]string{"one", "two"}, three, droppedBase0[3:]), "\n") + "\n"
}

// droppedStart is the shell test's new_repo: f holds BASE0 on main, branch pr starts there, and main
// is checked out.
func droppedStart(t *testing.T) *droppedRepo {
	t.Helper()
	r := droppedNewRepo(t)
	r.commit("f", "f", strings.Join(droppedBase0, "\n")+"\n")
	r.git("branch", "pr")
	return r
}

// on checks out branch.
func (r *droppedRepo) on(branch string) {
	r.t.Helper()
	r.git("checkout", "-q", branch)
}

// conflict is the shell test's conflict: main replaces three with three-main and main-added, pr with
// three-pr; it leaves pr checked out.
func (r *droppedRepo) conflict() {
	r.t.Helper()
	r.commit("main's three", "f", droppedF("three-main", "main-added"))
	r.on("pr")
	r.commit("pr's three", "f", droppedF("three-pr"))
}

// start begins a merge of branch into the branch checked out, with no commit; a conflict leaves
// the merge for the case to resolve.
func (r *droppedRepo) start(branch string) {
	r.t.Helper()
	got, err := git.Repo{}.Run(iface.GitCall{Dir: r.dir, Bound: droppedSetupBound,
		Args: []string{"merge", "-q", "--no-ff", "--no-commit", branch}})
	if err != nil || got.TimedOut {
		r.t.Fatalf("git merge %s: %v %+v", branch, err, got)
	}
}

// finish commits the merge with every change in the work tree, and gives it.
func (r *droppedRepo) finish() string {
	r.t.Helper()
	r.git("add", "-A")
	r.git("commit", "-q", "--no-edit")
	return r.git("rev-parse", "HEAD")
}

// resolve merges branch into the branch checked out with each file (name, then content) resolved
// to its content, git's own merge for the rest, and gives the merge.
func (r *droppedRepo) resolve(branch string, files ...string) string {
	r.t.Helper()
	r.start(branch)
	for i := 0; i+1 < len(files); i += 2 {
		if err := os.WriteFile(filepath.Join(r.dir, files[i]), []byte(files[i+1]), 0o644); err != nil {
			r.t.Fatal(err)
		}
	}
	return r.finish()
}

// squash squash-merges branch into main, as main merges a PR.
func (r *droppedRepo) squash(branch string) string {
	r.t.Helper()
	r.on("main")
	r.git("merge", "-q", "--squash", branch)
	r.git("commit", "-q", "-m", "the parent (#1)")
	return r.git("rev-parse", "HEAD")
}

// octopus merges b1 and b2 into pr, each of the three adding a file of its own first, so the merge
// has three parents; it gives the merge.
func (r *droppedRepo) octopus() string {
	r.t.Helper()
	r.git("branch", "b1", "main")
	r.git("branch", "b2", "main")
	r.on("b1")
	r.commit("g", "g", "g1\n")
	r.on("b2")
	r.commit("h", "h", "h1\n")
	r.on("pr")
	r.commit("p", "p", "p1\n")
	r.git("merge", "-q", "--no-edit", "b1", "b2")
	return r.git("rev-parse", "HEAD")
}

// droppedOutput is what the check printed, then `exit <code>` on a line of its own, as the shell
// test's scan shows it; a run that errs ends the test.
func droppedOutput(t *testing.T, repo iface.Repo, args ...string) string {
	t.Helper()
	got, err := Dropped(repo, args)
	if err != nil {
		t.Fatalf("Dropped(%q): %v", args, err)
	}
	return strings.Join(append(slices.Clone(got.Lines), "exit "+strconv.Itoa(got.Code)), "\n")
}

// expect runs the check over r with args after r's folder as a subtest named name, and fails it
// unless it prints want, each line, then exit code.
func (r *droppedRepo) expect(name string, want []string, code int, args ...string) {
	r.t.Helper()
	r.t.Run(name, func(t *testing.T) {
		t.Helper()
		wanted := strings.Join(append(slices.Clone(want), "exit "+strconv.Itoa(code)), "\n")
		if got := droppedOutput(t, git.Repo{}, append([]string{r.dir}, args...)...); got != wanted {
			t.Errorf("got:\n%s\nwant:\n%s", got, wanted)
		}
	})
}

// droppedSeven is a commit's first seven characters, as a line names it.
func droppedSeven(sha string) string { return sha[:droppedShortChars] }

// droppedStackedStop is sides' stop for a merge with neither parent on main.
func droppedStackedStop(m string) string {
	return "merge " + droppedSeven(m) + " is unchecked: neither parent is on main, so it is not a merge of main" +
		" (a stacked build's merge of its parent branch?)"
}

// If the merges were not listed, or a merge SHA given were not kept, or one given in capitals were
// not lowered, one of these would print another line or none.
func TestDroppedCheckTwoMerges(t *testing.T) {
	r := droppedStart(t)
	r.conflict()
	m1 := r.resolve("main", "f", droppedF("three-pr", "three-main"))
	r.on("main")
	r.commit("g", "g", "g1\n")
	r.on("pr")
	m2 := r.resolve("main")
	line := droppedSeven(m1) + " f: main-added"
	r.expect("the older of two merges dropped a base line", []string{line}, 1, "main", "pr")
	r.expect("with SHAs given, a merge not among them is not scanned", nil, 0, "main", "pr", m2)
	r.expect("a merge among the SHAs given, in capitals, is scanned", []string{line}, 1,
		"main", "pr", strings.ToUpper(m1), m2)
}

// If a side's file were read only under the merge's name for it, main's f would not be found as g.
func TestDroppedCheckRenamed(t *testing.T) {
	r := droppedStart(t)
	r.commit("main's three", "f", droppedF("three-main", "main-added"))
	r.on("pr")
	r.git("mv", "f", "g")
	r.commit("pr's three", "g", droppedF("three-pr"))
	m := r.resolve("main", "g", droppedF("three-pr"))
	r.expect("a file the PR renamed: the dropped base lines print under its new name",
		[]string{droppedSeven(m) + " g: three-main", droppedSeven(m) + " g: main-added"}, 1, "main", "pr")
}

// If a merge sides cannot check did not stop the check, the octopus would pass as clean.
func TestDroppedCheckOctopus(t *testing.T) {
	r := droppedStart(t)
	m := r.octopus()
	r.expect("an octopus merge stops naming it",
		[]string{"merge " + droppedSeven(m) + " has 3 parents: an octopus merge is not remerged, so it is not checked"}, 2, "main", "pr")
}

// If a merge were scanned as soon as its sides are read, the older merge's remerge diff would be
// read before the octopus stops the check.
func TestDroppedCheckStopBeforeAnyScan(t *testing.T) {
	r := droppedStart(t)
	r.conflict()
	r.resolve("main", "f", droppedF("three-pr", "three-main"))
	m := r.octopus()
	rec := &droppedRecorder{}
	want := "merge " + droppedSeven(m) + " has 3 parents: an octopus merge is not remerged, so it is not checked\nexit 2"
	if got := droppedOutput(t, rec, r.dir, "main", "pr"); got != want {
		t.Errorf("a drop before an octopus: got:\n%s\nwant:\n%s", got, want)
	}
	for _, call := range rec.calls {
		if slices.Contains(call.Args, "--remerge-diff") {
			t.Errorf("a drop before an octopus: the check read a remerge diff before every merge's sides: git %q", call.Args)
		}
	}
}

// If --merged were not read, or not lowered, the merge of the merged parent's branch would stop as
// unchecked; if it were taken for any merge, the merge with no --merged would pass.
func TestDroppedCheckMergedParent(t *testing.T) {
	r := droppedStart(t)
	r.on("pr")
	r.commit("pr's three", "f", droppedF("three-pr"))
	r.git("checkout", "-q", "-b", "child", "pr")
	r.commit("c", "c", "c1\n")
	r.on("pr")
	r.commit("pr's ten", "f", strings.Replace(droppedF("three-pr"), "\nten\n", "\nten-pr\n", 1))
	r.on("child")
	m := r.resolve("pr")
	sq := r.squash("pr")
	r.on("child")
	r.resolve("main")
	pair := strings.ToUpper(r.git("rev-parse", "pr") + ":" + sq)
	r.expect("a merge of a merged parent's branch, its second parent --merged in capitals: nothing", nil, 0,
		"main", "child", "--merged", pair)
	r.expect("the same merge with no --merged: unchecked", []string{droppedStackedStop(m)}, 2, "main", "child")
}

// If the first parent's part of a conflict were not read for a merge of a merged parent's branch,
// or a copy the build's own commits added were taken as the base's, this merge would pass or print.
func TestDroppedCheckMergedParentOwnCopy(t *testing.T) {
	r := droppedStart(t)
	r.on("pr")
	r.commit("pr's three", "f", droppedF("three-pr"))
	r.git("checkout", "-q", "-b", "child", "pr")
	r.commit("c", "c", "c1\n")
	r.on("main")
	r.commit("main's line", "f", strings.Join(droppedBase0, "\n")+"\nmain-added\n")
	r.on("child")
	r.resolve("main")
	tail := strings.Join(droppedBase0[10:], "\n") + "\nmain-added\n"
	upToNine := strings.Join(slices.Concat([]string{"one", "two", "three-pr"}, droppedBase0[3:9]), "\n") + "\n"
	r.commit("child's brace", "f", upToNine+"}\n"+tail)
	r.on("pr")
	r.commit("pr's ten", "f", strings.Replace(droppedF("three-pr"), "\nten\n", "\nten-pr\n", 1))
	r.on("child")
	m := r.resolve("pr", "f", upToNine+"ten-pr\n"+tail)
	sq := r.squash("pr")
	r.on("child")
	r.resolve("main")
	r.expect("a merge of a merged parent's branch dropping a } child added from child's part of a conflict: unchecked",
		[]string{"merge " + droppedSeven(m) + " is unchecked: f: }, dropped from its first parent's part of a conflict, has" +
			" copies the build's own commits added, so a count cannot tell whose copy it dropped"}, 2,
		"main", "child", "--merged", r.git("rev-parse", "pr")+":"+sq)
}

// If the head's own copies were not read, the line put back would still print.
func TestDroppedCheckPutBack(t *testing.T) {
	r := droppedStart(t)
	r.conflict()
	r.resolve("main", "f", droppedF("three-pr", "three-main"))
	r.commit("put it back", "f", droppedF("three-pr", "three-main", "main-added"))
	r.expect("a line the merge dropped and a later PR commit put back: nothing", nil, 0, "main", "pr")
}

// If a head line that extends a dropped one did not clear it, the row would print.
func TestDroppedCheckExtendedRow(t *testing.T) {
	const row = "flow prints cost then features"
	r := droppedStart(t)
	r.commit("main's row", "f", droppedF("three-main", row))
	r.on("pr")
	r.commit("pr's three", "f", droppedF("three-pr"))
	r.resolve("main", "f", droppedF("three-pr", "three-main", "flow prints cost then panes then features"))
	r.expect("a base line the resolution kept with words inserted: nothing", nil, 0, "main", "pr")
}

// If gone did not read the base, a line main's squash took off would print for the parent's merge
// still in a stacked child's history.
func TestDroppedCheckGoneFromBase(t *testing.T) {
	r := droppedStart(t)
	r.conflict()
	r.resolve("main", "f", droppedF("three-pr", "three-main"))
	r.git("checkout", "-q", "-b", "child", "pr")
	r.commit("c", "c", "c1\n")
	r.squash("pr")
	r.on("child")
	r.expect("a parent's merge dropped a line main's squash took off: nothing", nil, 0, "main", "child")
}

// If --own skipped its file whatever the head holds, the kept story file's line would not print;
// if it skipped nothing, the deleted one's would.
func TestDroppedCheckOwn(t *testing.T) {
	t.Run("kept", func(t *testing.T) {
		r := droppedStart(t)
		r.commit("story", droppedStory, "status: ready\nx\n")
		r.git("branch", "-f", "pr", "main")
		r.commit("fix", droppedStory, "status: ready\nfix: true\nx\n")
		r.on("pr")
		r.commit("review", droppedStory, "status: review\nx\n")
		m := r.resolve("main", droppedStory, "status: review\nx\n")
		r.expect("own story file kept by the head, a base line of it dropped: it prints with --own",
			[]string{droppedSeven(m) + " " + droppedStory + ": fix: true"}, 1, "main", "pr", "--own", droppedStory)
	})
	t.Run("deleted", func(t *testing.T) {
		r := droppedStart(t)
		r.commit("story", droppedStory, "status: ready\nx\n")
		r.git("branch", "-f", "pr", "main")
		r.commit("fix", droppedStory, "status: ready\nfix: true\nx\n")
		r.on("pr")
		r.git("rm", "-q", droppedStory)
		r.git("commit", "-q", "-m", "the story is done")
		r.start("main")
		if err := os.Remove(filepath.Join(r.dir, droppedStory)); err != nil {
			t.Fatal(err)
		}
		m := r.finish()
		r.expect("own story file deleted by the head: no line of it prints with --own", nil, 0,
			"main", "pr", "--own", droppedStory)
		r.expect("the same with no --own: the line prints",
			[]string{droppedSeven(m) + " " + droppedStory + ": fix: true"}, 1, "main", "pr")
	})
}

// If the blank check took off more than ASCII whitespace, the no-break space line would not print;
// if it took off nothing, the spaces would.
func TestDroppedCheckBlank(t *testing.T) {
	r := droppedStart(t)
	r.commit("main's three", "f", droppedF("three-main", "   ", "\u00a0"))
	r.on("pr")
	r.commit("pr's three", "f", droppedF("three-pr"))
	m := r.resolve("main", "f", droppedF("three-pr", "three-main"))
	r.expect("a dropped line of spaces does not print; one of a no-break space does",
		[]string{droppedSeven(m) + " f: \u00a0"}, 1, "main", "pr")
}

// If git's failure to list the merges did not stop the check, it would pass with nothing scanned.
func TestDroppedCheckUnreadableRange(t *testing.T) {
	r := droppedStart(t)
	r.expect("a range git cannot read stops with git's line",
		[]string{"cannot list the merges in main..nope: fatal: bad revision 'main..nope'"}, 2, "main", "nope")
	r.expect("an argument that is not UTF-8 prints each such byte as ?, and git's line as droppedClean reads it",
		[]string{"cannot list the merges in ma?in..no?pe: fatal: bad revision 'ma\ufffdin?..no\ufffdpe'"}, 2,
		"ma\xffin\x01", "no\xffpe")
}

// If the arguments were read in any other way, these would not stop with the usage line before any
// git call. The line is spelled out, not taken from droppedUsage, so a change to its text goes red.
func TestDroppedCheckUsage(t *testing.T) {
	const usage = "usage: swarm.sh _dropped-lines <repo-dir> <base> <head> [--own <path>] [--merged <sha>:<squash>]... [<merge sha>...]"
	for _, c := range []struct {
		name string
		args []string
	}{
		{"no arguments", nil},
		{"two arguments", []string{"repo", "main"}},
		{"a --merged with nothing after it", []string{"repo", "main", "pr", "--merged"}},
		{"a --merged with no colon", []string{"repo", "main", "pr", "--merged", "abc"}},
		{"a --merged with no squash", []string{"repo", "main", "pr", "--merged", "abc:"}},
		{"a --merged of three parts", []string{"repo", "main", "pr", "--merged", "abc:def:0"}},
		{"an --own with nothing after it", []string{"repo", "main", "pr", "--own"}},
		{"an --own with an empty path", []string{"repo", "main", "pr", "--own", ""}},
	} {
		t.Run(c.name, func(t *testing.T) {
			rec := &droppedRecorder{}
			if got, want := droppedOutput(t, rec, c.args...), usage+"\nexit 2"; got != want {
				t.Errorf("args %q: got:\n%s\nwant:\n%s", c.args, got, want)
			}
			if len(rec.calls) > 0 {
				t.Errorf("args %q: git ran %q before the usage stop", c.args, rec.calls[0].Args)
			}
		})
	}
}

// If an argument the Python cannot encode were read on, the check would give lines or a stop where
// the Python raises.
func TestDroppedCheckNotUTF8(t *testing.T) {
	r := droppedStart(t)
	r.conflict()
	r.resolve("main", "f", droppedF("three-pr", "three-main"))
	t.Run("an --own path", func(t *testing.T) {
		if got, err := Dropped(git.Repo{}, []string{r.dir, "main", "pr", "--own", "s\xff"}); err == nil {
			t.Errorf("an --own path that is not UTF-8: got %+v, want an error", got)
		}
	})
	// macOS refuses a loose ref with such a name, so it goes in packed-refs.
	ref := r.git("rev-parse", "main") + " refs/heads/ma\xffin\n"
	if err := os.WriteFile(filepath.Join(r.dir, ".git", "packed-refs"), []byte(ref), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Run("a base a file is read at", func(t *testing.T) {
		if got, err := Dropped(git.Repo{}, []string{r.dir, "ma\xffin", "pr"}); err == nil {
			t.Errorf("a base that is not UTF-8, which a file is read at: got %+v, want an error", got)
		}
	})
}
