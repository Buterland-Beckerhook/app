// =============================================================================
// Directus API client + query functions
// Replaces mock-data.ts with real CMS queries
// =============================================================================

import { env } from '$env/dynamic/private';
import { createDirectus, rest, staticToken, readItems, aggregate } from '@directus/sdk';
import type { Schema, Article, Throne, Event, Person, Page } from '$lib/types';

// --- Client setup ---

function getEnv(key: string): string {
	const value = env[key];
	if (!value) {
		throw new Error(`Missing required environment variable: ${key}`);
	}
	return value;
}

function createClient() {
	return createDirectus<Schema>(getEnv('DIRECTUS_URL'))
		.with(staticToken(getEnv('DIRECTUS_TOKEN')))
		.with(rest());
}

const directus = createClient();

// --- Pure helper functions ---

/** Derive year from article for URL construction. */
export function getArticleYear(article: Article): number {
	return article.year;
}

/** Format throne years for display (e.g. "2024–2025" or "2024–"). */
export function formatThroneYears(throne: Throne): string {
	if (throne.end != null) return `${throne.begin}–${throne.end}`;
	return `${throne.begin}–`;
}

// --- Data normalization ---

/**
 * Normalize a raw article from Directus.
 *
 * The `throne` field is a O2M alias in Directus (thrones.article FK points to articles).
 * This means the API always returns `throne` as an array, even though each article
 * has at most one throne. We normalize it to a single object or null.
 */
function normalizeArticle(raw: Record<string, unknown>): Article {
	const article = raw as unknown as Article;
	if (Array.isArray(article.throne)) {
		article.throne = (article.throne as Throne[])[0] ?? null;
	}
	return article;
}

// --- Shared field definitions ---

// Directus SDK v21 uses nested object syntax for relational fields.
// The `image` field on ArticleImage references `directus_files` (a system collection
// not in our Schema), so the SDK's type-checker can't validate the deep nesting.
// We use a type assertion to bypass this — the actual query works fine at runtime.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const articleFields: any = [
	'id',
	'status',
	'title',
	'subtitle',
	'slug',
	'date_published',
	'date_modified',
	'year',
	'author',
	'tags',
	'body',
	'no_article',
	'aliases',
	{
		images: [
			'id',
			'logical_name',
			'title',
			'copyright',
			'sort',
			'use_as_throne_picture',
			'use_as_article_image',
			{ image: ['id', 'title', 'filename_download', 'type', 'width', 'height'] }
		]
	},
	{
		throne: [
			'id',
			'type',
			'begin',
			'end',
			'king_title',
			'king',
			'queen',
			'moh1',
			'moh2',
			'loh1',
			'loh2',
			'cupbearer',
			'courtmarshal'
		]
	}
];

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const eventFields: any = [
	'id',
	'status',
	'title',
	'slug',
	'start',
	'end',
	'year',
	'all_day',
	'body',
	'cancel_reason',
	'announce',
	'revision',
	'enable_ical',
	'parent',
	'calendar',
	{
		location: ['id', 'key', 'name', 'street', 'zip', 'city', 'lat', 'lng', 'maps_url', 'url']
	}
];

// --- Article queries ---

/** Get paginated published articles, sorted by date_published desc. */
export async function getArticles(
	page = 1,
	limit = 10
): Promise<{ articles: Article[]; total: number }> {
	const [articles, countResult] = await Promise.all([
		directus.request(
			readItems('articles', {
				fields: articleFields,
				filter: { status: { _eq: 'published' } },
				sort: ['-date_published'],
				limit,
				offset: (page - 1) * limit
			})
		),
		directus.request(
			aggregate('articles', {
				aggregate: { count: '*' },
				query: { filter: { status: { _eq: 'published' } } }
			})
		)
	]);

	const total = Number(countResult[0]?.count ?? 0);
	return { articles: (articles as Record<string, unknown>[]).map(normalizeArticle), total };
}

/** Get a single published article by slug and year. */
export async function getArticleBySlug(slug: string, year: number): Promise<Article | undefined> {
	const results = await directus.request(
		readItems('articles', {
			fields: articleFields,
			filter: {
				slug: { _eq: slug },
				status: { _eq: 'published' },
				year: { _eq: year }
			},
			limit: 1
		})
	);

	return results[0] ? normalizeArticle(results[0] as Record<string, unknown>) : undefined;
}

// --- Throne queries ---

/**
 * Get paginated throne articles (koenig + stadtkaiser, NOT kaiser).
 * Sorted by throne.begin descending (newest first).
 */
export async function getPaginatedThrones(
	page = 1,
	perPage = 1
): Promise<{ articles: Article[]; total: number; page: number; totalPages: number }> {
	const throneFilter = {
		status: { _eq: 'published' as const },
		throne: {
			type: { _in: ['koenig' as const, 'stadtkaiser' as const] }
		}
	};

	const [articles, countResult] = await Promise.all([
		directus.request(
			// Directus supports sorting by relational fields via dot-notation,
			// but the SDK's type system doesn't know about deep sort paths.
			readItems('articles', {
				fields: articleFields,
				filter: throneFilter,
				sort: ['-throne.begin'],
				limit: perPage,
				offset: (page - 1) * perPage
				// eslint-disable-next-line @typescript-eslint/no-explicit-any
			} as any)
		),
		directus.request(
			aggregate('articles', {
				aggregate: { count: '*' },
				query: { filter: throneFilter }
			})
		)
	]);

	const normalized = (articles as Record<string, unknown>[]).map(normalizeArticle);

	const total = Number(countResult[0]?.count ?? 0);
	const totalPages = Math.ceil(total / perPage);

	return { articles: normalized, total, page, totalPages };
}

