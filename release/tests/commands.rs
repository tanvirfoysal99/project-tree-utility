mod common;
use std::fs;

const COMMANDS: &[&str] = &[
    "import",
    "export",
    "scaffold",
    "verify",
    "merge",
    "watch",
    "gittree",
    "auth",
    "library",
    "security",
    "detection",
    "version",
];

#[test]
fn every_command_has_help_and_missing_inputs_fail_without_mutation() {
    let temp = common::fixture();
    for command in COMMANDS {
        common::success(&common::cli(&[command, "--help"], temp.path()));
        if *command != "version" {
            assert_eq!(
                common::cli(&[command, "--ci"], temp.path()).status.code(),
                Some(2),
                "{command}"
            );
        }
    }
    assert_eq!(fs::read_dir(temp.path()).unwrap().count(), 0);
}

#[test]
fn import_export_all_formats_and_display_modes() {
    let temp = common::fixture();
    fs::create_dir_all(temp.path().join("live/src")).unwrap();
    fs::write(temp.path().join("live/src/main.rs"), "source bytes").unwrap();
    for format in [
        "importable",
        "dash",
        "treesym",
        "json",
        "yaml",
        "txt",
        "md",
        "summary",
    ] {
        let output = format!("export-{format}");
        common::success(&common::cli(
            &[
                "export", "--root", "live", "--format", format, "--output", &output,
            ],
            temp.path(),
        ));
        assert!(temp.path().join(&output).is_file());
        if ["json", "yaml", "importable", "dash", "treesym"].contains(&format) {
            for target in [
                "json",
                "yaml",
                "importable",
                "treesym",
                "txt",
                "md",
                "summary",
            ] {
                common::success(&common::cli(
                    &[
                        "import",
                        "--structure",
                        &output,
                        "--format",
                        format,
                        "--output",
                        "converted",
                        "--output-format",
                        target,
                    ],
                    temp.path(),
                ));
            }
        }
    }
    for mode in ["all", "files", "folders"] {
        common::success(&common::cli(
            &[
                "export",
                "--root",
                "live",
                "--format",
                "json",
                "--output",
                "filtered.json",
                "--show-mode",
                mode,
            ],
            temp.path(),
        ));
    }
}

#[test]
fn tree_symbol_export_and_files_only_context_work_through_cli() {
    let temp = common::fixture();
    fs::create_dir_all(temp.path().join("live/src")).unwrap();
    fs::create_dir(temp.path().join("live/empty")).unwrap();
    fs::write(temp.path().join("live/src/main.rs"), "source bytes").unwrap();
    for mode in ["all", "files", "folders"] {
        common::success(&common::cli(
            &[
                "export",
                "--root",
                "live",
                "--format",
                "treesym",
                "--output",
                "tree.txt",
                "--max-depth",
                "0",
                "--show-mode",
                mode,
            ],
            temp.path(),
        ));
        let tree = fs::read_to_string(temp.path().join("tree.txt")).unwrap();
        assert!(tree.contains("src/"));
        if mode == "all" {
            assert_eq!(tree, "├── empty/\n└── src/\n    └── main.rs\n");
        }
        if mode == "files" {
            assert_eq!(tree, "└── src/\n    └── main.rs\n");
        }
        if mode == "folders" {
            assert!(!tree.contains("main.rs"));
        }
        common::success(&common::cli(
            &[
                "import",
                "--structure",
                "tree.txt",
                "--output",
                "parsed.json",
                "--output-format",
                "json",
            ],
            temp.path(),
        ));
    }
    let help = common::cli(&["export", "--help"], temp.path());
    common::success(&help);
    assert!(String::from_utf8_lossy(&help.stdout).contains("--format treesym"));
}

#[test]
fn merge_and_detection_exercise_all_strategies_and_metadata() {
    let temp = common::fixture();
    fs::write(temp.path().join("a.txt"), "- file @content:a\n").unwrap();
    fs::write(temp.path().join("b.txt"), "- file @content:b\n- extra/\n").unwrap();
    assert_eq!(
        common::cli(
            &[
                "merge", "a.txt", "dash", "b.txt", "dash", "union", "out.txt"
            ],
            temp.path()
        )
        .status
        .code(),
        Some(2)
    );
    assert!(!temp.path().join("out.txt").exists());
    for strategy in ["a_over_b", "b_over_a"] {
        common::success(&common::cli(
            &[
                "merge", "a.txt", "dash", "b.txt", "dash", strategy, "out.txt",
            ],
            temp.path(),
        ));
        common::success(&common::cli(
            &[
                "detection",
                "BUILD_TREE",
                "a.txt",
                "dash",
                "b.txt",
                "dash",
                strategy,
                "out.txt",
            ],
            temp.path(),
        ));
    }
    common::success(&common::cli(
        &["detection", "ANALYSE", "a.txt", "dash"],
        temp.path(),
    ));
}

