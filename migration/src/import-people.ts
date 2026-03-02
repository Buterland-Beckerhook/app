/**
 * Import people (Vorstand + Offiziere) from Hugo data into Directus.
 *
 * Usage:
 *   npx tsx src/import-people.ts [path-to-hugo-data]
 *
 * Maps YAML role keys to German display titles.
 */

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parse } from 'yaml';
import { createItem, deleteAllItems, readItems, DIRECTUS_URL } from './directus.js';

const HUGO_DATA_PATH = process.argv[2] ?? '../../buterland-beckerhook/data';

interface HugoPerson {
	name: string;
	street?: string;
	city?: string;
}

/** Mapping from YAML keys to German role display names + sort order */
const VORSTAND_ROLES: Record<string, { role: string; sortOrder: number }> = {
	praesident: { role: 'Präsident', sortOrder: 1 },
	vizePraesident: { role: 'Vizepräsident', sortOrder: 2 },
	geschaeftsfuehrer: { role: 'Geschäftsführer', sortOrder: 3 },
	schriftfuehrer: { role: 'Schriftführer', sortOrder: 4 },
	kassierer: { role: 'Kassierer', sortOrder: 5 }
};

const OFFIZIERE_ROLES: Record<string, { role: string; sortOrder: number }> = {
	oberst: { role: 'Oberst', sortOrder: 10 },
	oberstleutnant: { role: 'Oberstleutnant', sortOrder: 11 },
	major: { role: 'Major', sortOrder: 12 }
};

async function importGroup(
	filePath: string,
	group: 'vorstand' | 'offiziere',
	roleMap: Record<string, { role: string; sortOrder: number }>
) {
	console.log(`--- ${group.charAt(0).toUpperCase() + group.slice(1)} ---`);

	const content = readFileSync(filePath, 'utf-8');
	const data = parse(content) as Record<string, HugoPerson>;

	let count = 0;
	for (const [key, person] of Object.entries(data)) {
		const mapping = roleMap[key];
		if (!mapping) {
			console.log(`  WARN: Unknown role key "${key}" — skipping`);
			continue;
		}

		if (!person.name) {
			console.log(`  SKIP: ${key} (no name)`);
			continue;
		}

		const item = {
			group,
			role: mapping.role,
			role_key: key,
			name: person.name,
			street: person.street || null,
			city: person.city || null,
			sort_order: mapping.sortOrder
		};

		const created = await createItem('people', item);
		console.log(`  OK: ${mapping.role} → ${person.name} (${created.id})`);
		count++;
	}

	return count;
}

async function main() {
	console.log('=== Import People ===');
	console.log(`Directus: ${DIRECTUS_URL}`);
	console.log(`Source:   ${HUGO_DATA_PATH}`);
	console.log('');

	// Check for existing people
	const existing = await readItems('people');
	if (existing.length > 0) {
		console.log(`Found ${existing.length} existing people. Deleting...`);
		const deleted = await deleteAllItems('people');
		console.log(`Deleted ${deleted} people.`);
	}

	const vorstandFile = join(HUGO_DATA_PATH, 'vorstand.yaml');
	const offiziereFile = join(HUGO_DATA_PATH, 'offiziere.yaml');

	console.log('');
	const vorstandCount = await importGroup(vorstandFile, 'vorstand', VORSTAND_ROLES);

	console.log('');
	const offiziereCount = await importGroup(offiziereFile, 'offiziere', OFFIZIERE_ROLES);

	console.log('');
	console.log(`Done. Vorstand: ${vorstandCount}, Offiziere: ${offiziereCount}`);
}

main().catch((err) => {
	console.error('FATAL:', err);
	process.exit(1);
});
