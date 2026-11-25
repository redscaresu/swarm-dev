package report

import (
	"fmt"
	"slices"
	"time"

	"github.com/redscaresu/swarm-dev/internal/clock"
)

// The rework rules of bin/lib/report.py (REWORK_DAYS, RELEASE_FILES, rework_settled, rework_of,
// rework_from and rework_unknown): whether a later PR, or an escaped finding, says a merged PR needed
// rework within ReworkDays of its merge. Days are local days (LocalDay), as log-finding dates findings.

// ReworkDays is report.py's REWORK_DAYS: the local days after a PR's merge day in which a fix of it,
// or an escaped finding on it, counts as its rework.
const ReworkDays = 7

// secondsPerDay turns the gap between two of LocalDay's UTC midnights into whole days.
const secondsPerDay = 24 * 60 * 60

// escapedOutcome is the outcome of a log-finding --reviewer escaped row in findings.tsv.
const escapedOutcome = "escaped"

// skippedLine is rework_of's stderr line for the merged PRs whose mergedAt does not parse: how many,
// and the first of them.
const skippedLine = "rework: skipped %d merged PRs whose mergedAt does not parse, as %s"

// ReleaseFiles is report.py's RELEASE_FILES: a release PR changes these files alone, and fixes
// nothing. Each call returns a fresh slice.
func ReleaseFiles() []string {
	return []string{".claude-plugin/plugin.json"}
}

// ReworkSettled is report.py's rework_settled: the local day before which a merge has had all its
// ReworkDays for a fix to come, as YYYY-MM-DD: clock.Today minus ReworkDays. clock.Today's error
// (a pinned now that is no time) is returned.
func ReworkSettled() (string, error) {
	today, err := clock.Today()
	if err != nil {
		return "", err
	}
	return today.AddDate(0, 0, -ReworkDays).Format(time.DateOnly), nil
}

// MergedPR is one merged PR as report.py's merged_prs gives it: its pr_key, its mergedAt as gh gives
// it, its title and body, and the paths it changed (nil when unknown).
type MergedPR struct {
	Key      string
	MergedAt string
	Text     string
	Files    []string
}

// Judge picks the merged PRs ReworkOf judges: every one, as rework_of's judged=None, or those whose
// pr_key is in Keys alone. Its zero value judges none.
type Judge struct {
	Every bool
	Keys  map[string]bool
}

// judges reports whether j judges the PR whose pr_key is key.
func (j Judge) judges(key string) bool {
	return j.Every || j.Keys[key]
}

// mergedAt is a merged PR whose mergedAt parsed: its pr_key, the time and its local day.
type mergedAt struct {
	key       string
	when, day time.Time
}

// ReworkOf is report.py's rework_of: the pr_keys of the merged PRs judge judges that a later PR fixed
// within ReworkDays of their merge day (local days, for both kinds of fix). That is a PR merged after
// it, on that day or up to ReworkDays later, that FixesPR says fixes it (a release PR, one that
// changed ReleaseFiles alone, never does), or a log-finding --reviewer escaped row pointing at it,
// dated 0 to ReworkDays days after its merge day. findings are rows in fixed_rows' order (day, kind,
// pr, text, outcome); a row with no outcome, or whose day is no YYYY-MM-DD, counts for nothing.
// merged is in the order rework_of's dict holds it: a key given twice keeps its first place and its
// last value. A PR with an empty mergedAt is left out. One whose mergedAt does not parse (MergeTime)
// is left out too, and the second result is the one line rework_of prints on stderr for them, with no
// newline, for the caller to print; it is "" when every mergedAt parsed.
func ReworkOf(merged []MergedPR, findings [][]string, judge Judge) (map[string]bool, string) {
	prs := byKey(merged)
	var parsed []mergedAt
	var bad []string
	for _, pr := range prs {
		if pr.MergedAt == "" {
			continue
		}
		when, ok := MergeTime(pr.MergedAt)
		if !ok {
			bad = append(bad, pr.Key)
			continue
		}
		parsed = append(parsed, mergedAt{pr.Key, when, LocalDay(when)})
	}
	text, files := map[string]string{}, map[string][]string{}
	for _, pr := range prs {
		text[pr.Key], files[pr.Key] = pr.Text, pr.Files
	}
	out := map[string]bool{}
	judged := map[string]time.Time{}
	for _, k := range parsed {
		if !judge.judges(k.key) {
			continue
		}
		judged[k.key] = k.day
		for _, j := range parsed {
			if j.key != k.key && !slices.Equal(files[j.key], ReleaseFiles()) && k.when.Before(j.when) &&
				daysBetween(k.day, j.day) <= ReworkDays && FixesPR(text[j.key], k.key, j.key) {
				out[k.key] = true
				break
			}
		}
	}
	for _, f := range findings {
		if len(f) <= 4 || f[4] != escapedOutcome { // outcome-scan: ok findings.tsv's outcome, not events.tsv's
			continue
		}
		key := PRKey(f[2])
		mergeDay, ok := judged[key]
		if !ok {
			continue
		}
		if day, ok := isoDay(f[0]); ok {
			if d := daysBetween(mergeDay, day); d >= 0 && d <= ReworkDays {
				out[key] = true
			}
		}
	}
	if len(bad) == 0 {
		return out, ""
	}
	return out, fmt.Sprintf(skippedLine, len(bad), bad[0])
}

