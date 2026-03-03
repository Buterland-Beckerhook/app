/**
 * Import static pages from Hugo content into Directus.
 *
 * Creates: pages (with hierarchical parent/child structure).
 * Also uploads images from page bundles and headless gruppenfotos bundles.
 *
 * Usage:
 *   npx tsx src/import-pages.ts [path-to-hugo-content]
 */

import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, basename } from 'node:path';
import { parse as parseYaml } from 'yaml';
import { marked } from 'marked';
import { createItem, deleteAllItems, readItems, uploadFile, DIRECTUS_URL } from './directus.js';

const HUGO_CONTENT_PATH = process.argv[2] ?? '../../buterland-beckerhook/content';
const HUGO_DATA_PATH = process.argv[3] ?? '../../buterland-beckerhook/data';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface HugoPageFrontmatter {
	title?: string;
	Title?: string; // kontakt.md uses capital T
	headline?: string;
	subhead?: string;
	anchor?: string;
	weight?: number;
	headless?: boolean;
	draft?: boolean;
	resources?: HugoResource[];
	ref?: string;
	lastmod?: string;
	menu?: unknown;
}

interface HugoResource {
	src: string;
	name?: string;
	title?: string;
	params?: { copy?: string };
}

// ---------------------------------------------------------------------------
// Static data for shortcode replacement
// ---------------------------------------------------------------------------

function loadVorstandData(): Record<string, { name: string; street: string; city: string }> {
	const path = join(HUGO_DATA_PATH, 'vorstand.yaml');
	if (!existsSync(path)) return {};
	return parseYaml(readFileSync(path, 'utf-8'));
}

function loadOffiziereData(): Record<string, { name: string; street: string; city: string }> {
	const path = join(HUGO_DATA_PATH, 'offiziere.yaml');
	if (!existsSync(path)) return {};
	return parseYaml(readFileSync(path, 'utf-8'));
}

const vorstand = loadVorstandData();
const offiziere = loadOffiziereData();

// ---------------------------------------------------------------------------
// Shortcode replacements
// ---------------------------------------------------------------------------

function replaceImpressPublisher(): string {
	const gf = vorstand.geschaeftsfuehrer;
	if (!gf) return 'Schützenverein Buterland-Beckerhook e.V.';
	return `<span>Schützenverein Buterland-Beckerhook e.V.</span><br>\n<span>${gf.street || ''}</span><br>\n<span>${gf.city || ''}</span>`;
}

function replaceImpressRepresenter(): string {
	const gf = vorstand.geschaeftsfuehrer;
	return gf ? `<span>${gf.name}</span>` : '';
}

function replaceContactBoard(): string {
	const rows = [
		{ label: 'Präsident', key: 'praesident' },
		{ label: 'Vizepräsident', key: 'vizePraesident' },
		{ label: 'Geschäftsführer', key: 'geschaeftsfuehrer' },
		{ label: 'Schriftführer', key: 'schriftfuehrer' },
		{ label: 'Kassierer', key: 'kassierer' }
	];

	let html = '<table>\n<tbody>\n';
	for (const row of rows) {
		const person = vorstand[row.key];
		if (!person) continue;
		html += `<tr><td><strong>${row.label}:</strong></td><td>${person.name}<br>${person.street || ''}<br>${person.city || ''}</td></tr>\n`;
	}
	html += '</tbody>\n</table>';
	return html;
}

function replaceContactOfficers(): string {
	const rows = [
		{ label: 'Oberst', key: 'oberst' },
		{ label: 'Oberstleutnant', key: 'oberstleutnant' },
		{ label: 'Major', key: 'major' }
	];

	let html = '<table>\n<tbody>\n';
	for (const row of rows) {
		const person = offiziere[row.key];
		if (!person) continue;
		html += `<tr><td><strong>${row.label}:</strong></td><td>${person.name}<br>${person.street || ''}<br>${person.city || ''}</td></tr>\n`;
	}
	html += '</tbody>\n</table>';
	return html;
}

function replaceHeadOfBoard(): string {
	// Renders president info
	const pres = vorstand.praesident;
	if (!pres) return '';
	return `<p><strong>Präsident:</strong> ${pres.name}</p>`;
}

/**
 * Process all shortcodes in page body content.
 */
