package clock

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// failed is the one token either side prints for a call that fails, whatever the error.
const failed = "error"

// pythonTimeout bounds one python3 run, so a hung interpreter fails the test instead of stalling it.
const pythonTimeout = 30 * time.Second

// comparedPython prints, for each pin in argv[2:], one line: now() as "%.9f", today() as an ISO date
// and utc_now() with its microseconds and offset, each field the failed token when its call raises.
// argv[1] is bin/lib, since -I leaves the script's directory off sys.path.
const comparedPython = `import os, sys
sys.path.insert(0, sys.argv[1])
import clock

def field(call, show):
    try:
        return show(call())
    except Exception:
        return "` + failed + `"

for pin in sys.argv[2:]:
    os.environ["SWARM_DASH_NOW"] = pin
    print("\t".join([
        field(clock.now, lambda x: "%.9f" % x),
        field(clock.today, lambda d: d.isoformat()),
        field(clock.utc_now, lambda d: d.strftime("%Y-%m-%dT%H:%M:%S.%f%z")),
    ]))
`

// todayPython prints today() alone, with the pin unset.
const todayPython = `import sys
sys.path.insert(0, sys.argv[1])
import clock
print(clock.today().isoformat())
`

// utcLayout is the Go layout of comparedPython's utc_now() format. Go truncates to the microsecond
// where Python rounds; no pin here has a fraction finer than that.
const utcLayout = "2006-01-02T15:04:05.000000-0700"

// pythonClock runs script with python3 -I under the zone, SWARM_DASH_NOW taken out of its
// environment, and returns what it printed.
func pythonClock(t *testing.T, zone, script string, pins ...string) string {
	t.Helper()
	py, err := exec.LookPath("python3")
	if err != nil {
		t.Fatalf("python3 is not on PATH, so clock.py cannot be compared: %v", err)
	}
	lib, err := filepath.Abs(filepath.Join("..", "..", "bin", "lib"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(lib, "clock.py")); err != nil {
		t.Fatalf("no clock.py to compare against: %v", err)
	}
	env := []string{"TZ=" + zone}
	for _, kv := range os.Environ() {
		if !strings.HasPrefix(kv, pinVar+"=") && !strings.HasPrefix(kv, "TZ=") {
			env = append(env, kv)
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), pythonTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, py, append([]string{"-I", "-c", script, lib}, pins...)...)
	cmd.Env = env
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("python3 under TZ=%s failed: %v", zone, err)
	}
	return string(out)
}

// epochSeconds is t as signed epoch seconds to the nanosecond, the digits Python's "%.9f" prints for
// now() when t is that float rounded to the nanosecond.
func epochSeconds(t time.Time) string {
	ns := t.UnixNano()
	sign := ""
	if ns < 0 {
		sign, ns = "-", -ns
	}
	return fmt.Sprintf("%s%d.%09d", sign, ns/int64(time.Second), ns%int64(time.Second))
}

// goClock is comparedPython's output for the pins, from Now, Today and UTCNow in time.Local.
func goClock(t *testing.T, pins ...string) string {
	t.Helper()
	var b strings.Builder
	for _, pin := range pins {
		t.Setenv(pinVar, pin)
		fields := []string{failed, failed, failed}
		if now, err := Now(); err == nil {
			fields[0] = epochSeconds(now)
		}
		if today, err := Today(); err == nil {
			fields[1] = today.Format(time.DateOnly)
		}
		if utc, err := UTCNow(); err == nil {
			fields[2] = utc.Format(utcLayout)
		}
		b.WriteString(strings.Join(fields, "\t") + "\n")
	}
	return b.String()
}

// sameLines fails on each pin whose line differs between the two outputs, and on outputs whose line
// counts differ.
func sameLines(t *testing.T, zone string, pins []string, goOut, pyOut string) {
	t.Helper()
	if goOut == pyOut {
		return
	}
	g, p := strings.Split(goOut, "\n"), strings.Split(pyOut, "\n")
	if len(g) != len(p) {
		t.Errorf("under TZ=%s, Go printed %d lines and clock.py %d:\nGo:\n%sclock.py:\n%s", zone, len(g), len(p), goOut, pyOut)
		return
	}
	for i := range g {
		if g[i] != p[i] {
			t.Errorf("under TZ=%s with %s=%q:\n  Go       %s\n  clock.py %s", zone, pinVar, pins[i], g[i], p[i])
		}
	}
}

