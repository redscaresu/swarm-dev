// Package store is an adapter, so the names rule does not judge it.
package store

import "os"

// Load reads a file.
func Load(p string) ([]byte, error) {
	return os.ReadFile(p)
}
