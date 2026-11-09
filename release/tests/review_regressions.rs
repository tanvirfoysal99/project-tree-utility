mod common;
#[cfg(windows)]
use project_tree_utility::scan::Scope;
use project_tree_utility::{
    cli::Options,
    formats::{self, Entry},
    library::Library,
    operations,
};
use std::{fs, path::Path};

#[test]
fn detection_does_not_treat_content_as_yaml_keys() {
    let text = "- README.md @content:type: example\n";
    assert_eq!(
        formats::detect(Path::new("layout.txt"), text).unwrap(),
        "dash"
    );
    assert_eq!(
        formats::detect(Path::new("layout.txt"), "- path: src\n  type: directory\n").unwrap(),
        "yaml"
    );
}

#[test]
fn display_keeps_descendants_with_their_actual_parent() {
    let entries = formats::normalize(vec![
        Entry::new("src/a", false),
        Entry::new("src-other/b", false),
    ])
    .unwrap();
    assert_eq!(
        formats::render(&entries, "txt").unwrap(),
        "src/\n  a\nsrc-other/\n  b\n"
    );
}

#[test]
fn markdown_fence_cannot_be_closed_by_a_filename() {
    let entries = formats::normalize(vec![Entry::new("```", false)]).unwrap();
    let markdown = formats::render(&entries, "md").unwrap();
    assert!(markdown.starts_with("# Project structure\n\n````text\n"));
    assert!(markdown.ends_with("````\n"));
}

#[test]
fn failed_library_commit_preserves_memory_and_disk() {
    let temp = common::fixture();
    let mut library = Library::open(temp.path()).unwrap();
    library.save("original", "test", vec![]).unwrap();
    let before = fs::read(temp.path().join("library.json")).unwrap();
    fs::create_dir(temp.path().join("library.json.bak")).unwrap();
    assert!(library.rename("original", "renamed").is_err());
    assert!(library.find("original").is_some());
    assert!(library.find("renamed").is_none());
    assert!(library.save("failed", "test", vec![]).is_err());
    assert!(library.find("failed").is_none());
    assert_eq!(fs::read(temp.path().join("library.json")).unwrap(), before);
}

#[test]
fn end_of_options_preserves_literal_ci_filename() {
    let args = ["import", "--", "--ci", "dash", "out.txt"].map(str::to_owned);
    let options = Options::parse(&args).unwrap();
    assert_eq!(options.get("structure"), Some("--ci"));
    assert_eq!(options.get("format"), Some("dash"));
}

#[test]
fn invalid_library_command_does_not_create_data_directory() {
    let temp = common::fixture();
    assert_eq!(
        common::cli(&["library"], temp.path()).status.code(),
        Some(2)
    );
    assert!(!temp.path().join("library-data").exists());
}

#[test]
fn readonly_overwrite_is_refused_before_other_files_are_created() {
    let temp = common::fixture();
    let path = temp.path().join("z-existing");
    fs::write(&path, "keep").unwrap();
    let original = fs::metadata(&path).unwrap().permissions();
    let mut readonly = original.clone();
    readonly.set_readonly(true);
    fs::set_permissions(&path, readonly).unwrap();
    let entries = formats::normalize(vec![
        Entry::new("a-first", false),
        Entry::new("z-existing", false),
    ])
    .unwrap();
    let refused = operations::scaffold(temp.path(), &entries, "overwrite", false, false).is_err();
    let partial = temp.path().join("a-first").exists();
    fs::set_permissions(&path, original).unwrap();
    assert!(refused);
    assert!(!partial);
}

#[cfg(windows)]
#[test]
fn possible_move_protection_uses_windows_case_rules() {
    let temp = common::fixture();
    fs::create_dir(temp.path().join("old")).unwrap();
    fs::write(temp.path().join("old/main.rs"), "keep").unwrap();
    let expected = formats::normalize(vec![Entry::new("new/MAIN.RS", false)]).unwrap();
    operations::verify(
        temp.path(),
        &expected,
        &Scope {
            max_depth: 0,
            ..Scope::default()
        },
        true,
        true,
    )
    .unwrap();
    assert_eq!(
        fs::read_to_string(temp.path().join("old/main.rs")).unwrap(),
        "keep"
    );
}

#[cfg(unix)]
#[test]
fn atomic_overwrite_preserves_executable_permissions() {
    use std::os::unix::fs::PermissionsExt;
    let temp = common::fixture();
    let path = temp.path().join("script");
    fs::write(&path, "old").unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o750)).unwrap();
    project_tree_utility::safety::atomic_write(&path, b"new").unwrap();
    assert_eq!(
        fs::metadata(path).unwrap().permissions().mode() & 0o777,
        0o750
    );
}

#[test]
fn unicode_library_names_use_the_same_case_rules_for_save_and_load() {
    let temp = common::fixture();
    {
        let mut library = Library::open(temp.path()).unwrap();
        assert_eq!(library.save("Étage", "test", vec![]).unwrap(), "Étage");
        assert_eq!(library.save("étage", "test", vec![]).unwrap(), "étage-2");
        assert_eq!(library.find("éTAGE").unwrap().id, 1);
        assert!(library.rename("étage-2", "ÉTAGE").is_err());
    }
    assert_eq!(Library::open(temp.path()).unwrap().list().len(), 2);
}
