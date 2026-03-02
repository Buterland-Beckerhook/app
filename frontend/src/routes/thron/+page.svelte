<script lang="ts">
	import ThroneTable from '$lib/components/ThroneTable.svelte';

	let { data } = $props();
</script>

<svelte:head>
	<title>Thron &mdash; Schützenverein Buterland-Beckerhook</title>
	<meta
		name="description"
		content="Die Throne des Schützenvereins Buterland-Beckerhook e.V. - Könige, Königinnen und Hofstaat."
	/>
</svelte:head>

<h1 class="mb-8 text-3xl font-bold">Thron</h1>

{#if data.articles.length > 0}
	<div class="space-y-8">
		{#each data.articles as article (article.id)}
			{#if article.throne}
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
			{/if}
		{/each}
	</div>
{:else}
	<p class="text-gray-500 dark:text-gray-400">Keine Throne vorhanden.</p>
{/if}
