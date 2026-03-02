<script lang="ts">
	import DateFormat from '$lib/components/DateFormat.svelte';

	let { data } = $props();

	let isCanceled = $derived(data.event.status === 'canceled');
	let location = $derived(typeof data.event.location === 'object' ? data.event.location : null);
</script>

<svelte:head>
	<title>{data.event.title} &mdash; Termine &mdash; Schützenverein Buterland-Beckerhook</title>
	<meta name="description" content={data.event.title} />
</svelte:head>

<article class="mx-auto max-w-3xl">
	<header class="mb-8">
		{#if isCanceled}
			<div class="mb-4 rounded-lg bg-red-50 p-4">
				<p class="font-medium text-red-700">Diese Veranstaltung wurde abgesagt.</p>
				{#if data.event.cancel_reason}
					<p class="mt-1 text-sm text-red-600">{data.event.cancel_reason}</p>
				{/if}
			</div>
		{/if}

		<h1 class="text-3xl font-bold" class:line-through={isCanceled}>
			{data.event.title}
		</h1>

		<div class="mt-4 flex flex-col gap-2 text-gray-600">
			<div class="flex items-center gap-2">
				<span class="font-medium">Datum:</span>
				<DateFormat date={data.event.start} withTime />
				{#if data.event.end}
					<span>&mdash;</span>
					<DateFormat date={data.event.end} withTime />
				{/if}
			</div>
			{#if location}
				<div class="flex items-center gap-2">
					<span class="font-medium">Ort:</span>
					<span>{location.name}</span>
					{#if location.street}
						<span class="text-sm text-gray-400"
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
		<div class="prose max-w-none">
			{@html data.event.body}
		</div>
	{/if}

	<footer class="mt-8 border-t border-gray-200 pt-4">
		<a href="/termine" class="text-primary hover:underline">&larr; Zurück zu den Terminen</a>
	</footer>
</article>
