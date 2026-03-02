<script lang="ts">
	import ArticleCard from '$lib/components/ArticleCard.svelte';
	import EventCard from '$lib/components/EventCard.svelte';
	import ThroneTable from '$lib/components/ThroneTable.svelte';
	import { getFirstImage, getImageUrl, getImageAlt } from '$lib/utils/image';

	let { data } = $props();

	let throneImage = $derived(
		data.currentThroneArticle ? getFirstImage(data.currentThroneArticle.images) : undefined
	);
</script>

<svelte:head>
	<title>Schützenverein Buterland-Beckerhook e.V.</title>
	<meta
		name="description"
		content="Willkommen beim Schützenverein Buterland-Beckerhook e.V. aus Ahaus. Aktuelle Nachrichten, Termine und Informationen rund um unseren Verein."
	/>
</svelte:head>

<div class="grid gap-8 lg:grid-cols-3">
	<!-- Nächster Termin -->
	<div class="lg:col-span-2">
		{#if data.nextEvent}
			<section>
				<h2 class="mb-4 text-xl font-semibold">Nächster Termin</h2>
				<EventCard event={data.nextEvent} />
			</section>
		{/if}

		<!-- Letzte Nachrichten -->
		<section class="mt-8">
			<div class="mb-4 flex items-center justify-between">
				<h2 class="text-xl font-semibold">Aktuelles</h2>
				<a href="/aktuell" class="text-sm text-primary hover:underline">Alle Nachrichten &rarr;</a>
			</div>
			{#each data.articles as article (article.id)}
				<ArticleCard {article} />
			{/each}
		</section>
	</div>

	<!-- Sidebar: Aktueller Thron -->
	<aside>
		{#if data.currentThrone}
			{#if throneImage}
				<img
					src={getImageUrl(throneImage, 640, 427)}
					alt={getImageAlt(throneImage)}
					width="640"
					height="427"
					class="mb-4 w-full rounded-lg object-cover"
				/>
			{/if}
			<ThroneTable throne={data.currentThrone} />
		{/if}
	</aside>
</div>
