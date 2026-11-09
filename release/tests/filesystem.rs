mod common;
use project_tree_utility::{
    formats::{self, Entry},
    operations, safety,
    scan::{self, Scope},
};
use std::fs;

fn layout() -> Vec<Entry> {
    formats::parse("- src/\n-- main.rs @content:hello\n- empty/\n", "dash", 2).unwrap()
}
fn unlimited() -> Scope {
    Scope {
        max_depth: 0,
        ..Scope::default()
    }
}

#[test]
fn dry_run_has_no_filesystem_side_effects() {
    let temp = common::fixture();
    let root = temp.path().join("new");
    operations::scaffold(&root, &layout(), "skip", true, false).unwrap();
    assert!(!root.exists());
}

#[test]
fn scaffold_creates_content_and_respects_overwrite_modes() {
    let temp = common::fixture();
    let root = temp.path().join("new");
    operations::scaffold(&root, &layout(), "skip", false, false).unwrap();
    assert_eq!(
        fs::read_to_string(root.join("src/main.rs")).unwrap(),
        "hello"
    );
    fs::write(root.join("src/main.rs"), "custom").unwrap();
    assert_eq!(
        operations::scaffold(&root, &layout(), "skip", false, false)
            .unwrap()
            .skipped,
        1
    );
    assert_eq!(
        fs::read_to_string(root.join("src/main.rs")).unwrap(),
        "custom"
    );
    assert_eq!(
        operations::scaffold(&root, &layout(), "overwrite", false, false)
            .unwrap()
            .overwritten,
        1
    );
    assert_eq!(
        fs::read_to_string(root.join("src/main.rs")).unwrap(),
        "hello"
    );
    assert!(operations::scaffold(&root, &layout(), "ask", false, false).is_err());
}

#[test]
fn scaffold_preflight_prevents_partial_writes_on_type_conflict() {
    let temp = common::fixture();
    fs::write(temp.path().join("src"), "existing").unwrap();
    let mut entries = layout();
    entries.push(Entry::new("a-first", false));
    assert!(operations::scaffold(temp.path(), &entries, "overwrite", false, false).is_err());
    assert!(!temp.path().join("a-first").exists());
}

#[test]
fn reserved_log_cannot_be_supplied_by_structure() {
    let temp = common::fixture();
    assert!(
        operations::scaffold(
            temp.path(),
            &[Entry::new("_creation_log.txt", false)],
            "skip",
            false,
            false
        )
        .is_err()
    );
}

#[test]
fn scan_scope_is_shared_with_comparison() {
    let temp = common::fixture();
    fs::create_dir_all(temp.path().join("src/deep")).unwrap();
    fs::create_dir_all(temp.path().join("node_modules/pkg")).unwrap();
    fs::write(temp.path().join("src/deep/a"), "").unwrap();
    let scope = Scope {
        max_depth: 1,
        ..Scope::default()
    };
    let actual = scan::scan(temp.path(), &scope).unwrap();
    assert_eq!(actual, vec![Entry::new("src", true)]);
    let expected = formats::normalize(vec![
        Entry::new("src/deep/a", false),
        Entry::new("node_modules/pkg", true),
    ])
    .unwrap();
    assert!(scan::compare(&expected, &actual, &scope).clean());
}

#[test]
fn verify_sync_creates_missing_without_overwriting_existing_bytes() {
    let temp = common::fixture();
    fs::create_dir(temp.path().join("src")).unwrap();
    fs::write(temp.path().join("src/main.rs"), "custom").unwrap();
    let (report, _) =
        operations::verify(temp.path(), &layout(), &unlimited(), true, false).unwrap();
    assert!(report.clean());
    assert_eq!(
        fs::read_to_string(temp.path().join("src/main.rs")).unwrap(),
        "custom"
    );
}

#[test]
fn delete_extras_preserves_excluded_descendants() {
    let temp = common::fixture();
    fs::create_dir_all(temp.path().join("extra/node_modules")).unwrap();
    fs::write(temp.path().join("extra/node_modules/precious"), "keep").unwrap();
    fs::write(temp.path().join("extra/delete-me"), "remove").unwrap();
    let (_, counts) = operations::verify(temp.path(), &[], &unlimited(), true, true).unwrap();
    assert_eq!(counts.deleted, 1);
    assert!(temp.path().join("extra/node_modules/precious").exists());
    assert!(!temp.path().join("extra/delete-me").exists());
}

