package rules

import re "regexp"

// Aliased matches v under another name for regexp.
func Aliased(v string) bool {
	ok, _ := re.MatchString(v, "x")
	return ok
}
