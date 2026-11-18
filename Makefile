.PHONY: test lint check
SCRIPTS := hetzner-download-image.sh get.hetzner-download-image.sh

lint:
	shellcheck -s sh -e SC3043 $(SCRIPTS) test/bin/curl

test:
	bats test

check: lint test
