/**
 * Shared Directus API helper for migration scripts.
 *
 * Reads DIRECTUS_URL and DIRECTUS_TOKEN from environment or uses defaults.
 */

const DIRECTUS_URL = process.env.DIRECTUS_URL ?? 'http://localhost:8055';
const DIRECTUS_TOKEN = process.env.DIRECTUS_TOKEN ?? 'dev-static-token-change-in-production';

export interface DirectusItem {
	id?: string;
	[key: string]: unknown;
}

/** POST a single item to a collection. Returns the created item. */
export async function createItem(
	collection: string,
	data: DirectusItem
): Promise<DirectusItem> {
	const res = await fetch(`${DIRECTUS_URL}/items/${collection}`, {
		method: 'POST',
		headers: {
			Authorization: `Bearer ${DIRECTUS_TOKEN}`,
			'Content-Type': 'application/json'
		},
		body: JSON.stringify(data)
	});

	if (!res.ok) {
		const body = await res.text();
		throw new Error(`POST /items/${collection} failed (${res.status}): ${body}`);
	}

	const json = (await res.json()) as { data: DirectusItem };
	return json.data;
}

/** Read all items from a collection matching optional filters. */
export async function readItems(
	collection: string,
	params?: Record<string, string>
): Promise<DirectusItem[]> {
	const query = params ? '?' + new URLSearchParams(params).toString() : '';
	const res = await fetch(`${DIRECTUS_URL}/items/${collection}${query}`, {
		headers: { Authorization: `Bearer ${DIRECTUS_TOKEN}` }
	});

	if (!res.ok) {
		const body = await res.text();
		throw new Error(`GET /items/${collection} failed (${res.status}): ${body}`);
	}

	const json = (await res.json()) as { data: DirectusItem[] };
	return json.data;
}

/** Delete all items from a collection. Useful for re-running imports. */
export async function deleteAllItems(collection: string): Promise<number> {
	const items = await readItems(collection, { limit: '-1', fields: 'id' });
	if (items.length === 0) return 0;

	const ids = items.map((i) => i.id);
	const res = await fetch(`${DIRECTUS_URL}/items/${collection}`, {
		method: 'DELETE',
		headers: {
			Authorization: `Bearer ${DIRECTUS_TOKEN}`,
			'Content-Type': 'application/json'
		},
		body: JSON.stringify(ids)
	});

	if (!res.ok) {
		const body = await res.text();
		throw new Error(`DELETE /items/${collection} failed (${res.status}): ${body}`);
	}

	return items.length;
}

/** Upload a file to Directus. Returns the file item (with id). */
export async function uploadFile(
	filePath: string,
	title?: string,
	folder?: string
): Promise<DirectusItem> {
	const { createReadStream } = await import('node:fs');
	const { basename } = await import('node:path');
	const { Readable } = await import('node:stream');

	const fileName = basename(filePath);
	const stream = createReadStream(filePath);

	// Node 22 supports FormData + Blob natively
	const chunks: Buffer[] = [];
	for await (const chunk of Readable.toWeb(stream) as ReadableStream<Uint8Array>) {
		chunks.push(Buffer.from(chunk));
	}
	const fileBuffer = Buffer.concat(chunks);
	const blob = new Blob([fileBuffer]);

	const form = new FormData();
	form.append('file', blob, fileName);
	if (title) form.append('title', title);
	if (folder) form.append('folder', folder);

	const res = await fetch(`${DIRECTUS_URL}/files`, {
		method: 'POST',
		headers: { Authorization: `Bearer ${DIRECTUS_TOKEN}` },
		body: form
	});

	if (!res.ok) {
		const body = await res.text();
		throw new Error(`POST /files failed (${res.status}): ${body}`);
	}

	const json = (await res.json()) as { data: DirectusItem };
	return json.data;
}

/** Delete all files from Directus. */
export async function deleteAllFiles(): Promise<number> {
	const res = await fetch(`${DIRECTUS_URL}/files?limit=-1&fields=id`, {
		headers: { Authorization: `Bearer ${DIRECTUS_TOKEN}` }
	});
	if (!res.ok) return 0;
	const json = (await res.json()) as { data: DirectusItem[] };
	if (json.data.length === 0) return 0;

	const ids = json.data.map((f) => f.id);
	const delRes = await fetch(`${DIRECTUS_URL}/files`, {
		method: 'DELETE',
		headers: {
			Authorization: `Bearer ${DIRECTUS_TOKEN}`,
			'Content-Type': 'application/json'
		},
		body: JSON.stringify(ids)
	});

	if (!delRes.ok) {
		const body = await delRes.text();
		throw new Error(`DELETE /files failed (${delRes.status}): ${body}`);
	}

	return json.data.length;
}

export { DIRECTUS_URL };
