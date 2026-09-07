package main

import (
	"fmt"
	"os"
	"strings"

	"github.com/nhatminh06/pgsentry/internal/pgsafe"
)

var version = "dev"

func usage() {
	fmt.Fprintln(os.Stderr, "usage: pgsafe check [--format=text|json] [--fail-on=SEVERITY] [--transaction-mode=single|wrapped] <file...>\n       pgsafe rules\n       pgsafe explain <RULE_ID>\n       pgsafe version")
}
func main() { os.Exit(run(os.Args[1:])) }
func run(args []string) int {
	if len(args) == 0 {
		usage()
		return 2
	}
	switch args[0] {
	case "version":
		fmt.Printf("pgsafe %s (PostgreSQL 16 rules)\n", version)
		return 0
	case "rules":
		for _, r := range pgsafe.Rules() {
			fmt.Printf("%s %-8s %s\n", r.ID, r.Severity, r.Name)
		}
		return 0
	case "explain":
		if len(args) != 2 {
			usage()
			return 2
		}
		r, ok := pgsafe.RuleByID(strings.ToUpper(args[1]))
		if !ok {
			fmt.Fprintln(os.Stderr, "unknown rule")
			return 2
		}
		fmt.Printf("%s %s\nSeverity: %s\nConfidence: %s\nRisk: %s\nSafer alternative: %s\n", r.ID, r.Name, r.Severity, r.Confidence, r.Risk, r.Alternative)
		return 0
	case "check":
		return check(args[1:])
	default:
		usage()
		return 2
	}
}
func check(args []string) int {
	format := "text"
	fail := pgsafe.High
	mode := "single"
	files := []string{}
	for _, a := range args {
		switch {
		case strings.HasPrefix(a, "--format="):
			format = strings.TrimPrefix(a, "--format=")
		case strings.HasPrefix(a, "--fail-on="):
			var ok bool
			fail, ok = pgsafe.ParseSeverity(strings.TrimPrefix(a, "--fail-on="))
			if !ok {
				fmt.Fprintln(os.Stderr, "invalid --fail-on")
				return 2
			}
		case strings.HasPrefix(a, "--transaction-mode="):
			mode = strings.TrimPrefix(a, "--transaction-mode=")
		case strings.HasPrefix(a, "-") && a != "-":
			fmt.Fprintf(os.Stderr, "unknown option: %s\n", a)
			return 2
		default:
			files = append(files, a)
		}
	}
	if len(files) == 0 || (format != "text" && format != "json") {
		usage()
		return 2
	}
	r, err := pgsafe.Check(files, os.Stdin, pgsafe.Options{FailOn: fail, TransactionMode: mode})
	if err != nil {
		fmt.Fprintln(os.Stderr, "pgsafe:", err)
		return 2
	}
	if format == "json" {
		if err = pgsafe.WriteJSON(os.Stdout, r); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 2
		}
	} else {
		pgsafe.WriteText(os.Stdout, r)
	}
	return r.ExitCode
}
