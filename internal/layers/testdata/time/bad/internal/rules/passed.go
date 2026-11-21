package rules

import "time"

// Each name only passed as a value, never called here.
var passed = []any{
	time.Now,
	time.Since,
	time.Until,
	time.Sleep,
	time.After,
	time.AfterFunc,
	time.Tick,
	time.NewTicker,
	time.NewTimer,
	time.LoadLocation,
	time.LoadLocationFromTZData,
}
