mod common;
use std::{
    fs,
    process::{Child, Command, Stdio},
    thread,
    time::{Duration, Instant},
};

struct Process(Child);
impl Drop for Process {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

#[test]
fn watch_reports_changes_and_never_synchronizes() {
    let temp = common::fixture();
    let root = temp.path().join("project");
    fs::create_dir(&root).unwrap();
    let layout = temp.path().join("layout.txt");
    fs::write(&layout, "- missing.txt @content:never-created\n").unwrap();
    let log = temp.path().join("watch.log");
    let output = fs::File::create(&log).unwrap();
    let mut child = Process(
        Command::new(common::binary())
            .args(["watch", "--ci", "--path"])
            .arg(&root)
            .arg("--structure")
            .arg(&layout)
            .args(["--format", "dash", "--interval-ms", "100"])
            .stdout(Stdio::from(output))
            .stderr(Stdio::null())
            .spawn()
            .unwrap(),
    );
    let start = Instant::now();
    loop {
        if fs::read_to_string(&log)
            .unwrap_or_default()
            .contains("Watching")
        {
            break;
        }
        assert!(
            start.elapsed() < Duration::from_secs(10),
            "watch failed to start"
        );
        assert!(child.0.try_wait().unwrap().is_none());
        thread::sleep(Duration::from_millis(50));
    }
    fs::write(root.join("extra.txt"), "new").unwrap();
    loop {
        if fs::read_to_string(&log)
            .unwrap_or_default()
            .contains("EXTRA extra.txt")
        {
            break;
        }
        assert!(
            start.elapsed() < Duration::from_secs(10),
            "watch failed to report drift"
        );
        thread::sleep(Duration::from_millis(50));
    }
    assert!(!root.join("missing.txt").exists());
}

#[test]
fn watch_rejects_invalid_polling_intervals() {
    let temp = common::fixture();
    let output = common::cli(&["watch", "--path", ".", "--interval-ms", "0"], temp.path());
    assert_eq!(output.status.code(), Some(2));
}
