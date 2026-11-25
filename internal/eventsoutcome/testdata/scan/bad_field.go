package scan

// event holds a row in a struct's field.
type event struct {
	cols []string
}

// fromField reads the field.
func fromField(e event) string {
	return e.cols[4]
}
