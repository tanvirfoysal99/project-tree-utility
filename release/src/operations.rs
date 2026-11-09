use crate::{
    formats::Entry,
    safety,
    scan::{self, Comparison, Scope},
    templates,
};
use anyhow::{Context, Result, ensure};
use std::{
    fs,
    io::{self, Write},
    path::Path,
};

#[derive(Debug, Default)]
pub struct Counts {
    pub created: usize,
    pub overwritten: usize,
    pub skipped: usize,
    pub deleted: usize,
}

fn content(entry: &Entry) -> Result<String> {
    if let Some(content) = &entry.content {
        return Ok(content.clone());
    }
    templates::stub(&entry.path, entry.template.as_deref())
}

fn preflight(root: &Path, entries: &[Entry]) -> Result<()> {
    safety::check_ancestors(root)?;
    ensure!(
        !root.exists() || root.is_dir(),
        "Destination root is not a directory"
    );
    for entry in entries {
        let path = safety::destination(root, &entry.path)?;
        if let Ok(meta) = fs::symlink_metadata(&path) {
            ensure!(
                meta.is_dir() == entry.is_dir && (meta.is_file() || meta.is_dir()),
                "Existing path has incompatible type: {}",
                path.display()
            );
        }
        let mut parent = path.parent();
        while let Some(directory) = parent {
            if directory.exists() {
                ensure!(
                    directory.is_dir(),
                    "Ancestor is not a directory: {}",
                    directory.display()
                );
            }
            parent = directory.parent();
        }
        if !entry.is_dir {
            content(entry)?;
        }
    }
    Ok(())
}

pub fn scaffold(
    root: &Path,
    entries: &[Entry],
    overwrite: &str,
    dry_run: bool,
    interactive: bool,
) -> Result<Counts> {
    ensure!(!entries.is_empty(), "Cannot scaffold an empty structure");
    ensure!(
        ["skip", "overwrite", "ask"].contains(&overwrite),
        "Overwrite mode must be skip, overwrite, or ask"
    );
    ensure!(
        overwrite != "ask" || interactive,
        "Noninteractive mode cannot use overwrite=ask"
    );
    ensure!(
        !entries
            .iter()
            .any(|e| e.path.eq_ignore_ascii_case("_creation_log.txt")),
        "_creation_log.txt is reserved"
    );
    preflight(root, entries)?;
    let log = safety::destination(root, "_creation_log.txt")?;
    ensure!(
        !log.exists() || log.is_file(),
        "Creation log has incompatible type"
    );
    for path in std::iter::once(log.clone()).chain(
        entries
            .iter()
            .filter(|e| !e.is_dir && overwrite == "overwrite")
            .map(|e| root.join(&e.path)),
    ) {
        if let Ok(meta) = fs::metadata(&path) {
            ensure!(
                !meta.permissions().readonly(),
                "Overwrite destination is read-only: {}",
                path.display()
            );
        }
    }
    if dry_run {
        for entry in entries {
            println!(
                "PLAN {} {}",
                if entry.is_dir { "directory" } else { "file" },
                entry.path
            );
        }
        return Ok(Counts::default());
    }
    fs::create_dir_all(root)?;
    let mut counts = Counts::default();
    for entry in entries {
        let path = safety::destination(root, &entry.path)?;
        if entry.is_dir {
            fs::create_dir_all(&path)?;
            continue;
        }
        if path.exists() {
            let replace = match overwrite {
                "overwrite" => true,
                "ask" => {
                    print!("Overwrite {}? [y/N] ", path.display());
                    io::stdout().flush()?;
                    let mut answer = String::new();
                    io::stdin().read_line(&mut answer)?;
                    answer.trim().eq_ignore_ascii_case("y")
                }
                _ => false,
            };
            if !replace {
                counts.skipped += 1;
                continue;
            }
            safety::atomic_write(&path, content(entry)?.as_bytes())?;
            counts.overwritten += 1;
        } else {
            create_file(root, entry)?;
            counts.created += 1;
        }
    }
    safety::atomic_write(
        &log,
        format!(
            "Project Tree Utility {}\nCreated: {}\nOverwritten: {}\nSkipped: {}\n",
            env!("CARGO_PKG_VERSION"),
            counts.created,
            counts.overwritten,
            counts.skipped
        )
        .as_bytes(),
    )?;
    Ok(counts)
}

