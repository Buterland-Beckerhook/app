import type { PageServerLoad } from './$types';
import { getPage, getVereinPages } from '$lib/server/mock-data';

export const load: PageServerLoad = async () => {
	const page = getPage('ueber-uns');
	const subPages = getVereinPages().filter((p) => p.slug !== 'ueber-uns');

	return {
		page,
		subPages
	};
};
