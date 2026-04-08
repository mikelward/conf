install: install-dotfiles install-vcs

install-dotfiles:
	confinst

install-vcs:
	git submodule update --init vcs
	$(MAKE) -C vcs install

test:
	@shellcheck -s bash -S error shrc
	@dash -n shrc
	@bash -n shrc
	@shellcheck -s bash -S error shrc.vcs
	@bash -n shrc.vcs
	@dash -n profile
	@dash -n exitrc
	@fish -n config/fish/config.fish
	@if command -v nu >/dev/null 2>&1; then nu --no-config-file --commands 'source config/nushell/config.nu'; else echo "nushell not installed, skipping parse check"; fi
	@dash shrc_test.sh
	@bash shrc_test.sh
	@bash shrc_vcs_test.sh
	@bash shrc_vcs_binary_test.sh
	@bash shrc_prompt_test.sh
	@bash shrc_fish_test.sh
	@bash shrc_fish_prompt_test.sh
	@bash shrc_nushell_test.sh
	@bash makefile_test.sh
	@bash amethyst_test.sh

.PHONY: install install-dotfiles install-vcs test
