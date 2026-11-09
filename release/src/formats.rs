use crate::safety::{self, MAX_DEPTH, MAX_ENTRIES};
use anyhow::{Context, Result, bail, ensure};
use base64::{Engine, engine::general_purpose::STANDARD};
use serde::{
    Deserialize, Serialize,
    de::{self, MapAccess, SeqAccess, Visitor},
};
use serde_json::Value;
use std::{
    collections::{BTreeMap, BTreeSet},
    fmt,
    path::Path,
};
use yaml_rust2::{Yaml, YamlLoader};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Entry {
    pub path: String,
    #[serde(rename = "isDir")]
    pub is_dir: bool,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub content: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub template: Option<String>,
}

impl Entry {
    pub fn new(path: impl Into<String>, is_dir: bool) -> Self {
        Self {
            path: path.into(),
            is_dir,
            content: None,
            template: None,
        }
    }
    pub fn depth(&self) -> usize {
        self.path.split('/').count()
    }
}

/// Reject duplicate properties instead of silently accepting the last value.
struct StrictValue(Value);
impl<'de> Deserialize<'de> for StrictValue {
    fn deserialize<D: serde::Deserializer<'de>>(
        deserializer: D,
    ) -> std::result::Result<Self, D::Error> {
        struct StrictVisitor;
        impl<'de> Visitor<'de> for StrictVisitor {
            type Value = StrictValue;
            fn expecting(&self, f: &mut fmt::Formatter) -> fmt::Result {
                f.write_str("JSON value with unique properties")
            }
            fn visit_map<M: MapAccess<'de>>(
                self,
                mut map: M,
            ) -> std::result::Result<Self::Value, M::Error> {
                let mut result = serde_json::Map::new();
                let mut seen = BTreeSet::new();
                while let Some((key, value)) = map.next_entry::<String, StrictValue>()? {
                    if !seen.insert(key.to_lowercase()) {
                        return Err(de::Error::custom("Duplicate property"));
                    }
                    result.insert(key, value.0);
                }
                Ok(StrictValue(Value::Object(result)))
            }
            fn visit_seq<S: SeqAccess<'de>>(
                self,
                mut seq: S,
            ) -> std::result::Result<Self::Value, S::Error> {
                let mut result = Vec::new();
                while let Some(value) = seq.next_element::<StrictValue>()? {
                    result.push(value.0);
                }
                Ok(StrictValue(Value::Array(result)))
            }
            fn visit_str<E: de::Error>(self, value: &str) -> std::result::Result<Self::Value, E> {
                Ok(StrictValue(Value::String(value.into())))
            }
            fn visit_string<E: de::Error>(
                self,
                value: String,
            ) -> std::result::Result<Self::Value, E> {
                Ok(StrictValue(Value::String(value)))
            }
            fn visit_bool<E: de::Error>(self, value: bool) -> std::result::Result<Self::Value, E> {
                Ok(StrictValue(Value::Bool(value)))
            }
            fn visit_i64<E: de::Error>(self, value: i64) -> std::result::Result<Self::Value, E> {
                Ok(StrictValue(value.into()))
            }
            fn visit_u64<E: de::Error>(self, value: u64) -> std::result::Result<Self::Value, E> {
                Ok(StrictValue(value.into()))
            }
            fn visit_f64<E: de::Error>(self, value: f64) -> std::result::Result<Self::Value, E> {
                Ok(StrictValue(serde_json::json!(value)))
            }
            fn visit_unit<E: de::Error>(self) -> std::result::Result<Self::Value, E> {
                Ok(StrictValue(Value::Null))
            }
        }
        deserializer.deserialize_any(StrictVisitor)
    }
}

