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
	git config core.hooksPath gittemplates/hooks
	git submodule update --remote --init vcs
	$(MAKE) -C vcs

# Number of parallel jobs to use for `make test`. Defaults to the CPU count
# (falling back to 8 if nproc isn't available). Override with e.g.
# `make test TEST_JOBS=1` to run tests sequentially.
TEST_JOBS ?= $(shell nproc 2>/dev/null || echo 8)

# .test-cache holds per-target stamp files. Each test target's recipe
# only re-runs when one of its declared source dependencies is newer
# than the stamp; touching unrelated files (AGENTS.md, README, etc.)
# leaves stamps up-to-date so the suite is a no-op. `make test-full`
# wipes the cache to force a complete re-run.
CACHE := .test-cache

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

# Force every test to re-run by wiping the stamp cache, then dispatch
# to `test`. CI and Claude should use this; local dev gets the
# incremental `test`.
test-full:
	@rm -rf $(CACHE)
	@$(MAKE) test

test-all: \
	test-shrc \
	test-fish \
	test-nu \
	test-lint \
	test-gitconfig \
	test-makefile \
	test-amethyst

$(CACHE):
	@mkdir -p $@

# test-shrc: shrc behavior across dash/bash/zsh, plus shrc.vcs (which
# shrc itself sources when the running shell is bash/zsh per shrc:1133)
# and the prompt function. Depends on vcs-build because shrc_vcs_test.sh
# exercises the real `vcs` binary; order-only (|) so vcs-build's PHONY
# always-runs status doesn't invalidate the stamp every invocation.
$(CACHE)/test-shrc.stamp: shrc shrc.vcs shrc_test_lib.sh \
                          shrc_test.sh shrc_dash_test.sh \
                          shrc_bash_test.sh shrc_zsh_test.sh \
                          shrc_prompt_test.sh shrc_vcs_test.sh \
                          | vcs-build $(CACHE)
	@dash shrc_test.sh
	@dash shrc_dash_test.sh
	@bash shrc_test.sh
	@bash shrc_bash_test.sh
	@if command -v zsh >/dev/null 2>&1; then \
		zsh shrc_test.sh && zsh shrc_zsh_test.sh; \
	else \
		echo "SKIP: shrc_test.sh under zsh (zsh not installed)"; \
	fi
	@bash shrc_prompt_test.sh
	@PATH="$(CURDIR)/vcs:$$PATH" bash shrc_vcs_test.sh
	@touch $@

# test-fish: fish config + fish prompt. Stubs `vcs` as a fish function,
# so doesn't need vcs-build.
$(CACHE)/test-fish.stamp: config/fish/config.fish shrc_test_lib.sh \
                          shrc_fish_test.sh shrc_fish_prompt_test.sh \
                          | $(CACHE)
	@bash shrc_fish_test.sh
	@bash shrc_fish_prompt_test.sh
	@touch $@

# test-nu: nushell parse + behavioral tests. Stubs `vcs` with shell
# scripts in temp dirs, so doesn't need vcs-build. Skips gracefully
# when `nu` isn't installed.
$(CACHE)/test-nu.stamp: config/nushell/config.nu config/nushell/config_test.nu \
                        | $(CACHE)
	@if command -v nu >/dev/null 2>&1; then \
		nu --no-config-file --commands 'source config/nushell/config.nu' && \
		nu --no-config-file config/nushell/config_test.nu; \
	else \
		echo "SKIP: test-nu (nushell not installed)"; \
	fi
	@touch $@

# test-lint: static syntax/lint checks bundled into one target since
# each is sub-second. shellcheck, dash, and bash are required; fish is
# optional (skips gracefully when not installed).
$(CACHE)/test-lint.stamp: shrc shrc.vcs profile exitrc \
                          gittemplates/hooks/post-merge \
                          gittemplates/hooks/post-rewrite \
                          gittemplates/hooks/pre-commit \
                          config/fish/config.fish \
                          | $(CACHE)
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
	@touch $@

$(CACHE)/test-gitconfig.stamp: gitconfig gitconfig_test.sh shrc_test_lib.sh \
                               | $(CACHE)
	@sh gitconfig_test.sh
	@touch $@

$(CACHE)/test-makefile.stamp: Makefile makefile_test.sh shrc_test_lib.sh \
                              | $(CACHE)
	@bash makefile_test.sh
	@touch $@

$(CACHE)/test-amethyst.stamp: amethyst.yml amethyst_test.sh shrc_test_lib.sh \
                              | $(CACHE)
	@bash amethyst_test.sh
	@touch $@

# Friendly aliases that route through the stamps. Listed as .PHONY so
# `make test-shrc` always re-evaluates the stamp's source dependencies;
# the stamp itself is the real-file target whose timestamp gates work.
test-shrc: $(CACHE)/test-shrc.stamp
test-fish: $(CACHE)/test-fish.stamp
test-nu: $(CACHE)/test-nu.stamp
test-lint: $(CACHE)/test-lint.stamp
test-gitconfig: $(CACHE)/test-gitconfig.stamp
test-makefile: $(CACHE)/test-makefile.stamp
test-amethyst: $(CACHE)/test-amethyst.stamp

.PHONY: all install install-dotfiles install-vcs vcs-build \
	test test-verbose test-full test-all \
	test-shrc test-fish test-nu test-lint \
	test-gitconfig test-makefile test-amethyst
