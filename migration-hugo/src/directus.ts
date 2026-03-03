/**
 * Shared Directus SDK client for Hugo migration scripts.
 *
 * Uses a static token for authentication (set up via setup/setup-permissions.ts).
 * Provides the same function signatures as the previous raw-fetch implementation
 * so import scripts require minimal changes.
 *
 * Environment:
 *   DIRECTUS_URL    (default: http://localhost:8055)
 *   DIRECTUS_TOKEN  (default: dev-static-token-change-in-production)
 */

import { extname, basename } from 'node:path';
import { readFileSync } from 'node:fs';
import {
	createDirectus,
	rest,
	staticToken,
	createItem as sdkCreateItem,
	readItems as sdkReadItems,
	deleteItems as sdkDeleteItems,
	readFiles,
	deleteFiles as sdkDeleteFiles,
	uploadFiles as sdkUploadFiles,
	readFolders,
	createFolder,
	deleteFolders as sdkDeleteFolders
} from '@directus/sdk';

export const DIRECTUS_URL = process.env.DIRECTUS_URL ?? 'http://localhost:8055';
const DIRECTUS_TOKEN = process.env.DIRECTUS_TOKEN ?? 'dev-static-token-change-in-production';

const client = createDirectus(DIRECTUS_URL)
	.with(staticToken(DIRECTUS_TOKEN))
	.with(rest());

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface DirectusItem {
	id?: string;
	[key: string]: unknown;
}

// ---------------------------------------------------------------------------
// MIME types (for file uploads)
// ---------------------------------------------------------------------------

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

function getMimeType(filePath: string): string {
	const ext = extname(filePath).toLowerCase();
	return MIME_TYPES[ext] ?? 'application/octet-stream';
}

// ---------------------------------------------------------------------------
// Item CRUD
// ---------------------------------------------------------------------------

/** POST a single item to a collection. Returns the created item. */
export async function createItem(
	collection: string,
	data: DirectusItem
): Promise<DirectusItem> {
	const result = await client.request(sdkCreateItem(collection as never, data as never));
	return result as DirectusItem;
}

/** Read all items from a collection matching optional filters. */
export async function readItems(
	collection: string,
	params?: Record<string, string>
): Promise<DirectusItem[]> {
	// Convert URL-param-style filters to SDK query object
	const query: Record<string, unknown> = {};

	if (params) {
		if (params.limit) query.limit = params.limit === '-1' ? -1 : Number(params.limit);
		if (params.fields) query.fields = params.fields.split(',');
		if (params.sort) query.sort = params.sort.split(',');

		// Handle filter params like filter[field][_eq]=value
		const filter: Record<string, unknown> = {};
		for (const [key, value] of Object.entries(params)) {
			const match = key.match(/^filter\[(.+?)\]\[(.+?)\]$/);
			if (match) {
				const [, field, op] = match;
				filter[field] = { [op]: value };
			}
		}
		if (Object.keys(filter).length > 0) query.filter = filter;
	}

	const result = await client.request(sdkReadItems(collection as never, query as never));
	return result as DirectusItem[];
}

/** Delete all items from a collection. Useful for re-running imports. */
export async function deleteAllItems(collection: string): Promise<number> {
	const items = await readItems(collection, { limit: '-1', fields: 'id' });
	if (items.length === 0) return 0;

	const ids = items.map((i) => i.id as string);
	await client.request(sdkDeleteItems(collection as never, ids as never));
	return items.length;
}

/** Delete specific items by IDs from a collection. */
export async function deleteItemsByIds(collection: string, ids: string[]): Promise<void> {
	if (ids.length === 0) return;
	await client.request(sdkDeleteItems(collection as never, ids as never));
}

// ---------------------------------------------------------------------------
// File management
// ---------------------------------------------------------------------------

/** Upload a file to Directus. Returns the file item (with id). */
export async function uploadFile(
	filePath: string,
	title?: string,
	folder?: string
): Promise<DirectusItem> {
	const fileName = basename(filePath);
	const mimeType = getMimeType(filePath);
	const fileBuffer = readFileSync(filePath);
	const blob = new Blob([fileBuffer], { type: mimeType });

	const form = new FormData();
	// Metadata fields must come BEFORE the file field for Directus to process them
	if (title) form.append('title', title);
	if (folder) form.append('folder', folder);
	form.append('file', blob, fileName);

	const result = await client.request(sdkUploadFiles(form));
	return result as DirectusItem;
}

/** Delete all files from Directus. */
export async function deleteAllFiles(): Promise<number> {
	const files = await client.request(readFiles({ limit: -1, fields: ['id'] }));
	if (files.length === 0) return 0;

	const ids = files.map((f) => f.id as string);
	await client.request(sdkDeleteFiles(ids));
	return files.length;
}

/** Delete specific files by IDs. */
export async function deleteFilesByIds(ids: string[]): Promise<void> {
	if (ids.length === 0) return;
	await client.request(sdkDeleteFiles(ids));
}

// ---------------------------------------------------------------------------
// Folder management
// ---------------------------------------------------------------------------

const folderCache = new Map<string, string>();

/** Get or create a folder by name. Returns the folder ID. */
export async function getOrCreateFolder(name: string): Promise<string> {
	const cached = folderCache.get(name);
	if (cached) return cached;

	const existing = await client.request(
		readFolders({
			filter: { name: { _eq: name } },
			limit: 1
		})
	);

	if (existing.length > 0) {
		const id = existing[0].id as string;
		folderCache.set(name, id);
		return id;
	}

	const created = await client.request(createFolder({ name }));
	const id = created.id as string;
	folderCache.set(name, id);
	return id;
}

/** Delete all folders from Directus. */
export async function deleteAllFolders(): Promise<number> {
	const folders = await client.request(readFolders({ limit: -1, fields: ['id'] }));
	if (folders.length === 0) return 0;

	const ids = folders.map((f) => f.id as string);
	await client.request(sdkDeleteFolders(ids));
	folderCache.clear();
	return folders.length;
}
