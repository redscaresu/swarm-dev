package merge

// The dropped-lines check from its arguments to its lines and exit code, ported from
// bin/lib/dropped_lines.py: its main block and scan, built on dropped_diff.go's removed lines and
// text, dropped_counts.go's counting rules and dropped_reads.go's git reads. Nothing runs it yet.

import (
	"bytes"
	"errors"
	"fmt"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/redscaresu/swarm-dev/internal/iface"
)

// droppedUsage is the check's usage stop, the text swarm.sh _dropped-lines gives the Python.
const droppedUsage = "usage: swarm.sh _dropped-lines <repo-dir> <base> <head> [--own <path>] [--merged <sha>:<squash>]... [<merge sha>...]"

const (
	droppedFixedArgs  = 3          // <repo-dir> <base> <head>, before any flag or merge SHA
	droppedOwnFlag    = "--own"    // its path: the PR's own story file
	droppedMergedFlag = "--merged" // its <sha>:<squash>: a commit on a merged PR's branch, and that PR's squash
	droppedPairSep    = ":"        // what splits a --merged pair
	droppedArgByte    = '?'        // how the Python prints an argument's byte that is not UTF-8
)

// The check's exit codes.
const (
	droppedExitNone  = 0 // nothing dropped
	droppedExitFound = 1 // base lines dropped, one line per copy
	droppedExitStop  = 2 // it cannot check: one line says why
)

// DroppedResult is what the dropped-lines check prints on stdout and the code it exits with.
type DroppedResult struct {
	Lines []string // each line it prints, in order: the dropped lines, or the one stop line
	Code  int      // 0 with nothing dropped, 1 with dropped lines, 2 with a stop
}

// Dropped runs the dropped-lines check (the Python's main block) with args, its command line after
// the program's name, through repo. The error is where the Python raises, and so exits 1 with a
// traceback and prints nothing on stdout: an --own path that is not UTF-8, a file read at a commit
// named by an argument that is not UTF-8, or a remerge diff's path droppedUnquote cannot read. The
// result is then empty.
func Dropped(repo iface.Repo, args []string) (DroppedResult, error) {
	lines, err := droppedCheck(repo, args)
	var stop *droppedStop
	switch {
	case errors.As(err, &stop):
		return DroppedResult{Lines: []string{droppedClean([]byte(stop.why))}, Code: droppedExitStop}, nil
	case err != nil:
		return DroppedResult{}, err
	case len(lines) > 0:
		return DroppedResult{Lines: lines, Code: droppedExitFound}, nil
	}
	return DroppedResult{Code: droppedExitNone}, nil
}

// droppedArgs is the check's command line, as the Python's main block reads it.
type droppedArgs struct {
	dir, base, head string
	own             []byte              // --own's path; nil without --own
	merged          map[string][]string // --merged: each second parent to its PR's squashes, in the order given
	wanted          map[string]bool     // the merge SHAs given; none: every merge
}

// droppedParse reads args as the Python does: the usage stop for fewer than three, for an --own
// with no path or an empty one, and for a --merged whose next argument is not two parts split by
// one colon, each not empty, or that has none. A later --own takes the place of an earlier one.
// --merged pairs and merge SHAs are lowered (droppedLower). An --own path that is not UTF-8 is an
// error, where the Python's own.encode() raises.
func droppedParse(args []string) (droppedArgs, error) {
	if len(args) < droppedFixedArgs {
		return droppedArgs{}, &droppedStop{why: droppedUsage}
	}
	a := droppedArgs{dir: args[0], base: args[1], head: args[2], merged: map[string][]string{}, wanted: map[string]bool{}}
	rest := args[droppedFixedArgs:]
	for i := 0; i < len(rest); i++ {
		switch rest[i] {
		case droppedOwnFlag:
			i++
			if i >= len(rest) || rest[i] == "" {
				return droppedArgs{}, &droppedStop{why: droppedUsage}
			}
			if !utf8.ValidString(rest[i]) {
				return droppedArgs{}, fmt.Errorf("--own %q is not UTF-8, so the Python cannot encode it", rest[i])
			}
			a.own = []byte(rest[i])
		case droppedMergedFlag:
			pair := ""
			if i+1 < len(rest) {
				i++
				pair = rest[i]
			}
			sha, squash, ok := strings.Cut(droppedLower(pair), droppedPairSep)
			if !ok || sha == "" || squash == "" || strings.Contains(squash, droppedPairSep) {
				return droppedArgs{}, &droppedStop{why: droppedUsage}
			}
			a.merged[sha] = append(a.merged[sha], squash)
		default:
			a.wanted[droppedLower(rest[i])] = true
		}
	}
	return a, nil
}