/** Get current throne (koenig type with highest begin year). */
export async function getCurrentThrone(): Promise<Throne | undefined> {
	const results = await directus.request(
		readItems('thrones', {
			fields: [
				'id',
				'article',
				'type',
				'begin',
				'end',
				'king_title',
				'king',
				'queen',
				'moh1',
				'moh2',
				'loh1',
				'loh2',
				'cupbearer',
				'courtmarshal'
			],
			filter: { type: { _eq: 'koenig' } },
			sort: ['-begin'],
			limit: 1
		})
	);

	return (results[0] as Throne) ?? undefined;
}

/** Get the article linked to the current throne, with images. */
export async function getCurrentThroneArticle(): Promise<Article | undefined> {
	const throne = await getCurrentThrone();
	if (!throne) return undefined;

	const articleId = typeof throne.article === 'string' ? throne.article : throne.article?.id;
	if (!articleId) return undefined;

	const results = await directus.request(
		readItems('articles', {
			fields: articleFields,
			filter: {
				id: { _eq: articleId },
				status: { _eq: 'published' }
			},
			limit: 1
		})
	);

	return results[0] ? normalizeArticle(results[0] as Record<string, unknown>) : undefined;
}

// --- Event queries ---

/** Get public events for a given year. Excludes drafts and non-announced. Sorted by start. */
export async function getEvents(year?: number): Promise<Event[]> {
	const filter: Record<string, unknown> = {
		status: { _neq: 'draft' },
		announce: { _eq: true }
	};

	if (year) {
		const yearStart = `${year}-01-01T00:00:00`;
		const yearEnd = `${year + 1}-01-01T00:00:00`;
		filter['start'] = { _gte: yearStart, _lt: yearEnd };
	}

	const results = await directus.request(
		readItems('events', {
			fields: eventFields,
			filter,
			sort: ['start'],
			limit: -1
		})
	);

	return results as unknown as Event[];
}

/** Get a single event by slug and year (not draft). Includes location. */
export async function getEventBySlug(slug: string, year: number): Promise<Event | undefined> {
	const results = await directus.request(
		readItems('events', {
			fields: eventFields,
			filter: {
				slug: { _eq: slug },
				year: { _eq: year },
				status: { _neq: 'draft' }
			},
			limit: 1
		})
	);

	return (results[0] as unknown as Event) ?? undefined;
}

/** Get next upcoming event (published, announced, start >= now). */
export async function getNextEvent(): Promise<Event | undefined> {
	const now = new Date().toISOString();

	const results = await directus.request(
		readItems('events', {
			fields: eventFields,
			filter: {
				status: { _eq: 'published' },
				announce: { _eq: true },
				start: { _gte: now }
			} as Record<string, unknown>,
			sort: ['start'],
			limit: 1
		})
	);

	return (results[0] as unknown as Event) ?? undefined;
}

/** Get sub-events for a parent event, sorted by start time. */
export async function getSubEvents(parentId: string): Promise<Event[]> {
	const results = await directus.request(
		readItems('events', {
			fields: eventFields,
			filter: {
				parent: { _eq: parentId },
				status: { _neq: 'draft' }
			},
			sort: ['start'],
			limit: -1
		})
	);

	return results as unknown as Event[];
}

// --- People queries ---

/** Get people by group, sorted by sort_order. */
export async function getPeople(group?: 'vorstand' | 'offiziere'): Promise<Person[]> {
	const filter: Record<string, unknown> = {};
	if (group) {
		filter['group'] = { _eq: group };
	}

	const results = await directus.request(
		readItems('people', {
			fields: ['id', 'group', 'role', 'role_key', 'name', 'street', 'city', 'sort_order'],
			filter,
			sort: ['sort_order'],
			limit: -1
		})
	);

	return results as Person[];
}

// --- Page queries ---

/** Get a single published page by slug. */
export async function getPage(slug: string): Promise<Page | undefined> {
	const results = await directus.request(
		readItems('pages', {
			fields: ['id', 'status', 'title', 'slug', 'body', 'parent', 'sort_order'],
			filter: {
				slug: { _eq: slug },
				status: { _eq: 'published' }
			},
			limit: 1
		})
	);

	return (results[0] as Page) ?? undefined;
}

/** Get all published Verein sub-pages (those with known Verein slugs). */
export async function getVereinPages(): Promise<Page[]> {
	const vereinSlugs = [
		'ueber-uns',
		'vorstand',
		'offiziere',
		'jungschuetzen',
		'kinderfest',
		'mitglied-werden'
	];

	const results = await directus.request(
		readItems('pages', {
			fields: ['id', 'status', 'title', 'slug', 'body', 'parent', 'sort_order'],
			filter: {
				slug: { _in: vereinSlugs },
				status: { _eq: 'published' }
			},
			sort: ['sort_order'],
			limit: -1
		})
	);

	return results as Page[];
}
