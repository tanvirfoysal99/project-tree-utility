mod common;
use project_tree_utility::{auth, formats, library::Library, remote, scan::Scope, templates};
use std::fs;

#[test]
fn library_snapshot_roundtrips_and_keeps_backup() {
    let temp = common::fixture();
    let entries = formats::parse("- a @content:hello\n", "dash", 2).unwrap();
    {
        let mut library = Library::open(temp.path()).unwrap();
        assert_eq!(
            library.save("starter", "manual", entries.clone()).unwrap(),
            "starter"
        );
        assert_eq!(
            library.save("starter", "manual", entries.clone()).unwrap(),
            "starter-2"
        );
    }
    let library = Library::open(temp.path()).unwrap();
    assert_eq!(library.list().len(), 2);
    assert_eq!(library.find("1").unwrap().entries, entries);
    assert!(temp.path().join("library.json.bak").is_file());
}

#[test]
fn corrupted_library_is_preserved_instead_of_reset() {
    let temp = common::fixture();
    let original = "not valid JSON";
    fs::write(temp.path().join("library.json"), original).unwrap();
    assert!(Library::open(temp.path()).is_err());
    assert_eq!(
        fs::read_to_string(temp.path().join("library.json")).unwrap(),
        original
    );
}

#[test]
fn library_rejects_duplicate_rename_and_unknown_records() {
    let temp = common::fixture();
    let mut library = Library::open(temp.path()).unwrap();
    library.save("first", "manual", vec![]).unwrap();
    library.save("second", "manual", vec![]).unwrap();
    assert!(library.rename("first", "second").is_err());
    assert!(!library.delete("missing").unwrap());
    assert!(!library.rename("missing", "third").unwrap());
    assert!(library.rename("first", "2").is_err());
    assert!(library.save("1", "manual", vec![]).is_err());
    assert_eq!(library.find("1").unwrap().name, "first");
}

#[test]
fn library_lock_serializes_concurrent_writers() {
    let temp = common::fixture();
    let directory = temp.path().to_path_buf();
    let workers: Vec<_> = (0..6)
        .map(|i| {
            let directory = directory.clone();
            std::thread::spawn(move || {
                let mut library = Library::open(&directory).unwrap();
                library
                    .save(&format!("worker-{i}"), "test", vec![])
                    .unwrap();
            })
        })
        .collect();
    for worker in workers {
        worker.join().unwrap();
    }
    assert_eq!(Library::open(&directory).unwrap().list().len(), 6);
}

#[test]
fn credential_and_repository_urls_enforce_https_boundaries() {
    for target in [
        "http://example.com",
        "https://user@example.com",
        "https://example.com?token=x",
        "https://example.com#x",
    ] {
        assert!(auth::target(target).is_err());
    }
    assert_eq!(
        auth::target("github.com/owner/repo").unwrap().host_str(),
        Some("github.com")
    );
    assert!(
        remote::repository(
            "github",
            "https://github.com.evil.invalid/owner/repo",
            "https://gitlab.com"
        )
        .is_err()
    );
    assert!(
        remote::repository(
            "gitlab",
            "https://one.invalid/group/repo",
            "https://two.invalid"
        )
        .is_err()
    );
    let repo = remote::repository(
        "gitlab",
        "https://git.example.com/team/sub/repo.git",
        "https://git.example.com",
    )
    .unwrap();
    assert_eq!(repo.path, "team/sub/repo");
}

#[test]
fn remote_nodes_validate_paths_types_and_subfolder_scope() {
    let scope = Scope {
        max_depth: 0,
        ..Scope::default()
    };
    let mut entries = vec![];
    remote::push_node(
        &serde_json::json!({"path":"packages/tool/src/main.rs","type":"blob"}),
        "packages/tool",
        &scope,
        &mut entries,
    )
    .unwrap();
    assert_eq!(entries[0].path, "src/main.rs");
    remote::push_node(
        &serde_json::json!({"path":"packages/other/a","type":"blob"}),
        "packages/tool",
        &scope,
        &mut entries,
    )
    .unwrap();
    assert_eq!(entries.len(), 1);
    for node in [
        serde_json::json!({"path":"../escape","type":"blob"}),
        serde_json::json!({"path":"a","type":"unknown"}),
        serde_json::json!({"type":"blob"}),
    ] {
        assert!(remote::push_node(&node, "", &scope, &mut entries).is_err());
    }
}

#[test]
fn all_presets_have_valid_manifests_and_typecheck_scripts() {
    for name in ["react-vite", "hono-worker", "monorepo-pnpm"] {
        let entries = templates::preset(name).unwrap();
        let package = entries.iter().find(|e| e.path == "package.json").unwrap();
        let value: serde_json::Value =
            serde_json::from_str(package.content.as_ref().unwrap()).unwrap();
        assert_eq!(value["private"], true);
        assert!(value["scripts"]["build"].is_string());
        if name != "monorepo-pnpm" {
            assert!(value["scripts"]["typecheck"].is_string());
        }
        for format in ["json", "yaml", "importable"] {
            assert_eq!(
                formats::parse(&formats::render(&entries, format).unwrap(), format, 2).unwrap(),
                entries
            );
        }
    }
    assert!(templates::preset("unknown").is_err());
}
