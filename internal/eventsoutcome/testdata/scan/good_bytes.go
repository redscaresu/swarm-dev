package scan

// escDigits is the length of a \u escape's code.
const escDigits = 4

// escTail skips an escape's code in a []byte: its [4] is a byte of one value, never a column.
func escTail(rest []byte) []byte {
	if len(rest) > escDigits && rest[escDigits] == '"' {
		return nil
	}
	return rest[escDigits:]
}
