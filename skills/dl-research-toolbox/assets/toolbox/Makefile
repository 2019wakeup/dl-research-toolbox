SHELL := /usr/bin/env bash

.PHONY: setup doctor web web-tunnel bootstrap bootstrap-dry-run network-first check codex-sandbox-check proxy-deep-check mihomo-install mihomo-import mihomo-start mihomo-stop mihomo-status mihomo-check mihomo-select-best mihomo-autostart mihomo-autostart-status

setup:
	bash install.sh

doctor:
	bash scripts/doctor.sh

web:
	bash scripts/web-ui.sh

web-tunnel:
	bash scripts/web-tunnel.sh

bootstrap:
	bash scripts/bootstrap.sh

bootstrap-dry-run:
	bash scripts/bootstrap.sh --dry-run

network-first:
	bash scripts/network-first-setup.sh

check:
	bash scripts/check-machine.sh

codex-sandbox-check:
	bash scripts/check-codex-sandbox.sh

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

mihomo-select-best:
	bash scripts/mihomo-select-best.sh

mihomo-autostart:
	bash scripts/mihomo-autostart.sh install

mihomo-autostart-status:
	bash scripts/mihomo-autostart.sh status
