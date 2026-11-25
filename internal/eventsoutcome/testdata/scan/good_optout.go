package scan

// optOut reads another file's fifth column.
func optOut(f []string) string {
	return f[4] // outcome-scan: ok reads findings.tsv, whose fifth column has no tail
}
