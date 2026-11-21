package x

import (
	"testing"

	"example.com/m/internal/board"
)

func TestName(t *testing.T) {
	if board.Name == "" {
		t.Fatal("no name")
	}
}
