import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { getArticleBySlug } from '$lib/server/mock-data';

export const load: PageServerLoad = async ({ params }) => {
	const article = getArticleBySlug(params.slug);

	if (!article) {
		throw error(404, 'Artikel nicht gefunden');
	}

	return { article };
};
