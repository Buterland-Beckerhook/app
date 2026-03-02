import type { PageServerLoad } from './$types';
import { getPaginatedThrones } from '$lib/server/mock-data';

export const load: PageServerLoad = async ({ url }) => {
	const pageParam = Number(url.searchParams.get('seite')) || 1;
	const { articles, total, page, totalPages } = getPaginatedThrones(pageParam, 1);

	return { articles, total, page, totalPages };
};
