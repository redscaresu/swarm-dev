package merge

import (
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/redscaresu/swarm-dev/internal/adapter/git"
	"github.com/redscaresu/swarm-dev/internal/iface"
)

// droppedSetupBound bounds one git call that builds a test's repository.
const droppedSetupBound = 30 * time.Second

// droppedRepo is a git repository a test builds in a temp folder of its own.
type droppedRepo struct {
	t   *testing.T
	dir string
}

// droppedNewRepo makes an empty repository on branch main. git runs with no user or system config,
// and with no variable that points it at another repository, for the test's own calls and the
// check's.
func droppedNewRepo(t *testing.T) *droppedRepo {
	t.Helper()
	for _, k := range []string{"GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT"} {
		t.Setenv(k, "") // puts the old value back when the test ends
		if err := os.Unsetenv(k); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("GIT_CONFIG_GLOBAL", os.DevNull)
	t.Setenv("GIT_CONFIG_NOSYSTEM", "1")
	for _, who := range []string{"AUTHOR", "COMMITTER"} {
		t.Setenv("GIT_"+who+"_NAME", "dropped test")
		t.Setenv("GIT_"+who+"_EMAIL", "dropped@test.invalid")
	}
	r := &droppedRepo{t: t, dir: t.TempDir()}
	r.git("init", "-q", "-b", "main")
	return r
}

// git runs git -C <dir> args through the adapter and gives its stdout, trimmed; any failure ends
// the test.
func (r *droppedRepo) git(args ...string) string {
	r.t.Helper()
	got, err := git.Repo{}.Run(iface.GitCall{Dir: r.dir, Bound: droppedSetupBound, Args: args})
	if err != nil || got.TimedOut || got.Code != 0 {
		r.t.Fatalf("git %q: %v %+v", args, err, got)
	}
	return strings.TrimSpace(got.Stdout)
}

// says runs git -C <dir> args, which must fail, and gives the first line git wrote to stderr.
func (r *droppedRepo) says(args ...string) string {
	r.t.Helper()
	got, err := git.Repo{}.Run(iface.GitCall{Dir: r.dir, Bound: droppedSetupBound, Args: args})
	if err != nil || got.Code == 0 {
		r.t.Fatalf("git %q should fail: %v %+v", args, err, got)
	}
	line, _, _ := strings.Cut(strings.TrimSpace(got.Stderr), "\n")
	if !strings.HasPrefix(line, "fatal: ") {
		r.t.Fatalf("git %q wrote %q, not a fatal: line", args, got.Stderr)
	}
	return line
}

// commit writes each file (name, then content) and commits every change as msg; it gives the commit.
func (r *droppedRepo) commit(msg string, files ...string) string {
	r.t.Helper()
	for i := 0; i+1 < len(files); i += 2 {
		path := filepath.Join(r.dir, files[i])
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			r.t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(files[i+1]), 0o644); err != nil {
			r.t.Fatal(err)
		}
	}
	r.git("add", "-A")
	r.git("commit", "-q", "--allow-empty", "-m", msg)
	return r.git("rev-parse", "HEAD")
}

// merge merges revs into the branch checked out, as git's own merge with no edit; it gives the merge.
func (r *droppedRepo) merge(revs ...string) string {
	r.t.Helper()
	r.git(append([]string{"merge", "-q", "--no-ff", "--no-edit"}, revs...)...)
	return r.git("rev-parse", "HEAD")
}

// reads gives the check's reads of merge m in r, through the adapter.
func (r *droppedRepo) reads(m string) *droppedReads {
	return droppedReadsOf(droppedGit{repo: git.Repo{}, dir: r.dir}, m)
}

// droppedRecorder is an iface.Repo that records each call, then hands it to the adapter.
type droppedRecorder struct {
	calls []iface.GitCall
}

func (d *droppedRecorder) Run(call iface.GitCall) (iface.GitResult, error) {
	d.calls = append(d.calls, call)
	return git.Repo{}.Run(call)
}

