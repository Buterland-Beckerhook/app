/**
 * Import events from Hugo content/termine/ into Directus.
 *
 * Creates: events (linked to existing locations).
 *
 * Usage:
 *   npx tsx src/import-events.ts [path-to-hugo-content]
 */

import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, basename } from 'node:path';
import { parse as parseYaml } from 'yaml';
import { marked } from 'marked';
import {
	createItem,
	deleteAllItems,
	readItems,
	DIRECTUS_URL
} from './directus.js';

const HUGO_CONTENT_PATH = process.argv[2] ?? '../../buterland-beckerhook/content';
const TERMINE_DIR = join(HUGO_CONTENT_PATH, 'termine');

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface HugoEventFrontmatter {
	title: string;
	date: string;
	lastmod?: string;
	start: string;
	end?: string;
	location?: string;
	draft?: boolean;
	canceled?: boolean;
	announce?: boolean;
	revision?: number;
	outputs?: string[];
	hideOnHome?: boolean;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Parse frontmatter + body from markdown file content. */
function parseFrontmatter(content: string): { frontmatter: HugoEventFrontmatter; body: string } {
	const normalized = content.replace(/\r\n/g, '\n');
	const match = normalized.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
	if (!match) throw new Error('No frontmatter found');
	const frontmatter = parseYaml(match[1]) as HugoEventFrontmatter;
	const body = match[2].trim();
	return { frontmatter, body };
}

/**
 * Generate slug from event title and year.
 * Converts to lowercase kebab-case with year suffix for uniqueness.
 */
function generateSlug(title: string, start: string): string {
	const year = start.substring(0, 4);
	const base = title
		.toLowerCase()
		.replace(/[äÄ]/g, 'ae')
		.replace(/[öÖ]/g, 'oe')
		.replace(/[üÜ]/g, 'ue')
		.replace(/ß/g, 'ss')
		.replace(/[^a-z0-9]+/g, '-')
		.replace(/^-+|-+$/g, '');
	return `${base}-${year}`;
}

/**
 * Determine event status from Hugo frontmatter.
 * canceled: true → 'canceled'
 * draft: true → 'draft'
 * otherwise → 'published'
 */
function getStatus(fm: HugoEventFrontmatter): 'draft' | 'published' | 'canceled' {
	if (fm.canceled === true) return 'canceled';
	if (fm.draft === true) return 'draft';
	return 'published';
}

/**
 * Detect whether an event is all-day (no meaningful time component).
 * All-day if:
 *   - Date-only string (e.g. "2024-06-15")
 *   - Time is midnight with no offset or UTC (e.g. "2024-06-15T00:00:00", "2024-06-15T00:00:00Z")
 * If start has no time component we consider it all-day regardless of end.
 */
function isAllDay(start: string, end?: string): boolean {
	return hasNoTime(String(start)) && (end == null || hasNoTime(String(end)));
}

/** Check if a date string has no meaningful time component. */
function hasNoTime(dateStr: string): boolean {
	// Pure date: "2024-06-15"
	if (/^\d{4}-\d{2}-\d{2}$/.test(dateStr)) return true;
	// Midnight variants: T00:00:00, T00:00:00Z, T00:00:00+00:00, etc.
	if (/T00:00:00([Z+\-].*)?$/.test(dateStr)) return true;
	return false;
}

/**
 * Process body: remove Hugo shortcodes and refs, convert Markdown to HTML.
 */
function processBody(rawBody: string): string | null {
	if (!rawBody) return null;

	let body = rawBody;

	// Convert Hugo {{< ref "..." >}} to relative URLs
	body = body.replace(/\{\{<\s*ref\s+"([^"]+)"\s*>}}/g, (_match, path: string) => {
		// Convert Hugo content path to URL
		// e.g. "/aktuell/2024/einladung" → "/aktuell/2024/einladung"
		return path.startsWith('/') ? path : `/${path}`;
	});

	// Remove any remaining shortcodes
	body = body.replace(/\{\{<\s*.*?>}}/g, '');

	body = body.trim();
	if (!body) return null;

	return body;
}

/**
 * Normalize location slug.
 * Handles known typos/variants from Hugo data.
 */
function normalizeLocation(location?: string): string | null {
	if (!location) return null;

	const normalized = location.toLowerCase().trim();

	// Map known variants
	const locationMap: Record<string, string | null> = {
		dinkelhof: 'dinkelhof',
		dinkehof: 'dinkelhof', // typo
		platz: 'platz',
		gleis: 'gleis',
		none: null,
		unknown: null
	};

	if (normalized in locationMap) return locationMap[normalized];

	// Inline address or unknown location — skip
	return null;
}

