<script lang="ts">
	import PeopleTable from '$lib/components/PeopleTable.svelte';

	let { data } = $props();
</script>

<svelte:head>
	<title>{data.page.title} &mdash; Verein &mdash; Schützenverein Buterland-Beckerhook</title>
	<meta name="description" content={data.page.title} />
</svelte:head>

<h1 class="mb-8 text-3xl font-bold">{data.page.title}</h1>

{#if data.page.body}
	<div class="prose dark:prose-invert mb-8 max-w-none">
		{@html data.page.body}
	</div>
{/if}

{#if data.people}
	<PeopleTable people={data.people} title={data.page.title} />
{/if}

<footer class="mt-8 border-t border-gray-200 pt-4 dark:border-gray-700">
	<a href="/verein" class="text-primary hover:underline">&larr; Zurück zum Verein</a>
</footer>
