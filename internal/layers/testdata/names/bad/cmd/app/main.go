// Command app is wiring: it may exit and read its arguments, but not read a file.
package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Println(os.Args)
	_, _ = os.ReadFile("x")
	os.Exit(0)
}
