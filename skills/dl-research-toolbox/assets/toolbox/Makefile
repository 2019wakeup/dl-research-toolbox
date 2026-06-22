SHELL := /usr/bin/env bash

.PHONY: help setup proxy-only doctor status repair repair-status repair-codex codex-ready codex-login-check web web-tunnel bootstrap bootstrap-dry-run network-first check codex-sandbox-check proxy-deep-check install-skills skills-list mihomo-install mihomo-import mihomo-start mihomo-stop mihomo-status mihomo-check mihomo-select-best mihomo-autostart mihomo-autostart-status

help:
	./toolbox help

setup:
	./toolbox setup

proxy-only:
	./toolbox proxy-only

doctor:
	./toolbox doctor

status:
	./toolbox status

repair:
	./toolbox repair

repair-status:
	./toolbox repair status

repair-codex:
	./toolbox repair codex

codex-ready:
	./toolbox codex-ready

codex-login-check:
	./toolbox codex-login check

web:
	./toolbox web

web-tunnel:
	./toolbox web-tunnel

bootstrap:
	./toolbox bootstrap

bootstrap-dry-run:
	./toolbox bootstrap --dry-run

network-first:
	./toolbox proxy-only

check:
	./toolbox check

codex-sandbox-check:
	bash scripts/check-codex-sandbox.sh

proxy-deep-check:
	./toolbox deep-check

install-skills:
	./toolbox skills

skills-list:
	./toolbox skills --list

mihomo-install:
	./toolbox mihomo install

mihomo-import:
	./toolbox mihomo import

mihomo-start:
	./toolbox mihomo start

mihomo-stop:
	./toolbox mihomo stop

mihomo-status:
	./toolbox mihomo status

mihomo-check:
	./toolbox mihomo check

mihomo-select-best:
	./toolbox mihomo best

mihomo-autostart:
	./toolbox autostart

mihomo-autostart-status:
	./toolbox autostart status
