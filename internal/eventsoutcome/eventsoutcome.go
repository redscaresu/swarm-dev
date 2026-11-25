// Package eventsoutcome reads events.tsv's outcome column (row[4]), which may end in a key=value
// tail. It is the Go copy of bin/lib/events_outcome.py, and compare_test.go runs both over the same
// rows until the Python copy's last importer is ported.
//
// append_event (bin/lib/agents.sh) writes the outcome, then Sep and the fields, space-separated,
// when it has any. It strips Sep from the outcome first, so the first Sep in the column starts the
// tail. Rows written before the tail existed have none and read back whole.
package eventsoutcome

import "strings"

// Sep starts the outcome column's tail. It must equal agents.sh's EVENT_SEP and
// events_outcome.py's SEP; tests/events_test.sh pins the Python's, and compare_test.go the Go's.
const Sep = " ~~ "

// outcomeCol is the index of the outcome column in an events.tsv row.
const outcomeCol = 4

// split returns the outcome column cut at its first Sep: the outcome and the tail, which is ""
// when the column has no Sep. A row of outcomeCol columns or fewer has an empty column.
func split(row []string) (outcome, tail string) {
	col := ""
	if len(row) > outcomeCol {
		col = row[outcomeCol]
	}
	outcome, tail, _ = strings.Cut(col, Sep)
	return outcome, tail
}

// Outcome returns the outcome text without the tail: row[4] for a row with none, and "" for a row
// of 4 columns or fewer.
func Outcome(row []string) string {
	outcome, _ := split(row)
	return outcome
}

// Fields returns the tail's fields, an empty map for a row with none. The tail is split on single
// spaces; a field with no = or an empty key is skipped, a value may be empty, and a later key wins.
func Fields(row []string) map[string]string {
	_, tail := split(row)
	out := map[string]string{}
	for _, pair := range strings.Split(tail, " ") {
		key, value, eq := strings.Cut(pair, "=")
		if eq && key != "" {
			out[key] = value
		}
	}
	return out
}
