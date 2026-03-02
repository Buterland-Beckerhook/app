import type { PageServerLoad } from './$types';
import { getArticles } from '$lib/server/mock-data';

const ITEMS_PER_PAGE = 10;

export const load: PageServerLoad = async ({ url }) => {
	const page = Number(url.searchParams.get('seite')) || 1;
	const { articles, total } = getArticles(page, ITEMS_PER_PAGE);
	const totalPages = Math.ceil(total / ITEMS_PER_PAGE);

	return {
		articles,
		page,
		totalPages
	};
};
