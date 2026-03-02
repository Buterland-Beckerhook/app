import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { getEventBySlug } from '$lib/server/mock-data';

export const load: PageServerLoad = async ({ params }) => {
	const event = getEventBySlug(params.slug);

	if (!event) {
		throw error(404, 'Termin nicht gefunden');
	}

	return { event };
};