pub fn detect(path: &Path, text: &str) -> Result<String> {
    match path
        .extension()
        .and_then(|x| x.to_str())
        .unwrap_or("")
        .to_lowercase()
        .as_str()
    {
        "json" => return Ok("json".into()),
        "yaml" | "yml" => return Ok("yaml".into()),
        _ => {}
    }
    let lines: Vec<_> = text
        .lines()
        .filter(|x| !x.trim().is_empty() && !x.trim_start().starts_with('#'))
        .collect();
    ensure!(!lines.is_empty(), "Structure is empty");
    if text.trim_start().starts_with(['[', '{']) {
        return Ok("json".into());
    }
    if lines.iter().any(|line| {
        let line = line.trim_start();
        let node = line
            .strip_prefix("- ")
            .unwrap_or(line)
            .trim_start()
            .to_lowercase();
        ["name:", "path:", "type:", "children:", "entries:"]
            .iter()
            .any(|key| node.starts_with(key))
    }) {
        return Ok("yaml".into());
    }
    if lines.iter().all(|x| x.starts_with('-')) {
        return Ok("dash".into());
    }
    if lines.iter().any(|x| x.contains("── ")) {
        return Ok("treesym".into());
    }
    let tabs = lines.iter().any(|x| x.starts_with('\t'));
    let spaces = lines.iter().any(|x| x.starts_with(' '));
    if tabs && !spaces {
        return Ok("tab".into());
    }
    if spaces && !tabs {
        return Ok("space".into());
    }
    bail!("Ambiguous structure; specify --format explicitly")
}

pub fn read(path: &Path, format: Option<&str>, space_unit: usize) -> Result<Vec<Entry>> {
    let text = safety::read_text(path)?;
    let format = format
        .map(str::to_owned)
        .map(Ok)
        .unwrap_or_else(|| detect(path, &text))?;
    parse(&text, &format, space_unit)
        .with_context(|| format!("Parsing {} as {format}", path.display()))
}

pub fn parse(text: &str, format: &str, space_unit: usize) -> Result<Vec<Entry>> {
    ensure!(
        text.len() as u64 <= safety::MAX_INPUT_BYTES,
        "Input exceeds the 8 MiB limit"
    );
    ensure!(
        space_unit > 0 && space_unit <= 16,
        "Space unit must be 1 through 16"
    );
    let text = text.trim_start_matches('\u{feff}');
    let mut entries = Vec::new();
    match format {
        "json" => {
            let value = serde_json::from_str::<StrictValue>(text)?.0;
            parse_nodes(&value, "", 0, &mut entries)?;
        }
        "yaml" => {
            // Anchors, aliases and tags are deliberately outside the layout schema.
            use yaml_rust2::scanner::{Scanner, TokenType};
            let mut nesting = 0usize;
            for token in Scanner::new(text.chars()) {
                match token.1 {
                    TokenType::Anchor(_) | TokenType::Alias(_) | TokenType::Tag(..) => {
                        bail!("YAML anchors, aliases and tags are unsupported")
                    }
                    TokenType::BlockSequenceStart
                    | TokenType::BlockMappingStart
                    | TokenType::FlowSequenceStart
                    | TokenType::FlowMappingStart => {
                        nesting += 1;
                        ensure!(nesting <= MAX_DEPTH, "YAML nesting limit exceeded");
                    }
                    TokenType::BlockEnd
                    | TokenType::FlowSequenceEnd
                    | TokenType::FlowMappingEnd => nesting = nesting.saturating_sub(1),
                    _ => {}
                }
            }
            let documents = YamlLoader::load_from_str(text)?;
            ensure!(
                documents.len() == 1,
                "Exactly one YAML document is required"
            );
            parse_nodes(&yaml_value(&documents[0], 0)?, "", 0, &mut entries)?;
        }
        "dash" | "importable" | "space" | "tab" | "treesym" => {
            let mut parents: Vec<String> = Vec::new();
            for (number, line) in text.lines().enumerate() {
                if line.trim().is_empty() || line.trim_start().starts_with('#') {
                    continue;
                }
                let (depth, body) = text_line(line, format, space_unit)
                    .with_context(|| format!("Line {}", number + 1))?;
                ensure!(
                    depth <= parents.len() && depth < MAX_DEPTH,
                    "Invalid indentation at line {}",
                    number + 1
                );
                parents.truncate(depth);
                let mut entry = directive_entry(body)?;
                if depth > 0 {
                    entry.path = format!("{}/{}", parents[depth - 1], entry.path);
                }
                if entry.is_dir {
                    parents.push(entry.path.clone());
                }
                entries.push(entry);
                ensure!(entries.len() <= MAX_ENTRIES, "Too many entries");
            }
        }
        _ => bail!("Unsupported input format: {format}"),
    }
    normalize(entries)
}

