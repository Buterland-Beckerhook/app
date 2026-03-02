import type { PageServerLoad } from './$types';
import { getThroneArticles } from '$lib/server/mock-data';

export const load: PageServerLoad = async () => {
	const articles = getThroneArticles();

	return { articles };
};
