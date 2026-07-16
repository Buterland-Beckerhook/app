MAKEFLAGS += --always-make

# Development runs fully containerized (see compose.yml): Postgres + Phoenix
# (source mounted, code reload) + Caddy (local HTTPS at https://localhost).
# The mix wrappers below exec into the running phoenix container, so bring the
# stack up with `make dev` first.
COMPOSE := docker compose
MIX := $(COMPOSE) exec phoenix mix

# Default target
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

dev: ## Start the full dev stack (db + phoenix + caddy) at https://localhost
	$(COMPOSE) up --build

down: ## Stop the dev stack (data persists in volumes)
	$(COMPOSE) down

logs: ## Tail logs from the running dev stack
	$(COMPOSE) logs -f

dump: ## Snapshot dev DB + uploads into ./seed (stack must be running)
	./scripts/dump.sh

seed: ## Restore ./seed snapshot into the dev DB + uploads (stack must be running)
	./scripts/seed.sh

deps: ## Fetch Elixir dependencies (in the phoenix container)
	$(MIX) deps.get

migrate: ## Run pending Ecto migrations (in the phoenix container)
	$(MIX) ecto.migrate

reset-db: ## Drop, recreate and migrate the dev DB (in the phoenix container)
	$(MIX) ecto.reset

test: ## Run the test suite (in the phoenix container)
	$(MIX) test

format: ## Auto-format code with mix format (in the phoenix container)
	$(MIX) format

precommit: ## Format check + compile (warnings as errors) + tests (in the phoenix container)
	$(MIX) precommit

import: ## One-time Hugo content import (mix bbh.import) (in the phoenix container)
	$(MIX) bbh.import