// droppedFake is an iface.Repo that gives every call the same result and error.
type droppedFake struct {
	result iface.GitResult
	err    error
}

func (d droppedFake) Run(iface.GitCall) (iface.GitResult, error) { return d.result, d.err }

// droppedCopies is an iface.Repo that adds --find-copies-harder to each git diff, so real git
// writes the C entry of a copy, which git diff -M alone never writes, whatever diff.renames says.
type droppedCopies struct{}

func (droppedCopies) Run(call iface.GitCall) (iface.GitResult, error) {
	if i := slices.Index(call.Args, "diff"); i >= 0 {
		call.Args = slices.Insert(slices.Clone(call.Args), i+1, "--find-copies-harder")
	}
	return git.Repo{}.Run(call)
}

// droppedScript is an iface.Repo that answers each call by its arguments after the -c prefix, joined
// by spaces. A call it has no answer for ends the test.
type droppedScript struct {
	t       *testing.T
	answers map[string]iface.GitResult
}

func (d droppedScript) Run(call iface.GitCall) (iface.GitResult, error) {
	d.t.Helper()
	if len(call.Args) < len(droppedPrefix) {
		d.t.Fatalf("git %q has no -c prefix", call.Args)
	}
	key := strings.Join(call.Args[len(droppedPrefix):], " ")
	got, ok := d.answers[key]
	if !ok {
		d.t.Fatalf("no answer for git %s", key)
	}
	return got, nil
}

// droppedFatal is a git that failed and wrote line.
func droppedFatal(line string) iface.GitResult {
	return iface.GitResult{Code: 128, Stderr: line + "\n"}
}

// droppedStopText is err's stop text, or ends the test where err is not a stop.
func droppedStopText(t *testing.T, err error) string {
	t.Helper()
	var stop *droppedStop
	if !errors.As(err, &stop) {
		t.Fatalf("got %v, want a stop", err)
	}
	return stop.why
}

// droppedSidesEqual reports whether a and b are the same sides, an empty list equal to none.
func droppedSidesEqual(a, b droppedSides) bool {
	return a.pr == b.pr && a.base == b.base && a.baseFirst == b.baseFirst &&
		slices.Equal(a.holds, b.holds) && slices.Equal(a.held, b.held)
}

// droppedSameLines reports whether a and b hold the same lines, and are both a file or both none (nil).
func droppedSameLines(a, b [][]byte) bool {
	return (a == nil) == (b == nil) && slices.EqualFunc(a, b, bytes.Equal)
}

// droppedLines is text's lines as Go byte slices, for a want.
func droppedLines(lines ...string) [][]byte {
	out := make([][]byte, len(lines))
	for i, line := range lines {
		out[i] = []byte(line)
	}
	return out
}

