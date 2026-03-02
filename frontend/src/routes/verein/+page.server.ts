import type { PageServerLoad } from './$types';
import { getPage, getPeople } from '$lib/server/mock-data';

export const load: PageServerLoad = async () => {
	const page = getPage('about');
	const vorstand = getPeople('vorstand');
	const offiziere = getPeople('offiziere');

	return {
		page,
		vorstand,
		offiziere
	};
};
