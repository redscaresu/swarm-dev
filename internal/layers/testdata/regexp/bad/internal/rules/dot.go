package rules

import . "regexp"

// Dotted compiles a literal, but the dot import hides its calls.
var Dotted = MustCompile("x")
