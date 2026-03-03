/**
 * Erstellt Datenbank-Trigger, Indizes und Constraints, die über die Directus-API
 * nicht möglich sind. Alle Operationen sind idempotent (IF NOT EXISTS / DO $$).
 *
 * === Trigger ===
 *
 * Articles:
 *   - articles_set_year(): Setzt articles.year automatisch aus date_published
 *   - Trigger: BEFORE INSERT OR UPDATE OF date_published
 *
 * Events:
 *   - events_set_year(): Setzt events.year automatisch aus start
 *   - Trigger: BEFORE INSERT OR UPDATE OF start
 *
 * === Unique Indizes ===
 *
 *   - articles_slug_year_unique: Composite auf articles (slug, year)
 *   - events_slug_year_unique:   Composite auf events (slug, year)
 *
 * === CHECK Constraints (Datenintegrität) ===
 *
 *   - events_end_after_start:    events.end >= events.start (oder NULL)
 *   - thrones_end_after_begin:   thrones.end >= thrones.begin (oder NULL)
 *   - thrones_begin_positive:    thrones.begin > 0
 *   - articles_year_range:       articles.year >= 1900
 *   - events_year_range:         events.year >= 1900
 *   - people_sort_order_nonneg:  people.sort_order >= 0
 *
 * === Performance Indizes (B-Tree) ===
 *
 *   - articles_status_date_pub_idx:       (status, date_published DESC)
 *   - articles_status_slug_year_idx:      (status, slug, year)
 *   - events_status_announce_start_idx:   (status, announce, start)
 *   - events_status_slug_year_idx:        (status, slug, year)
 *   - events_parent_idx:                  (parent)
 *   - pages_status_slug_idx:              (status, slug)
 *   - thrones_type_begin_idx:             (type, begin DESC)
 *   - people_group_sort_idx:              (group, sort_order)
 *
 * Voraussetzung: Die Collections müssen bereits existieren (setup:schema).
 *
 * Umgebungsvariablen:
 *   DB_HOST      (default: localhost)
 *   DB_PORT      (default: 5432)
 *   DB_DATABASE  (default: directus)
 *   DB_USER      (default: directus)
 *   DB_PASSWORD  (default: directus)
 */

import pg from 'pg';

const { Client } = pg;

const DB_HOST = process.env.DB_HOST ?? 'localhost';
const DB_PORT = Number(process.env.DB_PORT ?? '5432');
const DB_DATABASE = process.env.DB_DATABASE ?? 'directus';
const DB_USER = process.env.DB_USER ?? 'directus';
const DB_PASSWORD = process.env.DB_PASSWORD ?? 'directus';

