// Package merge imports internal/board, a rules package the user does not merge, so go-checks fails.
package merge

import "github.com/redscaresu/swarm-dev/internal/board"

// Name leans on internal/board.
const Name = board.Name