fn yaml_value(yaml: &Yaml, depth: usize) -> Result<Value> {
    ensure!(depth <= MAX_DEPTH, "YAML nesting limit exceeded");
    Ok(match yaml {
        Yaml::String(value) => Value::String(value.clone()),
        Yaml::Boolean(value) => Value::Bool(*value),
        Yaml::Integer(value) => (*value).into(),
        Yaml::Real(value) => serde_json::from_str(value)?,
        Yaml::Null => Value::Null,
        Yaml::Array(values) => Value::Array(
            values
                .iter()
                .map(|v| yaml_value(v, depth + 1))
                .collect::<Result<_>>()?,
        ),
        Yaml::Hash(values) => {
            let mut result = serde_json::Map::new();
            let mut seen = BTreeSet::new();
            for (key, value) in values {
                let key = key
                    .as_str()
                    .context("YAML property names must be strings")?;
                ensure!(seen.insert(key.to_lowercase()), "Duplicate YAML property");
                result.insert(key.to_owned(), yaml_value(value, depth + 1)?);
            }
            Value::Object(result)
        }
        _ => bail!("Unsupported YAML value"),
    })
}

fn parse_nodes(value: &Value, parent: &str, depth: usize, out: &mut Vec<Entry>) -> Result<()> {
    ensure!(
        depth <= MAX_DEPTH && out.len() <= MAX_ENTRIES,
        "Structure complexity limit exceeded"
    );
    match value {
        Value::Array(nodes) => {
            for node in nodes {
                parse_nodes(node, parent, depth + 1, out)?;
            }
        }
        Value::String(path) => {
            let is_dir = path.ends_with(['/', '\\']);
            let mut entry = Entry::new(without_marker(path), is_dir);
            if !parent.is_empty() {
                entry.path = format!("{parent}/{}", entry.path);
            }
            out.push(entry);
        }
        Value::Object(object) => {
            let node: BTreeMap<_, _> = object
                .iter()
                .map(|(key, value)| (key.to_lowercase(), value))
                .collect();
            let allowed = [
                "name",
                "path",
                "type",
                "isdir",
                "children",
                "entries",
                "content",
                "contentdirective",
                "template",
            ];
            for key in node.keys() {
                ensure!(
                    allowed.contains(&key.as_str()),
                    "Unknown node property: {key}"
                );
            }
            ensure!(
                !(node.contains_key("name") && node.contains_key("path")),
                "Supply name or path, not both"
            );
            ensure!(
                !(node.contains_key("children") && node.contains_key("entries")),
                "Supply children or entries, not both"
            );
            let children = node.get("children").or_else(|| node.get("entries"));
            if let Some(children) = children {
                ensure!(children.is_array(), "Children must be an array");
            }
            let name = node.get("path").or_else(|| node.get("name"));
            if name.is_none() {
                ensure!(
                    node.len() == 1
                        && children.is_some_and(|v| v.as_array().is_some_and(|a| !a.is_empty())),
                    "Node requires name/path"
                );
                return parse_nodes(children.unwrap(), parent, depth + 1, out);
            }
            let name = name
                .unwrap()
                .as_str()
                .context("Name/path must be a string")?;
            let explicit_dir = if let Some(kind) = node.get("type") {
                Some(
                    match kind
                        .as_str()
                        .context("Type must be a string")?
                        .to_lowercase()
                        .as_str()
                    {
                        "file" | "blob" => false,
                        "dir" | "directory" | "folder" | "tree" => true,
                        _ => bail!("Unknown node type"),
                    },
                )
            } else {
                None
            };
            let bool_dir = node
                .get("isdir")
                .map(|v| v.as_bool().context("isDir must be boolean"))
                .transpose()?;
            if let (Some(a), Some(b)) = (explicit_dir, bool_dir) {
                ensure!(a == b, "Conflicting type indicators");
            }
            let is_dir = explicit_dir
                .or(bool_dir)
                .unwrap_or(children.is_some() || name.ends_with(['/', '\\']));
            ensure!(is_dir || children.is_none(), "Files cannot have children");
            ensure!(
                !name.ends_with(['/', '\\']) || is_dir,
                "Trailing slash conflicts with file type"
            );
            let path = without_marker(name);
            let path = if parent.is_empty() {
                path.to_owned()
            } else {
                format!("{parent}/{path}")
            };
            let mut entry = Entry::new(path.clone(), is_dir);
            entry.content = node
                .get("content")
                .map(|v| {
                    v.as_str()
                        .map(str::to_owned)
                        .context("Content must be a string")
                })
                .transpose()?;
            entry.template = node
                .get("template")
                .map(|v| {
                    v.as_str()
                        .map(str::to_owned)
                        .context("Template must be a string")
                })
                .transpose()?;
            if let Some(value) = node.get("contentdirective") {
                let content = decode_directive(
                    value
                        .as_str()
                        .context("contentDirective must be a string")?,
                )?;
                if entry.content.is_none() {
                    entry.content = Some(content);
                }
            }
            ensure!(
                !is_dir || (entry.content.is_none() && entry.template.is_none()),
                "Directories cannot carry file content/templates"
            );
            out.push(entry);
            if let Some(children) = children {
                parse_nodes(children, &path, depth + 1, out)?;
            }
        }
        _ => bail!("Expected a node, path string, or node array"),
    }
    Ok(())
}

