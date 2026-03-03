MAKEFLAGS += --always-make

# Default target
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

dev: backend frontend ## Start full dev environment (backend + frontend)

backend: ## Start Directus + PostgreSQL (Docker)
	docker compose -f compose.yml -f compose.dev.yml up -d

frontend: ## Start SvelteKit dev server (Vite HMR)
	cd frontend && npm run dev

stop: ## Stop Docker services
	docker compose -f compose.yml -f compose.dev.yml down

build: ## Build frontend for production
	cd frontend && npm run build

lint: ## Run ESLint + Prettier check
	cd frontend && npm run lint

lint-fix: ## Run ESLint + Prettier check
	cd frontend && npm run lint:fix

check: ## Run svelte-check (type checking)
	cd frontend && npm run check

format: ## Auto-format code with Prettier
	cd frontend && npm run format

setup-schema: ## Create Directus collections, fields, and relations
	cd setup && npm run setup:schema

setup-permissions: ## Set up static token, public permissions, and calendar role
	cd setup && npm run setup:permissions

setup-all: setup-schema setup-permissions ## Run all Directus setup scripts

migrate-hugo: ## Run all Hugo migration import scripts
	cd migration-hugo && npm run import:all

clean: ## Remove build artifacts and node_modules
	rm -rf frontend/build frontend/.svelte-kit frontend/node_modules setup/node_modules migration-hugo/node_modules

install: ## Install all dependencies (frontend + setup + migration-hugo)
	cd frontend && npm install
	cd setup && npm install
	cd migration-hugo && npm install