// If a git call of the check lost the 120 s bound, the -C <repo> or the -c prefix, or any argument
// the Python passes (--end-of-options, --literal-pathspecs, --all), or a read that is kept ran git
// again, the calls recorded here would differ.
func TestDroppedGitCalls(t *testing.T) {
	r := droppedNewRepo(t)
	r.commit("A", "a.txt", "a\n")
	r.git("checkout", "-q", "-b", "par")
	r.commit("P1", "par.txt", "par\n")
	r.git("checkout", "-q", "-b", "kid")
	r.commit("K1", "kid.txt", "kid\n")
	r.git("checkout", "-q", "par")
	p2 := r.commit("P2", "par.txt", "par\nmore\n")
	r.git("checkout", "-q", "main")
	nb := r.commit("NB", "new.txt", "new\n")
	r.git("checkout", "-q", "kid")
	k2 := r.merge("main")
	r.git("checkout", "-q", "main")
	r.git("merge", "-q", "--squash", "par")
	s := r.commit("S")
	r.git("checkout", "-q", "kid")
	m := r.merge("par")

	rec := &droppedRecorder{}
	g := droppedGit{repo: rec, dir: r.dir}
	if _, err := g.sides(m, "main", map[string][]string{p2: {s}}); err != nil {
		t.Fatal(err)
	}
	reads := droppedReadsOf(g, m)
	for range 2 {
		if name, lines, err := reads.named(nb, []byte("par.txt"), []byte("par.txt")); err != nil || name != nil || lines != nil {
			t.Fatalf("named at a commit without par.txt = %q, %q, %v; want nothing", name, lines, err)
		}
	}
	var want []iface.GitCall
	for _, args := range [][]string{
		{"rev-list", "--parents", "-n", "1", "--end-of-options", m},
		{"merge-base", "--is-ancestor", k2, "main"},
		{"merge-base", "--is-ancestor", p2, "main"},
		{"merge-base", "--is-ancestor", s, "main"},
		{"merge-base", "--all", k2, "main"},
		{"cat-file", "blob", nb + ":par.txt"},
		{"--literal-pathspecs", "ls-tree", "--name-only", "-z", nb, "--", "par.txt"},
		{"diff", "-M", "--name-status", "-z", "--no-ext-diff", nb, m, "--"},
	} {
		prefixed := append([]string{"-c", "core.quotePath=false", "-c", "merge.conflictStyle=merge"}, args...)
		want = append(want, iface.GitCall{Dir: r.dir, Bound: 120 * time.Second, Args: prefixed})
	}
	if !reflect.DeepEqual(rec.calls, want) {
		t.Errorf("git calls:\n%q\nwant\n%q", rec.calls, want)
	}
}

// If a git that ran past the bound, or did not start, gave its code, its output or Python's words, or
// no stop, these texts would differ. A bound result with exit 0 must still stop.
func TestDroppedGitNoRun(t *testing.T) {
	past := droppedFake{result: iface.GitResult{Code: 0, Stdout: "x", TimedOut: true}}
	noStart := droppedFake{err: errors.New(`exec: "git": executable file not found in $PATH`)}
	for _, tc := range []struct {
		name string
		repo droppedFake
		tail string
	}{
		{"past the bound", past, "git did not finish within 120 s"},
		{"no start", noStart, `git did not start: exec: "git": executable file not found in $PATH`},
	} {
		g := droppedGit{repo: tc.repo, dir: "/repo"}
		reads := droppedReadsOf(g, "1234567890")
		_, ancestorErr := g.ancestor("abcdef0123", "main")
		_, sidesErr := g.sides("1234567890", "main", nil)
		_, readErr := reads.read("abcdef0123", []byte("a.txt"))
		_, renamedErr := reads.renamed("abcdef0123")
		for _, c := range []struct {
			err  error
			want string
		}{
			{ancestorErr, "cannot tell whether abcdef0 is on main: "},
			{sidesErr, "cannot read the parents of merge 1234567: "},
			{readErr, "cannot read a.txt at abcdef0 for merge 1234567: "},
			{renamedErr, "cannot read the renames between abcdef0 and merge 1234567: "},
		} {
			if got := droppedStopText(t, c.err); got != c.want+tc.tail {
				t.Errorf("%s: stop %q, want %q", tc.name, got, c.want+tc.tail)
			}
		}
	}
}

// If git's line kept what follows a carriage return, or was stripped of more than ASCII whitespace
// (bytes.TrimSpace takes U+0085 and U+00A0 too), or split at a vertical tab or U+001C as
// str.splitlines does, these lines would differ from the Python's (each want is what
// (stderr.strip().splitlines() or [b""])[0] gives).
func TestDroppedFirstLine(t *testing.T) {
	for _, tc := range []struct{ stderr, want string }{
		{"fatal: one\rtwo\n", "fatal: one"},
		{"fatal: one\r\ntwo", "fatal: one"},
		{"  \n\t fatal: x \n", "fatal: x"},
		{"\vfatal\f", "fatal"},
		{"a\vb\x1cc\n", "a\vb\x1cc"},
		{"\u0085 nel\n", "\u0085 nel"},
		{"\u00a0x", "\u00a0x"},
		{" \n\t", ""},
	} {
		if got := droppedFirstLine(tc.stderr); got != tc.want {
			t.Errorf("droppedFirstLine(%q) = %q, want %q", tc.stderr, got, tc.want)
		}
	}
	g := droppedGit{repo: droppedFake{result: iface.GitResult{Code: 128, Stderr: "fatal: one\rtwo\n"}}, dir: "/repo"}
	_, err := g.ancestor("abcdef0123", "main")
	if got, want := droppedStopText(t, err), "cannot tell whether abcdef0 is on main: fatal: one"; got != want {
		t.Errorf("stop %q, want %q", got, want)
	}
}

