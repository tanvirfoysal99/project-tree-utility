fn main() {
    let args: Result<Vec<_>, _> = std::env::args_os()
        .skip(1)
        .map(|arg| arg.into_string())
        .collect();
    let code = match args {
        Ok(args) => project_tree_utility::cli::entrypoint(args),
        Err(_) => {
            eprintln!("Error: arguments and paths must be valid UTF-8");
            2
        }
    };
    std::process::exit(code);
}
