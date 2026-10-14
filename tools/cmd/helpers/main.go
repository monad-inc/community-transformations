// Command helpers keeps the jq helper copies in community transformations in
// line with the canonical definitions in helpers/helpers.jq.
//
//	go -C tools run ./cmd/helpers sync    # rewrite drifted copies in place
//	go -C tools run ./cmd/helpers check   # fail on drift; run helpers/tests.json
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"

	"github.com/itchyny/gojq"

	"github.com/monad-inc/community-transformations/tools/internal/repo"
)

func main() {
	root := flag.String("root", "..", "repository root")
	flag.Usage = func() {
		fmt.Fprintln(os.Stderr, "usage: helpers [-root dir] sync|check")
		flag.PrintDefaults()
	}
	flag.Parse()
	if flag.NArg() != 1 {
		flag.Usage()
		os.Exit(2)
	}
	helpers, err := repo.LoadHelpers(*root)
	if err != nil {
		fatal(err)
	}
	switch flag.Arg(0) {
	case "sync":
		err = sync(*root, helpers)
	case "check":
		err = check(*root, helpers)
	default:
		flag.Usage()
		os.Exit(2)
	}
	if err != nil {
		fatal(err)
	}
}

func fatal(err error) {
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}

// sync rewrites every line-leading top-level def of a canonical helper to
// the canonical body, and inserts canonical dependencies a rewritten helper
// needs but the transform lacks.
func sync(root string, helpers map[repo.Key]*repo.Helper) error {
	paths, err := repo.Transforms(root)
	if err != nil {
		return err
	}
	names := repo.Names(helpers)
	changed := 0
	for _, p := range paths {
		full := filepath.Join(root, p)
		b, err := os.ReadFile(full)
		if err != nil {
			return err
		}
		lines := strings.Split(string(b), "\n")
		out, err := syncLines(lines, helpers, names)
		if err != nil {
			return fmt.Errorf("%s: %w", p, err)
		}
		if reflect.DeepEqual(out, lines) {
			continue
		}
		if err := os.WriteFile(full, []byte(strings.Join(out, "\n")), 0o644); err != nil {
			return err
		}
		fmt.Println("synced", p)
		changed++
	}
	fmt.Printf("%d of %d transforms changed\n", changed, len(paths))
	return nil
}

func syncLines(lines []string, helpers map[repo.Key]*repo.Helper, names map[string]bool) ([]string, error) {
	defs, err := repo.ScanDefs(lines, names)
	if err != nil {
		return nil, err
	}
	present := map[string]int{} // helper name -> line index of its first def
	for _, d := range defs {
		if _, ok := present[d.Key.Name]; !ok {
			present[d.Key.Name] = d.Start
		}
	}
	var out []string
	next := 0
	for _, d := range defs {
		h, ok := helpers[d.Key]
		if !ok {
			return nil, fmt.Errorf("line %d: %s has no canonical definition (canonical arities differ)", d.Start+1, d.Key)
		}
		out = append(out, lines[next:d.Start]...)
		pipe := d.Pipe
		for _, r := range h.Requires {
			at, ok := present[r]
			if ok && at > d.Start {
				return nil, fmt.Errorf("line %d: %s requires %s, which is defined later in the query", d.Start+1, d.Key, r)
			}
			if ok {
				continue
			}
			dep := requiredHelper(helpers, r)
			if dep == nil {
				return nil, fmt.Errorf("%s requires unknown helper %s", d.Key, r)
			}
			out = append(out, indent(dep.Lines, d.Indent, pipe)...)
			pipe = strings.Repeat(" ", len(pipe))
			present[r] = d.Start
		}
		out = append(out, indent(h.Lines, d.Indent, pipe)...)
		next = d.End
	}
	return append(out, lines[next:]...), nil
}

func requiredHelper(helpers map[repo.Key]*repo.Helper, name string) *repo.Helper {
	for k, h := range helpers {
		if k.Name == name {
			return h
		}
	}
	return nil
}

func indent(lines []string, ind, pipe string) []string {
	out := make([]string, len(lines))
	for i, l := range lines {
		switch {
		case l == "":
			out[i] = ""
		case i == 0:
			out[i] = ind + pipe + l
		default:
			out[i] = ind + strings.Repeat(" ", len(pipe)) + l
		}
	}
	return out
}