fn text_line<'a>(line: &'a str, format: &str, unit: usize) -> Result<(usize, &'a str)> {
    match format {
        "dash" | "importable" => {
            let count = line.bytes().take_while(|b| *b == b'-').count();
            ensure!(
                count > 0 && line[count..].starts_with(' '),
                "Dash entries require '- name'"
            );
            Ok((count - 1, &line[count + 1..]))
        }
        "space" => {
            let count = line.bytes().take_while(|b| *b == b' ').count();
            ensure!(
                count.is_multiple_of(unit) && !line[count..].starts_with('\t'),
                "Invalid space indentation"
            );
            Ok((count / unit, &line[count..]))
        }
        "tab" => {
            let count = line.bytes().take_while(|b| *b == b'\t').count();
            ensure!(!line[count..].starts_with(' '), "Mixed indentation");
            Ok((count, &line[count..]))
        }
        "treesym" => {
            let mut depth = 0;
            let mut body = line;
            while body.starts_with("│   ") || body.starts_with("    ") {
                body = if let Some(rest) = body.strip_prefix("│   ") {
                    rest
                } else {
                    &body[4..]
                };
                depth += 1;
            }
            let body = body
                .strip_prefix("├── ")
                .or_else(|| body.strip_prefix("└── "))
                .context("Invalid tree connector")?;
            Ok((depth, body))
        }
        _ => unreachable!(),
    }
}

fn decode_directive(value: &str) -> Result<String> {
    if let Some(value) = value.strip_prefix("@content64:") {
        return String::from_utf8(STANDARD.decode(value)?).context("Content must be UTF-8");
    }
    if let Some(value) = value.strip_prefix("@content:") {
        return Ok(value.to_owned());
    }
    bail!("Unsupported content directive")
}

fn without_marker(path: &str) -> &str {
    path.strip_suffix('/')
        .or_else(|| path.strip_suffix('\\'))
        .unwrap_or(path)
}

fn directive_entry(body: &str) -> Result<Entry> {
    let marker = [" @content:", " @content64:", " @template:"]
        .iter()
        .filter_map(|m| body.find(m))
        .min();
    let name = &body[..marker.unwrap_or(body.len())];
    ensure!(!name.is_empty(), "Entry name is empty");
    let is_dir = name.ends_with(['/', '\\']);
    let mut entry = Entry::new(without_marker(name), is_dir);
    let mut directives = marker.map(|i| body[i..].trim_start()).unwrap_or("");
    while !directives.is_empty() {
        if let Some(rest) = directives.strip_prefix("@template:") {
            let end = rest.find(" @").unwrap_or(rest.len());
            ensure!(entry.template.is_none(), "Duplicate template directive");
            let name = &rest[..end];
            ensure!(
                !name.is_empty() && !name.contains(char::is_whitespace),
                "Invalid template directive"
            );
            entry.template = Some(name.into());
            directives = rest[end..].trim_start();
        } else if directives.starts_with("@content64:") {
            let end = directives.find(" @").unwrap_or(directives.len());
            ensure!(entry.content.is_none(), "Duplicate content directive");
            entry.content = Some(decode_directive(&directives[..end])?);
            directives = directives[end..].trim_start();
        } else if directives.starts_with("@content:") {
            ensure!(entry.content.is_none(), "Duplicate content directive");
            entry.content = Some(decode_directive(directives)?);
            break;
        } else {
            bail!("Unknown directive");
        }
    }
    ensure!(
        !entry.is_dir || (entry.content.is_none() && entry.template.is_none()),
        "Directory content is unsupported"
    );
    Ok(entry)
}

