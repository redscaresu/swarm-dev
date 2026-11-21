// Package redproof is a throwaway rules package that imports what a rules package may not, to show
// the import check fails it. Never merge it.
package redproof

import (
	"net"
	"os/exec"

	"github.com/redscaresu/swarm-dev/internal/adapter/gh"
)

// Uses keeps each import used.
var Uses = []any{exec.Command, net.Dial, gh.Host{}}
