package clock

import (
	"os"
	"testing"
	"time"
	_ "time/tzdata" // the zone database, so TestTodayAcrossSkippedMidnight runs on any machine
)

const (
	pinVar   = "SWARM_DASH_NOW"
	scaleEnv = "SWARM_SLEEP_SCALE"
	// pin is 2023-11-14 22:13:20 UTC, already 2023-11-15 at UTC+14.
	pin = 1700000000
)

// withLocal sets time.Local to zone for the test and puts it back after. Go reads TZ once per
// process, so t.Setenv("TZ") would not reach the clock; no test that calls it may run in parallel.
func withLocal(t *testing.T, zone *time.Location) {
	t.Helper()
	saved := time.Local
	time.Local = zone
	t.Cleanup(func() { time.Local = saved })
}

// between fails unless got is no earlier than before and no later than after.
func between(t *testing.T, what string, before, got, after time.Time) {
	t.Helper()
	if got.Before(before) || got.After(after) {
		t.Errorf("%s = %v, not between the real clock's %v and %v", what, got, before, after)
	}
}

// If Today used UTC, or Now dropped the pin, the days here would be wrong.
func TestPinnedDays(t *testing.T) {
	withLocal(t, time.FixedZone("UTC+14", 14*60*60))
	t.Setenv(pinVar, "1700000000")
	now, err := Now()
	if err != nil || !now.Equal(time.Unix(pin, 0)) {
		t.Errorf("Now() = %v, %v; want %v", now, err, time.Unix(pin, 0))
	}
	today, err := Today()
	if got := today.Format(time.DateTime); err != nil || got != "2023-11-15 00:00:00" || today.Location() != time.UTC {
		t.Errorf("Today() = %q in %v, %v; want 2023-11-15 00:00:00, held in UTC", got, today.Location(), err)
	}
	utc, err := UTCNow()
	if got := utc.Format(time.DateOnly); err != nil || got != "2023-11-14" || utc.Location() != time.UTC || !utc.Equal(now) {
		t.Errorf("UTCNow() = %v, %v; want %v on 2023-11-14 in UTC", utc, err, now)
	}
}

// If Today built the local midnight with time.Date, a day whose midnight a DST jump skips would read
// as the day before: Santiago's clocks went from 00:00 to 01:00 on 2026-09-06.
func TestTodayAcrossSkippedMidnight(t *testing.T) {
	zone, err := time.LoadLocation("America/Santiago") // from time/tzdata, so no zone files are needed
	if err != nil {
		t.Fatal(err)
	}
	withLocal(t, zone)
	t.Setenv(pinVar, "1788706800") // 2026-09-06 12:00 in Santiago
	if today, err := Today(); err != nil || today.Format(time.DateOnly) != "2026-09-06" {
		t.Errorf("Today() = %v, %v; want 2026-09-06", today, err)
	}
}

// If Now dropped the fraction or misread an exponent, these instants would be off.
func TestPinnedInstants(t *testing.T) {
	for _, c := range []struct {
		pin  string
		want time.Time
	}{
		{"1700000000.5", time.Unix(pin, int64(time.Second/2))},
		{"1.7e9", time.Unix(pin, 0)},
	} {
		t.Setenv(pinVar, c.pin)
		if got, err := Now(); err != nil || !got.Equal(c.want) {
			t.Errorf("with %s=%s, Now() = %v, %v; want %v", pinVar, c.pin, got, err, c.want)
		}
	}
}

// If Real read the pin, or an empty pin read as 0, Now would not be on the real clock.
func TestRealClock(t *testing.T) {
	t.Setenv(pinVar, "1700000000")
	before := time.Now()
	r := Real()
	between(t, "Real() under a pin", before, r, time.Now())

	t.Setenv(pinVar, "")
	before = time.Now()
	now, err := Now()
	if err != nil {
		t.Fatalf("with %s empty, Now() failed: %v", pinVar, err)
	}
	between(t, "Now() with the pin empty", before, now, time.Now())
}

// If Now took a non-number as 0 or the real clock, a test's pin typo would go unseen.
func TestBadPin(t *testing.T) {
	for _, v := range []string{"abc", "1e400", "1e19"} {
		t.Setenv(pinVar, v)
		_, err := Now()
		want := pinVar + ": '" + v + "' is not a number of epoch seconds"
		if err == nil || err.Error() != want {
			t.Errorf("with %s=%q, Now() error = %v; want %q", pinVar, v, err, want)
		}
		if _, err := Today(); err == nil {
			t.Errorf("with %s=%q, Today() did not fail", pinVar, v)
		}
		if _, err := UTCNow(); err == nil {
			t.Errorf("with %s=%q, UTCNow() did not fail", pinVar, v)
		}
	}
}

