// Package guard imports only the standard library, the interfaces, the clock and another of the
// four, so the protected rule passes it.
package guard

import (
	"fmt"
	"strings"

	"example.com/m/internal/clock"
	"example.com/m/internal/iface"
	"example.com/m/internal/release"
)

// Check uses each import.
func Check(s iface.Store) string {
	return fmt.Sprint(strings.ToUpper(release.Name), clock.Now(), s)
}
