package clock

import "time"

// Now is the clock's own read of the time, which the check allows here only.
func Now() time.Time { return time.Now() }

// Sleep waits d on the real clock.
func Sleep(d time.Duration) { time.Sleep(d) }
