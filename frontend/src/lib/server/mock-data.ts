// =============================================================================
// Mock data for development without Directus
// Replace with real Directus calls later
// =============================================================================

import type { Article, ArticleImage, Event, Location, Throne, Person, Page } from '$lib/types';

// --- Mock image helper ---
// Uses picsum.photos with fixed seeds for consistent placeholder images

function mockImage(
	id: string,
	articleId: string,
	seed: number,
	logicalName: string,
	title: string,
	sort: number
): ArticleImage {
	return {
		id,
		article: articleId,
		image: {
			id: `file-${id}`,
			title,
			filename_download: `${logicalName}.jpg`,
			type: 'image/jpeg',
			width: 1200,
			height: 800
		},
		logical_name: logicalName,
		title,
		copyright: 'Beispielfoto (picsum.photos)',
		sort
	};
}

/** Build a picsum URL for a mock image. Seed ensures the same photo each time. */
export function getMockImageUrl(imageId: string, width = 800, height = 533): string {
	// Extract numeric seed from image id (e.g., 'img-1-1' -> 11)
	const seed = imageId.split('-').filter(Number).join('');
	return `https://picsum.photos/seed/${seed}/${width}/${height}`;
}

// --- Locations ---

export const mockLocations: Location[] = [
	{
		id: 'loc-1',
		key: 'platz',
		name: 'Schützenplatz Beckerhook',
		street: 'Beckerhook 50',
		zip: '48683',
		city: 'Ahaus',
		lat: 52.095,
		lng: 7.035,
		maps_url: 'https://maps.google.com/?q=52.095,7.035'
	},
	{
		id: 'loc-2',
		key: 'dinkelhof',
		name: 'Dinkelhof',
		street: 'Beckerhook 12',
		zip: '48683',
		city: 'Ahaus',
		lat: 52.093,
		lng: 7.032,
		maps_url: null
	},
	{
		id: 'loc-3',
		key: 'none',
		name: 'Ohne Ortsangabe',
		street: null,
		zip: null,
		city: null,
		lat: null,
		lng: null,
		maps_url: null
	}
];

// --- Thrones ---

export const mockThrones: Throne[] = [
	{
		id: 'throne-1',
		article: 'art-1',
		type: 'thron',
		years: '2024-2025',
		king_title: 'Markus I.',
		king: 'Markus Mustermann',
		queen: 'Sabine Musterfrau',
		moh1: 'Anna Beispiel',
		moh2: 'Lisa Testerin',
		loh1: 'Peter Testmann',
		loh2: 'Klaus Beispielmann',
		cupbearer: 'Frank Mundschenk',
		courtmarshal: 'Heinz Hofmarschall'
	},
	{
		id: 'throne-2',
		article: 'art-2',
		type: 'thron',
		years: '2023-2024',
		king_title: 'Stefan II.',
		king: 'Stefan Beckermann',
		queen: 'Maria Beckermann',
		moh1: 'Petra Schulte',
		moh2: 'Claudia Berger',
		loh1: 'Thomas Schulte',
		loh2: 'Martin Berger',
		cupbearer: 'Ralf Diener',
		courtmarshal: 'Werner Ordnung'
	},
	{
		id: 'throne-3',
		article: 'art-6',
		type: 'kaiserthron',
		years: '2022-2025',
		king_title: 'Gerd X.',
		king: 'Gerd Kaiserlich',
		queen: 'Helga Kaiserlich',
		moh1: 'Ute Kaiser',
		moh2: 'Renate Kaiser',
		loh1: 'Friedrich Kaiser',
		loh2: 'Wilhelm Kaiser',
		cupbearer: 'Otto Schenk',
		courtmarshal: 'Ludwig Marschall'
	}
];

// --- Articles ---

