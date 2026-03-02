import type { PageServerLoad } from './$types';
import { getEvents } from '$lib/server/directus';

export const load: PageServerLoad = async ({ url }) => {
	const yearParam = url.searchParams.get('jahr');
	const year = yearParam ? Number(yearParam) : new Date().getFullYear();
	const events = await getEvents(year);

	return {
		events,
		year
	};
};
