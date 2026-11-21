// Command app is wiring, so it may import an adapter.
package main

import (
	"fmt"
	"os"

	"example.com/m/internal/adapter/gh"
	"example.com/m/internal/clean"
)

var _ = gh.X

func main() {
	fmt.Fprintln(os.Stderr, clean.Join("a", "b"))
}
