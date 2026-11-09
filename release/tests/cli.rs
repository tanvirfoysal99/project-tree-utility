mod common;
use project_tree_utility::cli::Options;
use std::{
    fs,
    io::Write,
    process::{Command, Stdio},
};

fn parse(args: &[&str]) -> anyhow::Result<Options> {
    Options::parse(&args.iter().map(|s| s.to_string()).collect::<Vec<_>>())
}

#[test]
fn parser_preserves_aliases_positionals_and_global_ci() {
    let options = parse(&["--ci", "export", "C:/project", "json", "output.json", "0"]).unwrap();
    assert!(options.ci);
    assert_eq!(options.get("max-depth"), Some("0"));
    let options = parse(&[
        "import",
        "-StructureFile",
        "a.txt",
        "-OutputFile",
        "out.txt",
        "--format=dash",
    ])
    .unwrap();
    assert_eq!(options.get("structure"), Some("a.txt"));
}

#[test]
fn parser_rejects_unknown_duplicate_and_conflicting_arguments() {
    for args in [
        vec!["export", "--surprise", "x"],
        vec!["import", "--format", "dash", "--format", "json"],
        vec!["import", "a", "--structure", "b"],
        vec!["scaffold", "--dry-run=true"],
        vec!["version", "extra"],
        vec!["verify", "--live"],
    ] {
        assert!(parse(&args).is_err(), "accepted {args:?}");
    }
}

#[test]
fn library_and_detection_legacy_forms_are_mapped() {
    let o = parse(&["library", "save", "layout", "dash", "manual", "starter"]).unwrap();
    assert_eq!(o.get("name"), Some("starter"));
    let o = parse(&["detection", "ANALYSE", "layout", "dash"]).unwrap();
    assert_eq!(o.command, "import");
    assert_eq!(o.get("output-format"), Some("summary"));
    let o = parse(&["security", "VALIDATE_PATH", "candidate", "base"]).unwrap();
    assert_eq!(o.get("candidate"), Some("candidate"));
}

#[test]
fn help_version_and_empty_piped_input_do_not_block() {
    let temp = common::fixture();
    for args in [
        vec!["--help"],
        vec!["help"],
        vec!["version"],
        vec!["--version"],
        vec!["detection", "--help"],
        vec![],
    ] {
        common::success(&common::cli(&args, temp.path()));
    }
    let output = common::cli(&["--ci"], temp.path());
    assert_eq!(output.status.code(), Some(2));
}

#[test]
fn interactive_commands_accept_windows_and_unix_line_endings() {
    use project_tree_utility::cli::parse_interactive;
    for ending in ["\r\n", "\n", "\r", ""] {
        for command in ["--help", "-h", "help", "export --help"] {
            let options = parse_interactive(&format!("{command}{ending}")).unwrap();
            assert!(options.help, "{command:?} with ending {ending:?}");
        }
        let options = parse_interactive(&format!("version{ending}")).unwrap();
        assert_eq!(options.command, "version");
        let options = parse_interactive(&format!(
            "export --root 'C:/Projects/my app' --format json --output 'layout file.json'{ending}"
        ))
        .unwrap();
        assert_eq!(options.get("root"), Some("C:/Projects/my app"));
        assert_eq!(options.get("output"), Some("layout file.json"));
    }
}

#[test]
fn cli_import_scaffold_export_and_verify_roundtrip() {
    let temp = common::fixture();
    fs::write(
        temp.path().join("layout.txt"),
        "- src/\n-- main.rs @content:hello\n- empty/\n- _creation_log.txt\n",
    )
    .unwrap();
    // Creation log is reserved for scaffold, so use a separate input.
    fs::write(
        temp.path().join("create.txt"),
        "- src/\n-- main.rs @content:hello\n- empty/\n",
    )
    .unwrap();
    common::success(&common::cli(
        &[
            "scaffold",
            "--ci",
            "--structure",
            "create.txt",
            "--format",
            "dash",
            "--target",
            ".",
            "--project",
            "project with spaces",
        ],
        temp.path(),
    ));
    common::success(&common::cli(
        &[
            "verify",
            "--ci",
            "--live",
            "project with spaces",
            "--structure",
            "layout.txt",
            "--format",
            "dash",
        ],
        temp.path(),
    ));
    common::success(&common::cli(
        &[
            "export",
            "--ci",
            "--root",
            "project with spaces",
            "--format",
            "json",
            "--output",
            "export.json",
            "--max-depth",
            "0",
        ],
        temp.path(),
    ));
    common::success(&common::cli(
        &[
            "import",
            "--ci",
            "--structure",
            "export.json",
            "--output",
            "roundtrip.yaml",
            "--output-format",
            "yaml",
        ],
        temp.path(),
    ));
    assert!(
        fs::read_to_string(temp.path().join("roundtrip.yaml"))
            .unwrap()
            .contains("src/main.rs")
    );
    fs::write(temp.path().join("project with spaces/extra"), "").unwrap();
    assert_eq!(
        common::cli(
            &[
                "verify",
                "--ci",
                "project with spaces",
                "layout.txt",
                "dash"
            ],
            temp.path()
        )
        .status
        .code(),
        Some(1)
    );
}

