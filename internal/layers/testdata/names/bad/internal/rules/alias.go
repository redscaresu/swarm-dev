package rules

import sys "os"

// Aliased calls ReadFile through an import name other than os.
func Aliased(p string) ([]byte, error) {
	return sys.ReadFile(p)
}