fn create_file(root: &Path, entry: &Entry) -> Result<()> {
    let path = safety::destination(root, &entry.path)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    safety::check_ancestors(&path)?;
    let mut file = fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&path)
        .with_context(|| format!("Creating {}", path.display()))?;
    file.write_all(content(entry)?.as_bytes())?;
    file.sync_all()?;
    Ok(())
}

pub fn verify(
    root: &Path,
    expected: &[Entry],
    scope: &Scope,
    sync: bool,
    delete_extras: bool,
) -> Result<(Comparison, Counts)> {
    ensure!(!delete_extras || sync, "--delete-extras requires --sync");
    let snapshot = scan::scan(root, scope)?;
    let report = scan::compare(expected, &snapshot, scope);
    if !sync {
        return Ok((report, Counts::default()));
    }
    ensure!(
        report.conflicts.is_empty(),
        "Synchronization refuses file/directory conflicts"
    );
    preflight(root, &report.missing)?;
    // Validate all removal paths before creating anything.
    for entry in &report.extra {
        safety::destination(root, &entry.path)?;
    }
    let mut counts = Counts::default();
    for entry in &report.missing {
        let path = safety::destination(root, &entry.path)?;
        if entry.is_dir {
            fs::create_dir_all(path)?;
        } else {
            create_file(root, entry)?;
        }
        counts.created += 1;
    }
    if delete_extras {
        use std::collections::BTreeSet;
        let basename = |entry: &Entry| {
            let name = entry.path.rsplit('/').next().unwrap();
            if cfg!(windows) {
                name.to_lowercase()
            } else {
                name.to_owned()
            }
        };
        let missing_names: BTreeSet<_> = report
            .missing
            .iter()
            .map(|e| (basename(e), e.is_dir))
            .collect();
        let move_sources: BTreeSet<_> = report
            .extra
            .iter()
            .filter(|e| missing_names.contains(&(basename(e), e.is_dir)))
            .map(|e| e.path.as_str())
            .collect();
        let mut protected_ancestors = BTreeSet::new();
        for source in &move_sources {
            let mut parent = *source;
            while let Some((ancestor, _)) = parent.rsplit_once('/') {
                protected_ancestors.insert(ancestor);
                parent = ancestor;
            }
        }
        let mut extras = report.extra.clone();
        extras.sort_by_key(|e| std::cmp::Reverse(e.depth()));
        for entry in extras {
            // Preserve possible move sources, their children, and their ancestors.
            let mut ancestor = entry.path.as_str();
            let mut possible_move =
                protected_ancestors.contains(ancestor) || move_sources.contains(ancestor);
            while let Some((parent, _)) = ancestor.rsplit_once('/') {
                possible_move |= move_sources.contains(parent);
                ancestor = parent;
            }
            if possible_move {
                println!("PRESERVED possible move source: {}", entry.path);
                continue;
            }
            let path = safety::destination(root, &entry.path)?;
            let meta = fs::symlink_metadata(&path)?;
            ensure!(
                meta.is_dir() == entry.is_dir,
                "Path type changed during sync"
            );
            if entry.is_dir {
                if fs::read_dir(&path)?.next().is_some() {
                    continue;
                }
                fs::remove_dir(path)?;
            } else {
                safety::ensure_regular(&path)?;
                fs::remove_file(path)?;
            }
            counts.deleted += 1;
        }
    }
    Ok((
        scan::compare(expected, &scan::scan(root, scope)?, scope),
        counts,
    ))
}
