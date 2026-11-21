//go:build windows

package rules

// The walk ignores build tags, so this file counts on every platform.
import "net/http"

var _ = http.Get