#[test]
fn delete_extras_preserves_possible_move_sources() {
    let temp = common::fixture();
    fs::create_dir(temp.path().join("old")).unwrap();
    fs::write(temp.path().join("old/main.rs"), "precious").unwrap();
    let expected = formats::normalize(vec![Entry::new("new/main.rs", false)]).unwrap();
    let (report, _) = operations::verify(temp.path(), &expected, &unlimited(), true, true).unwrap();
    assert!(!report.clean());
    assert_eq!(
        fs::read_to_string(temp.path().join("old/main.rs")).unwrap(),
        "precious"
    );
}

#[test]
fn deletion_requires_sync_and_type_conflicts_refuse_mutation() {
    let temp = common::fixture();
    fs::write(temp.path().join("src"), "keep").unwrap();
    assert!(operations::verify(temp.path(), &layout(), &unlimited(), false, true).is_err());
    assert!(operations::verify(temp.path(), &layout(), &unlimited(), true, true).is_err());
    assert_eq!(fs::read_to_string(temp.path().join("src")).unwrap(), "keep");
    assert!(!temp.path().join("empty").exists());
}

#[test]
fn atomic_output_does_not_damage_existing_file_on_error() {
    let temp = common::fixture();
    let path = temp.path().join("output");
    fs::write(&path, "original").unwrap();
    safety::atomic_write(&path, b"replacement").unwrap();
    assert_eq!(fs::read_to_string(&path).unwrap(), "replacement");
    assert!(safety::atomic_write(&temp.path().join("missing/file"), b"bad").is_err());
    assert_eq!(fs::read_to_string(path).unwrap(), "replacement");
}

#[test]
fn configuration_precedence_and_hidden_files() {
    let temp = common::fixture();
    fs::write(
        temp.path().join(".treeignore"),
        "exclude: cache; generated/assets\nmaxdepth=0\nshowmode: files\n",
    )
    .unwrap();
    fs::write(temp.path().join(".hidden"), "").unwrap();
    let scope = Scope::load(temp.path(), None).unwrap();
    assert_eq!(scope.max_depth, 0);
    assert_eq!(scope.show_mode, "files");
    assert!(!scope.includes("cache/a"));
    assert!(!scope.includes("generated/assets/a"));
    assert!(
        scan::scan(temp.path(), &scope)
            .unwrap()
            .iter()
            .any(|e| e.path == ".hidden")
    );
    assert!(Scope::load(temp.path(), Some(&temp.path().join("missing"))).is_err());
}

#[test]
fn containment_rejects_sibling_prefixes() {
    let temp = common::fixture();
    let base = temp.path().join("base");
    assert!(safety::contained(&base, &temp.path().join("base-other/file")).is_err());
    assert!(safety::destination(&base, "../escape").is_err());
}

#[cfg(unix)]
#[test]
fn symlinks_refuse_scans_writes_and_sync() {
    use std::os::unix::fs::symlink;
    let temp = common::fixture();
    let outside = common::fixture();
    symlink(outside.path(), temp.path().join("link")).unwrap();
    assert!(scan::scan(temp.path(), &unlimited()).is_err());
    assert!(safety::destination(temp.path(), "link/escape").is_err());
    assert!(operations::verify(temp.path(), &layout(), &unlimited(), true, true).is_err());
    assert!(!temp.path().join("src").exists());
}

#[cfg(windows)]
#[test]
fn junctions_refuse_scans_writes_and_sync() {
    let temp = common::fixture();
    let outside = common::fixture();
    let link = temp.path().join("link");
    let status = std::process::Command::new("cmd")
        .args(["/C", "mklink", "/J"])
        .arg(&link)
        .arg(outside.path())
        .output()
        .unwrap();
    assert!(
        status.status.success(),
        "{}",
        String::from_utf8_lossy(&status.stderr)
    );
    let refused = scan::scan(temp.path(), &unlimited()).is_err()
        && safety::destination(temp.path(), "link/escape").is_err()
        && operations::verify(temp.path(), &layout(), &unlimited(), true, true).is_err();
    fs::remove_dir(link).unwrap();
    assert!(refused);
    assert!(!temp.path().join("src").exists());
}