export const mockArticles: Article[] = [
	{
		id: 'art-1',
		status: 'published',
		title: 'Markus Mustermann regiert Buterland-Beckerhook',
		subtitle: 'Neuer König mit sicherem Schuss',
		slug: 'markus-mustermann-regiert-2024',
		date_published: '2024-07-15T14:00:00Z',
		author: 'Redaktion',
		tags: ['Thron', 'Schützenfest'],
		body: `<h2>Ein neuer König für Buterland-Beckerhook</h2>
<p>Mit einem sicheren Schuss holte Markus Mustermann den Vogel von der Stange und regiert nun als <strong>Markus I.</strong> gemeinsam mit seiner Königin Sabine den Schützenverein Buterland-Beckerhook.</p>
<p>Bei strahlendem Sonnenschein feierten die Schützenbrüder und ihre Familien ein gelungenes Schützenfest. Nach spannendem Wettstreit fiel der Vogel um 17:23 Uhr.</p>
<h3>Der Hofstaat</h3>
<p>An der Seite des Königspaares stehen die Ehrendamen Anna Beispiel und Lisa Testerin sowie die Ehrenherren Peter Testmann und Klaus Beispielmann. Als Mundschenk fungiert Frank Mundschenk, Oberhofmarschall ist Heinz Hofmarschall.</p>`,
		is_throne_article: true,
		no_article: false,
		aliases: ['/aktuell/2024/markus-mustermann-regiert/'],
		images: [
			mockImage('img-1-1', 'art-1', 101, 'thron', 'Der neue Thron 2024', 1),
			mockImage('img-1-2', 'art-1', 102, 'koenigspaar', 'Das Königspaar', 2),
			mockImage('img-1-3', 'art-1', 103, 'hofstaat', 'Der Hofstaat', 3)
		],
		throne: mockThrones[0]
	},
	{
		id: 'art-2',
		status: 'published',
		title: 'Stefan Beckermann ist neuer Schützenkönig',
		subtitle: null,
		slug: 'stefan-beckermann-schuetzenkoenig-2023',
		date_published: '2023-07-17T14:00:00Z',
		author: 'Redaktion',
		tags: ['Thron', 'Schützenfest'],
		body: `<p>Stefan Beckermann hat beim diesjährigen Schützenfest den Vogel abgeschossen und regiert nun als <strong>Stefan II.</strong> den Schützenverein.</p>`,
		is_throne_article: true,
		no_article: false,
		aliases: null,
		images: [
			mockImage('img-2-1', 'art-2', 201, 'thron', 'Thron 2023', 1),
			mockImage('img-2-2', 'art-2', 202, 'vogelschuss', 'Der Vogelschuss', 2)
		],
		throne: mockThrones[1]
	},
	{
		id: 'art-3',
		status: 'published',
		title: 'Generalversammlung 2024: Vorstand bestätigt',
		subtitle: 'Einstimmige Wiederwahl',
		slug: 'generalversammlung-2024',
		date_published: '2024-03-10T19:00:00Z',
		author: 'Schriftführer',
		tags: ['Verein'],
		body: `<p>Bei der diesjährigen Generalversammlung im Dinkelhof wurde der gesamte Vorstand einstimmig in seinen Ämtern bestätigt.</p>
<p>Der Vorsitzende bedankte sich bei allen Mitgliedern für die geleistete Arbeit und gab einen Ausblick auf die geplanten Aktivitäten im kommenden Jahr.</p>
<h3>Wichtige Beschlüsse</h3>
<ul>
<li>Der Mitgliedsbeitrag bleibt unverändert</li>
<li>Das Schützenfest findet vom 12.-14. Juli statt</li>
<li>Renovierung der Schützenhalle wird geplant</li>
</ul>`,
		is_throne_article: false,
		no_article: false,
		aliases: null,
		images: [
			mockImage('img-3-1', 'art-3', 301, 'versammlung', 'Generalversammlung im Dinkelhof', 1)
		],
		throne: null
	},
	{
		id: 'art-4',
		status: 'published',
		title: 'Winterwanderung durch das Buterland',
		subtitle: null,
		slug: 'winterwanderung-2024',
		date_published: '2024-01-21T10:00:00Z',
		author: null,
		tags: ['Veranstaltung'],
		body: `<p>Trotz frostiger Temperaturen machten sich rund 40 Vereinsmitglieder mit Familien auf den Weg zur traditionellen Winterwanderung durch das Buterland.</p>
<p>Im Anschluss gab es warmen Glühwein und Erbsensuppe im Dinkelhof.</p>`,
		is_throne_article: false,
		no_article: false,
		aliases: null,
		images: [
			mockImage('img-4-1', 'art-4', 401, 'wanderung', 'Winterwanderung 2024', 1),
			mockImage('img-4-2', 'art-4', 402, 'einkehr', 'Einkehr im Dinkelhof', 2)
		],
		throne: null
	},
	{
		id: 'art-5',
		status: 'published',
		title: 'Schützenfest 2024: Das Programm steht',
		subtitle: 'Drei Tage Feiern im Beckerhook',
		slug: 'schuetzenfest-programm-2024',
		date_published: '2024-06-01T12:00:00Z',
		author: 'Redaktion',
		tags: ['Schützenfest'],
		body: `<p>Das Programm für das diesjährige Schützenfest steht fest. Vom 12. bis 14. Juli wird im Beckerhook gefeiert.</p>
<h3>Freitag, 12. Juli</h3>
<p>18:00 Uhr — Antreten und Abmarsch<br>20:00 Uhr — Festball mit DJ</p>
<h3>Samstag, 13. Juli</h3>
<p>14:00 Uhr — Vogelschießen<br>20:00 Uhr — Königsball</p>
<h3>Sonntag, 14. Juli</h3>
<p>10:00 Uhr — Frühschoppen<br>14:00 Uhr — Festumzug</p>`,
		is_throne_article: false,
		no_article: false,
		aliases: null,
		images: [mockImage('img-5-1', 'art-5', 501, 'plakat', 'Plakat Schützenfest 2024', 1)],
		throne: null
	},
	{
		id: 'art-6',
		status: 'published',
		title: 'Gerd Kaiserlich ist Bezirkskönig',
		subtitle: 'Kaiserthron für Buterland-Beckerhook',
		slug: 'gerd-kaiserlich-bezirkskoenig',
		date_published: '2022-09-10T15:00:00Z',
		author: 'Redaktion',
		tags: ['Thron', 'Kaiserthron'],
		body: `<p>Gerd Kaiserlich hat beim Bezirksschützenfest den Vogel geholt und regiert nun als Kaiser <strong>Gerd X.</strong> den Schützenbezirk.</p>`,
		is_throne_article: true,
		no_article: false,
		aliases: null,
		images: [
			mockImage('img-6-1', 'art-6', 601, 'kaiserthron', 'Der Kaiserthron', 1),
			mockImage('img-6-2', 'art-6', 602, 'kaiserkoenigspaar', 'Das Kaiserpaar', 2)
		],
		throne: mockThrones[2]
	}
];

