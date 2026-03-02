<script lang="ts">
	import Breadcrumb from '$lib/components/Breadcrumb.svelte';
	import EventCard from '$lib/components/EventCard.svelte';

	let { data } = $props();
</script>

<svelte:head>
	<title>Termine {data.year} &mdash; Schützenverein Buterland-Beckerhook</title>
	<meta
		name="description"
		content="Termine und Veranstaltungen {data.year} des Schützenvereins Buterland-Beckerhook e.V."
	/>
</svelte:head>

<Breadcrumb crumbs={[{ label: 'Termine' }]} />

<div class="mb-6 flex items-center justify-between">
	<h1 class="text-3xl font-bold">Termine {data.year}</h1>
	<div class="flex gap-2">
		<a
			href="/termine?jahr={data.year - 1}"
			class="rounded border border-gray-300 px-3 py-1 text-sm hover:bg-gray-50 dark:border-gray-600 dark:hover:bg-gray-700"
		>
			{data.year - 1}
		</a>
		<a
			href="/termine?jahr={data.year + 1}"
			class="rounded border border-gray-300 px-3 py-1 text-sm hover:bg-gray-50 dark:border-gray-600 dark:hover:bg-gray-700"
		>
			{data.year + 1}
		</a>
	</div>
</div>

{#if data.events.length > 0}
	<div class="grid gap-4 md:grid-cols-2">
		{#each data.events as event (event.id)}
			<EventCard {event} />
		{/each}
	</div>
{:else}
	<p class="text-gray-500 dark:text-gray-400">Keine Termine für {data.year} vorhanden.</p>
{/if}
