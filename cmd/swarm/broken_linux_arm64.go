//go:build linux && arm64

package main

// A type error on linux/arm64 only, to prove build-check goes red and names the platform.
var brokenOnLinuxArm64 int = "not an int"
