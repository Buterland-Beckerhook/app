<script lang="ts">
	import Breadcrumb from '$lib/components/Breadcrumb.svelte';
	import DateFormat from '$lib/components/DateFormat.svelte';

	let { data } = $props();

	let isCanceled = $derived(data.event.status === 'canceled');
	let location = $derived(typeof data.event.location === 'object' ? data.event.location : null);
	let isPast = $derived(
		data.event.end ? new Date(data.event.end) < new Date() : new Date(data.event.start) < new Date()
	);
</script>

<svelte:head>
	<title>{data.event.title} &mdash; Termine &mdash; Schützenverein Buterland-Beckerhook</title>
	<meta name="description" content={data.event.title} />
</svelte:head>

<Breadcrumb
	crumbs={[
		{ label: 'Termine', href: '/termine' },
		{ label: String(data.event.year), href: `/termine?jahr=${data.event.year}` },
		{ label: data.event.title }
	]}
/>

<article class="mx-auto max-w-3xl">
	<header class="mb-8">
		{#if isCanceled}
			<div class="mb-4 rounded-lg bg-red-50 p-4 dark:bg-red-900/20">
				<p class="font-medium text-red-700 dark:text-red-300">
					Diese Veranstaltung wurde abgesagt.
				</p>
				{#if data.event.cancel_reason}
					<p class="mt-1 text-sm text-red-600 dark:text-red-400">
						{data.event.cancel_reason}
					</p>
				{/if}
			</div>
		{/if}

		<h1 class="text-3xl font-bold" class:line-through={isCanceled} class:color-red-100={isPast}>
			{data.event.title}
		</h1>

		<div class="mt-4 flex flex-col gap-2 text-gray-600 dark:text-gray-300">
			<div class="flex flex-wrap items-center gap-2">
				<span class="font-medium">Datum:</span>
				<DateFormat date={data.event.start} withTime={!data.event.all_day} />
				{#if data.event.end}
					<span>&mdash;</span>
					<DateFormat date={data.event.end} withTime={!data.event.all_day} />
				{/if}
			</div>
			{#if location}
				<div class="flex flex-wrap items-center gap-2">
					<span class="font-medium">Ort:</span>
					<span>{location.name}</span>
					{#if location.street}
						<span class="text-sm text-gray-400 dark:text-gray-500"
							>({location.street}, {location.zip} {location.city})</span
						>
					{/if}
				</div>
				{#if location.maps_url}
					<a
						href={location.maps_url}
						target="_blank"
						rel="noopener noreferrer"
						class="text-sm text-primary hover:underline"
					>
						Auf Karte anzeigen &rarr;
					</a>
				{/if}
			{/if}
		</div>
	</header>

	{#if data.event.body}
		<div class="prose dark:prose-invert max-w-none">
			{@html data.event.body}
		</div>
	{/if}

	<footer class="mt-8 border-t border-gray-200 pt-4 dark:border-zinc-700">
		<a href="/termine" class="text-primary hover:underline">&larr; Zurück zu den Terminen</a>
	</footer>
</article>