// droppedLower is s lowered as Python's str.lower lowers an argument: each character as
// unicode.ToLower maps it, U+0130 to the i and combining dot Python's full mapping gives, and each
// byte that is not part of a UTF-8 character kept as it is, as Python keeps the surrogate it reads
// that byte as. Python's Final_Sigma rule is left out: a capital sigma that ends a word lowers to
// σ here and to ς there. A SHA is hex, so only a --merged squash that is no SHA can show it, in
// git's line and the stop that names that squash.
func droppedLower(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); {
		r, n := utf8.DecodeRuneInString(s[i:])
		switch {
		case r == utf8.RuneError && n == 1:
			b.WriteByte(s[i])
		case r == 'İ':
			b.WriteString("i̇")
		default:
			b.WriteRune(unicode.ToLower(r))
		}
		i += n
	}
	return b.String()
}

// droppedArgText is an argument as the Python prints it in a stop: it reads each byte that is not
// part of a UTF-8 character as a surrogate, and prints that surrogate as ?. sides' stops name the
// base and a squash as they are, so there such a byte prints as droppedClean gives it.
func droppedArgText(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); {
		r, n := utf8.DecodeRuneInString(s[i:])
		if r == utf8.RuneError && n == 1 {
			b.WriteByte(droppedArgByte)
		} else {
			b.WriteString(s[i : i+n])
		}
		i += n
	}
	return b.String()
}

// droppedRange is what the check reads every merge against: the PR's head, the merge base of
// base and head, the commits that must still have a line, and the PR's own story file.
type droppedRange struct {
	git       droppedGit
	head      string
	mergeBase string   // git merge-base <base> <head>; empty where they have no common ancestor
	later     []string // base, then mergeBase where there is one: where the base must still have a line (gone)
	own       []byte   // --own's path; nil without --own
	ownGone   bool     // the head has no file at own, so no line of it prints
}

// droppedCheck is the Python's main block up to its print: the dropped lines, or the stop. It
// lists the merges in base..head, oldest first on the first-parent line, keeping the SHAs given;
// checks --own's file at the head; reads every merge's sides before it scans any, so a merge it
// cannot check stops the check before a line of another is read; and with a merge to scan, takes
// the merge base of base and head. Then it scans each merge, and keeps the lines the head has not
// put back (droppedMissing) and does not extend (droppedExtended).
func droppedCheck(repo iface.Repo, args []string) ([]string, error) {
	a, err := droppedParse(args)
	if err != nil {
		return nil, err
	}
	r := &droppedRange{git: droppedGit{repo: repo, dir: a.dir}, head: a.head, own: a.own}
	list := r.git.run("rev-list", "--first-parent", "--merges", "--reverse", "--end-of-options", a.base+".."+a.head, "--")
	if list.code != 0 {
		return nil, droppedStopf("cannot list the merges in %s..%s: %s",
			droppedArgText(a.base), droppedArgText(a.head), list.errLine)
	}
	var merges []string
	for _, m := range strings.Fields(string(list.stdout)) {
		if len(a.wanted) == 0 || a.wanted[m] {
			merges = append(merges, m)
		}
	}
	if a.own != nil {
		ls := r.git.run("--literal-pathspecs", "ls-tree", "--name-only", "-z", "--end-of-options", a.head, "--", string(a.own))
		if ls.code != 0 {
			return nil, droppedStopf("cannot tell whether %s has %s: %s",
				droppedArgText(droppedShort(a.head)), a.own, ls.errLine)
		}
		r.ownGone = len(ls.stdout) == 0
	}
	sides := make([]droppedSides, len(merges))
	for i, m := range merges {
		if sides[i], err = r.git.sides(m, a.base, a.merged); err != nil {
			return nil, err
		}
	}
	if len(merges) > 0 {
		mb := r.git.run("merge-base", "--end-of-options", a.base, a.head)
		if mb.code != droppedGitYes && mb.code != droppedGitNo {
			return nil, droppedStopf("cannot find the merge base of %s and %s: %s",
				droppedArgText(a.base), droppedArgText(a.head), mb.errLine)
		}
		r.mergeBase = strings.TrimSpace(string(mb.stdout))
	}
	r.later = []string{a.base}
	if r.mergeBase != "" {
		r.later = append(r.later, r.mergeBase)
	}
	var found []droppedEntry
	for i, m := range merges {
		entries, err := r.scan(m, sides[i])
		if err != nil {
			return nil, err
		}
		found = append(found, entries...)
	}
	return droppedExtended(droppedMissing(found), found), nil
}

