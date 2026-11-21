// Package rules is a rules package that reaches files, the environment and the process through os.
package rules

import "os"

// Load calls os.ReadFile.
func Load(p string) ([]byte, error) {
	return os.ReadFile(p)
}

// Read passes os.ReadFile as a value rather than calling it.
var Read = os.ReadFile

// Mess removes a file, reads the working directory, sets a variable and exits.
func Mess() {
	_ = os.Remove("x")
	_, _ = os.Getwd()
	_ = os.Setenv("K", "v")
	os.Exit(1)
}

// Home and Missing use names os allows, so they add no finding.
func Home() (string, error) {
	if h := os.Getenv("HOME"); h != "" {
		return h, nil
	}
	return "", os.ErrNotExist
}
