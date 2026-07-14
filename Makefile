MAKEFLAGS += --always-make

# All mix commands run inside the Phoenix app directory.
APP := app
DEV_PG := bbh-dev-pg

# Default target
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

dev: db ## Start the Phoenix dev server (localhost:4000)
	cd $(APP) && mix phx.server

deps: ## Fetch Elixir dependencies
	cd $(APP) && mix deps.get

db: ## Start the dev PostgreSQL container
	docker start $(DEV_PG)

setup: deps ## First-time setup: deps + create/migrate/seed the dev DB
	cd $(APP) && mix ecto.setup

migrate: ## Run pending Ecto migrations
	cd $(APP) && mix ecto.migrate

reset-db: ## Drop, recreate, migrate and seed the dev DB
	cd $(APP) && mix ecto.reset

test: ## Run the test suite
	cd $(APP) && mix test

format: ## Auto-format code with mix format
	cd $(APP) && mix format

precommit: ## Format check + compile (warnings as errors) + tests
	cd $(APP) && mix precommit

import: ## One-time Hugo content import (mix bbh.import)
	cd $(APP) && mix bbh.import
