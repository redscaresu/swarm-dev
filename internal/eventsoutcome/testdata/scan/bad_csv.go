package scan

import (
	"encoding/csv"
	"io"
)

// fromCSV reads an encoding/csv record.
func fromCSV(in io.Reader) string {
	r := csv.NewReader(in)
	rec, _ := r.Read()
	return rec[4]
}