// If a stop cut a commit at seven bytes, not seven characters, or a byte that is not UTF-8 counted as
// anything but one, these would differ from the Python's s[:7].
func TestDroppedShort(t *testing.T) {
	for _, tc := range []struct{ s, want string }{
		{"0123456789abcdef", "0123456"},
		{"abc", "abc"},
		{"origin/main", "origin/"},
		{"éééééééé", "ééééééé"},
		{"\xff\xfeabcdef", "\xff\xfeabcde"},
	} {
		if got := droppedShort(tc.s); got != tc.want {
			t.Errorf("droppedShort(%q) = %q, want %q", tc.s, got, tc.want)
		}
	}
}

// If sides took the first parent as the base side in both orders, read --merged for a merge with a
// parent on the base, or lost a stop, these would differ. Each stop's text is the Python's format
// string (the Python helper's sides).
func TestDroppedSides(t *testing.T) {
	r := droppedNewRepo(t)
	a := r.commit("A", "a.txt", "a\n")
	r.git("checkout", "-q", "-b", "feat")
	f1 := r.commit("F1", "f.txt", "f\n")
	r.git("checkout", "-q", "main")
	b := r.commit("B", "b.txt", "b\n")
	r.git("checkout", "-q", "feat")
	baseSecond := r.merge("main")
	r.git("checkout", "-q", "-b", "into", b)
	baseFirst := r.merge(f1)
	r.git("checkout", "-q", "-b", "o1", b)
	o1 := r.commit("O1", "o1.txt", "o1\n")
	r.git("checkout", "-q", "-b", "o2", b)
	o2 := r.commit("O2", "o2.txt", "o2\n")
	r.git("checkout", "-q", "-b", "oct", b)
	octopus := r.merge(o1, o2)
	r.git("checkout", "-q", "-b", "side", a)
	s1 := r.commit("S1", "s.txt", "s\n")
	r.git("checkout", "-q", "main")
	both := r.merge(s1)
	g := droppedGit{repo: git.Repo{}, dir: r.dir}

	for _, tc := range []struct {
		name   string
		m      string
		merged map[string][]string
		want   droppedSides
	}{
		{"base side second", baseSecond, nil, droppedSides{pr: f1, base: b, holds: []string{b}}},
		{"base side first, --merged not read", baseFirst, map[string][]string{f1: {both}},
			droppedSides{pr: f1, base: b, baseFirst: true, holds: []string{b}}},
	} {
		got, err := g.sides(tc.m, "main", tc.merged)
		if err != nil || !droppedSidesEqual(got, tc.want) {
			t.Errorf("%s: sides = %+v, %v; want %+v", tc.name, got, err, tc.want)
		}
	}
	for _, tc := range []struct{ name, m, want string }{
		{"octopus", octopus, "merge " + octopus[:7] + " has 3 parents: an octopus merge is not remerged, so it is not checked"},
		{"both on the base", both, "merge " + both[:7] + " is unchecked: both parents are on main, so neither is the PR's side"},
		{"no such merge", "0000000000000000000000000000000000000000",
			"cannot read the parents of merge 0000000: " + r.says("rev-list", "--parents", "-n", "1", "--end-of-options", "0000000000000000000000000000000000000000")},
	} {
		_, err := g.sides(tc.m, "main", nil)
		if got := droppedStopText(t, err); got != tc.want {
			t.Errorf("%s: stop %q, want %q", tc.name, got, tc.want)
		}
	}
}

