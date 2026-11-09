use project_tree_utility::{remote, scan::Scope};
use reqwest::header::{HeaderMap, HeaderValue};
use serde_json::json;

fn unlimited() -> Scope {
    Scope {
        max_depth: 0,
        ..Scope::default()
    }
}

#[test]
fn github_complete_tree_branch_encoding_filtering_and_truncation() {
    let entries = remote::fetch_with("github", "https://github.com/owner/repo", "feature/a b", "packages/tool", "https://gitlab.com", &unlimited(), |url| {
        assert!(url.as_str().contains("feature%2Fa%20b"));
        assert_eq!(url.query(), Some("recursive=1"));
        Ok((json!({"truncated":false,"tree":[{"path":"packages/tool/src/main.rs","type":"blob"},{"path":"packages/tool/node_modules/a","type":"blob"},{"path":"other/a","type":"blob"}]}), HeaderMap::new()))
    }).unwrap();
    assert_eq!(entries.len(), 2);
    assert_eq!(entries[1].path, "src/main.rs");
    for value in [
        json!({"truncated":true,"tree":[]}),
        json!({"tree":[]}),
        json!({"truncated":false,"tree":{}}),
    ] {
        assert!(
            remote::fetch_with(
                "github",
                "https://github.com/owner/repo",
                "main",
                "",
                "https://gitlab.com",
                &unlimited(),
                |_| Ok((value.clone(), HeaderMap::new()))
            )
            .is_err()
        );
    }
}

#[test]
fn gitlab_nested_groups_base_prefix_and_multiple_pages() {
    let mut page = 0;
    let entries = remote::fetch_with(
        "gitlab",
        "https://git.example.com/gitlab/group/sub/repo.git",
        "feature/a b",
        "",
        "https://git.example.com/gitlab",
        &unlimited(),
        |url| {
            page += 1;
            assert!(
                url.as_str()
                    .contains("/gitlab/api/v4/projects/group%2Fsub%2Frepo/repository/tree")
            );
            assert!(
                url.query_pairs()
                    .any(|(key, value)| key == "ref" && value == "feature/a b")
            );
            assert!(
                url.query_pairs()
                    .any(|(key, value)| key == "page" && value == page.to_string())
            );
            let mut headers = HeaderMap::new();
            headers.insert(
                "x-next-page",
                HeaderValue::from_static(if page == 1 { "2" } else { "" }),
            );
            Ok((
                json!([{"path":format!("file-{page}"),"type":"blob"}]),
                headers,
            ))
        },
    )
    .unwrap();
    assert_eq!(page, 2);
    assert_eq!(entries.len(), 2);
}

#[test]
fn gitlab_refuses_missing_repeated_and_invalid_pagination() {
    for next in [None, Some("1"), Some("3"), Some("nonsense")] {
        assert!(
            remote::fetch_with(
                "gitlab",
                "https://gitlab.com/group/repo",
                "main",
                "",
                "https://gitlab.com",
                &unlimited(),
                |_| {
                    let mut headers = HeaderMap::new();
                    if let Some(next) = next {
                        headers.insert("x-next-page", HeaderValue::from_str(next)?);
                    }
                    Ok((json!([{"path":"a","type":"blob"}]), headers))
                }
            )
            .is_err()
        );
    }
}

#[test]
fn invalid_query_is_rejected_before_transport_is_called() {
    for (provider, repo, branch, folder) in [
        ("bad", "https://github.com/a/b", "main", ""),
        ("github", "https://github.com/a/b", "", ""),
        ("github", "https://github.com/a/b", "main", "../escape"),
    ] {
        assert!(
            remote::fetch_with(
                provider,
                repo,
                branch,
                folder,
                "https://gitlab.com",
                &unlimited(),
                |_| panic!("transport must not be called")
            )
            .is_err()
        );
    }
}

#[test]
fn version_check_handles_published_absent_and_invalid_releases() {
    remote::check_version_with(|url| {
        assert!(url.as_str().ends_with("/releases/latest"));
        Ok(json!({"tag_name":"rust-v3.0.0"}))
    })
    .unwrap();
    remote::check_version_with(|_| Err(remote::HttpFailure(404).into())).unwrap();
    assert!(remote::check_version_with(|_| Err(remote::HttpFailure(403).into())).is_err());
    for value in [
        json!({}),
        json!({"tag_name":""}),
        json!({"tag_name":"bad\ntag"}),
    ] {
        assert!(remote::check_version_with(|_| Ok(value)).is_err());
    }
}

#[test]
fn repository_suffix_and_base_path_do_not_change_project_identity() {
    assert_eq!(
        remote::repository(
            "github",
            "https://github.com/owner/repo.git.git",
            "https://gitlab.com"
        )
        .unwrap()
        .path,
        "owner/repo.git"
    );
    assert!(
        remote::repository(
            "gitlab",
            "https://git.example.com/gitlab/repo",
            "https://git.example.com/gitlab"
        )
        .is_err()
    );
}
