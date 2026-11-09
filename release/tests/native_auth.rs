#![cfg(any(windows, target_os = "macos"))]
mod common;
use project_tree_utility::auth;
use std::{
    io::Write,
    process::{Command, Stdio},
};

struct Credential(reqwest::Url);
impl Drop for Credential {
    fn drop(&mut self) {
        let _ = auth::clear(&self.0);
    }
}

#[test]
#[ignore = "Creates and removes one uniquely named dummy native-vault credential"]
fn native_vault_store_lookup_update_and_clear_through_cli() {
    let temp = common::fixture();
    let unique = temp
        .path()
        .file_name()
        .unwrap()
        .to_string_lossy()
        .replace('.', "");
    let target = format!("https://ptu-test-{unique}.invalid");
    let url = auth::target(&target).unwrap();
    let _cleanup = Credential(url.clone());
    let token = "dummy-ptu-fixture-token-not-a-real-credential";
    let output = Command::new(common::binary())
        .args([
            "auth",
            "--ci",
            "STORE",
            &target,
            "--secret-env",
            "PTU_QA_TOKEN",
        ])
        .env("PTU_QA_TOKEN", token)
        .current_dir(temp.path())
        .output()
        .unwrap();
    common::success(&output);
    assert!(!String::from_utf8_lossy(&output.stdout).contains(token));
    assert_eq!(auth::lookup(&url).unwrap().as_deref(), Some(token));
    let mut child = Command::new(common::binary())
        .args(["auth", "--ci", "store", &target, "--secret-stdin"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child
        .stdin
        .take()
        .unwrap()
        .write_all(b"dummy-updated-token\r\n")
        .unwrap();
    common::success(&child.wait_with_output().unwrap());
    assert_eq!(
        auth::lookup(&url).unwrap().as_deref(),
        Some("dummy-updated-token")
    );
    for _ in 0..2 {
        common::success(&common::cli(
            &["auth", "--ci", "CLEAR", &target],
            temp.path(),
        ));
    }
    let identity = format!("git:{}", url.as_str().trim_end_matches('/'));
    assert!(matches!(
        keyring::Entry::new(&identity, "ptu")
            .unwrap()
            .get_password(),
        Err(keyring::Error::NoEntry)
    ));
}
