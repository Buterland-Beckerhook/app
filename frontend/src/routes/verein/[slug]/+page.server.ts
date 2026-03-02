import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { getPage, getPeople } from '$lib/server/directus';

export const load: PageServerLoad = async ({ params }) => {
	const page = await getPage(params.slug);

	if (!page) {
		throw error(404, 'Seite nicht gefunden');
	}

	// Load people data for vorstand/offiziere pages
	const people =
		params.slug === 'vorstand' || params.slug === 'offiziere'
			? await getPeople(params.slug)
			: undefined;

	return { page, people };
};
