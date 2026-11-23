// Package consts holds the constants another package of the fixture names. TestWalkCalls asserts
// its records, so keep its lines where they are.
package consts

// Pattern is a raw string constant.
const Pattern = `^a+$`

// Level is a constant that is no string.
const Level = iota

// Name is a variable, so no constant.
var Name = "v"