#[test]
fn cli_dry_run_and_invalid_inputs_do_not_create_projects() {
    let temp = common::fixture();
    fs::write(temp.path().join("bad.txt"), "- ../escape\n").unwrap();
    let output = common::cli(
        &[
            "scaffold",
            "--structure",
            "bad.txt",
            "--format",
            "dash",
            "--target",
            ".",
            "--project",
            "safe",
        ],
        temp.path(),
    );
    assert_eq!(output.status.code(), Some(2));
    assert!(!temp.path().join("safe").exists());
    common::success(&common::cli(
        &[
            "scaffold",
            "--template",
            "react-vite",
            "--target",
            ".",
            "--project",
            "preview",
            "--dry-run",
        ],
        temp.path(),
    ));
    assert!(!temp.path().join("preview").exists());
}

#[test]
fn library_cli_is_isolated_from_legacy_data() {
    let temp = common::fixture();
    fs::write(temp.path().join("layout.txt"), "- src/main.rs\n").unwrap();
    common::success(&common::cli(
        &["library", "save", "layout.txt", "dash", "manual", "starter"],
        temp.path(),
    ));
    common::success(&common::cli(
        &["library", "rename", "starter", "new"],
        temp.path(),
    ));
    let output = common::cli(&["library", "open", "new"], temp.path());
    common::success(&output);
    let output_path = String::from_utf8(output.stdout).unwrap();
    assert!(std::path::Path::new(output_path.trim()).is_file());
    assert_eq!(
        common::cli(&["library", "purge"], temp.path())
            .status
            .code(),
        Some(2)
    );
    common::success(&common::cli(&["library", "purge", "--yes"], temp.path()));
    assert_eq!(
        common::cli(&["library", "open", "new"], temp.path())
            .status
            .code(),
        Some(1)
    );
}

#[test]
fn bad_credentials_are_rejected_without_exposing_input() {
    let temp = common::fixture();
    let secret = "dummy-secret-not-a-real-token";
    let output = common::cli(
        &["auth", "--ci", "store", "https://user:password@example.com"],
        temp.path(),
    );
    assert_eq!(output.status.code(), Some(2));
    let mut child = Command::new(common::binary())
        .args([
            "auth",
            "--ci",
            "store",
            "https://example.invalid",
            "--secret-stdin",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    // Empty token is rejected before accessing any credential vault.
    child.stdin.take().unwrap().write_all(b"\n").unwrap();
    let output = child.wait_with_output().unwrap();
    assert_eq!(output.status.code(), Some(2));
    let output = Command::new(common::binary())
        .args([
            "auth",
            "--ci",
            "store",
            "https://example.invalid",
            "--secret-env",
            "PTU_FIXTURE_TOKEN",
        ])
        .env("PTU_FIXTURE_TOKEN", format!("{secret}\nbad"))
        .output()
        .unwrap();
    assert_eq!(output.status.code(), Some(2));
    assert!(!String::from_utf8_lossy(&output.stderr).contains(secret));
    assert!(!String::from_utf8_lossy(&output.stdout).contains(secret));
}

#[test]
fn files_only_json_retains_required_ancestors() {
    let temp = common::fixture();
    fs::create_dir_all(temp.path().join("project/src")).unwrap();
    fs::write(temp.path().join("project/src/a"), "").unwrap();
    common::success(&common::cli(
        &[
            "export",
            "--root",
            "project",
            "--format",
            "json",
            "--output",
            "files.json",
            "--show-mode",
            "files",
        ],
        temp.path(),
    ));
    let entries =
        project_tree_utility::formats::read(&temp.path().join("files.json"), None, 2).unwrap();
    assert_eq!(entries.len(), 2);
    assert!(entries[0].is_dir);
}

#[test]
fn explicit_scan_options_override_configuration() {
    let temp = common::fixture();
    fs::create_dir_all(temp.path().join("project/src")).unwrap();
    fs::write(temp.path().join("project/src/a"), "").unwrap();
    fs::write(
        temp.path().join("project/.treeignore"),
        "maxdepth: 1\nshowmode: folders\n",
    )
    .unwrap();
    common::success(&common::cli(
        &[
            "export",
            "--root",
            "project",
            "--format",
            "json",
            "--output",
            "all.json",
            "--max-depth",
            "0",
            "--show-mode",
            "all",
        ],
        temp.path(),
    ));
    assert!(
        fs::read_to_string(temp.path().join("all.json"))
            .unwrap()
            .contains("src/a")
    );
}
