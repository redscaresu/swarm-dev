// Package report holds the Go copies of bin/lib/report.py's readers, rule for rule. findings.go is
// finding_rows and fixed_rows, the readers of .swarm/findings.tsv. No caller runs them yet.
package report

import (
	"errors"
	"fmt"
	"os"
	"slices"
	"strings"
	"unicode"

	"github.com/redscaresu/swarm-dev/internal/iface"
	"github.com/redscaresu/swarm-dev/internal/pytext"
)

// reviewersVar names the reviewers log-finding takes, space-separated. A row whose sixth column is
// none of them, and not unknownReviewer, is dropped.
const reviewersVar = "SWARM_FINDING_REVIEWERS"

// unknownReviewer is the reviewer every read keeps beside reviewersVar's: a row logged with no
// --reviewer, and a 4- or 5-column row from before the column existed.
const unknownReviewer = "unknown"

// minCols is the fewest columns a row needs to be read: day, kind, PR and text.
const minCols = 4

// maxCols is the columns a row is cut to before it is padded: a later column drops no row.
const maxCols = 8

// minWidth is the narrowest row a read may ask for: the outcome and reviewer columns it filters on.
const minWidth = 6

// emptyCols is the empty columns put after the padded row, before it is cut to the width.
const emptyCols = 2

// defaults is what a short row gets for its missing outcome and reviewer: a 4-column row both, a
// 5-column row the reviewer.
var defaults = []string{"fixed", unknownReviewer}

// readOutcomes is the outcomes finding_rows keeps when its caller names none.
var readOutcomes = []string{"fixed", "declined"}

// fixedOutcomes is the outcomes fixed_rows keeps.
var fixedOutcomes = []string{"fixed", "escaped"}

// ErrNoReviewers is the error when reviewersVar is unset, where Python's os.environ raises KeyError:
// a caller that does not pass it fails rather than drops every row.
var ErrNoReviewers = errors.New(reviewersVar + " is not set; the findings readers need the reviewer list")

// Findings reads findings.tsv through a store.
type Findings struct {
	Store iface.Store
}

// FindingRows is finding_rows(path, outcomes, width): each row of path with at least minCols
// columns, cut to maxCols, a missing outcome read as fixed and a missing reviewer as unknown, then
// padded with two empty columns and cut to width. Only rows whose outcome is in outcomes and whose
// reviewer is in reviewersVar, or is unknown, are kept. A nil outcomes is the default, fixed and
// declined.
//
// reviewersVar is read first, and an unset one is ErrNoReviewers, even for a missing file. A path
// that cannot be stat'ed gives no rows, as os.path.exists is false then; one that exists but cannot
// be read is the read's error, as open() raises. The bytes are read as Python's
// open(encoding="utf-8", errors="replace", newline="\n") reads them: one U+FFFD per bad sequence,
// lines cut at LF alone, so a CR stays in its column.
//
// A width under minWidth is an error. Python raises IndexError there only once it reaches a row,
// and slices a negative width from the end; no caller passes either.
func (r Findings) FindingRows(path string, outcomes []string, width int) ([][]string, error) {
	value, ok := os.LookupEnv(reviewersVar)
	if !ok {
		return nil, ErrNoReviewers
	}
	if width < minWidth {
		return nil, fmt.Errorf("a findings read needs a width of %d or more, not %d", minWidth, width)
	}
	if outcomes == nil {
		outcomes = readOutcomes
	}
	reviewers := append(strings.FieldsFunc(value, pySpace), unknownReviewer)
	if _, err := r.Store.Stat(path); err != nil {
		return nil, nil
	}
	data, err := r.Store.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var rows [][]string
	for _, line := range strings.Split(pytext.DecodeReplace(data), "\n") {
		f := strings.Split(line, "\t")
		if len(f) < minCols {
			continue
		}
		f = pad(f[:min(len(f), maxCols)], width)
		if slices.Contains(outcomes, f[4]) && slices.Contains(reviewers, f[5]) { // outcome-scan: ok findings.tsv's outcome, not events.tsv's
			rows = append(rows, f)
		}
	}
	return rows, nil
}

// FixedRows is fixed_rows(path): the first four columns of each fixed or escaped row FindingRows
// keeps at its default width.
func (r Findings) FixedRows(path string) ([][]string, error) {
	rows, err := r.FindingRows(path, fixedOutcomes, minWidth)
	for i, f := range rows {
		rows[i] = f[:minCols]
	}
	return rows, err
}

// pad is Python's (f + ["fixed", "unknown"][len(f) - 4:] + ["", ""])[:width] for a row of minCols to
// maxCols columns, in a new slice.
func pad(f []string, width int) []string {
	row := slices.Clone(f)
	if k := len(row) - minCols; k < len(defaults) {
		row = append(row, defaults[k:]...)
	}
	row = append(row, make([]string, emptyCols)...)
	return row[:min(len(row), width)]
}

// pySpace is what Python's str.split() with no argument splits at: Go's unicode.IsSpace and the
// four separators U+001C to U+001F, which Python counts as whitespace and Go does not.
func pySpace(r rune) bool {
	return unicode.IsSpace(r) || (r >= '\x1c' && r <= '\x1f')
}
