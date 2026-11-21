// Package git is the one implementation of iface.Repo. It runs the git program found on PATH, so the
// tests' stub git keeps working.
package git

import "github.com/redscaresu/swarm-dev/internal/iface"

// Repo reads and changes the repository through git.
type Repo struct{}

var _ iface.Repo = Repo{}
