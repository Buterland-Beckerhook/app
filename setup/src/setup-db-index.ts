/**
 * Erstellt Datenbank-Indizes, die über die Directus-API nicht möglich sind.
 *
 * Aktuell:
 *   - Composite Unique Index auf articles (slug, Jahr aus date_published)
 *     Damit darf derselbe Slug in verschiedenen Jahren vorkommen,
 *     aber nicht zweimal im selben Jahr.
 *
 * Voraussetzung: Die articles-Collection muss bereits existieren (setup:schema).
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
	console.log('=== Datenbank-Indizes erstellen ===');
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

		// Composite Unique Index: slug + Jahr (aus date_published)
		// Erlaubt z.B. slug "schuetzenfest" in 2022 und 2023, aber nicht zweimal in 2023.
		const indexName = 'articles_slug_year_unique';
		const sql = `
			CREATE UNIQUE INDEX IF NOT EXISTS ${indexName}
			ON articles (slug, EXTRACT(YEAR FROM date_published));
		`;

		console.log(`Erstelle Index: ${indexName} ...`);
		await client.query(sql);
		console.log(`  OK: ${indexName} erstellt (oder existierte bereits).`);

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
