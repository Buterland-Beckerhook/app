<script lang="ts">
	import Breadcrumb from '$lib/components/Breadcrumb.svelte';
	import ThroneTable from '$lib/components/ThroneTable.svelte';
	import { getImageUrl, getImageAlt, getThroneImage } from '$lib/utils/image';

	let { data } = $props();

	let article = $derived(data.articles[0]);
	let throneImage = $derived(article ? getThroneImage(article) : undefined);
</script>

<svelte:head>
	<title>Throne seit 1909 &mdash; Schützenverein Buterland-Beckerhook</title>
	<meta
		name="description"
		content="Die Throne des Schützenvereins Buterland-Beckerhook e.V. seit 1909 - Könige, Königinnen und Hofstaat."
	/>
</svelte:head>

<Breadcrumb crumbs={[{ label: 'Thron' }, { label: 'Throne seit 1909' }]} />

<h1 class="mb-8 text-3xl font-bold">Throne seit 1909</h1>

{#if article && article.throne}
	<div class="mx-auto max-w-3xl">
		{#if throneImage}
			<figure class="mb-6">
				<img
					src={getImageUrl(throneImage, 800, 600)}
					alt={getImageAlt(throneImage)}
					width="800"
					height="600"
					class="w-full rounded-lg object-cover"
				/>
				{#if throneImage.copyright}
					<figcaption class="mt-1 text-right text-xs text-gray-400 dark:text-gray-500">
						{throneImage.copyright}
					</figcaption>
				{/if}
			</figure>
		{/if}

		<div class="rounded-lg border border-gray-200 p-6 dark:border-gray-700">
			<ThroneTable throne={article.throne} />
			{#if !article.no_article}
				<a
					href="/aktuell/{article.slug}"
					class="mt-4 inline-block text-sm text-primary hover:underline"
				>
					Zum Artikel &rarr;
				</a>
			{/if}
		</div>

		<!-- Pagination -->
		{#if data.totalPages > 1}
			<div class="mt-8 flex items-center justify-between">
				{#if data.page > 1}
					<a
						href="/thron?seite={data.page - 1}"
						class="rounded border border-gray-300 px-4 py-2 text-sm hover:bg-gray-50 dark:border-gray-600 dark:hover:bg-gray-700"
					>
						&larr; Neuerer Thron
					</a>
				{:else}
					<span></span>
				{/if}

				<span class="text-sm text-gray-500 dark:text-gray-400">
					{data.page} / {data.totalPages}
				</span>

				{#if data.page < data.totalPages}
					<a
						href="/thron?seite={data.page + 1}"
						class="rounded border border-gray-300 px-4 py-2 text-sm hover:bg-gray-50 dark:border-gray-600 dark:hover:bg-gray-700"
					>
						Älterer Thron &rarr;
					</a>
				{:else}
					<span></span>
				{/if}
			</div>
		{/if}
	</div>
{:else}
	<p class="text-gray-500 dark:text-gray-400">Keine Throne vorhanden.</p>
{/if}
