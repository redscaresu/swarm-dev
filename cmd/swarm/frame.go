package main

import (
	"fmt"
	"io"
	"sort"
	"strconv"
	"strings"

	"github.com/redscaresu/swarm-dev/internal/iface"
)

// The frame stays bash: bin/swarm.sh resolves the project, the board and the settings, then hands
// them to the binary in these variables, set only for the binary's run. Each setting <key> comes as
// SWARMDEV_CFG_<key> (its value) and SWARMDEV_SRC_<key> (where the value came from). The binary keeps
// no list of the keys: it reads every SWARMDEV_CFG_ name it finds.
const (
	envHome       = "SWARMDEV_HOME"
	envProject    = "SWARMDEV_PROJECT"
	envBoard      = "SWARMDEV_BOARD"
	envDieFile    = "SWARMDEV_DIE_FILE"
	envFieldsFile = "SWARMDEV_FIELDS_FILE"
	envCfgPrefix  = "SWARMDEV_CFG_"
	envSrcPrefix  = "SWARMDEV_SRC_"
)

// fieldSpace is what bash's [[:space:]] matches in the C locale, the whitespace event_fields turns
// into _.
const fieldSpace = " \t\n\v\f\r"

// setting is one setting the frame hands over.
type setting struct {
	key, value, source string
}

// frame is what bin/swarm.sh hands the binary. project is empty when no frame was handed over.
type frame struct {
	home, project, board string
	dieFile, fieldsFile  string    // empty: the run records no outcome line or fields
	settings             []setting // sorted by key
}

// readFrame reads the frame from environ, a list of name=value strings as os.Environ gives.
func readFrame(environ []string) frame {
	env := make(map[string]string, len(environ))
	for _, kv := range environ {
		if k, v, ok := strings.Cut(kv, "="); ok {
			env[k] = v
		}
	}
	f := frame{
		home: env[envHome], project: env[envProject], board: env[envBoard],
		dieFile: env[envDieFile], fieldsFile: env[envFieldsFile],
	}
	for k, v := range env {
		if key, ok := strings.CutPrefix(k, envCfgPrefix); ok && key != "" {
			f.settings = append(f.settings, setting{key: key, value: v, source: env[envSrcPrefix+key]})
		}
	}
	sort.Slice(f.settings, func(i, j int) bool { return f.settings[i].key < f.settings[j].key })
	return f
}

// call is one run of an entry: its arguments, its streams, the frame and the store it writes through.
type call struct {
	args           []string
	stdin          io.Reader
	stdout, stderr io.Writer
	frame          frame
	store          iface.Store
}

// die stops the entry as bin/swarm.sh's die() does: msg goes on stderr after "swarm: ", and its first
// line, with no prefix, becomes the die file's only line, which main logs as the command's outcome.
// With no die file it writes no file. It returns code, the run's exit code.
func (c *call) die(code int, msg string) int {
	// The code already says the run failed; a stream or file that fails to take the line cannot change
	// it, and die() ignores both failures too.
	_, _ = fmt.Fprintln(c.stderr, "swarm: "+msg)
	if c.frame.dieFile != "" {
		first, _, _ := strings.Cut(msg, "\n")
		_ = c.store.WriteLine(c.frame.dieFile, first)
	}
	return code
}

// eventFields adds key=value pairs to the fields file, which main appends to the command's events.tsv
// line, as bin/swarm.sh's event_fields does: each value's whitespace becomes _, and an empty value
// is -. With no fields file it does nothing.
func (c *call) eventFields(pairs ...string) {
	if c.frame.fieldsFile == "" {
		return
	}
	lines := make([]string, 0, len(pairs))
	for _, p := range pairs {
		k, v, _ := strings.Cut(p, "=")
		v = strings.Map(func(r rune) rune {
			if strings.ContainsRune(fieldSpace, r) {
				return '_'
			}
			return r
		}, v)
		if v == "" {
			v = "-"
		}
		lines = append(lines, k+"="+v)
	}
	// As in event_fields, a fields file that cannot be written loses the fields, not the command.
	_ = c.store.AppendLines(c.frame.fieldsFile, lines)
}

// entry is one command the binary runs.
type entry struct {
	needsFrame bool // refuses to run with no frame; an entry a hook calls needs none
	fixture    bool // for the tests only, so no marker under bin/ported/ names it
	run        func(c *call) int
}

// entries is the binary's table, by dispatch name. Each entry but a fixture has a marker file
// bin/ported/<name>, which sends bin/swarm.sh's dispatch to the binary.
var entries = map[string]entry{
	"wrapper-fixture": {needsFrame: true, fixture: true, run: wrapperFixture},
}

// wrapperFixture is the wrapper's test entry. It prints the frame's project, board and home, each
// argument, each line of stdin and each setting with its source, one per line in that order. Then,
// told to by its arguments, it writes fields and fails:
//
//	--field <key>=<value>   add the pair to the fields file (repeatable)
//	--fail <code>           exit with code; with --line, fail as die() does
//	--line <line>           the failure's line
func wrapperFixture(c *call) int {
	in, err := io.ReadAll(c.stdin)
	if err != nil {
		return c.die(1, "wrapper-fixture: reading stdin: "+err.Error())
	}
	f := c.frame
	out := []string{"project = " + f.project, "board = " + f.board, "home = " + f.home}
	for _, a := range c.args {
		out = append(out, "arg = "+a)
	}
	if s := strings.TrimSuffix(string(in), "\n"); len(in) > 0 {
		for _, l := range strings.Split(s, "\n") {
			out = append(out, "stdin = "+l)
		}
	}
	for _, s := range f.settings {
		out = append(out, s.key+" = "+s.value+"    ("+s.source+")")
	}
	_, _ = fmt.Fprintln(c.stdout, strings.Join(out, "\n"))
	return fixtureActs(c)
}

// fixtureActs does what wrapper-fixture's arguments tell it to, and returns its exit code.
func fixtureActs(c *call) int {
	code, line := 0, ""
	for i := 0; i < len(c.args); i++ {
		flag := c.args[i]
		if flag != "--field" && flag != "--fail" && flag != "--line" {
			continue
		}
		if i+1 == len(c.args) {
			return c.die(exitUsage, "wrapper-fixture: "+flag+" takes a value")
		}
		i++
		switch v := c.args[i]; flag {
		case "--field":
			c.eventFields(v)
		case "--line":
			line = v
		case "--fail":
			n, err := strconv.Atoi(v)
			if err != nil || n < 1 || n > 255 {
				return c.die(exitUsage, "wrapper-fixture: --fail takes an exit code from 1 to 255, not '"+v+"'")
			}
			code = n
		}
	}
	if code != 0 && line != "" {
		return c.die(code, line)
	}
	return code
}
