# Security model

## Trust boundaries

Structure files, remote repository metadata, command arguments, configuration,
and library snapshots are validated before use. File content is treated as bytes
to write, never evaluated as shell or Rust code. Presets are data; scaffold never
installs dependencies, executes build scripts, or deploys.

The binary runs with the current user's permissions. Use normal user accounts
and explicit destinations. It does not need administrator/root privileges for
normal project workflows.

## Enforced safeguards

- Application Rust code forbids `unsafe`; dependencies and native APIs remain
  part of the trusted implementation.
- Portable relative names, bounded input, strict schemas, duplicate rejection,
  and inferred-parent type checks guard structure parsing.
- Symbolic links and Windows reparse points in existing destination ancestors
  are refused. Scans refuse incomplete snapshots instead of claiming success.
- Full scaffold preflight and sync conflict checks precede mutation. Deletion
  requires an additional switch, preserves possible moves, and removes directories
  only when empty.
- Output replacement stages and flushes a file before commit. Library operations
  serialize under a lock and replace a single snapshot.
- Remote APIs require HTTPS, verified TLS, bounded responses/retries/pagination,
  and no redirects. Authorization headers are marked sensitive.
- Credentials use native vaults or explicitly configured Git helpers. No automatic
  plaintext credential store or literal token argument exists.

## Limits

Path checks are not handle-relative filesystem sandboxing. A different process
with write access can race checks by replacing directories, links, or files.
Do not synchronize an adversarial concurrently writable tree. The same caveat
applies to library and output directories.

Memory safety does not establish safe deletion or confidentiality. Credentials
exist in process memory and are not guaranteed to be erased from every copy.
User-configured Git helpers are trusted external programs; custom helpers can
persist or expose secrets regardless of PTU's policy. Standard `store` helpers
are rejected for storage, but arbitrary helpers cannot be proven secure here.

Replacing files may change platform permissions/ownership semantics. No promise
is made to preserve ACLs, timestamps, extended attributes, hard links, or source
bytes in layout exports. Interrupted multi-entry operations are not rolled back.
Library backups can retain deleted seed content. Host filesystem path-length and
permission restrictions still apply after portable-name validation.

## Reporting

Report a suspected issue privately to the repository maintainer using an available
private channel. Do not publish real credentials, private repository metadata,
or destructive reproduction steps against valuable data. Include version,
platform, minimal dummy input, expected boundary, and observed result. No contact
address or security-response SLA is invented by this distribution.
