import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { getArticleBySlug, getArticleYear } from '$lib/server/directus';

export const load: PageServerLoad = async ({ params }) => {
	const year = Number(params.year);
	if (isNaN(year)) {
		throw error(404, 'Artikel nicht gefunden');
	}

	const article = await getArticleBySlug(params.slug);

	if (!article) {
		throw error(404, 'Artikel nicht gefunden');
	}

	// Validate that the year in the URL matches the article's publish year
	if (getArticleYear(article) !== year) {
		throw error(404, 'Artikel nicht gefunden');
	}

	return { article };
};
