package scan

// dateDash checks a date's fifth byte: a string's [4] is a byte of one value, never a column.
func dateDash(s string) bool {
	return len(s) > 4 && s[4] == '-' && s[4:] != ""
}
