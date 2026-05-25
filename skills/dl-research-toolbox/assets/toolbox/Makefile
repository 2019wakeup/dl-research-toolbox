SHELL := /usr/bin/env bash

.PHONY: setup doctor web bootstrap bootstrap-dry-run network-first check proxy-deep-check mihomo-install mihomo-import mihomo-start mihomo-stop mihomo-status mihomo-check mihomo-autostart mihomo-autostart-status

setup:
	bash install.sh

doctor:
	bash scripts/doctor.sh

web:
	bash scripts/web-ui.sh

bootstrap:
	bash scripts/bootstrap.sh

bootstrap-dry-run:
	bash scripts/bootstrap.sh --dry-run

network-first:
	bash scripts/network-first-setup.sh

check:
	bash scripts/check-machine.sh

proxy-deep-check:
	bash scripts/verify-proxy-deep.sh

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

mihomo-autostart:
	bash scripts/mihomo-autostart.sh install

mihomo-autostart-status:
	bash scripts/mihomo-autostart.sh status
