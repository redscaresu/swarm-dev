// Package clean is a rules package whose every import is allowed. TestWalkRecords asserts its
// records field by field, so keep its lines where they are.
package clean

import (
	"fmt"
	fp "path/filepath"
	"slices"
	_ "strings"
	"unicode/utf8"

	"example.com/m/internal/iface"
)

// S is a store.
var S iface.Store

// Join joins a and b.
func Join(a, b string) string {
	return fmt.Sprint(fp.Join(a, b))
}

// Base is filepath.Base, passed as a value rather than called.
var Base = fp.Base

// Width is the bytes r takes.
func Width(r rune) int {
	return utf8.RuneLen(r)
}

// Shadow's fmt is a parameter, but the walk counts fmt.Errorf as the fmt import's.
func Shadow(fmt interface{ Errorf(string, ...any) error }) error {
	return fmt.Errorf("x")
}

// Generic calls slices' functions with their type arguments written out.
func Generic(xs []int) int {
	return slices.Index[[]int, int](slices.Clone[[]int](xs), 1)
}
