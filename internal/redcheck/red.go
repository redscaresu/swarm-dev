// Package redcheck is a throwaway rules package that reads a file, to show go-checks go red.
package redcheck

import "os"

// Load reads p.
func Load(p string) ([]byte, error) {
	return os.ReadFile(p)
}