async function main(): Promise<void> {
	console.log('=== Datenbank-Trigger & Indizes erstellen ===');
	console.log(`PostgreSQL: ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_DATABASE}`);
	console.log('');

	const client = new Client({
		host: DB_HOST,
		port: DB_PORT,
		database: DB_DATABASE,
		user: DB_USER,
		password: DB_PASSWORD
	});

	try {
		await client.connect();
		console.log('Verbunden.');

		// 1. Trigger-Funktion: year aus date_published ableiten
		console.log('');
		console.log('--- Trigger: articles_set_year ---');

		const triggerFnSql = `
			CREATE OR REPLACE FUNCTION articles_set_year()
			RETURNS TRIGGER AS $$
			BEGIN
				NEW.year := EXTRACT(YEAR FROM NEW.date_published)::integer;
				RETURN NEW;
			END;
			$$ LANGUAGE plpgsql;
		`;
		await client.query(triggerFnSql);
		console.log('  OK: Funktion articles_set_year() erstellt.');

		// Trigger auf INSERT und UPDATE von date_published
		// DROP + CREATE da CREATE OR REPLACE für Trigger erst ab PG 14 geht
		const triggerSql = `
			DROP TRIGGER IF EXISTS trg_articles_set_year ON articles;
			CREATE TRIGGER trg_articles_set_year
				BEFORE INSERT OR UPDATE OF date_published
				ON articles
				FOR EACH ROW
				EXECUTE FUNCTION articles_set_year();
		`;
		await client.query(triggerSql);
		console.log('  OK: Trigger trg_articles_set_year erstellt (BEFORE INSERT OR UPDATE).');

		// 2. Composite Unique Index: slug + year
		console.log('');
		console.log('--- Index: articles_slug_year_unique ---');

		const indexSql = `
			CREATE UNIQUE INDEX IF NOT EXISTS articles_slug_year_unique
			ON articles (slug, year);
		`;
		await client.query(indexSql);
		console.log('  OK: Unique Index articles_slug_year_unique erstellt (oder existierte bereits).');

		// 3. Bestehende Artikel: year nachträglich befüllen (falls Daten vor dem Trigger existieren)
		console.log('');
		console.log('--- Bestehende Artikel: year aktualisieren ---');

		const updateResult = await client.query(`
			UPDATE articles
			SET year = EXTRACT(YEAR FROM date_published)::integer
			WHERE year IS NULL OR year != EXTRACT(YEAR FROM date_published)::integer;
		`);
		console.log(`  OK: ${updateResult.rowCount} Artikel aktualisiert.`);

		// =====================================================================
		// Events: Trigger + Unique Index (analog zu Articles)
		// =====================================================================

		// 4. Trigger-Funktion: year aus start ableiten
		console.log('');
		console.log('--- Trigger: events_set_year ---');

		const eventsTriggerFnSql = `
			CREATE OR REPLACE FUNCTION events_set_year()
			RETURNS TRIGGER AS $$
			BEGIN
				NEW.year := EXTRACT(YEAR FROM NEW.start)::integer;
				RETURN NEW;
			END;
			$$ LANGUAGE plpgsql;
		`;
		await client.query(eventsTriggerFnSql);
		console.log('  OK: Funktion events_set_year() erstellt.');

		// Trigger auf INSERT und UPDATE von start
		const eventsTriggerSql = `
			DROP TRIGGER IF EXISTS trg_events_set_year ON events;
			CREATE TRIGGER trg_events_set_year
				BEFORE INSERT OR UPDATE OF start
				ON events
				FOR EACH ROW
				EXECUTE FUNCTION events_set_year();
		`;
		await client.query(eventsTriggerSql);
		console.log('  OK: Trigger trg_events_set_year erstellt (BEFORE INSERT OR UPDATE).');

		// 5. Composite Unique Index: slug + year
		console.log('');
		console.log('--- Index: events_slug_year_unique ---');

		// Drop old unique constraint on slug alone (if it exists — Directus creates this
		// when schema defines is_unique: true on the slug field)
		try {
			await client.query(`ALTER TABLE events DROP CONSTRAINT IF EXISTS events_slug_unique;`);
		} catch {
			// Constraint may not exist or may be named differently
		}
		try {
			await client.query(`DROP INDEX IF EXISTS events_slug_unique;`);
		} catch {
			// Index may not exist
		}
		console.log('  OK: Alter slug-only Unique-Constraint entfernt (falls vorhanden).');

		const eventsIndexSql = `
			CREATE UNIQUE INDEX IF NOT EXISTS events_slug_year_unique
			ON events (slug, year);
		`;
		await client.query(eventsIndexSql);
		console.log('  OK: Unique Index events_slug_year_unique erstellt (oder existierte bereits).');

		// 6. Bestehende Events: year nachträglich befüllen
		console.log('');
		console.log('--- Bestehende Termine: year aktualisieren ---');

		const eventsUpdateResult = await client.query(`
			UPDATE events
			SET year = EXTRACT(YEAR FROM start)::integer
			WHERE year IS NULL OR year != EXTRACT(YEAR FROM start)::integer;
		`);
		console.log(`  OK: ${eventsUpdateResult.rowCount} Termine aktualisiert.`);

		// =====================================================================
		// CHECK Constraints (Datenintegrität)
		// =====================================================================

		console.log('');
		console.log('=== CHECK Constraints ===');

		const checkConstraints = [
			{
				name: 'events_end_after_start',
				table: 'events',
				check: '"end" IS NULL OR "end" >= start'
			},
			{
				name: 'thrones_end_after_begin',
				table: 'thrones',
				check: '"end" IS NULL OR "end" >= "begin"'
			},
			{
				name: 'thrones_begin_positive',
				table: 'thrones',
				check: '"begin" > 0'
			},
			{
				name: 'articles_year_range',
				table: 'articles',
				check: 'year >= 1900'
			},
			{
				name: 'events_year_range',
				table: 'events',
				check: 'year >= 1900'
			},
			{
				name: 'people_sort_order_nonneg',
				table: 'people',
				check: 'sort_order >= 0'
			}
		];

		for (const c of checkConstraints) {
			await client.query(`
				DO $$ BEGIN
					IF NOT EXISTS (
						SELECT 1 FROM pg_constraint WHERE conname = '${c.name}'
					) THEN
						ALTER TABLE ${c.table} ADD CONSTRAINT ${c.name} CHECK (${c.check});
					END IF;
				END $$;
			`);
			console.log(`  OK: ${c.name} auf ${c.table}`);
		}

		// =====================================================================
		// Performance Indizes (B-Tree, basierend auf Query-Patterns)
		// =====================================================================

		console.log('');
		console.log('=== Performance Indizes ===');

		const performanceIndexes = [
			{
				name: 'articles_status_date_pub_idx',
				sql: 'CREATE INDEX IF NOT EXISTS articles_status_date_pub_idx ON articles (status, date_published DESC)'
			},
			{
				name: 'articles_status_slug_year_idx',
				sql: 'CREATE INDEX IF NOT EXISTS articles_status_slug_year_idx ON articles (status, slug, year)'
			},
			{
				name: 'events_status_announce_start_idx',
				sql: 'CREATE INDEX IF NOT EXISTS events_status_announce_start_idx ON events (status, announce, start)'
			},
			{
				name: 'events_status_slug_year_idx',
				sql: 'CREATE INDEX IF NOT EXISTS events_status_slug_year_idx ON events (status, slug, year)'
			},
			{
				name: 'events_parent_idx',
				sql: 'CREATE INDEX IF NOT EXISTS events_parent_idx ON events (parent)'
			},
			{
				name: 'pages_status_slug_idx',
				sql: 'CREATE INDEX IF NOT EXISTS pages_status_slug_idx ON pages (status, slug)'
			},
			{
				name: 'thrones_type_begin_idx',
				sql: 'CREATE INDEX IF NOT EXISTS thrones_type_begin_idx ON thrones (type, "begin" DESC)'
			},
			{
				name: 'people_group_sort_idx',
				sql: 'CREATE INDEX IF NOT EXISTS people_group_sort_idx ON people ("group", sort_order)'
			}
		];

		for (const idx of performanceIndexes) {
			await client.query(`${idx.sql};`);
			console.log(`  OK: ${idx.name}`);
		}

		console.log('');
		console.log('Fertig.');
	} finally {
		await client.end();
	}
}

main().catch((err) => {
	console.error('FEHLER:', err);
	process.exit(1);
});
