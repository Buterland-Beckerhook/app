// =============================================================================
// Image URL utilities
// Builds URLs for article images — mock (picsum) or real (Directus assets)
// =============================================================================

import { env } from '$env/dynamic/public';
import type { Article, ArticleImage } from '$lib/types';

/**
 * Get the display URL for an ArticleImage.
 * When PUBLIC_DIRECTUS_URL is set, uses the Directus asset endpoint.
 * Otherwise falls back to picsum.photos placeholders (mock/dev mode).
 */
export function getImageUrl(articleImage: ArticleImage, width = 800, height = 533): string {
	const file = articleImage.image;
	const fileId = typeof file === 'string' ? file : file.id;
	const directusUrl = env.PUBLIC_DIRECTUS_URL;

	if (directusUrl) {
		return `${directusUrl}/assets/${fileId}?width=${width}&height=${height}&fit=cover`;
	}

	// Mock mode: use picsum.photos with deterministic seed
	const seed = fileId.replace(/[^0-9]/g, '') || '42';
	return `https://picsum.photos/seed/${seed}/${width}/${height}`;
}

/**
 * Get the alt text for an ArticleImage.
 * Prefers the image-level title, falls back to the Directus file title.
 */
export function getImageAlt(articleImage: ArticleImage): string {
	if (articleImage.title) return articleImage.title;
	const file = articleImage.image;
	if (typeof file !== 'string' && file.title) return file.title;
	return '';
}

/**
 * Get the article image from an article's images array.
 * Prefers images flagged with use_as_article_image, falls back to the first by sort order.
 */
export function getFirstImage(images: ArticleImage[]): ArticleImage | undefined {
	if (!images || images.length === 0) return undefined;
	const flagged = images.find((img) => img.use_as_article_image);
	if (flagged) return flagged;
	return [...images].sort((a, b) => (a.sort ?? 0) - (b.sort ?? 0))[0];
}

/**
 * Get the image flagged as throne picture from an article's images.
 * Falls back to the first image if none is flagged.
 */
export function getThroneImage(article: Article): ArticleImage | undefined {
	if (!article.images || article.images.length === 0) return undefined;
	const flagged = article.images.find((img) => img.use_as_throne_picture);
	if (flagged) return flagged;
	return [...article.images].sort((a, b) => (a.sort ?? 0) - (b.sort ?? 0))[0];
}
