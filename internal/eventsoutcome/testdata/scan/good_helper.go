package scan

import "github.com/redscaresu/swarm-dev/internal/eventsoutcome"

// helper reads the column through the parser.
func helper(row []string) bool {
	return eventsoutcome.Outcome(row) == "ok"
}
