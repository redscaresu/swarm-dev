package rules

import (
	"fmt"

	"example.com/m/internal/adapter/gh"
	"github.com/other/lib"
)

var _, _, _ = fmt.Sprint, gh.X, lib.X
