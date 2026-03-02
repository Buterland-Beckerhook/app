import type { PageServerLoad } from './$types';
import { getPage } from '$lib/server/mock-data';

export const load: PageServerLoad = async () => {
	const page = getPage('datenschutz');
	return { page };
};
