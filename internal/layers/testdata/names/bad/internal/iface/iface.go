// Package iface is the interfaces, held to the same names as a rules package.
package iface

import "fmt"

// Show prints, which only wiring may do.
func Show() {
	fmt.Print("x")
}
