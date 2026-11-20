package main

import (
	"os"
	"path/filepath"
	"testing"
)

// Throwaway: errcheck flags the dropped error; the test itself passes.
func TestRedErrcheck(t *testing.T) {
	os.Remove(filepath.Join(t.TempDir(), "absent"))
}