// --- Events ---

export const mockEvents: Event[] = [
	{
		id: 'evt-1',
		status: 'published',
		title: 'Schützenfest 2025',
		slug: 'schuetzenfest-2025',
		start: '2025-07-11T18:00:00Z',
		end: '2025-07-13T23:00:00Z',
		location: mockLocations[0],
		body: '<p>Unser traditionelles Schützenfest im Beckerhook. Drei Tage Programm mit Vogelschießen, Festumzug und Königsball.</p>',
		cancel_reason: null,
		announce: true,
		revision: 1,
		enable_ical: true
	},
	{
		id: 'evt-2',
		status: 'published',
		title: 'Generalversammlung 2025',
		slug: 'generalversammlung-2025',
		start: '2025-03-08T19:00:00Z',
		end: null,
		location: mockLocations[1],
		body: '<p>Ordentliche Generalversammlung des Schützenvereins. Alle Mitglieder sind herzlich eingeladen.</p>',
		cancel_reason: null,
		announce: true,
		revision: 1,
		enable_ical: true
	},
	{
		id: 'evt-3',
		status: 'published',
		title: 'Winterwanderung 2025',
		slug: 'winterwanderung-2025',
		start: '2025-01-19T10:00:00Z',
		end: null,
		location: mockLocations[0],
		body: '<p>Gemeinsame Wanderung durch das Buterland mit anschließendem Grünkohlessen.</p>',
		cancel_reason: null,
		announce: true,
		revision: 1,
		enable_ical: true
	},
	{
		id: 'evt-4',
		status: 'canceled',
		title: 'Osterfeuer 2025',
		slug: 'osterfeuer-2025',
		start: '2025-04-19T18:00:00Z',
		end: null,
		location: mockLocations[0],
		body: '<p>Traditionelles Osterfeuer auf dem Schützenplatz.</p>',
		cancel_reason: 'Wegen anhaltender Trockenheit und Waldbrandgefahr abgesagt.',
		announce: true,
		revision: 2,
		enable_ical: false
	},
	{
		id: 'evt-5',
		status: 'published',
		title: 'Herbstfest 2025',
		slug: 'herbstfest-2025',
		start: '2025-10-04T15:00:00Z',
		end: '2025-10-04T23:00:00Z',
		location: mockLocations[1],
		body: '<p>Gemütlicher Nachmittag mit Kaffee und Kuchen, abends Live-Musik.</p>',
		cancel_reason: null,
		announce: true,
		revision: 1,
		enable_ical: true
	},
	{
		id: 'evt-6',
		status: 'published',
		title: 'Generalversammlung 2026',
		slug: 'generalversammlung-2026',
		start: '2026-03-14T19:00:00Z',
		end: null,
		location: mockLocations[1],
		body: '<p>Ordentliche Generalversammlung des Schützenvereins. Alle Mitglieder sind herzlich eingeladen.</p>',
		cancel_reason: null,
		announce: true,
		revision: 1,
		enable_ical: true
	},
	{
		id: 'evt-7',
		status: 'published',
		title: 'Osterfeuer 2026',
		slug: 'osterfeuer-2026',
		start: '2026-04-04T18:00:00Z',
		end: null,
		location: mockLocations[0],
		body: '<p>Traditionelles Osterfeuer auf dem Schützenplatz. Für Getränke und Würstchen ist gesorgt.</p>',
		cancel_reason: null,
		announce: true,
		revision: 1,
		enable_ical: true
	},
	{
		id: 'evt-8',
		status: 'published',
		title: 'Schützenfest 2026',
		slug: 'schuetzenfest-2026',
		start: '2026-07-10T18:00:00Z',
		end: '2026-07-12T23:00:00Z',
		location: mockLocations[0],
		body: '<p>Unser traditionelles Schützenfest im Beckerhook. Drei Tage Programm mit Vogelschießen, Festumzug und Königsball.</p>',
		cancel_reason: null,
		announce: true,
		revision: 1,
		enable_ical: true
	},
	{
		id: 'evt-9',
		status: 'published',
		title: 'Herbstfest 2026',
		slug: 'herbstfest-2026',
		start: '2026-10-03T15:00:00Z',
		end: '2026-10-03T23:00:00Z',
		location: mockLocations[1],
		body: '<p>Gemütlicher Nachmittag mit Kaffee und Kuchen, abends Live-Musik.</p>',
		cancel_reason: null,
		announce: true,
		revision: 1,
		enable_ical: true
	},
	{
		id: 'evt-10',
		status: 'published',
		title: 'Winterwanderung 2027',
		slug: 'winterwanderung-2027',
		start: '2027-01-17T10:00:00Z',
		end: null,
		location: mockLocations[0],
		body: '<p>Gemeinsame Wanderung durch das Buterland mit anschließendem Grünkohlessen.</p>',
		cancel_reason: null,
		announce: true,
		revision: 1,
		enable_ical: true
	}
];