// A stacked build's merge of its parent's branch once the parent's PR merged: kid is cut from par,
// par moves on to p2, kid merges main (so its first parent holds nb, a base commit par lacks), par
// squash-merges into main as s, then kid merges par. If sides dropped git merge-base --all, held would be empty; if it skipped
// the squash check, the second case would not stop; if it stopped a merge resolved by hand (the
// automatic() check #1150 removed), the third would stop.
func TestDroppedSidesMergedParent(t *testing.T) {
	r := droppedNewRepo(t)
	r.commit("A", "a.txt", "a\n")
	r.git("checkout", "-q", "-b", "par")
	r.commit("P1", "par.txt", "par\n")
	r.git("checkout", "-q", "-b", "kid")
	k1 := r.commit("K1", "kid.txt", "kid\n")
	r.git("checkout", "-q", "par")
	p2 := r.commit("P2", "par.txt", "par\nmore\n")
	r.git("checkout", "-q", "main")
	nb := r.commit("NB", "new.txt", "new\n")
	r.git("checkout", "-q", "kid")
	k2 := r.merge("main")
	r.git("checkout", "-q", "main")
	r.git("merge", "-q", "--squash", "par")
	s := r.commit("S")
	r.git("checkout", "-q", "kid")
	own := r.merge("par")
	r.git("checkout", "-q", "-b", "kid-by-hand", k2)
	r.git("merge", "-q", "--no-ff", "--no-commit", "par")
	hand := r.commit("by hand", "kid.txt", "kid\nby hand\n")
	g := droppedGit{repo: git.Repo{}, dir: r.dir}
	merged := map[string][]string{p2: {s}}

	want := droppedSides{pr: k2, base: p2, holds: []string{s, nb}, held: []string{nb}}
	for _, m := range []string{own, hand} {
		got, err := g.sides(m, "main", merged)
		if err != nil || !droppedSidesEqual(got, want) {
			t.Errorf("sides(%s) = %+v, %v; want %+v", m[:7], got, err, want)
		}
	}
	for _, tc := range []struct {
		name   string
		merged map[string][]string
		want   string
	}{
		{"a squash not on the base", map[string][]string{p2: {k1}},
			"merge " + own[:7] + " is unchecked: " + k1[:7] + ", the squash of its second parent's PR, is not on main"},
		{"no --merged", nil,
			"merge " + own[:7] + " is unchecked: neither parent is on main, so it is not a merge of main" +
				" (a stacked build's merge of its parent branch?)"},
	} {
		_, err := g.sides(own, "main", tc.merged)
		if got := droppedStopText(t, err); got != tc.want {
			t.Errorf("%s: stop %q, want %q", tc.name, got, tc.want)
		}
	}
}

// If read counted, trimmed or dropped the empty last line, took an empty file for no file, read a
// path as a pathspec (":dir" names the folder dir that way), or read a folder as absent, these would
// differ. The stop's text is the Python's format string with cat-file's line.
func TestDroppedRead(t *testing.T) {
	r := droppedNewRepo(t)
	c := r.commit("C", "lines.txt", "one\n\ntwo\n", "empty.txt", "", "tail.txt", "no newline", "dir/in.txt", "in\n")
	reads := r.reads(c)
	for _, tc := range []struct {
		path string
		want [][]byte
	}{
		{"lines.txt", droppedLines("one", "", "two", "")},
		{"empty.txt", droppedLines("")},
		{"tail.txt", droppedLines("no newline")},
		{"missing.txt", nil},
		{":dir", nil},
	} {
		got, err := reads.read(c, []byte(tc.path))
		if err != nil || !droppedSameLines(got, tc.want) {
			t.Errorf("read(%s) = %q, %v; want %q", tc.path, got, err, tc.want)
		}
	}
	_, err := reads.read(c, []byte("dir"))
	want := "cannot read dir at " + c[:7] + " for merge " + c[:7] + ": " + r.says("cat-file", "blob", c+":dir")
	if got := droppedStopText(t, err); got != want {
		t.Errorf("read(dir): stop %q, want %q", got, want)
	}
}

