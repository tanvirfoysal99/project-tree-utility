use crate::{
    auth,
    formats::{self, Entry},
    safety,
    scan::Scope,
};
use anyhow::{Context, Result, bail, ensure};
use reqwest::{
    Url,
    blocking::Client,
    header::{AUTHORIZATION, HeaderMap, HeaderValue, USER_AGENT},
};
use serde_json::Value;
use std::{io::Read, thread, time::Duration};

const MAX_RESPONSE: u64 = 32 * 1024 * 1024;

#[derive(Debug)]
pub struct HttpFailure(pub u16);
impl std::fmt::Display for HttpFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Remote request failed (HTTP {})", self.0)
    }
}
impl std::error::Error for HttpFailure {}

pub fn client() -> Result<Client> {
    Ok(Client::builder()
        .timeout(Duration::from_secs(20))
        .connect_timeout(Duration::from_secs(10))
        .redirect(reqwest::redirect::Policy::none())
        .https_only(true)
        .build()?)
}

pub fn request(client: &Client, url: Url, token: Option<&str>) -> Result<(Value, HeaderMap)> {
    let mut headers = HeaderMap::new();
    headers.insert(
        USER_AGENT,
        HeaderValue::from_static("project-tree-utility/3"),
    );
    if let Some(token) = token {
        let mut value = HeaderValue::from_str(&format!("Bearer {token}"))
            .context("Token cannot be represented as an HTTP header")?;
        value.set_sensitive(true);
        headers.insert(AUTHORIZATION, value);
    }
    for attempt in 0..3 {
        let response = client.get(url.clone()).headers(headers.clone()).send();
        match response {
            Ok(response) => {
                let status = response.status();
                if (status.is_server_error() || status.as_u16() == 429) && attempt < 2 {
                    thread::sleep(Duration::from_millis(250 * (attempt + 1)));
                    continue;
                }
                if !status.is_success() {
                    return Err(HttpFailure(status.as_u16()).into());
                }
                ensure!(
                    response.content_length().is_none_or(|n| n <= MAX_RESPONSE),
                    "Remote response exceeds 32 MiB"
                );
                let headers = response.headers().clone();
                let mut bytes = Vec::new();
                response.take(MAX_RESPONSE + 1).read_to_end(&mut bytes)?;
                ensure!(
                    bytes.len() as u64 <= MAX_RESPONSE,
                    "Remote response exceeds 32 MiB"
                );
                return Ok((
                    serde_json::from_slice(&bytes).context("Invalid remote JSON")?,
                    headers,
                ));
            }
            Err(_) if attempt < 2 => thread::sleep(Duration::from_millis(250 * (attempt + 1))),
            Err(_) => {
                bail!("Remote request failed after bounded retries (connection or TLS error)")
            }
        }
    }
    unreachable!()
}

#[derive(Debug)]
pub struct Repository {
    pub url: Url,
    pub path: String,
    pub api: Url,
}

pub fn repository(provider: &str, repo: &str, gitlab_base: &str) -> Result<Repository> {
    let url = auth::target(repo)?;
    let path = url.path().trim_matches('/');
    let path = path.strip_suffix(".git").unwrap_or(path).to_owned();
    ensure!(
        path.split('/').count() >= 2 && !path.split('/').any(str::is_empty),
        "Repository URL requires owner/group and repository"
    );
    let api = match provider {
        "github" => {
            ensure!(
                url.host_str() == Some("github.com")
                    && url.port_or_known_default() == Some(443)
                    && path.split('/').count() == 2,
                "GitHub repository must be https://github.com/owner/repo"
            );
            Url::parse("https://api.github.com/")?
        }
        "gitlab" => {
            let mut base = auth::target(gitlab_base)?;
            ensure!(
                base.origin() == url.origin(),
                "GitLab base and repository must have the same HTTPS authority"
            );
            let prefix = base.path().trim_end_matches('/').to_owned();
            if !prefix.is_empty() {
                ensure!(
                    path.starts_with(&(prefix.trim_start_matches('/').to_string() + "/")),
                    "Repository is outside GitLab base path"
                );
            }
            base.set_path(&(prefix + "/api/v4/"));
            base
        }
        _ => bail!("Provider must be github or gitlab"),
    };
    let path = if provider == "gitlab" {
        let base = auth::target(gitlab_base)?;
        path.strip_prefix(base.path().trim_matches('/'))
            .unwrap_or(&path)
            .trim_start_matches('/')
            .to_string()
    } else {
        path
    };
    ensure!(
        path.split('/').count() >= 2,
        "Repository requires a namespace and name beneath the GitLab base"
    );
    Ok(Repository { url, path, api })
}

fn endpoint(base: &Url, segments: &[&str]) -> Result<Url> {
    let mut url = base.clone();
    {
        let mut path = url
            .path_segments_mut()
            .map_err(|_| anyhow::anyhow!("Invalid API base"))?;
        path.pop_if_empty();
        for segment in segments {
            path.push(segment);
        }
    }
    Ok(url)
}

