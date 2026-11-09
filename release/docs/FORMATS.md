# Structure formats

Layouts describe paths relative to a destination root. Export captures names
and types, not existing file bytes. Explicit content in imported layouts is seed
content for scaffold or missing-file synchronization.

## Text formats

Dash uses one dash per level, starting at one; directories end in `/`:

```text
- src/
-- main.rs @content:fn main() {}
- empty/
- README.md @content:Example project
```

Root-relative path entries such as `- src/main.rs` are also accepted; missing
directory ancestors are inferred. Hierarchical depth cannot jump, and files
cannot be used as parents.

Space format uses two spaces per level by default (`--space-unit 1` through 16
changes this). Tab format uses one actual tab per level. Do not mix them.

```text
src/
  main.rs
README.md
```

Tree-symbol format uses `├── ` / `└── ` connectors and `│   ` / four-space
prefixes. Root entries require connectors. Blank lines and hash-comment lines
are ignored in text formats.

Export this format with `ptu export --root ./app --format treesym --output tree.txt`.
Import or convert an existing description with `--output-format treesym`.
Exported tree symbols preserve directory markers and declared content/template
metadata, and can be read back with `--format treesym`.

```text
├── src/
│   └── main.rs
└── README.md
```

## JSON and YAML

```json
[
  {
    "name": "src",
    "type": "directory",
    "children": [
      { "name": "main.rs", "type": "file", "content": "fn main() {}\n" }
    ]
  },
  { "path": "empty", "isDir": true },
  { "path": "README.md", "type": "file", "content": "Example\n" }
]
```

```yaml
- name: src
  type: directory
  children:
    - name: main.rs
      type: file
      content: |
        fn main() {}
- path: empty
  isDir: true
```

Properties are case-insensitive. Unknown or duplicate properties fail.

| Property | Meaning |
| --- | --- |
| `name` or `path` | Relative path string; provide one |
| `type` | `file`/`blob` or `dir`/`directory`/`folder`/`tree` |
| `isDir` | Boolean type indicator; must agree with `type` |
| `children` or `entries` | Array of nodes, allowed only under directories |
| `content` | Exact UTF-8 string, including an empty string |
| `contentDirective` | `@content:` or `@content64:` string |
| `template` | One of the bundled preset contexts for file content lookup |

Path strings are valid nodes; trailing `/` indicates a directory. A wrapper with
only a nonempty children/entries array is accepted. Empty arrays represent an
empty layout. Directories cannot carry content or template metadata.

YAML uses a maintained YAML parser and accepts block/flow collections and literal
or folded strings. Anchors, aliases, and explicit tags are rejected. Exactly one
document is required. This is intentionally broader syntax than the legacy YAML
subset; the layout schema remains strict.

## Content directives

```text
- README.md @content:Hello world
- empty.txt @content64:
- multiline.txt @content64:SGVsbG8Kd29ybGQK
- src/App.tsx @template:react-vite
```

Base64 is decoded as UTF-8. Importable output uses Base64 to preserve multiline,
empty, or whitespace-sensitive content. `@content:` consumes the rest of its
line; place template metadata before literal content when combining directives.
Explicit content wins over a template. A template directive looks up a file
within that preset; it does not insert a full project. Files without content or
a matching template file receive empty content. Unknown template contexts fail
validation.

## Detection and portability

`.json`, `.yaml`, and `.yml` choose their parsers. Otherwise JSON delimiters,
YAML node keys, dash prefixes, tree connectors, and indentation are inspected.
Flat unindented lists can be ambiguous; use `--format` explicitly.

Portable naming rules apply on every platform: reject absolute/UNC paths,
dot/dot-dot components, repeated separators, Windows device names, alternate data
streams, control characters, invalid Windows filename characters, and trailing
dots/spaces. Backslashes normalize to `/`. Names containing harmless internal
double dots are accepted. Case-folded duplicate paths fail even on Linux; inferred
ancestor spelling is canonicalized. Native verification uses case-sensitive
matching on Unix and case-insensitive matching on Windows.

Inputs are UTF-8 (optional BOM), limited to 8 MiB, 100,000 normalized entries,
128 path components, and 255 UTF-16 code units per component. JSON/YAML parser
nesting limits can reject deeply nested node representations before the path
limit; use flat path nodes for deep layouts. These are defensive bounds, not a
promise that every valid layout fits the host's path-length restrictions.

Importable, JSON, and YAML preserve supported metadata. `txt` and `md` are display
formats. Merge union rejects conflicts; preference modes preserve the winning
type/subtree and fill absent metadata from the other input.
