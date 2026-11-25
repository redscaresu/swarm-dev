package scan

import "strings"

// splitCall indexes the strings.Split call itself.
func splitCall(l string) string {
	return strings.Split(l, "\t")[4]
}