// --- People ---

export const mockPeople: Person[] = [
	{
		id: 'ppl-1',
		group: 'vorstand',
		role: 'Präsident',
		role_key: 'praesident',
		name: 'Heinrich Vorsitzender',
		street: 'Beckerhook 1',
		city: 'Ahaus',
		sort_order: 1
	},
	{
		id: 'ppl-2',
		group: 'vorstand',
		role: 'Vizepräsident',
		role_key: 'vizepraesident',
		name: 'Karl Stellvertreter',
		street: 'Beckerhook 5',
		city: 'Ahaus',
		sort_order: 2
	},
	{
		id: 'ppl-3',
		group: 'vorstand',
		role: 'Geschäftsführer',
		role_key: 'geschaeftsfuehrer',
		name: 'Werner Ordentlich',
		street: null,
		city: 'Ahaus',
		sort_order: 3
	},
	{
		id: 'ppl-4',
		group: 'vorstand',
		role: 'Schriftführer',
		role_key: 'schriftfuehrer',
		name: 'Hans Protokoll',
		street: null,
		city: 'Ahaus',
		sort_order: 4
	},
	{
		id: 'ppl-5',
		group: 'vorstand',
		role: 'Kassierer',
		role_key: 'kassierer',
		name: 'Franz Finanzen',
		street: null,
		city: 'Ahaus',
		sort_order: 5
	},
	{
		id: 'ppl-6',
		group: 'offiziere',
		role: 'Oberst',
		role_key: 'oberst',
		name: 'Bernhard Kommandeur',
		street: 'Beckerhook 22',
		city: 'Ahaus',
		sort_order: 1
	},
	{
		id: 'ppl-7',
		group: 'offiziere',
		role: 'Major',
		role_key: 'major',
		name: 'Ralf Marschall',
		street: null,
		city: 'Ahaus',
		sort_order: 2
	},
	{
		id: 'ppl-8',
		group: 'offiziere',
		role: 'Hauptmann',
		role_key: 'hauptmann',
		name: 'Dirk Kompanie',
		street: null,
		city: 'Ahaus',
		sort_order: 3
	},
	{
		id: 'ppl-9',
		group: 'offiziere',
		role: 'Adjutant',
		role_key: 'adjutant',
		name: 'Michael Adjutant',
		street: null,
		city: 'Ahaus',
		sort_order: 4
	}
];

