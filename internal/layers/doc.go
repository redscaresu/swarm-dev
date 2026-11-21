// Package layers holds the Go checks that give each package of the module its layer, in its tests
// only. Each package is one of:
//
//   - wiring: cmd/ and every package under it;
//   - interfaces: internal/iface;
//   - an adapter: internal/adapter/herdr, gh, git or store, or a package under one, the one
//     implementation of its interface;
//   - the clock: internal/clock;
//   - rules: every other package in the module.
//
// Any other package under internal/adapter/ is an error, since each interface has one
// implementation. go test -v ./internal/layers/ prints the class it gives each package.
package layers
