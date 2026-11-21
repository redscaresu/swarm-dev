// Package rules uses only names a rules package may use.
package rules

import (
	"fmt"
	"os"
	"path/filepath"
)

// Where joins HOME with a name, or returns os.ErrNotExist's text when HOME is unset.
func Where() string {
	h := os.Getenv("HOME")
	if h == "" {
		return os.ErrNotExist.Error()
	}
	return fmt.Sprintf("%s", filepath.Join(h, "x"))
}
