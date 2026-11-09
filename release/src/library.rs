//! One atomically replaced snapshot is the library's source of truth. Exports are
//! disposable views, avoiding split index/file transactions and recovery journals.
use crate::{
    formats::{self, Entry},
    safety,
};
use anyhow::{Context, Result, ensure};
use fs2::FileExt;
use serde::{Deserialize, Serialize};
use std::{
    fs,
    path::{Path, PathBuf},
    thread,
    time::{Duration, Instant},
};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Saved {
    pub id: u64,
    pub name: String,
    pub source: String,
    pub entries: Vec<Entry>,
}

#[derive(Default, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Index {
    version: u32,
    next_id: u64,
    items: Vec<Saved>,
}

pub fn data_dir() -> Result<PathBuf> {
    if let Some(path) = std::env::var_os("PTU_DATA_DIR") {
        return safety::absolute(Path::new(&path));
    }
    Ok(
        directories::ProjectDirs::from("", "", "project-tree-utility")
            .context("Cannot locate user data directory; set PTU_DATA_DIR")?
            .data_local_dir()
            .to_path_buf(),
    )
}

fn validate_name(name: &str) -> Result<()> {
    ensure!(
        !name.trim().is_empty() && name.len() <= 200 && !name.chars().any(char::is_control),
        "Library name must be 1–200 bytes without control characters"
    );
    ensure!(
        !name.chars().all(|c| c.is_ascii_digit()),
        "Numeric-only library names are reserved for ID lookup"
    );
    Ok(())
}

pub struct Library {
    directory: PathBuf,
    index: Index,
    _lock: fs::File,
}

impl Library {
    pub fn open(directory: &Path) -> Result<Self> {
        safety::check_ancestors(directory)?;
        fs::create_dir_all(directory)?;
        let lock_path = directory.join("library.lock");
        safety::check_ancestors(&lock_path)?;
        let lock = fs::OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(lock_path)?;
        let start = Instant::now();
        loop {
            match lock.try_lock_exclusive() {
                Ok(()) => break,
                Err(error)
                    if error.raw_os_error() == fs2::lock_contended_error().raw_os_error()
                        && start.elapsed() < Duration::from_secs(5) =>
                {
                    thread::sleep(Duration::from_millis(50))
                }
                Err(error) => return Err(error).context("Library lock failed or timed out"),
            }
        }
        let path = directory.join("library.json");
        let index: Index = if path.exists() {
            serde_json::from_str(&safety::read_text(&path)?)
                .context("Invalid library index; original preserved")?
        } else {
            Index {
                version: 1,
                next_id: 1,
                items: vec![],
            }
        };
        ensure!(
            index.version == 1 && index.items.len() <= 10_000,
            "Unsupported or oversized library index"
        );
        let mut ids = std::collections::BTreeSet::new();
        let mut names = std::collections::BTreeSet::new();
        for item in &index.items {
            validate_name(&item.name)?;
            ensure!(
                ids.insert(item.id)
                    && names.insert(item.name.to_lowercase())
                    && item.id < index.next_id,
                "Invalid duplicate library record"
            );
            ensure!(
                formats::normalize(item.entries.clone())? == item.entries,
                "Noncanonical library structure"
            );
        }
        Ok(Self {
            directory: directory.to_path_buf(),
            index,
            _lock: lock,
        })
    }

    fn commit(&mut self, next: Index) -> Result<()> {
        let bytes = serde_json::to_vec_pretty(&next)?;
        ensure!(
            bytes.len() as u64 <= safety::MAX_INPUT_BYTES,
            "Library exceeds 8 MiB limit"
        );
        let path = self.directory.join("library.json");
        if path.exists() {
            safety::atomic_write(
                &self.directory.join("library.json.bak"),
                safety::read_text(&path)?.as_bytes(),
            )?;
        }
        safety::atomic_write(&path, &bytes)?;
        self.index = next;
        Ok(())
    }

    pub fn list(&self) -> &[Saved] {
        &self.index.items
    }
    pub fn find(&self, name: &str) -> Option<&Saved> {
        let folded = name.to_lowercase();
        self.index
            .items
            .iter()
            .find(|x| x.name.to_lowercase() == folded || x.id.to_string() == name)
    }

    pub fn save(&mut self, name: &str, source: &str, entries: Vec<Entry>) -> Result<String> {
        validate_name(name)?;
        ensure!(
            self.index.items.len() < 10_000,
            "Library entry limit exceeded"
        );
        let mut unique = name.to_owned();
        let mut suffix = 2;
        while self.find(&unique).is_some() {
            unique = format!("{name}-{suffix}");
            suffix += 1;
        }
        validate_name(&unique)?;
        let entries = formats::normalize(entries)?;
        let mut next = self.index.clone();
        let id = next.next_id;
        next.next_id = id.checked_add(1).context("Library ID overflow")?;
        next.items.push(Saved {
            id,
            name: unique.clone(),
            source: source.into(),
            entries,
        });
        self.commit(next)?;
        Ok(unique)
    }

    pub fn export(&self, name: &str) -> Result<Option<PathBuf>> {
        let Some(item) = self.find(name) else {
            return Ok(None);
        };
        let path = self.directory.join(format!("tree-{}.txt", item.id));
        safety::atomic_write(
            &path,
            formats::render(&item.entries, "importable")?.as_bytes(),
        )?;
        Ok(Some(path))
    }

    pub fn rename(&mut self, name: &str, new: &str) -> Result<bool> {
        validate_name(new)?;
        let Some(id) = self.find(name).map(|i| i.id) else {
            return Ok(false);
        };
        ensure!(
            !self
                .index
                .items
                .iter()
                .any(|x| x.id != id && x.name.to_lowercase() == new.to_lowercase()),
            "Library name already exists"
        );
        let mut next = self.index.clone();
        next.items.iter_mut().find(|x| x.id == id).unwrap().name = new.into();
        self.commit(next)?;
        Ok(true)
    }

    pub fn delete(&mut self, name: &str) -> Result<bool> {
        let Some(id) = self.find(name).map(|i| i.id) else {
            return Ok(false);
        };
        let mut next = self.index.clone();
        next.items.retain(|i| i.id != id);
        self.commit(next)?;
        self.remove_export(id)?;
        Ok(true)
    }

    fn remove_export(&self, id: u64) -> Result<()> {
        let path = self.directory.join(format!("tree-{id}.txt"));
        if fs::symlink_metadata(&path).is_ok() {
            safety::ensure_regular(&path)?;
            fs::remove_file(path)?;
        }
        Ok(())
    }

    pub fn purge(&mut self) -> Result<()> {
        let ids: Vec<_> = self.index.items.iter().map(|i| i.id).collect();
        let mut next = self.index.clone();
        next.items.clear();
        self.commit(next)?;
        for id in ids {
            self.remove_export(id)?;
        }
        Ok(())
    }
}