// --- Pages ---

export const mockPages: Page[] = [
	{
		id: 'page-1',
		status: 'published',
		title: 'Über uns',
		slug: 'about',
		body: `<h2>Schützenverein Buterland-Beckerhook e.V.</h2>
<p>Der Schützenverein Buterland-Beckerhook e.V. wurde 1925 gegründet und ist einer der traditionsreichsten Vereine in der Gemeinde Ahaus.</p>
<p>Mit rund 200 Mitgliedern pflegen wir das Brauchtum und den Zusammenhalt in unserer Nachbarschaft. Höhepunkt des Vereinsjahres ist das traditionelle Schützenfest im Juli.</p>`,
		parent: null,
		sort_order: 1
	},
	{
		id: 'page-2',
		status: 'published',
		title: 'Vorstand',
		slug: 'vorstand',
		body: '<p>Der Vorstand des Schützenvereins Buterland-Beckerhook e.V. wird alle drei Jahre auf der Generalversammlung gewählt.</p>',
		parent: null,
		sort_order: 2
	},
	{
		id: 'page-3',
		status: 'published',
		title: 'Offiziere',
		slug: 'offiziere',
		body: '<p>Die Offiziere sorgen für den ordnungsgemäßen Ablauf aller Veranstaltungen und repräsentieren den Verein bei externen Anlässen.</p>',
		parent: null,
		sort_order: 3
	},
	{
		id: 'page-4',
		status: 'published',
		title: 'Impressum',
		slug: 'impressum',
		body: `<h2>Angaben gemäß § 5 TMG</h2>
<p>Schützenverein Buterland-Beckerhook e.V.<br>Beckerhook 50<br>48683 Ahaus</p>
<h3>Vertreten durch</h3>
<p>Heinrich Vorsitzender (Präsident)</p>
<h3>Kontakt</h3>
<p>E-Mail: info@buterland-beckerhook.de</p>
<h3>Registereintrag</h3>
<p>Eingetragen im Vereinsregister.<br>Registergericht: Amtsgericht Coesfeld<br>Registernummer: VR XXXXX</p>`,
		parent: null,
		sort_order: 10
	},
	{
		id: 'page-5',
		status: 'published',
		title: 'Datenschutzerklärung',
		slug: 'datenschutz',
		body: `<h2>Datenschutzerklärung</h2>
<h3>1. Datenschutz auf einen Blick</h3>
<p>Die folgenden Hinweise geben einen einfachen Überblick darüber, was mit Ihren personenbezogenen Daten passiert, wenn Sie diese Website besuchen.</p>
<h3>2. Hosting</h3>
<p>Diese Website wird auf einem eigenen Server gehostet. Die Verarbeitung der Daten erfolgt ausschließlich in Deutschland.</p>
<h3>3. Allgemeine Hinweise und Pflichtinformationen</h3>
<p>Die Betreiber dieser Seiten nehmen den Schutz Ihrer persönlichen Daten sehr ernst. Wir behandeln Ihre personenbezogenen Daten vertraulich und entsprechend den gesetzlichen Datenschutzvorschriften sowie dieser Datenschutzerklärung.</p>`,
		parent: null,
		sort_order: 11
	}
];

