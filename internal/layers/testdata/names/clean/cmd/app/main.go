// Command app is wiring, which may use the process's arguments, exit and standard streams.
package main

import (
	"fmt"
	"os"

	"example.com/m/internal/rules"
)

func main() {
	fmt.Println(os.Args)
	fmt.Fprintln(os.Stderr, rules.Where())
	os.Exit(0)
}