/** Find all event files (excluding _index.md section files). */
function findEventFiles(termineDir: string): string[] {
	const results: string[] = [];

	const entries = readdirSync(termineDir);

	for (const entry of entries) {
		const fullPath = join(termineDir, entry);

		if (statSync(fullPath).isDirectory()) {
			// Year directories (2018, 2019, ...)
			const yearFiles = readdirSync(fullPath).filter(
				(f) => f.endsWith('.md') && f !== '_index.md'
			);
			for (const file of yearFiles) {
				results.push(join(fullPath, file));
			}
		} else if (entry.endsWith('.md') && entry !== '_index.md') {
			// Root-level event files (unlikely but handle)
			results.push(fullPath);
		}
	}

	return results.sort();
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
	console.log('=== Import Events ===');
	console.log(`Directus: ${DIRECTUS_URL}`);
	console.log(`Source:   ${TERMINE_DIR}`);
	console.log('');

	// Clean up existing events
	const existingEvents = await readItems('events', { limit: '-1' });
	if (existingEvents.length > 0) {
		console.log(`Deleting ${existingEvents.length} existing events...`);
		await deleteAllItems('events');
	}

	// Load existing locations for slug → ID mapping
	const locations = await readItems('locations', { limit: '-1' });
	const locationMap = new Map<string, string>();
	for (const loc of locations) {
		locationMap.set(loc.key as string, loc.id as string);
	}
	console.log(`Loaded ${locationMap.size} locations: ${[...locationMap.keys()].join(', ')}`);
	console.log('');

	// Find all event files
	const eventFiles = findEventFiles(TERMINE_DIR);
	console.log(`Found ${eventFiles.length} event files.`);
	console.log('');

	let imported = 0;
	let errors = 0;
	const usedSlugs = new Set<string>();

	for (const eventPath of eventFiles) {
		const fileName = basename(eventPath, '.md');
		const yearDir = basename(join(eventPath, '..'));
		const content = readFileSync(eventPath, 'utf-8');

		let frontmatter: HugoEventFrontmatter;
		let rawBody: string;

		try {
			const parsed = parseFrontmatter(content);
			frontmatter = parsed.frontmatter;
			rawBody = parsed.body;
		} catch (err) {
			const message = err instanceof Error ? err.message : JSON.stringify(err);
			console.error(`  ERROR parsing ${eventPath}: ${message}`);
			errors++;
			continue;
		}

		if (!frontmatter.start) {
			console.error(`  ERROR: ${yearDir}/${fileName} has no 'start' field — skipping`);
			errors++;
			continue;
		}

		// Generate unique slug
		let slug = generateSlug(frontmatter.title, String(frontmatter.start));
		if (usedSlugs.has(slug)) {
			// Append counter for duplicates
			let counter = 2;
			while (usedSlugs.has(`${slug}-${counter}`)) counter++;
			slug = `${slug}-${counter}`;
		}
		usedSlugs.add(slug);

		const status = getStatus(frontmatter);

		// Resolve location
		const locationKey = normalizeLocation(frontmatter.location);
		const locationId = locationKey ? locationMap.get(locationKey) ?? null : null;

		if (locationKey && !locationId) {
			console.log(`    WARN: Unknown location "${frontmatter.location}" → null`);
		}

		// Process body
		const body = processBody(rawBody);

		// Determine announce flag
		// Default is true (public event). Set to false if explicitly set in frontmatter.
		const announce = frontmatter.announce !== false;

		// Determine iCal enablement from outputs field
		const enableIcal = frontmatter.outputs?.includes('calendar') ?? false;

		// Format start/end dates as ISO strings
		const start = String(frontmatter.start);
		const end = frontmatter.end ? String(frontmatter.end) : null;
		const allDay = isAllDay(start, end ?? undefined);

		// Year is required by Directus (NOT NULL). The DB trigger also sets it from
		// `start`, but Directus validates before the INSERT reaches the DB.
		const year = parseInt(start.substring(0, 4), 10);

		const label = `${yearDir}/${fileName}`;

		try {
			await createItem('events', {
				title: frontmatter.title,
				slug,
				start,
				end,
				year,
				all_day: allDay,
				location: locationId,
				body,
				status,
				cancel_reason: status === 'canceled' ? body : null,
				announce,
				revision: frontmatter.revision ?? null,
				enable_ical: enableIcal,
				parent: null,
				calendar: null
			});

			const statusLabel = status !== 'published' ? ` [${status}]` : '';
			const locationLabel = frontmatter.location ? ` @ ${frontmatter.location}` : '';
			const allDayLabel = allDay ? ' [ganztägig]' : '';
			console.log(`  OK: ${label} → "${frontmatter.title}"${locationLabel}${statusLabel}${allDayLabel}`);
			imported++;
		} catch (err) {
			const message = err instanceof Error ? err.message : JSON.stringify(err);
			console.error(`  ERROR: ${label} → ${message}`);
			errors++;
		}
	}

	console.log('');
	console.log(`Done. Imported: ${imported}, Errors: ${errors}`);
}

main().catch((err) => {
	console.error('FATAL:', err);
	process.exit(1);
});
