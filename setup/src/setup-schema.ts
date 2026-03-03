/**
 * Directus Schema Setup
 * Creates all collections, fields, and relations for buterland-beckerhook.de
 *
 * Usage:
 *   npx tsx src/setup-schema.ts
 *
 * Environment:
 *   DIRECTUS_URL     (default: http://localhost:8055)
 *   ADMIN_EMAIL      (default: admin@buterland-beckerhook.de)
 *   ADMIN_PASSWORD   (default: directus)
 */

import {
	createCollection,
	createField,
	createRelation,
	updateField
} from '@directus/sdk';
import { createAdminClient, DIRECTUS_URL, ADMIN_EMAIL } from './directus.js';

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type NestedPartial = any;

async function main(): Promise<void> {
	console.log('=== Directus Schema Setup ===');
	console.log(`URL:   ${DIRECTUS_URL}`);
	console.log(`Admin: ${ADMIN_EMAIL}`);
	console.log('');

	const client = await createAdminClient();
	console.log('Authenticated.');

	// Helper: create collection, warn on conflict
	async function safeCreateCollection(data: NestedPartial): Promise<void> {
		try {
			await client.request(createCollection(data));
			console.log(`  OK: collection "${data.collection}"`);
		} catch (err) {
			console.log(`  WARN: collection "${data.collection}" may already exist or failed`);
			if (process.env.DEBUG) console.error(err);
		}
	}

	// Helper: create field, warn on conflict
	// Collection name is cast to `never` because the SDK expects a keyof Schema,
	// but we use an untyped schema for these admin setup scripts.
	async function safeCreateField(collection: string, data: NestedPartial): Promise<void> {
		try {
			await client.request(createField(collection as never, data));
			console.log(`  OK: field "${collection}.${data.field}"`);
		} catch (err) {
			console.log(`  WARN: field "${collection}.${data.field}" may already exist or failed`);
			if (process.env.DEBUG) console.error(err);
		}
	}

	// Helper: create relation, warn on conflict
	async function safeCreateRelation(data: NestedPartial): Promise<void> {
		try {
			await client.request(createRelation(data));
			console.log(`  OK: relation "${data.collection}.${data.field}"`);
		} catch (err) {
			console.log(
				`  WARN: relation "${data.collection}.${data.field}" may already exist or failed`
			);
			if (process.env.DEBUG) console.error(err);
		}
	}

	// Helper: update (patch) field, warn on failure
	async function safeUpdateField(
		collection: string,
		field: string,
		data: NestedPartial
	): Promise<void> {
		try {
			await client.request(updateField(collection as never, field, data));
			console.log(`  OK: patch "${collection}.${field}"`);
		} catch (err) {
			console.log(`  WARN: patch "${collection}.${field}" failed`);
			if (process.env.DEBUG) console.error(err);
		}
	}

	// =========================================================================
	// 1. COLLECTIONS
	// =========================================================================
	console.log('');
	console.log('--- Creating Collections ---');

	// locations
	await safeCreateCollection({
		collection: 'locations',
		meta: {
			icon: 'place',
			note: 'Veranstaltungsorte',
			sort_field: 'name',
			archive_field: null,
			archive_value: null,
			unarchive_value: null,
			translations: [{ language: 'de-DE', translation: 'Orte' }]
		},
		schema: {},
		fields: [
			{
				field: 'id',
				type: 'uuid',
				meta: { hidden: true, interface: 'input', readonly: true, special: ['uuid'] },
				schema: { is_primary_key: true, has_auto_increment: false }
			},
			{
				field: 'key',
				type: 'string',
				meta: {
					interface: 'input',
					required: true,
					note: 'Eindeutiger Schlüssel (z.B. platz, dinkelhof)'
				},
				schema: { is_unique: true, is_nullable: false }
			},
			{
				field: 'name',
				type: 'string',
				meta: { interface: 'input', required: true, note: 'Anzeigename' },
				schema: { is_nullable: false }
			},
			{
				field: 'street',
				type: 'string',
				meta: { interface: 'input' },
				schema: { is_nullable: true }
			},
			{
				field: 'zip',
				type: 'string',
				meta: { interface: 'input' },
				schema: { is_nullable: true }
			},
			{
				field: 'city',
				type: 'string',
				meta: { interface: 'input' },
				schema: { is_nullable: true }
			},
			{
				field: 'lat',
				type: 'float',
				meta: { interface: 'input', note: 'GPS Breitengrad' },
				schema: { is_nullable: true }
			},
			{
				field: 'lng',
				type: 'float',
				meta: { interface: 'input', note: 'GPS Längengrad' },
				schema: { is_nullable: true }
			},
			{
				field: 'url',
				type: 'string',
				meta: { interface: 'input', note: 'Website-URL (z.B. Homepage des Ortes)' },
				schema: { is_nullable: true }
			},
			{
				field: 'maps_url',
				type: 'string',
				meta: { interface: 'input', note: 'Google Maps Link' },
				schema: { is_nullable: true }
			}
		]
	});

	// people
	await safeCreateCollection({
		collection: 'people',
		meta: {
			icon: 'groups',
			note: 'Vorstand und Offiziere',
			sort_field: 'sort_order',
			translations: [{ language: 'de-DE', translation: 'Personen' }]
		},
		schema: {},
		fields: [
			{
				field: 'id',
				type: 'uuid',
				meta: { hidden: true, interface: 'input', readonly: true, special: ['uuid'] },
				schema: { is_primary_key: true, has_auto_increment: false }
			},
			{
				field: 'group',
				type: 'string',
				meta: {
					interface: 'select-dropdown',
					required: true,
					options: {
						choices: [
							{ text: 'Vorstand', value: 'vorstand' },
							{ text: 'Offiziere', value: 'offiziere' }
						]
					}
				},
				schema: { is_nullable: false }
			},
			{
				field: 'role',
				type: 'string',
				meta: {
					interface: 'input',
					required: true,
					note: 'z.B. Präsident, Oberst'
				},
				schema: { is_nullable: false }
			},
			{
				field: 'role_key',
				type: 'string',
				meta: {
					interface: 'input',
					required: true,
					note: 'z.B. praesident, oberst (für Sortierung)'
				},
				schema: { is_nullable: false }
			},
			{
				field: 'name',
				type: 'string',
				meta: { interface: 'input', required: true },
				schema: { is_nullable: false }
			},
			{
				field: 'street',
				type: 'string',
				meta: { interface: 'input' },
				schema: { is_nullable: true }
			},
			{
				field: 'city',
				type: 'string',
				meta: { interface: 'input' },
				schema: { is_nullable: true }
			},
			{
				field: 'sort_order',
				type: 'integer',
				meta: { interface: 'input', required: true },
				schema: { is_nullable: false, default_value: 0 }
			}
		]
	});

	// pages
	await safeCreateCollection({
		collection: 'pages',
		meta: {
			icon: 'article',
			note: 'Statische Seiten (Impressum, Datenschutz, Verein-Unterseiten)',
			sort_field: 'sort_order',
			archive_field: 'status',
			archive_value: 'archived',
			unarchive_value: 'draft',
			translations: [{ language: 'de-DE', translation: 'Seiten' }]
		},
		schema: {},
		fields: [
			{
				field: 'id',
				type: 'uuid',
				meta: { hidden: true, interface: 'input', readonly: true, special: ['uuid'] },
				schema: { is_primary_key: true, has_auto_increment: false }
			},
			{
				field: 'status',
				type: 'string',
				meta: {
					interface: 'select-dropdown',
					required: true,
					options: {
						choices: [
							{ text: 'Entwurf', value: 'draft' },
							{ text: 'Veröffentlicht', value: 'published' }
						]
					},
					default_value: 'draft',
					width: 'half'
				},
				schema: { is_nullable: false, default_value: 'draft' }
			},
			{
				field: 'title',
				type: 'string',
				meta: { interface: 'input', required: true, width: 'half' },
				schema: { is_nullable: false }
			},
			{
				field: 'slug',
				type: 'string',
				meta: {
					interface: 'input',
					required: true,
					note: 'URL-Pfad (z.B. impressum, ueber-uns)',
					options: { slug: true }
				},
				schema: { is_unique: true, is_nullable: false }
			},
			{
				field: 'body',
				type: 'text',
				meta: {
					interface: 'input-rich-text-html',
					required: true,
					note: 'Seiteninhalt'
				},
				schema: { is_nullable: false }
			},
			{
				field: 'sort_order',
				type: 'integer',
				meta: { interface: 'input', width: 'half' },
				schema: { is_nullable: true, default_value: 0 }
			}
		]
	});

	// articles (without relations — those come after thrones exists)
	await safeCreateCollection({
		collection: 'articles',
		meta: {
			icon: 'newspaper',
			note: 'Artikel und Neuigkeiten',
			sort_field: null,
			archive_field: 'status',
			archive_value: 'archived',
			unarchive_value: 'draft',
			translations: [{ language: 'de-DE', translation: 'Artikel' }]
		},
		schema: {},
		fields: [
			{
				field: 'id',
				type: 'uuid',
				meta: { hidden: true, interface: 'input', readonly: true, special: ['uuid'] },
				schema: { is_primary_key: true, has_auto_increment: false }
			},
			{
				field: 'status',
				type: 'string',
				meta: {
					interface: 'select-dropdown',
					required: true,
					options: {
						choices: [
							{ text: 'Entwurf', value: 'draft' },
							{ text: 'Veröffentlicht', value: 'published' },
							{ text: 'Archiviert', value: 'archived' }
						]
					},
					default_value: 'draft',
					width: 'half'
				},
				schema: { is_nullable: false, default_value: 'draft' }
			},
			{
				field: 'title',
				type: 'string',
				meta: { interface: 'input', required: true },
				schema: { is_nullable: false }
			},
			{
				field: 'subtitle',
				type: 'string',
				meta: { interface: 'input' },
				schema: { is_nullable: true }
			},
			{
				field: 'slug',
				type: 'string',
				meta: {
					interface: 'input',
					required: true,
					options: { slug: true }
				},
				schema: { is_unique: true, is_nullable: false }
			},
			{
				field: 'date_published',
				type: 'timestamp',
				meta: { interface: 'datetime', required: true, width: 'half' },
				schema: { is_nullable: false }
			},
			{
				field: 'author',
				type: 'string',
				meta: { interface: 'input', width: 'half' },
				schema: { is_nullable: true }
			},
			{
				field: 'tags',
				type: 'json',
				meta: {
					interface: 'tags',
					special: ['cast-json'],
					note: 'z.B. Thron, Schützenfest'
				},
				schema: { is_nullable: true }
			},
			{
				field: 'body',
				type: 'text',
				meta: { interface: 'input-rich-text-html', note: 'Artikeltext' },
				schema: { is_nullable: true }
			},
			{
				field: 'no_article',
				type: 'boolean',
				meta: {
					interface: 'boolean',
					width: 'half',
					note: 'Nur Thron-Anzeige, kein eigener Artikel'
				},
				schema: { is_nullable: false, default_value: false }
			},
			{
				field: 'aliases',
				type: 'json',
				meta: {
					interface: 'tags',
					special: ['cast-json'],
					note: 'Alte URLs für Redirects'
				},
				schema: { is_nullable: true }
			}
		]
	});

	// article_images
	await safeCreateCollection({
		collection: 'article_images',
		meta: {
			icon: 'photo_library',
			note: 'Bilder zu Artikeln',
			sort_field: 'sort',
			translations: [{ language: 'de-DE', translation: 'Artikelbilder' }],
			hidden: true
		},
		schema: {},
		fields: [
			{
				field: 'id',
				type: 'uuid',
				meta: { hidden: true, interface: 'input', readonly: true, special: ['uuid'] },
				schema: { is_primary_key: true, has_auto_increment: false }
			},
			{
				field: 'logical_name',
				type: 'string',
				meta: { interface: 'input', note: 'z.B. thron-1, bild-1' },
				schema: { is_nullable: true }
			},
			{
				field: 'title',
				type: 'string',
				meta: { interface: 'input', note: 'Bildunterschrift' },
				schema: { is_nullable: true }
			},
			{
				field: 'copyright',
				type: 'string',
				meta: { interface: 'input', note: 'Urheber' },
				schema: { is_nullable: true, default_value: 'Buterland-Beckerhook e.V.' }
			},
			{
				field: 'sort',
				type: 'integer',
				meta: { interface: 'input', hidden: true },
				schema: { is_nullable: true }
			},
			{
				field: 'use_as_throne_picture',
				type: 'boolean',
				meta: { interface: 'boolean', note: 'Als Thron-Bild verwenden?' },
				schema: { is_nullable: false, default_value: false }
			}
		]
	});

	// thrones
	await safeCreateCollection({
		collection: 'thrones',
		meta: {
			icon: 'emoji_events',
			note: 'Throne und Königspaare',
			translations: [{ language: 'de-DE', translation: 'Throne' }]
		},
		schema: {},
		fields: [
			{
				field: 'id',
				type: 'uuid',
				meta: { hidden: true, interface: 'input', readonly: true, special: ['uuid'] },
				schema: { is_primary_key: true, has_auto_increment: false }
			},
			{
				field: 'type',
				type: 'string',
				meta: {
					interface: 'select-dropdown',
					required: true,
					width: 'half',
					options: {
						choices: [
							{ text: 'König', value: 'koenig' },
							{ text: 'Kaiser', value: 'kaiser' },
							{ text: 'Stadtkaiser', value: 'stadtkaiser' }
						]
					}
				},
				schema: { is_nullable: false }
			},
			{
				field: 'begin',
				type: 'integer',
				meta: {
					interface: 'input',
					required: true,
					width: 'half',
					note: 'Startjahr (z.B. 2024)'
				},
				schema: { is_nullable: false }
			},
			{
				field: 'end',
				type: 'integer',
				meta: {
					interface: 'input',
					width: 'half',
					note: 'Endjahr (z.B. 2025), leer wenn noch regierend'
				},
				schema: { is_nullable: true }
			},
			{
				field: 'king_title',
				type: 'string',
				meta: {
					interface: 'input',
					width: 'half',
					note: 'Regalname: Gerd X., Bernhard I.'
				},
				schema: { is_nullable: true }
			},
			{
				field: 'king',
				type: 'string',
				meta: {
					interface: 'input',
					required: true,
					width: 'half',
					note: 'Bürgerlicher Name'
				},
				schema: { is_nullable: false }
			},
			{
				field: 'queen',
				type: 'string',
				meta: { interface: 'input', required: true, width: 'half' },
				schema: { is_nullable: false }
			},
			{
				field: 'moh1',
				type: 'string',
				meta: { interface: 'input', width: 'half', note: 'Ehrendame 1' },
				schema: { is_nullable: true }
			},
			{
				field: 'moh2',
				type: 'string',
				meta: { interface: 'input', width: 'half', note: 'Ehrendame 2' },
				schema: { is_nullable: true }
			},
			{
				field: 'loh1',
				type: 'string',
				meta: { interface: 'input', width: 'half', note: 'Ehrenherr 1' },
				schema: { is_nullable: true }
			},
			{
				field: 'loh2',
				type: 'string',
				meta: { interface: 'input', width: 'half', note: 'Ehrenherr 2' },
				schema: { is_nullable: true }
			},
			{
				field: 'cupbearer',
				type: 'string',
				meta: { interface: 'input', width: 'half', note: 'Mundschenk' },
				schema: { is_nullable: true }
			},
			{
				field: 'courtmarshal',
				type: 'string',
				meta: { interface: 'input', width: 'half', note: 'Oberhofmarschall' },
				schema: { is_nullable: true }
			}
		]
	});

	// events
	await safeCreateCollection({
		collection: 'events',
		meta: {
			icon: 'event',
			note: 'Termine und Veranstaltungen',
			archive_field: 'status',
			archive_value: 'canceled',
			unarchive_value: 'draft',
			translations: [{ language: 'de-DE', translation: 'Termine' }]
		},
		schema: {},
		fields: [
			{
				field: 'id',
				type: 'uuid',
				meta: { hidden: true, interface: 'input', readonly: true, special: ['uuid'] },
				schema: { is_primary_key: true, has_auto_increment: false }
			},
			{
				field: 'status',
				type: 'string',
				meta: {
					interface: 'select-dropdown',
					required: true,
					options: {
						choices: [
							{ text: 'Entwurf', value: 'draft' },
							{ text: 'Veröffentlicht', value: 'published' },
							{ text: 'Abgesagt', value: 'canceled' }
						]
					},
					default_value: 'draft',
					width: 'half'
				},
				schema: { is_nullable: false, default_value: 'draft' }
			},
			{
				field: 'title',
				type: 'string',
				meta: { interface: 'input', required: true },
				schema: { is_nullable: false }
			},
			{
				field: 'slug',
				type: 'string',
				meta: {
					interface: 'input',
					required: true,
					options: { slug: true }
				},
				schema: { is_unique: true, is_nullable: false }
			},
			{
				field: 'start',
				type: 'timestamp',
				meta: { interface: 'datetime', required: true, width: 'half' },
				schema: { is_nullable: false }
			},
			{
				field: 'end',
				type: 'timestamp',
				meta: { interface: 'datetime', width: 'half' },
				schema: { is_nullable: true }
			},
			{
				field: 'body',
				type: 'text',
				meta: { interface: 'input-rich-text-html' },
				schema: { is_nullable: true }
			},
			{
				field: 'cancel_reason',
				type: 'string',
				meta: { interface: 'input', note: 'Grund bei Absage' },
				schema: { is_nullable: true }
			},
			{
				field: 'announce',
				type: 'boolean',
				meta: {
					interface: 'boolean',
					width: 'half',
					note: 'Öffentlich ankündigen'
				},
				schema: { is_nullable: false, default_value: true }
			},
			{
				field: 'revision',
				type: 'integer',
				meta: { interface: 'input', width: 'half' },
				schema: { is_nullable: true }
			},
			{
				field: 'enable_ical',
				type: 'boolean',
				meta: {
					interface: 'boolean',
					width: 'half',
					note: 'iCal-Export aktivieren'
				},
				schema: { is_nullable: false, default_value: true }
			},
			{
				field: 'calendar',
				type: 'string',
				meta: {
					interface: 'select-dropdown',
					width: 'half',
					note: 'Interner Kalender (leer = öffentlich)',
					options: {
						choices: [
							{ text: 'Vorstand', value: 'vorstand' },
							{ text: 'Offiziere', value: 'offiziere' },
							{ text: 'Jungschützen', value: 'jungschuetzen' },
							{ text: 'Kinderfest', value: 'kinderfest' }
						],
						allowOther: false
					}
				},
				schema: { is_nullable: true }
			},
			{
				field: 'user_created',
				type: 'uuid',
				meta: {
					special: ['user-created'],
					interface: 'select-dropdown-m2o',
					display: 'user',
					readonly: true,
					hidden: true,
					width: 'half'
				},
				schema: { is_nullable: true }
			}
		]
	});

	// =========================================================================
	// 2. RELATIONS (after all collections exist)
	// =========================================================================
	console.log('');
	console.log('--- Creating Relations ---');

	// pages.parent -> pages (self-referencing M2O)
	await safeCreateField('pages', {
		field: 'parent',
		type: 'uuid',
		meta: { interface: 'select-dropdown-m2o', special: ['m2o'], note: 'Übergeordnete Seite' },
		schema: { is_nullable: true }
	});
	await safeCreateRelation({
		collection: 'pages',
		field: 'parent',
		related_collection: 'pages',
		meta: { one_field: null, sort_field: null }
	});

	// article_images.article -> articles (M2O)
	await safeCreateField('article_images', {
		field: 'article',
		type: 'uuid',
		meta: {
			interface: 'select-dropdown-m2o',
			special: ['m2o'],
			required: true,
			hidden: true
		},
		schema: { is_nullable: false }
	});
	await safeCreateRelation({
		collection: 'article_images',
		field: 'article',
		related_collection: 'articles',
		meta: { one_field: 'images', sort_field: 'sort', one_deselect_action: 'delete' }
	});

	// article_images.image -> directus_files (M2O file)
	await safeCreateField('article_images', {
		field: 'image',
		type: 'uuid',
		meta: { interface: 'file-image', special: ['file'], required: true },
		schema: { is_nullable: false }
	});
	await safeCreateRelation({
		collection: 'article_images',
		field: 'image',
		related_collection: 'directus_files'
	});

	// Patch the auto-created articles.images alias to set O2M interface options
	await safeUpdateField('articles', 'images', {
		meta: {
			interface: 'list-o2m',
			special: ['o2m'],
			note: 'Zugehörige Bilder',
			options: { template: '{{title}} ({{logical_name}})' }
		}
	});

	// thrones.article -> articles (M2O, effectively O2O)
	await safeCreateField('thrones', {
		field: 'article',
		type: 'uuid',
		meta: {
			interface: 'select-dropdown-m2o',
			special: ['m2o'],
			required: true,
			note: 'Zugehöriger Artikel'
		},
		schema: { is_nullable: false }
	});
	await safeCreateRelation({
		collection: 'thrones',
		field: 'article',
		related_collection: 'articles',
		meta: { one_field: 'throne', one_deselect_action: 'nullify' }
	});

	// Patch the auto-created articles.throne alias to set O2M interface options
	await safeUpdateField('articles', 'throne', {
		meta: {
			interface: 'list-o2m',
			special: ['o2m'],
			note: 'Thron-Daten (wenn Thron-Artikel)',
			options: { enableCreate: true, enableSelect: false, limit: 1 }
		}
	});

	// events.location -> locations (M2O)
	await safeCreateField('events', {
		field: 'location',
		type: 'uuid',
		meta: {
			interface: 'select-dropdown-m2o',
			special: ['m2o'],
			note: 'Veranstaltungsort',
			display: 'related-values',
			display_options: { template: '{{name}}' }
		},
		schema: { is_nullable: true }
	});
	await safeCreateRelation({
		collection: 'events',
		field: 'location',
		related_collection: 'locations',
		meta: { one_field: null, sort_field: null }
	});

	// events.parent -> events (self-referencing M2O)
	await safeCreateField('events', {
		field: 'parent',
		type: 'uuid',
		meta: {
			interface: 'select-dropdown-m2o',
			special: ['m2o'],
			note: 'Übergeordneter Termin (z.B. Schützenfest)'
		},
		schema: { is_nullable: true }
	});
	await safeCreateRelation({
		collection: 'events',
		field: 'parent',
		related_collection: 'events',
		meta: { one_field: null, sort_field: null }
	});

	// events.user_created -> directus_users (M2O, auto-tracked)
	await safeCreateRelation({
		collection: 'events',
		field: 'user_created',
		related_collection: 'directus_users'
	});

	console.log('');
	console.log('=== Schema setup complete! ===');
	console.log('');
	console.log('Next steps:');
	console.log('  1. Configure a static token for API access');
	console.log('  2. Set up public read permissions');
	console.log('  3. Import seed data');
}

main().catch((err) => {
	console.error('FATAL:', err);
	process.exit(1);
});
