import { error } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { getEventBySlug, getSubEvents } from '$lib/server/directus';

export const load: PageServerLoad = async ({ params }) => {
	const year = Number(params.year);
	if (isNaN(year)) {
		throw error(404, 'Termin nicht gefunden');
	}

	const event = await getEventBySlug(params.slug, year);

	if (!event) {
		throw error(404, 'Termin nicht gefunden');
	}

	// Load sub-events if this is a parent event
	const subEvents = await getSubEvents(event.id);

	return { event, subEvents };
};
