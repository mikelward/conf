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
# vcs binary" target: fetch latest main, then build. The recipe
# sequences the two pieces explicitly via sub-make so `make -j
# vcs-build` doesn't run `git submodule update --remote` (from
# vcs-fetch) concurrently with `git submodule update --init` (from
# the vcs/Makefile sentinel), which would contend on the same
# .git/modules/vcs lock files.
vcs-build:
	$(MAKE) vcs-fetch
	$(MAKE) vcs/vcs

# vcs-fetch is the only target that does an explicit `--remote` update.
# It also (idempotently) wires up core.hooksPath so the post-merge /
# post-rewrite hooks fire and re-fetch on every pull / rebase. The
# hooks invoke `git submodule update --remote --init vcs` directly
# (no make round-trip); the parent's `all` target sequences vcs-fetch
# before vcs/vcs via vcs-build, and explicit `make vcs-fetch` works
# too -- but `make test` does not depend on vcs-fetch and so doesn't
# do the --remote update on every test run. (Note: vcs/Makefile's
# initial-checkout recipe also does a `git submodule update --init`,
# which fetches the pinned commit on a fresh clone -- so vcs-fetch
# isn't *literally* the only network-doing target, but it is the only
# one tracking main HEAD.)
vcs-fetch:
	git config core.hooksPath gittemplates/hooks
	git submodule update --remote --init vcs

# vcs/vcs is a real-file target so depending on it from a test target
# only triggers a rebuild when the binary itself changed. vcs/Makefile
# uses real file targets internally, so `$(MAKE) -C vcs` is a no-op
# when sources are unchanged. The order-only dep on vcs/Makefile
# handles fresh clones where the submodule hasn't been checked out
# yet.
vcs/vcs: | vcs/Makefile
	$(MAKE) -C vcs

# Sentinel for "submodule is checked out". Absent on fresh clone;
# populated by a direct `git submodule update --init` (no `--remote`)
# so this rule doesn't race with vcs-fetch's `--remote` update under
# parallel make. Once vcs-build has run, the subsequent vcs-fetch
# moves the submodule to the latest main HEAD.
vcs/Makefile:
	git submodule update --init vcs

# Number of parallel jobs to use for `make test`. Defaults to the CPU count
# (falling back to 8 if nproc isn't available). Override with e.g.
# `make test TEST_JOBS=1` to run tests sequentially.
TEST_JOBS ?= $(shell nproc 2>/dev/null || echo 8)

# .test-cache holds per-target stamp files. Each test target's recipe
# only re-runs when one of its declared source dependencies is newer
# than the stamp, so editing unrelated files (AGENTS.md, README, etc.)
# leaves the suite as a no-op. Optional-tool targets (test-zsh,
# test-fish, test-nu) only touch their stamp when the tool was
# actually present and the tests ran -- so installing the tool later
# automatically re-runs the affected target. `make test-full` wipes
# the cache to force a complete re-run.
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
# to `test`. Used by CI and when verifying after installing a new
# optional tool.
test-full:
	@rm -rf $(CACHE)
	@$(MAKE) test

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

$(CACHE):
	@mkdir -p $@

# Targets group by what's under test, not by which interpreter runs the
# driver. shrc_test.sh runs under bash and zsh (the two shells whose
# functions we actually care about). The dash target only runs
# shrc_dash_test.sh, which regression-tests that sourcing shrc under
# dash falls into the basic-mode short-circuit cleanly -- we don't try
# to make every shrc function work under dash semantics. test-prompt
# and test-vcs are bash-only because their drivers use bash/zsh-only
# syntax (here-strings, arrays).

# shrc_dash_test.sh sources `shrc` under dash and symlinks shrc.vcs into
# $HOME/.shrc.vcs to regression-test the basic-mode short-circuit, so
# both files belong in the stamp deps even though dash never sources
# shrc.vcs as a normal user.
$(CACHE)/test-dash.stamp: shrc shrc.vcs shrc_test_lib.sh shrc_dash_test.sh | $(CACHE)
	@dash shrc_dash_test.sh
	@touch $@
test-dash: $(CACHE)/test-dash.stamp

$(CACHE)/test-bash.stamp: shrc shrc_test_lib.sh shrc_test.sh shrc_bash_test.sh | $(CACHE)
	@bash shrc_test.sh
	@bash shrc_bash_test.sh
	@touch $@
test-bash: $(CACHE)/test-bash.stamp

# zsh is optional; skip gracefully when it isn't installed. Only touch
# the stamp when zsh was actually present and the tests ran, otherwise
# installing zsh later wouldn't trigger a re-run.
$(CACHE)/test-zsh.stamp: shrc shrc_test_lib.sh shrc_test.sh shrc_zsh_test.sh | $(CACHE)
	@if command -v zsh >/dev/null 2>&1; then \
		zsh shrc_test.sh && zsh shrc_zsh_test.sh && touch $@; \
	else \
		echo "SKIP: test-zsh (zsh not installed)"; \
	fi
