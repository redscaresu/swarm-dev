package clock

import (
	"errors"
	"fmt"
	"math"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// nowVar pins Now, Today and UTCNow to an instant in epoch seconds, as it pins bin/lib/clock.py.
const nowVar = "SWARM_DASH_NOW"

// scaleVar multiplies the fixed sleeps, as it does for bin/lib/agents.sh's scaled and nap.
const scaleVar = "SWARM_SLEEP_SCALE"

// scalePattern and minScale are bin/swarm.sh's startup check on scaleVar: digits with at most one
// point, and at least a millisecond per second, so no scaled poll becomes a busy one.
var scalePattern = regexp.MustCompile(`^[0-9]*\.?[0-9]+$`)

const minScale = 0.001

// defaultScale is the scale when scaleVar is unset or empty: the sleeps as written.
const defaultScale = 1.0

// minSleep is Scaled's floor, as agents.sh's scaled has it: no scaled sleep is shorter.
const minSleep = 100 * time.Millisecond

// Now is the instant nowVar names in epoch seconds, fraction kept, when it is set and not empty, and
// the real clock otherwise. A value that is not a finite number of seconds that fits an int64 is an
// error. It reads the value with strconv.ParseFloat, which differs from Python's float(): it refuses
// spaces and non-ASCII digits and takes hex floats, and Now refuses inf and nan, which clock.py's
// now() returns.
func Now() (time.Time, error) {
	v := os.Getenv(nowVar)
	if v == "" {
		return time.Now(), nil
	}
	secs, err := strconv.ParseFloat(v, 64)
	if err != nil || math.IsInf(secs, 0) || math.IsNaN(secs) || secs < math.MinInt64 || secs >= math.MaxInt64 {
		return time.Time{}, fmt.Errorf("%s: '%s' is not a number of epoch seconds", nowVar, v)
	}
	whole := math.Floor(secs)
	return time.Unix(int64(whole), int64(math.Round((secs-whole)*float64(time.Second)))), nil
}

// Today is Now's day in time.Local, as clock.py's today() is the local day of now(). Like Python's
// date it is a day with no zone, held at midnight UTC: a local midnight can fall in a DST gap, where
// time.Date would move it to the day before.
func Today() (time.Time, error) {
	t, err := Now()
	if err != nil {
		return time.Time{}, err
	}
	y, m, d := t.In(time.Local).Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC), nil
}

// UTCNow is Now in UTC, as clock.py's utc_now() is.
func UTCNow() (time.Time, error) {
	t, err := Now()
	if err != nil {
		return time.Time{}, err
	}
	return t.UTC(), nil
}

// Real is the real clock, whatever nowVar says: for deadlines and ages, which must run on real time
// even under a test's pin. Every other package reads the time through this one.
func Real() time.Time {
	return time.Now()
}

// Scale is scaleVar as a number, or defaultScale when it is unset or empty. A value that fails
// bin/swarm.sh's check is an error with its message, word for word. One so long that it overflows a
// float64 fails here too, though awk's check would pass it as inf.
func Scale() (float64, error) {
	v := os.Getenv(scaleVar)
	if v == "" {
		return defaultScale, nil
	}
	k, err := strconv.ParseFloat(v, 64)
	if !scalePattern.MatchString(v) || err != nil || k < minScale {
		return 0, fmt.Errorf("%s: '%s' is not a number of at least %g", scaleVar, v, minScale)
	}
	return k, nil
}

// Scaled is seconds times Scale, rounded to the millisecond as awk's printf "%.3f" rounds it, and at
// least minSleep, as agents.sh's scaled is. A bad scale is Scale's error.
func Scaled(seconds float64) (time.Duration, error) {
	k, err := Scale()
	if err != nil {
		return 0, err
	}
	t := seconds * k
	if t < minSleep.Seconds() {
		t = minSleep.Seconds()
	}
	// FormatFloat rounds the float's exact value, ties to even, as C's printf does; the digits with the
	// point taken out are the milliseconds.
	ms, err := strconv.ParseInt(strings.Replace(strconv.FormatFloat(t, 'f', 3, 64), ".", "", 1), 10, 64)
	if err != nil || ms > math.MaxInt64/int64(time.Millisecond) {
		return 0, errors.New("clock: " + strconv.FormatFloat(seconds, 'g', -1, 64) + " s scaled is too long a sleep")
	}
	return time.Duration(ms) * time.Millisecond, nil
}

// Nap sleeps Scaled(seconds), as agents.sh's nap does, and returns Scaled's error without sleeping.
func Nap(seconds float64) error {
	d, err := Scaled(seconds)
	if err != nil {
		return err
	}
	time.Sleep(d)
	return nil
}