// Now reads the pin with strconv.ParseFloat, where bin/lib/clock.py uses Python's float(). Each row
// says what Python's float() gives, so a change on either side shows here; the byte comparison with
// clock.py itself is the differential run's.
func TestPinParsing(t *testing.T) {
	var fails time.Time // a want that means "Now fails"
	for _, c := range []struct {
		pin    string
		want   time.Time // the instant Now gives, or fails
		python string    // what Python's float() gives
	}{
		// The same as float(): integers, decimals, signs, exponents and underscores between digits.
		{"1700000000", time.Unix(pin, 0), "1700000000.0"},
		{"+1700000000", time.Unix(pin, 0), "1700000000.0"},
		{"-1.5", time.Unix(-2, int64(time.Second/2)), "-1.5"},
		{"1700000000.25", time.Unix(pin, int64(time.Second/4)), "1700000000.25"},
		{"1700000000.", time.Unix(pin, 0), "1700000000.0"},
		{".5", time.Unix(0, int64(time.Second/2)), "0.5"},
		{"17E8", time.Unix(pin, 0), "1700000000.0"},
		{"1.7e+9", time.Unix(pin, 0), "1700000000.0"},
		{"1_700_000_000", time.Unix(pin, 0), "1700000000.0"},
		{"1_700.5_5", time.Unix(1700, 550*int64(time.Millisecond)), "1700.55"},
		{"_1700", fails, "ValueError"},
		{"1700_", fails, "ValueError"},
		{"17__00", fails, "ValueError"},
		// Different: Go takes hex floats, which float() refuses. float() strips spaces, takes any
		// Unicode digit, and gives inf and nan, which no time.Time can hold.
		{"0x1p30", time.Unix(1<<30, 0), "ValueError"},
		{" 1700000000", fails, "1700000000.0"},
		{"1700000000\n", fails, "1700000000.0"},
		{"١٧٠٠", fails, "1700.0"},
		{"inf", fails, "inf"},
		{"-Infinity", fails, "-inf"},
		{"nan", fails, "nan"},
	} {
		t.Setenv(pinVar, c.pin)
		got, err := Now()
		switch {
		case c.want == fails && err == nil:
			t.Errorf("with %s=%q (float() gives %s), Now() = %v; want an error", pinVar, c.pin, c.python, got)
		case c.want != fails && (err != nil || !got.Equal(c.want)):
			t.Errorf("with %s=%q (float() gives %s), Now() = %v, %v; want %v", pinVar, c.pin, c.python, got, err, c.want)
		}
	}
}

// If Scale's check drifted from bin/swarm.sh's, a scale the bash refuses would run here, or the
// other way round.
func TestScale(t *testing.T) {
	for _, c := range []struct {
		v    string
		want float64
	}{
		{"0.01", 0.01}, {"5", 5}, {".5", 0.5}, {"0.001", 0.001}, {"", 1},
	} {
		t.Setenv(scaleEnv, c.v)
		if got, err := Scale(); err != nil || got != c.want {
			t.Errorf("with %s=%q, Scale() = %v, %v; want %v", scaleEnv, c.v, got, err, c.want)
		}
	}
	for _, v := range []string{"5.", "1e-2", "+1", "inf", "NaN", "0", "0.0009", " 1", "1_0", "-1"} {
		t.Setenv(scaleEnv, v)
		_, err := Scale()
		want := "SWARM_SLEEP_SCALE: '" + v + "' is not a number of at least 0.001"
		if err == nil || err.Error() != want {
			t.Errorf("with %s=%q, Scale() error = %v; want %q", scaleEnv, v, err, want)
		}
		if _, err := Scaled(1); err == nil || err.Error() != want {
			t.Errorf("with %s=%q, Scaled(1) error = %v; want %q", scaleEnv, v, err, want)
		}
	}
}

// TestScaleUnset is apart from TestScale, as t.Setenv cannot unset a name.
func TestScaleUnset(t *testing.T) {
	t.Setenv(scaleEnv, "")
	if err := os.Unsetenv(scaleEnv); err != nil {
		t.Fatal(err)
	}
	if got, err := Scale(); err != nil || got != 1 {
		t.Errorf("with %s unset, Scale() = %v, %v; want 1", scaleEnv, got, err)
	}
	if got, err := Scaled(30); err != nil || got != 30*time.Second {
		t.Errorf("with %s unset, Scaled(30) = %v, %v; want 30s", scaleEnv, got, err)
	}
}

// If Scaled lost its floor or rounded other than awk's %.3f, a scaled poll would differ from the bash.
func TestScaled(t *testing.T) {
	for _, c := range []struct {
		scale   string
		seconds float64
		want    time.Duration
	}{
		{"0.01", 30, 300 * time.Millisecond},
		{"0.01", 1, 100 * time.Millisecond},   // the floor
		{"0.01", 0, 100 * time.Millisecond},   // the floor
		{"0.1236", 1, 124 * time.Millisecond}, // rounded up to the millisecond
		{"0.3125", 1, 312 * time.Millisecond}, // an exact tie, to even, as awk prints it
		{"0.1875", 1, 188 * time.Millisecond}, // an exact tie, to even
		{"2", 1.5, 3 * time.Second},
	} {
		t.Setenv(scaleEnv, c.scale)
		if got, err := Scaled(c.seconds); err != nil || got != c.want {
			t.Errorf("at scale %s, Scaled(%v) = %v, %v; want %v", c.scale, c.seconds, got, err, c.want)
		}
	}
}

// If Nap skipped the sleep or slept it unscaled, its time would fall outside these bounds.
func TestNap(t *testing.T) {
	t.Setenv(scaleEnv, "0.01")
	start := time.Now()
	if err := Nap(1); err != nil {
		t.Fatalf("Nap(1) at scale 0.01 failed: %v", err)
	}
	if slept := time.Since(start); slept < 100*time.Millisecond || slept >= time.Second {
		t.Errorf("Nap(1) at scale 0.01 slept %v; want at least 100ms and less than 1s", slept)
	}
	t.Setenv(scaleEnv, "0")
	start = time.Now()
	if err := Nap(1); err == nil || time.Since(start) >= minSleep {
		t.Errorf("Nap(1) at scale 0 = %v after %v; want an error at once", err, time.Since(start))
	}
}
