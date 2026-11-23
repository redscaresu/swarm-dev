// Package layers holds the Go checks over the module's code, in its tests only, of which the layer
// checks are one set. The layer checks give each package of the module its layer, one of:
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
