package merge

import (
	"bytes"
	"fmt"
	"strings"
	"time"

	"github.com/redscaresu/swarm-dev/internal/iface"
)

// The git reads of the dropped-lines check, ported from the Python helper it replaced: git, ancestor,
// sides, and scan's read, renamed and named. Each read gives the stop the Python would print, as a
// *droppedStop, where the Python calls stop.

// droppedGitBound is the longest one git call of the check may run, the Python's GIT_SECONDS.
const droppedGitBound = 120 * time.Second

const (
	droppedGitYes     = 0  // git merge-base's exit for yes: an ancestor, or a merge base found
	droppedGitNo      = 1  // its exit for no: not an ancestor, or no common ancestor
	droppedNoRun      = -1 // the exit a call gives where git ran past the bound or did not start, as the Python's git gives -1
	droppedShortChars = 7  // how many characters of a commit a stop names, the Python's [:7]
)

const (
	droppedNoStart   = "git did not start: "            // a call's line where git did not start, before Go's error
	droppedPastBound = "git did not finish within %d s" // a call's line where git ran past droppedGitBound
	droppedASCII     = " \t\n\r\v\f"                    // what Python's bytes.strip takes off: ASCII whitespace only
	droppedLineEnds  = "\r\n"                           // where Python's bytes.splitlines ends a line: \n, \r and \r\n
)

// The --name-status letters of an entry that has an old and a new name.
const (
	droppedRenamed = 'R'
	droppedCopied  = 'C'
)

// droppedPrefix is what every git call of the check passes after -C <repo>: paths as they are, not
// C-quoted, and the remerge diff's conflicts in git's plain two-part style, whatever the user's config
// says.
var droppedPrefix = []string{"-c", "core.quotePath=false", "-c", "merge.conflictStyle=merge"}

// droppedStop is the check's stop (the Python's stop): the one line it prints, before any dropped
// line, when it cannot check, and then exits 2. why holds the Python's text, with git's line and any
// path as git wrote them, not yet cleaned: the printer cleans the whole line. The Python cleans those
// two parts on their own first, and each sits between ASCII text and ASCII text or the line's end, so
// one clean of the line gives the same text. A commit or base the line names from an argument that
// is not UTF-8 is the printer's to match: the Python prints each such byte as ?.
type droppedStop struct {
	why string
}

func (s *droppedStop) Error() string { return s.why }

// droppedStopf is the stop whose text is format with args, as the Python's stop(format % args).
func droppedStopf(format string, args ...any) error {
	return &droppedStop{why: fmt.Sprintf(format, args...)}
}

// droppedShort is s's first seven characters, as the Python's s[:7] on text. A byte that is not
// UTF-8 counts as one character, as the one code point Python's surrogateescape gives it.
func droppedShort(s string) string {
	n := 0
	for i := range s {
		if n == droppedShortChars {
			return s[:i]
		}
		n++
	}
	return s
}

// droppedGit runs the check's git calls in one repository through iface.Repo (the Python's git).
type droppedGit struct {
	repo iface.Repo
	dir  string // the repository, passed as git -C <dir>
}

// droppedRun is what one git call gave.
type droppedRun struct {
	code    int    // git's exit code, or droppedNoRun
	stdout  []byte // what git wrote to stdout; empty with droppedNoRun
	errLine string // stderr's first line (droppedFirstLine), or the Go's words with droppedNoRun
}

// run runs git -C <dir> with droppedPrefix and args, with no stdin, bounded by droppedGitBound. Where
// git ran past the bound or did not start, it gives droppedNoRun, no stdout and the Go's own words,
// where the Python gives its exception's text: "Command '[...]' timed out after 120 seconds", or
// "[Errno 2] No such file or directory: 'git'".
func (g droppedGit) run(args ...string) droppedRun {
	got, err := g.repo.Run(iface.GitCall{
		Dir:   g.dir,
		Bound: droppedGitBound,
		Args:  append(append([]string{}, droppedPrefix...), args...),
	})
	if err != nil {
		return droppedRun{code: droppedNoRun, errLine: droppedNoStart + err.Error()}
	}
	if got.TimedOut {
		return droppedRun{code: droppedNoRun, errLine: fmt.Sprintf(droppedPastBound, droppedGitBound/time.Second)}
	}
	return droppedRun{code: got.Code, stdout: []byte(got.Stdout), errLine: droppedFirstLine(got.Stderr)}
}

