package rules

import (
	"go/parser"
	"log"
	"text/template"
	"unsafe"
)

var _, _, _, _ = parser.ParseFile, log.Print, template.New, unsafe.Sizeof
