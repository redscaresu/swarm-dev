package scan

// byVariable indexes with a variable, which is no constant even while it holds 4.
func byVariable(r []string) string {
	i := 4
	return r[i]
}