pub fn normalize(entries: Vec<Entry>) -> Result<Vec<Entry>> {
    let mut nodes: BTreeMap<String, Entry> = BTreeMap::new();
    let mut explicit = BTreeSet::new();
    for mut entry in entries {
        entry.path = safety::relative_path(&entry.path)?;
        if let Some(template) = &entry.template {
            ensure!(
                ["react-vite", "hono-worker", "monorepo-pnpm"].contains(&template.as_str()),
                "Unknown template context: {template}"
            );
        }
        ensure!(
            !entry.is_dir || (entry.content.is_none() && entry.template.is_none()),
            "Directories cannot carry file content/templates"
        );
        let key = entry.path.to_lowercase();
        ensure!(
            explicit.insert(key.clone()),
            "Duplicate path: {}",
            entry.path
        );
        if let Some(old) = nodes.get(&key) {
            ensure!(
                old.is_dir && entry.is_dir,
                "Path type conflict: {}",
                entry.path
            );
        }
        let parts: Vec<_> = entry.path.split('/').collect();
        for length in 1..parts.len() {
            let path = parts[..length].join("/");
            let key = path.to_lowercase();
            if let Some(old) = nodes.get(&key) {
                ensure!(old.is_dir, "File used as parent: {path}");
            } else {
                nodes.insert(key, Entry::new(path, true));
            }
        }
        nodes.insert(key, entry);
        ensure!(nodes.len() <= MAX_ENTRIES, "Maximum entry count exceeded");
    }
    // Make implicit ancestor spelling canonical on case-sensitive filesystems too.
    let mut result = Vec::with_capacity(nodes.len());
    for entry in nodes.values() {
        let mut entry = entry.clone();
        let parts: Vec<_> = entry.path.split('/').collect();
        let mut canonical = Vec::new();
        for i in 1..=parts.len() {
            let ancestor = nodes
                .get(&parts[..i].join("/").to_lowercase())
                .context("Missing ancestor")?;
            canonical.push(ancestor.path.rsplit('/').next().unwrap().to_owned());
        }
        entry.path = canonical.join("/");
        result.push(entry);
    }
    result.sort_by_cached_key(|entry| entry.path.to_lowercase());
    Ok(result)
}

pub fn render(entries: &[Entry], format: &str) -> Result<String> {
    match format {
        "treesym" => render_tree(entries),
        "json" => Ok(serde_json::to_string_pretty(entries)? + "\n"),
        "yaml" => {
            if entries.is_empty() {
                return Ok("[]\n".into());
            }
            // Emit JSON-quoted scalars in block YAML, preserving arbitrary file content.
            let mut text = String::new();
            for entry in entries {
                text += &format!(
                    "- path: {}\n  isDir: {}\n",
                    serde_json::to_string(&entry.path)?,
                    entry.is_dir
                );
                if let Some(content) = &entry.content {
                    text += &format!("  content: {}\n", serde_json::to_string(content)?);
                }
                if let Some(template) = &entry.template {
                    text += &format!("  template: {}\n", serde_json::to_string(template)?);
                }
            }
            Ok(text)
        }
        "importable" | "dash" => {
            let mut text = String::new();
            for entry in entries {
                ensure!(
                    ![" @content:", " @content64:", " @template:"]
                        .iter()
                        .any(|marker| entry.path.contains(marker)),
                    "Path contains a text directive marker; use JSON or YAML output"
                );
                text += &format!("- {}{}", entry.path, if entry.is_dir { "/" } else { "" });
                if let Some(content) = &entry.content {
                    text += &format!(" @content64:{}", STANDARD.encode(content));
                }
                if let Some(template) = &entry.template {
                    text += &format!(" @template:{template}");
                }
                text.push('\n');
            }
            Ok(text)
        }
        "txt" | "md" => {
            let mut displayed: Vec<_> = entries.iter().collect();
            displayed.sort_by_cached_key(|entry| {
                entry
                    .path
                    .split('/')
                    .map(str::to_lowercase)
                    .collect::<Vec<_>>()
            });
            let longest_ticks = entries
                .iter()
                .flat_map(|e| e.path.split(|c| c != '`'))
                .map(str::len)
                .max()
                .unwrap_or(0);
            let fence = "`".repeat(longest_ticks.max(2) + 1);
            let mut text = if format == "md" {
                format!("# Project structure\n\n{fence}text\n")
            } else {
                String::new()
            };
            for entry in displayed {
                text += &format!(
                    "{}{}{}\n",
                    "  ".repeat(entry.depth() - 1),
                    entry.path.rsplit('/').next().unwrap(),
                    if entry.is_dir { "/" } else { "" }
                );
            }
            if format == "md" {
                text += &format!("{fence}\n");
            }
            Ok(text)
        }
        "summary" => Ok(format!(
            "{} directories, {} files\n",
            entries.iter().filter(|x| x.is_dir).count(),
            entries.iter().filter(|x| !x.is_dir).count()
        )),
        _ => bail!("Unsupported output format: {format}"),
    }
}