// droppedFile is a file as the remerge diff names it: the remerged file's name and its name in the
// merge, which hasAfter false makes the Python's None.
type droppedFile struct {
	path, after string
	hasAfter    bool
}

// droppedFileOf is the key of path and after, a nil after being the Python's None.
func droppedFileOf(path, after []byte) droppedFile {
	return droppedFile{path: string(path), after: string(after), hasAfter: after != nil}
}

// droppedMostAt is a key of most's: the commits read, joined by NUL, which no argument or SHA holds,
// and the file.
type droppedMostAt struct {
	revs string
	file droppedFile
}

// droppedTextAt is one line of one remerged file: a key of short's and counts'.
type droppedTextAt struct {
	path, text string
}

// droppedKept is what the first removed copy of a line says about it (the Python's counts): the
// file's name in the merge (nil: None), the merge's copies of the line, and the copies the PR side
// had removed before the merge.
type droppedKept struct {
	after []byte
	kept  int
	cut   int
}

// droppedFound is one copy of a line that a merge printed, before its head counts are read.
type droppedFound struct {
	at         droppedTextAt
	path, text []byte
	line       string // `<merge sha7> <file>: <text>`
}

// droppedScan is one merge's scan: the Python's scan with its closures and their caches, which live
// as long as the scan, as the Python's do.
type droppedScan struct {
	*droppedRange
	reads   *droppedReads
	merge   string
	sides   droppedSides
	ours    droppedSection // the base side's part of a conflict
	mb      string         // the merge base of the merge's two sides, where hasMB
	hasMB   bool
	counted map[droppedAt]*droppedCounts   // each file read, its lines counted once
	spares  map[droppedFile]*droppedCounts // spare's
	mosts   map[droppedMostAt]*droppedCounts
	short   map[droppedTextAt]int // the copies of a line the merge's file is short of, less those printed
	counts  map[droppedTextAt]droppedKept
	found   []droppedFound
}

