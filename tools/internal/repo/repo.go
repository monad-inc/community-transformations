// Package repo loads community transformations and the canonical jq helpers.
package repo

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strings"

	"github.com/itchyny/gojq"
	"gopkg.in/yaml.v3"
)

// HelpersFile is the canonical helper file, relative to the repo root.
const HelpersFile = "helpers/helpers.jq"

// TransformDirs are the top-level directories that hold transform YAML.
var TransformDirs = []string{"cef", "ecs", "ocsf", "tarsal", "utility"}

// Transform is one transformation file.
type Transform struct {
	Path         string   `yaml:"-"`
	Name         string   `yaml:"name"`
	Description  string   `yaml:"description"`
	Author       string   `yaml:"author"`
	Contributors []string `yaml:"contributors"`
	Inputs       []string `yaml:"inputs"`
	Tags         []string `yaml:"tags"`
	Config       struct {
		Operations []Operation `yaml:"operations"`
	} `yaml:"config"`
}

// Operation is one entry of config.operations.
type Operation struct {
	Operation string         `yaml:"operation"`
	Arguments map[string]any `yaml:"arguments"`
}

// Query returns the jq query of a jq operation.
func (o Operation) Query() string {
	q, _ := o.Arguments["query"].(string)
	return q
}

// Transforms returns every transform YAML file under root, sorted by path.
func Transforms(root string) ([]string, error) {
	var paths []string
	for _, dir := range TransformDirs {
		err := filepath.WalkDir(filepath.Join(root, dir), func(p string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if !d.IsDir() && (strings.HasSuffix(p, ".yaml") || strings.HasSuffix(p, ".yml")) {
				rel, err := filepath.Rel(root, p)
				if err != nil {
					return err
				}
				paths = append(paths, rel)
			}
			return nil
		})
		if err != nil && !os.IsNotExist(err) {
			return nil, err
		}
	}
	sort.Strings(paths)
	return paths, nil
}

// LoadTransform parses one transform file.
func LoadTransform(root, path string) (*Transform, error) {
	b, err := os.ReadFile(filepath.Join(root, path))
	if err != nil {
		return nil, err
	}
	t := &Transform{Path: path}
	if err := yaml.Unmarshal(b, t); err != nil {
		return nil, err
	}
	return t, nil
}

// Key identifies a jq function by name and arity, as jq does.
type Key struct {
	Name  string
	Arity int
}

func (k Key) String() string { return fmt.Sprintf("%s/%d", k.Name, k.Arity) }

// Helper is one canonical helper definition.
type Helper struct {
	Key      Key
	Lines    []string // source lines of the def, unindented
	Requires []string // helper names this helper calls
	Def      string   // gojq's normalized rendering, for comparison
}

var (
	defLine     = regexp.MustCompile(`^(\s*)(\|\s*)?def ([A-Za-z_][A-Za-z0-9_]*)\b`)
	requireLine = regexp.MustCompile(`^#\s*requires:\s*(.+)$`)
)

// LoadHelpers parses the canonical helper file.
func LoadHelpers(root string) (map[Key]*Helper, error) {
	b, err := os.ReadFile(filepath.Join(root, HelpersFile))
	if err != nil {
		return nil, err
	}
	lines := strings.Split(string(b), "\n")
	helpers := map[Key]*Helper{}
	var requires []string
	for i := 0; i < len(lines); i++ {
		if m := requireLine.FindStringSubmatch(lines[i]); m != nil {
			for _, r := range strings.Split(m[1], ",") {
				requires = append(requires, strings.TrimSpace(r))
			}
			continue
		}
		if strings.TrimSpace(lines[i]) == "" {
			requires = nil
			continue
		}
		m := defLine.FindStringSubmatch(lines[i])
		if m == nil || m[1] != "" || m[2] != "" {
			continue
		}
		d, err := FindDef(lines, i)
		if err != nil {
			return nil, fmt.Errorf("%s:%d: %w", HelpersFile, i+1, err)
		}
		h := &Helper{Key: d.Key, Lines: lines[i:d.End], Requires: requires, Def: d.Def}
		if _, dup := helpers[h.Key]; dup {
			return nil, fmt.Errorf("%s: %s defined twice", HelpersFile, h.Key)
		}
		helpers[h.Key] = h
		requires = nil
		i = d.End - 1
	}
	return helpers, nil
}

// Names returns the set of helper names.
func Names(helpers map[Key]*Helper) map[string]bool {
	names := map[string]bool{}
	for k := range helpers {
		names[k.Name] = true
	}
	return names
}

// Def is a function definition located in source lines.
type Def struct {
	Key    Key
	Start  int    // index of the line holding "def"
	End    int    // index one past the def's last line
	Indent string // leading whitespace of the def line
	Pipe   string // "| " when the def follows a pipe on its line
	Def    string // gojq's normalized rendering
}

// FindDef locates the definition that starts on lines[start]. The def must
// begin its line (after optional indentation and "|") and end its last
// line; it ends at the first line where the accumulated text parses as a
// single complete function definition.
func FindDef(lines []string, start int) (*Def, error) {
	m := defLine.FindStringSubmatch(lines[start])
	if m == nil {
		return nil, fmt.Errorf("no def on line")
	}
	first := strings.TrimPrefix(lines[start][len(m[1]):], m[2])
	text := first
	for end := start + 1; end <= len(lines); end++ {
		if q, err := gojq.Parse(text + "\n."); err == nil && len(q.FuncDefs) == 1 && q.FuncDefs[0].Name == m[3] && q.String() == q.FuncDefs[0].String()+" ." {
			fd := q.FuncDefs[0]
			return &Def{
				Key:    Key{fd.Name, len(fd.Args)},
				Start:  start,
				End:    end,
				Indent: m[1],
				Pipe:   m[2],
				Def:    fd.String(),
			}, nil
		}
		if end < len(lines) {
			text += "\n" + lines[end]
		}
	}
	return nil, fmt.Errorf("def %s: no complete definition ends at a line end", m[3])
}

// ScanDefs returns every line-leading def of one of names in lines.
func ScanDefs(lines []string, names map[string]bool) ([]*Def, error) {
	var defs []*Def
	for i := 0; i < len(lines); i++ {
		m := defLine.FindStringSubmatch(lines[i])
		if m == nil || !names[m[3]] {
			continue
		}
		d, err := FindDef(lines, i)
		if err != nil {
			return nil, fmt.Errorf("line %d: %w", i+1, err)
		}
		defs = append(defs, d)
		i = d.End - 1
	}
	return defs, nil
}

// TopLevelDefs returns every function definition in query that is not
// nested inside another function definition, keyed by name/arity, rendered
// in gojq's normalized form. A def that follows a pipe ("... | def f: ...;")
// counts as top level.
func TopLevelDefs(query string) (map[Key][]string, error) {
	q, err := gojq.Parse(query)
	if err != nil {
		return nil, err
	}
	defs := map[Key][]string{}
	var walk func(v reflect.Value)
	walk = func(v reflect.Value) {
		switch v.Kind() {
		case reflect.Ptr, reflect.Interface:
			if v.IsNil() {
				return
			}
			if fd, ok := v.Interface().(*gojq.FuncDef); ok {
				k := Key{fd.Name, len(fd.Args)}
				defs[k] = append(defs[k], fd.String())
				return
			}
			walk(v.Elem())
		case reflect.Struct:
			for i := 0; i < v.NumField(); i++ {
				walk(v.Field(i))
			}
		case reflect.Slice:
			for i := 0; i < v.Len(); i++ {
				walk(v.Index(i))
			}
		}
	}
	walk(reflect.ValueOf(q))
	return defs, nil
}
