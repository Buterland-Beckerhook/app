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
	sort: number,
	useAsThroneImage = false
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
		sort,
		use_as_throne_picture: useAsThroneImage
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
		maps_url: 'https://maps.google.com/?q=52.095,7.035',
		url: null
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
		maps_url: null,
		url: null
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
		maps_url: null,
		url: null
	}
];

// --- Thrones ---

export const mockThrones: Throne[] = [
	{
		id: 'throne-1',
		article: 'art-1',
		type: 'koenig',
		begin: 2024,
		end: 2025,
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
		type: 'koenig',
		begin: 2023,
		end: 2024,
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
		article: 'art-7',
		type: 'koenig',
		begin: 2022,
		end: 2023,
		king_title: 'Hermann III.',
		king: 'Hermann Feldmann',
		queen: 'Inge Feldmann',
		moh1: 'Karin Weber',
		moh2: 'Doris Lange',
		loh1: 'Norbert Weber',
		loh2: 'Jürgen Lange',
		cupbearer: 'Willi Schenker',
		courtmarshal: 'Theo Ordner'
	},
	{
		id: 'throne-4',
		article: 'art-8',
		type: 'koenig',
		begin: 2021,
		end: 2022,
		king_title: 'Andreas I.',
		king: 'Andreas Brinkmann',
		queen: 'Heike Brinkmann',
		moh1: 'Silvia Tepper',
		moh2: 'Monika Böhm',
		loh1: 'Bernd Tepper',
		loh2: 'Georg Böhm',
		cupbearer: 'Uwe Zapfer',
		courtmarshal: 'Lothar Stab'
	},
	{
		id: 'throne-5',
		article: 'art-9',
		type: 'koenig',
		begin: 2019,
		end: 2021,
		king_title: 'Dieter IV.',
		king: 'Dieter Ahlert',
		queen: 'Brigitte Ahlert',
		moh1: 'Elfriede Rosen',
		moh2: 'Gisela Kamp',
		loh1: 'Herbert Rosen',
		loh2: 'Manfred Kamp',
		cupbearer: 'Rudolf Krug',
		courtmarshal: 'Helmut Wache'
	},
	{
		id: 'throne-6',
		article: 'art-6',
		type: 'kaiser',
		begin: 2009,
		end: 2012,
		king_title: 'Gerd X.',
		king: 'Gerd Kaiserlich',
		queen: 'Helga Kaiserlich',
		moh1: 'Ute Kaiser',
		moh2: 'Renate Kaiser',
		loh1: 'Friedrich Kaiser',
		loh2: 'Wilhelm Kaiser',
		cupbearer: 'Otto Schenk',
		courtmarshal: 'Ludwig Marschall'
	},
	{
		id: 'throne-7',
		article: 'art-10',
		type: 'kaiser',
		begin: 1984,
		end: 1987,
		king_title: 'Heinrich V.',
		king: 'Heinrich Bröker',
		queen: 'Hildegard Bröker',
		moh1: 'Anneliese Hoff',
		moh2: 'Gertrud Sommer',
		loh1: 'Fritz Hoff',
		loh2: 'Walter Sommer',
		cupbearer: 'Karl Kanne',
		courtmarshal: 'Ernst Ordentlich'
	},
	{
		id: 'throne-8',
		article: 'art-11',
		type: 'stadtkaiser',
		begin: 2018,
		end: 2023,
		king_title: 'Werner II.',
		king: 'Werner Stadtmann',
		queen: 'Ursula Stadtmann',
		moh1: 'Christa Urban',
		moh2: 'Margret Kern',
		loh1: 'Reinhold Urban',
		loh2: 'Hubert Kern',
		cupbearer: 'Siegfried Pokal',
		courtmarshal: 'Günter Zeremonie'
	},
	{
		id: 'throne-9',
		article: 'art-12',
		type: 'stadtkaiser',
		begin: 2013,
		end: 2018,
		king_title: 'Paul I.',
		king: 'Paul Ahaus',
		queen: 'Erika Ahaus',
		moh1: 'Hannelore Bürger',
		moh2: 'Waltraud Platz',
		loh1: 'Alois Bürger',
		loh2: 'Josef Platz',
		cupbearer: 'Bruno Trank',
		courtmarshal: 'Anton Marsch'
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
		no_article: false,
		aliases: ['/aktuell/2024/markus-mustermann-regiert/'],
		images: [
			mockImage('img-1-1', 'art-1', 101, 'thron', 'Der neue Thron 2024', 1, true),
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
		no_article: false,
		aliases: null,
		images: [
			mockImage('img-2-1', 'art-2', 201, 'thron', 'Thron 2023', 1, true),
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
		slug: 'kaiserthron-2009',
		date_published: '2009-09-10T15:00:00Z',
		author: 'Redaktion',
		tags: ['Thron', 'Kaiserthron'],
		body: `<p>Gerd Kaiserlich hat beim Bezirksschützenfest den Vogel geholt und regiert nun als Kaiser <strong>Gerd X.</strong> den Schützenbezirk.</p>
<p>Ein historischer Moment für den Schützenverein Buterland-Beckerhook — nach 25 Jahren stellt der Verein wieder einen Bezirkskönig.</p>`,
		no_article: false,
		aliases: null,
		images: [
			mockImage('img-6-1', 'art-6', 601, 'kaiserthron', 'Der Kaiserthron', 1, true),
			mockImage('img-6-2', 'art-6', 602, 'kaiserkoenigspaar', 'Das Kaiserpaar', 2)
		],
		throne: mockThrones[5]
	},
	{
		id: 'art-7',
		status: 'published',
		title: 'Hermann Feldmann regiert als Hermann III.',
		subtitle: null,
		slug: 'hermann-feldmann-koenig-2022',
		date_published: '2022-07-16T14:00:00Z',
		author: 'Redaktion',
		tags: ['Thron', 'Schützenfest'],
		body: `<p>Hermann Feldmann holte den Vogel von der Stange und regiert nun als <strong>Hermann III.</strong> den Schützenverein Buterland-Beckerhook.</p>`,
		no_article: false,
		aliases: null,
		images: [
			mockImage('img-7-1', 'art-7', 701, 'thron', 'Thron 2022', 1, true),
			mockImage('img-7-2', 'art-7', 702, 'hofstaat', 'Der Hofstaat 2022', 2)
		],
		throne: mockThrones[2]
	},
	{
		id: 'art-8',
		status: 'published',
		title: 'Andreas Brinkmann ist Schützenkönig',
		subtitle: null,
		slug: 'andreas-brinkmann-koenig-2021',
		date_published: '2021-07-18T14:00:00Z',
		author: 'Redaktion',
		tags: ['Thron', 'Schützenfest'],
		body: `<p>Andreas Brinkmann regiert als <strong>Andreas I.</strong> den Schützenverein Buterland-Beckerhook.</p>`,
		no_article: false,
		aliases: null,
		images: [mockImage('img-8-1', 'art-8', 801, 'thron', 'Thron 2021', 1, true)],
		throne: mockThrones[3]
	},
	{
		id: 'art-9',
		status: 'published',
		title: 'Dieter Ahlert regiert als Dieter IV.',
		subtitle: 'Zwei Jahre König wegen Corona',
		slug: 'dieter-ahlert-koenig-2019',
		date_published: '2019-07-14T14:00:00Z',
		author: 'Redaktion',
		tags: ['Thron', 'Schützenfest'],
		body: `<p>Dieter Ahlert holte den Vogel von der Stange und regiert als <strong>Dieter IV.</strong> — wegen der Corona-Pandemie gleich für zwei Jahre.</p>`,
		no_article: false,
		aliases: null,
		images: [mockImage('img-9-1', 'art-9', 901, 'thron', 'Thron 2019', 1, true)],
		throne: mockThrones[4]
	},
	{
		id: 'art-10',
		status: 'published',
		title: 'Heinrich Bröker ist Bezirkskönig',
		subtitle: 'Kaiserthron 1984',
		slug: 'kaiserthron-1984',
		date_published: '1984-09-15T15:00:00Z',
		author: 'Redaktion',
		tags: ['Thron', 'Kaiserthron'],
		body: `<p>Heinrich Bröker hat beim Bezirksschützenfest den Vogel geholt und regiert als Kaiser <strong>Heinrich V.</strong> den Schützenbezirk.</p>`,
		no_article: false,
		aliases: null,
		images: [mockImage('img-10-1', 'art-10', 1001, 'kaiserthron', 'Kaiserthron 1984', 1, true)],
		throne: mockThrones[6]
	},
	{
		id: 'art-11',
		status: 'published',
		title: 'Werner Stadtmann ist Stadtkönig',
		subtitle: 'Buterland-Beckerhook stellt den Stadtkaiser',
		slug: 'stadtkaiser-2018',
		date_published: '2018-08-25T15:00:00Z',
		author: 'Redaktion',
		tags: ['Thron', 'Stadtkaiser'],
		body: `<p>Werner Stadtmann hat beim Stadtschützenfest der 10 Ahauser Vereine den Vogel geholt und regiert als Stadtkaiser <strong>Werner II.</strong></p>`,
		no_article: false,
		aliases: null,
		images: [mockImage('img-11-1', 'art-11', 1101, 'stadtkaiser', 'Stadtkaiser 2018', 1, true)],
		throne: mockThrones[7]
	},
	{
		id: 'art-12',
		status: 'published',
		title: 'Paul Ahaus ist Stadtkönig',
		subtitle: 'Stadtkaiser aus Buterland-Beckerhook',
		slug: 'stadtkaiser-2013',
		date_published: '2013-08-24T15:00:00Z',
		author: 'Redaktion',
		tags: ['Thron', 'Stadtkaiser'],
		body: `<p>Paul Ahaus hat den Vogel von der Stange geholt und regiert als Stadtkaiser <strong>Paul I.</strong></p>`,
		no_article: false,
		aliases: null,
		images: [mockImage('img-12-1', 'art-12', 1201, 'stadtkaiser', 'Stadtkaiser 2013', 1, true)],
		throne: mockThrones[8]
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
		enable_ical: true,
		parent: null
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
		enable_ical: true,
		parent: null
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
		enable_ical: true,
		parent: null
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
		enable_ical: false,
		parent: null
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
		enable_ical: true,
		parent: null
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
		enable_ical: true,
		parent: null
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
		enable_ical: true,
		parent: null
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
		enable_ical: true,
		parent: null
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
		enable_ical: true,
		parent: null
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
		enable_ical: true,
		parent: null
	},

	// --- Sub-Events: Schützenfest 2025 Festprogramm ---
	{
		id: 'evt-sub-1',
		status: 'published',
		title: 'Antreten und Abmarsch',
		slug: 'schuetzenfest-2025-antreten-freitag',
		start: '2025-07-11T18:00:00Z',
		end: null,
		location: mockLocations[0],
		body: '<p>Antreten der Schützen am Ehrenmal mit anschließendem Abmarsch zum Festzelt.</p>',
		cancel_reason: null,
		announce: false,
		revision: 1,
		enable_ical: true,
		parent: 'evt-1'
	},
	{
		id: 'evt-sub-2',
		status: 'published',
		title: 'Festball mit DJ',
		slug: 'schuetzenfest-2025-festball-freitag',
		start: '2025-07-11T20:00:00Z',
		end: '2025-07-12T02:00:00Z',
		location: mockLocations[0],
		body: '<p>Festball im Zelt mit DJ-Musik für Jung und Alt.</p>',
		cancel_reason: null,
		announce: false,
		revision: 1,
		enable_ical: true,
		parent: 'evt-1'
	},
	{
		id: 'evt-sub-3',
		status: 'published',
		title: 'Kinderfest',
		slug: 'schuetzenfest-2025-kinderfest',
		start: '2025-07-12T10:00:00Z',
		end: '2025-07-12T13:00:00Z',
		location: mockLocations[0],
		body: '<p>Spiele, Umzug und Wahl des Kinderkönigs/der Kinderkönigin.</p>',
		cancel_reason: null,
		announce: false,
		revision: 1,
		enable_ical: true,
		parent: 'evt-1'
	},
	{
		id: 'evt-sub-4',
		status: 'published',
		title: 'Vogelschießen',
		slug: 'schuetzenfest-2025-vogelschiessen',
		start: '2025-07-12T14:00:00Z',
		end: null,
		location: mockLocations[0],
		body: '<p>Wer wird neuer Schützenkönig? Spannung pur an der Vogelstange.</p>',
		cancel_reason: null,
		announce: false,
		revision: 1,
		enable_ical: true,
		parent: 'evt-1'
	},
	{
		id: 'evt-sub-5',
		status: 'published',
		title: 'Königsball',
		slug: 'schuetzenfest-2025-koenigsball',
		start: '2025-07-12T20:00:00Z',
		end: '2025-07-13T03:00:00Z',
		location: mockLocations[0],
		body: '<p>Großer Königsball zu Ehren des neuen Königspaares mit Live-Musik.</p>',
		cancel_reason: null,
		announce: false,
		revision: 1,
		enable_ical: true,
		parent: 'evt-1'
	},
	{
		id: 'evt-sub-6',
		status: 'published',
		title: 'Hl. Messe',
		slug: 'schuetzenfest-2025-gottesdienst',
		start: '2025-07-13T09:30:00Z',
		end: null,
		location: mockLocations[0],
		body: '<p>Gottesdienst für die Schützenfamilie auf dem Schützenplatz.</p>',
		cancel_reason: null,
		announce: false,
		revision: 1,
		enable_ical: true,
		parent: 'evt-1'
	},
	{
		id: 'evt-sub-7',
		status: 'published',
		title: 'Frühschoppen',
		slug: 'schuetzenfest-2025-fruehschoppen',
		start: '2025-07-13T10:30:00Z',
		end: '2025-07-13T13:00:00Z',
		location: mockLocations[0],
		body: '<p>Gemütlicher Frühschoppen mit Blasmusik.</p>',
		cancel_reason: null,
		announce: false,
		revision: 1,
		enable_ical: true,
		parent: 'evt-1'
	},
	{
		id: 'evt-sub-8',
		status: 'published',
		title: 'Festumzug',
		slug: 'schuetzenfest-2025-festumzug',
		start: '2025-07-13T14:00:00Z',
		end: null,
		location: mockLocations[0],
		body: '<p>Großer Festumzug durch die Nachbarschaft mit allen Vereinen.</p>',
		cancel_reason: null,
		announce: false,
		revision: 1,
		enable_ical: true,
		parent: 'evt-1'
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
		slug: 'ueber-uns',
		body: `<h2>Schützenverein Buterland-Beckerhook e.V.</h2>
<p>Der Schützenverein Buterland-Beckerhook e.V. wurde 1925 gegründet und ist einer der traditionsreichsten Vereine in der Gemeinde Ahaus.</p>
<p>Mit rund 200 Mitgliedern pflegen wir das Brauchtum und den Zusammenhalt in unserer Nachbarschaft. Höhepunkt des Vereinsjahres ist das traditionelle Schützenfest im Juli.</p>
<h3>Tradition und Gemeinschaft</h3>
<p>Unser Verein steht für Tradition, Kameradschaft und Engagement in der Nachbarschaft. Das Vereinsleben umfasst neben dem Schützenfest zahlreiche weitere Veranstaltungen wie Winterwanderung, Osterfeuer und Herbstfest.</p>`,
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
		id: 'page-6',
		status: 'published',
		title: 'Jungschützen',
		slug: 'jungschuetzen',
		body: `<h2>Jungschützenabteilung</h2>
<p>Die Jungschützen sind die Zukunft unseres Vereins. Alle Mitglieder zwischen 16 und 30 Jahren gehören automatisch der Jungschützenabteilung an.</p>
<h3>Aktivitäten</h3>
<p>Neben der Teilnahme am Schützenfest organisieren die Jungschützen eigene Veranstaltungen wie das jährliche Jungschützenfest, Ausflüge und gemeinsame Aktionen.</p>
<h3>Jungschützenvorstand</h3>
<p>Die Jungschützen wählen einen eigenen Vorstand, der ihre Interessen im Gesamtverein vertritt.</p>`,
		parent: null,
		sort_order: 4
	},
	{
		id: 'page-7',
		status: 'published',
		title: 'Kinderfest',
		slug: 'kinderfest',
		body: `<h2>Kinderfest</h2>
<p>Ein besonderer Höhepunkt für die Jüngsten ist das traditionelle Kinderfest, das jedes Jahr im Rahmen des Schützenfestes stattfindet.</p>
<h3>Programm</h3>
<p>Beim Kinderfest gibt es Spiele, einen Umzug der Kinder durch die Nachbarschaft und natürlich die Wahl des Kinderkönigs oder der Kinderkönigin.</p>
<p>Alle Kinder aus der Nachbarschaft sind herzlich eingeladen, an diesem besonderen Tag teilzunehmen.</p>`,
		parent: null,
		sort_order: 5
	},
	{
		id: 'page-8',
		status: 'published',
		title: 'Mitglied werden',
		slug: 'mitglied-werden',
		body: `<h2>Werden Sie Mitglied!</h2>
<p>Sie möchten Teil unserer Gemeinschaft werden? Wir freuen uns über jedes neue Mitglied!</p>
<h3>Vorteile einer Mitgliedschaft</h3>
<ul>
<li>Teilnahme an allen Vereinsveranstaltungen</li>
<li>Aktive Teilnahme am Schützenfest</li>
<li>Gemeinschaft und Nachbarschaftspflege</li>
<li>Mitspracherecht bei der Generalversammlung</li>
</ul>
<h3>Beitrag</h3>
<p>Der jährliche Mitgliedsbeitrag beträgt 25,00 €. Für Jungschützen (16-24 Jahre) gilt ein ermäßigter Beitrag.</p>
<h3>Anmeldung</h3>
<p>Sprechen Sie einfach ein Vorstandsmitglied an oder nutzen Sie unser <a href="/kontakt">Kontaktformular</a>. Wir melden uns dann bei Ihnen!</p>`,
		parent: null,
		sort_order: 6
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

/** Derive year from article date_published for URL construction. */
export function getArticleYear(article: Article): number {
	return new Date(article.date_published).getFullYear();
}

/** Format throne years for display (e.g. "2024–2025" or "2024–"). */
export function formatThroneYears(throne: Throne): string {
	if (throne.end != null) return `${throne.begin}–${throne.end}`;
	return `${throne.begin}–`;
}

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
			if (!e.announce) return false;
			if (year) return new Date(e.start).getFullYear() === year;
			return true;
		})
		.sort((a, b) => new Date(a.start).getTime() - new Date(b.start).getTime());
}

export function getEventBySlug(slug: string): Event | undefined {
	return mockEvents.find((e) => e.slug === slug && e.status !== 'draft');
}

export function getThrones(): Throne[] {
	return mockThrones.sort((a, b) => b.begin - a.begin);
}

export function getThroneArticles(): Article[] {
	return mockArticles
		.filter((a) => a.throne != null && a.status === 'published')
		.sort((a, b) => new Date(b.date_published).getTime() - new Date(a.date_published).getTime());
}

/**
 * Get paginated throne articles (regular thrones + stadtkaiser, NOT kaiserthrone).
 * Sorted by throne begin year descending (newest first).
 */
export function getPaginatedThrones(
	page = 1,
	limit = 1
): { articles: Article[]; total: number; page: number; totalPages: number } {
	const throneArticles = mockArticles
		.filter(
			(a) =>
				a.throne != null &&
				a.status === 'published' &&
				(a.throne.type === 'koenig' || a.throne.type === 'stadtkaiser')
		)
		.sort((a, b) => {
			const yearA = a.throne?.begin ?? 0;
			const yearB = b.throne?.begin ?? 0;
			return yearB - yearA;
		});
	const total = throneArticles.length;
	const totalPages = Math.ceil(total / limit);
	const start = (page - 1) * limit;
	return {
		articles: throneArticles.slice(start, start + limit),
		total,
		page,
		totalPages
	};
}

/**
 * Get all Kaiserthron articles (for navigation dropdown items).
 * Returns them sorted by begin year descending.
 */
export function getEmperorThrones(): Article[] {
	return mockArticles
		.filter((a) => a.throne != null && a.status === 'published' && a.throne.type === 'kaiser')
		.sort((a, b) => {
			const yearA = a.throne?.begin ?? 0;
			const yearB = b.throne?.begin ?? 0;
			return yearB - yearA;
		});
}

export function getPeople(group?: 'vorstand' | 'offiziere'): Person[] {
	return mockPeople
		.filter((p) => !group || p.group === group)
		.sort((a, b) => a.sort_order - b.sort_order);
}

export function getPage(slug: string): Page | undefined {
	return mockPages.find((p) => p.slug === slug && p.status === 'published');
}

/** Get all published pages for a section (e.g., all Verein sub-pages). */
export function getVereinPages(): Page[] {
	const vereinSlugs = [
		'ueber-uns',
		'vorstand',
		'offiziere',
		'jungschuetzen',
		'kinderfest',
		'mitglied-werden'
	];
	return mockPages
		.filter((p) => vereinSlugs.includes(p.slug) && p.status === 'published')
		.sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0));
}

export function getNextEvent(): Event | undefined {
	const now = new Date();
	return mockEvents
		.filter((e) => e.status === 'published' && e.announce && new Date(e.start) > now)
		.sort((a, b) => new Date(a.start).getTime() - new Date(b.start).getTime())[0];
}

/** Get sub-events for a parent event, sorted by start time. */
export function getSubEvents(parentId: string): Event[] {
	return mockEvents
		.filter((e) => e.parent === parentId && e.status !== 'draft')
		.sort((a, b) => new Date(a.start).getTime() - new Date(b.start).getTime());
}

export function getCurrentThrone(): Throne | undefined {
	return mockThrones.filter((t) => t.type === 'koenig').sort((a, b) => b.begin - a.begin)[0];
}

export function getCurrentThroneArticle(): Article | undefined {
	const throne = getCurrentThrone();
	if (!throne) return undefined;
	return mockArticles.find((a) => a.id === throne.article && a.status === 'published');
}
