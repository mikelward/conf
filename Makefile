# Default target: build everything locally (no install). Running `make`
# with no args builds the vcs submodule binaries in-place so subsequent
# `make test` runs pick them up; it does not touch $HOME or $PREFIX.
all: vcs-build

install: install-dotfiles install-vcs

install-dotfiles:
	confinst

install-vcs: vcs-build
	$(MAKE) -C vcs install

# Build the vcs submodule binaries in-place (no install). Tests that
# depend on the `vcs` binary prepend $(CURDIR)/vcs to PATH so they use
# these instead of requiring a prior `make install`. vcs/Makefile uses
# real file targets, so this is a no-op when sources are unchanged.
vcs-build:
	git submodule update --init vcs
	$(MAKE) -C vcs

# Number of parallel jobs to use for `make test`. Defaults to the CPU count
# (falling back to 8 if nproc isn't available). Override with e.g.
# `make test TEST_JOBS=1` to run tests sequentially.
TEST_JOBS ?= $(shell nproc 2>/dev/null || echo 8)

# `make test` runs every test target in parallel via a recursive make. Each
# test is its own target so GNU make can schedule them concurrently; they are
# independent (each test script creates its own temp dir via mktemp).
# --output-sync=target keeps each target's output grouped instead of
# interleaved (requires GNU make >= 4.0; older versions will warn and ignore).
test:
	@$(MAKE) --no-print-directory --output-sync=target -j $(TEST_JOBS) test-all

test-all: \
	test-lint \
	test-nu-parse \
	test-nu-config \
	test-shrc-dash \
	test-shrc-bash \
	test-shrc-zsh \
	test-shrc-vcs \
	test-shrc-prompt \
	test-shrc-fish \
	test-shrc-fish-prompt \
	test-gitconfig \
	test-makefile \
	test-amethyst

# Static lint/parse checks are sub-second each, so we bundle them into one
# target rather than spawning a make job per syntax check. shellcheck,
# dash, and bash are required; fish is optional (skips gracefully when
# not installed, matching the test-nu-parse pattern) since not every
# box has fish.
test-lint:
	@shellcheck -s bash -S error shrc
	@shellcheck -s bash -S error shrc.vcs
	@dash -n shrc
	@dash -n profile
	@dash -n exitrc
	@bash -n shrc
	@bash -n shrc.vcs
	@if command -v fish >/dev/null 2>&1; then \
		fish -n config/fish/config.fish; \
	else \
		echo "SKIP: fish -n config/fish/config.fish (fish not installed)"; \
	fi

test-nu-parse:
	@if command -v nu >/dev/null 2>&1; then \
		nu --no-config-file --commands 'source config/nushell/config.nu'; \
	else \
		echo "SKIP: test-nu-parse (nushell not installed)"; \
	fi

test-nu-config:
	@if command -v nu >/dev/null 2>&1; then \
		nu --no-config-file config/nushell/config_test.nu; \
	else \
		echo "SKIP: test-nu-config (nushell not installed)"; \
	fi

# shrc_test.sh holds sh-portable tests and is run under both dash and
# bash as a portability cross-check. Shell-specific end-to-end tests
# (which spawn an interactive subshell of that shell and source shrc)
# live in per-shell files so e.g. `dash shrc_test.sh` does not need to
# spawn `bash -i` at all -- that cross-shell invocation was the source
# of the SIGTTOU-under-tty hang the outer timeout only partially fenced.
test-shrc-dash:
	@dash shrc_test.sh
	@dash shrc_dash_test.sh

test-shrc-bash:
	@bash shrc_test.sh
	@bash shrc_bash_test.sh

# zsh is optional; skip gracefully when it isn't installed (same pattern
# as fish in test-lint / nu in test-nu-parse). Runs the sh-portable
# shrc_test.sh driver under zsh too -- shrc is sourced by zsh users in
# the wild, so zsh-runtime coverage of the extracted shrc helpers
# (word splitting, `local` scoping, empty-string semantics) shakes out
# portability issues that neither dash nor bash would catch.
test-shrc-zsh:
	@if command -v zsh >/dev/null 2>&1; then \
		zsh shrc_test.sh && zsh shrc_zsh_test.sh; \
	else \
		echo "SKIP: test-shrc-zsh (zsh not installed)"; \
	fi

test-shrc-vcs: vcs-build
	@PATH="$(CURDIR)/vcs:$$PATH" bash shrc_vcs_test.sh

test-shrc-prompt:
	@bash shrc_prompt_test.sh

test-shrc-fish:
	@bash shrc_fish_test.sh

test-shrc-fish-prompt:
	@bash shrc_fish_prompt_test.sh

test-gitconfig:
	@sh gitconfig_test.sh

test-makefile:
	@bash makefile_test.sh

test-amethyst:
	@bash amethyst_test.sh

.PHONY: all install install-dotfiles install-vcs vcs-build \
	test test-all test-lint \
	test-nu-parse test-nu-config \
	test-shrc-dash test-shrc-bash test-shrc-zsh \
	test-shrc-vcs \
	test-shrc-prompt test-shrc-fish test-shrc-fish-prompt \
	test-gitconfig test-makefile test-amethyst
