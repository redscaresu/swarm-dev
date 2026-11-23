// Package rules holds the patterns the check allows. TestRegexpFixtures asserts each call by its
// line, so keep the lines where they are.
package rules

import (
	"io/fs"
	"path/filepath"
	"regexp"

	"example.com/m/internal/consts"
)

// Tight builds each pattern from literals, constants and QuoteMeta.
func Tight(v string, fsys fs.FS) {
	_ = regexp.MustCompile(`^a$`)
	_ = regexp.MustCompile(pat)
	_ = regexp.MustCompile(consts.Pattern)
	_ = regexp.MustCompile(regexp.QuoteMeta(v))
	_ = regexp.MustCompile(("^" + regexp.QuoteMeta(v)) + pat + consts.Pattern + "$")
	_, _ = filepath.Glob("*.go")
	_, _ = fs.Glob(fsys, "*.md")
	_ = regexp.MustCompile(v) // loose-match: ok v is one of a fixed table of patterns
}

// QuoteMeta passed as a value is no pattern, so the check does not judge it.
var quote = regexp.QuoteMeta
