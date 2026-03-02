import type { PageServerLoad } from './$types';
import {
	getArticles,
	getNextEvent,
	getCurrentThrone,
	getCurrentThroneArticle
} from '$lib/server/mock-data';

export const load: PageServerLoad = async () => {
	const { articles } = getArticles(1, 3);
	const nextEvent = getNextEvent();
	const currentThrone = getCurrentThrone();
	const currentThroneArticle = getCurrentThroneArticle();

	return {
		articles,
		nextEvent,
		currentThrone,
		currentThroneArticle
	};
};
