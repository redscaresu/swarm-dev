package main

import (
	"fmt"
	"io"
	"strings"

	"github.com/redscaresu/swarm-dev/internal/adapter/git"
	"github.com/redscaresu/swarm-dev/internal/iface"
	"github.com/redscaresu/swarm-dev/internal/merge"
)

// droppedCrash is _dropped-lines' exit when the check fails rather than answers: an error from
// merge.Dropped, or a panic. It is 1, the exit of a Python traceback, with no dropped line on stdout,
// so dropped_lines in bin/lib/merge.sh dies and merge's hold stays unchecked. Go's own exit on a
// panic, 2, would read there as the check's own stop, an answer.
const droppedCrash = 1

// droppedBreaks turns each line break in a failure's text into a space, so the failure is one line.
var droppedBreaks = strings.NewReplacer("\r\n", " ", "\n", " ", "\r", " ")

func init() {
	// dropped_lines in bin/lib/merge.sh runs it in place of the Python helper it replaced.
	register("_dropped-lines", entry{needsFrame: true, run: func(c *call) int { return droppedLines(c, git.Repo{}) }})
}

// droppedLines is the _dropped-lines entry, which dropped_lines in bin/lib/merge.sh runs as
// `binary_run _dropped-lines <repo-dir> <base> <head> [--own <path>] [--merged <sha>:<squash>]... [<merge sha>...]`.
// It runs merge.Dropped with its arguments over repo, which reads <repo-dir> through git and changes
// nothing there. It prints each line the check gives on stdout and exits with the check's code: 0 with
// nothing dropped, 1 with one line per dropped copy, 2 with the one line of a stop. An error or a panic
// prints nothing on stdout and one line on stderr, and exits droppedCrash.
func droppedLines(c *call, repo iface.Repo) (code int) {
	defer func() {
		if p := recover(); p != nil {
			code = droppedFail(c, fmt.Sprintf("the check panicked: %v", p))
		}
	}()
	res, err := merge.Dropped(repo, c.args)
	if err != nil {
		return droppedFail(c, err.Error())
	}
	if len(res.Lines) > 0 {
		if _, err := io.WriteString(c.stdout, strings.Join(res.Lines, "\n")+"\n"); err != nil {
			return droppedFail(c, "cannot print its lines: "+err.Error())
		}
	}
	return res.Code
}

// droppedFail stops the entry as die() does, with why as one line, and gives droppedCrash.
func droppedFail(c *call, why string) int {
	return c.die(droppedCrash, "_dropped-lines: "+droppedBreaks.Replace(why))
}