// check fails when a transform's top-level definition of a canonical helper
// differs from helpers/helpers.jq, and runs the helper test cases.
func check(root string, helpers map[repo.Key]*repo.Helper) error {
	paths, err := repo.Transforms(root)
	if err != nil {
		return err
	}
	byName := map[string][]repo.Key{}
	for k := range helpers {
		byName[k.Name] = append(byName[k.Name], k)
	}
	var problems []string
	for _, p := range paths {
		t, err := repo.LoadTransform(root, p)
		if err != nil {
			problems = append(problems, fmt.Sprintf("%s: %v", p, err))
			continue
		}
		for i, op := range t.Config.Operations {
			if op.Operation != "jq" {
				continue
			}
			defs, err := repo.TopLevelDefs(op.Query())
			if err != nil {
				problems = append(problems, fmt.Sprintf("%s: operation %d: %v", p, i, err))
				continue
			}
			for k, bodies := range defs {
				if _, ok := byName[k.Name]; !ok {
					continue
				}
				h, ok := helpers[k]
				if !ok {
					problems = append(problems, fmt.Sprintf("%s: defines %s; helpers.jq defines %s only — rename the local function", p, k, keys(byName[k.Name])))
					continue
				}
				for _, b := range bodies {
					if b != h.Def {
						problems = append(problems, fmt.Sprintf("%s: %s differs from %s — run sync", p, k, repo.HelpersFile))
					}
				}
			}
		}
	}
	if err := runTests(root); err != nil {
		problems = append(problems, err.Error())
	}
	if len(problems) > 0 {
		sort.Strings(problems)
		return fmt.Errorf("%s\n%d problem(s)", strings.Join(problems, "\n"), len(problems))
	}
	fmt.Printf("%d transforms match %s; helper tests pass\n", len(paths), repo.HelpersFile)
	return nil
}

func keys(ks []repo.Key) string {
	s := make([]string, len(ks))
	for i, k := range ks {
		s[i] = k.String()
	}
	sort.Strings(s)
	return strings.Join(s, ", ")
}

// testSuite is one entry of helpers/tests.json: a query run against each
// case's input with helpers.jq included, expecting the case's output.
type testSuite struct {
	Query string `json:"query"`
	Cases []struct {
		In  any `json:"in"`
		Out any `json:"out"`
	} `json:"cases"`
}

func runTests(root string) error {
	b, err := os.ReadFile(filepath.Join(root, "helpers", "tests.json"))
	if err != nil {
		return err
	}
	var suites []testSuite
	if err := json.Unmarshal(b, &suites); err != nil {
		return fmt.Errorf("helpers/tests.json: %w", err)
	}
	loader := gojq.WithModuleLoader(gojq.NewModuleLoader([]string{filepath.Join(root, "helpers")}))
	var failures []string
	n := 0
	for _, s := range suites {
		q, err := gojq.Parse(`include "helpers"; ` + s.Query)
		if err != nil {
			return fmt.Errorf("helpers/tests.json: %s: %w", s.Query, err)
		}
		code, err := gojq.Compile(q, loader)
		if err != nil {
			return fmt.Errorf("helpers/tests.json: %s: %w", s.Query, err)
		}
		for _, c := range s.Cases {
			n++
			got, _ := code.Run(normalize(c.In)).Next()
			if err, ok := got.(error); ok {
				got = "error: " + err.Error()
			}
			if !equal(got, c.Out) {
				in, _ := json.Marshal(c.In)
				g, _ := gojq.Marshal(got)
				w, _ := json.Marshal(c.Out)
				failures = append(failures, fmt.Sprintf("helper test %s on %s: got %s, want %s", s.Query, in, g, w))
			}
		}
	}
	if len(failures) > 0 {
		return fmt.Errorf("%s", strings.Join(failures, "\n"))
	}
	fmt.Printf("%d helper test cases pass\n", n)
	return nil
}

// normalize round-trips v through gojq's encoder so inputs carry the value
// types a transform sees at runtime.
func normalize(v any) any {
	b, _ := gojq.Marshal(v)
	var out any
	_ = json.Unmarshal(b, &out)
	return out
}

func equal(got, want any) bool {
	g, err := gojq.Marshal(got)
	if err != nil {
		return false
	}
	var gv any
	if err := json.Unmarshal(g, &gv); err != nil {
		return false
	}
	return reflect.DeepEqual(gv, want)
}
