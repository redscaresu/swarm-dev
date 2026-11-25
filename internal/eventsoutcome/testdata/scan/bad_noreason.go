package scan

// noReason has the opt-out with no reason, which does not pass.
func noReason(f []string) string {
	return f[4] // outcome-scan: ok
}
