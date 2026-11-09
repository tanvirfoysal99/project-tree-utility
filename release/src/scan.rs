use crate::{
    formats::{self, Entry},
    safety,
};
use anyhow::{Context, Result, bail, ensure};
use std::{collections::BTreeMap, fs, path::Path};

pub const DEFAULT_EXCLUDES: &[&str] = &[
    "node_modules",
    "dist",
    ".git",
    ".wrangler",
    ".next",
    ".turbo",
    "out",
    "build",
];

#[derive(Clone, Debug)]
pub struct Scope {
    pub excludes: Vec<String>,
    pub max_depth: usize,
    pub show_mode: String,
}

impl Default for Scope {
    fn default() -> Self {
        Self {
            excludes: DEFAULT_EXCLUDES.iter().map(|s| s.to_string()).collect(),
            max_depth: 5,
            show_mode: "all".into(),
        }
    }
}

impl Scope {
    pub fn includes(&self, path: &str) -> bool {
        if self.max_depth > 0 && path.split('/').count() > self.max_depth {
            return false;
        }
        let path = path.to_lowercase();
        !self.excludes.iter().any(|rule| {
            let rule = rule.replace('\\', "/").trim_matches('/').to_lowercase();
            !rule.is_empty()
                && if rule.contains('/') {
                    path == rule || path.starts_with(&(rule + "/"))
                } else {
                    path.split('/').any(|part| part == rule)
                }
        })
    }

    pub fn load(root: &Path, explicit: Option<&Path>) -> Result<Self> {
        let mut scope = Self::default();
        let config = explicit.map(Path::to_path_buf).or_else(|| {
            [".treeignore", ".treerc"]
                .iter()
                .map(|s| root.join(s))
                .find(|p| p.exists())
        });
        if let Some(path) = config {
            for line in safety::read_text(&path)?.lines() {
                let line = line.trim();
                if line.is_empty() || line.starts_with(['#', ';']) {
                    continue;
                }
                if let Some((key, value)) = line.split_once([':', '=']) {
                    let value = value.trim();
                    match key.trim().to_lowercase().as_str() {
                        "exclude" | "ignore" | "skip" => scope.add_excludes(value),
                        "maxdepth" | "depth" => {
                            scope.max_depth =
                                value.parse().context("Invalid configuration depth")?
                        }
                        "showmode" | "show" => scope.show_mode = value.into(),
                        "template" => {}
                        _ => bail!("Unknown configuration key: {key}"),
                    }
                } else {
                    scope.add_excludes(line);
                }
            }
        }
        let gitignore = root.join(".gitignore");
        if gitignore.exists() {
            for line in safety::read_text(&gitignore)?.lines() {
                let rule = line.trim().trim_end_matches('/');
                if !rule.is_empty()
                    && !rule.starts_with(['#', '!'])
                    && !rule.contains(['/', '\\', '*', '?', '['])
                {
                    scope.excludes.push(rule.into());
                }
            }
        }
        scope.validate()?;
        Ok(scope)
    }

    pub fn add_excludes(&mut self, rules: &str) {
        self.excludes.extend(
            rules
                .split([',', ';'])
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_owned),
        );
    }

    pub fn validate(&self) -> Result<()> {
        ensure!(
            ["all", "files", "folders"].contains(&self.show_mode.as_str()),
            "Show mode must be all, files, or folders"
        );
        Ok(())
    }
}

/// A scan either returns a complete snapshot or fails. Never silently skip I/O errors.
pub fn scan(root: &Path, scope: &Scope) -> Result<Vec<Entry>> {
    safety::check_ancestors(root)?;
    ensure!(root.is_dir(), "Scan root must be an existing directory");
    let mut pending = vec![(root.to_path_buf(), String::new())];
    let mut result = Vec::new();
    while let Some((directory, relative)) = pending.pop() {
        for child in fs::read_dir(&directory)
            .with_context(|| format!("Incomplete scan: {}", directory.display()))?
        {
            let child = child?;
            let name = child
                .file_name()
                .into_string()
                .map_err(|_| anyhow::anyhow!("Non-UTF-8 filename cannot be exported"))?;
            let path = if relative.is_empty() {
                name
            } else {
                format!("{relative}/{name}")
            };
            if !scope.includes(&path) {
                continue;
            }
            let meta = fs::symlink_metadata(child.path())?;
            ensure!(
                !safety::is_link(&meta),
                "Incomplete scan: link/reparse point refused: {}",
                child.path().display()
            );
            ensure!(
                meta.is_dir() || meta.is_file(),
                "Incomplete scan: unsupported filesystem entry: {path}"
            );
            safety::relative_path(&path)?;
            let entry = Entry::new(&path, meta.is_dir());
            if entry.is_dir && (scope.max_depth == 0 || entry.depth() < scope.max_depth) {
                pending.push((child.path(), path));
            }
            result.push(entry);
            ensure!(
                result.len() <= safety::MAX_ENTRIES,
                "Scan exceeds maximum entry count"
            );
        }
    }
    formats::normalize(result)
}

pub fn displayed(entries: &[Entry], mode: &str, format: &str) -> Vec<Entry> {
    let filtered: Vec<_> = entries
        .iter()
        .filter(|e| mode == "all" || (mode == "folders") == e.is_dir)
        .cloned()
        .collect();
    if mode == "files" && ["json", "yaml", "treesym"].contains(&format) {
        // The source snapshot was already validated; normalization adds file ancestors.
        formats::normalize(filtered).expect("validated scan entries")
    } else {
        filtered
    }
}

#[derive(Debug, Default, PartialEq, Eq)]
pub struct Comparison {
    pub missing: Vec<Entry>,
    pub extra: Vec<Entry>,
    pub conflicts: Vec<String>,
    pub matched: usize,
}

impl Comparison {
    pub fn clean(&self) -> bool {
        self.missing.is_empty() && self.extra.is_empty() && self.conflicts.is_empty()
    }
    pub fn print(&self) {
        for entry in &self.missing {
            println!(
                "MISSING {}{}",
                entry.path,
                if entry.is_dir { "/" } else { "" }
            );
        }
        for entry in &self.extra {
            println!(
                "EXTRA {}{}",
                entry.path,
                if entry.is_dir { "/" } else { "" }
            );
        }
        for path in &self.conflicts {
            println!("TYPE CONFLICT {path}");
        }
        println!(
            "{} matched, {} missing, {} extra, {} type conflicts",
            self.matched,
            self.missing.len(),
            self.extra.len(),
            self.conflicts.len()
        );
    }
}

pub fn compare(expected: &[Entry], actual: &[Entry], scope: &Scope) -> Comparison {
    // Native case semantics: exact on Unix, case-insensitive on Windows.
    let key = |s: &str| {
        if cfg!(windows) {
            s.to_lowercase()
        } else {
            s.to_string()
        }
    };
    let expected: BTreeMap<_, _> = expected
        .iter()
        .filter(|e| scope.includes(&e.path))
        .map(|e| (key(&e.path), e))
        .collect();
    let actual: BTreeMap<_, _> = actual.iter().map(|e| (key(&e.path), e)).collect();
    let mut result = Comparison::default();
    for (path, entry) in &expected {
        match actual.get(path) {
            None => result.missing.push((*entry).clone()),
            Some(found) if found.is_dir != entry.is_dir => {
                result.conflicts.push(entry.path.clone())
            }
            Some(_) => result.matched += 1,
        }
    }
    for (path, entry) in &actual {
        if !expected.contains_key(path) {
            result.extra.push((*entry).clone());
        }
    }
    result
}
