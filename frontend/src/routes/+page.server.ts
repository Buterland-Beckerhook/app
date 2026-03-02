import type { PageServerLoad } from './$types';
import {
	getArticles,
	getNextEvent,
	getCurrentThrone,
	getCurrentThroneArticle
} from '$lib/server/directus';

export const load: PageServerLoad = async () => {
	const [{ articles }, nextEvent, currentThrone, currentThroneArticle] = await Promise.all([
		getArticles(1, 3),
		getNextEvent(),
		getCurrentThrone(),
		getCurrentThroneArticle()
	]);

	return {
		articles,
		nextEvent,
		currentThrone,
		currentThroneArticle
	};
};
