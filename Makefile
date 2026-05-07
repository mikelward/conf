# Default target: build everything locally (no install). Running `make`
# with no args builds the binaries in-place so subsequent `make test`
# runs pick them up; it does not touch $HOME or $PREFIX, and it does
# not hit the network on a working checkout. Staying current with the
# vcs submodule's remote branch is the post-merge/post-rewrite hooks'
# job (wired up on first build via the vcs/Makefile rule below); run
# `make vcs-sync` for an explicit update.
all: vcs-build

install: install-dotfiles install-vcs

install-dotfiles:
	confinst

# install-vcs explicitly advances vcs to its configured remote branch
# before building+installing, so an installer always ships the latest
# even if conf hasn't been pulled recently. The default `make` path
# (vcs-build alone) skips that fetch. The recipe sequences vcs-sync
# and vcs-build via sub-make so `make -j install-vcs` doesn't run the
# submodule checkout concurrently with the build.
install-vcs:
	$(MAKE) vcs-sync
	$(MAKE) vcs-build
	$(MAKE) -C vcs install

# vcs-build builds the vcs binary from whatever's currently checked
# out. It does NOT advance vcs to its configured remote branch -- the
# bootstrap/post-merge/post-rewrite hook chain handles staying current
# as you `git pull`, and `make vcs-sync` does it explicitly. Order-only
# dep on vcs/Makefile clones+wires the submodule on a fresh conf
# checkout. The recipe goes straight to vcs/Makefile rather than via
# vcs/vcs because vcs/vcs has no source-file deps in this Makefile, so
# only vcs/Makefile's own freshness checks see the updated sources
# after a pull.
vcs-build: | vcs/Makefile
	$(MAKE) -C vcs

# bootstrap/vcs-sync make the submodule workflow repo-local instead of
# relying on a user's global gitconfig or template hooks. After this
# has run once in a checkout, plain `git pull` recurses into submodules
# and the checked-in post-merge/post-rewrite hooks also refresh vcs to
# its configured remote branch when a pull/rebase updates conf.
bootstrap: vcs-sync

vcs-sync:
	git config core.hooksPath gittemplates/hooks
	git config submodule.recurse true
	git submodule update --remote --init --recursive vcs

# Backwards-compatible target name for existing muscle memory.
vcs-fetch: vcs-sync

# vcs/vcs is a real-file target so depending on it from a test target
# only triggers a rebuild when the binary itself changed. vcs/Makefile
# uses real file targets internally, so `$(MAKE) -C vcs` is a no-op
# when sources are unchanged. The order-only dep on vcs/Makefile
# handles fresh clones where the submodule hasn't been checked out
# yet.
vcs/vcs: | vcs/Makefile
	$(MAKE) -C vcs

# Sentinel for "submodule is checked out". Absent on fresh clone of
# conf; first `make` triggers this rule, which delegates to vcs-sync
# so the same single setup path wires hooksPath, submodule.recurse,
# and the initial submodule checkout. Subsequent `make` invocations
# see vcs/Makefile already exists and don't re-fetch.
vcs/Makefile:
	$(MAKE) vcs-sync

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

$(CACHE)/test-prompt.stamp: shrc shrc_test_lib.sh shrc_prompt_test.sh | $(CACHE)
	@bash shrc_prompt_test.sh
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
$(CACHE)/test-fish.stamp: config/fish/config.fish shrc_test_lib.sh \
                          fish_test.sh fish_prompt_test.sh | $(CACHE)
	@if command -v fish >/dev/null 2>&1; then \
		fish -n config/fish/config.fish && \
		bash fish_test.sh && \
		bash fish_prompt_test.sh && \
		touch $@; \
	else \
		echo "SKIP: test-fish (fish not installed)"; \
	fi
test-fish: $(CACHE)/test-fish.stamp

# Nushell parse + behavioral tests, bundled because both invoke `nu` and
# share the same skip behavior. Stamp only touched when nu is present.
$(CACHE)/test-nu.stamp: config/nushell/config.nu config/nushell/config_test.nu | $(CACHE)
	@if command -v nu >/dev/null 2>&1; then \
		nu --no-config-file --commands 'source config/nushell/config.nu' && \
		nu --no-config-file config/nushell/config_test.nu && \
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

# Order-only dep on vcs/Makefile guarantees the submodule is checked
# out before makefile_test.sh introspects `make -n` / `make -pRrq` --
# otherwise the assertions about bare `make` not hitting the network
# would legitimately fail on a fresh checkout where vcs-build's
# order-only path through vcs/Makefile is still the active recipe.
$(CACHE)/test-makefile.stamp: Makefile makefile_test.sh shrc_test_lib.sh \
                              | $(CACHE) vcs/Makefile
	@bash makefile_test.sh
	@touch $@
test-makefile: $(CACHE)/test-makefile.stamp

$(CACHE)/test-amethyst.stamp: amethyst.yml amethyst_test.sh shrc_test_lib.sh | $(CACHE)
	@bash amethyst_test.sh
	@touch $@
test-amethyst: $(CACHE)/test-amethyst.stamp

.PHONY: all install install-dotfiles install-vcs bootstrap \
	vcs-build vcs-sync vcs-fetch \
	test test-verbose test-full test-all \
	test-dash test-bash test-zsh test-prompt test-vcs \
	test-fish test-nu test-lint \
	test-gitconfig test-makefile test-amethyst