// If renamed misread git diff -M's -z list (an R or C entry has an old and a new name, any other
// one name), or mapped the old name to the new, or named looked for a renamed file under its new
// name, these would differ.
func TestDroppedRenamed(t *testing.T) {
	r := droppedNewRepo(t)
	body := "one\ntwo\nthree\nfour\nfive\n"
	c0 := r.commit("C0", "a.txt", "a\n", "old.txt", body, "copied.txt", body+"six\n")
	r.git("mv", "old.txt", "new.txt")
	c1 := r.commit("C1", "a.txt", "a changed\n", "copy.txt", body+"six\n")
	reads := r.reads(c1)

	got, err := reads.renamed(c0)
	if want := map[string][]byte{"new.txt": []byte("old.txt")}; err != nil || !reflect.DeepEqual(got, want) {
		t.Errorf("renamed = %q, %v; want %q", got, err, want)
	}
	copies := droppedReadsOf(droppedGit{repo: droppedCopies{}, dir: r.dir}, c1)
	got, err = copies.renamed(c0)
	if want := map[string][]byte{"new.txt": []byte("old.txt"), "copy.txt": []byte("copied.txt")}; err != nil || !reflect.DeepEqual(got, want) {
		t.Errorf("renamed with copies = %q, %v; want %q", got, err, want)
	}

	for _, tc := range []struct {
		name        string
		rev         string
		path, after []byte
		wantName    string
		want        [][]byte
	}{
		{"under its name in the merge", c1, []byte("x"), []byte("new.txt"), "new.txt", droppedLines("one", "two", "three", "four", "five", "")},
		{"under its old name", c0, []byte("x"), []byte("new.txt"), "old.txt", droppedLines("one", "two", "three", "four", "five", "")},
		{"no name in the merge", c0, []byte("a.txt"), nil, "a.txt", droppedLines("a", "")},
		{"under no name", c0, []byte("gone.txt"), []byte("gone.txt"), "", nil},
	} {
		name, lines, err := reads.named(tc.rev, tc.path, tc.after)
		if err != nil || string(name) != tc.wantName || !droppedSameLines(lines, tc.want) {
			t.Errorf("named %s = %q, %q, %v; want %q, %q", tc.name, name, lines, err, tc.wantName, tc.want)
		}
	}
}

// If sides went on past a failed ancestor read, in the parents' loop or the squashes', took git
// merge-base --all's exit 1 (no common ancestor) for a failure, or lost its stop's words, these would
// differ. Each git answer is scripted; the texts are the Python's format strings.
func TestDroppedSidesStops(t *testing.T) {
	const m, p0, p1, sq = "1111111111", "2222222222", "3333333333", "4444444444"
	parents := iface.GitResult{Stdout: m + " " + p0 + " " + p1 + "\n"}
	no, yes := iface.GitResult{Code: 1}, iface.GitResult{}
	merged := map[string][]string{p1: {sq}}
	for _, tc := range []struct {
		name    string
		answers map[string]iface.GitResult
		want    string
	}{
		{"a parent's ancestor read fails", map[string]iface.GitResult{
			"rev-list --parents -n 1 --end-of-options " + m: parents,
			"merge-base --is-ancestor " + p0 + " main":      droppedFatal("fatal: x"),
		}, "cannot tell whether 2222222 is on main: fatal: x"},
		{"a squash's ancestor read fails", map[string]iface.GitResult{
			"rev-list --parents -n 1 --end-of-options " + m: parents,
			"merge-base --is-ancestor " + p0 + " main":      no,
			"merge-base --is-ancestor " + p1 + " main":      no,
			"merge-base --is-ancestor " + sq + " main":      droppedFatal("fatal: x"),
		}, "cannot tell whether 4444444 is on main: fatal: x"},
		{"merge-base --all fails", map[string]iface.GitResult{
			"rev-list --parents -n 1 --end-of-options " + m: parents,
			"merge-base --is-ancestor " + p0 + " main":      no,
			"merge-base --is-ancestor " + p1 + " main":      no,
			"merge-base --is-ancestor " + sq + " main":      yes,
			"merge-base --all " + p0 + " main":              droppedFatal("fatal: y"),
		}, "cannot find the commits of main that merge 1111111's first parent holds: fatal: y"},
	} {
		_, err := droppedGit{repo: droppedScript{t: t, answers: tc.answers}}.sides(m, "main", merged)
		if got := droppedStopText(t, err); got != tc.want {
			t.Errorf("%s: stop %q, want %q", tc.name, got, tc.want)
		}
	}
	none := map[string]iface.GitResult{
		"rev-list --parents -n 1 --end-of-options " + m: parents,
		"merge-base --is-ancestor " + p0 + " main":      no,
		"merge-base --is-ancestor " + p1 + " main":      no,
		"merge-base --is-ancestor " + sq + " main":      yes,
		"merge-base --all " + p0 + " main":              no,
	}
	got, err := droppedGit{repo: droppedScript{t: t, answers: none}}.sides(m, "main", merged)
	if want := (droppedSides{pr: p0, base: p1, holds: []string{sq}}); err != nil || !droppedSidesEqual(got, want) {
		t.Errorf("no common ancestor: sides = %+v, %v; want %+v", got, err, want)
	}
}