// If Now, Today or UTCNow read a pin other than clock.py's now(), today() or utc_now() does, a line
// here differs. The pins are the ones TestPinParsing says float() reads alike or refuses alike; the
// five forms it pins as different (hex, spaces, Unicode digits, inf, nan) are left out on purpose.
// Etc/GMT-14 is UTC+14 with no DST or history, so the 2023 pins' local day there is the day after
// their UTC day.
func TestCompareParsedPins(t *testing.T) {
	const zone = "Etc/GMT-14"
	pins := []string{
		"1700000000", "+1700000000", "-1.5", "1700000000.25", "1700000000.", ".5", "17E8", "1.7e+9",
		"1_700_000_000", "1_700.5_5",
		"_1700", "1700_", "17__00",
	}
	loc, err := time.LoadLocation(zone) // from time/tzdata, which clock_test.go links in
	if err != nil {
		t.Fatal(err)
	}
	withLocal(t, loc)
	sameLines(t, zone, pins, goClock(t, pins...), pythonClock(t, zone, comparedPython, pins...))
}

// If Today or today() took the UTC day, or either moved a day across a DST change, a line here
// differs. Each instant is a second either side of a 2024 change, or late enough in the local day
// that the UTC day is the next or the one before.
func TestCompareDaysAcrossDST(t *testing.T) {
	for _, c := range []struct {
		zone string
		pins []string
	}{
		// 03-10 01:59:59 EST and 03:00 EDT; 03-10 23:30 EDT is 03-11 in UTC. 11-03 01:30 EDT and
		// 01:30 EST; 11-03 23:30 EST is 11-04 in UTC.
		{"America/New_York", []string{"1710053999", "1710054000", "1710127800", "1730611800", "1730615400", "1730694600"}},
		// 04-07 00:30 AEDT and 02:30 AEST, both 04-06 in UTC; 10-06 01:59:59 AEST and 03:00 AEDT.
		{"Australia/Sydney", []string{"1712410200", "1712421000", "1728143999", "1728144000"}},
		// 09-07 23:59:59 and then 09-08 01:00, the midnight between skipped; 04-06 23:30 twice and
		// then 04-07 00:00, all 04-07 in UTC.
		{"America/Santiago", []string{"1725767999", "1725768000", "1712457000", "1712460600", "1712462400"}},
	} {
		loc, err := time.LoadLocation(c.zone)
		if err != nil {
			t.Fatal(err)
		}
		withLocal(t, loc)
		sameLines(t, c.zone, c.pins, goClock(t, c.pins...), pythonClock(t, c.zone, comparedPython, c.pins...))
	}
}

// If Today or today() dropped the real clock's local day with the pin unset, the days here differ.
// The real clock moves, so the day alone is compared, and Go's day is read before and after Python's
// in case the run crosses midnight.
func TestCompareUnsetToday(t *testing.T) {
	const zone = "Etc/GMT-14"
	loc, err := time.LoadLocation(zone)
	if err != nil {
		t.Fatal(err)
	}
	withLocal(t, loc)
	t.Setenv(pinVar, "")
	if err := os.Unsetenv(pinVar); err != nil {
		t.Fatal(err)
	}
	day := func() string {
		d, err := Today()
		if err != nil {
			t.Fatalf("with %s unset, Today() failed: %v", pinVar, err)
		}
		return d.Format(time.DateOnly)
	}
	before := day()
	py := strings.TrimSuffix(pythonClock(t, zone, todayPython), "\n")
	after := day()
	if py != before && py != after {
		t.Errorf("with %s unset under TZ=%s, today() = %q; Today() was %q before it and %q after", pinVar, zone, py, before, after)
	}
}
