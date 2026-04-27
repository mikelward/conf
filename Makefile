# Default target: build everything locally (no install). Running `make`
# with no args fetches the latest vcs submodule HEAD and builds the
# binaries in-place so subsequent `make test` runs pick them up; it
# does not touch $HOME or $PREFIX.
all: vcs-build

install: install-dotfiles install-vcs

install-dotfiles:
	confinst

install-vcs: vcs-build
	$(MAKE) -C vcs install

# vcs-build is the user-facing "do whatever it takes to get a fresh
# vcs binary" target: fetch latest main, then build. Splits into the
# two finer-grained pieces below so `make test` can depend on the
# binary without triggering a network fetch on every invocation.
vcs-build: vcs-fetch vcs/vcs

# vcs-fetch is the only target that does network I/O. It also (idempo-
# tently) wires up core.hooksPath so the post-merge / post-rewrite
# hooks fire and re-fetch on every pull / rebase. Hooks call
# `make vcs-fetch`, the parent's `all` target calls it, and explicit
# `make vcs-fetch` works too -- but `make test` does not.
vcs-fetch:
	git config core.hooksPath gittemplates/hooks
	git submodule update --remote --init vcs

# vcs/vcs is a real-file target so depending on it from a test target
# only triggers a rebuild when the binary itself changed. vcs/Makefile
# uses real file targets internally, so `$(MAKE) -C vcs` is a no-op
# when sources are unchanged. The order-only dep on vcs/Makefile
# handles fresh clones where the submodule hasn't been checked out
# yet -- we delegate to vcs-fetch in that case.
vcs/vcs: | vcs/Makefile
	$(MAKE) -C vcs

# Sentinel for "submodule is checked out". Absent on fresh clone;
# vcs-fetch populates it. No prereqs because we don't want this to
# refire after the initial population.
vcs/Makefile:
	$(MAKE) vcs-fetch

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

# Same as `test`, with TEST_VERBOSE=1 exported so shrc_test_lib's
# start_test / assert_* helpers print per-section banners and per-
# assertion "ok" lines. Useful when attributing stray stderr to the
# right test block or stepping through a debug session. Delegates
# back to `test` so the parallel / output-sync / -j flags live in
# exactly one place.
test-verbose:
	@TEST_VERBOSE=1 $(MAKE) test

test-all: \
	test-dash \
	test-bash \
	test-zsh \
	test-prompt \
	test-vcs \
	test-fish \
	test-nu \
	test-lint \
	test-gitconfig \
	test-makefile \
	test-amethyst

# Targets group by what's under test, not by which interpreter runs the
# driver. shrc_test.sh is the sh-portable shrc test suite; running it
# under dash, bash, and zsh is a portability cross-check, hence three
# per-shell targets that each pair shrc_test.sh with the matching
# shell-specific driver. test-prompt and test-vcs are bash-only because
# their drivers use bash/zsh-only syntax (here-strings, arrays).

test-dash:
	@dash shrc_test.sh
	@dash shrc_dash_test.sh

test-bash:
	@bash shrc_test.sh
	@bash shrc_bash_test.sh

# zsh is optional; skip gracefully when it isn't installed (same pattern
# as fish in test-fish / nu in test-nu).
test-zsh:
	@if command -v zsh >/dev/null 2>&1; then \
		zsh shrc_test.sh && zsh shrc_zsh_test.sh; \
	else \
		echo "SKIP: test-zsh (zsh not installed)"; \
	fi

test-prompt:
	@bash shrc_prompt_test.sh

# test-vcs depends on vcs/vcs (the real binary) rather than the PHONY
# vcs-build, so editing AGENTS.md or running `make test` doesn't trigger
# a network fetch -- only an actual binary rebuild (when submodule
# sources changed) puts the binary on PATH.
test-vcs: vcs/vcs
	@PATH="$(CURDIR)/vcs:$$PATH" bash shrc_vcs_test.sh

# fish_test.sh / fish_prompt_test.sh are bash drivers that test
# config/fish/config.fish; fish itself isn't a hard requirement (the
# drivers stub or skip when fish isn't on PATH).
test-fish:
	@if command -v fish >/dev/null 2>&1; then \
		bash fish_test.sh && bash fish_prompt_test.sh; \
	else \
		echo "SKIP: test-fish (fish not installed)"; \
	fi

# Nushell parse + behavioral tests, bundled because both invoke `nu` and
# share the same skip behavior.
test-nu:
	@if command -v nu >/dev/null 2>&1; then \
		nu --no-config-file --commands 'source config/nushell/config.nu' && \
		nu --no-config-file config/nushell/config_test.nu; \
	else \
		echo "SKIP: test-nu (nushell not installed)"; \
	fi

# Static lint/parse checks bundled into one target since each is sub-
# second. shellcheck, dash, and bash are required; fish is optional
# (skips gracefully when not installed).
test-lint:
	@shellcheck -s bash -S error shrc
	@shellcheck -s bash -S error shrc.vcs
	@dash -n shrc
	@dash -n profile
	@dash -n exitrc
	@dash -n gittemplates/hooks/post-merge
	@dash -n gittemplates/hooks/post-rewrite
	@bash -n shrc
	@bash -n shrc.vcs
	@bash -n gittemplates/hooks/pre-commit
	@if command -v fish >/dev/null 2>&1; then \
		fish -n config/fish/config.fish; \
	else \
		echo "SKIP: fish -n config/fish/config.fish (fish not installed)"; \
	fi

test-gitconfig:
	@sh gitconfig_test.sh

test-makefile:
	@bash makefile_test.sh

test-amethyst:
	@bash amethyst_test.sh

.PHONY: all install install-dotfiles install-vcs vcs-build vcs-fetch \
	test test-verbose test-all \
	test-dash test-bash test-zsh test-prompt test-vcs \
	test-fish test-nu test-lint \
	test-gitconfig test-makefile test-amethyst
