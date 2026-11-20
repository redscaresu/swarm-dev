package main

import "testing"

// Throwaway: go vet's structtag check flags the unquoted tag. go test's own vet subset has no
// structtag, so this does not stop the failing test from running.
type redVet struct {
	A int `json:a`
}

func TestRedVet(t *testing.T) { _ = redVet{A: 1} }
