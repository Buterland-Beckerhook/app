/**
 * Directus Branding Setup
 * Configures project settings, uploads logo/favicon, and sets admin avatar.
 *
 * Settings:
 *   - Project name:  Buterland-Beckerhook e.V.
 *   - Project color: #0b8d36
 *   - Project URL:   https://buterland-beckerhook.de
 *   - Project logo:  logo.svg (uploaded to Directus)
 *   - Public favicon: favicon.ico (uploaded to Directus)
 *   - Admin avatar:  logo.svg (same file as project logo)
 *
 * Usage:
 *   npx tsx src/setup-branding.ts
 *
 * Environment:
 *   DIRECTUS_URL     (default: http://localhost:8055)
 *   ADMIN_EMAIL      (default: admin@buterland-beckerhook.de)
 *   ADMIN_PASSWORD   (default: directus)
 */

import { readMe, updateUser } from '@directus/sdk';
import {
	createAdminClient,
	rawPatch,
	rawGet,
	uploadFile,
	replaceFile,
	DIRECTUS_URL
} from './directus.js';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { existsSync } from 'node:fs';

const __dirname = dirname(fileURLToPath(import.meta.url));

/** Resolve asset paths relative to repo root (setup/ is one level below root). */
const LOGO_PATH = resolve(__dirname, '../../frontend/static/logo.svg');
const FAVICON_PATH = resolve(__dirname, '../../frontend/static/favicon.ico');

interface DirectusFile {
	id: string;
	filename_download?: string;
	title?: string;
}

interface DirectusSettings {
	project_name?: string;
	project_color?: string;
	project_url?: string;
	project_logo?: string | null;
	public_favicon?: string | null;
	public_note?: string | null;
}

async function main(): Promise<void> {
	console.log('=== Directus Branding Setup ===');
	console.log(`URL: ${DIRECTUS_URL}`);
	console.log('');

	// Verify asset files exist
	if (!existsSync(LOGO_PATH)) {
		console.error(`ERROR: Logo not found at ${LOGO_PATH}`);
		process.exit(1);
	}
	if (!existsSync(FAVICON_PATH)) {
		console.error(`ERROR: Favicon not found at ${FAVICON_PATH}`);
		process.exit(1);
	}

	const client = await createAdminClient();
	console.log('Authenticated.');

	// =========================================================================
	// 1. Check for existing branding files in Directus
	// =========================================================================
	console.log('');
	console.log('--- Uploading Branding Assets ---');

	// Check current settings to see if logo/favicon are already set
	let currentSettings: DirectusSettings = {};
	try {
		const settingsRes = (await rawGet(client, '/settings')) as { data: DirectusSettings };
		currentSettings = settingsRes.data;
	} catch {
		console.log('  Could not read current settings, will create fresh.');
	}

	// Upload or replace logo
	let logoFileId: string;
	if (currentSettings.project_logo) {
		console.log(`  Logo already set (${currentSettings.project_logo}), replacing...`);
		const file = await replaceFile(
			client,
			currentSettings.project_logo,
			LOGO_PATH,
			'Buterland-Beckerhook Logo'
		);
		logoFileId = file.id;
		console.log(`  OK: logo replaced (${logoFileId})`);
	} else {
		const file = await uploadFile(client, LOGO_PATH, 'Buterland-Beckerhook Logo');
		logoFileId = file.id;
		console.log(`  OK: logo uploaded (${logoFileId})`);
	}

	// Upload or replace favicon
	let faviconFileId: string;
	if (currentSettings.public_favicon) {
		console.log(`  Favicon already set (${currentSettings.public_favicon}), replacing...`);
		const file = await replaceFile(
			client,
			currentSettings.public_favicon,
			FAVICON_PATH,
			'Buterland-Beckerhook Favicon'
		);
		faviconFileId = file.id;
		console.log(`  OK: favicon replaced (${faviconFileId})`);
	} else {
		const file = await uploadFile(client, FAVICON_PATH, 'Buterland-Beckerhook Favicon');
		faviconFileId = file.id;
		console.log(`  OK: favicon uploaded (${faviconFileId})`);
	}

	// =========================================================================
	// 2. Update Directus project settings
	// =========================================================================
	console.log('');
	console.log('--- Configuring Project Settings ---');

	await rawPatch(client, '/settings', {
		project_name: 'Buterland-Beckerhook e.V.',
		project_color: '#0b8d36',
		project_url: 'https://buterland-beckerhook.de',
		project_logo: logoFileId,
		public_favicon: faviconFileId,
		public_note:
			'Schützenverein Buterland-Beckerhook e.V. | OpenSource / Community use | admin@buterland-beckerhook.de'
	});

	console.log('  OK: project_name  = Buterland-Beckerhook e.V.');
	console.log('  OK: project_color = #0b8d36');
	console.log('  OK: project_url   = https://buterland-beckerhook.de');
	console.log(`  OK: project_logo  = ${logoFileId}`);
	console.log(`  OK: public_favicon = ${faviconFileId}`);
	console.log('  OK: public_note   = (owner info set)');

	// =========================================================================
	// 3. Set admin user avatar to logo
	// =========================================================================
	console.log('');
	console.log('--- Setting Admin Avatar ---');

	const me = await client.request(readMe({ fields: ['id', 'email', 'avatar'] }));
	console.log(`Admin user: ${me.email} (${me.id})`);

	try {
		await client.request(updateUser(me.id as string, { avatar: logoFileId }));
		console.log(`  OK: admin avatar set to logo (${logoFileId})`);
	} catch (err) {
		console.log('  WARN: setting admin avatar failed');
		if (process.env.DEBUG) console.error(err);
	}

	// =========================================================================
	// Done
	// =========================================================================
	console.log('');
	console.log('=== Branding setup complete! ===');
	console.log('');
	console.log('Summary:');
	console.log('  Project:  Buterland-Beckerhook e.V.');
	console.log('  Color:    #0b8d36');
	console.log('  URL:      https://buterland-beckerhook.de');
	console.log('  Owner:    admin@buterland-beckerhook.de / OpenSource / Community use');
	console.log(`  Logo:     ${logoFileId}`);
	console.log(`  Favicon:  ${faviconFileId}`);

	// Exit explicitly — the SDK auth refresh timer keeps Node alive otherwise
	process.exit(0);
}

main().catch((err) => {
	console.error('FATAL:', err);
	process.exit(1);
});
