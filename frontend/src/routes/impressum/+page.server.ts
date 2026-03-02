import type { PageServerLoad } from './$types';
import { getPage } from '$lib/server/directus';

export const load: PageServerLoad = async () => {
	const page = await getPage('impressum');
	return { page };
};
