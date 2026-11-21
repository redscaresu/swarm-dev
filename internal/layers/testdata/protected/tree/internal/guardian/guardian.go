// Package guardian shares internal/guard's first letters but is not under internal/guard/, so the
// protected rule does not judge its import of internal/board.
package guardian

import "example.com/m/internal/board"

// Name is the board's name.
const Name = board.Name
