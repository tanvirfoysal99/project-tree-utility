# Structure file formats

Structure files describe paths relative to a project root. Do not include the
destination directory itself as an extra root unless you want that directory
created inside the project. Files describe layout and optional seed content.

## Dash

One dash means a root entry; each additional dash adds a level.
A trailing slash marks a directory.

```text
- src/
-- main.ts @content:console.log('hello');
- tests/
-- main.test.ts
- README.md @content:Demo project
```

Root-relative paths are also accepted:

```text
- src/main.ts
- tests/main.test.ts
- empty/
```

Missing directory ancestors in path-style input are inferred. In hierarchical
input, parents must be directories and depth cannot jump over a missing level.
Paths are case-insensitive for duplicate detection on Windows.

## Tab, space, and tree-symbol formats

Tab format uses one actual tab per nested level; root entries have no indent.
Space format uses two spaces per level by default; specify another positive
width using `--space-unit`. Do not mix tab and space indentation.

Space example:

```text
src/
  main.ts
tests/
  main.test.ts
```

Tree-symbol format accepts the usual connectors and four-character indentation:

```text
├── src/
│   └── main.ts
└── README.md
```

Use `--format treesym` for this form. Directory markers remove ambiguity.
Format detection examines meaningful lines and preserves indentation.
Flat lists can be ambiguous; provide their format explicitly.
JSON and YAML filename extensions select the corresponding parser, which still
validates the contents.

## JSON

Use an array of nodes. A node may use a relative path or a name with children:

```json
[
  {
    "name": "src",
    "type": "directory",
    "children": [
      { "name": "main.ts", "type": "file", "content": "console.log('hello');\n" }
    ]
  },
  { "path": "empty", "isDir": true },
  { "path": "README.md", "type": "file", "content": "Demo\n" }
]
```

Properties are case-insensitive. Supported properties:

| Property | Value |
| --- | --- |
| name / path | String containing a name or relative path |
| type | file/blob, or dir/directory/folder/tree |
| isDir | Boolean directory indicator |
| children / entries | Array of child nodes |
| content | Exact string to seed a file, including an empty string |
| contentDirective | String containing a supported content directive |
| template | Named template context for file stub generation |

Path strings are also accepted as nodes; use a trailing slash for directories.
An object wrapping a nonempty children/entries array is supported.
Unknown properties, invalid property types, conflicting type indicators,
duplicate paths, and children beneath files are rejected.
Prefer explicit types for leaf nodes, especially empty directories.

## YAML

YAML represents the same nodes and properties as JSON:

```yaml
- name: src
  type: directory
  children:
    - name: main.ts
      type: file
      content: |
        console.log('hello');
- path: empty
  type: directory
- path: README.md
  type: file
  content: "Demo\n"
```

This is a purpose-built subset, not a general YAML implementation. It supports
block mappings/sequences, inline sequence mappings, a dash on its own line,
quoted scalars, empty arrays, and literal block scalars (`|`, `|-`, `|+`).
Literal content preserves its indentation, comments, and blank lines.

Duplicate properties, anchors, aliases, tags, folded block scalars (`>`), and
nonempty flow collections are unsupported and fail validation. Use JSON for
complex flow-style input. Exported YAML uses the parser's supported subset.

## Content and template directives

Text formats accept whitespace-separated directives after an entry:

```text
- README.md @content:Hello world
- empty.txt @content64:
- src/main.ts @template:react-vite
```

`@content:` supplies a single-line literal. `@content64:` supplies Base64
of UTF-8 bytes, allowing exact multiline or empty content.
`@template:` selects a template context for stub generation; it does not
insert the entire project preset at that path. Use scaffold's template option
to create a complete preset.

Content resolution prefers explicit content, then a content directive, then the
template/file stub. For complex content, prefer JSON/YAML content strings or
Base64 rather than combining multiple inline directives.

## Path and hierarchy validation

Paths must remain relative and inside the destination. Validation rejects
absolute/UNC paths, dot and dot-dot components, repeated separators, alternate
data streams, control characters, invalid Windows filename characters, reserved
device names, trailing dots/spaces, and oversized components.
A harmless filename containing two dots, such as `file..txt`, is permitted.

Duplicate normalized paths and file/directory conflicts are invalid.
Existing reparse points in write paths or their ancestors are rejected.
These checks do not constitute an operating-system sandbox against a separate
process changing the filesystem between validation and execution.

## Merge and round-trips

Importable output is dash format without presentation headers. Merge retains
content/template metadata and uses Base64 content directives where needed.
Missing ancestor directories are inferred.

Union rejects incompatible explicit content/template metadata or conflicting
types. Preference strategies keep the preferred type/subtree and preferred
metadata, using the other input to fill absent metadata.

Use importable/JSON/YAML exports for reusable layouts. Markdown and plain-text
exports are display formats and may contain headers or decoration.
A local or remote layout export cannot recover original file contents;
round-tripping a layout preserves supported structure, not the original source
files or every presentation detail.
