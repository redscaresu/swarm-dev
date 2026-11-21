// Package gh is an adapter, so its imports are not judged.
package gh

import (
	"net"
	"os/exec"
	. "strings"

	"github.com/other/lib"
)

var _, _, _, _ = net.Dial, exec.Command, Cut, lib.X
