use anyhow::{Context, Result, bail, ensure};
use std::{
    fs,
    path::{Component, Path, PathBuf},
};

pub const MAX_INPUT_BYTES: u64 = 8 * 1024 * 1024;
pub const MAX_ENTRIES: usize = 100_000;
pub const MAX_DEPTH: usize = 128;

/// Use portable Windows-compatible names on every platform so layouts travel safely.
pub fn relative_path(value: &str) -> Result<String> {
    ensure!(!value.is_empty(), "Path cannot be empty");
    let path = value.replace('\\', "/");
    ensure!(
        !path.starts_with('/'),
        "Absolute paths are forbidden: {value}"
    );
    for part in path.split('/') {
        ensure!(
            !part.is_empty() && part != "." && part != "..",
            "Invalid path component: {value}"
        );
        ensure!(
            part.encode_utf16().count() <= 255,
            "Filename component is too long"
        );
        ensure!(
            !part.ends_with(['.', ' ']),
            "Trailing dot/space is forbidden: {value}"
        );
        ensure!(
            !part
                .chars()
                .any(|c| c.is_control() || "<>:\"|?*".contains(c)),
            "Invalid filename: {value}"
        );
        let stem = part
            .split('.')
            .next()
            .unwrap_or(part)
            .trim_end()
            .to_uppercase();
        let device = matches!(
            stem.as_str(),
            "CON" | "PRN" | "AUX" | "NUL" | "CONIN$" | "CONOUT$"
        ) || ["COM", "LPT"].iter().any(|prefix| {
            stem.strip_prefix(prefix).is_some_and(|n| {
                matches!(
                    n,
                    "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" | "¹" | "²" | "³"
                )
            })
        });
        ensure!(!device, "Reserved device name: {value}");
    }
    ensure!(
        path.split('/').count() <= MAX_DEPTH,
        "Maximum layout depth is {MAX_DEPTH}"
    );
    Ok(path)
}

pub fn absolute(path: &Path) -> Result<PathBuf> {
    let input = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir()?.join(path)
    };
    ensure!(
        input.is_absolute(),
        "Ambiguous drive-relative path; use a fully qualified path"
    );
    let mut result = PathBuf::new();
    for part in input.components() {
        match part {
            Component::CurDir => {}
            Component::ParentDir => {
                ensure!(result.pop(), "Path escapes filesystem root");
            }
            other => result.push(other.as_os_str()),
        }
    }
    Ok(result)
}

pub fn is_link(metadata: &fs::Metadata) -> bool {
    #[cfg(windows)]
    {
        use std::os::windows::fs::MetadataExt;
        metadata.file_type().is_symlink() || metadata.file_attributes() & 0x400 != 0
    }
    #[cfg(not(windows))]
    {
        metadata.file_type().is_symlink()
    }
}

/// Reject symbolic links/reparse points in all existing ancestors, including the root.
pub fn check_ancestors(path: &Path) -> Result<()> {
    let path = absolute(path)?;
    let mut current = PathBuf::new();
    for component in path.components() {
        current.push(component.as_os_str());
        match fs::symlink_metadata(&current) {
            Ok(meta) => ensure!(
                !is_link(&meta),
                "Symbolic link/reparse point refused: {}",
                current.display()
            ),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => {
                return Err(error).with_context(|| format!("Inspecting {}", current.display()));
            }
        }
    }
    Ok(())
}

pub fn destination(base: &Path, relative: &str) -> Result<PathBuf> {
    let relative = relative_path(relative)?;
    let base = absolute(base)?;
    let result = base.join(relative);
    ensure!(
        result.starts_with(&base) && result != base,
        "Destination escapes root"
    );
    check_ancestors(&result)?;
    Ok(result)
}

pub fn contained(base: &Path, candidate: &Path) -> Result<()> {
    let base = absolute(base)?;
    let candidate = absolute(candidate)?;
    ensure!(
        candidate.starts_with(&base),
        "Candidate is outside the base directory"
    );
    check_ancestors(&candidate)
}

pub fn read_text(path: &Path) -> Result<String> {
    use std::io::Read;
    check_ancestors(path)?;
    let file = fs::File::open(path).with_context(|| format!("Opening {}", path.display()))?;
    ensure!(file.metadata()?.is_file(), "Input must be a regular file");
    let mut bytes = Vec::new();
    file.take(MAX_INPUT_BYTES + 1).read_to_end(&mut bytes)?;
    ensure!(
        bytes.len() as u64 <= MAX_INPUT_BYTES,
        "Input exceeds the 8 MiB limit"
    );
    Ok(String::from_utf8(bytes)
        .context("Input must be UTF-8")?
        .trim_start_matches('\u{feff}')
        .to_owned())
}

/// Stage beside the destination and atomically replace it; never truncate first.
pub fn atomic_write(path: &Path, bytes: &[u8]) -> Result<()> {
    use std::io::Write;
    let path = absolute(path)?;
    check_ancestors(&path)?;
    let parent = path.parent().context("Output has no parent")?;
    ensure!(
        parent.is_dir(),
        "Output parent does not exist: {}",
        parent.display()
    );
    if let Ok(meta) = fs::symlink_metadata(&path) {
        ensure!(
            meta.is_file() && !is_link(&meta),
            "Output is not a regular file"
        );
        ensure!(!meta.permissions().readonly(), "Output is read-only");
    }
    let mut staged = tempfile::NamedTempFile::new_in(parent)?;
    #[cfg(unix)]
    if let Ok(meta) = fs::metadata(&path) {
        staged.as_file().set_permissions(meta.permissions())?;
    }
    staged.write_all(bytes)?;
    staged.as_file().sync_all()?;
    check_ancestors(&path)?;
    staged
        .persist(&path)
        .map_err(|e| e.error)
        .context("Committing atomic write")?;
    #[cfg(unix)]
    fs::File::open(parent)?.sync_all()?;
    Ok(())
}

pub fn ensure_regular(path: &Path) -> Result<()> {
    check_ancestors(path)?;
    let meta = fs::symlink_metadata(path)?;
    if !meta.is_file() {
        bail!("Not a regular file: {}", path.display());
    }
    Ok(())
}