// scan is the Python's scan of merge m with its sides: each base line its resolution dropped, as
// an entry with what the head owes and holds of it. It reads the remerge diff, with a/ and b/
// prefixes whatever the user's config says, and the merge base of the two sides (none: every line
// is new). Each removed line is judged in diff order (line), and once every line is read, each
// printed copy's head counts are read in print order (owing).
func (r *droppedRange) scan(m string, sd droppedSides) ([]droppedEntry, error) {
	show := r.git.run("show", "--remerge-diff", "--format=", "--no-color", "--no-ext-diff", "--no-textconv",
		"--src-prefix=a/", "--dst-prefix=b/", "--end-of-options", m)
	if show.code != 0 {
		return nil, droppedStopf("git show --remerge-diff failed on merge %s: %s", droppedShort(m), show.errLine)
	}
	mb := r.git.run("merge-base", sd.pr, sd.base)
	if mb.code != droppedGitYes && mb.code != droppedGitNo {
		return nil, droppedStopf("cannot find the merge base of merge %s's parents: %s", droppedShort(m), mb.errLine)
	}
	s := &droppedScan{
		droppedRange: r, reads: droppedReadsOf(r.git, m), merge: m, sides: sd, ours: droppedSecond,
		counted: map[droppedAt]*droppedCounts{}, spares: map[droppedFile]*droppedCounts{},
		mosts: map[droppedMostAt]*droppedCounts{}, short: map[droppedTextAt]int{}, counts: map[droppedTextAt]droppedKept{},
	}
	if sd.baseFirst {
		s.ours = droppedFirst
	}
	if mb.code == droppedGitYes {
		s.mb, s.hasMB = strings.TrimSpace(string(mb.stdout)), true
	}
	removed, bad := droppedRemoved(show.stdout)
	for _, l := range removed { // the lines before a path droppedUnquote cannot read, as the Python's generator yields them
		if err := s.line(l); err != nil {
			return nil, err
		}
	}
	if bad != nil {
		return nil, bad
	}
	return s.owings()
}

// skips reports whether l is never printed: a line of ASCII whitespace alone (Python's bytes.strip
// takes off no other), a line outside the sections a merge's base lines sit in (outside any
// conflict and the base side's part, and the first parent's part too where the PR side holds base
// commits), or a line of the PR's own story file where the head has none.
func (s *droppedScan) skips(l droppedLine) bool {
	if len(bytes.Trim(l.text, droppedASCII)) == 0 {
		return true
	}
	held := len(s.sides.held) > 0
	if l.section != droppedOutside && l.section != s.ours && !(held && l.section == droppedFirst) {
		return true
	}
	return s.ownGone && (bytes.Equal(l.file, s.own) || (l.hasAfter && bytes.Equal(l.after, s.own)))
}

// line judges one removed line (the Python's loop body). The base's copies are the most any commit
// of the sides' holds has; where none has the file, the line is skipped, or in the base side's part
// of a conflict, the merge is unchecked. The first copy of a line sets how many copies the merge's
// file is short of (first), and each copy printed takes one off.
func (s *droppedScan) line(l droppedLine) error {
	if s.skips(l) {
		return nil
	}
	base, err := s.most(s.sides.holds, l.file, l.after)
	if err != nil {
		return err
	}
	if base == nil {
		if l.section == s.ours { // the base's part of a conflict, so the base side has this file
			return droppedStopf("merge %s is unchecked: %s, in a conflict, is not on its base side under that name or"+
				" a rename git finds", droppedShort(s.merge), l.file)
		}
		return nil
	}
	side, err := s.copies(s.sides.pr, l.file, l.after)
	if err != nil {
		return err
	}
	var root, kept *droppedCounts // nil reads as no copies, the Python's Counter()
	if s.hasMB {
		if root, err = s.copies(s.mb, l.file, l.after); err != nil {
			return err
		}
	}
	if l.hasAfter {
		if kept, err = s.read(s.merge, l.after); err != nil {
			return err
		}
	}
	at := droppedTextAt{path: string(l.file), text: string(l.text)}
	if _, seen := s.short[at]; !seen {
		if err := s.first(l, at, droppedSidesCounts{base: base, side: side, root: root, kept: kept}); err != nil {
			return err
		}
	}
	if s.short[at] > 0 { // a copy the resolution moved is removed here and added back elsewhere
		s.short[at]--
		line := fmt.Sprintf("%s %s: %s", droppedShort(s.merge), droppedClean(l.file), droppedCut(droppedClean(l.text)))
		s.found = append(s.found, droppedFound{at: at, path: l.file, text: l.text, line: line})
	}
	return nil
}

// droppedSidesCounts is one file's copies on each side of a merge: the most the base holds, the PR
// side's, the merge base of the two sides' and the merge's own. A nil one holds no copies.
type droppedSidesCounts struct {
	base, side, root, kept *droppedCounts
}