// droppedFirstLine is stderr's first line as the Python reads it: ASCII whitespace taken off both
// ends, as bytes.strip does, then cut at the first newline or carriage return, as bytes.splitlines
// cuts. It is empty where nothing is left. Its bytes are git's, not yet cleaned.
func droppedFirstLine(stderr string) string {
	s := strings.Trim(stderr, droppedASCII)
	if i := strings.IndexAny(s, droppedLineEnds); i >= 0 {
		return s[:i]
	}
	return s
}

// ancestor reports whether rev is on of, with git merge-base --is-ancestor; any exit but yes or no
// is the stop (the Python's ancestor).
func (g droppedGit) ancestor(rev, of string) (bool, error) {
	r := g.run("merge-base", "--is-ancestor", rev, of)
	if r.code != droppedGitYes && r.code != droppedGitNo {
		return false, droppedStopf("cannot tell whether %s is on %s: %s", droppedShort(rev), of, r.errLine)
	}
	return r.code == droppedGitYes, nil
}

// droppedSides is how the check reads one merge, as the Python's sides gives it.
type droppedSides struct {
	pr        string   // the PR side
	base      string   // the base side
	baseFirst bool     // the base side is the first parent: its part of a conflict is the first (FIRST, else SECOND)
	holds     []string // the commits whose files say what the base holds
	held      []string // the base commits the PR side holds: none but for a merge of a merged parent's branch
}

// sides reads merge m's parents, or stops saying why m cannot be checked (the Python's sides). A
// merge of base has two parents, exactly one on base, and that one is the base side, in either
// order. merged maps a second parent on the branch of a PR merged into base to that PR's squashes
// (the --merged pairs). A merge with neither parent on base whose second parent is in merged is a
// stacked build's merge of its merged parent's branch: every squash must be on base, the second
// parent is the base side, and the files of the squashes and of the base commits the first parent
// holds (git merge-base --all) say what the base holds.
func (g droppedGit) sides(m, base string, merged map[string][]string) (droppedSides, error) {
	r := g.run("rev-list", "--parents", "-n", "1", "--end-of-options", m)
	if r.code != 0 {
		return droppedSides{}, droppedStopf("cannot read the parents of merge %s: %s", droppedShort(m), r.errLine)
	}
	var parents []string // rev-list prints the commit, then its parents: hex ids, split as str.split splits them
	if ids := strings.Fields(string(r.stdout)); len(ids) > 0 {
		parents = ids[1:]
	}
	if len(parents) != 2 {
		return droppedSides{}, droppedStopf("merge %s has %d parents: an octopus merge is not remerged, so it is not checked",
			droppedShort(m), len(parents))
	}
	var on []string
	for _, p := range parents {
		yes, err := g.ancestor(p, base)
		if err != nil {
			return droppedSides{}, err
		}
		if yes {
			on = append(on, p)
		}
	}
	if squashes, ok := merged[parents[1]]; len(on) == 0 && ok {
		for _, squash := range squashes {
			yes, err := g.ancestor(squash, base)
			if err != nil {
				return droppedSides{}, err
			}
			if !yes {
				return droppedSides{}, droppedStopf("merge %s is unchecked: %s, the squash of its second parent's PR, is not on %s",
					droppedShort(m), droppedShort(squash), base)
			}
		}
		r := g.run("merge-base", "--all", parents[0], base)
		if r.code != droppedGitYes && r.code != droppedGitNo {
			return droppedSides{}, droppedStopf("cannot find the commits of %s that merge %s's first parent holds: %s",
				base, droppedShort(m), r.errLine)
		}
		held := strings.Fields(string(r.stdout))
		holds := append(append([]string{}, squashes...), held...)
		return droppedSides{pr: parents[0], base: parents[1], holds: holds, held: held}, nil
	}
	if len(on) == 0 {
		return droppedSides{}, droppedStopf("merge %s is unchecked: neither parent is on %s, so it is not a merge of %s"+
			" (a stacked build's merge of its parent branch?)", droppedShort(m), base, base)
	}
	if len(on) == 2 {
		return droppedSides{}, droppedStopf("merge %s is unchecked: both parents are on %s, so neither is the PR's side",
			droppedShort(m), base)
	}
	if on[0] == parents[0] {
		return droppedSides{pr: parents[1], base: parents[0], baseFirst: true, holds: []string{parents[0]}}, nil
	}
	return droppedSides{pr: parents[0], base: parents[1], holds: []string{parents[1]}}, nil
}

