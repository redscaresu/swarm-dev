package rules

import "fmt"

// Say writes to standard output, which only wiring may do. Sprintf is allowed.
func Say(n int) {
	fmt.Println(fmt.Sprintf("%d", n))
}
