// Package report holds bin/lib/report.py's rules as Go, beside the Python copy that the flow,
// outcomes, retro and dataset helpers still import. Each part has a comparison test that runs
// report.py and the Go over the same inputs and fails when either side alone changes. The Python
// copy goes when its last importer is ported.
package report
