# Project Instructions

## Style

- Preserve existing code style unless there are correctness issues.
- Use `if test` rather than `if [`.
- In `shrc` and `shrc.*`, use existing helper functions such as `error`, `warn`, `have_command`, `is_function`, `gets`, and `puts`.
- When parsing options, support long flags in both `--option argument` and `--option=argument` formats.
- Preserve feature parity between `shrc` (bash/zsh), `config/fish/config.fish`, and `config/nushell/config.nu`. When adding or changing functionality in one shell config, apply the equivalent change to the others (bash, zsh, fish, and nushell).

## Testing

- Always add or update tests when writing or modifying code.
- If a test file already exists for the module being changed, add tests there. Otherwise, create a new test file following the project's existing test conventions.
- Do not consider a task complete until tests are included.
- Run `make test` after making any changes.
- When modifying VCS functions or prompt functions, run performance tests, include timing info, and warn of any regressions.
- Per-VCS subcommand behaviour (git/hg/jj) lives in the `vcs` Go binary, cloned on demand into `./vcs/` from https://github.com/mikelward/vcs; add tests there for changes to subcommand semantics. `make test` clones and builds the binary automatically.
- When touching `config/nushell/*` files, install `nu` locally before running tests so that the nu-native tests (`config/nushell/config_test.nu`) execute rather than being skipped.
- Do not use `apt-get` or `apt` to install tools. Use direct binary downloads (e.g. from GitHub releases) or `cargo install` instead.
