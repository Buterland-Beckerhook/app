# AGENTS.md

## Project Overview

Monorepo for **buterland-beckerhook.de** -- a German shooting club (Schützenverein) website.
Stack: SvelteKit 5 (SSR, Node adapter) + Directus CMS (PostgreSQL) + TailwindCSS 4 + TypeScript.
Deployed via Docker Compose with Caddy reverse proxy.

## Repository Structure

```
frontend/           # SvelteKit app (main application)
  src/lib/          # Components, server utilities, shared utils
  src/lib/server/   # Server-only code (Directus client, queries)
  src/lib/components/  # Svelte components (PascalCase)
  src/lib/utils/    # Shared utility functions
  src/lib/types.ts  # All Directus schema types + SDK Schema interface
  src/routes/       # SvelteKit pages and API routes
  static/           # Favicon, fonts, manifest, PWA icons
setup/              # TypeScript setup scripts (schema, permissions, branding), run via tsx
migration/          # TypeScript migration scripts (Hugo -> Directus), run via tsx
docker/             # Caddy config, Directus extensions
```

## Build / Dev / Lint Commands

All frontend commands run from the `frontend/` directory.

```bash
npm install                # Install dependencies
npm run dev                # Vite dev server on localhost:5173
npm run build              # Production build
npm run preview            # Preview production build

# Type checking
npm run check              # svelte-kit sync + svelte-check (strict mode)

# Linting & formatting
npm run lint               # ESLint + Prettier check
npm run lint:fix           # Auto-fix lint + format
npm run format             # Prettier --write only
npx eslint src/routes/aktuell/+page.server.ts   # Lint a single file
npx prettier --write src/lib/components/Foo.svelte  # Format a single file

# Docker (from repo root)
docker compose up --build       # Full dev stack (compose.yml): db + phoenix + caddy
```

> **Note:** the site is being rewritten to Elixir/Phoenix (the app now lives in
> `app/`); the SvelteKit/Directus notes above are historical. Dev runs fully
> containerized. Use the repo-root `Makefile`:
>
> - `make dev` — start the dev stack (Postgres + Phoenix + Caddy) at `https://localhost`
> - `make down` / `make logs` — stop / tail the stack
> - `make dump` — snapshot the dev DB + uploads into `./seed` (DB dump + tarball)
> - `make seed` — restore a `./seed` snapshot into the dev DB + uploads
> - `make test`, `make format`, `make precommit`, `make migrate`, `make reset-db` —
>   run the corresponding `mix` task inside the running phoenix container
>
> First run trusts Caddy's local CA for a clean HTTPS lock: extract
> `/data/caddy/pki/authorities/local/root.crt` from the `caddy_data` volume and
> add it to your system trust store.

### Tests

No test framework is currently configured. There are no Vitest/Playwright configs or test files yet. When tests are added, they should use Vitest for unit tests (colocated `.test.ts` files) and Playwright for e2e tests.

## Code Style Guidelines

### Formatting (Prettier)

- **Tabs** for indentation (not spaces)
- **Single quotes**
- **No trailing commas**
- **100 character** print width
- Svelte files parsed with `prettier-plugin-svelte`

### ESLint

- Flat config with `typescript-eslint` + `eslint-plugin-svelte` + `eslint-config-prettier`
- `svelte/no-at-html-tags`: **off** (CMS content uses `{@html}`)
- `svelte/no-navigation-without-resolve`: **off**
- Ignores: `build/`, `.svelte-kit/`, `dist/`, `node_modules/`

### TypeScript

- **Strict mode** everywhere. No `any` unless unavoidable (add a comment explaining why).
- `moduleResolution: "bundler"`, `esModuleInterop: true`
- Always type function parameters and return values. Let TypeScript infer locals.
- Use `interface` for object shapes, `type` for unions and computed types.
- Prefer `unknown` over `any`. Validate and narrow before use.

### File Naming

- Svelte components: **PascalCase** -- `ArticleCard.svelte`, `ThroneTable.svelte`
- TypeScript files: **kebab-case** -- `directus.ts`, `push-utils.ts`
- SvelteKit routes: conventions -- `+page.svelte`, `+page.server.ts`, `+layout.svelte`, `+server.ts`

