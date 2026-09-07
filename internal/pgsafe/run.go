package pgsafe

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"sort"
)

func Check(files []string, stdin io.Reader, opts Options) (Report, error) {
	report := Report{SchemaVersion: SchemaVersion, PostgreSQLVersion: 16, Diagnostics: []Diagnostic{}, Summary: Summary{Files: len(files), FailOn: opts.FailOn}}
	for _, file := range files {
		var b []byte
		var err error
		if file == "-" {
			b, err = io.ReadAll(stdin)
		} else {
			b, err = os.ReadFile(file)
		}
		if err != nil {
			return report, fmt.Errorf("%s: %w", file, err)
		}
		ds, n, err := Analyze(file, string(b), opts)
		if err != nil {
			return report, fmt.Errorf("%s: %w", file, err)
		}
		report.Summary.Statements += n
		report.Diagnostics = append(report.Diagnostics, ds...)
	}
	sort.SliceStable(report.Diagnostics, func(i, j int) bool {
		a, b := report.Diagnostics[i], report.Diagnostics[j]
		if a.File != b.File {
			return a.File < b.File
		}
		if a.Statement != b.Statement {
			return a.Statement < b.Statement
		}
		return a.RuleID < b.RuleID
	})
	for _, d := range report.Diagnostics {
		if d.Suppressed {
			report.Summary.Suppressed++
			continue
		}
		report.Summary.Diagnostics++
		if d.Severity.Rank() >= opts.FailOn.Rank() {
			report.Summary.Failing++
		}
	}
	if report.Summary.Failing > 0 {
		report.ExitCode = 1
	}
	return report, nil
}

func WriteJSON(w io.Writer, r Report) error {
	e := json.NewEncoder(w)
	e.SetIndent("", "  ")
	return e.Encode(r)
}
func WriteText(w io.Writer, r Report) {
	for _, d := range r.Diagnostics {
		status := ""
		if d.Suppressed {
			status = " SUPPRESSED"
		}
		fmt.Fprintf(w, "%s:%d:%d\n  %s %s%s\n  %s\n\n  %s\n\n  Risk: %s\n  Safer alternative: %s\n", d.File, d.Line, d.Column, d.RuleID, d.Severity, status, d.Title, d.SQL, d.Risk, d.Alternative)
		if d.Suppressed {
			fmt.Fprintf(w, "  Suppression reason: %s\n", d.SuppressionReason)
		}
		fmt.Fprintln(w)
	}
	fmt.Fprintf(w, "%d actionable diagnostics, %d suppressed, %d failing at %s\n", r.Summary.Diagnostics, r.Summary.Suppressed, r.Summary.Failing, r.Summary.FailOn)
}
