SHELL := /usr/bin/env bash

.PHONY: bootstrap bootstrap-dry-run check mihomo-install mihomo-import mihomo-start mihomo-stop mihomo-status mihomo-check

bootstrap:
	bash scripts/bootstrap.sh

bootstrap-dry-run:
	bash scripts/bootstrap.sh --dry-run

check:
	bash scripts/check-machine.sh

mihomo-install:
	bash scripts/mihomo-install.sh

mihomo-import:
	bash scripts/mihomo-import-subscription.sh

mihomo-start:
	bash scripts/mihomo-start.sh

mihomo-stop:
	bash scripts/mihomo-stop.sh

mihomo-status:
	bash scripts/mihomo-status.sh

mihomo-check:
	bash scripts/mihomo-status.sh --strict --test-proxy
