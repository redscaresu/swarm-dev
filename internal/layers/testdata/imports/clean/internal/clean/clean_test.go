package clean

// A test file may import anything: the walk skips it.
import "os/exec"

var _ = exec.Command