// droppedAt is one path at one commit: a key of droppedReads' files.
type droppedAt struct {
	rev  string
	path string // the path's bytes as they are
}

// droppedReads reads one merge's files at the commits the check compares them with (scan's read,
// renamed and named in the Python). Each file at a commit, and each commit's renames, is read from
// git once and kept.
type droppedReads struct {
	git     droppedGit
	merge   string                       // the merge, which each stop names
	files   map[droppedAt][][]byte       // each path read: its lines, nil where the commit has no such path
	renames map[string]map[string][]byte // per commit: each path of the merge's tree it holds under another name, to that name
}

// droppedReadsOf gives the reads of merge m through g.
func droppedReadsOf(g droppedGit, m string) *droppedReads {
	return &droppedReads{git: g, merge: m, files: map[droppedAt][][]byte{}, renames: map[string]map[string][]byte{}}
}

// read gives path's lines at rev, split at each newline as the Python's blob.split(b"\n") splits
// them: an empty file is one empty line, and a file that ends in a newline ends in an empty line. It
// gives nil where rev has no such path: git cat-file cannot read the blob, and git ls-tree, with the
// path taken literally, lists nothing there. Where ls-tree fails or lists something, such as a
// folder, it stops with cat-file's line. Later reads share the lines: never change them.
func (r *droppedReads) read(rev string, path []byte) ([][]byte, error) {
	key := droppedAt{rev: rev, path: string(path)}
	if lines, ok := r.files[key]; ok {
		return lines, nil
	}
	blob := r.git.run("cat-file", "blob", rev+":"+string(path))
	var lines [][]byte
	if blob.code == 0 {
		lines = bytes.Split(blob.stdout, []byte("\n"))
	} else {
		listed := r.git.run("--literal-pathspecs", "ls-tree", "--name-only", "-z", rev, "--", string(path))
		if listed.code != 0 || len(listed.stdout) > 0 {
			return nil, droppedStopf("cannot read %s at %s for merge %s: %s",
				path, droppedShort(rev), droppedShort(r.merge), blob.errLine)
		}
	}
	r.files[key] = lines
	return lines, nil
}

// renamed maps each path of the merge's tree that rev holds under another name to that name, as git
// diff -M --name-status -z from rev to the merge lists them: an R or C entry gives its old name, then
// its new one. git ends every name with a NUL, so such an entry always has both. Where one does not,
// the Go stops reading the list there, where the Python raises.
func (r *droppedReads) renamed(rev string) (map[string][]byte, error) {
	if got, ok := r.renames[rev]; ok {
		return got, nil
	}
	d := r.git.run("diff", "-M", "--name-status", "-z", "--no-ext-diff", rev, r.merge, "--")
	if d.code != 0 {
		return nil, droppedStopf("cannot read the renames between %s and merge %s: %s",
			droppedShort(rev), droppedShort(r.merge), d.errLine)
	}
	f, got := bytes.Split(d.stdout, []byte{0}), map[string][]byte{}
	for i := 0; i+1 < len(f) && len(f[i]) > 0; {
		if c := f[i][0]; c != droppedRenamed && c != droppedCopied {
			i += 2
			continue
		}
		if i+2 >= len(f) {
			break
		}
		got[string(f[i+2])] = f[i+1]
		i += 3
	}
	r.renames[rev] = got
	return got, nil
}

// named gives rev's own name for a file and its lines (the Python's named). The name is after, the
// file's name in the merge, or path, the remerged file's name, where after is empty. Where rev has no
// file there, after is not nil and rev holds after under another name (renamed), it is that name. It
// gives nil, nil where rev has none of them. A nil after is the Python's None: the file has no name
// in the merge.
func (r *droppedReads) named(rev string, path, after []byte) ([]byte, [][]byte, error) {
	name := path
	if len(after) > 0 {
		name = after
	}
	lines, err := r.read(rev, name)
	if err != nil {
		return nil, nil, err
	}
	if lines == nil && after != nil {
		renames, err := r.renamed(rev)
		if err != nil {
			return nil, nil, err
		}
		if old, ok := renames[string(after)]; ok {
			if lines, err = r.read(rev, old); err != nil {
				return nil, nil, err
			}
			name = old
		}
	}
	if lines == nil {
		return nil, nil, nil
	}
	return name, lines, nil
}
