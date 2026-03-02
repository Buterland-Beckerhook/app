import { env } from '$env/dynamic/private';
import { createDirectus, rest, staticToken, readItems, readItem } from '@directus/sdk';
import type { Schema } from '$lib/types';

function getEnv(key: string): string {
	const value = env[key];
	if (!value) {
		throw new Error(`Missing required environment variable: ${key}`);
	}
	return value;
}

function createClient() {
	return createDirectus<Schema>(getEnv('DIRECTUS_URL'))
		.with(staticToken(getEnv('DIRECTUS_TOKEN')))
		.with(rest());
}

const directus = createClient();

export { directus, readItems, readItem };
