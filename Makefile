test:
	@dash -n shrc
	@dash -n profile
	@dash -n exitrc
	@fish -n config/fish/config.fish
	@dash shrc_test.sh
	@bash shrc_test.sh
	@bash shrc_vcs_test.sh
