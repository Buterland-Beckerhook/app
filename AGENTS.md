# AGENTS.md

## Project Overview

Monorepo for **buterland-beckerhook.de** -- a German shooting club (Schuetzenverein) website.
Stack: SvelteKit (SSR, Node adapter) + Directus CMS (PostgreSQL) + TailwindCSS 4 + TypeScript.
Deployed via Docker Compose with Caddy reverse proxy.

## Repository Structure

```
frontend/          # SvelteKit app (main application)
  src/lib/         # Components, server utilities, shared utils
  src/routes/      # SvelteKit pages and API routes
  static/          # Favicon, manifest, PWA icons
migration/         # TypeScript content migration scripts (Hugo -> Directus)
docker/            # Caddy config, Directus extensions
```

## Build / Dev / Lint / Test Commands

All frontend commands run from the `frontend/` directory.

```bash
# Install dependencies
cd frontend && npm install

# Development (runs Vite dev server on localhost:5173)
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview

# Type checking
npx svelte-check --tsconfig ./tsconfig.json

# Linting
npm run lint            # ESLint + Prettier check
npm run lint:fix        # Auto-fix lint issues
npx eslint src/         # Lint only src directory
npx eslint src/routes/aktuell/+page.server.ts   # Lint a single file

# Formatting
npx prettier --check .
npx prettier --write .
npx prettier --write src/lib/components/Navbar.svelte  # Format single file

# Tests (Vitest for unit, Playwright for e2e)
npm run test            # Run all unit tests
npm run test:unit       # Unit tests only (Vitest)
npx vitest run src/lib/utils/date.test.ts         # Single unit test file
npx vitest run --testNamePattern="formats date"   # Single test by name
npm run test:e2e        # End-to-end tests (Playwright)
npx playwright test tests/homepage.spec.ts        # Single e2e test

# Docker (from repo root)
docker compose -f docker-compose.dev.yml up       # Dev environment (Directus + PostgreSQL)
docker compose up --build                         # Full production stack

# Migration scripts (from migration/)
cd migration && npm install
npx tsx src/import-locations.ts
npx tsx src/import-articles.ts
```

## Code Style Guidelines

### Language & Framework

- **TypeScript** in strict mode everywhere. No `any` unless absolutely unavoidable (and then add a comment explaining why).
- **SvelteKit** with SSR via `@sveltejs/adapter-node`. Use `+page.server.ts` for data loading (server-side), `+server.ts` for API endpoints.
- **TailwindCSS 4** for styling. No custom CSS files unless absolutely necessary.

### File Naming

- Svelte components: **PascalCase** -- `ArticleCard.svelte`, `ThroneGallery.svelte`
- TypeScript files: **kebab-case** -- `directus.ts`, `push-utils.ts`, `date-format.ts`
- SvelteKit routes: follow SvelteKit conventions -- `+page.svelte`, `+page.server.ts`, `+layout.svelte`, `+server.ts`
- Test files: colocated with source, suffix `.test.ts` -- `date-format.test.ts`

### Imports

- Use `$lib/` alias for imports from `src/lib/` (SvelteKit convention).
- Server-only code goes in `$lib/server/` and must only be imported from `+page.server.ts`, `+layout.server.ts`, or `+server.ts`.
- Group imports in order: (1) svelte/sveltekit, (2) third-party, (3) `$lib/` local.
- Use named exports, not default exports (except for Svelte components which are default by nature).

```typescript
// Good
import { error, redirect } from '@sveltejs/kit';
import { readItems } from '@directus/sdk';
import { directus } from '$lib/server/directus';
import type { Article } from '$lib/types';
```

### Types

- Define shared types in `$lib/types/` or `$lib/types.ts`.
- Directus schema types should mirror the CMS collections exactly.
- Use `interface` for object shapes, `type` for unions and computed types.
- Always type function parameters and return values. Let TypeScript infer locals.
- Prefer `unknown` over `any` for truly unknown data. Validate and narrow before use.

### Svelte Components

- Use Svelte 5 runes syntax (`$state`, `$derived`, `$effect`, `$props`).
- Props via `$props()`, not `export let`.
- Keep components focused and small. Extract reusable logic into `$lib/utils/`.
- Use semantic HTML elements. Add ARIA labels where needed (a11y).
- Reactive declarations with `$derived` instead of `$:`.

```svelte
<script lang="ts">
  import type { Article } from '$lib/types';

  let { article, showImage = true }: { article: Article; showImage?: boolean } = $props();
  let formattedDate = $derived(new Date(article.date_published).toLocaleDateString('de-DE'));
</script>
```

### Naming Conventions

- Variables and functions: **camelCase** -- `getArticles`, `datePublished`
- Types and interfaces: **PascalCase** -- `Article`, `ThroneData`, `PushSubscription`
- Constants: **UPPER_SNAKE_CASE** for env vars and true constants -- `DIRECTUS_URL`, `ITEMS_PER_PAGE`
- CSS classes: TailwindCSS utility classes only. Use `class:` directive for conditional styles.
- URL slugs and route params: **kebab-case** -- `/aktuell/mein-artikel`

### Error Handling

- In `+page.server.ts` / `+server.ts`: use SvelteKit's `error()` and `redirect()` helpers.
- Wrap Directus SDK calls in try/catch. Throw `error(404)` for missing content, `error(500)` for unexpected failures.
- Never expose internal error details to the client. Log them server-side.
- API endpoints (`+server.ts`) return proper HTTP status codes and JSON bodies.

```typescript
// +page.server.ts
import { error } from '@sveltejs/kit';

export const load = async ({ params }) => {
  try {
    const article = await getArticleBySlug(params.slug);
    if (!article) throw error(404, 'Artikel nicht gefunden');
    return { article };
  } catch (err) {
    if (err instanceof HttpError) throw err;
    console.error('Failed to load article:', err);
    throw error(500, 'Interner Fehler');
  }
};
```

### Directus Integration

- Directus client lives in `$lib/server/directus.ts` (server-only).
- Use `@directus/sdk` with typed schema for all API calls.
- Always filter by `status: 'published'` for public-facing queries.
- Use static token auth (`DIRECTUS_TOKEN` env var), not user credentials.
- Fetch only the fields you need (use `fields` parameter), never fetch `*`.

### Environment Variables

- Secrets (DB passwords, tokens, VAPID private key) go in `.env`, **never committed**.
- Use `.env.example` as reference for required variables.
- SvelteKit public env: prefix with `PUBLIC_` -- `PUBLIC_SITE_URL`, `PUBLIC_VAPID_KEY`.
- Private env: no prefix -- `DIRECTUS_URL`, `DIRECTUS_TOKEN`, `VAPID_PRIVATE_KEY`.

### Internationalization

- This is a **German-language** site. UI strings are in German.
- Date formatting: use `de-DE` locale -- `toLocaleDateString('de-DE')`.
- No i18n framework needed. Hardcoded German strings are acceptable.

### Accessibility & SEO

- Semantic HTML (`<article>`, `<nav>`, `<main>`, `<section>`, `<time>`).
- Every page sets `<title>` and `<meta name="description">` via `<svelte:head>`.
- Images require `alt` text. Use Directus `title` field as alt text.
- Keyboard navigable. Visible focus indicators.
- Structured data (JSON-LD) for events.

### Git & Workflow

- Main branches: `main` (production), `develop` (integration).
- Feature branches off `develop`, merged via PR.
- Commit messages: conventional style -- `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`.
- CI runs lint + type-check on push to `main`.
- Docker images are built and deployed from `main`.