function processShortcodes(md: string): string {
	let result = md;

	// Replace specific data shortcodes
	result = result.replace(/\{\{<\s*impress-publisher\s*>}}/g, replaceImpressPublisher());
	result = result.replace(/\{\{<\s*impress-representer\s*>}}/g, replaceImpressRepresenter());
	result = result.replace(/\{\{<\s*contactboard\s*>}}/g, replaceContactBoard());
	result = result.replace(/\{\{<\s*contactofficers\s*>}}/g, replaceContactOfficers());
	result = result.replace(/\{\{<\s*headofboard\s*>}}/g, replaceHeadOfBoard());

	// Convert {{< maillink >}}text{{< /maillink >}} → email link
	result = result.replace(
		/\{\{<\s*maillink\s*>}}([\s\S]*?)\{\{<\s*\/maillink\s*>}}/g,
		'<a href="mailto:info@buterland-beckerhook.de">$1</a>'
	);
	// Standalone maillink without closing tag
	result = result.replace(/\{\{<\s*maillink\s*>}}/g, '<a href="mailto:info@buterland-beckerhook.de">info@buterland-beckerhook.de</a>');

	// Convert {{< ref "..." >}} to relative URLs
	result = result.replace(/\{\{<\s*ref\s+"([^"]+)"\s*>}}/g, (_match, path: string) => {
		let url = path.replace(/\.md$/, '').replace(/\/_index$/, '');
		if (!url.startsWith('/')) url = `/${url}`;
		return url;
	});

	// Convert {{< tlink ... >}} to HTML links
	result = result.replace(/\{\{<\s*tlink\s+(.*?)>}}/g, (_match, params: string) => {
		const url = extractParam(params, 'url') ?? '#';
		const text = extractParam(params, 'text');
		const target = extractParam(params, 'target');
		let linkText = text;
		if (!linkText) {
			try { linkText = new URL(url).hostname; } catch { linkText = url; }
		}
		const targetAttr = target ? ` target="${target}" rel="noopener noreferrer"` : '';
		return `<a href="${url}"${targetAttr}>${linkText}</a>`;
	});

	// Convert {{< br >}} to <br>
	result = result.replace(/\{\{<\s*br\s*>}}/g, '<br>');

	// Convert {{< hr >}} to <hr>
	result = result.replace(/\{\{<\s*hr\s*>}}/g, '<hr>');

	// Strip {{< bottomspace >}}
	result = result.replace(/^\s*\{\{<\s*bottomspace\s*>}}\s*$/gm, '');

	// Strip image/imageslide/imagegrid shortcodes (images handled separately)
	result = result.replace(/^\s*\{\{<\s*image(?:slide|grid)?\s+.*?>}}\s*$/gm, '');
	result = result.replace(/\{\{<\s*image(?:slide|grid)?\s+.*?>}}/g, '');

	// Convert {{< emailjs >}}...{{< /emailjs >}} → placeholder
	result = result.replace(
		/\{\{<\s*emailjs[^>]*>}}[\s\S]*?\{\{<\s*\/emailjs\s*>}}/g,
		'<p><em>Kontaktformular wird hier angezeigt.</em></p>'
	);

	// Strip mediacardright/mediacardleft paired shortcodes — keep inner content
	result = result.replace(/\{\{<\s*mediacard(?:right|left)\s*.*?>}}/g, '');
	result = result.replace(/\{\{<\s*\/mediacard(?:right|left)\s*>}}/g, '');

	// Strip grid/card paired shortcodes — keep inner content
	result = result.replace(/\{\{[<%]\s*grid\s*[%>]}}/g, '');
	result = result.replace(/\{\{[<%]\s*\/grid\s*[%>]}}/g, '');
	result = result.replace(/\{\{[<%]\s*card\s*.*?[%>]}}/g, '');
	result = result.replace(/\{\{[<%]\s*\/card\s*[%>]}}/g, '');

	// Strip alert paired shortcodes — keep inner content
	result = result.replace(/\{\{[<%]\s*alert\s*.*?[%>]}}/g, '');
	result = result.replace(/\{\{[<%]\s*\/alert\s*[%>]}}/g, '');

	// Strip span shortcodes — keep inner content
	result = result.replace(/\{\{<\s*span\s+.*?>}}/g, '');
	result = result.replace(/\{\{<\s*\/span\s*>}}/g, '');

	// Strip any remaining shortcodes
	result = result.replace(/\{\{[<%]\s*.*?[%>]}}/g, '');

	return result.trim();
}

function extractParam(params: string, name: string): string | undefined {
	const match = params.match(new RegExp(`${name}\\s*=\\s*"([^"]*)"`, 'i'))
		|| params.match(new RegExp(`${name}\\s*=\\s*'([^']*)'`, 'i'));
	return match?.[1];
}

// ---------------------------------------------------------------------------
// Page structure definition
// ---------------------------------------------------------------------------

interface PageDef {
	slug: string;
	title: string;
	hugoPath: string; // relative to HUGO_CONTENT_PATH
	sortOrder: number;
	children?: PageDef[];
	skipImport?: boolean;
}