// first is what the first removed copy of a line sets. The merge's own sides say how many copies a
// merge of them keeps (droppedOwed): the base side's copies where the PR side holds base commits,
// else the base's. The file is short of those less the merge's own, or of none where the base has
// no copy or no longer has the line (gone). In the PR side's own part of a conflict, where the PR
// side holds base commits, a line it is short of with copies the build's own commits added (beyond
// the most the merge base of the sides, or a base commit the PR side holds, has) cannot be told
// from the base's, and the merge is unchecked.
func (s *droppedScan) first(l droppedLine, at droppedTextAt, c droppedSidesCounts) error {
	held := len(s.sides.held) > 0
	two := c.base
	if held {
		var err error
		if two, err = s.copies(s.sides.base, l.file, l.after); err != nil {
			return err
		}
	}
	short := 0
	if c.base.of(l.text) > 0 {
		gone, err := s.gone(l.file, l.after, l.text)
		if err != nil {
			return err
		}
		if !gone {
			short = droppedOwed(two.of(l.text), c.side.of(l.text), c.root.of(l.text)) - c.kept.of(l.text)
		}
	}
	s.short[at] = short
	s.counts[at] = droppedKept{after: l.after, kept: c.kept.of(l.text), cut: max(0, c.root.of(l.text)-c.side.of(l.text))}
	if short <= 0 || !held || l.section != droppedFirst {
		return nil
	}
	mine, err := s.most(s.sides.held, l.file, l.after)
	if err != nil {
		return err
	}
	if c.side.of(l.text) > max(c.root.of(l.text), mine.of(l.text)) {
		return droppedStopf("merge %s is unchecked: %s: %s, dropped from its first parent's part of a conflict, has"+
			" copies the build's own commits added, so a count cannot tell whose copy it dropped",
			droppedShort(s.merge), l.file, droppedCut(droppedClean(l.text)))
	}
	return nil
}

// owings is the scan's entries, one per printed copy in print order, each with the head's counts
// (owing). printed is each line's copies the merge printed.
func (s *droppedScan) owings() ([]droppedEntry, error) {
	printed := map[droppedTextAt]int{}
	for _, f := range s.found {
		printed[f.at]++
	}
	entries := make([]droppedEntry, 0, len(s.found))
	for _, f := range s.found {
		e, err := s.owing(f, printed[f.at])
		if err != nil {
			return nil, err
		}
		entries = append(entries, e)
	}
	return entries, nil
}

// owing is f's entry (the Python's owing): the head's own name for the file and its copies of the
// line, and the copies the head owes the merge, the larger of the merge's kept copies plus the
// ones it printed and the copies the merge base of base and head holds less those the PR side had
// removed. There is no bound where that merge base has no such file. The head key is the merge's
// name for the file where the head has it under no name.
func (s *droppedScan) owing(f droppedFound, printed int) (droppedEntry, error) {
	k := s.counts[f.at]
	name, now, err := s.named(s.head, f.path, k.after)
	if err != nil {
		return droppedEntry{}, err
	}
	var since *droppedCounts
	if s.mergeBase != "" {
		if since, err = s.copies(s.mergeBase, f.path, k.after); err != nil {
			return droppedEntry{}, err
		}
	}
	e := droppedEntry{file: droppedHeadFile{name: string(f.path)}, text: f.text, held: now.of(f.text), line: f.line}
	if name != nil {
		e.file = droppedHeadFile{headHas: true, name: string(name)}
	}
	if since != nil {
		e.need = max(k.kept+printed, since.of(f.text)-k.cut)
	} else {
		e.unbounded = true
	}
	if e.spare, err = s.spare(f.path, k.after); err != nil {
		return droppedEntry{}, err
	}
	return e, nil
}