fn render_tree(entries: &[Entry]) -> Result<String> {
    let entries = normalize(entries.to_vec())?;
    let mut children: BTreeMap<&str, Vec<&Entry>> = BTreeMap::new();
    for entry in &entries {
        let parent = entry
            .path
            .rsplit_once('/')
            .map(|(parent, _)| parent)
            .unwrap_or("");
        children.entry(parent).or_default().push(entry);
    }
    fn emit(
        parent: &str,
        prefix: &str,
        children: &BTreeMap<&str, Vec<&Entry>>,
        output: &mut String,
    ) {
        let Some(siblings) = children.get(parent) else {
            return;
        };
        for (index, entry) in siblings.iter().enumerate() {
            let last = index + 1 == siblings.len();
            output.push_str(prefix);
            output.push_str(if last { "└── " } else { "├── " });
            output.push_str(entry.path.rsplit('/').next().unwrap());
            if entry.is_dir {
                output.push('/');
            }
            if let Some(content) = &entry.content {
                output.push_str(&format!(" @content64:{}", STANDARD.encode(content)));
            }
            if let Some(template) = &entry.template {
                output.push_str(&format!(" @template:{template}"));
            }
            output.push('\n');
            if entry.is_dir {
                emit(
                    &entry.path,
                    &format!("{prefix}{}", if last { "    " } else { "│   " }),
                    children,
                    output,
                );
            }
        }
    }
    let mut output = String::new();
    emit("", "", &children, &mut output);
    Ok(output)
}

pub fn merge(a: Vec<Entry>, b: Vec<Entry>, strategy: &str) -> Result<Vec<Entry>> {
    ensure!(
        ["union", "a_over_b", "b_over_a"].contains(&strategy),
        "Unknown merge strategy"
    );
    let (preferred, fallback) = if strategy == "b_over_a" {
        (b, a)
    } else {
        (a, b)
    };
    let mut nodes: BTreeMap<_, _> = preferred
        .into_iter()
        .map(|e| (e.path.to_lowercase(), e))
        .collect();
    for entry in fallback {
        let key = entry.path.to_lowercase();
        if key
            .split('/')
            .scan(String::new(), |parent, part| {
                if !parent.is_empty() {
                    parent.push('/');
                }
                parent.push_str(part);
                Some(parent.clone())
            })
            .any(|p| p != key && nodes.get(&p).is_some_and(|n| !n.is_dir))
        {
            continue;
        }
        if let Some(old) = nodes.get_mut(&key) {
            if old.is_dir != entry.is_dir {
                ensure!(strategy != "union", "Type conflict: {}", entry.path);
                continue;
            }
            if strategy == "union" {
                ensure!(
                    old.content.is_none()
                        || entry.content.is_none()
                        || old.content == entry.content,
                    "Content conflict: {}",
                    entry.path
                );
                ensure!(
                    old.template.is_none()
                        || entry.template.is_none()
                        || old.template == entry.template,
                    "Template conflict: {}",
                    entry.path
                );
            }
            if old.content.is_none() {
                old.content = entry.content;
            }
            if old.template.is_none() {
                old.template = entry.template;
            }
        } else {
            nodes.insert(key, entry);
        }
    }
    normalize(nodes.into_values().collect())
}
