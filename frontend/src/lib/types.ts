// =============================================================================
// Directus Schema Types
// Mirror the CMS collections defined in RELAUNCH_PLAN.md
// =============================================================================

export interface Article {
	id: string;
	status: 'draft' | 'published' | 'archived';
	title: string;
	subtitle: string | null;
	slug: string;
	date_published: string;
	author: string | null;
	tags: string[] | null;
	body: string | null;
	no_article: boolean;
	aliases: string[] | null;
	images: ArticleImage[];
	throne: Throne | null;
}

export interface ArticleImage {
	id: string;
	article: string | Article;
	image: string | DirectusFile;
	logical_name: string | null;
	title: string | null;
	copyright: string | null;
	sort: number | null;
	use_as_throne_picture: boolean;
}

export interface Throne {
	id: string;
	article: string | Article;
	type: 'koenig' | 'kaiser' | 'stadtkaiser';
	begin: number;
	end: number | null;
	king_title: string | null;
	king: string;
	queen: string;
	moh1: string | null;
	moh2: string | null;
	loh1: string | null;
	loh2: string | null;
	cupbearer: string | null;
	courtmarshal: string | null;
}

export interface Event {
	id: string;
	status: 'draft' | 'published' | 'canceled';
	title: string;
	slug: string;
	start: string;
	end: string | null;
	location: string | Location | null;
	body: string | null;
	cancel_reason: string | null;
	announce: boolean;
	revision: number | null;
	enable_ical: boolean;
}

export interface Location {
	id: string;
	key: string;
	name: string;
	street: string | null;
	zip: string | null;
	city: string | null;
	lat: number | null;
	lng: number | null;
	maps_url: string | null;
	url: string | null;
}

export interface Person {
	id: string;
	group: 'vorstand' | 'offiziere';
	role: string;
	role_key: string;
	name: string;
	street: string | null;
	city: string | null;
	sort_order: number;
}

export interface Page {
	id: string;
	status: 'draft' | 'published';
	title: string;
	slug: string;
	body: string;
	parent: string | Page | null;
	sort_order: number | null;
}

export interface PushSubscription {
	id: string;
	endpoint: string;
	keys_p256dh: string;
	keys_auth: string;
	categories: string[];
	created_at: string;
	last_used: string | null;
}

export interface DirectusFile {
	id: string;
	title: string | null;
	filename_download: string;
	type: string | null;
	width: number | null;
	height: number | null;
}

// Directus SDK Schema definition
// Maps collection names to their types
export interface Schema {
	articles: Article[];
	article_images: ArticleImage[];
	thrones: Throne[];
	events: Event[];
	locations: Location[];
	people: Person[];
	pages: Page[];
	push_subscriptions: PushSubscription[];
}