// gone reports whether the base itself no longer has text in this file: at base, or then at the
// merge base of base and head, the file, read under that commit's own name for it, has no copy. A
// commit with no such file under any name git finds still counts the line. It stops at the first
// commit that has no copy, as the Python does, so the next is not read.
func (s *droppedScan) gone(path, after, text []byte) (bool, error) {
	for _, rev := range s.later {
		got, err := s.copies(rev, path, after)
		if err != nil {
			return false, err
		}
		if got != nil && got.of(text) == 0 {
			return true, nil
		}
	}
	return false, nil
}

// spare is the head's copies of each line of the file beyond the most that base or the merge base
// of base and head holds, each file read under that commit's own name for it, and the head's only
// where both have it; none where one of them has no such file, as its copies are then unknown.
func (s *droppedScan) spare(path, after []byte) (*droppedCounts, error) {
	key := droppedFileOf(path, after)
	if got, ok := s.spares[key]; ok {
		return got, nil
	}
	base, known := droppedCount(nil), true
	for _, rev := range s.later {
		got, err := s.copies(rev, path, after)
		if err != nil {
			return nil, err
		}
		base, known = base.union(got), known && got != nil
	}
	spare := droppedCount(nil)
	if known {
		_, head, err := s.named(s.head, path, after)
		if err != nil {
			return nil, err
		}
		spare = head.minus(base)
	}
	s.spares[key] = spare
	return spare, nil
}

// most is the most copies of each line that the file holds at any of revs, read once per file
// (copies); nil where none of them has it. With one commit it is that commit's own copies.
func (s *droppedScan) most(revs []string, path, after []byte) (*droppedCounts, error) {
	if len(revs) == 1 {
		return s.copies(revs[0], path, after)
	}
	key := droppedMostAt{revs: strings.Join(revs, "\x00"), file: droppedFileOf(path, after)}
	if got, ok := s.mosts[key]; ok {
		return got, nil
	}
	top, seen := droppedCount(nil), false
	for _, rev := range revs {
		got, err := s.copies(rev, path, after)
		if err != nil {
			return nil, err
		}
		if got != nil {
			top, seen = top.union(got), true
		}
	}
	if !seen {
		top = nil
	}
	s.mosts[key] = top
	return top, nil
}

// copies is the file's lines at rev, read under rev's own name for it (named); nil where rev has
// none of them.
func (s *droppedScan) copies(rev string, path, after []byte) (*droppedCounts, error) {
	_, got, err := s.named(rev, path, after)
	return got, err
}

// named is the reads' named with the lines counted: rev's own name for the file and its copies of
// each line, or nil, nil where rev has none of its names.
func (s *droppedScan) named(rev string, path, after []byte) ([]byte, *droppedCounts, error) {
	if err := droppedEncodable(rev); err != nil {
		return nil, nil, err
	}
	name, lines, err := s.reads.named(rev, path, after)
	if err != nil || lines == nil {
		return nil, nil, err
	}
	return name, s.count(rev, name, lines), nil
}

// read is the reads' read with the lines counted: path's copies of each line at rev, nil where rev
// has no such path.
func (s *droppedScan) read(rev string, path []byte) (*droppedCounts, error) {
	if err := droppedEncodable(rev); err != nil {
		return nil, err
	}
	lines, err := s.reads.read(rev, path)
	if err != nil || lines == nil {
		return nil, err
	}
	return s.count(rev, path, lines), nil
}

// count is the lines of path at rev counted, once per file.
func (s *droppedScan) count(rev string, path []byte, lines [][]byte) *droppedCounts {
	key := droppedAt{rev: rev, path: string(path)}
	if got, ok := s.counted[key]; ok {
		return got
	}
	got := droppedCount(lines)
	s.counted[key] = got
	return got
}

// droppedEncodable is an error where rev is not UTF-8: the Python's read raises encoding it, before
// it reads or keeps anything, so every read at it raises. Only an argument can name such a commit,
// as every other commit the check reads at is a SHA git printed.
func droppedEncodable(rev string) error {
	if utf8.ValidString(rev) {
		return nil
	}
	return fmt.Errorf("cannot read a file at %q: it is not UTF-8, so the Python cannot encode it", rev)
}
