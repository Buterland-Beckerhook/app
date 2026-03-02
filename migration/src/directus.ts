/**
 * Shared Directus API helper for migration scripts.
 *
 * Reads DIRECTUS_URL and DIRECTUS_TOKEN from environment or uses defaults.
 */

import { extname } from 'node:path';

const DIRECTUS_URL = process.env.DIRECTUS_URL ?? 'http://localhost:8055';
const DIRECTUS_TOKEN = process.env.DIRECTUS_TOKEN ?? 'dev-static-token-change-in-production';

/** Map file extensions to MIME types for image uploads. */
const MIME_TYPES: Record<string, string> = {
	'.jpg': 'image/jpeg',
	'.jpeg': 'image/jpeg',
	'.png': 'image/png',
	'.gif': 'image/gif',
	'.webp': 'image/webp',
	'.svg': 'image/svg+xml',
	'.avif': 'image/avif',
	'.bmp': 'image/bmp',
	'.tiff': 'image/tiff',
	'.tif': 'image/tiff',
	'.pdf': 'application/pdf'
};

/** Get MIME type from file extension. Falls back to application/octet-stream. */
function getMimeType(filePath: string): string {
	const ext = extname(filePath).toLowerCase();
	return MIME_TYPES[ext] ?? 'application/octet-stream';
}

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
	const { readFileSync } = await import('node:fs');
	const { basename } = await import('node:path');

	const fileName = basename(filePath);
	const mimeType = getMimeType(filePath);
	const fileBuffer = readFileSync(filePath);

	const blob = new Blob([fileBuffer], { type: mimeType });

	const form = new FormData();
	// Metadata fields must come BEFORE the file field for Directus to process them
	if (title) form.append('title', title);
	if (folder) form.append('folder', folder);
	form.append('file', blob, fileName);

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

// ---------------------------------------------------------------------------
// Folder management
// ---------------------------------------------------------------------------

/** Cache of folder name → folder ID to avoid redundant lookups. */
const folderCache = new Map<string, string>();

/** Get or create a folder by name. Returns the folder ID. */
export async function getOrCreateFolder(name: string): Promise<string> {
	// Check cache first
	const cached = folderCache.get(name);
	if (cached) return cached;

	// Check if folder already exists
	const res = await fetch(
		`${DIRECTUS_URL}/folders?filter[name][_eq]=${encodeURIComponent(name)}&limit=1`,
		{ headers: { Authorization: `Bearer ${DIRECTUS_TOKEN}` } }
	);
	if (res.ok) {
		const json = (await res.json()) as { data: DirectusItem[] };
		if (json.data.length > 0) {
			const id = json.data[0].id as string;
			folderCache.set(name, id);
			return id;
		}
	}

	// Create the folder
	const createRes = await fetch(`${DIRECTUS_URL}/folders`, {
		method: 'POST',
		headers: {
			Authorization: `Bearer ${DIRECTUS_TOKEN}`,
			'Content-Type': 'application/json'
		},
		body: JSON.stringify({ name })
	});

	if (!createRes.ok) {
		const body = await createRes.text();
		throw new Error(`POST /folders failed (${createRes.status}): ${body}`);
	}

	const createJson = (await createRes.json()) as { data: DirectusItem };
	const id = createJson.data.id as string;
	folderCache.set(name, id);
	return id;
}

/** Delete all folders from Directus. */
export async function deleteAllFolders(): Promise<number> {
	const res = await fetch(`${DIRECTUS_URL}/folders?limit=-1&fields=id`, {
		headers: { Authorization: `Bearer ${DIRECTUS_TOKEN}` }
	});
	if (!res.ok) return 0;
	const json = (await res.json()) as { data: DirectusItem[] };
	if (json.data.length === 0) return 0;

	const ids = json.data.map((f) => f.id);
	const delRes = await fetch(`${DIRECTUS_URL}/folders`, {
		method: 'DELETE',
		headers: {
			Authorization: `Bearer ${DIRECTUS_TOKEN}`,
			'Content-Type': 'application/json'
		},
		body: JSON.stringify(ids)
	});

	if (!delRes.ok) {
		const body = await delRes.text();
		throw new Error(`DELETE /folders failed (${delRes.status}): ${body}`);
	}

	// Clear cache
	folderCache.clear();
	return json.data.length;
}

export { DIRECTUS_URL };
