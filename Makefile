test:
	@shellcheck -s bash -S error shrc
	@dash -n shrc
	@bash -n shrc
	@dash -n profile
	@dash -n exitrc
	@fish -n config/fish/config.fish
	@dash shrc_test.sh
	@bash shrc_test.sh
	@bash shrc_vcs_test.sh