// --- Helper functions ---

export function getArticles(page = 1, limit = 10): { articles: Article[]; total: number } {
	const published = mockArticles
		.filter((a) => a.status === 'published')
		.sort((a, b) => new Date(b.date_published).getTime() - new Date(a.date_published).getTime());
	const total = published.length;
	const start = (page - 1) * limit;
	return { articles: published.slice(start, start + limit), total };
}

export function getArticleBySlug(slug: string): Article | undefined {
	return mockArticles.find((a) => a.slug === slug && a.status === 'published');
}

export function getEvents(year?: number): Event[] {
	return mockEvents
		.filter((e) => {
			if (e.status === 'draft') return false;
			if (year) return new Date(e.start).getFullYear() === year;
			return true;
		})
		.sort((a, b) => new Date(a.start).getTime() - new Date(b.start).getTime());
}

export function getEventBySlug(slug: string): Event | undefined {
	return mockEvents.find((e) => e.slug === slug && e.status !== 'draft');
}

export function getThrones(): Throne[] {
	return mockThrones.sort((a, b) => b.years.localeCompare(a.years));
}

export function getThroneArticles(): Article[] {
	return mockArticles
		.filter((a) => a.is_throne_article && a.status === 'published')
		.sort((a, b) => new Date(b.date_published).getTime() - new Date(a.date_published).getTime());
}

export function getPeople(group?: 'vorstand' | 'offiziere'): Person[] {
	return mockPeople
		.filter((p) => !group || p.group === group)
		.sort((a, b) => a.sort_order - b.sort_order);
}

export function getPage(slug: string): Page | undefined {
	return mockPages.find((p) => p.slug === slug && p.status === 'published');
}

export function getNextEvent(): Event | undefined {
	const now = new Date();
	return mockEvents
		.filter((e) => e.status === 'published' && new Date(e.start) > now)
		.sort((a, b) => new Date(a.start).getTime() - new Date(b.start).getTime())[0];
}

export function getCurrentThrone(): Throne | undefined {
	return mockThrones
		.filter((t) => t.type === 'thron')
		.sort((a, b) => b.years.localeCompare(a.years))[0];
}

export function getCurrentThroneArticle(): Article | undefined {
	const throne = getCurrentThrone();
	if (!throne) return undefined;
	return mockArticles.find((a) => a.id === throne.article && a.status === 'published');
}
