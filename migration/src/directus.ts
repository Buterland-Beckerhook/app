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

export { DIRECTUS_URL };
