/**
 * Import non-throne articles from Hugo content into Directus.
 *
 * Creates: articles + article_images (with file uploads).
 * Does NOT touch throne articles or thrones — those are handled by import-thrones.ts.
 *
 * Usage:
 *   npx tsx src/import-articles.ts [path-to-hugo-content]
 */

import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, basename, dirname } from 'node:path';
import { parse as parseYaml } from 'yaml';
import { marked } from 'marked';
import {
	createItem,
	readItems,
	deleteItemsByIds,
	deleteFilesByIds,
	uploadFile,
	getOrCreateFolder,
	DIRECTUS_URL
} from './directus.js';

const HUGO_CONTENT_PATH = process.argv[2] ?? '../../buterland-beckerhook/content';
const AKTUELL_DIR = join(HUGO_CONTENT_PATH, 'aktuell');

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface HugoResource {
	src: string;
	name?: string;
	title?: string;
	params?: { copy?: string };
}

interface HugoFrontmatter {
	title: string;
	subtitle?: string;
	date: string;
	lastmod?: string;
	author?: string;
	tags?: string[];
	aliases?: string[];
	resources?: HugoResource[];
	throne?: unknown; // used to detect and skip throne articles
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Parse frontmatter + body from markdown file content. */
function parseFrontmatter(content: string): { frontmatter: HugoFrontmatter; body: string } {
	// Normalize Windows \r\n to \n before parsing
	const normalized = content.replace(/\r\n/g, '\n');
	const match = normalized.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
	if (!match) throw new Error('No frontmatter found');

	// Fix broken YAML: single-quoted strings that span multiple lines
	// by joining continuation lines (indented lines after an unclosed quote)
	let yaml = match[1];
	yaml = fixMultilineQuotedStrings(yaml);

	const frontmatter = parseYaml(yaml) as HugoFrontmatter;
	const body = match[2].trim();
	return { frontmatter, body };
}

/**
 * Fix YAML strings where a single-quoted value wraps to the next line.
 * e.g.:
 *   title: 'some long text that
 *   continues here'
 * becomes:
 *   title: 'some long text that continues here'
 */
function fixMultilineQuotedStrings(yaml: string): string {
	const lines = yaml.split('\n');
	const result: string[] = [];
	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		// Count single quotes — if odd, the quote is unclosed
		const quoteCount = (line.match(/'/g) || []).length;
		if (quoteCount % 2 === 1) {
			// Unclosed quote — join with next line(s) until quotes balance
			let joined = line;
			while (i + 1 < lines.length) {
				i++;
				joined += ' ' + lines[i].trim();
				const totalQuotes = (joined.match(/'/g) || []).length;
				if (totalQuotes % 2 === 0) break;
			}
			result.push(joined);
		} else {
			result.push(line);
		}
	}
	return result.join('\n');
}

/**
 * Normalize tags: Hugo stores tags as single comma-separated strings within arrays.
 * e.g. ['Schützenfest, Festprogramm'] → ['Schützenfest', 'Festprogramm']
 */
function normalizeTags(tags?: string[]): string[] {
	if (!tags || tags.length === 0) return [];
	const result: string[] = [];
	for (const tag of tags) {
		const parts = tag.split(',').map((t) => t.trim()).filter(Boolean);
		result.push(...parts);
	}
	return result;
}

/** Convert {{< tlink >}} shortcodes to HTML links. */
function convertTlinks(md: string): string {
	// Match {{< tlink key="value" ... >}} with named params
	return md.replace(/\{\{<\s*tlink\s+(.*?)>}}/g, (_match, params: string) => {
		const url = extractParam(params, 'url') ?? '#';
		const text = extractParam(params, 'text');
		const target = extractParam(params, 'target');

		// If no text, use URL domain as display text
		let linkText = text;
		if (!linkText) {
			try {
				linkText = new URL(url).hostname;
			} catch {
				linkText = url;
			}
		}

		const targetAttr = target ? ` target="${target}" rel="noopener noreferrer"` : '';
		return `<a href="${url}"${targetAttr}>${linkText}</a>`;
	});
}

/** Extract a named parameter from shortcode params string. */
function extractParam(params: string, name: string): string | undefined {
	// Match name="value" or name='value'
	const match = params.match(new RegExp(`${name}\\s*=\\s*"([^"]*)"`, 'i'))
		|| params.match(new RegExp(`${name}\\s*=\\s*'([^']*)'`, 'i'));
	return match?.[1];
}

/** Convert {{< html >}}...{{< /html >}} blocks to their inner HTML. */
function convertHtmlBlocks(md: string): string {
	return md.replace(/\{\{<\s*html\s*>}}([\s\S]*?)\{\{<\s*\/html\s*>}}/g, (_match, inner: string) => {
		return inner.trim();
	});
}

/**
 * Process shortcodes in markdown body.
 * - tlink → HTML links
 * - html blocks → inner HTML
 * - br → <br>
 * - hr → <hr>
 * - bottomspace → stripped
 * - image/imageslide/imagegrid → stripped (images handled via article_images)
 * - pdf → stripped (PDFs not migrated yet)
 */
function processShortcodes(md: string): string {
	let result = md;

	// Convert tlinks to proper HTML links
	result = convertTlinks(result);

	// Convert html blocks
	result = convertHtmlBlocks(result);

	// Replace {{< br >}} with <br>
	result = result.replace(/\{\{<\s*br\s*>}}/g, '<br>');

	// Replace {{< hr >}} with <hr>
	result = result.replace(/\{\{<\s*hr\s*>}}/g, '<hr>');

	// Strip {{< bottomspace >}}
	result = result.replace(/^\s*\{\{<\s*bottomspace\s*>}}\s*$/gm, '');

	// Strip image/imageslide/imagegrid shortcodes (images handled via article_images)
	result = result.replace(/^\s*\{\{<\s*image(?:slide|grid)?\s+.*?>}}\s*$/gm, '');
	result = result.replace(/\{\{<\s*image(?:slide|grid)?\s+.*?>}}/g, '');

	// Strip pdf shortcodes
	result = result.replace(/^\s*\{\{<\s*pdf\s+.*?>}}\s*$/gm, '');
	result = result.replace(/\{\{<\s*pdf\s+.*?>}}/g, '');

	// Strip any remaining shortcodes we missed
	result = result.replace(/\{\{<\s*.*?>}}/g, '');

	return result.trim();
}

/** Remove <!--more--> comment and return {summary, body}. */
function splitMore(md: string): { summary: string | null; body: string } {
	const idx = md.indexOf('<!--more-->');
	if (idx === -1) return { summary: null, body: md };

	const before = md.substring(0, idx).trim();
	const after = md.substring(idx + '<!--more-->'.length).trim();
	const summary = before || null;
	const fullBody = [before, after].filter(Boolean).join('\n\n');
	return { summary, body: fullBody };
}

/** Generate slug from article directory name. Uniqueness is per year (DB index). */
function generateSlug(articleDir: string): string {
	return articleDir.toLowerCase().replace(/[_\s]+/g, '-');
}

/** Find all non-throne article directories in aktuell/. */
function findNonThroneArticles(aktuellDir: string): string[] {
	const results: string[] = [];

	const yearDirs = readdirSync(aktuellDir).filter((d) => {
		const fullPath = join(aktuellDir, d);
		return statSync(fullPath).isDirectory() && /^\d{4}$/.test(d);
	});

	for (const yearDir of yearDirs) {
		const yearPath = join(aktuellDir, yearDir);
		const subDirs = readdirSync(yearPath).filter((d) => statSync(join(yearPath, d)).isDirectory());

		for (const subDir of subDirs) {
			const indexPath = join(yearPath, subDir, 'index.md');
			if (!existsSync(indexPath)) continue;

			const content = readFileSync(indexPath, 'utf-8');
			// Skip throne articles (handled by import-thrones.ts)
			if (content.includes('\nthrone:') || content.includes('\r\nthrone:')) {
				continue;
			}

			results.push(indexPath);
		}
	}

	return results.sort();
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
	console.log('=== Import Articles (non-throne) ===');
	console.log(`Directus: ${DIRECTUS_URL}`);
	console.log(`Source:   ${AKTUELL_DIR}`);
	console.log('');

	// Delete existing non-throne articles (those WITHOUT a throne relation)
	// We need to be careful not to delete throne articles
	const existingArticles = await readItems('articles', { limit: '-1', fields: 'id,slug' });
	const existingThrones = await readItems('thrones', { limit: '-1', fields: 'id,article' });
	const throneArticleIds = new Set(existingThrones.map((t) => t.article as string));

	const nonThroneArticles = existingArticles.filter((a) => !throneArticleIds.has(a.id as string));
	if (nonThroneArticles.length > 0) {
		console.log(`Deleting ${nonThroneArticles.length} existing non-throne articles...`);
		// Delete associated article_images first
		for (const article of nonThroneArticles) {
			const images = await readItems('article_images', {
				'filter[article][_eq]': article.id as string,
				limit: '-1',
				fields: 'id,image'
			});
			if (images.length > 0) {
				const imageIds = images.map((i) => i.id as string);
				// Delete article_images
				try {
					await deleteItemsByIds('article_images', imageIds);
				} catch {
					console.error(`  WARN: Failed to delete article_images for ${article.slug}`);
				}
				// Delete associated files
				const fileIds = images.map((i) => i.image as string).filter(Boolean);
				if (fileIds.length > 0) {
					try {
						await deleteFilesByIds(fileIds);
					} catch {
						console.error(`  WARN: Failed to delete files for ${article.slug}`);
					}
				}
			}
		}
		// Delete the articles themselves
		const articleIds = nonThroneArticles.map((a) => a.id as string);
		try {
			await deleteItemsByIds('articles', articleIds);
		} catch {
			console.error('  WARN: Failed to delete existing non-throne articles');
		}
	}

	console.log('');

	// Find all non-throne articles
	const articlePaths = findNonThroneArticles(AKTUELL_DIR);
	console.log(`Found ${articlePaths.length} non-throne articles.`);
	console.log('');

	let imported = 0;
	let errors = 0;

	for (const articlePath of articlePaths) {
		const articleDir = dirname(articlePath);
		const yearDir = basename(dirname(articleDir));
		const dirName = basename(articleDir);
		const content = readFileSync(articlePath, 'utf-8');

		let frontmatter: HugoFrontmatter;
		let rawBody: string;

		try {
			const parsed = parseFrontmatter(content);
			frontmatter = parsed.frontmatter;
			rawBody = parsed.body;
		} catch (err) {
			const message = err instanceof Error ? err.message : JSON.stringify(err);
			console.error(`  ERROR parsing ${articlePath}: ${message}`);
			errors++;
			continue;
		}

		const slug = generateSlug(dirName);
		const tags = normalizeTags(frontmatter.tags);

		// Process body: split <!--more-->, process shortcodes, convert MD → HTML
		const { summary: rawSummary, body: cleanedMdBody } = splitMore(rawBody);
		const processedBody = processShortcodes(cleanedMdBody);

		let htmlBody: string | null = null;
		if (processedBody) {
			htmlBody = await marked.parse(processedBody);
		}

		// Convert summary to HTML too if present
		let summaryHtml: string | null = null;
		if (rawSummary) {
			const processedSummary = processShortcodes(rawSummary);
			if (processedSummary) {
				summaryHtml = await marked.parse(processedSummary);
			}
		}

		// Parse aliases (URL redirects)
		const aliases = frontmatter.aliases ?? null;

		const label = `${yearDir}/${dirName}`;

		try {
			// 1. Create article
			const article = await createItem('articles', {
				title: frontmatter.title,
				subtitle: frontmatter.subtitle ?? null,
				slug,
				date_published: frontmatter.date,
				year: parseInt(yearDir, 10),
				author: frontmatter.author ?? null,
				tags: tags.length > 0 ? tags : null,
				body: htmlBody,
				no_article: false,
				status: 'published',
				aliases
			});

			const articleId = article.id as string;

			// 2. Upload images and create article_images
			const resources = (frontmatter.resources ?? []).filter((r) =>
				// Only import image files, not PDFs
				!r.src.toLowerCase().endsWith('.pdf')
			);
			let imageSort = 0;
			const folderName = parseInt(yearDir, 10) <= 2000 ? '1909-2000' : yearDir;
			const folderId = resources.length > 0 ? await getOrCreateFolder(folderName) : undefined;

			for (const resource of resources) {
				const imagePath = join(articleDir, resource.src);
				if (!existsSync(imagePath)) {
					console.log(`    WARN: Image not found: ${resource.src}`);
					continue;
				}

				try {
					const file = await uploadFile(imagePath, resource.title || resource.src, folderId);

					await createItem('article_images', {
						article: articleId,
						image: file.id,
						logical_name: resource.name ?? null,
						title: resource.title ?? null,
						copyright: resource.params?.copy ?? 'Buterland-Beckerhook e.V.',
						sort: imageSort++,
						use_as_throne_picture: false
					});
				} catch (imgErr) {
					console.log(`    WARN: Image upload failed for ${resource.src}: ${imgErr}`);
				}
			}

			console.log(
				`  OK: ${label} → "${frontmatter.title}" (${resources.length} images, ${tags.join(', ') || 'no tags'})`
			);
			imported++;
		} catch (err) {
			const msg = err instanceof Error ? err.message : JSON.stringify(err);
			console.error(`  ERROR: ${label} → ${msg}`);
			errors++;
		}
	}

	console.log('');
	console.log(`Done. Imported: ${imported}, Errors: ${errors}`);
}

main().catch((err) => {
	console.error('FATAL:', err);
	process.exit(1);
});
