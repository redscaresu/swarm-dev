// Package tmpread is a throwaway rules package that reads the time, for a red go-checks run.
package tmpread

import "time"

// Stamp reads the real clock, which only internal/clock may do.
func Stamp() time.Time { return time.Now() }
