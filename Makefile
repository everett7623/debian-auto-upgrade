SHELL := /usr/bin/env bash

.PHONY: check syntax shellcheck test

check: syntax shellcheck test

syntax:
	@bash -n debian_upgrade.sh
	@for file in scripts/*.sh tests/*.sh; do bash -n "$$file"; done

shellcheck:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -x debian_upgrade.sh scripts/*.sh tests/*.sh; \
	else \
		echo "shellcheck not installed; skipping static analysis"; \
	fi

test:
	@bash tests/smoke.sh
