import type { PageServerLoad } from './$types';
import { getArticles, getNextEvent, getCurrentThrone } from '$lib/server/mock-data';

export const load: PageServerLoad = async () => {
	const { articles } = getArticles(1, 3);
	const nextEvent = getNextEvent();
	const currentThrone = getCurrentThrone();

	return {
		articles,
		nextEvent,
		currentThrone
	};
};
