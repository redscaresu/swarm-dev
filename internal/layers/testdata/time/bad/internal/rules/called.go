package rules

import "time"

// Each call reads the time; the allowed names beside them add no finding.
func called() {
	_ = time.Now()
	_ = time.Since(time.Time{})
	_ = time.Until(time.Time{})
	time.Sleep(time.Second)
	<-time.After(time.Second)
	time.AfterFunc(time.Second, func() {})
	<-time.Tick(time.Second)
	_ = time.NewTicker(time.Second)
	_ = time.NewTimer(time.Second)
	_, _ = time.LoadLocation("UTC")
}
