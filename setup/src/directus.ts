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
