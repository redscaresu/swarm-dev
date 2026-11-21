package layers

import (
	"fmt"
	"slices"
	"strings"
	"testing"
)

// timePath is the import path of the standard time package.
const timePath = "time"

// allowedTime is every name of time a package but the clock may select: the types, the constants
// and the functions that build a time or a zone from values, none of which reads the clock. A name
// not here fails, called or only passed, so a name Go adds to time later fails until someone lists
// it. LoadLocation is left off, as it reads the zone files. A context deadline is not a read: it
// runs on the real clock, as bin/lib/clock.py leaves time.time() to deadlines.
var allowedTime = []string{
	// The types.
	"Duration", "Location", "Month", "ParseError", "Time", "Weekday",
	// The units.
	"Nanosecond", "Microsecond", "Millisecond", "Second", "Minute", "Hour",
	// The layouts.
	"Layout", "ANSIC", "UnixDate", "RubyDate", "RFC822", "RFC822Z", "RFC850", "RFC1123", "RFC1123Z",
	"RFC3339", "RFC3339Nano", "Kitchen", "Stamp", "StampMilli", "StampMicro", "StampNano",
	"DateTime", "DateOnly", "TimeOnly",
	// The months.
	"January", "February", "March", "April", "May", "June", "July", "August", "September",
	"October", "November", "December",
	// The days.
	"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
	// The functions and values that build a time or a zone from values.
	"Date", "FixedZone", "Local", "Parse", "ParseDuration", "ParseInLocation", "Unix", "UnixMicro",
	"UnixMilli", "UTC",
}

// timeFinding is one use of time the rule fails.
type timeFinding struct {
	file string // the file's slash path relative to the root
	line int
	pkg  string // the package that uses time
	use  string // what the file does: "calls time.Now", "uses time.Now" or "dot-imports time"
	why  string
}

func (f timeFinding) String() string {
	return fmt.Sprintf("%s:%d: %s %s: %s", f.file, f.line, f.pkg, f.use, f.why)
}

// The reasons a timeFinding gives.
const (
	whyTimeName = "not on time's allowed names; only " + clockDir + " may read the time"
	whyTimeDot  = "a dot import of time, which hides its names from this check"
)

// selectorUse is how a finding names a selector on time: "calls time.X" where X is called, and
// "uses time.X" where it is only passed or read.
func selectorUse(s selectorRecord) string {
	if s.called {
		return "calls time." + s.name
	}
	return "uses time." + s.name
}

// timeFindings applies the time rule to the walk's records. In every package but the clock,
// adapters and wiring included, a dot import of time fails, and so does a selector on time, under
// any import name, whose name is not on allowedTime.
func timeFindings(records []fileRecord) []timeFinding {
	var found []timeFinding
	for _, r := range records {
		if r.class.kind == kindClock {
			continue
		}
		for _, imp := range r.imports {
			if imp.path == timePath && imp.kind == importDot {
				found = append(found, timeFinding{file: r.path, line: imp.line, pkg: r.pkg, use: "dot-imports time", why: whyTimeDot})
			}
		}
		for _, s := range r.selectors {
			if s.path == timePath && !slices.Contains(allowedTime, s.name) {
				found = append(found, timeFinding{file: r.path, line: s.line, pkg: r.pkg, use: selectorUse(s), why: whyTimeName})
			}
		}
	}
	return found
}

// clockReads lists, as "file:line: calls time.X", each selector on time in the clock that is not on
// allowedTime: the reads the rule allows there and nowhere else.
func clockReads(records []fileRecord) []string {
	var reads []string
	for _, r := range records {
		if r.class.kind != kindClock {
			continue
		}
		for _, s := range r.selectors {
			if s.path == timePath && !slices.Contains(allowedTime, s.name) {
				reads = append(reads, fmt.Sprintf("%s:%d: %s", r.path, s.line, selectorUse(s)))
			}
		}
	}
	return reads
}

// timeFindingLines is each finding as its String, in the walk's order.
func timeFindingLines(found []timeFinding) []string {
	lines := make([]string, 0, len(found))
	for _, f := range found {
		lines = append(lines, f.String())
	}
	return lines
}

// TestTimeFixtures asserts the exact findings on the fixture trees under testdata/time/, written out
// here. bad/ calls each of ten names that read the time and passes each as a value, uses an aliased
// time, dot-imports time in an adapter and reads the time in an adapter, the interfaces and wiring.
// clean/ uses Duration, Unix, Date and a context deadline, and its clock reads the time: it has no
// finding.
func TestTimeFixtures(t *testing.T) {
	m := fixtureModule
	rules := m + "/internal/rules"
	banned := []string{"Now", "Since", "Until", "Sleep", "After", "AfterFunc", "Tick", "NewTicker", "NewTimer", "LoadLocation"}
	want := []string{
		"cmd/app/main.go:8: " + m + "/cmd/app calls time.Now: " + whyTimeName,
		"internal/adapter/gh/gh.go:3: " + m + "/internal/adapter/gh dot-imports time: " + whyTimeDot,
		"internal/adapter/git/git.go:5: " + m + "/internal/adapter/git calls time.Sleep: " + whyTimeName,
		"internal/iface/iface.go:5: " + m + "/internal/iface calls time.Now: " + whyTimeName,
		"internal/rules/alias.go:5: " + rules + " calls time.Since: " + whyTimeName,
		"internal/rules/alias.go:5: " + rules + " calls time.Now: " + whyTimeName,
	}
	for i, name := range banned {
		want = append(want, fmt.Sprintf("internal/rules/called.go:%d: %s calls time.%s: %s", 7+i, rules, name, whyTimeName))
	}
	for i, name := range append(banned, "LoadLocationFromTZData") {
		want = append(want, fmt.Sprintf("internal/rules/passed.go:%d: %s uses time.%s: %s", 7+i, rules, name, whyTimeName))
	}
	if got := timeFindingLines(timeFindings(walkFixture(t, "time/bad"))); !slices.Equal(got, want) {
		t.Errorf("findings on time/bad:\n got %s\nwant %s", strings.Join(got, "\n     "), strings.Join(want, "\n     "))
	}

	clean := walkFixture(t, "time/clean")
	if len(clean) != 2 {
		t.Errorf("the walk of time/clean found %d files, want 2: the rules package and the clock", len(clean))
	}
	if got := timeFindings(clean); len(got) != 0 {
		t.Errorf("findings on time/clean, want none:\n%s", strings.Join(timeFindingLines(got), "\n"))
	}
	wantReads := []string{"internal/clock/clock.go:6: calls time.Now", "internal/clock/clock.go:9: calls time.Sleep"}
	if got := clockReads(clean); !slices.Equal(got, wantReads) {
		t.Errorf("the clock's reads on time/clean, which the rule allows:\n got %q\nwant %q", got, wantReads)
	}
}

// TestRealTreeTime applies the rule to the module itself. It logs the allowed names, the clock as
// the one package that may read the time and each read the clock makes, and fails when the walk
// finds no file of the clock.
func TestRealTreeTime(t *testing.T) {
	root, module := moduleRoot(t)
	records, err := walk(root, module)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("names of time a package but the clock may use: %s", strings.Join(allowedTime, " "))
	t.Logf("%s is the one package that may read the time", clockDir)
	if !slices.ContainsFunc(records, func(r fileRecord) bool { return r.class.kind == kindClock }) {
		t.Errorf("the walk of %s found no file of %s, the one package that may read the time", root, clockDir)
	}
	for _, read := range clockReads(records) {
		t.Logf("allows %s", read)
	}
	for _, f := range timeFindings(records) {
		t.Error(f)
	}
}
