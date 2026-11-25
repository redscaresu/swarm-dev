package main

import (
	"strconv"

	"github.com/redscaresu/swarm-dev/internal/trust"
)

// trustedArgs is how many arguments _require-trusted takes: <root> <config> <git|>.
const trustedArgs = 3

// trustedInGit is the third argument's value when <root> is a git root, so its ancestors are not
// checked. Any other value, the empty one included, walks the ancestors.
const trustedInGit = "git"

func init() {
	// bash's require_trusted runs it in place of the Python helper it replaced.
	register("_require-trusted", entry{needsFrame: true, run: requireTrusted})
}

// requireTrusted is the _require-trusted entry, which bash's require_trusted (bin/lib/agents.sh) runs
// as `binary_run _require-trusted <root> <config> <git|>`. It reads <config>, a .claude.json, through
// the store, prints nothing, and exits with trust.Decide's code: 0 when Claude Code trusts <root> (or
// the file cannot be read or is not JSON), 1 when it does not. bash dies with its own line on 1. With
// any other number of arguments it exits exitUsage with one line.
func requireTrusted(c *call) int {
	if len(c.args) != trustedArgs {
		return c.die(exitUsage, "_require-trusted takes <root> <config> <git|>, and was given "+
			strconv.Itoa(len(c.args))+" argument(s)")
	}
	root, config, where := c.args[0], c.args[1], c.args[2]
	data, err := c.store.ReadFile(config)
	return trust.Decide(data, err, root, where == trustedInGit)
}
