/**
 * Shared Directus SDK client for setup scripts.
 *
 * Authenticates via email/password (admin) to get a temporary access token.
 * All setup operations use this authenticated client.
 *
 * Environment / CLI defaults:
 *   DIRECTUS_URL       = http://localhost:8055
 *   ADMIN_EMAIL        = admin@buterland-beckerhook.de
 *   ADMIN_PASSWORD     = directus
 */

import type { AuthenticationClient, DirectusClient, RestClient } from '@directus/sdk';
import { createDirectus, rest, authentication } from '@directus/sdk';

export const DIRECTUS_URL = process.env.DIRECTUS_URL ?? 'http://localhost:8055';
export const ADMIN_EMAIL = process.env.ADMIN_EMAIL ?? 'admin@buterland-beckerhook.de';
export const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD ?? 'directus';

/** Fully typed admin client with authentication + REST. */
export type AdminClient = DirectusClient<object> &
	AuthenticationClient<object> &
	RestClient<object>;

/**
 * Create an authenticated Directus client using admin credentials.
 * Uses email/password login to obtain a temporary access token.
 */
export async function createAdminClient(): Promise<AdminClient> {
	const client = createDirectus(DIRECTUS_URL).with(authentication()).with(rest());

	await client.login({ email: ADMIN_EMAIL, password: ADMIN_PASSWORD });

	return client;
}

/**
 * Helper for raw API calls not covered by the SDK (e.g. /access).
 * Uses the client's current access token.
 */
export async function rawPost(
	client: AdminClient,
	endpoint: string,
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	data: Record<string, any>
): Promise<unknown> {
	const token = await client.getToken();
	const res = await fetch(`${DIRECTUS_URL}${endpoint}`, {
		method: 'POST',
		headers: {
			Authorization: `Bearer ${token}`,
			'Content-Type': 'application/json'
		},
		body: JSON.stringify(data)
	});

	if (!res.ok) {
		const body = await res.text();
		throw new Error(`POST ${endpoint} failed (${res.status}): ${body}`);
	}

	return res.json();
}

/**
 * Helper for raw GET calls not covered by the SDK.
 */
export async function rawGet(client: AdminClient, endpoint: string): Promise<unknown> {
	const token = await client.getToken();
	const res = await fetch(`${DIRECTUS_URL}${endpoint}`, {
		headers: {
			Authorization: `Bearer ${token}`,
			'Content-Type': 'application/json'
		}
	});

	if (!res.ok) {
		const body = await res.text();
		throw new Error(`GET ${endpoint} failed (${res.status}): ${body}`);
	}

	return res.json();
}

/**
 * Helper for raw PATCH calls not covered by the SDK (e.g. /settings).
 */
export async function rawPatch(
	client: AdminClient,
	endpoint: string,
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	data: Record<string, any>
): Promise<unknown> {
	const token = await client.getToken();
	const res = await fetch(`${DIRECTUS_URL}${endpoint}`, {
		method: 'PATCH',
		headers: {
			Authorization: `Bearer ${token}`,
			'Content-Type': 'application/json'
		},
		body: JSON.stringify(data)
	});

	if (!res.ok) {
		const body = await res.text();
		throw new Error(`PATCH ${endpoint} failed (${res.status}): ${body}`);
	}

	return res.json();
}

/** Map file extensions to MIME types for branding assets. */
const MIME_TYPES: Record<string, string> = {
	'.svg': 'image/svg+xml',
	'.ico': 'image/x-icon',
	'.png': 'image/png',
	'.jpg': 'image/jpeg',
	'.jpeg': 'image/jpeg',
	'.webp': 'image/webp'
};

/** Resolve MIME type from file extension, falls back to application/octet-stream. */
function mimeType(filePath: string): string {
	const ext = filePath.slice(filePath.lastIndexOf('.')).toLowerCase();
	return MIME_TYPES[ext] ?? 'application/octet-stream';
}

/**
 * Upload a file to Directus via multipart/form-data.
 * Returns the created file object (including `id`).
 */
export async function uploadFile(
	client: AdminClient,
	filePath: string,
	title: string,
	folder?: string
): Promise<{ id: string }> {
	const fs = await import('node:fs');
	const path = await import('node:path');

	const fileName = path.basename(filePath);
	const fileBuffer = fs.readFileSync(filePath);
	const mime = mimeType(filePath);
	const blob = new Blob([fileBuffer], { type: mime });

	const form = new FormData();
	form.append('title', title);
	form.append('type', mime);
	if (folder) form.append('folder', folder);
	form.append('file', blob, fileName);

	const token = await client.getToken();
	const res = await fetch(`${DIRECTUS_URL}/files`, {
		method: 'POST',
		headers: { Authorization: `Bearer ${token}` },
		body: form
	});

	if (!res.ok) {
		const body = await res.text();
		throw new Error(`File upload failed (${res.status}): ${body}`);
	}

	const json = (await res.json()) as { data: { id: string } };
	return json.data;
}

/**
 * Replace (update) an existing Directus file with new content.
 */
export async function replaceFile(
	client: AdminClient,
	fileId: string,
	filePath: string,
	title: string
): Promise<{ id: string }> {
	const fs = await import('node:fs');
	const path = await import('node:path');

	const fileName = path.basename(filePath);
	const fileBuffer = fs.readFileSync(filePath);
	const mime = mimeType(filePath);
	const blob = new Blob([fileBuffer], { type: mime });

	const form = new FormData();
	form.append('title', title);
	form.append('type', mime);
	form.append('file', blob, fileName);

	const token = await client.getToken();
	const res = await fetch(`${DIRECTUS_URL}/files/${fileId}`, {
		method: 'PATCH',
		headers: { Authorization: `Bearer ${token}` },
		body: form
	});

	if (!res.ok) {
		const body = await res.text();
		throw new Error(`File replace failed (${res.status}): ${body}`);
	}

	const json = (await res.json()) as { data: { id: string } };
	return json.data;
}