const PAGE_TREE: PageDef[] = [
	{
		slug: 'impressum',
		title: 'Impressum',
		hugoPath: 'impressum.md',
		sortOrder: 1
	},
	{
		slug: 'datenschutz',
		title: 'Datenschutzerklärung',
		hugoPath: 'datenschutzerklaerung.md',
		sortOrder: 2
	},
	{
		slug: 'kontakt',
		title: 'Kontakt',
		hugoPath: 'kontakt.md',
		sortOrder: 3
	},
	{
		slug: 'ueber-uns',
		title: 'Über uns',
		hugoPath: 'verein/about/_index.md',
		sortOrder: 1,
		children: [
			{ slug: 'schuetzenfest', title: 'Schützenfest', hugoPath: 'verein/about/schuetzenfest/index.md', sortOrder: 1 },
			{ slug: 'vereinslokal', title: 'Vereinslokal', hugoPath: 'verein/about/vereinslokal/index.md', sortOrder: 2 },
			{ slug: 'ehrenmal', title: 'Ehrenmal', hugoPath: 'verein/about/erhrenmal/index.md', sortOrder: 3 }
		]
	},
	{
		slug: 'vorstand',
		title: 'Vorstand',
		hugoPath: 'verein/vorstand/_index.md',
		sortOrder: 2,
		children: [
			{ slug: 'praesidenten', title: 'Die Präsidenten', hugoPath: 'verein/vorstand/praesidenten/index.md', sortOrder: 1 },
			{ slug: 'kontakt-vorstand', title: 'Kontakt zum Vorstand', hugoPath: 'verein/vorstand/kontakt/index.md', sortOrder: 2 }
		]
	},
	{
		slug: 'offiziere',
		title: 'Offiziere',
		hugoPath: 'verein/offiziere/_index.md',
		sortOrder: 3,
		children: [
			{ slug: 'chefs', title: 'Die Chefs der Offiziere', hugoPath: 'verein/offiziere/chefs/index.md', sortOrder: 1 },
			{ slug: 'kontakt-offiziere', title: 'Kontakt zu den Offizieren', hugoPath: 'verein/offiziere/kontakt/index.md', sortOrder: 2 }
		]
	},
	{
		slug: 'jungschuetzen',
		title: 'Jungschützen',
		hugoPath: 'verein/jungschuetzen/_index.md',
		sortOrder: 4,
		children: [
			{ slug: 'geschichte', title: 'Geschichte der Jungschützen', hugoPath: 'verein/jungschuetzen/geschichte/index.md', sortOrder: 1 },
			{ slug: 'heute', title: 'Die Jungschützen heute', hugoPath: 'verein/jungschuetzen/heute/index.md', sortOrder: 2 },
			{ slug: 'jubilaeum', title: 'Jubiläum', hugoPath: 'verein/jungschuetzen/jubilaeum/index.md', sortOrder: 3 }
		]
	},
	{
		slug: 'mitglied-werden',
		title: 'Mitglied werden',
		hugoPath: 'verein/aufnahmeantrag/_index.md',
		sortOrder: 5
	}
];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Parse frontmatter + body. Handles files without frontmatter (like impressum.md). */
function parsePage(content: string): { frontmatter: HugoPageFrontmatter; body: string } {
	const normalized = content.replace(/\r\n/g, '\n');
	const match = normalized.match(/^---\n([\s\S]*?)\n---\n?([\s\S]*)$/);
	if (!match) {
		// No frontmatter — entire content is body
		return { frontmatter: {}, body: normalized.trim() };
	}
	const frontmatter = parseYaml(match[1]) as HugoPageFrontmatter;
	const body = match[2].trim();
	return { frontmatter, body };
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
	console.log('=== Import Pages ===');
	console.log(`Directus: ${DIRECTUS_URL}`);
	console.log(`Source:   ${HUGO_CONTENT_PATH}`);
	console.log('');

	// Clean up existing pages
	const existingPages = await readItems('pages', { limit: '-1' });
	if (existingPages.length > 0) {
		console.log(`Deleting ${existingPages.length} existing pages...`);
		await deleteAllItems('pages');
	}
	console.log('');

	let imported = 0;
	let errors = 0;

	async function importPage(def: PageDef, parentId: string | null, depth: number) {
		const indent = '  '.repeat(depth);
		const filePath = join(HUGO_CONTENT_PATH, def.hugoPath);

		if (!existsSync(filePath)) {
			console.error(`${indent}ERROR: File not found: ${def.hugoPath}`);
			errors++;
			return;
		}

		const content = readFileSync(filePath, 'utf-8');
		const { frontmatter, body: rawBody } = parsePage(content);

		// Use title from definition (overrides Hugo frontmatter for consistency)
		const title = def.title;

		// Process body
		const processedMd = processShortcodes(rawBody);
		let htmlBody = '';
		if (processedMd) {
			htmlBody = await marked.parse(processedMd);
		}

		try {
			const page = await createItem('pages', {
				title,
				slug: def.slug,
				body: htmlBody || '<p></p>',
				parent: parentId,
				sort_order: def.sortOrder,
				status: 'published'
			});

			const pageId = page.id as string;
			console.log(`${indent}OK: ${def.slug} → "${title}"`);
			imported++;

			// Import children
			if (def.children) {
				for (const child of def.children) {
					await importPage(child, pageId, depth + 1);
				}
			}
		} catch (err) {
			console.error(`${indent}ERROR: ${def.slug} → ${err}`);
			errors++;
		}
	}

	for (const pageDef of PAGE_TREE) {
		await importPage(pageDef, null, 0);
	}

	console.log('');
	console.log(`Done. Imported: ${imported}, Errors: ${errors}`);
}

main().catch((err) => {
	console.error('FATAL:', err);
	process.exit(1);
});
