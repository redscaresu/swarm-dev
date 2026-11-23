// Package rules holds one loose pattern of each shape. TestRegexpFixtures asserts each finding by
// its line, so keep the lines where they are.
package rules

import (
	"fmt"
	"io/fs"
	"path"
	"path/filepath"
	"regexp"
	"regexp/syntax"
)

// Loose builds each pattern from v.
func Loose(v, name string, fsys fs.FS) {
	_ = regexp.MustCompile(v)
	_ = regexp.MustCompile("^" + v + "$")
	_ = regexp.MustCompile(fmt.Sprintf("^%s$", v))
	_, _ = path.Match(v, name)
	_, _ = filepath.Match(v, name)
	_, _ = filepath.Glob(v)
	_, _ = fs.Glob(fsys, v)
	_, _ = syntax.Parse(v, syntax.Perl)
	_ = regexp.MustCompile(v) // loose-match: ok
}

// pat is a constant that Shadowed's parameter hides.
const pat = "x"

// Shadowed names pat, but its pat is the parameter.
func Shadowed(pat string) {
	_ = regexp.MustCompile(pat)
}

// compile is regexp.MustCompile as a value, whose calls the check cannot see.
var compile = regexp.MustCompile
