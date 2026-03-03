/**
 * Import throne articles from Hugo content into Directus.
 *
 * Creates: articles + thrones + article_images (with file uploads).
 *
 * Usage:
 *   npx tsx src/import-thrones.ts [path-to-hugo-content]
 */

import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, basename, dirname } from 'node:path';
import { parse as parseYaml } from 'yaml';
import { marked } from 'marked';
import {
	createItem,
	deleteAllItems,
	deleteAllFiles,
	deleteAllFolders,
	readItems,
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

interface HugoThrone {
	years?: string | number;
	king_title?: string;
	king: string;
	queen: string;
	loh1?: string;
	loh2?: string;
	moh1?: string;
	moh2?: string;
	cupbearer?: string;
	courtmarshal?: string;
}

interface HugoFrontmatter {
	title: string;
	subtitle?: string;
	date: string;
	lastmod?: string;
	tags?: string[];
	noarticle?: boolean;
	throne: HugoThrone;
	resources?: HugoResource[];
	menu?: unknown;
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
	const frontmatter = parseYaml(match[1]) as HugoFrontmatter;
	const body = match[2].trim();
	return { frontmatter, body };
}

/** Remove Hugo shortcodes from markdown body. */
function removeShortcodes(md: string): string {
	// Remove {{< shortcode ... >}} lines
	return md
		.replace(/^\s*\{\{<.*?>}}\s*$/gm, '')
		.replace(/\{\{<.*?>}}/g, '')
		.trim();
}

/** Remove Hugo <!--more--> comment. */
function removeMoreTag(md: string): string {
	return md.replace(/<!--\s*more\s*-->/g, '').trim();
}

/**
 * Parse throne years string into begin/end integers.
 * Formats: "2022-2023", "1929/1930", "2009", "1939-1949", "2019-2022", empty
 */
function parseYears(years?: string | number): { begin: number; end: number | null } {
	if (!years) return { begin: 0, end: null };
	const str = String(years);
	const parts = str.split(/[/-]/);
	const begin = parseInt(parts[0], 10);
	const end = parts.length > 1 ? parseInt(parts[1], 10) : null;
	return { begin, end };
}

/** Determine throne type from tags. */
function getThroneType(tags?: string[]): 'koenig' | 'kaiser' {
	if (tags?.some((t) => t.toLowerCase().includes('kaiser'))) return 'kaiser';
	return 'koenig';
}

/** Generate slug from throne type. Uniqueness is per year (DB index). */
function generateSlug(throneType: string): string {
	return throneType === 'kaiser' ? 'kaiserthron' : 'thron';
}

/** Find all throne article directories by scanning aktuell/YYYY/ for dirs containing index.md with "throne:" */
function findThroneArticles(aktuellDir: string): string[] {
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
			if (content.includes('\nthrone:')) {
				results.push(indexPath);
			}
		}
	}

	return results.sort();
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
	console.log('=== Import Thrones ===');
	console.log(`Directus: ${DIRECTUS_URL}`);
	console.log(`Source:   ${AKTUELL_DIR}`);
	console.log('');

	// Clean up existing data (order matters: thrones → article_images → articles → files)
	const existingThrones = await readItems('thrones', { limit: '-1' });
	if (existingThrones.length > 0) {
		console.log(`Deleting ${existingThrones.length} existing thrones...`);
		await deleteAllItems('thrones');
	}

	const existingImages = await readItems('article_images', { limit: '-1' });
	if (existingImages.length > 0) {
		console.log(`Deleting ${existingImages.length} existing article_images...`);
		await deleteAllItems('article_images');
	}

	const existingArticles = await readItems('articles', { limit: '-1' });
	if (existingArticles.length > 0) {
		console.log(`Deleting ${existingArticles.length} existing articles...`);
		await deleteAllItems('articles');
	}

	// Delete uploaded files
	const deletedFiles = await deleteAllFiles();
	if (deletedFiles > 0) {
		console.log(`Deleted ${deletedFiles} uploaded files.`);
	}

	// Delete folders
	const deletedFolders = await deleteAllFolders();
	if (deletedFolders > 0) {
		console.log(`Deleted ${deletedFolders} folders.`);
	}

	console.log('');

	// Find all throne articles
	const articlePaths = findThroneArticles(AKTUELL_DIR);
	console.log(`Found ${articlePaths.length} throne articles.`);
	console.log('');

	let imported = 0;
	let errors = 0;

	for (const articlePath of articlePaths) {
		const articleDir = dirname(articlePath);
		const yearDir = basename(dirname(articleDir));
		const content = readFileSync(articlePath, 'utf-8');

		let frontmatter: HugoFrontmatter;
		let rawBody: string;

		try {
			const parsed = parseFrontmatter(content);
			frontmatter = parsed.frontmatter;
			rawBody = parsed.body;
		} catch (err) {
			console.error(`  ERROR parsing ${articlePath}: ${err}`);
			errors++;
			continue;
		}

		const throneType = getThroneType(frontmatter.tags);
		const slug = generateSlug(throneType);
		const { begin, end } = parseYears(frontmatter.throne.years);

		// Process body: remove shortcodes, <!--more-->, convert MD → HTML
		let cleanBody = removeShortcodes(rawBody);
		cleanBody = removeMoreTag(cleanBody);

		let htmlBody: string | null = null;
		if (cleanBody && !frontmatter.noarticle) {
			htmlBody = await marked.parse(cleanBody);
		}

		const label = `${yearDir} ${throneType === 'kaiser' ? 'Kaiser' : 'Thron'}`;

		try {
			// 1. Create article
			const article = await createItem('articles', {
				title: frontmatter.title,
				subtitle: frontmatter.subtitle ?? null,
				slug,
				date_published: frontmatter.date,
				tags: frontmatter.tags ?? ['Thron'],
				body: htmlBody,
				no_article: frontmatter.noarticle ?? false,
				status: 'published',
				aliases: null
			});

			const articleId = article.id as string;

			// 2. Create throne
			await createItem('thrones', {
				type: throneType,
				begin,
				end,
				king_title: frontmatter.throne.king_title ?? null,
				king: frontmatter.throne.king,
				queen: frontmatter.throne.queen,
				loh1: frontmatter.throne.loh1 ?? null,
				loh2: frontmatter.throne.loh2 ?? null,
				moh1: frontmatter.throne.moh1 ?? null,
				moh2: frontmatter.throne.moh2 ?? null,
				cupbearer: frontmatter.throne.cupbearer ?? null,
				courtmarshal: frontmatter.throne.courtmarshal ?? null,
				article: articleId
			});

			// 3. Upload images and create article_images
			const resources = frontmatter.resources ?? [];
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

					const isThronePicture =
						resource.name?.startsWith('thron-') ?? false;

					await createItem('article_images', {
						article: articleId,
						image: file.id,
						logical_name: resource.name ?? null,
						title: resource.title ?? null,
						copyright: resource.params?.copy ?? 'Buterland-Beckerhook e.V.',
						sort: imageSort++,
						use_as_throne_picture: isThronePicture
					});
				} catch (imgErr) {
					console.log(`    WARN: Image upload failed for ${resource.src}: ${imgErr}`);
				}
			}

			console.log(
				`  OK: ${label} → "${frontmatter.throne.king}" (${resources.length} images, ${frontmatter.noarticle ? 'no article' : 'with article'})`
			);
			imported++;
		} catch (err) {
			console.error(`  ERROR: ${label} → ${err}`);
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
