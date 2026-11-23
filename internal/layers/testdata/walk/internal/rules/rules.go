// Package rules holds the calls TestWalkCalls asserts, so keep its lines where they are.
package rules

import (
	"os/exec"
	"regexp"
	"time"

	"example.com/m/internal/consts"
)

const local = "b+" // a trailing comment

const (
	first = "x"
	again
	count, _ = 2, "y"
)

var loose = regexp.MustCompile(local) /* a block comment */ // the last comment on its line

/* a block comment alone */

// Match calls in a function.
func Match(s string) bool {
	re := regexp.MustCompile(consts.Pattern)
	_ = regexp.QuoteMeta(s)
	_ = regexp.MustCompile(consts.Name)
	_ = time.Duration(consts.Level)
	return re.MatchString(s) && loose.MatchString(s)
}

// Later calls in a function literal, under a parameter that shadows the constant first.
func Later(first string) func() *exec.Cmd {
	return func() *exec.Cmd {
		time.Sleep(time.Second)
		regexp.MustCompile(first)
		regexp.MustCompile((again))
		return &exec.Cmd{Path: local}
	}
}

var _ = exec.Cmd{}
