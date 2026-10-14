// Command validate checks every community transformation the way the Monad
// platform will load it: the file must sit where the ingest indexes
// transforms, carry the metadata the catalog shows, and every jq query must
// parse and compile under the gojq version the jq operation runs.
//
//	go -C tools run ./cmd/validate
package main

import (
	"flag"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/itchyny/gojq"

	"github.com/monad-inc/community-transformations/tools/internal/repo"
)

func main() {
	root := flag.String("root", "..", "repository root")
	flag.Parse()
	problems, n, err := validate(*root)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if len(problems) > 0 {
		sort.Strings(problems)
		fmt.Fprintln(os.Stderr, strings.Join(problems, "\n"))
		fmt.Fprintf(os.Stderr, "%d problem(s) in %d transforms\n", len(problems), n)
		os.Exit(1)
	}
	fmt.Printf("%d transforms valid\n", n)
}

func validate(root string) ([]string, int, error) {
	var problems []string

	// The ingest indexes every .yaml/.yml file in the repository as a
	// transform, so YAML outside the transform directories (other than
	// GitHub's own config) would surface in the catalog.
	transformDir := map[string]bool{}
	for _, d := range repo.TransformDirs {
		transformDir[d] = true
	}
	err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(root, p)
		if d.IsDir() {
			if rel == ".git" || rel == ".github" {
				return filepath.SkipDir
			}
			return nil
		}
		top := strings.SplitN(rel, string(filepath.Separator), 2)[0]
		switch {
		case strings.HasSuffix(rel, ".yml"):
			problems = append(problems, fmt.Sprintf("%s: use the .yaml extension", rel))
		case strings.HasSuffix(rel, ".yaml") && !transformDir[top]:
			problems = append(problems, fmt.Sprintf("%s: YAML outside %s is indexed as a transform", rel, strings.Join(repo.TransformDirs, ", ")))
		}
		return nil
	})
	if err != nil {
		return nil, 0, err
	}

	paths, err := repo.Transforms(root)
	if err != nil {
		return nil, 0, err
	}
	names := map[string][]string{}
	for _, p := range paths {
		t, err := repo.LoadTransform(root, p)
		if err != nil {
			problems = append(problems, fmt.Sprintf("%s: %v", p, err))
			continue
		}
		problems = append(problems, checkTransform(t)...)
		names[t.Name] = append(names[t.Name], p)
	}
	for name, ps := range names {
		if name != "" && len(ps) > 1 {
			problems = append(problems, fmt.Sprintf("%s: name %q is also used by %s", ps[0], name, strings.Join(ps[1:], ", ")))
		}
	}
	return problems, len(paths), nil
}

func checkTransform(t *repo.Transform) []string {
	var problems []string
	bad := func(format string, a ...any) {
		problems = append(problems, t.Path+": "+fmt.Sprintf(format, a...))
	}
	utility := strings.HasPrefix(t.Path, "utility"+string(filepath.Separator))
	if !utility && len(strings.Split(t.Path, string(filepath.Separator))) < 4 {
		bad("expected <format>/<version>/<vendor>/<transform>.yaml")
	}
	for field, v := range map[string]string{"name": t.Name, "description": t.Description, "author": t.Author} {
		if strings.TrimSpace(v) == "" {
			bad("%s is required", field)
		}
	}
	if len(t.Tags) == 0 {
		bad("tags is required")
	}
	// A source-agnostic transform (a utility serializer, an output-schema
	// fixup) declares that explicitly with "inputs: []".
	if t.Inputs == nil {
		bad("inputs is required; use \"inputs: []\" for a source-agnostic transform")
	}
	if len(t.Config.Operations) == 0 {
		bad("config.operations is required")
	}
	for i, op := range t.Config.Operations {
		switch op.Operation {
		case "":
			bad("operation %d: operation is required", i)
		case "jq":
			// Mirrors the jq operation's Init: parse, then compile.
			query := op.Query()
			if strings.TrimSpace(query) == "" {
				bad("operation %d: arguments.query is required", i)
				continue
			}
			q, err := gojq.Parse(query)
			if err != nil {
				bad("operation %d: jq parse: %v", i, err)
				continue
			}
			if _, err := gojq.Compile(q); err != nil {
				bad("operation %d: jq compile: %v", i, err)
			}
		}
	}
	return problems
}
