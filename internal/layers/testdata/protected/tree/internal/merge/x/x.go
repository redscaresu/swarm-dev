package x

import (
	"strings"

	"example.com/m/internal/board"
	_ "example.com/m/internal/guardian"
	"example.com/m/internal/iface"
)

// Name leans on internal/board, which the user does not merge.
func Name(s iface.Store) string {
	return strings.ToUpper(board.Name)
}