// byKey is merged as a Python dict built from it holds it: each key once, at its first place, with
// its last value.
func byKey(merged []MergedPR) []MergedPR {
	at := map[string]int{}
	var out []MergedPR
	for _, pr := range merged {
		if i, seen := at[pr.Key]; seen {
			out[i] = pr
			continue
		}
		at[pr.Key] = len(out)
		out = append(out, pr)
	}
	return out
}

// daysBetween is the whole days from day a to day b, both midnights in UTC as LocalDay and isoDay
// hold them. It counts by Unix seconds, as time.Sub saturates past 292 years.
func daysBetween(a, b time.Time) int64 {
	return (b.Unix() - a.Unix()) / secondsPerDay
}

// isoDay is s as a day held at midnight UTC, when s is YYYY-MM-DD with ASCII digits and a real date of
// years 1 to 9999. That is what every supported python3's date.fromisoformat reads; Python 3.11 and
// later also read YYYYMMDD and week dates, which isoDay refuses.
func isoDay(s string) (time.Time, bool) {
	if len(s) != dateLen {
		return time.Time{}, false
	}
	year, month, day, ok := isoDate(s)
	if !ok || !validDate(year, month, day) {
		return time.Time{}, false
	}
	return time.Date(year, time.Month(month), day, 0, 0, 0, 0, time.UTC), true
}

// firstDay is the first day Python's date holds, 0001-01-01; a day before it overflows.
var firstDay = time.Date(1, time.January, 1, 0, 0, 0, 0, time.UTC)

// ReworkFrom is report.py's rework_from: the first local merge day outcomes judges rework for, given
// flow's or its own --since, ReworkDays before it so a fix in the window still counts. It is false for
// no --since (0000-00-00 or empty), a since isoDay refuses, or one under ReworkDays after 0001-01-01.
func ReworkFrom(since string) (time.Time, bool) {
	day, ok := isoDay(since)
	if !ok {
		return time.Time{}, false
	}
	from := day.AddDate(0, 0, -ReworkDays)
	if from.Before(firstDay) {
		return time.Time{}, false
	}
	return from, true
}

// The outcomes columns ReworkUnknown reads.
const (
	prColumn       = "pr"
	mergedAtColumn = "merged_at"
	reworkColumn   = "rework"
)

// ReworkUnknown is report.py's rework_unknown: whether outcomes could not judge rework for some PR it
// should have (gh failed, or its list hit its limit). That is when the latest row on a PR (rows are
// outcomes' rows by column, oldest first) merged from ReworkFrom(since), or at any time when that is
// false, to before ReworkSettled, and has an empty rework cell. A row with no pr or a merged_at that
// MergeTime refuses is passed over, and so is one with no rework column. ReworkSettled's error is
// returned, read only once a row's merge day is not before ReworkFrom's, as rework_unknown reads it.
func ReworkUnknown(rows []map[string]string, since string) (bool, error) {
	last := map[string]map[string]string{}
	var order []string
	for _, r := range rows {
		if r[prColumn] == "" {
			continue
		}
		key := PRKey(r[prColumn])
		if _, seen := last[key]; !seen {
			order = append(order, key)
		}
		last[key] = r
	}
	from, bounded := ReworkFrom(since)
	settled := ""
	for _, key := range order {
		r := last[key]
		when, ok := MergeTime(r[mergedAtColumn])
		if !ok {
			continue
		}
		day := LocalDay(when)
		if bounded && day.Before(from) {
			continue
		}
		if settled == "" {
			s, err := ReworkSettled()
			if err != nil {
				return false, err
			}
			settled = s
		}
		if rework, has := r[reworkColumn]; day.Format(time.DateOnly) < settled && has && rework == "" {
			return true, nil
		}
	}
	return false, nil
}
