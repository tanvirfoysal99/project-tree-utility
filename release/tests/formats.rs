use project_tree_utility::{
    formats::{self, Entry},
    safety,
};

#[test]
fn all_reusable_formats_preserve_exact_content_and_templates() {
    let source = "- src/\n-- main.ts @content64:SGVsbG8K\n- empty.txt @content64:\n- other.ts @template:react-vite\n";
    let expected = formats::parse(source, "dash", 2).unwrap();
    for format in ["importable", "json", "yaml"] {
        let text = formats::render(&expected, format).unwrap();
        assert_eq!(
            formats::parse(&text, format, 2).unwrap(),
            expected,
            "{format}"
        );
    }
    assert_eq!(
        expected
            .iter()
            .find(|e| e.path == "empty.txt")
            .unwrap()
            .content
            .as_deref(),
        Some("")
    );
}

#[test]
fn all_text_indentations_produce_the_same_layout() {
    let cases = [
        ("dash", "- src/\n-- main.rs\n- README.md\n"),
        ("space", "src/\n  main.rs\nREADME.md\n"),
        ("tab", "src/\n\tmain.rs\nREADME.md\n"),
        ("treesym", "├── src/\n│   └── main.rs\n└── README.md\n"),
    ];
    let expected = formats::parse(cases[0].1, cases[0].0, 2).unwrap();
    for (format, text) in cases {
        assert_eq!(formats::parse(text, format, 2).unwrap(), expected);
    }
}

