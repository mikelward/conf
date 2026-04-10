# Project Instructions

## Style

- Preserve existing code style unless there are correctness issues.
- Use `if test` rather than `if [`.
- In `shrc` and `shrc.*`, use existing helper functions such as `error`, `warn`, `have_command`, `is_function`, `gets`, and `puts`.
- When parsing options, support long flags in both `--option argument` and `--option=argument` formats.

## Testing

- Always add or update tests when writing or modifying code.
- If a test file already exists for the module being changed, add tests there. Otherwise, create a new test file following the project's existing test conventions.
- Do not consider a task complete until tests are included.
- Run `make test` after making any changes.
- When modifying VCS functions or prompt functions, run performance tests, include timing info, and warn of any regressions.
- When touching `shrc.vcs*` files, install `jj` and `hg` locally before running tests so that all VCS test suites execute rather than being skipped.
- When touching `config/nushell/*` files, install `nu` locally before running tests so that both the bash-harness nushell tests and the nu-native tests (`config/nushell/config_test.nu`) execute rather than being skipped.