// If named passed over a stop from its first read, from renamed or from the read under the old name,
// or renamed read past an R entry with no new name (the Python raises there; git never writes one),
// these would differ. Each git answer is scripted.
func TestDroppedNamedStops(t *testing.T) {
	const m = "1111111111"
	absent := func(rev, path string) map[string]iface.GitResult {
		return map[string]iface.GitResult{
			"cat-file blob " + rev + ":" + path:                                 droppedFatal("fatal: path '" + path + "' does not exist"),
			"--literal-pathspecs ls-tree --name-only -z " + rev + " -- " + path: {},
		}
	}
	answers := map[string]iface.GitResult{
		"cat-file blob 5555555555:new.txt":                                 droppedFatal("fatal: a"),
		"--literal-pathspecs ls-tree --name-only -z 5555555555 -- new.txt": {Stdout: "new.txt\x00"},
		"diff -M --name-status -z --no-ext-diff 6666666666 " + m + " --":   droppedFatal("fatal: b"),
		"diff -M --name-status -z --no-ext-diff 7777777777 " + m + " --":   {Stdout: "R100\x00old\x00new.txt\x00"},
		"cat-file blob 7777777777:old":                                     droppedFatal("fatal: c"),
		"--literal-pathspecs ls-tree --name-only -z 7777777777 -- old":     {Stdout: "old\x00"},
		"diff -M --name-status -z --no-ext-diff 8888888888 " + m + " --":   {Stdout: "R100\x00old"},
	}
	for _, rev := range []string{"6666666666", "7777777777"} {
		for k, v := range absent(rev, "new.txt") {
			answers[k] = v
		}
	}
	reads := droppedReadsOf(droppedGit{repo: droppedScript{t: t, answers: answers}}, m)
	for _, tc := range []struct{ name, rev, want string }{
		{"its first read", "5555555555", "cannot read new.txt at 5555555 for merge 1111111: fatal: a"},
		{"renamed", "6666666666", "cannot read the renames between 6666666 and merge 1111111: fatal: b"},
		{"the read under the old name", "7777777777", "cannot read old at 7777777 for merge 1111111: fatal: c"},
	} {
		_, _, err := reads.named(tc.rev, []byte("x"), []byte("new.txt"))
		if got := droppedStopText(t, err); got != tc.want {
			t.Errorf("%s: stop %q, want %q", tc.name, got, tc.want)
		}
	}
	if got, err := reads.renamed("8888888888"); err != nil || len(got) != 0 {
		t.Errorf("renamed of an R entry with no new name = %q, %v; want none", got, err)
	}
}
