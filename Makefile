SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

RECORDS ?= 20000

.PHONY: help
help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: tools
tools: ## Install pinned CLI tools (kind, kubectl, kubeconform) with checksum verification
	bash tools/install-tools.sh

.PHONY: phoenix
phoenix: ## Run the full drill: build, seed, back up, destroy, rebuild, verify
	RECORDS=$(RECORDS) bash scripts/phoenix.sh

.PHONY: up
up: ## Bring up vault, cluster and the full stack (no drill)
	bash scripts/vault.sh up
	bash scripts/cluster.sh up
	bash scripts/deploy.sh data
	bash scripts/deploy.sh app "$$(bash scripts/build.sh)"
	bash scripts/deploy.sh backups-on

.PHONY: seed
seed: ## Write RECORDS deterministic records
	bash scripts/seed.sh $(RECORDS)

.PHONY: backup
backup: ## Take an on-demand backup
	bash scripts/backup.sh

.PHONY: restore
restore: ## Restore the newest backup into the current cluster
	bash scripts/restore.sh

.PHONY: backups
backups: ## List backups in the vault
	bash scripts/vault.sh list

.PHONY: summary
summary: ## Show record count and checksum of live data
	bash scripts/summary.sh

.PHONY: destroy
destroy: ## Delete the cluster (the vault and its backups survive)
	bash scripts/cluster.sh down

.PHONY: down
down: ## Delete everything, including the vault and all backups
	bash scripts/cluster.sh down
	bash scripts/vault.sh down --purge
	rm -rf .phoenix

.PHONY: lint
lint: ## Run every static check that CI runs
	shellcheck tools/*.sh scripts/*.sh
	yamllint --strict .
	cd app && ruff check . && ruff format --check .
	source tools/versions.env && for d in deploy/data deploy/app; do \
	  kubectl kustomize $$d | kubeconform -strict -summary -kubernetes-version "$${KUBECTL_VERSION#v}" -; done
	docker run --rm -i hadolint/hadolint:v2.12.0 < app/Dockerfile

.PHONY: test
test: ## Run unit tests (set TEST_DATABASE_URL for integration tests)
	cd app && python -m pytest -q
