<script lang="ts">
	import DateFormat from '$lib/components/DateFormat.svelte';
	import ThroneTable from '$lib/components/ThroneTable.svelte';
	import { getFirstImage, getImageUrl, getImageAlt } from '$lib/utils/image';

	let { data } = $props();

	let heroImage = $derived(getFirstImage(data.article.images));
	let galleryImages = $derived(
		data.article.images.length > 1
			? [...data.article.images].sort((a, b) => (a.sort ?? 0) - (b.sort ?? 0))
			: []
	);
</script>

<svelte:head>
	<title>{data.article.title} &mdash; Schützenverein Buterland-Beckerhook</title>
	<meta name="description" content={data.article.subtitle ?? data.article.title} />
</svelte:head>

<article class="mx-auto max-w-3xl">
	<header class="mb-8">
		<div class="mb-2 text-sm text-gray-500 dark:text-gray-400">
			<DateFormat date={data.article.date_published} />
			{#if data.article.author}
				<span>&mdash; {data.article.author}</span>
			{/if}
		</div>
		<h1 class="text-3xl font-bold">{data.article.title}</h1>
		{#if data.article.subtitle}
			<p class="mt-2 text-lg text-gray-600 dark:text-gray-300">{data.article.subtitle}</p>
		{/if}
		{#if data.article.tags && data.article.tags.length > 0}
			<div class="mt-3 flex flex-wrap gap-2">
				{#each data.article.tags as tag (tag)}
					<span
						class="rounded-full bg-gray-100 px-3 py-0.5 text-xs text-gray-600 dark:bg-gray-700 dark:text-gray-300"
						>{tag}</span
					>
				{/each}
			</div>
		{/if}
	</header>

	{#if heroImage}
		<figure class="mb-8">
			<img
				src={getImageUrl(heroImage, 960, 540)}
				alt={getImageAlt(heroImage)}
				width="960"
				height="540"
				class="w-full rounded-lg object-cover"
			/>
			{#if heroImage.copyright}
				<figcaption class="mt-1 text-right text-xs text-gray-400 dark:text-gray-500">
					{heroImage.copyright}
				</figcaption>
			{/if}
		</figure>
	{/if}

	{#if data.article.body}
		<div class="prose dark:prose-invert max-w-none">
			{@html data.article.body}
		</div>
	{/if}

	{#if galleryImages.length > 0}
		<section class="mt-8">
			<h2 class="mb-4 text-xl font-semibold">Bilder</h2>
			<div class="grid grid-cols-2 gap-4 md:grid-cols-3">
				{#each galleryImages as image (image.id)}
					<figure>
						<img
							src={getImageUrl(image, 400, 300)}
							alt={getImageAlt(image)}
							width="400"
							height="300"
							loading="lazy"
							class="w-full rounded-lg object-cover"
						/>
						{#if image.title}
							<figcaption class="mt-1 text-center text-xs text-gray-500 dark:text-gray-400">
								{image.title}
							</figcaption>
						{/if}
					</figure>
				{/each}
			</div>
		</section>
	{/if}

	{#if data.article.throne}
		<section class="mt-8 rounded-lg border border-gray-200 p-6 dark:border-gray-700">
			<ThroneTable throne={data.article.throne} />
		</section>
	{/if}

	<footer class="mt-8 border-t border-gray-200 pt-4 dark:border-gray-700">
		<a href="/aktuell" class="text-primary hover:underline">&larr; Zurück zur Übersicht</a>
	</footer>
</article>
