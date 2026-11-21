package clean

import (
	"context"
	"time"
)

// Timeout is a Duration; a deadline from it runs on the real clock and is not a read.
const Timeout time.Duration = 5 * time.Second

// Epoch builds times from numbers, which reads no clock.
func Epoch(sec int64) (time.Time, time.Time) {
	return time.Unix(sec, 0), time.Date(2026, time.January, 2, 0, 0, 0, 0, time.UTC)
}

// Bounded gives ctx a deadline of Timeout.
func Bounded(ctx context.Context) (context.Context, context.CancelFunc) {
	return context.WithTimeout(ctx, Timeout)
}
