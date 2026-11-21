package clean

import (
	"testing"
	"time"
)

// A test file is not walked, so its read of the time is no finding.
func TestNow(t *testing.T) { _ = time.Now() }
