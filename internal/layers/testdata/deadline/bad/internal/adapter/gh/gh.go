package gh

import (
	. "context"
	. "os/exec"
)

// Dot imports hide Command and Background from the check, in an adapter too.
var _, _ = Background, Command