pub fn fetch(
    provider: &str,
    repo: &str,
    branch: &str,
    subfolder: &str,
    gitlab_base: &str,
    scope: &Scope,
) -> Result<Vec<Entry>> {
    let repo_url = repository(provider, repo, gitlab_base)?.url;
    let token = auth::lookup(&repo_url)?;
    let client = client()?;
    fetch_with(
        provider,
        repo,
        branch,
        subfolder,
        gitlab_base,
        scope,
        |url| request(&client, url, token.as_deref()),
    )
}

/// Public repository access that never reads a credential vault or Git helper.
pub fn fetch_anonymous(
    provider: &str,
    repo: &str,
    branch: &str,
    subfolder: &str,
    gitlab_base: &str,
    scope: &Scope,
) -> Result<Vec<Entry>> {
    let client = client()?;
    fetch_with(
        provider,
        repo,
        branch,
        subfolder,
        gitlab_base,
        scope,
        |url| request(&client, url, None),
    )
}

/// Provider logic with a supplied transport, used by deterministic API fixtures.
pub fn fetch_with(
    provider: &str,
    repo: &str,
    branch: &str,
    subfolder: &str,
    gitlab_base: &str,
    scope: &Scope,
    mut get: impl FnMut(Url) -> Result<(Value, HeaderMap)>,
) -> Result<Vec<Entry>> {
    ensure!(
        !branch.is_empty() && !branch.chars().any(char::is_control),
        "Branch cannot be empty or contain control characters"
    );
    let repo = repository(provider, repo, gitlab_base)?;
    let subfolder = subfolder.trim_matches('/');
    if !subfolder.is_empty() {
        safety::relative_path(subfolder)?;
    }
    let mut entries = Vec::new();
    if provider == "github" {
        let parts: Vec<_> = repo.path.split('/').collect();
        let mut url = endpoint(
            &repo.api,
            &["repos", parts[0], parts[1], "git", "trees", branch],
        )?;
        url.query_pairs_mut().append_pair("recursive", "1");
        let (value, _) = get(url)?;
        ensure!(
            value["truncated"].as_bool() == Some(false),
            "GitHub tree is truncated or missing completeness metadata"
        );
        let nodes = value["tree"]
            .as_array()
            .context("GitHub response lacks a tree array")?;
        for node in nodes {
            push_node(node, subfolder, scope, &mut entries)?;
        }
    } else {
        for page in 1..=1000usize {
            let mut url = endpoint(&repo.api, &["projects", &repo.path, "repository", "tree"])?;
            url.query_pairs_mut()
                .append_pair("ref", branch)
                .append_pair("recursive", "true")
                .append_pair("per_page", "100")
                .append_pair("page", &page.to_string());
            let (value, headers) = get(url)?;
            let nodes = value
                .as_array()
                .context("GitLab response must be an array")?;
            for node in nodes {
                push_node(node, subfolder, scope, &mut entries)?;
            }
            let next = headers
                .get("x-next-page")
                .context("GitLab pagination metadata is missing")?
                .to_str()?;
            if next.is_empty() {
                break;
            }
            ensure!(
                next.parse::<usize>()? == page + 1 && page < 1000,
                "Invalid or excessive GitLab pagination"
            );
        }
    }
    formats::normalize(entries)
}

pub fn push_node(
    node: &Value,
    subfolder: &str,
    scope: &Scope,
    entries: &mut Vec<Entry>,
) -> Result<()> {
    let path = node["path"]
        .as_str()
        .context("Remote node requires a path")?;
    safety::relative_path(path)?;
    let kind = node["type"]
        .as_str()
        .context("Remote node requires a type")?;
    ensure!(
        ["tree", "blob", "commit"].contains(&kind),
        "Unknown remote node type"
    );
    let path = if subfolder.is_empty() {
        path
    } else if let Some(path) = path.strip_prefix(&(subfolder.to_string() + "/")) {
        path
    } else {
        return Ok(());
    };
    if scope.includes(path) {
        entries.push(Entry::new(path, kind == "tree" || kind == "commit"));
    }
    ensure!(
        entries.len() <= safety::MAX_ENTRIES,
        "Remote entry limit exceeded"
    );
    Ok(())
}

pub fn check_version() -> Result<()> {
    let client = client()?;
    check_version_with(|url| request(&client, url, None).map(|(value, _)| value))
}

pub fn check_version_with(get: impl FnOnce(Url) -> Result<Value>) -> Result<()> {
    let value = match get(Url::parse(
        "https://api.github.com/repos/tanvirfoysal99/project-tree-utility/releases/latest",
    )?) {
        Ok(value) => value,
        Err(error)
            if error
                .downcast_ref::<HttpFailure>()
                .is_some_and(|e| e.0 == 404) =>
        {
            println!("No published upstream release is available; no update can be compared.");
            return Ok(());
        }
        Err(error) => return Err(error),
    };
    let tag = value["tag_name"]
        .as_str()
        .context("Release has no tag name")?;
    ensure!(
        !tag.is_empty() && tag.len() <= 256 && !tag.chars().any(char::is_control),
        "Invalid release tag"
    );
    println!("Latest published release: {}", tag);
    println!("This may refer to the legacy edition; inspect release notes before updating.");
    Ok(())
}
