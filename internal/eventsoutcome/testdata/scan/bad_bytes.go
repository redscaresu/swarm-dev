package scan

import "bytes"

// bytesRow reads a bytes.Split row's column, which is no string though each field is bytes.
func bytesRow(line []byte) []byte {
	f := bytes.Split(line, []byte("\t"))
	return f[4]
}