#[test]
fn json_nested_nodes_and_aliases_are_supported() {
    let entries = formats::parse(r#"{"entries":[{"Name":"src","Type":"tree","children":[{"name":"main.rs","type":"blob","content":""}]},{"path":"empty/"}]}"#, "json", 2).unwrap();
    assert_eq!(entries.len(), 3);
    assert_eq!(
        entries
            .iter()
            .find(|e| e.path == "src/main.rs")
            .unwrap()
            .content
            .as_deref(),
        Some("")
    );
}

#[test]
fn yaml_literal_content_preserves_indentation_and_comments() {
    let entries = formats::parse("- path: script.py\n  type: file\n  content: |\n    # comment\n    if True:\n      print('hello')\n", "yaml", 2).unwrap();
    assert_eq!(
        entries[0].content.as_deref(),
        Some("# comment\nif True:\n  print('hello')\n")
    );
}

#[test]
fn malformed_schema_is_rejected() {
    for text in [
        r#"[{"path":"a","PATH":"b"}]"#,
        r#"[{"path":"a","surprise":true}]"#,
        r#"[{"path":"a","isDir":"true"}]"#,
        r#"[{"path":"a","type":"file","isDir":true}]"#,
        r#"[{"path":"a","type":"file","children":[]}]"#,
        r#"[{"path":"a","type":"directory","content":"bad"}]"#,
        r#"[{"path":"a"},{"path":"A"}]"#,
        r#"[{"path":"a","type":"file"},{"path":"a/b"}]"#,
    ] {
        assert!(formats::parse(text, "json", 2).is_err(), "accepted {text}");
    }
}

#[test]
fn yaml_anchors_tags_duplicate_keys_and_multiple_documents_are_rejected() {
    for text in [
        "- &anchor a\n- *anchor\n",
        "- path: !!str a\n",
        "- path: a\n  path: b\n",
        "---\n- a\n---\n- b\n",
    ] {
        assert!(formats::parse(text, "yaml", 2).is_err(), "accepted {text}");
    }
}

#[test]
fn malformed_indentation_and_directives_are_rejected() {
    for (text, format) in [
        ("- a/\n--- b\n", "dash"),
        ("a/\n   b\n", "space"),
        ("a/\n\t b\n", "tab"),
        ("- a @content64:%%%\n", "dash"),
        ("- a/ @content:x\n", "dash"),
    ] {
        assert!(formats::parse(text, format, 2).is_err(), "accepted {text}");
    }
}

#[test]
fn portable_names_reject_traversal_devices_and_streams() {
    for path in [
        "../secret",
        "/absolute",
        "C:/absolute",
        "a//b",
        "a/./b",
        "a/../b",
        "NUL.txt",
        "COM1",
        "LPT¹.log",
        "x:stream",
        "trailing.",
        "trailing ",
        "a\0b",
        "a?b",
        "\\\\host\\share",
    ] {
        assert!(safety::relative_path(path).is_err(), "accepted {path}");
    }
    assert_eq!(
        safety::relative_path("src\\file..txt").unwrap(),
        "src/file..txt"
    );
    assert!(safety::relative_path(&"x".repeat(256)).is_err());
}

#[test]
fn implicit_ancestors_and_case_are_canonicalized() {
    let entries = formats::normalize(vec![
        Entry::new("Src/a.rs", false),
        Entry::new("src/B.rs", false),
    ])
    .unwrap();
    assert!(
        entries
            .iter()
            .all(|e| e.path == "Src" || e.path.starts_with("Src/"))
    );
}

#[test]
fn merge_union_preserves_metadata_and_rejects_conflicts() {
    let a = formats::parse("- src/main.rs @content:first\n", "dash", 2).unwrap();
    let b = formats::parse("- src/main.rs @template:react-vite\n- empty/\n", "dash", 2).unwrap();
    let merged = formats::merge(a.clone(), b, "union").unwrap();
    let file = merged.iter().find(|e| e.path == "src/main.rs").unwrap();
    assert_eq!(file.content.as_deref(), Some("first"));
    assert_eq!(file.template.as_deref(), Some("react-vite"));
    let conflict = formats::parse("- src/main.rs @content:second\n", "dash", 2).unwrap();
    assert!(formats::merge(a, conflict, "union").is_err());
}

#[test]
fn merge_preference_keeps_winning_subtree_and_type() {
    let a = formats::parse("- node @content:file\n", "dash", 2).unwrap();
    let b = formats::parse("- node/\n-- child\n", "dash", 2).unwrap();
    assert!(formats::merge(a.clone(), b.clone(), "union").is_err());
    assert_eq!(formats::merge(a.clone(), b.clone(), "a_over_b").unwrap(), a);
    assert_eq!(formats::merge(a, b.clone(), "b_over_a").unwrap(), b);
}

#[test]
fn empty_machine_readable_layouts_roundtrip() {
    assert!(formats::parse("[]", "json", 2).unwrap().is_empty());
    assert!(formats::parse("[]", "yaml", 2).unwrap().is_empty());
}

#[test]
fn limits_and_format_detection_are_enforced() {
    assert!(formats::parse("a", "space", 0).is_err());
    assert!(
        formats::parse(
            &"x".repeat(safety::MAX_INPUT_BYTES as usize + 1),
            "space",
            2
        )
        .is_err()
    );
    assert!(safety::relative_path(&vec!["a"; safety::MAX_DEPTH + 1].join("/")).is_err());
    assert_eq!(
        formats::detect(std::path::Path::new("a.yaml"), "- a").unwrap(),
        "yaml"
    );
    assert!(formats::detect(std::path::Path::new("a.txt"), "flat.txt\n").is_err());
}

#[test]
fn repeated_trailing_separators_and_unknown_templates_fail() {
    for (text, format) in [
        ("- dir//\n", "dash"),
        (r#"["dir//"]"#, "json"),
        (r#"[{"path":"dir//","type":"directory"}]"#, "json"),
        ("- a @template:unknown\n", "dash"),
    ] {
        assert!(formats::parse(text, format, 2).is_err(), "accepted {text}");
    }
}

#[test]
fn leading_spaces_and_decorator_like_names_roundtrip() {
    let entries = formats::normalize(vec![Entry::new(" leading-space.txt", false)]).unwrap();
    assert_eq!(
        formats::parse(&formats::render(&entries, "importable").unwrap(), "dash", 2).unwrap(),
        entries
    );
    let entries = formats::normalize(vec![Entry::new("literal @content-filename", false)]).unwrap();
    assert_eq!(
        formats::parse(&formats::render(&entries, "importable").unwrap(), "dash", 2).unwrap(),
        entries
    );
}

#[test]
fn exact_unicode_and_special_content_roundtrips() {
    for content in [
        "",
        "\0",
        "\r\n\t # text\n",
        "বাংলা 🦀 日本語",
        " @content64: @template: # & * !",
        " leading and trailing \n\n",
        "\"quotes\" and 'quotes' \\slashes",
        "---\n- path: nested\n",
    ] {
        let mut file = Entry::new("src/বাংলা.txt", false);
        file.content = Some(content.into());
        file.template = Some("react-vite".into());
        let entries = formats::normalize(vec![file]).unwrap();
        for format in ["json", "yaml", "importable"] {
            assert_eq!(
                formats::parse(&formats::render(&entries, format).unwrap(), format, 2).unwrap(),
                entries,
                "{format}: {content:?}"
            );
        }
    }
}

#[test]
fn tree_symbol_output_has_correct_continuations_and_last_children() {
    let entries = formats::normalize(vec![
        Entry::new("README.md", false),
        Entry::new("src/deep/leaf.rs", false),
        Entry::new("src/main.rs", false),
        Entry::new("tests/smoke.rs", false),
    ])
    .unwrap();
    let tree = formats::render(&entries, "treesym").unwrap();
    assert_eq!(
        tree,
        "├── README.md\n├── src/\n│   ├── deep/\n│   │   └── leaf.rs\n│   └── main.rs\n└── tests/\n    └── smoke.rs\n"
    );
    assert_eq!(formats::parse(&tree, "treesym", 2).unwrap(), entries);
    assert_eq!(formats::render(&[], "treesym").unwrap(), "");
}

#[test]
fn tree_symbol_output_preserves_unicode_content_templates_and_empty_directories() {
    let mut file = Entry::new("src/বাংলা.txt", false);
    file.content = Some("Hello\nবাংলা\n".into());
    file.template = Some("react-vite".into());
    let entries = formats::normalize(vec![file, Entry::new("empty", true)]).unwrap();
    let tree = formats::render(&entries, "treesym").unwrap();
    assert!(tree.contains("├── empty/\n"));
    assert!(tree.contains("@content64:"));
    assert_eq!(formats::parse(&tree, "treesym", 2).unwrap(), entries);
}
