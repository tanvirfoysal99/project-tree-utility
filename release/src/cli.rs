use crate::{
    auth, formats, library, operations, remote, safety,
    scan::{self, Scope},
    templates,
};
use anyhow::{Context, Result, bail, ensure};
use std::{
    collections::BTreeMap,
    io::{self, BufRead, IsTerminal, Read, Write},
    path::Path,
    sync::{
        Arc, OnceLock,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::Duration,
};

pub const HELP: &str = "Project Tree Utility (Rust edition)\n\nUsage: ptu <command> [options] [--ci]\n\nCommands:\n  import      Validate and convert a structure file\n  export      Export a directory layout\n  scaffold    Create a project from a structure or template\n  verify      Compare a directory; optionally synchronize\n  merge       Merge two structures\n  watch       Monitor structural changes (read-only)\n  gittree     Export a GitHub/GitLab repository layout\n  auth        Store or clear a remote credential\n  library     Manage saved structures\n  security    Validate names, structure, and containment\n  detection   Legacy analysis/merge adapter\n  version     Print version; optionally check upstream\n\nUse ptu <command> --help for options. No arguments opens a menu on a terminal.\nInput: dash, tab, space, treesym, json, yaml. Output: treesym, importable, txt, md, json, yaml.\nExit codes: 0 success, 1 drift/not found/negative result, 2 invalid input or failure.\n";

#[derive(Debug)]
pub struct Options {
    pub command: String,
    pub values: BTreeMap<String, String>,
    pub ci: bool,
    pub help: bool,
}

fn specification(command: &str) -> Result<(&'static str, &'static str)> {
    Ok(match command {
        "import" => (
            "structure format output output-format space-unit",
            "structure format output output-format",
        ),
        "export" => (
            "root format output output-format max-depth show-mode exclude ignore-file",
            "root format output max-depth show-mode exclude ignore-file",
        ),
        "scaffold" => (
            "structure format target project template overwrite dry-run space-unit",
            "structure format target project",
        ),
        "verify" => (
            "live structure format space-unit ignore-file sync delete-extras",
            "live structure format",
        ),
        "merge" => (
            "file-a format-a file-b format-b strategy output space-unit-a space-unit-b",
            "file-a format-a file-b format-b strategy output",
        ),
        "watch" => (
            "path structure format max-depth ignore-file interval-ms",
            "path structure ignore-file max-depth",
        ),
        "gittree" => (
            "provider repo branch output format subfolder max-depth exclude gitlab-base anonymous",
            "provider repo branch output format subfolder max-depth exclude gitlab-base",
        ),
        "auth" => (
            "action target username secret-env secret-stdin",
            "action target username",
        ),
        "library" => ("action file format source name new-name yes", ""),
        "security" => ("action file format base candidate", ""),
        "version" => ("check", ""),
        "detection" => ("", ""),
        _ => bail!("Unknown command: {command}. Use --help."),
    })
}

fn alias(key: &str) -> &str {
    match key {
        "structurefile" => "structure",
        "livepath" => "live",
        "rootpath" => "root",
        "outputfile" => "output",
        "outputformat" => "output-format",
        "targetbase" => "target",
        "projectname" => "project",
        "templatename" => "template",
        "overwritemode" => "overwrite",
        "dryrun" => "dry-run",
        "ignorefile" => "ignore-file",
        "maxdepth" => "max-depth",
        "showmode" => "show-mode",
        "extraexclude" | "excludelist" => "exclude",
        "spaceunit" => "space-unit",
        "deleteextras" => "delete-extras",
        "filea" => "file-a",
        "fileb" => "file-b",
        "formata" => "format-a",
        "formatb" => "format-b",
        "spaceunita" => "space-unit-a",
        "spaceunitb" => "space-unit-b",
        "repourl" => "repo",
        "gitlabbaseurl" => "gitlab-base",
        "subfolder" => "subfolder",
        "check-update" | "checkupdate" => "check",
        key => key,
    }
}

impl Options {
    pub fn parse(args: &[String]) -> Result<Self> {
        let mut args = args.to_vec();
        let mut ci = std::env::var("TREE_CI")
            .is_ok_and(|v| ["1", "true", "yes"].contains(&v.to_lowercase().as_str()));
        let mut ended = false;
        args.retain(|a| {
            if a == "--" {
                ended = true;
            }
            if !ended && (a.eq_ignore_ascii_case("--ci") || a.eq_ignore_ascii_case("-ci")) {
                ci = true;
                false
            } else {
                true
            }
        });
        if args.first().is_some_and(|a| a == "--version" || a == "-V") {
            args[0] = "version".into();
        }
        if args.is_empty() {
            ensure!(!ci, "A command is required in CI mode");
            return Ok(Self {
                command: String::new(),
                values: BTreeMap::new(),
                ci,
                help: true,
            });
        }
        if args[0] == "--help" || args[0] == "-h" {
            return Ok(Self {
                command: String::new(),
                values: BTreeMap::new(),
                ci,
                help: true,
            });
        }
        if args[0] == "help" {
            args.remove(0);
            if args.is_empty() {
                return Self::parse(&[]);
            }
            args.push("--help".into());
            return Self::parse(&args);
        }
        let command = args[0].to_lowercase();
        let (allowed, positional) = specification(&command)?;
        let switches = [
            "sync",
            "delete-extras",
            "dry-run",
            "check",
            "yes",
            "secret-stdin",
            "anonymous",
        ];
        let mut values = BTreeMap::new();
        let mut positionals = Vec::new();
        let mut help = false;
        let mut index = 1;
        while index < args.len() {
            let token = &args[index];
            if token == "--help" || token == "-h" {
                help = true;
                index += 1;
                continue;
            }
            if token == "--" {
                positionals.extend(args[index + 1..].iter().cloned());
                break;
            }
            if token.starts_with('-') {
                let (raw, inline) = token
                    .trim_start_matches('-')
                    .split_once('=')
                    .map(|(k, v)| (k, Some(v)))
                    .unwrap_or((token.trim_start_matches('-'), None));
                let lower = raw.to_lowercase();
                let key = alias(&lower);
                ensure!(
                    allowed.split_whitespace().any(|a| a == key),
                    "Unknown option for {command}: --{key}"
                );
                ensure!(!values.contains_key(key), "Duplicate option: --{key}");
                let value = if switches.contains(&key) {
                    ensure!(inline.is_none(), "--{key} takes no value");
                    "true".into()
                } else if let Some(value) = inline {
                    value.into()
                } else {
                    index += 1;
                    let value = args
                        .get(index)
                        .filter(|v| !v.starts_with("--"))
                        .with_context(|| format!("Missing value for --{key}"))?;
                    value.clone()
                };
                values.insert(key.to_string(), value);
            } else {
                positionals.push(token.clone());
            }
            index += 1;
        }
        if command == "detection" {
            if help {
                return Ok(Self {
                    command,
                    values,
                    ci,
                    help,
                });
            }
            let mode = positionals
                .first()
                .context("Detection requires ANALYSE or BUILD_TREE")?
                .to_uppercase();
            let mapped = match mode.as_str() {
                "ANALYSE" if positionals.len() == 3 => vec![
                    "import".into(),
                    "--structure".into(),
                    positionals[1].clone(),
                    "--format".into(),
                    positionals[2].clone(),
                    "--output".into(),
                    "unused".into(),
                    "--output-format".into(),
                    "summary".into(),
                ],
                "BUILD_TREE" if positionals.len() == 7 => vec![
                    "merge".into(),
                    positionals[1].clone(),
                    positionals[2].clone(),
                    positionals[3].clone(),
                    positionals[4].clone(),
                    positionals[5].clone(),
                    positionals[6].clone(),
                ],
                _ if help => {
                    return Ok(Self {
                        command,
                        values,
                        ci,
                        help,
                    });
                }
                _ => bail!(
                    "Detection requires ANALYSE file format or BUILD_TREE fileA formatA fileB formatB strategy output"
                ),
            };
            let mut options = Self::parse(&mapped)?;
            options.ci = ci;
            return Ok(options);
        }
        let mut names = positional.to_string();
        if command == "library" || command == "security" {
            if !positionals.is_empty() {
                ensure!(!values.contains_key("action"), "Specify action once");
                values.insert("action".into(), positionals.remove(0));
            }
            let action = values
                .get("action")
                .map(|s| s.to_lowercase())
                .unwrap_or_default();
            names = match (command.as_str(), action.as_str()) {
                ("library", "save") => "file format source name",
                ("library", "open" | "delete") => "name",
                ("library", "rename") => "name new-name",
                ("security", "validate_path") => "candidate base",
                ("security", _) => "file format base",
                _ => "",
            }
            .into();
        }
        let names: Vec<_> = names.split_whitespace().collect();
        ensure!(
            positionals.len() <= names.len(),
            "Too many positional arguments for {command}"
        );
        for (name, value) in names.iter().zip(positionals) {
            ensure!(!values.contains_key(*name), "Specify {name} once");
            values.insert(name.to_string(), value);
        }
        Ok(Self {
            command,
            values,
            ci,
            help,
        })
    }

    pub fn get(&self, key: &str) -> Option<&str> {
        self.values.get(key).map(String::as_str)
    }
    pub fn required(&self, key: &str) -> Result<&str> {
        self.get(key)
            .filter(|v| !v.is_empty())
            .with_context(|| format!("Required option: --{key}"))
    }
    pub fn value<'a>(&'a self, key: &str, default: &'a str) -> &'a str {
        self.get(key).unwrap_or(default)
    }
    pub fn flag(&self, key: &str) -> bool {
        self.values.contains_key(key)
    }
    pub fn number(&self, key: &str, default: usize) -> Result<usize> {
        self.get(key)
            .map(|v| {
                v.parse()
                    .with_context(|| format!("--{key} must be a nonnegative integer"))
            })
            .unwrap_or(Ok(default))
    }
    fn layout(&self, key: &str, format: &str, unit: &str) -> Result<Vec<formats::Entry>> {
        formats::read(
            Path::new(self.required(key)?),
            self.get(format),
            self.number(unit, 2)?,
        )
    }

    pub fn validate(&self) -> Result<()> {
        let required: &[&str] = match self.command.as_str() {
            "import" => &["structure", "output"],
            "export" => &["root", "output"],
            "scaffold" => &["target", "project"],
            "verify" => &["live", "structure"],
            "merge" => &["file-a", "file-b", "output"],
            "watch" => &["path"],
            "gittree" => &["provider", "repo", "branch", "format", "output"],
            "auth" => &["action", "target"],
            "library" | "security" => &["action"],
            _ => &[],
        };
        for key in required {
            self.required(key)?;
        }
        if self.command == "export" {
            ensure!(
                !(self.flag("format") && self.flag("output-format")),
                "Specify --format or --output-format, not both"
            );
            ensure!(
                self.flag("format") || self.flag("output-format"),
                "Required option: --format"
            );
        }
        for key in ["format", "format-a", "format-b", "output-format"] {
            if let Some(value) = self.get(key) {
                let output = key == "output-format"
                    || (["export", "gittree"].contains(&self.command.as_str()) && key == "format");
                let allowed: &[&str] = if output {
                    &[
                        "importable",
                        "dash",
                        "treesym",
                        "txt",
                        "md",
                        "json",
                        "yaml",
                        "summary",
                    ]
                } else {
                    &[
                        "dash",
                        "importable",
                        "tab",
                        "space",
                        "treesym",
                        "json",
                        "yaml",
                    ]
                };
                ensure!(allowed.contains(&value), "Unsupported {key}: {value}");
            }
        }
        for key in ["space-unit", "space-unit-a", "space-unit-b"] {
            if self.flag(key) {
                ensure!(
                    (1..=16).contains(&self.number(key, 2)?),
                    "--{key} must be 1–16"
                );
            }
        }
        if self.flag("max-depth") {
            self.number("max-depth", 5)?;
        }
        if self.flag("show-mode") {
            ensure!(
                ["all", "files", "folders"].contains(&self.required("show-mode")?),
                "Invalid show mode"
            );
        }
        if self.command == "verify" {
            ensure!(
                !self.flag("delete-extras") || self.flag("sync"),
                "--delete-extras requires --sync"
            );
        }
        if self.command == "scaffold" {
            ensure!(
                self.flag("structure") != self.flag("template"),
                "Choose exactly one of --structure or --template"
            );
            ensure!(
                ["skip", "overwrite", "ask"].contains(&self.value("overwrite", "skip")),
                "Invalid overwrite mode"
            );
        }
        if self.command == "library" {
            let fields: &[&str] = match self.required("action")?.to_lowercase().as_str() {
                "save" => &["file", "name"],
                "open" | "delete" => &["name"],
                "rename" => &["name", "new-name"],
                "list" => &[],
                "purge" => {
                    ensure!(self.flag("yes"), "Library purge requires --yes");
                    &[]
                }
                _ => bail!("Unknown library action"),
            };
            for key in fields {
                self.required(key)?;
            }
        }
        if self.command == "security" {
            let fields: &[&str] = match self.required("action")?.to_uppercase().as_str() {
                "VALIDATE_FILE" | "VALIDATE_NAMES" => &["file"],
                "VALIDATE_ALL" => &["file", "base"],
                "VALIDATE_PATH" => &["candidate", "base"],
                _ => bail!("Unknown security action"),
            };
            for key in fields {
                self.required(key)?;
            }
        }
        if self.command == "auth" {
            ensure!(
                ["store", "clear"].contains(&self.required("action")?.to_lowercase().as_str()),
                "Auth action must be store or clear"
            );
        }
        Ok(())
    }
}

pub fn run(options: Options) -> Result<i32> {
    if options.help {
        if options.command.is_empty() {
            print!("{HELP}");
        } else {
            let (allowed, positional) = specification(&options.command)?;
            println!(
                "ptu {}\n\nOptions: {}\nPositional order: {}\n\nUse --ci for noninteractive execution. See docs/CLI.md for requirements and examples.",
                options.command,
                allowed
                    .split_whitespace()
                    .map(|s| format!("--{s}"))
                    .collect::<Vec<_>>()
                    .join(" "),
                positional
            );
        }
        if ["export", "import", "gittree"].contains(&options.command.as_str()) {
            println!("\nOutput formats: treesym, importable, dash, txt, md, json, yaml, summary.");
        }
        if options.command == "export" {
            println!(
                "Example: export --root \"C:/Projects/app\" --format treesym --output \"C:/Projects/tree.txt\" --max-depth 0"
            );
        }
        return Ok(0);
    }
    options.validate()?;
    let o = &options;
    match o.command.as_str() {
        "import" => {
            let entries = o.layout("structure", "format", "space-unit")?;
            let output = o.required("output")?;
            let format = o.value("output-format", "importable");
            let text = formats::render(&entries, format)?;
            if format == "summary" {
                print!("{text}");
            } else {
                safety::atomic_write(Path::new(output), text.as_bytes())?;
            }
        }
        "export" => {
            ensure!(
                !(o.flag("format") && o.flag("output-format")),
                "Specify --format or --output-format, not both"
            );
            let root = Path::new(o.required("root")?);
            let format = o
                .get("format")
                .or_else(|| o.get("output-format"))
                .context("Required option: --format")?;
            let scope = scope(o, root)?;
            let entries = scan::scan(root, &scope)?;
            let shown = scan::displayed(&entries, &scope.show_mode, format);
            safety::atomic_write(
                Path::new(o.required("output")?),
                formats::render(&shown, format)?.as_bytes(),
            )?;
            println!("Exported {} entries", shown.len());
        }
        "scaffold" => {
            ensure!(
                o.flag("structure") != o.flag("template"),
                "Choose exactly one of --structure or --template"
            );
            let project = safety::relative_path(o.required("project")?)?;
            ensure!(
                !project.contains('/'),
                "Project name must be one directory component"
            );
            let root = safety::destination(Path::new(o.required("target")?), &project)?;
            let entries = if let Some(name) = o.get("template") {
                templates::preset(name)?
            } else {
                o.layout("structure", "format", "space-unit")?
            };
            let counts = operations::scaffold(
                &root,
                &entries,
                o.value("overwrite", "skip"),
                o.flag("dry-run"),
                !o.ci && io::stdin().is_terminal(),
            )?;
            println!(
                "{} created, {} overwritten, {} skipped{}",
                counts.created,
                counts.overwritten,
                counts.skipped,
                if o.flag("dry-run") { " (dry run)" } else { "" }
            );
        }
        "verify" => {
            let root = Path::new(o.required("live")?);
            let entries = o.layout("structure", "format", "space-unit")?;
            let scope = scope(o, root)?;
            let (report, counts) = operations::verify(
                root,
                &entries,
                &scope,
                o.flag("sync"),
                o.flag("delete-extras"),
            )?;
            report.print();
            if o.flag("sync") {
                println!("{} created, {} deleted", counts.created, counts.deleted);
            }
            return Ok(i32::from(!report.clean()));
        }
        "merge" => {
            let a = o.layout("file-a", "format-a", "space-unit-a")?;
            let b = o.layout("file-b", "format-b", "space-unit-b")?;
            let merged = formats::merge(a, b, o.value("strategy", "union"))?;
            safety::atomic_write(
                Path::new(o.required("output")?),
                formats::render(&merged, "importable")?.as_bytes(),
            )?;
        }
        "security" => {
            let action = o.required("action")?.to_uppercase();
            match action.as_str() {
                "VALIDATE_PATH" => {
                    match safety::contained(
                        Path::new(o.required("base")?),
                        Path::new(o.required("candidate")?),
                    ) {
                        Ok(()) => {}
                        Err(error) => {
                            eprintln!("Rejected: {error}");
                            return Ok(1);
                        }
                    }
                }
                "VALIDATE_FILE" | "VALIDATE_NAMES" | "VALIDATE_ALL" => {
                    let entries = o.layout("file", "format", "space-unit")?;
                    if action == "VALIDATE_ALL" {
                        let base = Path::new(o.required("base")?);
                        for entry in entries {
                            safety::destination(base, &entry.path)?;
                        }
                    }
                }
                _ => bail!("Unknown security action"),
            }
            println!("Security validation passed");
        }
        "library" => {
            let directory = library::data_dir()?;
            let mut library = library::Library::open(&directory)?;
            match o.required("action")?.to_lowercase().as_str() {
                "list" => {
                    println!("ID\tNAME\tENTRIES\tSOURCE");
                    for item in library.list() {
                        println!(
                            "{}\t{}\t{}\t{}",
                            item.id,
                            item.name,
                            item.entries.len(),
                            item.source
                        );
                    }
                }
                "save" => {
                    let entries = o.layout("file", "format", "space-unit")?;
                    println!(
                        "Saved {}",
                        library.save(o.required("name")?, o.value("source", "manual"), entries)?
                    );
                }
                "open" => match library.export(o.required("name")?)? {
                    Some(path) => println!("{}", path.display()),
                    None => return Ok(1),
                },
                "rename" => {
                    return Ok(i32::from(
                        !library.rename(o.required("name")?, o.required("new-name")?)?,
                    ));
                }
                "delete" => return Ok(i32::from(!library.delete(o.required("name")?)?)),
                "purge" => {
                    ensure!(o.flag("yes"), "Library purge requires --yes");
                    library.purge()?;
                }
                _ => bail!("Unknown library action"),
            }
        }
        "auth" => {
            let target = auth::target(o.required("target")?)?;
            match o.required("action")?.to_lowercase().as_str() {
                "clear" => {
                    ensure!(
                        !o.flag("secret-env") && !o.flag("secret-stdin"),
                        "Clear does not accept a secret"
                    );
                    auth::clear(&target)?;
                }
                "store" => {
                    ensure!(
                        !(o.flag("secret-env") && o.flag("secret-stdin")),
                        "Choose one secret channel"
                    );
                    let secret = if let Some(name) = o.get("secret-env") {
                        std::env::var(name)
                            .context("Secret environment variable is missing or not UTF-8")?
                    } else if o.flag("secret-stdin") {
                        let mut value = String::new();
                        io::stdin().lock().take(16_386).read_line(&mut value)?;
                        value.trim_end_matches(['\r', '\n']).to_owned()
                    } else {
                        ensure!(
                            !o.ci && io::stdin().is_terminal(),
                            "Noninteractive storage requires --secret-env NAME or --secret-stdin"
                        );
                        rpassword::prompt_password("Token: ")?
                    };
                    auth::store(&target, o.value("username", "oauth2"), &secret)?;
                }
                _ => bail!("Auth action must be store or clear"),
            }
            println!("Credential operation completed");
        }
        "gittree" => {
            let mut scope = Scope {
                max_depth: o.number("max-depth", 0)?,
                ..Scope::default()
            };
            if let Some(excludes) = o.get("exclude") {
                scope.add_excludes(excludes);
            }
            let fetch = if o.flag("anonymous") {
                remote::fetch_anonymous
            } else {
                remote::fetch
            };
            let entries = fetch(
                o.required("provider")?,
                o.required("repo")?,
                o.required("branch")?,
                o.value("subfolder", ""),
                o.value("gitlab-base", "https://gitlab.com"),
                &scope,
            )?;
            if entries.is_empty() {
                return Ok(1);
            }
            safety::atomic_write(
                Path::new(o.required("output")?),
                formats::render(&entries, o.required("format")?)?.as_bytes(),
            )?;
        }
        "watch" => watch(o)?,
        "version" => {
            println!("ptu {}", env!("CARGO_PKG_VERSION"));
            if o.flag("check") {
                remote::check_version()?;
            }
        }
        _ => unreachable!(),
    }
    Ok(0)
}

fn scope(o: &Options, root: &Path) -> Result<Scope> {
    let mut scope = Scope::load(root, o.get("ignore-file").map(Path::new))?;
    scope.max_depth = o.number("max-depth", scope.max_depth)?;
    if let Some(mode) = o.get("show-mode") {
        scope.show_mode = mode.into();
    }
    if let Some(exclude) = o.get("exclude") {
        scope.add_excludes(exclude);
    }
    scope.validate()?;
    Ok(scope)
}

fn watch(o: &Options) -> Result<()> {
    let root = Path::new(o.required("path")?);
    let scope = scope(o, root)?;
    let expected = if o.flag("structure") {
        Some(o.layout("structure", "format", "space-unit")?)
    } else {
        None
    };
    let interval = o.number("interval-ms", 1000)?;
    ensure!(
        (100..=60_000).contains(&interval),
        "Watch interval must be 100–60000 milliseconds"
    );
    static WATCH_STATE: OnceLock<Arc<AtomicBool>> = OnceLock::new();
    let running = if let Some(state) = WATCH_STATE.get() {
        state.clone()
    } else {
        let state = Arc::new(AtomicBool::new(true));
        let signal = state.clone();
        ctrlc::set_handler(move || signal.store(false, Ordering::Relaxed))?;
        WATCH_STATE
            .set(state.clone())
            .map_err(|_| anyhow::anyhow!("Watch state already initialized"))?;
        state
    };
    running.store(true, Ordering::Relaxed);
    let mut previous = scan::scan(root, &scope)?;
    if let Some(expected) = &expected {
        scan::compare(expected, &previous, &scope).print();
    }
    println!("Watching {} (Ctrl+C to stop)", root.display());
    io::stdout().flush()?;
    while running.load(Ordering::Relaxed) {
        let mut remaining = interval;
        while remaining > 0 && running.load(Ordering::Relaxed) {
            let step = remaining.min(100);
            thread::sleep(Duration::from_millis(step as u64));
            remaining -= step;
        }
        if !running.load(Ordering::Relaxed) {
            break;
        }
        match scan::scan(root, &scope) {
            Ok(current) if current != previous => {
                if let Some(expected) = &expected {
                    scan::compare(expected, &current, &scope).print();
                } else {
                    println!("Layout changed:");
                    scan::compare(&previous, &current, &scope).print();
                }
                previous = current;
                io::stdout().flush()?;
            }
            Ok(_) => {}
            Err(error) => eprintln!("Incomplete snapshot; retrying: {error:#}"),
        }
    }
    Ok(())
}

pub fn entrypoint(args: Vec<String>) -> i32 {
    if args.is_empty()
        && io::stdin().is_terminal()
        && io::stdout().is_terminal()
        && !std::env::var("TREE_CI")
            .is_ok_and(|v| ["1", "true", "yes"].contains(&v.to_lowercase().as_str()))
    {
        return match menu() {
            Ok(()) => 0,
            Err(error) => {
                eprintln!("Error: {error:#}");
                2
            }
        };
    }
    if args.is_empty()
        && std::env::var("TREE_CI")
            .is_ok_and(|v| ["1", "true", "yes"].contains(&v.to_lowercase().as_str()))
    {
        eprintln!("A command is required in CI mode");
        return 2;
    }
    match Options::parse(&args).and_then(run) {
        Ok(code) => code,
        Err(error) => {
            eprintln!("Error: {error:#}");
            2
        }
    }
}

/// Console input on Windows includes CRLF. Shell-style tokenization recognizes
/// LF as whitespace but retains CR, so remove the line ending before parsing.
pub fn parse_interactive(line: &str) -> Result<Options> {
    let args = shell_words::split(line.trim_end_matches(['\r', '\n']))?;
    Options::parse(&args)
}

fn menu() -> Result<()> {
    println!(
        "Project Tree Utility {}\nChoose a number, enter a command with options, or type 'exit'.\nFor typed commands use forward slashes in paths and quote spaces.\n",
        env!("CARGO_PKG_VERSION")
    );
    print!("{HELP}");
    println!(
        "1 Import    2 Export    3 Scaffold    4 Verify    5 Merge    6 Watch\n7 Git tree  8 Library   9 Credentials 10 Security  11 Version  0 Exit"
    );
    loop {
        print!("ptu> ");
        io::stdout().flush()?;
        let mut line = String::new();
        if io::stdin().read_line(&mut line)? == 0 || ["exit", "quit", "0"].contains(&line.trim()) {
            break;
        }
        let options = if let Ok(choice) = line.trim().parse::<usize>() {
            guided(choice).and_then(|args| Options::parse(&args))
        } else {
            parse_interactive(&line)
        };
        match options.and_then(run) {
            Ok(code) if code != 0 => println!("Command exited with status {code}"),
            Ok(_) => {}
            Err(error) => eprintln!("Error: {error:#}"),
        }
    }
    Ok(())
}

fn prompt(label: &str, default: &str) -> Result<String> {
    print!(
        "{label}{}: ",
        if default.is_empty() {
            String::new()
        } else {
            format!(" [{default}]")
        }
    );
    io::stdout().flush()?;
    let mut input = String::new();
    ensure!(io::stdin().read_line(&mut input)? > 0, "Input closed");
    let input = input.trim();
    Ok(if input.is_empty() {
        default.into()
    } else {
        input.into()
    })
}

fn guided(choice: usize) -> Result<Vec<String>> {
    guided_with(choice, &mut prompt)
}

fn guided_with(
    choice: usize,
    prompt: &mut impl FnMut(&str, &str) -> Result<String>,
) -> Result<Vec<String>> {
    let (command, fields): (&str, Vec<(&str, &str)>) = match choice {
        1 => (
            "import",
            vec![
                ("structure", ""),
                ("format", "dash"),
                ("output", ""),
                ("output-format", "importable"),
            ],
        ),
        2 => (
            "export",
            vec![
                ("root", "."),
                ("format", "importable"),
                ("output", ""),
                ("max-depth", "5"),
            ],
        ),
        3 => (
            "scaffold",
            vec![
                ("structure", ""),
                ("format", "dash"),
                ("target", "."),
                ("project", ""),
                ("overwrite", "skip"),
            ],
        ),
        4 => (
            "verify",
            vec![("live", "."), ("structure", ""), ("format", "dash")],
        ),
        5 => (
            "merge",
            vec![
                ("file-a", ""),
                ("format-a", "dash"),
                ("file-b", ""),
                ("format-b", "dash"),
                ("strategy", "union"),
                ("output", ""),
            ],
        ),
        6 => ("watch", vec![("path", ".")]),
        7 => (
            "gittree",
            vec![
                ("provider", "github"),
                ("repo", ""),
                ("branch", "main"),
                ("format", "importable"),
                ("output", ""),
            ],
        ),
        8 => {
            let action =
                prompt("action (list/save/open/rename/delete/purge)", "list")?.to_lowercase();
            let mut args = vec!["library".into(), "--action".into(), action.clone()];
            let fields = match action.as_str() {
                "save" => vec![("file", ""), ("format", "dash"), ("name", "")],
                "open" | "delete" => vec![("name", "")],
                "rename" => vec![("name", ""), ("new-name", "")],
                "purge" => {
                    if prompt("Type PURGE to confirm", "")? == "PURGE" {
                        args.push("--yes".into());
                    }
                    vec![]
                }
                _ => vec![],
            };
            for (key, default) in fields {
                args.extend([format!("--{key}"), prompt(key, default)?]);
            }
            return Ok(args);
        }
        9 => (
            "auth",
            vec![
                ("action", "store"),
                ("target", "https://github.com"),
                ("username", "oauth2"),
            ],
        ),
        10 => {
            let action = prompt(
                "action (VALIDATE_FILE/VALIDATE_NAMES/VALIDATE_ALL/VALIDATE_PATH)",
                "VALIDATE_FILE",
            )?
            .to_uppercase();
            let fields: Vec<(&str, &str)> = match action.as_str() {
                "VALIDATE_PATH" => vec![("candidate", ""), ("base", ".")],
                "VALIDATE_ALL" => vec![("file", ""), ("format", "dash"), ("base", ".")],
                "VALIDATE_FILE" | "VALIDATE_NAMES" => vec![("file", ""), ("format", "dash")],
                _ => bail!("Unknown security action"),
            };
            let mut args = vec!["security".into(), "--action".into(), action];
            for (key, default) in fields {
                args.extend([format!("--{key}"), prompt(key, default)?]);
            }
            return Ok(args);
        }
        11 => ("version", vec![]),
        _ => bail!("Choose a menu number from 0 through 11"),
    };
    let mut args = vec![command.into()];
    for (key, default) in fields {
        let label = if command == "export" && key == "format" {
            "format (treesym/importable/txt/md/json/yaml)"
        } else {
            key
        };
        args.extend([format!("--{key}"), prompt(label, default)?]);
    }
    Ok(args)
}

#[cfg(test)]
mod menu_tests {
    use super::*;

    fn answer(label: &str, default: &str) -> Result<String> {
        Ok(if !default.is_empty() {
            default.to_owned()
        } else {
            match label {
                "project" => "demo",
                "repo" => "https://github.com/owner/repo",
                "output" => "output.txt",
                "name" | "new-name" => "starter",
                "candidate" => "child",
                _ => "layout.txt",
            }
            .to_owned()
        })
    }

    #[test]
    fn every_numbered_menu_option_builds_a_complete_valid_command() {
        for choice in 1..=11 {
            let args = guided_with(choice, &mut answer).unwrap();
            Options::parse(&args)
                .unwrap()
                .validate()
                .unwrap_or_else(|error| panic!("choice {choice}: {error}"));
        }
    }

    #[test]
    fn security_menu_asks_for_action_specific_paths() {
        for action in [
            "VALIDATE_FILE",
            "VALIDATE_NAMES",
            "VALIDATE_ALL",
            "VALIDATE_PATH",
        ] {
            let args = guided_with(10, &mut |label, default| {
                if label.starts_with("action") {
                    Ok(action.into())
                } else {
                    answer(label, default)
                }
            })
            .unwrap();
            let options = Options::parse(&args).unwrap();
            options.validate().unwrap();
            if action == "VALIDATE_PATH" {
                assert_eq!(options.get("candidate"), Some("child"));
                assert!(options.get("file").is_none());
            }
            if action == "VALIDATE_ALL" {
                assert_eq!(options.get("base"), Some("."));
            }
        }
    }

    #[test]
    fn library_menu_supports_all_actions_and_confirmation() {
        for action in ["list", "SAVE", "open", "rename", "delete", "purge"] {
            let args = guided_with(8, &mut |label, default| {
                if label.starts_with("action") {
                    Ok(action.into())
                } else if label == "Type PURGE to confirm" {
                    Ok("PURGE".into())
                } else {
                    answer(label, default)
                }
            })
            .unwrap();
            Options::parse(&args).unwrap().validate().unwrap();
        }
        let args = guided_with(8, &mut |label, default| {
            if label.starts_with("action") {
                Ok("purge".into())
            } else {
                Ok(default.into())
            }
        })
        .unwrap();
        assert!(Options::parse(&args).unwrap().validate().is_err());
    }
}
