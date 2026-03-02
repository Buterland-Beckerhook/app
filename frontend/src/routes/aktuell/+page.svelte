<script lang="ts">
	import ArticleCard from '$lib/components/ArticleCard.svelte';
	import Pagination from '$lib/components/Pagination.svelte';

	let { data } = $props();
</script>

<svelte:head>
	<title>Aktuelles &mdash; Schützenverein Buterland-Beckerhook</title>
	<meta
		name="description"
		content="Aktuelle Nachrichten und Berichte vom Schützenverein Buterland-Beckerhook e.V."
	/>
</svelte:head>

<h1 class="mb-6 text-3xl font-bold">Aktuelles</h1>

{#if data.articles.length > 0}
	{#each data.articles as article (article.id)}
		<ArticleCard {article} />
	{/each}

	<Pagination currentPage={data.page} totalPages={data.totalPages} baseUrl="/aktuell" />
{:else}
	<p class="text-gray-500">Keine Nachrichten vorhanden.</p>
{/if}