### Naming Conventions

- Variables/functions: **camelCase** -- `getArticles`, `datePublished`
- Types/interfaces: **PascalCase** -- `Article`, `ThroneData`
- Constants/env vars: **UPPER_SNAKE_CASE** -- `DIRECTUS_URL`, `ITEMS_PER_PAGE`
- URL slugs/route params: **kebab-case** -- `/aktuell/mein-artikel`
- German URL params: `?seite=` (page), `?jahr=` (year)

### Imports

- Use `$lib/` alias for imports from `src/lib/`.
- Server-only code in `$lib/server/` -- only import from `+page.server.ts`, `+layout.server.ts`, or `+server.ts`.
- Group imports: (1) svelte/sveltekit, (2) third-party, (3) `$lib/` local.
- Named exports, not default exports (Svelte components are default by nature).

```typescript
import { error, redirect } from '@sveltejs/kit';
import { readItems } from '@directus/sdk';
import { directus } from '$lib/server/directus';
import type { Article } from '$lib/types';
```

### Svelte Components

- **Svelte 5 runes** syntax: `$state`, `$derived`, `$effect`, `$props`.
- Props via `$props()`, **not** `export let`.
- Reactive declarations with `$derived`, **not** `$:`.
- Snippets via `{#snippet}` / `{@render}`, **not** slots.
- Semantic HTML elements. ARIA labels where needed.
- TailwindCSS 4 utility classes only. No custom CSS files unless necessary.

```svelte
<script lang="ts">
  import type { Article } from '$lib/types';
  let { article, showImage = true }: { article: Article; showImage?: boolean } = $props();
  let formattedDate = $derived(new Date(article.date_published).toLocaleDateString('de-DE'));
</script>
```

### Error Handling

- In `+page.server.ts` / `+server.ts`: use SvelteKit `error()` and `redirect()` helpers.
- Wrap Directus SDK calls in try/catch. `error(404)` for missing content, `error(500)` for unexpected failures.
- Never expose internal error details to the client. Log server-side with `console.error`.

```typescript
import { error } from '@sveltejs/kit';
import type { HttpError } from '@sveltejs/kit';

export const load = async ({ params }) => {
  try {
    const article = await getArticleBySlug(params.slug);
    if (!article) throw error(404, 'Artikel nicht gefunden');
    return { article };
  } catch (err) {
    if ((err as HttpError).status) throw err;
    console.error('Failed to load article:', err);
    throw error(500, 'Interner Fehler');
  }
};
```

### Directus Integration

- Client in `$lib/server/directus.ts` (server-only). Uses `@directus/sdk` v21 with typed schema.
- Auth via static token (`DIRECTUS_TOKEN` env var from `$env/dynamic/private`).
- Always filter by `status: 'published'` for public-facing queries.
- Fetch only needed fields (use `fields` parameter), never `*`.
- Image URLs built via `$lib/utils/image.ts` using `PUBLIC_DIRECTUS_URL`.

### Environment Variables

- Secrets in `.env`, **never committed**. See `.env.example` for reference.
- SvelteKit public env: prefix `PUBLIC_` -- `PUBLIC_SITE_URL`, `PUBLIC_DIRECTUS_URL`.
- Private env: no prefix -- `DIRECTUS_URL`, `DIRECTUS_TOKEN`, `VAPID_PRIVATE_KEY`.

### Internationalization

- **German-language** site. UI strings are hardcoded German.
- Date formatting: `de-DE` locale -- `toLocaleDateString('de-DE')`.

### Accessibility & SEO

- Semantic HTML (`<article>`, `<nav>`, `<main>`, `<section>`, `<time>`).
- Every page sets `<title>` and `<meta name="description">` via `<svelte:head>`.
- Images require `alt` text (use Directus `title` field).

### Git & Workflow

- Branches: `main` (production), `develop` (integration). Feature branches off `develop`.
- Commit messages: conventional style -- `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`.
