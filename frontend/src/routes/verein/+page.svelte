<script lang="ts">
	import Breadcrumb from '$lib/components/Breadcrumb.svelte';
	import PeopleTable from '$lib/components/PeopleTable.svelte';

	let { data } = $props();
</script>

<svelte:head>
	<title>Verein &mdash; Schützenverein Buterland-Beckerhook</title>
	<meta
		name="description"
		content="Informationen über den Schützenverein Buterland-Beckerhook e.V. - Vorstand, Offiziere und mehr."
	/>
</svelte:head>

<Breadcrumb crumbs={[{ label: 'Verein' }]} />

<h1 class="mb-8 text-3xl font-bold">Unser Verein</h1>

{#if data.page?.body}
	<div class="prose dark:prose-invert mb-8 max-w-none">
		{@html data.page.body}
	</div>
{/if}

<nav class="mb-8 flex flex-wrap gap-4">
	<a
		href="/verein/vorstand"
		class="rounded-lg border border-gray-200 px-4 py-2 hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-800"
	>
		Vorstand
	</a>
	<a
		href="/verein/offiziere"
		class="rounded-lg border border-gray-200 px-4 py-2 hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-800"
	>
		Offiziere
	</a>
</nav>

<div class="grid gap-8 md:grid-cols-2">
	<PeopleTable people={data.vorstand} title="Vorstand" />
	<PeopleTable people={data.offiziere} title="Offiziere" />
</div>
