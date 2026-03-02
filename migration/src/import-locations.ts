/**
 * Import locations from Hugo data/locations/*.yaml into Directus.
 *
 * Usage:
 *   npx tsx src/import-locations.ts [path-to-hugo-data]
 *
 * Skips 'none' and 'unknown' (placeholder locations).
 * Swaps lat/lng values (Hugo has them reversed).
 */

import { readFileSync, readdirSync } from 'node:fs';
import { basename, join } from 'node:path';
import { parse } from 'yaml';
import { createItem, deleteAllItems, readItems, DIRECTUS_URL } from './directus.js';

const HUGO_DATA_PATH = process.argv[2] ?? '../../buterland-beckerhook/data';
const LOCATIONS_DIR = join(HUGO_DATA_PATH, 'locations');

/** Placeholder files to skip */
const SKIP_FILES = new Set(['none', 'unknown']);

interface HugoLocation {
	name: string;
	street?: string;
	zip?: number | string;
	city?: string;
	lat?: number;
	lng?: number;
	maps?: string;
	url?: string;
}

async function main() {
	console.log('=== Import Locations ===');
	console.log(`Directus: ${DIRECTUS_URL}`);
	console.log(`Source:   ${LOCATIONS_DIR}`);
	console.log('');

	// Check for existing locations — skip if already present (referenced by events via FK)
	const existing = await readItems('locations');
	if (existing.length > 0) {
		console.log(`Found ${existing.length} existing locations. Skipping import (already present).`);
		console.log('To re-import locations, delete events first, then re-run.');
		return;
	}

	// Read all YAML files
	const files = readdirSync(LOCATIONS_DIR).filter((f) => f.endsWith('.yaml'));
	console.log(`Found ${files.length} location files.`);
	console.log('');

	let imported = 0;
	let skipped = 0;

	for (const file of files) {
		const key = basename(file, '.yaml');

		if (SKIP_FILES.has(key)) {
			console.log(`  SKIP: ${file} (placeholder)`);
			skipped++;
			continue;
		}

		const content = readFileSync(join(LOCATIONS_DIR, file), 'utf-8');
		const data = parse(content) as HugoLocation;

		if (!data.name) {
			console.log(`  SKIP: ${file} (no name)`);
			skipped++;
			continue;
		}

		// Swap lat/lng (Hugo has them reversed: lat contains longitude, lng contains latitude)
		const item = {
			key,
			name: data.name,
			street: data.street ?? null,
			zip: data.zip ? String(data.zip) : null,
			city: data.city ?? null,
			lat: data.lng ?? null, // Hugo lng is actually latitude
			lng: data.lat ?? null, // Hugo lat is actually longitude
			url: data.url ?? null,
			maps_url: data.maps ?? null
		};

		const created = await createItem('locations', item);
		console.log(`  OK: ${key} → "${data.name}" (${created.id})`);
		imported++;
	}

	console.log('');
	console.log(`Done. Imported: ${imported}, Skipped: ${skipped}`);
}

main().catch((err) => {
	console.error('FATAL:', err);
	process.exit(1);
});
