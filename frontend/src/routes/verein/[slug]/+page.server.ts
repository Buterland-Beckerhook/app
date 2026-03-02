import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { getPage, getPeople } from '$lib/server/mock-data';

export const load: PageServerLoad = async ({ params }) => {
	const page = getPage(params.slug);

	if (!page) {
		throw error(404, 'Seite nicht gefunden');
	}

	// Load people data for vorstand/offiziere pages
	const people =
		params.slug === 'vorstand' || params.slug === 'offiziere' ? getPeople(params.slug) : undefined;

	return { page, people };
};