test-zsh: $(CACHE)/test-zsh.stamp

# test-prompt depends on vcs/vcs because maybe_background_fetch shells
# out to `vcs detect` / `vcs rootdir` for VCS-aware dispatch; the test
# stubs those calls but `have_command vcs` still expects the binary
# on PATH. bash is a hard requirement (no skip branch), so the make
# dep is always reached anyway.
$(CACHE)/test-prompt.stamp: shrc shrc_test_lib.sh shrc_prompt_test.sh vcs/vcs | $(CACHE)
	@PATH="$(CURDIR)/vcs:$$PATH" bash shrc_prompt_test.sh
	@touch $@
test-prompt: $(CACHE)/test-prompt.stamp

# test-vcs depends on vcs/vcs (the real binary, not the PHONY vcs-build)
# so a binary rebuild invalidates the stamp and the tests re-run. No
# fetch is triggered by `make test`.
$(CACHE)/test-vcs.stamp: shrc.vcs shrc_test_lib.sh shrc_vcs_test.sh vcs/vcs | $(CACHE)
	@PATH="$(CURDIR)/vcs:$$PATH" bash shrc_vcs_test.sh
	@touch $@
test-vcs: $(CACHE)/test-vcs.stamp

# fish_test.sh / fish_prompt_test.sh are bash drivers that test
# config/fish/config.fish; fish itself isn't a hard requirement. The
# fish syntax check (fish -n) lives here too rather than in test-lint
# so that test-lint stays fish-free and caches normally even when fish
# isn't installed. Stamp only touched when fish is present so installing
# fish later re-runs the suite.
# vcs/vcs is built inside the if-fish branch, not declared as a make
# prereq, so environments without go/submodules still hit the SKIP
# branch cleanly when fish is absent.
$(CACHE)/test-fish.stamp: config/fish/config.fish shrc_test_lib.sh \
                          fish_test.sh fish_prompt_test.sh | $(CACHE)
	@if command -v fish >/dev/null 2>&1; then \
		$(MAKE) --no-print-directory vcs/vcs && \
		fish -n config/fish/config.fish && \
		PATH="$(CURDIR)/vcs:$$PATH" bash fish_test.sh && \
		PATH="$(CURDIR)/vcs:$$PATH" bash fish_prompt_test.sh && \
		touch $@; \
	else \
		echo "SKIP: test-fish (fish not installed)"; \
	fi
test-fish: $(CACHE)/test-fish.stamp

# Nushell parse + behavioral tests, bundled because both invoke `nu` and
# share the same skip behavior. Stamp only touched when nu is present.
# vcs/vcs is built inside the if-nu branch, not declared as a make
# prereq, so environments without go/submodules still hit the SKIP
# branch cleanly when nu is absent.
$(CACHE)/test-nu.stamp: config/nushell/config.nu config/nushell/config_test.nu | $(CACHE)
	@if command -v nu >/dev/null 2>&1; then \
		$(MAKE) --no-print-directory vcs/vcs && \
		PATH="$(CURDIR)/vcs:$$PATH" nu --no-config-file --commands 'source config/nushell/config.nu' && \
		PATH="$(CURDIR)/vcs:$$PATH" nu --no-config-file config/nushell/config_test.nu && \
		touch $@; \
	else \
		echo "SKIP: test-nu (nushell not installed)"; \
	fi
test-nu: $(CACHE)/test-nu.stamp

# Static lint/parse checks for non-fish files; bundled into one target
# since each check is sub-second. shellcheck, dash, and bash are all
# required (no skip branch), so the stamp can be touched unconditionally
# at the end and caches normally. Fish syntax check lives in test-fish.
$(CACHE)/test-lint.stamp: shrc shrc.vcs profile exitrc \
                          gittemplates/hooks/post-merge \
                          gittemplates/hooks/post-rewrite \
                          gittemplates/hooks/pre-commit | $(CACHE)
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
	@touch $@
test-lint: $(CACHE)/test-lint.stamp

$(CACHE)/test-gitconfig.stamp: gitconfig gitconfig_test.sh shrc_test_lib.sh | $(CACHE)
	@sh gitconfig_test.sh
	@touch $@
test-gitconfig: $(CACHE)/test-gitconfig.stamp

$(CACHE)/test-makefile.stamp: Makefile makefile_test.sh shrc_test_lib.sh | $(CACHE)
	@bash makefile_test.sh
	@touch $@
test-makefile: $(CACHE)/test-makefile.stamp

$(CACHE)/test-amethyst.stamp: amethyst.yml amethyst_test.sh shrc_test_lib.sh | $(CACHE)
	@bash amethyst_test.sh
	@touch $@
test-amethyst: $(CACHE)/test-amethyst.stamp

.PHONY: all install install-dotfiles install-vcs vcs-build vcs-fetch \
	test test-verbose test-full test-all \
	test-dash test-bash test-zsh test-prompt test-vcs \
	test-fish test-nu test-lint \
	test-gitconfig test-makefile test-amethyst
