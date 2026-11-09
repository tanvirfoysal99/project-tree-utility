#![allow(dead_code)]
use std::{
    fs,
    path::{Path, PathBuf},
    process::{Command, Output},
};

pub fn fixture() -> tempfile::TempDir {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("target/test-fixtures");
    fs::create_dir_all(&root).unwrap();
    tempfile::tempdir_in(root).unwrap()
}

pub fn binary() -> PathBuf {
    std::env::var_os("PTU_TEST_BINARY")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(env!("CARGO_BIN_EXE_ptu")))
}

pub fn cli(args: &[&str], directory: &Path) -> Output {
    Command::new(binary())
        .args(args)
        .env_remove("TREE_CI")
        .env("PTU_DATA_DIR", directory.join("library-data"))
        .current_dir(directory)
        .output()
        .unwrap()
}

pub fn success(output: &Output) {
    assert!(
        output.status.success(),
        "stdout: {}\nstderr: {}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
}
