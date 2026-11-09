use anyhow::{Context, Result, bail, ensure};
use reqwest::Url;
use std::{
    io::{Read, Write},
    process::{Command, Stdio},
    thread,
    time::{Duration, Instant},
};

pub fn target(value: &str) -> Result<Url> {
    let value = value.strip_prefix("git:").unwrap_or(value);
    let value = if value.contains("://") {
        value.to_string()
    } else {
        format!("https://{value}")
    };
    let mut url = Url::parse(&value)?;
    ensure!(
        url.scheme() == "https"
            && url.host_str().is_some()
            && url.username().is_empty()
            && url.password().is_none()
            && url.query().is_none()
            && url.fragment().is_none(),
        "Credential target must be HTTPS without user info, query, or fragment"
    );
    let path = url.path().trim_end_matches('/').to_owned();
    url.set_path(&path);
    Ok(url)
}

#[cfg(any(windows, target_os = "macos"))]
fn identity(url: &Url) -> String {
    format!("git:{}", url.as_str().trim_end_matches('/'))
}

fn helper(action: &str, url: &Url, username: Option<&str>, secret: Option<&str>) -> Result<String> {
    let mut payload = format!(
        "protocol=https\nhost={}\npath={}\n",
        &url[url::Position::BeforeHost..url::Position::AfterPort],
        url.path().trim_start_matches('/')
    );
    if let Some(username) = username {
        ensure!(!username.contains(['\n', '\r', '\0']), "Invalid username");
        payload += &format!("username={username}\n");
    }
    if let Some(secret) = secret {
        ensure!(
            !secret.contains(['\n', '\r', '\0']) && secret.len() <= 16_384,
            "Invalid token"
        );
        payload += &format!("password={secret}\n");
    }
    payload += "\n";
    run_git(&["credential", action], payload.as_bytes())
}

fn run_git(args: &[&str], input: &[u8]) -> Result<String> {
    let output = tempfile::tempfile()?;
    let mut child = Command::new("git")
        .args(args)
        .env("GIT_TERMINAL_PROMPT", "0")
        .env("GCM_INTERACTIVE", "never")
        .stdin(Stdio::piped())
        .stdout(Stdio::from(output.try_clone()?))
        .stderr(Stdio::null())
        .spawn()
        .context("Git credential helper is unavailable")?;
    child
        .stdin
        .take()
        .context("Cannot open helper input")?
        .write_all(input)?;
    let start = Instant::now();
    loop {
        if let Some(status) = child.try_wait()? {
            ensure!(status.success(), "Git credential helper failed");
            break;
        }
        if start.elapsed() > Duration::from_secs(10) {
            let _ = child.kill();
            let _ = child.wait();
            bail!("Credential helper timed out");
        }
        thread::sleep(Duration::from_millis(25));
    }
    use std::io::{Seek, SeekFrom};
    let mut output = output;
    output.seek(SeekFrom::Start(0))?;
    let mut text = String::new();
    output.take(65_537).read_to_string(&mut text)?;
    ensure!(
        text.len() <= 65_536,
        "Credential helper response is too large"
    );
    Ok(text)
}

// Use native vaults on desktops. Linux/Termux use explicitly configured Git
// credential helpers; never silently fall back to a plaintext credential file.
pub fn store(url: &Url, username: &str, secret: &str) -> Result<()> {
    ensure!(
        !secret.is_empty() && secret.len() <= 16_384 && !secret.contains(['\n', '\r', '\0']),
        "Token is empty, too large, or contains a newline"
    );
    #[cfg(any(windows, target_os = "macos"))]
    {
        keyring::Entry::new(&identity(url), "ptu")?.set_password(&serde_json::to_string(
            &serde_json::json!({"username":username,"secret":secret}),
        )?)?;
        Ok(())
    }
    #[cfg(not(any(windows, target_os = "macos")))]
    {
        let helpers = run_git(&["config", "--get-all", "credential.helper"], b"")
            .context("Configure a secure Git credential helper before storing credentials")?;
        ensure!(
            !helpers.trim().is_empty() && !helpers.lines().any(|h| h.trim().starts_with("store")),
            "Configure a secure credential helper; plaintext 'store' is unsupported"
        );
        helper("approve", url, Some(username), Some(secret))?;
        Ok(())
    }
}

pub fn clear(url: &Url) -> Result<()> {
    #[cfg(any(windows, target_os = "macos"))]
    {
        match keyring::Entry::new(&identity(url), "ptu")?.delete_credential() {
            Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
            Err(error) => Err(error.into()),
        }
    }
    #[cfg(not(any(windows, target_os = "macos")))]
    {
        helper("reject", url, None, None)?;
        Ok(())
    }
}

pub fn lookup(url: &Url) -> Result<Option<String>> {
    let mut host = url.clone();
    host.set_path("");
    for url in [url, &host] {
        #[cfg(any(windows, target_os = "macos"))]
        {
            match keyring::Entry::new(&identity(url), "ptu")?.get_password() {
                Ok(value) => {
                    let value: serde_json::Value =
                        serde_json::from_str(&value).context("Invalid stored credential")?;
                    return Ok(Some(
                        value["secret"]
                            .as_str()
                            .context("Invalid stored secret")?
                            .into(),
                    ));
                }
                Err(keyring::Error::NoEntry) => {}
                Err(error) => return Err(error.into()),
            }
        }
        if let Ok(response) = helper("fill", url, None, None)
            && let Some(password) = response.lines().find_map(|s| s.strip_prefix("password="))
            && !password.is_empty()
        {
            return Ok(Some(password.into()));
        }
    }
    Ok(None)
}