#[test]
fn every_security_action_accepts_valid_input_and_rejects_invalid_input() {
    let temp = common::fixture();
    fs::write(temp.path().join("layout.txt"), "- src/main.rs\n").unwrap();
    fs::write(temp.path().join("bad.txt"), "- ../escape\n").unwrap();
    for action in ["VALIDATE_FILE", "VALIDATE_NAMES", "VALIDATE_ALL"] {
        let args = if action == "VALIDATE_ALL" {
            vec!["security", action, "layout.txt", "dash", "."]
        } else {
            vec!["security", action, "layout.txt", "dash"]
        };
        common::success(&common::cli(&args, temp.path()));
        assert_eq!(
            common::cli(&["security", action, "bad.txt", "dash", "."], temp.path())
                .status
                .code(),
            Some(2)
        );
    }
    common::success(&common::cli(
        &["security", "VALIDATE_PATH", "child", "."],
        temp.path(),
    ));
    assert_eq!(
        common::cli(
            &["security", "VALIDATE_PATH", "../outside", "."],
            temp.path()
        )
        .status
        .code(),
        Some(1)
    );
}

#[test]
fn all_templates_scaffold_and_verify_generated_layouts() {
    let temp = common::fixture();
    for template in ["react-vite", "hono-worker", "monorepo-pnpm"] {
        common::success(&common::cli(
            &[
                "scaffold",
                "--template",
                template,
                "--target",
                ".",
                "--project",
                template,
            ],
            temp.path(),
        ));
        common::success(&common::cli(
            &[
                "export",
                "--root",
                template,
                "--format",
                "json",
                "--output",
                "expected.json",
                "--max-depth",
                "0",
            ],
            temp.path(),
        ));
        common::success(&common::cli(
            &["verify", "--live", template, "--structure", "expected.json"],
            temp.path(),
        ));
        assert!(temp.path().join(template).join("package.json").exists());
    }
}

#[test]
fn verify_sync_and_delete_exit_codes_reflect_final_state() {
    let temp = common::fixture();
    fs::create_dir(temp.path().join("live")).unwrap();
    fs::write(
        temp.path().join("layout.txt"),
        "- src/main.rs @content:created\n",
    )
    .unwrap();
    assert_eq!(
        common::cli(&["verify", "live", "layout.txt", "dash"], temp.path())
            .status
            .code(),
        Some(1)
    );
    common::success(&common::cli(
        &["verify", "live", "layout.txt", "dash", "--sync"],
        temp.path(),
    ));
    fs::write(temp.path().join("live/extra"), "remove").unwrap();
    common::success(&common::cli(
        &[
            "verify",
            "live",
            "layout.txt",
            "dash",
            "--sync",
            "--delete-extras",
        ],
        temp.path(),
    ));
    assert!(!temp.path().join("live/extra").exists());
    assert_eq!(
        fs::read_to_string(temp.path().join("live/src/main.rs")).unwrap(),
        "created"
    );
}

#[test]
fn malformed_remote_and_auth_commands_fail_before_network_or_storage() {
    let temp = common::fixture();
    for args in [
        vec![
            "gittree",
            "--provider",
            "github",
            "--repo",
            "https://github.com/a/b",
            "--branch",
            "main",
        ],
        vec![
            "gittree",
            "--provider",
            "github",
            "--repo",
            "http://github.com/a/b",
            "--branch",
            "main",
            "--format",
            "json",
            "--output",
            "out",
            "--anonymous",
        ],
        vec!["auth", "--ci", "store", "https://example.invalid"],
        vec![
            "auth",
            "--ci",
            "clear",
            "https://example.invalid",
            "--secret-stdin",
        ],
    ] {
        assert_eq!(
            common::cli(&args, temp.path()).status.code(),
            Some(2),
            "{args:?}"
        );
    }
    assert_eq!(fs::read_dir(temp.path()).unwrap().count(), 0);
}

#[test]
fn all_six_input_formats_work_through_the_executable() {
    let temp = common::fixture();
    for (format, text) in [
        ("dash", "- src/\n-- main.rs\n"),
        ("space", "src/\n  main.rs\n"),
        ("tab", "src/\n\tmain.rs\n"),
        ("treesym", "├── src/\n│   └── main.rs\n"),
        ("json", r#"[{"path":"src/main.rs"}]"#),
        ("yaml", "- path: src/main.rs\n"),
    ] {
        fs::write(temp.path().join("input.txt"), text).unwrap();
        common::success(&common::cli(
            &[
                "import",
                "--structure",
                "input.txt",
                "--format",
                format,
                "--output",
                "out.json",
                "--output-format",
                "json",
            ],
            temp.path(),
        ));
        assert!(
            fs::read_to_string(temp.path().join("out.json"))
                .unwrap()
                .contains("src/main.rs")
        );
    }
}

#[test]
fn library_list_save_open_rename_delete_and_purge_work_through_cli() {
    let temp = common::fixture();
    fs::write(temp.path().join("layout.txt"), "- src/main.rs\n").unwrap();
    common::success(&common::cli(
        &[
            "library",
            "--action",
            "save",
            "--file",
            "layout.txt",
            "--format",
            "dash",
            "--name",
            "starter",
        ],
        temp.path(),
    ));
    let list = common::cli(&["library", "list"], temp.path());
    common::success(&list);
    assert!(String::from_utf8_lossy(&list.stdout).contains("starter"));
    common::success(&common::cli(&["library", "open", "starter"], temp.path()));
    common::success(&common::cli(
        &["library", "rename", "starter", "renamed"],
        temp.path(),
    ));
    common::success(&common::cli(&["library", "delete", "renamed"], temp.path()));
    assert_eq!(
        common::cli(&["library", "open", "renamed"], temp.path())
            .status
            .code(),
        Some(1)
    );
    common::success(&common::cli(&["library", "purge", "--yes"], temp.path()));
}
