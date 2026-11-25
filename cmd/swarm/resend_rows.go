package main

import (
	"fmt"
	"io"
	"strconv"
	"strings"

	"github.com/redscaresu/swarm-dev/internal/resend"
)

// resendRowsArgs is how many arguments _resend-rows takes:
// <events> <resent> <briefs> <panes> <backlog> <name-max>.
const resendRowsArgs = 6

// resendRowsUsage names _resend-rows' arguments in its usage line.
const resendRowsUsage = "_resend-rows takes <events> <resent> <briefs> <panes> <backlog> <name-max>"

// markerGlob matches the .unsent markers in the briefs folder.
const markerGlob = "*.unsent"

func init() {
	// resend_pass (bin/lib/lifecycle.sh) will run it in place of its inline Python program.
	register("_resend-rows", entry{needsFrame: true, run: resendRows})
}

// resendRows is the _resend-rows entry, the row program of resend_pass: it reads herdr's agent list on
// stdin, <events> (events.tsv), <resent> (LEAD_RESENT) and each .unsent marker in <briefs>, and prints
// resend.Rows' rows, one per line. <panes> is own_panes' output, <backlog> the backlog conductor's name
// and <name-max> AGENT_NAME_MAX. It removes the markers Rows names, ignoring a failed removal. Where
// the program failed as a whole (a list that is not herdr's JSON, a marker or resent file that is not
// UTF-8), it prints no row and exits 1 with one line, so the caller's `|| return 0` holds. With any
// other number of arguments, or a <name-max> that is not a whole number, it exits exitUsage.
//
// The markers are read in sorted order, where Python's glob gave the folder's own order: that decides
// only which marker names an agent's stem when two idle markers name it, and which markers were
// removed before a failing one.
func resendRows(c *call) int {
	if len(c.args) != resendRowsArgs {
		return c.die(exitUsage, resendRowsUsage+", and was given "+strconv.Itoa(len(c.args))+" argument(s)")
	}
	events, resent, briefs, panes := c.args[0], c.args[1], c.args[2], c.args[3]
	backlog, max := c.args[4], c.args[5] // outcome-scan: ok c.args[4] is the <backlog> argument; this line reads no file's column
	nameMax, err := strconv.Atoi(max)
	if err != nil || nameMax < 0 {
		return c.die(exitUsage, "_resend-rows: <name-max> takes a whole number, not '"+max+"'")
	}
	agents, err := io.ReadAll(c.stdin)
	if err != nil {
		return c.die(1, "_resend-rows: reading the agent list: "+err.Error())
	}
	in := resend.Input{
		Agents: agents, Own: panes, Backlog: backlog, NameMax: nameMax,
		Events: c.readFile(events), Resent: c.readFile(resent),
	}
	paths, err := c.store.Glob(briefs, markerGlob)
	if err != nil {
		return c.die(1, "_resend-rows: listing "+briefs+": "+err.Error())
	}
	for _, p := range paths {
		in.Markers = append(in.Markers, c.readFile(p))
	}
	rows, remove, err := resend.Rows(in)
	for _, p := range remove {
		// As the program's os.remove: a marker that is already gone, or cannot go, is left.
		_ = c.store.Remove(p)
	}
	if err != nil {
		return c.die(1, "_resend-rows: "+err.Error())
	}
	if len(rows) > 0 {
		if _, err := fmt.Fprintln(c.stdout, strings.Join(rows, "\n")); err != nil {
			return c.die(1, "_resend-rows: writing the rows: "+err.Error())
		}
	}
	return 0
}

// readFile reads path through the store, keeping the read's error for the rule.
func (c *call) readFile(path string) resend.File {
	data, err := c.store.ReadFile(path)
	return resend.File{Path: path, Data: data, Err: err}
}
