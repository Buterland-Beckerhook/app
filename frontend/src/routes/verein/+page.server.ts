import type { PageServerLoad } from './$types';
import { getPage, getVereinPages } from '$lib/server/directus';

export const load: PageServerLoad = async () => {
	const [page, allPages] = await Promise.all([getPage('ueber-uns'), getVereinPages()]);
	const subPages = allPages.filter((p) => p.slug !== 'ueber-uns');

	return {
		page,
		subPages
	};
};
