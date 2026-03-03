import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { getArticleBySlug } from '$lib/server/directus';

export const load: PageServerLoad = async ({ params }) => {
	const year = Number(params.year);
	if (isNaN(year)) {
		throw error(404, 'Artikel nicht gefunden');
	}

	const article = await getArticleBySlug(params.slug, year);

	if (!article) {
		throw error(404, 'Artikel nicht gefunden');
	}

	return { article };
};
