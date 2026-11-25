package scan

import "strings"

// splitRow compares a strings.Split row's column.
func splitRow(line string) bool {
	f := strings.Split(line, "\t")
	return f[4] == "ok"
}
